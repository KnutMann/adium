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
#import <AIUtilities/AIScannerAdditions.h>

@interface TestScannerAdditions : XCTestCase
@end

@implementation TestScannerAdditions

- (void)testScansADecimalNumber
{
	NSScanner *scanner = [NSScanner scannerWithString:@"42"];
	unsigned int value = 0;
	XCTAssertTrue([scanner scanUnsignedInt:&value]);
	XCTAssertEqual(value, 42U);
	XCTAssertEqual([scanner scanLocation], (NSUInteger)2);
}

- (void)testScansZero
{
	NSScanner *scanner = [NSScanner scannerWithString:@"0"];
	unsigned int value = 99;
	XCTAssertTrue([scanner scanUnsignedInt:&value]);
	XCTAssertEqual(value, 0U);
}

- (void)testScansTheLargestUnsignedInt
{
	NSScanner *scanner = [NSScanner scannerWithString:@"4294967295"];
	unsigned int value = 0;
	XCTAssertTrue([scanner scanUnsignedInt:&value]);
	XCTAssertEqual(value, UINT_MAX);
}

- (void)testAcceptsALeadingPlusSign
{
	NSScanner *scanner = [NSScanner scannerWithString:@"+7"];
	unsigned int value = 0;
	XCTAssertTrue([scanner scanUnsignedInt:&value]);
	XCTAssertEqual(value, 7U);
	XCTAssertEqual([scanner scanLocation], (NSUInteger)2);
}

- (void)testRejectsAMinusSign
{
	NSScanner *scanner = [NSScanner scannerWithString:@"-3"];
	unsigned int value = 99;
	XCTAssertFalse([scanner scanUnsignedInt:&value]);
	XCTAssertEqual(value, 99U, @"A failed scan leaves the value alone");
	XCTAssertEqual([scanner scanLocation], (NSUInteger)0, @"A failed scan does not consume anything");
}

- (void)testRejectsNonDigits
{
	NSScanner *scanner = [NSScanner scannerWithString:@"abc"];
	unsigned int value = 99;
	XCTAssertFalse([scanner scanUnsignedInt:&value]);
	XCTAssertEqual(value, 99U);
}

- (void)testRejectsAnEmptyString
{
	NSScanner *scanner = [NSScanner scannerWithString:@""];
	unsigned int value = 99;
	XCTAssertFalse([scanner scanUnsignedInt:&value]);
	XCTAssertEqual(value, 99U);
}

- (void)testRejectsALonePlusSign
{
	NSScanner *scanner = [NSScanner scannerWithString:@"+"];
	unsigned int value = 99;
	XCTAssertFalse([scanner scanUnsignedInt:&value]);
}

- (void)testRejectsNonASCIIDigits
{
	//Arabic-Indic digits are digits to Unicode, but an unsigned int parser reads ASCII only.
	NSScanner *scanner = [NSScanner scannerWithString:@"٣"];
	unsigned int value = 99;
	XCTAssertFalse([scanner scanUnsignedInt:&value]);
}

- (void)testStopsAtTheFirstNonDigit
{
	NSScanner *scanner = [NSScanner scannerWithString:@"12x"];
	unsigned int value = 0;
	XCTAssertTrue([scanner scanUnsignedInt:&value]);
	XCTAssertEqual(value, 12U);
	XCTAssertEqual([scanner scanLocation], (NSUInteger)2);
}

- (void)testSkipsLeadingWhitespaceLikeTheOtherScanMethods
{
	NSScanner *scanner = [NSScanner scannerWithString:@"  12"];
	unsigned int value = 0;
	XCTAssertTrue([scanner scanUnsignedInt:&value]);
	XCTAssertEqual(value, 12U);
}

- (void)testScanLocationEndsAfterTheNumberWhenWhitespaceWasSkipped
{
	XCTExpectFailure(@"AIScannerAdditions.m:55 sets the scan location to an index relative to the old location instead of an absolute one, so after skipping two spaces and reading two digits it points at 2 rather than 4");
	NSScanner *scanner = [NSScanner scannerWithString:@"  12x"];
	unsigned int value = 0;
	XCTAssertTrue([scanner scanUnsignedInt:&value]);
	XCTAssertEqual([scanner scanLocation], (NSUInteger)4);
}

- (void)testSequentialScansReadSuccessiveNumbers
{
	NSScanner *scanner = [NSScanner scannerWithString:@"7 8"];
	unsigned int first = 0, second = 0;
	XCTAssertTrue([scanner scanUnsignedInt:&first]);
	XCTAssertTrue([scanner scanUnsignedInt:&second]);
	XCTAssertEqual(first, 7U);
	XCTAssertEqual(second, 8U);
}

- (void)testHonoursACustomSkipSet
{
	NSScanner *scanner = [NSScanner scannerWithString:@"##5"];
	[scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@"#"]];
	unsigned int value = 0;
	XCTAssertTrue([scanner scanUnsignedInt:&value]);
	XCTAssertEqual(value, 5U);
	XCTAssertEqualObjects([scanner charactersToBeSkipped], [NSCharacterSet characterSetWithCharactersInString:@"#"], @"The skip set must be restored afterwards");
}

@end
