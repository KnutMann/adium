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

#import <Adium/AIIconState.h>

@interface TestIconState : XCTestCase
@end

@implementation TestIconState

#pragma mark Images to build states from

- (NSImage *)imageOfSize:(CGFloat)edge color:(NSColor *)color
{
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(edge, edge)];

	[image lockFocus];
	[color set];
	NSRectFill(NSMakeRect(0, 0, edge, edge));
	[image unlockFocus];

	return image;
}

/* The colour at a point given in fractions of the image, origin bottom left as NSImage draws, read
 * from whatever pixel density the image was rendered at */
- (NSColor *)colorOf:(NSImage *)image atX:(CGFloat)x y:(CGFloat)y
{
	NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
	NSInteger column = (NSInteger)(x * ([rep pixelsWide] - 1));
	NSInteger row = (NSInteger)((1.0 - y) * ([rep pixelsHigh] - 1));

	return [[rep colorAtX:column y:row] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
}

/* Which of the colours the tests draw with a pixel shows. The image is rendered in the colour space
 * of whatever display this runs on and read back through another, so the components drift from
 * machine to machine; which channel leads does not. */
- (NSString *)nameOfColor:(NSColor *)color
{
	CGFloat red = [color redComponent], green = [color greenComponent], blue = [color blueComponent];

	if (red > 0.85 && green > 0.85 && blue > 0.85) return @"white";
	if (red > green && red > blue) return @"red";
	if (green > red && green > blue) return @"green";
	if (blue > red && blue > green) return @"blue";
	return @"none";
}

- (void)assertColor:(NSColor *)color is:(NSString *)name
{
	XCTAssertEqualObjects([self nameOfColor:color], name, @"Pixel is %@", color);
}

- (AIIconState *)redBase
{
	return [[AIIconState alloc] initWithImage:[self imageOfSize:4 color:[NSColor redColor]] overlay:NO];
}

/* A quarter-sized green square in the bottom left corner of a base */
- (AIIconState *)greenCornerOverlay
{
	return [[AIIconState alloc] initWithImage:[self imageOfSize:2 color:[NSColor greenColor]] overlay:YES];
}

#pragma mark A single state

- (void)testStaticStateHoldsItsImageAndDoesNotAnimate
{
	NSImage *image = [self imageOfSize:4 color:[NSColor redColor]];
	AIIconState *state = [[AIIconState alloc] initWithImage:image overlay:NO];

	XCTAssertEqual([state image], image);
	XCTAssertFalse([state animated]);
	XCTAssertFalse([state overlay]);
	XCTAssertEqual([state numberOfFrames], (NSInteger)0);
	XCTAssertEqual([state currentFrame], (NSInteger)0);
}

- (void)testOverlayFlagIsKept
{
	XCTAssertTrue([[[AIIconState alloc] initWithImage:[self imageOfSize:4 color:[NSColor redColor]] overlay:YES] overlay]);
}

- (void)testAnimatedStateHoldsFramesDelayAndLooping
{
	NSArray *frames = [NSArray arrayWithObjects:
					   [self imageOfSize:4 color:[NSColor redColor]],
					   [self imageOfSize:4 color:[NSColor greenColor]],
					   [self imageOfSize:4 color:[NSColor blueColor]],
					   nil];
	AIIconState *state = [[AIIconState alloc] initWithImages:frames delay:0.25 looping:YES overlay:NO];

	XCTAssertTrue([state animated]);
	XCTAssertEqualObjects([state imageArray], frames);
	XCTAssertEqual([state numberOfFrames], (NSInteger)3);
	XCTAssertEqualWithAccuracy([state animationDelay], 0.25, AIFloatComparisonAccuracy);
	XCTAssertTrue([state looping]);
	XCTAssertEqual([state currentFrame], (NSInteger)0);
}

- (void)testNextFrameStepsThroughTheFramesAndWraps
{
	NSArray *frames = [NSArray arrayWithObjects:
					   [self imageOfSize:4 color:[NSColor redColor]],
					   [self imageOfSize:4 color:[NSColor greenColor]],
					   [self imageOfSize:4 color:[NSColor blueColor]],
					   nil];
	AIIconState *state = [[AIIconState alloc] initWithImages:frames delay:0.25 looping:NO overlay:NO];

	[state nextFrame];
	XCTAssertEqual([state currentFrame], (NSInteger)1);
	XCTAssertEqual([state image], [frames objectAtIndex:1]);

	[state nextFrame];
	XCTAssertEqual([state currentFrame], (NSInteger)2);
	XCTAssertEqual([state image], [frames objectAtIndex:2]);

	[state nextFrame];
	XCTAssertEqual([state currentFrame], (NSInteger)0);
	XCTAssertEqual([state image], [frames objectAtIndex:0]);
}

- (void)testNextFrameLeavesAStaticStateAlone
{
	AIIconState *state = [self redBase];
	NSImage *image = [state image];

	[state nextFrame];

	XCTAssertEqual([state currentFrame], (NSInteger)0);
	XCTAssertEqual([state image], image);
}

#pragma mark Compositing

- (void)testCompositeOfOneStaticStateIsThatImage
{
	AIIconState *composite = [[AIIconState alloc] initByCompositingStates:[NSArray arrayWithObject:[self redBase]]];

	XCTAssertFalse([composite animated]);
	XCTAssertTrue(NSEqualSizes([[composite image] size], NSMakeSize(4, 4)));
	[self assertColor:[self colorOf:[composite image] atX:0.9 y:0.9] is:@"red"];
}

- (void)testOverlaysAreDrawnOverTheBase
{
	AIIconState *composite = [[AIIconState alloc] initByCompositingStates:
							  [NSArray arrayWithObjects:[self redBase], [self greenCornerOverlay], nil]];

	XCTAssertFalse([composite animated]);
	XCTAssertTrue(NSEqualSizes([[composite image] size], NSMakeSize(4, 4)), @"The base sets the size");
	[self assertColor:[self colorOf:[composite image] atX:0.1 y:0.1] is:@"green"];
	[self assertColor:[self colorOf:[composite image] atX:0.9 y:0.9] is:@"red"];
}

- (void)testTopMostNonOverlayStateIsTheBase
{
	AIIconState *below = [[AIIconState alloc] initWithImage:[self imageOfSize:6 color:[NSColor redColor]] overlay:NO];
	AIIconState *above = [[AIIconState alloc] initWithImage:[self imageOfSize:4 color:[NSColor blueColor]] overlay:NO];
	AIIconState *composite = [[AIIconState alloc] initByCompositingStates:[NSArray arrayWithObjects:below, above, nil]];

	XCTAssertTrue(NSEqualSizes([[composite image] size], NSMakeSize(4, 4)), @"Got %@", NSStringFromSize([[composite image] size]));
	[self assertColor:[self colorOf:[composite image] atX:0.5 y:0.5] is:@"blue"];
}

- (void)testCompositeWithoutABaseHasNoImage
{
	AIIconState *nothing = [[AIIconState alloc] initByCompositingStates:[NSArray array]];
	AIIconState *overlaysOnly = [[AIIconState alloc] initByCompositingStates:[NSArray arrayWithObject:[self greenCornerOverlay]]];

	XCTAssertNil([nothing image]);
	XCTAssertFalse([nothing animated]);
	XCTAssertNil([overlaysOnly image]);
	XCTAssertFalse([overlaysOnly animated]);
}

- (void)testAnimatedOverlayMakesTheCompositeAnimateWithItsTiming
{
	NSArray *frames = [NSArray arrayWithObjects:
					   [self imageOfSize:2 color:[NSColor greenColor]],
					   [self imageOfSize:2 color:[NSColor blueColor]],
					   [self imageOfSize:2 color:[NSColor whiteColor]],
					   nil];
	AIIconState *overlay = [[AIIconState alloc] initWithImages:frames delay:0.5 looping:YES overlay:YES];
	AIIconState *composite = [[AIIconState alloc] initByCompositingStates:[NSArray arrayWithObjects:[self redBase], overlay, nil]];

	XCTAssertTrue([composite animated]);
	XCTAssertEqualWithAccuracy([composite animationDelay], 0.5, AIFloatComparisonAccuracy);
	XCTAssertEqual([composite numberOfFrames], (NSInteger)3);
	XCTAssertTrue(NSEqualSizes([[composite image] size], NSMakeSize(4, 4)), @"The base still sets the size");
}

- (void)testEachFrameOfTheCompositeShowsTheMatchingOverlayFrame
{
	NSArray *frames = [NSArray arrayWithObjects:
					   [self imageOfSize:2 color:[NSColor greenColor]],
					   [self imageOfSize:2 color:[NSColor blueColor]],
					   [self imageOfSize:2 color:[NSColor whiteColor]],
					   nil];
	AIIconState *overlay = [[AIIconState alloc] initWithImages:frames delay:0.5 looping:YES overlay:YES];
	AIIconState *composite = [[AIIconState alloc] initByCompositingStates:[NSArray arrayWithObjects:[self redBase], overlay, nil]];

	[self assertColor:[self colorOf:[composite image] atX:0.1 y:0.1] is:@"green"];
	[self assertColor:[self colorOf:[composite image] atX:0.9 y:0.9] is:@"red"];

	[composite nextFrame];
	XCTAssertEqual([composite currentFrame], (NSInteger)1);
	[self assertColor:[self colorOf:[composite image] atX:0.1 y:0.1] is:@"blue"];
	[self assertColor:[self colorOf:[composite image] atX:0.9 y:0.9] is:@"red"];

	[composite nextFrame];
	XCTAssertEqual([composite currentFrame], (NSInteger)2);
	[self assertColor:[self colorOf:[composite image] atX:0.1 y:0.1] is:@"white"];

	[composite nextFrame];
	XCTAssertEqual([composite currentFrame], (NSInteger)0, @"Wraps around to the first frame");
	[self assertColor:[self colorOf:[composite image] atX:0.1 y:0.1] is:@"green"];
}

- (void)testCompositeFramesAreRenderedAsTheyAreReached
{
	NSArray *frames = [NSArray arrayWithObjects:
					   [self imageOfSize:2 color:[NSColor greenColor]],
					   [self imageOfSize:2 color:[NSColor blueColor]],
					   nil];
	AIIconState *overlay = [[AIIconState alloc] initWithImages:frames delay:0.5 looping:YES overlay:YES];
	AIIconState *composite = [[AIIconState alloc] initByCompositingStates:[NSArray arrayWithObjects:[self redBase], overlay, nil]];

	XCTAssertEqual([[composite imageArray] count], (NSUInteger)1, @"Only the first frame is drawn up front");
	[composite nextFrame];
	XCTAssertEqual([[composite imageArray] count], (NSUInteger)2);
	[composite nextFrame];
	XCTAssertEqual([[composite imageArray] count], (NSUInteger)2, @"Wrapping around draws nothing new");
}

- (void)testAnimatedBaseMakesTheCompositeAnimateWithItsFrames
{
	NSArray *frames = [NSArray arrayWithObjects:
					   [self imageOfSize:4 color:[NSColor redColor]],
					   [self imageOfSize:4 color:[NSColor blueColor]],
					   nil];
	AIIconState *base = [[AIIconState alloc] initWithImages:frames delay:0.75 looping:NO overlay:NO];
	AIIconState *composite = [[AIIconState alloc] initByCompositingStates:[NSArray arrayWithObjects:base, [self greenCornerOverlay], nil]];

	XCTAssertTrue([composite animated]);
	XCTAssertEqual([composite numberOfFrames], (NSInteger)2);
	XCTAssertEqualWithAccuracy([composite animationDelay], 0.75, AIFloatComparisonAccuracy);
	[self assertColor:[self colorOf:[composite image] atX:0.9 y:0.9] is:@"red"];
	[self assertColor:[self colorOf:[composite image] atX:0.1 y:0.1] is:@"green"];

	[composite nextFrame];
	[self assertColor:[self colorOf:[composite image] atX:0.9 y:0.9] is:@"blue"];
	//The overlay stays on every frame
	[self assertColor:[self colorOf:[composite image] atX:0.1 y:0.1] is:@"green"];
}

@end
