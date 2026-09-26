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
 * @brief What holds for the whole program, built as an AISettingsFormView
 *
 * Light or dark, and the icon packs, which are seen well outside any one window.
 * Everything that belongs to the contact list alone moved to the pane named after
 * it, which is where it was half kept anyway, and where the window style no
 * longer appears twice on two levels.
 *
 * Every control below is created by -buildSettingsForm and owned by that form
 * (which the inherited 'view' ivar retains); the pane's own references are
 * cleared again in -viewWillClose, so a closed pane holds no piece of the form
 * alive. There is no nib.
 */
@interface AIAppearancePreferences : AIPreferencePane <NSMenuDelegate> {
	NSPopUpButton	*popUp_statusIcons;
	NSPopUpButton	*popUp_serviceIcons;
	NSPopUpButton	*popUp_menuBarIcons;
	NSPopUpButton	*popUp_emoticons;
	NSPopUpButton	*popUp_dockIcon;
	NSPopUpButton	*popUp_appearanceStyle;

	NSButton		*button_customizeEmoticons;
	NSButton		*button_showAllDockIcons;
}

- (IBAction)showAllDockIcons:(id)sender;
- (IBAction)customizeEmoticons:(id)sender;

- (void)xtrasChanged:(NSNotification *)notification;

@end
