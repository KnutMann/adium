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

	//Card 1: the list of statuses
	[form addSectionHeader:AILocalizedString(@"Statuses", nil)];

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

	/* The list lives in the form's card, and the form and this pane are released on different paths
	 * (-tearDown here, -[AIModularPane closeView] there). Cut it loose from us here, so a view which
	 * outlives us for a moment can never ask a freed pane anything - its delegate is a non-retaining
	 * reference to us. */
	[listView_states tearDown];

	//Same for everything else we handed a target or a delegate to
	for (NSControl *control in [NSArray arrayWithObjects:
								button_addOrRemoveState,
								checkBox_idle, checkBox_awayReminder,
								stepper_idleMinutes, stepper_awayReminderMinutes,
								nil]) {
		[control setTarget:nil];
	}
	for (NSTextField *field in [NSArray arrayWithObjects:
								textField_idleMinutes, textField_awayReminderMinutes,
								nil]) {
		[field setTarget:nil];
		[field setDelegate:nil];
	}
	/* Every item of these menus carries our address as its target (AIStatusMenu sets it per item),
	 * so the menus go rather than outlive us on a button the form has not released yet. */
	for (NSPopUpButton *popUp in [NSArray arrayWithObjects:
								  popUp_autoAwayStatusState, popUp_fastUserSwitchingStatusState,
								  popUp_screenSaverStatusState, nil]) {
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

	//A refresh may have been due; -cancelPreviousPerformRequestsWithTarget: above took it away
	refreshScheduled = NO;

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

	if ([field integerValue] < MINUTES_MINIMUM) [self configureOtherControls];
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
	[self changedTimeValue:[notification object]];
}

@end
