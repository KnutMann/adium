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

@class AISettingsFormView;

#import <Adium/AIAccountViewController.h>

@interface PurpleAccountViewController : AIAccountViewController {
	IBOutlet	NSButton	*checkBox_broadcastMusic;
	IBOutlet	NSButton	*checkBox_displayCustomEmoticons;
}

- (NSMenu *)encodingMenu;


/*!
 * @brief Build this protocol's own options as ordinary settings rows
 *
 * A libpurple protocol describes each of its options: name, type, default, and for a choice the
 * choices. Pidgin builds its whole account dialog out of that; nothing here read it, which is why
 * every option was at some point drawn into a nib by hand and no two services looked alike.
 */
- (void)addOptionRowsToForm:(AISettingsFormView *)form;

/*!
 * @brief Does this protocol declare any option at all?
 */
- (BOOL)hasProtocolOptions;

@end
