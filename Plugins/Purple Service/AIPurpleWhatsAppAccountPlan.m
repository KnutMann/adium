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

#import "AIPurpleWhatsAppAccountPlan.h"

#import <AIUtilities/AIStringUtilities.h>

@implementation AIPurpleWhatsAppAccountPlan

/*!
 * @brief Say what the three ways of fetching a picture are
 *
 * The protocol calls the row "Download user profile pictures" and lists its three settings under the
 * names it stores them as, "original", "preview" and "no". Read as a menu, those are not three
 * answers to that question: two of them are sizes and one is a refusal. What is really being chosen
 * is how good a picture is worth fetching, so the row says that and the entries answer it.
 *
 * The values stay exactly as they are. They are what the protocol keeps and what it compares against.
 */
- (void)refineField:(AIAccountPlanField *)field forSetting:(NSString *)setting
{
	[super refineField:field forSetting:setting];

	if (![setting isEqualToString:@"get-icons"] || ![[field choiceValues] count])
		return;

	NSDictionary *titles = [NSDictionary dictionaryWithObjectsAndKeys:
		AILocalizedString(@"Original", "WhatsApp profile picture quality: the full sized picture"), @"original",
		AILocalizedString(@"Preview", "WhatsApp profile picture quality: the small version"), @"preview",
		AILocalizedString(@"Do not load", "WhatsApp profile picture quality: fetch no pictures at all"), @"no",
		nil];

	NSMutableArray *rebuilt = [NSMutableArray array];

	//By value rather than by position, so a protocol that reorders its list still reads correctly
	for (NSString *value in [field choiceValues]) {
		NSString *title = [titles objectForKey:value];

		[rebuilt addObject:(title ? title : value)];
	}

	[field setLabel:AILocalizedString(@"Profile picture quality",
									  "Row asking how good a contact's picture is worth fetching")];
	[field setChoiceTitles:rebuilt];
}

@end
