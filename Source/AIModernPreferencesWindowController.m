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

#import "AIModernPreferencesWindowController.h"

#import <Adium/AIPreferencePane.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <AIUtilities/AIStringAdditions.h>

#define MODERN_PREFS_SELECTED_PANE_KEY	@"AIModernPreferencesSelectedPane"

static const CGFloat AIPrefsSidebarMinWidth = 190.0;
static const CGFloat AIPrefsSidebarMaxWidth = 240.0;
static const CGFloat AIPrefsContentWidth = 680.0;
static const CGFloat AIPrefsContentMinHeight = 380.0;
static const CGFloat AIPrefsContentPadding = 20.0;

static AIModernPreferencesWindowController *sharedModernPrefsController = nil;

/* The main panes speak the SS_PreferencePaneProtocol (paneName/paneView/…);
 * the advanced panes are plain AIModularPanes (label/view). These helpers
 * bridge both without touching the pane classes. */
static NSString *AIPrefPaneName(id pane)
{
	return [pane respondsToSelector:@selector(paneName)] ? [pane paneName] : [pane label];
}

static NSString *AIPrefPaneIdentifier(id pane)
{
	return [pane respondsToSelector:@selector(paneIdentifier)] ? [pane paneIdentifier] : [pane label];
}

static NSView *AIPrefPaneView(id pane)
{
	return [pane respondsToSelector:@selector(paneView)] ? [pane paneView] : [pane view];
}

static NSImage *AIPrefPaneIcon(id pane)
{
	if ([pane respondsToSelector:@selector(paneIcon)]) return [pane paneIcon];
	if ([pane respondsToSelector:@selector(image)]) return [pane performSelector:@selector(image)];
	return nil;
}

/*!
 * @brief Document view of the content scroll view.
 *
 * Flipped so a pane shorter than the visible area sticks to the top instead
 * of floating at the bottom, the way scrolling settings panes behave.
 */
@interface AIPrefsContentContainerView : NSView
@end

@implementation AIPrefsContentContainerView
- (BOOL)isFlipped
{
	return YES;
}
@end

/*!
 * @brief Sidebar row that mirrors the System Settings text colors.
 *
 * AppKit's automatic label coloring tints the selected row with the accent
 * color, while System Settings dims every label — including the selected
 * one — as soon as the window is no longer key. Take the colors over.
 */
@interface AIPrefsSidebarCellView : NSTableCellView {
	BOOL isGroupRow;
}
@property (assign) BOOL isGroupRow;
- (void)updateTextColors;
@end

@implementation AIPrefsSidebarCellView

@synthesize isGroupRow;

- (void)setBackgroundStyle:(NSBackgroundStyle)style
{
	[super setBackgroundStyle:style];
	[self updateTextColors];
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	[self updateTextColors];
}

- (void)updateTextColors
{
	BOOL windowActive = [[self window] isKeyWindow] || [[self window] isMainWindow];
	NSColor *color;

	if (isGroupRow) {
		color = (windowActive ? [NSColor secondaryLabelColor] : [NSColor tertiaryLabelColor]);
	} else if (!windowActive) {
		//Inactive window: everything dims, the selected row included
		color = [NSColor secondaryLabelColor];
	} else if ([self backgroundStyle] == NSBackgroundStyleEmphasized) {
		color = [NSColor alternateSelectedControlTextColor];
	} else {
		color = [NSColor labelColor];
	}

	[[self textField] setTextColor:color];
}

@end

@interface AIModernPreferencesWindowController ()
- (void)buildSidebarEntries;
- (void)buildWindow;
- (AIPreferencePane *)paneWithIdentifier:(NSString *)identifier;
- (void)selectPane:(AIPreferencePane *)pane;
- (void)layoutCurrentPane;
- (void)updateNavigationControl;
- (void)refreshSidebarColors:(NSNotification *)notification;
- (void)paneViewFrameChanged:(NSNotification *)notification;
- (CGFloat)contentTopInset;
- (void)navigate:(id)sender;
- (NSString *)mainPaneOrderIdentifiers;
@end

@implementation AIModernPreferencesWindowController

+ (AIModernPreferencesWindowController *)sharedController
{
	if (!sharedModernPrefsController) {
		sharedModernPrefsController = [[self alloc] init];
	}
	return sharedModernPrefsController;
}

+ (void)closeSharedController
{
	if (sharedModernPrefsController) {
		[sharedModernPrefsController close];
	}
}

- (id)init
{
	if ((self = [super initWithWindow:nil])) {
		sidebarEntries = [[NSMutableArray alloc] init];
		openedPanes = [[NSMutableSet alloc] init];
		history = [[NSMutableArray alloc] init];
		historyIndex = -1;
		[self buildSidebarEntries];
		[self buildWindow];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[sidebarEntries release];
	[openedPanes release];
	[history release];
	[navigationControl release];
	[toolbarTitleField release];
	[super dealloc];
}

#pragma mark - Data

/*!
 * @brief The main panes in their classic order, followed by the advanced group.
 *
 * Accounts leads (like the old shell), the remaining main panes follow the
 * historic order, and every advanced pane becomes its own entry under an
 * "Advanced" group header — that flattening is the System Settings idiom
 * and replaces the nested shelf container of the old Advanced pane.
 */
- (NSString *)mainPaneOrderIdentifiers
{
	return @"Accounts,General,Personal,Appearance,Messages,Status,Events,File Transfer";
}

- (void)buildSidebarEntries
{
	[sidebarEntries removeAllObjects];

	NSMutableArray *mainPanes = [[[adium.preferenceController paneArray] mutableCopy] autorelease];
	for (NSString *identifier in [[self mainPaneOrderIdentifiers] componentsSeparatedByString:@","]) {
		for (AIPreferencePane *pane in mainPanes) {
			if ([AIPrefPaneIdentifier(pane) isEqualToString:identifier] || [AIPrefPaneName(pane) isEqualToString:identifier]) {
				[sidebarEntries addObject:pane];
				[mainPanes removeObject:pane];
				break;
			}
		}
	}
	//Anything unordered (third party panes), minus the old Advanced container we replace
	for (AIPreferencePane *pane in mainPanes) {
		if (![AIPrefPaneIdentifier(pane) isEqualToString:@"Advanced"]) {
			[sidebarEntries addObject:pane];
		}
	}

	NSArray *advancedPanes = [[adium.preferenceController advancedPaneArray] sortedArrayUsingComparator:
		^NSComparisonResult(id a, id b) {
			return [AIPrefPaneName(a) localizedCaseInsensitiveCompare:AIPrefPaneName(b)];
		}];
	if (advancedPanes.count) {
		[sidebarEntries addObject:AILocalizedString(@"Advanced", nil)];
		[sidebarEntries addObjectsFromArray:advancedPanes];
	}
}

- (AIPreferencePane *)paneWithIdentifier:(NSString *)identifier
{
	for (id entry in sidebarEntries) {
		if (![entry isKindOfClass:[NSString class]] &&
			([AIPrefPaneIdentifier(entry) caseInsensitiveCompare:identifier] == NSOrderedSame ||
			 [AIPrefPaneName(entry) caseInsensitiveCompare:identifier] == NSOrderedSame)) {
			return entry;
		}
	}
	return nil;
}

#pragma mark - Window construction

- (void)buildWindow
{
	NSRect contentRect = NSMakeRect(0, 0, AIPrefsSidebarMinWidth + AIPrefsContentWidth, 560);
	NSWindow *window = [[[NSWindow alloc] initWithContentRect:contentRect
													styleMask:(NSWindowStyleMaskTitled |
															   NSWindowStyleMaskClosable |
															   NSWindowStyleMaskMiniaturizable |
															   NSWindowStyleMaskResizable |
															   NSWindowStyleMaskFullSizeContentView)
													  backing:NSBackingStoreBuffered
														defer:NO] autorelease];
	[window setReleasedWhenClosed:NO];
	[window setTitlebarAppearsTransparent:NO];
	/* The title lives in the toolbar as its own item so the navigation arrows
	 * can sit before it, the way System Settings arranges them. -setTitle: is
	 * still used: the Window menu and Mission Control read it. */
	[window setTitleVisibility:NSWindowTitleHidden];
	if (@available(macOS 11.0, *)) {
		[window setToolbarStyle:NSWindowToolbarStyleUnified];
		/* No hairline under the titlebar: the content scrolls underneath the
		 * titlebar material, which blurs it — the way System Settings behaves. */
		[window setTitlebarSeparatorStyle:NSTitlebarSeparatorStyleNone];
	}
	NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:@"AIModernPreferencesToolbar"] autorelease];
	[toolbar setShowsBaselineSeparator:NO];
	[toolbar setDelegate:self];
	[toolbar setAllowsUserCustomization:NO];
	[window setToolbar:toolbar];
	[window setContentMinSize:NSMakeSize(AIPrefsSidebarMinWidth + AIPrefsContentWidth, AIPrefsContentMinHeight)];
	[window setContentSize:NSMakeSize(AIPrefsSidebarMinWidth + AIPrefsContentWidth, 620)];
	[window setFrameAutosaveName:@"AIModernPreferencesWindow"];
	[window center];

	//Sidebar: source list outline in a scroll view
	outlineView = [[[NSOutlineView alloc] initWithFrame:NSZeroRect] autorelease];
	NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"pane"] autorelease];
	[column setEditable:NO];
	[outlineView addTableColumn:column];
	[outlineView setOutlineTableColumn:column];
	[outlineView setHeaderView:nil];
	[outlineView setDataSource:self];
	[outlineView setDelegate:self];
	[outlineView setFloatsGroupRows:NO];
	[outlineView setRowSizeStyle:NSTableViewRowSizeStyleDefault];
	if (@available(macOS 11.0, *)) {
		[outlineView setStyle:NSTableViewStyleSourceList];
	} else {
		[outlineView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
	}

	NSScrollView *sidebarScroll = [[[NSScrollView alloc] initWithFrame:NSZeroRect] autorelease];
	[sidebarScroll setDocumentView:outlineView];
	[sidebarScroll setHasVerticalScroller:YES];
	[sidebarScroll setDrawsBackground:NO];

	NSViewController *sidebarVC = [[[NSViewController alloc] init] autorelease];
	[sidebarVC setView:sidebarScroll];

	//Content: a scrolling column. The pane keeps its natural height; when it
	//does not fit, the column scrolls instead of the window growing.
	contentHost = [[[AIPrefsContentContainerView alloc] initWithFrame:NSMakeRect(0, 0, AIPrefsContentWidth, 560)] autorelease];
	[contentHost setWantsLayer:YES];

	NSScrollView *contentScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, AIPrefsContentWidth, 560)] autorelease];
	[contentScroll setDocumentView:contentHost];
	[contentScroll setHasVerticalScroller:YES];
	[contentScroll setAutohidesScrollers:YES];
	[contentScroll setDrawsBackground:NO];
	//Inset is applied explicitly in -layoutCurrentPane; the automatic one does
	//not engage for a scroll view nested in a split view item, which left the
	//first rows hidden underneath the titlebar even when scrolled to the top.
	[contentScroll setAutomaticallyAdjustsContentInsets:NO];

	/* The column can change width without the window resizing — dragging the
	 * sidebar divider, or a scroller appearing — and the document view does not
	 * follow the clip view on its own. Re-lay out whenever the clip view moves.
	 */
	[[contentScroll contentView] setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(contentClipViewFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:[contentScroll contentView]];

	NSViewController *contentVC = [[[NSViewController alloc] init] autorelease];
	[contentVC setView:contentScroll];

	NSSplitViewController *splitVC = [[[NSSplitViewController alloc] init] autorelease];
	NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarVC];
	[sidebarItem setMinimumThickness:AIPrefsSidebarMinWidth];
	[sidebarItem setMaximumThickness:AIPrefsSidebarMaxWidth];
	[sidebarItem setCanCollapse:NO];
	NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:contentVC];
	[contentItem setMinimumThickness:AIPrefsContentWidth];
	if (@available(macOS 11.0, *)) {
		/* Each split view item decides on its own titlebar separator and
		 * overrides the window's setting, so the hairline has to go here. */
		[sidebarItem setTitlebarSeparatorStyle:NSTitlebarSeparatorStyleNone];
		[contentItem setTitlebarSeparatorStyle:NSTitlebarSeparatorStyleNone];
	}
	[splitVC addSplitViewItem:sidebarItem];
	[splitVC addSplitViewItem:contentItem];

	[window setContentViewController:splitVC];
	[self setWindow:window];
	[window setDelegate:(id<NSWindowDelegate>)self];

	//System Settings dims the whole sidebar while the window is not key
	for (NSString *name in [NSArray arrayWithObjects:NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification,
													 NSWindowDidBecomeMainNotification, NSWindowDidResignMainNotification, nil]) {
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(refreshSidebarColors:)
													 name:name
												   object:window];
	}

	[outlineView reloadData];
	for (id entry in sidebarEntries) {
		if ([entry isKindOfClass:[NSString class]]) {
			[outlineView expandItem:entry];
		}
	}
}

#pragma mark - Selection

- (void)showWindowAndSelectPaneWithIdentifier:(NSString *)identifier
{
	AIPreferencePane *pane = (identifier ? [self paneWithIdentifier:identifier] : nil);
	if (!pane) {
		NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:MODERN_PREFS_SELECTED_PANE_KEY];
		pane = (saved ? [self paneWithIdentifier:saved] : nil);
	}
	if (!pane) {
		for (id entry in sidebarEntries) {
			if (![entry isKindOfClass:[NSString class]]) {
				pane = entry;
				break;
			}
		}
	}

	[self showWindow:nil];
	if (pane) {
		[self selectPane:pane];
	}
}

- (void)selectPane:(AIPreferencePane *)pane
{
	if (!pane || pane == currentPane) {
		return;
	}

	NSView *paneView = AIPrefPaneView(pane);
	if (!paneView) {
		return;
	}

	for (NSView *subview in [[[contentHost subviews] copy] autorelease]) {
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:NSViewFrameDidChangeNotification
													  object:subview];
		[subview removeFromSuperview];
	}

	currentPane = pane;
	[openedPanes addObject:pane];

	if (!navigatingHistory) {
		//A fresh selection truncates whatever was ahead in the history
		if (historyIndex >= 0 && historyIndex + 1 < (NSInteger)[history count]) {
			[history removeObjectsInRange:NSMakeRange(historyIndex + 1, [history count] - historyIndex - 1)];
		}
		[history addObject:pane];
		historyIndex = (NSInteger)[history count] - 1;
	}
	[self updateNavigationControl];

	[paneView setAutoresizingMask:NSViewWidthSizable];
	[paneView setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(paneViewFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:paneView];
	[contentHost addSubview:paneView];
	[self layoutCurrentPane];
	[[[contentHost enclosingScrollView] contentView] scrollToPoint:NSMakePoint(0, -[self contentTopInset])];

	NSString *paneTitle = (AIPrefPaneName(pane) ?: @"");
	[[self window] setTitle:paneTitle];
	[toolbarTitleField setStringValue:paneTitle];

	NSInteger row = [outlineView rowForItem:pane];
	if (row >= 0 && [outlineView selectedRow] != row) {
		[outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	}

	NSString *selectedIdentifier = AIPrefPaneIdentifier(pane);
	if (selectedIdentifier) {
		[[NSUserDefaults standardUserDefaults] setObject:selectedIdentifier forKey:MODERN_PREFS_SELECTED_PANE_KEY];
	}
}

/*!
 * @brief Size the scrolling column and place the pane at its top.
 *
 * The document view is at least as tall as the visible area so short panes
 * do not leave the column scrollable for no reason.
 */
- (void)layoutCurrentPane
{
	NSView *paneView = [[contentHost subviews] lastObject];
	if (!paneView) {
		return;
	}

	NSScrollView *scrollView = [contentHost enclosingScrollView];
	NSClipView *clipView = [scrollView contentView];

	//Keep the content clear of the titlebar it scrolls underneath
	CGFloat topInset = [self contentTopInset];
	NSEdgeInsets insets = [scrollView contentInsets];
	if (insets.top != topInset) {
		[scrollView setContentInsets:NSEdgeInsetsMake(topInset, 0, 0, 0)];
		[scrollView setScrollerInsets:NSEdgeInsetsMake(topInset, 0, 0, 0)];
	}
	/* The clip view's own bounds, not -contentSize: with autohiding scrollers
	 * -contentSize still reports the width the column had before the vertical
	 * scroller appeared, which would push the card's right edge out of sight.
	 */
	NSSize visibleSize = (clipView ? [clipView bounds].size : [scrollView contentSize]);
	CGFloat paneHeight = NSHeight([paneView frame]);
	CGFloat documentHeight = MAX(paneHeight + 2 * AIPrefsContentPadding, visibleSize.height);

	[contentHost setFrame:NSMakeRect(0, 0, visibleSize.width, documentHeight)];
	//Setting the pane's frame posts a frame-change notification of its own
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSViewFrameDidChangeNotification
												  object:paneView];
	//Flipped container: y grows downwards, so the padding puts the pane on top.
	[paneView setFrame:NSMakeRect(0, AIPrefsContentPadding, visibleSize.width, paneHeight)];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(paneViewFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:paneView];

	/* The pane may have grown or shrunk to fit its new width (AISettingsFormView
	 * reflows), so the document view height above can already be stale.
	 */
	CGFloat settledHeight = NSHeight([paneView frame]);
	if (fabs(settledHeight - paneHeight) > 0.5) {
		[contentHost setFrame:NSMakeRect(0, 0, visibleSize.width,
										 MAX(settledHeight + 2 * AIPrefsContentPadding, visibleSize.height))];
	}
}

/*!
 * @brief The scrolling column changed width without the window resizing.
 *
 * Dragging the sidebar divider and a vertical scroller appearing both do that;
 * neither sends -windowDidResize:, and the document view has no autoresizing
 * mask that would follow the clip view.
 */
- (void)contentClipViewFrameChanged:(NSNotification *)notification
{
	if (layingOutPane) {
		return;
	}

	layingOutPane = YES;
	[self layoutCurrentPane];
	layingOutPane = NO;
}

/*!
 * @brief Height of the titlebar area the content scrolls underneath
 */
- (CGFloat)contentTopInset
{
	NSWindow *window = [self window];
	CGFloat inset = NSHeight([[window contentView] frame]) - NSHeight([window contentLayoutRect]);
	return (inset > 0 ? inset : 0);
}

- (void)windowDidResize:(NSNotification *)notification
{
	[self layoutCurrentPane];
}

/*!
 * @brief A pane grew or shrank on its own (a list gained rows, a label wrapped)
 *
 * Resize the scrolling column to match instead of leaving the pane clipped.
 */
- (void)paneViewFrameChanged:(NSNotification *)notification
{
	if ([notification object] == [[contentHost subviews] lastObject]) {
		[self layoutCurrentPane];
	}
}

- (void)refreshSidebarColors:(NSNotification *)notification
{
	for (NSInteger row = 0; row < [outlineView numberOfRows]; row++) {
		id view = [outlineView viewAtColumn:0 row:row makeIfNecessary:NO];
		if ([view isKindOfClass:[AIPrefsSidebarCellView class]]) {
			[(AIPrefsSidebarCellView *)view updateTextColors];
		}
	}
}

#pragma mark - Back/forward navigation

- (void)updateNavigationControl
{
	if (!navigationControl) {
		return;
	}
	[navigationControl setEnabled:(historyIndex > 0) forSegment:0];
	[navigationControl setEnabled:(historyIndex >= 0 && historyIndex + 1 < (NSInteger)[history count]) forSegment:1];
}

- (void)navigate:(id)sender
{
	NSInteger target = historyIndex + ([sender selectedSegment] == 0 ? -1 : 1);
	if (target < 0 || target >= (NSInteger)[history count]) {
		return;
	}

	historyIndex = target;
	navigatingHistory = YES;
	[self selectPane:[history objectAtIndex:(NSUInteger)target]];
	navigatingHistory = NO;
}

#pragma mark - Toolbar delegate

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	if (@available(macOS 11.0, *)) {
		//The tracking separator keeps our items aligned with the content column
		return [NSArray arrayWithObjects:NSToolbarSidebarTrackingSeparatorItemIdentifier,
										 @"navigation", @"paneTitle", nil];
	}
	return [NSArray arrayWithObjects:@"navigation", @"paneTitle", nil];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
	 itemForItemIdentifier:(NSString *)identifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
	if ([identifier isEqualToString:@"paneTitle"]) {
		if (!toolbarTitleField) {
			toolbarTitleField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 22)];
			[toolbarTitleField setBordered:NO];
			[toolbarTitleField setEditable:NO];
			[toolbarTitleField setDrawsBackground:NO];
			[toolbarTitleField setFont:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold]];
			[toolbarTitleField setTextColor:[NSColor labelColor]];
			[toolbarTitleField setStringValue:(currentPane ? (AIPrefPaneName(currentPane) ?: @"") : @"")];
		}
		NSToolbarItem *titleItem = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
		[titleItem setView:toolbarTitleField];
		[titleItem setLabel:@""];
		[titleItem setVisibilityPriority:NSToolbarItemVisibilityPriorityHigh];
		return titleItem;
	}

	if (![identifier isEqualToString:@"navigation"]) {
		return nil;
	}

	if (!navigationControl) {
		NSImage *back = nil, *forward = nil;
		if (@available(macOS 11.0, *)) {
			back = [NSImage imageWithSystemSymbolName:@"chevron.backward"
							 accessibilityDescription:AILocalizedString(@"Back", nil)];
			forward = [NSImage imageWithSystemSymbolName:@"chevron.forward"
								accessibilityDescription:AILocalizedString(@"Forward", nil)];
		}
		if (!back) back = [NSImage imageNamed:NSImageNameGoLeftTemplate];
		if (!forward) forward = [NSImage imageNamed:NSImageNameGoRightTemplate];

		navigationControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 72, 24)];
		[navigationControl setSegmentCount:2];
		[navigationControl setSegmentStyle:NSSegmentStyleSeparated];
		[navigationControl setTrackingMode:NSSegmentSwitchTrackingMomentary];
		[navigationControl setImage:back forSegment:0];
		[navigationControl setImage:forward forSegment:1];
		[navigationControl setTarget:self];
		[navigationControl setAction:@selector(navigate:)];
		[self updateNavigationControl];
	}

	NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
	[item setView:navigationControl];
	[item setLabel:@""];
	[item setPaletteLabel:AILocalizedString(@"Navigation", nil)];
	[item setVisibilityPriority:NSToolbarItemVisibilityPriorityHigh];
	return item;
}

#pragma mark - Outline view data source

- (NSInteger)outlineView:(NSOutlineView *)aView numberOfChildrenOfItem:(id)item
{
	if (item == nil) {
		//Top level: panes before the first group header, plus the headers
		NSInteger count = 0;
		for (id entry in sidebarEntries) {
			if ([entry isKindOfClass:[NSString class]]) {
				count++;
			} else if ([self outlineView:aView parentForItem:entry] == nil) {
				count++;
			}
		}
		return count;
	}
	if ([item isKindOfClass:[NSString class]]) {
		NSInteger count = 0;
		BOOL inGroup = NO;
		for (id entry in sidebarEntries) {
			if (entry == item) {
				inGroup = YES;
			} else if ([entry isKindOfClass:[NSString class]]) {
				if (inGroup) break;
			} else if (inGroup) {
				count++;
			}
		}
		return count;
	}
	return 0;
}

- (id)outlineView:(NSOutlineView *)aView child:(NSInteger)index ofItem:(id)item
{
	if (item == nil) {
		NSInteger seen = -1;
		for (id entry in sidebarEntries) {
			if ([entry isKindOfClass:[NSString class]] || [self outlineView:aView parentForItem:entry] == nil) {
				if (++seen == index) return entry;
			}
		}
		return nil;
	}
	NSInteger seen = -1;
	BOOL inGroup = NO;
	for (id entry in sidebarEntries) {
		if (entry == item) {
			inGroup = YES;
		} else if ([entry isKindOfClass:[NSString class]]) {
			if (inGroup) break;
		} else if (inGroup) {
			if (++seen == index) return entry;
		}
	}
	return nil;
}

/*!
 * @brief The group header a pane belongs to, or nil for ungrouped top-level panes.
 */
- (id)outlineView:(NSOutlineView *)aView parentForItem:(id)item
{
	id lastHeader = nil;
	for (id entry in sidebarEntries) {
		if ([entry isKindOfClass:[NSString class]]) {
			lastHeader = entry;
		} else if (entry == item) {
			return lastHeader;
		}
	}
	return nil;
}

- (BOOL)outlineView:(NSOutlineView *)aView isItemExpandable:(id)item
{
	return [item isKindOfClass:[NSString class]];
}

#pragma mark - Outline view delegate

- (BOOL)outlineView:(NSOutlineView *)aView isGroupItem:(id)item
{
	return [item isKindOfClass:[NSString class]];
}

- (BOOL)outlineView:(NSOutlineView *)aView shouldSelectItem:(id)item
{
	return ![item isKindOfClass:[NSString class]];
}

- (NSView *)outlineView:(NSOutlineView *)aView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	BOOL isGroup = [item isKindOfClass:[NSString class]];
	NSString *reuseIdentifier = (isGroup ? @"group" : @"pane");
	NSTableCellView *cell = [aView makeViewWithIdentifier:reuseIdentifier owner:self];

	if (!cell) {
		cell = [[[AIPrefsSidebarCellView alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)] autorelease];
		[cell setIdentifier:reuseIdentifier];

		NSTextField *label = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
		[label setBordered:NO];
		[label setEditable:NO];
		[label setDrawsBackground:NO];
		[label setLineBreakMode:NSLineBreakByTruncatingTail];
		[label setTranslatesAutoresizingMaskIntoConstraints:NO];
		[cell addSubview:label];
		[cell setTextField:label];

		if (!isGroup) {
			NSImageView *icon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
			[icon setTranslatesAutoresizingMaskIntoConstraints:NO];
			[cell addSubview:icon];
			[cell setImageView:icon];

			[cell addConstraints:[NSArray arrayWithObjects:
				[NSLayoutConstraint constraintWithItem:icon attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual
												toItem:cell attribute:NSLayoutAttributeLeading multiplier:1 constant:0],
				[NSLayoutConstraint constraintWithItem:icon attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual
												toItem:cell attribute:NSLayoutAttributeCenterY multiplier:1 constant:0],
				[NSLayoutConstraint constraintWithItem:icon attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual
												toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:18],
				[NSLayoutConstraint constraintWithItem:icon attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual
												toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:18],
				[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual
												toItem:icon attribute:NSLayoutAttributeTrailing multiplier:1 constant:6],
				[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationLessThanOrEqual
												toItem:cell attribute:NSLayoutAttributeTrailing multiplier:1 constant:-4],
				[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual
												toItem:cell attribute:NSLayoutAttributeCenterY multiplier:1 constant:0],
				nil]];
		} else {
			[cell addConstraints:[NSArray arrayWithObjects:
				[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual
												toItem:cell attribute:NSLayoutAttributeLeading multiplier:1 constant:0],
				[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationLessThanOrEqual
												toItem:cell attribute:NSLayoutAttributeTrailing multiplier:1 constant:-4],
				[NSLayoutConstraint constraintWithItem:label attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual
												toItem:cell attribute:NSLayoutAttributeCenterY multiplier:1 constant:0],
				nil]];
		}
	}

	[(AIPrefsSidebarCellView *)cell setIsGroupRow:isGroup];

	if (isGroup) {
		[[cell textField] setStringValue:(NSString *)item];
		[[cell textField] setFont:[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold]];
	} else {
		id pane = item;
		[[cell textField] setStringValue:(AIPrefPaneName(pane) ?: @"")];
		[[cell textField] setFont:[NSFont systemFontOfSize:13]];
		NSImage *icon = AIPrefPaneIcon(pane);
		[icon setSize:NSMakeSize(18, 18)];
		[[cell imageView] setImage:icon];
	}
	[(AIPrefsSidebarCellView *)cell updateTextColors];

	return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	id item = [outlineView itemAtRow:[outlineView selectedRow]];
	if (item && ![item isKindOfClass:[NSString class]]) {
		[self selectPane:item];
	}
}

#pragma mark - Window delegate

- (void)windowWillClose:(NSNotification *)notification
{
	//Give every pane that was shown a chance to save and tear down,
	//matching the behavior of the old SS_PrefsController shell.
	for (AIPreferencePane *pane in openedPanes) {
		[pane closeView];
	}
	[openedPanes removeAllObjects];
	currentPane = nil;
	for (NSView *subview in [[[contentHost subviews] copy] autorelease]) {
		[subview removeFromSuperview];
	}

	[sharedModernPrefsController autorelease];
	sharedModernPrefsController = nil;
}

@end
