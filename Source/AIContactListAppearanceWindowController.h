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

/*!
 * @brief Which part of the editor to open on
 */
typedef enum {
	AIContactListAppearanceSectionShape = 0,
	AIContactListAppearanceSectionContactRow,
	AIContactListAppearanceSectionGroupRow,
	AIContactListAppearanceSectionColours
} AIContactListAppearanceSection;

/*!
 * @brief What the contact list looks like, in one window
 *
 * Replaces the two sheets that used to sit behind the Customize buttons, one
 * for the layout and one for the colours. They were a split of where the
 * settings are stored, not of what a reader sees, and neither showed what it
 * was doing: the list itself was behind the sheet.
 *
 * The storage is unchanged. Everything still goes into the same two preference
 * groups under the same key names, so a layout or colour set somebody
 * installed keeps working.
 */
@interface AIContactListAppearanceWindowController : NSWindowController

/*!
 * @param inLayoutName The layout set the changes are saved into
 * @param inThemeName The colour set the changes are saved into
 * @param inSection The part of the editor to show first
 * @param inTarget Told when the editor closes, see AIListLayoutEditorTarget below
 */
- (instancetype)initWithLayoutNamed:(NSString *)inLayoutName
						 themeNamed:(NSString *)inThemeName
							section:(AIContactListAppearanceSection)inSection
					notifyingTarget:(id)inTarget;

- (void)showOnWindow:(NSWindow *)parentWindow;

@end

/*!
 * @brief What the editor tells whoever opened it
 */
@interface NSObject (AIContactListAppearanceEditorTarget)
- (void)listLayoutEditorWillCloseWithChanges:(BOOL)saveChanges forLayoutNamed:(NSString *)name;
- (void)listThemeEditorWillCloseWithChanges:(BOOL)saveChanges forThemeNamed:(NSString *)name;
@end
