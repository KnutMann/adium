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

/*!
 * @class ESContactListAdvancedPreferences
 * @brief The advanced Contact List pane, built as an AISettingsFormView
 *
 * Four cards — how the list is drawn, its tooltips, how its window behaves, and
 * when it hides itself. Every control below is created by -buildSettingsForm and
 * owned by that form (which the inherited 'view' ivar retains), so the
 * references here are non-owning and are cleared again in -viewWillClose. There
 * is no nib.
 */
@interface ESContactListAdvancedPreferences : AIAdvancedPreferencePane {
	NSPopUpButton	*popUp_windowPosition;

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

@end
