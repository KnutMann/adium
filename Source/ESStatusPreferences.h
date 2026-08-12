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

#import "AIPreferencePane.h"
#import "AIStatusListView.h"

@class AIStatus, AISettingsFormView;

/*!
 * @class ESStatusPreferences
 * @brief The Status preference pane, built as an AISettingsFormView
 *
 * Four cards: the list of statuses with its "+" button, the idle and away
 * settings, the two automatic status changes, and what the Now Playing status
 * sends. The list itself is built in code (AIStatusListView); what the nib
 * still supplies is the two minute fields with their steppers and unit labels,
 * the three status menus and the "+". -view moves those controls into the form
 * and keeps the nib's top level view in nibView for as long as they are in use.
 *
 * The Now Playing card lived in a second pane which was also called "Status",
 * under Advanced - one name, two sidebar entries, and the setting for what a
 * status sends was the one thing not on the pane that manages statuses. The
 * status itself is switched on and off in the list above like any other, so
 * everything about it is in one place now.
 *
 * Every control writes its preference the moment it is touched: the preferences
 * window only calls -closeView when the window itself closes, so leaving the
 * pane through the sidebar is not a point at which anything could still be
 * saved. The old -saveTimeValues, which wrote the two intervals from
 * -viewWillClose and nowhere else, is gone with it.
 */
@interface ESStatusPreferences : AIPreferencePane <AIStatusListViewDelegate, NSTextFieldDelegate> {
	/* The nib is only a supplier of ready made controls now; our view is the settings form we
	 * move them into. This reference keeps the nib's top level view — and with it its ownership
	 * of everything we did not move — alive for as long as we use its controls. */
	NSView								*nibView;

	/* The status list. Built in code and owned by the form once it has been handed over; this is a
	 * non-retaining reference, cleared by -tearDown. */
	AIStatusListView					*listView_states;
	//The one button under the list, the nib's segmented control cut down to a single "+"
	IBOutlet	NSSegmentedControl		*button_addOrRemoveState;

	/* The two checkboxes are NSSwitches built by -buildSettingsForm, the way every converted
	 * pane does it; their titles moved into the row labels. Everything else below still comes
	 * from the nib and is owned by the form once it has been moved there.
	 *
	 * There is one idleness now, not two: this switch and this duration report the idleness and,
	 * if popUp_autoAwayStatusState names a status, set it. The three status menus carry their own
	 * off switch in their first entry, "Do not change", so they need no checkbox of their own —
	 * but popUp_autoAwayStatusState still dims with this switch, because everything the switch
	 * turns off includes the status change (see -configureControlDimming). */
	NSSwitch			*checkBox_idle;
	IBOutlet	NSTextField		*textField_idleMinutes;
	IBOutlet	NSStepper		*stepper_idleMinutes;
	IBOutlet	NSTextField		*label_idleMinutes;		//The "minutes" behind the field

	IBOutlet	NSPopUpButton	*popUp_autoAwayStatusState;
	IBOutlet	NSPopUpButton	*popUp_fastUserSwitchingStatusState;
	IBOutlet	NSPopUpButton	*popUp_screenSaverStatusState;

	NSSwitch			*checkBox_awayReminder;
	IBOutlet	NSTextField		*textField_awayReminderMinutes;
	IBOutlet	NSStepper		*stepper_awayReminderMinutes;
	IBOutlet	NSTextField		*label_awayReminderMinutes;

	/* A rebuild of the menus and the list is due on the next turn of the run loop. The state array
	 * notification can arrive from inside a row's own switch, which must not be torn out from under
	 * AppKit; -stateArrayChanged: says so. */
	BOOL						refreshScheduled;

	/* The Now Playing card. All built in code; non-retaining references, cleared by -tearDown. */
	NSTextField			*textField_format;
	NSPopUpButton		*popUp_insertToken;
	NSTextField			*textField_preview;			//Shows what the format resolves to right now; read-only

	/* Where the caret stood when the format field last gave up editing. Choosing
	 * from the pull down can take the focus away, and the token still has to land
	 * where the user left off. */
	NSRange				 savedSelectedRange;
	BOOL				 hasSavedSelectedRange;

	BOOL				 formatChangePending;		//A coalesced format announcement is still outstanding

	/* Whether the players have already been asked during this visit to the pane.
	 * Asking is not free — it is an Apple event and possibly an automation dialog —
	 * so it waits for the user to actually take hold of the card, and then happens
	 * once. See -askPlayersOnFirstInteraction.
	 */
	BOOL				 hasAskedPlayers;
}

- (IBAction)addOrRemoveState:(id)sender;

/*!
 * @brief A minutes field or its stepper changed; write that interval now
 */
- (IBAction)changedTimeValue:(id)sender;

- (void)stateArrayChanged:(NSNotification *)notification;

@end
