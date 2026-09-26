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
 * @brief Which of the two saved sets a page writes into
 */
typedef enum {
	AIContactListAppearanceScopeLayout = 0,	//Fonts, sizes, what is shown in a row
	AIContactListAppearanceScopeTheme		//Colours
} AIContactListAppearanceScope;

/*!
 * @brief One page of settings for how the contact list is drawn
 *
 * A step below the contact list settings rather than a window in front of them:
 * the list itself is the preview, because every control here writes its
 * preference straight away and the list redraws. That is also why there is no
 * Cancel. Going back keeps what was changed and writes it into the set whose
 * name the page carries.
 *
 * Storage is unchanged from the two sheets this grew out of. Everything still
 * goes into the same preference groups under the same key names, so a layout or
 * a colour set somebody installed keeps working.
 */
@interface AIContactListAppearancePage : NSViewController

/*!
 * @param inScope Which half of the settings the page shows and writes
 */
- (instancetype)initWithScope:(AIContactListAppearanceScope)inScope;

/*!
 * @brief Which half this page shows
 */
@property (readonly, nonatomic) AIContactListAppearanceScope scope;

/*!
 * @brief Whether anything on the page was touched
 *
 * Opening a page and leaving it again must not turn a set that ships with the
 * program into a copy of it on disk, so the host only writes when this says so.
 */
@property (readonly, nonatomic) BOOL hasChanges;

/*!
 * @brief Let go of the colour panel and the preference observers
 */
/*!
 * @brief The window style changed under this page; show what that style has
 *
 * Which rows there are depends on it, and the pop up that changes it is one step
 * up, on the page this one was opened from.
 */
- (void)rebuildForStyleChange;

- (void)tearDown;

@end
