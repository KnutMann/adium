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

#import <Adium/AIPreferencePane.h>

@class ESContactAlertsViewController, AIVariableHeightFlexibleColumnsOutlineView;

/*!
 * @class ESGlobalEventsPreferences
 * @brief The Events preference pane, built as an AISettingsFormView
 *
 * Three cards: what the pane is about, the preset/sound set/volume controls,
 * and the list of events with its action bar. The nib is only a supplier of
 * ready made controls now — above all the ESContactAlertsViewController with
 * its outline view, which is shared with the contact inspector and cannot be
 * rebuilt here — while their arrangement is the form's.
 *
 * Every control writes its preference the moment it is touched, as it always
 * did here: the preset menu, the sound set menu and the volume slider each
 * apply their change in their own action. The preferences window only calls
 * -closeView when the window itself closes, so leaving the pane through the
 * sidebar is not a point at which anything could still be saved.
 */
@interface ESGlobalEventsPreferences : AIPreferencePane {
	/* The nib is only a supplier of ready made controls now; our view is the settings form we
	 * move them into. This reference keeps the nib's top level view — and with it its ownership
	 * of everything we did not move — alive for as long as we use its controls. */
	NSView		*nibView;

	IBOutlet	ESContactAlertsViewController	*contactAlertsViewController;

	IBOutlet	NSPopUpButton	*popUp_eventPreset;
	IBOutlet	NSPopUpButton	*popUp_soundSet;

	//Code-built: the global gate for Notification Center, above the per-event list
	NSSwitch		*switch_notifications;
	NSPopUpButton	*popUp_notificationIconShape;	//Round or rounded corners for the banner's contact picture

	/* No longer displayed: their words became the row labels. The outlets stay because the nib
	 * still connects them, and nib loading throws on a key it cannot find. */
	IBOutlet	NSTextField		*label_eventPreset;
	IBOutlet	NSTextField		*label_soundSet;

	IBOutlet	NSSlider		*slider_volume;
	IBOutlet	NSButton		*button_minvolume;
	IBOutlet	NSButton		*button_maxvolume;

	/* The alerts view controller's container and outline view, reached through the outlets the
	 * nib wired into that controller. Let go of again by -tearDown: the container belongs to the
	 * form once it has been handed over. */
	NSView										*view_alertsHost;
	AIVariableHeightFlexibleColumnsOutlineView	*outlineView_alerts;

	/* A height update for the events card is due on the next turn of the run loop. The outline's
	 * frame moves from inside its own tiling, which must not be re-entered; -alertsListFrameChanged:
	 * says so. */
	BOOL		alertsHeightUpdateScheduled;
}

- (IBAction)selectVolume:(id)sender;

@end
