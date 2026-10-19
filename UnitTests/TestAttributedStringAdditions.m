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

#import "TestAttributedStringAdditions.h"

#import <AIUtilities/AIAttributedStringAdditions.h>

/* An attachment that knows its own text, as Adium's emoticon attachments do. */
@interface AITestNamedAttachment : NSTextAttachment
@end
@implementation AITestNamedAttachment
- (NSString *)string
{
	return @":)";
}
@end

static CGFloat Brightness(NSColor *color)
{
	return [[color colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]] brightnessComponent];
}

static NSMutableAttributedString *StringWithAttachments(NSString *lead, NSTextAttachment *first, NSString *middle, NSTextAttachment *second, NSString *trail)
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:lead];
	if (first) [string appendAttributedString:[NSAttributedString attributedStringWithAttachment:first]];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:middle]];
	if (second) [string appendAttributedString:[NSAttributedString attributedStringWithAttachment:second]];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:trail]];
	return string;
}

@implementation TestAttributedStringAdditions

- (void) testLinkedAttributedString
{
	NSString *linkLabel = @"Adium";
	NSString *linkURLString = @"http://www.adium.im/";
	NSURL *linkURL = [NSURL URLWithString:linkURLString];
	NSRange linkRange = { 0UL, 0UL };
	id linkValue;
	NSAttributedString *attributedString = nil;
	NSRange attributedStringRange;

	//First, try a string containing a URL.
	XCTAssertNoThrow(attributedString = [NSAttributedString attributedStringWithLinkLabel:linkLabel linkDestination:linkURLString], @"attributedStringWithLinkLabel:linkDestination: threw an exception");
	XCTAssertNotNil(attributedString, @"attributedStringWithLinkLabel:linkDestination: returned nil");
	XCTAssertEqualObjects([attributedString string], linkLabel, @"Attributed string's text is not equal to the original string");
	XCTAssertEqual([attributedString length], [linkLabel length], @"Attributed string is not the same length (%lu) as the original string (%lu)", [attributedString length], [linkLabel length]);
	linkValue = [attributedString attribute:NSLinkAttributeName atIndex:0UL effectiveRange:&linkRange];
	XCTAssertNotNil(linkValue, @"Attributed string does not have a link");
	XCTAssertTrue([linkValue isKindOfClass:[NSURL class]], @"Link value is not an NSURL");
	XCTAssertEqualObjects(linkValue, linkURL, @"Link value is not equal to the URL we provided");
	attributedStringRange = (NSRange){ 0UL, [attributedString length] };
	XCTAssertTrue(NSEqualRanges(linkRange, attributedStringRange), @"Link range is not the entire range of the attributed string");

	//Next, try an NSURL object.
	XCTAssertNoThrow(attributedString = [NSAttributedString attributedStringWithLinkLabel:linkLabel linkDestination:linkURL], @"attributedStringWithLinkLabel:linkDestination: threw an exception");
	XCTAssertNotNil(attributedString, @"attributedStringWithLinkLabel:linkDestination: returned nil");
	XCTAssertEqualObjects([attributedString string], linkLabel, @"Attributed string's text is not equal to the original string");
	XCTAssertEqual([attributedString length], [linkLabel length], @"Attributed string is not the same length (%lu) as the original string (%lu)", [attributedString length], [linkLabel length]);
	linkValue = [attributedString attribute:NSLinkAttributeName atIndex:0UL effectiveRange:&linkRange];
	XCTAssertNotNil(linkValue, @"Attributed string does not have a link");
	XCTAssertTrue([linkValue isKindOfClass:[NSURL class]], @"Link value is not an NSURL");
	XCTAssertEqualObjects(linkValue, linkURL, @"Link value is not equal to the URL we provided");
	attributedStringRange = (NSRange){ 0UL, [attributedString length] };
	XCTAssertTrue(NSEqualRanges(linkRange, attributedStringRange), @"Link range is not the entire range of the attributed string");
}
- (void) testAttributedStringWithLinkedSubstring
{
	NSString *linkLabel = @"Download Adium now!";
	NSString *linkURLString = @"http://www.adium.im/";
	NSURL *linkURL = [NSURL URLWithString:linkURLString];
	NSRange intendedLinkRange = { 9UL, 5UL }; //@"Adium"
	NSRange linkRange = { 0UL, 0UL };
	id linkValue;
	NSAttributedString *attributedString = nil;

	//First, try a string containing a URL.
	XCTAssertNoThrow(attributedString = [NSAttributedString attributedStringWithString:linkLabel linkRange:intendedLinkRange linkDestination:linkURLString], @"attributedStringWithLinkLabel:linkDestination: threw an exception");
	XCTAssertNotNil(attributedString, @"attributedStringWithLinkLabel:linkDestination: returned nil");
	XCTAssertEqualObjects([attributedString string], linkLabel, @"Attributed string's text is not equal to the original string");
	XCTAssertEqual([attributedString length], [linkLabel length], @"Attributed string is not the same length (%lu) as the original string (%lu)", [attributedString length], [linkLabel length]);
	linkValue = [attributedString attribute:NSLinkAttributeName atIndex:intendedLinkRange.location effectiveRange:&linkRange];
	XCTAssertNotNil(linkValue, @"Attributed string does not have a link");
	XCTAssertTrue([linkValue isKindOfClass:[NSURL class]], @"Link value is not an NSURL");
	XCTAssertEqualObjects(linkValue, linkURL, @"Link value is not equal to the URL we provided");
	XCTAssertTrue(NSEqualRanges(linkRange, intendedLinkRange), @"Link range is not the range we wanted to link");

	//Next, try an NSURL object.
	XCTAssertNoThrow(attributedString = [NSAttributedString attributedStringWithString:linkLabel linkRange:intendedLinkRange linkDestination:linkURL], @"attributedStringWithLinkLabel:linkDestination: threw an exception");
	XCTAssertNotNil(attributedString, @"attributedStringWithLinkLabel:linkDestination: returned nil");
	XCTAssertEqualObjects([attributedString string], linkLabel, @"Attributed string's text is not equal to the original string");
	XCTAssertEqual([attributedString length], [linkLabel length], @"Attributed string is not the same length (%lu) as the original string (%lu)", [attributedString length], [linkLabel length]);
	linkValue = [attributedString attribute:NSLinkAttributeName atIndex:intendedLinkRange.location effectiveRange:&linkRange];
	XCTAssertNotNil(linkValue, @"Attributed string does not have a link");
	XCTAssertTrue([linkValue isKindOfClass:[NSURL class]], @"Link value is not an NSURL");
	XCTAssertEqualObjects(linkValue, linkURL, @"Link value is not equal to the URL we provided");
	XCTAssertTrue(NSEqualRanges(linkRange, intendedLinkRange), @"Link range is not the range we wanted to link");
}
- (void) testAttributedStringWithLinkedEntireStringUsingSubstringMethod
{
	NSString *linkLabel = @"Adium";
	NSString *linkURLString = @"http://www.adium.im/";
	NSURL *linkURL = [NSURL URLWithString:linkURLString];
	NSRange intendedLinkRange = { 0UL, [linkLabel length] };
	NSRange linkRange = { 0UL, 0UL };
	id linkValue;
	NSAttributedString *attributedString = nil;
	NSRange attributedStringRange;

	//First, try a string containing a URL.
	XCTAssertNoThrow(attributedString = [NSAttributedString attributedStringWithString:linkLabel linkRange:intendedLinkRange linkDestination:linkURLString], @"attributedStringWithLinkLabel:linkDestination: threw an exception");
	XCTAssertNotNil(attributedString, @"attributedStringWithLinkLabel:linkDestination: returned nil");
	XCTAssertEqualObjects([attributedString string], linkLabel, @"Attributed string's text is not equal to the original string");
	XCTAssertEqual([attributedString length], [linkLabel length], @"Attributed string is not the same length (%lu) as the original string (%lu)", [attributedString length], [linkLabel length]);
	linkValue = [attributedString attribute:NSLinkAttributeName atIndex:0UL effectiveRange:&linkRange];
	XCTAssertNotNil(linkValue, @"Attributed string does not have a link");
	XCTAssertTrue([linkValue isKindOfClass:[NSURL class]], @"Link value is not an NSURL");
	XCTAssertEqualObjects(linkValue, linkURL, @"Link value is not equal to the URL we provided");
	attributedStringRange = (NSRange){ 0UL, [attributedString length] };
	XCTAssertTrue(NSEqualRanges(linkRange, attributedStringRange), @"Link range is not the entire range of the attributed string");

	//Next, try an NSURL object.
	XCTAssertNoThrow(attributedString = [NSAttributedString attributedStringWithString:linkLabel linkRange:intendedLinkRange linkDestination:linkURL], @"attributedStringWithLinkLabel:linkDestination: threw an exception");
	XCTAssertNotNil(attributedString, @"attributedStringWithLinkLabel:linkDestination: returned nil");
	XCTAssertEqualObjects([attributedString string], linkLabel, @"Attributed string's text is not equal to the original string");
	XCTAssertEqual([attributedString length], [linkLabel length], @"Attributed string is not the same length (%lu) as the original string (%lu)", [attributedString length], [linkLabel length]);
	linkValue = [attributedString attribute:NSLinkAttributeName atIndex:0UL effectiveRange:&linkRange];
	XCTAssertNotNil(linkValue, @"Attributed string does not have a link");
	XCTAssertTrue([linkValue isKindOfClass:[NSURL class]], @"Link value is not an NSURL");
	XCTAssertEqualObjects(linkValue, linkURL, @"Link value is not equal to the URL we provided");
	attributedStringRange = (NSRange){ 0UL, [attributedString length] };
	XCTAssertTrue(NSEqualRanges(linkRange, attributedStringRange), @"Link range is not the entire range of the attributed string");
}
- (void) testAttributedStringWithLinkedEmptySubstring
{
	NSString *linkLabel = @"Download Adium now!";
	NSString *linkURLString = @"http://www.adium.im/";
	NSURL *linkURL = [NSURL URLWithString:linkURLString];
	NSRange intendedLinkRange = { 9UL, 0UL }; //@""
	NSRange linkRange = { 0UL, 0UL };
	id linkValue;
	NSAttributedString *attributedString = nil;
	NSRange attributedStringRange;

	//First, try a string containing a URL.
	XCTAssertNoThrow(attributedString = [NSAttributedString attributedStringWithString:linkLabel linkRange:intendedLinkRange linkDestination:linkURLString], @"attributedStringWithLinkLabel:linkDestination: threw an exception");
	XCTAssertNotNil(attributedString, @"attributedStringWithLinkLabel:linkDestination: returned nil");
	XCTAssertEqualObjects([attributedString string], linkLabel, @"Attributed string's text is not equal to the original string");
	XCTAssertEqual([attributedString length], [linkLabel length], @"Attributed string is not the same length (%lu) as the original string (%lu)", [attributedString length], [linkLabel length]);
	linkValue = [attributedString attribute:NSLinkAttributeName atIndex:intendedLinkRange.location effectiveRange:&linkRange];
	XCTAssertNil(linkValue, @"Attributed string has a link");
	//linkRange, at this point, should be the range that does not have a link, which should be the entire string.
	attributedStringRange = (NSRange){ 0UL, [attributedString length] };
	XCTAssertTrue(NSEqualRanges(linkRange, attributedStringRange), @"Non-link range is not the entire string");

	//Next, try an NSURL object.
	XCTAssertNoThrow(attributedString = [NSAttributedString attributedStringWithString:linkLabel linkRange:intendedLinkRange linkDestination:linkURL], @"attributedStringWithLinkLabel:linkDestination: threw an exception");
	XCTAssertNotNil(attributedString, @"attributedStringWithLinkLabel:linkDestination: returned nil");
	XCTAssertEqualObjects([attributedString string], linkLabel, @"Attributed string's text is not equal to the original string");
	XCTAssertEqual([attributedString length], [linkLabel length], @"Attributed string is not the same length (%lu) as the original string (%lu)", [attributedString length], [linkLabel length]);
	linkValue = [attributedString attribute:NSLinkAttributeName atIndex:intendedLinkRange.location effectiveRange:&linkRange];
	XCTAssertNil(linkValue, @"Attributed string has a link");
	//linkRange, at this point, should be the range that does not have a link, which should be the entire string.
	attributedStringRange = (NSRange){ 0UL, [attributedString length] };
	XCTAssertTrue(NSEqualRanges(linkRange, attributedStringRange), @"Non-link range is not the entire string");
}

- (void) testAttributedStringByConvertingLinksToStrings {
	NSMutableAttributedString *input = [[NSMutableAttributedString alloc] initWithString:@"Adium requires Growl."];
	[input addAttribute:NSLinkAttributeName value:[NSURL URLWithString:@"http://www.adium.im/"] range:[[input string] rangeOfString:@"Adium"]];
	[input addAttribute:NSLinkAttributeName value:[NSURL URLWithString:@"http://growl.info/"] range:[[input string] rangeOfString:@"Growl"]];

	NSAttributedString *result = nil;
	XCTAssertNoThrow(result = [input attributedStringByConvertingLinksToStrings], @"-attributedStringByConvertingLinksToStrings threw an exception");
	XCTAssertNotNil(result, @"-attributedStringByConvertingLinksToStrings returned nil");

	XCTAssertEqualObjects([result string], @"Adium (http://www.adium.im/) requires Growl (http://growl.info/).", @"-attributedStringByConvertingLinksToStrings did not correctly expand the links");
}

- (void) testAttributedStringByConvertingLinksToURLStrings {
	NSMutableAttributedString *input = [[NSMutableAttributedString alloc] initWithString:@"Adium requires Growl."];
	[input addAttribute:NSLinkAttributeName value:[NSURL URLWithString:@"http://www.adium.im/"] range:[[input string] rangeOfString:@"Adium"]];
	[input addAttribute:NSLinkAttributeName value:[NSURL URLWithString:@"http://growl.info/"] range:[[input string] rangeOfString:@"Growl"]];

	NSAttributedString *result = nil;
	XCTAssertNoThrow(result = [input attributedStringByConvertingLinksToURLStrings], @"-attributedStringByConvertingLinksToURLStrings threw an exception");
	XCTAssertNotNil(result, @"-attributedStringByConvertingLinksToURLStrings returned nil");

	XCTAssertEqualObjects([result string], @"http://www.adium.im/ requires http://growl.info/.", @"-attributedStringByConvertingLinksToURLStrings did not correctly expand the links");
}

#pragma mark Appending and replacing

- (void)testAppendStringWithAttributesAppliesThemToTheAppendedTextOnly
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"ab"];
	[string appendString:@"cd" withAttributes:@{ NSForegroundColorAttributeName: [NSColor redColor] }];
	XCTAssertEqualObjects([string string], @"abcd");
	NSRange range = NSMakeRange(0, 0);
	XCTAssertNotNil([string attribute:NSForegroundColorAttributeName atIndex:2 effectiveRange:&range]);
	XCTAssertTrue(NSEqualRanges(range, NSMakeRange(2, 2)), @"Range was %@", NSStringFromRange(range));
	XCTAssertNil([string attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]);
}

- (void)testAppendStringWithNilAttributesAppendsPlainText
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"ab" attributes:@{ NSForegroundColorAttributeName: [NSColor redColor] }];
	[string appendString:@"cd" withAttributes:nil];
	XCTAssertEqualObjects([string string], @"abcd");
	XCTAssertEqual([[string attributesAtIndex:2 effectiveRange:NULL] count], (NSUInteger)0);
}

- (void)testReplaceOccurrencesMatchesNSMutableStringOnRepeatedWords
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"one two one two one"];
	NSMutableString *oracle = [@"one two one two one" mutableCopy];
	NSUInteger expected = [oracle replaceOccurrencesOfString:@"one" withString:@"1" options:0 range:NSMakeRange(0, [oracle length])];
	NSUInteger count = [string replaceOccurrencesOfString:@"one" withString:@"1" options:0 range:NSMakeRange(0, [string length])];
	XCTAssertEqual(count, expected);
	XCTAssertEqualObjects([string string], oracle);
}

- (void)testReplaceOccurrencesReplacesEveryMatchInTheRange
{
	XCTExpectFailure(@"AIAttributedStringAdditions.m:61 stops searching when the remaining length happens to equal the next location, so abXdXf keeps its second X where NSMutableString replaces both");
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"abXdXf"];
	NSMutableString *oracle = [@"abXdXf" mutableCopy];
	NSUInteger expected = [oracle replaceOccurrencesOfString:@"X" withString:@"Y" options:0 range:NSMakeRange(0, [oracle length])];
	NSUInteger count = [string replaceOccurrencesOfString:@"X" withString:@"Y" options:0 range:NSMakeRange(0, [string length])];
	XCTAssertEqual(count, expected);
	XCTAssertEqualObjects([string string], oracle);
}

- (void)testReplaceOccurrencesGivesTheReplacementTheAttributesOfTheReplacedText
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"aXb"];
	NSFont *bold = [NSFont fontWithName:@"Helvetica-Bold" size:12];
	[string addAttribute:NSFontAttributeName value:bold range:NSMakeRange(1, 1)];
	XCTAssertEqual([string replaceOccurrencesOfString:@"X" withString:@"YY" options:0 range:NSMakeRange(0, 3)], (NSUInteger)1);
	XCTAssertEqualObjects([string string], @"aYYb");
	XCTAssertEqualObjects([string attribute:NSFontAttributeName atIndex:1 effectiveRange:NULL], bold);
	XCTAssertEqualObjects([string attribute:NSFontAttributeName atIndex:2 effectiveRange:NULL], bold);
	XCTAssertNil([string attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL]);
	XCTAssertNil([string attribute:NSFontAttributeName atIndex:3 effectiveRange:NULL]);
}

- (void)testReplaceOccurrencesReturnsZeroWhenNothingMatches
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"abc"];
	XCTAssertEqual([string replaceOccurrencesOfString:@"X" withString:@"Y" options:0 range:NSMakeRange(0, 3)], (NSUInteger)0);
	XCTAssertEqualObjects([string string], @"abc");
}

- (void)testReplaceOccurrencesHonoursTheSearchRange
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"XaX"];
	XCTAssertEqual([string replaceOccurrencesOfString:@"X" withString:@"Y" options:0 range:NSMakeRange(0, 1)], (NSUInteger)1);
	XCTAssertEqualObjects([string string], @"YaX");
}

- (void)testReplaceOccurrencesCanIgnoreCase
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"xax"];
	XCTAssertEqual([string replaceOccurrencesOfString:@"X" withString:@"Y" options:NSCaseInsensitiveSearch range:NSMakeRange(0, 3)], (NSUInteger)2);
	XCTAssertEqualObjects([string string], @"YaY");
}

- (void)testReplaceOccurrencesWithAttributesGivesTheReplacementThoseAttributes
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"aXb"];
	NSDictionary *attributes = @{ NSForegroundColorAttributeName: [NSColor redColor] };
	XCTAssertEqual([string replaceOccurrencesOfString:@"X" withString:@"Y" attributes:attributes options:0 range:NSMakeRange(0, 3)], (NSUInteger)1);
	XCTAssertEqualObjects([string string], @"aYb");
	XCTAssertEqualObjects([string attributesAtIndex:1 effectiveRange:NULL], attributes);
	XCTAssertEqual([[string attributesAtIndex:0 effectiveRange:NULL] count], (NSUInteger)0);
}

- (void)testReplaceOccurrencesWithAttributesReplacesEveryMatchInTheRange
{
	XCTExpectFailure(@"AIAttributedStringAdditions.m:83 has the same early exit as line 61, so abXdXf keeps its second X");
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"abXdXf"];
	NSUInteger count = [string replaceOccurrencesOfString:@"X" withString:@"Y" attributes:@{ NSForegroundColorAttributeName: [NSColor redColor] } options:0 range:NSMakeRange(0, 6)];
	XCTAssertEqual(count, (NSUInteger)2);
	XCTAssertEqualObjects([string string], @"abYdYf");
}

#pragma mark Colors on a background

- (void)testAdjustColorsMakesBlackReadableOnBlack
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"hi" attributes:@{ NSForegroundColorAttributeName: [NSColor blackColor] }];
	[string adjustColorsToShowOnBackground:[NSColor blackColor]];
	XCTAssertGreaterThan(Brightness([string attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]), 0.5);
}

- (void)testAdjustColorsLeavesBlackOnWhiteAlone
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"hi" attributes:@{ NSForegroundColorAttributeName: [NSColor blackColor] }];
	[string adjustColorsToShowOnBackground:[NSColor whiteColor]];
	XCTAssertEqualWithAccuracy(Brightness([string attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]), 0.0, AIFloatComparisonAccuracy);
}

- (void)testAdjustColorsTreatsMissingColorAsBlack
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"hi"];
	[string adjustColorsToShowOnBackground:[NSColor blackColor]];
	NSColor *color = [string attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
	XCTAssertNotNil(color, @"Unstyled text is black and black on black needs a color");
	XCTAssertGreaterThan(Brightness(color), 0.5);
}

- (void)testAdjustColorsRelativeToOriginalBackgroundDarkensWhiteOnWhite
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"hi" attributes:@{ NSForegroundColorAttributeName: [NSColor whiteColor] }];
	[string adjustColorsToShowOnBackgroundRelativeToOriginalBackground:[NSColor whiteColor]];
	XCTAssertLessThan(Brightness([string attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]), 1.0);
}

#pragma mark Link formatting and expansion

- (void)testAddFormattingForLinksColorsAndUnderlinesLinkedTextOnly
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"Adium rocks"];
	[string addAttribute:NSLinkAttributeName value:[NSURL URLWithString:@"http://www.adium.im/"] range:NSMakeRange(0, 5)];
	[string addFormattingForLinks];
	NSRange range = NSMakeRange(0, 0);
	XCTAssertNotNil([string attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:&range]);
	XCTAssertTrue(NSEqualRanges(range, NSMakeRange(0, 5)), @"Range was %@", NSStringFromRange(range));
	XCTAssertTrue([[string attribute:NSUnderlineStyleAttributeName atIndex:4 effectiveRange:NULL] boolValue]);
	XCTAssertNil([string attribute:NSForegroundColorAttributeName atIndex:6 effectiveRange:NULL]);
	XCTAssertNil([string attribute:NSUnderlineStyleAttributeName atIndex:6 effectiveRange:NULL]);
}

- (void)testStringByAddingFormattingForLinksLeavesTheReceiverUntouched
{
	NSAttributedString *original = [NSAttributedString attributedStringWithLinkLabel:@"Adium" linkDestination:@"http://www.adium.im/"];
	NSAttributedString *formatted = [original stringByAddingFormattingForLinks];
	XCTAssertNotNil([formatted attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL]);
	XCTAssertNil([original attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL]);
	XCTAssertNil([original attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]);
}

- (void)testConvertingLinksLeavesALinkWhoseTitleIsItsAddressAlone
{
	NSAttributedString *input = [NSAttributedString attributedStringWithLinkLabel:@"HTTP://www.adium.im/" linkDestination:@"http://www.adium.im/"];
	XCTAssertEqualObjects([[input attributedStringByConvertingLinksToStrings] string], @"HTTP://www.adium.im/");
	XCTAssertEqualObjects([[input attributedStringByConvertingLinksToURLStrings] string], @"HTTP://www.adium.im/");
}

- (void)testConvertingLinksRemovesTheLinkAttribute
{
	NSAttributedString *input = [NSAttributedString attributedStringWithString:@"Get Adium now" linkRange:NSMakeRange(4, 5) linkDestination:@"http://www.adium.im/"];
	NSAttributedString *result = [input attributedStringByConvertingLinksToStrings];
	__block BOOL foundLink = NO;
	[result enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, [result length]) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
		if (value) foundLink = YES;
	}];
	XCTAssertFalse(foundLink);
	XCTAssertNotNil([input attribute:NSLinkAttributeName atIndex:4 effectiveRange:NULL], @"The receiver keeps its link");
}

- (void)testConvertingLinksKeepsTheOtherAttributesOfTheLinkedText
{
	NSMutableAttributedString *input = [[NSMutableAttributedString alloc] initWithString:@"Get Adium"];
	NSFont *bold = [NSFont fontWithName:@"Helvetica-Bold" size:12];
	[input addAttributes:@{ NSLinkAttributeName: [NSURL URLWithString:@"http://www.adium.im/"], NSFontAttributeName: bold } range:NSMakeRange(4, 5)];
	NSAttributedString *result = [input attributedStringByConvertingLinksToStrings];
	XCTAssertEqualObjects([result string], @"Get Adium (http://www.adium.im/)");
	XCTAssertEqualObjects([result attribute:NSFontAttributeName atIndex:[result length] - 1 effectiveRange:NULL], bold);
	XCTAssertNil([result attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL]);
}

- (void)testConvertingLinksWithoutLinksReturnsAnEqualString
{
	NSAttributedString *input = [[NSAttributedString alloc] initWithString:@"No links here" attributes:@{ NSFontAttributeName: [NSFont fontWithName:@"Menlo-Regular" size:11] }];
	XCTAssertEqualObjects([input attributedStringByConvertingLinksToStrings], input);
	XCTAssertEqualObjects([input attributedStringByConvertingLinksToURLStrings], input);
}

- (void)testConvertingLinksAroundTextBeyondASCII
{
	//An e with a combining acute, an emoji outside the Basic Multilingual Plane and a right-to-left word.
	NSString *text = @"é \U0001F642 שלום!";
	NSMutableAttributedString *input = [[NSMutableAttributedString alloc] initWithString:text];
	NSURL *url = [NSURL URLWithString:@"http://example.com/"];
	[input addAttribute:NSLinkAttributeName value:url range:[text rangeOfString:@"שלום"]];
	[input addAttribute:NSLinkAttributeName value:url range:[text rangeOfString:@"é"]];
	NSAttributedString *result = [input attributedStringByConvertingLinksToStrings];
	XCTAssertEqualObjects([result string], @"é (http://example.com/) \U0001F642 שלום (http://example.com/)!");
}

#pragma mark Attachments

- (void)testConvertAttachmentsReplacesEachWithThePlaceholder
{
	NSMutableAttributedString *string = StringWithAttachments(@"a", [[NSTextAttachment alloc] init], @"b", [[NSTextAttachment alloc] init], @"c");
	XCTAssertTrue([string containsAttachments]);
	[string convertAttachmentsToStringsUsingPlaceholder:@"[x]"];
	XCTAssertEqualObjects([string string], @"a[x]b[x]c");
	XCTAssertFalse([string containsAttachments]);
}

- (void)testConvertAttachmentsUsesTheAttachmentsOwnString
{
	NSMutableAttributedString *string = StringWithAttachments(@"a", [[AITestNamedAttachment alloc] init], @"b", nil, @"");
	[string convertAttachmentsToStringsUsingPlaceholder:@"[x]"];
	XCTAssertEqualObjects([string string], @"a:)b");
}

- (void)testConvertAttachmentsAtTheStartAndTheEnd
{
	NSMutableAttributedString *string = StringWithAttachments(@"", [[NSTextAttachment alloc] init], @"mid", [[NSTextAttachment alloc] init], @"");
	[string convertAttachmentsToStringsUsingPlaceholder:@"[x]"];
	XCTAssertEqualObjects([string string], @"[x]mid[x]");
}

- (void)testConvertAttachmentsKeepsTheSurroundingAttributes
{
	NSMutableAttributedString *string = StringWithAttachments(@"a", [[NSTextAttachment alloc] init], @"b", nil, @"");
	NSFont *bold = [NSFont fontWithName:@"Helvetica-Bold" size:12];
	[string addAttribute:NSFontAttributeName value:bold range:NSMakeRange(0, 1)];
	[string addAttribute:NSFontAttributeName value:bold range:NSMakeRange(2, 1)];
	[string convertAttachmentsToStringsUsingPlaceholder:@"[x]"];
	XCTAssertEqualObjects([string string], @"a[x]b");
	XCTAssertEqualObjects([string attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL], bold);
	XCTAssertEqualObjects([string attribute:NSFontAttributeName atIndex:4 effectiveRange:NULL], bold);
	XCTAssertNil([string attribute:NSAttachmentAttributeName atIndex:1 effectiveRange:NULL]);
}

- (void)testAttributedStringByConvertingAttachmentsReturnsTheReceiverWhenThereAreNone
{
	NSAttributedString *plain = [[NSAttributedString alloc] initWithString:@"nothing attached"];
	XCTAssertTrue([plain attributedStringByConvertingAttachmentsToStrings] == plain);
}

- (void)testAttributedStringByConvertingAttachmentsUsesTheAttachmentsString
{
	NSAttributedString *input = StringWithAttachments(@"a", [[AITestNamedAttachment alloc] init], @"b", nil, @"");
	NSAttributedString *result = [input attributedStringByConvertingAttachmentsToStrings];
	XCTAssertEqualObjects([result string], @"a:)b");
	XCTAssertTrue([input containsAttachments], @"The receiver is left alone");
}

#pragma mark CSS

- (void)testCSSCapableAttributesExcludeLinksAndAttachments
{
	NSSet *capable = [NSAttributedString CSSCapableAttributesSet];
	XCTAssertTrue([capable containsObject:NSFontAttributeName]);
	XCTAssertTrue([capable containsObject:NSForegroundColorAttributeName]);
	XCTAssertTrue([capable containsObject:NSUnderlineStyleAttributeName]);
	XCTAssertFalse([capable containsObject:NSLinkAttributeName]);
	XCTAssertFalse([capable containsObject:NSAttachmentAttributeName]);
}

- (void)testCSSForAFontUsesTheFontsCSSRepresentation
{
	NSString *css = [NSAttributedString CSSStringForTextAttributes:@{ NSFontAttributeName: [NSFont fontWithName:@"Helvetica" size:12] }];
	XCTAssertEqualObjects(css, @"font: 12pt Helvetica;");
}

- (void)testCSSForUnderlineAndStrikethroughIsOneTextDecoration
{
	XCTAssertEqualObjects([NSAttributedString CSSStringForTextAttributes:@{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle) }], @"text-decoration: underline;");
	XCTAssertEqualObjects([NSAttributedString CSSStringForTextAttributes:@{ NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle) }], @"text-decoration: line-through;");
	NSDictionary *both = @{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle), NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle) };
	XCTAssertEqualObjects([NSAttributedString CSSStringForTextAttributes:both], @"text-decoration: line-through underline;");
}

- (void)testCSSPropertiesAreSortedAndSeparatedBySpaces
{
	NSString *css = [NSAttributedString CSSStringForTextAttributes:@{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle), NSFontAttributeName: [NSFont fontWithName:@"Helvetica" size:12], NSForegroundColorAttributeName: [NSColor blackColor] }];
	XCTAssertEqualObjects(css, @"color: #000000; font: 12pt Helvetica; text-decoration: underline;");
}

- (void)testCSSOmitsLinksAndAttachments
{
	NSString *css = [NSAttributedString CSSStringForTextAttributes:@{ NSLinkAttributeName: [NSURL URLWithString:@"http://www.adium.im/"], NSAttachmentAttributeName: [[NSTextAttachment alloc] init] }];
	XCTAssertEqualObjects(css, @"");
}

- (void)testCSSIsEmptyForNoAttributes
{
	XCTAssertEqualObjects([NSAttributedString CSSStringForTextAttributes:@{}], @"");
}

- (void)testCSSUnderlineStyleNoneProducesNoDecoration
{
	XCTExpectFailure(@"AIAttributedStringAdditions.m:374 looks only for the presence of the underline key, so a value of NSUnderlineStyleNone, which AppKit uses to switch an underline off, still produces text-decoration: underline");
	XCTAssertEqualObjects([NSAttributedString CSSStringForTextAttributes:@{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone) }], @"");
}

- (void)testCSSSuperscriptRaisesTheText
{
	XCTExpectFailure(@"AIAttributedStringAdditions.m:379 writes vertical-align: baseline for every superscript value, which is the CSS default and changes nothing; a positive superscript is vertical-align: super");
	XCTAssertEqualObjects([NSAttributedString CSSStringForTextAttributes:@{ NSSuperscriptAttributeName: @1 }], @"vertical-align: super;");
}

#pragma mark Data representation

- (NSAttributedString *)richSample
{
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:@"Zoë \U0001F642 שלום é" attributes:@{ NSFontAttributeName: [NSFont fontWithName:@"Menlo-Regular" size:11] }];
	[string addAttribute:NSForegroundColorAttributeName value:[NSColor colorWithSRGBRed:0.25 green:0.5 blue:0.75 alpha:1.0] range:NSMakeRange(0, 3)];
	[string addAttribute:NSLinkAttributeName value:[NSURL URLWithString:@"http://example.com/"] range:[[string string] rangeOfString:@"שלום"]];
	[string addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:NSMakeRange([string length] - 2, 2)];
	return string;
}

- (void)testDataRepresentationRoundTripsTextAndAttributes
{
	NSAttributedString *original = [self richSample];
	NSData *data = [original dataRepresentation];
	XCTAssertGreaterThan([data length], (NSUInteger)0);
	NSAttributedString *decoded = [NSAttributedString stringWithData:data];
	XCTAssertEqualObjects([decoded string], [original string]);
	XCTAssertEqualObjects(decoded, original);
}

- (void)testDataAttributedStringReadsTheSameArchive
{
	NSAttributedString *original = [self richSample];
	XCTAssertEqualObjects([[original dataRepresentation] attributedString], original);
}

- (void)testStringWithDataReturnsNilForNilAndEmptyData
{
	XCTAssertNil([NSAttributedString stringWithData:nil]);
	XCTAssertNil([NSAttributedString stringWithData:[NSData data]]);
}

- (void)testStringWithDataReturnsNilForBytesThatAreNoArchive
{
	const char junk[] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
	NSData *data = [NSData dataWithBytes:junk length:sizeof(junk)];
	NSAttributedString *result = nil;
	XCTAssertNoThrow(result = [NSAttributedString stringWithData:data]);
	XCTAssertNil(result);
}

- (void)testStringWithDataReadsRTF
{
	NSData *rtf = [@"{\\rtf1\\ansi Hello \\b bold\\b0 .}" dataUsingEncoding:NSASCIIStringEncoding];
	NSAttributedString *result = [NSAttributedString stringWithData:rtf];
	XCTAssertEqualObjects([result string], @"Hello bold.");
	NSFont *font = [result attribute:NSFontAttributeName atIndex:6 effectiveRange:NULL];
	XCTAssertTrue([[NSFontManager sharedFontManager] traitsOfFont:font] & NSBoldFontMask);
}

- (void)testStringWithDataReadsTheArchivesEarlierVersionsWrote
{
	NSAttributedString *original = [self richSample];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	NSData *legacy = [NSArchiver archivedDataWithRootObject:original];
#pragma clang diagnostic pop
	NSAttributedString *decoded = [NSAttributedString stringWithData:legacy];
	XCTAssertEqualObjects([decoded string], [original string]);
	XCTAssertEqualObjects([decoded attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL], [original attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL]);
	XCTAssertEqualObjects([decoded attribute:NSLinkAttributeName atIndex:6 effectiveRange:NULL], [original attribute:NSLinkAttributeName atIndex:6 effectiveRange:NULL]);
	XCTAssertEqualObjects([decoded attribute:NSUnderlineStyleAttributeName atIndex:[decoded length] - 1 effectiveRange:NULL], @(NSUnderlineStyleSingle));
	/* The old encoder stores colors in the calibrated RGB space, so the color comes back in that
	 * space and a conversion step away from the original; its sRGB components are what has to survive.
	 */
	NSColor *color = [[decoded attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	XCTAssertEqualWithAccuracy([color redComponent], 0.25, 0.01);
	XCTAssertEqualWithAccuracy([color greenComponent], 0.5, 0.01);
	XCTAssertEqualWithAccuracy([color blueComponent], 0.75, 0.01);
}

#pragma mark Heights

- (void)testHeightGrowsWithTheFontSize
{
	CGFloat small = [NSAttributedString stringHeightForAttributes:@{ NSFontAttributeName: [NSFont fontWithName:@"Helvetica" size:12] }];
	CGFloat large = [NSAttributedString stringHeightForAttributes:@{ NSFontAttributeName: [NSFont fontWithName:@"Helvetica" size:24] }];
	XCTAssertGreaterThan(small, 0.0);
	XCTAssertGreaterThan(large, small);
}

- (void)testHeightGrowsWhenTheTextWraps
{
	NSAttributedString *string = [[NSAttributedString alloc] initWithString:@"word word word word word word" attributes:@{ NSFontAttributeName: [NSFont fontWithName:@"Helvetica" size:12] }];
	CGFloat oneLine = [string heightWithWidth:10000];
	CGFloat wrapped = [string heightWithWidth:40];
	XCTAssertGreaterThan(wrapped, oneLine);
}

#pragma mark Construction

- (void)testStringWithStringWrapsPlainText
{
	NSAttributedString *string = [NSAttributedString stringWithString:@"plain"];
	XCTAssertEqualObjects([string string], @"plain");
	XCTAssertEqual([[string attributesAtIndex:0 effectiveRange:NULL] count], (NSUInteger)0);
}

- (void)testLinkLabelWithNilLabelOrNilLinkThrows
{
	XCTAssertThrows([NSAttributedString attributedStringWithLinkLabel:nil linkDestination:@"http://www.adium.im/"]);
	XCTAssertThrows([NSAttributedString attributedStringWithLinkLabel:@"Adium" linkDestination:nil]);
	XCTAssertThrows([NSAttributedString attributedStringWithString:@"Adium" linkRange:NSMakeRange(0, 5) linkDestination:nil]);
}

- (void)testLinkRangeOutsideTheStringThrows
{
	XCTAssertThrows([NSAttributedString attributedStringWithString:@"Adium" linkRange:NSMakeRange(3, 5) linkDestination:@"http://www.adium.im/"]);
}

@end
