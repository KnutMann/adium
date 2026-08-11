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

#import "AIXtraListView.h"
#import "AIXtraInfo.h"
#import <Adium/AISettingsFormView.h>
/* -[NSTableView menuForEvent:] hands the event to its delegate; that is what gets a row's context
 * menu built here rather than in a subclass of the table. */
#import <AIUtilities/AITableViewAdditions.h>

//Identifier of the single, full width column and of the reusable row view
#define XTRA_COLUMN_IDENTIFIER		@"xtra"
#define XTRA_CELL_IDENTIFIER		@"AIXtraListCell"

/* Horizontal margin the settings form leaves inside its cards, mirrored here so a row's hairline
 * ends where every other pane's does. */
#define SEPARATOR_CARD_MARGIN		16.0f

//Metrics of a single Xtra row, System Settings style
#define MINIMUM_ROW_HEIGHT			44.0f
#define ROW_V_PADDING				 6.0f		//Space above the name and below the detail line
#define NAME_DETAIL_SPACING			 1.0f
#define NAME_FONT_SIZE				13.0f
#define DETAIL_FONT_SIZE			11.0f
#define CELL_H_PADDING				10.0f		//Leading/trailing padding inside a row
#define XTRA_ICON_SIZE				32.0f
#define XTRA_ICON_GAP				10.0f		//Space between the icon and the text
#define CONTROL_GAP					10.0f		//Space around the switch
#define DISABLED_ICON_ALPHA			 0.5f		//How far a switched off Xtra's icon recedes

//Room the inset table style claims; measured off the table itself as soon as it has tiled once
#define INSET_STYLE_MARGIN			32.0f
#define INSET_STYLE_PADDING			10.0f

/*!
 * @brief Create a non-editable, non-bordered label
 */
static NSTextField *AIXtraListLabel(CGFloat fontSize, NSColor *textColor)
{
	NSTextField *label = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];

	[label setTranslatesAutoresizingMaskIntoConstraints:NO];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBezeled:NO];
	[label setBordered:NO];
	[label setDrawsBackground:NO];
	[label setRefusesFirstResponder:YES];
	[label setFont:[NSFont systemFontOfSize:fontSize]];
	[label setTextColor:textColor];
	[[label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
	[label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
									forOrientation:NSLayoutConstraintOrientationHorizontal];
	[label setStringValue:@""];

	return label;
}

/*!
 * @brief Height of every row of every Xtra list
 *
 * Unlike an account row, an Xtra row is always exactly two lines tall: a name and a line of detail
 * which is never allowed to be empty. So the height is a property of the fonts rather than of the
 * row, and it is measured once instead of per row and per width - which is also what lets a list
 * report its own height without laying a single row out.
 */
static CGFloat AIXtraRowHeight(void)
{
	static CGFloat rowHeight = 0.0f;

	if (rowHeight <= 0.0f) {
		NSTextField	*nameField = AIXtraListLabel(NAME_FONT_SIZE, [NSColor labelColor]);
		NSTextField	*detailField = AIXtraListLabel(DETAIL_FONT_SIZE, [NSColor secondaryLabelColor]);

		//A single space, so the cell measures a line rather than nothing at all
		[nameField setStringValue:@" "];
		[detailField setStringValue:@" "];

		CGFloat		textHeight = (ceil([[nameField cell] cellSize].height) +
								  NAME_DETAIL_SPACING +
								  ceil([[detailField cell] cellSize].height));

		rowHeight = ceil(MAX(MAX(MINIMUM_ROW_HEIGHT, XTRA_ICON_SIZE + 2.0f * ROW_V_PADDING),
							 textHeight + 2.0f * ROW_V_PADDING));
	}

	return rowHeight;
}

/*!
 * @class AIXtraListCellView
 * @brief View based row of an Xtra list
 *
 * Layout: [icon] [name / detail line] [switch] [⊖], with a hairline along the bottom edge. All
 * subviews are owned by the view hierarchy; the properties below are non-retaining references for
 * convenience (manual retain/release).
 *
 * Private to the list on purpose: no pane ever builds one, and nothing outside this file has any
 * business knowing what an Xtra row is made of.
 */
@interface AIXtraListCellView : NSTableCellView
@property (nonatomic, assign) NSTextField		*detailField;
@property (nonatomic, assign) NSSwitch			*enabledSwitch;
@property (nonatomic, assign) NSButton			*removeButton;
@property (nonatomic, assign) NSBox				*separator;
@property (nonatomic, retain) NSLayoutConstraint *separatorTrailingConstraint;
@property (nonatomic, assign) BOOL				 dimmed;
/* Drawn behind the row while its context menu is open: with no selection, this is the only thing
 * which says which Xtra "Move to Trash" is about to ask about. */
@property (nonatomic, assign) BOOL				 contextHighlighted;
- (void)updateTextColors;
@end

@interface AIXtraListView ()
- (void)configureList;
- (void)synchronizeColumnWidth;
- (CGFloat)rowInsetPerSide;
- (void)listFrameChanged:(NSNotification *)notification;
- (void)relayoutRows;
- (void)updateHeight;
- (void)configureCellView:(AIXtraListCellView *)cellView forRow:(NSInteger)row;
- (void)refreshRow:(NSInteger)row;
- (void)setContextMenuRow:(NSInteger)row;
- (AIXtraInfo *)xtraAtRow:(NSInteger)row;
- (BOOL)xtraIsUsers:(AIXtraInfo *)xtraInfo;
- (NSString *)detailLineForXtra:(AIXtraInfo *)xtraInfo;
- (NSMenu *)menuForRow:(NSInteger)row;
- (void)deleteXtra:(AIXtraInfo *)xtraInfo;
@end

@implementation AIXtraListCellView

- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		[self setIdentifier:XTRA_CELL_IDENTIFIER];

		//The Xtra's icon
		NSImageView *iconView = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
		[iconView setTranslatesAutoresizingMaskIntoConstraints:NO];
		[iconView setImageScaling:NSImageScaleProportionallyUpOrDown];
		[iconView setEditable:NO];
		//The name right next to it says everything the icon says; don't read it twice
		[iconView setAccessibilityElement:NO];
		[self addSubview:iconView];
		[self setImageView:iconView];

		//Container holding the two lines of text, vertically centered as a block
		NSView *textContainer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
		[textContainer setTranslatesAutoresizingMaskIntoConstraints:NO];
		[self addSubview:textContainer];

		//Name of the Xtra
		NSTextField *nameField = AIXtraListLabel(NAME_FONT_SIZE, [NSColor labelColor]);
		[textContainer addSubview:nameField];
		[self setTextField:nameField];

		//Version, origin and state
		NSTextField *detailField = AIXtraListLabel(DETAIL_FONT_SIZE, [NSColor secondaryLabelColor]);
		[textContainer addSubview:detailField];
		[self setDetailField:detailField];

		//Enabled switch
		NSSwitch *enabledSwitch = [[[NSSwitch alloc] initWithFrame:NSZeroRect] autorelease];
		//System Settings uses the small switch, not the regular one
		[enabledSwitch setControlSize:NSControlSizeSmall];
		[enabledSwitch setTranslatesAutoresizingMaskIntoConstraints:NO];
		[self addSubview:enabledSwitch];
		[self setEnabledSwitch:enabledSwitch];

		/* The ⊖ which throws the Xtra away. Built by the settings form's factory, so it is the same
		 * control as the (i) of an account row - down to its tint and its size, which is read back
		 * here rather than repeated as a number of our own. */
		NSButton *removeButton = [AISettingsFormView inlineSymbolButtonWithSymbolName:@"minus.circle"
																   fallbackImageName:@"remove"
																			  target:nil
																			  action:NULL];
		NSSize	 removeButtonSize = [removeButton frame].size;

		[removeButton setTranslatesAutoresizingMaskIntoConstraints:NO];
		[self addSubview:removeButton];
		[self setRemoveButton:removeButton];

		//Hairline separating this row from the next one
		NSBox *separator = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
		[separator setTranslatesAutoresizingMaskIntoConstraints:NO];
		[separator setBoxType:NSBoxSeparator];
		[self addSubview:separator];
		[self setSeparator:separator];

		/* The hairline runs past the trailing edge of the cell all the way to the card's edge, the
		 * way System Settings draws it. How far that is depends on the table's style, so the list
		 * sets the constant; see -[AIXtraListView rowInsetPerSide]. */
		NSLayoutConstraint *separatorTrailing = [[separator trailingAnchor] constraintEqualToAnchor:[self trailingAnchor]];
		[self setSeparatorTrailingConstraint:separatorTrailing];

		[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
			//Icon
			[[iconView leadingAnchor] constraintEqualToAnchor:[self leadingAnchor] constant:CELL_H_PADDING],
			[[iconView centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
			[[iconView widthAnchor] constraintEqualToConstant:XTRA_ICON_SIZE],
			[[iconView heightAnchor] constraintEqualToConstant:XTRA_ICON_SIZE],

			//Remove button
			[[removeButton trailingAnchor] constraintEqualToAnchor:[self trailingAnchor] constant:-CELL_H_PADDING],
			[[removeButton centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
			[[removeButton widthAnchor] constraintEqualToConstant:removeButtonSize.width],
			[[removeButton heightAnchor] constraintEqualToConstant:removeButtonSize.height],

			//Switch
			[[enabledSwitch trailingAnchor] constraintEqualToAnchor:[removeButton leadingAnchor] constant:-CONTROL_GAP],
			[[enabledSwitch centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],

			//Text block
			[[textContainer leadingAnchor] constraintEqualToAnchor:[iconView trailingAnchor] constant:XTRA_ICON_GAP],
			[[textContainer trailingAnchor] constraintEqualToAnchor:[enabledSwitch leadingAnchor] constant:-CONTROL_GAP],
			[[textContainer centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],

			//Name
			[[nameField topAnchor] constraintEqualToAnchor:[textContainer topAnchor]],
			[[nameField leadingAnchor] constraintEqualToAnchor:[textContainer leadingAnchor]],
			[[nameField trailingAnchor] constraintEqualToAnchor:[textContainer trailingAnchor]],

			//Detail line
			[[detailField topAnchor] constraintEqualToAnchor:[nameField bottomAnchor] constant:NAME_DETAIL_SPACING],
			[[detailField leadingAnchor] constraintEqualToAnchor:[textContainer leadingAnchor]],
			[[detailField trailingAnchor] constraintEqualToAnchor:[textContainer trailingAnchor]],
			[[detailField bottomAnchor] constraintEqualToAnchor:[textContainer bottomAnchor]],

			//Separator
			[[separator leadingAnchor] constraintEqualToAnchor:[textContainer leadingAnchor]],
			separatorTrailing,
			[[separator bottomAnchor] constraintEqualToAnchor:[self bottomAnchor]],
			[[separator heightAnchor] constraintEqualToConstant:1.0f],
			nil]];
	}

	return self;
}

- (void)dealloc
{
	[_separatorTrailingConstraint release];
	[super dealloc];
}

/*!
 * @brief Only the switch and the ⊖ swallow clicks
 *
 * Everything else is handed to the table view so that a right click anywhere on the row - including
 * on one of those two controls, neither of which supplies a context menu - still reaches the row's
 * own menu.
 */
- (NSView *)hitTest:(NSPoint)aPoint
{
	NSView *hitView = [super hitTest:aPoint];

	if (!hitView) return nil;

	NSEvent		*currentEvent = [NSApp currentEvent];
	NSEventType	 eventType = [currentEvent type];
	BOOL		 contextClick = ((eventType == NSEventTypeRightMouseDown) ||
								 (eventType == NSEventTypeRightMouseUp) ||
								 (((eventType == NSEventTypeLeftMouseDown) || (eventType == NSEventTypeLeftMouseUp)) &&
								  (([currentEvent modifierFlags] & NSEventModifierFlagControl) != 0)));

	if (!contextClick &&
		(hitView == [self enabledSwitch] || [hitView isDescendantOf:[self enabledSwitch]] ||
		 hitView == [self removeButton] || [hitView isDescendantOf:[self removeButton]])) {
		return hitView;
	}

	return self;
}

/*!
 * @brief Let the table view (and therefore the list) supply the context menu
 */
- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
	NSView *view = [self superview];

	while (view && ![view isKindOfClass:[NSTableView class]]) {
		view = [view superview];
	}

	if (view) return [view menuForEvent:theEvent];

	return [super menuForEvent:theEvent];
}

- (void)setDimmed:(BOOL)inDimmed
{
	_dimmed = inDimmed;
	[self updateTextColors];
}

- (void)setContextHighlighted:(BOOL)inHighlighted
{
	if (_contextHighlighted == inHighlighted) return;

	_contextHighlighted = inHighlighted;
	[self setNeedsDisplay:YES];
}

/*!
 * @brief Draw the context menu highlight
 *
 * A row is not selectable, so nothing else ever marks one. The shape is the one a list in System
 * Settings uses: the full width of the row, rounded, in the unemphasized selection color - the row
 * is pointed out, not selected.
 */
- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];

	if (!_contextHighlighted) return;

	NSBezierPath	*highlight = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self bounds], 0.0f, 1.0f)
																 xRadius:6.0f
																 yRadius:6.0f];

	[[NSColor unemphasizedSelectedContentBackgroundColor] set];
	[highlight fill];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
	[super setBackgroundStyle:backgroundStyle];
	[self updateTextColors];
}

- (void)updateTextColors
{
	BOOL emphasized = ([self backgroundStyle] == NSBackgroundStyleEmphasized);

	[[self textField] setTextColor:(emphasized ?
									[NSColor alternateSelectedControlTextColor] :
									(_dimmed ? [NSColor secondaryLabelColor] : [NSColor labelColor]))];
	[[self detailField] setTextColor:(emphasized ?
									  [NSColor alternateSelectedControlTextColor] :
									  [NSColor secondaryLabelColor])];
	[[self removeButton] setContentTintColor:(emphasized ?
											  [NSColor alternateSelectedControlTextColor] :
											  [NSColor secondaryLabelColor])];
}

@end

@implementation AIXtraListView

- (id)initWithXtras:(NSArray *)inXtras
{
	/* Any width will do: the settings form hands the list the width of its card before it is ever
	 * drawn, and the height is recomputed from the rows right below. */
	if ((self = [super initWithFrame:NSMakeRect(0.0f, 0.0f, 400.0f, AIXtraRowHeight())])) {
		xtras = [inXtras copy];
		/* Only an Xtra of this user's own folder can be moved into a "(Disabled)" folder beside it;
		 * everything else lives somewhere we may well not be allowed to write. */
		userDirectory = [[[adium applicationSupportDirectory] stringByStandardizingPath] retain];
		cachedLayoutWidth = 0.0f;
		columnMargin = INSET_STYLE_MARGIN;
		contextMenuRow = -1;
		layoutScheduled = NO;

		[self configureList];
		[self updateHeight];
	}

	return self;
}

- (void)dealloc
{
	[self tearDown];

	[xtras release];
	[userDirectory release];

	[super dealloc];
}

/*!
 * @brief Build the table and turn the scroll view into a plain container
 */
- (void)configureList
{
	tableView = [[[NSTableView alloc] initWithFrame:[self bounds]] autorelease];

	[tableView setDataSource:self];
	[tableView setDelegate:self];
	[tableView setIntercellSpacing:NSZeroSize];
	[tableView setHeaderView:nil];
	[tableView setCornerView:nil];
	[tableView setGridStyleMask:NSTableViewGridNone];
	[tableView setUsesAlternatingRowBackgroundColors:NO];
	[tableView setBackgroundColor:[NSColor clearColor]];
	[tableView setRowSizeStyle:NSTableViewRowSizeStyleCustom];
	/* Rows are not selectable: every action a row offers sits on the row itself - its switch, its
	 * ⊖, its context menu. -tableView:shouldSelectRow: is what refuses the selection; the highlight
	 * style is left alone all the same, because NSTableViewSelectionHighlightStyleNone also turns
	 * off the feedback a drag draws. */
	[tableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
	[tableView setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[tableView setAllowsMultipleSelection:NO];
	[tableView setAllowsEmptySelection:YES];
	[tableView setAllowsColumnReordering:NO];
	//The single column has to follow the width of the table; without a header the user can't drag it anyway
	[tableView setAllowsColumnResizing:YES];
	[tableView setFocusRingType:NSFocusRingTypeNone];
	[tableView setAutoresizingMask:NSViewWidthSizable];
	if (@available(macOS 11.0, *)) {
		[tableView setStyle:NSTableViewStyleInset];
	}

	NSTableColumn *xtraColumn = [[[NSTableColumn alloc] initWithIdentifier:XTRA_COLUMN_IDENTIFIER] autorelease];
	[xtraColumn setResizingMask:NSTableColumnAutoresizingMask];
	[xtraColumn setEditable:NO];
	[xtraColumn setMinWidth:80.0f];
	[xtraColumn setMaxWidth:10000.0f];
	//The table tiles the column to the width the inset style leaves over; start out with that width
	[xtraColumn setWidth:(NSWidth([tableView bounds]) - INSET_STYLE_MARGIN)];
	[tableView addTableColumn:xtraColumn];

	/* The list does not scroll: it is as tall as its rows and the preferences column scrolls
	 * instead. The scroll view stays - a table view outside of one loses its tiling and its
	 * enclosing clip view - but it never scrolls anything: no scrollers, no elasticity, which also
	 * lets the scroll wheel through to the column behind us.
	 *
	 * The card around the list is drawn by AISettingsFormView, so nothing here draws a background
	 * of its own; the form also rounds our corners to the card's radius. */
	[self setDocumentView:tableView];
	[self setBorderType:NSNoBorder];
	[self setDrawsBackground:NO];
	[self setHasVerticalScroller:NO];
	[self setHasHorizontalScroller:NO];
	[self setVerticalScrollElasticity:NSScrollElasticityNone];
	[self setHorizontalScrollElasticity:NSScrollElasticityNone];
	[self setAutomaticallyAdjustsContentInsets:NO];
	[self setContentInsets:NSEdgeInsetsZero];
	[self setAutoresizingMask:NSViewNotSizable];

	/* The column and the hairlines follow the width the card gives us, so we have to hear about it
	 * changing. Starting out at zero rather than at the width we happen to have right now
	 * guarantees that the first real width the form hands us counts as a change. */
	[tableView setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(listFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:tableView];
}

#pragma mark Contents

- (NSArray *)xtras
{
	return xtras;
}

- (void)setXtras:(NSArray *)inXtras
{
	if (xtras == inXtras) return;

	[xtras release];
	xtras = [inXtras copy];

	contextMenuRow = -1;

	[tableView reloadData];
	[self updateHeight];
}

- (id<AIXtraListViewDelegate>)listDelegate
{
	return listDelegate;
}

- (void)setListDelegate:(id<AIXtraListViewDelegate>)inDelegate
{
	listDelegate = inDelegate;
}

- (AIXtraInfo *)xtraAtRow:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[xtras count]) return nil;

	return [xtras objectAtIndex:row];
}

- (void)tearDown
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSViewFrameDidChangeNotification
												  object:tableView];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(relayoutRows) object:nil];
	layoutScheduled = NO;
	contextMenuRow = -1;

	/* Delegate, data source and the target of every row's controls are non-retaining references;
	 * the form owns our views and may outlive the pane by a moment, so cut them all now. */
	listDelegate = nil;
	[tableView setDelegate:nil];
	[tableView setDataSource:nil];
	[tableView setTarget:nil];
}

#pragma mark Geometry

/*!
 * @brief The height the list needs to show every row without scrolling
 *
 * The sum of the row heights plus the table's intercell spacing per row, plus the room the table
 * style keeps above the first and below the last row - NSTableViewStyleInset keeps 10pt at each
 * end, and leaving that out is exactly what makes a card too short for its list. That padding is
 * measured off the table rather than assumed, as soon as the table has a row to measure it on.
 *
 * The table then gets the last word through its row rects, so a layout we did not predict still
 * cannot end up with less room than the table laid itself out in. An empty list still gets one
 * row's worth of height so its card cannot collapse into a line.
 */
- (CGFloat)requiredHeight
{
	CGFloat		spacing = [tableView intercellSpacing].height;
	NSInteger	tableRows = [tableView numberOfRows];
	CGFloat		endPadding = INSET_STYLE_PADDING;

	if (tableRows > 0) {
		CGFloat		topInset = NSMinY([tableView rectOfRow:0]);

		if (topInset >= 0.0f) endPadding = topInset;
	}

	CGFloat		height = ((CGFloat)[xtras count] * (AIXtraRowHeight() + spacing)) + (2.0f * endPadding);

	if (tableRows > 0 && tableRows == (NSInteger)[xtras count]) {
		CGFloat		contentHeight = NSMaxY([tableView rectOfRow:(tableRows - 1)]) + endPadding;

		if (contentHeight > height) height = contentHeight;
	}

	CGFloat		minimumHeight = AIXtraRowHeight() + (2.0f * endPadding);

	return ceil(height < minimumHeight ? minimumHeight : height);
}

/*!
 * @brief Grow or shrink to fit our rows and tell the owner about it
 *
 * The list is the edge to edge row of a card, so its height is the card's height. The delegate
 * passes the news on to the settings form, which resizes the card and itself, and the preferences
 * window - which watches the pane's frame - resizes its scrolling column in turn.
 */
- (void)updateHeight
{
	CGFloat		height = [self requiredHeight];

	if (fabs(NSHeight([self frame]) - height) < 0.5f) return;

	[self setFrameSize:NSMakeSize(NSWidth([self frame]), height)];

	if ([listDelegate respondsToSelector:@selector(xtraListViewDidChangeHeight:)]) {
		[listDelegate xtraListViewDidChangeHeight:self];
	}
}

/*!
 * @brief Keep the single column as wide as the room the list has
 *
 * A table does not reliably re-tile its columns when it is widened, and a column left behind lays
 * every row out narrower than the card - which puts the switch and the ⊖ in the middle of the row
 * and stops the hairline short of the card's edge. A column left <em>wider</em> than the clip view
 * is worse still, because the list has no scrollers and the trailing end of every row would then
 * simply be unreachable. So the column is set from the width of the clip view rather than left to
 * the table, and the margin the table style wants around it is measured off the table itself.
 */
- (void)synchronizeColumnWidth
{
	NSTableColumn	*xtraColumn = [tableView tableColumnWithIdentifier:XTRA_COLUMN_IDENTIFIER];
	CGFloat			 clipWidth = NSWidth([[self contentView] bounds]);

	if (!xtraColumn || clipWidth <= 0.0f) return;

	CGFloat			 tableWidth = NSWidth([tableView bounds]);
	CGFloat			 observedMargin = tableWidth - [xtraColumn width];

	/* While the table is tiled to its clip view, whatever it keeps beside its column is the truth
	 * about this table style on this system; remember it instead of assuming 16pt per side. */
	if ((fabs(tableWidth - clipWidth) < 0.5f) &&
		(observedMargin >= 0.0f) && (observedMargin <= (INSET_STYLE_MARGIN * 2.0f))) {
		columnMargin = observedMargin;
	}

	CGFloat			 targetWidth = clipWidth - columnMargin;

	if (targetWidth < [xtraColumn minWidth]) targetWidth = [xtraColumn minWidth];

	if (fabs([xtraColumn width] - targetWidth) > 0.5f) [xtraColumn setWidth:targetWidth];
}

/*!
 * @brief How far the inset table style keeps a row away from the edge of the card
 */
- (CGFloat)rowInsetPerSide
{
	NSTableColumn	*xtraColumn = [tableView tableColumnWithIdentifier:XTRA_COLUMN_IDENTIFIER];
	CGFloat			 tableWidth = NSWidth([tableView bounds]);
	CGFloat			 columnWidth = (xtraColumn ? [xtraColumn width] : 0.0f);

	if (tableWidth <= 0.0f || columnWidth <= 0.0f) return 0.0f;

	CGFloat			 inset = floor((tableWidth - columnWidth) / 2.0f);

	//A column wider than the table (mid-tiling) must never push the hairline the other way
	return (inset > 0.0f ? inset : 0.0f);
}

/*!
 * @brief The available width changed; the column and the hairlines follow it
 */
- (void)listFrameChanged:(NSNotification *)notification
{
	CGFloat		width = NSWidth([tableView bounds]);

	if (fabs(width - cachedLayoutWidth) < 1.0f) return;

	cachedLayoutWidth = width;

	/* We may be inside the table's own layout pass, so act once the run loop comes back around - in
	 * the common modes rather than the default one, so a width handed to us while the window is
	 * being resized is not left unacted upon until the drag ends.
	 *
	 * A pass which is already scheduled is left alone rather than cancelled and queued again: it
	 * reads the width when it runs, so it is up to date whatever happened in between. */
	if (layoutScheduled) return;

	layoutScheduled = YES;
	[self performSelector:@selector(relayoutRows)
			   withObject:nil
			   afterDelay:0.0
				  inModes:[NSArray arrayWithObject:(NSString *)NSRunLoopCommonModes]];
}

/*!
 * @brief Re-tile the column and rebuild the visible rows for the new width
 *
 * Row heights are constant, so nothing has to be recalculated; the rows on screen are simply
 * reconfigured in place, which is what moves their hairlines out to the card's new edge.
 */
- (void)relayoutRows
{
	layoutScheduled = NO;

	[self synchronizeColumnWidth];
	//The end padding only becomes measurable once the table has tiled, so the height may still move
	[self updateHeight];

	[tableView enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
		[self refreshRow:row];
	}];
}

#pragma mark Row contents

/*!
 * @brief Whether @a xtraInfo lives in this user's own Xtras folder
 *
 * Only those can be switched on and off here: everything else sits in /Library or on a server,
 * where Adium has no business creating a "(Disabled)" folder of its own.
 */
- (BOOL)xtraIsUsers:(AIXtraInfo *)xtraInfo
{
	NSString	*path = [[xtraInfo path] stringByStandardizingPath];

	if (![userDirectory length] || ![path length]) return NO;

	return [path hasPrefix:[userDirectory stringByAppendingString:@"/"]];
}

/*!
 * @brief The second line of a row: version, origin and state, joined by " · "
 *
 * Never empty. An Xtra which is none of the above - a lone .ListLayout plist, an old sound set
 * folder - falls back to its filename extension, so that every row of a list is two lines tall and
 * the row height stays the constant AIXtraRowHeight() promises it is.
 */
- (NSString *)detailLineForXtra:(AIXtraInfo *)xtraInfo
{
	NSMutableArray	*parts = [NSMutableArray array];
	NSString		*version = [xtraInfo version];

	if ([version length]) {
		[parts addObject:[NSString stringWithFormat:AILocalizedString(@"Version %@", "Version of an installed Xtra, shown below its name"), version]];
	}

	if (![self xtraIsUsers:xtraInfo]) {
		/* Where it came from only needs saying when it is not this user's own; that it can't be
		 * switched off here is what the switch's tool tip explains. */
		[parts addObject:([[xtraInfo path] hasPrefix:@"/Network/"] ?
						  AILocalizedString(@"Network", "Origin of an Xtra installed on a network volume") :
						  AILocalizedString(@"All Users", "Origin of an Xtra installed for every user of this Mac"))];
	}

	if (![xtraInfo enabled]) {
		[parts addObject:AILocalizedString(@"Disabled", nil)];
	}

	if (![parts count]) {
		NSString	*extension = [[xtraInfo path] pathExtension];

		[parts addObject:([extension length] ? extension : [[xtraInfo path] lastPathComponent])];
	}

	return [parts componentsJoinedByString:@" · "];
}

/*!
 * @brief Fill a row's view with the current state of its Xtra
 */
- (void)configureCellView:(AIXtraListCellView *)cellView forRow:(NSInteger)row
{
	AIXtraInfo	*xtraInfo = [self xtraAtRow:row];

	if (!xtraInfo) return;

	BOOL		 enabled = [xtraInfo enabled];
	BOOL		 usersOwn = [self xtraIsUsers:xtraInfo];
	NSString	*name = [xtraInfo name];
	NSString	*detail = [self detailLineForXtra:xtraInfo];

	/* Never -setSize: on the icon: -[AIXtraInfo icon] may hand out the shared image
	 * +[NSWorkspace iconForFileType:] returns, and resizing that would resize it everywhere it is
	 * drawn. The image view scales it into its fixed 32pt box instead, and a switched off Xtra is
	 * dimmed by fading the view rather than by making a faded copy of the image. */
	[[cellView imageView] setImage:[xtraInfo icon]];
	[[cellView imageView] setAlphaValue:(enabled ? 1.0f : DISABLED_ICON_ALPHA)];

	[[cellView textField] setStringValue:(name ?: @"")];
	[[cellView detailField] setStringValue:detail];

	/* No tool tip on the row. One covering the whole row swallows scroll events for as long as it
	 * is showing, so the pane cannot be scrolled while the pointer rests on a list - and it said
	 * little worth that: the folder has a button of its own in the card above, and the name is
	 * already in the accessibility label. The switch and the remove button keep theirs; those
	 * appear only over a small control and explain something not written anywhere else. */

	/* Setting the state unconditionally would interfere with the switch's own click handling, which
	 * is still tracking while the list is rebuilt underneath it. */
	NSControlStateValue	switchState = (enabled ? NSControlStateValueOn : NSControlStateValueOff);

	if ([[cellView enabledSwitch] state] != switchState) {
		[[cellView enabledSwitch] setState:switchState];
	}

	[[cellView enabledSwitch] setEnabled:usersOwn];
	[[cellView enabledSwitch] setTarget:self];
	[[cellView enabledSwitch] setAction:@selector(toggleXtraEnabled:)];
	[[cellView enabledSwitch] setToolTip:(usersOwn ?
										  nil :
										  AILocalizedString(@"This Xtra was installed for all users and cannot be changed here.",
															"Tool tip of the disabled switch of an Xtra which is not in the user's own Xtras folder"))];
	[[cellView enabledSwitch] setAccessibilityLabel:[NSString stringWithFormat:AILocalizedString(@"Enable %@", "Accessibility label of the switch which enables an Xtra. %@ is the name of the Xtra."), (name ?: @"")]];

	[[cellView removeButton] setTarget:self];
	[[cellView removeButton] setAction:@selector(removeXtraFromRowButton:)];
	[[cellView removeButton] setToolTip:AILocalizedStringFromTable(@"Delete", @"Buttons", "Verb 'delete' on a button")];
	[[cellView removeButton] setAccessibilityLabel:[NSString stringWithFormat:AILocalizedString(@"Delete %@", "Accessibility label of the button which deletes an Xtra. %@ is the name of the Xtra."), (name ?: @"")]];

	/* The hairline sits between two rows, so there is none below the last one. It runs from the
	 * text indent out to the card's edge - past the trailing edge of the cell, which the inset
	 * table style keeps away from that edge - stopping where every other card's rows stop. */
	[[cellView separatorTrailingConstraint] setConstant:([self rowInsetPerSide] - SEPARATOR_CARD_MARGIN)];
	[[cellView separator] setHidden:(row >= ((NSInteger)[xtras count] - 1))];

	[cellView setDimmed:!enabled];
	[cellView setContextHighlighted:(row == contextMenuRow)];
	[cellView setAccessibilityLabel:[NSString stringWithFormat:@"%@, %@", (name ?: @""), detail]];
}

/*!
 * @brief Reconfigure a row which is currently on screen
 */
- (void)refreshRow:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[xtras count] || row >= [tableView numberOfRows]) return;

	id	cellView = [tableView viewAtColumn:0 row:row makeIfNecessary:NO];

	if ([cellView isKindOfClass:[AIXtraListCellView class]]) {
		[self configureCellView:(AIXtraListCellView *)cellView forRow:row];
	}
}

#pragma mark Actions

/*!
 * @brief The switch of a row was flipped
 *
 * The list knows nothing about what it means to switch an Xtra off; it hands the row's Xtra and the
 * new state to its owner and waits to be given a new set of Xtras.
 */
- (IBAction)toggleXtraEnabled:(id)sender
{
	AIXtraInfo	*xtraInfo = [self xtraAtRow:[tableView rowForView:(NSView *)sender]];

	if (xtraInfo && [listDelegate respondsToSelector:@selector(xtraListView:setEnabled:forXtra:)]) {
		[listDelegate xtraListView:self
						setEnabled:([(NSSwitch *)sender state] == NSControlStateValueOn)
						   forXtra:xtraInfo];
	}
}

/*!
 * @brief The ⊖ of a row was clicked
 */
- (IBAction)removeXtraFromRowButton:(id)sender
{
	[self deleteXtra:[self xtraAtRow:[tableView rowForView:(NSView *)sender]]];
}

- (void)deleteXtra:(AIXtraInfo *)xtraInfo
{
	if (xtraInfo && [listDelegate respondsToSelector:@selector(xtraListView:deleteXtra:)]) {
		[listDelegate xtraListView:self deleteXtra:xtraInfo];
	}
}

/*!
 * @brief "Move to Trash" was chosen from a row's context menu
 */
- (void)deleteXtraFromMenu:(id)sender
{
	[self deleteXtra:[sender representedObject]];
}

/*!
 * @brief "Enable"/"Disable" was chosen from a row's context menu
 */
- (void)toggleXtraEnabledFromMenu:(id)sender
{
	AIXtraInfo	*xtraInfo = [sender representedObject];

	if (xtraInfo && [listDelegate respondsToSelector:@selector(xtraListView:setEnabled:forXtra:)]) {
		[listDelegate xtraListView:self setEnabled:![xtraInfo enabled] forXtra:xtraInfo];
	}
}

/*!
 * @brief "Show in Finder" was chosen from a row's context menu
 */
- (void)revealXtraFromMenu:(id)sender
{
	AIXtraInfo	*xtraInfo = [sender representedObject];

	if (xtraInfo && [listDelegate respondsToSelector:@selector(xtraListView:revealXtra:)]) {
		[listDelegate xtraListView:self revealXtra:xtraInfo];
	}
}

#pragma mark Table view data source and delegate

/*!
 * @brief Rows cannot be selected
 *
 * Nothing acts on a selection: the switch, the ⊖ and the context menu each work on the row the
 * pointer is on.
 */
- (BOOL)tableView:(NSTableView *)inTableView shouldSelectRow:(NSInteger)row
{
	return NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)inTableView
{
	return [xtras count];
}

- (id)tableView:(NSTableView *)inTableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	return [self xtraAtRow:row];
}

- (CGFloat)tableView:(NSTableView *)inTableView heightOfRow:(NSInteger)row
{
	return AIXtraRowHeight();
}

- (NSView *)tableView:(NSTableView *)inTableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[xtras count]) return nil;

	AIXtraListCellView	*cellView = (AIXtraListCellView *)[inTableView makeViewWithIdentifier:XTRA_CELL_IDENTIFIER
																						owner:self];

	if (![cellView isKindOfClass:[AIXtraListCellView class]]) {
		cellView = [[[AIXtraListCellView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f,
																		 NSWidth([inTableView bounds]),
																		 AIXtraRowHeight())] autorelease];
	}

	[self configureCellView:cellView forRow:row];

	return cellView;
}

#pragma mark Context menu

/*!
 * @brief The context menu of the row under the pointer
 *
 * There is no selection to consult and none is made: the row the user right clicked is the row the
 * menu acts on, and every item carries its Xtra in its represented object so the action which runs
 * afterwards does not depend on that row still being the one we marked.
 */
- (NSMenu *)tableView:(NSTableView *)inTableView menuForEvent:(NSEvent *)theEvent
{
	NSInteger	mouseRow = [inTableView rowAtPoint:[inTableView convertPoint:[theEvent locationInWindow] fromView:nil]];
	NSMenu		*menu = [self menuForRow:mouseRow];

	[self setContextMenuRow:(menu ? mouseRow : -1)];
	[menu setDelegate:self];

	return menu;
}

- (NSMenu *)menuForRow:(NSInteger)row
{
	AIXtraInfo	*xtraInfo = [self xtraAtRow:row];

	if (!xtraInfo) return nil;

	NSMenu		*menu = [[[NSMenu alloc] init] autorelease];
	NSMenuItem	*menuItem;

	//Items are enabled by hand: "Disable" is not offered for an Xtra we may not move
	[menu setAutoenablesItems:NO];

	menuItem = [[[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Show in Finder", nil)
										   action:@selector(revealXtraFromMenu:)
									keyEquivalent:@""] autorelease];
	[menuItem setTarget:self];
	[menuItem setRepresentedObject:xtraInfo];
	[menu addItem:menuItem];

	menuItem = [[[NSMenuItem alloc] initWithTitle:([xtraInfo enabled] ?
												   AILocalizedString(@"Disable", nil) :
												   AILocalizedString(@"Enable", nil))
										   action:@selector(toggleXtraEnabledFromMenu:)
									keyEquivalent:@""] autorelease];
	[menuItem setTarget:self];
	[menuItem setRepresentedObject:xtraInfo];
	[menuItem setEnabled:[self xtraIsUsers:xtraInfo]];
	[menu addItem:menuItem];

	[menu addItem:[NSMenuItem separatorItem]];

	menuItem = [[[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Move to Trash", "Context menu item which deletes an installed Xtra")
										   action:@selector(deleteXtraFromMenu:)
									keyEquivalent:@""] autorelease];
	[menuItem setTarget:self];
	[menuItem setRepresentedObject:xtraInfo];
	[menu addItem:menuItem];

	return menu;
}

/*!
 * @brief The context menu closed; the row it belonged to is nothing special again
 */
- (void)menuDidClose:(NSMenu *)menu
{
	[self setContextMenuRow:-1];
}

/*!
 * @brief Move the context menu highlight to @a row (-1 for none)
 */
- (void)setContextMenuRow:(NSInteger)row
{
	if (contextMenuRow == row) return;

	NSInteger	previousRow = contextMenuRow;

	contextMenuRow = row;

	[self refreshRow:previousRow];
	[self refreshRow:row];
}

@end
