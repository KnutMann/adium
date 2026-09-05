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
#import "CBPurpleAccount.h"

#import <Adium/AISharedAdium.h>
#import <Adium/AILoginControllerProtocol.h>
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

/*!
 * @brief A button under the database address that shows the file it names
 *
 * The row above it holds a connection string, not a path, and the person reading it cannot click
 * their way from "$purple_user_dir" to the folder the database really sits in. The button does that
 * walk for them.
 */
- (void)addField:(AIAccountPlanField *)field toCard:(NSString *)cardIdentifier
{
	[super addField:field toCard:cardIdentifier];

	if (![[field name] isEqualToString:@"option:database-address"])
		return;

	AIAccountPlanField *reveal = [AIAccountPlanField fieldNamed:@"reveal-database"
														   kind:AIAccountFieldAction];

	[reveal setLabel:AILocalizedString(@"Show Database in Finder",
									   "Button under the WhatsApp database address; opens the folder holding the database file")];
	[reveal setAction:@selector(showDatabaseInFinder:)];

	[super addField:reveal toCard:cardIdentifier];
}

- (void)showDatabaseInFinder:(AIAccountPlanField *)field
{
	NSString *address = [self valueForField:[self fieldForSetting:@"database-address"]];
	if (![address length])
		return;

	/* The address is what the plug-in hands to its SQL driver: an optional dialect prefix, a path
	 * with $purple_user_dir and $username placeholders, and driver parameters behind a question
	 * mark. A postgres address names no local file at all. */
	if ([address hasPrefix:@"postgres:"]) {
		NSBeep();
		return;
	}

	if ([address hasPrefix:@"file:"])
		address = [address substringFromIndex:[@"file:" length]];

	NSRange parameters = [address rangeOfString:@"?"];
	if (parameters.location != NSNotFound)
		address = [address substringToIndex:parameters.location];

	//The same expansions the plug-in applies before opening the database, see its login()
	NSString *userDir = [[[adium.loginController userDirectory] stringByAppendingPathComponent:@"libpurple"] stringByExpandingTildeInPath];
	address = [address stringByReplacingOccurrencesOfString:@"$purple_user_dir" withString:userDir];

	const char *purpleName = [(CBPurpleAccount *)self.account purpleAccountName];
	if (purpleName)
		address = [address stringByReplacingOccurrencesOfString:@"$username"
													 withString:[NSString stringWithUTF8String:purpleName]];

	address = [address stringByExpandingTildeInPath];

	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ([fileManager fileExistsAtPath:address]) {
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:
			[NSArray arrayWithObject:[NSURL fileURLWithPath:address]]];
		return;
	}

	//No database yet; its folder is still worth opening
	NSString *folder = [address stringByDeletingLastPathComponent];
	BOOL isDirectory = NO;
	if ([fileManager fileExistsAtPath:folder isDirectory:&isDirectory] && isDirectory) {
		[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:folder isDirectory:YES]];
	} else {
		NSBeep();
	}
}

@end
