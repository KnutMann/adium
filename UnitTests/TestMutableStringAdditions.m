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
#import "TestMutableStringAdditions.h"
#import "AIUnitTestUtilities.h"

#import <AIUtilities/AIMutableStringAdditions.h>

@implementation TestMutableStringAdditions

- (void)testReplaceOccurrencesOfString_withString_options
{
	NSMutableString *testString = [NSMutableString stringWithString:@"The quick brown fox jumped over the other quick brown fox"];
	
	//first make the string longer
	[testString replaceOccurrencesOfString:@"brown" withString:@"kinda lime-green with a bit of ecru" options:NSLiteralSearch];
	AISimplifiedAssertEqualObjects([NSMutableString stringWithString:@"The quick kinda lime-green with a bit of ecru fox jumped over the other quick kinda lime-green with a bit of ecru fox"], 
								   testString, 
								   @"Modified string wasn't equal to hand-made modified string");
	
	//next, try replacing something at the end; if the range didn't expand, this will fail
	[testString replaceOccurrencesOfString:@"fox" withString:@"aardvark" options:NSLiteralSearch];
	AISimplifiedAssertEqualObjects([NSMutableString stringWithString:@"The quick kinda lime-green with a bit of ecru aardvark jumped over the other quick kinda lime-green with a bit of ecru aardvark"], 
								   testString, 
								   @"After making the string longer, modifications no longer took into account the full length");
}

- (void)testMutableStringReturnsTheReceiver
{
	NSMutableString *string = [NSMutableString stringWithString:@"x"];
	XCTAssertTrue([string mutableString] == string);
}

#pragma mark Replacing

- (void)testReplaceOccurrencesReturnsHowManyWereReplaced
{
	NSMutableString *string = [NSMutableString stringWithString:@"a-b-c"];
	XCTAssertEqual([string replaceOccurrencesOfString:@"-" withString:@"+" options:NSLiteralSearch], (NSUInteger)2);
	XCTAssertEqualObjects(string, @"a+b+c");
}

- (void)testReplaceOccurrencesOfAnAbsentStringChangesNothing
{
	NSMutableString *string = [NSMutableString stringWithString:@"abc"];
	XCTAssertEqual([string replaceOccurrencesOfString:@"x" withString:@"y" options:NSLiteralSearch], (NSUInteger)0);
	XCTAssertEqualObjects(string, @"abc");
}

- (void)testReplaceOccurrencesHonoursTheOptions
{
	NSMutableString *string = [NSMutableString stringWithString:@"Ab ab AB"];
	XCTAssertEqual([string replaceOccurrencesOfString:@"ab" withString:@"x" options:NSCaseInsensitiveSearch], (NSUInteger)3);
	XCTAssertEqualObjects(string, @"x x x");
}

- (void)testReplaceOccurrencesWithAShorterStringCoversTheWholeString
{
	NSMutableString *string = [NSMutableString stringWithString:@"aaaa"];
	XCTAssertEqual([string replaceOccurrencesOfString:@"aa" withString:@"a" options:NSLiteralSearch], (NSUInteger)2);
	XCTAssertEqualObjects(string, @"aa");
}

- (void)testReplaceOccurrencesOnTheEmptyString
{
	NSMutableString *string = [NSMutableString string];
	XCTAssertEqual([string replaceOccurrencesOfString:@"a" withString:@"b" options:NSLiteralSearch], (NSUInteger)0);
	XCTAssertEqualObjects(string, @"");
}

#pragma mark Newlines to slashes

- (NSString *)slashed:(NSString *)input
{
	NSMutableString *string = [input mutableCopy];
	[string convertNewlinesToSlashes];
	return string;
}

- (void)testLineFeedBecomesASlash
{
	XCTAssertEqualObjects([self slashed:@"a\nb"], @"a / b");
}

- (void)testCarriageReturnBecomesASlash
{
	XCTAssertEqualObjects([self slashed:@"a\rb"], @"a / b");
}

- (void)testCRLFBecomesOneSlash
{
	XCTAssertEqualObjects([self slashed:@"a\r\nb"], @"a / b");
}

- (void)testRepeatedLineFeedsBecomeOneSlash
{
	XCTAssertEqualObjects([self slashed:@"a\n\n\nb"], @"a / b");
}

- (void)testRepeatedCarriageReturnsBecomeOneSlash
{
	XCTAssertEqualObjects([self slashed:@"a\r\rb"], @"a / b");
}

- (void)testRepeatedCRLFsBecomeOneSlash
{
	XCTAssertEqualObjects([self slashed:@"a\r\n\r\nb"], @"a / b");
}

- (void)testEveryLineGetsASlash
{
	XCTAssertEqualObjects([self slashed:@"a\nb\nc"], @"a / b / c");
}

- (void)testTrailingLineBreakLeavesATrailingSlash
{
	XCTAssertEqualObjects([self slashed:@"a\n"], @"a / ");
}

- (void)testStringWithoutLineBreaksIsUnchanged
{
	XCTAssertEqualObjects([self slashed:@"no breaks here"], @"no breaks here");
	XCTAssertEqualObjects([self slashed:@""], @"");
}

#pragma mark ASCII files

- (void)testStringWithContentsOfASCIIFileReadsAMutableString
{
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"TestMutableStringAdditions-%@.txt", [[NSUUID UUID] UUIDString]]];
	XCTAssertTrue([[NSData dataWithBytes:"plain ascii" length:11] writeToFile:path atomically:YES]);

	NSMutableString *string = [NSMutableString stringWithContentsOfASCIIFile:path];
	XCTAssertEqualObjects(string, @"plain ascii");
	XCTAssertTrue([string isKindOfClass:[NSMutableString class]]);
	[string appendString:@"!"];
	XCTAssertEqualObjects(string, @"plain ascii!");

	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (void)testStringWithContentsOfAMissingASCIIFileIsNil
{
	NSString *missing = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"TestMutableStringAdditions-missing-%@", [[NSUUID UUID] UUIDString]]];
	XCTAssertNil([NSMutableString stringWithContentsOfASCIIFile:missing]);
}

@end
