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

@interface NSDateFormatter (AIDateFormatterAdditions)

+ (void)withLocalizedDateFormatterPerform:(void (^)(NSDateFormatter *))block;
+ (void)withLocalizedShortDateFormatterPerform:(void (^)(NSDateFormatter *))block;
+ (void)withLocalizedDateFormatterShowingSeconds:(BOOL)seconds showingAMorPM:(BOOL)showAmPm perform:(void (^)(NSDateFormatter *))block;
+ (NSString *)localizedDateFormatStringShowingSeconds:(BOOL)seconds showingAMorPM:(BOOL)showAmPm;
/*!
 * @brief A formatter for dates that are not for reading
 *
 * Pinned to the POSIX locale and the Gregorian calendar, so what comes out is the same on every
 * machine whatever language it is set to. That is what you want for a log file name, a timestamp
 * sent to a server, or a line in the debug window, and never what you want for anything a person
 * reads: for that there are the localized formatters above.
 *
 * The result is safe to keep and to format on any thread, as long as nothing changes its settings
 * afterwards. The localized formatters need a queue precisely because each caller reconfigures them.
 *
 * @param format A Unicode TR35 pattern, not a strftime one
 * @param timeZone The zone to format in, or nil for the machine's own
 */
+ (NSDateFormatter *)ai_fixedFormatterWithFormat:(NSString *)format timeZone:(NSTimeZone *)timeZone;

+ (NSString *)stringForTimeIntervalSinceDate:(NSDate *)inDate;
+ (NSString *)stringForTimeIntervalSinceDate:(NSDate *)inDate showingSeconds:(BOOL)showSeconds abbreviated:(BOOL)abbreviate;
+ (NSString *)stringForApproximateTimeIntervalBetweenDate:(NSDate *)firstDate andDate:(NSDate *)secondDate;
+ (NSString *)stringForApproximateTimeInterval:(NSTimeInterval)interval abbreviated:(BOOL)abbreviate;
+ (NSString *)stringForTimeInterval:(NSTimeInterval)interval;
+ (NSString *)stringForTimeInterval:(NSTimeInterval)interval showingSeconds:(BOOL)showSeconds abbreviated:(BOOL)abbreviate approximated:(BOOL)approximate;
/*!
 * @brief Translate an old CalendarDate/strftime-style pattern (%H:%M) into Unicode TR35.
 */
+ (NSString *)ai_unicodeFormatFromCalendarFormat:(NSString *)format;

- (NSString *)dateCalendarFormat;
- (NSString *)dateUnicodeFormat;
@end
