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

#import "ESAddressBookIntegrationAdvancedPreferences.h"
#import <Adium/AIAddressBookController.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>

//Width the form starts out at; the preferences window resizes it to its column.
#define ADDRESS_BOOK_PANE_INITIAL_WIDTH	540.0

@interface NSTokenField (NSTokenFieldAdditions)
- (void)updateDisplay;
@end

@implementation NSTokenField (NSTokenFieldAdditions)
- (void)updateDisplay
{
	NSRange selectionRange = [[[self window] fieldEditor:YES forObject:self] selectedRange];

	// XXX - Reassign objectValue to let NSTokenField know it has changed.
	id objectValue = [self objectValue];
	[self setObjectValue:nil];
	[self setObjectValue:objectValue];

	[[[self window] fieldEditor:YES forObject:self] setSelectedRange:selectionRange];
}
@end

@interface ESAddressBookIntegrationAdvancedPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (NSTokenField *)formatTokenField;
- (NSPopUpButton *)insertNameElementPopUpButton;
- (IBAction)changeFormat:(id)sender;
- (void)insertNameElement:(id)sender;
- (NSArray *)separateStringIntoTokens:(NSString *)string;
- (void)changeFormatToFullName:(id)representedObject;
- (void)changeFormatToInitialCharacter:(id)representedObject;
@end

/*!
 * @class ESAddressBookIntegrationAdvancedPreferences
 * @brief Provide advanced preferences for the address book integration
 */
@implementation ESAddressBookIntegrationAdvancedPreferences

/*!
 * @brief Label
 */
- (NSString *)label{
    return AILocalizedString(@"Address Book",nil);
}
/*!
 * @brief Image for advanced preferences
 */
- (NSImage *)image{
	return [NSImage imageNamed:@"AddressBook" forClass:[self class]];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads a nib for us.
 * AddressBookPrefs.xib, which used to hold this interface, has been deleted along with its entry
 * in the target: nothing loaded it any more, and it still wired outlets this class no longer has,
 * so anything that did load it would have raised rather than fallen back to the old interface.
 */

#pragma mark View

/*!
 * @brief Build our view instead of loading a nib.
 *
 * Mirrors -[AIModularPane view] so the subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		AISettingsFormView	*form = [self buildSettingsForm];

		view = [form retain];

		[self viewDidLoad];
		[self localizePane];

		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Release the form.
 *
 * -closeView releases the view and is idempotent; without it a deallocated pane
 * would leave the form's rows — and the KVO observations they register on their
 * controls — alive. Same pattern as the other panes built on AISettingsFormView.
 */
- (void)dealloc
{
	[self closeView];
	[super dealloc];
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * Four cards behind an info block. The nib had three plain labels — Names,
 * Images, Contacts — and expressed everything else by position: the name format
 * field, its line of instructions and a boxed palette of four draggable name
 * elements all hung under the import checkbox. The labels are section headers
 * now, the palette is an "Insert" pull down under the Names card (same
 * elements, reachable by keyboard, and each inserted element keeps its menu for
 * switching between full name and initial), and the two Nick options follow in
 * a headerless card so the format block keeps its Insert button directly under
 * itself.
 *
 * Every control keeps the preference key its nib counterpart wrote; only the
 * presentation changes. Everything is dimmed by the same rules as before
 * (-configureControlDimming).
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:ADDRESS_BOOK_PANE_INITIAL_WIDTH] autorelease];

	/* What this pane is about, before any switch: the pane's name says "Address
	 * Book" but not what Adium does with it. No header over this card: it would
	 * only repeat the pane's own title.
	 */
	[form addInfoRow:AILocalizedString(@"Adium can name your contacts after their Address Book cards, show the pictures stored there, and combine the screen names of one card into a single contact.",
									   "Paragraph at the top of the Address Book pane")
		   withImage:[self image]];

	//The nib's "Names" label, kept as the card's section header
	[form addSectionHeader:AILocalizedString(@"Names",nil)];

	checkBox_enableImport = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Import my contacts' names from the Address Book",nil)
				  control:checkBox_enableImport];

	tokenField_format = [self formatTokenField];
	[form addRowWithLabel:AILocalizedString(@"Name format", "Label of the field holding the Address Book name format")
		stretchingControl:tokenField_format];

	/* The nib said "drag name elements"; the palette they were dragged from is
	 * the Insert menu below the card now, so the sentence changed with it.
	 */
	[form addDetailRow:AILocalizedString(@"Type text and insert name elements to create a custom name format. Click an element to choose between the full name and the initial.",
										 "Explanation under the Address Book name format field")];

	popUp_insertNameElement = [self insertNameElementPopUpButton];
	[form addTrailingAccessoryView:popUp_insertNameElement];

	/* The two Nick fallbacks. Their own, headerless card: they belong to the
	 * import switch above, but placing them in its card would push the Insert
	 * button — which hangs below the card — away from the format field it
	 * belongs to.
	 */
	[form endCard];

	checkBox_useFirstName = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Replace Nick with First if not available", nil)
				  control:checkBox_useFirstName];

	checkBox_useNickName = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Use Nick exclusively if available",nil)
				  control:checkBox_useNickName];

	//The nib's "Images" label
	[form addSectionHeader:AILocalizedString(@"Images",nil)];

	checkBox_useABImages = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Use Address Book images as contacts' icons",nil)
				  control:checkBox_useABImages];

	/* Indented under the checkbox above in the nib; a row of equal rank now,
	 * directly beneath the row it qualifies and dimmed with it exactly as before.
	 */
	checkBox_preferABImages = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Even if the contact already has a contact icon",nil)
				  control:checkBox_preferABImages];

	//The nib's "Contacts" label
	[form addSectionHeader:AILocalizedString(@"Contacts",nil)];

	checkBox_metaContacts = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Combine contacts listed on a single card",nil)
				  control:checkBox_metaContacts];

	return form;
}

/*!
 * @brief The field the name format is edited in.
 *
 * A token field, as in the nib: the %[…] elements show as pills carrying the
 * full name / initial menu, everything else stays plain text. The tokenizing
 * character set is empty because the format is free text — nothing may split on
 * comma or space; elements become tokens through their %[…] shape alone
 * (-tokenField:representedObjectForEditingString:).
 */
- (NSTokenField *)formatTokenField
{
	NSTokenField *field = [[[NSTokenField alloc] initWithFrame:NSZeroRect] autorelease];

	[field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[field setDelegate:self];
	[field setTokenizingCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@""]];
	[field setTarget:self];
	[field setAction:@selector(changeFormat:)];
	/* Return alone is not enough: the format must also be saved when the focus
	 * moves away — including when the preferences window swaps this pane out,
	 * which never sends -closeView. The nib set the same flag.
	 */
	[[field cell] setSendsActionOnEndEditing:YES];

	//The row decides the width; only the height comes from the field itself
	[field sizeToFit];
	[field setFrameSize:NSMakeSize(100.0, ceil(NSHeight([field frame])))];

	return field;
}

/*!
 * @brief The "Insert" menu of name elements, sitting under the format card.
 *
 * A pull down rather than a pop up: the button is a verb, not a choice that
 * stays selected, so its title never changes. Its first item is that title and
 * is never chosen.
 *
 * The titles are the ones the nib labelled its drag palette with — same
 * strings, same order — so every existing translation still applies. Each item
 * carries the FULL form of its element; the INITIAL form stays reachable
 * through the menu of the inserted pill, exactly as it was from a dragged one.
 */
- (NSPopUpButton *)insertNameElementPopUpButton
{
	NSPopUpButton	*popUp = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES] autorelease];
	NSArray			*titles = [NSArray arrayWithObjects:
							   AILocalizedString(@"First", "First name token"),
							   AILocalizedString(@"Middle", "Middle name token"),
							   AILocalizedString(@"Last", "Last name token"),
							   AILocalizedString(@"Nick", "Nickname token"),
							   nil];
	NSArray			*elements = [NSArray arrayWithObjects:
								 FORMAT_FIRST_FULL,
								 FORMAT_MIDDLE_FULL,
								 FORMAT_LAST_FULL,
								 FORMAT_NICK_FULL,
								 nil];

	[popUp addItemWithTitle:AILocalizedString(@"Insert", nil)];

	for (NSUInteger i = 0; i < [elements count]; i++) {
		NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:[titles objectAtIndex:i]
													   action:@selector(insertNameElement:)
												keyEquivalent:@""] autorelease];

		[item setTarget:self];
		[item setRepresentedObject:[elements objectAtIndex:i]];
		[[popUp menu] addItem:item];
	}

	[popUp sizeToFit];

	return popUp;
}

#pragma mark Configuration

/*!
 * @brief The view loaded: fill the controls from the stored preferences
 */
- (void)viewDidLoad
{
	NSString *displayFormat = [adium.preferenceController preferenceForKey:KEY_AB_DISPLAYFORMAT group:PREF_GROUP_ADDRESSBOOK];
	[tokenField_format setObjectValue:[self separateStringIntoTokens:displayFormat]];

	[checkBox_enableImport setState:([[adium.preferenceController preferenceForKey:KEY_AB_ENABLE_IMPORT
																			 group:PREF_GROUP_ADDRESSBOOK] boolValue] ?
									 NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_useFirstName setState:([[adium.preferenceController preferenceForKey:KEY_AB_USE_FIRSTNAME
																			 group:PREF_GROUP_ADDRESSBOOK] boolValue] ?
									 NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_useNickName setState:([[adium.preferenceController preferenceForKey:KEY_AB_USE_NICKNAME
																			group:PREF_GROUP_ADDRESSBOOK] boolValue] ?
									NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_useABImages setState:([[adium.preferenceController preferenceForKey:KEY_AB_USE_IMAGES
																			group:PREF_GROUP_ADDRESSBOOK] boolValue] ?
									NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_preferABImages setState:([[adium.preferenceController preferenceForKey:KEY_AB_PREFER_ADDRESS_BOOK_IMAGES
																			   group:PREF_GROUP_ADDRESSBOOK] boolValue] ?
									   NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_metaContacts setState:([[adium.preferenceController preferenceForKey:KEY_AB_CREATE_METACONTACTS
																			 group:PREF_GROUP_ADDRESSBOOK] boolValue] ?
									 NSControlStateValueOn : NSControlStateValueOff)];

	[self configureControlDimming];

	[super viewDidLoad];
}

- (void)viewWillClose
{
	/* The form owns every control; these are the pane's non-owning references to
	 * them and must not outlive the view.
	 */
	checkBox_enableImport = nil;
	checkBox_useFirstName = nil;
	checkBox_useNickName = nil;
	tokenField_format = nil;
	popUp_insertNameElement = nil;
	checkBox_useABImages = nil;
	checkBox_preferABImages = nil;
	checkBox_metaContacts = nil;

	[super viewWillClose];
}

/*!
 * @brief Configure control dimming
 */
- (void)configureControlDimming
{
	BOOL            enableImport = [[adium.preferenceController preferenceForKey:KEY_AB_ENABLE_IMPORT
																			 group:PREF_GROUP_ADDRESSBOOK] boolValue];
	BOOL            useImages = [[adium.preferenceController preferenceForKey:KEY_AB_USE_IMAGES
																		  group:PREF_GROUP_ADDRESSBOOK] boolValue];

	//The name format and the Nick fallbacks are irrelevant if importing of names is not enabled
	[checkBox_useFirstName setEnabled:enableImport];
	[checkBox_useNickName setEnabled:enableImport];
	[tokenField_format setEnabled:enableImport];
	[popUp_insertNameElement setEnabled:enableImport];

	//Disable the image priority checkbox if we aren't using images
	[checkBox_preferABImages setEnabled:useImages];
}

#pragma mark Changing preferences

/*!
 * @brief Save changed name format preference
 */
- (IBAction)changeFormat:(id)sender
{
	/* The action also arrives from the dying field editor while the window
	 * closes, after -viewWillClose has already let go of the field: nothing left
	 * to read then, and setting nil would remove the key instead of writing it.
	 */
	if (!tokenField_format) return;

	NSArray *tokens = [tokenField_format objectValue];

	[adium.preferenceController setPreference:(tokens ? [tokens componentsJoinedByString:@""] : @"")
									   forKey:KEY_AB_DISPLAYFORMAT
                                        group:PREF_GROUP_ADDRESSBOOK];
}

/*!
 * @brief An item of the Insert menu was chosen: put its element into the format.
 *
 * Into the live edit at the caret when the field is being edited — the raw
 * %[…] text becomes a pill when the field tokenizes it — and appended as a
 * ready-made token otherwise. Mutable in both cases, because the pill's menu
 * edits the represented object in place (-changeFormatToInitialCharacter:).
 */
- (void)insertNameElement:(id)sender
{
	NSString	*element = [sender representedObject];
	NSText		*editor = [tokenField_format currentEditor];

	if (![element length] || !tokenField_format) return;

	if ([editor isKindOfClass:[NSTextView class]]) {
		[(NSTextView *)editor insertText:element replacementRange:[editor selectedRange]];

		/* Fold the edit back into -objectValue so the save below stores what is
		 * on screen; the editing session itself goes on.
		 */
		[tokenField_format validateEditing];
	} else {
		NSMutableArray	*tokens = [[[tokenField_format objectValue] mutableCopy] autorelease];

		if (!tokens) tokens = [NSMutableArray array];
		[tokens addObject:[NSMutableString stringWithString:element]];
		[tokenField_format setObjectValue:tokens];
	}

	[self changeFormat:tokenField_format];
}

/*!
 * @brief Save changed preference
 */
- (IBAction)changePreference:(id)sender
{
    if (sender == checkBox_useABImages) {
        [adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_useABImages state] == NSControlStateValueOn)]
                                             forKey:KEY_AB_USE_IMAGES
                                              group:PREF_GROUP_ADDRESSBOOK];
	} else if (sender == checkBox_useFirstName) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_useFirstName state] == NSControlStateValueOn)]
										   forKey:KEY_AB_USE_FIRSTNAME
											group:PREF_GROUP_ADDRESSBOOK];
    } else if (sender == checkBox_useNickName) {
        [adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_useNickName state] == NSControlStateValueOn)]
										   forKey:KEY_AB_USE_NICKNAME
                                            group:PREF_GROUP_ADDRESSBOOK];
    } else if (sender == checkBox_enableImport) {
        [adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_enableImport state] == NSControlStateValueOn)]
                                             forKey:KEY_AB_ENABLE_IMPORT
                                              group:PREF_GROUP_ADDRESSBOOK];

    } else if (sender == checkBox_preferABImages) {
        [adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_preferABImages state] == NSControlStateValueOn)]
                                             forKey:KEY_AB_PREFER_ADDRESS_BOOK_IMAGES
                                              group:PREF_GROUP_ADDRESSBOOK];

    } else if (sender == checkBox_enableNoteSync) {
		//Unreachable until the note sync control returns; see the ivar's comment
        [adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_enableNoteSync state] == NSControlStateValueOn)]
                                             forKey:KEY_AB_NOTE_SYNC
                                              group:PREF_GROUP_ADDRESSBOOK];

    } else if (sender == checkBox_metaContacts) {
		BOOL shouldCreateMetaContacts = ([checkBox_metaContacts state] == NSControlStateValueOn);

		if (shouldCreateMetaContacts) {
			[adium.preferenceController setPreference:[NSNumber numberWithBool:YES]
												 forKey:KEY_AB_CREATE_METACONTACTS
												  group:PREF_GROUP_ADDRESSBOOK];

		} else {
			NSAlert *alert = [[[NSAlert alloc] init] autorelease];
			[alert setMessageText:AILocalizedString(@"Disabling automatic contact consolidation will also unconsolidate all existing metacontacts, including any created manually.  You will need to recreate any manually-created metacontacts if you proceed.",nil)];
			[alert addButtonWithTitle:AILocalizedString(@"Unconsolidate all metacontacts",nil)];	//NSAlertFirstButtonReturn, was the default button
			[alert addButtonWithTitle:AILocalizedString(@"Cancel",nil)];
			[alert beginSheetModalForWindow:[[self view] window] completionHandler:^(NSModalResponse returnCode) {
				if (returnCode == NSAlertFirstButtonReturn) {
					//If we now shouldn't create metaContacts, clear 'em all... not pretty, but effective.

					//Delay to the next run loop to give better UI responsiveness
					[adium.contactController performSelector:@selector(clearAllMetaContactData)
												  withObject:nil
												  afterDelay:0];

					[adium.preferenceController setPreference:[NSNumber numberWithBool:NO]
														forKey:KEY_AB_CREATE_METACONTACTS
														 group:PREF_GROUP_ADDRESSBOOK];
				} else {
					//Put the switch back: the preference was never written
					[checkBox_metaContacts setState:NSControlStateValueOn];
				}
			}];
		}
	}

    [self configureControlDimming];
}


#pragma mark Token Field Delegate

- (NSArray *)tokenField:(NSTokenField *)tokenField shouldAddObjects:(NSArray *)tokens atIndex:(NSUInteger)index
{
	NSString *tokenStrings = [tokens componentsJoinedByString:@""];
	return [self separateStringIntoTokens:tokenStrings];
}

- (BOOL)tokenField:(NSTokenField *)tokenField writeRepresentedObjects:(NSArray *)objects toPasteboard:(NSPasteboard *)pboard
{
	[pboard setString:[objects componentsJoinedByString:@""] forType:NSPasteboardTypeString];
	return YES;
}

- (NSArray *)tokenField:(NSTokenField *)tokenField readFromPasteboard:(NSPasteboard *)pboard
{
	return [self separateStringIntoTokens:[pboard stringForType:NSPasteboardTypeString]];
}

- (NSTokenStyle)tokenField:(NSTokenField *)tokenField styleForRepresentedObject:(id)representedObject
{
	if ([representedObject hasPrefix:@"%["] && [representedObject hasSuffix:@"]"]) {
		return NSRoundedTokenStyle;
	} else {
		return NSPlainTextTokenStyle;
	}
}

- (NSString *)tokenField:(NSTokenField *)tokenField displayStringForRepresentedObject:(id)representedObject
{
	if ([representedObject isEqualToString:FORMAT_FIRST_FULL]) {
		return @"Evan";
	} else if ([representedObject isEqualToString:FORMAT_FIRST_INITIAL]) {
		return @"E";
	} else if ([representedObject isEqualToString:FORMAT_MIDDLE_FULL]) {
		return @"Dreskin";
	} else if ([representedObject isEqualToString:FORMAT_MIDDLE_INITIAL]) {
		return @"D";
	} else if ([representedObject isEqualToString:FORMAT_LAST_FULL]) {
		return @"Schoenberg";
	} else if ([representedObject isEqualToString:FORMAT_LAST_INITIAL]) {
		return @"S";
	} else if ([representedObject isEqualToString:FORMAT_NICK_FULL]) {
		return @"TekJew";
	} else if ([representedObject isEqualToString:FORMAT_NICK_INITIAL]) {
		return @"T";
	} else {
		return nil;
	}
}

- (NSString *)tokenField:(NSTokenField *)tokenField editingStringForRepresentedObject:(id)representedObject
{
	if ([representedObject hasPrefix:@"%["] && [representedObject hasSuffix:@"]"]) {
		return nil;
	} else {
		return representedObject;
	}
}

- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:(NSString *)editingString
{
	if ([editingString hasPrefix:@"%["] && [editingString hasSuffix:@"]"]) {
		// Return mutable string as formats should be modifiable
		return [NSMutableString stringWithString:editingString];
	} else {
		return editingString;
	}
}

- (BOOL)tokenField:(NSTokenField *)tokenField hasMenuForRepresentedObject:(id)representedObject
{
	if (tokenField == tokenField_format) {
		// Only tokens in Format should have menus
		return YES;
	} else {
		return NO;
	}
}

- (NSMenu *)tokenField:(NSTokenField *)tokenField menuForRepresentedObject:(id)representedObject
{
	NSMenu *menu = [[[NSMenu alloc] init] autorelease];

	if (!representedObject)
		return nil;

	NSString *fullName = [self tokenField:tokenField
		displayStringForRepresentedObject:[representedObject stringByReplacingOccurrencesOfString:@"INITIAL"
																					   withString:@"FULL"]];
	[menu addItemWithTitle:fullName
					target:self
					action:@selector(changeFormatToFullName:)
			 keyEquivalent:@""
		 representedObject:representedObject];

	NSString *initialCharacter = [self tokenField:tokenField
				displayStringForRepresentedObject:[representedObject stringByReplacingOccurrencesOfString:@"FULL"
																					   withString:@"INITIAL"]];
	[menu addItemWithTitle:initialCharacter
					target:self
					action:@selector(changeFormatToInitialCharacter:)
			 keyEquivalent:@""
		 representedObject:representedObject];

	return menu;
}

- (void)changeFormatToInitialCharacter:(id)sender
{
	[[sender representedObject] replaceOccurrencesOfString:FORMAT_FULL
												withString:FORMAT_INITIAL
												   options:NSLiteralSearch
													 range:NSMakeRange(0, [[sender representedObject] length])];

	[tokenField_format updateDisplay];
	[self changeFormat:tokenField_format];
}

- (void)changeFormatToFullName:(id)sender
{
	[[sender representedObject] replaceOccurrencesOfString:FORMAT_INITIAL
												withString:FORMAT_FULL
												   options:NSLiteralSearch
													 range:NSMakeRange(0, [[sender representedObject] length])];

	[tokenField_format updateDisplay];
	[self changeFormat:tokenField_format];
}

- (NSArray *)separateStringIntoTokens:(NSString *)string
{
	NSMutableArray *tokens = [NSMutableArray array];

	int i = 0;
	while (i < [string length]) {
		unsigned int start = i;

		// Search for end of current token
		if ([[string substringFromIndex:i] hasPrefix:@"%["]) {
			for (; i < [string length]; i++) {
				if ([[string substringFromIndex:i] hasPrefix:@"]"]) {
					i++;
					break;
				}
			}

		// Search for start of next token
		} else {
			for (; i < [string length]; i++) {
				if ([[string substringFromIndex:(i + 1)] hasPrefix:@"%["]) {
					i++;
					break;
				}
			}
		}

		[tokens addObject:[[[string substringWithRange:NSMakeRange(start, i - start)] mutableCopy] autorelease]];
	}

	return tokens;
}

@end
