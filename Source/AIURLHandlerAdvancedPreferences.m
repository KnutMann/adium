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

#import "AIURLHandlerAdvancedPreferences.h"
#import "AIPreferenceWindowController.h"

#import <Adium/AISettingsFormView.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIService.h>

#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIImageDrawingAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>

//Width the form starts out at; the preferences window resizes it to its column.
#define URL_HANDLER_PANE_INITIAL_WIDTH	540.0

@interface AIURLHandlerAdvancedPreferences ()
- (AISettingsFormView *)buildSettingsForm;

- (IBAction)setDefault:(id)sender;
- (IBAction)enforceDefault:(id)sender;
- (IBAction)changeDefaultApplication:(id)sender;

- (void)initializeServiceInformationForSchemes:(NSArray *)schemes;
- (NSMenu *)applicationMenuForScheme:(NSString *)scheme;
- (NSArray *)applicationDictionaryArrayForScheme:(NSString *)scheme;
- (NSArray *)applicationURLsForScheme:(NSString *)scheme;
- (NSString *)serviceNameForScheme:(NSString *)scheme;
- (void)selectDefaultApplications;
- (void)applicationDidBecomeActive:(NSNotification *)notification;
@end

@implementation AIURLHandlerAdvancedPreferences
#pragma mark Preference pane settings
- (AIPreferenceCategory)category
{
    return AIPref_Advanced;
}
/* Unlocalized, unlike the label: the sidebar grouping matches panes by this,
 * and a match must not depend on the user's language. */
- (NSString *)paneIdentifier{
	return @"Default Client";
}
- (NSString *)label{
    return AILocalizedString(@"Default Client",nil);
}
- (NSImage *)image{
	return [NSImage imageNamed:@"pref-defaultclient" forClass:[AIPreferenceWindowController class]];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads a nib for us.
 * AIURLHandlerPreferences.xib, which used to hold this interface, has been deleted along with its entry
 * in the target: nothing loaded it any more, and it still wired outlets this class no longer has,
 * so anything that did load it would have raised rather than fallen back.
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

		settingsForm = form;
		view = form;

		[self viewDidLoad];
		[self localizePane];

		/* The pop up rows measure their buttons themselves at every layout, so all
		 * that is left after -viewDidLoad filled the menus is one more layout pass.
		 */
		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Undo everything -view built.
 *
 * -closeView lets go of the view and is idempotent; without it a deallocated pane
 * would leave the form's rows — and the KVO observations they register on their
 * controls — alive.
 */
- (void)dealloc
{
	[self closeView];
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * Two cards. The first is Adium's claim on the schemes as a whole — the nib's
 * checkbox and its "Set Default for All" button, which stood at opposite ends of
 * the pane with the table between them although they say the same thing in two
 * strengths: once and for good. The second is the choice per scheme, which the
 * nib drew as a table with a service icon, a name and a pop up cell per row;
 * -[AIURLHandlerPlugin uniqueSchemes] is down to two schemes, so two ordinary
 * pop up rows carry it — and a pop up row re-measures its button at every
 * layout, which a table column never did.
 *
 * The first card has no header: it would only repeat the pane's own title.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[AISettingsFormView alloc] initWithWidth:URL_HANDLER_PANE_INITIAL_WIDTH];

	/* The schemes decide how many rows there are, so the list is settled here and
	 * not in -viewDidLoad: a card already on screen cannot grow a row. -uniqueSchemes
	 * is a constant list, so there is nothing to re-read later either.
	 */
	servicesList = [(AIURLHandlerPlugin *)plugin uniqueSchemes];
	[self initializeServiceInformationForSchemes:servicesList];

	//Adium as the default, once and for all
	checkBox_enforceDefault = [AISettingsFormView switchWithTarget:self action:@selector(enforceDefault:)];
	[form addRowWithLabel:AILocalizedString(@"Always set Adium as the default", nil)
				  control:checkBox_enforceDefault];

	/* Under the switch and not as the card's footnote: a footnote is drawn below
	 * the last row, which is the button row below, and "turn it off" would then
	 * read as if it were about a button.
	 */
	[form addDetailRow:AILocalizedString(@"While this is on, Adium claims every chat link again each time it starts. Turn it off to choose an application per link.",
										 "Explanation below the switch which keeps Adium the default client")];

	/* The nib's button, with a row label to name what it acts on: on its own at the
	 * foot of the pane it could lean on the table above it for that, in a card of
	 * two rows it cannot. The button keeps its own title — and with it every
	 * existing translation of that title.
	 */
	button_setDefault = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Set Default for All", nil)
														target:self
														action:@selector(setDefault:)];
	[form addRowWithLabel:AILocalizedString(@"Use Adium for every chat link", "Label of the row whose button makes Adium the default application for all supported link types at once")
				  control:button_setDefault];

	/* One row per scheme. A card with a header and no rows would be drawn as a bold
	 * heading over nothing, so a scheme list which ever comes back empty gets no
	 * card at all rather than an empty one.
	 */
	if ([servicesList count]) {
		[form addSectionHeader:AILocalizedString(@"Chat Links", "Section header above the choice of which application opens which kind of chat link")];

		popUpButtons = [[NSMutableArray alloc] init];

		for (NSString *scheme in servicesList) {
			/* The menu is filled in -viewDidLoad, which is why this is a pop up row
			 * and not a plain control row: only a pop up row measures its button
			 * afresh at every layout, and the title changes again whenever the user
			 * picks another application.
			 */
			NSPopUpButton *popUp = [AISettingsFormView popUpButtonWithTitles:nil
																	  target:self
																	  action:@selector(changeDefaultApplication:)];

			[popUpButtons addObject:popUp];
			[form addRowWithLabel:[self serviceNameForScheme:scheme]
					  popUpButton:popUp
				  accessoryButton:nil];
		}

		[form addFootnote:AILocalizedString(@"Chat links on web pages and in other applications are opened with the application chosen here.",
											"Footnote below the list of chat link types")];
	}

	return form;
}

#pragma mark Configuration

/*!
 * @brief The view loaded: fill the menus and the switch from what is set now
 */
- (void)viewDidLoad
{
	for (NSUInteger index = 0; index < [popUpButtons count]; index++) {
		[[popUpButtons objectAtIndex:index] setMenu:[self applicationMenuForScheme:[servicesList objectAtIndex:index]]];
	}

	[self selectDefaultApplications];

	[checkBox_enforceDefault setState:([[adium.preferenceController preferenceForKey:PREF_KEY_ENFORCE_DEFAULT
																			   group:GROUP_URL_HANDLING] boolValue] ?
									   NSControlStateValueOn : NSControlStateValueOff)];

	[self configureControlDimming];

	/* LaunchServices is written by everybody, not only by us: another client or an
	 * installer can take a scheme over while this window stands open, and nothing
	 * tells us about it. The table asked the plugin again for every cell it drew,
	 * so a change made elsewhere showed up on the next redraw; the pop up buttons
	 * only change when we set something ourselves. Coming back to Adium is the
	 * moment a change made in another application could have happened, so the
	 * selections are re-read then.
	 */
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(applicationDidBecomeActive:)
												 name:NSApplicationDidBecomeActiveNotification
											   object:nil];

	[super viewDidLoad];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
	[self selectDefaultApplications];
}

- (void)viewWillClose
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSApplicationDidBecomeActiveNotification
												  object:nil];

	settingsForm = nil;
	button_setDefault = nil;
	checkBox_enforceDefault = nil;

	/* The pop up buttons belong to the form, which is about to let go of them; the
	 * array is ours. The cache goes with them — it holds their menus, and a menu of
	 * applications is worth asking LaunchServices for again the next time the pane
	 * is opened anyway.
	 */
	popUpButtons = nil;
	services = nil;
	servicesList = nil;

	[super viewWillClose];
}

/*!
 * @brief Dim what the "always" switch decides on the user's behalf.
 *
 * While Adium claims every scheme at every launch, choosing another application
 * per scheme would be undone by the next start, so those rows are dimmed — the
 * table was disabled for exactly that reason.
 *
 * "Set Default for All" stays clickable, as it was in the nib: the switch only
 * acts at launch, and LSSetDefaultHandlerForURLScheme can quietly lose against
 * another application which claims a scheme while Adium runs. Dimming the button
 * would take the one way of putting that right without restarting.
 *
 * A scheme nothing at all is registered for leaves its menu empty; an empty menu
 * has nothing to choose from, so its row stays dimmed either way.
 */
- (void)configureControlDimming
{
	BOOL enforcing = ([checkBox_enforceDefault state] == NSControlStateValueOn);

	for (NSPopUpButton *popUp in popUpButtons) {
		[popUp setEnabled:(!enforcing && [popUp numberOfItems] > 0)];
	}
}

#pragma mark Actions

/*!
 * @brief Make Adium the default for every scheme we support, now.
 *
 * -setAdiumAsDefault comes back through -refreshTable for every scheme it sets;
 * asking once more afterwards costs nothing and keeps this action honest should
 * that ever change.
 */
- (IBAction)setDefault:(id)sender
{
	[(AIURLHandlerPlugin *)plugin setAdiumAsDefault];

	[self refreshTable];
}

- (IBAction)enforceDefault:(id)sender
{
	[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
									   forKey:PREF_KEY_ENFORCE_DEFAULT
										group:GROUP_URL_HANDLING];

	[self configureControlDimming];

	if ([sender state] == NSControlStateValueOn) {
		[(AIURLHandlerPlugin *)plugin setAdiumAsDefault];
	}
}

/*!
 * @brief The user picked an application for one scheme.
 *
 * There is nothing to save when the pane closes: LaunchServices is the storage,
 * and it is written here and now.
 */
- (IBAction)changeDefaultApplication:(id)sender
{
	NSUInteger	index = [popUpButtons indexOfObjectIdenticalTo:sender];
	NSString	*bundleID = [[(NSPopUpButton *)sender selectedItem] representedObject];

	if (index == NSNotFound || !bundleID) return;

	[(AIURLHandlerPlugin *)plugin setDefaultForScheme:[servicesList objectAtIndex:index]
										   toBundleID:bundleID];
}

/*!
 * @brief Show the default application of every scheme.
 *
 * The plugin calls this whenever it sets a default — including at launch, long
 * before anybody opened the preferences window. Asking for [self view] here
 * would build the whole pane for nothing, so a pane without a view has nothing
 * to refresh.
 */
- (void)refreshTable
{
	if (!view) return;

	[self selectDefaultApplications];
}

- (void)selectDefaultApplications
{
	for (NSUInteger index = 0; index < [popUpButtons count]; index++) {
		NSPopUpButton	*popUp = [popUpButtons objectAtIndex:index];
		NSString		*defaultApplication = [(AIURLHandlerPlugin *)plugin defaultApplicationBundleIDForScheme:[servicesList objectAtIndex:index]];
		NSInteger		 itemIndex = (defaultApplication ? [popUp indexOfItemWithRepresentedObject:defaultApplication] : -1);

		/* Nothing matching means the default is an application which does not
		 * declare the scheme (or none is set at all): show no selection rather
		 * than the first item, which would claim something that is not so.
		 */
		if (itemIndex >= 0) {
			[popUp selectItemAtIndex:itemIndex];
		} else {
			[popUp selectItem:nil];
		}
	}

	/* Another application is another title and another width. The pop up row sizes
	 * the button to it on its own, it only has to be asked for a fresh layout.
	 */
	[settingsForm noteContentSizeChanged];
}

#pragma mark Scheme information

- (void)initializeServiceInformationForSchemes:(NSArray *)schemes
{
	services = [[NSMutableDictionary alloc] init];

	for (NSString *scheme in schemes) {
		[services setObject:[NSMutableDictionary dictionary] forKey:scheme];
	}
}

- (NSMenu *)applicationMenuForScheme:(NSString *)scheme
{
	NSMutableDictionary		*servicesInformation = [services objectForKey:scheme];
	NSMenu					*menu = [servicesInformation objectForKey:@"applicationsMenu"];

	if (!menu) {
		menu = [[NSMenu alloc] init];

		for (NSDictionary *application in [self applicationDictionaryArrayForScheme:scheme]) {
			NSMenuItem *menuItem = [menu addItemWithTitle:[application objectForKey:@"ApplicationName"]
												   target:nil
												   action:nil
											keyEquivalent:@""];

			[menuItem setImage:[[application objectForKey:@"ApplicationImage"] imageByScalingForMenuItem]];
			[menuItem setRepresentedObject:[application objectForKey:@"BundleID"]];
		}

		[servicesInformation setObject:menu forKey:@"applicationsMenu"];
	}

	return menu;
}

/*!
 * @brief Every application which can open @a scheme, by name, icon and bundle ID.
 *
 * This used to walk from a bundle ID to an FSRef with LSFindApplicationForInfo,
 * read the name out of the catalog with FSGetCatalogInfo and the icon with
 * GetIconRefFromFileInfo — three Carbon calls, all deprecated for a decade, and
 * any one of them failing threw away the whole list and left an empty menu.
 * LaunchServices hands out application URLs directly, and NSFileManager and
 * NSWorkspace know what to call an application and how to draw it; an entry
 * which cannot be read is now skipped instead of taking its neighbours with it.
 *
 * Sorted by name, because the order LaunchServices answers in is its own.
 */
- (NSArray *)applicationDictionaryArrayForScheme:(NSString *)scheme
{
	NSMutableDictionary		*servicesInformation = [services objectForKey:scheme];
	NSArray					*applications = [servicesInformation objectForKey:@"applications"];

	if (!applications) {
		NSMutableArray		*mutableApplications = [NSMutableArray array];
		NSMutableSet		*seenBundleIDs = [NSMutableSet set];
		NSFileManager		*fileManager = [NSFileManager defaultManager];
		NSWorkspace			*workspace = [NSWorkspace sharedWorkspace];

		for (NSURL *applicationURL in [self applicationURLsForScheme:scheme]) {
			NSString	*path = [applicationURL path];
			//Lower case throughout: -defaultApplicationBundleIDForScheme: answers in lower case
			NSString	*bundleID = [[[NSBundle bundleWithURL:applicationURL] bundleIdentifier] lowercaseString];

			//No bundle ID is nothing we could set as a default; several copies of one application are one entry
			if (!path || !bundleID || [seenBundleIDs containsObject:bundleID]) continue;
			[seenBundleIDs addObject:bundleID];

			//-displayNameAtPath: is the name the Finder shows: the application's own, localized
			NSString	*applicationName = [fileManager displayNameAtPath:path];
			NSImage		*image = [workspace iconForFile:path];

			if (!applicationName) continue;

			/* ...including the extension, for a user who asked the Finder to show
			 * extensions. A menu of applications never shows one.
			 */
			if ([[applicationName pathExtension] isEqualToString:@"app"]) {
				applicationName = [applicationName stringByDeletingPathExtension];
			}

			[mutableApplications addObject:[NSDictionary dictionaryWithObjectsAndKeys:
											bundleID, @"BundleID",
											applicationName, @"ApplicationName",
											image, @"ApplicationImage", /* may be nil, so should be last */
											nil]];
		}

		[mutableApplications sortUsingComparator:^NSComparisonResult(id left, id right) {
			return [[left objectForKey:@"ApplicationName"] localizedStandardCompare:[right objectForKey:@"ApplicationName"]];
		}];

		[servicesInformation setObject:mutableApplications forKey:@"applications"];

		applications = mutableApplications;
	}

	return applications;
}

/*!
 * @brief The URLs of the applications registered for @a scheme.
 */
- (NSArray *)applicationURLsForScheme:(NSString *)scheme
{
	NSURL	*url = [NSURL URLWithString:[scheme stringByAppendingString:@":"]];

	if (!url) return [NSArray array];

	if (@available(macOS 12.0, *)) {
		return [[NSWorkspace sharedWorkspace] URLsForApplicationsToOpenURL:url];
	}

	/* Deployment target 11.0, where NSWorkspace cannot answer this yet, so ask
	 * LaunchServices itself. Not the very same list: kLSRolesAll also hands out
	 * applications which declare the scheme in a role NSWorkspace filters away,
	 * so on 11 the menu can hold an entry or two more than on 12 and later. Both
	 * lists are of applications registered for the scheme, which is what the menu
	 * is about, so the wider one is left as it is rather than guessing at which
	 * roles the newer call keeps.
	 */
	return (__bridge_transfer NSArray *)LSCopyApplicationURLsForURL((__bridge CFURLRef)url, kLSRolesAll);
}

/*!
 * @brief What to call @a scheme in its row label.
 *
 * The name of the service which uses it — the same text the table's service
 * column showed. A scheme whose service is not installed falls back to the
 * scheme itself ("irc:"), which at least names what the row is about; the table
 * put a literal, untranslated "(unknown)" there.
 */
- (NSString *)serviceNameForScheme:(NSString *)scheme
{
	NSMutableDictionary		*servicesInformation = [services objectForKey:scheme];
	NSString				*longServiceName = [servicesInformation objectForKey:@"name"];

	if (!longServiceName) {
		AIService *service = [adium.accountController firstServiceWithServiceID:[(AIURLHandlerPlugin *)plugin serviceIDForScheme:scheme]];

		longServiceName = ([service longDescription] ?: [scheme stringByAppendingString:@":"]);
		[servicesInformation setObject:longServiceName forKey:@"name"];
	}

	return longServiceName;
}

@end
