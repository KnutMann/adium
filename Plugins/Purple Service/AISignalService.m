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

#import <Adium/AIStatusControllerProtocol.h>
#import "AISignalService.h"
#import "AIPurpleSignalAccount.h"
#import "AISignalAccountViewController.h"
#import <AIUtilities/AIImageAdditions.h>

/*!
 * @brief Signal service, provided by the bundled purple-presage plugin
 *
 * Adium is linked to the phone as a secondary device via QR code, exactly the
 * way Signal Desktop links; there is no password and no server to configure.
 * The account name is the Signal account UUID - and, as the plugin's own README
 * says, entering anything at all is fine the first time: the plugin then tells
 * the user, over the "Logon" system contact, which UUID to put here.
 */
@implementation AISignalService

//Account Creation
- (Class)accountClass{
	return [AIPurpleSignalAccount class];
}

- (AIAccountViewController *)accountViewController{
	return [AISignalAccountViewController accountViewController];
}

- (DCJoinChatViewController *)joinChatView{
	return nil;
}

//Service Description
- (NSString *)serviceCodeUniqueID{
	return @"libpurple-Signal";
}
- (NSString *)serviceID{
	return @"Signal";
}
- (NSString *)serviceClass{
	return @"Signal";
}
- (NSString *)shortDescription{
	return @"Signal";
}
- (NSString *)longDescription{
	return @"Signal";
}
/* Not "Signal UUID", although a UUID is what it ends up holding. Nobody knows their Signal UUID
 * before they have linked, and the first thing this field asks for is a placeholder, so naming it
 * after the value it will eventually contain reads as a demand for something the user cannot
 * supply. */
- (NSString *)userNameLabel{
	return AILocalizedString(@"Account Name", "Label for the account name field for Signal; holds a placeholder until the first link, then the account's UUID");
}
- (NSCharacterSet *)allowedCharacters{
	//A UUID is hex and hyphens; permissive because the first link accepts any placeholder
	return [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF-+@."];
}
- (NSUInteger)allowedLength{
	return 64;
}
- (BOOL)caseSensitive{
	return NO;
}
- (BOOL)supportsPassword{
	return NO;
}
- (BOOL)requiresPassword{
	return NO;
}
- (BOOL)canCreateGroupChats{
	return YES;
}
- (AIServiceImportance)serviceImportance{
	return AIServiceSecondary;
}

- (NSImage *)defaultServiceIconOfType:(AIServiceIconType)iconType
{
	return [NSImage imageNamed:((iconType == AIServiceIconSmall || iconType == AIServiceIconList) ? @"Signal-small" : @"Signal-large")
					  forClass:[self class] loadLazily:YES];
}

- (NSString *)pathForDefaultServiceIconOfType:(AIServiceIconType)iconType
{
	if ((iconType == AIServiceIconSmall) || (iconType == AIServiceIconList)) {
		return [[NSBundle bundleForClass:[self class]] pathForImageResource:@"Signal-small"];
	} else {
		return [[NSBundle bundleForClass:[self class]] pathForImageResource:@"Signal-large"];
	}
}

- (void)registerStatuses{
	[adium.statusController registerStatus:STATUS_NAME_AVAILABLE
						   withDescription:[adium.statusController localizedDescriptionForCoreStatusName:STATUS_NAME_AVAILABLE]
									ofType:AIAvailableStatusType
								forService:self];

	[adium.statusController registerStatus:STATUS_NAME_AWAY
						   withDescription:[adium.statusController localizedDescriptionForCoreStatusName:STATUS_NAME_AWAY]
									ofType:AIAwayStatusType
								forService:self];

	[adium.statusController registerStatus:STATUS_NAME_OFFLINE
						   withDescription:[adium.statusController localizedDescriptionForCoreStatusName:STATUS_NAME_OFFLINE]
									ofType:AIOfflineStatusType
								forService:self];
}

@end
