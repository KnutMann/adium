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

/*!
 * @class AICheckboxTableCellView
 * @brief The cell view ai_checkboxCellViewForColumn:on:enabled:target:action: hands out
 */
@interface AICheckboxTableCellView : NSTableCellView
@property (nonatomic, strong) NSButton *checkbox;
@end

@interface NSTableView (AITableViewAdditions)
- (NSArray *)selectedItemsFromArray:(NSArray *)sourceArray;
- (void)selectItemsInArray:(NSArray *)selectedItems usingSourceArray:(NSArray *)sourceArray;

/*!
 * @brief The one row most lists need: a label, centred, in a standard cell view
 *
 * A table becomes view based the moment its delegate hands out views, and for a list of plain
 * text that view is always the same: an NSTableCellView with a text field as its label. Handed
 * to the table that way, the label is centred by layout, turned white on a selected row, and
 * recoloured for dark mode, all by the table itself. This builds that view once per column and
 * reuses it, so a delegate's whole job is to say what the text is.
 *
 * @param tableColumn The column the row is for; its identifier is the reuse identifier
 * @param value What to show: a string, or anything else, shown by its description. nil or
 *              NSNull show an empty label.
 * @return The cell view, ready to be returned from tableView:viewForTableColumn:row:
 */
- (NSTableCellView *)ai_labelCellViewForColumn:(NSTableColumn *)tableColumn value:(id)value;

/*!
 * @brief The one row a column of pictures needs: an image view, centred, in a standard cell view
 *
 * The companion of ai_labelCellViewForColumn:value: for the column that shows a picture beside
 * the text, a service icon or an emoticon say. The picture is scaled down to fit the row and
 * never up, and centred both ways. Built once per column and reused, like the label.
 *
 * @param tableColumn The column the row is for; its identifier is the reuse identifier
 * @param image What to show; nil shows nothing
 * @return The cell view, ready to be returned from tableView:viewForTableColumn:row:
 */
- (NSTableCellView *)ai_imageCellViewForColumn:(NSTableColumn *)tableColumn image:(NSImage *)image;

/*!
 * @brief The one row a column of checkboxes needs: a checkbox, centred, in a cell view
 *
 * For the column in which every row is switched on or off. The checkbox has no title; the
 * label column beside it says what the row is. It sends @a action to @a target when clicked, and
 * the handler finds the row it belongs to with -rowForView:. Built once per column and reused,
 * so state, enabled and target are set afresh on every call.
 *
 * @return An AICheckboxTableCellView, whose checkbox is at hand for an accessibility label
 */
- (AICheckboxTableCellView *)ai_checkboxCellViewForColumn:(NSTableColumn *)tableColumn
															on:(BOOL)on
													   enabled:(BOOL)enabled
														target:(id)target
														action:(SEL)action;
@end

@protocol AITableViewDelegate
@optional
- (void)tableViewDeleteSelectedRows:(NSTableView *)tableView;
- (NSMenu *)tableView:(NSTableView *)inTableView menuForEvent:(NSEvent *)theEvent;
@end
