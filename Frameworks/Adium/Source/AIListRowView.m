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

#import <Adium/AIListRowView.h>
#import <Adium/AIListCell.h>
#import <Adium/AIListOutlineView.h>
#import <Adium/AIProxyListObject.h>

@implementation AIListRowView

- (AIListCell *)cell
{
	return [self.cellSource listCellForProxyObject:self.proxyObject inOutlineView:self.listView];
}

/* The table's own ground, its background image and the alternating stripe are
 * all painted by the outline view in -drawBackgroundInClipRect:, for every row
 * at once, so there is nothing left for a single row to do here. */
- (void)drawBackgroundInRect:(NSRect)dirtyRect
{
}

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
	AIListOutlineView *listView = self.listView;
	if (!listView) return;

	/* The square highlight, which the bubble and Mockie layouts switch off
	 * because they draw a shape of their own instead. */
	if ([listView drawsSelectedRowHighlight] &&
		(![listView drawHighlightOnlyWhenMain] || listView.window.isMainWindow)) {
		if (listView.window.firstResponder != listView || !listView.window.isKeyWindow) {
			[[NSColor unemphasizedSelectedContentBackgroundColor] set];
		} else {
			[[NSColor selectedContentBackgroundColor] set];
		}
		NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
	}

	[[self cell] _drawHighlightWithFrame:self.bounds inView:listView];
}

- (void)drawDraggingDestinationFeedbackInRect:(NSRect)dirtyRect
{
	[[self cell] drawDropHighlightWithFrame:self.bounds];
}

@end

@implementation AIListCellHostView

/* The cells count downwards, the way the outline view they were written for
 * does. */
- (BOOL)isFlipped
{
	return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
	AIListCell *cell = [self.cellSource listCellForProxyObject:self.proxyObject inOutlineView:self.listView];
	[cell drawWithFrame:self.bounds inView:self.listView];
}

#pragma mark Accessibility

- (NSAccessibilityRole)accessibilityRole
{
	return NSAccessibilityStaticTextRole;
}

- (NSString *)accessibilityLabel
{
	return [[self.cellSource listCellForProxyObject:self.proxyObject inOutlineView:self.listView] labelString];
}

- (id)accessibilityValue
{
	return [[self.cellSource listCellForProxyObject:self.proxyObject inOutlineView:self.listView] spokenDescription];
}

@end
