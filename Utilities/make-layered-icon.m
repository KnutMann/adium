// The layer of a layered application icon: a portrait of a duck, cut from a bigger picture.
//
// Compiled and run by make-layered-icon.sh, which says what the result is for. Given a
// picture on a transparent background, this finds the drawing's extent and its eyes (the
// near-white pixels in the upper half), puts the face centre a little under the eyes, and
// takes a square crop around that centre as tight as the top of the head allows plus some
// headroom, shifted down a little so the head does not touch the tile's edge. The crop is
// drawn onto a transparent canvas of the requested size.
//
//   make-layered-icon <picture.png> <headroom 0..1> <shift 0..1> <canvas px> <out.png>
#import <Cocoa/Cocoa.h>

int main(int argc, char **argv)
{
	if (argc != 6) { fprintf(stderr, "usage: make-layered-icon <picture.png> <headroom> <shift> <canvas px> <out.png>\n"); return 2; }
	@autoreleasepool {
		NSString *path = @(argv[1]);
		double headroom = atof(argv[2]), shift = atof(argv[3]);
		CGFloat canvas = atof(argv[4]);
		NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:path]];
		if (!rep || !rep.hasAlpha) { fprintf(stderr, "%s: not a picture with transparency\n", argv[1]); return 1; }

		NSInteger w = rep.pixelsWide, h = rep.pixelsHigh, minx = w, miny = h, maxx = -1, maxy = -1;
		for (NSInteger y = 0; y < h; y++) for (NSInteger x = 0; x < w; x++) {
			NSUInteger p[4] = {0, 0, 0, 0}; [rep getPixel:p atX:x y:y];
			if (p[3] > 8) { if (x < minx) minx = x; if (x > maxx) maxx = x; if (y < miny) miny = y; if (y > maxy) maxy = y; }
		}
		if (maxx < 0) { fprintf(stderr, "%s: nothing drawn\n", argv[1]); return 1; }
		NSInteger cw = maxx - minx, ch = maxy - miny, ex0 = w, ey0 = h, ex1 = -1, ey1 = -1;
		for (NSInteger y = miny; y < miny + ch * 0.5; y++) for (NSInteger x = minx + cw * 0.25; x < minx + cw * 0.75; x++) {
			NSUInteger p[4] = {0, 0, 0, 0}; [rep getPixel:p atX:x y:y];
			if (p[3] > 200 && p[0] > 200 && p[1] > 200 && p[2] > 200) { if (x < ex0) ex0 = x; if (x > ex1) ex1 = x; if (y < ey0) ey0 = y; if (y > ey1) ey1 = y; }
		}
		if (ex1 < 0) { fprintf(stderr, "%s: no eyes found (no near-white pixels in the upper half)\n", argv[1]); return 1; }

		// Image coordinates count from the top. The face centre sits between the eyes and the beak.
		double faceX = (ex0 + ex1) / 2.0, faceY = (ey0 + ey1) / 2.0 + 0.10 * ch;
		double H = 2 * (faceY - (miny - headroom * ch));
		double cropTop = faceY - H / 2 - shift * H, cropLeft = faceX - H / 2;
		double scale = canvas / H;

		NSImage *img = [[NSImage alloc] initWithContentsOfFile:path];
		NSBitmapImageRep *out = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:canvas pixelsHigh:canvas
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
		[NSGraphicsContext saveGraphicsState];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:out]];
		[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
		// The whole picture is drawn, placed so that the crop lands on the canvas; rows are flipped.
		CGFloat dx = -cropLeft * scale, dy = canvas - (h - cropTop) * scale;
		[img drawInRect:NSMakeRect(dx, dy, w * scale, h * scale) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
		[NSGraphicsContext restoreGraphicsState];
		if (![[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[5]) atomically:YES]) {
			fprintf(stderr, "could not write %s\n", argv[5]); return 1;
		}
		printf("    %s: %ld px, face at (%.0f, %.0f), crop %.0f px square from (%.0f, %.0f), scaled %.2fx\n",
			   path.lastPathComponent.UTF8String, (long)w, faceX, faceY, H, cropLeft, cropTop, scale);
	}
	return 0;
}
