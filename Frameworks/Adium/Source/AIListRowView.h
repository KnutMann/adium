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

@class AIListCell, AIProxyListObject, AIListOutlineView;

/*!
 * @brief Hands out the cell that knows how to draw one row
 *
 * There is one cell per kind of row, shared by every row of that kind, so it is
 * configured immediately before it draws. That is what the old
 * outlineView:willDisplayCell:forTableColumn:item: did, once per row, and it is
 * what the two views below ask for here.
 */
@protocol AIListCellSource <NSObject>
- (AIListCell *)listCellForProxyObject:(AIProxyListObject *)proxyObject
						 inOutlineView:(AIListOutlineView *)outlineView;
@end

/*!
 * @brief The row behind a contact or a group
 *
 * Carries the selection, which used to be painted for the whole table at once in
 * -[AIVariableHeightOutlineView highlightSelectionInClipRect:], and the drop
 * mark, which used to come out of private NSOutlineView methods.
 */
@interface AIListRowView : NSTableRowView

@property (nonatomic, weak) id<AIListCellSource> cellSource;
@property (nonatomic, weak) AIListOutlineView *listView;
@property (nonatomic, strong) AIProxyListObject *proxyObject;

@end

/*!
 * @brief The contents of one row
 *
 * The drawing itself still belongs to the cells; this view gives it a place to
 * happen that the table can reuse, hit test and read aloud.
 */
@interface AIListCellHostView : NSTableCellView

@property (nonatomic, weak) id<AIListCellSource> cellSource;
@property (nonatomic, weak) AIListOutlineView *listView;
@property (nonatomic, strong) AIProxyListObject *proxyObject;

@end
