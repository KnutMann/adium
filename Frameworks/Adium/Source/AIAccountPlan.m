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

#import <Adium/AIAccountPlan.h>
#import <Adium/AIAccount.h>
#import <Adium/AIChat.h>
#import <Adium/AIService.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIStringUtilities.h>

#define KEY_DISABLE_TYPING_NOTIFICATIONS	@"Disable Typing Notifications"

NSString *AIAccountCardAccount	= @"account";
NSString *AIAccountCardPersonal	= @"personal";
NSString *AIAccountCardOptions	= @"options";
NSString *AIAccountCardMore		= @"more";
NSString *AIAccountCardPrivacy	= @"privacy";

@implementation AIAccountPlanField

@synthesize name, label, detail, placeholder, preferenceKey, preferenceGroup, legacyKey;
@synthesize choiceTitles, choiceValues, defaultValue, action, kind, store;
@synthesize inverted, secure, attributed, disabledWhileOnline, width;

+ (AIAccountPlanField *)fieldNamed:(NSString *)inName kind:(AIAccountFieldKind)inKind
{
	AIAccountPlanField *field = [[AIAccountPlanField alloc] init];

	[field setName:inName];
	[field setKind:inKind];

	return field;
}

- (id)init
{
	if ((self = [super init])) {
		store = AIAccountFieldStoreNone;
		preferenceGroup = GROUP_ACCOUNT_STATUS;
	}

	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %@ in %@>", NSStringFromClass([self class]), name, preferenceKey];
}

@end

@implementation AIAccountPlanCard

@synthesize identifier;

- (id)init
{
	if ((self = [super init]))
		fields = [[NSMutableArray alloc] init];

	return self;
}

- (NSArray *)fields
{
	return fields;
}

- (void)addField:(AIAccountPlanField *)field
{
	if (field)
		[fields addObject:field];
}

@end

@implementation AIAccountPlan

- (id)initWithAccount:(AIAccount *)inAccount
{
	if ((self = [super init])) {
		account = inAccount;

		/* Whether the keychain had anything to give when the page opened. Emptying the field only
		 * means "forget it" if there was something there to begin with. */
		passwordWasShown = ([[adium.accountController passwordForAccount:account] length] != 0);
	}

	return self;
}

- (AIAccount *)account
{
	return account;
}

//The cards --------------------------------------------------------------------------------------
#pragma mark The cards

- (NSArray *)cards
{
	if (!cards) {
		cards = [[NSMutableArray alloc] init];

		/* Opened up front, in the order they are shown, so that a subclass adding to one lands where
		 * that card belongs rather than behind everything the base class described. An empty one is
		 * never drawn. */
		for (NSString *identifier in [NSArray arrayWithObjects:AIAccountCardAccount, AIAccountCardPersonal,
									  AIAccountCardOptions, AIAccountCardMore, AIAccountCardPrivacy, nil])
			[self cardWithIdentifier:identifier];

		[self describe];
	}

	return cards;
}

/*!
 * @brief The card of that name, opened at the end if it is not there yet
 *
 * Cards come out in the order they are first asked for, so a subclass adding to a card the base class
 * already opened lands underneath it rather than in a second card of the same name.
 */
- (AIAccountPlanCard *)cardWithIdentifier:(NSString *)cardIdentifier
{
	for (AIAccountPlanCard *card in cards) {
		if ([[card identifier] isEqualToString:cardIdentifier])
			return card;
	}

	AIAccountPlanCard *card = [[AIAccountPlanCard alloc] init];
	[card setIdentifier:cardIdentifier];
	[cards addObject:card];

	return card;
}

- (void)addField:(AIAccountPlanField *)field toCard:(NSString *)cardIdentifier
{
	if (field)
		[[self cardWithIdentifier:cardIdentifier] addField:field];
}

- (BOOL)offersPassword
{
	return [[account service] supportsPassword];
}

- (BOOL)offersReadReceipts
{
	return YES;
}

- (void)describe
{
	AIService *service = [account service];

	//What this account is called on its service
	AIAccountPlanField *uid = [AIAccountPlanField fieldNamed:@"name" kind:AIAccountFieldText];
	[uid setStore:AIAccountFieldStoreAccountName];
	[uid setLabel:[service userNameLabel]];
	[uid setPlaceholder:[service UIDPlaceholder]];
	[uid setDisabledWhileOnline:YES];

	/* A service whose account names are phone numbers takes them in international form only; say so
	 * under the field, because the national spelling can be typed and connects to nobody. The form
	 * itself is enforced in -setValue:forField:. */
	if ([service userNamesArePhoneNumbers])
		[uid setDetail:AILocalizedString(@"International format with country code, for example +4917012345678",
										 "Under the account name of phone number services: the only accepted form")];

	[self addField:uid toCard:AIAccountCardAccount];

	if ([self offersPassword]) {
		AIAccountPlanField *password = [AIAccountPlanField fieldNamed:@"password" kind:AIAccountFieldText];
		[password setStore:AIAccountFieldStorePassword];
		[password setSecure:YES];
		[password setLabel:AILocalizedString(@"Password", nil)];
		[self addField:password toCard:AIAccountCardAccount];
	}

	//The name other people see, which falls back to the one set for every account
	AIAccountPlanField *displayName = [AIAccountPlanField fieldNamed:@"displayName" kind:AIAccountFieldText];
	[displayName setStore:AIAccountFieldStorePreference];
	[displayName setPreferenceKey:KEY_ACCOUNT_DISPLAY_NAME];
	[displayName setAttributed:YES];
	[displayName setLabel:AILocalizedString(@"Display Name", nil)];
	[displayName setPlaceholder:[[[adium.preferenceController preferenceForKey:KEY_ACCOUNT_DISPLAY_NAME
																		group:GROUP_ACCOUNT_STATUS] attributedString] string]];
	[self addField:displayName toCard:AIAccountCardPersonal];

	/* Two things the other side is told, so the row says what is allowed rather than naming the
	 * setting. Both are stored as what they switch off. */
	AIAccountPlanField *typing = [AIAccountPlanField fieldNamed:@"typing" kind:AIAccountFieldSwitch];
	[typing setStore:AIAccountFieldStorePreference];
	[typing setPreferenceKey:KEY_DISABLE_TYPING_NOTIFICATIONS];
	[typing setInverted:YES];
	/* What is stored is what it switches off, so "not disabled" is the default and the row shows it
	 * as on. Telling the other side is what every messenger does unless it is asked not to. */
	[typing setDefaultValue:[NSNumber numberWithBool:NO]];
	[typing setLabel:AILocalizedString(@"Let others know when I am typing",
									   "Account privacy row: whether typing is reported to the other side")];
	[self addField:typing toCard:AIAccountCardPrivacy];

	if ([self offersReadReceipts]) {
		AIAccountPlanField *receipts = [AIAccountPlanField fieldNamed:@"readReceipts" kind:AIAccountFieldSwitch];
		[receipts setStore:AIAccountFieldStorePreference];
		[receipts setPreferenceKey:KEY_DISABLE_READ_RECEIPTS];
		[receipts setInverted:YES];
		[receipts setDefaultValue:[NSNumber numberWithBool:NO]];
		[receipts setLabel:AILocalizedString(@"Let others know when I have read their messages",
											 "Account privacy row: whether read receipts are sent")];
		[self addField:receipts toCard:AIAccountCardPrivacy];
	}

	//Encryption is a choice, not a permission, so it keeps its name
	AIAccountPlanField *encryption = [AIAccountPlanField fieldNamed:@"encryption" kind:AIAccountFieldEncryption];
	[encryption setStore:AIAccountFieldStorePreference];
	[encryption setPreferenceKey:KEY_ENCRYPTED_CHAT_PREFERENCE];
	[encryption setPreferenceGroup:GROUP_ENCRYPTION];
	[encryption setLabel:AILocalizedString(@"Encryption", nil)];
	[self addField:encryption toCard:AIAccountCardPrivacy];
}

//Values -----------------------------------------------------------------------------------------
#pragma mark Values

- (id)valueForField:(AIAccountPlanField *)field
{
	switch ([field store]) {
		case AIAccountFieldStoreAccountName:
			return [account formattedUID];

		case AIAccountFieldStorePassword:
			return [adium.accountController passwordForAccount:account];

		case AIAccountFieldStorePreference: {
			id stored = [account preferenceForKey:[field preferenceKey] group:[field preferenceGroup]];

			if (!stored && [field legacyKey]) {
				stored = [account preferenceForKey:[field legacyKey] group:[field preferenceGroup]];

				/* Purely a move: written where the field lives now, and the old key is left alone so
				 * that going back a version loses nothing. */
				if (stored)
					[account setPreference:stored forKey:[field preferenceKey] group:[field preferenceGroup]];
			}

			if (!stored)
				stored = [field defaultValue];

			if (!stored)
				return nil;

			if ([field attributed])
				return [[stored attributedString] string];

			if ([field inverted])
				return [NSNumber numberWithBool:![stored boolValue]];

			return stored;
		}

		case AIAccountFieldStoreNone:
			break;
	}

	return nil;
}

/*!
 * @brief The international form of a phone number, or nil where none can be read
 *
 * The grouping people type is dropped and the 00 exit code spelling becomes the plus; what remains
 * must be a plus followed by digits that do not begin with another zero. A number in national form
 * is refused rather than completed: the country code it lacks is the one part nobody can invent.
 */
static NSString *AIInternationalPhoneNumber(NSString *entered)
{
	NSMutableString *number = [entered mutableCopy];
	NSCharacterSet *grouping = [NSCharacterSet characterSetWithCharactersInString:@" ./-()\u00A0"];

	for (NSUInteger index = [number length]; index > 0; index--) {
		if ([grouping characterIsMember:[number characterAtIndex:index - 1]])
			[number deleteCharactersInRange:NSMakeRange(index - 1, 1)];
	}

	if ([number hasPrefix:@"00"])
		[number replaceCharactersInRange:NSMakeRange(0, 2) withString:@"+"];

	if (![number hasPrefix:@"+"] || [number length] < 7)
		return nil;

	NSString *digits = [number substringFromIndex:1];

	if ([digits hasPrefix:@"0"])
		return nil;	//National form wearing a plus

	NSCharacterSet *notADigit = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
	if ([digits rangeOfCharacterFromSet:notADigit].location != NSNotFound)
		return nil;

	return number;
}

- (void)setValue:(id)value forField:(AIAccountPlanField *)field
{
	switch ([field store]) {
		case AIAccountFieldStoreAccountName: {
			NSString *newUID = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

			/* Phone number services take the international form only: the national spelling can be
			 * typed, reaches nobody on any of them, and cannot be completed automatically. What can
			 * be read as international is normalized; what cannot is refused with a beep, and the
			 * page puts the name the account kept back into the field. */
			if ([newUID length] && [[account service] userNamesArePhoneNumbers]) {
				newUID = AIInternationalPhoneNumber(newUID);

				if (!newUID) {
					NSBeep();
					break;
				}
			}

			/* Never to nothing. An account renamed to the empty string loses the name its stored
			 * settings and its message history are filed under, and a field is empty at some point
			 * during every edit. */
			if ([newUID length] &&
				(![[account UID] isEqualToString:newUID] || ![[account formattedUID] isEqualToString:newUID]))
				[account filterAndSetUID:newUID];

			break;
		}

		case AIAccountFieldStorePassword: {
			NSString *password = value;
			NSString *oldPassword = [adium.accountController passwordForAccount:account];

			if ([password length]) {
				if (![password isEqualToString:oldPassword])
					[adium.accountController setPassword:password forAccount:account];

				passwordWasShown = YES;
			} else if ([oldPassword length] && passwordWasShown) {
				//Emptied by the user, not merely empty because the keychain had nothing to say earlier
				[adium.accountController forgetPasswordForAccount:account];
			}

			break;
		}

		case AIAccountFieldStorePreference: {
			id stored = value;

			if ([field attributed])
				stored = ([value length] ? [[NSAttributedString stringWithString:value] dataRepresentation] : nil);
			else if ([field inverted])
				stored = [NSNumber numberWithBool:![value boolValue]];
			else if ([value isKindOfClass:[NSString class]] && ![value length])
				stored = nil;

			[account setPreference:stored forKey:[field preferenceKey] group:[field preferenceGroup]];
			break;
		}

		case AIAccountFieldStoreNone:
			break;
	}
}

- (BOOL)fieldIsEnabled:(AIAccountPlanField *)field
{
	if ([field disabledWhileOnline] && [account online])
		return NO;

	return YES;
}

- (void)performActionForField:(AIAccountPlanField *)field
{
	SEL selector = [field action];

	if (selector && [self respondsToSelector:selector])
		/* Void callback selector; no returned object to leak. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[self performSelector:selector withObject:field];
#pragma clang diagnostic pop
}

@end
