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

#import <AIUtilities/AICursorAdditions.h>

@interface TestCursorAdditions : XCTestCase
@end

@implementation TestCursorAdditions

- (void)testCrosshairOpenHandAndPointingHandMapToTheirKeywords
{
	XCTAssertEqualObjects([[NSCursor crosshairCursor] CSSRepresentation], @"crosshair");
	XCTAssertEqualObjects([[NSCursor openHandCursor] CSSRepresentation], @"move");
	XCTAssertEqualObjects([[NSCursor pointingHandCursor] CSSRepresentation], @"pointer");
}

- (void)testArrowCursorIsTheDefault
{
	//Without an application the arrow cursor is nil in a fresh process; it exists once AppKit has been used
	NSCursor *arrow = [NSCursor arrowCursor];
	XCTSkipIf(arrow == nil, @"the arrow cursor is not available to this process");

	XCTAssertEqualObjects([arrow CSSRepresentation], @"default");
}

- (void)testIBeamCursorIsText
{
	NSCursor *beam = [NSCursor IBeamCursor];
	XCTSkipIf(beam == nil, @"the I-beam cursor is not available to this process");

	XCTAssertEqualObjects([beam CSSRepresentation], @"text");
}

- (void)testResizeCursorsPointTheWayTheirCSSKeywordsDo
{
	XCTExpectFailure(@"CSSRepresentation (AICursorAdditions.m, the resize branches, and the table in the comment above it) pairs each resize cursor with the keyword of the opposite direction: CSS n-resize is the arrow pointing up, which is resizeUpCursor, not resizeDownCursor; the same for the other three");

	XCTAssertEqualObjects([[NSCursor resizeUpCursor] CSSRepresentation], @"n-resize");
	XCTAssertEqualObjects([[NSCursor resizeDownCursor] CSSRepresentation], @"s-resize");
	XCTAssertEqualObjects([[NSCursor resizeLeftCursor] CSSRepresentation], @"w-resize");
	XCTAssertEqualObjects([[NSCursor resizeRightCursor] CSSRepresentation], @"e-resize");
}

- (void)testACustomCursorHasNoCSSRepresentation
{
	NSCursor *custom = [[NSCursor alloc] initWithImage:[[NSImage alloc] initWithSize:NSMakeSize(4, 4)] hotSpot:NSZeroPoint];

	XCTAssertNil([custom CSSRepresentation]);
}

- (void)testClosedHandCursorIsWrittenOutAndReferencedByURL
{
	XCTExpectFailure(@"CSSRepresentation (AICursorAdditions.m) promises in its comment that the closed hand, the disappearing item and the two double resize cursors are written to the cache folder and returned as a url; the branch is marked XXX and returns nil");

	XCTAssertNotNil([[NSCursor closedHandCursor] CSSRepresentation]);
}

@end
