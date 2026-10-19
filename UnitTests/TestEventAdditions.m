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

#import <AIUtilities/AIEventAdditions.h>

@interface TestEventAdditions : XCTestCase
@end

@implementation TestEventAdditions

- (NSEvent *)keyEventWithModifiers:(NSEventModifierFlags)flags
{
	return [NSEvent keyEventWithType:NSEventTypeKeyDown
							location:NSZeroPoint
					   modifierFlags:flags
						   timestamp:0
						windowNumber:0
							 context:nil
						  characters:@"a"
		 charactersIgnoringModifiers:@"a"
						   isARepeat:NO
							 keyCode:0];
}

- (void)testAnEventWithoutModifiersReportsNone
{
	NSEvent *event = [self keyEventWithModifiers:0];

	XCTAssertFalse([event cmdKey]);
	XCTAssertFalse([event shiftKey]);
	XCTAssertFalse([event optionKey]);
	XCTAssertFalse([event controlKey]);
}

- (void)testCmdKeyReportsTheCommandFlagAlone
{
	NSEvent *event = [self keyEventWithModifiers:NSEventModifierFlagCommand];

	XCTAssertTrue([event cmdKey]);
	XCTAssertFalse([event shiftKey]);
	XCTAssertFalse([event optionKey]);
	XCTAssertFalse([event controlKey]);
}

- (void)testShiftKeyReportsTheShiftFlagAlone
{
	NSEvent *event = [self keyEventWithModifiers:NSEventModifierFlagShift];

	XCTAssertTrue([event shiftKey]);
	XCTAssertFalse([event cmdKey]);
	XCTAssertFalse([event optionKey]);
	XCTAssertFalse([event controlKey]);
}

- (void)testOptionKeyReportsTheOptionFlagAlone
{
	NSEvent *event = [self keyEventWithModifiers:NSEventModifierFlagOption];

	XCTAssertTrue([event optionKey]);
	XCTAssertFalse([event cmdKey]);
	XCTAssertFalse([event shiftKey]);
	XCTAssertFalse([event controlKey]);
}

- (void)testControlKeyReportsTheControlFlagAlone
{
	NSEvent *event = [self keyEventWithModifiers:NSEventModifierFlagControl];

	XCTAssertTrue([event controlKey]);
	XCTAssertFalse([event cmdKey]);
	XCTAssertFalse([event shiftKey]);
	XCTAssertFalse([event optionKey]);
}

- (void)testEveryModifierIsReportedWhenAllAreDown
{
	NSEvent *event = [self keyEventWithModifiers:(NSEventModifierFlagCommand | NSEventModifierFlagShift |
												  NSEventModifierFlagOption | NSEventModifierFlagControl |
												  NSEventModifierFlagCapsLock)];

	XCTAssertTrue([event cmdKey]);
	XCTAssertTrue([event shiftKey]);
	XCTAssertTrue([event optionKey]);
	XCTAssertTrue([event controlKey]);
}

@end
