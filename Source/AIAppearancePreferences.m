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

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "AIAppearancePreferences.h"
#import "AIAppearancePreferencesPlugin.h"
#import "AIDockIconSelectionSheet.h"
#import "AIEmoticonPack.h"
#import "AIEmoticonPreferences.h"
#import "AIContactListAppearancePage.h"
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIImageDrawingAdditions.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <Adium/AIAbstractListController.h>
#import <Adium/AIDockControllerProtocol.h>
#import <Adium/AIEmoticonControllerProtocol.h>
#import <Adium/AIIconState.h>
#import <Adium/AIServiceIcons.h>
#import <Adium/AIStatusIcons.h>
#import <Adium/ESPresetManagementController.h>
#import <Adium/ESPresetNameSheetController.h>
#import <Adium/AISettingsFormView.h>
#import "AIMenuBarIcons.h"

typedef enum {
	AIEmoticonMenuNone = 1,
	AIEmoticonMenuMultiple
} AIEmoticonMenuTag;

//Width the form starts out at; the preferences window resizes it to its column.
#define APPEARANCE_PANE_INITIAL_WIDTH	540.0

/* The widest text each slider's readout ever shows: the opacity slider's 5-100
 * percent and the width slider's 32-640 pixels. Sizing the readouts for these
 * keeps the sliders from changing length as their numbers do.
 */
#define OPACITY_WIDEST_VALUE			@"100%"
#define WIDTH_WIDEST_VALUE				@"640px"

@interface AIAppearancePreferences ()
- (NSMenu *)_appearanceStyleMenu;
- (NSMenu *)_emoticonPackMenu;
- (void)_rebuildEmoticonMenuAndSelectActivePack;
- (void)xtrasChanged:(NSNotification *)notification;

- (void)configureDockIconMenu;
- (void)configureStatusIconsMenu;
- (void)configureServiceIconsMenu;
- (void)configureMenuBarIconsMenu;

- (AISettingsFormView *)buildSettingsForm;
- (AISettingsFormView *)settingsForm;
- (NSWindow *)paneWindow;
- (void)menusChanged;
- (void)layOutChangedMenus;
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
	NSString		*trimmed = [label stringByTrimmingCharactersInSet:whitespace];

	while ([trimmed hasSuffix:@":"]) {
		trimmed = [[trimmed substringToIndex:([trimmed length] - 1)] stringByTrimmingCharactersInSet:whitespace];
	}

	return trimmed;
}

@implementation AIAppearancePreferences

/*!
 * @brief Preference pane properties
 */
- (NSString *)paneIdentifier
{
	return @"Appearance";
}
- (NSString *)paneName{
    return AILocalizedString(@"Appearance","Appearance preferences label");
}
- (NSImage *)paneIcon
{
	return [NSImage imageNamed:@"pref-appearance" forClass:[self class]];
}

#pragma mark View

/*!
 * @brief Build our view instead of loading a nib.
 *
 * The pane's controls are pop up buttons, sliders, switches and push buttons —
 * nothing a nib could supply that a factory cannot — so there is nothing left
 * for AppearancePrefs.xib to hand over; the form creates and arranges all of
 * them. Mirrors -[AIModularPane view] so the subclass hooks fire in the same
 * order.
 */
- (NSView *)view
{
	if (!view) {
		AISettingsFormView	*form = [self buildSettingsForm];

		view = form;

		[self viewDidLoad];
		[self localizePane];

		//-viewDidLoad filled the pop up menus; the rows measure the buttons in this last layout pass.
		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief The settings form we live in, or nil before -view built it
 */
- (AISettingsFormView *)settingsForm
{
	return ([view isKindOfClass:[AISettingsFormView class]] ? (AISettingsFormView *)view : nil);
}

/*!
 * @brief The window our sheets belong on, or nil once the pane has closed
 *
 * Deliberately not @c [[self view] window]: -view builds the whole pane when it
 * finds none, so a stray call after -closeView would raise a second form —
 * with a second set of preference observers — that nothing ever closes again. A
 * sheet with no window shows as a window of its own, which is the old behaviour
 * for a pane that has no window either.
 */
- (NSWindow *)paneWindow
{
	return [[self settingsForm] window];
}

/*!
 * @brief Create the controls and stack them into cards
 *
 * Three cards: the contact list window, the themes it is drawn with, and the
 * icon packs. Each control keeps the preference key and group its nib
 * counterpart had; the two "Size to fit" options, which used to sit indented
 * under an "Automatic Sizing:" label, are plain rows of the first card now, so
 * the pane needs no indentation to express what belongs together.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[AISettingsFormView alloc] initWithWidth:APPEARANCE_PANE_INITIAL_WIDTH];

	/* Opacity and width are settings, not a canvas: a slider running the whole card reads as the
	 * main event of its row, which these are not. Capped to the moderate length the events pane's
	 * volume slider has, sitting on the right by its readout. */
	[form setMaximumSliderWidth:200.0];

	/* The whole application, before any single window: light, dark, or whatever the
	 * system says. The card is named after what it decides rather than after the
	 * pane, which carries the same word and would only say it twice.
	 */
	[form addSectionHeader:AILocalizedString(@"Light and Dark", "Section header above the choice between a light and a dark application")];

	popUp_appearanceStyle = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Appearance", "Label of the menu choosing between system, light and dark appearance for the whole application")
			  popUpButton:popUp_appearanceStyle
		  accessoryButton:nil];

	//Icon packs
	[form addSectionHeader:AILocalizedString(@"Icons","Section header above the icon pack settings")];

	popUp_emoticons = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	button_customizeEmoticons = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Customize…",nil)
																target:self
																action:@selector(customizeEmoticons:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Emoticons:",nil))
			  popUpButton:popUp_emoticons
		  accessoryButton:button_customizeEmoticons];

	popUp_dockIcon = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	button_showAllDockIcons = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Show All…",nil)
															  target:self
															  action:@selector(showAllDockIcons:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Dock Icon:",nil))
			  popUpButton:popUp_dockIcon
		  accessoryButton:button_showAllDockIcons];

	popUp_statusIcons = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Status Icons:",nil))
			  popUpButton:popUp_statusIcons
		  accessoryButton:nil];

	popUp_serviceIcons = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Service Icons:",nil))
			  popUpButton:popUp_serviceIcons
		  accessoryButton:nil];

	popUp_menuBarIcons = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Menu Bar Icons:",nil))
			  popUpButton:popUp_menuBarIcons
		  accessoryButton:nil];

	return form;
}

/*!
 * @brief A pop up menu was (re)built; let the form measure the buttons again
 *
 * Every menu here is filled after its button was created, and refilled whenever
 * an Xtra appears or disappears. A pop up row re-measures its button on each
 * layout, so all this has to do is ask for one.
 *
 * The request is coalesced into the next pass of the run loop: -xtrasChanged:
 * rebuilds up to six menus in a row and would otherwise pay for six layouts, and
 * a menu which rebuilds itself while it is open (-menuNeedsUpdate:) must not be
 * re-measured until it has closed again — the default run loop mode is not
 * served while a menu tracks.
 */
- (void)menusChanged
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(layOutChangedMenus) object:nil];
	[self performSelector:@selector(layOutChangedMenus) withObject:nil afterDelay:0.0];
}

- (void)layOutChangedMenus
{
	[[self settingsForm] noteContentSizeChanged];
}

#pragma mark Configuration

/*!
 * @brief Configure the preference view
 */
- (void)viewDidLoad
{
	[popUp_appearanceStyle setMenu:[self _appearanceStyleMenu]];

	//Observe preference changes
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_EMOTICONS];
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_APPEARANCE];

	//Observe xtras changes
	[[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(xtrasChanged:)
									   name:AIXtrasDidChangeNotification
									 object:nil];	
	[self xtrasChanged:nil];
}

/*!
 * @brief View will close
 */
- (void)viewWillClose
{
	[adium.preferenceController unregisterPreferenceObserver:self];

	/* Only our own registration: removeObserver:self would silently take any
	 * other one — a category's, a superclass's — with it. */
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:AIXtrasDidChangeNotification
												  object:nil];

	/* Everything we scheduled: a relayout from -menuNeedsUpdate:, but also the
	 * theme and layout editors -presetNameSheetControllerDidEnd:… defers. A
	 * deferred call reaching a closed pane would ask -view for a window and so
	 * build a second form, with a second set of observers, which nothing would
	 * ever close again. */
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	/* The form owns every control; clearing the pane's own references with it
	 * lets the form and its controls go when the view does. */
	popUp_statusIcons = nil;
	popUp_serviceIcons = nil;
	popUp_menuBarIcons = nil;
	popUp_emoticons = nil;
	popUp_dockIcon = nil;
	popUp_appearanceStyle = nil;
	button_customizeEmoticons = nil;
	button_showAllDockIcons = nil;
}

/*!
 * @brief Undo everything -view built
 *
 * The pane registers itself as a preference and a notification observer while
 * its view exists; -closeView is what unregisters it again, and it is idempotent.
 */
- (void)dealloc
{
	[self closeView];
}

/*!
 * @brief Xtras changed, update our menus to reflect the new Xtras
 */
- (void)xtrasChanged:(NSNotification *)notification
{
	NSString *filenameExtension = [notification object];

	/* Which kind of Xtra changed is asked of the type its extension stands for, rather than of the
	 * extension itself, so that a file named by any of a type's extensions is still recognised.
	 *
	 * Asked by tag rather than through +typeWithFilenameExtension:, which reads like the obvious
	 * way and is not the same question: for these types, all of them declared by Adium and
	 * packages rather than files, it answers with a made up type derived from the extension, and
	 * every comparison below would then fail and no menu would ever be rebuilt. Asking by tag
	 * gives what the function this replaces gave, which was checked against it for the Xtra
	 * extensions and for an ordinary one.
	 *
	 * No extension at all means every kind changed, which is how this is called once at setup to
	 * fill the menus in the first place. It has to be kept away from the question: asked for
	 * nothing, the type system does not answer nothing, it raises, and the menus that are built
	 * here and nowhere else then stay empty. */
	UTType *type = (filenameExtension ?
					[UTType typeWithTag:filenameExtension
							   tagClass:UTTagClassFilenameExtension
					   conformingToType:nil] :
					nil);

	//The same question as before: is this that type, not is it a kind of it
	BOOL (^changed)(NSString *) = ^BOOL(NSString *identifier) {
		return (!type || [[type identifier] isEqualToString:identifier]);
	};

	if (changed(@"com.adiumx.emoticonset")) {
		[self _rebuildEmoticonMenuAndSelectActivePack];
	}

	if (changed(@"com.adiumx.dockicon")) {
		[self configureDockIconMenu];
	}

	if (changed(@"com.adiumx.serviceicons")) {
		[self configureServiceIconsMenu];
	}

	if (changed(@"com.adiumx.statusicons")) {
		[self configureStatusIconsMenu];
	}

	if (changed(@"com.adiumx.menubaricons")) {
		[self configureMenuBarIconsMenu];
	}

	//Menus which grew or shrank change how much room their buttons need
	[self menusChanged];
}

/*!
 * @brief Preferences changed
 *
 * Update controls in our view to reflect the changed preferences
 */
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key object:(AIListObject *)object
					preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	//Emoticons
	if ([group isEqualToString:PREF_GROUP_EMOTICONS] && !firstTime) {
		[self _rebuildEmoticonMenuAndSelectActivePack];
	}
	
	//Appearance
	if ([group isEqualToString:PREF_GROUP_APPEARANCE]) {
		if (firstTime) {
			//Absent means "match the system", which is tag zero
			[popUp_appearanceStyle selectItemWithTag:[[prefDict objectForKey:KEY_APPEARANCE_STYLE] integerValue]];
		}

		//Selected menu items
		if (firstTime || [key isEqualToString:KEY_STATUS_ICON_PACK]) {
			[popUp_statusIcons selectItemWithTitle:[prefDict objectForKey:KEY_STATUS_ICON_PACK]];
			
			//If the prefDict's item isn't present, we're using the default, so select that one
			if (![popUp_statusIcons selectedItem]) {
				[popUp_statusIcons selectItemWithTitle:[adium.preferenceController defaultPreferenceForKey:KEY_STATUS_ICON_PACK
																										group:PREF_GROUP_APPEARANCE
																									   object:nil]];
			}			
		}
		if (firstTime || [key isEqualToString:KEY_SERVICE_ICON_PACK]) {
			[popUp_serviceIcons selectItemWithTitle:[prefDict objectForKey:KEY_SERVICE_ICON_PACK]];
			
			//If the prefDict's item isn't present, we're using the default, so select that one
			if (![popUp_serviceIcons selectedItem]) {
				[popUp_serviceIcons selectItemWithTitle:[adium.preferenceController defaultPreferenceForKey:KEY_SERVICE_ICON_PACK
																										group:PREF_GROUP_APPEARANCE
																									   object:nil]];
			}
		}
		if (firstTime || [key isEqualToString:KEY_MENU_BAR_ICONS]) {
			[popUp_menuBarIcons selectItemWithTitle:[prefDict objectForKey:KEY_MENU_BAR_ICONS]];
			
			//If the prefDict's item isn't present, we're using the default, so select that one
			if (![popUp_menuBarIcons selectedItem]) {
				[popUp_menuBarIcons selectItemWithTitle:[adium.preferenceController defaultPreferenceForKey:KEY_MENU_BAR_ICONS
																										group:PREF_GROUP_APPEARANCE
																									   object:nil]];
			}
		}
		if (firstTime || [key isEqualToString:KEY_ACTIVE_DOCK_ICON]) {
			/* popUp_dockIcon initially is a single-item popup menu with just the active icon; it is built
			 * lazily in menuNeedsUpdate:.  If we haven't displayed it yet, we'll need to configure again
			 * to show just the current icon */
			if (![popUp_dockIcon selectItemWithRepresentedObject:[prefDict objectForKey:KEY_ACTIVE_DOCK_ICON]])
				[self configureDockIconMenu];
		}
	}
}

/*!
 * @brief Rebuild the emoticon menu
 */
- (void)_rebuildEmoticonMenuAndSelectActivePack
{
	[popUp_emoticons setMenu:[self _emoticonPackMenu]];
	
	//Update the selected pack
	NSArray	*activeEmoticonPacks = [adium.emoticonController activeEmoticonPacks];
	NSInteger		numActivePacks = [activeEmoticonPacks count];
	
	if (numActivePacks == 0) {
		[popUp_emoticons selectItemWithTag:AIEmoticonMenuNone];
	} else if (numActivePacks > 1) {
		[popUp_emoticons selectItemWithTag:AIEmoticonMenuMultiple];
	} else {
		[popUp_emoticons selectItemWithRepresentedObject:[activeEmoticonPacks objectAtIndex:0]];
	}

	//A pack more or less changes how much room the button needs
	[self menusChanged];
}

/*!
 * @brief Save changed preferences
 */
- (IBAction)changePreference:(id)sender
{
 	if (sender == popUp_statusIcons) {
        [adium.preferenceController setPreference:[[sender selectedItem] title]
                                             forKey:KEY_STATUS_ICON_PACK
                                              group:PREF_GROUP_APPEARANCE];
		
	} else if (sender == popUp_serviceIcons) {
        [adium.preferenceController setPreference:[[sender selectedItem] title]
                                             forKey:KEY_SERVICE_ICON_PACK
                                              group:PREF_GROUP_APPEARANCE];
	} else if (sender == popUp_menuBarIcons) {
        [adium.preferenceController setPreference:[[sender selectedItem] title]
                                             forKey:KEY_MENU_BAR_ICONS
                                              group:PREF_GROUP_APPEARANCE];	
	} else if (sender == popUp_dockIcon) {
        [adium.preferenceController setPreference:[[sender selectedItem] representedObject]
                                             forKey:KEY_ACTIVE_DOCK_ICON
                                              group:PREF_GROUP_APPEARANCE];
		
	} else if (sender == popUp_appearanceStyle) {
		//The default, "match the system", is stored as nothing at all
		NSInteger styleTag = [[sender selectedItem] tag];
		[adium.preferenceController setPreference:(styleTag ? [NSNumber numberWithInteger:styleTag] : nil)
										   forKey:KEY_APPEARANCE_STYLE
											group:PREF_GROUP_APPEARANCE];

	} else if (sender == popUp_emoticons) {
		if ([[sender selectedItem] tag] != AIEmoticonMenuMultiple) {
			//Disable all active emoticons
			NSArray			*activePacks = [[adium.emoticonController activeEmoticonPacks] mutableCopy];
			AIEmoticonPack	*pack, *selectedPack;
			
			selectedPack = [[sender selectedItem] representedObject];
			
			[adium.preferenceController delayPreferenceChangedNotifications:YES];

			for (pack in activePacks) {
				[adium.emoticonController setEmoticonPack:pack enabled:NO];
			}
			
			//Enable the selected pack
			if (selectedPack) [adium.emoticonController setEmoticonPack:selectedPack enabled:YES];

			[adium.preferenceController delayPreferenceChangedNotifications:NO];
		}
	}
}

//Emoticons ------------------------------------------------------------------------------------------------------------
#pragma mark Emoticons
/*!
 *
 */
- (IBAction)customizeEmoticons:(id)sender
{
	AIEmoticonPreferences *emoticonPreferences = [[AIEmoticonPreferences alloc] init];
	[emoticonPreferences openOnWindow:[self paneWindow]];
}

/*!
 *
 */
- (NSMenu *)_emoticonPackMenu
{
	NSMenu			*menu = [[NSMenu alloc] init];
	NSEnumerator	*enumerator = [[adium.emoticonController availableEmoticonPacks] objectEnumerator];
	AIEmoticonPack	*pack;
	NSMenuItem		*menuItem;
		
	//Add the "No Emoticons" option
	menuItem = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"None",nil)
																	 target:nil
																	 action:nil
															  keyEquivalent:@""];
	[menuItem setImage:[NSImage imageNamed:@"emoticonBlank" forClass:[self class]]];
	[menuItem setTag:AIEmoticonMenuNone];
	[menu addItem:menuItem];

	//Add the "Multiple packs selected" option
	if ([[adium.emoticonController activeEmoticonPacks] count] > 1) {
		menuItem = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Multiple Packs Selected",nil)
																		 target:nil
																		 action:nil
																  keyEquivalent:@""];
		[menuItem setImage:[NSImage imageNamed:@"emoticonBlank" forClass:[self class]]];
		[menuItem setTag:AIEmoticonMenuMultiple];
		[menu addItem:menuItem];
	}

	//Divider
	[menu addItem:[NSMenuItem separatorItem]];

	//Emoticon Packs
	while ((pack = [enumerator nextObject])) {
		menuItem = [[NSMenuItem alloc] initWithTitle:[pack name]
																		 target:nil
																		 action:nil
																  keyEquivalent:@""];
		[menuItem setRepresentedObject:pack];
		[menuItem setImage:[pack menuPreviewImage]];
		[menu addItem:menuItem];
	}

	return menu;
}


//Contact list options -------------------------------------------------------------------------------------------------
#pragma mark Contact list options
/*!
 *
 */
- (NSMenu *)_appearanceStyleMenu
{
	NSMenu	*menu = [[NSMenu alloc] init];

	//Tags are the stored values: 0 match the system (stored as nothing), 1 light, 2 dark
	NSArray *titles = [NSArray arrayWithObjects:
					   AILocalizedString(@"Match System", "Appearance choice: follow the system's light/dark setting"),
					   AILocalizedString(@"Light", "Appearance choice: always light"),
					   AILocalizedString(@"Dark", "Appearance choice: always dark"),
					   nil];

	for (NSUInteger tag = 0; tag < [titles count]; tag++) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[titles objectAtIndex:tag]
													  action:nil
											   keyEquivalent:@""];
		[item setTag:tag];
		[menu addItem:item];
	}

	return menu;
}

#pragma mark Dock icons
/*!
 *
 */
- (IBAction)showAllDockIcons:(id)sender
{
	AIDockIconSelectionSheet *dockIconSelectionSheet = [[AIDockIconSelectionSheet alloc] init];
	[dockIconSelectionSheet openOnWindow:[self paneWindow]];
}

/*!
 * @brief Return the menu item for a dock icon
 */
- (NSMenuItem *)meuItemForDockIconPackAtPath:(NSString *)packPath
{
	NSMenuItem	*menuItem;
	NSString	*name = nil;
	NSString	*packName = [[packPath lastPathComponent] stringByDeletingPathExtension];
	AIIconState	*preview = nil;
	
	[adium.dockController getName:&name
					   previewState:&preview
				  forIconPackAtPath:packPath];
	
	if (!name) {
		name = packName;
	}
	
	menuItem = [[NSMenuItem alloc] initWithTitle:name
																	 target:nil
																	 action:nil
															  keyEquivalent:@""];
	[menuItem setRepresentedObject:packName];
	[menuItem setImage:[[preview image] imageByScalingForMenuItem]];
	
	return menuItem;
}

/*!
 * @brief Returns an array of menu items of all dock icon packs
 */
- (NSArray *)_dockIconMenuArray
{
	NSMutableArray		*menuItemArray = [NSMutableArray array];
	NSEnumerator		*enumerator;
	NSString			*packPath;

	enumerator = [[adium.dockController availableDockIconPacks] objectEnumerator];
	while ((packPath = [enumerator nextObject])) {
		[menuItemArray addObject:[self meuItemForDockIconPackAtPath:packPath]];
	}

	[menuItemArray sortUsingSelector:@selector(titleCompare:)];

	return menuItemArray;
}

/*!
 * @brief Configure the dock icon meu initially or after the xtras change
 *
 * Initially, the dock icon menu just has the currently selected icon; the others will be generated lazily if the icon is displayed, in menuNeedsUpdate:
 */
- (void)configureDockIconMenu
{
	NSMenu		*tempMenu = [[NSMenu alloc] init];
	NSString	*iconPath;
	NSString	*activePackName = [adium.preferenceController preferenceForKey:KEY_ACTIVE_DOCK_ICON
																		   group:PREF_GROUP_APPEARANCE];
	iconPath = [adium pathOfPackWithName:activePackName
							   extension:@"AdiumIcon"
					  resourceFolderName:FOLDER_DOCK_ICONS];
	
	[tempMenu addItem:[self meuItemForDockIconPackAtPath:iconPath]];
	[tempMenu setDelegate:self];
	[tempMenu setTitle:@"Temporary Dock Icon Menu"];

	[popUp_dockIcon setMenu:tempMenu];
	[popUp_dockIcon selectItemWithRepresentedObject:activePackName];

	[self menusChanged];
}

//Status, Service and Menu Bar icons ---------------------------------------------------------------------------------------------
#pragma mark Status, service and menu bar icons
- (NSMenuItem *)menuItemForIconPackAtPath:(NSString *)packPath class:(Class)iconClass
{
	NSString	*name = [[packPath lastPathComponent] stringByDeletingPathExtension];
	NSMenuItem	*menuItem = [[NSMenuItem alloc] initWithTitle:name
																				  target:nil
																				  action:nil
																		   keyEquivalent:@""];
	[menuItem setRepresentedObject:name];
	[menuItem setImage:[iconClass previewMenuImageForIconPackAtPath:packPath]];	

	return menuItem;
}

/*!
 * @brief Builds and returns an icon pack menu
 *
 * @param packs NSArray of icon pack file paths
 * @param iconClass The controller class (AIStatusIcons, AIServiceIcons) for icon pack previews
 */
- (NSArray *)_iconPackMenuArrayForPacks:(NSArray *)packs class:(Class)iconClass
{
	NSMutableArray	*menuItemArray = [NSMutableArray array];
	NSString		*packPath;

	for (packPath in packs) {
		[menuItemArray addObject:[self menuItemForIconPackAtPath:packPath class:iconClass]];
	}
	
	[menuItemArray sortUsingSelector:@selector(titleCompare:)];

	return menuItemArray;	
}

- (void)configureStatusIconsMenu
{
	NSMenu		*tempMenu = [[NSMenu alloc] init];
	NSString	*iconPath;
	NSString	*activePackName = [adium.preferenceController preferenceForKey:KEY_STATUS_ICON_PACK
																		   group:PREF_GROUP_APPEARANCE];
	iconPath = [adium pathOfPackWithName:activePackName
							   extension:@"AdiumStatusIcons"
					  resourceFolderName:@"Status Icons"];
	
	if (!iconPath) {
		activePackName = [adium.preferenceController defaultPreferenceForKey:KEY_STATUS_ICON_PACK
																		 group:PREF_GROUP_APPEARANCE
																		object:nil];
		
		iconPath = [adium pathOfPackWithName:activePackName
								   extension:@"AdiumStatusIcons"
						  resourceFolderName:@"Status Icons"];		
	}
	[tempMenu addItem:[self menuItemForIconPackAtPath:iconPath class:[AIStatusIcons class]]];
	[tempMenu setDelegate:self];
	[tempMenu setTitle:@"Temporary Status Icons Menu"];
	
	[popUp_statusIcons setMenu:tempMenu];
	[popUp_statusIcons selectItemWithRepresentedObject:activePackName];

	[self menusChanged];
}

- (void)configureServiceIconsMenu
{
	NSMenu		*tempMenu = [[NSMenu alloc] init];
	NSString	*iconPath;
	NSString	*activePackName = [adium.preferenceController preferenceForKey:KEY_SERVICE_ICON_PACK
																		   group:PREF_GROUP_APPEARANCE];
	iconPath = [adium pathOfPackWithName:activePackName
							   extension:@"AdiumServiceIcons"
					  resourceFolderName:@"Service Icons"];
	
	if (!iconPath) {
		activePackName = [adium.preferenceController defaultPreferenceForKey:KEY_SERVICE_ICON_PACK
																		 group:PREF_GROUP_APPEARANCE
																		object:nil];
		
		iconPath = [adium pathOfPackWithName:activePackName
								   extension:@"AdiumServiceIcons"
						  resourceFolderName:@"Service Icons"];		
	}
	[tempMenu addItem:[self menuItemForIconPackAtPath:iconPath class:[AIServiceIcons class]]];
	[tempMenu setDelegate:self];
	[tempMenu setTitle:@"Temporary Service Icons Menu"];
	
	[popUp_serviceIcons setMenu:tempMenu];
	[popUp_serviceIcons selectItemWithRepresentedObject:activePackName];

	[self menusChanged];
}

- (void)configureMenuBarIconsMenu
{
	NSMenu		*tempMenu = [[NSMenu alloc] init];
	NSString	*iconPath;
	NSString	*activePackName = [adium.preferenceController preferenceForKey:KEY_MENU_BAR_ICONS
																		   group:PREF_GROUP_APPEARANCE];
	iconPath = [adium pathOfPackWithName:activePackName
							   extension:@"AdiumMenuBarIcons"
					  resourceFolderName:@"Menu Bar Icons"];
	
	if (!iconPath) {
		activePackName = [adium.preferenceController defaultPreferenceForKey:KEY_MENU_BAR_ICONS
																		 group:PREF_GROUP_APPEARANCE
																		object:nil];
		
		iconPath = [adium pathOfPackWithName:activePackName
								   extension:@"AdiumMenuBarIcons"
						  resourceFolderName:@"Menu Bar Icons"];		
	}
	[tempMenu addItem:[self menuItemForIconPackAtPath:iconPath class:[AIMenuBarIcons class]]];
	[tempMenu setDelegate:self];
	[tempMenu setTitle:@"Temporary Menu Bar Icons Menu"];
	
	[popUp_menuBarIcons setMenu:tempMenu];
	[popUp_menuBarIcons selectItemWithRepresentedObject:activePackName];

	[self menusChanged];
}

#pragma mark Menu delegate
- (void)menuNeedsUpdate:(NSMenu *)menu
{
	NSString		*title =[menu title];
	NSString		*repObject = nil;
	NSArray			*menuItemArray = nil;
	NSPopUpButton	*popUpButton;
	
	if ([title isEqualToString:@"Temporary Dock Icon Menu"]) {
		//If the menu has @"Temporary Dock Icon Menu" as its title, we should update it to have all dock icons, not just our selected one
		menuItemArray = [self _dockIconMenuArray];
		repObject = [adium.preferenceController preferenceForKey:KEY_ACTIVE_DOCK_ICON
															 group:PREF_GROUP_APPEARANCE];
		popUpButton = popUp_dockIcon;
		
	} else if ([title isEqualToString:@"Temporary Status Icons Menu"]) {		
		menuItemArray = [self _iconPackMenuArrayForPacks:[adium allResourcesForName:@"Status Icons" 
																	 withExtensions:@"AdiumStatusIcons"] 
												   class:[AIStatusIcons class]];
		repObject = [adium.preferenceController preferenceForKey:KEY_STATUS_ICON_PACK
															 group:PREF_GROUP_APPEARANCE];
		popUpButton = popUp_statusIcons;
		
	} else if ([title isEqualToString:@"Temporary Service Icons Menu"]) {		
		menuItemArray = [self _iconPackMenuArrayForPacks:[adium allResourcesForName:@"Service Icons" 
																	 withExtensions:@"AdiumServiceIcons"] 
												   class:[AIServiceIcons class]];
		repObject = [adium.preferenceController preferenceForKey:KEY_SERVICE_ICON_PACK
															 group:PREF_GROUP_APPEARANCE];
		popUpButton = popUp_serviceIcons;
		
	} else if ([title isEqualToString:@"Temporary Menu Bar Icons Menu"]) {
		menuItemArray = [self _iconPackMenuArrayForPacks:[adium allResourcesForName:@"Menu Bar Icons" 
																	 withExtensions:@"AdiumMenuBarIcons"] 
												   class:[AIMenuBarIcons class]];
		repObject = [adium.preferenceController preferenceForKey:KEY_MENU_BAR_ICONS
															 group:PREF_GROUP_APPEARANCE];
		popUpButton = popUp_menuBarIcons;	
	}
	
	if (menuItemArray) {
		NSMenuItem		*menuItem;
		
		//Remove existing items
		[menu removeAllItems];
		
		//Clear the title so we know we don't need to do this again
		[menu setTitle:@""];
		
		//Add the items
		for (menuItem in menuItemArray) {
			[menu addItem:menuItem];
		}
		
		//Clear the title so we know we don't need to do this again
		[menu setTitle:@""];
		
		//Put a checkmark by the appropriate menu item
		[popUpButton selectItemWithRepresentedObject:repObject];

		//A menu of every pack instead of just the active one may need a wider button
		[self menusChanged];
	}	
}

@end
