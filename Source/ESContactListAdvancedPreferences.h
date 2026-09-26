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

#import <Adium/AIAdvancedPreferencePane.h>
#import <Adium/AISettingsNavigationController.h>
#import "AISettingsFormView.h"
#import "AIContactListAppearancePage.h"

/*!
 * @class ESContactListAdvancedPreferences
 * @brief Everything about the contact list, in the pane named after it
 *
 * Six cards: the window it is drawn in, how it is drawn, how it behaves, its
 * tooltips, where it sits among other windows, and when it takes itself away.
 *
 * The first two used to live in the Appearance pane, which is how the list came
 * to be settled in two places at once, with the window style appearing twice on
 * two different levels. Appearance keeps what holds for the whole program: light
 * or dark, and the icon packs, which are seen well outside this window.
 *
 * Each of the two saved sets, the colours and the layout, has its own page a step
 * below this one, reached by the chevron beside it. Every control below is
 * created by -buildSettingsForm and owned by that form, so the references here
 * are non-owning and are cleared again in -viewWillClose. There is no nib.
 */
@interface ESContactListAdvancedPreferences : AIAdvancedPreferencePane <AISettingsNavigationControllerDelegate> {
	NSPopUpButton	*popUp_windowPosition;

	//The contact list's own window
	NSPopUpButton	*popUp_windowStyle;
	NSSwitch		*checkBox_verticalAutosizing;
	NSSwitch		*checkBox_horizontalAutosizing;
	NSSlider		*slider_windowOpacity;
	NSTextField		*textField_windowOpacity;
	NSSlider		*slider_horizontalWidth;
	NSTextField		*textField_horizontalWidthIndicator;

	//The two saved sets and the pages behind them
	NSPopUpButton	*popUp_colorTheme;
	NSPopUpButton	*popUp_listLayout;
	NSButton		*button_customizeColorTheme;
	NSButton		*button_customizeListLayout;
	NSArray			*_listLayouts;	//Only compared against: the presets last handed to the preset sheet
	NSArray			*_listThemes;	//Only compared against: the presets last handed to the preset sheet

	AISettingsFormView				*rootForm;
	AISettingsNavigationController	*navigationController;
	AIContactListAppearancePage		*detailPage;
	BOOL							 buildingView;

	//The three cells matrix_hiding used to hold, in display order
	NSPopUpButton	*popUp_hidingStyle;
	NSSwitch		*checkBox_hideOnScreenEdgesOnlyInBackground;

	NSSwitch		*checkBox_flash;
	NSSwitch		*checkBox_animateChanges;
	NSSwitch		*checkBox_showTooltips;
	NSSwitch		*checkBox_showTooltipsInBackground;
	NSSwitch		*checkBox_windowHasShadow;
	NSSwitch		*checkBox_showOnAllSpaces;
}

- (IBAction)customizeListLayout:(id)sender;
- (IBAction)customizeListTheme:(id)sender;
- (IBAction)createListLayout:(id)sender;
- (IBAction)createListTheme:(id)sender;

@end
