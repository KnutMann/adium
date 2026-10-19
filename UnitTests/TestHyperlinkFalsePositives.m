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

/* Text that looks a little like a link and must not become one. Every case here is one a
 * person types in a chat without meaning a web address. Cases whose verdict depends on which
 * applications are installed (a word before a colon is a "tentative" scheme the scanner asks
 * Launch Services about) are left out, because they would pass or fail by machine. */
@interface TestHyperlinkFalsePositives : XCTestCase
@end

@implementation TestHyperlinkFalsePositives

- (void)assertNoLinkIn:(NSString *)string
{
	NSArray *links = [[AHHyperlinkScanner hyperlinkScannerWithString:string] allURIs];
	XCTAssertEqual(links.count, (NSUInteger)0, @"\"%@\" produced %@", string, [links valueForKey:@"URL"]);
}

- (void)testVersionNumberIsNotALink
{
	[self assertNoLinkIn:@"version 3.14.2 is out"];
}

- (void)testFourPartVersionNumberIsNotALink
{
	[self assertNoLinkIn:@"version 1.2.3.4 is out"];
}

- (void)testDecimalNumberIsNotALink
{
	[self assertNoLinkIn:@"pi is 3.14159"];
	[self assertNoLinkIn:@"3.14"];
}

- (void)testNumberWithThousandsSeparatorsIsNotALink
{
	[self assertNoLinkIn:@"1.000.000 euro"];
}

- (void)testTimeOfDayIsNotALink
{
	[self assertNoLinkIn:@"at 12:30 sharp"];
	[self assertNoLinkIn:@"12:30pm"];
	[self assertNoLinkIn:@"from 09:00 to 17:30."];
}

- (void)testLatinAbbreviationsAreNotLinks
{
	[self assertNoLinkIn:@"e.g. this"];
	[self assertNoLinkIn:@"i.e., that"];
	[self assertNoLinkIn:@"a.k.a. Bob"];
}

/* ".md" is also Moldova's country code, which is why the lexer takes the bait. A file name
 * in a chat is still a file name. */
- (void)testFileNameWithMarkdownExtensionIsNotALink
{
	XCTExpectFailure(@"AHLinkLexer.l:75 urlSpec links any word.ccTLD; README.md becomes http://README.md");
	[self assertNoLinkIn:@"read README.md first"];
}

- (void)testScriptFileNamesAreNotLinks
{
	XCTExpectFailure(@"AHLinkLexer.l:75, same rule: .sh is Saint Helena and .py is Paraguay");
	[self assertNoLinkIn:@"run build.sh then setup.py"];
}

- (void)testMentionIsNotALink
{
	[self assertNoLinkIn:@"@adium hi"];
}

- (void)testJabberIDWithAResourceIsNotALink
{
	[self assertNoLinkIn:@"jdoe@jabber.org/Adium"];
}

- (void)testEllipsisBetweenWordsIsNotALink
{
	[self assertNoLinkIn:@"wait...com"];
	[self assertNoLinkIn:@"so...then"];
}

- (void)testWordsJoinedByAPeriodWithoutATopLevelDomainAreNotALink
{
	[self assertNoLinkIn:@"etc.etc"];
	[self assertNoLinkIn:@"foo.bar"];
}

- (void)testSchemeWithoutAHostIsNotALink
{
	[self assertNoLinkIn:@"see http:// here"];
	[self assertNoLinkIn:@"https://"];
}

- (void)testSentenceWithoutAnyLinkHasNone
{
	[self assertNoLinkIn:@"Nullam porta. Praesent turpis velit, sagittis non, volutpat quis, lacinia eu, ipsum."];
}

@end
