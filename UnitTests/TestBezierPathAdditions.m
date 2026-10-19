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

#import <AIUtilities/AIBezierPathAdditions.h>

@interface TestBezierPathAdditions : XCTestCase
@end

static NSPoint AIPointAt(NSBezierPath *path, NSInteger index)
{
	NSPoint points[3];
	[path elementAtIndex:index associatedPoints:points];
	return points[0];
}

#define AIAssertPoint(point, px, py) do { \
	NSPoint p = (point); \
	XCTAssertEqualWithAccuracy(p.x, (px), AIFloatComparisonAccuracy); \
	XCTAssertEqualWithAccuracy(p.y, (py), AIFloatComparisonAccuracy); \
} while (0)

#define AIAssertRect(rect, rx, ry, rw, rh) do { \
	NSRect r = (rect); \
	XCTAssertEqualWithAccuracy(r.origin.x, (rx), AIFloatComparisonAccuracy); \
	XCTAssertEqualWithAccuracy(r.origin.y, (ry), AIFloatComparisonAccuracy); \
	XCTAssertEqualWithAccuracy(r.size.width, (rw), AIFloatComparisonAccuracy); \
	XCTAssertEqualWithAccuracy(r.size.height, (rh), AIFloatComparisonAccuracy); \
} while (0)

@implementation TestBezierPathAdditions

#pragma mark Rounded rectangles

- (void)testRoundedRectWithRadiusSpansTheRect
{
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(5, 10, 40, 20) radius:4];

	AIAssertRect([path bounds], 5, 10, 40, 20);
}

- (void)testRoundedRectWithRadiusLeavesTheCornersOutside
{
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, 20, 20) radius:10];

	XCTAssertFalse([path containsPoint:NSMakePoint(0.5, 0.5)]);
	XCTAssertFalse([path containsPoint:NSMakePoint(19.5, 19.5)]);
	XCTAssertTrue([path containsPoint:NSMakePoint(10, 10)]);
	XCTAssertTrue([path containsPoint:NSMakePoint(10, 0.5)], @"the middle of an edge is on the straight part");
}

- (void)testRoundedRectWithZeroRadiusIsTheRect
{
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, 20, 20) radius:0];

	XCTAssertTrue([path containsPoint:NSMakePoint(0.5, 0.5)]);
	XCTAssertTrue([path containsPoint:NSMakePoint(19.5, 19.5)]);
}

- (void)testRoundedRectWithoutRadiusIsAPill
{
	//The radius is half the shorter side, so the short ends are semicircles
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, 40, 20)];

	AIAssertRect([path bounds], 0, 0, 40, 20);
	XCTAssertFalse([path containsPoint:NSMakePoint(1, 1)]);
	XCTAssertFalse([path containsPoint:NSMakePoint(39, 19)]);
	XCTAssertTrue([path containsPoint:NSMakePoint(20, 0.5)]);
	XCTAssertTrue([path containsPoint:NSMakePoint(0.5, 10)]);
}

- (void)testRoundedRectOfSizeStartsAtTheOrigin
{
	AIAssertRect([[NSBezierPath bezierPathRoundedRectOfSize:NSMakeSize(30, 12)] bounds], 0, 0, 30, 12);
}

- (void)testRoundedTopCornersRoundsTheCornersOnTheOriginEdge
{
	/* The cells that use this draw flipped, so the rect's origin edge is the top of the row;
	 * the path speaks their language and rounds the corners at the smallest y. */
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedTopCorners:NSMakeRect(0, 0, 20, 20) radius:10];

	AIAssertRect([path bounds], 0, 0, 20, 20);
	XCTAssertFalse([path containsPoint:NSMakePoint(0.5, 0.5)]);
	XCTAssertFalse([path containsPoint:NSMakePoint(19.5, 0.5)]);
	XCTAssertTrue([path containsPoint:NSMakePoint(0.5, 19.5)]);
	XCTAssertTrue([path containsPoint:NSMakePoint(19.5, 19.5)]);
	XCTAssertTrue([path containsPoint:NSMakePoint(10, 10)]);
}

- (void)testRoundedBottomCornersRoundsTheCornersOnTheFarEdge
{
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedBottomCorners:NSMakeRect(0, 0, 20, 20) radius:10];

	AIAssertRect([path bounds], 0, 0, 20, 20);
	XCTAssertTrue([path containsPoint:NSMakePoint(0.5, 0.5)]);
	XCTAssertTrue([path containsPoint:NSMakePoint(19.5, 0.5)]);
	XCTAssertFalse([path containsPoint:NSMakePoint(0.5, 19.5)]);
	XCTAssertFalse([path containsPoint:NSMakePoint(19.5, 19.5)]);
	XCTAssertTrue([path containsPoint:NSMakePoint(10, 10)]);
}

#pragma mark Arrows

- (void)testArrowFillsTheUnitSquareWithItsPointAtTheTop
{
	NSBezierPath *arrow = [NSBezierPath bezierPathWithArrow];

	AIAssertRect([arrow bounds], 0, 0, 1, 1);
	AIAssertPoint(AIPointAt(arrow, 4), 0.5, 1);
	XCTAssertTrue([arrow containsPoint:NSMakePoint(0.5, 0.9)]);
	XCTAssertFalse([arrow containsPoint:NSMakePoint(0.05, 0.95)]);
}

- (void)testArrowShaftIsAThirdWideAndHalfTheHeightByDefault
{
	NSBezierPath *arrow = [NSBezierPath bezierPathWithArrow];
	const CGFloat third = 1.0 / 3.0;

	AIAssertPoint(AIPointAt(arrow, 0), third, 0);
	AIAssertPoint(AIPointAt(arrow, 1), 2 * third, 0);
	AIAssertPoint(AIPointAt(arrow, 2), 2 * third, 0.5);
	AIAssertPoint(AIPointAt(arrow, 3), 1, 0.5);
	AIAssertPoint(AIPointAt(arrow, 5), 0, 0.5);
	AIAssertPoint(AIPointAt(arrow, 6), third, 0.5);
}

- (void)testArrowShaftLengthMultiplierExtendsTheShaftBelowTheSquare
{
	NSBezierPath *arrow = [NSBezierPath bezierPathWithArrowWithShaftLengthMultiplier:2];

	AIAssertRect([arrow bounds], 0, -0.5, 1, 1.5);
	AIAssertPoint(AIPointAt(arrow, 0), 1.0 / 3.0, -0.5);
	AIAssertPoint(AIPointAt(arrow, 4), 0.5, 1);
}

- (void)testArrowShaftWidthOfOneLeavesNoWings
{
	NSBezierPath *arrow = [NSBezierPath bezierPathWithArrowWithShaftWidth:1];

	AIAssertPoint(AIPointAt(arrow, 0), 0, 0);
	AIAssertPoint(AIPointAt(arrow, 1), 1, 0);
	AIAssertPoint(AIPointAt(arrow, 2), 1, 0.5);
	AIAssertPoint(AIPointAt(arrow, 3), 1, 0.5);
	AIAssertPoint(AIPointAt(arrow, 6), 0, 0.5);
}

- (void)testArrowWithBothMetricsCombinesThem
{
	NSBezierPath *arrow = [NSBezierPath bezierPathWithArrowWithShaftLengthMultiplier:0.5 shaftWidth:0.5];

	AIAssertRect([arrow bounds], 0, 0.25, 1, 0.75);
	AIAssertPoint(AIPointAt(arrow, 0), 0.25, 0.25);
	AIAssertPoint(AIPointAt(arrow, 1), 0.75, 0.25);
}

#pragma mark Flipping and scaling

- (NSBezierPath *)slantedLine
{
	NSBezierPath *path = [NSBezierPath bezierPath];
	[path moveToPoint:NSMakePoint(0.25, 0.1)];
	[path lineToPoint:NSMakePoint(0.5, 0.9)];
	return path;
}

- (void)testFlipHorizontallyMirrorsAcrossTheUnitSquareInPlace
{
	NSBezierPath *path = [self slantedLine];

	XCTAssertTrue([path flipHorizontally] == path);
	AIAssertPoint(AIPointAt(path, 0), 0.75, 0.1);
	AIAssertPoint(AIPointAt(path, 1), 0.5, 0.9);
}

- (void)testFlipVerticallyMirrorsAcrossTheUnitSquareInPlace
{
	NSBezierPath *path = [self slantedLine];

	XCTAssertTrue([path flipVertically] == path);
	AIAssertPoint(AIPointAt(path, 0), 0.25, 0.9);
	AIAssertPoint(AIPointAt(path, 1), 0.5, 0.1);
}

- (void)testScaleToSizeMultipliesEveryPointInPlace
{
	NSBezierPath *path = [self slantedLine];

	XCTAssertTrue([path scaleToSize:NSMakeSize(10, 20)] == path);
	AIAssertPoint(AIPointAt(path, 0), 2.5, 2);
	AIAssertPoint(AIPointAt(path, 1), 5, 18);
}

- (void)testFlippingTwiceRestoresThePath
{
	NSBezierPath *path = [self slantedLine];

	[[path flipHorizontally] flipHorizontally];
	[[path flipVertically] flipVertically];
	AIAssertPoint(AIPointAt(path, 0), 0.25, 0.1);
	AIAssertPoint(AIPointAt(path, 1), 0.5, 0.9);
}

- (void)testBezierPathByFlippingAndScalingReturnCopiesAndLeaveTheOriginalAlone
{
	NSBezierPath *path = [self slantedLine];

	NSBezierPath *horizontal = [path bezierPathByFlippingHorizontally];
	NSBezierPath *vertical = [path bezierPathByFlippingVertically];
	NSBezierPath *scaled = [path bezierPathByScalingToSize:NSMakeSize(10, 20)];

	XCTAssertFalse(horizontal == path);
	XCTAssertFalse(vertical == path);
	XCTAssertFalse(scaled == path);
	AIAssertPoint(AIPointAt(horizontal, 0), 0.75, 0.1);
	AIAssertPoint(AIPointAt(vertical, 0), 0.25, 0.9);
	AIAssertPoint(AIPointAt(scaled, 1), 5, 18);
	AIAssertPoint(AIPointAt(path, 0), 0.25, 0.1);
	AIAssertPoint(AIPointAt(path, 1), 0.5, 0.9);
}

@end
