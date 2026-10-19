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
#import <AIUtilities/AIFunctions.h>

@interface AIFunctionsActionRecorder : NSObject
{
	@public
	id lastSender;
	NSUInteger actionCount;
}
- (void)act:(id)sender;
@end

@implementation AIFunctionsActionRecorder
- (void)act:(id)sender
{
	lastSender = sender;
	actionCount++;
}
@end

@interface TestFunctions : XCTestCase
@end

@implementation TestFunctions

#define AIAssertRectSize(rect, w, h) do { \
	XCTAssertEqualWithAccuracy((double)NSWidth(rect), (double)(w), AIFloatComparisonAccuracy); \
	XCTAssertEqualWithAccuracy((double)NSHeight(rect), (double)(h), AIFloatComparisonAccuracy); \
} while (0)

#pragma mark Edges

- (void)testCoordinateForEachEdge
{
	NSRect rect = NSMakeRect(10, 20, 30, 40);
	XCTAssertEqualWithAccuracy((double)AICoordinateForRect_edge_(rect, NSMinXEdge), 10.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy((double)AICoordinateForRect_edge_(rect, NSMaxXEdge), 40.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy((double)AICoordinateForRect_edge_(rect, NSMinYEdge), 20.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy((double)AICoordinateForRect_edge_(rect, NSMaxYEdge), 60.0, AIFloatComparisonAccuracy);
}

- (void)testOppositeOfEachEdge
{
	XCTAssertEqual(AIOppositeRectEdge_(NSMinXEdge), NSMaxXEdge);
	XCTAssertEqual(AIOppositeRectEdge_(NSMaxXEdge), NSMinXEdge);
	XCTAssertEqual(AIOppositeRectEdge_(NSMinYEdge), NSMaxYEdge);
	XCTAssertEqual(AIOppositeRectEdge_(NSMaxYEdge), NSMinYEdge);
}

- (void)testOppositeOfSomethingThatIsNotAnEdgeIsNotAnEdge
{
	XCTAssertEqual((NSInteger)AIOppositeRectEdge_((NSRectEdge)99), (NSInteger)AINotARectEdge);
}

#pragma mark Exterior distance

- (void)testExteriorDistanceMatchesTheHeadersExample
{
	//rect.origin.x is 50, rect.size.width is 50, point.x is 25, edge is NSMaxXEdge: the header says -75.
	NSRect rect = NSMakeRect(50, 0, 50, 10);
	XCTAssertEqualWithAccuracy((double)AISignedExteriorDistanceRect_edge_toPoint_(rect, NSMaxXEdge, NSMakePoint(25, 5)), -75.0, AIFloatComparisonAccuracy);
}

- (void)testExteriorDistanceIsPositiveOutsideTheEdge
{
	NSRect rect = NSMakeRect(50, 0, 50, 10);
	XCTAssertEqualWithAccuracy((double)AISignedExteriorDistanceRect_edge_toPoint_(rect, NSMaxXEdge, NSMakePoint(125, 5)), 25.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy((double)AISignedExteriorDistanceRect_edge_toPoint_(rect, NSMinXEdge, NSMakePoint(25, 5)), 25.0, AIFloatComparisonAccuracy);
}

- (void)testExteriorDistanceIsZeroOnTheEdge
{
	NSRect rect = NSMakeRect(50, 0, 50, 10);
	XCTAssertEqualWithAccuracy((double)AISignedExteriorDistanceRect_edge_toPoint_(rect, NSMaxXEdge, NSMakePoint(100, 5)), 0.0, AIFloatComparisonAccuracy);
}

- (void)testExteriorDistanceForYEdges
{
	NSRect rect = NSMakeRect(0, 10, 10, 20);
	NSPoint above = NSMakePoint(5, 40);
	XCTAssertEqualWithAccuracy((double)AISignedExteriorDistanceRect_edge_toPoint_(rect, NSMaxYEdge, above), 10.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy((double)AISignedExteriorDistanceRect_edge_toPoint_(rect, NSMinYEdge, above), -30.0, AIFloatComparisonAccuracy);
}

#pragma mark Aligning

- (void)testAligningMinXToMaxXPutsTheRectToTheRight
{
	NSRect moved = AIRectByAligningRect_edge_toRect_edge_(NSMakeRect(0, 0, 10, 10), NSMinXEdge, NSMakeRect(100, 100, 50, 50), NSMaxXEdge);
	XCTAssertEqualWithAccuracy((double)NSMinX(moved), 150.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy((double)NSMinY(moved), 0.0, AIFloatComparisonAccuracy, @"Aligning an X edge leaves Y alone");
	AIAssertRectSize(moved, 10, 10);
}

- (void)testAligningMaxXToMinXPutsTheRectToTheLeft
{
	NSRect moved = AIRectByAligningRect_edge_toRect_edge_(NSMakeRect(0, 0, 10, 10), NSMaxXEdge, NSMakeRect(100, 100, 50, 50), NSMinXEdge);
	XCTAssertEqualWithAccuracy((double)NSMaxX(moved), 100.0, AIFloatComparisonAccuracy);
	AIAssertRectSize(moved, 10, 10);
}

- (void)testAligningMinYToMaxYPutsTheRectAbove
{
	NSRect moved = AIRectByAligningRect_edge_toRect_edge_(NSMakeRect(0, 0, 10, 10), NSMinYEdge, NSMakeRect(100, 100, 50, 50), NSMaxYEdge);
	XCTAssertEqualWithAccuracy((double)NSMinY(moved), 150.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy((double)NSMinX(moved), 0.0, AIFloatComparisonAccuracy, @"Aligning a Y edge leaves X alone");
	AIAssertRectSize(moved, 10, 10);
}

- (void)testAligningMaxYToMinYPutsTheRectBelow
{
	NSRect moved = AIRectByAligningRect_edge_toRect_edge_(NSMakeRect(0, 0, 10, 10), NSMaxYEdge, NSMakeRect(100, 100, 50, 50), NSMinYEdge);
	XCTAssertEqualWithAccuracy((double)NSMaxY(moved), 100.0, AIFloatComparisonAccuracy);
	AIAssertRectSize(moved, 10, 10);
}

- (void)testAligningSameEdgesMakesThemCoincide
{
	NSRect moved = AIRectByAligningRect_edge_toRect_edge_(NSMakeRect(0, 0, 10, 10), NSMaxXEdge, NSMakeRect(100, 100, 50, 50), NSMaxXEdge);
	XCTAssertEqualWithAccuracy((double)NSMaxX(moved), 150.0, AIFloatComparisonAccuracy);
}

#pragma mark Alignment test

- (void)testEdgesCloserThanToleranceAreAligned
{
	XCTAssertTrue(AIRectIsAligned_edge_toRect_edge_tolerance_(NSMakeRect(0, 0, 40, 10), NSMaxXEdge, NSMakeRect(42, 50, 10, 10), NSMinXEdge, 3));
}

- (void)testEdgesExactlyToleranceApartAreNotAligned
{
	XCTAssertFalse(AIRectIsAligned_edge_toRect_edge_tolerance_(NSMakeRect(0, 0, 40, 10), NSMaxXEdge, NSMakeRect(42, 50, 10, 10), NSMinXEdge, 2));
}

- (void)testEdgesFurtherThanToleranceAreNotAligned
{
	XCTAssertFalse(AIRectIsAligned_edge_toRect_edge_tolerance_(NSMakeRect(0, 0, 40, 10), NSMaxXEdge, NSMakeRect(60, 50, 10, 10), NSMinXEdge, 3));
}

- (void)testAlignmentDistanceIsUnsigned
{
	XCTAssertTrue(AIRectIsAligned_edge_toRect_edge_tolerance_(NSMakeRect(42, 0, 10, 10), NSMinXEdge, NSMakeRect(0, 50, 40, 10), NSMaxXEdge, 3), @"The same pair the other way round is just as aligned");
}

#pragma mark Moving into a rect

- (void)testRectAlreadyInsideIsNotMoved
{
	NSRect moved = AIRectByMovingRect_intoRect_(NSMakeRect(10, 10, 20, 20), NSMakeRect(0, 0, 100, 100));
	XCTAssertTrue(NSEqualRects(moved, NSMakeRect(10, 10, 20, 20)));
}

- (void)testRectLeftOfTheContainerIsMovedRight
{
	NSRect moved = AIRectByMovingRect_intoRect_(NSMakeRect(-30, 10, 20, 20), NSMakeRect(0, 0, 100, 100));
	XCTAssertEqualWithAccuracy((double)NSMinX(moved), 0.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy((double)NSMinY(moved), 10.0, AIFloatComparisonAccuracy);
	AIAssertRectSize(moved, 20, 20);
}

- (void)testRectRightOfTheContainerIsMovedLeft
{
	NSRect moved = AIRectByMovingRect_intoRect_(NSMakeRect(130, 10, 20, 20), NSMakeRect(0, 0, 100, 100));
	XCTAssertEqualWithAccuracy((double)NSMaxX(moved), 100.0, AIFloatComparisonAccuracy);
	AIAssertRectSize(moved, 20, 20);
}

- (void)testRectBelowTheContainerIsMovedUp
{
	NSRect moved = AIRectByMovingRect_intoRect_(NSMakeRect(10, -5, 20, 20), NSMakeRect(0, 0, 100, 100));
	XCTAssertEqualWithAccuracy((double)NSMinY(moved), 0.0, AIFloatComparisonAccuracy);
	AIAssertRectSize(moved, 20, 20);
}

- (void)testRectAboveTheContainerIsMovedDown
{
	NSRect moved = AIRectByMovingRect_intoRect_(NSMakeRect(10, 95, 20, 20), NSMakeRect(0, 0, 100, 100));
	XCTAssertEqualWithAccuracy((double)NSMaxY(moved), 100.0, AIFloatComparisonAccuracy);
	AIAssertRectSize(moved, 20, 20);
}

- (void)testRectOutsideOnBothAxesIsMovedOnBoth
{
	NSRect moved = AIRectByMovingRect_intoRect_(NSMakeRect(-30, 200, 20, 20), NSMakeRect(0, 0, 100, 100));
	XCTAssertTrue(NSContainsRect(NSMakeRect(0, 0, 100, 100), moved));
	AIAssertRectSize(moved, 20, 20);
}

#pragma mark Target and action

- (void)testSendActionDeliversTheSender
{
	AIFunctionsActionRecorder *target = [[AIFunctionsActionRecorder alloc] init];
	id sender = [[NSObject alloc] init];
	AISendActionToTarget(target, @selector(act:), sender);
	XCTAssertEqual(target->actionCount, (NSUInteger)1);
	XCTAssertTrue(target->lastSender == sender);
}

- (void)testSendActionToNilTargetDoesNothing
{
	AISendActionToTarget(nil, @selector(act:), self);
}

- (void)testSendNilActionDoesNothing
{
	AIFunctionsActionRecorder *target = [[AIFunctionsActionRecorder alloc] init];
	AISendActionToTarget(target, NULL, self);
	XCTAssertEqual(target->actionCount, (NSUInteger)0);
}

#pragma mark Ticks

- (void)testTickCountNeverGoesBackwards
{
	uint64_t first = AITickCount();
	uint64_t second = AITickCount();
	XCTAssertTrue(second >= first);
}

@end
