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

@class AIStatusItem, AIStatusListView;

/*!
 * @protocol AIStatusListViewDelegate
 * @brief What a list of statuses asks of its owner
 *
 * The list draws rows and decides nothing: only the pane knows how to open the status editor, how to
 * ask before it deletes something and where the "show in the status menu" switch is stored.
 */
@protocol AIStatusListViewDelegate <NSObject>
/*!
 * @brief The switch of a row was flipped
 */
- (void)statusListView:(AIStatusListView *)listView setShownInStatusMenu:(BOOL)shown forStatus:(AIStatusItem *)statusItem;
/*!
 * @brief The ⊖ of a row was clicked
 */
- (void)statusListView:(AIStatusListView *)listView deleteStatus:(AIStatusItem *)statusItem;
/*!
 * @brief A row was double clicked
 */
- (void)statusListView:(AIStatusListView *)listView editStatus:(AIStatusItem *)statusItem;
/*!
 * @brief The list is a different height than it was
 *
 * The list is the edge to edge row of a card, so its height is the card's height; the pane passes
 * this on to the settings form, which is what makes the card - and the scrolling column around it -
 * follow along.
 */
- (void)statusListViewDidChangeHeight:(AIStatusListView *)listView;
@end

/*!
 * @class AIStatusListView
 * @brief The list of statuses, as the single edge to edge row of a card
 *
 * The list System Settings puts inside a card: no scrollers of its own, as tall as its rows, one
 * full width column, no selection, a hairline between two rows. A row shows the status's icon, its
 * title, a switch saying whether it appears in the status menus and a ⊖ which deletes it.
 *
 * Unlike the outline view it replaces, this list shows the built-in statuses too - they are the very
 * reason the switch exists, since they cannot be deleted and would otherwise be in the menu forever.
 * Their ⊖ is dimmed accordingly, and so is the switch of the built-in Offline: Offline has no
 * "Custom…" stand-in in the status menu and no menu command of its own, so hiding it would take the
 * way back offline away.
 *
 * Hand it to @c -[AISettingsFormView addEdgeToEdgeRow:] and keep no other reference to its views;
 * the form owns them from then on. Call @c -tearDown before letting go of the delegate.
 */
@interface AIStatusListView : AIPassthroughScrollView <NSTableViewDataSource, NSTableViewDelegate> {
	NSTableView					 *tableView;		//Owned by the view hierarchy
	NSArray						 *statusItems;		//AIStatusItem, in display order
	__unsafe_unretained id<AIStatusListViewDelegate>  listDelegate;		//Not retained
	/* Width the rows were last laid out for; see -listFrameChanged: */
	CGFloat						  cachedLayoutWidth;
	/* Room the table keeps between its own edge and its column, measured off the table itself */
	CGFloat						  columnMargin;
	BOOL						  layoutScheduled;
}

/*!
 * @brief A list showing @a inStatusItems, sized to hold them
 */
- (id)initWithStatusItems:(NSArray *)inStatusItems;

- (NSArray *)statusItems;
/*!
 * @brief Show a different set of statuses; the list resizes itself to fit
 */
- (void)setStatusItems:(NSArray *)inStatusItems;

- (id<AIStatusListViewDelegate>)listDelegate;
- (void)setListDelegate:(id<AIStatusListViewDelegate>)inDelegate;

/*!
 * @brief The height the list needs to show every row without scrolling
 */
- (CGFloat)requiredHeight;

/*!
 * @brief Cut the table loose from its delegate
 *
 * The form owns the views and may outlive the pane by a moment; delegate, data source and target are
 * all non-retaining references to it. Idempotent.
 */
- (void)tearDown;

@end
