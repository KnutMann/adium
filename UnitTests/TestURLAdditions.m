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
#import <AIUtilities/AIURLAdditions.h>

@interface TestURLAdditions : XCTestCase
@end

@implementation TestURLAdditions

- (NSURL *)URLWithQuery:(NSString *)query
{
	return [NSURL URLWithString:[@"http://example.com/path?" stringByAppendingString:query]];
}

- (void)testLengthIsThatOfTheAbsoluteString
{
	NSURL *url = [NSURL URLWithString:@"http://example.com/"];
	XCTAssertEqual([url length], (NSUInteger)19);
}

- (void)testLengthOfRelativeURLCountsTheResolvedString
{
	NSURL *url = [NSURL URLWithString:@"b" relativeToURL:[NSURL URLWithString:@"http://example.com/a/"]];
	XCTAssertEqual([url length], [@"http://example.com/a/b" length]);
}

- (void)testFindsTheArgumentForAKey
{
	XCTAssertEqualObjects([[self URLWithQuery:@"a=1&b=2&c=3"] queryArgumentForKey:@"b"], @"2");
}

- (void)testFindsTheFirstAndLastArguments
{
	NSURL *url = [self URLWithQuery:@"a=1&b=2&c=3"];
	XCTAssertEqualObjects([url queryArgumentForKey:@"a"], @"1");
	XCTAssertEqualObjects([url queryArgumentForKey:@"c"], @"3");
}

- (void)testMissingKeyIsNil
{
	XCTAssertNil([[self URLWithQuery:@"a=1&b=2"] queryArgumentForKey:@"z"]);
}

- (void)testURLWithoutQueryIsNil
{
	XCTAssertNil([[NSURL URLWithString:@"http://example.com/path"] queryArgumentForKey:@"a"]);
}

- (void)testKeyMustMatchWholeNotAsPrefix
{
	NSURL *url = [self URLWithQuery:@"ab=1&a=2&abc=3"];
	XCTAssertEqualObjects([url queryArgumentForKey:@"a"], @"2");
	XCTAssertEqualObjects([url queryArgumentForKey:@"abc"], @"3");
}

- (void)testEmptyValueIsAnEmptyString
{
	XCTAssertEqualObjects([[self URLWithQuery:@"a=&b=2"] queryArgumentForKey:@"a"], @"");
}

- (void)testKeyWithoutEqualsSignHasNoArgument
{
	XCTAssertNil([[self URLWithQuery:@"flag&b=2"] queryArgumentForKey:@"flag"]);
}

- (void)testFirstOccurrenceOfARepeatedKeyWins
{
	XCTAssertEqualObjects([[self URLWithQuery:@"a=1&a=2"] queryArgumentForKey:@"a"], @"1");
}

- (void)testSemicolonDelimitersAreDetected
{
	NSURL *url = [self URLWithQuery:@"a=1;b=2;c=3"];
	XCTAssertEqualObjects([url queryArgumentForKey:@"b"], @"2");
	XCTAssertEqualObjects([url queryArgumentForKey:@"c"], @"3");
}

- (void)testExplicitDelimiterIsUsed
{
	NSURL *url = [self URLWithQuery:@"a=1,b=2"];
	XCTAssertEqualObjects([url queryArgumentForKey:@"b" withDelimiter:@","], @"2");
	XCTAssertNil([url queryArgumentForKey:@"b" withDelimiter:@"&"]);
}

- (void)testPercentAndPlusEscapesAreLeftToTheCaller
{
	XCTAssertEqualObjects([[self URLWithQuery:@"q=a%20b+c"] queryArgumentForKey:@"q"], @"a%20b+c");
}

- (void)testValueContainingAnEqualsSignIsReturnedWhole
{
	XCTAssertEqualObjects([[self URLWithQuery:@"token=abc=="] queryArgumentForKey:@"token"], @"abc==");
}

- (void)testKeyLookupIsCaseSensitiveAsTheHeaderSays
{
	NSURL *url = [self URLWithQuery:@"Key=upper&key=lower"];
	XCTAssertEqualObjects([url queryArgumentForKey:@"key"], @"lower");
	XCTAssertNil([url queryArgumentForKey:@"KEY"]);
}

@end
