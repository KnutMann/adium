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

#import "AIAddressBookController.h"

#import <Contacts/Contacts.h>
#import <Adium/AIControllerProtocol.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIMenuControllerProtocol.h>
#import <Adium/AIAccount.h>
#import <Adium/AIListObject.h>
#import <Adium/AIMetaContact.h>
#import <Adium/AIService.h>
#import <Adium/AIUserIcons.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIDictionaryAdditions.h>
#import <AIUtilities/AIMutableOwnerArray.h>
#import <AIUtilities/AIStringAdditions.h>
#import <AIUtilities/AIFileManagerAdditions.h>
#import <AIUtilities/AIImageAdditions.h>

#import "AIAddressBookUserIconSource.h"

#define SHOW_IN_AB_CONTEXTUAL_MENU_TITLE AILocalizedString(@"Show In Address Book", "Show In Address Book Contextual Menu")
#define EDIT_IN_AB_CONTEXTUAL_MENU_TITLE AILocalizedString(@"Edit In Address Book", "Edit In Address Book Contextual Menu")

/* The version is part of the name so that a change to what gets installed runs once more on a
 * Mac where the previous set is already lying about. Raised when the actions for services
 * Adium no longer has were taken back out. */
#define KEY_ADDRESS_BOOK_ACTIONS_INSTALLED	@"Adium:Installed Address Book Actions 2.0"

#define KEY_AB_TO_METACONTACT_DICT			@"UniqueIDToMetaContactObjectIDDictionary"

/*!
 * @brief The Jabber field's name, as the search window files it
 *
 * The old framework had a per-service card field of this name; the modern one
 * files the same information under instant-message entries whose service is
 * Jabber. The name survives as the token the service mapping trades in.
 */
#define AB_JABBER_INSTANT_PROPERTY	@"JabberInstant"

@interface AIAddressBookController()
+ (AIAddressBookPerson *)_searchForUID:(NSString *)UID serviceID:(NSString *)serviceID;
- (void)updateAllContacts;
- (void)updateSelfIncludingIcon:(BOOL)includeIcon;
- (NSString *)nameForPerson:(AIAddressBookPerson *)person phonetic:(NSString **)phonetic;
- (NSSet *)applyPerson:(AIAddressBookPerson *)person toContact:(AIListContact *)listContact silent:(BOOL)silent;
- (void)rebuildAddressBookDict;
- (void)rebuildAddressBookDictSoon;
- (void)showInAddressBook;
- (void)editInAddressBook;
- (void)installAddressBookActions;
- (void)openAddressBookWhenAllowed;
- (void)openAddressBook;
- (NSSet *)contactsForPerson:(AIAddressBookPerson *)person;

- (void)adiumFinishedLaunching:(NSNotification *)notification;
- (void)addressBookChanged:(NSNotification *)notification;
- (void)accountListChanged:(NSNotification *)notification;
@end

/*!
 * @class AIAddressBookController
 * @brief Provides Contacts integration
 *
 * One question is answered here: which card belongs to this contact. Two answer
 * paths, in this order: a link the user made, else a search over the card's
 * chat names, phone numbers and email addresses. Names, pictures and the
 * metacontact grouping all hang off that one answer.
 *
 * The data comes from Contacts.framework. The deprecated AddressBook framework,
 * which this class grew up on, is gone from it; the stored links keep working
 * unchanged, because the store's identifiers turn out to be the old framework's
 * own, ":ABPerson" suffix included - see AINormalizedUniqueId.
 */
@implementation AIAddressBookController

static AIAddressBookController	*addressBookController = nil;
static CNContactStore			*sharedStore = nil;
static NSMutableDictionary		*personCache = nil;			//uniqueId → AIAddressBookPerson
static NSString					*meUniqueId = nil;
static NSMutableDictionary		*addressBookDict = nil;
static NSDictionary				*serviceDict = nil;

/*!
 * @brief Where phone numbers are indexed
 *
 * Not a service, so it cannot collide with one: a card's numbers are filed here and looked up by any
 * service that says its names are numbers.
 */
#define AB_PHONE_NUMBERS	@"\1phone numbers"

/*!
 * @brief Where email addresses are indexed
 *
 * Same arrangement as the numbers above, and for the same reason: a service whose names are
 * addresses can look a card up by one without an entry of its own having to exist on the card.
 */
#define AB_EMAIL_ADDRESSES	@"\1email addresses"

/*!
 * @brief What two phone numbers have to share to be the same person
 *
 * Numbers are written down every way there is: +49 157 …, 0157 …, 004915 …, with spaces, dashes and
 * brackets. Comparing the digits alone still leaves the country code, which one side usually has and
 * the other usually has not, so the last nine are what is compared. That is one rule for the whole
 * problem, and short enough numbers, which are not mobile numbers anyway, simply never match.
 */
static NSString *AIPhoneNumberKey(NSString *number)
{
	NSMutableString *digits = [NSMutableString string];
	NSRange			 at = [number rangeOfString:@"@"];

	/* A name may arrive as a whole address, and then only the part in front of the @ could be a
	 * number. What follows it also says whether it is one at all: WhatsApp hands out @lid names
	 * beside @s.whatsapp.net ones, and a lid is an opaque fifteen digit identifier that no more
	 * belongs to a person's phone than a serial number does. Left in, its last nine digits would
	 * happily match somebody's real number and attach the wrong card. */
	if (at.location != NSNotFound) {
		if ([[number substringFromIndex:NSMaxRange(at)] caseInsensitiveCompare:@"lid"] == NSOrderedSame)
			return nil;

		number = [number substringToIndex:at.location];
	}

	for (NSUInteger i = 0; i < [number length]; i++) {
		unichar c = [number characterAtIndex:i];

		if (c >= '0' && c <= '9')
			[digits appendFormat:@"%C", c];
	}

	if ([digits length] < 9)
		return nil;

	return [digits substringFromIndex:([digits length] - 9)];
}

/*!
 * @brief What two email addresses have to share to be the same person
 *
 * Far less work than a phone number, because an address is already written one way. Case is the
 * only thing that varies in practice, and no mail system in use treats two addresses differing
 * only in case as two people.
 */
static NSString *AIEmailKey(NSString *address)
{
	NSString *trimmed = [address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if (![trimmed length] || ([trimmed rangeOfString:@"@"].location == NSNotFound))
		return nil;

	return [trimmed lowercaseString];
}

/*!
 * @brief A stored card identifier, brought into the store's form
 *
 * Measured, not assumed: on macOS the Contacts store hands out identifiers in
 * the old framework's own shape, UUID plus ":ABPerson", and a lookup with the
 * bare UUID answers "Updated Record Does Not Exist". Old links therefore fit
 * as they are; a bare UUID from anywhere else gets the suffix put on.
 */
static NSString *AINormalizedUniqueId(NSString *uniqueId)
{
	if ([uniqueId rangeOfString:@":"].location == NSNotFound)
		return [uniqueId stringByAppendingString:@":ABPerson"];

	return uniqueId;
}

/*!
 * @brief The card fields one fetch reads for the cache
 *
 * Everything the lookups and the name derivation use. Pictures are deliberately
 * absent: they are big, rarely needed, and fetched per card on demand.
 */
static NSArray *AIContactKeysToFetch(void)
{
	return [NSArray arrayWithObjects:
			CNContactIdentifierKey,
			CNContactTypeKey,
			CNContactGivenNameKey,
			CNContactMiddleNameKey,
			CNContactFamilyNameKey,
			CNContactNicknameKey,
			CNContactOrganizationNameKey,
			CNContactPhoneticGivenNameKey,
			CNContactPhoneticMiddleNameKey,
			CNContactPhoneticFamilyNameKey,
			CNContactEmailAddressesKey,
			CNContactPhoneNumbersKey,
			CNContactInstantMessageAddressesKey,
			nil];
}

+ (void) startAddressBookIntegration
{
	if(!addressBookController)
		addressBookController = [[self alloc] init];
}

- (id)init
{
	if ((self = [super init]))
	{
		addressBookDict = nil;
		createMetaContacts = NO;

		personUniqueIdToMetaContactDict = [[NSMutableDictionary alloc] init];

		//Configure our preferences
		[adium.preferenceController registerDefaults:[NSDictionary dictionaryNamed:AB_DISPLAYFORMAT_DEFAULT_PREFS forClass:[self class]]
						      forGroup:PREF_GROUP_ADDRESSBOOK];

		//We want the enableImport preference immediately (without waiting for the preferences observer to be registered in adiumFinishedLaunching:)
		enableImport = [[adium.preferenceController preferenceForKey:KEY_AB_ENABLE_IMPORT
															   group:PREF_GROUP_ADDRESSBOOK] boolValue];

		//If Address Book integration is enabled, we need those preferences to determine contact's names
		if (enableImport) {
			displayFormat = [[adium.preferenceController preferenceForKey:KEY_AB_DISPLAYFORMAT
																	group:PREF_GROUP_ADDRESSBOOK] retain];
			useFirstName = [[adium.preferenceController preferenceForKey:KEY_AB_USE_FIRSTNAME
																   group:PREF_GROUP_ADDRESSBOOK] boolValue];
			useNickNameOnly = [[adium.preferenceController preferenceForKey:KEY_AB_USE_NICKNAME
																	  group:PREF_GROUP_ADDRESSBOOK] boolValue];
		}

		//If old format-menu preference is set, perform migration
		if ([adium.preferenceController preferenceForKey:@"AB Display Format" group:PREF_GROUP_ADDRESSBOOK]) {

			[displayFormat release];

			NSInteger oldPreference = [[adium.preferenceController preferenceForKey:@"AB Display Format" group:PREF_GROUP_ADDRESSBOOK] integerValue];

			switch (oldPreference) {
				case 0: //firstlast
					displayFormat = [[NSString alloc] initWithFormat:@"%@ %@", FORMAT_FIRST_FULL, FORMAT_LAST_FULL];
					break;
				case 1: //first
					displayFormat = [FORMAT_FIRST_FULL retain];
					break;
				case 2: //lastfirst
					displayFormat = [[NSString alloc] initWithFormat:@"%@, %@", FORMAT_LAST_FULL, FORMAT_FIRST_FULL];
					break;
				case 3: //lastfirstnocomma
					displayFormat = [[NSString alloc] initWithFormat:@"%@ %@", FORMAT_LAST_FULL, FORMAT_FIRST_FULL];
					break;
				case 4: //firstlastinitial
					displayFormat = [[NSString alloc] initWithFormat:@"%@ %@", FORMAT_FIRST_FULL, FORMAT_LAST_INITIAL];
					break;
				default:
					displayFormat = [[NSString alloc] initWithFormat:@"%@ %@", FORMAT_FIRST_FULL, FORMAT_LAST_FULL];
			}

			[adium.preferenceController setPreference:nil forKey:@"AB Display Format" group:PREF_GROUP_ADDRESSBOOK];
			[adium.preferenceController setPreference:displayFormat
											   forKey:KEY_AB_DISPLAYFORMAT
												group:PREF_GROUP_ADDRESSBOOK];
		}

		/* Two elements with nothing between them, "%[FIRSTFULL]%[LASTFULL]", which reads as
		 * "JohnSmith". The format is assembled from the pieces in the settings and the separator
		 * between them went missing on the way in, and nothing downstream puts one back: the name is
		 * built by replacing the elements and by nothing else. Repaired once rather than on every
		 * read, so that anyone who really wants them run together can say so and be left alone. */
		if ([displayFormat rangeOfString:@"]%["].location != NSNotFound) {
			NSString *repaired = [displayFormat stringByReplacingOccurrencesOfString:@"]%[" withString:@"] %["];

			[displayFormat release];
			displayFormat = [repaired retain];

			[adium.preferenceController setPreference:displayFormat
											   forKey:KEY_AB_DISPLAYFORMAT
												group:PREF_GROUP_ADDRESSBOOK];
		}

		/* Which card field holds a name for which service. One entry: Jabber. What the modern
		 * services are recognised by is not a field of their own but the number or the address on
		 * the card, which is indexed separately. */
		serviceDict = [[NSDictionary dictionaryWithObjectsAndKeys:AB_JABBER_INSTANT_PROPERTY,@"Jabber", nil] retain];

		//The contact store, once we are allowed to read it
		[self openAddressBookWhenAllowed];

		[self installAddressBookActions];

		//Wait for Adium to finish launching before we build the address book so the contact list will be ready
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(adiumFinishedLaunching:)
													 name:AIApplicationDidFinishLoadingNotification
												   object:nil];

		//Update self immediately so the information is available to plugins and interface elements as they load
		[self updateSelfIncludingIcon:YES];
	}
	return self;
}

/*!
 * @brief Open the contact store, once the user has allowed us to read it
 *
 * Reading contacts has needed consent since Catalina. Until it is given the store answers empty
 * rather than refusing, which from here is indistinguishable from an address book with nobody in it.
 *
 * Nothing is asked twice: once denied, the system does not put the question up again, and once
 * granted the answer is remembered across launches.
 */
- (void)openAddressBookWhenAllowed
{
	switch ([CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts]) {
		case CNAuthorizationStatusAuthorized:
			[self openAddressBook];
			break;

		case CNAuthorizationStatusNotDetermined:
			[[[[CNContactStore alloc] init] autorelease] requestAccessForEntityType:CNEntityTypeContacts
																 completionHandler:^(BOOL granted, NSError *error) {
				if (!granted)
					return;

				/* The answer comes back on a queue of its own, and everything below here touches the
				 * contact list. Granting also arrives after the launch that would normally have read
				 * the address book, so this does that work as well rather than waiting for a restart. */
				dispatch_async(dispatch_get_main_queue(), ^{
					[self openAddressBook];
					[self rebuildAddressBookDict];
					[self updateAllContacts];
					[self updateSelfIncludingIcon:YES];
				});
			}];
			break;

		default:
			AILogWithSignature(@"No permission to read contacts; the address book stays closed");
			break;
	}
}

- (void)openAddressBook
{
	[sharedStore release];
	sharedStore = [[CNContactStore alloc] init];
}

- (void)installAddressBookActions
{
	NSNumber		*installedActions = [[NSUserDefaults standardUserDefaults] objectForKey:KEY_ADDRESS_BOOK_ACTIONS_INSTALLED];

	if (!installedActions || ![installedActions boolValue]) {
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSArray		  *libraryDirectoryArray;
		NSString	  *libraryDirectory, *pluginDirectory;

		libraryDirectoryArray = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
		if ([libraryDirectoryArray count]) {
			libraryDirectory = [libraryDirectoryArray objectAtIndex:0];

		} else {
			//Ridiculous safety since everyone should have a Library folder...
			libraryDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library"];
			[fileManager createDirectoryAtPath:libraryDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
		}

		pluginDirectory = [[libraryDirectory stringByAppendingPathComponent:@"Address Book Plug-Ins"] stringByAppendingPathComponent:@"/"];
		[fileManager createDirectoryAtPath:pluginDirectory withIntermediateDirectories:YES attributes:nil error:NULL];

		/* Take back the ones for services Adium no longer has. They were put here by earlier
		 * versions, they can only ever offer to start a conversation on a network that is gone, and
		 * leaving somebody else's Library tidier than we left it is the least this can do. Trashed
		 * rather than deleted, so anybody who wants them back can take them out again. */
		for (NSString *name in [NSArray arrayWithObjects:@"AIM", @"MSN", @"Yahoo", @"ICQ", @"SMS", nil]) {
			NSString *fullName = [NSString stringWithFormat:@"AdiumAddressBookAction_%@", name];

			[fileManager trashFileAtPath:[pluginDirectory stringByAppendingPathComponent:
				[fullName stringByAppendingPathExtension:@"scpt"]]];
			[fileManager trashFileAtPath:[pluginDirectory stringByAppendingPathComponent:
				[NSString stringWithFormat:@"%@-Adium.scpt", name]]];
		}

		for (NSString *name in [NSArray arrayWithObject:@"Jabber"]) {
			NSString *fullName = [NSString stringWithFormat:@"AdiumAddressBookAction_%@",name];
			NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:fullName ofType:@"scpt"];

			if (path) {
				NSString *destination = [pluginDirectory stringByAppendingPathComponent:[fullName stringByAppendingPathExtension:@"scpt"]];
				[fileManager trashFileAtPath:destination];
				[fileManager copyItemAtPath:path
							   toPath:destination
							  error:NULL];

				//Remove the old xtra if installed
				[fileManager trashFileAtPath:[pluginDirectory stringByAppendingPathComponent:
					[NSString stringWithFormat:@"%@-Adium.scpt",name]]];
			} else {
				AILogWithSignature(@"Warning: Could not find %@ in %p.", fullName, self);
			}
		}

		[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES]
												  forKey:KEY_ADDRESS_BOOK_ACTIONS_INSTALLED];
	}
}

+ (void) stopAddressBookIntegration
{
	[[AIContactObserverManager sharedManager] unregisterListObjectObserver:addressBookController];
	[adium.preferenceController unregisterPreferenceObserver:addressBookController];
	[[NSNotificationCenter defaultCenter] removeObserver:addressBookController];

	[addressBookController release]; addressBookController = nil;
}

- (void)dealloc
{
	[serviceDict release]; serviceDict = nil;

	[sharedStore release]; sharedStore = nil;
	[personCache release]; personCache = nil;
	[meUniqueId release]; meUniqueId = nil;
	[addressBookDict release]; addressBookDict = nil;
	[personUniqueIdToMetaContactDict release]; personUniqueIdToMetaContactDict = nil;

	[[AIContactObserverManager sharedManager] unregisterListObjectObserver:self];
	[adium.preferenceController unregisterPreferenceObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[displayFormat release]; displayFormat = nil;

	[super dealloc];
}

/*!
 * @brief Adium finished launching
 *
 * Register our observers for the address book changing externally and for the account list changing.
 * Register our preference observers. This will trigger initial building of the address book dictionary.
 */
- (void)adiumFinishedLaunching:(NSNotification *)notification
{
	//Create our contextual menus
	showInABContextualMenuItem = [[[NSMenuItem alloc] initWithTitle:SHOW_IN_AB_CONTEXTUAL_MENU_TITLE
											   action:@selector(showInAddressBook)
										    keyEquivalent:@""] autorelease];
	[showInABContextualMenuItem setTarget:self];
	[showInABContextualMenuItem setTag:AIRequiresAddressBookEntry];

	editInABContextualMenuItem = [[[NSMenuItem alloc] initWithTitle:EDIT_IN_AB_CONTEXTUAL_MENU_TITLE
											   action:@selector(editInAddressBook)
										    keyEquivalent:@""] autorelease];
	[editInABContextualMenuItem setTarget:self];
	[editInABContextualMenuItem setKeyEquivalentModifierMask:NSEventModifierFlagOption];
	[editInABContextualMenuItem setAlternate:YES];
	[editInABContextualMenuItem setTag:AIRequiresAddressBookEntry];


	//Install our menus
	[adium.menuController addContextualMenuItem:showInABContextualMenuItem toLocation:Context_Contact_Action];
	[adium.menuController addContextualMenuItem:editInABContextualMenuItem toLocation:Context_Contact_Action];

	/* Observe external address book changes. The store never says what changed, only that
	 * something did, so every change is a coalesced full rebuild. */
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(addressBookChanged:)
												 name:CNContactStoreDidChangeNotification
											   object:nil];

	//Observe account changes
	[[NSNotificationCenter defaultCenter] addObserver:self
										selector:@selector(accountListChanged:)
									   name:Account_ListChanged
									 object:nil];

	//Observe preferences changes
	id<AIPreferenceController> preferenceController = adium.preferenceController;
	[preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_ADDRESSBOOK];
	[preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_USERICONS];

	addressBookUserIconSource = [[AIAddressBookUserIconSource alloc] init];
	[AIUserIcons registerUserIconSource:addressBookUserIconSource];
}

/*!
 * @brief Used as contacts are created and icons are changed.
 *
 * When first created, load a contact's address book information from our dict.
 */
- (NSSet *)updateListObject:(AIListObject *)inObject keys:(NSSet *)inModifiedKeys silent:(BOOL)silent
{
	AIListContact	*listContact;
	NSSet			*modifiedAttributes = nil;

	//Just stop here if we don't have an address book dict to work with
	if (!addressBookDict) return nil;

	//We handle accounts separately; doing updates here causes chaos in addition to being inefficient.
	if ([inObject isKindOfClass:[AIAccount class]]) return nil;

	//Only contacts have associated address book info
	if (![inObject isKindOfClass:[AIListContact class]]) return nil;
	listContact = (AIListContact *)inObject;

    if (inModifiedKeys == nil) { //Only perform this when updating for all list objects or when a contact is created
		modifiedAttributes = [self applyPerson:[listContact addressBookPerson]
									 toContact:listContact
										silent:silent];
    }

    return modifiedAttributes;
}

/*!
 * @brief Apply (or clear) an address book card's name on a contact
 *
 * Shared by the observer path, which looks the person up from the stored preference, and by the
 * inspector's explicit assignment, which passes the card it has in hand.
 */
- (NSSet *)applyPerson:(AIAddressBookPerson *)person toContact:(AIListContact *)listContact silent:(BOOL)silent
{
	NSSet	*modifiedAttributes = nil;

	if (person && enableImport) {
		//Load the name if appropriate
		AIMutableOwnerArray *displayNameArray, *phoneticNameArray;
		NSString			*displayName, *phoneticName = nil;

		displayNameArray = [listContact displayArrayForKey:@"Display Name"];

		displayName = [self nameForPerson:person phonetic:&phoneticName];

		//Apply the values
		NSString *oldValue = [displayNameArray objectWithOwner:self];
		if (!oldValue || ![oldValue isEqualToString:displayName]) {
			[displayNameArray setObject:displayName withOwner:self];
			modifiedAttributes = [NSSet setWithObject:@"Display Name"];
		}

		if (phoneticName) {
			phoneticNameArray = [listContact displayArrayForKey:@"Phonetic Name"];

			//Apply the values
			oldValue = [phoneticNameArray objectWithOwner:self];
			if (!oldValue || ![oldValue isEqualToString:phoneticName]) {
				[phoneticNameArray setObject:phoneticName withOwner:self];
				modifiedAttributes = [NSSet setWithObjects:@"Display Name", @"Phonetic Name", nil];
			}
		} else {
			phoneticNameArray = [listContact displayArrayForKey:@"Phonetic Name"
														 create:NO];
			/* Clear any stored value. This used to null the display name it had just set,
			 * whenever a card without a phonetic name replaced one that had one. */
			if ([phoneticNameArray objectWithOwner:self]) {
				[phoneticNameArray setObject:nil withOwner:self];
				modifiedAttributes = [NSSet setWithObjects:@"Display Name", @"Phonetic Name", nil];
			}
		}

	} else {
		AIMutableOwnerArray *displayNameArray, *phoneticNameArray;

		displayNameArray = [listContact displayArrayForKey:@"Display Name"
													create:NO];

		//Clear any stored value
		if ([displayNameArray objectWithOwner:self]) {
			[displayNameArray setObject:nil withOwner:self];
			modifiedAttributes = [NSSet setWithObject:@"Display Name"];
		}

		phoneticNameArray = [listContact displayArrayForKey:@"Phonetic Name"
													 create:NO];
		//Clear any stored value
		if ([phoneticNameArray objectWithOwner:self]) {
			[phoneticNameArray setObject:nil withOwner:self];
			modifiedAttributes = [NSSet setWithObjects:@"Display Name", @"Phonetic Name", nil];
		}

	}

	//If we changed anything, request an update of the alias / long display name
	if (modifiedAttributes) {
		[[NSNotificationCenter defaultCenter] postNotificationName:Contact_ApplyDisplayName
															object:listContact
														  userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:silent]
																							   forKey:@"Notify"]];
	}

	//Add this contact to the person's metacontact if it's not already there.
	if (person) {
		AIMetaContact *personMetaContact;
		if ((personMetaContact = [personUniqueIdToMetaContactDict objectForKey:[person uniqueId]]) &&
			(personMetaContact != listContact) &&
			![personMetaContact containsObject:listContact]) {
			AILog(@"AIAddressBookController: personMetaContact = %@; listContact = %@; performing metacontact grouping",
				  personMetaContact, listContact);
			[adium.contactController groupContacts:[NSArray arrayWithObjects:personMetaContact, listContact, nil]];
		}
	}

	return modifiedAttributes;
}

/*!
 * @brief The inspector assigned a card to (or removed one from) a contact
 *
 * Applies the choice right away, with the very card that was picked. Passing nil re-derives from
 * the stored preference and search, for the removal case.
 */
+ (void)userAssignedPerson:(AIAddressBookPerson *)person toContact:(AIListContact *)contact
{
	if (!addressBookController || !contact) return;

	AIListContact	*owner = contact.parentContact ?: contact;
	NSSet			*modified = [addressBookController applyPerson:(person ?: [owner addressBookPerson])
														 toContact:owner
															silent:NO];

	if (modified)
		[[AIContactObserverManager sharedManager] listObjectAttributesChanged:owner
																 modifiedKeys:modified];
}

/*!
 * @brief Return the name of a person in the way Adium should display it
 *
 * @param person An <tt>AIAddressBookPerson</tt>
 * @param phonetic A pointer to an <tt>NSString</tt> which will be filled with the phonetic display name if available
 * @result A string based on the first name, middle name, last name, and/or nickname of the person, as specified via preferences.
 */
- (NSString *)nameForPerson:(AIAddressBookPerson *)person phonetic:(NSString **)phonetic
{
	NSString *firstName = person.firstName;
	NSString *middleName = person.middleName;
	NSString *lastName = person.lastName;
	NSString *nickName = person.nickname;
	NSString *phoneticFirstName = person.phoneticFirstName;
	NSString *phoneticMiddleName = person.phoneticMiddleName;
	NSString *phoneticLastName = person.phoneticLastName;

	//The wrapper hands back empty strings where the old framework handed back nil; treat them alike
	if (![firstName length]) firstName = nil;
	if (![middleName length]) middleName = nil;
	if (![lastName length]) lastName = nil;
	if (![nickName length]) nickName = nil;
	if (![phoneticFirstName length]) phoneticFirstName = nil;
	if (![phoneticMiddleName length]) phoneticMiddleName = nil;
	if (![phoneticLastName length]) phoneticLastName = nil;

	NSString *displayName = displayFormat;

	// Fallback if format string is empty or unexpected
	if (!displayName || ![displayName isKindOfClass:[NSString class]] || [displayName isEqualToString:@""]) {
		displayName = FORMAT_FIRST_FULL;
	}

	// If the record is for a company, return the company name if present
	if (person.isCompany) {
		NSString *companyName = person.organization;
		if (companyName && [companyName length]) {
			return companyName;
		}
	}

	BOOL havePhonetic = ((phonetic != NULL) && (phoneticFirstName || phoneticMiddleName || phoneticLastName));

	if (useNickNameOnly && nickName && [nickName length] != 0)
		return nickName;

	if (useFirstName && (!nickName || [nickName isEqualToString:@""]) && firstName)
		nickName = firstName;


	displayName = [displayName stringByReplacingOccurrencesOfString:FORMAT_FIRST_FULL
														 withString:firstName ? firstName : @""];
	displayName = [displayName stringByReplacingOccurrencesOfString:FORMAT_FIRST_INITIAL
														 withString:([firstName length] > 0) ? [firstName substringToIndex:1] : @""];

	displayName = [displayName stringByReplacingOccurrencesOfString:FORMAT_MIDDLE_FULL
														 withString:middleName ? middleName : @""];
	displayName = [displayName stringByReplacingOccurrencesOfString:FORMAT_MIDDLE_INITIAL
														 withString:([middleName length] > 0) ? [middleName substringToIndex:1] : @""];

	displayName = [displayName stringByReplacingOccurrencesOfString:FORMAT_LAST_FULL
														 withString:lastName ? lastName : @""];
	displayName = [displayName stringByReplacingOccurrencesOfString:FORMAT_LAST_INITIAL
														 withString:([lastName length] > 0) ? [lastName substringToIndex:1] : @""];

	displayName = [displayName stringByReplacingOccurrencesOfString:FORMAT_NICK_FULL
														 withString:nickName ? nickName : @""];
	displayName = [displayName stringByReplacingOccurrencesOfString:FORMAT_NICK_INITIAL
														 withString:([nickName length] > 0) ? [nickName substringToIndex:1] : @""];

	if (havePhonetic) {
		*phonetic = displayFormat;

		*phonetic = [*phonetic stringByReplacingOccurrencesOfString:FORMAT_FIRST_FULL
														 withString:phoneticFirstName ? phoneticFirstName : @""];
		*phonetic = [*phonetic stringByReplacingOccurrencesOfString:FORMAT_FIRST_INITIAL
														 withString:([phoneticFirstName length] > 0) ? [phoneticFirstName substringToIndex:1] : @""];

		*phonetic = [*phonetic stringByReplacingOccurrencesOfString:FORMAT_MIDDLE_FULL
														 withString:phoneticMiddleName ? phoneticMiddleName : @""];
		*phonetic = [*phonetic stringByReplacingOccurrencesOfString:FORMAT_MIDDLE_INITIAL
														 withString:([phoneticMiddleName length] > 0) ? [phoneticMiddleName substringToIndex:1] : @""];

		*phonetic = [*phonetic stringByReplacingOccurrencesOfString:FORMAT_LAST_FULL
														 withString:phoneticLastName ? phoneticLastName : @""];
		*phonetic = [*phonetic stringByReplacingOccurrencesOfString:FORMAT_LAST_INITIAL
														 withString:([phoneticLastName length] > 0) ? [phoneticLastName substringToIndex:1] : @""];

		*phonetic = [*phonetic stringByReplacingOccurrencesOfString:FORMAT_NICK_FULL withString:@""];
		*phonetic = [*phonetic stringByReplacingOccurrencesOfString:FORMAT_NICK_INITIAL withString:@""];
	}

	return displayName;
}

/*!
 * @brief Observe preference changes
 *
 * On first call, this method builds the addressBookDict. Subsequently, it rebuilds the dict only if the "create metaContacts"
 * option is toggled, as metaContacts are created while building the dict.
 */
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	if (object) {
		[[AIContactObserverManager sharedManager] updateContacts:[NSSet setWithObject:object] forObserver:self];
		return;
	}

	if (![group isEqualToString:PREF_GROUP_ADDRESSBOOK] || [key isEqualToString:KEY_AB_TO_METACONTACT_DICT])
		return;

	BOOL			oldCreateMetaContacts = createMetaContacts;

	//load new displayFormat
	enableImport = [[prefDict objectForKey:KEY_AB_ENABLE_IMPORT] boolValue];
	useFirstName = [[prefDict objectForKey:KEY_AB_USE_FIRSTNAME] boolValue];
	useNickNameOnly = [[prefDict objectForKey:KEY_AB_USE_NICKNAME] boolValue];
	displayFormat = [[prefDict objectForKey:KEY_AB_DISPLAYFORMAT] retain];


	createMetaContacts = [[prefDict objectForKey:KEY_AB_CREATE_METACONTACTS] boolValue];

	if (firstTime) {
		//Build the address book dictionary, which will also trigger metacontact grouping as appropriate
		[self rebuildAddressBookDict];

		//Register ourself as a listObject observer, which will update all objects
		[[AIContactObserverManager sharedManager] registerListObjectObserver:self];

		//Note: we don't need to call updateSelfIncludingIcon: because it was already done in installPlugin
	} else {
		//This isn't the first time through

		//If we weren't creating meta contacts before but we are now
		if (!oldCreateMetaContacts && createMetaContacts) {
			/*
			 Build the address book dictionary, which will also trigger metacontact grouping as appropriate
			 Delay to the next run loop to give better UI responsiveness
			 */
			[self performSelector:@selector(rebuildAddressBookDict)
					   withObject:nil
					   afterDelay:0];
		}

		//Update all contacts, which will update objects and then our "me" card information
		[self updateAllContacts];
	}

}

/*!
 * @brief Returns the appropriate service for the property.
 *
 * @param property - a service field token, see AB_JABBER_INSTANT_PROPERTY.
 */
+ (AIService *)serviceFromProperty:(NSString *)property
{
	NSString	*serviceID = ([property isEqualToString:AB_JABBER_INSTANT_PROPERTY] ? @"Jabber" : nil);

	return (serviceID ? [adium.accountController firstServiceWithServiceID:serviceID] : nil);
}

/*!
 * @brief Returns the appropriate property for the service.
 */
+ (NSString *)propertyFromService:(AIService *)inService
{
	return [serviceDict objectForKey:inService.serviceID];
}

#pragma mark Searching

+ (NSArray *)allPeople
{
	return [personCache allValues];
}

+ (AIAddressBookPerson *)personForUniqueId:(NSString *)uniqueId
{
	if (![uniqueId length]) return nil;

	NSString			*normalized = AINormalizedUniqueId(uniqueId);
	AIAddressBookPerson	*person = [personCache objectForKey:normalized];

	if (!person && sharedStore) {
		//Not cached, perhaps not yet: ask the store directly
		CNContact *contact = [sharedStore unifiedContactWithIdentifier:normalized
														   keysToFetch:AIContactKeysToFetch()
																 error:NULL];
		person = [AIAddressBookPerson personWithContact:contact];
	}

	return person;
}

/*!
 * @brief Find a person corresponding to an AIListObject
 *
 * @param inObject The object for which it search
 * @result An AIAddressBookPerson if one is found, or nil if none is found
 */
+ (AIAddressBookPerson *)personForListObject:(AIListObject *)inObject
{
	AIAddressBookPerson	*person = nil;
	NSString	*uniqueID = [inObject preferenceForKey:KEY_AB_UNIQUE_ID group:PREF_GROUP_ADDRESSBOOK];
	if (!uniqueID) uniqueID = [inObject valueForProperty:KEY_AB_UNIQUE_ID];

	if (uniqueID)
		person = [self personForUniqueId:uniqueID];

	if (!person) {
		if ([inObject isKindOfClass:[AIMetaContact class]]) {
			//Search for the first person for a listContact within the metaContact
			for (AIListContact *listContact in [(AIMetaContact *)inObject listContactsIncludingOfflineAccounts]) {
				person = [self personForListObject:listContact];
				if (person)
					break;
			}
		} else {
			NSString		*UID = inObject.UID;
			NSString		*serviceID = inObject.service.serviceID;

			person = [self _searchForUID:UID serviceID:serviceID];

			/* A service whose names are numbers says so, and then the number is what identifies the
			 * person rather than a handle nobody wrote on their card. The service is asked instead of
			 * the string being guessed at, so a numeric name on some other service stays a name. */
			if (!person && inObject.service.userNamesArePhoneNumbers) {
				NSString *key = AIPhoneNumberKey(UID);
				NSString *uniqueId = (key ? [[addressBookDict objectForKey:AB_PHONE_NUMBERS] objectForKey:key] : nil);

				person = (uniqueId ? [self personForUniqueId:uniqueId] : nil);
			}

			/* And a number the contact brought with it rather than wears as a name. Telegram names
			 * a contact after a Telegram user id and knows the telephone number separately, when
			 * the person shares it; the protocol leaves it on the contact and it is looked up the
			 * same way as a name that is a number. Asking what the contact carries, rather than
			 * reading its name harder, is also what keeps the two apart: the last nine digits of a
			 * Telegram user id would match somebody's real number sooner or later. */
			if (!person && [inObject isKindOfClass:[AIListContact class]]) {
				NSString *carried = [inObject valueForProperty:KEY_CONTACT_PHONE_NUMBER];
				NSString *key = ([carried length] ? AIPhoneNumberKey(carried) : nil);
				NSString *uniqueId = (key ? [[addressBookDict objectForKey:AB_PHONE_NUMBERS] objectForKey:key] : nil);

				person = (uniqueId ? [self personForUniqueId:uniqueId] : nil);
			}

			//The same again for a service whose names are email addresses, Teams above all
			if (!person && inObject.service.userNamesAreEmailAddresses) {
				NSString *key = AIEmailKey(UID);
				NSString *uniqueId = (key ? [[addressBookDict objectForKey:AB_EMAIL_ADDRESSES] objectForKey:key] : nil);

				person = (uniqueId ? [self personForUniqueId:uniqueId] : nil);
			}

		}
	}

	return person;
}

/*!
 * @brief Find a person for a given UID and serviceID combination
 *
 * Uses our addressBookDict cache created in rebuildAddressBookDict.
 */
+ (AIAddressBookPerson *)_searchForUID:(NSString *)UID serviceID:(NSString *)serviceID
{
	NSDictionary	*dict = [addressBookDict objectForKey:serviceID];

	if (dict) {
		NSString *uniqueID = [dict objectForKey:[UID compactedString]];
		if (uniqueID)
			return [self personForUniqueId:uniqueID];
	}

	return nil;
}

#pragma mark -

- (NSSet *)contactsForPerson:(AIAddressBookPerson *)person
{
	NSMutableSet	*contactSet = [NSMutableSet set];

	/* The one case where an email address is also a chat name: a Jabber account at Google is
	 * reached under the same address. */
	for (NSString *email in person.emailAddresses) {
		if ([email hasSuffix:@"gmail.com"] || [email hasSuffix:@"googlemail.com"]) {
			NSSet	*contacts = [adium.contactController allContactsWithService:[adium.accountController firstServiceWithServiceID:@"Jabber"]
																			UID:email];

			[contactSet unionSet:contacts];
		}
	}

	//And the card's Jabber names
	for (NSString *name in person.jabberNames) {
		NSString *UID = [name compactedString];

		if ([UID length]) {
			NSSet	*contacts = [adium.contactController allContactsWithService:[adium.accountController firstServiceWithServiceID:@"Jabber"]
																			UID:UID];

			[contactSet unionSet:contacts];
		}
	}

	return contactSet;
}

#pragma mark Address book changed
/*!
 * @brief Address book changed externally
 *
 * The store's change notification names nothing: not who changed, not how many, sometimes not even
 * on the main thread. Every change is therefore a coalesced full rebuild followed by a full contact
 * update, which for address books of ordinary size costs nothing worth optimizing away.
 */
- (void)addressBookChanged:(NSNotification *)notification
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self rebuildAddressBookDictSoon];
	});
}

- (void)rebuildAddressBookDictSoon
{
	if (rebuildScheduled) return;

	rebuildScheduled = YES;
	[self performSelector:@selector(rebuildAddressBookDictAndUpdate) withObject:nil afterDelay:0.0];
}

- (void)rebuildAddressBookDictAndUpdate
{
	rebuildScheduled = NO;

	[self rebuildAddressBookDict];
	[self updateAllContacts];
}

/*!
 * @brief Update all existing contacts and accounts
 */
- (void)updateAllContacts
{
	[[AIContactObserverManager sharedManager] updateAllListObjectsForObserver:self];
    [self updateSelfIncludingIcon:YES];
}

/*!
 * @brief Account list changed: Update all existing accounts
 */
- (void)accountListChanged:(NSNotification *)notification
{
	[self updateSelfIncludingIcon:NO];
}

/*!
 * @brief Update all existing accounts
 *
 * We use the "me" card to determine the default icon and account display name
 */
- (void)updateSelfIncludingIcon:(BOOL)includeIcon
{
	if (!sharedStore) return;

	NSError		*error = nil;
	CNContact	*meContact = [sharedStore unifiedMeContactWithKeysToFetch:AIContactKeysToFetch() error:&error];
	AIAddressBookPerson *me = [AIAddressBookPerson personWithContact:meContact];

	if (!me) return;

	[meUniqueId release];
	meUniqueId = [me.uniqueId copy];

	//Default buddy icon
	if (includeIcon) {
		NSData *imageData = [me imageData];
		if (imageData) {
			[adium.preferenceController setPreference:imageData
											   forKey:KEY_DEFAULT_USER_ICON
												group:GROUP_ACCOUNT_STATUS];
		}
	}

	//Set account display names
	if (enableImport) {
		NSString *myPhonetic = nil;
		NSString *myDisplayName = [self nameForPerson:me phonetic:&myPhonetic];

		for (AIAccount *account in adium.accountController.accounts) {
			if (![account isTemporary]) {
				[[account displayArrayForKey:@"Display Name"] setObject:myDisplayName
															  withOwner:self
														  priorityLevel:Low_Priority];

				if (myPhonetic) {
					[[account displayArrayForKey:@"Phonetic Name"] setObject:myPhonetic
																   withOwner:self
															   priorityLevel:Low_Priority];
				}
			}
		}

		[adium.preferenceController registerDefaults:[NSDictionary dictionaryWithObject:[[NSAttributedString stringWithString:myDisplayName] dataRepresentation]
																				 forKey:KEY_ACCOUNT_DISPLAY_NAME]
											forGroup:GROUP_ACCOUNT_STATUS];
	}
}

#pragma mark Address book caching
/*!
 * @brief Rebuild our person cache and lookup dictionary
 *
 * One pass over the store fills the person cache (uniqueId to person) and the lookup dictionary:
 * per service the chat names, and under keys of their own the phone numbers and email addresses,
 * so a service that knows people by number or address can find a card without a field of its own
 * existing on it.
 *
 * Cards carrying more than one chat name become metacontacts here, when the option asks for it.
 */
- (void)rebuildAddressBookDict
{
	if (!sharedStore) return;

	//Delay listObjectNotifications to speed up metaContact creation
	[[AIContactObserverManager sharedManager] delayListObjectNotifications];

	[addressBookDict release]; addressBookDict = [[NSMutableDictionary alloc] init];
	[personCache release]; personCache = [[NSMutableDictionary alloc] init];

	CNContactFetchRequest	*request = [[[CNContactFetchRequest alloc] initWithKeysToFetch:AIContactKeysToFetch()] autorelease];
	NSMutableArray			*people = [NSMutableArray array];

	request.unifyResults = YES;
	[sharedStore enumerateContactsWithFetchRequest:request
											 error:NULL
										usingBlock:^(CNContact *contact, BOOL *stop) {
		AIAddressBookPerson *person = [AIAddressBookPerson personWithContact:contact];
		if (person) {
			[personCache setObject:person forKey:person.uniqueId];
			[people addObject:person];
		}
	}];

	for (AIAddressBookPerson *person in people) {
		NSString *uniqueId = person.uniqueId;

		/* The card's phone numbers, so that a service which identifies people by their number can
		 * find them. Deliberately not part of the metacontact grouping below: sharing a number is a
		 * good enough reason to look somebody up but not a good enough reason to merge them without
		 * being asked. */
		for (NSString *number in person.phoneNumbers) {
			NSString *key = AIPhoneNumberKey(number);
			if (!key) continue;

			NSMutableDictionary *phoneDict = [addressBookDict objectForKey:AB_PHONE_NUMBERS];
			if (!phoneDict) {
				phoneDict = [NSMutableDictionary dictionary];
				[addressBookDict setObject:phoneDict forKey:AB_PHONE_NUMBERS];
			}
			[phoneDict setObject:uniqueId forKey:key];
		}

		/* And the card's email addresses, for a service that knows people by one. Kept out of the
		 * grouping for the same reason as the numbers. */
		for (NSString *address in person.emailAddresses) {
			NSString *key = AIEmailKey(address);
			if (!key) continue;

			NSMutableDictionary *emailDict = [addressBookDict objectForKey:AB_EMAIL_ADDRESSES];
			if (!emailDict) {
				emailDict = [NSMutableDictionary dictionary];
				[addressBookDict setObject:emailDict forKey:AB_EMAIL_ADDRESSES];
			}
			[emailDict setObject:uniqueId forKey:key];
		}

		NSMutableArray	*UIDsArray = [NSMutableArray array];
		NSMutableArray	*servicesArray = [NSMutableArray array];

		/* A card's email addresses, for the one case where an address is also a chat name: a Jabber
		 * account at Google is reached under the same address. */
		for (NSString *email in person.emailAddresses) {
			if ([email hasSuffix:@"gmail.com"] || [email hasSuffix:@"googlemail.com"]) {
				NSMutableDictionary *dict = [addressBookDict objectForKey:@"Jabber"];
				if (!dict) {
					dict = [NSMutableDictionary dictionary];
					[addressBookDict setObject:dict forKey:@"Jabber"];
				}

				[dict setObject:uniqueId forKey:email];

				[UIDsArray addObject:email];
				[servicesArray addObject:@"Jabber"];
			}
		}

		//And the card's Jabber names
		for (NSString *name in person.jabberNames) {
			NSString *UID = [name compactedString];
			if (![UID length]) continue;

			NSMutableDictionary *dict = [addressBookDict objectForKey:@"Jabber"];
			if (!dict) {
				dict = [NSMutableDictionary dictionary];
				[addressBookDict setObject:dict forKey:@"Jabber"];
			}

			[dict setObject:uniqueId forKey:UID];

			[UIDsArray addObject:UID];
			[servicesArray addObject:@"Jabber"];
		}

		if (([UIDsArray count] > 1) && createMetaContacts) {
			/* Got a card with multiple names. Group the names together, adding them to the meta contact. */
			AIMetaContact *metaContact, *metaContactHint;

			metaContactHint = [adium.contactController knownMetaContactForGroupingUIDs:UIDsArray
																		 forServices:servicesArray];
			if (!metaContactHint) {
				/* Find a metacontact we used previously but which wasn't saved, if possible. The
				 * store's identifiers wear the same ":ABPerson" suffix the stored keys always
				 * did, so the key fits as it is. */
				NSDictionary *prefsDict = [adium.preferenceController preferenceForKey:KEY_AB_TO_METACONTACT_DICT
																			  group:PREF_GROUP_ADDRESSBOOK];
				NSNumber *metaContactObjectID = [prefsDict objectForKey:uniqueId];
				if (metaContactObjectID)
					metaContactHint = [adium.contactController metaContactWithObjectID:metaContactObjectID];
			}

			metaContact = [adium.contactController groupUIDs:UIDsArray
												   forServices:servicesArray
										  usingMetaContactHint:metaContactHint];
			if (metaContact) {
				[metaContact setValue:uniqueId
						  forProperty:KEY_AB_UNIQUE_ID
							   notify:NotifyNever];

				[personUniqueIdToMetaContactDict setObject:metaContact
													forKey:uniqueId];
				if (metaContact != metaContactHint) {
					//Keep track of the use of this metacontact for this address book card
					NSMutableDictionary *prefsDict = [[[adium.preferenceController preferenceForKey:KEY_AB_TO_METACONTACT_DICT
																						   group:PREF_GROUP_ADDRESSBOOK] mutableCopy] autorelease];
					if (!prefsDict) prefsDict = [NSMutableDictionary dictionary];
					[prefsDict setObject:[metaContact objectID]
								  forKey:uniqueId];
					[adium.preferenceController setPreference:prefsDict
														 forKey:KEY_AB_TO_METACONTACT_DICT
														  group:PREF_GROUP_ADDRESSBOOK];
				}
			}
		}
	}

	//Stop delaying list object notifications since we are done
	[[AIContactObserverManager sharedManager] endListObjectNotificationsDelay];
}

#pragma mark AB contextual menu

/*!
 * @brief Validate menu item
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	AIListObject *listObject = adium.menuController.currentContextMenuObject;
	BOOL		 hasABEntry = ([[self class] personForListObject:listObject] != nil);
	BOOL		 result = NO;

	if ([menuItem tag] == AIRequiresAddressBookEntry) {
		result = hasABEntry;
	}

	return result;
}

/*!
 * @brief The Contacts app's deep link to a card
 *
 * The store's identifiers already wear the shape the scheme expects.
 */
+ (NSURL *)addressBookURLForPerson:(AIAddressBookPerson *)person edit:(BOOL)edit
{
	if (!person) return nil;

	return [NSURL URLWithString:[NSString stringWithFormat:@"addressbook://%@%@",
								 person.uniqueId, (edit ? @"?edit" : @"")]];
}

/*!
 * @brief Shows the selected contact in Address Book
 */
- (void)showInAddressBook
{
	AIAddressBookPerson *selectedPerson = [[self class] personForListObject:adium.menuController.currentContextMenuObject];
	NSURL *url = [[self class] addressBookURLForPerson:selectedPerson edit:NO];
	if (url) [[NSWorkspace sharedWorkspace] openURL:url];
}

/*!
 * @brief Edits the selected contact in Address Book
 */
- (void)editInAddressBook
{
	AIAddressBookPerson *selectedPerson = [[self class] personForListObject:adium.menuController.currentContextMenuObject];
	NSURL *url = [[self class] addressBookURLForPerson:selectedPerson edit:YES];
	if (url) [[NSWorkspace sharedWorkspace] openURL:url];
}


@end
