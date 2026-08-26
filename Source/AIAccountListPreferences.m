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
#import "AIAccountSettingsPage.h"
#import <Adium/AIContactControllerProtocol.h>
#import "AIStatusController.h"
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
#import <Adium/AIEditStateWindowController.h>
#import <Adium/AIStatusControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <AIUtilities/AIDataAdditions.h>
#import <AIUtilities/AIEventAdditions.h>
#import <Adium/AIServiceIcons.h>
#import <Adium/AIServiceMenu.h>
#import <Adium/AIStatusIcons.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIBundleAdditions.h>

/* Horizontal margin the settings form leaves inside its cards, mirrored here
 * so the account rows line their dividers up with every other pane. */
#define SEPARATOR_CARD_MARGIN		16.0f

/* Extra room around the "+" and its chevron, and the gap between button and menu */
#define ADD_BUTTON_PADDING		22.0f
#define ADD_MENU_GAP			9.0f

#define MINIMUM_ROW_HEIGHT				44
#define MINIMUM_CELL_SPACING			 4


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
#define DISCLOSURE_TRAILING_INSET		4.0f		//The chevron sits nearer the edge than a control does
#define CONTROL_GAP						10.0f		//Space around the switch
#define LOCK_ICON_SIZE					12.0f
#define INSET_STYLE_MARGIN				32.0f		//Horizontal room claimed by NSTableViewStyleInset (16pt per side), fallback only
#define INSET_STYLE_PADDING				10.0f		//Vertical room NSTableViewStyleInset keeps above the first and below the last row, fallback only
#define STATUS_WIDTH_SAFETY				 4.0f		//Deliberately underestimate the text width so rows are never too short

/*!
 * @class AIAccountListCellView
 * @brief View based row of the account list
 *
 * Layout: [service icon] [name / status line] [switch] [info button], with a hairline separator
 * along the bottom edge. All subviews are owned by the view hierarchy; the properties below are
 * non-retaining references for convenience.
 */
@interface AIAccountListCellView : NSTableCellView
@property (nonatomic, unsafe_unretained) NSTextField	*statusField;
@property (nonatomic, unsafe_unretained) NSImageView	*statusDot;
@property (nonatomic, unsafe_unretained) NSImageView	*lockView;
@property (nonatomic, unsafe_unretained) NSSwitch		*enabledSwitch;
@property (nonatomic, unsafe_unretained) NSButton		*infoButton;
@property (nonatomic, unsafe_unretained) NSBox			*separator;
@property (nonatomic, strong) NSLayoutConstraint *lockWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *separatorTrailingConstraint;
@property (nonatomic, assign) BOOL				 dimmed;
/* Drawn behind the row while its context menu is open: with no selection, this is the only thing
 * which says which account "Remove Account..." is about to ask about. */
@property (nonatomic, assign) BOOL				 contextHighlighted;
@end

@interface AIAccountListPreferences () <NSMenuDelegate>
{
	CGFloat		cachedLayoutWidth;
	/* Room the table keeps between its own edge and its column; measured off the table itself,
	 * INSET_STYLE_MARGIN only until it has tiled once. */
	CGFloat		columnMargin;
	/* The row whose context menu is open, or -1. It is the row every context menu action works on,
	 * so it is also the row which is drawn highlighted while the menu is up. */
	NSInteger	contextMenuRow;
	/* Whether a row height recalculation is already on its way; see -accountListFrameChanged: */
	BOOL		heightRecalcScheduled;
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
- (void)setStatusFromMenu:(id)sender;
- (void)setCustomStatusFromMenu:(id)sender;
- (void)removeAccountFromMenu:(id)sender;
- (NSMenu *)statusMenuForAccount:(AIAccount *)account;

- (void)configureCellView:(AIAccountListCellView *)cellView forRow:(NSInteger)row;
- (void)refreshRow:(NSInteger)row;
- (void)configureAddAccountControl;
- (void)showAddAccountMenuFromControl:(id)control segment:(NSInteger)segment;
- (AIAccount *)accountAtRow:(NSInteger)row;
- (CGFloat)statusTextWidth;
- (CGFloat)rowInsetPerSide;
- (NSString *)statusTitleForAccount:(AIAccount *)account;
- (NSString *)nameLineForAccount:(AIAccount *)account;
- (NSString *)statusLineForAccount:(AIAccount *)account;
- (NSColor *)statusColorForAccount:(AIAccount *)account;
- (void)setAccountEnabled:(BOOL)inEnabled atRow:(NSInteger)row;
- (void)accountListFrameChanged:(NSNotification *)notification;
- (void)recalculateRowHeights;
- (void)synchronizeAccountColumnWidth;
- (void)setContextMenuRow:(NSInteger)row;
- (BOOL)separatorHiddenForRow:(NSInteger)row;
- (void)tearDown;
@end

/*!
 * @brief Name @a account as the account a status menu applies to
 *
 * +[AIStatusMenu staticStatusStatesMenuNotifyingTarget:selector:] builds a menu of the status
 * states alone: one flat level, every item carrying an "AIStatus" but no account. Adding the account
 * to each represented object turns that generic menu into one for a single account - the same shape
 * -[AIAccountMenu] hands out, but without depending on the state that menu happens to be in.
 */
static void AIAddAccountToStatusMenu(NSMenu *menu, AIAccount *account)
{
	for (NSMenuItem *menuItem in [menu itemArray]) {
		if ([menuItem isSeparatorItem]) continue;

		NSMutableDictionary	*info = [[menuItem representedObject] mutableCopy];

		if (!info) info = [NSMutableDictionary dictionary];
		[info setObject:account forKey:@"AIAccount"];
		[menuItem setRepresentedObject:info];
	}
}

/*!
 * @brief A "Custom..." item for one status type and one account
 *
 * The same item -[AIStatusMenu customMenuItemForStatusType:] puts into every status menu: no
 * status of its own (which is what marks it as the custom item), the type in its tag and an icon
 * for that type. The account rides along in the represented object, exactly as it does on the
 * items which carry a saved state.
 */
static NSMenuItem *AICustomStatusMenuItem(AIStatusType statusType, AIAccount *account, id target, SEL action)
{
	/* The very string AIStatusMenu titles its custom items with. Spelled out rather than written
	 * as AILocalizedString(), which needs a "self" to take its bundle from. */
	NSString	*customTitle = NSLocalizedStringFromTableInBundle(@"Custom", nil,
																  [NSBundle bundleForClass:[AIAccountListPreferences class]],
																  "Title of the menu item which writes a status message of one's own");

	NSMenuItem	*menuItem = [[NSMenuItem alloc] initWithTitle:[customTitle stringByAppendingEllipsis]
													   target:target
													   action:action
												keyEquivalent:@""];

	[menuItem setImage:[AIStatusIcons statusIconForStatusName:nil
												   statusType:statusType
													 iconType:AIStatusIconMenu
													direction:AIIconNormal]];
	[menuItem setTag:statusType];
	[menuItem setRepresentedObject:[NSDictionary dictionaryWithObject:account forKey:@"AIAccount"]];

	return menuItem;
}

/*!
 * @brief Give a status menu the "Custom..." item of every status group in it
 *
 * +staticStatusStatesMenuNotifyingTarget: builds the saved states and nothing else, while the
 * status menu everywhere else in Adium ends each group of states with a "Custom..." item - the
 * only way to give <em>this one account</em> a status message of its own. -[AIStatusMenu
 * rebuildMenu] puts that item at the end of each group, i.e. right before the separator which
 * starts the next one, and gives the last group (the offline states) none; this does the same to
 * a menu which is already built.
 */
static void AIAddCustomStatusItemsToMenu(NSMenu *menu, AIAccount *account, id target, SEL action)
{
	NSInteger	index = 0;

	while (index < [menu numberOfItems]) {
		NSMenuItem	*menuItem = [menu itemAtIndex:index];

		if ([menuItem isSeparatorItem] && (index > 0)) {
			AIStatusType	statusType = (AIStatusType)[[menu itemAtIndex:(index - 1)] tag];

			//Invisible states are part of the away group, and so is their custom item
			if (statusType == AIInvisibleStatusType) statusType = AIAwayStatusType;

			[menu insertItem:AICustomStatusMenuItem(statusType, account, target, action) atIndex:index];
			index++;		//Step over the separator we just pushed down
		}

		index++;
	}

	/* ...and the group the menu ends with, which no separator follows. The offline group is the
	 * one exception: there is no custom offline state to write a message for. */
	NSMenuItem	*lastItem = ([menu numberOfItems] ? [menu itemAtIndex:([menu numberOfItems] - 1)] : nil);

	if (lastItem && ![lastItem isSeparatorItem]) {
		AIStatusType	statusType = (AIStatusType)[lastItem tag];

		if (statusType == AIInvisibleStatusType) statusType = AIAwayStatusType;

		if (statusType != AIOfflineStatusType) {
			[menu addItem:AICustomStatusMenuItem(statusType, account, target, action)];
		}
	}
}

/*!
 * @brief Check the item of the status @a account is in right now
 *
 * -[AIStatusMenu validateMenuItem:] does this for the menus that class owns; ours are built fresh
 * every time the menu is asked for and are not its, so the state is set here on the spot. The rule
 * is the one that method uses for an account specific menu: if the account is in a saved state,
 * that state's item is on; if it is in a state the user typed, the "Custom..." item of that type is
 * on instead.
 */
static void AISetAccountStatusMenuStates(NSMenu *menu, AIAccount *account)
{
	AIStatus	*activeState = account.statusState;
	BOOL		 isSavedState = (activeState && [adium.statusController.flatStatusSet containsObject:activeState]);

	for (NSMenuItem *menuItem in [menu itemArray]) {
		if ([menuItem isSeparatorItem]) continue;

		AIStatusItem	*itemState = [[menuItem representedObject] objectForKey:@"AIStatus"];
		BOOL			 isActive;

		if (isSavedState) {
			isActive = (itemState == activeState);
		} else {
			//A state the user typed: the custom item of its type is the active one
			isActive = (activeState && !itemState && ([menuItem tag] == (NSInteger)activeState.statusType));
		}

		[menuItem setState:(isActive ? NSControlStateValueOn : NSControlStateValueOff)];
	}
}

/*!
 * @brief Width of an NSSwitch, determined once
 */
static CGFloat AIAccountSwitchWidth(void)
{
	static CGFloat switchWidth = 0.0f;

	if (switchWidth <= 0.0f) {
		NSSwitch *sizingSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
		[sizingSwitch setControlSize:NSControlSizeSmall];
		switchWidth = [sizingSwitch intrinsicContentSize].width;

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

		dotImage = image;
	}

	return dotImage;
}

/*!
 * @brief Create a non-editable, non-bordered label
 */
static NSTextField *AIAccountListLabel(CGFloat fontSize, NSColor *textColor)
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];

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
		NSImageView *serviceIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
		[serviceIcon setTranslatesAutoresizingMaskIntoConstraints:NO];
		[serviceIcon setImageScaling:NSImageScaleProportionallyUpOrDown];
		[serviceIcon setEditable:NO];
		//The service is named in the accessibility label of the whole row; don't read it twice
		[serviceIcon setAccessibilityElement:NO];
		[self addSubview:serviceIcon];
		[self setImageView:serviceIcon];

		//Container holding the two lines of text, vertically centered as a block
		NSView *textContainer = [[NSView alloc] initWithFrame:NSZeroRect];
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
		NSImageView *lockView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		[lockView setTranslatesAutoresizingMaskIntoConstraints:NO];
		[lockView setImageScaling:NSImageScaleProportionallyDown];
		[lockView setEditable:NO];
		[textContainer addSubview:lockView];
		[self setLockView:lockView];

		//Colored status dot; its meaning is spelled out by the status line right next to it
		NSImageView *statusDot = [[NSImageView alloc] initWithFrame:NSZeroRect];
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
		NSSwitch *enabledSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
		//System Settings uses the small switch, not the regular one
		[enabledSwitch setControlSize:NSControlSizeSmall];
		[enabledSwitch setTranslatesAutoresizingMaskIntoConstraints:NO];
		[self addSubview:enabledSwitch];
		[self setEnabledSwitch:enabledSwitch];

		//Info button, opens the account editor
		/* A chevron, not an (i): the row no longer opens a window to one side but leads into the
		 * account's own settings, and that is the mark the rest of the system uses for it. Drawn
		 * from the same place the form's own rows take theirs, so the two never drift apart. */
		NSImage *infoImage = [AISettingsFormView disclosureIndicatorImage];

		NSButton *infoButton = [NSButton buttonWithImage:infoImage target:nil action:NULL];
		[infoButton setTranslatesAutoresizingMaskIntoConstraints:NO];
		[infoButton setBordered:NO];
		[infoButton setImagePosition:NSImageOnly];
		/* Lighter than quaternaryLabelColor, which is the lightest of the named label colours and
		 * still reads heavier here than the system's own chevrons. */
		[infoButton setAccessibilityLabel:AILocalizedString(@"Account Information", "Accessibility description of the button which opens an account's settings")];
		[self addSubview:infoButton];
		[self setInfoButton:infoButton];

		//Hairline separating this row from the next one
		NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
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
			/* Closer to the edge than the rest of the row: a chevron sits at the very end of a
			 * System Settings row, further out than any control would. */
			[[infoButton trailingAnchor] constraintEqualToAnchor:[self trailingAnchor] constant:-DISCLOSURE_TRAILING_INSET],
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

/*!
 * @brief Only the switch and the info button swallow clicks
 *
 * Everything else is handed to the table view so that double clicks, drags and context menus keep
 * working exactly as they did with the old cell based list.
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
	[[self statusField] setTextColor:(emphasized ?
									  [NSColor alternateSelectedControlTextColor] :
									  [NSColor secondaryLabelColor])];
	/* The chevron is a signpost, not a label: tertiaryLabelColor is what the system uses for one,
	 * and measuring System Settings' own chevron against ours put it at #b7b7b7, which is what that
	 * colour comes to on a card. No arithmetic on top of it: alpha applied to a semantic colour does
	 * not compose the way plain arithmetic suggests, which is why three attempts at it moved nothing.
	 * On a selected row it follows the selection colour or it would vanish into it. This is also the
	 * only place the colour may be set, since this runs on every selection change and would put back
	 * whatever the row was built with. */
	[[self infoButton] setContentTintColor:(emphasized ?
											[NSColor alternateSelectedControlTextColor] :
											[NSColor tertiaryLabelColor])];
}

@end

/*!
 * @class AIAccountListPreferences
 * @brief Shows a list of accounts and provides for management of them
 */
/* The window this pane sits in, when it is one that follows navigation. Only ever called behind
 * a respondsToSelector: guard, and written down so the compiler is not left guessing.
 */
@protocol AIPreferencePaneNavigationHost <NSObject>
@optional
- (void)paneNavigationChanged;
@end

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
		[NSBundle ai_loadNibNamed:[self nibName] owner:self];
		/* The loader hands every top level object one reference that belongs to nobody
		 * (see AIBundleAdditions.h); the strong outlet holds its own, so the stray one is
		 * given up here, once. */
		if (view) CFRelease((__bridge CFTypeRef)view);

		/* The nib set the inherited 'view' outlet to its own top level view. We hold on to it here
		 * because the outlet is about to point somewhere else; it keeps the nib alive while we use
		 * its controls, and -tearDown lets it go. */
		nibView = view;

		/* The form is no longer the pane's view but its first page. What the pane hands out is the
		 * navigation controller's container, so that an account's own settings can slide in over the
		 * list without the window having to know that anything moved. */
		listForm = [self buildSettingsForm];

		NSViewController *listPage = [[NSViewController alloc] init];
		[listPage setView:listForm];

		navigationController = [[AISettingsNavigationController alloc] init];
		[navigationController setDelegate:self];
		[navigationController setRootViewController:listPage];

		view = [navigationController view];

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
	AISettingsFormView	*form = [[AISettingsFormView alloc] initWithWidth:0.0f];

	/* Row heights are measured against the table's width, so the table has to follow the width the
	 * form gives the scroll view from the very first layout - the nib leaves it non-resizable. */
	[tableView_accountList setAutoresizingMask:NSViewWidthSizable];

	[form addSectionHeader:AILocalizedString(@"My Accounts", "Section title above the list of accounts")];

	/* The list is the card: it fills it edge to edge and its height decides how tall the card is.
	 * Adding a view which still has a superview moves it, so the nib's arrangement comes apart on
	 * its own - no view is ever left without an owner in between. */
	[form addEdgeToEdgeRow:scrollView_accountList];

	/* ...and the "add" control hangs under the right-hand corner of that card, the way System
	 * Settings puts one under a list. Its natural size is what the form arranges it by; nothing
	 * here positions it. */
	[self configureAddAccountControl];
	[form addTrailingAccessoryView:button_addOrRemoveAccount];

	/* button_editAccount and textField_overview stay behind in the nib's view: a row's (i) button
	 * opens the account editor and the pane shows no overview line, so neither view is ever
	 * installed anywhere. */

	return form;
}

/*!
 * @brief Turn the nib's +/- pair into the "add" control System Settings puts under a list
 *
 * One segment, showing a "+" and the menu chevron next to it inside a single small rounded group.
 * The minus segment is gone: an account is removed through its row's context menu now. Clicking
 * anywhere on the control - the "+" as much as the chevron - drops the list of services out of it,
 * which is the whole of "add an account": an account cannot exist without a service.
 */
- (void)configureAddAccountControl
{
	NSImage		*addImage = [NSImage imageWithSystemSymbolName:@"plus"
										  accessibilityDescription:AILocalizedString(@"Add Account", nil)];

	if (!addImage) addImage = [NSImage imageNamed:NSImageNameAddTemplate];

	[button_addOrRemoveAccount setSegmentCount:1];
	[button_addOrRemoveAccount setSegmentStyle:NSSegmentStyleRounded];
	[button_addOrRemoveAccount setTrackingMode:NSSegmentSwitchTrackingMomentary];
	[button_addOrRemoveAccount setImage:addImage forSegment:0];
	[button_addOrRemoveAccount setImageScaling:NSImageScaleProportionallyDown forSegment:0];
	[button_addOrRemoveAccount setLabel:@"" forSegment:0];

	/* The chevron beside the "+". -setShowsMenuIndicator:forSegment: is the standard way to say
	 * "this button drops a menu" and it needs no menu of its own to do it: measured on macOS 26,
	 * the segment draws the chevron and the fitted width grows from 24pt to 36pt for it whether a
	 * segment menu is attached or not. The menu is deliberately left on the control rather than on
	 * the segment, so that the whole control - "+" and chevron alike - opens the list of services
	 * through -addOrRemoveAccount:; an account cannot exist without a service, so choosing one is
	 * all that "add an account" can mean. */
	[button_addOrRemoveAccount setShowsMenuIndicator:YES forSegment:0];

	/* Zero asks the control for the width its content needs, which packs the "+" and the chevron
	 * tightly together; System Settings gives them noticeably more room, so the fitted width gets
	 * that padding added back. */
	[button_addOrRemoveAccount setWidth:0.0f forSegment:0];
	[button_addOrRemoveAccount sizeToFit];

	NSSize	fittedSize = [button_addOrRemoveAccount frame].size;
	NSSize	fittingSize = [button_addOrRemoveAccount fittingSize];
	CGFloat	contentWidth = MAX(fittedSize.width, fittingSize.width);

	[button_addOrRemoveAccount setWidth:(contentWidth + ADD_BUTTON_PADDING) forSegment:0];
	[button_addOrRemoveAccount sizeToFit];
	[button_addOrRemoveAccount setFrameSize:NSMakeSize(MAX(NSWidth([button_addOrRemoveAccount frame]),
														  contentWidth + ADD_BUTTON_PADDING),
													   MAX(fittedSize.height, fittingSize.height))];

	[button_addOrRemoveAccount setToolTip:AILocalizedString(@"Add Account", nil)];
	[button_addOrRemoveAccount setAccessibilityLabel:AILocalizedString(@"Add Account", nil)];
}

/*!
 * @brief The settings form we live in, or nil before -view built it
 */
- (AISettingsFormView *)settingsForm
{
	/* The pane's view is the navigation container now, so asking it what class it is would answer
	 * "not a form" and quietly stop every height update the list depends on. */
	return listForm;
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
	heightRecalcScheduled = NO;
	contextMenuRow = -1;

	/* The list no longer lives in the nib's view but in the form's card, and those two are released
	 * on different paths (-tearDown here, -[AIModularPane closeView] there). Cut the table loose
	 * from us here, so a table which outlives us for a moment can never ask a freed pane for its
	 * rows - its delegate, data source and target are all non-retaining references to us. */
	[tableView_accountList setDelegate:nil];
	[tableView_accountList setDataSource:nil];
	[tableView_accountList setTarget:nil];
	[tableView_accountList setAction:NULL];
	[scrollView_accountList removeFromSuperview];

	/* The views behind both outlets belong to the form now, which may be released after us; let go
	 * of them here so a second -tearDown has nothing left to touch. */
	tableView_accountList = nil;
	scrollView_accountList = nil;

	nibView = nil;

	[detailPage tearDown];
	detailPage = nil;

	[navigationController setDelegate:nil];
	navigationController = nil;
	listForm = nil;

	accountArray = nil;
	requiredHeightDict = nil;

	// Cancel our auto-refreshing reconnect countdown.
	[reconnectTimeUpdater invalidate];
	reconnectTimeUpdater = nil;
}

- (void)dealloc
{
	[self tearDown];
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
/*!
 * @brief The "add" control was clicked
 *
 * Only one segment is left; removing an account runs through the row's context menu.
 */
- (IBAction)addOrRemoveAccount:(id)sender
{
	[self showAddAccountMenuFromControl:sender segment:0];
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

		/* The menu hangs from its top left corner, so it has to start below the
		 * button's lower edge — which is NSMaxY in a flipped view and NSMinY in
		 * an unflipped one. Anything else drops the menu over the button. */
		CGFloat	 lowerEdge = ([controlView isFlipped] ? NSMaxY(bounds) : NSMinY(bounds));
		CGFloat	 direction = ([controlView isFlipped] ? 1.0f : -1.0f);
		NSPoint	 location = NSMakePoint(NSMinX(bounds), lowerEdge + direction * ADD_MENU_GAP);

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

	if (navigationController) {
		/* Real from the start, and disabled. There is no OK to make it real at, so the alternative
		 * would be an account that exists only inside a page: not in the list behind it, not
		 * anywhere if the page went away. Disabled and offline, the way System Settings adds a new
		 * configuration before it is filled in; the switch is what puts it online.
		 *
		 * Left again without a name, it is taken back out, which is what Cancel used to do. */
		[account setPreference:[NSNumber numberWithBool:NO] forKey:@"Online" group:GROUP_ACCOUNT_STATUS];
		[adium.accountController addAccount:account];

		[self editAccount:account];
		newAccountBeingCreated = account;
	}
}

- (void)editAccount:(AIAccount *)inAccount
{
	//Slid in over the list rather than opened beside it
	if (!navigationController || !inAccount)
		return;

	[detailPage tearDown];

	detailPage = [[AIAccountSettingsPage alloc] initWithAccount:inAccount
													 backTarget:self
														 action:@selector(accountPageWantsBack:)];
	[navigationController pushViewController:detailPage animated:YES];
}

/*!
 * @brief The account in @a row, or nil if there is none
 */
- (AIAccount *)accountAtRow:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[accountArray count]) return nil;

	return [accountArray objectAtIndex:row];
}

/*!
 * @brief Edit the account the user clicked
 *
 * Rows are not selectable any more, so the account is the one under the pointer:
 * -clickedRow is set for the whole time an action sent by the table is running.
 */
/*!
 * @brief The open account page asked to go back to the list
 */
- (void)accountPageWantsBack:(id)sender
{
	[self commitOpenAccountPage];
	[navigationController popViewControllerAnimated:YES];
}

/*!
 * @brief Write what is on the open account page before leaving it
 *
 * Ending editing first, because a field the user is still in writes its value when it is left. This
 * is the last chance to make that happen: taking the page off screen does not end editing by itself.
 */
- (void)commitOpenAccountPage
{
	if (!detailPage)
		return;

	[[[self view] window] makeFirstResponder:nil];
	[detailPage commit];

	/* An account just added and left again without a name never became anything. Taking it back out
	 * is what Cancel did in the window this replaces; there is nothing to ask about, because there
	 * is nothing there. */
	AIAccount *account = [detailPage account];
	if (account && account == newAccountBeingCreated && ![[account UID] length]) {
		[adium.accountController deleteAccount:account];
		newAccountBeingCreated = nil;
	}
}

/*!
 * @brief The stack changed: the list is showing again, so the page can go
 */
- (void)settingsNavigationControllerDidChangeStack:(AISettingsNavigationController *)controller
{
	if (![controller canGoBack] && detailPage) {
		[detailPage commit];
		newAccountBeingCreated = nil;
		[detailPage tearDown];
		detailPage = nil;
	}

	//The window draws the back arrow and the title, so it has to be told
	id windowController = [[[self view] window] windowController];
	if ([windowController respondsToSelector:@selector(paneNavigationChanged)])
		[(id<AIPreferencePaneNavigationHost>)windowController paneNavigationChanged];
}

//What the window asks of a pane which can drill into something -------------------------------------------------------
#pragma mark Navigation

- (BOOL)preferencePaneCanNavigateBack
{
	return [navigationController canGoBack];
}

- (void)preferencePaneNavigateBack
{
	/* Only when the account page itself is being left. A page opened on top of it, the protocol's
	 * remaining options for instance, goes away without any of that: an account being created has no
	 * name yet, and taking it out because a page above it closed would be wrong. */
	if ([navigationController topViewController] == detailPage)
		[self commitOpenAccountPage];

	[navigationController popViewControllerAnimated:YES];
}

/*!
 * @brief What the window should call itself while a page is open
 */
- (NSString *)preferencePaneNavigationTitle
{
	return (detailPage ? [[detailPage account] formattedUID] : nil);
}

- (IBAction)editSelectedAccount:(id)sender
{
	AIAccount	*account = [self accountAtRow:[tableView_accountList clickedRow]];

	if (account) [self editAccount:account];
}

/*!
 * @brief Handle a click within our table
 *
 * Clicks on the switch and on the chevron never reach the table view, so a click which arrives here
 * landed on the row itself, and a row with a chevron opens when it is clicked.
 *
 * A click on empty space below the last row reports -1, which is not an account.
 */
- (void)singleClickInTableView:(id)sender
{
	if ([tableView_accountList clickedRow] < 0)
		return;

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
	AIAccount	*account = [self accountAtRow:[tableView_accountList rowForView:(NSView *)sender]];

	if (account) [self editAccount:account];
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
 * @brief Delete an account
 *
 * Prompts for confirmation first. The dialog releases itself once it is done with.
 */
- (void)deleteAccount:(AIAccount *)inAccount
{
	if (!inAccount) return;

	id<AIAccountControllerRemoveConfirmationDialog> dialog = [inAccount confirmationDialogForAccountDeletion];

	/* The one reference the dialog was handed belongs to nobody here: -alertForAccountDeletion:didReturn:
	 * gives it up when the sheet is answered. Counting references would hand it back at the end of this
	 * method instead, so it is passed out of their reach first. */
	(void)CFBridgingRetain(dialog);

	[dialog beginSheetModalForWindow:[[self view] window]];
}

/*!
 * @brief "Remove" was chosen from a row's context menu
 */
- (void)removeAccountFromMenu:(id)sender
{
	[self deleteAccount:[sender representedObject]];
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

//Account List ---------------------------------------------------------------------------------------------------------
#pragma mark Account List
/*!
 * @brief Configure the account list table
 */
- (void)configureAccountList
{
	//Configure our table view for a view based, System Settings style list
	[tableView_accountList setTarget:self];
	/* A single click opens the account now, the way a row with a chevron behaves everywhere else.
	 * The switch and the chevron have their own targets and never reach the table, so what arrives
	 * here is a click on the row itself. */
	[tableView_accountList setAction:@selector(singleClickInTableView:)];
	[tableView_accountList setIntercellSpacing:NSZeroSize];
	[tableView_accountList setHeaderView:nil];
	[tableView_accountList setCornerView:nil];
	[tableView_accountList setGridStyleMask:NSTableViewGridNone];
	[tableView_accountList setUsesAlternatingRowBackgroundColors:NO];
	[tableView_accountList setBackgroundColor:[NSColor clearColor]];
	[tableView_accountList setRowSizeStyle:NSTableViewRowSizeStyleCustom];
	/* Rows are not selectable: selecting one used to be how an account was picked for "Edit" and
	 * "-", and both of those are gone - the (i) button edits and the context menu removes, each of
	 * them acting on the row the pointer is on. -tableView:shouldSelectRow: is what refuses the
	 * selection, and with no selection there is nothing for the regular highlight style to draw.
	 * Pointing out the row a context menu belongs to is our own job (see -setContextMenuRow:); the
	 * style is left alone all the same, because NSTableViewSelectionHighlightStyleNone also turns
	 * off the feedback a drag draws. */
	[tableView_accountList setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
	[tableView_accountList setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[tableView_accountList setAllowsMultipleSelection:NO];
	[tableView_accountList setAllowsEmptySelection:YES];
	[tableView_accountList setAllowsColumnReordering:NO];
	//The single column has to follow the width of the table; without a header the user can't drag it anyway
	[tableView_accountList setAllowsColumnResizing:YES];
	[tableView_accountList setFocusRingType:NSFocusRingTypeNone];
	if (@available(macOS 11.0, *)) {
		[tableView_accountList setStyle:NSTableViewStyleInset];
	}

	//Replace the legacy cell based columns with a single, full width column
	for (NSTableColumn *tableColumn in [[tableView_accountList tableColumns] copy]) {
		[tableView_accountList removeTableColumn:tableColumn];
	}

	NSTableColumn *accountColumn = [[NSTableColumn alloc] initWithIdentifier:ACCOUNT_COLUMN_IDENTIFIER];
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
	columnMargin = INSET_STYLE_MARGIN;
	contextMenuRow = -1;
	[tableView_accountList setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(accountListFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:tableView_accountList];

	//Enable dragging of accounts

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
	accountArray = [adium.accountController.accounts copy];

	//Row heights have to be known before the table asks for them
	[self calculateAllHeights];

	//Refresh the account table
	[tableView_accountList reloadData];
	[self updateAccountListHeight];
}

/*!
 * @brief The height the list needs to show every row without scrolling
 *
 * A table view lays itself out as the sum of its row heights plus its intercell spacing per row,
 * so that is what we add up here - we do set the spacing to zero in -configureAccountList, but
 * reading it rather than assuming it keeps this in step with the table even if that ever changes.
 * Every single row height is a whole number of points (see -calculateHeightForRow:), so the sum
 * cannot drift away from what the table lays out by a fraction per row.
 *
 * On top of the rows themselves a table style keeps room above the first row and below the last -
 * NSTableViewStyleInset keeps 10pt at each end. That padding is measured off the table (the top of
 * its first row is exactly it) rather than assumed, and it is added to the sum unconditionally:
 * leaving it out is precisely what makes a card 20pt too short for its list, which is what the
 * user sees as "the list scrolls inside its card".
 *
 * The table then gets the last word through its row rects, so that a layout we did not predict
 * still cannot end up with less room than the table laid itself out in.
 *
 * An empty list still gets one row's worth of height so its card does not collapse into a line.
 */
- (CGFloat)heightOfAccountList
{
	CGFloat		height = 0.0f;
	CGFloat		spacing = [tableView_accountList intercellSpacing].height;
	NSInteger	tableRows = [tableView_accountList numberOfRows];

	/* The room the style keeps at each end of the list. Only the table can say what it is, and only
	 * once it has rows; until then the value the inset style uses is the best guess we have. */
	CGFloat		endPadding = INSET_STYLE_PADDING;

	if (tableRows > 0) {
		CGFloat		topInset = NSMinY([tableView_accountList rectOfRow:0]);

		if (topInset >= 0.0f) endPadding = topInset;
	}

	for (NSInteger row = 0; row < (NSInteger)[accountArray count]; row++) {
		height += [self tableView:tableView_accountList heightOfRow:row] + spacing;
	}

	height += 2.0f * endPadding;

	/* ...and then let the table have the last word. -rectOfRow: is where the table says how it
	 * really laid its rows out - it follows -noteHeightOfRowsWithIndexesChanged: immediately, so
	 * this never reads a layout which is a run loop turn behind. The table's own frame is no use
	 * for this, because a table never shrinks below its clip view; its row rects do not stretch. */
	if (tableRows > 0 && tableRows == (NSInteger)[accountArray count]) {
		CGFloat		contentHeight = NSMaxY([tableView_accountList rectOfRow:(tableRows - 1)]) + endPadding;

		if (contentHeight > height) height = contentHeight;
	}

	CGFloat		minimumHeight = MINIMUM_ROW_HEIGHT + (2.0f * endPadding);

	return ceil(height < minimumHeight ? minimumHeight : height);
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
 * @brief Set the status of a single account from a row's "Set Status" submenu
 *
 * The represented object carries both the status and the account, see AIAddAccountToStatusMenu().
 *
 * This is -[AIStatusMenu selectState:] for one account, and it has to be: a status the user typed
 * lives in the status controller's array of temporary states, which is kept alive by the accounts
 * using it. Leaving a temporary state without telling the status controller leaves that state in
 * every status menu in Adium for good. The option click shortcut is handled here for the same
 * reason - a menu which behaves differently from the same menu elsewhere is a bug of its own.
 */
- (void)setStatusFromMenu:(id)sender
{
	NSDictionary	*info = [sender representedObject];
	AIStatusItem	*statusItem = [info objectForKey:@"AIStatus"];
	AIAccount		*account = [info objectForKey:@"AIAccount"];

	if (!account || !statusItem) return;

	/* Holding option - or picking the status the account is already in - opens the custom status
	 * window on that status instead of just setting it, as everywhere else in Adium. */
	NSEventType		 eventType = [[NSApp currentEvent] type];
	BOOL			 keyEvent = ((eventType == NSEventTypeKeyDown) || (eventType == NSEventTypeKeyUp));
	BOOL			 isOptionClick = ([NSEvent optionKey] && !keyEvent);

	if (isOptionClick ||
		(([sender state] == NSControlStateValueOn) && (statusItem.statusType != AIOfflineStatusType))) {
		[AIEditStateWindowController editCustomState:(AIStatus *)statusItem
											 forType:statusItem.statusType
										  andAccount:account
									  withSaveOption:YES
											onWindow:nil
									 notifyingTarget:adium.statusController];
		return;
	}

	//Hand the status the account is leaving back, in case it was a temporary one nobody else uses
	BOOL			 shouldRebuild = [adium.statusController removeIfNecessaryTemporaryStatusState:account.statusState];

	[account setStatusState:(AIStatus *)statusItem];

	//Enable the account if it isn't currently enabled and this isn't an offline status
	if (!account.enabled && statusItem.statusType != AIOfflineStatusType) {
		[account setEnabled:YES];
	}

	if (shouldRebuild) {
		//A temporary state went away; every status menu in Adium has to be rebuilt without it
		[[NSNotificationCenter defaultCenter] postNotificationName:AIStatusStateArrayChangedNotification object:nil];
	}
}

/*!
 * @brief Write a status message for a single account, from a row's "Custom..." item
 *
 * -[AIStatusMenu selectCustomState:] for one account, prefill and all: switching to a custom state
 * of another type starts from the last status of that type rather than from the state the account
 * is in right now.
 */
- (void)setCustomStatusFromMenu:(id)sender
{
	NSDictionary	*info = [sender representedObject];
	AIAccount		*account = [info objectForKey:@"AIAccount"];
	AIStatusType	 statusType = (AIStatusType)[sender tag];
	AIStatus		*baseStatusState;

	if (!account) return;

	baseStatusState = account.statusState;

	if (baseStatusState.statusType != statusType) {
		NSDictionary	*lastStatusStates = [adium.preferenceController preferenceForKey:@"LastStatusStates"
																				   group:PREF_GROUP_STATUS_PREFERENCES];
		NSData			*lastStatusStateData = [lastStatusStates objectForKey:[[NSNumber numberWithInt:statusType] stringValue]];
		AIStatus		*lastStatusStateOfThisType = (lastStatusStateData ?
													  [NSKeyedUnarchiver objectWithArchivedData:lastStatusStateData] :
													  nil);

		if (lastStatusStateOfThisType) {
			/* Keep the message the account is showing right now: users tend to want to carry it
			 * over rather than to get the one they last saved. */
			if (baseStatusState.statusMessage.length) {
				lastStatusStateOfThisType.statusMessage = baseStatusState.statusMessage;
			}

			baseStatusState = lastStatusStateOfThisType;
		}
	}

	[AIEditStateWindowController editCustomState:baseStatusState
										 forType:statusType
									  andAccount:account
								  withSaveOption:YES
										onWindow:nil
								 notifyingTarget:adium.statusController];
}

/*!
 * @brief The "Set Status" submenu of one account
 *
 * The same menu the rest of Adium offers for a single account: every saved state, the "Custom..."
 * item of each group of states, and a checkmark on the state the account is in.
 */
- (NSMenu *)statusMenuForAccount:(AIAccount *)account
{
	NSMenu	*statusMenu = [AIStatusMenu staticStatusStatesMenuNotifyingTarget:self
																	 selector:@selector(setStatusFromMenu:)];

	AIAddAccountToStatusMenu(statusMenu, account);
	AIAddCustomStatusItemsToMenu(statusMenu, account, self, @selector(setCustomStatusFromMenu:));
	AISetAccountStatusMenuStates(statusMenu, account);

	return statusMenu;
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
 * @brief The context menu of the account in @a row
 *
 * Everything in here acts on that one account - the row the pointer is on - since rows are not
 * selectable any more.
 *
 * The menu is built from scratch rather than assembled out of an AIAccountMenu's submenus, which
 * is where the duplicates used to come from: an AIAccountMenu created with a submenu type fills
 * its items with the account's <em>actions</em> and then, as soon as there is more than one
 * account, AIStatusMenu overwrites those very submenus with the <em>status</em> menu. Copying that
 * submenu to the top level therefore produced either "Edit Account" plus "Disable" (one account)
 * or the whole list of statuses a second time (several accounts). The two sources are used
 * directly instead:
 *
 * <ul>
 * <li>the states, as the one "Set Status" submenu (see -statusMenuForAccount:);</li>
 * <li>the protocol's own actions from -[AIAccount accountActionMenuItems].</li>
 * </ul>
 *
 * Editing is the (i) button's job and enabling is the switch's, so neither appears here; removing
 * an account has nowhere else to live and does.
 */
- (NSMenu *)menuForRow:(NSInteger)row
{
	AIAccount	*account = [self accountAtRow:row];

	if (!account) return nil;

	NSMenu		*optionsMenu = [[NSMenu alloc] init];

	//Set Status: the states and their "Custom..." items, and nothing else
	NSMenuItem	*statusMenuItem = [optionsMenu addItemWithTitle:AILocalizedString(@"Set Status", "Used in the context menu for the accounts list for the sub menu to set status in.")
														 target:nil
														 action:nil
												  keyEquivalent:@""];
	[statusMenuItem setSubmenu:[self statusMenuForAccount:account]];

	if (!account.online && ![account boolValueForProperty:@"isConnecting"] && [self statusMessageForAccount:account]) {
		[optionsMenu addItemWithTitle:AILocalizedString(@"Copy Error Message","Menu Item for the context menu of an account in the accounts list")
							   target:self
							   action:@selector(copyStatusMessage:)
						keyEquivalent:@""
					representedObject:account];
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

	/* The actions the protocol itself offers - "Set Vanity Name", "Join Chat"... An offline
	 * account has none. */
	NSArray		*accountActions = (account.online ? [account accountActionMenuItems] : nil);

	if ([accountActions count]) {
		[optionsMenu addItem:[NSMenuItem separatorItem]];

		for (NSMenuItem *menuItem in accountActions) {
			//Use copies of the menu items rather than moving the actual items, as we may want to use them again
			[optionsMenu addItem:[menuItem copy]];
		}
	}

	/* Removing the account, with the usual confirmation - hence the ellipsis. A key of its own,
	 * not the "Remove" every other pane shares: this one is a whole account, and the contact list
	 * is not to be renamed along with it. */
	[optionsMenu addItem:[NSMenuItem separatorItem]];
	[optionsMenu addItemWithTitle:[AILocalizedString(@"Remove Account", "Menu item in the context menu of the accounts list which deletes the account") stringByAppendingEllipsis]
						   target:self
						   action:@selector(removeAccountFromMenu:)
					keyEquivalent:@""
				representedObject:account];

	return optionsMenu;
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
		reconnectTimeUpdater = [NSTimer scheduledTimerWithTimeInterval:1.0
																target:self
															  selector:@selector(updateReconnectTime:)
															  userInfo:nil
															   repeats:YES];
	} else if (!moreUpdatesNeeded && reconnectTimeUpdater != nil) {
		[reconnectTimeUpdater invalidate];
		reconnectTimeUpdater = nil;
	}
}

/*!
 * @brief Status icons changed, refresh our table
 */
- (void)iconPackDidChange:(NSNotification *)notification
{
	[tableView_accountList reloadData];
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
		NSMutableString *returnedMessage = [[account lastDisconnectionError] mutableCopy];
		
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
/*!
 * @brief Keep the single column as wide as the room the list has
 *
 * A table does not reliably re-tile its columns when it is widened - measured on macOS 26: a table
 * grown from 505pt to 640pt left its only column at the 473pt it had before, while narrowing it
 * and widening it again did re-tile. A column left behind like that lays every row out over 100pt
 * narrower than the card, which puts the switch and the (i) button in the middle of the row and
 * stops the hairline short of the card's edge; a column left <em>wider</em> than the clip view is
 * worse still, because the list has no scrollers and the right hand end of every row is then
 * simply unreachable.
 *
 * So the column is set from the width of the clip view rather than left to the table. The margin
 * the table style wants around its column is measured off the table itself whenever the table is
 * tiled to its clip view, and only guessed at (INSET_STYLE_MARGIN) before that ever happened.
 */
- (void)synchronizeAccountColumnWidth
{
	NSTableColumn	*accountColumn = [tableView_accountList tableColumnWithIdentifier:ACCOUNT_COLUMN_IDENTIFIER];
	CGFloat			 clipWidth = NSWidth([[scrollView_accountList contentView] bounds]);

	if (!accountColumn || clipWidth <= 0.0f) return;

	CGFloat			 tableWidth = NSWidth([tableView_accountList bounds]);
	CGFloat			 observedMargin = tableWidth - [accountColumn width];

	/* While the table is tiled to its clip view, whatever it keeps beside its column is the truth
	 * about this table style on this system; remember it instead of assuming 16pt per side. A
	 * margin far too large for that is the very case this method exists for: a column which was
	 * left behind by a table that grew. */
	if ((fabs(tableWidth - clipWidth) < 0.5f) &&
		(observedMargin >= 0.0f) && (observedMargin <= (INSET_STYLE_MARGIN * 2.0f))) {
		columnMargin = observedMargin;
	}

	CGFloat			 targetWidth = clipWidth - columnMargin;

	if (targetWidth < [accountColumn minWidth]) targetWidth = [accountColumn minWidth];

	if (fabs([accountColumn width] - targetWidth) > 0.5f) [accountColumn setWidth:targetWidth];
}

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
 * @brief The line naming an account in the list
 *
 * Says which of the two things it is showing rather than leaving the reader to work it out. The
 * account name alone is unambiguous only as long as every service has one that looks like an
 * address, and they do not: a phone number, a UUID, a nickname and a bare word are all account names
 * here, and an IRC account is identified as much by its server as by its nickname.
 *
 * The name comes first because that is what the user is looking for. The server follows where there
 * is one, and stands alone where there is no name, which IRC permits.
 */
- (NSString *)nameLineForAccount:(AIAccount *)account
{
	NSMutableArray	*parts = [NSMutableArray array];
	/* formattedUID, not explicitFormattedUID. The two are the same everywhere but IRC, which
	 * overrides the explicit one to read "server (nickname)" precisely because this list had no other
	 * way to tell two accounts on different servers apart. It has one now, and taking the composed
	 * string here would print the server twice and call the whole of it the account name. */
	NSString		*uid = [account formattedUID];
	NSString		*host = [account host];

	if ([uid length]) {
		[parts addObject:[NSString stringWithFormat:
						  AILocalizedString(@"Account Name: %@", "Account list entry; %@ is the name of the account"), uid]];
	}

	if ([host length]) {
		[parts addObject:[NSString stringWithFormat:
						  AILocalizedString(@"Server: %@", "Account list entry; %@ is the server the account connects to"), host]];
	}

	if (![parts count])
		return NEW_ACCOUNT_DISPLAY_TEXT;

	return [parts componentsJoinedByString:@", "];
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
		nameSizingField = AIAccountListLabel(NAME_FONT_SIZE, [NSColor labelColor]);
		[[nameSizingField cell] setLineBreakMode:NSLineBreakByTruncatingTail];

		statusSizingField = AIAccountListLabel(STATUS_FONT_SIZE, [NSColor secondaryLabelColor]);
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

	/* Whole points only. Text measures out fractional, and a table lays a row out at whatever
	 * height it is told - but the sum of a dozen fractions is where a card ends up a few points
	 * short of its list and the list starts scrolling inside it. Rounding here, not in the sum,
	 * means the sum and the table agree row by row. */
	necessaryHeight = ceil(necessaryHeight);

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

	/* We may be inside the table's own layout pass, so reload once the run loop comes back around.
	 * In the common modes rather than the default one: a width handed to us while the window is
	 * being resized, a menu is up or a sheet is tracking would otherwise not be acted upon until
	 * that ends, and until then the rows are laid out for a width they no longer have - which is
	 * what leaves a row too short for its text and the list scrolling inside its card.
	 *
	 * A recalculation which is already scheduled is left alone rather than cancelled and queued
	 * again: it reads the width when it runs, so it is up to date whatever happened in between,
	 * and rescheduling it on every single width of a window being dragged is what could push it
	 * back for the whole length of the drag. */
	if (heightRecalcScheduled) return;

	heightRecalcScheduled = YES;
	[self performSelector:@selector(recalculateRowHeights)
			   withObject:nil
			   afterDelay:0.0
				  inModes:[NSArray arrayWithObject:(NSString *)NSRunLoopCommonModes]];
}

/*!
 * @brief Recalculate every row height and rebuild the visible rows for the new width
 *
 * Deliberately without -reloadData: -noteHeightOfRowsWithIndexesChanged: gives the table the new
 * heights without throwing its row views away, and the rows on screen are simply reconfigured in
 * place afterwards.
 */
- (void)recalculateRowHeights
{
	heightRecalcScheduled = NO;

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

	/* Row heights are measured against the column, so the column has to be the width it will be
	 * laid out at before anything is measured against it */
	[self synchronizeAccountColumnWidth];

	requiredHeightDict = [[NSMutableDictionary alloc] init];

	for (accountNumber = 0; accountNumber < [accountArray count]; accountNumber++) {
		[self calculateHeightForRow:accountNumber];
	}
}


//Account List Table Delegate ------------------------------------------------------------------------------------------
#pragma mark Account List (Table Delegate)
/*!
 * @brief Rows cannot be selected
 *
 * Selection only ever served to point the "Edit" and "-" buttons at an account, and both of those
 * are gone. Everything else a row does - its switch, its (i) button, a double click, a right click,
 * dragging it to another position - works on the row itself and needs no selection.
 */
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	return NO;
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
		cellView = [[AIAccountListCellView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f,
																		   NSWidth([tableView bounds]),
																		   MINIMUM_ROW_HEIGHT)];
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

	NSString	*nameLine = [self nameLineForAccount:account];
	[[cellView textField] setStringValue:nameLine];

	/* The bare name for the switch, which reads better spoken as "Enable Christian" than as "Enable
	 * Account Name: Christian". */
	NSString	*accountName = ([[account explicitFormattedUID] length] ?
								[account explicitFormattedUID] :
								NEW_ACCOUNT_DISPLAY_TEXT);

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
	/* rowInsetPerSide alone would end the hairline flush with the card edge;
	 * keep the same margin the settings form leaves inside its own cards. */
	[[cellView separatorTrailingConstraint] setConstant:([self rowInsetPerSide] - SEPARATOR_CARD_MARGIN)];
	[[cellView separator] setHidden:[self separatorHiddenForRow:row]];

	[cellView setDimmed:!accountEnabled];
	[cellView setContextHighlighted:(row == contextMenuRow)];
	[cellView setAccessibilityLabel:[NSString stringWithFormat:@"%@, %@, %@",
									 nameLine, [account.service longDescription], statusLine]];
}

/*!
 * @brief Whether the hairline below a row has to be hidden
 *
 * A separator sits between two rows, so there is none below the last one. Nothing else hides it:
 * with no selection there is no capsule for it to be drawn across.
 */
- (BOOL)separatorHiddenForRow:(NSInteger)row
{
	return (row >= ((NSInteger)[accountArray count] - 1));
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
 * @brief The context menu of the row under the pointer
 *
 * There is no selection to consult and none is made: the row the user right clicked is the row the
 * menu acts on.
 */
- (NSMenu *)tableView:(NSTableView *)inTableView menuForEvent:(NSEvent *)theEvent
{
	NSInteger	mouseRow = [inTableView rowAtPoint:[inTableView convertPoint:[theEvent locationInWindow] fromView:nil]];
	NSMenu		*menu = [self menuForRow:mouseRow];

	/* Mark the row while its menu is up: with no selection there would otherwise be nothing at all
	 * to say which account the menu - "Remove Account..." above all - is about to act on, and the
	 * menu itself usually covers the row. */
	[self setContextMenuRow:(menu ? mouseRow : -1)];
	[menu setDelegate:self];

	return menu;
}

/*!
 * @brief The context menu closed; the row it belonged to is nothing special again
 *
 * Every item of that menu carries its account in its represented object, so the action which is
 * about to run does not need the row we are forgetting here.
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
