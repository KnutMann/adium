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

#import "AIMentionAdvancedPreferences.h"
#import "AIPreferenceWindowController.h"
#import "AIPassthroughScrollView.h"

#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIImageAdditions.h>

//Width the form starts out at; the preferences window resizes it to its column
#define MENTION_PANE_INITIAL_WIDTH	540.0f

//Identifier of the single, full width column and of the two reusable row views
#define MENTION_COLUMN_IDENTIFIER	@"term"
#define MENTION_CELL_IDENTIFIER		@"AIMentionListCell"
#define MENTION_EMPTY_IDENTIFIER	@"AIMentionEmptyCell"

/* Horizontal margin the settings form leaves inside its cards, mirrored here so a row's hairline
 * ends where every other pane's does. */
#define SEPARATOR_CARD_MARGIN		16.0f

//Metrics of a single term row, System Settings style
#define MENTION_ROW_HEIGHT			36.0f
#define CELL_H_PADDING				10.0f		//Leading/trailing padding inside a row
#define CONTROL_GAP					 8.0f		//Space between the text and the ⊖
#define TERM_FONT_SIZE				13.0f

//Room the inset table style claims; measured off the table itself as soon as it has tiled once
#define INSET_STYLE_MARGIN			32.0f
#define INSET_STYLE_PADDING			10.0f

/*!
 * @brief The editable field a term is typed into
 *
 * Borderless and without a background of its own: the card behind it is what the user sees, exactly
 * as in the account and Xtra lists. It never wraps - a term is one line - and scrolls its own text
 * instead, so a long regular expression stays reachable in a narrow window.
 */
static NSTextField *AIMentionTermField(void)
{
	NSTextField *field = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];

	[field setTranslatesAutoresizingMaskIntoConstraints:NO];
	[field setFont:[NSFont systemFontOfSize:TERM_FONT_SIZE]];
	[field setTextColor:[NSColor labelColor]];
	[field setEditable:YES];
	[field setSelectable:YES];
	[field setBezeled:NO];
	[field setBordered:NO];
	[field setDrawsBackground:NO];
	[[field cell] setWraps:NO];
	[[field cell] setScrollable:YES];
	[[field cell] setLineBreakMode:NSLineBreakByClipping];
	[field setStringValue:@""];

	return field;
}

/*!
 * @brief The centred, dimmed label of the "nothing here yet" row
 */
static NSTextField *AIMentionEmptyLabel(void)
{
	NSTextField *label = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];

	[label setTranslatesAutoresizingMaskIntoConstraints:NO];
	[label setFont:[NSFont systemFontOfSize:TERM_FONT_SIZE]];
	[label setTextColor:[NSColor secondaryLabelColor]];
	[label setAlignment:NSTextAlignmentCenter];
	[label setEditable:NO];
	//Not selectable: a selection highlight in an empty card reads as if something were there after all
	[label setSelectable:NO];
	[label setBezeled:NO];
	[label setBordered:NO];
	[label setDrawsBackground:NO];
	[label setRefusesFirstResponder:YES];
	[[label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
	[label setStringValue:@""];

	return label;
}

/*!
 * @brief What VoiceOver reads out for the ⊖ of the row holding <em>term</em>
 *
 * In one place because two of them name that button: the row when it is configured, and every
 * keystroke afterwards - a label built once would go on naming the term as it was before the user
 * started typing over it.
 */
static NSString *AIMentionRemoveAccessibilityLabel(NSString *term)
{
	/* Not AILocalizedString: that one reaches for [self class] to find its bundle, and a function
	 * has no self. Name the class outright instead. */
	return [NSString stringWithFormat:AILocalizedStringFromTableInBundle(@"Remove %@", nil,
																		[NSBundle bundleForClass:[AIMentionAdvancedPreferences class]],
																		"Accessibility label of the button which removes a term from the list. %@ is the term."),
									  (term ? term : @"")];
}

/*!
 * @class AIMentionTableView
 * @brief A table whose text fields take the very first click
 *
 * NSTableView refuses a text field inside a cell view the first click: the default
 * -validateProposedFirstResponder:forEvent: hands it to the row's selection instead, which is the
 * "click to select, click again to edit" behaviour of a Finder name. This list has no selection at
 * all - every row is a field the user is meant to type in - so every proposed first responder is
 * allowed straight away.
 */
@interface AIMentionTableView : NSTableView
@end

@implementation AIMentionTableView

- (BOOL)validateProposedFirstResponder:(NSResponder *)responder forEvent:(NSEvent *)event
{
	return YES;
}

@end

/*!
 * @class AIMentionCellView
 * @brief View based row of the term list: [text field] [⊖], with a hairline along the bottom edge
 *
 * All subviews are owned by the view hierarchy; the properties below are non-retaining references
 * for convenience (manual retain/release). Private to this pane on purpose.
 */
@interface AIMentionCellView : NSTableCellView
@property (nonatomic, assign) NSButton			*removeButton;
@property (nonatomic, assign) NSBox				*separator;
@property (nonatomic, retain) NSLayoutConstraint *separatorTrailingConstraint;
@end

@implementation AIMentionCellView

- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		[self setIdentifier:MENTION_CELL_IDENTIFIER];

		//The term itself
		NSTextField *termField = AIMentionTermField();
		[self addSubview:termField];
		[self setTextField:termField];

		/* The ⊖ which throws the term away. Built by the settings form's factory, so it is the same
		 * control as the ⊖ of an Xtra row - down to its tint and its size, which is read back here
		 * rather than repeated as a number of our own. */
		NSButton *removeButton = [AISettingsFormView inlineSymbolButtonWithSymbolName:@"minus.circle"
																   fallbackImageName:@"NSRemoveTemplate"
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
		 * way System Settings draws it. How far that is depends on the table's style, so the pane
		 * sets the constant; see -[AIMentionAdvancedPreferences rowInsetPerSide]. */
		NSLayoutConstraint *separatorTrailing = [[separator trailingAnchor] constraintEqualToAnchor:[self trailingAnchor]];
		[self setSeparatorTrailingConstraint:separatorTrailing];

		[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
			//Remove button
			[[removeButton trailingAnchor] constraintEqualToAnchor:[self trailingAnchor] constant:-CELL_H_PADDING],
			[[removeButton centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
			[[removeButton widthAnchor] constraintEqualToConstant:removeButtonSize.width],
			[[removeButton heightAnchor] constraintEqualToConstant:removeButtonSize.height],

			//Term
			[[termField leadingAnchor] constraintEqualToAnchor:[self leadingAnchor] constant:CELL_H_PADDING],
			[[termField trailingAnchor] constraintEqualToAnchor:[removeButton leadingAnchor] constant:-CONTROL_GAP],
			[[termField centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],

			//Separator
			[[separator leadingAnchor] constraintEqualToAnchor:[termField leadingAnchor]],
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

@end

#pragma mark -

@interface AIMentionAdvancedPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (void)configureList;
- (NSButton *)addButton;
- (void)saveTerms;
- (void)configureCellView:(AIMentionCellView *)cellView forRow:(NSInteger)row;
- (IBAction)removeTermFromRowButton:(id)sender;
- (CGFloat)requiredListHeight;
- (void)updateListHeight;
- (void)synchronizeColumnWidth;
- (CGFloat)rowInsetPerSide;
- (void)listFrameChanged:(NSNotification *)notification;
- (void)relayoutRows;
@end

@implementation AIMentionAdvancedPreferences

#pragma mark Preference pane settings
- (AIPreferenceCategory)category
{
    return AIPref_Advanced;
}
- (NSString *)label{
    return AILocalizedString(@"Mention",nil);
}
- (NSImage *)image{
	return [NSImage imageNamed:@"pref-mention" forClass:[AIPreferenceWindowController class]];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads a nib for us.
 * AIMentionAdvancedPreferences.xib is dead - and it must stay unloaded: it still wires four outlets
 * this class no longer has (label_explanation, tableView, button_add, button_remove) and hangs a
 * cell based table's delegate and data source off us, so loading it would raise
 * NSUnknownKeyException rather than fall back to the old interface. Removing it from the target
 * needs project file access we do not have here.
 */

#pragma mark View

/*!
 * @brief Build our view instead of loading a nib.
 *
 * Mirrors -[AIModularPane view] so the subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		AISettingsFormView	*form = [self buildSettingsForm];

		settingsForm = form;
		view = [form retain];

		[self viewDidLoad];
		[self localizePane];

		/* -viewDidLoad is what reads the terms, so the list only gets its rows - and therefore its
		 * height - after the form was built; one more layout pass settles the card around it. */
		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Undo everything -view built.
 *
 * -closeView runs -viewWillClose and releases the view, and is idempotent. Without it a deallocated
 * pane would leave the list's frame observer registered on freed memory and the table pointing at
 * us as its delegate.
 */
- (void)dealloc
{
	[self closeView];
	[super dealloc];
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * Two cards. The nib had one explanatory line above a bordered table with a +/- bar under it; here
 * the sentence carries a whole card of its own - it is what this pane is about, and it names the
 * list below it, so it cannot become a footnote under that list ("the following terms" would then
 * point backwards). The list itself is the second card: it fills it edge to edge, its height is the
 * card's height, and the "+" hangs under the card's trailing corner the way System Settings puts one
 * under a list.
 *
 * The only preference of this pane keeps the key and group its nib counterpart had; only the
 * presentation, and where a term is written, change.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:MENTION_PANE_INITIAL_WIDTH] autorelease];

	/* The nib's explanation, word for word and with the key it already had, so it stays translated
	 * in all 29 localizations. No header over this card: it would only repeat the pane's own title. */
	[form addInfoRow:AILocalizedString(@"Messages are highlighted when the following terms are spoken. Your username is always highlighted.", nil)
		   withImage:[self image]];

	[form addSectionHeader:AILocalizedString(@"Highlighted Terms", "Section title above the list of terms which highlight a message")];

	[self configureList];
	[form addEdgeToEdgeRow:scrollView];
	[form addTrailingAccessoryView:[self addButton]];

	return form;
}

/*!
 * @brief Build the list: a table which never scrolls, sized to its rows
 *
 * The scroll view stays - a table view outside of one loses its tiling and its enclosing clip view -
 * but it never scrolls anything: no scrollers, no elasticity, and AIPassthroughScrollView hands the
 * wheel on to the preference column behind it. The card around the list is drawn by
 * AISettingsFormView, which also rounds our corners, so nothing here draws a background of its own.
 */
- (void)configureList
{
	if (scrollView) return;

	scrollView = [[AIPassthroughScrollView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f,
																		   MENTION_PANE_INITIAL_WIDTH,
																		   MENTION_ROW_HEIGHT + 2.0f * INSET_STYLE_PADDING)];

	tableView = [[[AIMentionTableView alloc] initWithFrame:[scrollView bounds]] autorelease];

	[tableView setDataSource:self];
	[tableView setDelegate:self];
	[tableView setIntercellSpacing:NSZeroSize];
	[tableView setHeaderView:nil];
	[tableView setCornerView:nil];
	[tableView setGridStyleMask:NSTableViewGridNone];
	[tableView setUsesAlternatingRowBackgroundColors:NO];
	[tableView setBackgroundColor:[NSColor clearColor]];
	[tableView setRowSizeStyle:NSTableViewRowSizeStyleCustom];
	/* Rows are not selectable: a row's text field and its ⊖ are everything a row offers, and both
	 * work on the row they sit in. -tableView:shouldSelectRow: is what refuses the selection. */
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

	NSTableColumn *termColumn = [[[NSTableColumn alloc] initWithIdentifier:MENTION_COLUMN_IDENTIFIER] autorelease];
	[termColumn setResizingMask:NSTableColumnAutoresizingMask];
	//View based: the column never edits anything itself, its cell view's text field does
	[termColumn setEditable:NO];
	[termColumn setMinWidth:80.0f];
	[termColumn setMaxWidth:10000.0f];
	//The table tiles the column to the width the inset style leaves over; start out with that width
	[termColumn setWidth:(NSWidth([tableView bounds]) - INSET_STYLE_MARGIN)];
	[tableView addTableColumn:termColumn];

	[scrollView setDocumentView:tableView];
	[scrollView setBorderType:NSNoBorder];
	[scrollView setDrawsBackground:NO];
	[scrollView setHasVerticalScroller:NO];
	[scrollView setHasHorizontalScroller:NO];
	[scrollView setVerticalScrollElasticity:NSScrollElasticityNone];
	[scrollView setHorizontalScrollElasticity:NSScrollElasticityNone];
	[scrollView setAutomaticallyAdjustsContentInsets:NO];
	[scrollView setContentInsets:NSEdgeInsetsZero];
	[scrollView setAutoresizingMask:NSViewNotSizable];

	/* The column and the hairlines follow the width the card gives us, so we have to hear about it
	 * changing. Starting out at zero rather than at the width we happen to have right now guarantees
	 * that the first real width the form hands us counts as a change. */
	cachedLayoutWidth = 0.0f;
	columnMargin = INSET_STYLE_MARGIN;
	layoutScheduled = NO;
	[tableView setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(listFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:tableView];
}

/*!
 * @brief The "+" which hangs under the trailing corner of the list's card
 */
- (NSButton *)addButton
{
	NSButton	*button = [AISettingsFormView inlineSymbolButtonWithSymbolName:@"plus"
															 fallbackImageName:@"NSAddTemplate"
																		target:self
																		action:@selector(add:)];

	//A symbol has no title to fall back on, so it is named here
	[button setToolTip:AILocalizedString(@"Add", nil)];
	[button setAccessibilityLabel:AILocalizedString(@"Add", nil)];

	return button;
}

#pragma mark Configuration

/*!
 * @brief Read the terms and show them
 */
- (void)viewDidLoad
{
	[mentionTerms release];
	mentionTerms = [[NSMutableArray alloc] initWithArray:[adium.preferenceController preferenceForKey:PREF_KEY_MENTIONS
																							   group:PREF_GROUP_GENERAL]];

	[tableView reloadData];
	[self updateListHeight];

	[super viewDidLoad];
}

/*!
 * @brief Preference view is closing
 *
 * Note that this runs when the preferences <em>window</em> closes, not when the user picks another
 * pane: switching panes only takes our view out of the window. Nothing is lost by that, because
 * nothing is ever held back - every keystroke is written where it is made (-controlTextDidChange:).
 *
 * The form owns our views and may outlive this call by a moment, so every non-retaining reference
 * back to us is cut before we let go: the table's delegate and data source, and the delegate and
 * target of the controls of every row still on screen.
 */
- (void)viewWillClose
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSViewFrameDidChangeNotification
												  object:tableView];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(relayoutRows) object:nil];
	layoutScheduled = NO;

	NSTableView	*closingTableView = tableView;

	[closingTableView enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
		id	cellView = [closingTableView viewAtColumn:0 row:row makeIfNecessary:NO];

		if ([cellView isKindOfClass:[AIMentionCellView class]]) {
			[[(AIMentionCellView *)cellView textField] setDelegate:nil];
			[[(AIMentionCellView *)cellView removeButton] setTarget:nil];
		}
	}];

	[closingTableView setDelegate:nil];
	[closingTableView setDataSource:nil];

	settingsForm = nil;
	tableView = nil;
	[scrollView release]; scrollView = nil;

	[mentionTerms release]; mentionTerms = nil;

	[super viewWillClose];
}

#pragma mark Saving

/*!
 * @brief Write the terms, right now
 *
 * Refuses to write once the pane has been torn down: -viewWillClose lets go of mentionTerms while
 * the form may still hold the views, and a nil value does not empty the preference - it deletes the
 * key outright (AIPreferenceContainer). No default is registered for "Saved Mentions", so that
 * would take every term with it.
 *
 * A blank term is never saved: a row which was just added, or one the user emptied while typing,
 * stays in the list until it is filled in or removed.
 */
- (void)saveTerms
{
	if (!mentionTerms) return;

	NSMutableArray *termsCopy = [[mentionTerms mutableCopy] autorelease];

	[termsCopy removeObject:@""];

	[adium.preferenceController setPreference:termsCopy
									   forKey:PREF_KEY_MENTIONS
										group:PREF_GROUP_GENERAL];
}

#pragma mark Actions

/*!
 * @brief Add a term and put the cursor in it
 *
 * Nothing is written here: an empty term is dropped by -saveTerms anyway, and the first keystroke
 * saves it. A blank row which is already there is offered again instead of being duplicated - the
 * nib's "+" made a second, third and fourth empty row, none of which ever reached the preference.
 */
- (IBAction)add:(id)sender
{
	if (!mentionTerms) return;

	NSInteger	row = (NSInteger)[mentionTerms count] - 1;

	if (row < 0 || [[mentionTerms objectAtIndex:row] length] > 0) {
		[mentionTerms addObject:@""];

		[tableView reloadData];
		[self updateListHeight];

		row = (NSInteger)[mentionTerms count] - 1;
	}

	id	cellView = [tableView viewAtColumn:0 row:row makeIfNecessary:YES];

	if ([cellView isKindOfClass:[AIMentionCellView class]]) {
		NSTextField	*termField = [(AIMentionCellView *)cellView textField];

		[[termField window] makeFirstResponder:termField];
	}
}

/*!
 * @brief The ⊖ of a row was clicked: drop that term and write immediately
 *
 * No confirmation and no undo - which is exactly what the nib's "-" did. Editing is ended first:
 * the field editor is shared between the rows, and a field taken away while it still holds it would
 * write its text back into whichever row moves up into its place.
 */
- (IBAction)removeTermFromRowButton:(id)sender
{
	if (!mentionTerms) return;

	NSInteger	row = [tableView rowForView:(NSView *)sender];

	if (row < 0 || row >= (NSInteger)[mentionTerms count]) return;

	[[tableView window] makeFirstResponder:tableView];

	[mentionTerms removeObjectAtIndex:row];
	[self saveTerms];

	[tableView reloadData];
	[self updateListHeight];
}

/*!
 * @brief A term was typed in: write it on every keystroke
 *
 * This is the whole point of the rebuild. AIModernPreferencesWindowController takes a pane's view
 * out of the window when the user picks another pane in the sidebar and calls neither -closeView nor
 * anything which ends editing, so a term which is only written when editing ends is a term the user
 * loses by clicking on the sidebar. Written here, there is nothing left to end.
 *
 * The text is read off the field editor rather than off the field: the field's own value is only
 * brought up to date when editing ends. It has to be copied, too - the field editor hands out the
 * mutable string of its text storage, which would go on changing inside our array as the user types.
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	if (!mentionTerms) return;

	id	object = [notification object];

	if (![object isKindOfClass:[NSTextField class]]) return;

	NSTextField	*termField = (NSTextField *)object;
	NSInteger	 row = [tableView rowForView:termField];

	if (row < 0 || row >= (NSInteger)[mentionTerms count]) return;

	NSText		*fieldEditor = [[notification userInfo] objectForKey:@"NSFieldEditor"];
	NSString	*term = [[(fieldEditor ? [fieldEditor string] : [termField stringValue]) copy] autorelease];

	[mentionTerms replaceObjectAtIndex:row withObject:(term ?: @"")];
	[self saveTerms];

	/* The row's ⊖ is named after the term it would remove, and nothing reconfigures the row while it
	 * is being typed in - so without this, VoiceOver would go on announcing "Remove chef" for a row
	 * which now reads "chefin", and "Remove " for a row which was just added. The view is asked for
	 * but never made: a row which is not on screen has no label to correct. */
	id	cellView = [tableView viewAtColumn:0 row:row makeIfNecessary:NO];

	if ([cellView isKindOfClass:[AIMentionCellView class]]) {
		[[(AIMentionCellView *)cellView removeButton] setAccessibilityLabel:AIMentionRemoveAccessibilityLabel(term)];
	}
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
 * cannot end up with less room than the table laid itself out in. An empty list is one row tall: it
 * shows the empty state row instead of nothing at all.
 */
- (CGFloat)requiredListHeight
{
	CGFloat		spacing = [tableView intercellSpacing].height;
	NSInteger	tableRows = [tableView numberOfRows];
	CGFloat		endPadding = INSET_STYLE_PADDING;

	if (tableRows > 0) {
		CGFloat		topInset = NSMinY([tableView rectOfRow:0]);

		if (topInset >= 0.0f) endPadding = topInset;
	}

	NSInteger	rowCount = MAX((NSInteger)[mentionTerms count], 1);
	CGFloat		height = ((CGFloat)rowCount * (MENTION_ROW_HEIGHT + spacing)) + (2.0f * endPadding);

	if (tableRows > 0) {
		CGFloat		contentHeight = NSMaxY([tableView rectOfRow:(tableRows - 1)]) + endPadding;

		if (contentHeight > height) height = contentHeight;
	}

	return ceil(height);
}

/*!
 * @brief Grow or shrink the card around the list to fit its rows
 *
 * The list is the edge to edge row of a card, so its height is the card's height. Handing the new
 * height to the form makes the form resize its card and itself, and the preferences window - which
 * watches the pane's frame - resizes its scrolling column in turn. Forget this and the height
 * measured when the list was hung into the form is frozen, and the list scrolls inside its card
 * instead of the card growing.
 */
- (void)updateListHeight
{
	if (!scrollView) return;

	CGFloat		height = [self requiredListHeight];

	if (fabs(NSHeight([scrollView frame]) - height) < 0.5f) return;

	[scrollView setFrameSize:NSMakeSize(NSWidth([scrollView frame]), height)];
	[settingsForm noteContentSizeChanged];
}

/*!
 * @brief Keep the single column as wide as the room the list has
 *
 * A table does not reliably re-tile its columns when it is widened, and a column left behind lays
 * every row out narrower than the card - which puts the ⊖ in the middle of the row and stops the
 * hairline short of the card's edge. A column left <em>wider</em> than the clip view is worse still,
 * because the list has no scrollers and the trailing end of every row would then be unreachable.
 */
- (void)synchronizeColumnWidth
{
	NSTableColumn	*termColumn = [tableView tableColumnWithIdentifier:MENTION_COLUMN_IDENTIFIER];
	CGFloat			 clipWidth = NSWidth([[scrollView contentView] bounds]);

	if (!termColumn || clipWidth <= 0.0f) return;

	CGFloat			 tableWidth = NSWidth([tableView bounds]);
	CGFloat			 observedMargin = tableWidth - [termColumn width];

	/* While the table is tiled to its clip view, whatever it keeps beside its column is the truth
	 * about this table style on this system; remember it instead of assuming 16pt per side. */
	if ((fabs(tableWidth - clipWidth) < 0.5f) &&
		(observedMargin >= 0.0f) && (observedMargin <= (INSET_STYLE_MARGIN * 2.0f))) {
		columnMargin = observedMargin;
	}

	CGFloat			 targetWidth = clipWidth - columnMargin;

	if (targetWidth < [termColumn minWidth]) targetWidth = [termColumn minWidth];

	if (fabs([termColumn width] - targetWidth) > 0.5f) [termColumn setWidth:targetWidth];
}

/*!
 * @brief How far the inset table style keeps a row away from the edge of the card
 */
- (CGFloat)rowInsetPerSide
{
	NSTableColumn	*termColumn = [tableView tableColumnWithIdentifier:MENTION_COLUMN_IDENTIFIER];
	CGFloat			 tableWidth = NSWidth([tableView bounds]);
	CGFloat			 columnWidth = (termColumn ? [termColumn width] : 0.0f);

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
 * @brief Re-tile the column and reconfigure the visible rows for the new width
 *
 * Row heights are constant, so nothing has to be recalculated; the rows on screen are reconfigured
 * in place, which is what moves their hairlines out to the card's new edge.
 */
- (void)relayoutRows
{
	layoutScheduled = NO;

	[self synchronizeColumnWidth];
	//The end padding only becomes measurable once the table has tiled, so the height may still move
	[self updateListHeight];

	NSTableView	*listTableView = tableView;

	[listTableView enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
		id	cellView = [listTableView viewAtColumn:0 row:row makeIfNecessary:NO];

		if ([cellView isKindOfClass:[AIMentionCellView class]]) {
			[self configureCellView:(AIMentionCellView *)cellView forRow:row];
		}
	}];
}

#pragma mark Table view data source and delegate

/*!
 * @brief An empty list still has one row: the one saying that it is empty
 */
- (NSInteger)numberOfRowsInTableView:(NSTableView *)inTableView
{
	NSInteger	termCount = (NSInteger)[mentionTerms count];

	return (termCount > 0 ? termCount : 1);
}

/*!
 * @brief Rows cannot be selected
 *
 * Nothing acts on a selection: a row is a text field and a ⊖, and both work on the row they sit in.
 */
- (BOOL)tableView:(NSTableView *)inTableView shouldSelectRow:(NSInteger)row
{
	return NO;
}

- (CGFloat)tableView:(NSTableView *)inTableView heightOfRow:(NSInteger)row
{
	return MENTION_ROW_HEIGHT;
}

- (id)tableView:(NSTableView *)inTableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	//View based: the row's own text field carries the term. Answered all the same for anything asking.
	if (row < 0 || row >= (NSInteger)[mentionTerms count]) return nil;

	return [mentionTerms objectAtIndex:row];
}

- (NSView *)tableView:(NSTableView *)inTableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (![mentionTerms count]) {
		/* The shape System Settings gives a list with nothing in it yet. It lives in the table rather
		 * than in an -addEmptyStateRow: of the form, so that adding the first term does not mean
		 * tearing the whole form down and building it again - which would happen at exactly the
		 * moment the user is about to type into the row that rebuild throws away. */
		NSTableCellView	*emptyView = [inTableView makeViewWithIdentifier:MENTION_EMPTY_IDENTIFIER owner:self];

		if (![emptyView isKindOfClass:[NSTableCellView class]] || [emptyView isKindOfClass:[AIMentionCellView class]]) {
			NSTextField	*label = AIMentionEmptyLabel();

			emptyView = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f,
																		   NSWidth([inTableView bounds]),
																		   MENTION_ROW_HEIGHT)] autorelease];
			[emptyView setIdentifier:MENTION_EMPTY_IDENTIFIER];
			[emptyView addSubview:label];
			[emptyView setTextField:label];

			[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
				[[label leadingAnchor] constraintEqualToAnchor:[emptyView leadingAnchor] constant:CELL_H_PADDING],
				[[label trailingAnchor] constraintEqualToAnchor:[emptyView trailingAnchor] constant:-CELL_H_PADDING],
				[[label centerYAnchor] constraintEqualToAnchor:[emptyView centerYAnchor]],
				nil]];
		}

		[[emptyView textField] setStringValue:AILocalizedString(@"No Terms", "Shown instead of the list when no terms have been added yet")];

		return emptyView;
	}

	AIMentionCellView	*cellView = (AIMentionCellView *)[inTableView makeViewWithIdentifier:MENTION_CELL_IDENTIFIER
																					   owner:self];

	if (![cellView isKindOfClass:[AIMentionCellView class]]) {
		cellView = [[[AIMentionCellView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f,
																		NSWidth([inTableView bounds]),
																		MENTION_ROW_HEIGHT)] autorelease];
	}

	[self configureCellView:cellView forRow:row];

	return cellView;
}

/*!
 * @brief Fill a row's view with the term it shows
 */
- (void)configureCellView:(AIMentionCellView *)cellView forRow:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[mentionTerms count]) return;

	NSString	*term = [mentionTerms objectAtIndex:row];
	NSTextField	*termField = [cellView textField];

	[termField setDelegate:self];
	/* Never while the user is typing in this very field - a width change reconfigures the rows which
	 * are on screen, and setting the value of a field which is being edited throws the insertion
	 * point to the end of the line. -currentEditor is nil unless this field holds the field editor,
	 * and what it holds is what we were told about keystroke by keystroke anyway. */
	if (![termField currentEditor] && ![[termField stringValue] isEqualToString:term]) {
		[termField setStringValue:term];
	}
	[termField setPlaceholderString:AILocalizedString(@"New Term", "Placeholder of an empty row of the list of terms which highlight a message")];

	[[cellView removeButton] setTarget:self];
	[[cellView removeButton] setAction:@selector(removeTermFromRowButton:)];
	[[cellView removeButton] setToolTip:AILocalizedString(@"Remove", nil)];
	[[cellView removeButton] setAccessibilityLabel:AIMentionRemoveAccessibilityLabel(term)];

	/* The hairline sits between two rows, so there is none below the last one. It runs from the text
	 * indent out to the card's edge - past the trailing edge of the cell, which the inset table style
	 * keeps away from that edge - stopping where every other card's rows stop. */
	[[cellView separatorTrailingConstraint] setConstant:([self rowInsetPerSide] - SEPARATOR_CARD_MARGIN)];
	[[cellView separator] setHidden:(row >= ((NSInteger)[mentionTerms count] - 1))];
}

@end
