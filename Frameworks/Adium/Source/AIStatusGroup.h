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

#import <Adium/AIStatusItem.h>

@class AIStatus;

/*!
 * @class AIStatusGroup
 * @brief The container the status controller keeps the saved statuses in
 *
 * Not a user concept any more, and no longer nestable: there is exactly one instance of this class
 * in a running Adium, the root group of AIStatusController, and the user never sees it. What used
 * to be a group in the status menu is gone; a status either sits in this container or it does not.
 *
 * The class stays because the root is load bearing in two ways which are easy to miss:
 *
 *   1. It <em>is</em> the save trigger. Every add, remove and replace ends in
 *      -containedStatusesChanged, and since the root has no containing group of its own that lands
 *      at [adium.statusController savedStatusesChanged]. Replacing the root with a plain array
 *      would silently drop the writing, without a single compiler warning.
 *   2. -[AIStatusItem setUniqueStatusID:] only reports a newly assigned ID when the item has a
 *      containing group. That report is what saves the ID, and the three automatic status settings
 *      know a status by nothing but its ID.
 *
 * So the root's containingStatusGroup must stay nil: a root placed inside anything would send its
 * saves to that container instead of to the status controller, and nothing would ever reach disk.
 *
 * This is a public header of the Adium framework. Shrinking it is source incompatible for any
 * consumer outside this tree; there is none.
 */
@interface AIStatusGroup : AIStatusItem {
	NSMutableArray		*containedStatusItems;
	NSMutableSet		*_flatStatusSet;
}

+ (id)statusGroup;
/*!
 * @brief A group holding @a inContainedObjects
 *
 * Still needed for the Adium 0.8x archive format, which stored a bare array where later versions
 * store the root's contents.
 */
+ (id)statusGroupWithContainedStatusItems:(NSArray *)inContainedObjects;

- (void)setContainedStatusItems:(NSArray *)inContainedStatusItems;

- (void)addStatusItem:(AIStatusItem *)inStatusItem atIndex:(NSUInteger)index;
- (void)removeStatusItem:(AIStatusItem *)inStatusItem;
- (void)replaceExistingStatusState:(AIStatus *)oldStatusState withStatusState:(AIStatus *)newStatusState;

- (NSArray *)containedStatusItems;
- (NSSet *)flatStatusSet;

+ (void)sortArrayOfStatusItems:(NSMutableArray *)inArray context:(void *)context;

@end
