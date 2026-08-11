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

#import <Adium/AIAccountControllerProtocol.h>
#import "AIAccountListPreferences.h"
#import <Adium/AIContactControllerProtocol.h>
#import "AIStatusController.h"
#import "AIEditAccountWindowController.h"
#import <AIUtilities/AIAutoScrollView.h>
#import <AIUtilities/AITableViewAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIImageDrawingAdditions.h>
#import <AIUtilities/AIMutableStringAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <AIUtilities/AIDateFormatterAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <Adium/AIAccount.h>
#import <Adium/AIListObject.h>
#import <Adium/AIService.h>
#import <Adium/AIStatusMenu.h>
#import <Adium/AIStatus.h>
#import <Adium/AIServiceIcons.h>
#import <Adium/AIServiceMenu.h>
#import <Adium/AIStatusIcons.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIAttributedStringAdditions.h>

#define MINIMUM_ROW_HEIGHT				44
#define MINIMUM_CELL_SPACING			 4

#define	ACCOUNT_DRAG_TYPE				@"AIAccount"	    			//ID for an account drag

#define NEW_ACCOUNT_DISPLAY_TEXT		AILocalizedString(@"<New Account>", "Placeholder displayed as the name of a new account")

//Identifier of the single, full width column of the modern account list
#define ACCOUNT_COLUMN_IDENTIFIER		@"account"
#define ACCOUNT_CELL_IDENTIFIER			@"AIAccountListCell"

//Metrics of a single account row, System Settings style
#define ROW_V_PADDING					 6.0f		//Space above the name and below the status line
#define NAME_STATUS_SPACING				 1.0f		//Space between the name and the status line
#define NAME_FONT_SIZE					13.0f
#define STATUS_FONT_SIZE				11.0f
#define CELL_H_PADDING					10.0f		//Leading/trailing padding inside a row
#define SERVICE_ICON_SIZE				32.0f
#define SERVICE_ICON_GAP				10.0f		//Space between the service icon and the text
#define STATUS_DOT_SIZE					 8.0f
#define STATUS_DOT_GAP					 6.0f		//Space between the status dot and the status text
#define STATUS_DOT_TOP_INSET			 4.0f		//Keeps the dot optically centered on the status line
#define INFO_BUTTON_SIZE				22.0f
#define CONTROL_GAP						10.0f		//Space around the switch
#define LOCK_ICON_SIZE					12.0f
#define INSET_STYLE_MARGIN				32.0f		//Horizontal room claimed by NSTableViewStyleInset (16pt per side), fallback only
#define STATUS_WIDTH_SAFETY				 4.0f		//Deliberately underestimate the text width so rows are never too short

/*!
 * @class AIAccountListCellView
 * @brief View based row of the account list
 *
 * Layout: [service icon] [name / status line] [switch] [info button], with a hairline separator
 * along the bottom edge. All subviews are owned by the view hierarchy; the properties below are
 * non-retaining references for convenience (manual retain/release).
 */
@interface AIAccountListCellView : NSTableCellView
@property (nonatomic, assign) NSTextField		*statusField;
@property (nonatomic, assign) NSImageView		*statusDot;
@property (nonatomic, assign) NSImageView		*lockView;
@property (nonatomic, assign) NSSwitch			*enabledSwitch;
@property (nonatomic, assign) NSButton			*infoButton;
@property (nonatomic, assign) NSBox				*separator;
@property (nonatomic, retain) NSLayoutConstraint *lockWidthConstraint;
@property (nonatomic, retain) NSLayoutConstraint *separatorTrailingConstraint;
@property (nonatomic, assign) BOOL				 dimmed;
@end

@interface AIAccountListPreferences ()
{
	CGFloat		cachedLayoutWidth;
}
- (AISettingsFormView *)buildSettingsForm;
- (AISettingsFormView *)settingsForm;
- (void)configureAccountList;
- (void)accountListChanged:(NSNotification *)notification;
- (CGFloat)heightOfAccountList;
- (void)updateAccountListHeight;

- (void)calculateHeightForRow:(NSInteger)row;
- (void)calculateAllHeights;

- (void)updateReconnectTime:(NSTimer *)timer;

- (void)iconPackDidChange:(NSNotification *)notification;
- (void)updateAccountsForStatus:(id)sender;
- (void)toggleOnlineForAccounts:(id)sender;
- (void)toggleEnabledForAccounts:(id)sender;

- (void)configureCellView:(AIAccountListCellView *)cellView forRow:(NSInteger)row;
- (void)refreshRow:(NSInteger)row;
- (void)showAddAccountMenuFromControl:(id)control segment:(NSInteger)segment;
- (CGFloat)statusTextWidth;
- (CGFloat)rowInsetPerSide;
- (NSString *)statusTitleForAccount:(AIAccount *)account;
- (NSString *)statusLineForAccount:(AIAccount *)account;
- (NSColor *)statusColorForAccount:(AIAccount *)account;
- (void)setAccountEnabled:(BOOL)inEnabled atRow:(NSInteger)row;
- (void)accountListFrameChanged:(NSNotification *)notification;
- (void)recalculateRowHeights;
- (BOOL)separatorHiddenForRow:(NSInteger)row;
- (void)updateSeparators;
- (void)tearDown;
@end

/*!
 * @brief Width of an NSSwitch, determined once
 */
static CGFloat AIAccountSwitchWidth(void)
{
	static CGFloat switchWidth = 0.0f;

	if (switchWidth <= 0.0f) {
		NSSwitch *sizingSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
		switchWidth = [sizingSwitch intrinsicContentSize].width;
		[sizingSwitch release];

		if (switchWidth <= 0.0f) switchWidth = 38.0f;
	}

	return switchWidth;
}

/*!
 * @brief A filled circle used as the status indicator of a row
 *
 * This is a template image which is colored by the image view's contentTintColor. Keeping the color
 * out of the image matters: an NSImage caches its rasterization, so a color baked into a drawing
 * handler would keep the appearance it was first drawn in when the user switches between light and
 * dark mode. A tint color is resolved against the view's effective appearance on every draw.
 */
static NSImage *AIStatusDotImage(void)
{
	static NSImage *dotImage = nil;

	if (!dotImage) {
		NSImage *image = [NSImage imageWithSystemSymbolName:@"circle.fill" accessibilityDescription:nil];

		image = [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:STATUS_DOT_SIZE
																									weight:NSFontWeightRegular]];

		if (!image) {
			//Fall back to a plain drawn circle; as a template image it is tinted just the same
			image = [NSImage imageWithSize:NSMakeSize(STATUS_DOT_SIZE, STATUS_DOT_SIZE)
								   flipped:NO
							drawingHandler:^BOOL(NSRect dstRect) {
								[[NSColor blackColor] set];
								[[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dstRect, 0.5f, 0.5f)] fill];
								return YES;
							}];
			[image setTemplate:YES];
		}

		dotImage = [image retain];
	}

	return dotImage;
}

/*!
 * @brief Create a non-editable, non-bordered label
 */
static NSTextField *AIAccountListLabel(CGFloat fontSize, NSColor *textColor)
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
	[label setStringValue:@""];

	return label;
}

@implementation AIAccountListCellView

- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		[self setIdentifier:ACCOUNT_CELL_IDENTIFIER];

		//Service icon
		NSImageView *serviceIcon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
		[serviceIcon setTranslatesAutoresizingMaskIntoConstraints:NO];
		[serviceIcon setImageScaling:NSImageScaleProportionallyUpOrDown];
		[serviceIcon setEditable:NO];
		//The service is named in the accessibility label of the whole row; don't read it twice
		[serviceIcon setAccessibilityElement:NO];
		[self addSubview:serviceIcon];
		[self setImageView:serviceIcon];

		//Container holding the two lines of text, vertically centered as a block
		NSView *textContainer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
		[textContainer setTranslatesAutoresizingMaskIntoConstraints:NO];
		[self addSubview:textContainer];

		//Account name
		NSTextField *nameField = AIAccountListLabel(NAME_FONT_SIZE, [NSColor labelColor]);
		[[nameField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
		[nameField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
											forOrientation:NSLayoutConstraintOrientationHorizontal];
		[textContainer addSubview:nameField];
		[self setTextField:nameField];

		//Encryption indicator, shown right after the name
		NSImageView *lockView = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
		[lockView setTranslatesAutoresizingMaskIntoConstraints:NO];
		[lockView setImageScaling:NSImageScaleProportionallyDown];
		[lockView setEditable:NO];
		[textContainer addSubview:lockView];
		[self setLockView:lockView];

		//Colored status dot; its meaning is spelled out by the status line right next to it
		NSImageView *statusDot = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
		[statusDot setTranslatesAutoresizingMaskIntoConstraints:NO];
		[statusDot setImageScaling:NSImageScaleProportionallyDown];
		[statusDot setEditable:NO];
		[statusDot setImage:AIStatusDotImage()];
		[statusDot setAccessibilityElement:NO];
		[textContainer addSubview:statusDot];
		[self setStatusDot:statusDot];

		//Status line
		NSTextField *statusField = AIAccountListLabel(STATUS_FONT_SIZE, [NSColor secondaryLabelColor]);
		[[statusField cell] setLineBreakMode:NSLineBreakByWordWrapping];
		[[statusField cell] setWraps:YES];
		[statusField setMaximumNumberOfLines:0];
		[statusField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
											  forOrientation:NSLayoutConstraintOrientationHorizontal];
		[textContainer addSubview:statusField];
		[self setStatusField:statusField];

		//Enabled switch
		NSSwitch *enabledSwitch = [[[NSSwitch alloc] initWithFrame:NSZeroRect] autorelease];
		[enabledSwitch setTranslatesAutoresizingMaskIntoConstraints:NO];
		[self addSubview:enabledSwitch];
		[self setEnabledSwitch:enabledSwitch];

		//Info button, opens the account editor
		NSImage *infoImage = [NSImage imageWithSystemSymbolName:@"info.circle"
									   accessibilityDescription:AILocalizedString(@"Account Information", "Accessibility description of the button which opens an account's settings")];
		infoImage = [infoImage imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:16.0f
																										   weight:NSFontWeightRegular]];
		if (!infoImage) infoImage = [NSImage imageNamed:NSImageNameRevealFreestandingTemplate];

		NSButton *infoButton = [NSButton buttonWithImage:infoImage target:nil action:NULL];
		[infoButton setTranslatesAutoresizingMaskIntoConstraints:NO];
		[infoButton setBordered:NO];
		[infoButton setImagePosition:NSImageOnly];
		[infoButton setContentTintColor:[NSColor secondaryLabelColor]];
		[self addSubview:infoButton];
		[self setInfoButton:infoButton];

		//Hairline separating this row from the next one
		NSBox *separator = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
		[separator setTranslatesAutoresizingMaskIntoConstraints:NO];
		[separator setBoxType:NSBoxSeparator];
		[self addSubview:separator];
		[self setSeparator:separator];

		NSLayoutConstraint *lockWidth = [[lockView widthAnchor] constraintEqualToConstant:0.0f];
		[self setLockWidthConstraint:lockWidth];

		/* The hairline runs past the trailing edge of the cell all the way to the card's edge, the
		 * way System Settings draws it. How far that is depends on the table's style, so the pane
		 * sets the constant; see -[AIAccountListPreferences rowInsetPerSide]. */
		NSLayoutConstraint *separatorTrailing = [[separator trailingAnchor] constraintEqualToAnchor:[self trailingAnchor]];
		[self setSeparatorTrailingConstraint:separatorTrailing];

		[NSLayoutConstraint activateConstraints:[NSArray arrayWithObjects:
			//Service icon
			[[serviceIcon leadingAnchor] constraintEqualToAnchor:[self leadingAnchor] constant:CELL_H_PADDING],
			[[serviceIcon centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
			[[serviceIcon widthAnchor] constraintEqualToConstant:SERVICE_ICON_SIZE],
			[[serviceIcon heightAnchor] constraintEqualToConstant:SERVICE_ICON_SIZE],

			//Info button
			[[infoButton trailingAnchor] constraintEqualToAnchor:[self trailingAnchor] constant:-CELL_H_PADDING],
			[[infoButton centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],
			[[infoButton widthAnchor] constraintEqualToConstant:INFO_BUTTON_SIZE],
			[[infoButton heightAnchor] constraintEqualToConstant:INFO_BUTTON_SIZE],

			//Switch
			[[enabledSwitch trailingAnchor] constraintEqualToAnchor:[infoButton leadingAnchor] constant:-CONTROL_GAP],
			[[enabledSwitch centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],

			//Text block
			[[textContainer leadingAnchor] constraintEqualToAnchor:[serviceIcon trailingAnchor] constant:SERVICE_ICON_GAP],
			[[textContainer trailingAnchor] constraintEqualToAnchor:[enabledSwitch leadingAnchor] constant:-CONTROL_GAP],
			[[textContainer centerYAnchor] constraintEqualToAnchor:[self centerYAnchor]],

			//Name and encryption indicator
			[[nameField topAnchor] constraintEqualToAnchor:[textContainer topAnchor]],
			[[nameField leadingAnchor] constraintEqualToAnchor:[textContainer leadingAnchor]],
			[[lockView leadingAnchor] constraintEqualToAnchor:[nameField trailingAnchor] constant:4.0f],
			[[lockView centerYAnchor] constraintEqualToAnchor:[nameField centerYAnchor]],
			[[lockView trailingAnchor] constraintLessThanOrEqualToAnchor:[textContainer trailingAnchor]],
			[[lockView heightAnchor] constraintEqualToConstant:LOCK_ICON_SIZE],
			lockWidth,

			//Status dot and status line
			[[statusDot leadingAnchor] constraintEqualToAnchor:[textContainer leadingAnchor]],
			[[statusDot topAnchor] constraintEqualToAnchor:[nameField bottomAnchor] constant:(NAME_STATUS_SPACING + STATUS_DOT_TOP_INSET)],
			[[statusDot widthAnchor] constraintEqualToConstant:STATUS_DOT_SIZE],
			[[statusDot heightAnchor] constraintEqualToConstant:STATUS_DOT_SIZE],
			[[statusField topAnchor] constraintEqualToAnchor:[nameField bottomAnchor] constant:NAME_STATUS_SPACING],
			[[statusField leadingAnchor] constraintEqualToAnchor:[statusDot trailingAnchor] constant:STATUS_DOT_GAP],
			[[statusField trailingAnchor] constraintEqualToAnchor:[textContainer trailingAnchor]],
			[[statusField bottomAnchor] constraintEqualToAnchor:[textContainer bottomAnchor]],

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
	[_lockWidthConstraint release];
	[_separatorTrailingConstraint release];
	[super dealloc];
}

/*!
 * @brief Only the switch and the info button swallow clicks
 *
 * Everything else is handed to the table view so that row selection, double clicks, drags and
 * context menus keep working exactly as they did with the old cell based list.
 *
 * Right clicks (and control clicks) always go to the row itself: neither NSSwitch nor NSButton
 * supplies a context menu, so a right click landing on one of them would otherwise be swallowed
 * and the account's context menu would be unreachable in that corner of the row.
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
		 hitView == [self infoButton] || [hitView isDescendantOf:[self infoButton]])) {
		return hitView;
	}

	return self;
}

/*!
 * @brief Let the table view (and therefore our delegate) supply the context menu
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
	[[self statusField] setTextColor:(emphasized ?
									  [NSColor alternateSelectedControlTextColor] :
									  [NSColor secondaryLabelColor])];
	[[self infoButton] setContentTintColor:(emphasized ?
											[NSColor alternateSelectedControlTextColor] :
											[NSColor secondaryLabelColor])];
}

@end

/*!
 * @class AIAccountListPreferences
 * @brief Shows a list of accounts and provides for management of them
 */
@implementation AIAccountListPreferences

/*!
 * @brief Preference pane properties
 */
- (NSString *)paneIdentifier
{
	return @"Accounts";
}
- (NSString *)paneName{
    return AILocalizedString(@"Accounts","Accounts preferences label");
}
- (NSString *)nibName{
    return @"AccountListPreferences";
}
- (NSImage *)paneIcon
{
	return [NSImage imageNamed:@"pref-accounts" forClass:[self class]];
}

#pragma mark View

/*!
 * @brief Our view: the nib's controls, arranged by the settings form
 *
 * The nib still supplies the table (with its delegate and data source connections), the +/-
 * control and the Edit button, but no longer their arrangement: the list becomes the single,
 * edge to edge row of a card and the buttons the accessory bar below it, both placed by
 * AISettingsFormView. Mirrors -[AIModularPane view] so the subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		[NSBundle loadNibNamed:[self nibName] owner:self];

		/* The nib set the inherited 'view' outlet to its own top level view, retaining it. We take
		 * that reference over rather than retaining it again; it keeps the nib alive while we use
		 * its controls, and -tearDown releases it. */
		[nibView release];
		nibView = view;
		view = [[self buildSettingsForm] retain];

		[self viewDidLoad];
		[self localizePane];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Stack the account list and its buttons into a settings form
 */
- (AISettingsFormView *)buildSettingsForm
{
	/* No width of our own: the form falls back to a usable one and the preferences window hands it
	 * its column width right afterwards. */
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:0.0f] autorelease];

	/* Row heights are measured against the table's width, so the table has to follow the width the
	 * form gives the scroll view from the very first layout - the nib leaves it non-resizable. */
	[tableView_accountList setAutoresizingMask:NSViewWidthSizable];

	[form addSectionHeader:AILocalizedString(@"My Accounts", "Section title above the list of accounts")];

	/* The list is the card: it fills it edge to edge and its height decides how tall the card is.
	 * Adding a view which still has a superview moves it, so the nib's arrangement comes apart on
	 * its own - no view is ever left without an owner in between. */
	[form addEdgeToEdgeRow:scrollView_accountList];

	//...and the buttons sit right below that card, the way System Settings arranges a list
	[button_editAccount setTitle:AILocalizedStringFromTable(@"Edit", @"Buttons", "Verb 'edit' on a button")];
	//Their natural sizes are what the form arranges them by, with the form's own gap in between
	[button_addOrRemoveAccount sizeToFit];
	[button_editAccount sizeToFit];
	[form addAccessoryView:[AISettingsFormView rowOfViews:[NSArray arrayWithObjects:
														   button_addOrRemoveAccount, button_editAccount, nil]]];

	/* textField_overview stays behind in the nib's view: the pane does not show an overview line
	 * any more, and that view is never installed anywhere. */

	return form;
}

/*!
 * @brief The settings form we live in, or nil before -view built it
 */
- (AISettingsFormView *)settingsForm
{
	return ([view isKindOfClass:[AISettingsFormView class]] ? (AISettingsFormView *)view : nil);
}

/*!
 * @brief Configure the view initially
 */
- (void)viewDidLoad
{
	//Configure the account list
	[self configureAccountList];

	//Build the 'add account' menu of each available service
	NSMenu	*serviceMenu = [AIServiceMenu menuOfServicesWithTarget:self 
												activeServicesOnly:NO
												   longDescription:YES
															format:AILocalizedString(@"%@",nil)];
	[serviceMenu setAutoenablesItems:YES];
	
	//Indent each item in the service menu one level
	for (NSMenuItem *menuItem in [serviceMenu itemArray]) {
		[menuItem setIndentationLevel:[menuItem indentationLevel]+1];
	}

	//Add a label to the top of the menu to clarify why we're showing this list of services
	[serviceMenu insertItemWithTitle:AILocalizedString(@"Add an account for:",nil)
							  action:NULL
					   keyEquivalent:@""
							 atIndex:0];
	
	//Assign the menu
	[button_addOrRemoveAccount setMenu:serviceMenu];
	[button_addOrRemoveAccount setMenuIndicatorShown:YES forSegment:0];
	
	//Set ourselves up for Account Menus
	accountMenu_options = [[AIAccountMenu accountMenuWithDelegate:self
													  submenuType:AIAccountOptionsSubmenu
												   showTitleVerbs:NO] retain];
	
	accountMenu_status = [[AIAccountMenu accountMenuWithDelegate:self
													 submenuType:AIAccountStatusSubmenu
												  showTitleVerbs:NO] retain];

	//Observe status icon pack changes
	[[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(iconPackDidChange:)
									   name:AIStatusIconSetDidChangeNotification
									 object:nil];
	
	//Observe service icon pack changes
	[[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(iconPackDidChange:)
									   name:AIServiceIconSetDidChangeNotification
									 object:nil];
	
	[tableView_accountList setAccessibilityLabel:AILocalizedString(@"Accounts", nil)];

	// Start updating the reconnect time if an account is already reconnecting.	
	[self updateReconnectTime:nil];
}

/*!
 * @brief Perform actions before the view closes
 */
- (void)viewWillClose
{
	[self tearDown];
}

/*!
 * @brief Undo everything -viewDidLoad and -configureAccountList set up
 *
 * Idempotent, so that it is safe to run it from both -viewWillClose and -dealloc. Running it from
 * -dealloc matters: AIContactObserverManager keeps observers in non-retaining, non-zeroing
 * NSValues, so an instance which is released without -viewWillClose ever having run would leave a
 * dangling pointer behind and the next status change of any account would message freed memory.
 */
- (void)tearDown
{
	[[AIContactObserverManager sharedManager] unregisterListObjectObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(recalculateRowHeights) object:nil];

	/* The list no longer lives in the nib's view but in the form's card, and those two are released
	 * on different paths (-tearDown here, -[AIModularPane closeView] there). Cut the table loose
	 * from us here, so a table which outlives us for a moment can never ask a freed pane for its
	 * rows - its delegate, data source and target are all non-retaining references to us. */
	[tableView_accountList setDelegate:nil];
	[tableView_accountList setDataSource:nil];
	[tableView_accountList setTarget:nil];
	[tableView_accountList setDoubleAction:NULL];
	[scrollView_accountList removeFromSuperview];

	/* Both outlets are non-retaining and the views behind them go away with the form, which may be
	 * released after us; forget them so a second -tearDown cannot message freed memory. */
	tableView_accountList = nil;
	scrollView_accountList = nil;

	[nibView release]; nibView = nil;

	[accountArray release]; accountArray = nil;
	[tempDragAccounts release]; tempDragAccounts = nil;
	[requiredHeightDict release]; requiredHeightDict = nil;
	[accountMenu_options release]; accountMenu_options = nil;
	[accountMenu_status release]; accountMenu_status = nil;

	// Cancel our auto-refreshing reconnect countdown.
	[reconnectTimeUpdater invalidate];
	[reconnectTimeUpdater release]; reconnectTimeUpdater = nil;
}

- (void)dealloc
{
	[self tearDown];
	[super dealloc];
}

/*!
 * @brief Account status changed.
 *
 * Disable the service menu and user name field for connected accounts
 */
- (NSSet *)updateListObject:(AIListObject *)inObject keys:(NSSet *)inModifiedKeys silent:(BOOL)silent
{
	if ([inObject isKindOfClass:[AIAccount class]]) {
		if ([inModifiedKeys containsObject:@"isOnline"] ||
			[inModifiedKeys containsObject:@"Enabled"] ||
		   [inModifiedKeys containsObject:@"isConnecting"] ||
		   [inModifiedKeys containsObject:@"waitingToReconnect"] ||
		   [inModifiedKeys containsObject:@"isDisconnecting"] ||
		   [inModifiedKeys containsObject:@"connectionProgressString"] ||
		   [inModifiedKeys containsObject:@"connectionProgressPercent"] ||
		   [inModifiedKeys containsObject:@"isWaitingForNetwork"] ||
		   [inModifiedKeys containsObject:@"idleSince"] ||
		   [inModifiedKeys containsObject:@"accountStatus"]) {

			/* Refresh this account in our list. The table may not know about every account yet:
			 * accountArray is the account controller's own array, so it grows and shrinks the
			 * moment an account is added or removed - before Account_ListChanged reaches us and we
			 * reload. Telling the table about a row it does not have raises an exception. */
			NSUInteger accountRow = [accountArray indexOfObject:inObject];
			if (accountRow != NSNotFound && accountRow < (NSUInteger)[tableView_accountList numberOfRows]) {
				// Update the height of the row.
				[self calculateHeightForRow:accountRow];
				[tableView_accountList noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndex:accountRow]];
				// A row which grew or shrank changes the height of the whole list.
				[self updateAccountListHeight];
				// Reconfigure the row's view with the new status.
				[self refreshRow:accountRow];

				// If necessary, update our reconnection display time.
				if (!reconnectTimeUpdater) {
					[self updateReconnectTime:nil];
				}
			}
		}
	}
    
    return nil;
}

//Actions --------------------------------------------------------------------------------------------------------------
#pragma mark Actions
- (IBAction)addOrRemoveAccount:(id)sender
{
	NSInteger selectedSegment = [sender selectedSegment];

	switch (selectedSegment) {
		case 0:
			[self showAddAccountMenuFromControl:sender segment:selectedSegment];
			break;
		case 1:
			[self deleteAccount];
			break;
	}
}

/*!
 * @brief Drop the list of services out of the "+" segment
 *
 * -[AISegmentedControl showMenuForSegment:] positions the menu at the control's frame origin read
 * in its superview's coordinates but interpreted in the window's content view - a point which has
 * nothing to do with where the control is on screen once the control is nested in a container, as
 * it is in the form's button bar. Anchoring the menu to the control itself is right wherever the
 * form happens to put the bar and however far the preferences column is scrolled.
 */
- (void)showAddAccountMenuFromControl:(id)control segment:(NSInteger)segment
{
	NSMenu	*serviceMenu = ([control respondsToSelector:@selector(menu)] ? [control menu] : nil);

	if (serviceMenu && [control isKindOfClass:[NSView class]]) {
		NSView	*controlView = (NSView *)control;
		NSRect	 bounds = [controlView bounds];
		//The bottom edge of the control, so the menu drops out of it
		NSPoint	 location = NSMakePoint(NSMinX(bounds),
									    ([controlView isFlipped] ? NSMaxY(bounds) : NSMinY(bounds)));

		[serviceMenu popUpMenuPositioningItem:nil atLocation:location inView:controlView];
	} else if ([control respondsToSelector:@selector(showMenuForSegment:)]) {
		[control showMenuForSegment:segment];
	}
}

/*!
 * @brief Create a new account
 *
 * Called when a service type is selected from the Add menu
 */
- (IBAction)selectServiceType:(id)sender
{
	AIService	*service = [sender representedObject];
	AIAccount	*account = [adium.accountController createAccountWithService:service
																		   UID:[service defaultUserName]];

	AIEditAccountWindowController *editAccountWindowController = [[AIEditAccountWindowController alloc] initWithAccount:account
																										notifyingTarget:self];
	[editAccountWindowController showOnWindow:[[self view] window]];
}

- (void)editAccount:(AIAccount *)inAccount
{
	AIEditAccountWindowController *editAccountWindowController = [[AIEditAccountWindowController alloc] initWithAccount:inAccount
																										notifyingTarget:self];
	[editAccountWindowController showOnWindow:[[self view] window]];	
}

/*!
 * @brief Edit the currently selected account using <tt>AIEditAccountWindowController</tt>
 */
- (IBAction)editSelectedAccount:(id)sender
{
    NSInteger	selectedRow = [tableView_accountList selectedRow];
	if ([tableView_accountList numberOfSelectedRows] == 1 && selectedRow >= 0 && selectedRow < [accountArray count]) {
		[self editAccount:[accountArray objectAtIndex:selectedRow]];
    }
}

/*!
 * @brief Handle a double click within our table
 *
 * Clicks on the switch and on the info button never reach the table view, so any double click
 * which arrives here is meant to open the account editor.
 */
- (void)doubleClickInTableView:(id)sender
{
	[self editSelectedAccount:sender];
}

/*!
 * @brief The switch of a row was toggled
 *
 * Takes exactly the same path the "enabled" checkbox column used to take.
 */
- (IBAction)toggleAccountEnabled:(id)sender
{
	NSInteger	row = [tableView_accountList rowForView:(NSView *)sender];

	[self setAccountEnabled:([(NSSwitch *)sender state] == NSControlStateValueOn) atRow:row];
}

/*!
 * @brief Enable or disable the account in a given row
 *
 * This is the code path formerly used by -tableView:setObjectValue:forTableColumn:row: for the
 * "enabled" checkbox column.
 */
- (void)setAccountEnabled:(BOOL)inEnabled atRow:(NSInteger)row
{
	if (row >= 0 && row < (NSInteger)[accountArray count]) {
		[(AIAccount *)[accountArray objectAtIndex:row] setEnabled:inEnabled];
	}
}

/*!
 * @brief The info button of a row was clicked; edit that account
 */
- (IBAction)editAccountFromRowButton:(id)sender
{
	NSInteger	row = [tableView_accountList rowForView:(NSView *)sender];

	if (row >= 0 && row < (NSInteger)[accountArray count]) {
		[tableView_accountList selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
		[self editAccount:[accountArray objectAtIndex:row]];
	}
}

/*!
 * @brief Editing of an account completed
 */
- (void)editAccountSheetDidEndForAccount:(AIAccount *)inAccount withSuccess:(BOOL)successful
{
	BOOL existingAccount = ([adium.accountController.accounts containsObject:inAccount]);
	
	if (!existingAccount && successful) {
		//New accounts need to be added to our account list once they're configured
		[adium.accountController addAccount:inAccount];

		//Scroll the new account visible so that the user can see we added it
		[tableView_accountList scrollRowToVisible:[accountArray indexOfObject:inAccount]];
		
		//Put new accounts online by default
		[inAccount setPreference:[NSNumber numberWithBool:YES] forKey:@"isOnline" group:GROUP_ACCOUNT_STATUS];
	} else if (existingAccount && successful && [inAccount enabled]) {
		//If the user edited an account that is "reconnecting" or "connecting", disconnect it and try to reconnect.
		if ([inAccount boolValueForProperty:@"isConnecting"] ||
			[inAccount valueForProperty:@"waitingToReconnect"] ||
			[inAccount boolValueForProperty:@"Reconnect After Edit"]) {
			// Stop connecting or stop waiting to reconnect.
			[inAccount setShouldBeOnline:NO];
			// Connect it.
			[inAccount setShouldBeOnline:YES];
		}
	}
	
	[inAccount setValue:nil forProperty:@"Reconnect After Edit" notify:NotifyNever];
}

/*!
 * @brief Delete the selected account
 *
 * Prompts for confirmation first
 */
- (void)deleteAccount
{
	NSInteger idx = [tableView_accountList selectedRow];
	
	if ([tableView_accountList numberOfSelectedRows] == 1 && idx >= 0 && idx < [accountArray count]) {
		[[(AIAccount *)[accountArray objectAtIndex:idx] confirmationDialogForAccountDeletion] beginSheetModalForWindow:[[self view] window]];
	}
}

/*!
* @brief Toggles an account online or offline.
 */
- (void)toggleShouldBeOnline:(id)sender
{
	AIAccount		*account = [sender representedObject];
	if (!account.enabled)
		[account setEnabled:YES];
	else
		[account toggleOnline];
}

#pragma mark AIAccountMenu Delegates

/*!
* @brief AIAccountMenu delieate method
 */
- (void)accountMenu:(AIAccountMenu *)inAccountMenu didRebuildMenuItems:(NSArray *)menuItems {
	return;
}

/*!
* @brief AIAccountMenu delegate method -- this allows disabled items to have menus.
 */
- (BOOL)accountMenu:(AIAccountMenu *)inAccountMenu shouldIncludeAccount:(AIAccount *)inAccount
{
	return YES;
}

//Account List ---------------------------------------------------------------------------------------------------------
#pragma mark Account List
/*!
 * @brief Configure the account list table
 */
- (void)configureAccountList
{
	//Configure our table view for a view based, System Settings style list
	[tableView_accountList setTarget:self];
	[tableView_accountList setDoubleAction:@selector(doubleClickInTableView:)];
	[tableView_accountList setIntercellSpacing:NSZeroSize];
	[tableView_accountList setHeaderView:nil];
	[tableView_accountList setCornerView:nil];
	[tableView_accountList setGridStyleMask:NSTableViewGridNone];
	[tableView_accountList setUsesAlternatingRowBackgroundColors:NO];
	[tableView_accountList setBackgroundColor:[NSColor clearColor]];
	[tableView_accountList setRowSizeStyle:NSTableViewRowSizeStyleCustom];
	[tableView_accountList setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
	[tableView_accountList setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[tableView_accountList setAllowsMultipleSelection:YES];
	[tableView_accountList setAllowsColumnReordering:NO];
	//The single column has to follow the width of the table; without a header the user can't drag it anyway
	[tableView_accountList setAllowsColumnResizing:YES];
	[tableView_accountList setFocusRingType:NSFocusRingTypeNone];
	if (@available(macOS 11.0, *)) {
		[tableView_accountList setStyle:NSTableViewStyleInset];
	}

	//Replace the legacy cell based columns with a single, full width column
	for (NSTableColumn *tableColumn in [[[tableView_accountList tableColumns] copy] autorelease]) {
		[tableView_accountList removeTableColumn:tableColumn];
	}

	NSTableColumn *accountColumn = [[[NSTableColumn alloc] initWithIdentifier:ACCOUNT_COLUMN_IDENTIFIER] autorelease];
	[accountColumn setResizingMask:NSTableColumnAutoresizingMask];
	[accountColumn setEditable:NO];
	[accountColumn setMinWidth:80.0f];
	[accountColumn setMaxWidth:10000.0f];
	//The table tiles the column to the width the inset style leaves over; start out with that width
	//so the first row heights are not calculated against a column which is 32pt too wide
	[accountColumn setWidth:(NSWidth([tableView_accountList bounds]) - INSET_STYLE_MARGIN)];
	[tableView_accountList addTableColumn:accountColumn];

	/* The list does not scroll: it is as tall as its rows and the preferences column scrolls
	 * instead. The scroll view stays - a table view outside of one loses its tiling, its drag
	 * autoscrolling and its enclosing clip view - but it never scrolls anything: no scrollers, no
	 * elasticity, which also lets the scroll wheel through to the column behind us.
	 *
	 * The card around the list is drawn by AISettingsFormView, so nothing here draws a background
	 * of its own; the form also rounds our corners to the card's radius. */
	[scrollView_accountList setBorderType:NSNoBorder];
	[scrollView_accountList setDrawsBackground:NO];
	[scrollView_accountList setHasVerticalScroller:NO];
	[scrollView_accountList setHasHorizontalScroller:NO];
	[scrollView_accountList setVerticalScrollElasticity:NSScrollElasticityNone];
	[scrollView_accountList setHorizontalScrollElasticity:NSScrollElasticityNone];
	[scrollView_accountList setAutomaticallyAdjustsContentInsets:NO];
	[scrollView_accountList setContentInsets:NSEdgeInsetsZero];
	[scrollView_accountList setAutoresizingMask:NSViewNotSizable];

	/* Row heights depend on the available width, so recalculate them when it changes. Starting out
	 * at zero rather than at the width we happen to have right now guarantees that the first real
	 * width the form hands us counts as a change, whatever the nib's width was. */
	cachedLayoutWidth = 0.0f;
	[tableView_accountList setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(accountListFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:tableView_accountList];

	//Enable dragging of accounts
	[tableView_accountList registerForDraggedTypes:[NSArray arrayWithObjects:ACCOUNT_DRAG_TYPE,nil]];

	//Observe changes to the account list
    [[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(accountListChanged:) 
									   name:Account_ListChanged 
									 object:nil];
	[self accountListChanged:nil];
	
	//Observe accounts so we can display accurate status
    [[AIContactObserverManager sharedManager] registerListObjectObserver:self];
}

/*!
 * @brief Account list changed, refresh our table
 */
- (void)accountListChanged:(NSNotification *)notification
{
    /* Update our list of accounts. This has to be a snapshot: the account controller hands out its
	 * own mutable array, which would change underneath the table between a change to the account
	 * list and the reload below. */
    [accountArray release];
	accountArray = [adium.accountController.accounts copy];

	//Row heights have to be known before the table asks for them
	[self calculateAllHeights];

	//Refresh the account table
	[tableView_accountList reloadData];
	[self updateControlAvailability];
	[self updateAccountListHeight];
}

/*!
 * @brief The height the list needs to show every row without scrolling
 *
 * A table view lays itself out as the sum of its row heights plus its intercell spacing per row,
 * so that is what we add up here - we do set the spacing to zero in -configureAccountList, but
 * reading it rather than assuming it keeps this in step with the table even if that ever changes.
 * An empty list still gets one row's worth of height so its card does not collapse into a line.
 */
- (CGFloat)heightOfAccountList
{
	CGFloat		height = 0.0f;
	CGFloat		spacing = [tableView_accountList intercellSpacing].height;

	for (NSInteger row = 0; row < (NSInteger)[accountArray count]; row++) {
		height += [self tableView:tableView_accountList heightOfRow:row] + spacing;
	}

	return ceil(height < MINIMUM_ROW_HEIGHT ? MINIMUM_ROW_HEIGHT : height);
}

/*!
 * @brief Grow or shrink the card around the list to fit its rows
 *
 * The list is the edge to edge row of a card, so its height is the card's height. Handing the new
 * height to the form makes the form resize its card and itself, and the preferences window - which
 * watches the pane's frame - resizes its scrolling column in turn. That is the whole chain: the
 * card grows with the number of accounts and the window scrolls, not the list.
 */
- (void)updateAccountListHeight
{
	CGFloat		height = [self heightOfAccountList];

	if (fabs(NSHeight([scrollView_accountList frame]) - height) < 0.5f) return;

	[scrollView_accountList setFrameSize:NSMakeSize(NSWidth([scrollView_accountList frame]), height)];
	[[self settingsForm] noteContentSizeChanged];
}

/*!
 * @brief Returns the status menu associated with several rows
 */
- (NSMenu *)menuForRowIndexes:(NSIndexSet *)indexes
{
	NSMenu			*statusMenu = nil, *optionsMenu = [[[NSMenu alloc] init] autorelease];
	NSMenuItem		*statusMenuItem = nil;
	NSArray			*accounts = [accountArray objectsAtIndexes:indexes];
	AIAccount		*account;
	BOOL			atLeastOneDisabledAccount = NO, atLeastOneOfflineAccount = NO;
	
	// Check the accounts' enabled/disabled and online/offline status.
	for (account in accounts) {
		if (!account.enabled)
			atLeastOneDisabledAccount = YES;
		
		if (!account.online && ![account boolValueForProperty:@"isConnecting"])
			atLeastOneOfflineAccount = YES;
		
		if (atLeastOneOfflineAccount && atLeastOneDisabledAccount)
			break;
	}
	
	statusMenuItem = [optionsMenu addItemWithTitle:AILocalizedString(@"Set Status", "Used in the context menu for the accounts list for the sub menu to set status in.")
											target:nil
											action:nil
									 keyEquivalent:@""];

	statusMenu = [AIStatusMenu staticStatusStatesMenuNotifyingTarget:self
														selector:@selector(updateAccountsForStatus:)];
	[statusMenuItem setSubmenu:statusMenu];
	
	//If any accounts are offline, present the option to connect them all.
	if (atLeastOneOfflineAccount) {
		[optionsMenu addItemWithTitle:AILocalizedString(@"Connect",nil)
							   target:self
							   action:@selector(toggleOnlineForAccounts:)
						keyEquivalent:@""
					representedObject:[NSDictionary dictionaryWithObjectsAndKeys:accounts,@"Accounts",
						[NSNumber numberWithBool:YES],@"Connect",nil]];
	}
	[optionsMenu addItemWithTitle:AILocalizedString(@"Disconnect",nil)
						   target:self
						   action:@selector(toggleOnlineForAccounts:)
					keyEquivalent:@""
				representedObject:[NSDictionary dictionaryWithObjectsAndKeys:accounts,@"Accounts",
					[NSNumber numberWithBool:NO],@"Connect",nil]];
	
	[optionsMenu addItem:[NSMenuItem separatorItem]];
	
	// If any accounts are disable,d show the option to enable them.
	if (atLeastOneDisabledAccount) {
		[optionsMenu addItemWithTitle:AILocalizedString(@"Enable",nil)
							   target:self
							   action:@selector(toggleEnabledForAccounts:)
						keyEquivalent:@""
					representedObject:[NSDictionary dictionaryWithObjectsAndKeys:accounts,@"Accounts",
						[NSNumber numberWithBool:YES],@"Enable",nil]];
		
	}
	[optionsMenu addItemWithTitle:AILocalizedString(@"Disable",nil)
						   target:self
						   action:@selector(toggleEnabledForAccounts:)
					keyEquivalent:@""
				representedObject:[NSDictionary dictionaryWithObjectsAndKeys:accounts,@"Accounts",
					[NSNumber numberWithBool:NO],@"Enable",nil]];
	
	return optionsMenu;
}

/*!
 * @brief Callback for the Connect/Disconnect menu item in a multiple account selection
 */
- (void)toggleOnlineForAccounts:(id)sender
{
	NSDictionary *dict = [sender representedObject];
	BOOL		 connect = [[dict objectForKey:@"Connect"] boolValue];

	for (AIAccount *account in [dict objectForKey:@"Accounts"]) {
		if (!account.enabled && connect)
			[account setEnabled:YES];
		[account setShouldBeOnline:connect];
	}
}

/*!
 * @brief Callback for the Enable/Disable menu item in a multiple account selection
 */
- (void)toggleEnabledForAccounts:(id)sender
{
	NSDictionary *dict = [sender representedObject];
	BOOL		 enable	 = [[dict objectForKey:@"Enable"] boolValue];

	for (AIAccount *account in [dict objectForKey:@"Accounts"]) {
		[account setEnabled:enable];
	}	
}

/*!
 * @brief Callback for the Set Status menu item in a multiple-account selection
 */
- (void)updateAccountsForStatus:(id)sender
{
	AIStatus		*status		= [[sender representedObject] objectForKey:@"AIStatus"];
	
	for (AIAccount *account in [accountArray objectsAtIndexes:[tableView_accountList selectedRowIndexes]]) {
		[account setStatusState:status];
		
		//Enable the account if it isn't currently enabled and this isn't an offline status
		if (!account.enabled && status.statusType != AIOfflineStatusType) {
			[account setEnabled:YES];
		}
	}
}

/*!
* @brief Callback for the Copy Error Message menu item for an account
 */
- (void)copyStatusMessage:(id)sender
{
	NSPasteboard		*generalPasteboard = [NSPasteboard generalPasteboard];
	
	[generalPasteboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString]
							  owner:nil];
	[generalPasteboard setString:[self statusMessageForAccount:[sender representedObject]]
						 forType:NSPasteboardTypeString];
}

/*!
 * @brief Returns the status menu associated with a particular row
 */
- (NSMenu *)menuForRow:(NSInteger)row
{
	if (row >= 0 && row < [accountArray count]) {
		AIAccount		*account = [accountArray objectAtIndex:row];
		NSMenu			*optionsMenu = [[[NSMenu alloc] init] autorelease];
		NSMenu			*accountOptionsMenu = [[accountMenu_options menuItemForAccount:account] submenu];

		NSMenuItem	*statusMenuItem = [optionsMenu addItemWithTitle:AILocalizedString(@"Set Status", "Used in the context menu for the accounts list for the sub menu to set status in.")
															 target:nil
															 action:nil
													  keyEquivalent:@""];

		//We can't put the submenu into our menu directly or otherwise modify the accountMenu_status, as we may want to use it again
		[statusMenuItem setSubmenu:[[[[accountMenu_status menuItemForAccount:account] submenu] copy] autorelease]];
		
		if (!account.online && ![account boolValueForProperty:@"isConnecting"] && [self statusMessageForAccount:account]) {
			[optionsMenu addItemWithTitle:AILocalizedString(@"Copy Error Message","Menu Item for the context menu of an account in the accounts list")
								   target:self
								   action:@selector(copyStatusMessage:)
							keyEquivalent:@""
						representedObject:account];
		}
		
		if ([[statusMenuItem submenu] numberOfItems] >= 2) {
			//Remove the 'Disable' item
			[[statusMenuItem submenu] removeItemAtIndex:([[statusMenuItem submenu] numberOfItems] - 1)];
			
			//And remove the separator above it
			[[statusMenuItem submenu] removeItemAtIndex:([[statusMenuItem submenu] numberOfItems] - 1)];
		}
		
		//Connect or disconnect the account. Enabling a disabled account will connect it, so this is only valid for non-disabled accounts.
		//Only online & connecting can be "Disconnected"; those offline or waiting to reconnect can be "Connected"
		[optionsMenu addItemWithTitle:((account.online || [account boolValueForProperty:@"isConnecting"]) ?
									   AILocalizedString(@"Disconnect",nil) :
									   AILocalizedString(@"Connect",nil))
							   target:self
							   action:@selector(toggleShouldBeOnline:)
						keyEquivalent:@""
					representedObject:account];
				
		//Add a separator if we have any items shown so far
		[optionsMenu addItem:[NSMenuItem separatorItem]];
		
		//Add account options
		for (NSMenuItem *menuItem in [accountOptionsMenu itemArray]) {
			//Use copies of the menu items rather than moving the actual items, as we may want to use them again
			[optionsMenu addItem:[[menuItem copy] autorelease]];
		}

		return optionsMenu;
	}
	
	return nil;
}

/*!
 * @brief Updates reconnecting time where necessary.
 *
 * The countdown is part of the wrapping status line, so a tick can change how many lines that line
 * needs - the row height has to follow it, exactly as it does for any other status change.
 */
- (void)updateReconnectTime:(NSTimer *)timer
{
	NSInteger				accountRow;
	BOOL			moreUpdatesNeeded = NO;
	NSMutableIndexSet		*changedRows = [NSMutableIndexSet indexSet];

	for (accountRow = 0; accountRow < [accountArray count]; accountRow++) {
		if ([[accountArray objectAtIndex:accountRow] valueForProperty:@"waitingToReconnect"] != nil) {
			if (accountRow < [tableView_accountList numberOfRows]) {
				//Only tell the table about rows whose height really moved; this runs once a second
				CGFloat		previousHeight = [self tableView:tableView_accountList heightOfRow:accountRow];

				[self calculateHeightForRow:accountRow];

				if (fabs([self tableView:tableView_accountList heightOfRow:accountRow] - previousHeight) >= 0.5f) {
					[changedRows addIndex:accountRow];
				}
			}
			[self refreshRow:accountRow];
			moreUpdatesNeeded = YES;
		}
	}

	if ([changedRows count]) {
		[tableView_accountList noteHeightOfRowsWithIndexesChanged:changedRows];
		[self updateAccountListHeight];
	}

	if (moreUpdatesNeeded && reconnectTimeUpdater == nil) {
		reconnectTimeUpdater = [[NSTimer scheduledTimerWithTimeInterval:1.0
																 target:self 
															   selector:@selector(updateReconnectTime:) 
															   userInfo:nil
																repeats:YES] retain];
	} else if (!moreUpdatesNeeded && reconnectTimeUpdater != nil) {
		[reconnectTimeUpdater invalidate];
		[reconnectTimeUpdater release]; reconnectTimeUpdater = nil;
	}
}

/*!
 * @brief Status icons changed, refresh our table
 */
- (void)iconPackDidChange:(NSNotification *)notification
{
	//A view based table forgets its selection in -reloadData, and does so silently
	NSIndexSet	*selectedIndexes = [[[tableView_accountList selectedRowIndexes] copy] autorelease];

	[tableView_accountList reloadData];

	if ([selectedIndexes count]) {
		[tableView_accountList selectRowIndexes:selectedIndexes byExtendingSelection:NO];
	}

	[self updateControlAvailability];
}

/*!
 * @brief Update control availability based on list selection
 */
- (void)updateControlAvailability
{
	BOOL	selection = ([tableView_accountList numberOfSelectedRows] == 1 && [tableView_accountList selectedRow] != -1);

	[button_editAccount setEnabled:selection];
	[button_addOrRemoveAccount setEnabled:selection forSegment:1];
}

/*!
* @brief Returns the status string associated with the account
 *
 * Returns a connection status if connecting, or an error if disconnected with an error
 */
- (NSString *)statusMessageForAccount:(AIAccount *)account
{
	NSString *statusMessage = nil;
	
	if ([account valueForProperty:@"connectionProgressString"] && [account boolValueForProperty:@"isConnecting"]) {
		// Connection status if we're currently connecting, with the percent at the end
		statusMessage = [[account valueForProperty:@"connectionProgressString"] stringByAppendingFormat:@" (%2.f%%)", [[account valueForProperty:@"connectionProgressPercent"] doubleValue]];
	} else if ([account lastDisconnectionError] && ![account boolValueForProperty:@"isOnline"] && ![account boolValueForProperty:@"isConnecting"]) {
		// If there's an error and we're not online and not connecting
		NSMutableString *returnedMessage = [[[account lastDisconnectionError] mutableCopy] autorelease];
		
		// Replace the LibPurple error prefixes
		[returnedMessage replaceOccurrencesOfString:@"Could not establish a connection with the server:\n"
										 withString:@""
											options:NSLiteralSearch
											  range:NSMakeRange(0, [returnedMessage length])];
		[returnedMessage replaceOccurrencesOfString:@"Connection error from Notification server:\n"
										 withString:@""
											options:NSLiteralSearch
											  range:NSMakeRange(0, [returnedMessage length])];
		[returnedMessage replaceOccurrencesOfString:@"Could not connect to authentication server:\n"
										 withString:@""
											options:NSLiteralSearch
											  range:NSMakeRange(0, [returnedMessage length])];

		// Remove newlines from the error message, replace them with spaces
		[returnedMessage replaceOccurrencesOfString:@"\n"
										 withString:@" "
											options:NSLiteralSearch
											  range:NSMakeRange(0, [returnedMessage length])];
		
		statusMessage = [NSString stringWithFormat:@"%@: %@", AILocalizedString(@"Error", "Prefix to error messages in the Account List."), returnedMessage];
	}
	
	return statusMessage;
}

/*!
 * @brief The width available to the status line of a row
 *
 * The same value is used to lay out the status label and to calculate the height of a row, so the
 * calculated height and the height the label actually needs always agree.
 *
 * The width of a row is the width of our column, not the width of the table: NSTableViewStyleInset
 * takes 16pt off each side. Rather than assuming that constant we ask the column, which is what the
 * table really lays the cell out with; the constant is only a fallback for the time before the
 * table has tiled. A few points are shaved off on top of that, so the label is laid out slightly
 * narrower than it really is and a row therefore never ends up too short for its text.
 */
/*!
 * @brief How far the inset table style keeps a row away from the edge of the card
 *
 * NSTableViewStyleInset lays its rows out inside a margin whose width AppKit decides; measuring it
 * rather than assuming the usual 16pt keeps us right on whatever macOS we run on. Used to run the
 * hairline between two rows out to the edge of the card, the way System Settings draws it.
 */
- (CGFloat)rowInsetPerSide
{
	NSTableColumn	*accountColumn = [tableView_accountList tableColumnWithIdentifier:ACCOUNT_COLUMN_IDENTIFIER];
	CGFloat			 tableWidth = NSWidth([tableView_accountList bounds]);
	CGFloat			 columnWidth = (accountColumn ? [accountColumn width] : 0.0f);

	if (tableWidth <= 0.0f || columnWidth <= 0.0f) return 0.0f;

	CGFloat			 inset = floor((tableWidth - columnWidth) / 2.0f);

	//A column wider than the table (mid-tiling) must never push the hairline the other way
	return (inset > 0.0f ? inset : 0.0f);
}

- (CGFloat)statusTextWidth
{
	NSTableColumn	*accountColumn = [tableView_accountList tableColumnWithIdentifier:ACCOUNT_COLUMN_IDENTIFIER];
	CGFloat			 cellWidth = (accountColumn ? [accountColumn width] : 0.0f);

	if (cellWidth <= 0.0f) {
		CGFloat		tableWidth = NSWidth([tableView_accountList bounds]);

		if (tableWidth <= 0.0f) tableWidth = NSWidth([scrollView_accountList bounds]);
		if (tableWidth <= 0.0f) tableWidth = 500.0f;

		cellWidth = tableWidth - INSET_STYLE_MARGIN;
	}

	CGFloat		width = (cellWidth
						 - (CELL_H_PADDING + SERVICE_ICON_SIZE + SERVICE_ICON_GAP)
						 - (CONTROL_GAP + AIAccountSwitchWidth() + CONTROL_GAP + INFO_BUTTON_SIZE + CELL_H_PADDING)
						 - (STATUS_DOT_SIZE + STATUS_DOT_GAP)
						 - STATUS_WIDTH_SAFETY);

	return (width < 80.0f ? 80.0f : width);
}

/*!
 * @brief The one-word description of an account's state
 */
- (NSString *)statusTitleForAccount:(AIAccount *)account
{
	if (!account.enabled)
		return AILocalizedString(@"Disabled",nil);

	if ([account boolValueForProperty:@"isConnecting"])
		return AILocalizedString(@"Connecting",nil);

	if ([account boolValueForProperty:@"isDisconnecting"])
		return AILocalizedString(@"Disconnecting",nil);

	if ([account boolValueForProperty:@"isOnline"]) {
		/* Name the status the account is actually in - away, invisible, a custom state - the way the
		 * status icon column of the old list did. Without this every connected account would read
		 * "Online" and away or invisible accounts would be indistinguishable. */
		AIStatus	*statusState = [account statusState];
		NSString	*title = (statusState ? [adium.statusController descriptionForStateOfStatus:statusState] : nil);

		if (![title length]) title = AILocalizedString(@"Online",nil);

		if ([account valueForProperty:@"idleSince"]) {
			title = [NSString stringWithFormat:@"%@ (%@)", title, AILocalizedString(@"Idle", nil)];
		}

		return title;
	}

	if ([account valueForProperty:@"waitingToReconnect"])
		return AILocalizedString(@"Reconnecting", @"Used when the account will perform an automatic reconnection after a certain period of time.");

	if ([account boolValueForProperty:@"isWaitingForNetwork"])
		return AILocalizedString(@"Network Offline", @"Used when the account will connect once the network returns.");

	return [adium.statusController localizedDescriptionForCoreStatusName:STATUS_NAME_OFFLINE];
}

/*!
 * @brief The complete status line of an account
 *
 * Combines the state, the reconnection countdown and the connection progress or error message
 * which the cell based list used to draw as separate sub strings.
 */
- (NSString *)statusLineForAccount:(AIAccount *)account
{
	NSString	*statusLine = [self statusTitleForAccount:account];
	NSString	*statusMessage = [self statusMessageForAccount:account];

	//Countdown until the automatic reconnection happens
	if (account.enabled &&
		![account boolValueForProperty:@"isConnecting"] &&
		[account valueForProperty:@"waitingToReconnect"]) {
		NSString *format = [NSDateFormatter stringForTimeInterval:[[account valueForProperty:@"waitingToReconnect"] timeIntervalSinceNow]
												   showingSeconds:YES
													  abbreviated:YES
													 approximated:NO];

		statusLine = [statusLine stringByAppendingFormat:@" %@",
					  [NSString stringWithFormat:AILocalizedString(@"...in %@", @"The amount of time until a reconnect occurs. %@ is the formatted time remaining."), format]];
	}

	if ([statusMessage length]) {
		if ([account boolValueForProperty:@"isConnecting"]) {
			//The connection progress string already describes what is going on
			statusLine = statusMessage;
		} else {
			statusLine = [NSString stringWithFormat:@"%@ — %@", statusLine, statusMessage];
		}
	}

	return statusLine;
}

/*!
 * @brief The color of the status dot of an account
 */
- (NSColor *)statusColorForAccount:(AIAccount *)account
{
	if (!account.enabled)
		return [NSColor systemGrayColor];

	if ([account boolValueForProperty:@"isOnline"])
		return [NSColor systemGreenColor];

	if ([account boolValueForProperty:@"isConnecting"] ||
		[account boolValueForProperty:@"isDisconnecting"] ||
		[account valueForProperty:@"waitingToReconnect"] ||
		[account boolValueForProperty:@"isWaitingForNetwork"])
		return [NSColor systemOrangeColor];

	if ([account lastDisconnectionError])
		return [NSColor systemRedColor];

	return [NSColor systemGrayColor];
}

/*!
* @brief Calculates the height of a given row and stores it
 */
- (void)calculateHeightForRow:(NSInteger)row
{
	// Make sure this is a valid row.
	if (row < 0 || row >= [accountArray count]) {
		return;
	}

	AIAccount		*account = [accountArray objectAtIndex:row];
	NSString		*statusLine = [self statusLineForAccount:account];

	/* Measure with the very cells which draw the two lines later on. NSTextField lays its text out
	 * differently from a bare NSLayoutManager (14pt versus 13pt per line at this font size), so
	 * measuring any other way makes rows come out too short for multi-line error messages. */
	static NSTextField	*nameSizingField = nil;
	static NSTextField	*statusSizingField = nil;

	if (!nameSizingField) {
		nameSizingField = [AIAccountListLabel(NAME_FONT_SIZE, [NSColor labelColor]) retain];
		[[nameSizingField cell] setLineBreakMode:NSLineBreakByTruncatingTail];

		statusSizingField = [AIAccountListLabel(STATUS_FONT_SIZE, [NSColor secondaryLabelColor]) retain];
		[[statusSizingField cell] setLineBreakMode:NSLineBreakByWordWrapping];
		[[statusSizingField cell] setWraps:YES];
		[statusSizingField setMaximumNumberOfLines:0];
	}

	// The name is always a single line
	[nameSizingField setStringValue:@"Xy"];

	// The status line wraps; it grows for connection errors and reconnection countdowns
	[statusSizingField setStringValue:([statusLine length] ? statusLine : @"Xy")];

	CGFloat			necessaryHeight = ((ROW_V_PADDING * 2.0f) +
									   [[nameSizingField cell] cellSizeForBounds:NSMakeRect(0.0f, 0.0f, 100000.0f, 100000.0f)].height +
									   NAME_STATUS_SPACING +
									   [[statusSizingField cell] cellSizeForBounds:NSMakeRect(0.0f, 0.0f, [self statusTextWidth], 100000.0f)].height);

	// Never go below the minimum row height
	if (necessaryHeight < MINIMUM_ROW_HEIGHT) {
		necessaryHeight = MINIMUM_ROW_HEIGHT;
	}

	// Cache the height value
	[requiredHeightDict setObject:[NSNumber numberWithDouble:necessaryHeight]
						   forKey:[NSNumber numberWithInteger:row]];
}

/*!
 * @brief The available width changed; row heights and text wrapping depend on it
 */
- (void)accountListFrameChanged:(NSNotification *)notification
{
	CGFloat		width = NSWidth([tableView_accountList bounds]);

	if (fabs(width - cachedLayoutWidth) < 1.0f) return;

	cachedLayoutWidth = width;

	//We may be inside the table's own layout pass, so reload once the run loop comes back around
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(recalculateRowHeights) object:nil];
	[self performSelector:@selector(recalculateRowHeights) withObject:nil afterDelay:0.0];
}

/*!
 * @brief Recalculate every row height and rebuild the visible rows for the new width
 *
 * Deliberately without -reloadData: a view based table drops its selection there without posting a
 * selection notification, which would leave "Edit" and "-" enabled with nothing selected.
 * -noteHeightOfRowsWithIndexesChanged: keeps the selection, and the rows on screen are simply
 * reconfigured in place.
 */
- (void)recalculateRowHeights
{
	[self calculateAllHeights];

	NSUInteger	rowCount = MIN((NSUInteger)[tableView_accountList numberOfRows], [accountArray count]);

	[tableView_accountList noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, rowCount)]];

	//Rows which wrap differently at the new width make the whole list taller or shorter
	[self updateAccountListHeight];

	[tableView_accountList enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
		[self refreshRow:row];
	}];
}

/*!
* @brief Calculates the height of all rows
 */
- (void)calculateAllHeights
{
	NSInteger accountNumber;

	[requiredHeightDict release]; requiredHeightDict = [[NSMutableDictionary alloc] init];

	for (accountNumber = 0; accountNumber < [accountArray count]; accountNumber++) {
		[self calculateHeightForRow:accountNumber];
	}
}


//Account List Table Delegate ------------------------------------------------------------------------------------------
#pragma mark Account List (Table Delegate)
/*!
 * @brief Delete the selected row
 */
- (void)tableViewDeleteSelectedRows:(NSTableView *)tableView
{
    [self deleteAccount];
}

/*!
 * @brief Number of rows in the table
 */
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [accountArray count];
}

/*!
 * @brief Table values
 */
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || row >= [accountArray count]) {
		return nil;
	}

	return [accountArray objectAtIndex:row];
}

/*!
 * @brief Supply the view of a row
 */
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || row >= [accountArray count]) {
		return nil;
	}

	AIAccountListCellView	*cellView = (AIAccountListCellView *)[tableView makeViewWithIdentifier:ACCOUNT_CELL_IDENTIFIER
																						    owner:self];

	if (![cellView isKindOfClass:[AIAccountListCellView class]]) {
		cellView = [[[AIAccountListCellView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f,
																			NSWidth([tableView bounds]),
																			MINIMUM_ROW_HEIGHT)] autorelease];
	}

	[self configureCellView:cellView forRow:row];

	return cellView;
}

/*!
 * @brief Fill a row's view with the current state of its account
 */
- (void)configureCellView:(AIAccountListCellView *)cellView forRow:(NSInteger)row
{
	if (row < 0 || row >= [accountArray count]) {
		return;
	}

	AIAccount	*account = [accountArray objectAtIndex:row];
	BOOL		accountEnabled = account.enabled;

	//Service icon; dimmed for disabled accounts
	[[cellView imageView] setImage:[[AIServiceIcons serviceIconForObject:account
																   type:AIServiceIconLarge
															  direction:AIIconNormal] imageByScalingToSize:NSMakeSize(SERVICE_ICON_SIZE, SERVICE_ICON_SIZE)
																								  fraction:(accountEnabled ? 1.0f : 0.5f)]];

	//Account name
	NSString	*accountName = ([[account explicitFormattedUID] length] ?
								[account explicitFormattedUID] :
								NEW_ACCOUNT_DISPLAY_TEXT);
	[[cellView textField] setStringValue:accountName];

	//Encryption indicator
	if ([account encrypted]) {
		[[cellView lockView] setImage:[NSImage imageForSSL]];
		[[cellView lockWidthConstraint] setConstant:LOCK_ICON_SIZE];
	} else {
		[[cellView lockView] setImage:nil];
		[[cellView lockWidthConstraint] setConstant:0.0f];
	}

	//Status line and status dot
	NSString	*statusLine = [self statusLineForAccount:account];

	[[cellView statusField] setPreferredMaxLayoutWidth:[self statusTextWidth]];
	[[cellView statusField] setStringValue:statusLine];
	[[cellView statusDot] setContentTintColor:[self statusColorForAccount:account]];

	/* Enable/disable switch. Setting the state unconditionally would interfere with the switch's own
	 * click handling: -setEnabled: on the account notifies observers synchronously, so this method
	 * runs again while the switch the user just hit is still tracking. */
	NSControlStateValue	switchState = (accountEnabled ? NSControlStateValueOn : NSControlStateValueOff);

	if ([[cellView enabledSwitch] state] != switchState) {
		[[cellView enabledSwitch] setState:switchState];
	}

	[[cellView enabledSwitch] setTarget:self];
	[[cellView enabledSwitch] setAction:@selector(toggleAccountEnabled:)];
	[[cellView enabledSwitch] setAccessibilityLabel:[NSString stringWithFormat:AILocalizedString(@"Enable %@", "Accessibility label of the switch which enables an account. %@ is the account name."), accountName]];

	//Info button
	[[cellView infoButton] setTarget:self];
	[[cellView infoButton] setAction:@selector(editAccountFromRowButton:)];
	[[cellView infoButton] setToolTip:AILocalizedStringFromTable(@"Edit", @"Buttons", "Verb 'edit' on a button")];

	/* The separator sits between two rows, so it goes away below the last row and around the
	 * selection. It runs from the text indent out to the edge of the card - past the trailing edge
	 * of the cell, which the inset table style keeps away from that edge. */
	[[cellView separatorTrailingConstraint] setConstant:[self rowInsetPerSide]];
	[[cellView separator] setHidden:[self separatorHiddenForRow:row]];

	[cellView setDimmed:!accountEnabled];
	[cellView setAccessibilityLabel:[NSString stringWithFormat:@"%@, %@, %@",
									 accountName, [account.service longDescription], statusLine]];
}

/*!
 * @brief Whether the hairline below a row has to be hidden
 *
 * There is no separator below the last row, and - as in System Settings - none directly above or
 * below the selection, where it would be drawn across the selection capsule.
 */
- (BOOL)separatorHiddenForRow:(NSInteger)row
{
	if (row >= ((NSInteger)[accountArray count] - 1)) return YES;

	NSIndexSet	*selectedIndexes = [tableView_accountList selectedRowIndexes];

	return ([selectedIndexes containsIndex:row] || [selectedIndexes containsIndex:(row + 1)]);
}

/*!
 * @brief Update the separators of the rows on screen after a selection change
 */
- (void)updateSeparators
{
	[tableView_accountList enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
		id	cellView = [tableView_accountList viewAtColumn:0 row:row makeIfNecessary:NO];

		if ([cellView isKindOfClass:[AIAccountListCellView class]] && row < (NSInteger)[accountArray count]) {
			[[(AIAccountListCellView *)cellView separator] setHidden:[self separatorHiddenForRow:row]];
		}
	}];
}

/*!
 * @brief Reconfigure a row which is currently on screen
 */
- (void)refreshRow:(NSInteger)row
{
	if (row < 0 || row >= [accountArray count] || row >= [tableView_accountList numberOfRows]) {
		return;
	}

	id	cellView = [tableView_accountList viewAtColumn:0 row:row makeIfNecessary:NO];

	if ([cellView isKindOfClass:[AIAccountListCellView class]]) {
		[self configureCellView:(AIAccountListCellView *)cellView forRow:row];
	}
}
/*!
 * @brief Configure the height of each account for error messages if necessary
 */
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	// We should probably have this value cached.
	CGFloat necessaryHeight = MINIMUM_ROW_HEIGHT;
	
	NSNumber *cachedHeight = [requiredHeightDict objectForKey:[NSNumber numberWithInteger:row]];
	if (cachedHeight) {
		necessaryHeight = (CGFloat)[cachedHeight doubleValue];
	}
	
	return necessaryHeight;
}

/*!
 * @brief Drag start
 */
- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet*)rows toPasteboard:(NSPasteboard*)pboard
{
	[tempDragAccounts release];
    tempDragAccounts = [[accountArray objectsAtIndexes:rows] retain];

    [pboard declareTypes:[NSArray arrayWithObject:ACCOUNT_DRAG_TYPE] owner:self];
    [pboard setString:@"Account" forType:ACCOUNT_DRAG_TYPE];
    
    return YES;
}

/*!
 * @brief Drag validate
 */
- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op
{
    if (op == NSTableViewDropAbove && row != -1) {
        return NSDragOperationPrivate;
    } else {
        return NSDragOperationNone;
    }
}

/*!
 * @brief Drag complete
 */
- (BOOL)tableView:(NSTableView*)tv acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)op
{
    NSString		*avaliableType = [[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:ACCOUNT_DRAG_TYPE]];
	
    if ([avaliableType isEqualToString:@"AIAccount"]) {
		NSEnumerator	*enumerator;

		//Indexes are shifting as we're doing this, so we have to iterate in the right order
		//If we're moving accounts to an earlier point in the list, we've got to insert backwards
		if ([accountArray indexOfObject:[tempDragAccounts objectAtIndex:0]] >= row) 
			enumerator = [tempDragAccounts reverseObjectEnumerator];
		else //If we're inserting into a later part of the list, we've got to insert forwards
			enumerator = [tempDragAccounts objectEnumerator];
		
		[tableView_accountList deselectAll:nil];
		
		for (AIAccount *account in enumerator) {
			[adium.accountController moveAccount:account toIndex:row];
		}
		
		//Re-select our now-moved accounts
		[tableView_accountList selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange([accountArray indexOfObject:[tempDragAccounts objectAtIndex:0]], [tempDragAccounts count])]
						   byExtendingSelection:NO];

        return YES;
    } else {
        return NO;
    }
}

/*!
 * @brief Selection change
 */
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self updateControlAvailability];
	[self updateSeparators];
}

- (NSMenu *)tableView:(NSTableView *)inTableView menuForEvent:(NSEvent *)theEvent
{
	NSIndexSet	*selectedIndexes	= [inTableView selectedRowIndexes];
	NSInteger			mouseRow			= [inTableView rowAtPoint:[inTableView convertPoint:[theEvent locationInWindow] fromView:nil]];

	if (mouseRow < 0 || mouseRow >= (NSInteger)[accountArray count]) {
		return nil;
	}

	//Multiple rows selected where the right-clicked row is in the selection
	if ([selectedIndexes count] > 1 && [selectedIndexes containsIndex:mouseRow]) {
		//Display a multi-selection menu
		return [self menuForRowIndexes:selectedIndexes];
	} else {
		// Otherwise, select our new row and provide a menu for it.
		[inTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:mouseRow] byExtendingSelection:NO];

		// Return our delegate's menu for this row.
		return [self menuForRow:mouseRow];
	}	
}

@end
