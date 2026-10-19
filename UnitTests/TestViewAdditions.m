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

#import <AIUtilities/AIViewAdditions.h>

@interface TestViewAdditions : XCTestCase
@end

@implementation TestViewAdditions

- (NSView *)viewWithSubviews:(NSUInteger)count
{
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	for (NSUInteger i = 0; i < count; i++) {
		NSView *subview = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
		[subview setIdentifier:[NSString stringWithFormat:@"v%lu", (unsigned long)i]];
		[view addSubview:subview];
	}
	return view;
}

- (NSArray<NSString *> *)orderOf:(NSView *)view
{
	return [[view subviews] valueForKey:@"identifier"];
}

- (void)testRemoveAllSubviewsLeavesNoneAndDetachesEachOfThem
{
	NSView *view = [self viewWithSubviews:3];
	NSArray<NSView *> *subviews = [[view subviews] copy];

	[view removeAllSubviews];
	XCTAssertEqual([[view subviews] count], 0u);
	for (NSView *subview in subviews) {
		XCTAssertNil([subview superview]);
	}
}

- (void)testRemoveAllSubviewsOnAViewWithoutSubviewsIsHarmless
{
	NSView *view = [self viewWithSubviews:0];

	XCTAssertNoThrow([view removeAllSubviews]);
	XCTAssertEqual([[view subviews] count], 0u);
}

- (void)testBringSubviewToFrontMakesItTheLastSubviewAndKeepsTheOthersInOrder
{
	NSView *view = [self viewWithSubviews:5];
	NSView *second = [view subviews][1];

	[view bringSubviewToFront:second];
	XCTAssertTrue([[view subviews] lastObject] == second);
	XCTAssertEqualObjects([self orderOf:view], (@[@"v0", @"v2", @"v3", @"v4", @"v1"]));
}

- (void)testBringSubviewToFrontOfTheFrontmostChangesNothing
{
	NSView *view = [self viewWithSubviews:3];

	[view bringSubviewToFront:[[view subviews] lastObject]];
	XCTAssertEqualObjects([self orderOf:view], (@[@"v0", @"v1", @"v2"]));
}

- (void)testBringSubviewToFrontTwiceOverLeavesTheLatestInFront
{
	NSView *view = [self viewWithSubviews:4];

	[view bringSubviewToFront:[view subviews][1]];
	[view bringSubviewToFront:[view subviews][2]];
	XCTAssertEqualObjects([self orderOf:view], (@[@"v0", @"v2", @"v1", @"v3"]));
}

- (void)testBringSubviewToFrontWithAStrangerLeavesTheOrderAlone
{
	NSView *view = [self viewWithSubviews:3];
	NSView *stranger = [[NSView alloc] initWithFrame:NSZeroRect];

	[view bringSubviewToFront:stranger];
	XCTAssertEqualObjects([self orderOf:view], (@[@"v0", @"v1", @"v2"]));
	XCTAssertNil([stranger superview]);
}

@end
