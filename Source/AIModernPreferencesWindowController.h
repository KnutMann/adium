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

@class AIPreferencePane;

/*!
 * @class AIModernPreferencesWindowController
 * @brief System Settings style preferences window
 *
 * Hosts the AIPreferencePane instances registered with the preference
 * controller in a split view: a full-height vibrancy sidebar (source list,
 * grouped) on the left and a fixed-width content column on the right.
 * The advanced panes appear as their own sidebar entries under an
 * "Advanced" group instead of a nested container pane.
 */
@interface AIModernPreferencesWindowController : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSToolbarDelegate> {
	NSMutableArray		*sidebarEntries;	//Group headers (NSString) and panes (AIPreferencePane)
	NSOutlineView		*outlineView;
	NSView				*contentHost;
	AIPreferencePane	*currentPane;
	NSMutableSet		*openedPanes;		//Panes whose view was shown at least once (closeView on window close)
	BOOL				layingOutPane;		//Guards the clip view frame observer against re-entering itself

	//Back/forward navigation through visited panes
	NSMutableArray		*history;
	NSInteger			historyIndex;
	BOOL				navigatingHistory;
	NSSegmentedControl	*navigationControl;
}

+ (AIModernPreferencesWindowController *)sharedController;
+ (void)closeSharedController;

- (void)showWindowAndSelectPaneWithIdentifier:(NSString *)identifier;

@end
