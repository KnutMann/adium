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
#import <AIUtilities/AITextAttributes.h>

@interface TestTextAttributes : XCTestCase
@end

@implementation TestTextAttributes

- (NSFont *)fontOf:(AITextAttributes *)attributes
{
	return [[attributes dictionary] objectForKey:NSFontAttributeName];
}

- (NSFontTraitMask)traitsOfFont:(NSFont *)font
{
	return [[NSFontManager sharedFontManager] traitsOfFont:font];
}

#pragma mark Fonts

- (void)testDictionaryCarriesTheRequestedFont
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:14];
	NSFont *font = [self fontOf:attributes];
	XCTAssertEqualObjects([font familyName], @"Helvetica");
	XCTAssertEqualWithAccuracy([font pointSize], 14.0, AIFloatComparisonAccuracy);
	XCTAssertEqualObjects([attributes fontFamily], @"Helvetica");
	XCTAssertEqual([attributes fontSize], (NSInteger)14);
}

- (void)testBoldTraitProducesABoldFace
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:NSBoldFontMask size:12];
	XCTAssertTrue([self traitsOfFont:[self fontOf:attributes]] & NSBoldFontMask);
	XCTAssertFalse([self traitsOfFont:[self fontOf:attributes]] & NSItalicFontMask);
}

- (void)testItalicTraitProducesAnItalicFace
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:NSItalicFontMask size:12];
	XCTAssertTrue([self traitsOfFont:[self fontOf:attributes]] & NSItalicFontMask);
	XCTAssertFalse([self traitsOfFont:[self fontOf:attributes]] & NSBoldFontMask);
}

- (void)testUnknownFamilyFallsBackToHelvetica
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"No Such Family" traits:0 size:12];
	XCTAssertEqualObjects([[self fontOf:attributes] familyName], @"Helvetica");
}

- (void)testFamilyNameIsMatchedCaseInsensitively
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"menlo" traits:0 size:12];
	XCTAssertEqualObjects([[self fontOf:attributes] familyName], @"Menlo");
}

- (void)testZeroSizeMeansTwelvePoints
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:0];
	XCTAssertEqualWithAccuracy([[self fontOf:attributes] pointSize], 12.0, AIFloatComparisonAccuracy);
}

- (void)testSettingTheSizeReplacesTheFont
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	XCTAssertEqualWithAccuracy([[self fontOf:attributes] pointSize], 12.0, AIFloatComparisonAccuracy);
	[attributes setFontSize:20];
	XCTAssertEqual([attributes fontSize], (NSInteger)20);
	XCTAssertEqualWithAccuracy([[self fontOf:attributes] pointSize], 20.0, AIFloatComparisonAccuracy);
}

- (void)testSettingTheFamilyReplacesTheFont
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	XCTAssertEqualObjects([[self fontOf:attributes] familyName], @"Helvetica");
	[attributes setFontFamily:@"Menlo"];
	XCTAssertEqualObjects([[self fontOf:attributes] familyName], @"Menlo");
}

- (void)testEnableTraitAddsToTheMask
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	[attributes enableTrait:NSBoldFontMask];
	XCTAssertEqual([attributes traits], (NSFontTraitMask)NSBoldFontMask);
	XCTAssertTrue([self traitsOfFont:[self fontOf:attributes]] & NSBoldFontMask);
}

- (void)testDisableTraitRemovesOnlyThatTrait
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:(NSBoldFontMask | NSItalicFontMask) size:12];
	[attributes disableTrait:NSBoldFontMask];
	XCTAssertEqual([attributes traits], (NSFontTraitMask)NSItalicFontMask);
	XCTAssertFalse([self traitsOfFont:[self fontOf:attributes]] & NSBoldFontMask);
	XCTAssertTrue([self traitsOfFont:[self fontOf:attributes]] & NSItalicFontMask);
}

- (void)testDisablingAnAbsentTraitLeavesTheMaskAlone
{
	XCTExpectFailure(@"AITextAttributes.m:207 removes a trait with ^= instead of &= ~, so disabling bold on an italic-only mask turns bold on");
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:NSItalicFontMask size:12];
	[attributes disableTrait:NSBoldFontMask];
	XCTAssertEqual([attributes traits], (NSFontTraitMask)NSItalicFontMask);
	XCTAssertFalse([self traitsOfFont:[self fontOf:attributes]] & NSBoldFontMask);
}

#pragma mark Decorations

- (void)testUnderlineIsStoredAndRemoved
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	XCTAssertFalse([attributes underline]);
	[attributes setUnderline:YES];
	XCTAssertTrue([attributes underline]);
	XCTAssertTrue([[[attributes dictionary] objectForKey:NSUnderlineStyleAttributeName] boolValue]);
	[attributes setUnderline:NO];
	XCTAssertFalse([attributes underline]);
	XCTAssertNil([[attributes dictionary] objectForKey:NSUnderlineStyleAttributeName]);
}

- (void)testStrikethroughIsStoredAndRemoved
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	[attributes setStrikethrough:YES];
	XCTAssertTrue([attributes strikethrough]);
	XCTAssertTrue([[[attributes dictionary] objectForKey:NSStrikethroughStyleAttributeName] boolValue]);
	[attributes setStrikethrough:NO];
	XCTAssertFalse([attributes strikethrough]);
	XCTAssertNil([[attributes dictionary] objectForKey:NSStrikethroughStyleAttributeName]);
}

- (void)testSubscriptLowersTheBaselineAndShrinksTheFont
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	[attributes setSubscript:YES];
	XCTAssertLessThan([[[attributes dictionary] objectForKey:NSBaselineOffsetAttributeName] floatValue], 0.0f);
	XCTAssertLessThan([[self fontOf:attributes] pointSize], 12.0);
	[attributes setSubscript:NO];
	XCTAssertNil([[attributes dictionary] objectForKey:NSBaselineOffsetAttributeName]);
	XCTAssertEqualWithAccuracy([[self fontOf:attributes] pointSize], 12.0, AIFloatComparisonAccuracy);
}

- (void)testSuperscriptRaisesTheBaselineAndShrinksTheFont
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	[attributes setSuperscript:YES];
	XCTAssertGreaterThan([[[attributes dictionary] objectForKey:NSBaselineOffsetAttributeName] floatValue], 0.0f);
	XCTAssertLessThan([[self fontOf:attributes] pointSize], 12.0);
	[attributes setSuperscript:NO];
	XCTAssertNil([[attributes dictionary] objectForKey:NSBaselineOffsetAttributeName]);
	XCTAssertEqualWithAccuracy([[self fontOf:attributes] pointSize], 12.0, AIFloatComparisonAccuracy);
}

#pragma mark Colors, links, language, direction

- (void)testTextColorIsStoredAsForegroundColorAndNilRemovesIt
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	NSColor *color = [NSColor colorWithSRGBRed:0.25 green:0.5 blue:0.75 alpha:1.0];
	[attributes setTextColor:color];
	XCTAssertEqualObjects([attributes textColor], color);
	XCTAssertEqualObjects([[attributes dictionary] objectForKey:NSForegroundColorAttributeName], color);
	[attributes setTextColor:nil];
	XCTAssertNil([attributes textColor]);
	XCTAssertNil([[attributes dictionary] objectForKey:NSForegroundColorAttributeName]);
}

- (void)testTextBackgroundColorIsStoredAsBackgroundColorAndNilRemovesIt
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	NSColor *color = [NSColor colorWithSRGBRed:1.0 green:1.0 blue:0.0 alpha:1.0];
	[attributes setTextBackgroundColor:color];
	XCTAssertEqualObjects([attributes textBackgroundColor], color);
	XCTAssertEqualObjects([[attributes dictionary] objectForKey:NSBackgroundColorAttributeName], color);
	[attributes setTextBackgroundColor:nil];
	XCTAssertNil([[attributes dictionary] objectForKey:NSBackgroundColorAttributeName]);
}

- (void)testBackgroundColorIsStoredUnderTheBodyColorKey
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	NSColor *color = [NSColor colorWithSRGBRed:0.0 green:0.0 blue:0.5 alpha:1.0];
	[attributes setBackgroundColor:color];
	XCTAssertEqualObjects([attributes backgroundColor], color);
	XCTAssertEqualObjects([[attributes dictionary] objectForKey:AIBodyColorAttributeName], color);
	XCTAssertNil([[attributes dictionary] objectForKey:NSBackgroundColorAttributeName], @"The body color is not the text background");
	[attributes setBackgroundColor:nil];
	XCTAssertNil([[attributes dictionary] objectForKey:AIBodyColorAttributeName]);
}

- (void)testLinkURLIsStoredAndNilRemovesIt
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	NSURL *url = [NSURL URLWithString:@"https://adium.im/"];
	[attributes setLinkURL:url];
	XCTAssertEqualObjects([[attributes dictionary] objectForKey:NSLinkAttributeName], url);
	[attributes setLinkURL:nil];
	XCTAssertNil([[attributes dictionary] objectForKey:NSLinkAttributeName]);
}

- (void)testLanguageValueIsStoredAndNilRemovesIt
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	[attributes setLanguageValue:@"de"];
	XCTAssertEqualObjects([attributes languageValue], @"de");
	[attributes setLanguageValue:nil];
	XCTAssertNil([attributes languageValue]);
}

- (void)testWritingDirectionGoesIntoTheParagraphStyle
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	[attributes setWritingDirection:NSWritingDirectionRightToLeft];
	NSParagraphStyle *style = [[attributes dictionary] objectForKey:NSParagraphStyleAttributeName];
	XCTAssertEqual([style baseWritingDirection], NSWritingDirectionRightToLeft);
	[attributes setWritingDirection:NSWritingDirectionLeftToRight];
	style = [[attributes dictionary] objectForKey:NSParagraphStyleAttributeName];
	XCTAssertEqual([style baseWritingDirection], NSWritingDirectionLeftToRight);
}

#pragma mark Reset, construction from a dictionary, copying

- (void)testResetFontAttributesRestoresTheDefaults
{
	XCTExpectFailure(@"AITextAttributes.m:308 resetFontAttributes clears the family and size but leaves the old NSFont in the dictionary, so -dictionary keeps handing out Menlo 20 instead of the default Helvetica 12 the header promises");
	AITextAttributes *attributes = [AITextAttributes textAttributesWithFontFamily:@"Menlo" traits:0 size:20];
	[attributes setTextColor:[NSColor redColor]];
	[attributes setTextBackgroundColor:[NSColor yellowColor]];
	[attributes setLanguageValue:@"de"];
	XCTAssertEqualObjects([[self fontOf:attributes] familyName], @"Menlo");

	[attributes resetFontAttributes];
	XCTAssertNil([attributes textColor]);
	XCTAssertNil([attributes textBackgroundColor]);
	XCTAssertNil([attributes languageValue]);
	XCTAssertEqualObjects([[self fontOf:attributes] familyName], @"Helvetica");
	XCTAssertEqualWithAccuracy([[self fontOf:attributes] pointSize], 12.0, AIFloatComparisonAccuracy);
}

- (void)testAttributesFromADictionaryTakeFamilySizeAndTraitsFromItsFont
{
	NSColor *color = [NSColor colorWithSRGBRed:0.25 green:0.5 blue:0.75 alpha:1.0];
	NSDictionary *dictionary = @{ NSFontAttributeName: [NSFont fontWithName:@"Helvetica-Bold" size:14], NSForegroundColorAttributeName: color };
	AITextAttributes *attributes = [AITextAttributes textAttributesWithDictionary:dictionary];
	XCTAssertEqualObjects([attributes fontFamily], @"Helvetica");
	XCTAssertEqual([attributes fontSize], (NSInteger)14);
	XCTAssertTrue([attributes traits] & NSBoldFontMask);
	XCTAssertEqualObjects([attributes textColor], color, @"Other attributes are kept");
}

- (void)testAttributesFromADictionaryWithoutAFontDefaultToHelveticaTwelve
{
	AITextAttributes *attributes = [AITextAttributes textAttributesWithDictionary:@{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle) }];
	XCTAssertEqualObjects([attributes fontFamily], @"Helvetica");
	XCTAssertEqual([attributes fontSize], (NSInteger)12);
	XCTAssertEqualObjects([[self fontOf:attributes] familyName], @"Helvetica");
	XCTAssertTrue([attributes underline]);
}

- (void)testCopyIsIndependentOfTheOriginal
{
	AITextAttributes *original = [AITextAttributes textAttributesWithFontFamily:@"Helvetica" traits:0 size:12];
	[original setUnderline:YES];
	AITextAttributes *copy = [original copy];
	[copy setFontSize:20];
	[copy setUnderline:NO];
	XCTAssertEqual([original fontSize], (NSInteger)12);
	XCTAssertTrue([original underline]);
	XCTAssertEqual([copy fontSize], (NSInteger)20);
	XCTAssertFalse([copy underline]);
}

@end
