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
#import "AIWhatsAppService.h"
#import "AIPurpleWhatsAppAccount.h"
#import "AIWhatsAppAccountViewController.h"
#import <AIUtilities/AIImageAdditions.h>

/*!
 * @brief WhatsApp service, provided by the bundled purple-gowhatsapp plugin
 *
 * The account name is the phone number in international format
 * (e.g. +4917012345678); the leading plus and the JID domain are
 * handled automatically. The account is linked to the
 * phone via QR code / pairing code on first login; no password is used.
 */
@implementation AIWhatsAppService

//Account Creation
- (Class)accountClass{
	return [AIPurpleWhatsAppAccount class];
}

- (AIAccountViewController *)accountViewController{
	return [AIWhatsAppAccountViewController accountViewController];
}

- (DCJoinChatViewController *)joinChatView{
	return nil;
}

//Service Description
- (NSString *)serviceCodeUniqueID{
	return @"libpurple-WhatsApp";
}
- (NSString *)serviceID{
	return @"WhatsApp";
}
- (NSString *)serviceClass{
	return @"WhatsApp";
}
- (NSString *)shortDescription{
	return @"WhatsApp";
}
- (NSString *)longDescription{
	return @"WhatsApp";
}
- (NSString *)userNameLabel{
	return AILocalizedString(@"Phone Number", "Used as a label for the account name field for WhatsApp (international format without +, e.g. 4917012345678)");
}
- (NSCharacterSet *)allowedCharacters{
	return [NSCharacterSet characterSetWithCharactersInString:@"+0123456789@.abcdefghijklmnopqrstuvwxyz"];
}
- (NSUInteger)allowedLength{
	return 20;
}
- (BOOL)caseSensitive{
	return NO;
}
- (BOOL)supportsPassword{
	return NO;
}
- (BOOL)userNamesArePhoneNumbers
{
	return YES;
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
	return [NSImage imageNamed:((iconType == AIServiceIconSmall || iconType == AIServiceIconList) ? @"WhatsApp-small" : @"WhatsApp-large")
					  forClass:[self class] loadLazily:YES];
}

- (NSString *)pathForDefaultServiceIconOfType:(AIServiceIconType)iconType
{
	if ((iconType == AIServiceIconSmall) || (iconType == AIServiceIconList)) {
		return [[NSBundle bundleForClass:[self class]] pathForImageResource:@"WhatsApp-small"];
	} else {
		return [[NSBundle bundleForClass:[self class]] pathForImageResource:@"WhatsApp-large"];
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
