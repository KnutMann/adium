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

#import <AIUtilities/AIWindowAdditions.h>

@interface TestWindowAdditions : XCTestCase
@end

@interface AIInnerResponderView : NSView
@end

@implementation AIInnerResponderView

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (void)ai_handleTestCommand
{
}

@end

@interface AIOuterResponderView : NSView
@end

@implementation AIOuterResponderView

- (void)ai_handleTestCommand
{
}

@end

//Declared so that the selector has a name; nobody implements it
@interface NSObject (AIWindowTestSelectors)
- (void)ai_nobodyHandlesThis;
@end

@implementation TestWindowAdditions

/* Deferred and never ordered front: the window exists for its frame, its content view and its
 * responder chain, and it is not released by close because nothing ever closes it. */
- (NSWindow *)windowWithStyle:(NSWindowStyleMask)style
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
												   styleMask:style
													 backing:NSBackingStoreBuffered
													   defer:YES];
	[window setReleasedWhenClosed:NO];
	return window;
}

- (NSWindow *)windowWithResponders:(AIInnerResponderView **)innerOut outer:(AIOuterResponderView **)outerOut
{
	NSWindow *window = [self windowWithStyle:NSWindowStyleMaskTitled];
	AIOuterResponderView *outer = [[AIOuterResponderView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
	AIInnerResponderView *inner = [[AIInnerResponderView alloc] initWithFrame:NSMakeRect(0, 0, 50, 25)];
	[outer addSubview:inner];
	[[window contentView] addSubview:outer];
	XCTAssertTrue([window makeFirstResponder:inner], @"precondition");
	*innerOut = inner;
	*outerOut = outer;
	return window;
}

#pragma mark Geometry

- (void)testSetContentSizeKeepsTheTopLeftCornerWhereItWas
{
	NSWindow *window = [self windowWithStyle:NSWindowStyleMaskTitled];
	NSRect before = [window frame];

	[window setContentSize:NSMakeSize(300, 50) display:NO animate:NO];
	NSRect after = [window frame];
	XCTAssertEqualWithAccuracy(NSMinX(after), NSMinX(before), AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy(NSMaxY(after), NSMaxY(before), AIFloatComparisonAccuracy);
	XCTAssertTrue(NSEqualSizes([[window contentView] frame].size, NSMakeSize(300, 50)), @"%@", NSStringFromRect([[window contentView] frame]));
	XCTAssertTrue(NSEqualSizes(after.size, [window frameRectForContentRect:NSMakeRect(0, 0, 300, 50)].size));
}

- (void)testIsBorderlessOnlyForTheBorderlessStyle
{
	XCTAssertTrue([[self windowWithStyle:NSWindowStyleMaskBorderless] isBorderless]);
	XCTAssertFalse([[self windowWithStyle:NSWindowStyleMaskTitled] isBorderless]);
	XCTAssertFalse([[self windowWithStyle:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)] isBorderless]);
}

#pragma mark Toolbars

- (void)testToolbarHeightIsZeroWithoutAToolbar
{
	XCTAssertEqualWithAccuracy([[self windowWithStyle:NSWindowStyleMaskTitled] toolbarHeight], 0, AIFloatComparisonAccuracy);
}

- (void)testToolbarHeightIsZeroWhileTheToolbarIsHidden
{
	NSWindow *window = [self windowWithStyle:NSWindowStyleMaskTitled];
	NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"AITestToolbar"];
	[window setToolbar:toolbar];
	[toolbar setVisible:NO];
	XCTAssertFalse([toolbar isVisible], @"precondition");

	XCTAssertEqualWithAccuracy([window toolbarHeight], 0, AIFloatComparisonAccuracy);
}

- (void)testToolbarHeightIsTheRoomAVisibleToolbarTakes
{
	NSWindow *window = [self windowWithStyle:NSWindowStyleMaskTitled];
	NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"AITestToolbar"];
	[window setToolbar:toolbar];
	XCTAssertTrue([toolbar isVisible], @"precondition");

	XCTAssertGreaterThan([window toolbarHeight], 0);
	XCTAssertLessThan([window toolbarHeight], NSHeight([window frame]), @"a toolbar takes part of the window, not all of it");
}

#pragma mark Responders

- (void)testEarliestResponderWhichRespondsToSelectorStartsWithTheFirstResponder
{
	AIInnerResponderView *inner;
	AIOuterResponderView *outer;
	NSWindow *window = [self windowWithResponders:&inner outer:&outer];

	XCTAssertTrue([window earliestResponderWhichRespondsToSelector:@selector(ai_handleTestCommand) andIsNotOfClass:Nil] == inner);
}

- (void)testEarliestResponderWhichRespondsToSelectorSkipsTheClassToAvoid
{
	AIInnerResponderView *inner;
	AIOuterResponderView *outer;
	NSWindow *window = [self windowWithResponders:&inner outer:&outer];

	XCTAssertTrue([window earliestResponderWhichRespondsToSelector:@selector(ai_handleTestCommand) andIsNotOfClass:[AIInnerResponderView class]] == outer);
}

- (void)testEarliestResponderWhichRespondsToSelectorIsNilWhenNobodyDoes
{
	AIInnerResponderView *inner;
	AIOuterResponderView *outer;
	NSWindow *window = [self windowWithResponders:&inner outer:&outer];

	XCTAssertNil([window earliestResponderWhichRespondsToSelector:@selector(ai_nobodyHandlesThis) andIsNotOfClass:Nil]);
	XCTAssertNil([window earliestResponderWhichRespondsToSelector:@selector(ai_handleTestCommand) andIsNotOfClass:[NSView class]],
				 @"both responders are views");
}

- (void)testEarliestResponderOfClassWalksTheChainUpToTheWindow
{
	AIInnerResponderView *inner;
	AIOuterResponderView *outer;
	NSWindow *window = [self windowWithResponders:&inner outer:&outer];

	XCTAssertTrue([window earliestResponderOfClass:[AIInnerResponderView class]] == inner);
	XCTAssertTrue([window earliestResponderOfClass:[AIOuterResponderView class]] == outer);
	XCTAssertTrue([window earliestResponderOfClass:[NSWindow class]] == window);
}

- (void)testEarliestResponderOfClassIsNilWhenNoSuchResponderIsInTheChain
{
	AIInnerResponderView *inner;
	AIOuterResponderView *outer;
	NSWindow *window = [self windowWithResponders:&inner outer:&outer];

	XCTAssertNil([window earliestResponderOfClass:[NSTextView class]]);
}

@end
