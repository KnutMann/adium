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

/* What TestColorAdditions, the generated file, does not pin: the CSS colour function, the
 * names, conversions of colours away from the primaries, and the space the results are in. */
@interface TestColorConversions : XCTestCase
@end

#define AIAssertSRGB(color, r, g, b, a) do { \
	NSColor *converted = [(color) colorUsingColorSpace:[NSColorSpace sRGBColorSpace]]; \
	XCTAssertNotNil(converted); \
	XCTAssertEqualWithAccuracy([converted redComponent], (r), AIFloatComparisonAccuracy); \
	XCTAssertEqualWithAccuracy([converted greenComponent], (g), AIFloatComparisonAccuracy); \
	XCTAssertEqualWithAccuracy([converted blueComponent], (b), AIFloatComparisonAccuracy); \
	XCTAssertEqualWithAccuracy([converted alphaComponent], (a), AIFloatComparisonAccuracy); \
} while (0)

@implementation TestColorConversions

#pragma mark The CSS colour function

- (void)testRGBFunctionTakesItsChannelsFromZeroTo255
{
	AIAssertSRGB([NSColor colorWithHTMLString:@"rgb(128,0,0)"], 128.0 / 255.0, 0, 0, 1);
	XCTAssertEqualObjects([[NSColor colorWithHTMLString:@"rgb(128,0,0)"] hexString], @"800000");
}

- (void)testRGBFunctionTakesPercentages
{
	AIAssertSRGB([NSColor colorWithHTMLString:@"rgb(50%,0%,100%)"], 0.5, 0, 1, 1);
}

- (void)testRGBFunctionAllowsSpacesAroundTheNumbers
{
	AIAssertSRGB([NSColor colorWithHTMLString:@"rgb( 0 , 128 , 255 )"], 0, 128.0 / 255.0, 1, 1);
}

- (void)testRGBAFunctionTakesItsAlphaFromZeroToOne
{
	AIAssertSRGB([NSColor colorWithHTMLString:@"rgba(0,0,255,0.5)"], 0, 0, 1, 0.5);
}

- (void)testRGBFunctionClampsChannelsToTheGamut
{

	AIAssertSRGB([NSColor colorWithHTMLString:@"rgb(300,-5,0)"], 1, 0, 0, 1);
}

- (void)testRGBFunctionWithTheWrongNumberOfArgumentsGivesTheDefault
{
	NSColor *fallback = [NSColor colorWithSRGBRed:0.1 green:0.2 blue:0.3 alpha:1];

	XCTAssertTrue([NSColor colorWithHTMLString:@"rgb(1,2)" defaultColor:fallback] == fallback);
	XCTAssertTrue([NSColor colorWithHTMLString:@"rgb(1,2,3,4,5)" defaultColor:fallback] == fallback);
	XCTAssertNil([NSColor colorWithHTMLString:@"rgb(1,2)"]);
}

- (void)testRGBWithoutParenthesesGivesTheDefault
{
	NSColor *fallback = [NSColor colorWithSRGBRed:0.1 green:0.2 blue:0.3 alpha:1];

	XCTAssertTrue([NSColor colorWithHTMLString:@"rgb" defaultColor:fallback] == fallback);
	XCTAssertTrue([NSColor colorWithHTMLString:@"rgb 1,2,3" defaultColor:fallback] == fallback);
}

- (void)testColoursFromHTMLStringsAreInSRGB
{
	NSColorSpace *sRGB = [NSColorSpace sRGBColorSpace];

	//colorWithHTMLString: returns id, so the receiver is named for the compiler's sake
	XCTAssertEqualObjects([(NSColor *)[NSColor colorWithHTMLString:@"#123456"] colorSpace], sRGB);
	XCTAssertEqualObjects([(NSColor *)[NSColor colorWithHTMLString:@"#abc"] colorSpace], sRGB);
	XCTAssertEqualObjects([(NSColor *)[NSColor colorWithHTMLString:@"rgb(1,2,3)"] colorSpace], sRGB);
}

#pragma mark Names

- (void)testNamedColoursResolveThroughTheNameTable
{

	AIAssertSRGB([NSColor colorWithHTMLString:@"red"], 1, 0, 0, 1);
	AIAssertSRGB([NSColor colorWithHTMLString:@"white"], 1, 1, 1, 1);
	AIAssertSRGB([NSColor colorWithHTMLString:@"maroon"], 128.0 / 255.0, 0, 0, 1);
}

- (void)testNamedColoursAreFoundWhateverTheirCase
{

	AIAssertSRGB([NSColor colorWithHTMLString:@"TEAL"], 0, 128.0 / 255.0, 128.0 / 255.0, 1);
}

- (void)testTheNameTableItselfHoldsTheCSSColours
{
	NSDictionary *names = [NSColor colorNamesDictionary];

	AIAssertSRGB(names[@"maroon"], 128.0 / 255.0, 0, 0, 1);
	AIAssertSRGB(names[@"teal"], 0, 128.0 / 255.0, 128.0 / 255.0, 1);
	AIAssertSRGB(names[@"white"], 1, 1, 1, 1);
}

#pragma mark Writing colours out

- (void)testHexStringKeepsChannelsBetweenThePrimaries
{
	XCTAssertEqualObjects([[NSColor colorWithSRGBRed:128.0 / 255.0 green:1.0 / 255.0 blue:254.0 / 255.0 alpha:1] hexString], @"8001fe");
	XCTAssertEqualObjects([[NSColor colorWithHTMLString:@"#123456"] hexString], @"123456");
	XCTAssertEqualObjects([[NSColor colorWithHTMLString:@"#0a0b0c"] hexString], @"0a0b0c");
}

- (void)testHexStringConvertsOtherSpacesIntoSRGB
{
	XCTAssertEqualObjects([[NSColor colorWithDeviceWhite:1 alpha:1] hexString], @"ffffff");
	XCTAssertEqualObjects([[NSColor colorWithGenericGamma22White:0 alpha:1] hexString], @"000000");
}

- (void)testCSSRepresentationWithAlphaUses255ChannelsAndAUnitAlpha
{
	XCTAssertEqualObjects([[NSColor colorWithSRGBRed:0.5 green:0 blue:1 alpha:0.25] CSSRepresentation], @"rgba(127.5,0,255,0.25)");
}

- (void)testCSSRepresentationOfAnOpaqueColourIsAHexLiteral
{
	XCTAssertEqualObjects([[NSColor colorWithSRGBRed:128.0 / 255.0 green:1.0 / 255.0 blue:254.0 / 255.0 alpha:1] CSSRepresentation], @"#8001fe");
}

#pragma mark Deriving colours

- (void)testContrastingColorInvertsAColourThatIsNotMedium
{
	NSColor *navy = [NSColor colorWithSRGBRed:0 green:0 blue:0.2 alpha:1];

	AIAssertSRGB([navy contrastingColor], 1, 1, 0.8, 1);
	XCTAssertEqualObjects([[navy contrastingColor] colorSpace], [NSColorSpace sRGBColorSpace]);
}

- (void)testContrastingColorIsWhiteOrBlackForAMediumColour
{
	AIAssertSRGB([[NSColor colorWithSRGBRed:0.4 green:0.4 blue:0.4 alpha:1] contrastingColor], 1, 1, 1, 1);
	AIAssertSRGB([[NSColor colorWithSRGBRed:0.6 green:0.6 blue:0.6 alpha:1] contrastingColor], 0, 0, 0, 1);
	//Exactly half bright is medium but not dark, as colorIsDark documents
	AIAssertSRGB([[NSColor colorWithSRGBRed:0.5 green:0.5 blue:0.5 alpha:1] contrastingColor], 0, 0, 0, 1);
}

- (void)testDarkenByLowersOnlyTheBrightness
{
	NSColor *blue = [NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:0.5];

	NSColor *darker = [blue darkenBy:0.25];
	AIAssertSRGB(darker, 0, 0, 0.75, 0.5);
	XCTAssertEqualWithAccuracy([darker hueComponent], 2.0 / 3.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy([darker saturationComponent], 1, AIFloatComparisonAccuracy);
	XCTAssertEqualObjects([darker colorSpace], [NSColorSpace sRGBColorSpace]);
}

- (void)testAdjustHueMovesAroundTheWheel
{
	NSColor *red = [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1];

	AIAssertSRGB([red adjustHue:0.5 saturation:0 brightness:0], 0, 1, 1, 1);
	AIAssertSRGB([red adjustHue:0 saturation:0 brightness:0], 1, 0, 0, 1);
}

- (void)testAdjustHueCapsSaturationAndBrightnessAtTheEnds
{
	NSColor *gray = [NSColor colorWithSRGBRed:0.5 green:0.5 blue:0.5 alpha:1];

	AIAssertSRGB([gray adjustHue:0 saturation:0 brightness:0.7], 1, 1, 1, 1);
	AIAssertSRGB([gray adjustHue:0 saturation:0 brightness:-0.7], 0, 0, 0, 1);
	AIAssertSRGB([gray adjustHue:0 saturation:-0.3 brightness:0], 0.5, 0.5, 0.5, 1);
}

@end
