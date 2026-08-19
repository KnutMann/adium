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

#import "AISoundController.h"
#import "AIPassthroughScrollView.h"
#import "Adium/ESContactAlertsViewController.h"
#import <Adium/AIContactAlertsControllerProtocol.h>
#import "ESGlobalEventsPreferences.h"
#import "ESGlobalEventsPreferencesPlugin.h"
#import "AIUserNotificationPlugin.h"
#import <Adium/AISettingsFormView.h>
#import <Adium/ESPresetManagementController.h>
#import <Adium/ESPresetNameSheetController.h>
#import <Adium/AISoundSet.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <AIUtilities/AIVariableHeightFlexibleColumnsOutlineView.h>
#import <AIUtilities/AIVerticallyCenteredTextCell.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIArrayAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIImageTextCell.h>
#import <AIUtilities/AIBundleAdditions.h>

#define PREF_GROUP_EVENT_PRESETS	@"Event Presets"
#define CUSTOM_TITLE				AILocalizedString(@"Custom",nil)
#define COPY_IN_PARENTHESIS			AILocalizedString(@"(Copy)","Copy, in parenthesis, as a noun indicating that the preceding item is a duplicate")

/* The events card is never empty — the list shows every event, with or without actions — but a
 * moment can exist before the first reload. A card of no height at all would read as a missing
 * card rather than as an empty list. */
#define ALERTS_LIST_MINIMUM_HEIGHT	48.0f

#define VOLUME_SOUND_PATH   [NSString pathWithComponents:[NSArray arrayWithObjects: \
	@"/", @"System", @"Library", @"LoginPlugins", \
	[@"BezelServices" stringByAppendingPathExtension:@"loginPlugin"], \
	@"Contents", @"Resources", \
	[@"volume" stringByAppendingPathExtension:@"aiff"], \
	nil]]

@interface ESGlobalEventsPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (AISettingsFormView *)settingsForm;
- (NSView *)volumeRowView;
- (void)configureAlertsList;
- (void)alertsListFrameChanged:(NSNotification *)notification;
- (void)deferredUpdateAlertsListHeight;
- (void)updateAlertsListHeight;
- (void)tearDown;

- (void)popUp:(NSPopUpButton *)inPopUp shouldShowCustom:(BOOL)showCustom;
- (void)xtrasChanged:(NSNotification *)notification;
- (void)contactAlertsDidChangeForActionID:(NSString *)actionID;
- (NSMenu *)eventPresetsMenu;
- (IBAction)selectSoundSet:(id)sender;
- (void)changeNotificationsEnabled:(id)sender;
- (NSMenu *)_soundSetMenu;
- (NSString *)_localizedTitle:(NSString *)englishTitle;
- (void)saveCurrentEventPreset;
- (void)setAndConfigureEventPresetsMenu;
- (void)updateSoundSetSelection;
- (void)updateSoundSetSelectionForSoundSet:(AISoundSet *)soundSet;

- (void)selectEventPreset:(id)sender;
- (void)addNewPreset:(id)sender;
- (void)editPresets:(id)sender;
- (void)showPresetCopySheet:(NSString *)originalPresetName;
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
	/* U+003A and the full width U+FF1A the CJK translations use */
	NSCharacterSet	*colons = [NSCharacterSet characterSetWithCharactersInString:@":："];
	NSString		*trimmed = [label stringByTrimmingCharactersInSet:whitespace];

	while ([trimmed length] > 0 &&
		   [colons characterIsMember:[trimmed characterAtIndex:([trimmed length] - 1)]]) {
		trimmed = [[trimmed substringToIndex:([trimmed length] - 1)] stringByTrimmingCharactersInSet:whitespace];
	}

	return trimmed;
}

@implementation ESGlobalEventsPreferences
- (NSString *)paneIdentifier
{
	return @"Events";
}
- (NSString *)paneName{
    return AILocalizedString(@"Events", "Name of preferences and tab for specifying what Adium should do when events occur - for example, display a notification when John signs on.");
}
/*!
 * @brief Nib name
 */
- (NSString *)nibName{
    return @"GlobalEventsPreferences";
}
- (NSImage *)paneIcon
{
	return [NSImage imageNamed:@"pref-events" forClass:[self class]];
}

- (BOOL)resizableHorizontally
{
	return YES;
}

#pragma mark View

/*!
 * @brief Our view: the nib's controls, arranged by the settings form
 *
 * The nib still supplies the two pop ups, the volume slider with its speaker buttons and — above
 * all — the ESContactAlertsViewController with its outline view, but no longer their arrangement.
 * Mirrors -[AIModularPane view] so the subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		[NSBundle ai_loadNibNamed:[self nibName] owner:self];

		/* The nib set the inherited 'view' outlet to its own top level view, retaining it. We take
		 * that reference over rather than retaining it again; it keeps the nib alive while we use
		 * its controls, and -tearDown releases it. */
		[nibView release];
		nibView = view;
		view = nil;

		/* -viewDidLoad runs before the form is built: it fills both pop up menus, and the pop up
		 * rows measure their buttons in the layout pass below. */
		[self viewDidLoad];

		view = [[self buildSettingsForm] retain];

		[self localizePane];

		[(AISettingsFormView *)view layoutForWidth:NSWidth([view frame])];

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
 * @brief Stack the nib's controls into cards
 *
 * Three of them: what the pane is about, the preset/sound set/volume controls, and the list of
 * events with the action bar under it. The nib's two field labels became the row labels.
 */
- (AISettingsFormView *)buildSettingsForm
{
	/* No width of our own: the form falls back to a usable one and the preferences window hands it
	 * its column width right afterwards. */
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:0.0f] autorelease];

	/* The form lays everything out by frame, and a view out of a nib saved without Auto Layout
	 * arrives with translatesAutoresizingMaskIntoConstraints turned off. Every way into the form
	 * adopts the views handed to it for frame based layout, except the pop up row, so these two
	 * have to say it for themselves. */
	for (NSPopUpButton *popUp in [NSArray arrayWithObjects:popUp_eventPreset, popUp_soundSet, nil]) {
		[popUp setTranslatesAutoresizingMaskIntoConstraints:YES];
	}

	//Card 1: what an event is, before any control that acts on one
	[form addInfoRow:AILocalizedString(@"When an event occurs — a contact signs on, a message arrives, a file transfer finishes — Adium can play a sound, show a notification, or take other actions. Pick a preset, or configure each event below.",
									   "Paragraph at the top of the Events preferences explaining what events are")
		   withImage:[NSImage imageNamed:@"pref-events" forClass:[self class]]];
	[form endCard];

	//Card 2: the preset and the sounds it brings along
	[form addSectionHeader:AILocalizedString(@"Notifications", "Section header above the event preset, sound set and volume settings")];

	/* The global gate for Notification Center. Everything below decides what happens per
	 * event; this decides whether banners appear at all. An absent preference means on,
	 * so only an explicit off is ever stored and everybody starts with the old behavior.
	 */
	NSNumber *notificationsEnabled = [adium.preferenceController preferenceForKey:KEY_NOTIFICATIONS_ENABLED
																			 group:PREF_GROUP_NOTIFICATIONS];
	switch_notifications = [AISettingsFormView switchWithTarget:self action:@selector(changeNotificationsEnabled:)];
	[switch_notifications setState:((notificationsEnabled && ![notificationsEnabled boolValue]) ? NSControlStateValueOff : NSControlStateValueOn)];
	[form addRowWithLabel:AILocalizedString(@"Show notifications", "Label of the global switch for Notification Center banners on the Events pane")
				  control:switch_notifications
				   detail:AILocalizedString(@"Banners in Notification Center for the events below. Whether macOS lets them through is decided in System Settings.", "Second line under the global notifications switch")];

	/* Pop up rows rather than plain control rows: both menus are rebuilt while the pane is open —
	 * presets as they are added and removed, sound sets as Xtras come and go — and the buttons then
	 * have to be free to grow and to shrink again. */
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Event preset:",nil))
			  popUpButton:popUp_eventPreset
		  accessoryButton:nil];

	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Sound set:",nil))
			  popUpButton:popUp_soundSet
		  accessoryButton:nil];

	[form addRowWithLabel:AILocalizedString(@"Volume", "Accessibility label for the sound volume slider")
				  control:[self volumeRowView]];

	/* Card 3: the list of events. The header reuses the pane name's key on purpose, so every
	 * existing translation of "Events" applies here as well. */
	[form addSectionHeader:AILocalizedString(@"Events", "Name of preferences and tab for specifying what Adium should do when events occur - for example, display a notification when John signs on.")];

	[self configureAlertsList];

	/* The list is the card: it fills it edge to edge and its own height decides how tall the card
	 * is. The height has to be right before the row is added — the form reads the natural size of
	 * a hosted view when it takes it in. */
	[self updateAlertsListHeight];
	[form addEdgeToEdgeRow:view_alertsHost];

	/* ...and the buttons hang under it, the way System Settings puts a bar under a list. Both keep
	 * the targets the nib gave them: they belong to the alerts view controller, not to us. */
	NSSegmentedControl	*addRemoveControl = [contactAlertsViewController valueForKey:@"button_addOrRemoveAlert"];
	NSButton			*editButton = [contactAlertsViewController valueForKey:@"button_edit"];

	[addRemoveControl setSegmentStyle:NSSegmentStyleRounded];

	/* The nib built the button small for the old, cramped layout; a form's accessory bar sits next
	 * to regular sized cards. */
	[editButton setControlSize:NSControlSizeRegular];
	[editButton setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeRegular]]];
	[editButton sizeToFit];

	[form addAccessoryView:[AISettingsFormView rowOfViews:[NSArray arrayWithObjects:
															addRemoveControl, editButton, nil]]];

	return form;
}

/*!
 * @brief The volume row: the two speaker buttons with the slider between them
 *
 * All three come from the nib with their actions already wired to -selectVolume:; the buttons jump
 * to the ends of the scale. They stay one bundle rather than becoming a form slider row, because a
 * slider row has no place for the buttons — and losing them would lose the one-click way to mute.
 *
 * The bundle has a fixed, moderate width and goes into an ordinary control row, which puts its
 * trailing edge on the same inset the pop ups above end on. What broke that alignment before was
 * not the row but the buttons: the nib draws each speaker as a 32 point icon with air around the
 * glyph inside its own frame, so the bundle's frame ended on the inset and the visible speaker
 * ended well short of it. The buttons wear tightly-fitting SF symbols now — template images, so
 * they follow the label colour the way every other inline symbol here does.
 */
- (NSView *)volumeRowView
{
	const CGFloat	gap = 6.0f;
	const CGFloat	sliderWidth = 200.0f;

	struct { NSButton *button; NSString *symbol; } speakers[] = {
		{ button_minvolume, @"speaker.fill" },
		{ button_maxvolume, @"speaker.wave.3.fill" },
	};
	for (unsigned i = 0; i < 2; i++) {
		NSImage *symbol = [NSImage imageWithSystemSymbolName:speakers[i].symbol
									accessibilityDescription:nil];
		if (symbol) {
			[speakers[i].button setImage:symbol];
			[speakers[i].button setBordered:NO];
			/* The nib marks both buttons transparent, and a transparent button draws nothing
			 * at all - bezel and image alike. They were bare click targets in the old layout;
			 * here the glyph is the whole point. */
			[speakers[i].button setTransparent:NO];
			[speakers[i].button setImagePosition:NSImageOnly];
			[speakers[i].button sizeToFit];
		}
	}

	NSRect		minFrame = [button_minvolume frame];
	NSRect		maxFrame = [button_maxvolume frame];
	NSRect		sliderFrame = [slider_volume frame];
	CGFloat		height = ceil(fmax(NSHeight(sliderFrame), fmax(NSHeight(minFrame), NSHeight(maxFrame))));
	CGFloat		width = NSWidth(minFrame) + gap + sliderWidth + gap + NSWidth(maxFrame);
	NSView		*row = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)] autorelease];

	for (NSView *view in [NSArray arrayWithObjects:button_minvolume, slider_volume, button_maxvolume, nil]) {
		[view setTranslatesAutoresizingMaskIntoConstraints:YES];
		[view setAutoresizingMask:NSViewNotSizable];
		[row addSubview:view];
	}

	[button_minvolume setFrameOrigin:NSMakePoint(0, floor((height - NSHeight(minFrame)) / 2.0))];
	[slider_volume setFrame:NSMakeRect(NSMaxX([button_minvolume frame]) + gap,
									   floor((height - NSHeight(sliderFrame)) / 2.0),
									   sliderWidth, NSHeight(sliderFrame))];
	[button_maxvolume setFrameOrigin:NSMakePoint(NSMaxX([slider_volume frame]) + gap,
												 floor((height - NSHeight(maxFrame)) / 2.0))];

	return row;
}

/*!
 * @brief Turn the alerts controller's bordered, scrolling list into the list a card is made of
 *
 * The outline itself is untouched — the same columns, the same cells, the same controller behind
 * it — but it no longer scrolls: it is laid out at the full height of its rows and the preferences
 * column scrolls instead. Its nib scroll view is replaced by an AIPassthroughScrollView (a table
 * view outside of any scroll view loses its tiling and its clip view), which hands the scroll
 * wheel on to the column behind it instead of swallowing it the way the nib's bordered one did.
 *
 * The controller's view and outlets are reached through KVC: they are wired inside that controller
 * by the nib, the controller is shared with the contact inspector, and giving it pane-only
 * accessors for the benefit of one host would be the tail wagging the dog. The container keeps
 * being the controller's 'view', so the sheets it opens keep finding their window through it.
 */
- (void)configureAlertsList
{
	if (view_alertsHost) return;

	view_alertsHost = [contactAlertsViewController valueForKey:@"view"];
	outlineView_alerts = [contactAlertsViewController valueForKey:@"outlineView_summary"];

	NSScrollView			*nibScrollView = [outlineView_alerts enclosingScrollView];
	AIPassthroughScrollView	*scrollView = [[[AIPassthroughScrollView alloc] initWithFrame:[view_alertsHost bounds]] autorelease];

	/* Held across the reparenting below: leaving the nib's clip view is what would otherwise
	 * release the outline before the new scroll view owns it. */
	[[outlineView_alerts retain] autorelease];

	[scrollView setDocumentView:outlineView_alerts];
	[nibScrollView removeFromSuperview];

	[scrollView setBorderType:NSNoBorder];
	[scrollView setDrawsBackground:NO];
	[scrollView setHasVerticalScroller:NO];
	[scrollView setHasHorizontalScroller:NO];
	[scrollView setVerticalScrollElasticity:NSScrollElasticityNone];
	[scrollView setHorizontalScrollElasticity:NSScrollElasticityNone];
	[scrollView setAutomaticallyAdjustsContentInsets:NO];
	[scrollView setContentInsets:NSEdgeInsetsZero];
	[scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

	[view_alertsHost setAutoresizesSubviews:YES];
	[view_alertsHost addSubview:scrollView];
	[scrollView setFrame:[view_alertsHost bounds]];

	/* Row heights are measured against the outline's width, so it has to follow the width the form
	 * gives the card from the very first layout. */
	[outlineView_alerts setTranslatesAutoresizingMaskIntoConstraints:YES];
	[outlineView_alerts setAutoresizingMask:NSViewWidthSizable];
	//A focus ring drawn inside a card would trace the list rather than the card
	[outlineView_alerts setFocusRingType:NSFocusRingTypeNone];

	/* The outline re-tiles whenever alerts change, rows expand or the width moves; its frame is
	 * where all of those changes meet, so that is what the card's height follows. */
	[outlineView_alerts setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(alertsListFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:outlineView_alerts];
}

/*!
 * @brief The outline re-tiled; follow it with the card, but not from in here
 *
 * Coalesced onto the next turn of the run loop: the frame moves from inside the outline's own
 * tiling and from inside the form's layout pass, and resizing the card right there would re-enter
 * the very layout that is running.
 */
- (void)alertsListFrameChanged:(NSNotification *)notification
{
	if (alertsHeightUpdateScheduled) return;

	alertsHeightUpdateScheduled = YES;
	[self performSelector:@selector(deferredUpdateAlertsListHeight) withObject:nil afterDelay:0.0];
}

- (void)deferredUpdateAlertsListHeight
{
	alertsHeightUpdateScheduled = NO;
	[self updateAlertsListHeight];
}

/*!
 * @brief Grow or shrink the card around the list to fit its rows
 *
 * The list is the edge to edge row of a card, so its height is the card's height. The height is
 * asked of the outline itself — -totalHeight is the sum of its variable row heights — rather than
 * measured off a frame mid-tiling. Converges rather than loops: a width change may re-measure the
 * rows once more, but a height already in place is left alone.
 */
- (void)updateAlertsListHeight
{
	if (!view_alertsHost || !outlineView_alerts) return;

	CGFloat		height = ceil((CGFloat)[outlineView_alerts totalHeight]);

	if (height < ALERTS_LIST_MINIMUM_HEIGHT) height = ALERTS_LIST_MINIMUM_HEIGHT;

	if (fabs(NSHeight([view_alertsHost frame]) - height) < 0.5f) return;

	[view_alertsHost setFrameSize:NSMakeSize(NSWidth([view_alertsHost frame]), height)];

	//Only a card the form is actually holding asks it for a layout
	if ([view_alertsHost superview]) [[self settingsForm] noteContentSizeChanged];
}

#pragma mark Configuration

/*!
 * @brief Configure the preference view
 */
- (void)viewDidLoad
{
	//Configure our global contact alerts view controller
	[contactAlertsViewController setConfigureForGlobal:YES];
	[contactAlertsViewController setDelegate:self];
	[contactAlertsViewController setShowEventsInEditSheet:NO];

	//Observe for installation of new sound sets and set up the sound set menu
	[[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(xtrasChanged:)
									   name:AIXtrasDidChangeNotification
									 object:nil];

	//This will build the sound set menu
	[self xtrasChanged:nil];

	//Presets menu
	[self setAndConfigureEventPresetsMenu];

	//And event presets to update our presets menu
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_EVENT_PRESETS];

	//Ensure the correct sound set is selected
	[self updateSoundSetSelection];

	//Volume
	[slider_volume setDoubleValue:[[adium.preferenceController preferenceForKey:KEY_SOUND_CUSTOM_VOLUME_LEVEL
																		   group:PREF_GROUP_SOUNDS] doubleValue]];
}

- (void)localizePane
{
	[[button_minvolume cell] setAccessibilityLabel:AILocalizedString(@"Set minimum volume", "Accessibility label for button to set to the minimum sound volume")];
	[[button_maxvolume cell] setAccessibilityLabel:AILocalizedString(@"Set maximum volume", "Accessibility label for button to set to the maximum sound volume")];
	[[slider_volume cell] setAccessibilityLabel:AILocalizedString(@"Volume", "Accessibility label for the sound volume slider")];
}

/*!
 * @brief Preference view is closing
 *
 * Nothing is saved here: every control on this pane has always written the moment it was touched,
 * and the preferences window only gets here when the window itself closes.
 */
- (void)viewWillClose
{
	[self tearDown];
}

/*!
 * @brief Undo everything -viewDidLoad and -buildSettingsForm set up
 *
 * Idempotent, so that it is safe to run it from both -viewWillClose and -dealloc. Running it from
 * -dealloc matters, because -viewWillClose is only reached when the preference window closes.
 */
- (void)tearDown
{
	//A deferred height update reaching a torn down pane would message outlets already forgotten
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	alertsHeightUpdateScheduled = NO;

	[adium.preferenceController unregisterPreferenceObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[contactAlertsViewController viewWillClose];
	[contactAlertsViewController release]; contactAlertsViewController = nil;

	/* Every item of these menus carries our address as its target, so the menus go rather than
	 * outlive us on a button the form has not released yet. */
	for (NSPopUpButton *popUp in [NSArray arrayWithObjects:popUp_eventPreset, popUp_soundSet, nil]) {
		[popUp setMenu:[[[NSMenu alloc] initWithTitle:@""] autorelease]];
	}

	//The nib wired these three to us; a control which outlives us must not still point at us
	[slider_volume setTarget:nil];
	[button_minvolume setTarget:nil];
	[button_maxvolume setTarget:nil];
	[switch_notifications setTarget:nil];
	switch_notifications = nil;

	/* All of these references are non-retaining and the views behind them go away with the form or
	 * with the nib's view, either of which may be released after us; forget them so a second
	 * -tearDown cannot message freed memory. */
	popUp_eventPreset = nil;
	popUp_soundSet = nil;
	label_eventPreset = nil;
	label_soundSet = nil;
	slider_volume = nil;
	button_minvolume = nil;
	button_maxvolume = nil;
	view_alertsHost = nil;
	outlineView_alerts = nil;

	[nibView release]; nibView = nil;
}

/*!
 * @brief Deallocate
 */
- (void)dealloc
{
	//Releases the form and runs -viewWillClose, but only if a view was ever built
	[self closeView];
	//...so tear down again for the pane which never showed itself. -tearDown is idempotent.
	[self tearDown];
	[super dealloc];
}

/*!
 * @brief PREF_GROUP_EVENT_PRESETS changed; update our presets menu
 */
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	if ([group isEqualToString:PREF_GROUP_EVENT_PRESETS]) {
		if (!key || [key isEqualToString:@"Event Presets"]) {
			//Update when the available event presets change
			[self setAndConfigureEventPresetsMenu];
		}
	}
}

/*!
 * @brief Set if a popup should have a "Custom" menu item
 */
- (void)popUp:(NSPopUpButton *)inPopUp shouldShowCustom:(BOOL)showCustom
{
	NSMenuItem	*lastItem = [inPopUp lastItem];
	BOOL		customIsShowing = (lastItem && (![lastItem representedObject] &&
												[[lastItem title] isEqualToString:CUSTOM_TITLE]));
	if (showCustom && !customIsShowing) {
		//Add 'custom' then select it
		[[inPopUp menu] addItem:[NSMenuItem separatorItem]];
		[[inPopUp menu] addItemWithTitle:CUSTOM_TITLE
								  target:nil
								  action:nil
						   keyEquivalent:@""];
		[inPopUp selectItem:[inPopUp lastItem]];

	} else if (!showCustom && customIsShowing) {
		//If it currently has a 'custom' item listed, remove it and the separator above it
		[inPopUp removeItemAtIndex:([inPopUp numberOfItems]-1)];
		[inPopUp removeItemAtIndex:([inPopUp numberOfItems]-1)];

	} else {
		return;
	}

	//A pop up row is measured afresh at every layout; a menu which changed its items asks for one
	[[self settingsForm] noteContentSizeChanged];
}

/*!
 * @brief Update our soundset menu if a new sound set is instaled
 */
- (void)xtrasChanged:(NSNotification *)notification
{
	if (!notification || [[notification object] caseInsensitiveCompare:@"AdiumSoundset"] == NSOrderedSame) {
		//Build the soundset menu
		[popUp_soundSet setMenu:[self _soundSetMenu]];

		//The rebuilt menu may need a wider or narrower button
		[[self settingsForm] noteContentSizeChanged];
	}
}

#pragma mark Event presets

/*!
 * @brief Buld and return the event presets menu
 *
 * The menu will have built in presets, a divider, user-set presets, a divider, and then the preset management item(s)
 */
- (NSMenu *)eventPresetsMenu
{
	NSMenu			*eventPresetsMenu = [[NSMenu alloc] init];
	NSEnumerator	*enumerator;
	NSDictionary	*eventPreset;
	NSMenuItem		*menuItem;

	//Built in event presets
	enumerator = [[plugin builtInEventPresetsArray] objectEnumerator];
	while ((eventPreset = [enumerator nextObject])) {
		NSString		*name = [eventPreset objectForKey:@"Name"];

		//Add a menu item for the set
		menuItem = [[[NSMenuItem alloc] initWithTitle:[self _localizedTitle:name]
																		 target:self
																		 action:@selector(selectEventPreset:)
																  keyEquivalent:@""] autorelease];
		[menuItem setRepresentedObject:eventPreset];
		[eventPresetsMenu addItem:menuItem];
	}

	NSArray	*storedEventPresetsArray = [plugin storedEventPresetsArray];

	if ([storedEventPresetsArray count]) {
		[eventPresetsMenu addItem:[NSMenuItem separatorItem]];

		for (eventPreset in storedEventPresetsArray) {
			NSString		*name = [eventPreset objectForKey:@"Name"];

			//Add a menu item for the set
			menuItem = [[[NSMenuItem alloc] initWithTitle:name
																			 target:self
																			 action:@selector(selectEventPreset:)
																	  keyEquivalent:@""] autorelease];
			[menuItem setRepresentedObject:eventPreset];
			[eventPresetsMenu addItem:menuItem];
		}
	}

	//Edit Presets
	[eventPresetsMenu addItem:[NSMenuItem separatorItem]];

	menuItem = [[[NSMenuItem alloc] initWithTitle:[AILocalizedString(@"Add New Preset",nil) stringByAppendingEllipsis]
																	 target:self
																	 action:@selector(addNewPreset:)
															  keyEquivalent:@""] autorelease];
	[eventPresetsMenu addItem:menuItem];

	menuItem = [[[NSMenuItem alloc] initWithTitle:[AILocalizedString(@"Edit Presets",nil) stringByAppendingEllipsis]
																	 target:self
																	 action:@selector(editPresets:)
															  keyEquivalent:@""] autorelease];
	[eventPresetsMenu addItem:menuItem];

	return [eventPresetsMenu autorelease];
}

- (void)selectActiveEventInPopUp
{
	NSString	*activeEventSetName = [adium.preferenceController preferenceForKey:KEY_ACTIVE_EVENT_SET
																			   group:PREF_GROUP_EVENT_PRESETS];

	//First try to set the localized version
	[popUp_eventPreset selectItemWithTitle:[self _localizedTitle:activeEventSetName]];
	//If that fails, look for one exactly matching
	if (![popUp_eventPreset selectedItem]) [popUp_eventPreset selectItemWithTitle:activeEventSetName];
	//And if that fails, select the first item (something went wrong, we should at least have a selection)
	if (![popUp_eventPreset selectedItem]) [popUp_eventPreset selectItemAtIndex:0];
}

- (void)setAndConfigureEventPresetsMenu
{
	[popUp_eventPreset setMenu:[self eventPresetsMenu]];
	[self selectActiveEventInPopUp];

	//A pop up row is measured afresh at every layout; a rebuilt menu asks for one
	[[self settingsForm] noteContentSizeChanged];
}

/*!
 * @brief Selected an event preset
 *
 * Pass it to the plugin, which will perform necessary changes to our contact alerts
 */
- (void)selectEventPreset:(id)sender
{
	NSDictionary	*eventPreset = [sender representedObject];
	[plugin setEventPreset:eventPreset];

	[self updateSoundSetSelection];
}

/*
 * Add a new preset
 *
 * Called by the "Add New preset..." menu item.  Functions the same as duplicate from the preset management, duplicating
 * the current event set with a new name.
 */
- (void)addNewPreset:(id)sender
{
	NSString	*defaultName;
	NSString	*explanatoryText;

	defaultName = [NSString stringWithFormat:@"%@ %@",
		[self _localizedTitle:[adium.preferenceController preferenceForKey:KEY_ACTIVE_EVENT_SET
																	   group:PREF_GROUP_EVENT_PRESETS]],
		COPY_IN_PARENTHESIS];
	explanatoryText = AILocalizedString(@"Enter a unique name for this new event set.",nil);

	ESPresetNameSheetController *presetNameSheetController = [[ESPresetNameSheetController alloc] initWithDefaultName:defaultName
																									  explanatoryText:explanatoryText
																									  notifyingTarget:self
																											 userInfo:nil];
	[presetNameSheetController showOnWindow:[[self view] window]];

	//Get our event presets menu back to its proper selection
	[self selectActiveEventInPopUp];
}

/*!
 * @brief Manage presets
 *
 * Called by the "Edit Presets..." menu item
 */
- (void)editPresets:(id)sender
{
	ESPresetManagementController *presentManagementController = [[ESPresetManagementController alloc] initWithPresets:[plugin storedEventPresetsArray]
																										   namedByKey:@"Name"
																										 withDelegate:self];
	[presentManagementController showOnWindow:[[self view] window]];

	//Get our event presets menu back to its proper selection
	[self selectActiveEventInPopUp];
}

- (BOOL)allowDeleteOfPreset:(NSDictionary *)preset
{
	NSString	*name = [preset objectForKey:@"Name"];
	NSString	*localizedTitle;

	localizedTitle = [self _localizedTitle:[adium.preferenceController preferenceForKey:KEY_ACTIVE_EVENT_SET
																					group:PREF_GROUP_EVENT_PRESETS]];
	//Don't allow the active preset to be deleted
	return (![localizedTitle isEqualToString:name]);
}

- (NSArray *)renamePreset:(NSDictionary *)preset toName:(NSString *)newName inPresets:(NSArray *)presets renamedPreset:(id *)renamedPreset
{
	NSString				*oldPresetName = [preset objectForKey:@"Name"];
	NSMutableDictionary		*newPreset = [[preset mutableCopy] autorelease];
	NSString				*localizedCurrentName = [self _localizedTitle:[adium.preferenceController preferenceForKey:KEY_ACTIVE_EVENT_SET
																												   group:PREF_GROUP_EVENT_PRESETS]];
	[newPreset setObject:newName
				  forKey:@"Name"];

	//Mark the newly created (but still functionally identical) event set as active if the old one was active
	if ([localizedCurrentName isEqualToString:oldPresetName]) {
		[adium.preferenceController setPreference:newName
											 forKey:KEY_ACTIVE_EVENT_SET
											  group:PREF_GROUP_EVENT_PRESETS];
	}

	//Remove the original one from the array, and add the newly-renamed one
	[plugin deleteEventPreset:preset];
	[plugin saveEventPreset:newPreset];

	if (renamedPreset) *renamedPreset = newPreset;

	//Return an updated presets array
	return [plugin storedEventPresetsArray];
}

- (NSArray *)duplicatePreset:(NSDictionary *)preset inPresets:(NSArray *)presets createdDuplicate:(id *)duplicatePreset
{
	NSMutableDictionary	*newEventPreset = [preset mutableCopy];
	NSString			*newName = [NSString stringWithFormat:@"%@ %@", [preset objectForKey:@"Name"], COPY_IN_PARENTHESIS];
	[newEventPreset setObject:newName
					   forKey:@"Name"];

	//Remove the original preset's order index
	[newEventPreset removeObjectForKey:@"OrderIndex"];

	//Now save the new preset
	[plugin saveEventPreset:newEventPreset];

	//Return the created duplicate by reference
	if (duplicatePreset != NULL) *duplicatePreset = [[newEventPreset retain] autorelease];

	//Cleanup
	[newEventPreset release];

	//Return an updated presets array
	return [plugin storedEventPresetsArray];
}

- (NSArray *)deletePreset:(NSDictionary *)preset inPresets:(NSArray *)presets
{
	//Remove the preset
	[plugin deleteEventPreset:preset];

	//Return an updated presets array
	return [plugin storedEventPresetsArray];
}

- (NSArray *)movePreset:(NSDictionary *)preset toIndex:(NSUInteger)idx inPresets:(NSArray *)presets presetAfterMove:(id *)presetAfterMove
{
	NSMutableDictionary	*newEventPreset = [preset mutableCopy];
	CGFloat newOrderIndex;
	if (idx == 0) {
		newOrderIndex = (CGFloat)[[[presets objectAtIndex:0] objectForKey:@"OrderIndex"] doubleValue] / 2.0f;

	} else if (idx < [presets count]) {
		CGFloat above = (CGFloat)[[[presets objectAtIndex:idx-1] objectForKey:@"OrderIndex"] doubleValue];
		CGFloat below = (CGFloat)[[[presets objectAtIndex:idx] objectForKey:@"OrderIndex"] doubleValue];
		newOrderIndex = ((above + below) / 2.0f);

	} else {
		newOrderIndex = [plugin nextOrderIndex];
	}

	[newEventPreset setObject:[NSNumber numberWithDouble:newOrderIndex]
					   forKey:@"OrderIndex"];

	//Now save the new preset
	[plugin saveEventPreset:newEventPreset];
	if (presetAfterMove != NULL) *presetAfterMove = [[newEventPreset retain] autorelease];
	[newEventPreset release];

	//Return an updated presets array
	return [plugin storedEventPresetsArray];
}

#pragma mark Contact alerts changed by user
- (void)contactAlertsViewController:(ESContactAlertsViewController *)inController
					   updatedAlert:(NSDictionary *)newAlert
						   oldAlert:(NSDictionary *)oldAlert
{
	[self contactAlertsDidChangeForActionID:[newAlert objectForKey:KEY_ACTION_ID]];
}

- (void)contactAlertsViewController:(ESContactAlertsViewController *)inController
					   deletedAlert:(NSDictionary *)deletedAlert
{
	[self contactAlertsDidChangeForActionID:[deletedAlert objectForKey:KEY_ACTION_ID]];
}

/*!
 * @brief Contact alerts were changed by the user
 */
- (void)contactAlertsDidChangeForActionID:(NSString *)actionID
{
	if (!actionID ||
		[actionID isEqualToString:SOUND_ALERT_IDENTIFIER]) {

		NSArray			*alertsArray = [adium.contactAlertsController alertsForListObject:nil
																				withEventID:nil
																				   actionID:SOUND_ALERT_IDENTIFIER];
		NSMenuItem		*soundMenuItem;

		if (![alertsArray count]) {
			//We can select "None" if there are no sounds
			soundMenuItem = (NSMenuItem *)[popUp_soundSet itemWithTitle:@"None"];

		} else {
			/* Otherwise, check to see if we remain in our proper soundset.
			 * Note that this won't detect if we return to a soundset, but that'd be an expensive search.
			 */
			soundMenuItem = (NSMenuItem *)[popUp_soundSet selectedItem];

			AISoundSet		*soundSet = [soundMenuItem representedObject];
			NSEnumerator	*enumerator;
			NSString		*key;
			NSDictionary	*sounds = [soundSet sounds];

			if ([alertsArray count] && ![sounds count]) {
				//If we have one or more sound alerts and there are no sounds in this sound set ("None" sound set), there's no matching soundSetMenuitem.
				soundMenuItem = nil;

			} else {
				//First, check to see if any sounds which are present within this sound set have been changed
				enumerator = [sounds keyEnumerator];
				while ((key = [enumerator nextObject])) {
					NSDictionary *soundAlert = [ESGlobalEventsPreferencesPlugin soundAlertForKey:key
																					inSoundsDict:sounds];
					if (![alertsArray containsObject:soundAlert]) {
						soundMenuItem = nil;
						break;
					}
				}

				//Next, see if any sounds not present within this sound set have been added
				if (soundMenuItem) {
					NSDictionary	*alertDict;
					for (alertDict in alertsArray) {
						if ([[alertDict objectForKey:KEY_ACTION_ID] isEqualToString:SOUND_ALERT_IDENTIFIER]) {
							NSString *englishEvent = [adium.contactAlertsController eventIDForEnglishDisplayName:key];
							/*
							 * If the sounds dictionary has no action for this event, or it has one but
							 * it is for a different sound than specified, the sound set has been changed
							 */
							if (![sounds objectForKey:englishEvent] ||
								![[[alertDict objectForKey:KEY_ACTION_DETAILS] objectForKey:KEY_ALERT_SOUND_PATH] isEqualToString:[sounds objectForKey:englishEvent]]) {
								soundMenuItem = nil;
								break;
							}
						}
					}
				}

			}
		}

		[self selectSoundSet:([soundMenuItem representedObject] ? soundMenuItem : nil)];

	} else {
		[self saveCurrentEventPreset];
	}
}

#pragma mark Notifications
/*!
 * @brief The global notifications switch was flipped.
 *
 * Off is stored, on removes the stored preference — absent means on, so a profile
 * that never touched the switch carries nothing. Turning it on also asks the system
 * whether Adium may notify at all: this switch looks exactly like the one in System
 * Settings, and standing on while macOS drops every banner would be a lie the user
 * cannot see through here. Only an actual denial earns the hint; "not yet asked" and
 * "allowed" stay quiet.
 */
- (void)changeNotificationsEnabled:(id)sender
{
	BOOL enabled = ([switch_notifications state] == NSControlStateValueOn);

	[adium.preferenceController setPreference:(enabled ? nil : [NSNumber numberWithBool:NO])
									   forKey:KEY_NOTIFICATIONS_ENABLED
										group:PREF_GROUP_NOTIFICATIONS];

	if (!enabled) return;

	[[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
		if (settings.authorizationStatus != UNAuthorizationStatusDenied) return;

		//The completion handler arrives on a background queue; the alert belongs on the main thread
		dispatch_async(dispatch_get_main_queue(), ^{
			NSAlert *alert = [[[NSAlert alloc] init] autorelease];

			[alert setAlertStyle:NSAlertStyleWarning];
			[alert setMessageText:AILocalizedString(@"macOS is blocking Adium's notifications", "Title of the alert shown when notifications are switched on here while System Settings denies them")];
			[alert setInformativeText:AILocalizedString(@"The switch here is on, but System Settings does not allow Adium to show notifications. Allow them under Notifications in System Settings.", "Body of the alert shown when notifications are switched on here while System Settings denies them")];
			[alert addButtonWithTitle:AILocalizedString(@"Open System Settings", "Button on the notifications alert that jumps to the Notifications pane of System Settings")];
			[alert addButtonWithTitle:AILocalizedString(@"OK", nil)];

			if ([alert runModal] == NSAlertFirstButtonReturn) {
				NSString *deepLink = [NSString stringWithFormat:@"x-apple.systempreferences:com.apple.preference.notifications?id=%@",
									  [[NSBundle mainBundle] bundleIdentifier]];
				[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:deepLink]];
			}
		});
	}];
}

#pragma mark Sound sets
/*!
 * @brief Called when an item in the sound set popUp is selected.
 *
 * Also called after the user changes sounds manually, by -[ESGlobalEventsPreferences contactAlertsDidChangeForActionID].
 */
- (IBAction)selectSoundSet:(id)sender
{
	//Apply the sound set so its events are in the current alerts.
	if (sender) {
		[plugin applySoundSet:[sender representedObject]];
	}

	/* Update the selection, which will select Custom as appropriate.  This must be done before saving the event
	 * preset so the menu is on the correct sound set to save.
	 */
	[self updateSoundSetSelectionForSoundSet:[sender representedObject]];

	/* Save the preset which is now updated to have the appropriate sounds;
	 * in saving, the name of the soundset, or @"", will also be saved.
	 */
	[self saveCurrentEventPreset];
}

/*!
 * @brief Revert the event set to how it was before the last attempted operation
 */
- (void)revertToSavedEventSet
{
	NSDictionary		*eventPreset;

	[self selectActiveEventInPopUp];
	eventPreset = [[popUp_eventPreset selectedItem] representedObject];

	[plugin setEventPreset:eventPreset];

	//Ensure the correct sound set is selected
	[self updateSoundSetSelection];
}

/*!
 * @brief Build and return the event set as it should be saved
 */
- (NSMutableDictionary *)currentEventSetForSaving
{
	NSDictionary		*eventPreset = [[popUp_eventPreset selectedItem] representedObject];
	NSMutableDictionary	*currentEventSetForSaving = [[eventPreset mutableCopy] autorelease];

	//Set the sound set, which is just stored here for ease of preference pane display
	NSString			*soundSetName = [[[popUp_soundSet selectedItem] representedObject] name];
	if (soundSetName) {
		[currentEventSetForSaving setObject:soundSetName
									 forKey:KEY_EVENT_SOUND_SET];
	} else {
		[currentEventSetForSaving removeObjectForKey:KEY_EVENT_SOUND_SET];
	}

	//Get and store the alerts array
	NSArray				*alertsArray = [adium.contactAlertsController alertsForListObject:nil
																				withEventID:nil
																				   actionID:nil];
	[currentEventSetForSaving setObject:alertsArray forKey:@"Events"];

	//Ensure this set doesn't claim to be built in.
	[currentEventSetForSaving removeObjectForKey:@"Built In"];

	return currentEventSetForSaving;
}

#pragma mark Volume
//New value selected on the volume slider or chosen by clicking a volume icon
- (IBAction)selectVolume:(id)sender
{
    CGFloat			volume, oldVolume;

	if (sender == slider_volume) {
		volume = (CGFloat)[slider_volume doubleValue];
	} else if (sender == button_maxvolume) {
		volume = (CGFloat)[slider_volume maxValue];
		[slider_volume setDoubleValue:volume];
	} else if (sender == button_minvolume) {
		volume = (CGFloat)[slider_volume minValue];
		[slider_volume setDoubleValue:volume];
	} else {
		volume = 0;
	}

	NSNumber *oldVolumeValue = [adium.preferenceController preferenceForKey:KEY_SOUND_CUSTOM_VOLUME_LEVEL
																		group:PREF_GROUP_SOUNDS];
	oldVolume = (oldVolumeValue ? (CGFloat)[oldVolumeValue doubleValue] : -1.0f);

    //Volume
    if (volume != oldVolume) {
        [adium.preferenceController setPreference:[NSNumber numberWithDouble:volume]
                                             forKey:KEY_SOUND_CUSTOM_VOLUME_LEVEL
                                              group:PREF_GROUP_SOUNDS];

		//Play a sample sound
        [adium.soundController playSoundAtPath:VOLUME_SOUND_PATH];
    }
}

#pragma mark Preset saving

/*!
 * @brief Save the current event preset
 *
 * Called after each event change to immediately update the current preset.
 * If a built-in preset is currently selected, this method will prompt for a new name before saving.
 */
- (void)saveCurrentEventPreset
{
	NSDictionary		*eventPreset = [[popUp_eventPreset selectedItem] representedObject];

	if ([eventPreset objectForKey:@"Built In"] && [[eventPreset objectForKey:@"Built In"] boolValue]) {
		/* Perform after a delay so that if we got here as a result of a sheet-based add or edit of an event
		 * the sheet will close before we try to open a new one. */
		[self performSelector:@selector(showPresetCopySheet:)
				   withObject:[self _localizedTitle:[eventPreset objectForKey:@"Name"]]
				   afterDelay:0];
	} else {
		//Now save the current settings
		[plugin saveEventPreset:[self currentEventSetForSaving]];
	}
}

/*!
 * @brief Show the sheet for naming the preset created by an attempt to modify a built-in set
 *
 * @param originalPresetName The name of the original set, used as a base for the new name.
 */
- (void)showPresetCopySheet:(NSString *)originalPresetName
{
	NSString	*defaultName;
	NSString	*explanatoryText;

	defaultName = [NSString stringWithFormat:@"%@ %@", originalPresetName, COPY_IN_PARENTHESIS];
	explanatoryText = AILocalizedString(@"You are editing a default event set.  Please enter a unique name for your modified set.",nil);

	ESPresetNameSheetController *presetNameSheetController = [[ESPresetNameSheetController alloc] initWithDefaultName:defaultName
													explanatoryText:explanatoryText
													notifyingTarget:self
														   userInfo:nil];
	[presetNameSheetController showOnWindow:[[self view] window]];
}

- (BOOL)presetNameSheetController:(ESPresetNameSheetController *)controller
			  shouldAcceptNewName:(NSString *)newName
						 userInfo:(id)userInfo
{
	return (![[[plugin builtInEventPresets] allKeys] containsObject:newName] &&
		   ![[[plugin storedEventPresets] allKeys] containsObject:newName]);
}

- (void)presetNameSheetControllerDidEnd:(ESPresetNameSheetController *)controller
							 returnCode:(ESPresetNameSheetReturnCode)returnCode
								newName:(NSString *)newName
							   userInfo:(id)userInfo
{
	switch (returnCode) {
		case ESPresetNameSheetOkayReturn:
		{
			//XXX error if overwriting existing set?
			NSMutableDictionary	*newEventPreset = [self currentEventSetForSaving];
			[newEventPreset setObject:newName
							   forKey:@"Name"];

			//Now save the current settings
			[plugin saveEventPreset:newEventPreset];

			//Presets menu
			[adium.preferenceController setPreference:newName
												 forKey:KEY_ACTIVE_EVENT_SET
												  group:PREF_GROUP_EVENT_PRESETS];
			[popUp_eventPreset setMenu:[self eventPresetsMenu]];
			[popUp_eventPreset selectItemWithTitle:newName];

			//The new name may need a wider button; the pop up row re-measures at the next layout
			[[self settingsForm] noteContentSizeChanged];

			break;
		}
		case ESPresetNameSheetCancelReturn:
		{
			[self revertToSavedEventSet];
			break;
		}
	}
}

- (void)updateSoundSetSelectionForSoundSet:(AISoundSet *)soundSet
{
	if (soundSet) {
		[popUp_soundSet selectItemWithRepresentedObject:soundSet];

		[self popUp:popUp_soundSet shouldShowCustom:NO];

	} else {
		[self popUp:popUp_soundSet shouldShowCustom:YES];
	}
}

- (void)updateSoundSetSelection
{
	NSEnumerator	*enumerator = [[adium.soundController soundSets] objectEnumerator];
    AISoundSet		*soundSet;
	NSString		*name;

	name = [[[popUp_eventPreset selectedItem] representedObject] objectForKey:KEY_EVENT_SOUND_SET];
	name = [[name lastPathComponent] stringByDeletingPathExtension];

    while ((soundSet = [enumerator nextObject])) {
		if ([[soundSet name] isEqualToString:name]) break;
	}

	[self updateSoundSetSelectionForSoundSet:soundSet];
}

#define NONE AILocalizedString(@"None",nil)
/*!
 * @brief Build and return a menu of sound set choices
 *
 * The menu items have an action of -[self selectSoundSet:].
 */
- (NSMenu *)_soundSetMenu
{
    NSMenu			*soundSetMenu = [[NSMenu alloc] init];
    NSEnumerator	*enumerator = [[adium.soundController soundSets] objectEnumerator];
	NSMutableArray	*menuItemArray = [NSMutableArray array];
    AISoundSet		*soundSet;
    NSMenuItem		*menuItem, *noneMenuItem = nil;

    while ((soundSet = [enumerator nextObject])) {
		menuItem = [[NSMenuItem alloc] initWithTitle:[self _localizedTitle:[soundSet name]]
											  target:self
											  action:@selector(selectSoundSet:)
									   keyEquivalent:@""
								   representedObject:soundSet];

		if ([[menuItem title] isEqualToString:NONE]) {
			[noneMenuItem release];
			noneMenuItem = menuItem;

		} else {
			[menuItemArray addObject:menuItem];
			[menuItem release];
		}
	}

	[menuItemArray sortUsingSelector:@selector(titleCompare:)];

	for (menuItem in menuItemArray) {
		[soundSetMenu addItem:menuItem];
	}

	if (noneMenuItem) {
		[soundSetMenu addItem:[NSMenuItem separatorItem]];
		[soundSetMenu addItem:noneMenuItem];
		[noneMenuItem release];
	}

    return [soundSetMenu autorelease];
}

#pragma mark Common menu methods
/*!
 * @brief Localized a menu item title for global events preferences
 *
 * @result The equivalent localized title if available; otherwise, the passed English title
 */
- (NSString *)_localizedTitle:(NSString *)englishTitle
{
	NSString	*localizedTitle = nil;

	if ([englishTitle isEqualToString:@"None"])
		localizedTitle = NONE;
	else if ([englishTitle isEqualToString:@"Default Notifications"])
		localizedTitle = AILocalizedString(@"Default Notifications",nil);
	else if ([englishTitle isEqualToString:@"Visual Notifications"])
		localizedTitle = AILocalizedString(@"Visual Notifications",nil);
	else if ([englishTitle isEqualToString:@"Audio Notifications"])
		localizedTitle = AILocalizedString(@"Audio Notifications",nil);

	return (localizedTitle ? localizedTitle : englishTitle);
}

@end
