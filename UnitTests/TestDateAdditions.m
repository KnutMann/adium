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
#import "TestDateAdditions.h"

#import <AIUtilities/AIDateAdditions.h>

//2009-03-08T03:00:00.5 PDT - half a second after the start of Daylight Saving Time.
#define TEST_DATE [NSDate dateWithTimeIntervalSinceReferenceDate:258199200.5]

//We're testing converting intervals. If we use a time zone that supports DST, the DST changes screw us up. We need an invariant time zone, and UTC works well for this purpose.
#define TEST_TIME_ZONE [NSTimeZone timeZoneWithName:@"UTC"]

@implementation TestDateAdditions

- (void)testConvertIntervalToWeeks
{
	NSDate *now = TEST_DATE;
	NSDate *then;

	NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	NSTimeZone *tz = TEST_TIME_ZONE;
	gregorianCalendar.timeZone = tz;
	NSDateComponents *components;

	NSInteger weeks, days, hours, minutes;
	NSTimeInterval seconds;

	//Test exactly one week ago.
	components = [[NSDateComponents alloc] init];
	components.day = -7;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)1, @"Expected the difference between now and 7 days ago, which is %f seconds, to be 1 week; result was %ldw, %ldd, %ldh, %ldm, %fs", [now timeIntervalSinceDate:then], (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)0, @"Expected the difference between now and 7 days ago to be 1 week, 0 days; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)0, @"Expected the difference between now and 7 days ago to be 1 week, 0 hours; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)0, @"Expected the difference between now and 7 days ago to be 1 week, 0 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 7 days ago to be 1 week, 0 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);

	//Test eight days ago. [Insert obligatory Beatles reference]
	components.day = -8;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)1, @"Expected the difference between now and 8 days ago to be 1 week, 1 day; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)1, @"Expected the difference between now and 8 days ago to be 1 week, 1 day; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)0, @"Expected the difference between now and 8 days ago to be 1 week, 1 day, 0 hours; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)0, @"Expected the difference between now and 8 days ago to be 1 week, 1 day, 0 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 8 days ago to be 1 week, 1 day, 0 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);

	//Test six days (almost, but not quite, one week) ago. [Insert obligatory DJ Shadow reference]
	components = [[NSDateComponents alloc] init];
	components.day = -6;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0, @"Expected the difference between now and 6 days ago to be 0 weeks, 6 days; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)6, @"Expected the difference between now and 6 days ago to be 6 days; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)0, @"Expected the difference between now and 6 days ago to be 6 days, 0 hours; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)0, @"Expected the difference between now and 6 days ago to be 6 days, 0 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 6 days ago to be 6 days, 0 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
}
- (void)testConvertIntervalToDays
{
	NSDate *now = TEST_DATE;
	NSDate *then;

	NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	NSTimeZone *tz = TEST_TIME_ZONE;
	gregorianCalendar.timeZone = tz;
	NSDateComponents *components;

	NSInteger weeks, days, hours, minutes;
	NSTimeInterval seconds;

	//Test one day ago.
	components = [[NSDateComponents alloc] init];
	components.day = -1;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0, @"Expected the difference between now and 1 day ago to be 0 weeks, 1 day; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)1, @"Expected the difference between now and 1 day ago to be 1 day; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)0, @"Expected the difference between now and 1 day ago to be 1 day, 0 hours; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)0, @"Expected the difference between now and 1 day ago to be 1 day, 0 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 1 day ago to be 1 day, 0 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);

	//Test one day ago, expressed as hours.
	components = [[NSDateComponents alloc] init];
	components.hour = -24;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0, @"Expected the difference between now and 1 day ago to be 0 weeks, 1 day; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)1, @"Expected the difference between now and 1 day ago to be 1 day; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)0, @"Expected the difference between now and 1 day ago to be 1 day, 0 hours; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)0, @"Expected the difference between now and 1 day ago to be 1 day, 0 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 1 day ago to be 1 day, 0 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	
	//Test 23 hours (almost, but not quite, one day) ago.
	components = [[NSDateComponents alloc] init];
	components.hour = -23;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0, @"Expected the difference between now and 23 hours ago to be 0 weeks, 23 hours; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)0, @"Expected the difference between now and 23 hours ago to be 0 days, 23 hours; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)23, @"Expected the difference between now and 23 hours ago to be 23 hours; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)0, @"Expected the difference between now and 23 hours ago to be 23 hours, 0 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 23 hours ago to be 23 hours, 0 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
}
- (void)testConvertIntervalToHours
{
	NSDate *now = TEST_DATE;
	NSDate *then;

	NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	NSTimeZone *tz = TEST_TIME_ZONE;
	gregorianCalendar.timeZone = tz;
	NSDateComponents *components;

	NSInteger weeks, days, hours, minutes;
	NSTimeInterval seconds;

	//Test one hour ago.
	components = [[NSDateComponents alloc] init];
	components.hour = -1;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0, @"Expected the difference between now and 1 hour ago to be 0 weeks, 1 hour; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)0, @"Expected the difference between now and 1 hour ago to be 0 days, 1 hour; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)1, @"Expected the difference between now and 1 hour ago to be 1 hour; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)0, @"Expected the difference between now and 1 hour ago to be 1 hour, 0 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 1 hour ago to be 1 hour, 0 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);

	//Test one hour ago, expressed as minutes.
	components = [[NSDateComponents alloc] init];
	components.minute = -60;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0, @"Expected the difference between now and 1 hour ago to be 0 weeks, 1 hour; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)0, @"Expected the difference between now and 1 hour ago to be 0 days, 1 hour; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)1, @"Expected the difference between now and 1 hour ago to be 1 hour; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)0, @"Expected the difference between now and 1 hour ago to be 1 hour, 0 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 1 hour ago to be 1 hour, 0 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);

	//Test 59 minutes (almost, but not quite, one hour) ago.
	components = [[NSDateComponents alloc] init];
	components.minute = -59;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0, @"Expected the difference between now and 59 minutes ago to be 0 weeks, 59 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)0, @"Expected the difference between now and 59 minutes ago to be 0 days, 59 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)0, @"Expected the difference between now and 59 minutes ago to be 0 hours, 59 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)59, @"Expected the difference between now and 59 minutes ago to be 59 minutes; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 59 minutes ago to be 59 minutes, 0 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
}
- (void)testConvertIntervalToMinutes
{
	NSDate *now = TEST_DATE;
	NSDate *then;

	NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	NSTimeZone *tz = TEST_TIME_ZONE;
	gregorianCalendar.timeZone = tz;
	NSDateComponents *components;

	NSInteger weeks, days, hours, minutes;
	NSTimeInterval seconds;

	//Test one minute ago.
	components = [[NSDateComponents alloc] init];
	components.minute = -1;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0, @"Expected the difference between now and 1 minute ago to be 0 weeks, 1 minute; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)0, @"Expected the difference between now and 1 minute ago to be 0 days, 1 minute; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)0, @"Expected the difference between now and 1 minute ago to be 0 hours, 1 minute; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)1, @"Expected the difference between now and 1 minute ago to be 1 minute; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 1 minute ago to be 1 minute, 0 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);

	//Test 59 seconds (almost, but not quite, one minute) ago.
	components = [[NSDateComponents alloc] init];
	components.second = -59;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0, @"Expected the difference between now and 59 seconds ago to be 0 weeks, 59 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)0, @"Expected the difference between now and 59 seconds ago to be 0 days, 59 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)0, @"Expected the difference between now and 59 seconds ago to be 0 hours, 59 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)0, @"Expected the difference between now and 59 seconds ago to be 0 minutes, 59 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 59.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 59 seconds ago to be 59 seconds; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
}
- (void)testConvertIntervalToSeconds
{
	NSDate *now = TEST_DATE;
	NSDate *then;

	NSCalendar *gregorianCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	NSTimeZone *tz = TEST_TIME_ZONE;
	gregorianCalendar.timeZone = tz;
	NSDateComponents *components;

	NSInteger weeks, days, hours, minutes;
	NSTimeInterval seconds;

	//Test one second ago.
	components = [[NSDateComponents alloc] init];
	components.second = -1;
	then = [gregorianCalendar dateByAddingComponents:components toDate:now options:0UL];
	[NSDate convertTimeInterval:[now timeIntervalSinceDate:then]
						toWeeks:&weeks
						   days:&days
						  hours:&hours
						minutes:&minutes
						seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0, @"Expected the difference between now and 1 second ago to be 0 weeks, 1 second; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual( days, (NSInteger)0, @"Expected the difference between now and 1 second ago to be 0 days, 1 second; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(hours, (NSInteger)0, @"Expected the difference between now and 1 second ago to be 0 hours, 1 second; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqual(minutes, (NSInteger)0, @"Expected the difference between now and 1 second ago to be 0 minutes, 1 second; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
	XCTAssertEqualWithAccuracy(seconds, 1.0, AIFloatComparisonAccuracy, @"Expected the difference between now and 1 second ago to be 1 second; result was %ldw, %ldd, %ldh, %ldm, %fs", (long)weeks, (long)days, (long)hours, (long)minutes, seconds);
}

#pragma mark Negative, zero and fractional intervals

- (void)testConvertNegativeIntervalYieldsNegativeParts
{
	NSInteger weeks, days, hours, minutes;
	NSTimeInterval seconds;
	[NSDate convertTimeInterval:-(7 * 86400 + 3661) toWeeks:&weeks days:&days hours:&hours minutes:&minutes seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)-1);
	XCTAssertEqual(days, (NSInteger)0);
	XCTAssertEqual(hours, (NSInteger)-1);
	XCTAssertEqual(minutes, (NSInteger)-1);
	XCTAssertEqualWithAccuracy(seconds, -1.0, AIFloatComparisonAccuracy);
}

- (void)testConvertZeroIntervalYieldsZeroes
{
	NSInteger weeks = 9, days = 9, hours = 9, minutes = 9;
	NSTimeInterval seconds = 9;
	[NSDate convertTimeInterval:0 toWeeks:&weeks days:&days hours:&hours minutes:&minutes seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)0);
	XCTAssertEqual(days, (NSInteger)0);
	XCTAssertEqual(hours, (NSInteger)0);
	XCTAssertEqual(minutes, (NSInteger)0);
	XCTAssertEqualWithAccuracy(seconds, 0.0, AIFloatComparisonAccuracy);
}

- (void)testConvertIntervalKeepsTheFractionOfASecond
{
	NSInteger minutes;
	NSTimeInterval seconds;
	[NSDate convertTimeInterval:90.25 toWeeks:NULL days:NULL hours:NULL minutes:&minutes seconds:&seconds];
	XCTAssertEqual(minutes, (NSInteger)1);
	XCTAssertEqualWithAccuracy(seconds, 30.25, AIFloatComparisonAccuracy);
}

- (void)testConvertIntervalAcceptsNullForEveryUnwantedPart
{
	NSInteger weeks = 0;
	XCTAssertNoThrow([NSDate convertTimeInterval:(15 * 86400) toWeeks:&weeks days:NULL hours:NULL minutes:NULL seconds:NULL]);
	XCTAssertEqual(weeks, (NSInteger)2);
	XCTAssertNoThrow([NSDate convertTimeInterval:(15 * 86400) toWeeks:NULL days:NULL hours:NULL minutes:NULL seconds:NULL]);
}

- (void)testConvertIntervalCarriesEveryUnitAtItsLargestValue
{
	NSInteger weeks, days, hours, minutes;
	NSTimeInterval seconds;
	NSTimeInterval interval = (100 * 7 * 86400) + (6 * 86400) + (23 * 3600) + (59 * 60) + 59.5;
	[NSDate convertTimeInterval:interval toWeeks:&weeks days:&days hours:&hours minutes:&minutes seconds:&seconds];
	XCTAssertEqual(weeks, (NSInteger)100);
	XCTAssertEqual(days, (NSInteger)6);
	XCTAssertEqual(hours, (NSInteger)23);
	XCTAssertEqual(minutes, (NSInteger)59);
	XCTAssertEqualWithAccuracy(seconds, 59.5, AIFloatComparisonAccuracy);
}

#pragma mark Same day and midnight

/* +isDate:sameDayAsDate: and +midnightTomorrow work in the current calendar, which is the
 * machine's; the instants below are chosen so the answer is the same in every time zone.
 */

- (void)testAnInstantIsOnTheSameDayAsItself
{
	NSDate *date = TEST_DATE;
	XCTAssertTrue([NSDate isDate:date sameDayAsDate:date]);
	XCTAssertTrue([NSDate isDate:date sameDayAsDate:[date copy]]);
}

- (void)testInstantsOneSecondApartAwayFromMidnightAreOnTheSameDay
{
	//2013-09-08T12:07:30Z. Zone offsets are multiples of 15 minutes, so this is xx:07:30, xx:22:30, xx:37:30 or xx:52:30 local time everywhere, never at a day boundary.
	NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:400334850.0];
	XCTAssertTrue([NSDate isDate:date sameDayAsDate:[date dateByAddingTimeInterval:1.0]]);
	XCTAssertTrue([NSDate isDate:date sameDayAsDate:[date dateByAddingTimeInterval:-1.0]]);
}

- (void)testInstantsTwoDaysApartAreNotOnTheSameDay
{
	NSDate *date = TEST_DATE;
	XCTAssertFalse([NSDate isDate:date sameDayAsDate:[date dateByAddingTimeInterval:(2 * 86400)]]);
	XCTAssertFalse([NSDate isDate:date sameDayAsDate:[date dateByAddingTimeInterval:-(2 * 86400)]]);
}

- (void)testMidnightTomorrowIsTheStartOfADayAfterNow
{
	NSDate *before = [NSDate date];
	NSDate *midnight = [NSDate midnightTomorrow];
	NSCalendar *calendar = [NSCalendar currentCalendar];
	XCTAssertGreaterThan([midnight timeIntervalSinceDate:before], 0.0);
	XCTAssertLessThan([midnight timeIntervalSinceDate:before], 2.0 * 86400, @"Tomorrow's midnight is less than two days away");
	XCTAssertEqualObjects(midnight, [calendar startOfDayForDate:midnight], @"It is the first instant of its day");
}

@end
