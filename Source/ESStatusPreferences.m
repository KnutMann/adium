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

#import "ESStatusPreferences.h"
#import "AIStatusController.h"
#import "AICoreComponentLoader.h"
#import "ESiTunesPlugin.h"
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIAccount.h>
#import <Adium/AIEditStateWindowController.h>
#import <Adium/AIStatusMenu.h>
#import <Adium/AIStatusGroup.h>
#import <Adium/AISettingsFormView.h>

/* Width of the three minute fields. Wide enough for more digits than the stepper can produce: a
 * setting made before this pane had a stepper at all may be any number of minutes, and the field
 * shows what is stored rather than what the stepper could reach. */
#define MINUTES_FIELD_WIDTH			52.0
/* The range of the steppers, not of the settings. Zero minutes is not a setting, and a stepper has
 * to stop somewhere; a stored value outside this range is shown and kept as it is. */
#define MINUTES_MINIMUM				1
#define MINUTES_MAXIMUM				999

/* Extra room around the "+", so it is not packed as tightly as the control asks for. Smaller than
 * the account list's ADD_BUTTON_PADDING, which is meant for a "+" plus its menu chevron; this one
 * opens the status editor straight away and has no chevron. */
#define ADD_BUTTON_PADDING			12.0f

/* How long the typing in the format field has to stop before the plugin is told. Announcing the
 * format makes every account rebuild its dynamic content, which is far too much to do once per
 * keystroke. */
#define FORMAT_CHANGE_DELAY			0.5

/* How long before the preview follows the typing. Deliberately far shorter than
 * FORMAT_CHANGE_DELAY and deliberately not the same timer: resolving the format is two passes over
 * a short string and costs nothing, so this delay is only there to stop the line flickering under
 * the caret — the half second above is there because what it triggers is expensive. Hanging the
 * preview off the expensive one would make it visibly lag behind the field. */
#define PREVIEW_UPDATE_DELAY		0.2

@interface ESStatusPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (AISettingsFormView *)settingsForm;
- (void)tearDown;

- (void)configureAddStatusControl;
- (NSArray *)statusItemsForList;
- (void)refreshFromStateArray;
- (NSView *)minutesRowWithField:(NSTextField *)field
						stepper:(NSStepper *)stepper
					  unitLabel:(NSTextField *)unitLabel;

- (void)configureOtherControls;
- (void)refreshDisplayedValues;
- (void)showMinutes:(double)minutes inField:(NSTextField *)field stepper:(NSStepper *)stepper;
- (void)configureAutoAwayStatusStatePopUp;
- (void)prependDoNotChangeItemToMenu:(NSMenu *)menu action:(SEL)action;
- (NSNumber *)statusIDForSelectedMenuItem:(id)sender;
- (void)commitMinutesFromField:(NSTextField *)field
					   stepper:(NSStepper *)stepper
						sender:(id)sender
						forKey:(NSString *)key;
- (void)_selectStatusWithUniqueID:(NSNumber *)uniqueID inPopUpButton:(NSPopUpButton *)inPopUpButton;

- (void)changedAutoAwayStatus:(id)sender;
- (void)changedFastUserSwitchingStatus:(id)sender;
- (void)changedScreenSaverStatus:(id)sender;

- (void)newState;
- (void)editStatus:(AIStatusItem *)statusItem;
- (void)deleteStatus:(AIStatusItem *)statusItem;

//The music status card
- (void)configureMusicStatusControls;
- (void)changeMusicStatusShown:(id)sender;
- (NSTokenField *)formatTokenField;
- (NSArray *)tokenTriggers;
- (NSString *)displayNameForTrigger:(NSString *)trigger;
- (NSArray *)tokensForFormatString:(NSString *)string;
- (NSPopUpButton *)insertTokenPopUpButton;
- (NSTextField *)previewField;
- (ESiTunesPlugin *)musicPlugin;
- (IBAction)changeFormat:(id)sender;
- (void)insertToken:(id)sender;
- (void)refreshNowPlaying:(id)sender;
- (void)askPlayersOnFirstInteraction;
- (NSString *)currentFormat;
- (void)saveFormat;
- (void)postFormatChanged;
- (void)updatePreview;
- (void)setPreviewNeedsUpdate;
- (void)trackChanged:(NSNotification *)notification;
@end

@implementation ESStatusPreferences

- (NSString *)paneIdentifier
{
	return @"Status";
}
- (NSString *)paneName
{
    return AILocalizedString(@"Status",nil);
}
- (NSImage *)paneIcon
{
	return [NSImage imageNamed:@"pref-status" forClass:[self class]];
}

/*!
 * @brief Nib name
 */
- (NSString *)nibName{
    return @"StatusPreferences";
}

#pragma mark View

/*!
 * @brief Our view: the nib's controls, arranged by the settings form
 *
 * The nib supplies the "+" under the list, the minute fields, their steppers and the three status
 * menus, but no longer their arrangement; the list itself is built in code. Mirrors
 * -[AIModularPane view] so the subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		[NSBundle loadNibNamed:[self nibName] owner:self];

		/* The nib set the inherited 'view' outlet to its own top level view, retaining it. We take
		 * that reference over rather than retaining it again; it keeps the nib alive while we use
		 * its controls, and -tearDown releases it. */
		[nibView release];
		nibView = view;
		view = [[self buildSettingsForm] retain];

		[self viewDidLoad];
		[self localizePane];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];

	} else {
		/* The preferences window asks a pane for its view every time that pane is selected, and it
		 * leaves a pane it switches away from by taking its view out of the window - not by closing
		 * it. Nothing on that way out ends editing, so a field left holding a half typed number, or
		 * nothing at all, would come back on screen still holding it while the setting says
		 * something else. This is where that is put right: the counterpart of
		 * -controlTextDidEndEditing: for the exit which never ends editing. */
		[self refreshDisplayedValues];
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
 * Three of them: the statuses with the "+" under them, everything about being idle and away, and
 * the two status changes Adium makes on its own. The checkbox titles of the old layout became
 * row labels, and the sentences they used to continue ("Set idle after [10] minutes of
 * inactivity") became a row of their own — a dependent row, dimmed with the switch above it,
 * rather than an indented one.
 */
- (AISettingsFormView *)buildSettingsForm
{
	/* No width of our own: the form falls back to a usable one and the preferences window hands it
	 * its column width right afterwards. */
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:0.0f] autorelease];

	/* The form lays everything out by frame, and a view out of a nib saved without Auto Layout
	 * arrives with translatesAutoresizingMaskIntoConstraints turned off - the layout engine owns it
	 * and resolves it as ambiguous, which collapses it to nothing. Every way into the form adopts
	 * the views handed to it for frame based layout, except the pop up row, so these three have to
	 * say it for themselves; the other nib views reach the form through -addEdgeToEdgeRow: and
	 * +rowOfViews:, which do it for them. */
	for (NSPopUpButton *popUp in [NSArray arrayWithObjects:
								  popUp_autoAwayStatusState, popUp_fastUserSwitchingStatusState,
								  popUp_screenSaverStatusState, nil]) {
		[popUp setTranslatesAutoresizingMaskIntoConstraints:YES];
	}

	/* Card 1: the list of statuses. "Custom", because that is what the list holds: the states the
	 * user saved, and only those - the built-in ones are deliberately not in here. */
	[form addSectionHeader:AILocalizedString(@"Custom Statuses", "Section title above the list of statuses the user has saved")];

	/* The list is the card: it fills it edge to edge and its height decides how tall the card is.
	 * The form owns it from here on; listView_states is a non-retaining reference. */
	listView_states = [[[AIStatusListView alloc] initWithStatusItems:[self statusItemsForList]] autorelease];
	[listView_states setListDelegate:self];
	[form addEdgeToEdgeRow:listView_states];

	/* ...and the "+" hangs under the right-hand corner of that card, the way System Settings puts
	 * one under a list. Its natural size is what the form arranges it by; nothing here positions
	 * it. */
	[self configureAddStatusControl];
	[form addTrailingAccessoryView:button_addOrRemoveState];

	//Card 2: idle and away
	[form addSectionHeader:AILocalizedString(@"Idle and Away","Section title above the idle and away status settings")];

	checkBox_idle = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Report me as idle","Switch for telling contacts when the user is inactive")
				  control:checkBox_idle];

	[form addRowWithLabel:AILocalizedString(@"Report idle after","Label of the field holding how many minutes of inactivity make the user idle")
				  control:[self minutesRowWithField:textField_idleMinutes
											stepper:stepper_idleMinutes
										  unitLabel:label_idleMinutes]];

	/* A pop up row rather than a plain control row: the menu is rebuilt whenever the saved
	 * statuses change, and the button then has to be free to grow and to shrink again. */
	[form addRowWithLabel:AILocalizedString(@"Change my status to","Label of the menu holding the status set after a while of inactivity")
			  popUpButton:popUp_autoAwayStatusState
		  accessoryButton:nil];

	checkBox_awayReminder = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	/* Says "I set myself" because that is exactly what it now covers, and the second line says which
	 * away it therefore leaves alone. That sentence has to be here: the row directly above this one
	 * is the menu which picks the away Adium sets by itself, and without a word the two read as if
	 * the reminder were about the status the row above it sets. It goes with the switch rather than
	 * above the card, the way a System Settings row explains itself under its own label - the
	 * exception is not about this card, it is about this switch. */
	[form addRowWithLabel:AILocalizedString(@"Remind me when I set myself away","Switch for being reminded that an away status one chose oneself is still on; an away Adium sets on its own is left alone")
				  control:checkBox_awayReminder
				   detail:AILocalizedString(@"An away status Adium sets while you are idle ends at your next keystroke, so no reminder is given for it.",
											"Second line of the away reminder switch, saying which away statuses it leaves alone")];

	[form addRowWithLabel:AILocalizedString(@"Remind me every","Label of the field holding how many minutes lie between two away reminders")
				  control:[self minutesRowWithField:textField_awayReminderMinutes
											stepper:stepper_awayReminderMinutes
										  unitLabel:label_awayReminderMinutes]];

	//Card 3: the status changes Adium makes on its own
	[form addSectionHeader:AILocalizedString(@"Automatic Status Changes","Section title above the fast user switching and screen saver status settings")];

	[form addRowWithLabel:AILocalizedString(@"Status after switching users","Label of the menu holding the status set when another user logs in")
			  popUpButton:popUp_fastUserSwitchingStatusState
		  accessoryButton:nil];

	[form addRowWithLabel:AILocalizedString(@"Status while the screen saver runs","Label of the menu holding the status set while the screen saver runs")
			  popUpButton:popUp_screenSaverStatusState
		  accessoryButton:nil];

	/* Card 4: the music status. Same header key as the status's own title (ESiTunesPlugin), so the
	 * card and the entry it governs in the list above always carry one name. */
	[form addSectionHeader:AILocalizedString(@"Music Status", "Current track information (Track - Artist)")];

	/* The switch is the same setting as the status's switch in the list above: whether the music
	 * status is offered in the status menu at all. Two handles on one value - the list rebuild
	 * notification keeps this one honest (see -refreshFromStateArray). */
	checkBox_musicStatus = [AISettingsFormView switchWithTarget:self action:@selector(changeMusicStatusShown:)];
	[form addRowWithLabel:AILocalizedString(@"Show a music status", "Switch for offering the music status in the status menu")
				  control:checkBox_musicStatus
				   detail:AILocalizedString(@"In the early days of instant messaging it was simply part of it - showing your friends over ICQ, MSN or IRC what you were listening to. Turn the music status on to bring this little tradition of internet history back.",
											"Second line of the music status switch, saying where the feature comes from")];

	textField_format = [self formatTokenField];
	[form addRowWithLabel:AILocalizedString(@"Format", "Title of the Format menu")
		stretchingControl:textField_format];

	/* What that format currently comes to. A row of its own rather than a detail line under the
	 * field: it shares the label column with Format, so the resolved text starts on the same line
	 * as the text it was made from, and a detail line offers no way to change its text afterwards.
	 */
	textField_preview = [self previewField];

	/* The refresh next to it asks Music and Spotify there and then. The broadcast the preview
	 * lives on only arrives when something changes, so after a launch — or with the answer gone
	 * stale — this button is the way to one without waiting for the next track. */
	button_refreshPreview = [AISettingsFormView inlineSymbolButtonWithSymbolName:@"arrow.clockwise"
															   fallbackImageName:NSImageNameRefreshTemplate
																		  target:self
																		  action:@selector(refreshNowPlaying:)];
	[button_refreshPreview setToolTip:AILocalizedString(@"Ask the running music players what is playing", "Tool tip and accessibility label of the refresh button next to the Now Playing preview")];
	[button_refreshPreview setAccessibilityLabel:AILocalizedString(@"Ask the running music players what is playing", "Tool tip and accessibility label of the refresh button next to the Now Playing preview")];

	NSView *previewRow = [AISettingsFormView rowOfViews:[NSArray arrayWithObjects:
														 textField_preview, button_refreshPreview, nil]];
	/* The row is laid out as a stretching control, which resizes this container to the room the
	 * card leaves; inside it the field takes every point of that and the button keeps to the
	 * trailing edge, the way the resolved text lines up with the format above it. */
	[textField_preview setAutoresizingMask:NSViewWidthSizable];
	[button_refreshPreview setAutoresizingMask:NSViewMinXMargin];

	[form addRowWithLabel:AILocalizedString(@"Preview", "Title of the row showing what the Now Playing format currently resolves to")
		stretchingControl:previewRow];

	popUp_insertToken = [self insertTokenPopUpButton];
	[form addTrailingAccessoryView:popUp_insertToken];

	return form;
}

/*!
 * @brief Configure the preference view
 */
- (void)viewDidLoad
{
	/* Register as an observer of state array changes so we can refresh our list
	 * in response to changes. */
	[[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(stateArrayChanged:)
									   name:AIStatusStateArrayChangedNotification
									 object:nil];
	//Straight away, not coalesced: the three menus have to be filled before the form is first laid out
	[self refreshFromStateArray];

	[self configureOtherControls];

	NSString *displayFormat = [adium.preferenceController preferenceForKey:KEY_ITUNES_TRACK_FORMAT
																	 group:PREF_GROUP_STATUS_PREFERENCES];

	/* The plugin falls back to the same default for an empty preference, so show it rather than an
	 * empty field — but do not write it: an untouched setting stays untouched, and the fallback is
	 * allowed to change with the locale.
	 */
	if (![displayFormat length]) {
		displayFormat = [NSString stringWithFormat:@"%@ - %@", TRIGGER_TRACK, TRIGGER_ARTIST];
	}
	[textField_format setObjectValue:[self tokensForFormatString:displayFormat]];

	/* The track only changes every few minutes, so without this the preview would stand still
	 * while the music moved on. Posted by -[ESiTunesPlugin fireUpdateiTunesInfo], which already
	 * coalesces three seconds' worth of changes, so there is nothing left for us to coalesce.
	 * -tearDown takes the pane off it with everything else.
	 */
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(trackChanged:)
												 name:Adium_iTunesTrackChangedNotification
											   object:nil];

	[self configureMusicStatusControls];

	/* Deliberately no player query here; see -askPlayersOnFirstInteraction for where it went and
	 * why merely putting this view on screen is not enough to earn it.
	 */
}

/*!
 * @brief Mirror the music status onto its card
 *
 * The switch shows whether the music status is offered in the status menu, and the rows under it
 * only mean anything while it is - a format for a status nobody can pick is dead text, so they dim
 * with it. Runs from -viewDidLoad, after the switch itself was flipped, and from
 * -refreshFromStateArray, which is how a flip of the same status's switch in the list above
 * reaches this card.
 */
- (void)configureMusicStatusControls
{
	AIStatus	*musicStatus = [adium.statusController statusStateWithUniqueStatusID:
								[NSNumber numberWithInteger:ITUNES_STATUS_ID]];
	BOOL		 shown = (musicStatus && [musicStatus showsInStatusMenu]);

	//No status registered means no plugin to talk to; a switch that cannot do anything is off
	[checkBox_musicStatus setEnabled:(musicStatus != nil)];
	[checkBox_musicStatus setState:(shown ? NSControlStateValueOn : NSControlStateValueOff)];

	[textField_format setEnabled:shown];
	[popUp_insertToken setEnabled:shown];
	[textField_preview setEnabled:shown];
	[button_refreshPreview setEnabled:shown];

	//The preview recolours itself by its field's enabled state; see the note in -updatePreview
	[self updatePreview];
}

/*!
 * @brief The card's switch was flipped
 *
 * The same setting the status's own row in the list above writes: whether it is offered in the
 * status menu. Writing it rebuilds every status menu in Adium and posts the state array
 * notification, which brings the list in line; the dimming here does not wait for that round trip.
 */
- (void)changeMusicStatusShown:(id)sender
{
	AIStatus	*musicStatus = [adium.statusController statusStateWithUniqueStatusID:
								[NSNumber numberWithInteger:ITUNES_STATUS_ID]];

	[musicStatus setShowsInStatusMenu:([checkBox_musicStatus state] == NSControlStateValueOn)];

	[self configureMusicStatusControls];
}

/*!
 * @brief Preference view is closing
 *
 * Nothing is saved here any more: every control writes the moment it is touched, which it has to,
 * since the preferences window only closes a pane when the window itself closes.
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
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	/* The two lines above already made the pane deaf and took the format timer with them, and the
	 * order matters: -postFormatChanged reaches -[ESiTunesPlugin currentTrackFormatDidChange:],
	 * which comes back out of -fireUpdateiTunesInfo as Adium_iTunesTrackChangedNotification on
	 * this very stack. A pane still listening at that moment would run a full preview pass in the
	 * middle of its own teardown. Deaf first, then whatever was typed last still has to reach the
	 * plugin. */
	if (formatChangePending) [self postFormatChanged];

	/* The list lives in the form's card, and the form and this pane are released on different paths
	 * (-tearDown here, -[AIModularPane closeView] there). Cut it loose from us here, so a view which
	 * outlives us for a moment can never ask a freed pane anything - its delegate is a non-retaining
	 * reference to us. */
	[listView_states tearDown];

	//Same for everything else we handed a target or a delegate to
	for (NSControl *control in [NSArray arrayWithObjects:
								button_addOrRemoveState, button_refreshPreview,
								checkBox_idle, checkBox_awayReminder, checkBox_musicStatus,
								stepper_idleMinutes, stepper_awayReminderMinutes,
								nil]) {
		[control setTarget:nil];
	}
	for (NSTextField *field in [NSArray arrayWithObjects:
								textField_idleMinutes, textField_awayReminderMinutes,
								textField_format,
								nil]) {
		[field setTarget:nil];
		[field setDelegate:nil];
	}
	/* Every item of these menus carries our address as its target (AIStatusMenu sets it per item,
	 * -insertTokenPopUpButton likewise), so the menus go rather than outlive us on a button the
	 * form has not released yet. */
	for (NSPopUpButton *popUp in [NSArray arrayWithObjects:
								  popUp_autoAwayStatusState, popUp_fastUserSwitchingStatusState,
								  popUp_screenSaverStatusState, popUp_insertToken, nil]) {
		[popUp setMenu:[[[NSMenu alloc] initWithTitle:@""] autorelease]];
	}

	/* All of these references are non-retaining and the views behind them go away with the form,
	 * which may be released after us; forget them so a second -tearDown cannot message freed
	 * memory. */
	listView_states = nil;
	button_addOrRemoveState = nil;
	checkBox_idle = nil;
	checkBox_awayReminder = nil;
	textField_idleMinutes = nil;
	textField_awayReminderMinutes = nil;
	stepper_idleMinutes = nil;
	stepper_awayReminderMinutes = nil;
	label_idleMinutes = nil;
	label_awayReminderMinutes = nil;
	popUp_autoAwayStatusState = nil;
	popUp_fastUserSwitchingStatusState = nil;
	popUp_screenSaverStatusState = nil;
	checkBox_musicStatus = nil;
	textField_format = nil;
	textField_preview = nil;
	button_refreshPreview = nil;
	popUp_insertToken = nil;

	//A refresh may have been due; -cancelPreviousPerformRequestsWithTarget: above took it away
	refreshScheduled = NO;

	/* The pane object outlives its view, so the next visit gets its own chance to ask. Not a way
	 * around the once-per-visit limit: the plugin's own guards decide whether anything is actually
	 * sent, and they hold for the whole launch. */
	hasAskedPlayers = NO;

	[nibView release]; nibView = nil;
}

/*!
 * @brief Deallocate
 */
- (void)dealloc
{
	[self tearDown];
	[super dealloc];
}

#pragma mark Status list and controls
/*!
 * @brief The statuses the list shows: the ones the user saved, and only those
 *
 * The states Adium brings with it are deliberately left out. They were briefly in here, so that the
 * switch in each row could take one out of the status menu - they cannot be deleted, after all. That
 * was a bad trade: it made "Available" switchable, and a hidden "Available" leaves no way back from
 * away through the menu. The built-in states stay out of reach, and the switch means what it says
 * for a status of one's own - keep it, but do not show it for now.
 *
 * Temporary states are left out as well: they belong to the accounts currently wearing them, are
 * never saved, and have no business in a list which manages saved statuses.
 */
- (NSArray *)statusItemsForList
{
	NSArray			*originalStateArray = [[adium.statusController rootStateGroup] containedStatusItems];
	NSMutableArray	*sortedItems = [[originalStateArray mutableCopy] autorelease];

	//The original array's indexes are what keeps statuses of one kind in the order they were saved in
	[AIStatusGroup sortArrayOfStatusItems:sortedItems context:originalStateArray];

	return sortedItems;
}

/*!
 * @brief Turn the nib's +/- pair into the single "+" System Settings puts under a list
 *
 * One segment showing a "+", in the small rounded group, sized to its content plus a little room.
 * The minus segment is gone: a status is deleted through the ⊖ in its own row, and "Edit" with
 * it - a double click on a row opens the status editor.
 *
 * The accessory bar never resizes what it is given, so the button has to be finished before it is
 * handed over. A symbol has no title to fall back on, hence both a tool tip and an accessibility
 * label.
 */
- (void)configureAddStatusControl
{
	NSImage		*addImage = [NSImage imageWithSystemSymbolName:@"plus"
									  accessibilityDescription:AILocalizedString(@"Add Status", "Button which creates a new saved status")];

	if (!addImage) addImage = [NSImage imageNamed:NSImageNameAddTemplate];

	[button_addOrRemoveState setSegmentCount:1];
	[button_addOrRemoveState setSegmentStyle:NSSegmentStyleRounded];
	[button_addOrRemoveState setTrackingMode:NSSegmentSwitchTrackingMomentary];
	[button_addOrRemoveState setImage:addImage forSegment:0];
	[button_addOrRemoveState setImageScaling:NSImageScaleProportionallyDown forSegment:0];
	[button_addOrRemoveState setLabel:@"" forSegment:0];
	//No menu drops out of this one: it opens the status editor straight away
	[button_addOrRemoveState setShowsMenuIndicator:NO forSegment:0];

	//Zero asks the control for the width its content needs; that is tighter than System Settings draws it
	[button_addOrRemoveState setWidth:0.0f forSegment:0];
	[button_addOrRemoveState sizeToFit];

	NSSize	fittedSize = [button_addOrRemoveState frame].size;
	NSSize	fittingSize = [button_addOrRemoveState fittingSize];
	CGFloat	contentWidth = MAX(fittedSize.width, fittingSize.width);

	[button_addOrRemoveState setWidth:(contentWidth + ADD_BUTTON_PADDING) forSegment:0];
	[button_addOrRemoveState sizeToFit];
	[button_addOrRemoveState setFrameSize:NSMakeSize(MAX(NSWidth([button_addOrRemoveState frame]),
														contentWidth + ADD_BUTTON_PADDING),
													 MAX(fittedSize.height, fittingSize.height))];

	[button_addOrRemoveState setToolTip:AILocalizedString(@"Add Status", "Button which creates a new saved status")];
	[button_addOrRemoveState setAccessibilityLabel:AILocalizedString(@"Add Status", "Button which creates a new saved status")];
}

/*!
 * @brief One minute setting: a field, its stepper and the unit behind them
 *
 * Both halves send their action here rather than to each other, which is the whole of the old
 * pane's trouble: the nib had the steppers hand their value to their text field, so a click on one
 * never reached this class and the value was written by -saveTimeValues at window close, if at
 * all. Now the stepper writes on every click and the field on every keystroke.
 *
 * The unit label is part of the bundle rather than part of the row label, so the row reads
 * "Report idle after [10] minutes". It is also the trailing-most control of the row, which is the
 * one the form watches to dim the row's label - see -configureControlDimming.
 */
- (NSView *)minutesRowWithField:(NSTextField *)field
						stepper:(NSStepper *)stepper
					  unitLabel:(NSTextField *)unitLabel
{
	NSNumberFormatter	*formatter = [[[NSNumberFormatter alloc] init] autorelease];

	/* Plain digits, and deliberately no minimum and no maximum. A formatter which rejects what
	 * stands in the field refuses to let editing end, and with no
	 * -control:didFailToFormatString:errorDescription: that is an alert and a focus which cannot
	 * leave the field - for a blank field, for a zero, and for every setting outside the stepper's
	 * range. Anything the user may pass through on the way to a number is a matter for
	 * -commitMinutesFromField:… (which writes nothing below a minute) and for
	 * -controlTextDidEndEditing: (which puts the setting back on screen), not for the formatter. */
	[formatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
	[formatter setPositiveFormat:@"0"];

	[field setFormatter:formatter];
	[field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[field setAlignment:NSTextAlignmentRight];
	[field setTarget:self];
	[field setAction:@selector(changedTimeValue:)];
	[[field cell] setSendsActionOnEndEditing:YES];
	[field setDelegate:(id<NSTextFieldDelegate>)self];
	[field sizeToFit];
	[field setFrameSize:NSMakeSize(MINUTES_FIELD_WIDTH, ceil(NSHeight([field frame])))];

	/* Zero minutes is not a setting, and with the nib's valueWraps a single click on "down" at
	 * zero used to land on 999 - which, now that every click writes, would be 999 minutes in the
	 * preferences before the user could let go of the mouse. */
	[stepper setMinValue:MINUTES_MINIMUM];
	[stepper setMaxValue:MINUTES_MAXIMUM];
	[stepper setIncrement:1.0];
	[stepper setValueWraps:NO];
	[stepper setAutorepeat:YES];
	[stepper setContinuous:YES];
	[stepper setTarget:self];
	[stepper setAction:@selector(changedTimeValue:)];
	[stepper sizeToFit];

	[field setNextKeyView:stepper];

	[unitLabel setStringValue:AILocalizedString(@"minutes",nil)];
	[unitLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[unitLabel sizeToFit];

	//Field and stepper are one control and sit closer together than the standard gap
	NSView	*valueBundle = [AISettingsFormView rowOfViews:[NSArray arrayWithObjects:field, stepper, nil]
												  spacing:2.0];

	return [AISettingsFormView rowOfViews:[NSArray arrayWithObjects:valueBundle, unitLabel, nil]];
}

/*!
 * @brief Invoked when the state array changes
 *
 * A status was added, edited, deleted or switched out of the status menu, anywhere in Adium.
 *
 * Coalesced onto the next turn of the run loop rather than answered on the spot, the way
 * AIXtrasPreferences answers its own switches. The notification reaches us from inside a row's
 * NSSwitch action - -toggleStatusShown: writes the setting, which rebuilds every status menu in
 * Adium and lands back here - and the answer to it throws every row away and builds it again. Doing
 * that while AppKit is still tracking the switch would pull the control out from under it.
 */
- (void)stateArrayChanged:(NSNotification *)notification
{
	//A refresh already due is left where it is, so a run of changes cannot keep deferring it
	if (refreshScheduled) return;

	refreshScheduled = YES;
	[self performSelector:@selector(refreshFromStateArray) withObject:nil afterDelay:0.0];
}

/*!
 * @brief Build the three status menus and the list from the status controller again
 */
- (void)refreshFromStateArray
{
	refreshScheduled = NO;

	/* Menus first, list second. A pop up row measures its button at every layout pass, and the list
	 * reporting a new height is what triggers one - so filling the menus afterwards left the three
	 * buttons measured empty, which is a width of nothing and a row that looks like it has no
	 * control at all. It only ever corrected itself one notification late, when the next layout
	 * found the menus the previous round had built. */
	[self configureAutoAwayStatusStatePopUp];

	//The card is as tall as the list; a status more or less changes it, and the list says so
	[listView_states setStatusItems:[self statusItemsForList]];

	//The music status card mirrors one of those states; flipping it in the list lands here
	[self configureMusicStatusControls];
}

//State Editing --------------------------------------------------------------------------------------------------------
#pragma mark State Editing
/*!
 * @brief Edit a status
 *
 * Opens an edit state sheet. If the sheet is closed with success our -customStatusState:changedTo:
 * method is invoked and saves the changes.
 *
 * Anything but a status the user made is left alone: an edit is written through
 * [[originalState containingStatusGroup] replaceExistingStatusState:...], and a built-in status has
 * no containing group - the change would simply vanish.
 */
- (void)editStatus:(AIStatusItem *)statusItem
{
	if (![statusItem isKindOfClass:[AIStatus class]]) return;
	if ([statusItem mutabilityType] != AIEditableStatusState) return;

	[AIEditStateWindowController editCustomState:(AIStatus *)statusItem
										 forType:statusItem.statusType
									  andAccount:nil
								  withSaveOption:NO
										onWindow:[[self view] window]
								 notifyingTarget:self];
}

/*!
* @brief State edited callback
 *
 * Invoked when the user successfully edits a state.  This method adds the new or updated state to Adium's state array.
 */
- (void)customStatusState:(AIStatus *)originalState changedTo:(AIStatus *)newState forAccount:(AIAccount *)account
{
	if (originalState) {
		/* As far the user was concerned, this was an edit.  The unique status ID should remain the same so that anything
		 * depending upon this status will update to using it.  Furthermore, since this may be a copy of originalState
		 * rather than the exact same object, we should update all accounts which are using this state to use the new copy
		 */
		[newState setUniqueStatusID:[originalState uniqueStatusID]];
		
		for (AIAccount *loopAccount in adium.accountController.accounts) {
			if (loopAccount.statusState == originalState) {
				[loopAccount setStatusStateAndRemainOffline:newState];
				
				[loopAccount notifyOfChangedPropertiesSilently:YES];
			}
		}

		[[originalState containingStatusGroup] replaceExistingStatusState:originalState withStatusState:newState];

		[originalState setUniqueStatusID:nil];

	} else {
		[adium.statusController addStatusState:newState];
	}
	
	/* Nothing to select and nothing to scroll to: the list has no selection and never scrolls - it is
	 * as tall as its rows, and the preferences column scrolls instead. */
}

/*!
 * @brief Ask before deleting a status, then delete it
 *
 * The question is the point: a saved status is gone for good, and the three automatic status
 * settings know their status by nothing but its unique ID - deleting the wrong one switches one of
 * them off without a word.
 */
- (void)deleteStatus:(AIStatusItem *)statusItem
{
	NSAlert		*warning = [[[NSAlert alloc] init] autorelease];
	NSWindow	*sheetParent = [[self view] window];

	[warning setMessageText:AILocalizedString(@"Delete Status?", "Title of the confirmation before deleting a saved status")];
	[warning setInformativeText:[NSString stringWithFormat:
								 AILocalizedString(@"“%@” will be deleted.",
												   "Confirmation before deleting a saved status. %@ is the title of the status."),
								 ([statusItem title] ?: @"")]];
	[warning addButtonWithTitle:AILocalizedString(@"Delete", nil)];	//NSAlertFirstButtonReturn, the default button
	[warning addButtonWithTitle:AILocalizedString(@"Cancel", nil)];

	/* The block holds the status - and nothing else. It deliberately never touches self, and that has
	 * to stay so: the sheet outlives the click that opened it, and the pane behind it can be torn
	 * down (-tearDown, -dealloc) while it stands, so anything sent to self from in here would reach
	 * a freed view. Only the status is captured, which is what keeps it alive - the list holding it
	 * may well have been rebuilt by the time the sheet is answered. */
	void (^completionHandler)(NSModalResponse) = ^(NSModalResponse returnCode) {
		if (returnCode != NSAlertFirstButtonReturn) return;

		/* Take the status out of the "hidden from the status menu" setting first, while it still
		 * knows its own ID. Not strictly needed - IDs are counted up and never reused - but it keeps
		 * that setting finite. */
		if (![statusItem showsInStatusMenu]) [statusItem setShowsInStatusMenu:YES];

		//This is the write to disk: the root group turns every change of its contents into a save
		[[statusItem containingStatusGroup] removeStatusItem:statusItem];
	};

	if (sheetParent) {
		[warning beginSheetModalForWindow:sheetParent completionHandler:completionHandler];
	} else {
		completionHandler([warning runModal]);
	}
}

/*!
* @brief Add a new state
 *
 * Creates a new state.  This is done by invoking an edit window without passing it a base state.  When the edit window
 * returns successfully, it will invoke our customStatusState:changedTo: which adds the new state to Adium's state
 * array.
 */
- (void)newState
{
	[AIEditStateWindowController editCustomState:nil
										 forType:AIAwayStatusType
									  andAccount:nil
								  withSaveOption:NO
										onWindow:[[self view] window]
								 notifyingTarget:self];
}

/*!
 * @brief The "+" under the list was clicked
 *
 * One segment, one meaning. The name is the nib's and stays because the connection is.
 */
- (IBAction)addOrRemoveState:(id)sender
{
	[self newState];
}

#pragma mark Status list delegate

- (void)statusListView:(AIStatusListView *)listView setShownInStatusMenu:(BOOL)shown forStatus:(AIStatusItem *)statusItem
{
	//Writes there and then, and rebuilds every status menu in Adium
	[statusItem setShowsInStatusMenu:shown];
}

- (void)statusListView:(AIStatusListView *)listView deleteStatus:(AIStatusItem *)statusItem
{
	[self deleteStatus:statusItem];
}

- (void)statusListView:(AIStatusListView *)listView editStatus:(AIStatusItem *)statusItem
{
	[self editStatus:statusItem];
}

- (void)statusListViewDidChangeHeight:(AIStatusListView *)listView
{
	//The list is the edge to edge row of a card, so its height is the card's height
	[[self settingsForm] noteContentSizeChanged];
}

#pragma mark Other status-related controls

/*!
 * @brief Configure initial values for idle, auto-away, etc., preferences.
 */

- (void)configureOtherControls
{
	NSDictionary	*prefDict = [adium.preferenceController preferencesForGroup:PREF_GROUP_STATUS_PREFERENCES];

	[checkBox_idle setState:([[prefDict objectForKey:KEY_STATUS_REPORT_IDLE] boolValue] ?
							 NSControlStateValueOn : NSControlStateValueOff)];
	[self showMinutes:([[prefDict objectForKey:KEY_STATUS_REPORT_IDLE_INTERVAL] doubleValue] / 60.0)
			  inField:textField_idleMinutes
			  stepper:stepper_idleMinutes];

	[checkBox_awayReminder setState:([[prefDict objectForKey:KEY_STATUS_AWAY_REMINDER] boolValue] ?
									 NSControlStateValueOn : NSControlStateValueOff)];
	[self showMinutes:([[prefDict objectForKey:KEY_STATUS_AWAY_REMINDER_INTERVAL] doubleValue] / 60.0)
			  inField:textField_awayReminderMinutes
			  stepper:stepper_awayReminderMinutes];

	[self configureControlDimming];
}

/*!
 * @brief Show the stored values again, unless the user is in the middle of typing one
 *
 * Called when the pane is handed out for display a second time. A field which is being edited right
 * now belongs to the user, not to us: -view is also asked for the pane's window when a sheet is
 * opened from one of the list's buttons, and taking a half typed number off the screen at that
 * moment would be worse than the stale number this exists to clear away.
 */
- (void)refreshDisplayedValues
{
	for (NSTextField *field in [NSArray arrayWithObjects:
								textField_idleMinutes, textField_awayReminderMinutes, nil]) {
		if ([field currentEditor]) return;
	}

	[self configureOtherControls];
}

/*!
 * @brief Put a stored interval on screen, in both halves of its row
 *
 * Rounded to whole minutes, because that is what the field and the stepper can express, but
 * otherwise shown exactly as it is stored: the number in the field is the setting, always. A value
 * from before this pane had a stepper may well lie outside the stepper's range - an interval of a
 * whole day, say - and clamping the field to that range would put a number on screen which is not
 * the setting and which one click of the stepper would then make true. The stepper alone takes what
 * it can of such a value.
 */
- (void)showMinutes:(double)minutes inField:(NSTextField *)field stepper:(NSStepper *)stepper
{
	NSInteger	rounded = (NSInteger)round(minutes);

	[field setIntegerValue:rounded];
	//Out of range in either direction, the stepper stops at its own end; it never writes on its own
	[stepper setIntegerValue:rounded];
}

/*!
 * @brief Configure the pop up of states for autoAway.
 *
 * Called by -refreshFromStateArray, for the first set up and for every later change alike.
 */
- (void)configureAutoAwayStatusStatePopUp
{
	NSMenu		*statusStatesMenu;
	NSNumber	*targetUniqueStatusIDNumber;

	statusStatesMenu = [AIStatusMenu staticStatusStatesMenuNotifyingTarget:self selector:@selector(changedAutoAwayStatus:)];
	[self prependDoNotChangeItemToMenu:statusStatesMenu action:@selector(changedAutoAwayStatus:)];
	[popUp_autoAwayStatusState setMenu:statusStatesMenu];

	statusStatesMenu = [AIStatusMenu staticStatusStatesMenuNotifyingTarget:self selector:@selector(changedFastUserSwitchingStatus:)];
	[self prependDoNotChangeItemToMenu:statusStatesMenu action:@selector(changedFastUserSwitchingStatus:)];
	[popUp_fastUserSwitchingStatusState setMenu:[[statusStatesMenu copy] autorelease]];

	statusStatesMenu = [AIStatusMenu staticStatusStatesMenuNotifyingTarget:self selector:@selector(changedScreenSaverStatus:)];
	[self prependDoNotChangeItemToMenu:statusStatesMenu action:@selector(changedScreenSaverStatus:)];
	[popUp_screenSaverStatusState setMenu:[[statusStatesMenu copy] autorelease]];

	//Now select the proper state, or deselect all items if there is no chosen state or the chosen state doesn't exist
	targetUniqueStatusIDNumber = [adium.preferenceController preferenceForKey:KEY_STATUS_AUTO_AWAY_STATUS_STATE_ID
																		  group:PREF_GROUP_STATUS_PREFERENCES];
	[self _selectStatusWithUniqueID:targetUniqueStatusIDNumber inPopUpButton:popUp_autoAwayStatusState];
	
	targetUniqueStatusIDNumber = [adium.preferenceController preferenceForKey:KEY_STATUS_FUS_STATUS_STATE_ID
																		  group:PREF_GROUP_STATUS_PREFERENCES];
	[self _selectStatusWithUniqueID:targetUniqueStatusIDNumber inPopUpButton:popUp_fastUserSwitchingStatusState];	
	
	targetUniqueStatusIDNumber = [adium.preferenceController preferenceForKey:KEY_STATUS_SS_STATUS_STATE_ID
																		  group:PREF_GROUP_STATUS_PREFERENCES];
	[self _selectStatusWithUniqueID:targetUniqueStatusIDNumber inPopUpButton:popUp_screenSaverStatusState];

	/* A pop up row is measured afresh at every layout, so a menu which just gained or lost a
	 * status only needs to be told that a layout is due. */
	[[self settingsForm] noteContentSizeChanged];
}

/*!
 * @brief Put "Do not change" plus a separator at the top of a status menu
 *
 * This entry <em>is</em> the off switch of an automatic status change; the three checkboxes which
 * used to do that job are gone, and a checkbox whose meaning lives in a menu below it said the same
 * thing twice. Its represented object is deliberately nil, so -changed…Status: recognises it by
 * finding no status behind it and writes STATUS_STATE_ID_NONE.
 */
- (void)prependDoNotChangeItemToMenu:(NSMenu *)menu action:(SEL)action
{
	NSMenuItem	*doNotChange = [[[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Do not change","First entry of the menus choosing a status Adium sets on its own; it means: leave the status alone")
														  action:action
												   keyEquivalent:@""] autorelease];

	[doNotChange setTarget:self];

	[menu insertItem:[NSMenuItem separatorItem] atIndex:0];
	[menu insertItem:doNotChange atIndex:0];
}

/*!
 * @brief Select a status with uniqueID in inPopUpButton
 *
 * An ID no status answers to — STATUS_STATE_ID_NONE, or one whose status has since been deleted —
 * selects the first entry, "Do not change". It has to select something now: the menus are the only
 * place left where an automatic status change is switched off, and a button showing nothing at all
 * would not say which of its entries is in force.
 */
- (void)_selectStatusWithUniqueID:(NSNumber *)uniqueID inPopUpButton:(NSPopUpButton *)inPopUpButton
{
	NSMenuItem	*menuItem = nil;
	
	if (uniqueID) {
		NSInteger			 targetUniqueStatusID= [uniqueID integerValue];

		/* One level, because there is only one: +staticStatusStatesMenuNotifyingTarget: built
		 * submenus while groups of statuses existed, and every entry stands on its own now. */
		for (NSMenuItem *candidate in [[inPopUpButton menu] itemArray]) {
			AIStatusItem	*statusState;

			statusState = [[candidate representedObject] objectForKey:@"AIStatus"];

			/* Found the right status by matching its status ID to our preferred one. Only an item
			 * with a real status behind it may match: separators and our own "Do not change" carry
			 * no represented object, and [nil preexistingUniqueStatusID] is 0 - which would answer
			 * to a stored ID of 0 and select a separator. */
			if (statusState && ([statusState preexistingUniqueStatusID] == targetUniqueStatusID)) {
				menuItem = candidate;
				break;
			}
		}
	}

	if (menuItem) {
		[inPopUpButton selectItem:menuItem];
	} else {
		//Nothing to select: fall back on "Do not change", which we put at the top ourselves
		if ([[inPopUpButton menu] numberOfItems]) [inPopUpButton selectItemAtIndex:0];
	}
}

/*!
 * @brief Configure control dimming for idle, auto-away, etc., preferences.
 *
 * Every dependent control still follows the switch above it. The two unit labels are here because a
 * row of the form has a label of its own which follows the enabled state of the trailing-most
 * control of the row — that is the unit label, so without these lines the labels on the left would
 * never grey out with their row.
 *
 * Two of the three status menus are never dimmed: the ones for the fast user switch and for the
 * screen saver carry their own off switch in their first entry, and nothing above them could take
 * them away. The third is not like them. It hangs on the switch for being reported as idle, because
 * AIAutomaticStatus only ever sets the idle bit inside "reporting is on and the duration has run
 * out" — with the switch off, a status chosen here would never be set. Left black and usable it
 * would be exactly the thing this pane was rebuilt to be rid of, only the other way round: not a
 * setting which works while being invisible, but one which is visible while doing nothing.
 */
- (void)configureControlDimming
{
	BOOL	idleControlsEnabled, awayReminderControlsEnabled;

	idleControlsEnabled = ([checkBox_idle state] == NSControlStateValueOn);
	[textField_idleMinutes setEnabled:idleControlsEnabled];
	[stepper_idleMinutes setEnabled:idleControlsEnabled];
	[label_idleMinutes setEnabled:idleControlsEnabled];
	[popUp_autoAwayStatusState setEnabled:idleControlsEnabled];

	awayReminderControlsEnabled = ([checkBox_awayReminder state] == NSControlStateValueOn);
	[textField_awayReminderMinutes setEnabled:awayReminderControlsEnabled];
	[stepper_awayReminderMinutes setEnabled:awayReminderControlsEnabled];
	[label_awayReminderMinutes setEnabled:awayReminderControlsEnabled];
}

/*!
 * @brief Change preference
 *
 * Sent when one of the two switches is clicked. Each of them writes there and then: the
 * preferences window only calls -closeView when it closes — switching to another pane takes the
 * view out with -removeFromSuperview — so there is no later point at which anything could be
 * saved.
 */
- (IBAction)changePreference:(id)sender
{
	/* Read the state through the ivar rather than through sender: -state is declared on NSSwitch
	 * and on NSButton alike, and asking an untyped id for it leaves the compiler to pick one. */
	if (sender == checkBox_idle) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_idle state] == NSControlStateValueOn)]
											 forKey:KEY_STATUS_REPORT_IDLE
											  group:PREF_GROUP_STATUS_PREFERENCES];

	} else if (sender == checkBox_awayReminder) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_awayReminder state] == NSControlStateValueOn)]
											 forKey:KEY_STATUS_AWAY_REMINDER
											  group:PREF_GROUP_STATUS_PREFERENCES];

	}

	[self configureControlDimming];
}

/*!
 * @brief The status ID a menu item stands for, or "do not change" for the first entry
 *
 * The "Do not change" item carries no represented object, and STATUS_STATE_ID_NONE is what has to
 * be written for it — not nil, which would let the default take over again.
 */
- (NSNumber *)statusIDForSelectedMenuItem:(id)sender
{
	AIStatus	*statusState = [[sender representedObject] objectForKey:@"AIStatus"];

	return (statusState ?
			[statusState uniqueStatusID] :
			[NSNumber numberWithInteger:STATUS_STATE_ID_NONE]);
}

- (void)changedAutoAwayStatus:(id)sender
{
	[adium.preferenceController setPreference:[self statusIDForSelectedMenuItem:sender]
										 forKey:KEY_STATUS_AUTO_AWAY_STATUS_STATE_ID
										  group:PREF_GROUP_STATUS_PREFERENCES];
}

- (void)changedFastUserSwitchingStatus:(id)sender
{
	[adium.preferenceController setPreference:[self statusIDForSelectedMenuItem:sender]
										 forKey:KEY_STATUS_FUS_STATUS_STATE_ID
										  group:PREF_GROUP_STATUS_PREFERENCES];
}

- (void)changedScreenSaverStatus:(id)sender
{
	[adium.preferenceController setPreference:[self statusIDForSelectedMenuItem:sender]
										 forKey:KEY_STATUS_SS_STATUS_STATE_ID
										  group:PREF_GROUP_STATUS_PREFERENCES];
}

/*!
 * @brief A minutes field or its stepper changed; write that interval now
 *
 * The one place both time settings are written. Every click of a stepper and every keystroke
 * in a field lands here, and the value goes straight into the preferences: the preferences window
 * only calls -closeView when the window itself closes, so leaving this pane through the sidebar is
 * not a point at which anything could still be saved. The old pane wrote the idle and auto away
 * intervals from -viewWillClose alone, which is exactly why a value set with a stepper used to
 * survive closing the window but not switching to another pane.
 */
- (IBAction)changedTimeValue:(id)sender
{
	if (sender == stepper_idleMinutes || sender == textField_idleMinutes) {
		[self commitMinutesFromField:textField_idleMinutes
							 stepper:stepper_idleMinutes
							  sender:sender
							  forKey:KEY_STATUS_REPORT_IDLE_INTERVAL];

	} else if (sender == stepper_awayReminderMinutes || sender == textField_awayReminderMinutes) {
		[self commitMinutesFromField:textField_awayReminderMinutes
							 stepper:stepper_awayReminderMinutes
							  sender:sender
							  forKey:KEY_STATUS_AWAY_REMINDER_INTERVAL];
	}
}

/*!
 * @brief Keep a field and its stepper in step and store what they now say, in seconds
 *
 * Whichever half the user touched is the one that is believed; the other is brought up to it. A
 * field is read through its field editor while it is being edited, because -stringValue is still
 * the last committed text until then.
 *
 * A blank field, a zero and a half typed number are what the user passes through on the way to a
 * real value, not settings: they leave both the stepper and the preference alone. The stepper
 * cannot produce them at all — it starts at one minute and no longer wraps round.
 *
 * A typed value above the stepper's range is written as typed. The stepper stops at its own end,
 * but the setting is the user's to make: the pane used to take any number of minutes and there is
 * no reason for the range of a stepper to become the range of a preference.
 */
- (void)commitMinutesFromField:(NSTextField *)field
					   stepper:(NSStepper *)stepper
						sender:(id)sender
						forKey:(NSString *)key
{
	NSInteger	minutes;

	if (sender == stepper) {
		minutes = [stepper integerValue];
		[field setIntegerValue:minutes];

	} else {
		NSText		*editor = [field currentEditor];

		minutes = (editor ? [[editor string] integerValue] : [field integerValue]);

		if (minutes < MINUTES_MINIMUM) return;

		[stepper setIntegerValue:minutes];
	}

	[adium.preferenceController setPreference:[NSNumber numberWithDouble:(minutes * 60.0)]
									   forKey:key
										group:PREF_GROUP_STATUS_PREFERENCES];
}

/*!
 * @brief Control text did end editing
 *
 * The value itself is already in the preferences twice over by now — once per keystroke through
 * -controlTextDidChange:, and once more through the field's own action, which it sends on Return,
 * on Tab and when the focus moves away. What is left to do here is the other half: if the field
 * was left holding something which was never written — blank, or below a minute — put the stored
 * setting back on screen, so that the number standing there is always the setting.
 *
 * This only covers the ways out which end editing. Leaving the pane through the sidebar is not one
 * of them; -view puts the values back when the pane is shown again.
 */
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	NSTextField		*field = [notification object];

	if (field == textField_format) {
		/* Editing the format ended: remember where the caret was. Clicking the pull down may take
		 * the focus off the field, and the token still has to be inserted where the user left off,
		 * not at the end and not over the whole text — which is what a field freshly made first
		 * responder would offer. */
		NSText *editor = [[notification userInfo] objectForKey:@"NSFieldEditor"];

		if (editor) {
			savedSelectedRange = [editor selectedRange];
			hasSavedSelectedRange = YES;
		}
		return;
	}

	if ([field integerValue] < MINUTES_MINIMUM) [self configureOtherControls];
}

/*!
 * @brief The caret went into the format field
 *
 * The first deliberate act on the Now Playing card, and the moment the preview stops being
 * decoration: whoever is editing the format wants to see what it comes to. The minute fields
 * arrive here too and need nothing done.
 */
- (void)controlTextDidBeginEditing:(NSNotification *)notification
{
	if ([notification object] == textField_format) [self askPlayersOnFirstInteraction];
}

/*!
 * @brief Something which is not a number was left in a field
 *
 * Saying yes here means: end the editing anyway. The alternative is AppKit's own answer, which is
 * to put up an alert and keep the focus in the field until a number is typed — and the field a user
 * has just emptied to type a new value into holds exactly such a string. Nothing is accepted by
 * saying yes: the field keeps its old value, -controlTextDidEndEditing: then puts the setting back
 * on screen, and the preference was never touched.
 */
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error
{
	return YES;
}

/*!
 * @brief Control text did change
 *
 * Every keystroke is written, not only the committed value. Taking a preference pane off screen
 * does not end editing — the preferences window simply removes the view — so a number which had
 * only reached the field editor would otherwise be lost on the way to another pane. Half typed
 * numbers cost nothing here: -commitMinutesFromField:… drops anything below a minute, and the
 * user is on their way to a real value in the same second — and what such a field is left showing
 * is put right the next time the pane is shown (see -view).
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] == textField_format) {
		/* Storing at every keystroke, for the same reason as the minute fields below: Adium never
		 * ends the editing session itself, it takes the pane out of the window and leaves it to
		 * AppKit whether an action still follows. */
		[self saveFormat];
		[self setPreviewNeedsUpdate];
		return;
	}

	[self changedTimeValue:[notification object]];
}

#pragma mark The Now Playing format

/*!
 * @brief The %_ triggers offered as building blocks, in the Insert menu's order.
 *
 * The plugin knows more triggers than these — %_iTMS, %_music, %_iTunes — but those are composites
 * with rules of their own, not fields of the current track. A format holding one of them still
 * survives this pane: anything not in this list rides along as plain text.
 */
- (NSArray *)tokenTriggers
{
	return [NSArray arrayWithObjects:
			TRIGGER_TRACK, TRIGGER_ARTIST, TRIGGER_ALBUM,
			TRIGGER_COMPOSER, TRIGGER_GENRE, TRIGGER_YEAR, TRIGGER_STATUS,
			nil];
}

/*!
 * @brief The name a trigger's pill and its Insert item carry, or nil for anything else.
 *
 * One place for both, so the word on the pill is always the word that put it there.
 */
- (NSString *)displayNameForTrigger:(NSString *)trigger
{
	if ([trigger isEqualToString:TRIGGER_TRACK])	return AILocalizedString(@"Title", nil);
	if ([trigger isEqualToString:TRIGGER_ARTIST])	return AILocalizedString(@"Artist", nil);
	if ([trigger isEqualToString:TRIGGER_ALBUM])	return AILocalizedString(@"Album", nil);
	if ([trigger isEqualToString:TRIGGER_COMPOSER])	return AILocalizedString(@"Composer", nil);
	if ([trigger isEqualToString:TRIGGER_GENRE])	return AILocalizedString(@"Genre", nil);
	if ([trigger isEqualToString:TRIGGER_YEAR])		return AILocalizedString(@"Year", nil);
	if ([trigger isEqualToString:TRIGGER_STATUS])	return AILocalizedString(@"Player State", nil);

	return nil;
}

/*!
 * @brief Split a stored format into the token field's objects.
 *
 * The triggers become tokens, every run of text between them becomes one object of plain text, and
 * nothing else happens: joining the result with nothing in between is the stored string again, to
 * the character. That round trip has to be exact, because whatever a user once typed into the old
 * plain field — including triggers this pane does not offer — comes through here on its way to the
 * screen and back into the preference.
 *
 * Always the leftmost match, and of two matches in the same place the longer one; no offered
 * trigger is a prefix of another today, but this is not the place to depend on it.
 */
- (NSArray *)tokensForFormatString:(NSString *)string
{
	NSMutableArray	*tokens = [NSMutableArray array];
	NSArray			*triggers = [self tokenTriggers];
	NSUInteger		 length = [string length];
	NSUInteger		 position = 0;

	while (position < length) {
		NSRange		bestRange = NSMakeRange(NSNotFound, 0);

		for (NSString *trigger in triggers) {
			NSRange	candidate = [string rangeOfString:trigger
											  options:NSLiteralSearch
												range:NSMakeRange(position, length - position)];

			if (candidate.location == NSNotFound) continue;
			if (bestRange.location == NSNotFound ||
				candidate.location < bestRange.location ||
				(candidate.location == bestRange.location && candidate.length > bestRange.length)) {
				bestRange = candidate;
			}
		}

		if (bestRange.location == NSNotFound) {
			[tokens addObject:[string substringFromIndex:position]];
			break;
		}

		if (bestRange.location > position) {
			[tokens addObject:[string substringWithRange:NSMakeRange(position, bestRange.location - position)]];
		}
		[tokens addObject:[string substringWithRange:bestRange]];
		position = NSMaxRange(bestRange);
	}

	return tokens;
}

/*!
 * @brief The field the format is edited in.
 *
 * A token field, the way the Address Book pane edits its name format: the %_ triggers show as
 * pills named after what they stand for, and everything between them stays ordinary text. The
 * tokenizing character set is empty because the format is free text — nothing may split on comma
 * or space; triggers become pills through their %_ shape alone
 * (-tokenField:shouldAddObjects:atIndex:).
 */
- (NSTokenField *)formatTokenField
{
	NSTokenField *field = [[[NSTokenField alloc] initWithFrame:NSZeroRect] autorelease];

	[field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[field setDelegate:self];
	[field setTokenizingCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@""]];
	[field setTarget:self];
	[field setAction:@selector(changeFormat:)];
	/* Most changes are stored per keystroke through -controlTextDidChange:; the action on the end
	 * of editing closes what that cannot see, such as autocompletion committing text. */
	[[field cell] setSendsActionOnEndEditing:YES];

	//The row decides the width; only the height comes from the field itself
	[field sizeToFit];
	[field setFrameSize:NSMakeSize(100.0, ceil(NSHeight([field frame])))];

	return field;
}

/*!
 * @brief The "Insert" menu of tokens, sitting under the format card.
 *
 * A pull down rather than a pop up: the button is a verb, not a choice that stays selected, so its
 * title never changes. Its first item is that title and is never chosen. Each token carries its
 * own action, so the button itself needs none.
 */
- (NSPopUpButton *)insertTokenPopUpButton
{
	NSPopUpButton	*popUp = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES] autorelease];

	[popUp addItemWithTitle:AILocalizedString(@"Insert", nil)];

	for (NSString *trigger in [self tokenTriggers]) {
		NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:[self displayNameForTrigger:trigger]
													  action:@selector(insertToken:)
											   keyEquivalent:@""] autorelease];

		[item setTarget:self];
		[item setRepresentedObject:trigger];
		[[popUp menu] addItem:item];
	}

	[popUp sizeToFit];

	return popUp;
}

#pragma mark Token field delegate

/*!
 * @brief Whatever is about to become tokens is re-split along the triggers
 *
 * This is what turns a typed or pasted %_track into a pill: with no tokenizing characters the
 * field only tokenizes when editing settles, and what it then proposes is whole stretches of
 * text. Splitting the joined proposal rather than each piece also mends a trigger which arrives
 * in halves.
 */
- (NSArray *)tokenField:(NSTokenField *)tokenField shouldAddObjects:(NSArray *)tokens atIndex:(NSUInteger)index
{
	return [self tokensForFormatString:[tokens componentsJoinedByString:@""]];
}

//Only the triggers are pills; the text between them looks like the text it is
- (NSTokenStyle)tokenField:(NSTokenField *)tokenField styleForRepresentedObject:(id)representedObject
{
	return ([[self tokenTriggers] containsObject:representedObject] ?
			NSRoundedTokenStyle : NSPlainTextTokenStyle);
}

//nil for free text lets the field show the string itself
- (NSString *)tokenField:(NSTokenField *)tokenField displayStringForRepresentedObject:(id)representedObject
{
	return ([representedObject isKindOfClass:[NSString class]] ?
			[self displayNameForTrigger:representedObject] : nil);
}

//A pill is not edited as text; nil keeps it one. Free text goes back to being typed in.
- (NSString *)tokenField:(NSTokenField *)tokenField editingStringForRepresentedObject:(id)representedObject
{
	if ([[self tokenTriggers] containsObject:representedObject]) return nil;

	return representedObject;
}

- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:(NSString *)editingString
{
	//As it stands; -tokenField:shouldAddObjects:atIndex: is where triggers are picked out
	return editingString;
}

//Copied pills leave as the %_ triggers they stand for, so the clipboard holds a working format
- (BOOL)tokenField:(NSTokenField *)tokenField writeRepresentedObjects:(NSArray *)objects toPasteboard:(NSPasteboard *)pboard
{
	[pboard setString:[objects componentsJoinedByString:@""] forType:NSPasteboardTypeString];
	return YES;
}

- (NSArray *)tokenField:(NSTokenField *)tokenField readFromPasteboard:(NSPasteboard *)pboard
{
	return [self tokensForFormatString:[pboard stringForType:NSPasteboardTypeString]];
}

/*!
 * @brief The field the resolved format is written into.
 *
 * A read-only field rather than a label, for two reasons: the row's label dims with the enabled
 * state of its control, which only a control has, and a field can be selected, so the result can
 * be copied out of here.
 *
 * One line, truncated at the end, never wrapped. The row is exactly as tall as the control it is
 * handed and re-reads that height at every layout, so a preview allowed to grow would shove the
 * Insert button up and down with every keystroke. What does not fit is put in
 * the row's tool tip instead — see -updatePreview.
 *
 * The height is fixed here, once, by measuring a line of the font; nothing set later changes it,
 * because -setStringValue: does not resize a field.
 */
- (NSTextField *)previewField
{
	NSTextField *field = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];

	[field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[field setEditable:NO];
	[field setSelectable:YES];
	[field setBordered:NO];
	[field setBezeled:NO];
	[field setDrawsBackground:NO];
	[field setAlignment:NSTextAlignmentLeft];
	//-setWraps: rewrites the line break mode (clipping when NO), so the mode goes after it
	[[field cell] setWraps:NO];
	[[field cell] setScrollable:NO];
	[field setLineBreakMode:NSLineBreakByTruncatingTail];

	//Measure one line of the font, not of any particular text
	[field setStringValue:@"Xg"];
	[field sizeToFit];
	[field setFrameSize:NSMakeSize(NSWidth([field frame]), ceil(NSHeight([field frame])))];
	[field setStringValue:@""];

	return field;
}

/*!
 * @brief Ask the players what they are playing — once, and only after the user has taken hold of
 *        the Now Playing card.
 *
 * Without a query somewhere the preview is honest but useless after every launch: Music broadcasts
 * only when something changes, so until the next track the answer to "what would this send?" is
 * "we have no idea".
 *
 * The tempting place for it was -viewDidLoad, and it was there once. The answer does not stop at
 * the preview: it reaches -[ESiTunesPlugin setiTunesCurrentInfo:fromPlayer:], which starts the
 * three second bundle and ends in every account re-filtering and re-publishing its status message.
 * A user standing on the Now Playing status would have had the text every contact sees change
 * because a settings window came up — and the preferences window reopens on whichever pane was
 * last used, so ⌘, alone was enough to land there. That is a side effect on the real status with
 * no act behind it, and drawing a line of text may not have one.
 *
 * Hung off a deliberate act instead: the caret going into the format field, or the Insert menu
 * being used. Both are unmistakably somebody working on what the music status sends — the same
 * standard -[ESiTunesPlugin requestPlayerQuery] holds every other caller to — and both come with
 * the card on screen, which explains any automation dialog that follows.
 *
 * Still the tamer of the two query methods: it returns at once if anything is known or if an
 * earlier attempt already came back empty-handed, sends nothing to a player which is not running,
 * and sends nothing twice within a few seconds. The flag here is only so that a hundred
 * keystrokes do not each walk into those guards.
 */
- (void)askPlayersOnFirstInteraction
{
	if (hasAskedPlayers) return;
	hasAskedPlayers = YES;

	[[self musicPlugin] requestPlayerQueryIfNothingIsKnown];
}

/*!
 * @brief The refresh button next to the preview was clicked: ask the players now.
 *
 * The unconditional query, not the tame one the first touch of the card sends — a click on
 * refresh means "what is playing *now*", which the answer already held may no longer be. The
 * click itself is the deliberate act that earns it, automation dialog included.
 *
 * Fire and done: the method carries its own restraint (nothing to a player that is not running,
 * nothing twice within seconds — see its header), and the answer comes back asynchronously as
 * Adium_iTunesTrackChangedNotification, which -trackChanged: already turns into a fresh preview.
 */
- (void)refreshNowPlaying:(id)sender
{
	[[self musicPlugin] requestPlayerQuery];
}

/*!
 * @brief The format field finished editing: Return, Tab or the focus moving away.
 */
- (IBAction)changeFormat:(id)sender
{
	[self saveFormat];
}

/*!
 * @brief Put a token where the caret is.
 *
 * Through the field editor rather than through -setObjectValue:, so the token lands at the caret,
 * replaces a selection, can be undone, and does not throw away an edit in progress.
 */
- (void)insertToken:(id)sender
{
	NSString	*token = [sender representedObject];
	NSText		*editor = [textField_format currentEditor];

	if (![token length] || !textField_format) return;

	/* The other deliberate act on this card. Before the insertion rather than after, so the
	 * answer is on its way while the token is being put in; the preview below redraws itself when
	 * it arrives. Making the field first responder further down would reach this anyway — the
	 * flag inside makes sure it costs nothing twice.
	 */
	[self askPlayersOnFirstInteraction];

	/* -currentEditor is nil unless this very field is being edited; asking the window for a field
	 * editor would also hand back one that belongs to somebody else. Start editing, then put the
	 * caret back where it was: making a text field first responder selects all of its text, and
	 * inserting would replace the whole format.
	 */
	if (!editor) {
		[[textField_format window] makeFirstResponder:textField_format];
		editor = [textField_format currentEditor];

		if (editor) {
			NSUInteger	length = [[editor string] length];
			NSRange		range = (hasSavedSelectedRange ? savedSelectedRange : NSMakeRange(length, 0));

			//The text may have been shortened since the range was remembered
			if (NSMaxRange(range) > length) range = NSMakeRange(length, 0);
			[editor setSelectedRange:range];
		}
	}

	if ([editor isKindOfClass:[NSTextView class]]) {
		[(NSTextView *)editor insertText:token replacementRange:[editor selectedRange]];

		/* Fold the raw trigger back into -objectValue, which is also what turns it into a pill;
		 * the editing session itself goes on. The Address Book pane inserts the same way. */
		[textField_format validateEditing];
	} else {
		//No window to edit in; appending beats losing the token
		NSMutableArray	*tokens = [[[textField_format objectValue] mutableCopy] autorelease];

		if (!tokens) tokens = [NSMutableArray array];
		[tokens addObject:token];
		[textField_format setObjectValue:tokens];
	}

	[self saveFormat];

	/* At once, not on the timer: the user has just clicked something and is owed an answer. Any
	 * typing delay still pending would only repeat this a moment later.
	 */
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updatePreview) object:nil];
	[self updatePreview];
}

/*!
 * @brief What stands in the format field right now, as the %_ string that is stored.
 *
 * While a field is being edited its -objectValue is still the last committed state; only the
 * field editor knows what stands there now. In a token field, though, the editor's -string is no
 * use: every pill in it is a single attachment character, so reading it would store object
 * replacement characters where the triggers belong. The pill still knows what it stands for —
 * its attachment cell carries the trigger as its represented object — so the live format is
 * reassembled from the editor's attributed text instead: pills contribute their trigger, plain
 * runs contribute themselves. Built fresh on every call, so nothing here ever aliases the field
 * editor's own storage.
 *
 * Outside an editing session the committed tokens are simply joined back up, which is the exact
 * inverse of -tokensForFormatString:.
 *
 * @result The format, or nil once the field is gone.
 */
- (NSString *)currentFormat
{
	if (!textField_format) return nil;

	NSText *editor = [textField_format currentEditor];

	if ([editor isKindOfClass:[NSTextView class]]) {
		NSAttributedString	*contents = [(NSTextView *)editor textStorage];
		NSString			*plainText = [contents string];
		NSMutableString		*format = [NSMutableString string];
		NSUInteger			 length = [contents length];
		NSRange				 effectiveRange = NSMakeRange(0, 0);

		for (NSUInteger index = 0; index < length; index = NSMaxRange(effectiveRange)) {
			NSTextAttachment	*attachment = [contents attribute:NSAttachmentAttributeName
														   atIndex:index
													effectiveRange:&effectiveRange];
			id					 cell = (attachment ? [attachment attachmentCell] : nil);

			if (cell) {
				/* The token field's attachment cells answer -representedObject with the token's
				 * object — our trigger or free text string. Anything that does not is not one of
				 * our pills and has no place in a format string. */
				id representedObject = ([cell respondsToSelector:@selector(representedObject)] ?
										[(NSCell *)cell representedObject] : nil);

				if ([representedObject isKindOfClass:[NSString class]]) {
					[format appendString:representedObject];
				}
			} else {
				[format appendString:[plainText substringWithRange:effectiveRange]];
			}
		}

		return format;
	}

	NSArray *tokens = [textField_format objectValue];

	return ([tokens count] ? [tokens componentsJoinedByString:@""] : @"");
}

/*!
 * @brief Store the format at once, announce it once the typing stops.
 */
- (void)saveFormat
{
	/* The field sends its action whenever an editing session ends, and that is not always the
	 * user's doing: the closing window pulls the view out from under the field editor, and it
	 * does so after -tearDown has already let go of the field. Without the field there is nothing
	 * to read, and writing nil removes the key rather than setting it. There is nothing left to
	 * save either — every keystroke went through -controlTextDidChange: — so the stray action may
	 * run out into nothing.
	 */
	NSString	*format = [self currentFormat];

	if (!format) return;

	[adium.preferenceController setPreference:format
									   forKey:KEY_ITUNES_TRACK_FORMAT
										group:PREF_GROUP_STATUS_PREFERENCES];

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(postFormatChanged) object:nil];
	[self performSelector:@selector(postFormatChanged) withObject:nil afterDelay:FORMAT_CHANGE_DELAY];
	formatChangePending = YES;
}

/*!
 * @brief Tell the plugin the format changed.
 *
 * Reads the stored value rather than the field, so this is safe to fire while the pane is being
 * taken apart.
 */
- (void)postFormatChanged
{
	formatChangePending = NO;

	[[NSNotificationCenter defaultCenter] postNotificationName:Adium_CurrentTrackFormatChangedNotification
													   object:[adium.preferenceController preferenceForKey:KEY_ITUNES_TRACK_FORMAT
																								     group:PREF_GROUP_STATUS_PREFERENCES]];
}

/*!
 * @brief The plugin that owns the replacement, or nil if it is not loaded.
 *
 * Asked of the component loader by class name, the way BGICLogImportController and
 * SMContactListShowBehaviorPlugin reach their plugins. Going through the content filter chain
 * instead was considered and rejected — the chain resolves %_iTunes from the plugin's cached
 * table, which only learns about a new format half a second after the last keystroke, so the
 * preview would visibly trail the field.
 *
 * A class name is a string, so this can come back nil. Every caller has to cope; see
 * -updatePreview, which then says the same thing it says when nothing is known.
 */
- (ESiTunesPlugin *)musicPlugin
{
	return (ESiTunesPlugin *)[adium.componentLoader pluginWithClassName:@"ESiTunesPlugin"];
}

/*!
 * @brief Show what the format in the field would currently send.
 *
 * The resolution is the plugin's, not ours: -previewOfTrackFormat:state: runs the same two-stage
 * replacement over the same %_iTunes trigger the Now Playing status message consists of.
 * Rebuilding that here would be a second implementation of a thing that exists, and the two would
 * disagree the first time either changed.
 *
 * Nothing is written on the way: no preference, no notification, no status change.
 *
 * An empty result would be the one thing worse than no preview at all — it says nothing about
 * why. There are four ways to arrive at one and they call for four different sentences, only the
 * last of which is the user's to fix. The first three are set in secondary colour so they cannot
 * be mistaken for a result; only a real preview is drawn in the ordinary label colour.
 */
- (void)updatePreview
{
	AIMusicPreviewState	 state = AIMusicPreviewNothingKnown;
	ESiTunesPlugin		*plugin = [self musicPlugin];
	NSString			*resolved = nil;
	NSString			*text = nil;
	BOOL				 isResult = NO;

	if (!textField_preview) return;

	if (plugin) resolved = [plugin previewOfTrackFormat:[self currentFormat] state:&state];

	switch (state) {
		case AIMusicPreviewPlaying:
			/* Trimmed for the decision, untrimmed for the display: what is shown stays literally
			 * what would be sent, but a result made of nothing but spaces is counted as the empty
			 * one it looks like. It is not a contrived case — "%_track %_artist" over a payload
			 * which says Playing and names neither (Apple Music radio, a shared library) comes to
			 * a single space — and drawn as a result it would be a blank line in the ordinary
			 * colour with a tool tip of spaces, which is exactly the wordless preview the
			 * sentences below exist to prevent.
			 */
			if ([[resolved stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]) {
				text = resolved;
				isResult = YES;
			} else {
				text = AILocalizedString(@"This format currently produces empty text.",
										 "Shown as the Now Playing preview when something is playing but the format resolves to nothing");
			}
			break;

		case AIMusicPreviewPaused:
			text = AILocalizedString(@"Playback is paused.",
									 "Shown as the Now Playing preview while the music player is paused");
			break;

		case AIMusicPreviewStopped:
			text = AILocalizedString(@"Nothing is playing right now.",
									 "Shown as the Now Playing preview while the music player is stopped");
			break;

		case AIMusicPreviewNothingKnown:
		default:
			text = AILocalizedString(@"Adium does not know yet what is playing.",
									 "Shown as the Now Playing preview before any music player has said anything");
			break;
	}

	[textField_preview setStringValue:text];

	/* The disabled case first, and it is not dead weight. AISettingsFormRow dims a row by
	 * following its control's enabled state, but -updateLabelColor only recolours the label, the
	 * detail and the value — never the control itself. So whoever switches the music status off
	 * and disables this field would find the text recoloured to full strength again at the next
	 * track change, since this method also runs on Adium_iTunesTrackChangedNotification, without
	 * anybody having touched the pane. One line here rather than a puzzle later.
	 */
	if (![textField_preview isEnabled]) {
		[textField_preview setTextColor:[NSColor disabledControlTextColor]];
	} else {
		[textField_preview setTextColor:(isResult ? [NSColor labelColor] : [NSColor secondaryLabelColor])];
	}

	/* The row is one line and truncates, so a long result would end in an ellipsis with nowhere
	 * to read the rest. The tool tip covers the whole row, label included. Only for a real
	 * result: the four sentences above always fit, and a tool tip repeating a line that is fully
	 * visible is noise.
	 */
	[[self settingsForm] setToolTip:(isResult ? text : nil) forRowWithControl:textField_preview];
}

/*!
 * @brief Update the preview once the typing settles.
 *
 * Its own short timer rather than -postFormatChanged's half second; PREVIEW_UPDATE_DELAY explains
 * why the two are not the same.
 */
- (void)setPreviewNeedsUpdate
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updatePreview) object:nil];
	[self performSelector:@selector(updatePreview) withObject:nil afterDelay:PREVIEW_UPDATE_DELAY];
}

/*!
 * @brief The track, the player state or the answer to a query changed.
 *
 * On the main thread, and it has to stay that way, because this touches a field: the notification
 * is posted from -[ESiTunesPlugin fireUpdateiTunesInfo], which is reached either from a delayed
 * perform or from the format notification, both of them main thread. Should a third caller ever
 * appear, it is this method that has to hop.
 */
- (void)trackChanged:(NSNotification *)notification
{
	[self updatePreview];
}

@end
