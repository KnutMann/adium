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

- (instancetype)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		/* A row must not paint outside its row. Since macOS 14 a view does not
		 * hold its drawing inside its own frame unless it is told to, and a
		 * shape that reaches past the edge would land on the neighbour. */
		self.clipsToBounds = YES;
		/* One cell draws every row of its kind, pointed at the row in hand
		 * right before it draws. Two rows drawing at the same time would point
		 * it at two rows at once. */
		self.canDrawConcurrently = NO;
	}

	return self;
}

- (AIListCell *)cell
{
	return [self.cellSource listCellForProxyObject:self.proxyObject inOutlineView:self.listView];
}

/* The table's own ground, its background image and the alternating stripe are
 * all painted by the outline view in -drawBackgroundInClipRect:, for every row
 * at once, so there is nothing left for a single row to do here.
 *
 * And nothing to rub out either: wiping the row clean here takes the selection
 * with it, which is drawn into the same place right after. The row's contents
 * are rubbed out where they are drawn, in the view below. */
- (void)drawBackgroundInRect:(NSRect)dirtyRect
{
}

/*!
 * @brief The row was picked or let go
 *
 * The contents are written in a colour that answers to that, and they are drawn
 * in a view of their own, which a change of selection does not redraw by
 * itself. It did while both drew into one surface.
 */
- (void)setSelected:(BOOL)selected
{
	if (selected == self.isSelected) return;

	[super setSelected:selected];
	for (NSView *subview in self.subviews) [subview setNeedsDisplay:YES];
}

/*!
 * @brief The window this row is in came forward or went behind
 *
 * Same reason: the picked row is drawn in a paler colour then, and the ink on
 * it has to hold up against that.
 */
- (void)setEmphasized:(BOOL)emphasized
{
	if (emphasized == self.isEmphasized) return;

	[super setEmphasized:emphasized];
	for (NSView *subview in self.subviews) [subview setNeedsDisplay:YES];
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

- (instancetype)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		//As on the row view above, and for the same two reasons
		self.clipsToBounds = YES;
		self.canDrawConcurrently = NO;

		/* A surface of its own, and this is not decoration.
		 *
		 * Without it this view draws into the row view's, which the table hands
		 * on from one row to the next as the list changes. Nothing clears that
		 * surface in between: the row view paints no background, because the
		 * ground and the stripe belong to the table and are painted behind all
		 * of the rows at once. So the name of the row this view held before
		 * stayed where it was and the new one was drawn over it, two names in
		 * one line, until something redrew the whole table. Measured after it
		 * was reported from the running program, on a list filling up as an
		 * account signed on.
		 *
		 * Clearing the surface here instead was tried and is wrong: it is the
		 * row view's surface, and the selection it had just drawn went with it.
		 */
		self.wantsLayer = YES;
		self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
	}

	return self;
}

/* The cells count downwards, the way the outline view they were written for
 * does. */
- (BOOL)isFlipped
{
	return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
	/* Nothing is rubbed out first. Tried and reverted: a clear fill with the
	 * copy operation does wipe out whatever this view held for the row before,
	 * but this view and the row view under it share one drawing surface, so it
	 * also wipes out the selection the row view has just drawn. What keeps one
	 * row's drawing off its neighbour is the clipping set up above. */
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
