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

@class AIStatus, AIAlternatingRowOutlineView, AISettingsFormView;

/*!
 * @class ESStatusPreferences
 * @brief The Status preference pane, built as an AISettingsFormView
 *
 * Three cards: the list of saved statuses with its button bar, the idle and away
 * settings, and the two automatic status changes. The nib no longer supplies an
 * arrangement, only ready made controls — above all the outline view with its
 * data source, its delegate and its drag registration, which is far too much to
 * rebuild by hand. -view moves those controls into the form and keeps the nib's
 * top level view in nibView for as long as they are in use.
 *
 * Every control writes its preference the moment it is touched: the preferences
 * window only calls -closeView when the window itself closes, so leaving the
 * pane through the sidebar is not a point at which anything could still be
 * saved. The old -saveTimeValues, which wrote the two intervals from
 * -viewWillClose and nowhere else, is gone with it.
 */
@interface ESStatusPreferences : AIPreferencePane {
	/* The nib is only a supplier of ready made controls now; our view is the settings form we
	 * move them into. This reference keeps the nib's top level view — and with it its ownership
	 * of everything we did not move — alive for as long as we use its controls. */
	NSView								*nibView;

	//Status state list
	IBOutlet	NSButton				*button_editState;
	IBOutlet	NSButton				*button_addGroup;
	IBOutlet	NSSegmentedControl		*button_addOrRemoveState;

	IBOutlet	AIAlternatingRowOutlineView	*outlineView_stateList;
	//AIPassthroughScrollView in the nib: the list is sized to its rows and must not eat the wheel
	IBOutlet	NSScrollView			*scrollView_stateList;

	NSArray								*draggingItems;
	BOOL								 stateListHeightUpdateScheduled;
	/* A drop takes a rebuilding delay from the status controller and the perform which follows it
	 * gives it back. -tearDown cancels pending performs, so it has to know whether it just cancelled
	 * the one which would have balanced that delay. */
	BOOL								 delayedStatusMenuRebuilding;
	//What the outline view keeps beside its column, measured while it is tiled to its clip view
	CGFloat								 stateColumnMargin;

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
	BOOL						showingSubmenuItemInAutoAway;

	IBOutlet	NSPopUpButton	*popUp_fastUserSwitchingStatusState;
	BOOL						showingSubmenuItemInFastUserSwitching;

	IBOutlet	NSPopUpButton	*popUp_screenSaverStatusState;
	BOOL						showingSubmenuItemInScreenSaver;

	NSSwitch			*checkBox_awayReminder;
	IBOutlet	NSTextField		*textField_awayReminderMinutes;
	IBOutlet	NSStepper		*stepper_awayReminderMinutes;
	IBOutlet	NSTextField		*label_awayReminderMinutes;
}

- (void)configureStateList;

- (IBAction)addOrRemoveState:(id)sender;
- (IBAction)editState:(id)sender;
- (IBAction)addGroup:(id)sender;

/*!
 * @brief A minutes field or its stepper changed; write that interval now
 */
- (IBAction)changedTimeValue:(id)sender;

- (void)stateArrayChanged:(NSNotification *)notification;

@end
