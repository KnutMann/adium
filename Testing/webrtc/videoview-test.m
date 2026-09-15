/* Does our video view actually draw what it is handed?
 *
 * The framework's Metal view showed nothing while the decoder counted hundreds
 * of frames, which is exactly the kind of silence a test should end. This feeds
 * the view a frame of a known colour, both the way a hardware decoder hands one
 * over and the way a software decoder does, and reads the drawn picture back out
 * of the layer to see whether it is there and what colour it came out.
 */
#import <AppKit/AppKit.h>
#import <WebRTC/WebRTC.h>
#import "AIJingleVideoView.h"

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

/*! A frame the way a hardware decoder delivers one: a pixel buffer, filled evenly */
static RTCVideoFrame *pixelBufferFrame(int width, int height, uint8_t blue, uint8_t green, uint8_t red)
{
	CVPixelBufferRef buffer = NULL;
	CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
						(__bridge CFDictionaryRef)@{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}}, &buffer);
	CVPixelBufferLockBaseAddress(buffer, 0);
	uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
	size_t stride = CVPixelBufferGetBytesPerRow(buffer);
	for (int row = 0; row < height; row++) {
		for (int column = 0; column < width; column++) {
			uint8_t *pixel = base + row * stride + column * 4;
			pixel[0] = blue; pixel[1] = green; pixel[2] = red; pixel[3] = 255;
		}
	}
	CVPixelBufferUnlockBaseAddress(buffer, 0);

	RTCVideoFrame *frame = [[RTCVideoFrame alloc] initWithBuffer:[[RTCCVPixelBuffer alloc] initWithPixelBuffer:buffer]
													   rotation:RTCVideoRotation_0
													timeStampNs:0];
	CVPixelBufferRelease(buffer);
	return frame;
}

/*! A frame the way a software decoder delivers one: three planes */
static RTCVideoFrame *planarFrame(int width, int height, uint8_t y, uint8_t u, uint8_t v)
{
	RTCMutableI420Buffer *buffer = [[RTCMutableI420Buffer alloc] initWithWidth:width height:height];
	memset((void *)buffer.mutableDataY, y, (size_t)buffer.strideY * height);
	memset((void *)buffer.mutableDataU, u, (size_t)buffer.strideU * ((height + 1) / 2));
	memset((void *)buffer.mutableDataV, v, (size_t)buffer.strideV * ((height + 1) / 2));

	return [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:RTCVideoRotation_0 timeStampNs:0];
}

/*! What the layer is actually showing, as one pixel from the middle */
static BOOL colourInTheMiddle(AIJingleVideoView *view, CGFloat *red, CGFloat *green, CGFloat *blue)
{
	CGImageRef shown = (__bridge CGImageRef)[[view layer] contents];
	if (!shown)
		return NO;

	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:shown];
	NSColor *colour = [[rep colorAtX:(rep.pixelsWide / 2) y:(rep.pixelsHigh / 2)]
					   colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	*red = [colour redComponent]; *green = [colour greenComponent]; *blue = [colour blueComponent];
	return YES;
}

static void settle(void)
{
	for (int i = 0; i < 30; i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

int main(void) { @autoreleasepool {
	[NSApplication sharedApplication];

	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 240)
												   styleMask:NSWindowStyleMaskTitled
													 backing:NSBackingStoreBuffered
													   defer:NO];
	AIJingleVideoView *view = [[AIJingleVideoView alloc] initWithFrame:NSMakeRect(0, 0, 320, 240)];
	[[window contentView] addSubview:view];

	//A hardware decoder's frame: strong red
	[view renderFrame:pixelBufferFrame(320, 240, 0, 0, 255)];
	settle();

	check(@"Bild aus einem Pixelpuffer wird gezeichnet", view.renderedFrames > 0,
		  [NSString stringWithFormat:@"gezeichnet=%ld", (long)view.renderedFrames]);
	check(@"Groesse des Bildes stimmt",
		  view.lastFrameSize.width == 320 && view.lastFrameSize.height == 240,
		  NSStringFromSize(view.lastFrameSize));

	CGFloat red = 0, green = 0, blue = 0;
	BOOL shown = colourInTheMiddle(view, &red, &green, &blue);
	check(@"Die Ebene zeigt wirklich ein Bild", shown, nil);
	check(@"und es ist rot", shown && red > 0.8 && green < 0.2 && blue < 0.2,
		  [NSString stringWithFormat:@"r=%.2f g=%.2f b=%.2f", red, green, blue]);

	//A software decoder's frame: three planes making green
	NSInteger before = view.renderedFrames;
	[view renderFrame:planarFrame(320, 240, 149, 43, 21)];
	settle();
	check(@"Bild aus drei Ebenen wird gezeichnet", view.renderedFrames > before,
		  [NSString stringWithFormat:@"gezeichnet=%ld", (long)view.renderedFrames]);

	shown = colourInTheMiddle(view, &red, &green, &blue);
	check(@"und es ist gruen", shown && green > 0.6 && red < 0.35 && blue < 0.35,
		  [NSString stringWithFormat:@"r=%.2f g=%.2f b=%.2f", red, green, blue]);

	/* Schwarze Bilder erkennen, denn manche Gegenstellen schalten ihre Kamera aus,
	 * ohne es zu sagen, und schicken danach genau das. */
	check(@"Ein Bild mit Inhalt gilt nicht als schwarz", !view.looksBlack, nil);

	for (int i = 0; i < 40; i++) {
		[view renderFrame:pixelBufferFrame(320, 240, 0, 0, 0)];
		settle();
	}
	check(@"Anhaltendes Schwarz wird erkannt", view.looksBlack, nil);

	//Ein dunkler Raum ist nicht schwarz: Rauschen liegt deutlich darueber
	[view renderFrame:pixelBufferFrame(320, 240, 40, 38, 42)];
	settle();
	check(@"Ein dunkler Raum gilt nicht als abgeschaltet", !view.looksBlack, nil);

	//Und aus drei Ebenen ebenso, also auf dem Weg eines Software-Dekoders
	for (int i = 0; i < 40; i++) {
		[view renderFrame:planarFrame(320, 240, 16, 128, 128)];
		settle();
	}
	check(@"Auch aus drei Ebenen wird Schwarz erkannt", view.looksBlack, nil);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
