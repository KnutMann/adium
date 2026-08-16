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

//Only to ask for permission; everything else here uses the older framework
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
#import <AIUtilities/OWAddressBookAdditions.h>
#import <AIUtilities/AIFileManagerAdditions.h>
#import <AIUtilities/AIImageAdditions.h>

#import "AIAddressBookUserIconSource.h"

#define IMAGE_LOOKUP_INTERVAL   0.01
#define SHOW_IN_AB_CONTEXTUAL_MENU_TITLE AILocalizedString(@"Show In Address Book", "Show In Address Book Contextual Menu")
#define EDIT_IN_AB_CONTEXTUAL_MENU_TITLE AILocalizedString(@"Edit In Address Book", "Edit In Address Book Contextual Menu")


/* The version is part of the name so that a change to what gets installed runs once more on a
 * Mac where the previous set is already lying about. Raised when the actions for services
 * Adium no longer has were taken back out. */
#define KEY_ADDRESS_BOOK_ACTIONS_INSTALLED	@"Adium:Installed Address Book Actions 2.0"

#define KEY_AB_TO_METACONTACT_DICT			@"UniqueIDToMetaContactObjectIDDictionary"

@interface AIAddressBookController()
+ (ABPerson *)_searchForUID:(NSString *)UID serviceID:(NSString *)serviceID;
- (void)updateAllContacts;
- (void)updateSelfIncludingIcon:(BOOL)includeIcon;
- (NSString *)nameForPerson:(ABPerson *)person phonetic:(NSString **)phonetic;
- (void)rebuildAddressBookDict;
- (void)showInAddressBook;
- (void)editInAddressBook;
- (void)addToAddressBookDict:(NSArray *)people;
- (void)removeFromAddressBookDict:(NSArray *)UIDs;
- (void)installAddressBookActions;
- (void)openAddressBookWhenAllowed;
- (void)openAddressBook;

- (void)adiumFinishedLaunching:(NSNotification *)notification;
- (void)addressBookChanged:(NSNotification *)notification;
- (void)accountListChanged:(NSNotification *)notification;
@end

/*!
 * @class AIAddressBookController
 * @brief Provides Apple Address Book integration
 *
 * This class allows Adium to seamlessly interact with the Apple Address Book, pulling names and icons, storing icons
 * if desired, and generating metaContacts based on screen name grouping.  It relies upon cards having screen names listed
 * in the appropriate service fields in the address book.
 */
@implementation AIAddressBookController

static AIAddressBookController	*addressBookController = nil;
static ABAddressBook			*sharedAddressBook;
static NSMutableDictionary		*addressBookDict;
static NSDictionary				*serviceDict;

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


+ (void) startAddressBookIntegration
{
	if(!addressBookController)
		addressBookController = [[self alloc] init];
}

- (id)init
{
	if ((self = [super init]))
	{
		meTag = -1;
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

		//Services dictionary
		/* Which card field holds a name for which service. Once six entries, now one: AIM, ICQ, MSN,
		 * Yahoo and Facebook are gone from Adium, and a field can only ever match a contact of a
		 * service that exists. What the modern services are recognised by is not a field of their
		 * own but the number or the address on the card, which is indexed separately. */
		serviceDict = [[NSDictionary dictionaryWithObjectsAndKeys:kABJabberInstantProperty,@"Jabber", nil] retain];
		
		//Shared Address Book, once we are allowed to read it
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
 * @brief Open the address book, once the user has allowed us to read it
 *
 * Reading contacts has needed consent since Catalina. Until it is given the address book opens empty
 * rather than refusing, which from here is indistinguishable from an address book with nobody in it,
 * and that is what this integration looked like for years: present, working, and about nobody.
 *
 * The question is asked through Contacts.framework, which is where it lives now. The answer covers
 * the older framework the rest of this class uses, because both ask the system the same thing.
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
	[sharedAddressBook release];
	sharedAddressBook = [[ABAddressBook sharedAddressBook] retain];
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

	[sharedAddressBook release]; sharedAddressBook = nil;
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
	
	//Observe external address book changes
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(addressBookChanged:)
												 name:kABDatabaseChangedExternallyNotification
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
 * When an icon as a property changes, if desired, write the changed icon out to the appropriate AB card.
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
        ABPerson *person = [listContact addressBookPerson];

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
				//Clear any stored value
				if ([phoneticNameArray objectWithOwner:self]) {
					[displayNameArray setObject:nil withOwner:self];
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
		
		//Add this contact to the ABPerson's metacontact if it's not already there.
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
    }
    
    return modifiedAttributes;
}

/*!
 * @brief Return the name of an ABPerson in the way Adium should display it
 *
 * @param person An <tt>ABPerson</tt>
 * @param phonetic A pointer to an <tt>NSString</tt> which will be filled with the phonetic display name if available
 * @result A string based on the first name, middle name, last name, and/or nickname of the person, as specified via preferences.
 */
- (NSString *)nameForPerson:(ABPerson *)person phonetic:(NSString **)phonetic
{
	NSString *firstName = [person valueForProperty:kABFirstNameProperty];
	NSString *middleName = [person valueForProperty:kABMiddleNameProperty];
	NSString *lastName = [person valueForProperty:kABLastNameProperty];
	NSString *nickName = [person valueForProperty:kABNicknameProperty]; 
	NSString *phoneticFirstName = [person valueForProperty:kABFirstNamePhoneticProperty]; 
	NSString *phoneticMiddleName = [person valueForProperty:kABMiddleNamePhoneticProperty];
	NSString *phoneticLastName = [person valueForProperty:kABLastNamePhoneticProperty];
	
	NSString *displayName = displayFormat;

	// Fallback if format string is empty or unexpected
	if (!displayName || ![displayName isKindOfClass:[NSString class]] || [displayName isEqualToString:@""]) {
		displayName = FORMAT_FIRST_FULL;
	}
	
	// If the record is for a company, return the company name if present
	if (([[person valueForProperty:kABPersonFlags] integerValue] & kABShowAsMask) == kABShowAsCompany) {
		NSString *companyName = [person valueForProperty:kABOrganizationProperty];
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
 *
 * If the user set a new image as a preference for an object, write it out to the contact's AB card if desired.
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
 * @param property - an ABPerson property.
 */
+ (AIService *)serviceFromProperty:(NSString *)property
{
	NSString	*serviceID = ([property isEqualToString:kABJabberInstantProperty] ? @"Jabber" : nil);

	return (serviceID ? [adium.accountController firstServiceWithServiceID:serviceID] : nil);
}

/*!
 * @brief Returns the appropriate property for the service.
 */
+ (NSString *)propertyFromService:(AIService *)inService
{
	NSString *result;
	NSString *serviceID = inService.serviceID;

	//No special cases left: the services they named, GTalk, LiveJournal, Mac and MobileMe, are gone
	return [serviceDict objectForKey:serviceID];
}

/*!
 * @brief Called when the address book completes an asynchronous image lookup
 *
 * @param inData NSData representing an NSImage
 * @param tag A tag indicating the lookup with which this call is associated.
 */
- (void)consumeImageData:(NSData *)inData forTag:(NSInteger)tag
{
	if (tag == meTag) {
		[adium.preferenceController setPreference:inData
											 forKey:KEY_DEFAULT_USER_ICON 
											  group:GROUP_ACCOUNT_STATUS];
		meTag = -1;
	}
}
		
#pragma mark Searching
/*!
 * @brief Find an ABPerson corresponding to an AIListObject
 *
 * @param inObject The object for which it search
 * @result An ABPerson is one is found, or nil if none is found
 */
+ (ABPerson *)personForListObject:(AIListObject *)inObject
{
	ABPerson	*person = nil;
	NSString	*uniqueID = [inObject preferenceForKey:KEY_AB_UNIQUE_ID group:PREF_GROUP_ADDRESSBOOK];
	if (!uniqueID) uniqueID = [inObject valueForProperty:KEY_AB_UNIQUE_ID];
	ABRecord	*record = nil;
	
	if (uniqueID)
		record = [sharedAddressBook recordForUniqueId:uniqueID];
	
	if (record && [record isKindOfClass:[ABPerson class]]) {
		person = (ABPerson *)record;
	} else {
		if ([inObject isKindOfClass:[AIMetaContact class]]) {
			//Search for the first ABPerson for a listContact within the metaContact
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
				ABRecord *found = (uniqueId ? [sharedAddressBook recordForUniqueId:uniqueId] : nil);

				if ([found isKindOfClass:[ABPerson class]])
					person = (ABPerson *)found;
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
				ABRecord *found = (uniqueId ? [sharedAddressBook recordForUniqueId:uniqueId] : nil);

				if ([found isKindOfClass:[ABPerson class]])
					person = (ABPerson *)found;
			}

			//The same again for a service whose names are email addresses, Teams above all
			if (!person && inObject.service.userNamesAreEmailAddresses) {
				NSString *key = AIEmailKey(UID);
				NSString *uniqueId = (key ? [[addressBookDict objectForKey:AB_EMAIL_ADDRESSES] objectForKey:key] : nil);
				ABRecord *found = (uniqueId ? [sharedAddressBook recordForUniqueId:uniqueId] : nil);

				if ([found isKindOfClass:[ABPerson class]])
					person = (ABPerson *)found;
			}

		}
	}

	return person;
}

/*!
 * @brief Find an ABPerson for a given UID and serviceID combination
 * 
 * Uses our addressBookDict cache created in rebuildAddressBook.
 *
 * @param UID The UID for the contact
 * @param serviceID The serviceID for the contact
 * @result A corresponding <tt>ABPerson</tt>
 */

+ (ABPerson *)_searchForUID:(NSString *)UID serviceID:(NSString *)serviceID
{
	ABPerson		*person = nil;
	NSDictionary	*dict;
	
	/* Every service that used to need redirecting here, Mac and MobileMe to AIM, GTalk and
	 * LiveJournal to Jabber, Yahoo! Japan to Yahoo!, has itself been gone for years. */
	dict = [addressBookDict objectForKey:serviceID];
	
	if (dict) {
		NSString *uniqueID = [dict objectForKey:[UID compactedString]];
		if (uniqueID) {
			person = (ABPerson *)[sharedAddressBook recordForUniqueId:uniqueID];
		}
	}
	
	return person;
}

#pragma mark -

- (NSSet *)contactsForPerson:(ABPerson *)person
{
	NSArray			*allServiceKeys = [serviceDict allKeys];
	NSString		*serviceID;
	NSMutableSet	*contactSet = [NSMutableSet set];
	ABMultiValue	*emails;
	NSInteger				i, emailsCount;

	//An ABPerson may have multiple emails; iterate through them looking for @mac.com addresses
	{
		emails = [person valueForProperty:kABEmailProperty];
		emailsCount = [emails count];
		
		for (i = 0; i < emailsCount ; i++) {
			NSString	*email;
			
			email = [emails valueAtIndex:i];

			/* The one case where an email address is also a chat name: a Jabber account at Google is
			 * reached under the same address. The branches that stood beside this one asked for
			 * services called Mac, MobileMe, MSN and Facebook, none of which Adium has any more, and
			 * a lookup on a service that is nil finds nobody. */
			if ([email hasSuffix:@"gmail.com"] || [email hasSuffix:@"googlemail.com"]) {
				NSSet	*contacts = [adium.contactController allContactsWithService:[adium.accountController firstServiceWithServiceID:@"Jabber"]
																				UID:email];

				[contactSet unionSet:contacts];
			}
		}
	}

	//Now go through the instant messaging keys
	for (serviceID in allServiceKeys) {
		NSString		*addressBookKey = [serviceDict objectForKey:serviceID];
		ABMultiValue	*names;
		NSInteger				nameCount;

		//An ABPerson may have multiple names; iterate through them
		names = [person valueForProperty:addressBookKey];
		nameCount = [names count];
		
		//Continue to the next serviceID immediately if no names are found
		if (nameCount == 0) continue;
		
		for (i = 0 ; i < nameCount ; i++) {
			NSString	*UID = [[names valueAtIndex:i] compactedString];
			if ([UID length]) {
				/* The service is the one whose field the name was read from, full stop. A gmail
				 * address used to be turned into "GTalk" here and a numeric name into "ICQ", and
				 * since neither service exists any more the lookup that followed asked for a
				 * service that is nil and found nobody. A Jabber contact at gmail was invisible to
				 * the address book because of it. */
				NSSet	*contacts = [adium.contactController allContactsWithService:[adium.accountController firstServiceWithServiceID:serviceID]
																				  UID:UID];
				
				//Add them to our set
				[contactSet unionSet:contacts];
			}
		}
	}

	return contactSet;
}

#pragma mark Address book changed
/*!
 * @brief Address book changed externally
 *
 * As a result we add/remove people to/from our address book dictionary cache and update all contacts based on it
 */
- (void)addressBookChanged:(NSNotification *)notification
{
	/* In case of a single person, these will be NSStrings.
	 * In case of more then one, they are will be NSArrays containing NSStrings.
	 */	
	id				addedPeopleUniqueIDs, modifiedPeopleUniqueIDs, deletedPeopleUniqueIDs;
	NSMutableSet	*allModifiedPeople = [[NSMutableSet alloc] init];
	ABPerson		*me = [sharedAddressBook me];
	BOOL			modifiedMe = NO;;

	//Delay listObjectNotifications to speed up metaContact creation
	[[AIContactObserverManager sharedManager] delayListObjectNotifications];

	//Addition of new records
	if ((addedPeopleUniqueIDs = [[notification userInfo] objectForKey:kABInsertedRecords])) {
		NSArray	*peopleToAdd;

		if ([addedPeopleUniqueIDs isKindOfClass:[NSArray class]]) {
			//We are dealing with multiple records
			peopleToAdd = [sharedAddressBook peopleFromUniqueIDs:(NSArray *)addedPeopleUniqueIDs];
		} else {
			//We have only one record
			peopleToAdd = [NSArray arrayWithObject:(ABPerson *)[sharedAddressBook recordForUniqueId:addedPeopleUniqueIDs]];
		}
		AILogWithSignature(@"Adding %@ to address book", peopleToAdd);
		[allModifiedPeople addObjectsFromArray:peopleToAdd];
		[self addToAddressBookDict:peopleToAdd];
	}
	
	//Modification of existing records
	if ((modifiedPeopleUniqueIDs = [[notification userInfo] objectForKey:kABUpdatedRecords])) {
		NSArray	*peopleToAdd;

		if ([modifiedPeopleUniqueIDs isKindOfClass:[NSArray class]]) {
			//We are dealing with multiple records
			[self removeFromAddressBookDict:modifiedPeopleUniqueIDs];
			peopleToAdd = [sharedAddressBook peopleFromUniqueIDs:modifiedPeopleUniqueIDs];
		} else {
			//We have only one record
			[self removeFromAddressBookDict:[NSArray arrayWithObject:modifiedPeopleUniqueIDs]];
			peopleToAdd = [NSArray arrayWithObject:(ABPerson *)[sharedAddressBook recordForUniqueId:modifiedPeopleUniqueIDs]];
		}
		AILogWithSignature(@"Modified unique IDs %@, which correspond to people %@", modifiedPeopleUniqueIDs, peopleToAdd);
		[allModifiedPeople addObjectsFromArray:peopleToAdd];
		[self addToAddressBookDict:peopleToAdd];
	}
	
	//Deletion of existing records
	if ((deletedPeopleUniqueIDs = [[notification userInfo] objectForKey:kABDeletedRecords])) {
		if ([deletedPeopleUniqueIDs isKindOfClass:[NSArray class]]) {
			//We are dealing with multiple records
			[self removeFromAddressBookDict:deletedPeopleUniqueIDs];
		} else {
			//We have only one record
			[self removeFromAddressBookDict:[NSArray arrayWithObject:deletedPeopleUniqueIDs]];
		}
		
		//Note: We have no way of retrieving the records of people who were removed, so we really can't do much here.
		AILogWithSignature(@"Removed %@", deletedPeopleUniqueIDs);
	}
	
	ABPerson		*person;
	
	//Do appropriate updates for each updated ABPerson
	for (person in allModifiedPeople) {
		if (person == me) {
			modifiedMe = YES;
		}

		//It's tempting to not do this if (person == me), but the 'me' contact may also be in the contact list
		[[AIContactObserverManager sharedManager] updateContacts:[self contactsForPerson:person]
									  forObserver:self];
	}

	//Update us if appropriate
	if (modifiedMe) {
		[self updateSelfIncludingIcon:YES];
	}
	
	//Stop delaying list object notifications since we are done
	[[AIContactObserverManager sharedManager] endListObjectNotificationsDelay];
	[allModifiedPeople release];
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
	@try
	{
        //Begin loading image data for the "me" address book entry, if one exists
        ABPerson *me;
        if ((me = [sharedAddressBook me])) {
			
			//Default buddy icon
			if (includeIcon) {
				//Begin the image load
				meTag = [me beginLoadingImageDataForClient:self];
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
	}
	@catch(id exc)
	{
		NSLog(@"ABIntegration: Caught %@", exc);
	}
}

#pragma mark Address book caching
/*!
 * @brief rebuild our address book lookup dictionary
 */
- (void)rebuildAddressBookDict
{
	//Delay listObjectNotifications to speed up metaContact creation
	[[AIContactObserverManager sharedManager] delayListObjectNotifications];
	
	[addressBookDict release]; addressBookDict = [[NSMutableDictionary alloc] init];
	
	[self addToAddressBookDict:[sharedAddressBook people]];

	//Stop delaying list object notifications since we are done
	[[AIContactObserverManager sharedManager] endListObjectNotificationsDelay];
}



/*!
 * @brief add people to our address book lookup dictionary
 *
 * Rather than continually searching the address book, a lookup dictionary addressBookDict provides an quick and easy
 * way to look up a unique record ID for an ABPerson based on the service and UID of a contact. addressBookDict contains
 * NSDictionary objects keyed by service ID. Each of these NSDictionary objects contains unique record IDs keyed by compacted
 * (that is, no spaces and no all lowercase) UID. This means we can search while ignoring spaces, which normal AB searching
 * does not allow.
 *
 * In the process of building we look for cards which have multiple screen names listed and, if desired, automatically
 * create metaContacts baesd on this information.
 */
- (void)addToAddressBookDict:(NSArray *)people
{
	NSArray				*allServiceKeys = [serviceDict allKeys];
	ABPerson			*person;
	
	for (person in people) {
		NSString			*serviceID;

		/* The card's phone numbers, so that a service which identifies people by their number can
		 * find them. Deliberately not added to the arrays below: those group contacts into one
		 * metacontact, and sharing a number is a good enough reason to look somebody up but not a
		 * good enough reason to merge them without being asked. */
		{
			ABMultiValue	*numbers = [person valueForProperty:kABPhoneProperty];
			NSMutableDictionary *phoneDict = [addressBookDict objectForKey:AB_PHONE_NUMBERS];

			for (NSUInteger n = 0; n < [numbers count]; n++) {
				NSString *key = AIPhoneNumberKey([numbers valueAtIndex:n]);
				if (!key) continue;

				if (!phoneDict) {
					phoneDict = [[[NSMutableDictionary alloc] init] autorelease];
					[addressBookDict setObject:phoneDict forKey:AB_PHONE_NUMBERS];
				}

				[phoneDict setObject:[person uniqueId] forKey:key];
			}
		}

		/* And the card's email addresses, for a service that knows people by one. Kept out of the
		 * arrays below for the same reason as the numbers: sharing an address is reason enough to
		 * look somebody up, and not reason enough to merge two contacts unasked. */
		{
			ABMultiValue		*addresses = [person valueForProperty:kABEmailProperty];
			NSMutableDictionary *emailDict = [addressBookDict objectForKey:AB_EMAIL_ADDRESSES];

			for (NSUInteger n = 0; n < [addresses count]; n++) {
				NSString *key = AIEmailKey([addresses valueAtIndex:n]);
				if (!key) continue;

				if (!emailDict) {
					emailDict = [[[NSMutableDictionary alloc] init] autorelease];
					[addressBookDict setObject:emailDict forKey:AB_EMAIL_ADDRESSES];
				}

				[emailDict setObject:[person uniqueId] forKey:key];
			}
		}

		NSMutableArray		*UIDsArray = [NSMutableArray array];
		NSMutableArray		*servicesArray = [NSMutableArray array];
		
		NSMutableDictionary	*dict;
		ABMultiValue		*emails;
		NSInteger					i, emailsCount;
		
		/* A card's email addresses, for the one case where an address is also a chat name: a Jabber
		 * account at Google is reached under the same address. The other cases that stood here,
		 * @mac.com and @me.com becoming AIM names, hotmail becoming MSN, and an fb:// homepage
		 * becoming a Facebook name, named services Adium no longer has.
		 */
		{
			emails = [person valueForProperty:kABEmailProperty];
			emailsCount = [emails count];

			for (i = 0; i < emailsCount ; i++) {
				NSString	*email = [emails valueAtIndex:i];

				if ([email hasSuffix:@"gmail.com"] || [email hasSuffix:@"googlemail.com"]) {
					if (!(dict = [addressBookDict objectForKey:@"Jabber"])) {
						dict = [[[NSMutableDictionary alloc] init] autorelease];
						[addressBookDict setObject:dict forKey:@"Jabber"];
					}

					[dict setObject:[person uniqueId] forKey:email];

					[UIDsArray addObject:email];
					[servicesArray addObject:@"Jabber"];
				}
			}
		}

		//Now go through the instant messaging keys
		for (serviceID in allServiceKeys) {
			NSString			*addressBookKey = [serviceDict objectForKey:serviceID];
			ABMultiValue		*names;
			NSInteger					nameCount;
			
			//An ABPerson may have multiple names; iterate through them
			names = [person valueForProperty:addressBookKey];
			nameCount = [names count];
			
			//Continue to the next serviceID immediately if no names are found
			if (nameCount == 0) continue;
			
			//One or more names were found, so we'll need a dictionary
			if (!(dict = [addressBookDict objectForKey:serviceID])) {
				dict = [[NSMutableDictionary alloc] init];
				[addressBookDict setObject:dict forKey:serviceID];
				[dict release];
			}
			
			for (i = 0 ; i < nameCount ; i++) {
				NSString	*UID = [[names valueAtIndex:i] compactedString];
				if ([UID length]) {
					[dict setObject:[person uniqueId] forKey:UID];

					/* The service is the field the name came from. Guessing a narrower one from the
					 * shape of the name, ICQ for digits, GTalk for a gmail address, named services
					 * that no longer exist, and a grouping made under a service that is nil groups
					 * nothing. */
					[UIDsArray addObject:UID];
					[servicesArray addObject:serviceID];
				}
			}
		}

		if (([UIDsArray count] > 1) && createMetaContacts) {
			/* Got a record with multiple names. Group the names together, adding them to the meta contact. */
			AIMetaContact *metaContact, *metaContactHint;
			NSString *uniqueId = [person uniqueId];

			metaContactHint = [adium.contactController knownMetaContactForGroupingUIDs:UIDsArray
																		 forServices:servicesArray];
			if (!metaContactHint) {
				/* Find a metacontact we used previously but which wasn't saved, if possible. This keeps us from creating a 
				 * new metacontact with every launch when the metacontact is created by the address book rather than the user.
				 *
				 * We don't make address book metacontacts actually persistent because then we would persist them even if the address
				 * book card were modified or deleted or if the user disabled "Conslidate contacts listed on the card."
				 */
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
														 forKey:@"UniqueIDToMetaContactObjectIDDictionary"
														  group:PREF_GROUP_ADDRESSBOOK];
				}
			}
		}
	}
}

/*!
 * @brief remove people from our address book lookup dictionary
 */
- (void)removeFromAddressBookDict:(NSArray *)uniqueIDs
{
	/* The numbers and the addresses are filed under keys of their own rather than under a service,
	 * so they have to be named here: going by the services alone would leave a deleted card still
	 * answering to its own phone number until the next full rebuild. */
	NSMutableArray *tables = [[[serviceDict allKeys] mutableCopy] autorelease];

	[tables addObject:AB_PHONE_NUMBERS];
	[tables addObject:AB_EMAIL_ADDRESSES];

	for (NSString *uniqueID in uniqueIDs) {

		//The same person may be in several of these; iterate through them and remove each one.
		for (NSString *table in tables) {

			NSMutableDictionary *dict = [addressBookDict objectForKey:table];

			//The same person may have multiple accounts from the same service; we should remove them all.
			for (NSString *key in [dict allKeysForObject:uniqueID]) {
				[dict removeObjectForKey:key];
			}
		}
	}
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
 * @brief Shows the selected contact in Address Book
 */
- (void)showInAddressBook
{
	ABPerson *selectedPerson = [[self class] personForListObject:adium.menuController.currentContextMenuObject];
	NSString *url = [NSString stringWithFormat:@"addressbook://%@", [selectedPerson uniqueId]];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
}

/*!
 * @brief Edits the selected contact in Address Book
 */
- (void)editInAddressBook
{
	ABPerson *selectedPerson = [[self class] personForListObject:adium.menuController.currentContextMenuObject];
	NSString *url = [NSString stringWithFormat:@"addressbook://%@?edit", [selectedPerson uniqueId]];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
}


@end
