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
#import <AutoHyperlinks/AutoHyperlinks.h>

/* Where a link begins and ends inside running text: the punctuation around it that is not
 * part of it, the parentheses inside it that are, and the range reported back, measured
 * against the original string. */
@interface TestHyperlinkBoundaries : XCTestCase
@end

@implementation TestHyperlinkBoundaries

#pragma mark Helpers

- (NSArray *)linksIn:(NSString *)string
{
	return [[AHHyperlinkScanner hyperlinkScannerWithString:string] allURIs];
}

/* A range outside the string would throw out of substringWithRange: and take the whole run
 * down with it, so it is turned into an ordinary failure here. */
- (NSString *)textOfLink:(AHMarkedHyperlink *)link in:(NSString *)string
{
	if (NSMaxRange(link.range) > string.length) {
		XCTFail(@"Range %@ lies outside \"%@\" (length %lu)", NSStringFromRange(link.range), string, (unsigned long)string.length);
		return nil;
	}
	return [string substringWithRange:link.range];
}

- (AHMarkedHyperlink *)onlyLinkIn:(NSString *)string
{
	NSArray *links = [self linksIn:string];
	XCTAssertEqual(links.count, (NSUInteger)1, @"Expected exactly one link in \"%@\", got %@", string, [links valueForKey:@"URL"]);
	return links.firstObject;
}

- (AHMarkedHyperlink *)assertString:(NSString *)string linksText:(NSString *)text toURL:(NSString *)url
{
	AHMarkedHyperlink *link = [self onlyLinkIn:string];
	XCTAssertEqualObjects([self textOfLink:link in:string], text, @"wrong range in \"%@\"", string);
	XCTAssertEqualObjects(link.URL.absoluteString, url, @"wrong URL in \"%@\"", string);
	return link;
}

#pragma mark Trailing punctuation

- (void)testTrailingPeriodIsNotPartOfTheLink
{
	[self assertString:@"Visit http://example.com/." linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

- (void)testTrailingPeriodAfterTheHostIsNotPartOfTheLink
{
	[self assertString:@"Visit http://example.com." linksText:@"http://example.com" toURL:@"http://example.com"];
}

- (void)testTrailingPeriodAfterABareDomainIsNotPartOfTheLink
{
	[self assertString:@"Visit example.com." linksText:@"example.com" toURL:@"http://example.com"];
}

- (void)testTrailingPeriodAfterAnEmailAddressIsNotPartOfTheLink
{
	[self assertString:@"mail me at foo@example.com." linksText:@"foo@example.com" toURL:@"mailto:foo@example.com"];
}

- (void)testTrailingCommaIsNotPartOfTheLink
{
	[self assertString:@"http://example.com/, then" linksText:@"http://example.com/" toURL:@"http://example.com/"];
	[self assertString:@"foo@example.com, then" linksText:@"foo@example.com" toURL:@"mailto:foo@example.com"];
}

- (void)testTrailingQuestionMarkIsNotPartOfTheLink
{
	[self assertString:@"seen http://example.com/?" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

- (void)testTrailingExclamationMarkIsNotPartOfTheLink
{
	[self assertString:@"wow http://example.com/!" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

- (void)testTrailingColonIsNotPartOfTheLink
{
	[self assertString:@"http://example.com/: yes" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

- (void)testTrailingSemicolonIsNotPartOfTheLink
{
	[self assertString:@"http://example.com/; yes" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

#pragma mark Enclosures and quotes

- (void)testClosingParenthesisAfterTheLinkIsNotPartOfIt
{
	[self assertString:@"(see http://example.com/)" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

- (void)testParenthesesAroundTheLinkAreNotPartOfIt
{
	[self assertString:@"(http://example.com/)" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

- (void)testBracesAroundTheLinkAreNotPartOfIt
{
	[self assertString:@"{http://example.com/}" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

- (void)testAngleBracketsAroundTheLinkAreNotPartOfIt
{
	[self assertString:@"<https://example.com/>" linksText:@"https://example.com/" toURL:@"https://example.com/"];
}

- (void)testStraightDoubleQuotesAroundTheLinkAreNotPartOfIt
{
	[self assertString:@"\"http://example.com/\"" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

- (void)testStraightSingleQuotesAroundTheLinkAreNotPartOfIt
{
	[self assertString:@"'http://example.com/'" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

// macOS substitutes curly quotes as one types, so this is what a quoted link usually looks like when sent.
- (void)testCurlyDoubleQuotesAroundTheLinkAreNotPartOfIt
{
	[self assertString:@"“http://example.com/”" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

- (void)testGuillemetsAroundTheLinkAreNotPartOfIt
{
	[self assertString:@"«http://example.com/»" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

- (void)testPunctuationBeforeTheLinkIsNotPartOfIt
{
	[self assertString:@"url:http://example.com/" linksText:@"http://example.com/" toURL:@"http://example.com/"];
	[self assertString:@"—http://example.com/" linksText:@"http://example.com/" toURL:@"http://example.com/"];
}

#pragma mark Parentheses inside the link

- (void)testBalancedParenthesesInsideThePathStayInTheLink
{
	NSString *url = @"https://en.wikipedia.org/wiki/Foo_(bar)";
	[self assertString:url linksText:url toURL:url];
}

- (void)testBalancedParenthesesStayWhenTheWholeLinkIsParenthesised
{
	NSString *url = @"https://en.wikipedia.org/wiki/Foo_(bar)";
	[self assertString:[NSString stringWithFormat:@"(%@)", url] linksText:url toURL:url];
}

/* Both ends are indices into the string; the period must go whether or not anything precedes
 * the link. */
- (void)testTrailingPeriodAfterBalancedParenthesesIsNotPartOfTheLink
{
	NSString *url = @"https://en.wikipedia.org/wiki/Foo_(bar)";
	[self assertString:[NSString stringWithFormat:@"see %@.", url] linksText:url toURL:url];
}

- (void)testClosingParenthesisAndPeriodAfterAParenthesisedWikipediaLinkAreNotPartOfIt
{
	NSString *url = @"https://en.wikipedia.org/wiki/Foo_(bar)";
	[self assertString:[NSString stringWithFormat:@"(see %@).", url] linksText:url toURL:url];
}

- (void)testUnbalancedClosingParenthesisIsNotPartOfTheLink
{
	[self assertString:@"http://example.com/x)" linksText:@"http://example.com/x" toURL:@"http://example.com/x"];
}

- (void)testParenthesesInsideTheQueryStayInTheLink
{
	[self assertString:@"http://example.com/?q=(x)" linksText:@"http://example.com/?q=(x)" toURL:@"http://example.com/?q=(x)"];
}

- (void)testBracketsInsideThePathStayInTheLink
{
	NSString *text = @"http://example.com/a[1]";
	AHMarkedHyperlink *link = [self onlyLinkIn:text];
	XCTAssertEqualObjects([self textOfLink:link in:text], text);
	XCTAssertNotNil(link.URL);
}

#pragma mark Ranges against the original string

- (void)testRangeIsInUTF16UnitsWhenNonBMPCharactersPrecedeTheLink
{
	NSString *text = @"\U0001F600 see https://example.com/ now";
	AHMarkedHyperlink *link = [self onlyLinkIn:text];
	XCTAssertEqual(link.range.location, (NSUInteger)7);
	XCTAssertEqual(link.range.length, (NSUInteger)20);
	XCTAssertEqualObjects([self textOfLink:link in:text], @"https://example.com/");
}

- (void)testSeveralLinksComeBackInOrderWithTheirOwnRanges
{
	NSString *text = @"a http://a.example/ b https://b.example/x c c.example.com d foo@example.com e";
	NSArray *links = [self linksIn:text];
	NSArray *texts = @[@"http://a.example/", @"https://b.example/x", @"c.example.com", @"foo@example.com"];
	NSArray *urls = @[@"http://a.example/", @"https://b.example/x", @"http://c.example.com", @"mailto:foo@example.com"];
	XCTAssertEqual(links.count, texts.count, @"%@", [links valueForKey:@"URL"]);
	for (NSUInteger i = 0; i < MIN(links.count, texts.count); i++) {
		AHMarkedHyperlink *link = links[i];
		XCTAssertEqualObjects([self textOfLink:link in:text], texts[i]);
		XCTAssertEqualObjects(link.URL.absoluteString, urls[i]);
		if (i) XCTAssertGreaterThanOrEqual(link.range.location, NSMaxRange([links[i - 1] range]), @"links overlap or run backwards");
	}
}

- (void)testLinkAtTheVeryStartOfTheString
{
	AHMarkedHyperlink *link = [self assertString:@"http://example.com/ first" linksText:@"http://example.com/" toURL:@"http://example.com/"];
	XCTAssertEqual(link.range.location, (NSUInteger)0);
}

- (void)testLinkAtTheVeryEndOfTheString
{
	NSString *text = @"last http://example.com/";
	AHMarkedHyperlink *link = [self assertString:text linksText:@"http://example.com/" toURL:@"http://example.com/"];
	XCTAssertEqual(NSMaxRange(link.range), text.length);
}

- (void)testStringThatIsOnlyAURLIsOneLinkCoveringAllOfIt
{
	NSString *text = @"http://example.com/";
	AHMarkedHyperlink *link = [self assertString:text linksText:text toURL:text];
	XCTAssertEqual(link.range.location, (NSUInteger)0);
	XCTAssertEqual(link.range.length, text.length);
}

- (void)testEmptyStringHasNoLinks
{
	AHHyperlinkScanner *scanner = [AHHyperlinkScanner hyperlinkScannerWithString:@""];
	XCTAssertEqual([scanner allURIs].count, (NSUInteger)0);
	XCTAssertNil([scanner nextURI]);
	XCTAssertEqual([scanner linkifiedString].length, (NSUInteger)0);
}

- (void)testNewlinesAndTabsEndTheLink
{
	[self assertString:@"a\nhttps://example.com/\tb" linksText:@"https://example.com/" toURL:@"https://example.com/"];
}

#pragma mark One link must not spawn or swallow the next

/* The lexer counts bytes and the scan location counts UTF-16 units; a Greek domain is nearly
 * twice as long in the one as in the other, and the link after it must still be found whole
 * rather than from somewhere inside it. */
- (void)testLinkFollowingAnInternationalisedDomainIsFoundWhole
{
	NSString *host = @"ουτοπία.δπθ.gr";
	NSString *text = [NSString stringWithFormat:@"%@ http://example.com/", host];
	NSArray *links = [self linksIn:text];
	XCTAssertEqual(links.count, (NSUInteger)2, @"%@", [links valueForKey:@"URL"]);
	XCTAssertEqualObjects([self textOfLink:links.firstObject in:text], host);
	XCTAssertEqualObjects([self textOfLink:links.lastObject in:text], @"http://example.com/");
	XCTAssertEqualObjects([links.lastObject URL].absoluteString, @"http://example.com/");
}

// The same arithmetic past the BMP: an emoji is four bytes and two UTF-16 units.
- (void)testLinkFollowingOneWithANonBMPPathIsFound
{
	NSString *text = @"https://example.com/\U0001F600 http://example.com/";
	NSArray *links = [self linksIn:text];
	XCTAssertEqual(links.count, (NSUInteger)2, @"%@", [links valueForKey:@"URL"]);
	XCTAssertEqualObjects([self textOfLink:links.lastObject in:text], @"http://example.com/");
}

/* After a link the scan resumes past the link itself, not a link's length past wherever it
 * stood before the whitespace in front of the link was skipped; from there it would resume
 * inside the link just found and report its tail again. */
- (void)testExtraSpacesBeforeALinkDoNotProduceAPhantomSecondLink
{
	NSString *text = @"a      https://host.example/dir/example.com/ x";
	NSArray *links = [self linksIn:text];
	XCTAssertEqual(links.count, (NSUInteger)1, @"%@", [links valueForKey:@"URL"]);
	XCTAssertEqualObjects([self textOfLink:links.firstObject in:text], @"https://host.example/dir/example.com/");
}

@end
