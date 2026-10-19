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

#import <Adium/AIHTMLDecoder.h>
#import <Adium/AIXMLElement.h>
#import <Adium/AITextAttachmentExtension.h>
#import <AIUtilities/AIColorAdditions.h>
#import <AIUtilities/AITextAttributes.h>

@interface TestHTMLDecoder : XCTestCase
@end

/* Every flag of the long encoder, so that a test names only the ones it is about and the rest
 * read as off. closeStyleTagsOnFontChange is not here: the encoder documents it as ignored. */
typedef struct {
	BOOL headers, fontTags, colorTags, closeFontTags, styleTags, nonASCII, spaces;
	BOOL attachmentsAsText, onlyOutgoingImages, simpleTagsOnly, bodyBackground, allowJS;
} AIEncodeFlags;

static NSString *encodeWith(NSAttributedString *message, AIEncodeFlags f, NSString *imagesPath)
{
	return [AIHTMLDecoder encodeHTML:message
							 headers:f.headers
							fontTags:f.fontTags
				  includingColorTags:f.colorTags
					   closeFontTags:f.closeFontTags
						   styleTags:f.styleTags
		  closeStyleTagsOnFontChange:NO
					  encodeNonASCII:f.nonASCII
						encodeSpaces:f.spaces
						  imagesPath:imagesPath
				   attachmentsAsText:f.attachmentsAsText
		   onlyIncludeOutgoingImages:f.onlyOutgoingImages
					  simpleTagsOnly:f.simpleTagsOnly
					  bodyBackground:f.bodyBackground
				 allowJavascriptURLs:f.allowJS];
}

static NSString *encode(NSAttributedString *message, AIEncodeFlags f)
{
	return encodeWith(message, f, nil);
}

static NSAttributedString *decode(NSString *html)
{
	return [AIHTMLDecoder decodeHTML:html];
}

static NSFont *fontAt(NSAttributedString *s, NSUInteger index)
{
	return [s attribute:NSFontAttributeName atIndex:index effectiveRange:NULL];
}

static BOOL hasTrait(NSFont *font, NSFontTraitMask trait)
{
	return ([[NSFontManager sharedFontManager] traitsOfFont:font] & trait) != 0;
}

static NSString *hexAt(NSAttributedString *s, NSString *attributeName, NSUInteger index)
{
	return [[s attribute:attributeName atIndex:index effectiveRange:NULL] hexString];
}

static NSUInteger countOf(NSString *needle, NSString *haystack)
{
	return [[haystack componentsSeparatedByString:needle] count] - 1;
}

/* A 3 by 2 picture written as PNG, for the tests that need an image on disk. */
static NSImage *smallImage(void)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
																	pixelsWide:3
																	pixelsHigh:2
																 bitsPerSample:8
															   samplesPerPixel:4
																	  hasAlpha:YES
																	  isPlanar:NO
																colorSpaceName:NSCalibratedRGBColorSpace
																   bytesPerRow:0
																  bitsPerPixel:0];
	for (NSInteger x = 0; x < 3; x++) {
		for (NSInteger y = 0; y < 2; y++) {
			[rep setColor:[NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:1] atX:x y:y];
		}
	}
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(3, 2)];
	[image addRepresentation:rep];
	return image;
}

@implementation TestHTMLDecoder {
	NSString *scratchDirectory;
}

- (void)setUp
{
	[super setUp];
	scratchDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:scratchDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
	[[NSFileManager defaultManager] removeItemAtPath:scratchDirectory error:NULL];
	[super tearDown];
}

- (NSString *)writeSmallPNGNamed:(NSString *)name
{
	NSString *path = [scratchDirectory stringByAppendingPathComponent:name];
	NSBitmapImageRep *rep = (NSBitmapImageRep *)[[smallImage() representations] firstObject];
	NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
	XCTAssertTrue([png writeToFile:path atomically:YES]);
	return path;
}

#pragma mark Text that is not markup

- (void)testNilDecodesToAnEmptyAttributedString
{
	NSAttributedString *result = decode(nil);
	XCTAssertNotNil(result);
	XCTAssertEqual([result length], (NSUInteger)0);
}

- (void)testEmptyStringDecodesToEmpty
{
	XCTAssertEqual([decode(@"") length], (NSUInteger)0);
}

- (void)testPlainTextKeepsItsCharactersAndGetsTheDefaultFont
{
	NSAttributedString *result = decode(@"Hello, world");
	XCTAssertEqualObjects([result string], @"Hello, world");
	XCTAssertEqualObjects([fontAt(result, 0) familyName], @"Helvetica");
	XCTAssertEqualWithAccuracy([fontAt(result, 0) pointSize], 12.0, AIFloatComparisonAccuracy);
	XCTAssertFalse(hasTrait(fontAt(result, 0), NSBoldFontMask));
}

- (void)testStrayLessThanIsKeptAsText
{
	XCTAssertEqualObjects([decode(@"1 < 2") string], @"1 < 2");
	XCTAssertEqualObjects([decode(@"<3") string], @"<3");
}

- (void)testUnknownTagIsKeptLiterally
{
	XCTAssertEqualObjects([decode(@"<foo>x</foo>") string], @"<foo>x</foo>");
}

- (void)testStrayAmpersandIsKeptAsText
{
	XCTAssertEqualObjects([decode(@"AT&T a & b; c") string], @"AT&T a & b; c");
}

- (void)testUnterminatedTagAtEndOfInputIsDropped
{
	// HTML's tokenizer discards a tag that the input ends inside of.
	XCTAssertEqualObjects([decode(@"text <b") string], @"text ");
}

- (void)testEntityWithoutSemicolonAtEndOfInputDecodes
{
	XCTAssertEqualObjects([decode(@"a&amp") string], @"a&");
}

#pragma mark Inline tags

- (void)testBoldTagSetsTheBoldTrait
{
	NSAttributedString *result = decode(@"<b>bold</b> plain");
	XCTAssertEqualObjects([result string], @"bold plain");
	XCTAssertTrue(hasTrait(fontAt(result, 0), NSBoldFontMask));
	XCTAssertFalse(hasTrait(fontAt(result, 5), NSBoldFontMask));
}

- (void)testStrongIsBold
{
	XCTAssertTrue(hasTrait(fontAt(decode(@"<strong>x</strong>"), 0), NSBoldFontMask));
}

- (void)testItalicAndEmSetTheItalicTrait
{
	XCTAssertTrue(hasTrait(fontAt(decode(@"<i>x</i>"), 0), NSItalicFontMask));
	XCTAssertTrue(hasTrait(fontAt(decode(@"<em>x</em>"), 0), NSItalicFontMask));
	XCTAssertFalse(hasTrait(fontAt(decode(@"<i>x</i>y"), 1), NSItalicFontMask));
}

- (void)testUnderlineTagSetsTheUnderlineAttribute
{
	NSAttributedString *result = decode(@"<u>u</u>n");
	XCTAssertNotEqual([[result attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] integerValue], (NSInteger)0);
	XCTAssertEqual([[result attribute:NSUnderlineStyleAttributeName atIndex:1 effectiveRange:NULL] integerValue], (NSInteger)0);
}

- (void)testStrikethroughTagSetsTheStrikethroughAttribute
{
	NSAttributedString *result = decode(@"<s>s</s>n");
	XCTAssertNotEqual([[result attribute:NSStrikethroughStyleAttributeName atIndex:0 effectiveRange:NULL] integerValue], (NSInteger)0);
	XCTAssertEqual([[result attribute:NSStrikethroughStyleAttributeName atIndex:1 effectiveRange:NULL] integerValue], (NSInteger)0);
}

- (void)testNestedBoldAndItalicCombine
{
	NSAttributedString *result = decode(@"<b>a<i>b</i>c</b>");
	XCTAssertTrue(hasTrait(fontAt(result, 1), NSBoldFontMask));
	XCTAssertTrue(hasTrait(fontAt(result, 1), NSItalicFontMask));
	XCTAssertTrue(hasTrait(fontAt(result, 2), NSBoldFontMask));
	XCTAssertFalse(hasTrait(fontAt(result, 2), NSItalicFontMask));
}

- (void)testTagNamesAreCaseInsensitive
{
	XCTAssertTrue(hasTrait(fontAt(decode(@"<B>x</B>"), 0), NSBoldFontMask));
	XCTAssertTrue(hasTrait(fontAt(decode(@"<Strong>x</STRONG>"), 0), NSBoldFontMask));
	XCTAssertEqualObjects([decode(@"a<BR>b") string], @"a\nb");
}

- (void)testUnclosedBoldRunsToTheEnd
{
	NSAttributedString *result = decode(@"a<b>bc");
	XCTAssertFalse(hasTrait(fontAt(result, 0), NSBoldFontMask));
	XCTAssertTrue(hasTrait(fontAt(result, 2), NSBoldFontMask));
}

- (void)testClosingTagWithoutOpenerIsHarmless
{
	NSAttributedString *result = decode(@"a</b></font></span></a>b");
	XCTAssertEqualObjects([result string], @"ab");
	XCTAssertFalse(hasTrait(fontAt(result, 1), NSBoldFontMask));
	XCTAssertNil([result attribute:NSLinkAttributeName atIndex:1 effectiveRange:NULL]);
}

- (void)testSuperscriptAndSubscriptShiftTheBaseline
{
	NSNumber *up = [decode(@"<sup>2</sup>") attribute:NSBaselineOffsetAttributeName atIndex:0 effectiveRange:NULL];
	NSNumber *down = [decode(@"<sub>2</sub>") attribute:NSBaselineOffsetAttributeName atIndex:0 effectiveRange:NULL];
	XCTAssertGreaterThan([up doubleValue], 0.0);
	XCTAssertLessThan([down doubleValue], 0.0);
}

#pragma mark Line breaks and block tags

- (void)testBRBecomesANewline
{
	XCTAssertEqualObjects([decode(@"a<br>b") string], @"a\nb");
}

- (void)testSelfClosingBRVariantsAllBreakTheLine
{
	XCTAssertEqualObjects([decode(@"a<br/>b") string], @"a\nb");
	XCTAssertEqualObjects([decode(@"a<br />b") string], @"a\nb");
	XCTAssertEqualObjects([decode(@"a</br>b") string], @"a\nb");
}

- (void)testNewlineFollowingBRIsSwallowed
{
	XCTAssertEqualObjects([decode(@"a<br>\nb") string], @"a\nb");
	XCTAssertEqualObjects([decode(@"a<br>\r\nb") string], @"a\nb");
}

- (void)testLiteralNewlinesInTextAreKept
{
	XCTAssertEqualObjects([decode(@"a\nb\n\nc") string], @"a\nb\n\nc");
}

- (void)testHRBecomesARuleAndEncodesBackAsHR
{
	NSAttributedString *result = decode(@"a<hr>b");
	XCTAssertTrue([[result string] hasPrefix:@"a\n"]);
	XCTAssertTrue([[result string] hasSuffix:@"\nb"]);
	XCTAssertEqualObjects(encode(result, (AIEncodeFlags){ .attachmentsAsText = YES }), @"a<HR>b");
}

- (void)testListItemsBecomeBullets
{
	XCTAssertEqualObjects([decode(@"<ul><li>one</li><li>two</li></ul>") string], @"\u2022 one\u2022 two");
}

- (void)testStructuralTagsAreIgnored
{
	XCTAssertEqualObjects([decode(@"<html><head><meta charset=\"utf-8\"></head><body><p>x</p></body></html>") string], @"x");
	XCTAssertEqualObjects([decode(@"<HTML><BODY>x</BODY></HTML>") string], @"x");
}

- (void)testClosingHTMLTagEndsTheDocument
{
	XCTAssertEqualObjects([decode(@"a</html>b") string], @"a");
}

- (void)testPreTagIsAcceptedWithoutLeakingAsText
{
	XCTAssertEqualObjects([decode(@"<pre>x</pre>") string], @"x");
}

- (void)testDivDirSetsTheParagraphDirection
{
	NSParagraphStyle *rtl = [decode(@"<div dir=\"rtl\">x</div>") attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
	NSParagraphStyle *ltr = [decode(@"<div dir=\"ltr\">x</div>") attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
	XCTAssertEqual([rtl baseWritingDirection], NSWritingDirectionRightToLeft);
	XCTAssertEqual([ltr baseWritingDirection], NSWritingDirectionLeftToRight);
}

#pragma mark Entities

- (void)testTheFiveXMLEntitiesAndNbspDecode
{
	XCTAssertEqualObjects([decode(@"&lt;&gt;&amp;&quot;&apos;&nbsp;") string], @"<>&\"' ");
}

- (void)testNamedEntitiesAreCaseInsensitive
{
	XCTAssertEqualObjects([decode(@"&LT;&Gt;&AMP;") string], @"<>&");
}

- (void)testUnknownNamedEntityIsKeptLiterally
{
	XCTAssertEqualObjects([decode(@"&bogus; &;") string], @"&bogus; &;");
}

- (void)testEntityInsideATagKeepsTheTagsAttributes
{
	NSAttributedString *result = decode(@"<b>&amp;</b>");
	XCTAssertEqualObjects([result string], @"&");
	XCTAssertTrue(hasTrait(fontAt(result, 0), NSBoldFontMask));
}

- (void)testDecimalNumericEntityDecodesToItsCharacter
{
	XCTAssertEqualObjects([decode(@"&#65;&#8364;") string], @"A\u20ac");
}

- (void)testHexNumericEntityDecodesToItsCharacter
{
	XCTAssertEqualObjects([decode(@"&#x41;&#x20ac;") string], @"A\u20ac");
}

- (void)testHexNumericEntityAcceptsAnUppercaseX
{
	XCTAssertEqualObjects([decode(@"a&#X42;c") string], @"aBc");
}

- (void)testAstralNumericEntityDecodesToASurrogatePair
{
	XCTAssertEqualObjects([decode(@"&#x1F600;") string], @"\U0001F600");
}

#pragma mark parseArguments

- (void)testParseArgumentsHandlesDoubleSingleAndNoQuotes
{
	NSDictionary *args = [AIHTMLDecoder parseArguments:@"src=\"a b\" alt='c d' width=10"];
	XCTAssertEqualObjects(args, (@{ @"src": @"a b", @"alt": @"c d", @"width": @"10" }));
}

- (void)testParseArgumentsLowercasesKeys
{
	XCTAssertEqualObjects([AIHTMLDecoder parseArguments:@"SRC=x Alt=y"], (@{ @"src": @"x", @"alt": @"y" }));
}

- (void)testParseArgumentsOfEmptyStringIsEmpty
{
	XCTAssertEqualObjects([AIHTMLDecoder parseArguments:@""], @{});
}

- (void)testParseArgumentsATrailingValuelessAttributeDoesNotDisturbItsNeighbour
{
	XCTAssertEqualObjects([[AIHTMLDecoder parseArguments:@"src=\"a\" ismap"] objectForKey:@"src"], @"a");
}

- (void)testParseArgumentsSkipsALeadingValuelessAttribute
{
	XCTAssertEqualObjects([AIHTMLDecoder parseArguments:@"ismap src=\"a\""], @{ @"src": @"a" });
}

- (void)testParseArgumentsAcceptsAnyWhitespaceBetweenAttributes
{
	XCTAssertEqualObjects([AIHTMLDecoder parseArguments:@"a=1\tb=2\nc=3"], (@{ @"a": @"1", @"b": @"2", @"c": @"3" }));
}

- (void)testClassMethodParseArgumentsMatchesInstance
{
	XCTAssertEqualObjects([AIHTMLDecoder parseArguments:@"a=1 b='2'"], [[AIHTMLDecoder decoder] parseArguments:@"a=1 b='2'"]);
}

#pragma mark Font tags

- (void)testFontFaceSetsTheFamily
{
	XCTAssertEqualObjects([fontAt(decode(@"<font face=\"Menlo\">m</font>"), 0) familyName], @"Menlo");
	XCTAssertEqualObjects([fontAt(decode(@"<font face=Menlo>m</font>h"), 1) familyName], @"Helvetica");
}

- (void)testFontSizesOneToSevenMapToTheHTMLPointSizes
{
	int expected[] = { 9, 10, 12, 14, 18, 24, 48 };
	for (int size = 1; size <= 7; size++) {
		NSString *html = [NSString stringWithFormat:@"<font size=%d>x</font>", size];
		XCTAssertEqualWithAccuracy([fontAt(decode(html), 0) pointSize], (CGFloat)expected[size - 1], AIFloatComparisonAccuracy, @"size=%d", size);
	}
}

- (void)testFontSizeBeyondTheScaleFallsBackToTwelve
{
	XCTAssertEqualWithAccuracy([fontAt(decode(@"<font size=9>x</font>"), 0) pointSize], 12.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy([fontAt(decode(@"<font size=99>x</font>"), 0) pointSize], 12.0, AIFloatComparisonAccuracy);
}

- (void)testABSZWinsOverSize
{
	XCTAssertEqualWithAccuracy([fontAt(decode(@"<font absz=20 size=1>x</font>"), 0) pointSize], 20.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy([fontAt(decode(@"<font size=1 ABSZ=20>x</font>"), 0) pointSize], 20.0, AIFloatComparisonAccuracy);
}

- (void)testFontSizeZeroDoesNotCrash
{
	XCTAssertEqualObjects([decode(@"<font size=0>z</font><font size=\"abc\">q</font>") string], @"zq");
}

- (void)testRelativeFontSizeIsRelativeToTheDefaultThree
{
	XCTAssertEqualWithAccuracy([fontAt(decode(@"<font size=\"+1\">x</font>"), 0) pointSize], 14.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy([fontAt(decode(@"<font size=\"-1\">x</font>"), 0) pointSize], 10.0, AIFloatComparisonAccuracy);
}

- (void)testClosingFontRestoresThePreviousFontAndColour
{
	NSAttributedString *result = decode(@"<font face=\"Menlo\" color=\"#ff0000\" absz=20>a</font>b");
	XCTAssertEqualObjects([fontAt(result, 1) familyName], @"Helvetica");
	XCTAssertEqualWithAccuracy([fontAt(result, 1) pointSize], 12.0, AIFloatComparisonAccuracy);
	XCTAssertNil([result attribute:NSForegroundColorAttributeName atIndex:1 effectiveRange:NULL]);
}

- (void)testNestedFontTagsRestoreInOrder
{
	NSAttributedString *result = decode(@"<font size=5><font size=1>a</font>b</font>c");
	XCTAssertEqualWithAccuracy([fontAt(result, 0) pointSize], 9.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy([fontAt(result, 1) pointSize], 18.0, AIFloatComparisonAccuracy);
	XCTAssertEqualWithAccuracy([fontAt(result, 2) pointSize], 12.0, AIFloatComparisonAccuracy);
}

#pragma mark Colours

- (void)testFontColourDecodesAndEncodesAsTheSameHex
{
	NSAttributedString *result = decode(@"<font color=\"#ff0000\">red</font>");
	XCTAssertEqualObjects(hexAt(result, NSForegroundColorAttributeName, 0), @"ff0000");
	NSString *html = encode(result, (AIEncodeFlags){ .colorTags = YES, .attachmentsAsText = YES });
	XCTAssertTrue([html containsString:@"COLOR=\"#ff0000\""], @"%@", html);
}

- (void)testShortHexColourExpands
{
	XCTAssertEqualObjects(hexAt(decode(@"<font color=\"#f00\">x</font>"), NSForegroundColorAttributeName, 0), @"ff0000");
	XCTAssertEqualObjects(hexAt(decode(@"<font color=\"#0f0\">x</font>"), NSForegroundColorAttributeName, 0), @"00ff00");
}

- (void)testHTMLColourNamesDecode
{
	XCTAssertEqualObjects(hexAt(decode(@"<font color=\"red\">x</font>"), NSForegroundColorAttributeName, 0), @"ff0000");
	XCTAssertEqualObjects(hexAt(decode(@"<font color=\"Blue\">x</font>"), NSForegroundColorAttributeName, 0), @"0000ff");
}

- (void)testUnrecognisedColourFallsBackToBlack
{
	XCTAssertEqualObjects(hexAt(decode(@"<font color=\"nonsense\">x</font>"), NSForegroundColorAttributeName, 0), @"000000");
}

- (void)testFontBackSetsTheTextBackgroundOnlyWhereItApplies
{
	NSAttributedString *result = decode(@"a<font back=\"#00ff00\">b</font>c");
	XCTAssertNil([result attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:NULL]);
	XCTAssertEqualObjects(hexAt(result, NSBackgroundColorAttributeName, 1), @"00ff00");
	XCTAssertNil([result attribute:NSBackgroundColorAttributeName atIndex:2 effectiveRange:NULL]);
	NSString *html = encode(result, (AIEncodeFlags){ .colorTags = YES, .attachmentsAsText = YES });
	XCTAssertTrue([html containsString:@"BACK=\"#00ff00\""], @"%@", html);
}

- (void)testConstantBackgroundColourIsPromotedToTheBodyColour
{
	NSAttributedString *result = decode(@"<font back=\"#00ff00\">all of it</font>");
	XCTAssertNil([result attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:NULL]);
	XCTAssertEqualObjects(hexAt(result, AIBodyColorAttributeName, 0), @"00ff00");
}

- (void)testBodyBgcolorBecomesTheBodyColourAndComesBackWithHeaders
{
	NSAttributedString *result = decode(@"<body bgcolor=\"#0000ff\">x</body>");
	XCTAssertEqualObjects(hexAt(result, AIBodyColorAttributeName, 0), @"0000ff");
	XCTAssertEqualObjects(encode(result, (AIEncodeFlags){ .headers = YES, .attachmentsAsText = YES }),
						  @"<HTML><BODY BGCOLOR=\"#0000ff\">x</BODY></HTML>");
}

- (void)testBodyBackgroundOptionReturnsOnlyTheHex
{
	XCTAssertEqualObjects(encode(decode(@"<body bgcolor=\"#0000ff\">x</body>"), (AIEncodeFlags){ .bodyBackground = YES, .attachmentsAsText = YES }), @"0000ff");
	XCTAssertEqualObjects(encode(decode(@"x"), (AIEncodeFlags){ .bodyBackground = YES, .attachmentsAsText = YES }), @"");
}

- (void)testColourTagsCanBeLeftOut
{
	NSString *html = encode(decode(@"<font color=\"#ff0000\">a</font><font back=\"#00ff00\">b</font>"), (AIEncodeFlags){ .attachmentsAsText = YES });
	XCTAssertEqualObjects(html, @"ab");
}

#pragma mark Span styles

- (void)testSpanFontFamilyAndPixelSize
{
	NSFont *font = fontAt(decode(@"<span style=\"font-family: Menlo; font-size: 14px\">x</span>"), 0);
	XCTAssertEqualObjects([font familyName], @"Menlo");
	XCTAssertEqualWithAccuracy([font pointSize], 14.0, AIFloatComparisonAccuracy);
}

- (void)testSpanKeywordFontSizesFollowTheHTMLScale
{
	NSDictionary *expected = @{ @"xx-small": @9, @"x-small": @10, @"small": @12, @"medium": @14, @"large": @18, @"x-large": @24 };
	for (NSString *keyword in expected) {
		NSString *html = [NSString stringWithFormat:@"<span style=\"font-size: %@\">x</span>", keyword];
		XCTAssertEqualWithAccuracy([fontAt(decode(html), 0) pointSize], [expected[keyword] doubleValue], AIFloatComparisonAccuracy, @"%@", keyword);
	}
}

- (void)testSpanFontWeightByKeywordAndNumber
{
	XCTAssertTrue(hasTrait(fontAt(decode(@"<span style=\"font-weight: bold\">x</span>"), 0), NSBoldFontMask));
	XCTAssertTrue(hasTrait(fontAt(decode(@"<span style=\"font-weight: 700\">x</span>"), 0), NSBoldFontMask));
	XCTAssertFalse(hasTrait(fontAt(decode(@"<span style=\"font-weight: 400\">x</span>"), 0), NSBoldFontMask));
	XCTAssertFalse(hasTrait(fontAt(decode(@"<b><span style=\"font-weight: normal\">x</span></b>"), 0), NSBoldFontMask));
}

- (void)testSpanFontStyleItalic
{
	XCTAssertTrue(hasTrait(fontAt(decode(@"<span style=\"font-style: italic\">x</span>"), 0), NSItalicFontMask));
	XCTAssertTrue(hasTrait(fontAt(decode(@"<span style=\"font-style: oblique\">x</span>"), 0), NSItalicFontMask));
	XCTAssertFalse(hasTrait(fontAt(decode(@"<i><span style=\"font-style: normal\">x</span></i>"), 0), NSItalicFontMask));
}

- (void)testSpanTextDecoration
{
	NSAttributedString *underline = decode(@"<span style=\"text-decoration: underline\">x</span>");
	NSAttributedString *lineThrough = decode(@"<span style=\"text-decoration: line-through\">x</span>");
	NSAttributedString *none = decode(@"<u><s><span style=\"text-decoration: none\">x</span></s></u>");
	XCTAssertNotEqual([[underline attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] integerValue], (NSInteger)0);
	XCTAssertNotEqual([[lineThrough attribute:NSStrikethroughStyleAttributeName atIndex:0 effectiveRange:NULL] integerValue], (NSInteger)0);
	XCTAssertEqual([[none attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL] integerValue], (NSInteger)0);
	XCTAssertEqual([[none attribute:NSStrikethroughStyleAttributeName atIndex:0 effectiveRange:NULL] integerValue], (NSInteger)0);
}

- (void)testSpanColourIsNotConfusedWithBackgroundColour
{
	NSAttributedString *result = decode(@"<span style=\"background-color: #00ff00; color: #ff0000\">x</span>");
	XCTAssertEqualObjects(hexAt(result, NSForegroundColorAttributeName, 0), @"ff0000");
	NSAttributedString *backgroundOnly = decode(@"<span style=\"background-color: #00ff00\">x</span>");
	XCTAssertNil([backgroundOnly attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL]);
}

- (void)testClosingSpanRestoresWhatItChanged
{
	NSAttributedString *result = decode(@"<span style=\"font-weight: bold; color: #ff0000; font-family: Menlo\">a</span>b");
	XCTAssertFalse(hasTrait(fontAt(result, 1), NSBoldFontMask));
	XCTAssertEqualObjects([fontAt(result, 1) familyName], @"Helvetica");
	XCTAssertNil([result attribute:NSForegroundColorAttributeName atIndex:1 effectiveRange:NULL]);
}

#pragma mark Links

- (void)testAnchorHrefBecomesAnNSURL
{
	NSAttributedString *result = decode(@"see <a href=\"http://example.com/\">here</a>");
	id link = [result attribute:NSLinkAttributeName atIndex:4 effectiveRange:NULL];
	XCTAssertTrue([link isKindOfClass:[NSURL class]]);
	XCTAssertEqualObjects([link absoluteString], @"http://example.com/");
	XCTAssertNil([result attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL]);
}

- (void)testEntitiesInHrefAreUnescaped
{
	NSURL *link = [decode(@"<a href=\"http://example.com/?a=1&amp;b=2\">x</a>") attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL];
	XCTAssertEqualObjects([link absoluteString], @"http://example.com/?a=1&b=2");
}

- (void)testClosingAnchorEndsTheLink
{
	NSAttributedString *result = decode(@"<a href=\"http://example.com/\">a</a>b");
	XCTAssertNotNil([result attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL]);
	XCTAssertNil([result attribute:NSLinkAttributeName atIndex:1 effectiveRange:NULL]);
}

- (void)testRelativeHrefResolvesAgainstTheDecodersBaseURL
{
	AIHTMLDecoder *decoder = [AIHTMLDecoder decoder];
	decoder.baseURL = @"http://example.com/dir/";
	NSURL *link = [[decoder decodeHTML:@"<a href=\"page.html\">x</a>"] attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL];
	XCTAssertEqualObjects([link absoluteString], @"http://example.com/dir/page.html");
}

- (void)testLinkIsEncodedWithHrefAndTitle
{
	NSString *html = encode(decode(@"see <a href=\"http://example.com/\">here</a>"), (AIEncodeFlags){ .attachmentsAsText = YES });
	XCTAssertEqualObjects(html, @"see <a href=\"http://example.com/\" title=\"http://example.com/\">here</a>");
}

- (void)testSimpleTagsOmitTheLinkTitle
{
	NSString *html = encode(decode(@"<a href=\"http://example.com/\">x</a>"), (AIEncodeFlags){ .simpleTagsOnly = YES, .attachmentsAsText = YES });
	XCTAssertEqualObjects(html, @"<a href=\"http://example.com/\">x</a>");
}

- (void)testAmpersandInLinkIsEscapedOnOutputAndRoundTrips
{
	NSAttributedString *original = decode(@"<a href=\"http://example.com/?a=1&amp;b=2\">x</a>");
	NSString *html = encode(original, (AIEncodeFlags){ .attachmentsAsText = YES });
	XCTAssertTrue([html containsString:@"href=\"http://example.com/?a=1&amp;b=2\""], @"%@", html);
	XCTAssertEqualObjects([[decode(html) attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL] absoluteString], @"http://example.com/?a=1&b=2");
}

- (void)testElementClassAttributeBecomesTheLinkClass
{
	NSAttributedString *linked = [[NSAttributedString alloc] initWithString:@"x" attributes:@{
		NSLinkAttributeName: [NSURL URLWithString:@"http://example.com/"],
		AIElementClassAttributeName: @"mention",
		NSFontAttributeName: [NSFont fontWithName:@"Helvetica" size:12]
	}];
	XCTAssertEqualObjects(encode(linked, (AIEncodeFlags){ .attachmentsAsText = YES }),
						  @"<a href=\"http://example.com/\" title=\"http://example.com/\" class=\"mention\">x</a>");
}

- (void)testJavascriptLinkIsRefusedUnlessAllowed
{
	NSAttributedString *bad = decode(@"<a href=\"javascript:alert(1)\">bad</a>");
	XCTAssertEqualObjects(encode(bad, (AIEncodeFlags){ .attachmentsAsText = YES }), @"bad");
	XCTAssertEqualObjects(encode(bad, (AIEncodeFlags){ .attachmentsAsText = YES, .allowJS = YES }),
						  @"<a href=\"javascript:alert(1)\" title=\"javascript:alert(1)\">bad</a>");
}

- (void)testJavascriptSchemeIsRefusedRegardlessOfCase
{
	NSString *html = encode(decode(@"<a href=\"JavaScript:alert(1)\">bad</a>"), (AIEncodeFlags){ .attachmentsAsText = YES });
	XCTAssertEqualObjects(html, @"bad");
}

- (void)testLinkMentioningJavascriptLaterInTheURLIsAllowed
{
	NSString *html = encode(decode(@"<a href=\"http://example.com/javascript/\">x</a>"), (AIEncodeFlags){ .attachmentsAsText = YES });
	XCTAssertTrue([html hasPrefix:@"<a href=\"http://example.com/javascript/\""], @"%@", html);
}

- (void)testAIMSubprofileLinksKeepTheirPercentN
{
	// %n is no percent escape NSURL accepts, so it is kept as %25n and written back as %n only when asked.
	NSAttributedString *linked = decode(@"<a href=\"aim:goim?screenname=%n\">x</a>");
	XCTAssertEqualObjects([[linked attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL] absoluteString], @"aim:goim?screenname=%25n");
	AIHTMLDecoder *decoder = [AIHTMLDecoder decoder];
	XCTAssertTrue([[decoder encodeHTML:linked imagesPath:nil] containsString:@"href=\"aim:goim?screenname=%25n\""]);
	decoder.allowAIMsubprofileLinks = YES;
	XCTAssertTrue([[decoder encodeHTML:linked imagesPath:nil] containsString:@"href=\"aim:goim?screenname=%n\""]);
}

- (void)testQuotedAttributeValueMayContainAGreaterThan
{
	NSAttributedString *result = decode(@"<a href=\"http://example.com/\" title=\"a>b\">t</a>");
	XCTAssertEqualObjects([result string], @"t");
}

- (void)testNewlineAfterTheTagNameStillOpensTheTag
{
	NSAttributedString *result = decode(@"<a\nhref=\"http://example.com/\">t</a>");
	XCTAssertEqualObjects([result string], @"t");
	XCTAssertNotNil([result attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL]);
}

#pragma mark Images

- (void)testImgWithAltDecodesToAnAttachmentCarryingTheAlt
{
	NSAttributedString *result = decode(@"pic:<img src=\"/nonexistent/x.png\" alt=\"alt text\" class=\"emoticon\">end");
	XCTAssertEqual([result length], (NSUInteger)8);
	id attachment = [result attribute:NSAttachmentAttributeName atIndex:4 effectiveRange:NULL];
	XCTAssertTrue([attachment isKindOfClass:[AITextAttachmentExtension class]]);
	XCTAssertEqualObjects([attachment string], @"alt text");
	XCTAssertTrue([attachment hasAlternate]);
	XCTAssertEqualObjects([attachment imageClass], @"emoticon");
	XCTAssertEqualObjects([attachment path], @"/nonexistent/x.png");
}

- (void)testAttachmentsAsTextWritesTheAlt
{
	NSAttributedString *result = decode(@"pic:<img src=\"/nonexistent/x.png\" alt=\"alt text\">end");
	XCTAssertEqualObjects(encode(result, (AIEncodeFlags){ .attachmentsAsText = YES }), @"pic:alt textend");
}

- (void)testAttachmentEncodesAsAnImgWithFileURLAltAndClass
{
	NSAttributedString *result = decode(@"pic:<img src=\"/nonexistent/x.png\" alt=\"alt text\" class=\"emoticon\">end");
	XCTAssertEqualObjects(encode(result, (AIEncodeFlags){ 0 }),
						  @"pic:<img class=\"emoticon\" src=\"file:///nonexistent/x.png\" alt=\"alt text\">end");
}

- (void)testImgOfARealFileCarriesItsSize
{
	NSString *path = [self writeSmallPNGNamed:@"three-by-two.png"];
	NSString *html = encode(decode([NSString stringWithFormat:@"<img src=\"%@\" alt=\"pic\">", path]), (AIEncodeFlags){ 0 });
	NSString *expected = [NSString stringWithFormat:@"<img src=\"%@\" alt=\"pic\" width=\"3\" height=\"2\">", [[NSURL fileURLWithPath:path] absoluteString]];
	XCTAssertEqualObjects(html, expected);
}

- (void)testOnlyOutgoingImagesTurnsATextOnlyAttachmentIntoItsString
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	[attachment setImage:smallImage()];
	[attachment setString:@"smiley"];
	[attachment setShouldAlwaysSendAsText:YES];
	NSAttributedString *message = [NSAttributedString attributedStringWithAttachment:attachment];

	XCTAssertEqualObjects(encodeWith(message, (AIEncodeFlags){ .onlyOutgoingImages = YES }, scratchDirectory), @"smiley");
	NSString *asImage = encodeWith(message, (AIEncodeFlags){ 0 }, scratchDirectory);
	XCTAssertTrue([asImage hasPrefix:@"<img src=\"file://"], @"%@", asImage);
	XCTAssertTrue([asImage containsString:@"alt=\"smiley\""], @"%@", asImage);
}

- (void)testImgWithARemoteSourceBecomesALinkToIt
{
	NSAttributedString *result = decode(@"<img src=\"http://example.com/a.png\">");
	XCTAssertEqualObjects([result string], @"http://example.com/a.png");
	XCTAssertEqualObjects([[result attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL] absoluteString], @"http://example.com/a.png");
}

#pragma mark Default attributes

- (void)testDefaultAttributesApplyToPlainTextAndUnderTags
{
	NSColor *blue = [NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:1];
	NSAttributedString *result = [AIHTMLDecoder decodeHTML:@"p<b>b</b>" withDefaultAttributes:@{
		NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:14],
		NSForegroundColorAttributeName: blue
	}];
	XCTAssertEqualObjects([fontAt(result, 0) familyName], @"Menlo");
	XCTAssertEqualWithAccuracy([fontAt(result, 0) pointSize], 14.0, AIFloatComparisonAccuracy);
	XCTAssertFalse(hasTrait(fontAt(result, 0), NSBoldFontMask));
	XCTAssertEqualObjects([fontAt(result, 1) familyName], @"Menlo");
	XCTAssertTrue(hasTrait(fontAt(result, 1), NSBoldFontMask));
	XCTAssertEqualObjects([result attribute:NSForegroundColorAttributeName atIndex:1 effectiveRange:NULL], blue);
}

#pragma mark Encoding options

- (void)testPlainTextEncodesUnchangedWithEverythingOff
{
	XCTAssertEqualObjects(encode(decode(@"Hello, world"), (AIEncodeFlags){ 0 }), @"Hello, world");
}

- (void)testSpecialCharactersAreEscapedOnOutput
{
	XCTAssertEqualObjects(encode(decode(@"a &lt;b&gt; &amp; \"c\" 'd'"), (AIEncodeFlags){ 0 }), @"a &lt;b&gt; &amp; \"c\" 'd'");
}

- (void)testHeadersWrapTheOutput
{
	XCTAssertEqualObjects(encode(decode(@"x"), (AIEncodeFlags){ .headers = YES }), @"<HTML>x</HTML>");
}

- (void)testStyleTagsEmitBoldItalicUnderlineAndStrike
{
	NSAttributedString *styled = decode(@"<b>b</b> <i>i</i> <u>u</u> <s>s</s>");
	XCTAssertEqualObjects(encode(styled, (AIEncodeFlags){ .styleTags = YES }), @"<B>b</B> <I>i</I> <U>u</U> <S>s</S>");
	XCTAssertEqualObjects(encode(styled, (AIEncodeFlags){ 0 }), @"b i u s");
}

- (void)testAdjacentStyleChangesStillDecodeBackFaithfully
{
	/* The encoder closes and opens the four styles in a fixed order, so where one ends exactly where
	 * another begins the tags come out interleaved. What is promised is that reading it back gives the
	 * same text with the same styles, not the order of the tags. */
	NSAttributedString *styled = decode(@"<b>b</b><i>i</i><u>u</u><s>s</s>");
	NSAttributedString *back = decode(encode(styled, (AIEncodeFlags){ .styleTags = YES }));
	XCTAssertTrue([back isEqualToAttributedString:styled]);
}

- (void)testStyleTagsLeftOpenAtTheEndAreClosed
{
	XCTAssertEqualObjects(encode(decode(@"<b><i>x"), (AIEncodeFlags){ .styleTags = YES }), @"<I><B>x</I></B>");
}

- (void)testFontTagsAreOmittedForTheDefaultFont
{
	XCTAssertEqualObjects(encode(decode(@"<font face=\"Helvetica\" absz=12>x</font>"), (AIEncodeFlags){ .fontTags = YES }), @"x");
}

- (void)testFontTagsCarryFaceABSZAndSize
{
	NSString *html = encode(decode(@"<font face=\"Menlo\" absz=18>x</font>"), (AIEncodeFlags){ .fontTags = YES });
	XCTAssertEqualObjects(html, @"<FONT FACE=\"Menlo\" ABSZ=18 SIZE=5>x");
}

- (void)testPointSizesMapToTheSevenHTMLSizes
{
	NSDictionary *expected = @{ @9: @1, @10: @2, @12: @3, @14: @4, @18: @5, @24: @6, @25: @7, @72: @7 };
	for (NSNumber *points in expected) {
		NSString *html = encode(decode([NSString stringWithFormat:@"<font face=\"Menlo\" absz=%@>x</font>", points]), (AIEncodeFlags){ .fontTags = YES });
		NSString *size = [NSString stringWithFormat:@"ABSZ=%@ SIZE=%@", points, expected[points]];
		XCTAssertTrue([html containsString:size], @"%@ pt gave %@", points, html);
	}
}

- (void)testCloseFontTagsClosesEveryFontTagItOpened
{
	NSAttributedString *message = decode(@"<font face=\"Menlo\">m</font>h<font color=\"#ff0000\">r</font>");
	NSString *open = encode(message, (AIEncodeFlags){ .fontTags = YES, .colorTags = YES });
	XCTAssertEqual(countOf(@"</FONT>", open), (NSUInteger)0);
	NSString *closed = encode(message, (AIEncodeFlags){ .fontTags = YES, .colorTags = YES, .closeFontTags = YES });
	XCTAssertEqual(countOf(@"</FONT>", closed), countOf(@"<FONT", closed));
	XCTAssertTrue([closed hasSuffix:@"</FONT>"], @"%@", closed);
}

- (void)testSimpleTagsSplitFaceAndColourIntoSeparateFontTags
{
	NSString *html = encode(decode(@"<font face=\"Menlo\" color=\"#ff0000\">x</font>"),
							(AIEncodeFlags){ .fontTags = YES, .colorTags = YES, .closeFontTags = YES, .simpleTagsOnly = YES });
	XCTAssertEqualObjects(html, @"<FONT FACE=\"Menlo\"><FONT COLOR=\"#ff0000\">x</FONT></FONT>");
}

- (void)testEncodeNonASCIIWritesHexEntities
{
	XCTAssertEqualObjects(encode(decode(@"caf\u00e9 \u00df"), (AIEncodeFlags){ .nonASCII = YES }), @"caf&#xe9; &#xdf;");
	XCTAssertEqualObjects(encode(decode(@"caf\u00e9"), (AIEncodeFlags){ 0 }), @"caf\u00e9");
}

- (void)testEncodeNonASCIIWritesOneEntityForAnAstralCharacter
{
	XCTAssertEqualObjects(encode(decode(@"a\U0001F600b"), (AIEncodeFlags){ .nonASCII = YES }), @"a&#x1f600;b");
}

- (void)testEncodeNonASCIIWritesControlCharactersAsEntities
{
	XCTAssertEqualObjects(encode(decode(@"a\tb"), (AIEncodeFlags){ .nonASCII = YES }), @"a&#x9;b");
}

- (void)testEncodeNonASCIIEncodesACombiningMarkAfterAnASCIIBase
{
	XCTAssertEqualObjects(encode(decode(@"e\u0301"), (AIEncodeFlags){ .nonASCII = YES }), @"e&#x301;");
}

- (void)testEncodeSpacesPreservesRunsOfSpaces
{
	XCTAssertEqualObjects(encode(decode(@" a  b"), (AIEncodeFlags){ .spaces = YES }), @"&nbsp;a &nbsp;b");
	XCTAssertEqualObjects(encode(decode(@"a\tb"), (AIEncodeFlags){ .spaces = YES }), @"a &nbsp;&nbsp;&nbsp;b");
}

- (void)testEncodeSpacesRoundTripsTheSpacing
{
	NSString *spaced = @" a  b   c";
	XCTAssertEqualObjects([decode(encode(decode(spaced), (AIEncodeFlags){ .spaces = YES })) string], spaced);
}

- (void)testWithoutEncodeSpacesTheSpacesAreLeftAlone
{
	XCTAssertEqualObjects(encode(decode(@" a  b\tc"), (AIEncodeFlags){ 0 }), @" a  b\tc");
}

- (void)testEveryKindOfLineBreakBecomesBR
{
	XCTAssertEqualObjects(encode(decode(@"a\r\nb\nc\rd"), (AIEncodeFlags){ 0 }), @"a<BR>b<BR>c<BR>d");
}

- (void)testHebrewTextIsWrappedInAnRTLDiv
{
	NSString *hebrew = @"\u05e9\u05dc\u05d5\u05dd";
	NSString *html = encode(decode(hebrew), (AIEncodeFlags){ 0 });
	XCTAssertEqualObjects(html, ([NSString stringWithFormat:@"<DIV dir=\"rtl\">%@</DIV>", hebrew]));
	NSAttributedString *back = decode(html);
	XCTAssertEqualObjects([back string], hebrew);
	XCTAssertEqual([[back attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] baseWritingDirection], NSWritingDirectionRightToLeft);
}

- (void)testLatinTextGetsNoDirectionDiv
{
	XCTAssertEqualObjects(encode(decode(@"hello"), (AIEncodeFlags){ 0 }), @"hello");
}

- (void)testSimpleTagsNeverEmitADirectionDiv
{
	NSString *hebrew = @"\u05e9\u05dc\u05d5\u05dd";
	XCTAssertEqualObjects(encode(decode(hebrew), (AIEncodeFlags){ .simpleTagsOnly = YES }), hebrew);
}

#pragma mark Round trips

- (void)assertRoundTripOf:(NSString *)html flags:(AIEncodeFlags)flags
{
	NSAttributedString *once = decode(html);
	NSString *encoded = encode(once, flags);
	NSAttributedString *twice = decode(encoded);
	XCTAssertTrue([twice isEqualToAttributedString:once], @"%@ became %@ which decodes differently", html, encoded);
	XCTAssertEqualObjects(encode(twice, flags), encoded);
}

- (void)testNestedBoldAndItalicRoundTrip
{
	[self assertRoundTripOf:@"<b>bold <i>both</i> bold</b> <i>italic</i>" flags:(AIEncodeFlags){ .styleTags = YES }];
}

- (void)testMisnestedInputRoundTripsStably
{
	[self assertRoundTripOf:@"<b>a<i>b</b>c</i>d" flags:(AIEncodeFlags){ .styleTags = YES }];
}

- (void)testColourFamilyAndSizeRoundTrip
{
	[self assertRoundTripOf:@"<font face=\"Menlo\" absz=18 color=\"#ff0000\">red</font> <font back=\"#00ff00\">green</font> plain"
					 flags:(AIEncodeFlags){ .fontTags = YES, .colorTags = YES, .closeFontTags = YES }];
}

- (void)testLinkRoundTrip
{
	[self assertRoundTripOf:@"see <a href=\"http://example.com/?a=1&amp;b=2\">here</a> and <b><a href=\"http://example.org/\">there</a></b>"
					 flags:(AIEncodeFlags){ .styleTags = YES }];
}

- (void)testEverythingOnRoundTrip
{
	[self assertRoundTripOf:@"<html><body><font face=\"Menlo\" absz=14><b>bold</b> &lt;tag&gt; <u>under</u> line two \u00e4</font></body></html>"
					 flags:(AIEncodeFlags){ .headers = YES, .fontTags = YES, .colorTags = YES, .closeFontTags = YES, .styleTags = YES, .spaces = YES, .attachmentsAsText = YES }];
}

- (void)testVeryLongInputRoundTrips
{
	// 2500 repetitions of 40 characters, of which seven are tags and four more collapse into one &.
	NSString *filler = [@"" stringByPaddingToLength:100000 withString:@"lorem ipsum <b>dolor</b> sit &amp; amet " startingAtIndex:0];
	NSAttributedString *once = decode(filler);
	XCTAssertEqual([once length], (NSUInteger)2500 * 29);
	NSString *encoded = encode(once, (AIEncodeFlags){ .styleTags = YES });
	XCTAssertTrue([decode(encoded) isEqualToAttributedString:once]);
}

#pragma mark The compatibility class methods

- (void)testEncodeFullStringMatchesTheDocumentedFlags
{
	NSAttributedString *message = decode(@"<font face=\"Menlo\" color=\"#ff0000\"><b>b\u00e9</b>  two</font>");
	AIEncodeFlags full = { .headers = YES, .fontTags = YES, .colorTags = YES, .closeFontTags = YES, .styleTags = YES, .nonASCII = YES, .spaces = YES, .attachmentsAsText = YES };
	AIEncodeFlags bare = { .styleTags = YES, .attachmentsAsText = YES };
	XCTAssertEqualObjects([AIHTMLDecoder encodeHTML:message encodeFullString:YES], encode(message, full));
	XCTAssertEqualObjects([AIHTMLDecoder encodeHTML:message encodeFullString:NO], encode(message, bare));
}

- (void)testClassAndInstanceDecodersAgree
{
	NSString *html = @"<b>a</b> <a href=\"http://example.com/\">l</a> &amp; <font color=\"#ff0000\">r</font>";
	XCTAssertTrue([[[AIHTMLDecoder decoder] decodeHTML:html] isEqualToAttributedString:[AIHTMLDecoder decodeHTML:html]]);
}

- (void)testPropertiesMirrorTheInitialiserFlags
{
	AIHTMLDecoder *decoder = [AIHTMLDecoder decoderWithHeaders:YES fontTags:NO closeFontTags:YES colorTags:NO styleTags:YES encodeNonASCII:NO
												  encodeSpaces:YES attachmentsAsText:NO onlyIncludeOutgoingImages:YES simpleTagsOnly:NO bodyBackground:YES allowJavascriptURLs:NO];
	XCTAssertTrue(decoder.includesHeaders);
	XCTAssertFalse(decoder.includesFontTags);
	XCTAssertTrue(decoder.closesFontTags);
	XCTAssertFalse(decoder.includesColorTags);
	XCTAssertTrue(decoder.includesStyleTags);
	XCTAssertFalse(decoder.encodesNonASCII);
	XCTAssertTrue(decoder.preservesAllSpaces);
	XCTAssertFalse(decoder.usesAttachmentTextEquivalents);
	XCTAssertTrue(decoder.onlyConvertImageAttachmentsToIMGTagsWhenSendingAMessage);
	XCTAssertFalse(decoder.onlyUsesSimpleTags);
	XCTAssertTrue(decoder.includesBodyBackground);
	XCTAssertFalse(decoder.allowJavascriptURLs);
	XCTAssertFalse(decoder.generatesStrictXHTML);
	XCTAssertFalse([AIHTMLDecoder decoder].includesHeaders);
}

#pragma mark Strict XHTML

- (AIHTMLDecoder *)strictDecoder
{
	AIHTMLDecoder *decoder = [AIHTMLDecoder decoder];
	decoder.generatesStrictXHTML = YES;
	return decoder;
}

- (NSXMLDocument *)parsedXML:(NSString *)xml
{
	NSError *error = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&error];
	XCTAssertNotNil(document, @"%@ did not parse: %@", xml, error);
	return document;
}

- (void)testStrictOutputIsWellFormedXML
{
	NSAttributedString *message = decode(@"<b>bold <i>both</i></b> <u>u</u> <a href=\"http://x/?a=1&amp;b=2\">l</a><br>line 2 &lt;&amp;&gt; \"q\" <font color=\"#ff0000\" size=5>big</font>");
	NSXMLDocument *document = [self parsedXML:[[self strictDecoder] encodeHTML:message imagesPath:nil]];
	XCTAssertEqualObjects([[document rootElement] name], @"div");
	// NSXMLDocument drops text nodes that are only whitespace, so the comparison leaves the spaces out.
	NSString *text = [[[document rootElement] stringValue] stringByReplacingOccurrencesOfString:@" " withString:@""];
	XCTAssertEqualObjects(text, @"boldbothulline2<&>\"q\"big");
}

- (void)testStrictRootIsADivWithoutHeaders
{
	NSString *xml = [[self strictDecoder] encodeHTML:decode(@"x") imagesPath:nil];
	XCTAssertTrue([xml hasPrefix:@"<div>"], @"%@", xml);
	XCTAssertTrue([xml hasSuffix:@"</div>"], @"%@", xml);
}

- (void)testStrictHeadersAddDoctypeHtmlAndBody
{
	AIHTMLDecoder *decoder = [self strictDecoder];
	decoder.includesHeaders = YES;
	NSString *xml = [decoder encodeHTML:decode(@"<body bgcolor=\"#0000ff\">x</body>") imagesPath:nil];
	XCTAssertTrue([xml hasPrefix:@"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\""], @"%@", xml);
	XCTAssertTrue([xml containsString:@"<html><body style=\"background-color: #0000ff\"><div>"], @"%@", xml);
	XCTAssertTrue([xml hasSuffix:@"</div></body></html>"], @"%@", xml);
	NSXMLDocument *document = [self parsedXML:xml];
	XCTAssertEqualObjects([[document rootElement] name], @"html");
}

- (void)testStrictLineBreaksAreSelfClosingBR
{
	NSString *xml = [[self strictDecoder] encodeHTML:decode(@"a<br>b") imagesPath:nil];
	XCTAssertEqual(countOf(@"<br />", xml), (NSUInteger)1);
	XCTAssertEqualObjects([[[self parsedXML:xml] rootElement] stringValue], @"ab");
}

- (void)testStrictNamespacePrefixesEveryElement
{
	AIHTMLDecoder *decoder = [self strictDecoder];
	decoder.XMLNamespace = @"x";
	NSString *xml = [decoder encodeHTML:decode(@"a<b>b</b><br>c") imagesPath:nil];
	XCTAssertTrue([xml hasPrefix:@"<x:div>"], @"%@", xml);
	XCTAssertTrue([xml containsString:@"<x:br />"], @"%@", xml);
	XCTAssertEqual(countOf(@"<span", xml), (NSUInteger)0, @"%@", xml);
	XCTAssertEqual(countOf(@"<x:span", xml), countOf(@"</x:span>", xml));
}

- (void)testStrictStylesBecomeCSS
{
	NSString *xml = [[self strictDecoder] encodeHTML:decode(@"<b>b</b><i>i</i><u>u</u><s>s</s><font color=\"#ff0000\" absz=18>r</font>") imagesPath:nil];
	XCTAssertTrue([xml containsString:@"font-weight: bold;"], @"%@", xml);
	XCTAssertTrue([xml containsString:@"font-style: italic;"], @"%@", xml);
	XCTAssertTrue([xml containsString:@"text-decoration: underline;"], @"%@", xml);
	XCTAssertTrue([xml containsString:@"text-decoration: line-through;"], @"%@", xml);
	XCTAssertTrue([xml containsString:@"color: #ff0000;"], @"%@", xml);
	XCTAssertTrue([xml containsString:@"font-size: 18pt;"], @"%@", xml);
	XCTAssertEqual(countOf(@"<B>", xml) + countOf(@"<FONT", xml), (NSUInteger)0, @"%@", xml);
}

- (void)testStrictLinkIsAnAnchorWithHref
{
	NSString *xml = [[self strictDecoder] encodeHTML:decode(@"<a href=\"http://example.com/\">x</a>") imagesPath:nil];
	XCTAssertTrue([xml containsString:@"<a href=\"http://example.com/\""], @"%@", xml);
	NSXMLElement *anchor = [[[[self parsedXML:xml] rootElement] nodesForXPath:@"//a" error:NULL] firstObject];
	XCTAssertEqualObjects([anchor stringValue], @"x");
}

- (void)testStrictEscapesTextCharacters
{
	NSString *xml = [[self strictDecoder] encodeHTML:decode(@"&lt;&amp;&gt;") imagesPath:nil];
	XCTAssertTrue([xml containsString:@"&lt;&amp;&gt;"], @"%@", xml);
}

- (void)testStrictAttachmentIsTextWhenThereIsNoImagesPath
{
	NSString *xml = [[self strictDecoder] encodeHTML:decode(@"a<img src=\"/nonexistent/x.png\" alt=\"pic\">b") imagesPath:nil];
	XCTAssertEqualObjects([[[self parsedXML:xml] rootElement] stringValue], @"apicb");
	XCTAssertEqual(countOf(@"<img", xml), (NSUInteger)0, @"%@", xml);
}

- (void)testStrictAttachmentWithAnImagesPathBecomesAnImgCopiedThere
{
	NSString *source = [self writeSmallPNGNamed:@"source.png"];
	NSString *imagesPath = [scratchDirectory stringByAppendingPathComponent:@"images"];
	NSString *xml = [[self strictDecoder] encodeHTML:decode([NSString stringWithFormat:@"<img src=\"%@\" alt=\"pic\">", source]) imagesPath:imagesPath];
	XCTAssertTrue([xml containsString:@"<img"], @"%@", xml);
	XCTAssertTrue([xml containsString:@"src=\"source.png\""], @"%@", xml);
	XCTAssertTrue([xml containsString:@"width=\"3\" height=\"2\""], @"%@", xml);
	XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[imagesPath stringByAppendingPathComponent:@"source.png"]]);
	[self parsedXML:xml];
}

- (void)testStrictImgAltIsTheAttachmentsText
{
	NSString *source = [self writeSmallPNGNamed:@"source.png"];
	NSString *imagesPath = [scratchDirectory stringByAppendingPathComponent:@"images"];
	NSString *xml = [[self strictDecoder] encodeHTML:decode([NSString stringWithFormat:@"<img src=\"%@\" alt=\"pic\">", source]) imagesPath:imagesPath];
	XCTAssertTrue([xml containsString:@"alt=\"pic\""], @"%@", xml);
}

- (void)testStrictRTLParagraphGetsADirAttribute
{
	NSString *xml = [[self strictDecoder] encodeHTML:decode(@"<div dir=\"rtl\">x</div>") imagesPath:nil];
	XCTAssertTrue([xml hasPrefix:@"<div dir=\"rtl\">"], @"%@", xml);
}

- (void)testRootElementTreeMatchesTheString
{
	AIXMLElement *root = [[self strictDecoder] rootStrictXHTMLElementForAttributedString:decode(@"a<b>b</b>") imagesPath:nil];
	XCTAssertEqualObjects([root name], @"div");
	XCTAssertEqual([root numberOfAttributes], (NSUInteger)0);
	XCTAssertEqualObjects([[[self parsedXML:[root XMLString]] rootElement] stringValue], @"ab");
}

@end
