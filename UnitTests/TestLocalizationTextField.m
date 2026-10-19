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

#import <Adium/AILocalizationAssistance.h>
#import <Adium/AILocalizationTextField.h>

#define LONG_TITLE	@"A title long enough that no forty point label could ever hold it"

/* The control resizes itself around a translated title the way a nib laid it out. Without a window
 * and with no anchor outlets connected, what is left to check is the part every placement relies on:
 * the edge the alignment fixes stays put, and a short title never makes the label smaller than the
 * nib drew it. */

@interface TestLocalizationTextField : XCTestCase {
	NSView	*container;
}
@end

@implementation TestLocalizationTextField

- (void)setUp
{
	[super setUp];
	container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 100)];
}

- (AILocalizationTextField *)labelWithFrame:(NSRect)frame alignment:(NSTextAlignment)alignment
{
	AILocalizationTextField *label = [[AILocalizationTextField alloc] initWithFrame:frame];

	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setAlignment:alignment];
	[container addSubview:label];

	return label;
}

- (void)testLongerTitleWidensALeftAlignedLabelToTheRight
{
	AILocalizationTextField *label = [self labelWithFrame:NSMakeRect(400, 40, 40, 17) alignment:NSTextAlignmentLeft];

	[label setStringValue:LONG_TITLE];

	XCTAssertEqualWithAccuracy(NSMinX([label frame]), 400, 0.5);
	XCTAssertGreaterThan(NSWidth([label frame]), 40);
}

- (void)testRightAlignedLabelKeepsItsRightEdge
{
	AILocalizationTextField *label = [self labelWithFrame:NSMakeRect(400, 40, 40, 17) alignment:NSTextAlignmentRight];

	[label setStringValue:LONG_TITLE];

	XCTAssertEqualWithAccuracy(NSMaxX([label frame]), 440, 0.5);
	XCTAssertGreaterThan(NSWidth([label frame]), 40);
}

- (void)testCenteredLabelKeepsItsCentre
{
	AILocalizationTextField *label = [self labelWithFrame:NSMakeRect(400, 40, 40, 17) alignment:NSTextAlignmentCenter];

	[label setStringValue:LONG_TITLE];

	XCTAssertEqualWithAccuracy(NSMidX([label frame]), 420, 1.0, @"Rounded to whole points, so up to one point off");
	XCTAssertGreaterThan(NSWidth([label frame]), 40);
}

- (void)testShortTitleNeverShrinksTheLabelBelowItsOriginalWidth
{
	AILocalizationTextField *label = [self labelWithFrame:NSMakeRect(400, 40, 40, 17) alignment:NSTextAlignmentLeft];

	[label setStringValue:@"a"];

	XCTAssertEqualWithAccuracy(NSWidth([label frame]), 40, 0.5);
	XCTAssertEqualWithAccuracy(NSMinX([label frame]), 400, 0.5);
}

- (void)testLabelThatWouldLeaveItsSuperviewIsPulledBackInside
{
	AILocalizationTextField *label = [self labelWithFrame:NSMakeRect(950, 40, 40, 17) alignment:NSTextAlignmentLeft];

	[label setStringValue:LONG_TITLE];

	XCTAssertLessThanOrEqual(NSMaxX([label frame]), 1000);
	XCTAssertGreaterThanOrEqual(NSMinX([label frame]), 0);
}

- (void)testLocalizedStringGoesThroughTheSameSizing
{
	AILocalizationTextField *label = [self labelWithFrame:NSMakeRect(400, 40, 40, 17) alignment:NSTextAlignmentRight];

	[label setLocalizedString:LONG_TITLE];

	XCTAssertEqualObjects([label stringValue], LONG_TITLE);
	XCTAssertEqualWithAccuracy(NSMaxX([label frame]), 440, 0.5);
}

@end
