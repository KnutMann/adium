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

#import "AIStatusListView.h"
#import <Adium/AIStatusItem.h>
#import <Adium/AIStatusDefines.h>
#import <Adium/AISettingsFormView.h>

//Identifier of the single, full width column and of the reusable row view
#define STATUS_COLUMN_IDENTIFIER	@"status"
#define STATUS_CELL_IDENTIFIER		@"AIStatusListCell"

/* Horizontal margin the settings form leaves inside its cards, mirrored here so a row's hairline
 * ends where every other pane's does. */
#define SEPARATOR_CARD_MARGIN		16.0f

//Metrics of a single status row, System Settings style
#define MINIMUM_ROW_HEIGHT			36.0f
#define ROW_V_PADDING				 6.0f		//Space above and below the title
#define TITLE_FONT_SIZE				13.0f
#define CELL_H_PADDING				10.0f		//Leading/trailing padding inside a row
#define STATUS_ICON_SIZE			16.0f
#define STATUS_ICON_GAP				10.0f		//Space between the icon and the title
#define CONTROL_GAP					10.0f		//Space around the switch

//Room the inset table style claims; measured off the table itself as soon as it has tiled once
#define INSET_STYLE_MARGIN			32.0f
#define INSET_STYLE_PADDING			10.0f

/*!
 * @brief Create a non-editable, non-bordered label
 */
static NSTextField *AIStatusListLabel(void)
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];

	[label setTranslatesAutoresizingMaskIntoConstraints:NO];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBezeled:NO];
	[label setBordered:NO];
	[label setDrawsBackground:NO];
	[label setRefusesFirstResponder:YES];
	[label setFont:[NSFont systemFontOfSize:TITLE_FONT_SIZE]];
	[label setTextColor:[NSColor labelColor]];
	[[label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
	[label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
									forOrientation:NSLayoutConstraintOrientationHorizontal];
	[label setStringValue:@""];

	return label;
}

/*!
 * @brief Height of every row of every status list
 *
 * A status row is always exactly one line tall - it carries a title and nothing else - so the height
 * is a property of the font rather than of the row, and it is measured once instead of per row and
 * per width. That constancy is also what lets a list report its own height without laying a single
 * row out.
 */
static CGFloat AIStatusRowHeight(void)
{
	static CGFloat rowHeight = 0.0f;

	if (rowHeight <= 0.0f) {
		NSTextField	*titleField = AIStatusListLabel();

		//A single space, so the cell measures a line rather than nothing at all
		[titleField setStringValue:@" "];

		CGFloat		textHeight = ceil([[titleField cell] cellSize].height);

		rowHeight = ceil(MAX(MAX(MINIMUM_ROW_HEIGHT, STATUS_ICON_SIZE + 2.0f * ROW_V_PADDING),
							 textHeight + 2.0f * ROW_V_PADDING));
	}

	return rowHeight;
}

/*!
 * @class AIStatusListCellView
 * @brief View based row of a status list
 *
 * Layout: [icon] [title] [switch] [⊖], with a hairline along the bottom edge. All subviews are owned
 * by the view hierarchy; the properties below are non-retaining references for convenience.
 *
 * Private to the list on purpose: no pane ever builds one, and nothing outside this file has any
 * business knowing what a status row is made of.
 */
@interface AIStatusListCellView : NSTableCellView
@property (nonatomic, unsafe_unretained) NSSwitch			*shownSwitch;
@property (nonatomic, unsafe_unretained) NSButton			*removeButton;
@property (nonatomic, unsafe_unretained) NSBox				*separator;
@property (nonatomic, retain) NSLayoutConstraint *separatorTrailingConstraint;
@end

@interface AIStatusListView ()
- (void)configureList;
- (void)synchronizeColumnWidth;
- (CGFloat)rowInsetPerSide;
- (void)listFrameChanged:(NSNotification *)notification;
- (void)relayoutRows;
- (void)updateHeight;
- (void)configureCellView:(AIStatusListCellView *)cellView forRow:(NSInteger)row;
- (void)refreshRow:(NSInteger)row;
- (AIStatusItem *)statusItemAtRow:(NSInteger)row;
@end

@implementation AIStatusListCellView

- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		[self setIdentifier:STATUS_CELL_IDENTIFIER];

		//The status icon
		NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		[iconView setTranslatesAutoresizingMaskIntoConstraints:NO];
		[iconView setImageScaling:NSImageScaleProportionallyUpOrDown];
		[iconView setEditable:NO];
		//The title right next to it says everything the icon says; don't read it twice
		[iconView setAccessibilityElement:NO];
		[self addSubview:iconView];
		[self setImageView:iconView];

		//Title of the status
		NSTextField *titleField = AIStatusListLabel();
		[self addSubview:titleField];
		[self setTextField:titleField];

		//"Show this status in the status menus"
		NSSwitch *shownSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
		//System Settings uses the small switch, not the regular one
		[shownSwitch setControlSize:NSControlSizeSmall];
		[shownSwitch setTranslatesAutoresizingMaskIntoConstraints:NO];
		[self addSubview:shownSwitch];
		[self setShownSwitch:shownSwitch];

		/* The ⊖ which deletes the status. Built by the settings form's factory, so it is the same
		 * control as the ⊖ of an Xtra row - down to its tint and its size, which is read back here
		 * rather than repeated as a number of our own. */
		NSButton *removeButton = [AISettingsFormView inlineSymbolButtonWithSymbolName:@"minus.circle"
																   fallbackImageName:@"remove"
																			  target:nil
																			  action:NULL];
		NSSize	 removeButtonSize = [removeButton frame].size;

		[removeButton setTranslatesAutoresizingMaskIntoConstraints:NO];
		[self addSubview:removeButton];
		[self setRemoveButton:removeButton];

		//Hairline separating this row from the next one
		NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
		[separator setTranslatesAutoresizingMaskIntoConstraints:NO];
		[separator setBoxType:NSBoxSeparator];
		[self addSubview:separator];
		[self setSeparator:separator];

		/* The hairline runs past the trailing edge of the cell all the way to the card's edge, the
		 * way System Settings draws it. How far that is depends on the table's style, so the list
		 * sets the constant; see -[AIStatusListView rowInsetPerSide]. */
		NSLayoutConstraint *separatorTrailing = [[separator trailingAnchor] constraintEqualToAnchor:[self trailingAnchor]];
		[self setSeparatorTrailingConstraint:separatorTrailing];

		[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
			//Icon
			[[iconView leadingAnchor] constraintEqualToAnchor:[self leadingAnchor] constant:CELL_H_PADDING],
			[[iconView centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
			[[iconView widthAnchor] constraintEqualToConstant:STATUS_ICON_SIZE],
			[[iconView heightAnchor] constraintEqualToConstant:STATUS_ICON_SIZE],

			//Remove button
			[[removeButton trailingAnchor] constraintEqualToAnchor:[self trailingAnchor] constant:-CELL_H_PADDING],
			[[removeButton centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
			[[removeButton widthAnchor] constraintEqualToConstant:removeButtonSize.width],
			[[removeButton heightAnchor] constraintEqualToConstant:removeButtonSize.height],

			//Switch
			[[shownSwitch trailingAnchor] constraintEqualToAnchor:[removeButton leadingAnchor] constant:-CONTROL_GAP],
			[[shownSwitch centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],

			//Title
			[[titleField leadingAnchor] constraintEqualToAnchor:[iconView trailingAnchor] constant:STATUS_ICON_GAP],
			[[titleField trailingAnchor] constraintEqualToAnchor:[shownSwitch leadingAnchor] constant:-CONTROL_GAP],
			[[titleField centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],

			//Separator
			[[separator leadingAnchor] constraintEqualToAnchor:[titleField leadingAnchor]],
			separatorTrailing,
			[[separator bottomAnchor] constraintEqualToAnchor:[self bottomAnchor]],
			[[separator heightAnchor] constraintEqualToConstant:1.0f],
			nil]];
	}

	return self;
}

/*!
 * @brief Only the switch and the ⊖ swallow clicks
 *
 * Everything else is handed to the table view, which is what keeps the double click that opens the
 * status editor working.
 */
- (NSView *)hitTest:(NSPoint)aPoint
{
	NSView *hitView = [super hitTest:aPoint];

	if (!hitView) return nil;

	if (hitView == [self shownSwitch] || [hitView isDescendantOf:[self shownSwitch]] ||
		hitView == [self removeButton] || [hitView isDescendantOf:[self removeButton]]) {
		return hitView;
	}

	return self;
}

@end

@implementation AIStatusListView

- (id)initWithStatusItems:(NSArray *)inStatusItems
{
	/* Any width will do: the settings form hands the list the width of its card before it is ever
	 * drawn, and the height is recomputed from the rows right below. */
	if ((self = [super initWithFrame:NSMakeRect(0.0f, 0.0f, 400.0f, AIStatusRowHeight())])) {
		statusItems = [inStatusItems copy];
		cachedLayoutWidth = 0.0f;
		columnMargin = INSET_STYLE_MARGIN;
		layoutScheduled = NO;

		[self configureList];
		[self updateHeight];
	}

	return self;
}

- (void)dealloc
{
	[self tearDown];
}

/*!
 * @brief Build the table and turn the scroll view into a plain container
 */
- (void)configureList
{
	tableView = [[NSTableView alloc] initWithFrame:[self bounds]];

	[tableView setDataSource:self];
	[tableView setDelegate:self];
	[tableView setIntercellSpacing:NSZeroSize];
	[tableView setHeaderView:nil];
	[tableView setCornerView:nil];
	[tableView setGridStyleMask:NSTableViewGridNone];
	[tableView setUsesAlternatingRowBackgroundColors:NO];
	[tableView setBackgroundColor:[NSColor clearColor]];
	[tableView setRowSizeStyle:NSTableViewRowSizeStyleCustom];
	/* Rows are not selectable: every action a row offers sits on the row itself - its switch, its ⊖
	 * and the double click which edits it. -tableView:shouldSelectRow: is what refuses the selection;
	 * the highlight style is left alone all the same, because
	 * NSTableViewSelectionHighlightStyleNone also turns off the feedback a drag draws. */
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

	//A double click anywhere on a row opens the status editor; there is no "Edit" button any more
	[tableView setTarget:self];
	[tableView setDoubleAction:@selector(doubleClickInTableView:)];

	[tableView setAccessibilityLabel:AILocalizedString(@"Statuses", nil)];

	NSTableColumn *statusColumn = [[NSTableColumn alloc] initWithIdentifier:STATUS_COLUMN_IDENTIFIER];
	[statusColumn setResizingMask:NSTableColumnAutoresizingMask];
	[statusColumn setEditable:NO];
	[statusColumn setMinWidth:80.0f];
	[statusColumn setMaxWidth:10000.0f];
	//The table tiles the column to the width the inset style leaves over; start out with that width
	[statusColumn setWidth:(NSWidth([tableView bounds]) - INSET_STYLE_MARGIN)];
	[tableView addTableColumn:statusColumn];

	/* The list does not scroll: it is as tall as its rows and the preferences column scrolls instead.
	 * The scroll view stays - a table view outside of one loses its tiling and its enclosing clip
	 * view - but it never scrolls anything: no scrollers, no elasticity, which also lets the scroll
	 * wheel through to the column behind us.
	 *
	 * The card around the list is drawn by AISettingsFormView, so nothing here draws a background of
	 * its own; the form also rounds our corners to the card's radius. */
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
	 * changing. Starting out at zero rather than at the width we happen to have right now guarantees
	 * that the first real width the form hands us counts as a change. */
	[tableView setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(listFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:tableView];
}

#pragma mark Contents

- (NSArray *)statusItems
{
	return statusItems;
}

- (void)setStatusItems:(NSArray *)inStatusItems
{
	if (statusItems == inStatusItems) return;

	statusItems = [inStatusItems copy];

	[tableView reloadData];
	[self updateHeight];
}

- (id<AIStatusListViewDelegate>)listDelegate
{
	return listDelegate;
}

- (void)setListDelegate:(id<AIStatusListViewDelegate>)inDelegate
{
	listDelegate = inDelegate;
}

- (AIStatusItem *)statusItemAtRow:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[statusItems count]) return nil;

	return [statusItems objectAtIndex:row];
}

- (void)tearDown
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSViewFrameDidChangeNotification
												  object:tableView];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(relayoutRows) object:nil];
	layoutScheduled = NO;

	/* Delegate, data source and the target of every row's controls are non-retaining references; the
	 * form owns our views and may outlive the pane by a moment, so cut them all now. */
	listDelegate = nil;
	[tableView setDelegate:nil];
	[tableView setDataSource:nil];
	[tableView setTarget:nil];
	[tableView setDoubleAction:NULL];
}

#pragma mark Geometry

/*!
 * @brief The height the list needs to show every row without scrolling
 *
 * The sum of the row heights plus the table's intercell spacing per row, plus the room the table
 * style keeps above the first and below the last row - NSTableViewStyleInset keeps 10pt at each end,
 * and leaving that out is exactly what makes a card too short for its list. That padding is measured
 * off the table rather than assumed, as soon as the table has a row to measure it on.
 *
 * The table then gets the last word through its row rects, so a layout we did not predict still
 * cannot end up with less room than the table laid itself out in. An empty list still gets one row's
 * worth of height so its card cannot collapse into a line - which in practice never happens, since
 * the built-in statuses are always in it.
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

	CGFloat		height = ((CGFloat)[statusItems count] * (AIStatusRowHeight() + spacing)) + (2.0f * endPadding);

	if (tableRows > 0 && tableRows == (NSInteger)[statusItems count]) {
		CGFloat		contentHeight = NSMaxY([tableView rectOfRow:(tableRows - 1)]) + endPadding;

		if (contentHeight > height) height = contentHeight;
	}

	CGFloat		minimumHeight = AIStatusRowHeight() + (2.0f * endPadding);

	return ceil(height < minimumHeight ? minimumHeight : height);
}

/*!
 * @brief Grow or shrink to fit our rows and tell the owner about it
 *
 * The half point guard is not decoration: the settings form runs a full layout pass when it is told,
 * which causes frame changes of its own, and without it that can circle.
 */
- (void)updateHeight
{
	CGFloat		height = [self requiredHeight];

	if (fabs(NSHeight([self frame]) - height) < 0.5f) return;

	[self setFrameSize:NSMakeSize(NSWidth([self frame]), height)];

	if ([listDelegate respondsToSelector:@selector(statusListViewDidChangeHeight:)]) {
		[listDelegate statusListViewDidChangeHeight:self];
	}
}

/*!
 * @brief Keep the single column as wide as the room the list has
 *
 * A table does not reliably re-tile its columns when it is widened, and a column left behind lays
 * every row out narrower than the card - which puts the switch and the ⊖ in the middle of the row
 * and stops the hairline short of the card's edge. A column left <em>wider</em> than the clip view is
 * worse still, because the list has no scrollers and the trailing end of every row would then simply
 * be unreachable. So the column is set from the width of the clip view rather than left to the table,
 * and the margin the table style wants around it is measured off the table itself.
 */
- (void)synchronizeColumnWidth
{
	NSTableColumn	*statusColumn = [tableView tableColumnWithIdentifier:STATUS_COLUMN_IDENTIFIER];
	CGFloat			 clipWidth = NSWidth([[self contentView] bounds]);

	if (!statusColumn || clipWidth <= 0.0f) return;

	CGFloat			 tableWidth = NSWidth([tableView bounds]);
	CGFloat			 observedMargin = tableWidth - [statusColumn width];

	/* While the table is tiled to its clip view, whatever it keeps beside its column is the truth
	 * about this table style on this system; remember it instead of assuming 16pt per side. */
	if ((fabs(tableWidth - clipWidth) < 0.5f) &&
		(observedMargin >= 0.0f) && (observedMargin <= (INSET_STYLE_MARGIN * 2.0f))) {
		columnMargin = observedMargin;
	}

	CGFloat			 targetWidth = clipWidth - columnMargin;

	if (targetWidth < [statusColumn minWidth]) targetWidth = [statusColumn minWidth];

	if (fabs([statusColumn width] - targetWidth) > 0.5f) [statusColumn setWidth:targetWidth];
}

/*!
 * @brief How far the inset table style keeps a row away from the edge of the card
 */
- (CGFloat)rowInsetPerSide
{
	NSTableColumn	*statusColumn = [tableView tableColumnWithIdentifier:STATUS_COLUMN_IDENTIFIER];
	CGFloat			 tableWidth = NSWidth([tableView bounds]);
	CGFloat			 columnWidth = (statusColumn ? [statusColumn width] : 0.0f);

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
	 * the common modes rather than the default one, so a width handed to us while the window is being
	 * resized is not left unacted upon until the drag ends.
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
 * @brief Fill a row's view with the current state of its status
 *
 * Target and action of the two controls are set here rather than when the row was built: rows are
 * recycled, and a recycled row would otherwise still be pointing at whatever it pointed at before.
 */
- (void)configureCellView:(AIStatusListCellView *)cellView forRow:(NSInteger)row
{
	AIStatusItem			*statusItem = [self statusItemAtRow:row];

	if (!statusItem) return;

	NSString				*title = [statusItem title];
	BOOL					 shown = [statusItem showsInStatusMenu];
	AIStatusMutabilityType	 mutabilityType = [statusItem mutabilityType];
	/* Offline is the one status which must stay in the menu. It has no "Custom…" stand-in there and
	 * no menu command of its own, so hiding it would take away the way back offline. */
	BOOL					 isBuiltInOffline = (([statusItem statusType] == AIOfflineStatusType) &&
												 (mutabilityType == AILockedStatusState));
	//Only a status the user made can be deleted; the built-in ones are not in the root group at all
	BOOL					 deletable = (mutabilityType == AIEditableStatusState);

	/* Never -setSize: on the icon: it comes from AIStatusIcons and is shared with the status menu,
	 * the contact list and the account list, so resizing it would resize it everywhere it is drawn.
	 * The image view scales it into its fixed 16pt box instead. */
	[[cellView imageView] setImage:[statusItem icon]];

	[[cellView textField] setStringValue:(title ?: @"")];

	/* Setting the state unconditionally would interfere with the switch's own click handling, which
	 * is still tracking while the list is rebuilt underneath it. */
	NSControlStateValue		 switchState = ((shown || isBuiltInOffline) ?
											NSControlStateValueOn : NSControlStateValueOff);

	if ([[cellView shownSwitch] state] != switchState) {
		[[cellView shownSwitch] setState:switchState];
	}

	[[cellView shownSwitch] setEnabled:!isBuiltInOffline];
	[[cellView shownSwitch] setTarget:self];
	[[cellView shownSwitch] setAction:@selector(toggleStatusShown:)];
	[[cellView shownSwitch] setToolTip:(isBuiltInOffline ?
										AILocalizedString(@"Offline is the only way back offline from the status menu and is always shown.",
														  "Tool tip of the fixed switch of the built-in Offline status") :
										nil)];
	[[cellView shownSwitch] setAccessibilityLabel:[NSString stringWithFormat:AILocalizedString(@"Show %@ in the status menu", "Accessibility label of the switch which shows a status in the status menu. %@ is the title of the status."), (title ?: @"")]];

	[[cellView removeButton] setEnabled:deletable];
	[[cellView removeButton] setTarget:self];
	[[cellView removeButton] setAction:@selector(removeStatusFromRowButton:)];
	[[cellView removeButton] setToolTip:(deletable ?
										 AILocalizedStringFromTable(@"Delete", @"Buttons", "Verb 'delete' on a button") :
										 AILocalizedString(@"Statuses Adium brings with it cannot be deleted; switch them off to take them out of the status menu.",
														   "Tool tip of the disabled delete button of a built-in status"))];
	[[cellView removeButton] setAccessibilityLabel:[NSString stringWithFormat:AILocalizedString(@"Delete %@", "Accessibility label of the button which deletes a status. %@ is the title of the status."), (title ?: @"")]];

	/* The hairline sits between two rows, so there is none below the last one. It runs from the text
	 * indent out to the card's edge - past the trailing edge of the cell, which the inset table style
	 * keeps away from that edge - stopping where every other card's rows stop. */
	[[cellView separatorTrailingConstraint] setConstant:([self rowInsetPerSide] - SEPARATOR_CARD_MARGIN)];
	[[cellView separator] setHidden:(row >= ((NSInteger)[statusItems count] - 1))];

	[cellView setAccessibilityLabel:(title ?: @"")];
}

/*!
 * @brief Reconfigure a row which is currently on screen
 */
- (void)refreshRow:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[statusItems count] || row >= [tableView numberOfRows]) return;

	id	cellView = [tableView viewAtColumn:0 row:row makeIfNecessary:NO];

	if ([cellView isKindOfClass:[AIStatusListCellView class]]) {
		[self configureCellView:(AIStatusListCellView *)cellView forRow:row];
	}
}

#pragma mark Actions

/*!
 * @brief The switch of a row was flipped
 */
- (IBAction)toggleStatusShown:(id)sender
{
	AIStatusItem	*statusItem = [self statusItemAtRow:[tableView rowForView:(NSView *)sender]];

	if (statusItem && [listDelegate respondsToSelector:@selector(statusListView:setShownInStatusMenu:forStatus:)]) {
		[listDelegate statusListView:self
				setShownInStatusMenu:([(NSSwitch *)sender state] == NSControlStateValueOn)
						   forStatus:statusItem];
	}
}

/*!
 * @brief The ⊖ of a row was clicked
 */
- (IBAction)removeStatusFromRowButton:(id)sender
{
	AIStatusItem	*statusItem = [self statusItemAtRow:[tableView rowForView:(NSView *)sender]];

	if (statusItem && [listDelegate respondsToSelector:@selector(statusListView:deleteStatus:)]) {
		[listDelegate statusListView:self deleteStatus:statusItem];
	}
}

/*!
 * @brief A row was double clicked
 *
 * Rows are not selectable, so the status is the one under the pointer: -clickedRow is set for the
 * whole time an action sent by the table is running. Clicks on the switch and on the ⊖ never reach
 * the table at all (see -[AIStatusListCellView hitTest:]), so anything arriving here is meant to
 * open the status editor.
 */
- (void)doubleClickInTableView:(id)sender
{
	AIStatusItem	*statusItem = [self statusItemAtRow:[tableView clickedRow]];

	if (statusItem && [listDelegate respondsToSelector:@selector(statusListView:editStatus:)]) {
		[listDelegate statusListView:self editStatus:statusItem];
	}
}

#pragma mark Table view data source and delegate

/*!
 * @brief Rows cannot be selected
 */
- (BOOL)tableView:(NSTableView *)inTableView shouldSelectRow:(NSInteger)row
{
	return NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)inTableView
{
	return [statusItems count];
}

- (id)tableView:(NSTableView *)inTableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	return [self statusItemAtRow:row];
}

- (CGFloat)tableView:(NSTableView *)inTableView heightOfRow:(NSInteger)row
{
	return AIStatusRowHeight();
}

- (NSView *)tableView:(NSTableView *)inTableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[statusItems count]) return nil;

	AIStatusListCellView	*cellView = (AIStatusListCellView *)[inTableView makeViewWithIdentifier:STATUS_CELL_IDENTIFIER
																							  owner:self];

	if (![cellView isKindOfClass:[AIStatusListCellView class]]) {
		cellView = [[AIStatusListCellView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f,
																		  NSWidth([inTableView bounds]),
																		  AIStatusRowHeight())];
	}

	[self configureCellView:cellView forRow:row];

	return cellView;
}

@end
