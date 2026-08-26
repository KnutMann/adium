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

@class AIXtraInfo, AISettingsFormView, AIXtraDetailsPage;

/*!
 * @protocol AIXtraDetailsPageDelegate
 * @brief What the page asks of the pane it was pushed from
 *
 * The page reads; it never writes. Both of the things it offers to do touch files, and both of them
 * already have an answer in the pane - the same one the row's context menu gets, sheet and all.
 */
@protocol AIXtraDetailsPageDelegate <NSObject>
- (void)xtraDetailsPage:(AIXtraDetailsPage *)page revealXtra:(AIXtraInfo *)xtra;
- (void)xtraDetailsPage:(AIXtraDetailsPage *)page deleteXtra:(AIXtraInfo *)xtra;
/*!
 * @brief Whether this Xtra can be thrown away at all
 *
 * The same question the row's context menu asks, and it is the pane's to answer: an Xtra which ships
 * inside the app has no file of the user's to trash. Answered NO, the page shows no button for it.
 */
- (BOOL)xtraDetailsPage:(AIXtraDetailsPage *)page canDeleteXtra:(AIXtraInfo *)xtra;
@end

/*!
 * @class AIXtraDetailsPage
 * @brief One Xtra's manifest, as a page inside the Xtras pane
 *
 * What a row can only hint at: the picture the Xtra ships, what it says it is, and every field of
 * its Info.plist worth reading out loud - version, author, who it was built for, what it needs.
 * Slid in over the list rather than opened beside it, the way an account's settings are.
 *
 * Nothing on the page is editable, because nothing about an installed Xtra is ours to change: the
 * manifest belongs to whoever made it. The two buttons act on the file, not on the manifest.
 *
 * A field which the Xtra does not carry is left out rather than shown empty. Most Xtras in the wild
 * fill in two or three of them, so a page of blanks would be the normal case; the ones Adium ships
 * itself fill in all of them.
 */
@interface AIXtraDetailsPage : NSViewController {
	AIXtraInfo						*xtraInfo;
	NSString						*categoryName;
	AISettingsFormView				*form;
	__unsafe_unretained
	id<AIXtraDetailsPageDelegate>	 pageDelegate;		//Not retained
}

/*!
 * @brief A page about @a inXtraInfo, which the list of @a inCategoryName holds
 *
 * @a inCategoryName may be nil, which leaves out the row naming the category.
 */
- (id)initWithXtra:(AIXtraInfo *)inXtraInfo
	  categoryName:(NSString *)inCategoryName
		  delegate:(id<AIXtraDetailsPageDelegate>)inDelegate;

- (AIXtraInfo *)xtra;

/*!
 * @brief Let go of the Xtra and of the pane
 */
- (void)tearDown;

@end
