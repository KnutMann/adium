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

/* What the lax scanner recognises: every scheme the lexer names, bare domains, hosts of every
 * kind, paths, e-mail addresses, international text and percent-encoding, plus the scanner's
 * own API (nextURI, allURIs, isValidURI, strictness) and the framework's URI corpus. Where a
 * link sits in text, and what comes out as an attributed string, are the other three files. */
@interface TestHyperlinkScanner : XCTestCase
@end

@implementation TestHyperlinkScanner

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

#pragma mark Schemes

/* The schemes AHLinkLexer.l names outright; any other scheme is "tentative" and asked of
 * Launch Services, which differs from machine to machine and is tested below through the
 * class method only. */
- (void)testEveryCanonicalSchemeIsALink
{
	NSArray *schemes = @[@"http", @"https", @"ftp", @"sftp", @"ssh", @"telnet", @"smb", @"afp", @"vnc",
						 @"webcal", @"feed", @"feeds", @"cifs", @"help", @"rtsp", @"daap", @"itms"];
	for (NSString *scheme in schemes) {
		NSString *url = [NSString stringWithFormat:@"%@://example.com/path", scheme];
		AHMarkedHyperlink *link = [self assertString:[NSString stringWithFormat:@"x %@ y", url] linksText:url toURL:url];
		XCTAssertEqual(link.validationStatus, AH_URL_VALID, @"%@", scheme);
	}
}

- (void)testFileURLIsALink
{
	AHMarkedHyperlink *link = [self assertString:@"open file:///Users/me/notes.txt now"
									  linksText:@"file:///Users/me/notes.txt"
										  toURL:@"file:///Users/me/notes.txt"];
	XCTAssertEqual(link.validationStatus, AH_FILE_VALID);
}

- (void)testMailtoURLIsALink
{
	AHMarkedHyperlink *link = [self assertString:@"write mailto:foo@example.com please"
									  linksText:@"mailto:foo@example.com"
										  toURL:@"mailto:foo@example.com"];
	XCTAssertEqual(link.validationStatus, AH_MAILTO_VALID);
}

// RFC 3986 section 3.1: schemes are case-insensitive, and section 3.2.2 says the same of hosts.
- (void)testSchemeAndHostAreCaseInsensitive
{
	AHMarkedHyperlink *link = [self onlyLinkIn:@"HTTP://EXAMPLE.COM/Path"];
	XCTAssertEqualObjects(link.URL.scheme.lowercaseString, @"http");
	XCTAssertEqualObjects(link.URL.host.lowercaseString, @"example.com");
	XCTAssertEqualObjects(link.URL.path, @"/Path");
}

/* A scheme the lexer does not name becomes a link only if an application is registered for
 * it, which this test cannot know. What it can pin is the verdict before that question: lax
 * checking accepts the syntax, strict checking does not. */
- (void)testUnknownSchemeIsAcceptedByLaxCheckingOnly
{
	for (NSString *uri in @[@"xmpp:foo@example.com", @"spotify:track:abcd1234", @"rdar://problem/1234"]) {
		AH_URI_VERIFICATION_STATUS status = AH_URL_INVALID;
		XCTAssertTrue([AHHyperlinkScanner isStringValidURI:uri usingStrict:NO fromIndex:NULL withStatus:&status schemeLength:NULL], @"%@", uri);
		XCTAssertEqual(status, AH_URL_TENTATIVE, @"%@", uri);
		XCTAssertFalse([AHHyperlinkScanner isStringValidURI:uri usingStrict:YES fromIndex:NULL withStatus:NULL schemeLength:NULL], @"%@", uri);
	}
}

- (void)testSchemeLengthIsReportedForTheCaller
{
	unsigned long schemeLength = 0;
	XCTAssertTrue([AHHyperlinkScanner isStringValidURI:@"https://example.com/" usingStrict:YES fromIndex:NULL withStatus:NULL schemeLength:&schemeLength]);
	XCTAssertEqual(schemeLength, 5UL);
	XCTAssertTrue([AHHyperlinkScanner isStringValidURI:@"xmpp:foo@example.com" usingStrict:NO fromIndex:NULL withStatus:NULL schemeLength:&schemeLength]);
	XCTAssertEqual(schemeLength, 4UL);
}

#pragma mark Bare domains

- (void)testBareDomainLinksWithHTTP
{
	AHMarkedHyperlink *link = [self assertString:@"example.com" linksText:@"example.com" toURL:@"http://example.com"];
	XCTAssertEqual(link.validationStatus, AH_URL_DEGENERATE);
}

- (void)testBareDomainWithWWWLinksWithHTTP
{
	[self assertString:@"see www.example.com today" linksText:@"www.example.com" toURL:@"http://www.example.com"];
}

- (void)testBareFTPHostLinksWithFTP
{
	[self assertString:@"ftp.example.com" linksText:@"ftp.example.com" toURL:@"ftp://ftp.example.com"];
}

- (void)testBareDomainKeepsItsPathQueryAndFragment
{
	[self assertString:@"see example.org/path/to?x=1&y=2#frag ok"
			 linksText:@"example.org/path/to?x=1&y=2#frag"
				 toURL:@"http://example.org/path/to?x=1&y=2#frag"];
}

- (void)testBareDomainWithSeveralLabelsAndACountryCodeLinks
{
	[self assertString:@"sub.domain.example.co.uk" linksText:@"sub.domain.example.co.uk" toURL:@"http://sub.domain.example.co.uk"];
}

- (void)testBareDomainKeepsItsPort
{
	AHMarkedHyperlink *link = [self assertString:@"example.com:8080/x" linksText:@"example.com:8080/x" toURL:@"http://example.com:8080/x"];
	XCTAssertEqualObjects(link.URL.port, @8080);
}

#pragma mark Hosts, ports, userinfo

- (void)testPathQueryAndFragmentAreKept
{
	NSString *url = @"http://example.com/path/to/page?x=1&y=2#section";
	AHMarkedHyperlink *link = [self assertString:url linksText:url toURL:url];
	XCTAssertEqualObjects(link.URL.path, @"/path/to/page");
	XCTAssertEqualObjects(link.URL.query, @"x=1&y=2");
	XCTAssertEqualObjects(link.URL.fragment, @"section");
}

- (void)testIPv4HostWithPortIsALink
{
	NSString *url = @"http://192.168.0.1:8080/path";
	AHMarkedHyperlink *link = [self assertString:[@"at " stringByAppendingString:url] linksText:url toURL:url];
	XCTAssertEqualObjects(link.URL.host, @"192.168.0.1");
	XCTAssertEqualObjects(link.URL.port, @8080);
}

- (void)testIPv6HostWithPortIsALink
{
	NSString *url = @"http://[2001:db8::1]:8080/path";
	AHMarkedHyperlink *link = [self assertString:[@"at " stringByAppendingString:url] linksText:url toURL:url];
	XCTAssertEqualObjects(link.URL.port, @8080);
	XCTAssertEqualObjects(link.URL.path, @"/path");
}

- (void)testIPv6LoopbackAndFullFormAreLinks
{
	[self assertString:@"http://[::1]/" linksText:@"http://[::1]/" toURL:@"http://[::1]/"];
	[self assertString:@"http://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]/x"
			 linksText:@"http://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]/x"
				 toURL:@"http://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]/x"];
}

- (void)testPortIsPartOfTheLink
{
	AHMarkedHyperlink *link = [self assertString:@"http://example.com:8080/" linksText:@"http://example.com:8080/" toURL:@"http://example.com:8080/"];
	XCTAssertEqualObjects(link.URL.port, @8080);
}

- (void)testUserAndPasswordArePartOfTheLink
{
	AHMarkedHyperlink *link = [self assertString:@"http://user:pass@example.com/" linksText:@"http://user:pass@example.com/" toURL:@"http://user:pass@example.com/"];
	XCTAssertEqualObjects(link.URL.user, @"user");
	XCTAssertEqualObjects(link.URL.password, @"pass");
	XCTAssertEqualObjects(link.URL.host, @"example.com");
}

- (void)testUserWithoutPasswordIsPartOfTheLink
{
	AHMarkedHyperlink *link = [self assertString:@"ftp://user@example.com/" linksText:@"ftp://user@example.com/" toURL:@"ftp://user@example.com/"];
	XCTAssertEqualObjects(link.URL.user, @"user");
	XCTAssertNil(link.URL.password);
}

- (void)testHyphenAndUnderscoreAreAllowedInHostLabels
{
	[self assertString:@"http://my-host.example.com/" linksText:@"http://my-host.example.com/" toURL:@"http://my-host.example.com/"];
	[self assertString:@"http://acts_as_solr.example.com/" linksText:@"http://acts_as_solr.example.com/" toURL:@"http://acts_as_solr.example.com/"];
}

#pragma mark E-mail

- (void)testBareEmailAddressLinksWithMailto
{
	AHMarkedHyperlink *link = [self assertString:@"write foo@example.com please" linksText:@"foo@example.com" toURL:@"mailto:foo@example.com"];
	XCTAssertEqual(link.validationStatus, AH_MAILTO_DEGENERATE);
}

// RFC 6068 keeps the address as the user typed it; "." and "+" in the local part are both common.
- (void)testEmailAddressWithDotsAndPlusInTheLocalPartLinksWhole
{
	[self assertString:@"foo.bar+tag@sub.example.co.uk" linksText:@"foo.bar+tag@sub.example.co.uk" toURL:@"mailto:foo.bar+tag@sub.example.co.uk"];
}

#pragma mark International text

// RFC 3987 maps an IRI host to a URI either by percent-encoding its UTF-8 or by IDNA; both open the same site.
- (void)testInternationalisedDomainNameIsALink
{
	NSString *host = @"ουτοπία.δπθ.gr";
	NSString *url = [NSString stringWithFormat:@"http://%@/", host];
	NSString *text = [NSString stringWithFormat:@"see %@ now", url];
	AHMarkedHyperlink *link = [self onlyLinkIn:text];
	XCTAssertEqualObjects([self textOfLink:link in:text], url);
	XCTAssertNotNil(link.URL);
	NSString *decodedHost = [link.URL.host stringByRemovingPercentEncoding];
	XCTAssertTrue([decodedHost isEqualToString:host] || [link.URL.host isEqualToString:@"xn--kxae4bafwg.xn--pxaix.gr"], @"host came out as %@", link.URL.host);
}

- (void)testBareInternationalisedDomainNameLinksWithHTTP
{
	NSString *host = @"ουτοπία.δπθ.gr";
	AHMarkedHyperlink *link = [self onlyLinkIn:host];
	XCTAssertEqualObjects([self textOfLink:link in:host], host);
	XCTAssertEqualObjects(link.URL.scheme, @"http");
	XCTAssertEqualObjects([link.URL.host stringByRemovingPercentEncoding], host);
}

- (void)testNonASCIIPathIsPercentEncodedInTheURL
{
	NSString *text = @"https://de.wikipedia.org/wiki/Straße";
	AHMarkedHyperlink *link = [self onlyLinkIn:text];
	XCTAssertEqualObjects([self textOfLink:link in:text], text);
	XCTAssertTrue([link.URL.absoluteString canBeConvertedToEncoding:NSASCIIStringEncoding], @"%@", link.URL);
	XCTAssertEqualObjects([link.URL.absoluteString stringByRemovingPercentEncoding], text);
}

// A character outside the BMP is two UTF-16 units in the range and four UTF-8 bytes in the URL.
- (void)testNonBMPCharacterInThePathIsPercentEncodedAndCountedInTheRange
{
	NSString *text = @"https://example.com/\U0001F600";
	AHMarkedHyperlink *link = [self assertString:text linksText:text toURL:@"https://example.com/%F0%9F%98%80"];
	XCTAssertEqual(link.range.length, text.length);
}

#pragma mark Percent-encoding

- (void)testPercentEncodedSpaceIsNotEncodedTwice
{
	[self assertString:@"http://example.com/a%20b" linksText:@"http://example.com/a%20b" toURL:@"http://example.com/a%20b"];
}

- (void)testPercentEncodedQueryValueIsKeptVerbatim
{
	[self assertString:@"http://example.com/?q=%E2%9C%93" linksText:@"http://example.com/?q=%E2%9C%93" toURL:@"http://example.com/?q=%E2%9C%93"];
}

// RFC 3986 section 2.2: "%2F" in a path is not the same as "/", so decoding it changes the resource.
- (void)testPercentEncodedReservedCharacterStaysEncoded
{
	[self assertString:@"http://example.com/a%2Fb" linksText:@"http://example.com/a%2Fb" toURL:@"http://example.com/a%2Fb"];
	[self assertString:@"http://example.com/a%3Fb" linksText:@"http://example.com/a%3Fb" toURL:@"http://example.com/a%3Fb"];
}

#pragma mark The scanner's own API

- (void)testNextURIWalksTheLinksInOrderThenReturnsNil
{
	AHHyperlinkScanner *scanner = [AHHyperlinkScanner hyperlinkScannerWithString:@"http://a.example/ and http://b.example/"];
	XCTAssertEqualObjects([scanner nextURI].URL.absoluteString, @"http://a.example/");
	XCTAssertEqualObjects([scanner nextURI].URL.absoluteString, @"http://b.example/");
	XCTAssertNil([scanner nextURI]);
	XCTAssertNil([scanner nextURI]);
}

- (void)testAllURIsGivesTheSameAnswerTwice
{
	AHHyperlinkScanner *scanner = [AHHyperlinkScanner hyperlinkScannerWithString:@"http://a.example/ and http://b.example/"];
	NSArray *first = [[scanner allURIs] valueForKey:@"URL"];
	NSArray *second = [[scanner allURIs] valueForKey:@"URL"];
	XCTAssertEqual(first.count, (NSUInteger)2);
	XCTAssertEqualObjects(first, second);
}

- (void)testParentStringIsTheScannedString
{
	NSString *text = @"see https://example.com/ now";
	XCTAssertEqualObjects([self onlyLinkIn:text].parentString, text);
}

- (void)testIsValidURIRequiresTheWholeStringToBeOneURI
{
	XCTAssertTrue([[AHHyperlinkScanner hyperlinkScannerWithString:@"http://example.com/"] isValidURI]);
	XCTAssertTrue([[AHHyperlinkScanner hyperlinkScannerWithString:@"example.com"] isValidURI]);
	XCTAssertFalse([[AHHyperlinkScanner hyperlinkScannerWithString:@"see http://example.com/"] isValidURI]);
	XCTAssertFalse([[AHHyperlinkScanner hyperlinkScannerWithString:@"example.com and more"] isValidURI]);
	XCTAssertFalse([[AHHyperlinkScanner hyperlinkScannerWithString:@""] isValidURI]);
}

- (void)testStrictScannerSkipsBareDomainsAndEmailAddresses
{
	NSString *text = @"example.com foo@example.com http://example.com/";
	NSArray *links = [[AHHyperlinkScanner strictHyperlinkScannerWithString:text] allURIs];
	XCTAssertEqual(links.count, (NSUInteger)1, @"%@", [links valueForKey:@"URL"]);
	XCTAssertEqualObjects([links.firstObject URL].absoluteString, @"http://example.com/");
	XCTAssertFalse([[AHHyperlinkScanner strictHyperlinkScannerWithString:@"example.com"] isValidURI]);
}

// The header promises "a new strict AHHyperlinkScanner with the given attributed string".
- (void)testStrictAttributedScannerIsStrict
{
	NSAttributedString *text = [[NSAttributedString alloc] initWithString:@"example.com foo@example.com"];
	NSArray *links = [[AHHyperlinkScanner strictHyperlinkScannerWithAttributedString:text] allURIs];
	XCTAssertEqual(links.count, (NSUInteger)0, @"%@", [links valueForKey:@"URL"]);
}

#pragma mark The framework's corpus

- (NSArray *)corpusLines
{
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"TestURIs" ofType:@"txt" inDirectory:@"Fixtures"];
	XCTAssertNotNil(path, @"Fixtures/TestURIs.txt is not in the test bundle");
	if (!path) return nil;
	NSString *corpus = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
	XCTAssertNotNil(corpus);
	return [corpus componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

/* TestURIs.txt is the framework's own list of what should link, in sections under "# " headers.
 * Two sections are kept out of this test: the Lorem Ipsum, which is the opposite claim and has
 * a test of its own, and the bare IPv4 addresses ("1.1.1.1", no scheme), which the lexer only
 * accepts behind a scheme and which this suite deliberately does not pin either way, because
 * a four-part version number looks the same. The IP section's "http://1.1.1.1" lines stay in. */
- (void)testEveryURIInTheCorpusIsOneLinkCoveringTheLine
{
	NSMutableArray *wrong = [NSMutableArray array];
	BOOL inLoremIpsum = NO;
	NSUInteger checked = 0;
	for (NSString *line in [self corpusLines]) {
		if ([line hasPrefix:@"#"]) {
			inLoremIpsum = ([line rangeOfString:@"Lorem Ipsum"].location != NSNotFound);
			continue;
		}
		if (!line.length || inLoremIpsum) continue;
		if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[line characterAtIndex:0]]) continue;
		checked++;
		NSArray *links = [self linksIn:line];
		AHMarkedHyperlink *link = links.firstObject;
		if (links.count != 1 || !NSEqualRanges(link.range, NSMakeRange(0, line.length)) || !link.URL)
			[wrong addObject:[NSString stringWithFormat:@"%@ -> %@", line, [links valueForKey:@"URL"]]];
	}
	XCTAssertGreaterThan(checked, (NSUInteger)100, @"the corpus was not read");
	XCTAssertEqual(wrong.count, (NSUInteger)0, @"%@", [wrong componentsJoinedByString:@"\n"]);
}

- (void)testTheLoremIpsumInTheCorpusHasNoLinks
{
	BOOL inLoremIpsum = NO;
	NSUInteger checked = 0;
	for (NSString *line in [self corpusLines]) {
		if ([line hasPrefix:@"#"]) {
			inLoremIpsum = ([line rangeOfString:@"Lorem Ipsum"].location != NSNotFound);
			continue;
		}
		if (!line.length || !inLoremIpsum) continue;
		checked++;
		NSArray *links = [self linksIn:line];
		XCTAssertEqual(links.count, (NSUInteger)0, @"%@ in \"%@\"", [links valueForKey:@"URL"], line);
	}
	XCTAssertGreaterThan(checked, (NSUInteger)0, @"the Lorem Ipsum section was not found");
}

@end
