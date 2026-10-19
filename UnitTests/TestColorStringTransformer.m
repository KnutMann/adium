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

#import <AIUtilities/AIColorAdditions.h>

/* AIColorStringTransformer.h is not among the framework's public headers; the class has nothing to
 * declare beyond what NSValueTransformer does. */
@interface AIColorStringTransformer : NSValueTransformer
@end

@interface TestColorStringTransformer : XCTestCase
@end

@implementation TestColorStringTransformer {
	AIColorStringTransformer *transformer;
}

- (void)setUp
{
	[super setUp];
	transformer = [[AIColorStringTransformer alloc] init];
}

- (void)testIsRegisteredUnderItsOwnNameWhenTheFrameworkLoads
{
	XCTAssertTrue([[NSValueTransformer valueTransformerForName:@"AIColorStringTransformer"] isKindOfClass:[AIColorStringTransformer class]]);
}

- (void)testIsReversible
{
	XCTAssertTrue([AIColorStringTransformer allowsReverseTransformation]);
}

- (void)testAStringOfComponentsBecomesAColour
{
	id colour = [transformer transformedValue:@"255,0,0"];
	XCTAssertTrue([colour isKindOfClass:[NSColor class]]);
	XCTAssertEqualObjects([colour hexString], @"ff0000");
	XCTAssertEqualWithAccuracy([colour alphaComponent], 1.0, AIFloatComparisonAccuracy);
}

- (void)testAFourthComponentIsTheAlpha
{
	NSColor *colour = [transformer transformedValue:@"255,255,255,0"];
	XCTAssertEqualObjects([colour hexString], @"ffffff");
	XCTAssertEqualWithAccuracy([colour alphaComponent], 0.0, AIFloatComparisonAccuracy);
}

- (void)testAColourBecomesAStringOfComponents
{
	XCTAssertEqualObjects([transformer reverseTransformedValue:[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1]], @"255,255,255");
	XCTAssertEqualObjects([transformer reverseTransformedValue:[NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:1]], @"0,0,0");
	XCTAssertEqualObjects([transformer reverseTransformedValue:[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0]], @"255,255,255,0");
}

- (void)testTheComponentsAreTheSRGBOnes
{
	XCTAssertEqualObjects([transformer reverseTransformedValue:[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1]], @"255,0,0");
	XCTAssertEqualObjects([transformer transformedValue:@"255,0,0"], [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1]);
}

- (void)testAStringSurvivesTheTripThroughAColour
{
	for (NSString *string in @[ @"255,0,0", @"0,255,0", @"0,0,255", @"0,0,0,0", @"255,255,255,128" ]) {
		XCTAssertEqualObjects([transformer reverseTransformedValue:[transformer transformedValue:string]], string);
	}
	// The alpha is written only when there is one, so a spelled-out 255 does not come back.
	XCTAssertEqualObjects([transformer reverseTransformedValue:[transformer transformedValue:@"0,0,0,255"]], @"0,0,0");
}

- (void)testAStringThatIsNotAColourGivesNothing
{
	XCTAssertNil([transformer transformedValue:@"red"]);
	XCTAssertNil([transformer transformedValue:@""]);
	XCTAssertNil([transformer transformedValue:@"1,2"]);
	XCTAssertNil([transformer transformedValue:@"1,2,3,4,5"]);
}

- (void)testValuesOfOtherClassesPassThroughUnchanged
{
	NSColor *colour = [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:1];
	XCTAssertEqual([transformer transformedValue:colour], colour);
	XCTAssertEqual([transformer reverseTransformedValue:@"0,0,0"], @"0,0,0");
	XCTAssertNil([transformer transformedValue:nil]);
	XCTAssertNil([transformer reverseTransformedValue:nil]);
}

- (void)testTransformedValueClassIsWhatTheForwardTransformReturns
{
	XCTAssertTrue([[transformer transformedValue:@"255,0,0"] isKindOfClass:[AIColorStringTransformer transformedValueClass]]);
}

@end
