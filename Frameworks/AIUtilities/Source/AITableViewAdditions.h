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

/*!
 * @class AISidebarCellView
 * @brief A source list row that keeps the text colours System Settings uses
 *
 * AppKit's automatic label colouring tints the selected row of a source list with the accent
 * colour once the list is not the focus, while System Settings keeps its labels plain and dims
 * every one of them, the selected one included, as soon as the window is no longer key. This view
 * takes the colours over.
 *
 * The built-in textField and imageView outlets stay empty on purpose: they are the handles the
 * source list style re-tints through, after everything here has run. A label AppKit has no outlet
 * to is a label it leaves alone, so sidebarLabel and sidebarIcon are the only way in.
 */
@interface AISidebarCellView : NSTableCellView {
	BOOL							isGroupRow;
	__unsafe_unretained NSTextField	*sidebarLabel;	//Owned by the view hierarchy
	__unsafe_unretained NSImageView	*sidebarIcon;	//Same
}
@property (assign) BOOL isGroupRow;
@property (assign) NSTextField *sidebarLabel;
@property (assign) NSImageView *sidebarIcon;
- (void)updateTextColors;
@end

/*!
 * @class AISidebarRowView
 * @brief A source list row that draws its own selection
 *
 * The unemphasised selection AppKit draws while the list is not the focus is paler than the one
 * System Settings shows; the pill is drawn here, deeper. Hand one out from rowViewForItem:.
 */
@interface AISidebarRowView : NSTableRowView
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
 * @brief The row that shows a small picture and a name side by side: a source list row
 *
 * A 16 point picture at the leading edge and the label after it, both centred in the row, in an
 * AISidebarCellView, which keeps its colours the way System Settings does whether or not the list
 * is the focus. Built once per column and reused; picture and text are set afresh on every call,
 * and nil for the picture leaves its place empty so the names still line up. Reach the label
 * through sidebarLabel: textField is empty on purpose, see the class.
 */
- (AISidebarCellView *)ai_iconLabelCellViewForColumn:(NSTableColumn *)tableColumn image:(NSImage *)image value:(id)value;

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
