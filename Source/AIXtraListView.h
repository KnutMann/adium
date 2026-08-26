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
#import "AIPassthroughScrollView.h"

@class AIXtraInfo, AIXtraListView;

/*!
 * @protocol AIXtraListViewDelegate
 * @brief What a list asks of its owner
 *
 * The list draws rows and nothing else: every action a row offers is handed on, because only the
 * pane knows how to ask before it deletes something and how to tell the rest of Adium that the set
 * of installed Xtras has changed.
 */
@protocol AIXtraListViewDelegate <NSObject>
/*!
 * @brief The switch of a row was flipped
 */
- (void)xtraListView:(AIXtraListView *)listView setEnabled:(BOOL)enabled forXtra:(AIXtraInfo *)xtra;
/*!
 * @brief A row was clicked, or its chevron was
 *
 * The row leads to a page about that one Xtra; the list does not know what stands on it.
 */
- (void)xtraListView:(AIXtraListView *)listView showDetailsForXtra:(AIXtraInfo *)xtra;
/*!
 * @brief "Move to Trash" was chosen from a row's context menu
 */
- (void)xtraListView:(AIXtraListView *)listView deleteXtra:(AIXtraInfo *)xtra;
/*!
 * @brief "Show in Finder" was chosen from a row's context menu
 */
- (void)xtraListView:(AIXtraListView *)listView revealXtra:(AIXtraInfo *)xtra;
/*!
 * @brief The list is a different height than it was
 *
 * The list is the edge to edge row of a card, so its height is the card's height; the pane passes
 * this on to the settings form, which is what makes the card - and the scrolling column around it -
 * follow along.
 */
- (void)xtraListViewDidChangeHeight:(AIXtraListView *)listView;

@optional
/*!
 * @brief Whether a row's switch may be flipped at all
 *
 * @a movable is the list's own answer - true only for an Xtra in the user's own folder, the only
 * kind it can move into a "(Disabled)" folder. A delegate returns it unchanged for the ordinary
 * case and overrides it for an Xtra it switches some other way: a JavaScript plugin is turned on
 * and off by preference, so its switch works wherever the plugin lives, the app's own bundle
 * included. Left out, @a movable stands.
 */
- (BOOL)xtraListView:(AIXtraListView *)listView canToggleXtra:(AIXtraInfo *)xtra whenMovable:(BOOL)movable;
/*!
 * @brief Whether a row may be thrown away
 *
 * @a movable is the list's own answer as above. A delegate returns YES for anything it can delete
 * and NO for one it cannot - a plugin that ships inside the app has no file of the user's to trash.
 * Left out, every row offers "Move to Trash".
 */
- (BOOL)xtraListView:(AIXtraListView *)listView canDeleteXtra:(AIXtraInfo *)xtra whenMovable:(BOOL)movable;
@end

/*!
 * @class AIXtraListView
 * @brief The list of Xtras of one category, as the single edge to edge row of a card
 *
 * The list System Settings puts inside a card: no scrollers of its own, as tall as its rows, one
 * full width column, no selection, a hairline between two rows. A row shows the Xtra's icon, its
 * name, a line of detail, a switch which enables or disables it and a chevron which leads to a page
 * about that Xtra - and so the whole row leads there, the way a row with a chevron does everywhere
 * else. Throwing an Xtra away is in the row's context menu rather than on a button of its own: it
 * is the one thing here which cannot be undone, and a target next to the switch is easy to hit by
 * accident.
 *
 * Everything a hosted list needs to keep working - following the width of its card, keeping its
 * single column in step with the table, reporting its own height - lives here rather than in the
 * pane, so that a page holding ten of these pays for it once.
 *
 * Hand it to @c -[AISettingsFormView addEdgeToEdgeRow:] and keep no other reference to its views;
 * the form owns them from then on. Call @c -tearDown before letting go of the delegate.
 */
@interface AIXtraListView : AIPassthroughScrollView <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate> {
	NSTableView					*tableView;			//The list itself; our clip view holds it too
	NSArray						*xtras;				//AIXtraInfo, in display order
	__unsafe_unretained
	id<AIXtraListViewDelegate>	 listDelegate;		//Not retained
	NSString					*userDirectory;		//Xtras below this one may be switched off
	/* Width the rows were last laid out for; see -listFrameChanged: */
	CGFloat						 cachedLayoutWidth;
	/* Room the table keeps between its own edge and its column, measured off the table itself */
	CGFloat						 columnMargin;
	//The row whose context menu is open, or -1; it is the row that menu acts on
	NSInteger					 contextMenuRow;
	BOOL						 layoutScheduled;
}

/*!
 * @brief A list showing @a inXtras, sized to hold them
 */
- (id)initWithXtras:(NSArray *)inXtras;

- (NSArray *)xtras;
/*!
 * @brief Show a different set of Xtras; the list resizes itself to fit
 */
- (void)setXtras:(NSArray *)inXtras;

- (id<AIXtraListViewDelegate>)listDelegate;
- (void)setListDelegate:(id<AIXtraListViewDelegate>)inDelegate;

/*!
 * @brief The height the list needs to show every row without scrolling
 */
- (CGFloat)requiredHeight;

/*!
 * @brief Cut the table loose from its delegate
 *
 * The form owns the views and may outlive the pane by a moment; delegate, data source and target
 * are all non-retaining references to it. Idempotent.
 */
- (void)tearDown;

@end
