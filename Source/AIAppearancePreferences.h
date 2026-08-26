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

/*!
 * @class AIAppearancePreferences
 * @brief The Appearance pane, built as an AISettingsFormView
 *
 * Three cards — the contact list window, its themes, and the icon packs. Every
 * control below is created by -buildSettingsForm and owned by that form (which
 * the inherited 'view' ivar retains); the pane's own references are cleared
 * again in -viewWillClose, so a closed pane holds no piece of the form alive.
 * There is no nib.
 */
@interface AIAppearancePreferences : AIPreferencePane <NSMenuDelegate> {
	NSPopUpButton	*popUp_statusIcons;
	NSPopUpButton	*popUp_serviceIcons;
	NSPopUpButton	*popUp_menuBarIcons;
	NSPopUpButton	*popUp_emoticons;
	NSPopUpButton	*popUp_dockIcon;
	NSPopUpButton	*popUp_listLayout;
	NSPopUpButton	*popUp_colorTheme;
	NSPopUpButton	*popUp_windowStyle;
	NSPopUpButton	*popUp_appearanceStyle;

	NSSwitch		*checkBox_verticalAutosizing;
	NSSwitch		*checkBox_horizontalAutosizing;

	NSSlider		*slider_windowOpacity;
	NSTextField		*textField_windowOpacity;

	NSSlider		*slider_horizontalWidth;
	NSTextField		*textField_horizontalWidthIndicator;

	NSButton		*button_customizeEmoticons;
	NSButton		*button_showAllDockIcons;
	NSButton		*button_customizeColorTheme;
	NSButton		*button_customizeListLayout;

	//
	NSArray		*_listLayouts;	//Only compared against, never read: the presets last handed to the preset sheet
	NSArray		*_listThemes;	//Only compared against, never read: the presets last handed to the preset sheet
}

- (IBAction)showAllDockIcons:(id)sender;
- (IBAction)customizeListLayout:(id)sender;
- (IBAction)customizeListTheme:(id)sender;
- (IBAction)customizeEmoticons:(id)sender;

- (void)xtrasChanged:(NSNotification *)notification;

@end
