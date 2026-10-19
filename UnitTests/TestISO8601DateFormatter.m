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
#import <AIUtilities/ISO8601DateFormatter.h>

@interface TestISO8601DateFormatter : XCTestCase
@end

/* Expected instants are built from UTC calendar components, never through the parser under test.
 * A string without a zone designator is interpreted in the machine's zone, so every test that
 * compares NSDate values uses a string carrying Z or an offset; date-only strings are checked by
 * their components.
 */
static NSTimeZone *UTCZone(void)
{
	return [NSTimeZone timeZoneWithName:@"UTC"];
}

static NSDate *DateUTC(NSInteger year, NSInteger month, NSInteger day, NSInteger hour, NSInteger minute, NSInteger second)
{
	NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	calendar.timeZone = UTCZone();
	NSDateComponents *components = [[NSDateComponents alloc] init];
	components.year = year;
	components.month = month;
	components.day = day;
	components.hour = hour;
	components.minute = minute;
	components.second = second;
	return [calendar dateFromComponents:components];
}

@implementation TestISO8601DateFormatter

- (ISO8601DateFormatter *)formatter
{
	ISO8601DateFormatter *formatter = [[ISO8601DateFormatter alloc] init];
	formatter.defaultTimeZone = UTCZone();
	return formatter;
}

#pragma mark Parsing calendar dates

- (void)testParsesCalendarDateWithTimeAndUTCDesignator
{
	NSTimeZone *zone = nil;
	NSDate *date = [[self formatter] dateFromString:@"2013-09-08T15:06:11Z" timeZone:&zone];
	XCTAssertEqualObjects(date, DateUTC(2013, 9, 8, 15, 6, 11));
	XCTAssertEqual([zone secondsFromGMT], (NSInteger)0, @"Z designates UTC");
}

- (void)testParsesDateOnlyStringAsMidnightComponentsWithoutZone
{
	NSTimeZone *zone = [NSTimeZone timeZoneWithName:@"Asia/Tokyo"];
	NSDateComponents *components = [[self formatter] dateComponentsFromString:@"2013-09-08" timeZone:&zone];
	XCTAssertEqual(components.year, (NSInteger)2013);
	XCTAssertEqual(components.month, (NSInteger)9);
	XCTAssertEqual(components.day, (NSInteger)8);
	XCTAssertEqual(components.hour, (NSInteger)0);
	XCTAssertEqual(components.minute, (NSInteger)0);
	XCTAssertEqual(components.second, (NSInteger)0);
	XCTAssertNil(zone, @"A string without a zone designator reports no zone");
}

- (void)testParsesBasicFormatCalendarDate
{
	NSDateComponents *components = [[self formatter] dateComponentsFromString:@"20130908"];
	XCTAssertEqual(components.year, (NSInteger)2013);
	XCTAssertEqual(components.month, (NSInteger)9);
	XCTAssertEqual(components.day, (NSInteger)8);
}

- (void)testParsesYearAndMonthAsFirstOfMonth
{
	NSDateComponents *components = [[self formatter] dateComponentsFromString:@"2013-09"];
	XCTAssertEqual(components.year, (NSInteger)2013);
	XCTAssertEqual(components.month, (NSInteger)9);
	XCTAssertEqual(components.day, (NSInteger)1);
}

- (void)testParsesYearAloneAsFirstOfJanuary
{
	NSDateComponents *components = [[self formatter] dateComponentsFromString:@"2013"];
	XCTAssertEqual(components.year, (NSInteger)2013);
	XCTAssertEqual(components.month, (NSInteger)1);
	XCTAssertEqual(components.day, (NSInteger)1);
}

- (void)testParsesSpaceInPlaceOfTheTimeDesignator
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2013-09-08 15:06:11Z"], DateUTC(2013, 9, 8, 15, 6, 11));
}

- (void)testParsesTimeOnlyStringKeepingItsTimeComponents
{
	NSDateComponents *components = [[self formatter] dateComponentsFromString:@"T15:06:11"];
	XCTAssertNotNil(components);
	XCTAssertEqual(components.hour, (NSInteger)15);
	XCTAssertEqual(components.minute, (NSInteger)6);
	XCTAssertEqual(components.second, (NSInteger)11);
}

- (void)testParsesHourTwentyFourAsMidnightOfTheNextDay
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2013-09-08T24:00:00Z"], DateUTC(2013, 9, 9, 0, 0, 0));
}

- (void)testParsesBasicFormatTime
{
	NSTimeZone *zone = nil;
	NSDate *date = [[self formatter] dateFromString:@"20130908T150611Z" timeZone:&zone];
	XCTAssertEqualObjects(date, DateUTC(2013, 9, 8, 15, 6, 11));
	XCTAssertEqual([zone secondsFromGMT], (NSInteger)0);
}

#pragma mark Time zone offsets

- (void)testParsesNegativeWholeHourOffset
{
	NSTimeZone *zone = nil;
	NSDate *date = [[self formatter] dateFromString:@"2013-09-08T15:06:11-0800" timeZone:&zone];
	XCTAssertEqualObjects(date, DateUTC(2013, 9, 8, 23, 6, 11));
	XCTAssertEqual([zone secondsFromGMT], (NSInteger)-28800);
}

- (void)testParsesHourOnlyOffset
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2013-09-08T15:06:11+01"], DateUTC(2013, 9, 8, 14, 6, 11));
}

- (void)testParsesBasicFormatOffsetWithMinutes
{
	NSTimeZone *zone = nil;
	NSDate *date = [[self formatter] dateFromString:@"2013-09-08T15:06:11+0545" timeZone:&zone];
	XCTAssertEqualObjects(date, DateUTC(2013, 9, 8, 9, 21, 11));
	XCTAssertEqual([zone secondsFromGMT], (NSInteger)(5 * 3600 + 45 * 60));
}

- (void)testParsesExtendedFormatOffsetWhenSeparatorIsColon
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.timeZoneSeparator = ':';
	XCTAssertEqualObjects([formatter dateFromString:@"2013-09-08T15:06:11+05:30"], DateUTC(2013, 9, 8, 9, 36, 11));
}

- (void)testParsesNegativeOffsetBelowOneHourWhenSeparatorIsColon
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.timeZoneSeparator = ':';
	NSTimeZone *zone = nil;
	NSDate *date = [formatter dateFromString:@"2013-09-08T15:06:11-00:30" timeZone:&zone];
	XCTAssertEqualObjects(date, DateUTC(2013, 9, 8, 15, 36, 11));
	XCTAssertEqual([zone secondsFromGMT], (NSInteger)-1800);
}

- (void)testParsesExtendedFormatOffsetByDefault
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2013-09-08T15:06:11+05:30"], DateUTC(2013, 9, 8, 9, 36, 11));
}

- (void)testBasicFormatOffsetStillParsesWhenSeparatorIsColon
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.timeZoneSeparator = ':';
	XCTAssertEqualObjects([formatter dateFromString:@"2013-09-08T15:06:11+0530"], DateUTC(2013, 9, 8, 9, 36, 11));
}

- (void)testAllowsWhitespaceBeforeZoneOnlyWhenLenient
{
	ISO8601DateFormatter *formatter = [self formatter];
	NSTimeZone *zone = nil;
	[formatter dateComponentsFromString:@"2013-09-08T15:06:11 Z" timeZone:&zone];
	XCTAssertEqual([zone secondsFromGMT], (NSInteger)0, @"Lenient parsing takes a zone after a single space");

	formatter.parsesStrictly = YES;
	zone = nil;
	[formatter dateComponentsFromString:@"2013-09-08T15:06:11 Z" timeZone:&zone];
	XCTAssertNil(zone, @"Strict parsing stops at the space");
}

#pragma mark Fractions

- (void)testParsesFractionOfSecondWithPeriod
{
	NSTimeInterval fraction = 0.0;
	NSDateComponents *components = [[self formatter] dateComponentsFromString:@"2013-09-08T15:06:11.5Z" timeZone:NULL range:NULL fractionOfSecond:&fraction];
	XCTAssertEqual(components.second, (NSInteger)11);
	XCTAssertEqualWithAccuracy(fraction, 0.5, AIFloatComparisonAccuracy);
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2013-09-08T15:06:11.5Z"], [DateUTC(2013, 9, 8, 15, 6, 11) dateByAddingTimeInterval:0.5]);
}

- (void)testParsesFractionOfSecondWithComma
{
	NSTimeInterval fraction = 0.0;
	[[self formatter] dateComponentsFromString:@"2013-09-08T15:06:11,25Z" timeZone:NULL range:NULL fractionOfSecond:&fraction];
	XCTAssertEqualWithAccuracy(fraction, 0.25, AIFloatComparisonAccuracy);
}

- (void)testParsesSixDigitFractionOfSecond
{
	NSTimeInterval fraction = 0.0;
	[[self formatter] dateComponentsFromString:@"2013-09-08T15:06:11.123456Z" timeZone:NULL range:NULL fractionOfSecond:&fraction];
	XCTAssertEqualWithAccuracy(fraction, 0.123456, AIFloatComparisonAccuracy);
}

- (void)testParsesFractionalMinuteAsSeconds
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2013-09-08T15:30.5Z"], DateUTC(2013, 9, 8, 15, 30, 30));
}

- (void)testFractionOfSecondIsZeroWhenTheStringHasNone
{
	NSTimeInterval fraction = 0.75;
	[[self formatter] dateComponentsFromString:@"2013-09-08T15:06:11Z" timeZone:NULL range:NULL fractionOfSecond:&fraction];
	XCTAssertEqualWithAccuracy(fraction, 0.0, AIFloatComparisonAccuracy);
}

#pragma mark Ordinal dates

- (void)testParsesOrdinalDate
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2009-032T00:00:00Z"], DateUTC(2009, 2, 1, 0, 0, 0));
}

- (void)testParsesBasicFormatOrdinalDate
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2009032T00:00:00Z"], DateUTC(2009, 2, 1, 0, 0, 0));
}

- (void)testParsesDay366OfALeapYear
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2008-366T00:00:00Z"], DateUTC(2008, 12, 31, 0, 0, 0));
}

- (void)testStrictParsingRejectsDay366OfACommonYear
{
	ISO8601DateFormatter *formatter = [self formatter];
	XCTAssertNotNil([formatter dateFromString:@"2009-366"], @"Lenient parsing lets the calendar normalise an overflow");

	formatter.parsesStrictly = YES;
	XCTAssertNil([formatter dateFromString:@"2009-366"]);
	XCTAssertNil([formatter dateFromString:@"2100-366"], @"A century year not divisible by 400 is a common year");
	XCTAssertNotNil([formatter dateFromString:@"2000-366"], @"A century year divisible by 400 is a leap year");
}

#pragma mark Week dates

- (void)testParsesWeekDateWhoseWeekOneStartsInThePreviousYear
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2009-W01-1T00:00:00Z"], DateUTC(2008, 12, 29, 0, 0, 0));
}

- (void)testParsesBasicFormatWeekDate
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2009W011T00:00:00Z"], DateUTC(2008, 12, 29, 0, 0, 0));
}

- (void)testParsesWeekFiftyThreeEndingInTheNextYear
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2009-W53-7T00:00:00Z"], DateUTC(2010, 1, 3, 0, 0, 0));
}

- (void)testParsesLastDayOfWeekFiftyTwo
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2010-W52-7T00:00:00Z"], DateUTC(2011, 1, 2, 0, 0, 0));
}

- (void)testParsesWeekWithoutDayAsItsMonday
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2009-W01T00:00:00Z"], DateUTC(2008, 12, 29, 0, 0, 0));
}

- (void)testParsesWeekDateWithTimeAndOffset
{
	XCTAssertEqualObjects([[self formatter] dateFromString:@"2009-W53-7T10:00:00+0200"], DateUTC(2010, 1, 3, 8, 0, 0));
}

- (void)testYearFollowedByBareWIsWeekOneDayOneOnlyWhenLenient
{
	ISO8601DateFormatter *formatter = [self formatter];
	XCTAssertEqualObjects([formatter dateFromString:@"2009-WT00:00:00Z"], DateUTC(2008, 12, 29, 0, 0, 0));
}

- (void)testStrictParsingRejectsYearFollowedByBareW
{
	ISO8601DateFormatter *formatter = [self formatter];
	XCTAssertNotNil([formatter dateFromString:@"2009-W"]);
	formatter.parsesStrictly = YES;
	XCTAssertNil([formatter dateFromString:@"2009-W"]);
}

#pragma mark Leniency and strictness

- (void)testSkipsLeadingWhitespaceWhenLenientAndReportsTheRange
{
	NSRange range = NSMakeRange(0, 0);
	NSDateComponents *components = [[self formatter] dateComponentsFromString:@"  2013-09-08" timeZone:NULL range:&range fractionOfSecond:NULL];
	XCTAssertEqual(components.day, (NSInteger)8);
	XCTAssertTrue(NSEqualRanges(range, NSMakeRange(2, 10)), @"Range was %@", NSStringFromRange(range));
}

- (void)testStrictParsingRejectsLeadingWhitespace
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.parsesStrictly = YES;
	NSRange range = NSMakeRange(0, 0);
	XCTAssertNil([formatter dateComponentsFromString:@"  2013-09-08" timeZone:NULL range:&range fractionOfSecond:NULL]);
	XCTAssertEqual(range.location, (NSUInteger)NSNotFound);
}

- (void)testReportsTheRangeOfTheDateInsideALongerString
{
	NSRange range = NSMakeRange(0, 0);
	NSDate *date = [[self formatter] dateFromString:@"2013-09-08T15:06:11Z and more" timeZone:NULL range:&range];
	XCTAssertEqualObjects(date, DateUTC(2013, 9, 8, 15, 6, 11));
	XCTAssertTrue(NSEqualRanges(range, NSMakeRange(0, 20)), @"Range was %@", NSStringFromRange(range));
}

- (void)testMonthAndDayWithoutSeparatorParseOnlyWhenLenient
{
	ISO8601DateFormatter *formatter = [self formatter];
	NSDateComponents *components = [formatter dateComponentsFromString:@"2013-0908"];
	XCTAssertEqual(components.month, (NSInteger)9);
	XCTAssertEqual(components.day, (NSInteger)8);

	formatter.parsesStrictly = YES;
	XCTAssertNil([formatter dateComponentsFromString:@"2013-0908"]);
}

- (void)testSingleDigitMonthAndDayParseWhenLenient
{
	NSDateComponents *components = [[self formatter] dateComponentsFromString:@"2013-9-8"];
	XCTAssertEqual(components.year, (NSInteger)2013);
	XCTAssertEqual(components.month, (NSInteger)9);
	XCTAssertEqual(components.day, (NSInteger)8);
}

- (void)testStrictParsingRejectsImpliedCentury
{
	ISO8601DateFormatter *formatter = [self formatter];
	XCTAssertNotNil([formatter dateComponentsFromString:@"130908"]);
	formatter.parsesStrictly = YES;
	XCTAssertNil([formatter dateComponentsFromString:@"130908"]);
}

- (void)testStrictParsingRejectsMonthThirteen
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.parsesStrictly = YES;
	XCTAssertNil([formatter dateFromString:@"2013-13-01"]);
}

- (void)testStrictParsingRejectsFebruaryTwentyNinthOfACommonYear
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.parsesStrictly = YES;
	XCTAssertNil([formatter dateFromString:@"2013-02-29"]);
}

- (void)testCustomTimeSeparatorIsUsedWhenLenient
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.timeSeparator = '.';
	XCTAssertEqualObjects([formatter dateFromString:@"2013-09-08T15.06.11Z"], DateUTC(2013, 9, 8, 15, 6, 11));
}

- (void)testCustomTimeSeparatorIsIgnoredWhenStrict
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.timeSeparator = '.';
	formatter.parsesStrictly = YES;
	XCTAssertEqualObjects([formatter dateFromString:@"2013-09-08T15:06:11Z"], DateUTC(2013, 9, 8, 15, 6, 11));
}

#pragma mark Refusals

- (void)testReturnsNilForNilString
{
	XCTAssertNil([[self formatter] dateFromString:nil]);
	XCTAssertNil([[self formatter] dateComponentsFromString:nil]);
}

- (void)testReturnsNilForEmptyString
{
	NSRange range = NSMakeRange(0, 0);
	XCTAssertNil([[self formatter] dateFromString:@"" timeZone:NULL range:&range]);
	XCTAssertEqual(range.location, (NSUInteger)NSNotFound);
}

- (void)testReturnsNilForTextThatIsNoDate
{
	XCTAssertNil([[self formatter] dateFromString:@"hello"]);
}

- (void)testReturnsNilForAnInterval
{
	XCTAssertNil([[self formatter] dateFromString:@"2013-09-08/2013-09-09"]);
}

- (void)testRefusingAnIntervalStillReportsTheRangeAsNotFound
{
	NSRange range = NSMakeRange(2, 10);
	NSTimeZone *zone = UTCZone();
	XCTAssertNil([[self formatter] dateComponentsFromString:@"2013-09-08/2013-09-09" timeZone:&zone range:&range fractionOfSecond:NULL]);
	XCTAssertEqual(range.location, (NSUInteger)NSNotFound);
	XCTAssertNil(zone);
}

#pragma mark NSFormatter interface

- (void)testGetObjectValueParsesAndReportsSuccess
{
	id value = nil;
	NSString *errorDescription = nil;
	XCTAssertTrue([[self formatter] getObjectValue:&value forString:@"2013-09-08T15:06:11Z" errorDescription:&errorDescription]);
	XCTAssertEqualObjects(value, DateUTC(2013, 9, 8, 15, 6, 11));
}

- (void)testGetObjectValueReportsFailureForTextThatIsNoDate
{
	id value = (id)@"untouched";
	XCTAssertFalse([[self formatter] getObjectValue:&value forString:@"hello" errorDescription:NULL]);
	XCTAssertNil(value);
}

- (void)testStringForObjectValueFormatsDatesOnly
{
	ISO8601DateFormatter *formatter = [self formatter];
	XCTAssertEqualObjects([formatter stringForObjectValue:DateUTC(2013, 9, 8, 15, 6, 11)], @"2013-09-08");
	XCTAssertNil([formatter stringForObjectValue:@"2013-09-08"]);
}

#pragma mark Unparsing calendar dates

- (void)testFormatsCalendarDateWithoutTimeByDefault
{
	XCTAssertEqualObjects([[self formatter] stringFromDate:DateUTC(2013, 9, 8, 15, 6, 11) timeZone:UTCZone()], @"2013-09-08");
}

- (void)testFormatsTimeInUTCWithZ
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	XCTAssertEqualObjects([formatter stringFromDate:DateUTC(2013, 9, 8, 15, 6, 11) timeZone:UTCZone()], @"2013-09-08T15:06:11Z");
}

- (void)testFormatsTimeDroppingTheFractionOfASecond
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	NSDate *date = [DateUTC(2013, 9, 8, 15, 6, 11) dateByAddingTimeInterval:0.75];
	XCTAssertEqualObjects([formatter stringFromDate:date timeZone:UTCZone()], @"2013-09-08T15:06:11Z");
}

- (void)testPadsEarlyYearsToFourDigits
{
	XCTAssertEqualObjects([[self formatter] stringFromDate:DateUTC(1, 1, 1, 0, 0, 0) timeZone:UTCZone()], @"0001-01-01");
}

- (void)testFormatsNegativeWholeHourOffset
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	NSString *string = [formatter stringFromDate:DateUTC(2013, 9, 8, 15, 6, 11) timeZone:[NSTimeZone timeZoneWithName:@"America/Los_Angeles"]];
	XCTAssertEqualObjects(string, @"2013-09-08T08:06:11-0700");
}

- (void)testFormatsPositiveHalfHourOffset
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	NSString *string = [formatter stringFromDate:DateUTC(2013, 9, 8, 15, 6, 11) timeZone:[NSTimeZone timeZoneWithName:@"Asia/Kolkata"]];
	XCTAssertEqualObjects(string, @"2013-09-08T20:36:11+0530");
}

- (void)testFormatsNegativeHalfHourOffset
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	NSString *string = [formatter stringFromDate:DateUTC(2013, 1, 15, 12, 0, 0) timeZone:[NSTimeZone timeZoneWithName:@"America/St_Johns"]];
	XCTAssertEqualObjects(string, @"2013-01-15T08:30:00-0330");
}

- (void)testFormatsOffsetWithTheConfiguredSeparator
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	formatter.timeZoneSeparator = ':';
	NSString *string = [formatter stringFromDate:DateUTC(2013, 9, 8, 15, 6, 11) timeZone:[NSTimeZone timeZoneWithName:@"Asia/Kolkata"]];
	XCTAssertEqualObjects(string, @"2013-09-08T20:36:11+05:30");
}

- (void)testFormatsTimeWithTheConfiguredSeparator
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	formatter.timeSeparator = '.';
	XCTAssertEqualObjects([formatter stringFromDate:DateUTC(2013, 9, 8, 15, 6, 11) timeZone:UTCZone()], @"2013-09-08T15.06.11Z");
}

- (void)testOffsetFollowsTheDaylightSavingSwitch
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	NSTimeZone *losAngeles = [NSTimeZone timeZoneWithName:@"America/Los_Angeles"];
	//Clocks in Los Angeles went from 01:59:59 PST to 03:00:00 PDT on 2009-03-08.
	XCTAssertEqualObjects([formatter stringFromDate:DateUTC(2009, 3, 8, 9, 59, 59) timeZone:losAngeles], @"2009-03-08T01:59:59-0800");
	XCTAssertEqualObjects([formatter stringFromDate:DateUTC(2009, 3, 8, 10, 0, 0) timeZone:losAngeles], @"2009-03-08T03:00:00-0700");
}

- (void)testOneArgumentStringFromDateUsesTheDefaultTimeZone
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	formatter.defaultTimeZone = [NSTimeZone timeZoneWithName:@"Asia/Kolkata"];
	XCTAssertEqualObjects([formatter stringFromDate:DateUTC(2013, 9, 8, 15, 6, 11)], @"2013-09-08T20:36:11+0530");
}

- (void)testUnknownFormatRaises
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = (ISO8601DateFormat)99;
	XCTAssertThrows([formatter stringFromDate:DateUTC(2013, 9, 8, 15, 6, 11) timeZone:UTCZone()]);
}

#pragma mark Unparsing ordinal dates

- (void)testFormatsOrdinalDate
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = ISO8601DateFormatOrdinal;
	XCTAssertEqualObjects([formatter stringFromDate:DateUTC(2009, 1, 1, 0, 0, 0) timeZone:UTCZone()], @"2009-001");
	XCTAssertEqualObjects([formatter stringFromDate:DateUTC(2009, 2, 1, 0, 0, 0) timeZone:UTCZone()], @"2009-032");
}

- (void)testOrdinalDateCountsTheLeapDay
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = ISO8601DateFormatOrdinal;
	XCTAssertEqualObjects([formatter stringFromDate:DateUTC(2008, 2, 29, 0, 0, 0) timeZone:UTCZone()], @"2008-060");
	XCTAssertEqualObjects([formatter stringFromDate:DateUTC(2008, 12, 31, 0, 0, 0) timeZone:UTCZone()], @"2008-366");
}

- (void)testFormatsOrdinalDateWithTimeAndOffset
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = ISO8601DateFormatOrdinal;
	formatter.includeTime = YES;
	NSString *string = [formatter stringFromDate:DateUTC(2013, 9, 8, 15, 6, 11) timeZone:[NSTimeZone timeZoneWithName:@"America/Los_Angeles"]];
	XCTAssertEqualObjects(string, @"2013-251T08:06:11-0700");
}

#pragma mark Unparsing week dates

/* Dates around the turn of the year, each with its ISO 8601 week date. Week 1 is the week
 * holding the first Thursday, so a year's first days can belong to the previous week-year
 * and its last days to the next.
 */
- (NSArray *)weekDateEdges
{
	return @[
		@[DateUTC(2008, 12, 29, 0, 0, 0), @"2009-W01-1"],
		@[DateUTC(2009,  1,  1, 0, 0, 0), @"2009-W01-4"],
		@[DateUTC(2010,  1,  3, 0, 0, 0), @"2009-W53-7"],
		@[DateUTC(2010,  1,  4, 0, 0, 0), @"2010-W01-1"],
		@[DateUTC(2011,  1,  1, 0, 0, 0), @"2010-W52-6"],
		@[DateUTC(2012,  1,  1, 0, 0, 0), @"2011-W52-7"],
		@[DateUTC(2012, 12, 31, 0, 0, 0), @"2013-W01-1"],
		@[DateUTC(2014,  1,  1, 0, 0, 0), @"2014-W01-3"],
		@[DateUTC(2008,  2, 29, 0, 0, 0), @"2008-W09-5"],
	];
}

- (void)testParsesWeekDatesAtYearBoundaries
{
	for (NSArray *edge in [self weekDateEdges]) {
		NSString *string = [edge[1] stringByAppendingString:@"T00:00:00Z"];
		XCTAssertEqualObjects([[self formatter] dateFromString:string], edge[0], @"%@", string);
	}
}

- (void)testFormatsWeekDatesAtYearBoundaries
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = ISO8601DateFormatWeek;
	for (NSArray *edge in [self weekDateEdges]) {
		XCTAssertEqualObjects([formatter stringFromDate:edge[0] timeZone:UTCZone()], edge[1]);
	}
}

- (void)testWeekDatesRoundTripAtYearBoundaries
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = ISO8601DateFormatWeek;
	formatter.includeTime = YES;
	for (NSArray *edge in [self weekDateEdges]) {
		NSString *string = [formatter stringFromDate:edge[0] timeZone:UTCZone()];
		XCTAssertEqualObjects([formatter dateFromString:string], edge[0], @"%@", string);
	}
}

- (void)testWeekDateCarriesTheWeekYearNotTheCalendarYear
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = ISO8601DateFormatWeek;
	NSString *string = [formatter stringFromDate:DateUTC(2010, 1, 3, 0, 0, 0) timeZone:UTCZone()];
	XCTAssertTrue([string hasPrefix:@"2009-W53-"], @"January 3rd, 2010 belongs to week 53 of 2009; got %@", string);
}

- (void)testWeekDateIsTakenInTheRequestedTimeZone
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = ISO8601DateFormatWeek;
	//Midnight UTC on Monday is still Sunday evening in Los Angeles, the last day of the previous week.
	NSString *string = [formatter stringFromDate:DateUTC(2010, 1, 4, 0, 0, 0) timeZone:[NSTimeZone timeZoneWithName:@"America/Los_Angeles"]];
	XCTAssertTrue([string hasPrefix:@"2009-W53-"], @"Got %@", string);
}

- (void)testWeekDateWithTimeAppendsTimeAndOffset
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = ISO8601DateFormatWeek;
	formatter.includeTime = YES;
	NSString *string = [formatter stringFromDate:DateUTC(2013, 9, 8, 15, 6, 11) timeZone:[NSTimeZone timeZoneWithName:@"Asia/Kolkata"]];
	XCTAssertTrue([string hasPrefix:@"2013-W36-"], @"Got %@", string);
	XCTAssertTrue([string hasSuffix:@"T20:36:11+0530"], @"Got %@", string);
}

- (void)testWeekDatePadsEarlyYearsToFourDigits
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = ISO8601DateFormatWeek;
	NSString *string = [formatter stringFromDate:DateUTC(1, 1, 1, 0, 0, 0) timeZone:UTCZone()];
	XCTAssertTrue([string hasPrefix:@"0001-W01-"], @"Got %@", string);
}

#pragma mark Round trips

- (void)testCalendarDateWithTimeRoundTripsThroughEveryOffset
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	NSDate *date = DateUTC(2008, 2, 29, 23, 59, 59);
	for (NSString *zoneName in @[@"UTC", @"America/Los_Angeles", @"Asia/Kolkata", @"Asia/Kathmandu", @"Pacific/Kiritimati"]) {
		NSString *string = [formatter stringFromDate:date timeZone:[NSTimeZone timeZoneWithName:zoneName]];
		XCTAssertEqualObjects([formatter dateFromString:string], date, @"%@ via %@", zoneName, string);
	}
}

- (void)testOrdinalDateWithTimeRoundTrips
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.format = ISO8601DateFormatOrdinal;
	formatter.includeTime = YES;
	NSDate *date = DateUTC(2012, 12, 31, 12, 0, 0);
	NSString *string = [formatter stringFromDate:date timeZone:[NSTimeZone timeZoneWithName:@"America/Los_Angeles"]];
	XCTAssertEqualObjects([formatter dateFromString:string], date, @"via %@", string);
}

- (void)testAmbiguousHourRoundTripsOnBothSidesOfTheSwitch
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	NSTimeZone *losAngeles = [NSTimeZone timeZoneWithName:@"America/Los_Angeles"];
	//01:30 local happened twice on 2009-11-01: first in PDT, then in PST.
	NSDate *firstPass = DateUTC(2009, 11, 1, 8, 30, 0);
	NSDate *secondPass = DateUTC(2009, 11, 1, 9, 30, 0);
	NSString *first = [formatter stringFromDate:firstPass timeZone:losAngeles];
	NSString *second = [formatter stringFromDate:secondPass timeZone:losAngeles];
	XCTAssertEqualObjects(first, @"2009-11-01T01:30:00-0700");
	XCTAssertEqualObjects(second, @"2009-11-01T01:30:00-0800");
	XCTAssertEqualObjects([formatter dateFromString:first], firstPass);
	XCTAssertEqualObjects([formatter dateFromString:second], secondPass);
}

- (void)testStrictParserAcceptsEveryFormatTheUnparserProduces
{
	ISO8601DateFormatter *formatter = [self formatter];
	formatter.includeTime = YES;
	formatter.parsesStrictly = YES;
	NSDate *date = DateUTC(2010, 1, 3, 10, 0, 0);
	NSTimeZone *kolkata = [NSTimeZone timeZoneWithName:@"Asia/Kolkata"];
	for (NSNumber *format in @[@(ISO8601DateFormatCalendar), @(ISO8601DateFormatOrdinal), @(ISO8601DateFormatWeek)]) {
		formatter.format = (ISO8601DateFormat)[format unsignedIntegerValue];
		NSString *string = [formatter stringFromDate:date timeZone:kolkata];
		XCTAssertEqualObjects([formatter dateFromString:string], date, @"format %@ via %@", format, string);
	}
}

@end
