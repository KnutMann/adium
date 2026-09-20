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

#import "AIContactLocalTimePlugin.h"
#import <Adium/AIListContact.h>
#import <Adium/AIAccount.h>
#import <AIUtilities/AIAttributedStringAdditions.h>

@implementation AIContactLocalTimePlugin

- (void)installPlugin
{
	[adium.interfaceController registerContactListTooltipEntry:self secondaryEntry:NO];
}

- (void)uninstallPlugin
{
	[adium.interfaceController unregisterContactListTooltipEntry:self secondaryEntry:NO];
}

- (NSString *)labelForObject:(AIListObject *)inObject
{
	return AILocalizedString(@"Local Time", "Tooltip label before the time of day where a contact is");
}

/*!
 * @brief The inspector asks every tooltip entry this, and asks it as a requirement, not a courtesy
 *
 * An entry that does not answer takes the application down with it the first time a contact
 * is inspected, which is how this one was found. The answer is yes: the inspector shows what
 * is known about a person, and where in the day they are is part of that.
 */
- (BOOL)shouldDisplayInContactInspector
{
	return YES;
}

/*!
 * @brief The time of day where this contact is, when they have said and it differs from ours
 *
 * Silent when nobody knows, which is every contact until they have been asked and answered,
 * and silent when they are in the same hour and minute as we are, because then the answer is
 * the clock in the corner of the screen and saying it twice is noise.
 */
- (NSAttributedString *)entryForObject:(AIListObject *)inObject
{
	if (![inObject isKindOfClass:[AIListContact class]]) return nil;

	AIListContact	*contact = (AIListContact *)inObject;
	NSTimeZone		*theirs = [contact.account timeZoneForContact:contact];
	if (!theirs) return nil;

	NSTimeZone *ours = [NSTimeZone localTimeZone];
	NSDate	   *now = [NSDate date];
	if ([theirs secondsFromGMTForDate:now] == [ours secondsFromGMTForDate:now]) return nil;

	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setTimeZone:theirs];
	[formatter setDateStyle:NSDateFormatterNoStyle];
	[formatter setTimeStyle:NSDateFormatterShortStyle];

	NSString *clock = [formatter stringFromDate:now];

	/* The difference said in whole hours where it is whole, which it is nearly everywhere,
	 * and left out where it is not rather than printed as a fraction nobody reads. */
	NSInteger	difference = [theirs secondsFromGMTForDate:now] - [ours secondsFromGMTForDate:now];
	NSString	*entry;

	if (difference % 3600 == 0) {
		NSInteger hours = difference / 3600;
		entry = [NSString stringWithFormat:AILocalizedString(@"%@ (%+ld h)",
				 "Contact's local time followed by how many hours that is from ours"),
				 clock, (long)hours];
	} else {
		entry = clock;
	}

	return [[NSAttributedString alloc] initWithString:entry];
}

@end
