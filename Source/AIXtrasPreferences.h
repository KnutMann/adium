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
#import "AIXtraListView.h"

/*!
 * @class AIXtrasPreferences
 * @brief The "Xtras" pane of the preferences window: everything installed, category by category
 *
 * One card per category which has anything in it - a category with nothing installed is skipped
 * rather than drawn as a bold heading above an empty card - plus a closing card pointing at the
 * Xtras website and at the folder downloaded Xtras end up in.
 *
 * The pane owns no state of its own worth saving: switching an Xtra off moves it into a
 * "(Disabled)" folder and deleting one puts it in the Trash, both of them at once and on disk. That
 * matters, because the preferences window only sends @c -closeView when the whole window closes:
 * a pane which held changes back until then would lose them the moment the user picks another pane.
 *
 * The set of installed Xtras is read from AIXtrasManager, which stays the one place that knows what
 * a category is. It is re-read whenever @c AIXtrasDidChangeNotification arrives, so an Xtra
 * installed from the web while this pane is on screen turns up in it.
 */
@interface AIXtrasPreferences : AIPreferencePane <AIXtraListViewDelegate> {
	//AIXtraListView, one per card; retained because the form releases its own reference on a rebuild
	NSMutableArray	*listViews;
	//Whether a rebuild is already on its way; see -xtrasChanged:
	BOOL			 rebuildScheduled;
}

@end
