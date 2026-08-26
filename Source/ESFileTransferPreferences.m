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

#import "ESFileTransferPreferences.h"
#import "ESFileTransferController.h"
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIImageDrawingAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIStringAdditions.h>

//Width the form starts out at; the preferences window resizes it to its column.
#define FILE_TRANSFER_PANE_INITIAL_WIDTH	540.0

@interface ESFileTransferPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (NSMenu *)downloadLocationMenu;
- (void)buildDownloadLocationMenu;
- (void)selectOtherDownloadFolder:(id)sender;
- (void)bindObject:(id)object binding:(NSString *)binding keyPath:(NSString *)keyPath options:(NSDictionary *)options;
- (NSString *)keyPathForGroup:(NSString *)group key:(NSString *)key;
@end

/*!
 * @brief A nib label reused as a row label: without its trailing colon.
 *
 * Keeps every existing translation of the old labels usable while matching the
 * System Settings look, where row labels carry no colon.
 */
static NSString *AIRowLabel(NSString *label)
{
	NSCharacterSet	*whitespace = [NSCharacterSet whitespaceCharacterSet];
	/* U+003A and the full width U+FF1A the CJK translations use ("ファイルの保存先：") */
	NSCharacterSet	*colons = [NSCharacterSet characterSetWithCharactersInString:@":："];
	NSString		*trimmed = [label stringByTrimmingCharactersInSet:whitespace];

	while ([trimmed length] > 0 &&
		   [colons characterIsMember:[trimmed characterAtIndex:([trimmed length] - 1)]]) {
		trimmed = [[trimmed substringToIndex:([trimmed length] - 1)] stringByTrimmingCharactersInSet:whitespace];
	}

	return trimmed;
}

/*!
 * @brief A continuation title reused as a row label: standing on its own.
 *
 * "only from contacts on my Contact List" read as the continuation of the
 * checkbox it was indented under. As a row of its own it is a title, so the
 * marks of that continuation go: the leading dots some translations point back
 * at the checkbox with ("...kun fra kontakter på min kontaktliste"), a trailing
 * full stop ("només dels meus contactes."), and lower case at the front.
 *
 * All three are applied to the translation, which keeps every existing
 * localization of the string usable instead of forcing a new one. Case is
 * folded in the locale of the localization actually on screen, not in the
 * user's region — Turkish dotted/dotless i is decided by the language of the
 * text, not by the region format. A no-op in scripts without letter case.
 */
static NSString *AISentenceCaseLabel(NSString *label)
{
	NSMutableCharacterSet	*strip = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
	[strip addCharactersInString:@".…。"];

	NSString	*trimmed = [label stringByTrimmingCharactersInSet:strip];
	if ([trimmed length] < 1) return label;

	NSString	*localization = [[[NSBundle bundleForClass:[ESFileTransferPreferences class]] preferredLocalizations] firstObject];
	NSLocale	*locale = (localization ? [NSLocale localeWithLocaleIdentifier:localization] : [NSLocale currentLocale]);
	NSRange		 first = [trimmed rangeOfComposedCharacterSequenceAtIndex:0];
	NSString	*head = [[trimmed substringWithRange:first] uppercaseStringWithLocale:locale];

	return [trimmed stringByReplacingCharactersInRange:first withString:head];
}

@implementation ESFileTransferPreferences
//Preference pane properties
- (NSString *)paneIdentifier
{
	return @"File Transfer";
}
- (NSString *)paneName{
	return AILocalizedString(@"File Transfer", nil);
}
- (NSImage *)paneIcon
{
	return [NSImage imageNamed:@"pref-file-transfer" forClass:[self class]];
}

/*!
 * @brief Undo everything -view built.
 *
 * -bind:toObject:withKeyPath:options: retains us, so every live binding is a
 * retain cycle the pane only escapes through -viewWillClose. -closeView unbinds
 * and releases the view, and is idempotent.
 */
- (void)dealloc
{
	[self closeView];
}

#pragma mark View

/*!
 * @brief Build our view instead of loading a nib.
 *
 * Mirrors -[AIModularPane view] so subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		AISettingsFormView	*form = [self buildSettingsForm];

		settingsForm = form;
		view = form;

		[self viewDidLoad];
		[self localizePane];

		/* The pop up row measures its button itself at every layout, so all that
		 * is left after -viewDidLoad filled the menu is one more layout pass.
		 */
		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * Each control keeps the binding (key and group) and the action its nib
 * counterpart had; only the presentation changes.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[AISettingsFormView alloc] initWithWidth:FILE_TRANSFER_PANE_INITIAL_WIDTH];

	/* The nib's two-line explanation of "safe" files becomes a detail line,
	 * which wraps by itself: its hard line break would only fold the text twice.
	 */
	NSString			*safeFilesDetail = [AILocalizedString(@"\"Safe\" files include movies, pictures,\nsounds, text documents, and archives.","Description of safe files (files which Adium can open automatically without danger to the user). This description should be on two lines; the lines are separated by \n.")
										    stringByReplacingOccurrencesOfString:@"\n" withString:@" "];

	/* The nib's "Receiving files:" heading becomes the card's section header —
	 * the same key, so the header is translated wherever the rows under it are;
	 * a new key would be English above translated rows in 29 localizations.
	 */
	[form addSectionHeader:AIRowLabel(AILocalizedString(@"Receiving files:","Section title of the settings for receiving files"))];

	/* Save files to. The pop up row re-measures the button at every layout, which
	 * a plain control row does not: the menu is rebuilt whenever the folder
	 * changes, and its title then has to be free to grow *and* to shrink again.
	 */
	popUp_downloadLocation = [AISettingsFormView popUpButtonWithTitles:nil target:nil action:NULL];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Save files to:","File Transfer preferences label"))
			  popUpButton:popUp_downloadLocation
		  accessoryButton:nil];

	/* Automatically accept files and images. The nib appended an ellipsis
	 * because the option continued in the indented line below it; as two rows of
	 * equal rank the sentence ends here, and an ellipsis would promise a dialog.
	 */
	checkBox_autoAcceptFiles = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Automatically accept files and images","File Transfer preferences")
				  control:checkBox_autoAcceptFiles];

	//...only from contacts on my Contact List: a row of its own, enabled with the switch above
	checkBox_autoAcceptOnlyFromCLList = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[self bindObject:checkBox_autoAcceptOnlyFromCLList
			 binding:NSEnabledBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_FILE_TRANSFER key:KEY_FT_AUTO_ACCEPT]
			 options:nil];
	[form addRowWithLabel:AISentenceCaseLabel(AILocalizedString(@"only from contacts on my Contact List","File Transfer preferences"))
				  control:checkBox_autoAcceptOnlyFromCLList];

	//Open "Safe" files after receiving
	checkBox_autoOpenFiles = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:checkBox_autoOpenFiles
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_FILE_TRANSFER key:KEY_FT_AUTO_OPEN_SAFE]
			 options:nil];
	[form addRowWithLabel:AILocalizedString(@"Open \"Safe\" files after receiving","File Transfer preferences")
				  control:checkBox_autoOpenFiles
				   detail:safeFilesDetail];

	//The nib's "Progress:" heading, likewise kept as the section header
	[form addSectionHeader:AIRowLabel(AILocalizedString(@"Progress:","Section title of the settings for the file transfer progress window"))];

	checkBox_showProgress = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:checkBox_showProgress
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_FILE_TRANSFER key:KEY_FT_SHOW_PROGRESS_WINDOW]
			 options:nil];
	[form addRowWithLabel:AILocalizedString(@"Show the File Transfers window automatically","File Transfer preferences")
				  control:checkBox_showProgress];

	return form;
}

#pragma mark Bindings

/*!
 * @brief The key path a preference has when bound through the shared controller.
 */
- (NSString *)keyPathForGroup:(NSString *)group key:(NSString *)key
{
	return [NSString stringWithFormat:@"adium.preferenceController.%@.%@", group, key];
}

/*!
 * @brief Bind @a object to ourselves, remembering the binding so we can undo it.
 */
- (void)bindObject:(id)object binding:(NSString *)binding keyPath:(NSString *)keyPath options:(NSDictionary *)options
{
	if (!object) return;

	[object bind:binding toObject:self withKeyPath:keyPath options:options];

	if (!establishedBindings) establishedBindings = [[NSMutableArray alloc] init];
	[establishedBindings addObject:[NSArray arrayWithObjects:object, binding, nil]];
}

/*!
 * @brief Tear the bindings down before the controls go away.
 */
- (void)viewWillClose
{
	for (NSArray *boundPair in establishedBindings) {
		[[boundPair objectAtIndex:0] unbind:[boundPair objectAtIndex:1]];
	}
	establishedBindings = nil;

	settingsForm = nil;
	popUp_downloadLocation = nil;
	checkBox_autoAcceptFiles = nil;
	checkBox_autoAcceptOnlyFromCLList = nil;
	checkBox_autoOpenFiles = nil;
	checkBox_showProgress = nil;
}

#pragma mark Configuration

//Configure the preference view
- (void)viewDidLoad
{
	AIFileTransferAutoAcceptType	autoAcceptType = [[adium.preferenceController preferenceForKey:KEY_FT_AUTO_ACCEPT
																					   group:PREF_GROUP_FILE_TRANSFER] intValue];

	[self buildDownloadLocationMenu];

	switch (autoAcceptType) {
		case AutoAccept_None:
			[checkBox_autoAcceptFiles setState:NSControlStateValueOff];
			[checkBox_autoAcceptOnlyFromCLList setState:NSControlStateValueOff];
			break;

		case AutoAccept_FromContactList:
			[checkBox_autoAcceptFiles setState:NSControlStateValueOn];
			[checkBox_autoAcceptOnlyFromCLList setState:NSControlStateValueOn];
			break;

		case AutoAccept_All:
			[checkBox_autoAcceptFiles setState:NSControlStateValueOn];
			[checkBox_autoAcceptOnlyFromCLList setState:NSControlStateValueOff];
			break;
	}
}

//Called in response to all preference controls, applies new settings
- (IBAction)changePreference:(id)sender
{
	if ((sender == checkBox_autoAcceptFiles) ||
		(sender == checkBox_autoAcceptOnlyFromCLList)) {
		AIFileTransferAutoAcceptType autoAcceptType;

		if ([checkBox_autoAcceptFiles state] == NSControlStateValueOff) {
			autoAcceptType = AutoAccept_None;
		} else {
			if ([checkBox_autoAcceptOnlyFromCLList state] == NSControlStateValueOn) {
				autoAcceptType = AutoAccept_FromContactList;
			} else {
				autoAcceptType = AutoAccept_All;
			}
		}

		[adium.preferenceController setPreference:[NSNumber numberWithInteger:autoAcceptType]
                                             forKey:KEY_FT_AUTO_ACCEPT
                                              group:PREF_GROUP_FILE_TRANSFER];
	}
}

#pragma mark Download location

- (void)buildDownloadLocationMenu
{
	[popUp_downloadLocation setMenu:[self downloadLocationMenu]];
	[popUp_downloadLocation selectItem:[popUp_downloadLocation itemAtIndex:0]];

	/* A new folder name is a new width: the pop up row sizes the button to its
	 * new title on its own, it only has to be asked for a fresh layout.
	 */
	[settingsForm noteContentSizeChanged];
}

- (NSMenu *)downloadLocationMenu
{
	NSMenu		*menu;
	NSMenuItem	*menuItem;
	NSString	*userPreferredDownloadFolder;

	menu = [[NSMenu alloc] init];
	[menu setAutoenablesItems:NO];

	//Create the menu item for the current download folder
	userPreferredDownloadFolder = [adium.preferenceController userPreferredDownloadFolder];
	menuItem = [[NSMenuItem alloc] initWithTitle:[[NSFileManager defaultManager] displayNameAtPath:userPreferredDownloadFolder]
																	 target:nil
																	 action:nil
															  keyEquivalent:@""];
	[menuItem setRepresentedObject:userPreferredDownloadFolder];
	[menuItem setImage:[[[NSWorkspace sharedWorkspace] iconForFile:userPreferredDownloadFolder] imageByScalingForMenuItem]];
	[menu addItem:menuItem];

	[menu addItem:[NSMenuItem separatorItem]];

	//Create the menu item for changing the current download folder
	menuItem = [[NSMenuItem alloc] initWithTitle:[AILocalizedString(@"Other",nil) stringByAppendingEllipsis]
																	 target:self
																	 action:@selector(selectOtherDownloadFolder:)
															  keyEquivalent:@""];
	[menuItem setRepresentedObject:userPreferredDownloadFolder];
	[menu addItem:menuItem];

	return menu;
}

- (void)selectOtherDownloadFolder:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	NSString	*userPreferredDownloadFolder = [sender representedObject];

	[openPanel setCanChooseFiles:NO];
	[openPanel setCanChooseDirectories:YES];
	openPanel.directoryURL = [NSURL fileURLWithPath:userPreferredDownloadFolder];
	[openPanel beginSheetModalForWindow:[[self view] window] completionHandler:^(NSInteger result) {
		if (result == NSModalResponseOK) {
			[adium.preferenceController setUserPreferredDownloadFolder:openPanel.URL. path];
		}

		[self buildDownloadLocationMenu];
	}];
}

@end
