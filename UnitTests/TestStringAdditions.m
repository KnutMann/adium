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
#import "TestStringAdditions.h"
#import "AIUnitTestUtilities.h"

#import <AIUtilities/AIStringAdditions.h>

#import <limits.h>

@implementation TestStringAdditions

- (void)testRandomStringOfLength
{
	//Test at least two different lengths, and see what happens when we ask for 0.
	NSString *str = [NSString randomStringOfLength:6];
	XCTAssertEqual([str length], (NSUInteger)6U, @"+randomStringOfLength:6 did not return a 6-character string; it returned \"%@\", which is %lu characters", str, (unsigned long)[str length]);
	str = [NSString randomStringOfLength:12];
	XCTAssertEqual([str length], (NSUInteger)12U, @"+randomStringOfLength:12 did not return a 12-character string; it returned \"%@\", which is %lu characters", str, (unsigned long)[str length]);
	str = [NSString randomStringOfLength:0];
	XCTAssertEqual([str length], (NSUInteger)0U, @"+randomStringOfLength:0 did not return a 0-character string; it returned \"%@\", which is %lu characters", str, (unsigned long)[str length]);
}
- (void)testStringWithContentsOfUTF8File
{
	//Our octest file contains a sample file to read in testing this method.
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSString *pathToFile = [bundle pathForResource:@"UTF8Snowman" ofType:@"txt"];

	char snowmanUTF8[4] = { 0xe2, 0x98, 0x83, 0 };
	NSString *snowman = [NSString stringWithUTF8String:snowmanUTF8];
	NSString *snowmanFromFile = [NSString stringWithContentsOfUTF8File:pathToFile];
	AISimplifiedAssertEqualObjects(snowman, snowmanFromFile, @"+stringWithContentsOfUTF8File: incorrectly read the file");
}
- (void)testMutableStringWithContentsOfUTF8File
{
	//Our octest file contains a sample file to read in testing this method.
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSString *pathToFile = [bundle pathForResource:@"UTF8Snowman" ofType:@"txt"];

	char snowmanUTF8[4] = { 0xe2, 0x98, 0x83, 0 };
	NSString *snowman = [NSString stringWithUTF8String:snowmanUTF8];
	NSMutableString *snowmanFromFile = [NSMutableString stringWithContentsOfUTF8File:pathToFile];
	AISimplifiedAssertEqualObjects(snowman, snowmanFromFile, @"+stringWithContentsOfUTF8File: incorrectly read the file");
	XCTAssertTrue([snowmanFromFile isKindOfClass:[NSMutableString class]], @"Sending +stringWithContentsOfUTF8File: to NSMutableString should result in a mutable string");
}
- (void)testEllipsis
{
	XCTAssertEqual([[NSString ellipsis] length], (NSUInteger)1U, @"+ellipsis did not return a 1-character string; it returned \"%@\"", [NSString ellipsis]);
	XCTAssertEqual((NSUInteger)[[NSString ellipsis] characterAtIndex:0U], (NSUInteger)0x2026U, @"+ellipsis did not return a horizontal ellipsis (U+2026); it returned \"%@\" instead", [NSString ellipsis]);
}
- (void)testMutableEllipsis
{
	XCTAssertEqual([[NSMutableString ellipsis] length], (NSUInteger)1U, @"+ellipsis did not return a 1-character string; it returned \"%@\"", [NSString ellipsis]);
	XCTAssertEqual((NSUInteger)[[NSMutableString ellipsis] characterAtIndex:0U], (NSUInteger)0x2026U, @"+ellipsis did not return a horizontal ellipsis (U+2026); it returned \"%@\" instead", [NSString ellipsis]);
	XCTAssertTrue([[NSMutableString ellipsis] isKindOfClass:[NSMutableString class]], @"Sending +ellipsis to NSMutableString should result in a mutable string");
}
- (void)testStringByAppendingEllipsis
{
	NSString *before = @"Foo";
	NSString *after  = [before stringByAppendingEllipsis];
	XCTAssertEqual(([after length] - [before length]), (NSUInteger)1U, @"Appending a single character should result in a string that is one character longer. before is \"%@\"; after is \"%@\"", before, after);
	XCTAssertTrue([after hasSuffix:[NSString ellipsis]], @"String formed by appending [NSString ellipsis] should end with [NSString ellipsis]. before is \"%@\"; after is \"%@\"", before, after);
}
- (void)testCompactedString
{
	AISimplifiedAssertEqualObjects([@"FOO" compactedString], @"foo", @"-compactedString should lowercase an all-uppercase string");
	AISimplifiedAssertEqualObjects([@"Foo" compactedString], @"foo", @"-compactedString should lowercase a mixed-case string");
	AISimplifiedAssertEqualObjects([@"foo" compactedString], @"foo", @"-compactedString should do nothing to an all-lowercase string");
	AISimplifiedAssertEqualObjects([@"foo bar" compactedString], @"foobar", @"-compactedString should remove spaces");
}
- (void)testStringWithEllipsisByTruncatingToLength
{
	NSString *before = @"Foo";
	NSString *after;

	//First, try truncating to a greater length.
	after = [before stringWithEllipsisByTruncatingToLength:[before length] + 1];
	XCTAssertEqualObjects(before, after, @"Truncating to a length greater than that of the string being truncated should not change the string. before is \"%@\"; after is \"%@\"", before, after);

	//Second, try truncating to the same length.
	after = [before stringWithEllipsisByTruncatingToLength:[before length]];
	XCTAssertEqualObjects(before, after, @"Truncating to a length equal to that of the string being truncated should not change the string. before is \"%@\"; after is \"%@\"", before, after);

	//Third, try truncating to a shorter length. This one should actually truncate the string and append an ellipsis.
	after = [before stringWithEllipsisByTruncatingToLength:[before length] - 1];
	XCTAssertEqual(([before length] - [after length]), (NSUInteger)1U, @"Appending a single character should result in a string that is one character longer. before is \"%@\"; after is \"%@\"", before, after);
	//The part before the ellipsis in after should be equal to the same portion of before.
	NSUInteger cutHere = [after length] - 1;
	XCTAssertEqualObjects([after  substringToIndex:cutHere - 1],
	                     [before substringToIndex:cutHere - 1],
						 @"Truncating a string should not result in any changes before the truncation point before is \"%@\"; after is \"%@\"", before, after);
	XCTAssertTrue([after hasSuffix:[NSString ellipsis]], @"String formed by appending [NSString ellipsis] should end with [NSString ellipsis]. before is \"%@\"; after is \"%@\"", before, after);
}
- (void)testIdentityMethod
{
	NSString *str = @"Foo";
	XCTAssertIdentical([str string], str, @"A method that returns itself must, by definition, return itself.");
}
- (void)testXMLEscaping
{
	NSString *originalXMLSource = @"<rel-date><number>Four score</number> &amp; <number>seven</number> years ago</rel-date>";
	NSString *escaped = [originalXMLSource stringByEscapingForXMLWithEntities:nil];
	NSString *unescaped = [escaped stringByUnescapingFromXMLWithEntities:nil];
	XCTAssertEqualObjects(originalXMLSource, unescaped, @"Round trip through scaping + unescaping did not preserve the original string.");
}
- (void)testEscapingForShell
{
	//Whitespace should be replaced by '\' followed by a character (one of [atnfr] for most of them; space simply puts a \ in front of the space).
	XCTAssertEqualObjects([@"\a" stringByEscapingForShell], @"\\a", @"-stringByEscapingForShell didn't properly escape the alert (bell) character");
	XCTAssertEqualObjects([@"\t" stringByEscapingForShell], @"\\t", @"-stringByEscapingForShell didn't properly escape the horizontal tab character");
	XCTAssertEqualObjects([@"\n" stringByEscapingForShell], @"\\n", @"-stringByEscapingForShell didn't properly escape the line-feed character");
	XCTAssertEqualObjects([@"\v" stringByEscapingForShell], @"\\v", @"-stringByEscapingForShell didn't properly escape the vertical tab character");
	XCTAssertEqualObjects([@"\f" stringByEscapingForShell], @"\\f", @"-stringByEscapingForShell didn't properly escape the form-feed character");
	XCTAssertEqualObjects([@"\r" stringByEscapingForShell], @"\\r", @"-stringByEscapingForShell didn't properly escape the carriage-return character");
	XCTAssertEqualObjects([@" "  stringByEscapingForShell], @"\\ ", @"-stringByEscapingForShell didn't properly escape the space character");

	//Other unsafe characters are simply backslash-escaped.
	XCTAssertEqualObjects([@"\\" stringByEscapingForShell], @"\\\\", @"-stringByEscapingForShell didn't properly escape the backslash character");
	XCTAssertEqualObjects([@"'" stringByEscapingForShell], @"\\'", @"-stringByEscapingForShell didn't properly escape the apostrophe/single-quotation-mark character");
	XCTAssertEqualObjects([@"\"" stringByEscapingForShell], @"\\\"", @"-stringByEscapingForShell didn't properly escape the quotation-mark character");
	XCTAssertEqualObjects([@"`" stringByEscapingForShell], @"\\`", @"-stringByEscapingForShell didn't properly escape the backquote character");
	XCTAssertEqualObjects([@"!" stringByEscapingForShell], @"\\!", @"-stringByEscapingForShell didn't properly escape the bang character");
	XCTAssertEqualObjects([@"$" stringByEscapingForShell], @"\\$", @"-stringByEscapingForShell didn't properly escape the dollar-sign character");
	XCTAssertEqualObjects([@"&"  stringByEscapingForShell], @"\\&", @"-stringByEscapingForShell didn't properly escape the ampersand character");
	XCTAssertEqualObjects([@"|"  stringByEscapingForShell], @"\\|", @"-stringByEscapingForShell didn't properly escape the pipe character");
}
- (void)testVolumePath
{
	XCTAssertEqualObjects([@"/" volumePath], @"/", @"Volume path of / is \"%@\", not /", [@"/" volumePath]);

	//Get the name of the startup volume, so that we can attempt to get the volume path of (what we hope is) a directory on it.
	NSString *volumeName = nil;
	NSError *error = nil;
	BOOL gotVolumeName = [[NSURL fileURLWithPath:@"/"] getResourceValue:&volumeName forKey:NSURLVolumeNameKey error:&error];
	XCTAssertTrue(gotVolumeName, @"Error while attempting to determine the name of the startup volume: %@", error);

	NSString *inputPath = [[@"/Volumes" stringByAppendingPathComponent:volumeName] stringByAppendingPathComponent:@"Applications"];
	NSString *outputPath = [inputPath volumePath];

	XCTAssertEqualObjects(outputPath, @"/", @"The volume path of %@ should be /; instead, it was \"%@\"", inputPath, outputPath);
}

- (void)testRangeOfLineBreakCharacterInRange
{
	NSRange searchRange = { 2U, 3U };
	XCTAssertEqualObjects([@"foo\nbar" substringWithRange:searchRange], @"o\nb", @"Search range returned an unexpected substring");

	NSRange range;

	//No line-break
	range = [@"foo bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that doesn't have one, should return a location of NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that doesn't have one, should return a length of 0");

	//Line feed
	range = [@"foo\nbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line feed, should return the location of the line feed");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line feed, should return a length of 1");

	//Form feed
	range = [@"foo\fbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a form feed, should return the location of the form feed");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a form feed, should return a length of 1");

	//Carriage return
	range = [@"foo\rbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a carriage return, should return the location of the carriage return");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a carriage return, should return a length of 1");

	//CRLF sequence
	range = [@"foo\r\nbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a CRLF sequence, should return the location of the carriage return");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)2U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a CRLF sequence, should return a length of 2");

	//Next line
	range = [[NSString stringWithUTF8String:"foo\xc2\x85""bar"] rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a next line, should return the location of the next line");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a next line, should return a length of 1");

	//Line separator
	range = [@"foo\u2028bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line separator, should return the location of the line separator");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line separator, should return a length of 1");

	//Paragraph separator
	range = [@"foo\u2029bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a paragraph separator, should return the location of the paragraph separator");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a paragraph separator, should return a length of 1");
}
- (void)testRangeOfLineBreakCharacterInEmptyRange
{
	NSRange searchRange = { 3U, 0U }; //3 being the index of the line-break
	XCTAssertEqualObjects([@"foo\nbar" substringWithRange:searchRange], @"", @"Search range returned an unexpected substring");

	NSRange range;

	//No line-break
	range = [@"foo bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that doesn't have one, should return a location of NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that doesn't have one, should return a length of 0");

	//Line feed
	range = [@"foo\nbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line feed, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line feed, should return a length of 0");

	//Form feed
	range = [@"foo\fbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a form feed, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a form feed, should return a length of 0");

	//Carriage return
	range = [@"foo\rbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a carriage return, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a carriage return, should return a length of 0");

	//CRLF sequence
	range = [@"foo\r\nbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a CRLF sequence, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a CRLF sequence, should return a length of 0");

	//Next line
	range = [@"foo\xc2\x85""bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a next line, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a next line, should return a length of 0");

	//Line separator
	range = [@"foo\u2028bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line separator, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line separator, should return a length of 0");

	//Paragraph separator
	range = [@"foo\u2029bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a paragraph separator, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a paragraph separator, should return a length of 0");
}
- (void)testRangeOfLineBreakCharacterInRangeNotContainingLineBreakCharacter
{
	NSRange searchRange = { 4U, 3U };
	XCTAssertEqualObjects([@"foo\nbar" substringWithRange:searchRange], @"bar", @"Search range returned an unexpected substring");
	NSRange searchRangeForCRLF = { searchRange.location + 1U, searchRange.length };
	XCTAssertEqualObjects([@"foo\r\nbar" substringWithRange:searchRangeForCRLF], @"bar", @"Search range (for CRLF)returned an unexpected substring");

	NSRange range;

	//No line-break
	range = [@"foo bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that doesn't have one, should return a location of NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that doesn't have one, should return a length of 0");

	//Line feed
	range = [@"foo\nbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line feed, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line feed, should return a length of 0");

	//Form feed
	range = [@"foo\fbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a form feed, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a form feed, should return a length of 0");

	//Carriage return
	range = [@"foo\rbar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a carriage return, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a carriage return, should return a length of 0");

	//CRLF sequence
	range = [@"foo\r\nbar" rangeOfLineBreakCharacterInRange:searchRangeForCRLF];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a CRLF sequence, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a CRLF sequence, should return a length of 0");

	//Next line
	range = [@"foo\xc2\x85""bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a next line, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a next line, should return a length of 0");

	//Line separator
	range = [@"foo\u2028bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line separator, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a line separator, should return a length of 0");

	//Paragraph separator
	range = [@"foo\u2029bar" rangeOfLineBreakCharacterInRange:searchRange];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a paragraph separator, should return NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterInRange:, sent to a string that contains a paragraph separator, should return a length of 0");
}
- (void)testRangeOfLineBreakCharacterInPartiallyInvalidRange
{
	NSRange searchRange = { 5U, 3U }; //"arX" (where X = outside the string)
	XCTAssertThrowsSpecificNamed([@"foo\nbar" rangeOfLineBreakCharacterInRange:searchRange], NSException, NSRangeException, @"-rangeOfLineBreakCharacterInRange:, with a range that is partially outside the receiver string, should throw NSRangeException");
}
- (void)testRangeOfLineBreakCharacterInInvalidRange
{
	NSRange searchRange = { 12U, 3U }; //Length of @"foo\nbar": 7; 12 > 7, so the range is wholly invalid
	XCTAssertThrowsSpecificNamed([@"foo\nbar" rangeOfLineBreakCharacterInRange:searchRange], NSException, NSRangeException, @"-rangeOfLineBreakCharacterInRange:, with a range that is wholly outside the receiver string, should throw NSRangeException");
}
- (void)testRangeOfLineBreakCharacterFromIndex
{
	XCTAssertEqualObjects([@"foo\nbar" substringFromIndex:3U], @"\nbar", @"Search range returned an unexpected substring");

	NSRange range;

	//No line-break
	range = [@"foo bar" rangeOfLineBreakCharacterFromIndex:3U];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that doesn't have one, should return a location of NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that doesn't have one, should return a length of 0");

	//Line feed
	range = [@"foo\nbar" rangeOfLineBreakCharacterFromIndex:3U];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a line feed, should return the location of the line feed");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a line feed, should return a length of 1");

	//Form feed
	range = [@"foo\fbar" rangeOfLineBreakCharacterFromIndex:3U];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a form feed, should return the location of the form feed");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a form feed, should return a length of 1");

	//Carriage return
	range = [@"foo\rbar" rangeOfLineBreakCharacterFromIndex:3U];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a carriage return, should return the location of the carriage return");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a carriage return, should return a length of 1");

	//CRLF sequence
	range = [@"foo\r\nbar" rangeOfLineBreakCharacterFromIndex:3U];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a CRLF sequence, should return the location of the carriage return");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)2U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a CRLF sequence, should return a length of 2");

	//Next line
	range = [@"foo\xc2\x85""bar" rangeOfLineBreakCharacterFromIndex:3U];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a next line, should return the location of the next line");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a next line, should return a length of 1");

	//Line separator
	range = [@"foo\u2028bar" rangeOfLineBreakCharacterFromIndex:3U];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a line separator, should return the location of the line separator");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a line separator, should return a length of 1");

	//Paragraph separator
	range = [@"foo\u2029bar" rangeOfLineBreakCharacterFromIndex:3U];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a paragraph separator, should return the location of the paragraph separator");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacterFromIndex:, sent to a string that contains a paragraph separator, should return a length of 1");
}
- (void)testRangeOfLineBreakCharacterFromInvalidIndex
{
	NSUInteger startIdx = 7U; //Length of @"foo\nbar": 7, so this index is just outside the string (last valid index: 6).
	XCTAssertThrowsSpecificNamed([@"foo\nbar" rangeOfLineBreakCharacterFromIndex:startIdx], NSException, NSRangeException, @"-rangeOfLineBreakCharacterFromIndex:, with a start index that is outside the receiver string, should throw NSRangeException");
}
- (void)testRangeOfLineBreakCharacter
{
	NSRange range;

	//No line-break
	range = [@"foo bar" rangeOfLineBreakCharacter];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacter, sent to a string that doesn't have one, should return a location of NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacter, sent to a string that doesn't have one, should return a length of 0");

	//Line feed
	range = [@"foo\nbar" rangeOfLineBreakCharacter];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacter, sent to a string that contains a line feed, should return the location of the line feed");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacter, sent to a string that contains a line feed, should return a length of 1");

	//Form feed
	range = [@"foo\fbar" rangeOfLineBreakCharacter];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacter, sent to a string that contains a form feed, should return the location of the form feed");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacter, sent to a string that contains a form feed, should return a length of 1");

	//Carriage return
	range = [@"foo\rbar" rangeOfLineBreakCharacter];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacter, sent to a string that contains a carriage return, should return the location of the carriage return");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacter, sent to a string that contains a carriage return, should return a length of 1");

	//CRLF sequence
	range = [@"foo\r\nbar" rangeOfLineBreakCharacter];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacter, sent to a string that contains a CRLF sequence, should return the location of the carriage return");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)2U, @"-rangeOfLineBreakCharacter, sent to a string that contains a CRLF sequence, should return a length of 2");

	//Next line
	range = [@"foo\xc2\x85""bar" rangeOfLineBreakCharacter];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacter, sent to a string that contains a next line, should return the location of the next line");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacter, sent to a string that contains a next line, should return a length of 1");

	//Line separator
	range = [@"foo\u2028bar" rangeOfLineBreakCharacter];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacter, sent to a string that contains a line separator, should return the location of the line separator");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacter, sent to a string that contains a line separator, should return a length of 1");

	//Paragraph separator
	range = [@"foo\u2029bar" rangeOfLineBreakCharacter];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)3U, @"-rangeOfLineBreakCharacter, sent to a string that contains a paragraph separator, should return the location of the paragraph separator");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)1U, @"-rangeOfLineBreakCharacter, sent to a string that contains a paragraph separator, should return a length of 1");
}
- (void)testRangeOfLineBreakCharacterInEmptyString
{
	NSRange range = [@"" rangeOfLineBreakCharacter];
	XCTAssertEqual((NSUInteger)range.location, (NSUInteger)NSNotFound, @"-rangeOfLineBreakCharacter, sent to an empty string, should return a location of NSNotFound");
	XCTAssertEqual((NSUInteger)range.length, (NSUInteger)0U, @"-rangeOfLineBreakCharacter, sent to an empty string, should return a length of 0");
}

- (void)testAllLinesWithSeparator
{
	NSString *str = @"Foo\nbar\nbaz";
	NSArray *linesWithSep = [str allLinesWithSeparator:@"Qux"];
	NSArray *expectedLines = [NSArray arrayWithObjects:@"Foo", @"Qux", @"bar", @"Qux", @"baz", nil];
	AISimplifiedAssertEqualObjects(linesWithSep, expectedLines, @"allLinesWithSeparator: did not properly split and splice the array");

	NSArray *lines = [str allLinesWithSeparator:nil];
	expectedLines = [NSArray arrayWithObjects:@"Foo", @"bar", @"baz", nil];
	AISimplifiedAssertEqualObjects(lines, expectedLines, @"allLinesWithSeparator: did not properly split the array");
}
- (void)testAllLines
{
	NSString *str = @"Foo\nbar\nbaz";
	NSArray *lines = [str allLines];
	NSArray *expectedLines = [NSArray arrayWithObjects:@"Foo", @"bar", @"baz", nil];
	AISimplifiedAssertEqualObjects(lines, expectedLines, @"allLines did not properly split the array");
}

- (void) testCaseInsensitivelyEqualToSameString {
	NSString *str = @"Adium rocks!";
	NSString *other = [NSMutableString stringWithString:str]; //Using NSMutableString guarantees that we won't simply get the same immutable string.
	XCTAssertTrue([str isCaseInsensitivelyEqualToString:other], @"string should be equal to itself!");
}
- (void) testCaseInsensitivelyEqualToSameStringInUppercase {
	NSString *str = @"Adium rocks!";
	NSString *other = [str uppercaseString];
	XCTAssertTrue([str isCaseInsensitivelyEqualToString:other], @"string should be case-insensitively equal to uppercase version of it");
}
- (void) testCaseInsensitivelyEqualToSameStringInLowercase {
	NSString *str = @"Adium rocks!";
	NSString *other = [str lowercaseString];
	XCTAssertTrue([str isCaseInsensitivelyEqualToString:other], @"string should be case-insensitively equal to lowercase version of it");
}
- (void) testCaseInsensitivelyEqualToStringPlusPrefix {
	NSString *str = @"Adium rocks!";
	NSString *other = [@"Verily, " stringByAppendingString:str];
	XCTAssertFalse([str isCaseInsensitivelyEqualToString:other], @"string should be inequal to prefixed version of it");
}
- (void) testCaseInsensitivelyEqualToStringPlusSuffix {
	NSString *str = @"Adium rocks!";
	NSString *other = [str stringByAppendingString:@" Yes it does!"];
	XCTAssertFalse([str isCaseInsensitivelyEqualToString:other], @"string should be inequal to suffixed version of it");
}
- (void) testCaseInsensitivelyEqualToCompletelyDifferentString {
	NSString *str = @"Adium rocks!";
	NSString *other = @"I just use iChat.";
	XCTAssertFalse([str isCaseInsensitivelyEqualToString:other], @"string should be inequal to completely different string");
}
- (void) testCaseInsensitivelyEqualToNil {
	NSString *str = @"Adium rocks!";
	XCTAssertThrows([str isCaseInsensitivelyEqualToString:nil], @"can't compare string to nil; this should have thrown");
}
- (void) testCaseInsensitivelyEqualToThingsThatAreNotStrings {
	NSString *str = @"Adium rocks!";
	XCTAssertThrows([str isCaseInsensitivelyEqualToString:(NSString *)[[NSObject alloc] init]], @"can't compare string to plain object; this should have thrown");
	XCTAssertThrows([str isCaseInsensitivelyEqualToString:(NSString *)[NSNumber numberWithInteger:42]], @"can't compare string to number; this should have thrown");
	XCTAssertThrows([str isCaseInsensitivelyEqualToString:(NSString *)[NSValue valueWithRect:NSMakeRect(0.0f, 0.0f, 128.0f, 128.0f)]], @"can't compare string to rect value; this should have thrown");
	XCTAssertThrows([str isCaseInsensitivelyEqualToString:(NSString *)[NSImage imageNamed:@"NSDefaultApplicationIcon"]], @"can't compare string to image; this should have thrown");
}

#pragma mark Construction

- (void)testStringWithDataDecodesWithTheGivenEncoding
{
	char snowmanUTF8[] = { (char)0xe2, (char)0x98, (char)0x83 };
	NSData *data = [NSData dataWithBytes:snowmanUTF8 length:3];
	XCTAssertEqualObjects([NSString stringWithData:data encoding:NSUTF8StringEncoding], @"\u2603");
}

- (void)testStringWithDataNotValidForTheEncodingIsNil
{
	char invalidUTF8[] = { (char)0xff, (char)0xfe };
	NSData *data = [NSData dataWithBytes:invalidUTF8 length:2];
	XCTAssertNil([NSString stringWithData:data encoding:NSUTF8StringEncoding]);
}

- (void)testStringWithEmptyDataIsEmpty
{
	XCTAssertEqualObjects([NSString stringWithData:[NSData data] encoding:NSUTF8StringEncoding], @"");
}

- (void)testStringWithBytesDecodesWithTheGivenEncoding
{
	XCTAssertEqualObjects([NSString stringWithBytes:"caf\xc3\xa9" length:5 encoding:NSUTF8StringEncoding], @"caf\u00e9");
	XCTAssertEqualObjects([NSString stringWithBytes:"caf\xe9" length:4 encoding:NSISOLatin1StringEncoding], @"caf\u00e9");
}

- (void)testStringWithZeroBytesIsEmpty
{
	XCTAssertEqualObjects([NSString stringWithBytes:"ignored" length:0 encoding:NSUTF8StringEncoding], @"");
}

- (void)testRandomStringIsUppercaseAlphanumeric
{
	NSCharacterSet *alphabet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"];
	NSString *str = [NSString randomStringOfLength:200];
	XCTAssertEqual([str rangeOfCharacterFromSet:[alphabet invertedSet]].location, (NSUInteger)NSNotFound, @"\"%@\" has a character outside the alphabet", str);
}

- (void)testStringWithContentsOfUTF8FileOfNilPathIsNil
{
	XCTAssertNil([NSString stringWithContentsOfUTF8File:nil]);
}

- (void)testStringWithContentsOfUTF8FileOfMissingFileIsNil
{
	NSString *missing = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"TestStringAdditions-missing-%@", [[NSUUID UUID] UUIDString]]];
	XCTAssertNil([NSString stringWithContentsOfUTF8File:missing]);
}

#pragma mark Ellipsis and truncation

- (void)testAppendingEllipsisToTheEmptyString
{
	XCTAssertEqualObjects([@"" stringByAppendingEllipsis], [NSString ellipsis]);
}

- (void)testTruncatedStringHasExactlyTheRequestedLength
{
	NSString *original = @"The quick brown fox";
	for (NSUInteger length = 1; length < [original length]; length++) {
		NSString *truncated = [original stringWithEllipsisByTruncatingToLength:length];
		XCTAssertEqual([truncated length], length, @"Truncating to %lu", (unsigned long)length);
		XCTAssertTrue([truncated hasSuffix:[NSString ellipsis]]);
		XCTAssertEqualObjects([truncated substringToIndex:length - 1], [original substringToIndex:length - 1]);
	}
}

- (void)testTruncatingToOneLeavesOnlyTheEllipsis
{
	XCTAssertEqualObjects([@"abc" stringWithEllipsisByTruncatingToLength:1], [NSString ellipsis]);
}

- (void)testTruncationDoesNotSplitASurrogatePair
{
	NSString *truncated = [@"ab\U0001F600cd" stringWithEllipsisByTruncatingToLength:4];
	XCTAssertFalse(CFStringIsSurrogateHighCharacter([truncated characterAtIndex:[truncated length] - 2]), @"\"%@\" ends in half a character", truncated);
}

#pragma mark Translating and compacting

- (void)testTranslatingByOffsetShiftsEveryCharacter
{
	XCTAssertEqualObjects([@"abc" stringByTranslatingByOffset:1], @"bcd");
	XCTAssertEqualObjects([@"HAL" stringByTranslatingByOffset:1], @"IBM");
}

- (void)testTranslatingByZeroIsIdentity
{
	XCTAssertEqualObjects([@"abc \u00e9" stringByTranslatingByOffset:0], @"abc \u00e9");
}

- (void)testTranslatingBackAndForthRoundTrips
{
	NSString *original = @"Adium \u00e9\u00e8";
	XCTAssertEqualObjects([[original stringByTranslatingByOffset:13] stringByTranslatingByOffset:-13], original);
}

- (void)testTranslatingTheEmptyString
{
	XCTAssertEqualObjects([@"" stringByTranslatingByOffset:5], @"");
}

- (void)testCompactedStringLowercasesBeyondASCII
{
	XCTAssertEqualObjects([@"\u00c4\u00d6\u00dc \u0391" compactedString], @"\u00e4\u00f6\u00fc\u03b1");
}

- (void)testCompactedStringRemovesLeadingAndInnerSpaces
{
	XCTAssertEqualObjects([@"  a  b c" compactedString], @"abc");
}

- (void)testCompactedStringRemovesTrailingSpaces
{
	XCTAssertEqualObjects([@"a b  " compactedString], @"ab");
	XCTAssertEqualObjects([@"   " compactedString], @"");
}

- (void)testCompactedEmptyString
{
	XCTAssertEqualObjects([@"" compactedString], @"");
}

#pragma mark Bundle path

- (void)testPathInsideTheBundleCollapsesToTheMarkerAndExpandsBack
{
	NSString *inside = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Resources/x.png"];
	NSString *collapsed = [inside stringByCollapsingBundlePath];
	XCTAssertEqualObjects(collapsed, @"$$BundlePath$$/Contents/Resources/x.png");
	XCTAssertEqualObjects([collapsed stringByExpandingBundlePath], inside);
}

- (void)testPathOutsideTheBundleIsNotCollapsed
{
	XCTAssertEqualObjects([@"/Library/Fonts/Menlo.ttc" stringByCollapsingBundlePath], @"/Library/Fonts/Menlo.ttc");
}

- (void)testMarkerNotAtTheStartIsNotExpanded
{
	XCTAssertEqualObjects([@"/Library/$$BundlePath$$/x" stringByExpandingBundlePath], @"/Library/$$BundlePath$$/x");
}

#pragma mark URL escapes

- (void)testURLEscapesLeaveUnreservedCharactersAlone
{
	NSString *unreserved = @"abcxyzABCXYZ0189_-";
	XCTAssertEqualObjects([unreserved stringByEncodingURLEscapes], unreserved);
}

- (void)testURLEscapesHexEncodeNonASCIIAsUTF8
{
	XCTAssertEqualObjects([[@"\u00e9" stringByEncodingURLEscapes] uppercaseString], @"%C3%A9");
	XCTAssertEqualObjects([[@"\U0001F600" stringByEncodingURLEscapes] uppercaseString], @"%F0%9F%98%80");
}

- (void)testURLEscapesHexEncodeControlCharacters
{
	XCTAssertEqualObjects([[@"\n" stringByEncodingURLEscapes] uppercaseString], @"%0A");
}

- (void)testEncodingURLEscapesTurnsSpacesIntoPluses
{
	XCTAssertEqualObjects([@"a b" stringByEncodingURLEscapes], @"a+b");
}

- (void)testEncodingURLEscapesEscapesReservedCharacters
{
	NSString *encoded = [@"&=/?#+" stringByEncodingURLEscapes];
	XCTAssertEqual([encoded rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"&=/?#+ "]].location, (NSUInteger)NSNotFound, @"\"%@\" still contains a reserved character", encoded);
}

- (void)testDecodingURLEscapesTurnsPlusesIntoSpaces
{
	XCTAssertEqualObjects([@"a+b+c" stringByDecodingURLEscapes], @"a b c");
}

- (void)testDecodingURLEscapesDecodesHexInEitherCase
{
	XCTAssertEqualObjects([@"%41%2a%2A" stringByDecodingURLEscapes], @"A**");
}

- (void)testDecodingURLEscapesLeavesPlainTextAlone
{
	XCTAssertEqualObjects([@"plain-text_123" stringByDecodingURLEscapes], @"plain-text_123");
	XCTAssertEqualObjects([@"" stringByDecodingURLEscapes], @"");
}

- (void)testDecodingURLEscapesDecodesUTF8Sequences
{
	XCTAssertEqualObjects([@"caf%C3%A9" stringByDecodingURLEscapes], @"caf\u00e9");
}

- (void)testURLEscapesRoundTrip
{
	NSString *original = @"a b caf\u00e9";
	XCTAssertEqualObjects([[original stringByEncodingURLEscapes] stringByDecodingURLEscapes], original);
}

#pragma mark Percent escapes for all characters

- (void)testPercentEscapesForAllCharactersLeaveTheDocumentedSetAlone
{
	NSString *allowed = @"!'()*,-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~";
	XCTAssertEqualObjects([allowed stringByAddingPercentEscapesForAllCharacters], allowed);
}

- (void)testPercentEscapesForAllCharactersEscapeTheReservedOnes
{
	XCTAssertEqualObjects([@";/?:@&=+$" stringByAddingPercentEscapesForAllCharacters], @"%3B%2F%3F%3A%40%26%3D%2B%24");
}

- (void)testPercentEscapesForAllCharactersEscapeSpaceAndNonASCII
{
	XCTAssertEqualObjects([@"a b" stringByAddingPercentEscapesForAllCharacters], @"a%20b");
	XCTAssertEqualObjects([@"\u00e9" stringByAddingPercentEscapesForAllCharacters], @"%C3%A9");
	XCTAssertEqualObjects([@"\U0001F600" stringByAddingPercentEscapesForAllCharacters], @"%F0%9F%98%80");
}

- (void)testPercentEscapesForAllCharactersOfTheEmptyString
{
	XCTAssertEqualObjects([@"" stringByAddingPercentEscapesForAllCharacters], @"");
}

#pragma mark Safe file names

- (void)testSafeFilenameReplacesEverySlash
{
	XCTAssertEqualObjects([@"a/b//c" safeFilenameString], @"a-b--c");
}

- (void)testSafeFilenameLeavesEverythingElseAlone
{
	XCTAssertEqualObjects([@"caf\u00e9 \U0001F600 (1).txt" safeFilenameString], @"caf\u00e9 \U0001F600 (1).txt");
}

- (void)testSafeFilenameOfTheEmptyString
{
	XCTAssertEqualObjects([@"" safeFilenameString], @"");
}

- (void)testSafeFilenameLongerThanNameMaxIsTruncated
{
	NSString *overlong = [@"" stringByPaddingToLength:300 withString:@"a" startingAtIndex:0];
	XCTAssertLessThanOrEqual([[overlong safeFilenameString] length], (NSUInteger)NAME_MAX);
}

- (void)testSafeFilenameLongerThanNameMaxHasNoSlashLeft
{
	NSString *overlong = [[@"" stringByPaddingToLength:290 withString:@"a" startingAtIndex:0] stringByAppendingString:@"/b"];
	XCTAssertEqual([[overlong safeFilenameString] rangeOfString:@"/"].location, (NSUInteger)NSNotFound);
}

#pragma mark XML entities

- (void)testEscapingForXMLEscapesTheFivePredefinedEntities
{
	XCTAssertEqualObjects([@"&" stringByEscapingForXMLWithEntities:nil], @"&amp;");
	XCTAssertEqualObjects([@"<" stringByEscapingForXMLWithEntities:nil], @"&lt;");
	XCTAssertEqualObjects([@">" stringByEscapingForXMLWithEntities:nil], @"&gt;");
	XCTAssertEqualObjects([@"\"" stringByEscapingForXMLWithEntities:nil], @"&quot;");
	XCTAssertEqualObjects([@"'" stringByEscapingForXMLWithEntities:nil], @"&apos;");
}

- (void)testEscapingForXMLEscapesEveryOccurrence
{
	XCTAssertEqualObjects([@"a<b<c&&" stringByEscapingForXMLWithEntities:nil], @"a&lt;b&lt;c&amp;&amp;");
}

- (void)testEscapingForXMLLeavesPlainAndNonASCIITextAlone
{
	NSString *plain = @"caf\u00e9 \U0001F600 \u05e9\u05dc\u05d5\u05dd e\u0301 123";
	XCTAssertEqualObjects([plain stringByEscapingForXMLWithEntities:nil], plain);
	XCTAssertEqualObjects([@"" stringByEscapingForXMLWithEntities:nil], @"");
}

- (void)testEscapingForXMLWithoutEntitiesEscapesWhitespace
{
	XCTAssertEqualObjects([@"\t" stringByEscapingForXMLWithEntities:nil], @"&#x09;");
	XCTAssertEqualObjects([@"\n" stringByEscapingForXMLWithEntities:nil], @"&#x0a;");
	XCTAssertEqualObjects([@"\r" stringByEscapingForXMLWithEntities:nil], @"&#x0d;");
}

- (void)testEscapingForXMLWithoutEntitiesEscapesNoBreakSpace
{
	XCTExpectFailure(@"Left as it is on purpose, pending a decision: &nbsp; is not a predefined XML entity, and AIXMLElement writes the chat logs through this method with no entities given, which NSXMLParser and NSXMLDocument then refuse to read (undeclared entity); a character reference such as &#xa0; would be the well-formed way to write it");
	XCTAssertEqualObjects([@"\u00a0" stringByEscapingForXMLWithEntities:nil], @"&nbsp;");
}

- (void)testUnescapingFromXMLDecodesTheFivePredefinedEntities
{
	XCTAssertEqualObjects([@"&amp;&lt;&gt;&quot;&apos;" stringByUnescapingFromXMLWithEntities:nil], @"&<>\"'");
}

- (void)testUnescapingFromXMLDecodesNumericReferences
{
	XCTAssertEqualObjects([@"&#65;&#x41;&#x61;" stringByUnescapingFromXMLWithEntities:nil], @"AAa");
}

- (void)testUnescapingFromXMLDecodesReferencesBeyondTheBasicPlane
{
	XCTAssertEqualObjects([@"&#x1F600;" stringByUnescapingFromXMLWithEntities:nil], @"\U0001F600");
}

- (void)testUnescapingFromXMLLeavesUnknownEntitiesAlone
{
	XCTAssertEqualObjects([@"&nbsp;&foo;" stringByUnescapingFromXMLWithEntities:nil], @"&nbsp;&foo;");
}

- (void)testUnescapingFromXMLUsesTheGivenEntities
{
	XCTAssertEqualObjects([@"a&nbsp;b" stringByUnescapingFromXMLWithEntities:@{@"nbsp": @"\u00a0"}], @"a\u00a0b");
}

- (void)testUnescapingFromXMLLeavesTextWithoutEntitiesAlone
{
	XCTAssertEqualObjects([@"plain & simple" stringByUnescapingFromXMLWithEntities:nil], @"plain & simple");
	XCTAssertEqualObjects([@"" stringByUnescapingFromXMLWithEntities:nil], @"");
}

- (void)testXMLEscapingRoundTripsQuotesAndNonASCII
{
	NSString *original = @"\"caf\u00e9\" & 'th\u00e9' <\U0001F600>";
	XCTAssertEqualObjects([[original stringByEscapingForXMLWithEntities:nil] stringByUnescapingFromXMLWithEntities:nil], original);
}

#pragma mark Shell and regexp escaping

- (void)testEscapingForShellLeavesSafeCharactersAlone
{
	NSString *safe = @"abcXYZ019_-./:,+@";
	XCTAssertEqualObjects([safe stringByEscapingForShell], safe);
}

- (void)testEscapingForShellLeavesNonASCIIAlone
{
	XCTAssertEqualObjects([@"caf\u00e9 \U0001F600" stringByEscapingForShell], @"caf\u00e9\\ \U0001F600");
}

- (void)testEscapingForShellOfTheEmptyString
{
	XCTAssertEqualObjects([@"" stringByEscapingForShell], @"");
}

- (void)testEscapingForShellEscapesEveryUnsafeCharacterInAMixedString
{
	XCTAssertEqualObjects([@"it's \"done\"!" stringByEscapingForShell], @"it\\'s\\ \\\"done\\\"\\!");
}

- (void)testEscapingForShellCopesWithAStringLongerThanItsBuffer
{
	//Ten thousand spaces double to twenty thousand characters, well past the page-sized buffer the method grows by.
	NSString *spaces = [@"" stringByPaddingToLength:10000 withString:@" " startingAtIndex:0];
	NSString *escaped = [spaces stringByEscapingForShell];
	XCTAssertEqual([escaped length], (NSUInteger)20000);
	XCTAssertEqualObjects([escaped substringToIndex:4], @"\\ \\ ");
	XCTAssertEqualObjects([escaped substringFromIndex:19996], @"\\ \\ ");
}

- (void)testEscapingForShellEscapesControlOperators
{
	XCTAssertEqualObjects([@";<>()" stringByEscapingForShell], @"\\;\\<\\>\\(\\)");
}

- (void)testEscapingForRegexpEscapesEveryMetacharacter
{
	XCTAssertEqualObjects([@"\\$|/.*+?{}()[^" stringByEscapingForRegexp], @"\\\\\\$\\|\\/\\.\\*\\+\\?\\{\\}\\(\\)\\[\\^");
}

- (void)testEscapingForRegexpLeavesOrdinaryTextAlone
{
	NSString *ordinary = @"abc XYZ 019 _-=:,;<>@#~&!\u00e9\U0001F600";
	XCTAssertEqualObjects([ordinary stringByEscapingForRegexp], ordinary);
	XCTAssertEqualObjects([@"" stringByEscapingForRegexp], @"");
}

- (void)testEscapedStringMatchesItselfLiterally
{
	NSString *literal = @"a\\$|/.*+?{}()[^]b-c";
	NSError *error = nil;
	NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:[literal stringByEscapingForRegexp] options:0 error:&error];
	XCTAssertNotNil(expression, @"%@", error);
	NSTextCheckingResult *match = [expression firstMatchInString:literal options:NSMatchingAnchored range:NSMakeRange(0, [literal length])];
	XCTAssertTrue(NSEqualRanges(match.range, NSMakeRange(0, [literal length])));

	NSRegularExpression *dot = [NSRegularExpression regularExpressionWithPattern:[@"." stringByEscapingForRegexp] options:0 error:NULL];
	XCTAssertNil([dot firstMatchInString:@"x" options:0 range:NSMakeRange(0, 1)], @"An escaped dot must not match as a wildcard");
}

#pragma mark Last characters

- (void)testLastCharactersOfTheEmptyStringAreFFFF
{
	XCTAssertEqual([@"" lastCharacter], (unichar)0xffff);
	XCTAssertEqual([@"" nextToLastCharacter], (unichar)0xffff);
	XCTAssertEqual([@"" lastLongCharacter], (UTF32Char)0xffff);
}

- (void)testLastAndNextToLastCharacter
{
	XCTAssertEqual([@"ab" lastCharacter], (unichar)'b');
	XCTAssertEqual([@"ab" nextToLastCharacter], (unichar)'a');
	XCTAssertEqual([@"b" nextToLastCharacter], (unichar)0xffff, @"A one-character string has no next-to-last character");
}

- (void)testLastLongCharacterJoinsASurrogatePair
{
	XCTAssertEqual([@"a\U0001F600" lastLongCharacter], (UTF32Char)0x1F600);
}

- (void)testLastLongCharacterOfABasicPlaneCharacter
{
	XCTAssertEqual([@"\U0001F600a" lastLongCharacter], (UTF32Char)'a');
	XCTAssertEqual([@"\u00e9" lastLongCharacter], (UTF32Char)0xe9);
}

#pragma mark UUID

- (void)testUUIDHasTheCanonicalForm
{
	NSString *uuid = [NSString uuid];
	XCTAssertEqual([uuid length], (NSUInteger)36);
	XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:uuid], @"\"%@\" is not a UUID string", uuid);
	XCTAssertEqualObjects(uuid, [uuid uppercaseString]);
}

- (void)testUUIDsDiffer
{
	XCTAssertNotEqualObjects([NSString uuid], [NSString uuid]);
}

#pragma mark Formatting a CGFloat

- (void)testStringWithCGFloatDropsTrailingZeros
{
	XCTAssertEqualObjects([NSString stringWithCGFloat:42.5 maxDigits:6], @"42.5");
	XCTAssertEqualObjects([NSString stringWithCGFloat:0.125 maxDigits:6], @"0.125");
}

- (void)testStringWithCGFloatOfAWholeNumberHasNoDecimalPoint
{
	XCTAssertEqualObjects([NSString stringWithCGFloat:100 maxDigits:6], @"100");
	XCTAssertEqualObjects([NSString stringWithCGFloat:0 maxDigits:6], @"0");
	XCTAssertEqualObjects([NSString stringWithCGFloat:10 maxDigits:2], @"10");
}

- (void)testStringWithCGFloatKeepsTheSign
{
	XCTAssertEqualObjects([NSString stringWithCGFloat:-1.25 maxDigits:6], @"-1.25");
	XCTAssertEqualObjects([NSString stringWithCGFloat:-3 maxDigits:6], @"-3");
}

- (void)testStringWithCGFloatRoundsToMaxDigits
{
	XCTAssertEqualObjects([NSString stringWithCGFloat:42.126 maxDigits:2], @"42.13");
	XCTAssertEqualObjects([NSString stringWithCGFloat:0.5 maxDigits:0], @"0.5", @"Zero means the default precision, not none");
}

#pragma mark Lines

- (void)testEmptyStringIsOneEmptyLine
{
	XCTAssertEqualObjects([@"" allLines], @[@""]);
}

- (void)testTrailingLineBreakYieldsATrailingEmptyLine
{
	XCTAssertEqualObjects([@"a\n" allLines], (@[@"a", @""]));
}

- (void)testCRLFIsOneLineBreak
{
	XCTAssertEqualObjects([@"a\r\nb" allLines], (@[@"a", @"b"]));
}

- (void)testConsecutiveLineBreaksYieldEmptyLines
{
	XCTAssertEqualObjects([@"a\n\nb" allLines], (@[@"a", @"", @"b"]));
	XCTAssertEqualObjects([@"a\r\n\nb" allLines], (@[@"a", @"", @"b"]));
}

- (void)testEveryKindOfLineBreakSplits
{
	NSString *everyKind = [NSString stringWithFormat:@"a\nb\fc\rd%Ce\u2028f\u2029g", (unichar)0x85];
	XCTAssertEqualObjects([everyKind allLines], (@[@"a", @"b", @"c", @"d", @"e", @"f", @"g"]));
}

- (void)testSeparatorObjectsAlternateWithLines
{
	XCTAssertEqualObjects([@"a\r\nb\nc" allLinesWithSeparator:@"|"], (@[@"a", @"|", @"b", @"|", @"c"]));
}

- (void)testStringWithoutLineBreaksIsOneLine
{
	XCTAssertEqualObjects([@"one line" allLinesWithSeparator:@"|"], @[@"one line"]);
}

#pragma mark Comparison and numbers

- (void)testCompareLengthOrdersByLengthOnly
{
	XCTAssertEqual([@"ab" compareLength:@"abc"], NSOrderedAscending);
	XCTAssertEqual([@"abc" compareLength:@"ab"], NSOrderedDescending);
	XCTAssertEqual([@"zzz" compareLength:@"aaa"], NSOrderedSame, @"Content does not matter, only length");
	XCTAssertEqual([@"" compareLength:@""], NSOrderedSame);
}

- (void)testCaseInsensitiveEqualityBeyondASCII
{
	XCTAssertTrue([@"\u00c4\u00d6\u00dc stra\u00dfe" isCaseInsensitivelyEqualToString:@"\u00e4\u00f6\u00fc STRA\u00dfE"]);
	XCTAssertFalse([@"\u00e4" isCaseInsensitivelyEqualToString:@"a"]);
}

- (void)testUnsignedLongLongValueParsesDecimalDigits
{
	XCTAssertEqual([@"0" unsignedLongLongValue], 0ULL);
	XCTAssertEqual([@"42" unsignedLongLongValue], 42ULL);
	XCTAssertEqual([@"18446744073709551615" unsignedLongLongValue], ULLONG_MAX);
}

- (void)testUnsignedLongLongValueTruncatesAFraction
{
	XCTAssertEqual([@"1.9" unsignedLongLongValue], 1ULL);
}

- (void)testUnsignedLongLongValueOfNonNumericTextIsZero
{
	XCTAssertEqual([@"abc" unsignedLongLongValue], 0ULL);
	XCTAssertEqual([@"" unsignedLongLongValue], 0ULL);
}

@end
