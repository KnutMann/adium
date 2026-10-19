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
#import <AIUtilities/AIStringFormatter.h>

@interface TestStringFormatter : XCTestCase
@end

@implementation TestStringFormatter

/* Every formatter here is made without an error message: with one set, the fourth rejected input
 * runs a modal alert, which would hang the test process. */
- (AIStringFormatter *)formatterAllowing:(NSCharacterSet *)characters length:(NSInteger)length caseSensitive:(BOOL)caseSensitive
{
	return [AIStringFormatter stringFormatterAllowingCharacters:characters length:length caseSensitive:caseSensitive errorMessage:nil];
}

- (NSCharacterSet *)lowercaseABC
{
	return [NSCharacterSet characterSetWithCharactersInString:@"abc"];
}

- (BOOL)formatter:(AIStringFormatter *)formatter accepts:(NSString *)proposed selection:(NSRange *)inOutSelection resulting:(NSString **)outString
{
	NSString *partial = proposed;
	NSRange selection = inOutSelection ? *inOutSelection : NSMakeRange([proposed length], 0);
	NSString *errorDescription = nil;
	BOOL valid = [formatter isPartialStringValid:&partial
						   proposedSelectedRange:&selection
								  originalString:@""
						   originalSelectedRange:NSMakeRange(0, 0)
								errorDescription:&errorDescription];
	if (inOutSelection) *inOutSelection = selection;
	if (outString) *outString = partial;
	return valid;
}

- (BOOL)formatter:(AIStringFormatter *)formatter accepts:(NSString *)proposed
{
	return [self formatter:formatter accepts:proposed selection:NULL resulting:NULL];
}

#pragma mark Object values

- (void)testStringForObjectValueReturnsTheString
{
	AIStringFormatter *formatter = [self formatterAllowing:nil length:0 caseSensitive:NO];
	XCTAssertEqualObjects([formatter stringForObjectValue:@"hello"], @"hello");
}

- (void)testStringForObjectValueOfNonStringIsNil
{
	AIStringFormatter *formatter = [self formatterAllowing:nil length:0 caseSensitive:NO];
	XCTAssertNil([formatter stringForObjectValue:@42]);
	XCTAssertNil([formatter stringForObjectValue:nil]);
}

- (void)testGetObjectValueHandsBackTheStringItself
{
	AIStringFormatter *formatter = [self formatterAllowing:nil length:0 caseSensitive:NO];
	id object = nil;
	NSString *errorDescription = nil;
	XCTAssertTrue([formatter getObjectValue:&object forString:@"hello" errorDescription:&errorDescription]);
	XCTAssertEqualObjects(object, @"hello");
	XCTAssertNil(errorDescription);
}

#pragma mark Character restriction

- (void)testStringOfAllowedCharactersIsValid
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:0 caseSensitive:YES];
	NSString *result = nil;
	XCTAssertTrue([self formatter:formatter accepts:@"abcabc" selection:NULL resulting:&result]);
	XCTAssertEqualObjects(result, @"abcabc", @"A valid string must come back untouched");
}

- (void)testEmptyStringIsValid
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:2 caseSensitive:YES];
	XCTAssertTrue([self formatter:formatter accepts:@""], @"Deleting everything is always allowed");
}

- (void)testCharacterOutsideTheSetIsRejected
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:0 caseSensitive:YES];
	NSString *result = nil;
	XCTAssertFalse([self formatter:formatter accepts:@"abd" selection:NULL resulting:&result]);
	XCTAssertEqualObjects(result, @"abd", @"A rejected string is not rewritten");
}

- (void)testStringStartingOutsideTheSetIsRejected
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:0 caseSensitive:YES];
	XCTAssertFalse([self formatter:formatter accepts:@"zabc"]);
}

- (void)testUnicodeLettersInTheSetAreAccepted
{
	AIStringFormatter *formatter = [self formatterAllowing:[NSCharacterSet letterCharacterSet] length:0 caseSensitive:YES];
	XCTAssertTrue([self formatter:formatter accepts:@"äöüßα"]);
}

- (void)testNilCharacterSetAllowsAnyCharacter
{
	AIStringFormatter *formatter = [self formatterAllowing:nil length:0 caseSensitive:YES];
	XCTAssertTrue([self formatter:formatter accepts:@"!@# é \U0001F600"]);
}

#pragma mark Case

- (void)testCaseInsensitiveFormatterAcceptsUppercaseInput
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:0 caseSensitive:NO];
	NSString *result = nil;
	XCTAssertTrue([self formatter:formatter accepts:@"ABC" selection:NULL resulting:&result]);
	XCTAssertEqualObjects(result, @"ABC", @"Case-insensitive checking must not change the case of the input");
}

- (void)testCaseSensitiveFormatterRejectsUppercaseInput
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:0 caseSensitive:YES];
	XCTAssertFalse([self formatter:formatter accepts:@"ABC"]);
}

#pragma mark Length

- (void)testStringAtTheLengthLimitIsValid
{
	AIStringFormatter *formatter = [self formatterAllowing:nil length:3 caseSensitive:NO];
	XCTAssertTrue([self formatter:formatter accepts:@"xyz"]);
}

- (void)testStringLongerThanTheLimitIsRejected
{
	AIStringFormatter *formatter = [self formatterAllowing:nil length:3 caseSensitive:NO];
	XCTAssertFalse([self formatter:formatter accepts:@"wxyz"]);
}

- (void)testLengthZeroMeansNoLimit
{
	AIStringFormatter *formatter = [self formatterAllowing:nil length:0 caseSensitive:NO];
	NSString *longString = [@"" stringByPaddingToLength:10000 withString:@"x" startingAtIndex:0];
	XCTAssertTrue([self formatter:formatter accepts:longString]);
}

- (void)testLengthAndCharactersAreBothEnforced
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:2 caseSensitive:YES];
	XCTAssertTrue([self formatter:formatter accepts:@"ab"]);
	XCTAssertFalse([self formatter:formatter accepts:@"abc"], @"Too long");
	XCTAssertFalse([self formatter:formatter accepts:@"ad"], @"Wrong character");
}

#pragma mark Trailing newline

/* Returning NO with a rewritten partial string is how an NSFormatter asks the field to substitute
 * the rewritten string, so a stripped newline is reported as NO plus the string without it. */
- (void)testTrailingLineFeedIsStrippedAndTheCaretMovedBack
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:0 caseSensitive:YES];
	NSString *result = nil;
	NSRange selection = NSMakeRange(4, 0);
	XCTAssertFalse([self formatter:formatter accepts:@"abc\n" selection:&selection resulting:&result]);
	XCTAssertEqualObjects(result, @"abc");
	XCTAssertEqual(selection.location, (NSUInteger)3);
	XCTAssertEqual(selection.length, (NSUInteger)0);
}

- (void)testTrailingCarriageReturnIsStripped
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:0 caseSensitive:YES];
	NSString *result = nil;
	NSRange selection = NSMakeRange(4, 0);
	XCTAssertFalse([self formatter:formatter accepts:@"abc\r" selection:&selection resulting:&result]);
	XCTAssertEqualObjects(result, @"abc");
}

- (void)testTrailingLineFeedShrinksANonEmptySelection
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:0 caseSensitive:YES];
	NSString *result = nil;
	NSRange selection = NSMakeRange(0, 4);
	XCTAssertFalse([self formatter:formatter accepts:@"abc\n" selection:&selection resulting:&result]);
	XCTAssertEqualObjects(result, @"abc");
	XCTAssertEqual(selection.location, (NSUInteger)0);
	XCTAssertEqual(selection.length, (NSUInteger)3);
}

- (void)testLineFeedInTheMiddleIsRejectedWithoutRewriting
{
	AIStringFormatter *formatter = [self formatterAllowing:[self lowercaseABC] length:0 caseSensitive:YES];
	NSString *result = nil;
	XCTAssertFalse([self formatter:formatter accepts:@"ab\ncb" selection:NULL resulting:&result]);
	XCTAssertEqualObjects(result, @"ab\ncb");
}

@end
