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

/*!
 * @brief Refuse frames that would displace or clip the pane.
 *
 * Every legitimate caller — -layoutCurrentPane and the form's own document
 * height update — puts this view at the origin and never below its content.
 * Frames from anywhere else arrive anyway: measured live, a document view
 * holding a 1014 point pane stood at origin y = -66 with a height of 560,
 * which cut everything past the first screen off, and no code of ours writes
 * either number. Whoever it is, the answer is an invariant rather than a hunt:
 * the origin is always zero, and the height never falls below the lowest
 * subview plus the standard padding. Growing beyond that stays allowed — a
 * short pane's document is deliberately taller than its content.
 */
- (NSRect)constrainedFrame:(NSRect)frame
{
	CGFloat need = 0.0;

	for (NSView *subview in [self subviews]) {
		need = MAX(need, NSMaxY([subview frame]));
	}

	frame.origin = NSZeroPoint;
	frame.size.height = MAX(frame.size.height, ceil(need + AIPrefsContentPadding));

	return frame;
}

- (void)setFrame:(NSRect)frame
{
	[super setFrame:[self constrainedFrame:frame]];
}

- (void)setFrameSize:(NSSize)newSize
{
	NSRect frame = [self constrainedFrame:NSMakeRect(0, 0, newSize.width, newSize.height)];

	[super setFrameSize:frame.size];
}

- (void)setFrameOrigin:(NSPoint)newOrigin
{
	[super setFrameOrigin:NSZeroPoint];
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
	__unsafe_unretained NSTextField		*sidebarLabel;	//Owned by the view hierarchy; deliberately NOT the textField outlet
	__unsafe_unretained NSImageView		*sidebarIcon;	//Same
}
@property (assign) BOOL isGroupRow;
/* The built-in textField/imageView outlets stay empty on purpose: they are the handles the
 * source list style re-tints through - the accent colour on an unemphasized selection reaches
 * the label over exactly that connection, after everything here has run. A label AppKit has no
 * outlet to is a label it leaves alone, and these two properties are the only way in. */
@property (assign) NSTextField *sidebarLabel;
@property (assign) NSImageView *sidebarIcon;
- (void)updateTextColors;
@end

@implementation AIPrefsSidebarCellView

@synthesize isGroupRow, sidebarLabel, sidebarIcon;

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

/*!
 * @brief AppKit re-tints the label right before drawing; have the last word.
 *
 * Without this, an unemphasized source list selection keeps the accent color
 * AppKit applies after -setBackgroundStyle: has run.
 */
- (void)viewWillDraw
{
	[self updateTextColors];
	[super viewWillDraw];
}

- (void)updateTextColors
{
	/* Only the focused window keeps full-strength labels: System Settings dims
	 * its sidebar as soon as the window is no longer key — whether the app went
	 * inactive or another window of the same app took focus. */
	BOOL windowActive = [[self window] isKeyWindow];
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

	[sidebarLabel setTextColor:color];
}

@end

/*!
 * @brief Sidebar row drawing its own selection.
 *
 * The unemphasized selection AppKit draws while the window is inactive is
 * paler than the one System Settings shows, so the pill is drawn here.
 */
@interface AIPrefsSidebarRowView : NSTableRowView
@end

@implementation AIPrefsSidebarRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
	if (![self isSelected]) {
		return;
	}

	BOOL windowActive = [[self window] isKeyWindow];
	NSColor *fill;
	if ([self isEmphasized] && windowActive) {
		fill = [NSColor selectedContentBackgroundColor];
	} else {
		//Noticeably deeper than +unemphasizedSelectedContentBackgroundColor
		fill = [[NSColor labelColor] colorWithAlphaComponent:0.14];
	}

	NSRect pill = NSInsetRect([self bounds], 5.0, 1.0);
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:pill xRadius:6.0 yRadius:6.0];
	[fill set];
	[path fill];
}

@end

@interface AIModernPreferencesWindowController ()
- (void)buildSidebarEntries;
- (void)buildWindow;
- (AIPreferencePane *)paneWithIdentifier:(NSString *)identifier;
- (void)selectPane:(AIPreferencePane *)pane;
- (void)layoutCurrentPane;
- (void)updateNavigationControl;
- (void)updatePaneTitle;
- (void)refreshSidebarColors:(NSNotification *)notification;
- (void)paneViewFrameChanged:(NSNotification *)notification;
- (CGFloat)contentTopInset;
- (void)navigate:(id)sender;
- (NSArray *)sidebarGroupDefinitions;
@end

/* What a preference pane may offer beyond its own view, and what the window asks it about before
 * drawing the back button. Written down because it was only ever implied: the calls were made
 * through id with a respondsToSelector: guard in front, which leaves the compiler to guess the
 * return types. It guessed id for a method that answers yes or no, and that happens to work on this
 * architecture and is no way to ask a question.
 */
@protocol AIPreferencePaneNavigation <NSObject>
@optional
- (NSString *)preferencePaneNavigationTitle;
- (BOOL)preferencePaneCanNavigateBack;
- (void)preferencePaneNavigateBack;
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
}

#pragma mark - Data

/*!
 * @brief The sidebar's groups: the arrangement the 1.6 line settled on
 *
 * Four groups instead of one flat list with an Advanced annex - the structure
 * the preferences redesign reached on the Mercurial mainline after our git
 * lineage had already frozen. Personal still leads within its group, the way
 * System Settings opens on the person rather than the machinery. An entry
 * prefixed "adv:" is resolved against the advanced registry; the bare name
 * alone would be ambiguous, since the chats pane and the message display pane
 * both answered to "Messages" before they got told apart.
 */
- (NSArray *)sidebarGroupDefinitions
{
	return [NSArray arrayWithObjects:
			[NSArray arrayWithObjects:AILocalizedString(@"General", nil),
			 @"Personal", @"Accounts", @"General", @"adv:Chats", @"Status", nil],
			[NSArray arrayWithObjects:AILocalizedString(@"Appearance", nil),
			 @"Appearance", @"adv:Contact List", @"Messages", nil],
			[NSArray arrayWithObjects:AILocalizedString(@"Events", nil),
			 @"Events", @"adv:Mention", @"adv:Message Alerts", nil],
			[NSArray arrayWithObjects:AILocalizedString(@"Advanced", nil),
			 @"adv:Address Book", @"adv:Default Client", @"adv:Encryption", @"File Transfer", @"adv:Privacy", @"Xtras", nil],
			nil];
}

- (void)buildSidebarEntries
{
	[sidebarEntries removeAllObjects];

	NSMutableArray *mainPool = [[adium.preferenceController paneArray] mutableCopy];
	NSMutableArray *advancedPool = [[adium.preferenceController advancedPaneArray] mutableCopy];

	//The old Advanced container pane is replaced by the group structure itself
	for (AIPreferencePane *pane in [mainPool copy]) {
		if ([AIPrefPaneIdentifier(pane) isEqualToString:@"Advanced"])
			[mainPool removeObject:pane];
	}

	NSMutableArray *groupTitles = [NSMutableArray array];
	NSMutableArray *resolvedGroups = [NSMutableArray array];

	for (NSArray *definition in [self sidebarGroupDefinitions]) {
		[groupTitles addObject:[definition objectAtIndex:0]];

		NSMutableArray *resolved = [NSMutableArray array];
		for (NSUInteger i = 1; i < definition.count; i++) {
			NSString *wanted = [definition objectAtIndex:i];
			BOOL advanced = [wanted hasPrefix:@"adv:"];
			NSString *name = (advanced ? [wanted substringFromIndex:4] : wanted);
			NSMutableArray *pool = (advanced ? advancedPool : mainPool);

			for (AIPreferencePane *pane in pool) {
				if ([AIPrefPaneIdentifier(pane) isEqualToString:name] || [AIPrefPaneName(pane) isEqualToString:name]) {
					[resolved addObject:pane];
					[pool removeObject:pane];
					break;
				}
			}
		}
		[resolvedGroups addObject:resolved];
	}

	/* Whatever nobody claimed - third party panes above all - joins the advanced
	 * group rather than vanishing. */
	NSMutableArray *leftovers = [NSMutableArray arrayWithArray:mainPool];
	[leftovers addObjectsFromArray:advancedPool];
	[leftovers sortUsingComparator:^NSComparisonResult(id a, id b) {
		return [AIPrefPaneName(a) localizedCaseInsensitiveCompare:AIPrefPaneName(b)];
	}];
	[[resolvedGroups lastObject] addObjectsFromArray:leftovers];

	for (NSUInteger i = 0; i < resolvedGroups.count; i++) {
		NSArray *panes = [resolvedGroups objectAtIndex:i];
		if (![panes count]) continue;
		[sidebarEntries addObject:[groupTitles objectAtIndex:i]];
		[sidebarEntries addObjectsFromArray:panes];
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
	NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
												  styleMask:(NSWindowStyleMaskTitled |
															 NSWindowStyleMaskClosable |
															 NSWindowStyleMaskMiniaturizable |
															 NSWindowStyleMaskResizable |
															 NSWindowStyleMaskFullSizeContentView)
													backing:NSBackingStoreBuffered
													  defer:NO];
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
	NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"AIModernPreferencesToolbar"];
	[toolbar setShowsBaselineSeparator:NO];
	[toolbar setDelegate:self];
	[toolbar setAllowsUserCustomization:NO];
	[window setToolbar:toolbar];
	[window setContentMinSize:NSMakeSize(AIPrefsSidebarMinWidth + AIPrefsContentWidth, AIPrefsContentMinHeight)];
	[window setContentSize:NSMakeSize(AIPrefsSidebarMinWidth + AIPrefsContentWidth, 620)];
	[window setFrameAutosaveName:@"AIModernPreferencesWindow"];
	[window center];

	//Sidebar: source list outline in a scroll view
	outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"pane"];
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

	NSScrollView *sidebarScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	[sidebarScroll setDocumentView:outlineView];
	[sidebarScroll setHasVerticalScroller:YES];
	[sidebarScroll setDrawsBackground:NO];
	[sidebarScroll setBorderType:NSNoBorder];

	NSViewController *sidebarVC = [[NSViewController alloc] init];
	[sidebarVC setView:sidebarScroll];

	//Content: a scrolling column. The pane keeps its natural height; when it
	//does not fit, the column scrolls instead of the window growing.
	contentHost = [[AIPrefsContentContainerView alloc] initWithFrame:NSMakeRect(0, 0, AIPrefsContentWidth, 560)];
	[contentHost setWantsLayer:YES];

	NSScrollView *contentScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, AIPrefsContentWidth, 560)];
	[contentScroll setDocumentView:contentHost];
	[contentScroll setHasVerticalScroller:YES];
	[contentScroll setBorderType:NSNoBorder];
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

	NSViewController *contentVC = [[NSViewController alloc] init];
	[contentVC setView:contentScroll];

	NSSplitViewController *splitVC = [[NSSplitViewController alloc] init];
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
	for (NSString *name in [NSArray arrayWithObjects:NSApplicationDidBecomeActiveNotification,
													 NSApplicationDidResignActiveNotification, nil]) {
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(refreshSidebarColors:)
													 name:name
												   object:NSApp];
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

	for (NSView *subview in [[contentHost subviews] copy]) {
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

	[self updatePaneTitle];

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

	/* Laying out sets frames, and a frame set here comes back as a notification asking for another
	 * layout: the document view resizes the pane with it. As long as both sides want the same height
	 * that settles after one pass, but a page that arrives with a different height has the two of
	 * them alternating, and AppKit gives up after sixty three nested passes.
	 *
	 * Not dropped, deferred: what arrives mid-pass is real, the pane really did end up a different
	 * height. One follow-up once this pass is off the stack reads that height and agrees with it. */
	if (layingOutPane) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(layoutCurrentPane)
												   object:nil];
		[self performSelector:@selector(layoutCurrentPane) withObject:nil afterDelay:0.0];
		return;
	}

	layingOutPane = YES;

	NSScrollView *scrollView = [contentHost enclosingScrollView];
	NSClipView *clipView = [scrollView contentView];

	//Keep the content clear of the titlebar it scrolls underneath
	CGFloat topInset = [self contentTopInset];
	NSEdgeInsets insets = [scrollView contentInsets];
	if (insets.top != topInset) {
		/* Only the content is inset. The scroller keeps the full height and its
		 * top runs underneath the frosted strip, as it does in System Settings;
		 * insetting it too would start it a titlebar's height further down. */
		[scrollView setContentInsets:NSEdgeInsetsMake(topInset, 0, 0, 0)];
	}
	/* The clip view's own bounds, not -contentSize: with autohiding scrollers
	 * -contentSize still reports the width the column had before the vertical
	 * scroller appeared, which would push the card's right edge out of sight.
	 */
	NSSize visibleSize = (clipView ? [clipView bounds].size : [scrollView contentSize]);
	CGFloat paneHeight = NSHeight([paneView frame]);
	/* The top inset is part of the scrollable range: a document as tall as the clip view can
	 * still travel by exactly the inset, which lets a pane that fits be pushed up under the
	 * title bar with blank space following it. A short pane's document therefore stops at the
	 * visible height minus the inset - travel zero - and a tall pane is unaffected. */
	CGFloat documentHeight = MAX(paneHeight + 2 * AIPrefsContentPadding, visibleSize.height - topInset);

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
										 MAX(settledHeight + 2 * AIPrefsContentPadding, visibleSize.height - topInset))];
	}

	layingOutPane = NO;
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
	/* A clip change arriving mid-layout is usually the vertical scroller appearing because of the
	 * very height that pass just set, and swallowing it would leave the column laid out for a width
	 * it no longer has. -layoutCurrentPane defers it rather than dropping it. */
	[self layoutCurrentPane];
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
			[(NSView *)view setNeedsDisplay:YES];
		}
		[[outlineView rowViewAtRow:row makeIfNecessary:NO] setNeedsDisplay:YES];
	}
}

#pragma mark - Back/forward navigation

/*!
 * @brief The pane's name, or the name of whatever it has drilled into
 */
- (void)updatePaneTitle
{
	NSString *paneTitle = (currentPane ? (AIPrefPaneName(currentPane) ?: @"") : @"");

	if (currentPane && [currentPane respondsToSelector:@selector(preferencePaneNavigationTitle)]) {
		NSString *pageTitle = [(id<AIPreferencePaneNavigation>)currentPane preferencePaneNavigationTitle];
		if ([pageTitle length])
			paneTitle = pageTitle;
	}

	[[self window] setTitle:paneTitle];
	[toolbarTitleField setStringValue:paneTitle];
}

/*!
 * @brief Can the pane itself go back, before the window's own history does?
 *
 * A pane which drills into something, an account's own settings for instance, is a step of its own:
 * back leaves that before it leaves the pane, which is what System Settings does.
 */
- (BOOL)currentPaneCanNavigateBack
{
	return (currentPane &&
			[currentPane respondsToSelector:@selector(preferencePaneCanNavigateBack)] &&
			[(id<AIPreferencePaneNavigation>)currentPane preferencePaneCanNavigateBack]);
}

- (void)updateNavigationControl
{
	if (!navigationControl) {
		return;
	}
	[navigationControl setEnabled:(historyIndex > 0 || [self currentPaneCanNavigateBack]) forSegment:0];
	[navigationControl setEnabled:(historyIndex >= 0 && historyIndex + 1 < (NSInteger)[history count]) forSegment:1];
}

/*!
 * @brief A pane pushed or popped a page of its own
 */
- (void)paneNavigationChanged
{
	[self updateNavigationControl];
	[self updatePaneTitle];
}

- (void)navigate:(id)sender
{
	//Out of the pane's own page first, and only then out of the pane
	if ([sender selectedSegment] == 0 && [self currentPaneCanNavigateBack]) {
		[(id<AIPreferencePaneNavigation>)currentPane preferencePaneNavigateBack];
		return;
	}

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
		NSToolbarItem *titleItem = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
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

	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
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
		cell = [[AIPrefsSidebarCellView alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)];
		[cell setIdentifier:reuseIdentifier];

		NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
		[label setBordered:NO];
		[label setEditable:NO];
		[label setDrawsBackground:NO];
		[label setLineBreakMode:NSLineBreakByTruncatingTail];
		[label setTranslatesAutoresizingMaskIntoConstraints:NO];
		[cell addSubview:label];
		[(AIPrefsSidebarCellView *)cell setSidebarLabel:label];

		if (!isGroup) {
			NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
			[icon setTranslatesAutoresizingMaskIntoConstraints:NO];
			[cell addSubview:icon];
			[(AIPrefsSidebarCellView *)cell setSidebarIcon:icon];

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

	NSTextField *cellLabel = [(AIPrefsSidebarCellView *)cell sidebarLabel];

	if (isGroup) {
		[cellLabel setStringValue:(NSString *)item];
		[cellLabel setFont:[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold]];
	} else {
		id pane = item;
		[cellLabel setStringValue:(AIPrefPaneName(pane) ?: @"")];
		[cellLabel setFont:[NSFont systemFontOfSize:13]];
		NSImage *icon = AIPrefPaneIcon(pane);
		[icon setSize:NSMakeSize(18, 18)];
		[[(AIPrefsSidebarCellView *)cell sidebarIcon] setImage:icon];
	}
	[(AIPrefsSidebarCellView *)cell updateTextColors];

	return cell;
}

- (NSTableRowView *)outlineView:(NSOutlineView *)aView rowViewForItem:(id)item
{
	NSString *identifier = @"sidebarRow";
	NSTableRowView *rowView = [aView makeViewWithIdentifier:identifier owner:self];
	if (!rowView) {
		rowView = [[AIPrefsSidebarRowView alloc] initWithFrame:NSZeroRect];
		[rowView setIdentifier:identifier];
	}
	return rowView;
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
	for (NSView *subview in [[contentHost subviews] copy]) {
		[subview removeFromSuperview];
	}

	/* The static holds the only reference, and -[NSWindow close] is still running and still
	 * talking to this controller as its delegate and window controller; the pool keeps it alive
	 * until the end of the run loop turn, which is the timing the autorelease had. */
	CFAutorelease(CFBridgingRetain(sharedModernPrefsController));
	sharedModernPrefsController = nil;
}

@end
