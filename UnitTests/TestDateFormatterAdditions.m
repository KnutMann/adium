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
#import <AIUtilities/AIDateFormatterAdditions.h>

/* The interval strings have their own file, TestDateFormatterStringRepWithInterval.m. This one
 * covers the fixed formatter, the cached localized formatters and the two pattern converters.
 */
@interface TestDateFormatterAdditions : XCTestCase
@end

//2013-09-08T15:06:11Z, a Sunday.
static NSDate *SampleDate(void)
{
	NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	calendar.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
	NSDateComponents *components = [[NSDateComponents alloc] init];
	components.year = 2013;
	components.month = 9;
	components.day = 8;
	components.hour = 15;
	components.minute = 6;
	components.second = 11;
	return [calendar dateFromComponents:components];
}

@implementation TestDateFormatterAdditions

#pragma mark Fixed formatter

- (void)testFixedFormatterUsesThePOSIXLocaleAndTheGregorianCalendar
{
	NSDateFormatter *formatter = [NSDateFormatter ai_fixedFormatterWithFormat:@"yyyy" timeZone:nil];
	XCTAssertEqualObjects([[formatter locale] localeIdentifier], @"en_US_POSIX");
	XCTAssertEqualObjects([[formatter calendar] calendarIdentifier], NSCalendarIdentifierGregorian);
	XCTAssertEqualObjects([formatter dateFormat], @"yyyy");
}

- (void)testFixedFormatterFormatsInTheGivenTimeZone
{
	NSDateFormatter *formatter = [NSDateFormatter ai_fixedFormatterWithFormat:@"yyyy-MM-dd HH:mm:ss" timeZone:[NSTimeZone timeZoneWithName:@"Asia/Kolkata"]];
	XCTAssertEqualObjects([formatter stringFromDate:SampleDate()], @"2013-09-08 20:36:11");
}

- (void)testFixedFormatterWithoutAZoneTakesTheDefaultZone
{
	NSDateFormatter *formatter = [NSDateFormatter ai_fixedFormatterWithFormat:@"HH:mm" timeZone:nil];
	XCTAssertTrue([[formatter timeZone] isEqualToTimeZone:[NSTimeZone defaultTimeZone]]);
}

- (void)testFixedFormatterSpellsNamesInEnglishWhateverTheMachineSpeaks
{
	NSDateFormatter *formatter = [NSDateFormatter ai_fixedFormatterWithFormat:@"EEEE, d MMMM yyyy" timeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
	XCTAssertEqualObjects([formatter stringFromDate:SampleDate()], @"Sunday, 8 September 2013");
}

- (void)testFixedFormatterParsesWhatItFormats
{
	NSDateFormatter *formatter = [NSDateFormatter ai_fixedFormatterWithFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ" timeZone:[NSTimeZone timeZoneWithName:@"America/Los_Angeles"]];
	NSString *string = [formatter stringFromDate:SampleDate()];
	XCTAssertEqualObjects(string, @"2013-09-08T08:06:11-07:00");
	XCTAssertEqualObjects([formatter dateFromString:string], SampleDate());
}

#pragma mark Localized formatters

- (void)testLocalizedDateFormatterIsHandedToTheBlockSynchronously
{
	__block NSDateFormatter *seen = nil;
	[NSDateFormatter withLocalizedDateFormatterPerform:^(NSDateFormatter *formatter) {
		seen = formatter;
	}];
	XCTAssertNotNil(seen);
	XCTAssertEqual([seen dateStyle], NSDateFormatterFullStyle);
	XCTAssertEqual([seen timeStyle], NSDateFormatterNoStyle);
}

- (void)testLocalizedDateFormatterIsCachedBetweenCalls
{
	__block NSDateFormatter *first = nil, *second = nil;
	[NSDateFormatter withLocalizedDateFormatterPerform:^(NSDateFormatter *formatter) { first = formatter; }];
	[NSDateFormatter withLocalizedDateFormatterPerform:^(NSDateFormatter *formatter) { second = formatter; }];
	XCTAssertTrue(first == second);
}

- (void)testLocalizedShortDateFormatterHasAShortDateAndNoTime
{
	__block NSDateFormatter *first = nil, *second = nil;
	[NSDateFormatter withLocalizedShortDateFormatterPerform:^(NSDateFormatter *formatter) { first = formatter; }];
	[NSDateFormatter withLocalizedShortDateFormatterPerform:^(NSDateFormatter *formatter) { second = formatter; }];
	XCTAssertEqual([first dateStyle], NSDateFormatterShortStyle);
	XCTAssertEqual([first timeStyle], NSDateFormatterNoStyle);
	XCTAssertTrue(first == second);
}

- (void)testLocalizedTimeFormatterUsesTheFormatStringOfTheSameOptions
{
	for (NSNumber *seconds in @[@YES, @NO]) {
		for (NSNumber *ampm in @[@YES, @NO]) {
			__block NSString *format = nil;
			[NSDateFormatter withLocalizedDateFormatterShowingSeconds:[seconds boolValue] showingAMorPM:[ampm boolValue] perform:^(NSDateFormatter *formatter) {
				format = [formatter dateFormat];
			}];
			XCTAssertEqualObjects(format, [NSDateFormatter localizedDateFormatStringShowingSeconds:[seconds boolValue] showingAMorPM:[ampm boolValue]], @"seconds %@, AM/PM %@", seconds, ampm);
		}
	}
}

/* The format strings come from the machine's locale, so only their shape is pinned: what the
 * options promise holds in every locale.
 */
- (void)testTimeFormatWithoutAMPMHasNoDayPeriod
{
	XCTAssertFalse([[NSDateFormatter localizedDateFormatStringShowingSeconds:YES showingAMorPM:NO] containsString:@"a"]);
	XCTAssertFalse([[NSDateFormatter localizedDateFormatStringShowingSeconds:NO showingAMorPM:NO] containsString:@"a"]);
}

- (void)testTimeFormatShowsSecondsOnlyWhenAsked
{
	XCTAssertTrue([[NSDateFormatter localizedDateFormatStringShowingSeconds:YES showingAMorPM:YES] containsString:@"ss"]);
	XCTAssertTrue([[NSDateFormatter localizedDateFormatStringShowingSeconds:YES showingAMorPM:NO] containsString:@"ss"]);
	XCTAssertFalse([[NSDateFormatter localizedDateFormatStringShowingSeconds:NO showingAMorPM:YES] containsString:@"ss"]);
	XCTAssertFalse([[NSDateFormatter localizedDateFormatStringShowingSeconds:NO showingAMorPM:NO] containsString:@"ss"]);
}

- (void)testTimeFormatHasNoSurroundingWhitespace
{
	NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
	for (NSNumber *seconds in @[@YES, @NO]) {
		for (NSNumber *ampm in @[@YES, @NO]) {
			NSString *format = [NSDateFormatter localizedDateFormatStringShowingSeconds:[seconds boolValue] showingAMorPM:[ampm boolValue]];
			XCTAssertGreaterThan([format length], (NSUInteger)0);
			XCTAssertEqualObjects(format, [format stringByTrimmingCharactersInSet:whitespace]);
		}
	}
}

#pragma mark strftime pattern to Unicode pattern

- (void)testConvertsHourAndMinute
{
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%H:%M"], @"HH:mm");
}

- (void)testConvertsTwelveHourClockWithDayPeriod
{
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%I:%M %p"], @"hh:mm a");
}

- (void)testConvertsSeconds
{
	XCTExpectFailure(@"AIDateFormatterAdditions.m:780 maps only a lowercase %s to seconds; strftime's seconds field is %S, which the converter drops, so %H:%M:%S becomes HH:mm:");
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%H:%M:%S"], @"HH:mm:ss");
}

- (void)testConvertsDayAndMonthNames
{
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%a %A %b %B"], @"EEE EEEE MMM MMMM");
}

- (void)testConvertsDayOfMonthForms
{
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%d.%m."], @"dd.MM.");
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%e"], @"d");
}

- (void)testConvertsTwoDigitYear
{
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%y"], @"yy");
}

- (void)testConvertsFourDigitYear
{
	XCTExpectFailure(@"AIDateFormatterAdditions.m:813 treats %Y like %y because the width defaults to 2; strftime's %Y is the four-digit year, so %d.%m.%Y comes out as dd.MM.yy");
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%Y"], @"yyyy");
}

- (void)testConvertsDayOfYear
{
	XCTExpectFailure(@"AIDateFormatterAdditions.m:754 gives %j two digits because the width defaults to 2; strftime's %j is the three-digit day of the year");
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%j"], @"DDD");
}

- (void)testConvertsZoneNameAndOffset
{
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%Z %z"], @"zzzz ZZ");
}

- (void)testWidthFlagOfOneDropsThePadding
{
	XCTExpectFailure(@"AIDateFormatterAdditions.m:695 skips two characters after a width digit, which swallows the field letter, so %1H:%1M yields :m instead of H:m and %5Y reads past the end");
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%1H:%1M"], @"H:m");
}

- (void)testEscapedPercentSignIsKept
{
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%%"], @"%");
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"100%% at %H"], @"100% at HH");
}

- (void)testLiteralTextPassesThrough
{
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"Sent at %H:%M Uhr"], @"Sent at HH:mm Uhr");
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"plain"], @"plain");
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@""], @"");
}

- (void)testTrailingPercentSignDoesNotThrow
{
	XCTExpectFailure(@"AIDateFormatterAdditions.m:687 reads the character after a % without checking that there is one, so a message style whose format ends in % raises instead of being tolerated");
	XCTAssertNoThrow([NSDateFormatter ai_unicodeFormatFromCalendarFormat:@"%H %"]);
}

#pragma mark Unicode pattern to strftime pattern

- (NSDateFormatter *)unicodeFormatterWithFormat:(NSString *)format
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.formatterBehavior = NSDateFormatterBehavior10_4;
	formatter.dateFormat = format;
	return formatter;
}

- (void)testCalendarFormatOfDateAndTime
{
	XCTAssertEqualObjects([[self unicodeFormatterWithFormat:@"yyyy-MM-dd HH:mm:ss"] dateCalendarFormat], @"%Y-%m-%d %H:%M:%S");
}

- (void)testCalendarFormatOfTwelveHourClock
{
	XCTAssertEqualObjects([[self unicodeFormatterWithFormat:@"h:mm a"] dateCalendarFormat], @"%1I:%M %p");
}

- (void)testCalendarFormatOfNames
{
	XCTAssertEqualObjects([[self unicodeFormatterWithFormat:@"EEEE, MMMM d, yyyy"] dateCalendarFormat], @"%A, %B %e, %Y");
	XCTAssertEqualObjects([[self unicodeFormatterWithFormat:@"EEE d MMM"] dateCalendarFormat], @"%a %e %b");
}

- (void)testCalendarFormatOfUnpaddedFields
{
	XCTAssertEqualObjects([[self unicodeFormatterWithFormat:@"H:m:s"] dateCalendarFormat], @"%1H:%1M:%1S");
}

- (void)testUnicodeFormatOfAUnicodeFormatterIsItsPattern
{
	XCTAssertEqualObjects([[self unicodeFormatterWithFormat:@"HH:mm"] dateUnicodeFormat], @"HH:mm");
}

- (void)testTimePatternSurvivesTheRoundTripThroughStrftime
{
	NSString *calendarFormat = [[self unicodeFormatterWithFormat:@"HH:mm"] dateCalendarFormat];
	XCTAssertEqualObjects([NSDateFormatter ai_unicodeFormatFromCalendarFormat:calendarFormat], @"HH:mm");
}

@end
