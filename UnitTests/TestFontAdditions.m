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
#import <AIUtilities/AIFontAdditions.h>

@interface TestFontAdditions : XCTestCase
@end

@implementation TestFontAdditions

#pragma mark Cached fonts

- (void)testCachedFontReturnsTheNamedFont
{
	NSFont *font = [NSFont cachedFontWithName:@"Helvetica" size:12];
	XCTAssertEqualObjects([font fontName], @"Helvetica");
	XCTAssertEqualWithAccuracy([font pointSize], 12.0, AIFloatComparisonAccuracy);
}

- (void)testCachedFontReturnsTheSameInstanceForTheSameRequest
{
	NSFont *first = [NSFont cachedFontWithName:@"Menlo-Regular" size:11];
	NSFont *second = [NSFont cachedFontWithName:@"Menlo-Regular" size:11];
	XCTAssertTrue(first == second, @"The cache should hand out the instance it holds");
}

- (void)testCachedFontDistinguishesSizes
{
	NSFont *twelve = [NSFont cachedFontWithName:@"Helvetica" size:12];
	NSFont *thirteen = [NSFont cachedFontWithName:@"Helvetica" size:13];
	XCTAssertEqualWithAccuracy([thirteen pointSize], 13.0, AIFloatComparisonAccuracy);
	XCTAssertNotEqualObjects(twelve, thirteen);
}

- (void)testCachedFontWithNilNameFallsBackToTheControlContentFont
{
	NSFont *font = [NSFont cachedFontWithName:nil size:13];
	NSFont *expected = [NSFont controlContentFontOfSize:13];
	XCTAssertEqualObjects([font fontName], [expected fontName]);
	XCTAssertEqualWithAccuracy([font pointSize], 13.0, AIFloatComparisonAccuracy);
}

- (void)testCachedFontWithUnknownNameFallsBackToTheControlContentFont
{
	NSFont *font = [NSFont cachedFontWithName:@"NoSuchFont-Regular" size:15];
	NSFont *expected = [NSFont controlContentFontOfSize:15];
	XCTAssertEqualObjects([font fontName], [expected fontName]);
	XCTAssertEqualWithAccuracy([font pointSize], 15.0, AIFloatComparisonAccuracy);
}

#pragma mark String representation

- (void)testStringRepresentationIsNameCommaSize
{
	XCTAssertEqualObjects([[NSFont fontWithName:@"Helvetica-Bold" size:14] stringRepresentation], @"Helvetica-Bold,14");
}

- (void)testRepresentedFontReadsTheRepresentationBack
{
	NSFont *font = [@"Menlo-Bold,11" representedFont];
	XCTAssertEqualObjects([font fontName], @"Menlo-Bold");
	XCTAssertEqualWithAccuracy([font pointSize], 11.0, AIFloatComparisonAccuracy);
}

- (void)testFontSurvivesARoundTripThroughItsRepresentation
{
	NSFont *font = [NSFont fontWithName:@"Helvetica-Oblique" size:18];
	XCTAssertEqualObjects([[font stringRepresentation] representedFont], font);
}

#pragma mark CSS

- (void)testCSSRepresentationIsSizeAndFamily
{
	XCTAssertEqualObjects([[NSFont fontWithName:@"Helvetica" size:12] CSSRepresentation], @"12pt Helvetica");
}

- (void)testCSSRepresentationLeadsWithTheWeight
{
	XCTAssertEqualObjects([[NSFont fontWithName:@"Menlo-Bold" size:11] CSSRepresentation], @"bold 11pt Menlo");
}

- (void)testCSSRepresentationPutsBoldBeforeItalic
{
	XCTAssertEqualObjects([[NSFont fontWithName:@"Helvetica-BoldOblique" size:12] CSSRepresentation], @"bold italic 12pt Helvetica");
	XCTAssertEqualObjects([[NSFont fontWithName:@"Helvetica-Oblique" size:12] CSSRepresentation], @"italic 12pt Helvetica");
}

- (void)testCSSRepresentationKeepsAFractionalSizeWithoutTrailingZeroes
{
	XCTAssertEqualObjects([[NSFont fontWithName:@"Helvetica" size:12.5] CSSRepresentation], @"12.5pt Helvetica");
	XCTAssertEqualObjects([[NSFont fontWithName:@"Helvetica" size:12.25] CSSRepresentation], @"12.25pt Helvetica");
}

- (void)testCSSRepresentationQuotesAFamilyNameWithSpaces
{
	XCTExpectFailure(@"AIFontAdditions.m:84 writes the family name bare; AIAttributedStringAdditions.h documents the CSS form as 12pt \"Lucida Grande\", and CSS needs the quotes for a name with a space");
	NSFont *font = [NSFont fontWithName:@"HelveticaNeue" size:12];
	XCTAssertEqualObjects([font familyName], @"Helvetica Neue");
	XCTAssertEqualObjects([font CSSRepresentation], @"12pt \"Helvetica Neue\"");
}

#pragma mark Trait support

- (void)testFamiliesWithABoldFaceSupportBold
{
	XCTAssertTrue([[NSFont fontWithName:@"Helvetica" size:12] supportsBold]);
	XCTAssertTrue([[NSFont fontWithName:@"Menlo-Regular" size:12] supportsBold]);
}

- (void)testFamiliesWithAnItalicFaceSupportItalics
{
	XCTAssertTrue([[NSFont fontWithName:@"Helvetica" size:12] supportsItalics]);
	XCTAssertTrue([[NSFont fontWithName:@"Menlo-Regular" size:12] supportsItalics]);
}

@end
