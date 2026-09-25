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
#import <Adium/AIListObject.h>
#import <Adium/AIListOutlineView.h>
#import <Adium/AIProxyListObject.h>
#import <Adium/ESDebugAILog.h>

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

/*!
 * @brief A click on a row is a click on the row, not a grip on the window
 *
 * The contact list window can be dragged by its background, and a view that does
 * not fill itself opaquely counts as background unless it says otherwise. The
 * table itself has always said otherwise; the views that now sit in front of it
 * inherited the default and had not, so a press on a group could be taken for
 * the start of a window drag and the click that should have folded the group
 * went nowhere. Which is why it sometimes took two.
 */
- (BOOL)mouseDownCanMoveWindow
{
	return NO;
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

//As on the row view above, and for the same reason
- (BOOL)mouseDownCanMoveWindow
{
	return NO;
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

#pragma mark -

/*!
 * @brief The tape measure described in the header
 */
@implementation AIListOutlineView (AIListProbe)

+ (void)ai_collectListViewsUnder:(NSView *)view into:(NSMutableArray *)found
{
	if ([view isKindOfClass:[AIListOutlineView class]]) [found addObject:view];
	for (NSView *subview in view.subviews) [self ai_collectListViewsUnder:subview into:found];
}

+ (NSArray *)ai_listViewsOnScreen
{
	NSMutableArray *found = [NSMutableArray array];
	for (NSWindow *window in [NSApp windows]) {
		if (window.contentView) [self ai_collectListViewsUnder:window.contentView into:found];
	}

	return found;
}

/*!
 * @brief What the row views are, against what the table says they should be
 *
 * @param outComplaints How many rows did not match. Nothing wrong means the rows
 *                      are innocent and the pixels are to blame.
 */
- (NSString *)ai_probeReport:(NSString *)occasion complaints:(NSUInteger *)outComplaints
{
	NSWindow *window = self.window;
	NSMutableArray *rows = [NSMutableArray array];
	for (NSView *subview in self.subviews) {
		if ([subview isKindOfClass:[AIListRowView class]]) [rows addObject:subview];
	}

	NSMutableString *complaints = [NSMutableString string];
	NSUInteger count = 0;

	for (AIListRowView *row in rows) {
		NSInteger index = [self rowForView:row];
		NSString *held = row.proxyObject.cachedDisplayNameString ?: row.proxyObject.key ?: @"(nichts)";

		if (index < 0 || index >= self.numberOfRows) {
			[complaints appendFormat:@"    ohne Zeile, aber im Baum: \"%@\" bei %@\n",
			 held, NSStringFromRect(row.frame)];
			count++;
			continue;
		}

		AIProxyListObject *item = [self itemAtRow:index];
		NSRect wanted = [self rectOfRow:index];

		if (item != row.proxyObject) {
			[complaints appendFormat:@"    Zeile %ld haelt \"%@\", die Tabelle sagt \"%@\"\n",
			 (long)index, held, item.cachedDisplayNameString ?: item.key ?: @"(nichts)"];
			count++;
		}
		if (!NSEqualRects(wanted, row.frame)) {
			[complaints appendFormat:@"    Zeile %ld (\"%@\") steht bei %@, gehoert nach %@\n",
			 (long)index, held, NSStringFromRect(row.frame), NSStringFromRect(wanted)];
			count++;
		}
	}

	//Two rows sharing a strip of the window is the reported picture itself
	for (NSUInteger i = 0; i < rows.count; i++) {
		for (NSUInteger j = i + 1; j < rows.count; j++) {
			NSRect a = [rows[i] frame], b = [rows[j] frame];
			if (!NSIsEmptyRect(a) && !NSIsEmptyRect(b) && NSIntersectsRect(a, b)) {
				[complaints appendFormat:@"    zwei Zeilen uebereinander: %@ und %@\n",
				 NSStringFromRect(a), NSStringFromRect(b)];
				count++;
			}
		}
	}

	AIListRowView *sample = rows.firstObject;
	NSView *content = sample.subviews.firstObject;

	NSMutableString *report = [NSMutableString stringWithFormat:@"Kontaktliste vermessen (%@)\n", occasion];
	[report appendFormat:@"  Fenster: undurchsichtig=%d, Deckkraft=%.2f, am Hintergrund verschiebbar=%d\n",
	 (int)window.isOpaque, window.alphaValue, (int)window.movableByWindowBackground];
	[report appendFormat:@"  Tabelle: %@ sichtbar %@, %ld Zeilen, Schicht=%d\n",
	 NSStringFromRect(self.frame), NSStringFromRect(self.visibleRect),
	 (long)self.numberOfRows, (int)(self.layer != nil)];
	[report appendFormat:@"  Zeilenansichten im Baum: %lu, Schicht Zeile=%d Inhalt=%d\n",
	 (unsigned long)rows.count, (int)(sample.layer != nil), (int)(content.layer != nil)];

	if (count) {
		[report appendFormat:@"  %lu Beanstandungen:\n%@", (unsigned long)count, complaints];
	} else {
		[report appendString:@"  Alle Zeilen sitzen richtig und halten das Richtige.\n"];
	}

	if (outComplaints) *outComplaints = count;

	return report;
}

- (void)ai_logProbeAlways:(NSString *)occasion
{
	AILogWithSignature(@"%@", [self ai_probeReport:occasion complaints:NULL]);
}

/*!
 * @brief Measure, and write it down only if something is wrong
 *
 * A hundred contacts arriving must not fill the log with a hundred clean bills
 * of health.
 */
- (void)ai_logProbeIfWrong:(NSString *)occasion
{
	NSUInteger complaints = 0;
	NSString *report = [self ai_probeReport:occasion complaints:&complaints];
	if (!complaints) return;

	/* Say what is wrong, then try the one cure that follows from it and say
	 * whether it took. A row that sits where it does not belong is a row the
	 * table has not laid out since the heights it lays out from changed, so the
	 * table is told they changed. If the rows are right afterwards, that was the
	 * cause; if they are not, this line says so and the hunt goes on. */
	AILogWithSignature(@"%@", report);

	[self noteHeightOfRowsWithIndexesChanged:
	 [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.numberOfRows)]];

	NSUInteger after = 0;
	NSString *second = [self ai_probeReport:@"nachdem die Hoehen neu gemeldet wurden" complaints:&after];
	if (after) {
		AILogWithSignature(@"Die Hoehen neu zu melden hat nicht gereicht:\n%@", second);
	} else {
		AILogWithSignature(@"Die Hoehen neu zu melden hat die Zeilen an ihren Platz gebracht");
	}
}

- (void)ai_scheduleProbes:(NSString *)occasion
{
	if (!AIDebugLoggingEnabled) return;

	[self ai_logProbeIfWrong:[occasion stringByAppendingString:@", sofort"]];

	/* The overlap was reported to stand for about a second and then go away by
	 * itself, so these two say whether it healed, and they are coalesced: the
	 * strings are fixed so the earlier request can be called off. */
	static NSString * const soon = @"kurz nach der letzten Aenderung";
	static NSString * const later = @"eine Sekunde nach der letzten Aenderung";

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(ai_logProbeIfWrong:) object:soon];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(ai_logProbeIfWrong:) object:later];
	[self performSelector:@selector(ai_logProbeIfWrong:) withObject:soon afterDelay:0.3];
	[self performSelector:@selector(ai_logProbeIfWrong:) withObject:later afterDelay:1.0];
}

@end
