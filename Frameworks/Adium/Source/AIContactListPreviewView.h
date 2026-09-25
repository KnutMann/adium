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

#import <Cocoa/Cocoa.h>
#import <Adium/AIAbstractListController.h>

@class AIListOutlineView;

/*!
 * @brief A small contact list made of invented contacts
 *
 * Shows what a layout and a colour set look like, without touching the real
 * contact list and without naming anybody real. The drawing is the program's
 * own: real groups, real contacts, the real list controller and the real cells,
 * so what is shown here is what the window will look like.
 *
 * The state colours that a contact is drawn in normally arrive from
 * AIContactStatusColoringPlugin, which only watches real contacts. This view
 * therefore reads them out of the colour set itself.
 */
@interface AIContactListPreviewView : NSView

/*!
 * @brief Show a layout and a colour set
 *
 * @param layoutDict Values of the PREF_GROUP_LIST_LAYOUT kind
 * @param themeDict Values of the PREF_GROUP_LIST_THEME kind
 * @param windowStyle The shape of window the list would be drawn in
 */
- (void)applyLayout:(NSDictionary *)layoutDict
			  theme:(NSDictionary *)themeDict
		windowStyle:(AIContactListWindowStyle)windowStyle;

/*!
 * @brief The height the list would like to have, for a window that grows with it
 */
@property (readonly, nonatomic) CGFloat listHeight;

/*!
 * @brief The list itself, for a harness that wants to photograph it
 */
@property (readonly, nonatomic) AIListOutlineView *listView;

/*!
 * @brief Fill the list up with more invented contacts
 *
 * Five contacts fit in any window. A harness looking for what happens when the
 * table has to hand its row views on from one row to the next needs a list that
 * does not fit, which is what this is for.
 */
- (void)addFillerContacts:(NSUInteger)count;

/*!
 * @brief Add a whole group with contacts in it, in one go
 *
 * What an account does when it signs on: a group that was not there before
 * appears with everything in it at once. A harness looking for what the list
 * does in that moment needs it to happen, not to be imagined.
 */
- (void)addFilledGroupNamed:(NSString *)name contacts:(NSUInteger)count;

@end
