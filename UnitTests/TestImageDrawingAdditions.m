/* 
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 * 
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import <AIUtilities/AIImageDrawingAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <ImageIO/ImageIO.h>

@interface TestImageDrawingAdditions : XCTestCase
@end

typedef struct {
	uint8_t red, green, blue, alpha;
} AITestPixel;

/* Everything a test reads is read from one of these: 8 bit sRGB, premultiplied, R G B A in
 * memory, one pixel per point, so no result depends on the display's scale factor or profile.
 * The category's own lockFocus images do follow the main screen; they are drawn into a canvas
 * from here before anything is asserted about them. */
static CGContextRef AINewCanvas(NSInteger width, NSInteger height)
{
	CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
												 (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGColorSpaceRelease(space);
	return context;
}

static void AIBeginDrawing(CGContextRef canvas)
{
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:canvas flipped:NO]];
	//Nearest neighbour, so that a pixel is either a tile's colour or nothing
	[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationNone];
}

static void AIEndDrawing(void)
{
	[NSGraphicsContext restoreGraphicsState];
}

//x and y count from the lower left, as drawing does
static AITestPixel AIPixelAt(CGContextRef canvas, NSInteger x, NSInteger y)
{
	const uint8_t *data = CGBitmapContextGetData(canvas);
	NSInteger height = CGBitmapContextGetHeight(canvas);
	const uint8_t *pixel = data + (height - 1 - y) * CGBitmapContextGetBytesPerRow(canvas) + x * 4;
	return (AITestPixel){ pixel[0], pixel[1], pixel[2], pixel[3] };
}

static NSImage *AIImageDrawnBy(NSInteger width, NSInteger height, void (^draw)(void))
{
	CGContextRef canvas = AINewCanvas(width, height);
	AIBeginDrawing(canvas);
	draw();
	AIEndDrawing();

	CGImageRef cgImage = CGBitmapContextCreateImage(canvas);
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
	[rep setSize:NSMakeSize(width, height)];
	CGImageRelease(cgImage);
	CGContextRelease(canvas);

	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
	[image addRepresentation:rep];
	return image;
}

static NSColor *AIRed(void)  { return [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1]; }
static NSColor *AIBlue(void) { return [NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:1]; }

static NSImage *AISolidImage(NSInteger width, NSInteger height, NSColor *color)
{
	return AIImageDrawnBy(width, height, ^{
		[color set];
		NSRectFill(NSMakeRect(0, 0, width, height));
	});
}

/* Four quadrants of two by two pixels: red lower left, green lower right, blue upper left,
 * white upper right. Any pixel of a tiling says which quadrant of which tile it came from. */
static NSImage *AIQuadrantTile(void)
{
	return AIImageDrawnBy(4, 4, ^{
		[AIRed() set];
		NSRectFill(NSMakeRect(0, 0, 2, 2));
		[[NSColor colorWithSRGBRed:0 green:1 blue:0 alpha:1] set];
		NSRectFill(NSMakeRect(2, 0, 2, 2));
		[AIBlue() set];
		NSRectFill(NSMakeRect(0, 2, 2, 2));
		[[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1] set];
		NSRectFill(NSMakeRect(2, 2, 2, 2));
	});
}

//Draws the image over the whole canvas, which for an image of the canvas' size is a pixel copy
static CGContextRef AIRender(NSImage *image, NSInteger width, NSInteger height)
{
	CGContextRef canvas = AINewCanvas(width, height);
	AIBeginDrawing(canvas);
	[image drawInRect:NSMakeRect(0, 0, width, height) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];
	AIEndDrawing();
	return canvas;
}

/* A two frame animation, written by ImageIO so that the bytes are what a file would hold. */
static NSImage *AIAnimatedImage(void)
{
	NSMutableData *data = [NSMutableData data];
	CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,
																		 CFSTR("com.compuserve.gif"), 2, NULL);
	NSArray<NSColor *> *colors = @[AIRed(), AIBlue()];
	for (NSUInteger i = 0; i < 2; i++) {
		NSBitmapImageRep *frame = (NSBitmapImageRep *)[[AISolidImage(8, 8, colors[i]) representations] firstObject];
		CGImageDestinationAddImage(destination, [frame CGImage], (__bridge CFDictionaryRef)@{
			(id)kCGImagePropertyGIFDictionary: @{ (id)kCGImagePropertyGIFDelayTime: @0.5 }
		});
	}
	CGImageDestinationFinalize(destination);
	CFRelease(destination);
	return [[NSImage alloc] initWithData:data];
}

static int AIFrameCount(NSImage *image)
{
	NSImageRep *rep = [[image representations] firstObject];
	if (![rep isKindOfClass:[NSBitmapImageRep class]]) return 1;
	return MAX(1, [[(NSBitmapImageRep *)rep valueForProperty:NSImageFrameCount] intValue]);
}

/* Interpolation and premultiplication move a channel by a step or two; three is more than that
 * and far less than the distance between any two colours these tests use. */
#define AIAssertPixel(canvas, x, y, r, g, b, a) do { \
	AITestPixel pixel = AIPixelAt((canvas), (x), (y)); \
	XCTAssertEqualWithAccuracy(pixel.red, (r), 3, @"red at %d,%d", (int)(x), (int)(y)); \
	XCTAssertEqualWithAccuracy(pixel.green, (g), 3, @"green at %d,%d", (int)(x), (int)(y)); \
	XCTAssertEqualWithAccuracy(pixel.blue, (b), 3, @"blue at %d,%d", (int)(x), (int)(y)); \
	XCTAssertEqualWithAccuracy(pixel.alpha, (a), 3, @"alpha at %d,%d", (int)(x), (int)(y)); \
} while (0)

#define AIAssertClear(canvas, x, y) AIAssertPixel(canvas, x, y, 0, 0, 0, 0)
#define AIAssertBlue(canvas, x, y) AIAssertPixel(canvas, x, y, 0, 0, 255, 255)

@implementation TestImageDrawingAdditions

#pragma mark Tiling

- (void)testTileInRectRepeatsTheImageAlongTheRowAndCropsAtTheRightEdge
{
	CGContextRef canvas = AINewCanvas(10, 4);
	AIBeginDrawing(canvas);
	[AIQuadrantTile() tileInRect:NSMakeRect(0, 0, 10, 4)];
	AIEndDrawing();

	//Two whole tiles, then the left half of a third
	AIAssertPixel(canvas, 0, 0, 255, 0, 0, 255);
	AIAssertPixel(canvas, 2, 0, 0, 255, 0, 255);
	AIAssertPixel(canvas, 4, 0, 255, 0, 0, 255);
	AIAssertPixel(canvas, 7, 0, 0, 255, 0, 255);
	AIAssertPixel(canvas, 8, 0, 255, 0, 0, 255);
	AIAssertPixel(canvas, 9, 0, 255, 0, 0, 255);
	AIAssertBlue(canvas, 0, 3);
	AIAssertPixel(canvas, 9, 3, 0, 0, 255, 255);
	CGContextRelease(canvas);
}

- (void)testTileInRectRepeatsTheImageUpwardsAndCropsAtTheTop
{
	XCTExpectFailure(@"tileInRect: (AIImageDrawingAdditions.m, the two nested while loops) never resets destRect.origin.x when it moves up a row, so every row after the first starts at the right edge and draws nothing: a rect taller than the image is tiled only along its bottom");
	CGContextRef canvas = AINewCanvas(4, 6);
	AIBeginDrawing(canvas);
	[AIQuadrantTile() tileInRect:NSMakeRect(0, 0, 4, 6)];
	AIEndDrawing();

	//The second row of tiles is cropped at the top, so only the tile's lower half shows
	AIAssertPixel(canvas, 0, 4, 255, 0, 0, 255);
	AIAssertPixel(canvas, 2, 5, 0, 255, 0, 255);
	CGContextRelease(canvas);
}

- (void)testTileInRectStartsAtTheRectsOriginAndStaysInsideIt
{
	CGContextRef canvas = AINewCanvas(8, 6);
	AIBeginDrawing(canvas);
	[AIQuadrantTile() tileInRect:NSMakeRect(1, 1, 6, 4)];
	AIEndDrawing();

	AIAssertClear(canvas, 0, 1);
	AIAssertClear(canvas, 1, 0);
	AIAssertPixel(canvas, 1, 1, 255, 0, 0, 255);
	AIAssertPixel(canvas, 6, 4, 0, 0, 255, 255);
	AIAssertClear(canvas, 7, 4);
	AIAssertClear(canvas, 6, 5);
	CGContextRelease(canvas);
}

- (void)testTileInRectWithAnEmptyRectDrawsNothing
{
	CGContextRef canvas = AINewCanvas(4, 4);
	AIBeginDrawing(canvas);
	[AIQuadrantTile() tileInRect:NSZeroRect];
	AIEndDrawing();

	AIAssertClear(canvas, 0, 0);
	AIAssertClear(canvas, 3, 3);
	CGContextRelease(canvas);
}

#pragma mark Scaling

- (void)testImageByScalingToTheSameSizeIsADistinctCopy
{
	NSImage *original = AISolidImage(20, 10, AIBlue());

	NSImage *copy = [original imageByScalingToSize:NSMakeSize(20, 10)];
	XCTAssertNotNil(copy);
	XCTAssertFalse(copy == original);
	XCTAssertTrue(NSEqualSizes([copy size], NSMakeSize(20, 10)));
}

- (void)testImageByScalingToSizeGivesTheWidthPriorityForALandscapeImage
{
	NSImage *scaled = [AISolidImage(200, 100, AIBlue()) imageByScalingToSize:NSMakeSize(50, 50)];

	XCTAssertTrue(NSEqualSizes([scaled size], NSMakeSize(50, 25)), @"%@", NSStringFromSize([scaled size]));
	CGContextRef canvas = AIRender(scaled, 50, 25);
	AIAssertBlue(canvas, 25, 12);
	CGContextRelease(canvas);
}

- (void)testImageByScalingToSizeGivesTheHeightPriorityForAPortraitImage
{
	NSImage *scaled = [AISolidImage(100, 200, AIBlue()) imageByScalingToSize:NSMakeSize(50, 50)];

	XCTAssertTrue(NSEqualSizes([scaled size], NSMakeSize(25, 50)), @"%@", NSStringFromSize([scaled size]));
}

- (void)testImageByScalingToSizeStretchesWhenNotAskedToKeepTheProportions
{
	NSImage *scaled = [AISolidImage(200, 100, AIBlue()) imageByScalingToSize:NSMakeSize(50, 50)
																	fraction:1.0
																   flipImage:NO
															  proportionally:NO
															  allowAnimation:NO];

	XCTAssertTrue(NSEqualSizes([scaled size], NSMakeSize(50, 50)), @"%@", NSStringFromSize([scaled size]));
	CGContextRef canvas = AIRender(scaled, 50, 50);
	AIAssertBlue(canvas, 2, 47);
	CGContextRelease(canvas);
}

- (void)testImageByScalingToSizeKeepsASquareImageSquare
{
	XCTExpectFailure(@"imageByScalingToSize:fraction:flipImage:proportionally:allowAnimation: (AIImageDrawingAdditions.m) only corrects the size when width and height differ, so a square image asked to scale proportionally into 50 by 20 is stretched to 50 by 20");
	NSImage *scaled = [AISolidImage(100, 100, AIBlue()) imageByScalingToSize:NSMakeSize(50, 20)];

	XCTAssertEqualWithAccuracy([scaled size].width, [scaled size].height, AIFloatComparisonAccuracy);
}

- (void)testImageByScalingToSizeWithAFractionSetsTheAlpha
{
	NSImage *faded = [AISolidImage(20, 10, AIBlue()) imageByScalingToSize:NSMakeSize(10, 5) fraction:0.5];

	XCTAssertTrue(NSEqualSizes([faded size], NSMakeSize(10, 5)));
	CGContextRef canvas = AIRender(faded, 10, 5);
	AIAssertPixel(canvas, 5, 2, 0, 0, 128, 128);
	CGContextRelease(canvas);
}

- (void)testImageByFadingToFractionKeepsTheSizeAndSetsTheAlpha
{
	NSImage *faded = [AISolidImage(20, 10, AIBlue()) imageByFadingToFraction:0.25];

	XCTAssertTrue(NSEqualSizes([faded size], NSMakeSize(20, 10)));
	CGContextRef canvas = AIRender(faded, 20, 10);
	AIAssertPixel(canvas, 10, 5, 0, 0, 64, 64);
	CGContextRelease(canvas);
}

- (void)testImageByScalingForMenuItemIsSixteenPointsAndKeepsTheProportions
{
	XCTAssertTrue(NSEqualSizes([[AISolidImage(64, 64, AIBlue()) imageByScalingForMenuItem] size], NSMakeSize(16, 16)));
	XCTAssertTrue(NSEqualSizes([[AISolidImage(64, 32, AIBlue()) imageByScalingForMenuItem] size], NSMakeSize(16, 8)));
	XCTAssertTrue(NSEqualSizes([[AISolidImage(32, 64, AIBlue()) imageByScalingForMenuItem] size], NSMakeSize(8, 16)));
}

- (void)testImageByScalingToSizeKeepsTheFramesOfAnAnimation
{
	NSImage *animated = AIAnimatedImage();
	XCTAssertEqual(AIFrameCount(animated), 2, @"precondition");

	XCTAssertEqual(AIFrameCount([animated imageByScalingToSize:NSMakeSize(4, 4)]), 2);
}

- (void)testImageByScalingToSizeOfAnAnimationHasTheRequestedSize
{
	/* The frames are drawn through lockFocus and read back as TIFF, which carries the main
	 * screen's pixel density but no point size, so on a Retina display the GIF comes out twice
	 * as large as asked; on a one to one display it is right. Not strict for that reason. */
	XCTExpectedFailureOptions *options = [[XCTExpectedFailureOptions alloc] init];
	[options setStrict:NO];
	XCTExpectFailureWithOptions(@"imageByScalingToSize:fraction:flipImage:proportionally:allowAnimation: (AIImageDrawingAdditions.m, the animation branch) builds the frames from lockFocus bitmaps whose pixel size follows the main screen, so the scaled animation is 8 by 8 points on a Retina display when 4 by 4 was asked", options);

	NSImage *scaled = [AIAnimatedImage() imageByScalingToSize:NSMakeSize(4, 4)];
	XCTAssertTrue(NSEqualSizes([scaled size], NSMakeSize(4, 4)), @"%@", NSStringFromSize([scaled size]));
}

- (void)testImageByScalingToSizeWithoutAnimationFlattensToOneFrame
{
	NSImage *flat = [AIAnimatedImage() imageByScalingToSize:NSMakeSize(4, 4)
												   fraction:1.0
												  flipImage:NO
											 proportionally:YES
											 allowAnimation:NO];

	XCTAssertEqual(AIFrameCount(flat), 1);
	XCTAssertTrue(NSEqualSizes([flat size], NSMakeSize(4, 4)));
}

#pragma mark Fitting

- (void)testImageByFittingInSizeCentresALandscapeImageInASquare
{
	NSImage *fitted = [AISolidImage(200, 100, AIBlue()) imageByFittingInSize:NSMakeSize(100, 100)];

	XCTAssertTrue(NSEqualSizes([fitted size], NSMakeSize(100, 100)));
	CGContextRef canvas = AIRender(fitted, 100, 100);
	//The picture is 100 by 50, so it covers the middle half and leaves a quarter above and below
	AIAssertBlue(canvas, 50, 50);
	AIAssertBlue(canvas, 2, 27);
	AIAssertBlue(canvas, 97, 72);
	AIAssertClear(canvas, 50, 10);
	AIAssertClear(canvas, 50, 22);
	AIAssertClear(canvas, 50, 77);
	AIAssertClear(canvas, 50, 90);
	CGContextRelease(canvas);
}

- (void)testImageByFittingInSizeKeepsTheWholeImageInsideAWiderBox
{
	XCTExpectFailure(@"imageByFittingInSize:fraction:flipImage:proportionally:allowAnimation: (AIImageDrawingAdditions.m) scales a landscape image by its width whatever the box's height, so 200 by 100 into 100 by 10 becomes 100 by 50 and is then drawn from a point 20 below the box: the result is blank, where a 20 by 10 picture centred in the box was asked for");
	NSImage *fitted = [AISolidImage(200, 100, AIBlue()) imageByFittingInSize:NSMakeSize(100, 10)];

	XCTAssertTrue(NSEqualSizes([fitted size], NSMakeSize(100, 10)));
	CGContextRef canvas = AIRender(fitted, 100, 10);
	AIAssertBlue(canvas, 50, 5);
	AIAssertClear(canvas, 10, 5);
	AIAssertClear(canvas, 89, 5);
	CGContextRelease(canvas);
}

- (void)testImageByFittingInSizeKeepsASquareImageSquare
{
	XCTExpectFailure(@"imageByFittingInSize:fraction:flipImage:proportionally:allowAnimation: (AIImageDrawingAdditions.m) only corrects the size when width and height differ, so a square image is stretched across a 50 by 20 box instead of being drawn 20 by 20 in its middle");
	NSImage *fitted = [AISolidImage(100, 100, AIBlue()) imageByFittingInSize:NSMakeSize(50, 20)];

	XCTAssertTrue(NSEqualSizes([fitted size], NSMakeSize(50, 20)));
	CGContextRef canvas = AIRender(fitted, 50, 20);
	AIAssertBlue(canvas, 25, 10);
	AIAssertClear(canvas, 2, 10);
	AIAssertClear(canvas, 47, 10);
	CGContextRelease(canvas);
}

#pragma mark Placing

- (void)testRectForDrawingAtTheLeftIsCentredVerticallyOnAWholePoint
{
	NSImage *image = AISolidImage(4, 4, AIBlue());

	//(25 - 8) / 2 is 8.5; the rect lands on 8
	NSRect rect = [image rectForDrawingInRect:NSMakeRect(10, 20, 100, 25) atSize:NSMakeSize(8, 8) position:IMAGE_POSITION_LEFT];
	XCTAssertTrue(NSEqualRects(rect, NSMakeRect(10, 28, 8, 8)), @"%@", NSStringFromRect(rect));
}

- (void)testRectForDrawingAtTheRightHugsTheRightEdge
{
	NSImage *image = AISolidImage(4, 4, AIBlue());

	NSRect rect = [image rectForDrawingInRect:NSMakeRect(10, 20, 100, 30) atSize:NSMakeSize(8, 8) position:IMAGE_POSITION_RIGHT];
	XCTAssertTrue(NSEqualRects(rect, NSMakeRect(102, 31, 8, 8)), @"%@", NSStringFromRect(rect));
}

- (void)testRectForDrawingAtTheLowerCornersHugsTheFarEdge
{
	NSImage *image = AISolidImage(4, 4, AIBlue());

	//Lower in the flipped coordinates of the cells that draw this way: the edge away from the origin
	NSRect left = [image rectForDrawingInRect:NSMakeRect(10, 20, 100, 30) atSize:NSMakeSize(8, 8) position:IMAGE_POSITION_LOWER_LEFT];
	NSRect right = [image rectForDrawingInRect:NSMakeRect(10, 20, 100, 30) atSize:NSMakeSize(8, 8) position:IMAGE_POSITION_LOWER_RIGHT];
	XCTAssertTrue(NSEqualRects(left, NSMakeRect(10, 42, 8, 8)), @"%@", NSStringFromRect(left));
	XCTAssertTrue(NSEqualRects(right, NSMakeRect(102, 42, 8, 8)), @"%@", NSStringFromRect(right));
}

- (void)testRectForDrawingWithAnEmptySizeUsesTheImagesOwnSize
{
	NSImage *image = AISolidImage(4, 4, AIBlue());

	NSRect rect = [image rectForDrawingInRect:NSMakeRect(0, 0, 20, 10) atSize:NSZeroSize position:IMAGE_POSITION_LEFT];
	XCTAssertTrue(NSEqualRects(rect, NSMakeRect(0, 3, 4, 4)), @"%@", NSStringFromRect(rect));
}

- (void)testDrawInRectAtTheLeftCentresTheImageInItsSlotAndHandsBackTheRest
{
	CGContextRef canvas = AINewCanvas(20, 10);
	AIBeginDrawing(canvas);
	NSRect rest = [AISolidImage(4, 4, AIBlue()) drawInRect:NSMakeRect(0, 0, 20, 10)
													atSize:NSMakeSize(10, 10)
												  position:IMAGE_POSITION_LEFT
												  fraction:1.0];
	AIEndDrawing();

	XCTAssertTrue(NSEqualRects(rest, NSMakeRect(10, 0, 10, 10)), @"%@", NSStringFromRect(rest));
	//A 4 by 4 picture in a 10 by 10 slot sits at 3 to 6, and is never stretched to the slot
	AIAssertBlue(canvas, 3, 3);
	AIAssertBlue(canvas, 6, 6);
	AIAssertClear(canvas, 2, 3);
	AIAssertClear(canvas, 7, 6);
	AIAssertClear(canvas, 3, 2);
	AIAssertClear(canvas, 3, 7);
	AIAssertClear(canvas, 15, 5);
	CGContextRelease(canvas);
}

- (void)testDrawInRectAtTheRightHandsBackTheRestOnTheLeft
{
	CGContextRef canvas = AINewCanvas(20, 10);
	AIBeginDrawing(canvas);
	NSRect rest = [AISolidImage(4, 4, AIBlue()) drawInRect:NSMakeRect(0, 0, 20, 10)
													atSize:NSZeroSize
												  position:IMAGE_POSITION_RIGHT
												  fraction:1.0];
	AIEndDrawing();

	XCTAssertTrue(NSEqualRects(rest, NSMakeRect(0, 0, 16, 10)), @"%@", NSStringFromRect(rest));
	AIAssertBlue(canvas, 16, 3);
	AIAssertBlue(canvas, 19, 6);
	AIAssertClear(canvas, 15, 4);
	AIAssertClear(canvas, 17, 7);
	CGContextRelease(canvas);
}

- (void)testDrawInRectWithAFractionDrawsTranslucently
{
	CGContextRef canvas = AINewCanvas(20, 10);
	AIBeginDrawing(canvas);
	[AISolidImage(4, 4, AIBlue()) drawInRect:NSMakeRect(0, 0, 20, 10) atSize:NSZeroSize position:IMAGE_POSITION_LEFT fraction:0.5];
	AIEndDrawing();

	AIAssertPixel(canvas, 1, 4, 0, 0, 128, 128);
	CGContextRelease(canvas);
}

- (void)testDrawRoundedInRectClipsTheCornersAndHandsBackTheRest
{
	CGContextRef canvas = AINewCanvas(20, 20);
	AIBeginDrawing(canvas);
	NSRect rest = [AISolidImage(20, 20, AIBlue()) drawRoundedInRect:NSMakeRect(0, 0, 20, 20) radius:10];
	AIEndDrawing();

	XCTAssertTrue(NSEqualRects(rest, NSMakeRect(20, 0, 0, 20)), @"%@", NSStringFromRect(rest));
	AIAssertClear(canvas, 0, 0);
	AIAssertClear(canvas, 19, 19);
	AIAssertClear(canvas, 1, 18);
	AIAssertBlue(canvas, 10, 10);
	AIAssertBlue(canvas, 1, 10);
	AIAssertBlue(canvas, 10, 18);
	CGContextRelease(canvas);
}

- (void)testDrawRoundedInRectWithAFractionDrawsTranslucently
{
	CGContextRef canvas = AINewCanvas(20, 20);
	AIBeginDrawing(canvas);
	[AISolidImage(20, 20, AIBlue()) drawRoundedInRect:NSMakeRect(0, 0, 20, 20) fraction:0.5 radius:4];
	AIEndDrawing();

	AIAssertPixel(canvas, 10, 10, 0, 0, 128, 128);
	AIAssertClear(canvas, 0, 0);
	CGContextRelease(canvas);
}

- (void)testDrawRoundedInRectAtSizePlacesTheImageLikeDrawInRect
{
	CGContextRef canvas = AINewCanvas(20, 10);
	AIBeginDrawing(canvas);
	NSRect rest = [AISolidImage(4, 4, AIBlue()) drawRoundedInRect:NSMakeRect(0, 0, 20, 10)
														   atSize:NSMakeSize(10, 10)
														 position:IMAGE_POSITION_LEFT
														 fraction:1.0
														   radius:0];
	AIEndDrawing();

	XCTAssertTrue(NSEqualRects(rest, NSMakeRect(10, 0, 10, 10)), @"%@", NSStringFromRect(rest));
	AIAssertBlue(canvas, 3, 3);
	AIAssertBlue(canvas, 6, 6);
	AIAssertClear(canvas, 2, 3);
	AIAssertClear(canvas, 7, 6);
	CGContextRelease(canvas);
}

@end
