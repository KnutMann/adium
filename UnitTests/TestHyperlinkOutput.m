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

/* The two ways the scanner hands its links out: the attributed string with NSLinkAttributeName
 * on exactly the link ranges, and fast enumeration with for (link in scanner). */
@interface TestHyperlinkOutput : XCTestCase
@end

@implementation TestHyperlinkOutput

#pragma mark Helpers

// A string with many links, each one distinct, so a lost or repeated link shows by its number.
- (NSString *)textWithLinks:(NSUInteger)count
{
	NSMutableString *text = [NSMutableString string];
	for (NSUInteger i = 0; i < count; i++)
		[text appendFormat:@"word%lu http://host%lu.example/p%lu ", (unsigned long)i, (unsigned long)i, (unsigned long)i];
	return text;
}

#pragma mark linkifiedString

- (void)testLinkifiedStringPutsTheLinkAttributeOnExactlyTheLinkRange
{
	NSString *text = @"see https://example.com/ now";
	NSAttributedString *linkified = [[AHHyperlinkScanner hyperlinkScannerWithString:text] linkifiedString];
	XCTAssertEqualObjects(linkified.string, text);

	NSRange effective = NSMakeRange(NSNotFound, 0);
	id value = [linkified attribute:NSLinkAttributeName atIndex:4 longestEffectiveRange:&effective inRange:NSMakeRange(0, text.length)];
	XCTAssertEqualObjects(value, [NSURL URLWithString:@"https://example.com/"]);
	XCTAssertEqual(effective.location, (NSUInteger)4);
	XCTAssertEqual(effective.length, (NSUInteger)20);
	XCTAssertNil([linkified attribute:NSLinkAttributeName atIndex:3 effectiveRange:NULL]);
	XCTAssertNil([linkified attribute:NSLinkAttributeName atIndex:24 effectiveRange:NULL]);
}

- (void)testLinkifiedStringKeepsTheAttributesItWasGiven
{
	NSString *text = @"see https://example.com/ now";
	NSFont *bold = [NSFont boldSystemFontOfSize:13];
	NSAttributedString *input = [[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName: bold}];
	NSAttributedString *linkified = [[AHHyperlinkScanner hyperlinkScannerWithAttributedString:input] linkifiedString];

	XCTAssertEqualObjects(linkified.string, text);
	NSDictionary *onLink = [linkified attributesAtIndex:10 effectiveRange:NULL];
	XCTAssertEqualObjects(onLink[NSFontAttributeName], bold);
	XCTAssertEqualObjects(onLink[NSLinkAttributeName], [NSURL URLWithString:@"https://example.com/"]);
	NSDictionary *offLink = [linkified attributesAtIndex:1 effectiveRange:NULL];
	XCTAssertEqualObjects(offLink[NSFontAttributeName], bold);
	XCTAssertNil(offLink[NSLinkAttributeName]);
}

- (void)testLinkifiedStringWithoutLinksIsTheInputText
{
	NSString *text = @"no links here at all";
	NSAttributedString *linkified = [[AHHyperlinkScanner hyperlinkScannerWithString:text] linkifiedString];
	XCTAssertEqualObjects(linkified.string, text);
	[linkified enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, linkified.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
		XCTAssertNil(value, @"a link attribute at %@", NSStringFromRange(range));
	}];
}

- (void)testLinkifiedStringCarriesEveryLinkThatAllURIsFinds
{
	NSString *text = [self textWithLinks:40];
	AHHyperlinkScanner *scanner = [AHHyperlinkScanner hyperlinkScannerWithString:text];
	NSArray *links = [scanner allURIs];
	NSAttributedString *linkified = [scanner linkifiedString];
	XCTAssertEqual(links.count, (NSUInteger)40);
	for (AHMarkedHyperlink *link in links) {
		NSRange effective = NSMakeRange(NSNotFound, 0);
		id value = [linkified attribute:NSLinkAttributeName atIndex:link.range.location longestEffectiveRange:&effective inRange:NSMakeRange(0, text.length)];
		XCTAssertEqualObjects(value, link.URL);
		XCTAssertTrue(NSEqualRanges(effective, link.range), @"%@ attributed over %@, link is %@", link.URL, NSStringFromRange(effective), NSStringFromRange(link.range));
	}
}

// Asking the same scanner twice is what the framework's own stress tests do.
- (void)testLinkifiedStringGivesTheSameAnswerTwice
{
	AHHyperlinkScanner *scanner = [AHHyperlinkScanner hyperlinkScannerWithString:@"see https://example.com/ now"];
	XCTAssertEqualObjects([scanner linkifiedString], [scanner linkifiedString]);
}

/* The header promises linkifiedString "scans the stored string", so like allURIs it starts
 * from the beginning whatever nextURI has already handed out. Adium never reads a scanner
 * both ways; the test keeps the two accessors agreeing. */
- (void)testLinkifiedStringCoversTheWholeStringAfterNextURIHasBeenCalled
{
	AHHyperlinkScanner *scanner = [AHHyperlinkScanner hyperlinkScannerWithString:@"http://a.example/ and http://b.example/"];
	[scanner nextURI];
	NSAttributedString *linkified = [scanner linkifiedString];
	XCTAssertEqualObjects([linkified attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL], [NSURL URLWithString:@"http://a.example/"]);
	XCTAssertEqualObjects([linkified attribute:NSLinkAttributeName atIndex:22 effectiveRange:NULL], [NSURL URLWithString:@"http://b.example/"]);
}

#pragma mark Fast enumeration

/* The regression test for the crash in countByEnumeratingWithState: the scanner once handed
 * out links it did not keep alive, so the loop body read freed objects once the autorelease
 * pool that had kept them by accident was gone. Many links, more than one stack buffer's worth,
 * each one touched inside the loop and again after it, inside a pool of their own. */
- (void)testFastEnumerationHandsOutEveryLinkAlive
{
	NSUInteger count = 200;
	NSString *text = [self textWithLinks:count];
	NSMutableArray *kept = [NSMutableArray array];
	@autoreleasepool {
		AHHyperlinkScanner *scanner = [AHHyperlinkScanner hyperlinkScannerWithString:text];
		NSUInteger i = 0;
		for (AHMarkedHyperlink *link in scanner) {
			NSString *expected = [NSString stringWithFormat:@"http://host%lu.example/p%lu", (unsigned long)i, (unsigned long)i];
			XCTAssertEqualObjects(link.URL.absoluteString, expected);
			XCTAssertTrue(NSMaxRange(link.range) <= text.length, @"range %@ outside the string", NSStringFromRange(link.range));
			XCTAssertEqualObjects([text substringWithRange:link.range], expected);
			[kept addObject:link];
			i++;
		}
		XCTAssertEqual(i, count);
	}
	XCTAssertEqual(kept.count, count);
	NSUInteger i = 0;
	for (AHMarkedHyperlink *link in kept) {
		XCTAssertEqualObjects(link.URL.host, ([NSString stringWithFormat:@"host%lu.example", (unsigned long)i]));
		XCTAssertEqualObjects(link.parentString, text);
		i++;
	}
}

- (void)testFastEnumerationYieldsTheSameLinksAsAllURIs
{
	NSString *text = [self textWithLinks:50];
	NSArray *collected = [[AHHyperlinkScanner hyperlinkScannerWithString:text] allURIs];
	NSMutableArray *enumerated = [NSMutableArray array];
	for (AHMarkedHyperlink *link in [AHHyperlinkScanner hyperlinkScannerWithString:text])
		[enumerated addObject:link];
	XCTAssertEqual(enumerated.count, collected.count);
	for (NSUInteger i = 0; i < MIN(enumerated.count, collected.count); i++) {
		XCTAssertEqualObjects([enumerated[i] URL], [collected[i] URL]);
		XCTAssertTrue(NSEqualRanges([enumerated[i] range], [collected[i] range]), @"link %lu", (unsigned long)i);
	}
}

- (void)testFastEnumerationOverAStringWithoutLinksRunsNoIterations
{
	NSUInteger iterations = 0;
	for (AHMarkedHyperlink *link in [AHHyperlinkScanner hyperlinkScannerWithString:@"nothing to see here"]) {
		(void)link;
		iterations++;
	}
	XCTAssertEqual(iterations, (NSUInteger)0);
}

- (void)testBreakingOutOfFastEnumerationIsSafe
{
	NSString *text = [self textWithLinks:30];
	AHMarkedHyperlink *second = nil;
	NSUInteger seen = 0;
	for (AHMarkedHyperlink *link in [AHHyperlinkScanner hyperlinkScannerWithString:text]) {
		if (++seen == 2) {
			second = link;
			break;
		}
	}
	XCTAssertEqual(seen, (NSUInteger)2);
	XCTAssertEqualObjects(second.URL.absoluteString, @"http://host1.example/p1");
}

@end
