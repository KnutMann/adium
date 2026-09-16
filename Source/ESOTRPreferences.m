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

#import "ESOTRPreferences.h"
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <Adium/AIAccount.h>
#import <Adium/AIService.h>

#import "OTRCommon.h"

#import "AdiumOTREncryption.h"

/* Adium OTR headers */
#import "ESOTRFingerprintDetailsWindowController.h"
#import <AIUtilities/AIBundleAdditions.h>
#import <AdiumLibpurple/AIOMEMOController.h>
#import <Adium/AIAccountControllerProtocol.h>

//Metrics of the fingerprint list
#define FINGERPRINT_ROW_HEIGHT				24.0f	//A nib row of 17pt is a line of type, not a list row
#define FINGERPRINT_STATUS_COLUMN_WIDTH	   160.0f	//Enough for the longest state, and for the menu that offers three
#define FINGERPRINT_METHOD_COLUMN_WIDTH		64.0f	//"OMEMO" and "OTR", and nothing longer is coming
#define FINGERPRINT_COLUMN_GAP				 3.0f	//The gap the nib kept between the name and the status column
#define INSET_STYLE_PADDING					10.0f	//Room NSTableViewStyleInset keeps above the first and below the last row, fallback only

/*!
 * @class AICenteredTextFieldCell
 * @brief A text cell that sits in the middle of its row rather than against the top
 *
 * A row tall enough to hold a popup menu is taller than one line of text, and a plain
 * NSTextFieldCell spends the difference below the line instead of around it. Beside a popup,
 * which centres itself, that reads as the words having slipped upwards, and two columns set in
 * different sizes slip by different amounts. Only the height is touched here: colour, font and
 * alignment stay whatever the column asked for.
 */
@interface AICenteredTextFieldCell : NSTextFieldCell
@end

@implementation AICenteredTextFieldCell

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	CGFloat lineHeight = [self cellSizeForBounds:cellFrame].height;

	if (lineHeight > 0.0f && lineHeight < NSHeight(cellFrame)) {
		cellFrame.origin.y += floor((NSHeight(cellFrame) - lineHeight) / 2.0f);
		cellFrame.size.height = lineHeight;
	}

	[super drawInteriorWithFrame:cellFrame inView:controlView];
}

@end

/*! Give a column a centring cell, keeping how the one it had was set up */
static void AICentreTheTextIn(NSTableColumn *column)
{
	NSCell					*old = [column dataCell];
	AICenteredTextFieldCell	*centred = [[AICenteredTextFieldCell alloc] initTextCell:@""];

	[centred setFont:[old font]];
	[centred setAlignment:[old alignment]];
	[centred setLineBreakMode:[old lineBreakMode]];
	[centred setEditable:NO];
	[centred setSelectable:NO];

	if ([old isKindOfClass:[NSTextFieldCell class]])
		[centred setTextColor:[(NSTextFieldCell *)old textColor]];

	[column setDataCell:centred];
}

@interface ESOTRPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (AISettingsFormView *)settingsForm;
- (void)populateForm:(AISettingsFormView *)form;
- (void)rebuildFormIfNeeded;
- (void)rebuildFormSoon;
- (void)rebuildForm;
- (void)holdView:(NSView *)aView;
- (void)configureFingerprintList;
- (void)configureControlSizes;
- (CGFloat)heightOfFingerprintList;
- (void)updateFingerprintListHeight;
- (void)tearDown;
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification;
@end

/*!
 * @brief A nib label reused as a row label: without its trailing colon.
 *
 * Keeps every existing translation of the old label usable while matching the
 * System Settings look, where row labels carry no colon.
 */
static NSString *AIRowLabel(NSString *label)
{
	NSCharacterSet	*whitespace = [NSCharacterSet whitespaceCharacterSet];
	/* U+003A and the full width U+FF1A the CJK translations use ("アカウント：") */
	NSCharacterSet	*colons = [NSCharacterSet characterSetWithCharactersInString:@":："];
	NSString		*trimmed = [label stringByTrimmingCharactersInSet:whitespace];

	while ([trimmed length] > 0 &&
		   [colons characterIsMember:[trimmed characterAtIndex:([trimmed length] - 1)]]) {
		trimmed = [[trimmed substringToIndex:([trimmed length] - 1)] stringByTrimmingCharactersInSet:whitespace];
	}

	return trimmed;
}

/*!
 * @brief The three things that can have been decided about one OMEMO device
 *
 * In the order of AIOMEMOTrust, so that the menu's index and the stored value are the same
 * number. Any other order would need a translation between them, which is one more place to
 * get a trust decision wrong.
 */
static NSArray *AIOMEMOTrustTitles(void)
{
	static NSArray *titles = nil;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		//Named through this class's bundle, since a function out here has no self to ask
		NSBundle *ours = [NSBundle bundleForClass:[ESOTRPreferences class]];

		titles = [NSArray arrayWithObjects:
				  AILocalizedStringFromTableInBundle(@"Not yet decided", nil, ours, "An OMEMO device the user has not said anything about"),
				  AILocalizedStringFromTableInBundle(@"Accepted", nil, ours, "An OMEMO device the user has accepted"),
				  AILocalizedStringFromTableInBundle(@"Rejected", nil, ours, "An OMEMO device the user has turned down"),
				  nil];
	});
	return titles;
}

/*!
 * @brief A row about an OMEMO device rather than an OTR key
 */
static BOOL AIRowIsOMEMO(NSDictionary *fingerprintDict)
{
	return [[fingerprintDict objectForKey:@"Method"] isEqualToString:@"OMEMO"];
}

@implementation ESOTRPreferences

//Preference pane properties
/* Unlocalized, unlike the label: the sidebar grouping matches panes by this,
 * and a match must not depend on the user's language. */
- (NSString *)paneIdentifier{
	return @"Encryption";
}
- (NSString *)label
{
    return AILocalizedString(@"Encryption",nil);
}
- (NSString *)nibName
{
    return @"OTRPrefs";
}
- (NSImage *)image
{
	return [NSImage imageNamed:@"lock-locked" forClass:[adium class]];
}

#pragma mark View

/*!
 * @brief Our view: the nib's controls, arranged by the settings form
 *
 * The nib still supplies the account menu's pop up, the three buttons and the fingerprint table
 * (with its scroll view), but no longer their arrangement: they become the rows of two cards laid
 * out by AISettingsFormView. Mirrors -[AIModularPane view] so the subclass hooks fire in the same
 * order, with one deliberate exception, see below.
 */
- (NSView *)view
{
	if (!view) {
		[NSBundle ai_loadNibNamed:[self nibName] owner:self];

		/* The nib set the inherited 'view' outlet to its own top level view. nibView takes it over;
		 * it keeps the controls the form does not host - the three labels and the private key
		 * field - alive, and -tearDown lets go of it.
		 */
		nibView = view;
		view = nil;

		/* -viewDidLoad runs before the form is built, unlike AIAccountListPreferences where it runs
		 * after: the shape of both cards depends on what it finds. Without an account there is no
		 * account row to build and without a fingerprint no list, and a card which was built with a
		 * row cannot exchange it for another one afterwards.
		 */
		[self viewDidLoad];

		view = [self buildSettingsForm];

		[self localizePane];

		/* The pop up row measures its button itself at every layout, so all that is left after
		 * -viewDidLoad filled the account menu is one more layout pass. */
		[(AISettingsFormView *)view layoutForWidth:NSWidth([view frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief The settings form we live in, or nil before -view built it
 */
- (AISettingsFormView *)settingsForm
{
	return ([view isKindOfClass:[AISettingsFormView class]] ? (AISettingsFormView *)view : nil);
}

/*!
 * @brief Stack the nib's controls into a settings form
 */
- (AISettingsFormView *)buildSettingsForm
{
	/* No width of our own: the form falls back to a usable one and the preferences window hands it
	 * its column width right afterwards. */
	AISettingsFormView	*form = [[AISettingsFormView alloc] initWithWidth:0.0f];

	[self populateForm:form];

	return form;
}

/*!
 * @brief Fill an empty form with our two cards
 *
 * Split off from -buildSettingsForm because it runs again on every rebuild, and it remembers what
 * it built for so -rebuildFormIfNeeded can tell when the answer would be a different one.
 */
- (void)populateForm:(AISettingsFormView *)form
{
	BOOL	hasAccounts = ([popUp_accounts numberOfItems] > 0);
	BOOL	hasFingerprints = ([fingerprintDictArray count] > 0);

	//The nib's first bold label with its rule under it, now the header of the first card
	[form addSectionHeader:AILocalizedString(@"Private Keys", nil)];

	if (hasAccounts) {
		/* A choice plus a way to act on it, which is exactly the shape of a pop up row: pick the
		 * account on the left, make it a key with the button at the trailing edge. The form dims
		 * the label with the menu, so the hand dimming below only has to reach the button. */
		[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Account:", nil))
				  popUpButton:popUp_accounts
			  accessoryButton:button_generate];
		[self holdView:popUp_accounts];
		[self holdView:button_generate];

		/* The fingerprint of that account's key, as the line which explains the row above it.
		 * Deliberately not the nib's text field in a full width row: only a detail row is measured
		 * again at every layout, so this is the only shape which refolds when the window is resized
		 * instead of clipping a fingerprint which no longer fits on one line. It is selectable, so
		 * the fingerprint can still be copied out of it. */
		[form addDetailRow:privateKeyDescription];
	} else {
		/* No account at all: the nib showed a dead pop up over an empty field and left the user to
		 * work out why. A card wants a row rather than a bold header above nothing. */
		[form addEmptyStateRow:AILocalizedString(@"No Accounts", "Shown instead of the account menu in the Encryption preferences when no account exists at all")];
		[form addFootnote:AILocalizedString(@"Add an account to create a private key.", "Footnote below the private key card of the Encryption preferences when no account exists")];
	}

	//...and the nib's second bold label heads the second card
	[form addSectionHeader:AILocalizedString(@"Known Fingerprints", nil)];

	/* Over the list, not under it: an explanation belongs before the thing it explains, the way
	 * System Settings puts one. It also has to stand where it is read when the list is empty -
	 * which is exactly when a reader has no idea what a fingerprint is doing here. */
	[form addInfoRow:AILocalizedString(@"A fingerprint identifies a key. Adium remembers one for everybody you have exchanged encrypted messages with, so it can tell you if it ever changes. OMEMO keeps one for each of a contact's devices, and you decide which of them to accept; OTR keeps one for the contact and is verified during a conversation.",
									   "Paragraph over the list of known fingerprints in the Encryption preferences")
		   withImage:[NSImage imageWithSystemSymbolName:@"person.badge.key" accessibilityDescription:nil]];

	if (hasFingerprints) {
		/* The list is the card: it fills it edge to edge and its own height decides how tall the
		 * card is. Its height is calculated rather than measured, see -heightOfFingerprintList, and
		 * it has to be right before the row is added: the form reads the natural size of a hosted
		 * view when it takes it in. */
		[self updateFingerprintListHeight];
		[form addEdgeToEdgeRow:scrollView_fingerprints];
		[self holdView:scrollView_fingerprints];

		/* ...and the two buttons hang under it, the way System Settings puts a +/- bar under a
		 * list. The bar is built by the form so that nothing here positions a button by hand. */
		[form addAccessoryView:[AISettingsFormView rowOfViews:[NSArray arrayWithObjects:
															   button_showFingerprint,
															   button_forgetFingerprint,
															   nil]]];
		[self holdView:button_showFingerprint];
		[self holdView:button_forgetFingerprint];
	} else {
		//Nothing known yet: an empty bordered table with no rows says less than a sentence does
		[form addEmptyStateRow:AILocalizedString(@"No Known Fingerprints", "Shown instead of the fingerprint list in the Encryption preferences when no fingerprint is known")];
	}

	builtWithAccountRow = hasAccounts;
	builtWithFingerprintList = hasFingerprints;
	builtPrivateKeyDescription = [privateKeyDescription copy];
}

/*!
 * @brief Keep a hold of a nib control the form is hosting
 *
 * A card retains the views it was given and lets go of them again when the form is rebuilt, and
 * the nib's view let go of them the moment they moved into that card. Without a reference of our
 * own the first rebuild would deallocate the very controls it is about to add back.
 */
- (void)holdView:(NSView *)aView
{
	if (!aView) return;

	if (!hostedViews) hostedViews = [[NSMutableArray alloc] init];
	if (![hostedViews containsObject:aView]) [hostedViews addObject:aView];
}

/*!
 * @brief Build the form again if it would come out differently now
 *
 * Three things decide the shape of the form - whether there is an account, whether there is a
 * fingerprint, and the line under the account row - and none of them can be changed in a row which
 * is already on screen. Everything else (the button titles, the rows of the list, the dimming) is
 * updated in place and never gets here.
 */
- (void)rebuildFormIfNeeded
{
	//Before -view built the form there is nothing to rebuild: -populateForm: is still to come
	if (![self settingsForm]) return;

	BOOL		hasAccounts = ([popUp_accounts numberOfItems] > 0);
	BOOL		hasFingerprints = ([fingerprintDictArray count] > 0);
	NSString	*description = (privateKeyDescription ? privateKeyDescription : @"");
	NSString	*built = (builtPrivateKeyDescription ? builtPrivateKeyDescription : @"");

	if ((hasAccounts == builtWithAccountRow) &&
		(hasFingerprints == builtWithFingerprintList) &&
		[description isEqualToString:built]) return;

	[self rebuildFormSoon];
}

/*!
 * @brief Rebuild the whole form once the run loop comes back around
 *
 * Coalesced on purpose: a single change to the key ring reaches us as both a key list and a
 * fingerprint list update, and each of those would otherwise pay for a complete rebuild. Deferring
 * it also keeps a rebuild out of the middle of a menu item's action, which is where the account
 * pop up sends us from.
 */
- (void)rebuildFormSoon
{
	if (rebuildScheduled || !viewIsOpen) return;

	rebuildScheduled = YES;
	[self performSelector:@selector(rebuildForm) withObject:nil afterDelay:0.0];
}

/*!
 * @brief Throw the cards away and build them again from what we know now
 *
 * Cheap - two cards - and it is the only way a card which was not there before (the list which
 * just gained its first fingerprint) can appear at all.
 */
- (void)rebuildForm
{
	rebuildScheduled = NO;

	AISettingsFormView	*form = [self settingsForm];

	if (!form) return;

	/* Where the scrolling column stands now: the form is empty for a moment while it is rebuilt,
	 * which drags the column back to the top. A fingerprint arriving from a conversation in another
	 * window must not make the page the user is reading jump. */
	NSClipView	*clipView = [[form enclosingScrollView] contentView];
	NSPoint		 scrollOrigin = (clipView ? [clipView bounds].origin : NSZeroPoint);

	/* Out of the cards before the cards go: every one of these is retained by us as well, so this
	 * hands them back rather than freeing them. */
	for (NSView *hosted in hostedViews) {
		[hosted removeFromSuperview];
	}

	[form removeAllSections];

	[self populateForm:form];
	[form layoutForWidth:NSWidth([form frame])];

	if (clipView) {
		//Constrained, because the form may well be shorter than it was
		NSRect	proposed = NSMakeRect(scrollOrigin.x, scrollOrigin.y,
									  NSWidth([clipView bounds]), NSHeight([clipView bounds]));

		[clipView scrollToPoint:[clipView constrainBoundsRect:proposed].origin];
		[[form enclosingScrollView] reflectScrolledClipView:clipView];
	}
}

#pragma mark Configuration

- (void)viewDidLoad
{
	/* Set before anything below asks for data: -updateFingerprintsList and -updatePrivateKeyList
	 * are called from the OTR adapter at any moment, and this flag is what keeps them off outlets
	 * which are not loaded yet or have already been given up. */
	viewIsOpen = YES;

	//Localize the interface; the xib is unlocalized
	[button_showFingerprint setTitle:[AILocalizedString(@"Show Fingerprint", nil) stringByAppendingEllipsis]];
	[button_forgetFingerprint setTitle:AILocalizedString(@"Forget Fingerprint", nil)];
	[[[tableView_fingerprints tableColumnWithIdentifier:@"UID"] headerCell] setStringValue:AILocalizedString(@"Name", nil)];
	[[[tableView_fingerprints tableColumnWithIdentifier:@"Status"] headerCell] setStringValue:AILocalizedString(@"Status", "Column header for the fingerprint status in the Encryption preferences")];

	[self configureFingerprintList];
	[self configureControlSizes];

	/* Account Menu. The pop up and the Generate button have to exist first: AIAccountMenu rebuilds
	 * its menu inside its own initializer, so -accountMenu:didRebuildMenuItems: reaches us before
	 * the assignment below comes back. In the nib world that went without saying. */
	accountMenu = [AIAccountMenu accountMenuWithDelegate:self
											 submenuType:AIAccountNoSubmenu
										  showTitleVerbs:NO];

	//Fingerprints
	[self updateFingerprintsList];

	[self updatePrivateKeyList];

	[textField_privateKey setSelectable:YES];

	[self tableViewSelectionDidChange:[NSNotification notificationWithName:@"SelectionChanged" object:nil]];
}

/*!
 * @brief Turn the nib's bordered table into the list a card is made of
 *
 * The table itself is untouched - the same two columns, the same cells, the same data source - but
 * it no longer scrolls: it is laid out at the full height of its rows and the preferences column
 * scrolls instead. The scroll view stays (a table view outside of one loses its tiling and its
 * clip view) and carries no border, no background and no scrollers; being an AIPassthroughScrollView
 * it hands the scroll wheel on to the column behind it, which an ordinary scroll view would swallow
 * as soon as the pointer rested over a row.
 */
- (void)configureFingerprintList
{
	[tableView_fingerprints setDelegate:self];
	[tableView_fingerprints setDataSource:self];
	[tableView_fingerprints setTarget:self];
	[tableView_fingerprints setDoubleAction:@selector(showFingerprint:)];

	/* Row heights are measured against the table's width, so the table has to follow the width the
	 * form gives the scroll view from the very first layout - the nib leaves it non-resizable. */
	[tableView_fingerprints setAutoresizingMask:NSViewWidthSizable];

	if (@available(macOS 11.0, *)) {
		[tableView_fingerprints setStyle:NSTableViewStyleInset];
	}
	[tableView_fingerprints setRowHeight:FINGERPRINT_ROW_HEIGHT];
	/* No room between the rows - a list row is its own height and nothing else, which is what
	 * -heightOfFingerprintList counts on - but the nib's 3pt between the two columns stays: it is
	 * the only thing keeping a name which had to be truncated off the status beside it. */
	[tableView_fingerprints setIntercellSpacing:NSMakeSize(FINGERPRINT_COLUMN_GAP, 0.0f)];
	[tableView_fingerprints setGridStyleMask:NSTableViewGridNone];
	[tableView_fingerprints setUsesAlternatingRowBackgroundColors:NO];
	//The card behind us is drawn by the form, so the table brings no background of its own
	[tableView_fingerprints setBackgroundColor:[NSColor clearColor]];
	[tableView_fingerprints setAllowsMultipleSelection:NO];
	[tableView_fingerprints setAllowsEmptySelection:YES];
	[tableView_fingerprints setAllowsColumnReordering:NO];
	//A focus ring drawn inside a card would trace the list rather than the card
	[tableView_fingerprints setFocusRingType:NSFocusRingTypeNone];
	//The table shows no column headers, so it needs a name of its own to be announced by
	[tableView_fingerprints setAccessibilityLabel:AILocalizedString(@"Known Fingerprints", nil)];

	/* The name takes whatever the status leaves, and the status keeps one width and hugs the
	 * trailing edge - the shape of a System Settings list row. The nib resized the last column
	 * instead, which in a card as wide as this one is left the status floating in the middle. */
	NSTableColumn	*statusColumn = [tableView_fingerprints tableColumnWithIdentifier:@"Status"];

	AICentreTheTextIn([tableView_fingerprints tableColumnWithIdentifier:@"UID"]);
	AICentreTheTextIn(statusColumn);

	/* Which of the two this row is about, between the name and the state. Added here rather than
	 * in the nib because everything else about this table is set up here, and because a column
	 * that only earns its place once there are two methods is easier to read about in code than
	 * in a file nobody opens. */
	if (![tableView_fingerprints tableColumnWithIdentifier:@"Method"]) {
		NSTableColumn *methodColumn = [[NSTableColumn alloc] initWithIdentifier:@"Method"];

		AICentreTheTextIn(methodColumn);
		[methodColumn setMinWidth:FINGERPRINT_METHOD_COLUMN_WIDTH];
		[methodColumn setMaxWidth:FINGERPRINT_METHOD_COLUMN_WIDTH];
		[methodColumn setWidth:FINGERPRINT_METHOD_COLUMN_WIDTH];
		[[methodColumn dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		[[methodColumn dataCell] setTextColor:[NSColor secondaryLabelColor]];

		//Between the name and the state, which is the order the eye reads them in
		[tableView_fingerprints addTableColumn:methodColumn];
		[tableView_fingerprints moveColumn:([tableView_fingerprints numberOfColumns] - 1)
								  toColumn:1];
	}

	[tableView_fingerprints setColumnAutoresizingStyle:NSTableViewFirstColumnOnlyAutoresizingStyle];
	[statusColumn setMinWidth:FINGERPRINT_STATUS_COLUMN_WIDTH];
	[statusColumn setMaxWidth:FINGERPRINT_STATUS_COLUMN_WIDTH];
	[statusColumn setWidth:FINGERPRINT_STATUS_COLUMN_WIDTH];
	[[statusColumn dataCell] setAlignment:NSTextAlignmentRight];

	/* The column has to be editable or a menu in it never opens, and that alone would make every
	 * other row's text typeable over. Which rows may actually be edited is decided one at a time,
	 * just below. */
	[statusColumn setEditable:YES];

	[scrollView_fingerprints setBorderType:NSNoBorder];
	[scrollView_fingerprints setDrawsBackground:NO];
	[scrollView_fingerprints setHasVerticalScroller:NO];
	[scrollView_fingerprints setHasHorizontalScroller:NO];
	[scrollView_fingerprints setVerticalScrollElasticity:NSScrollElasticityNone];
	[scrollView_fingerprints setHorizontalScrollElasticity:NSScrollElasticityNone];
	[scrollView_fingerprints setAutomaticallyAdjustsContentInsets:NO];
	[scrollView_fingerprints setContentInsets:NSEdgeInsetsZero];
	[scrollView_fingerprints setAutoresizingMask:NSViewNotSizable];
}

/*!
 * @brief Grow the nib's controls to the size a form row is laid out for
 *
 * Everything in this nib was built small, which is how the old, cramped pane fitted. A form row is
 * a regular sized row, and a small pop up sitting in one next to regular labels reads as broken.
 */
- (void)configureControlSizes
{
	NSFont	*regularFont = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeRegular]];

	for (NSButton *button in [NSArray arrayWithObjects:button_generate, button_showFingerprint, button_forgetFingerprint, nil]) {
		[button setControlSize:NSControlSizeRegular];
		[button setFont:regularFont];
		[button sizeToFit];
	}

	[popUp_accounts setControlSize:NSControlSizeRegular];
	[popUp_accounts setFont:regularFont];
	[popUp_accounts sizeToFit];
}

/*!
 * @brief Perform actions before the view closes
 */
- (void)viewWillClose
{
	[self tearDown];
}

/*!
 * @brief Undo everything -viewDidLoad set up
 *
 * Idempotent, so that it is safe to run it from both -viewWillClose and -dealloc. Running it from
 * -dealloc matters here: the table's delegate, its data source, its target, the target of the three
 * buttons and the account menu's delegate are all non-retaining references to us, and they sit on
 * views which are released on a different path (the form's, not ours).
 *
 * Note when this runs: the preferences window closing, never the user picking another pane from the
 * sidebar - switching panes only takes our view out of the window and leaves everything here alive.
 * Nothing is lost by that, because nothing is ever held back: generating a key and forgetting a
 * fingerprint both act the moment they are pressed.
 */
- (void)tearDown
{
	viewIsOpen = NO;

	//A rebuild reaching a closed pane would ask -view for a form and so build a second one
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(rebuildForm) object:nil];
	rebuildScheduled = NO;

	[tableView_fingerprints setDelegate:nil];
	[tableView_fingerprints setDataSource:nil];
	[tableView_fingerprints setTarget:nil];
	[tableView_fingerprints setDoubleAction:NULL];

	//The nib wired these three to us; a button which outlives us must not still point at us
	[button_generate setTarget:nil];
	[button_showFingerprint setTarget:nil];
	[button_forgetFingerprint setTarget:nil];

	[accountMenu setDelegate:nil];
	accountMenu = nil;

	for (NSView *hosted in hostedViews) {
		[hosted removeFromSuperview];
	}
	hostedViews = nil;

	/* The views behind these outlets belong to the form or to the nib's view, either of which may
	 * be released after us; forget them so a second -tearDown cannot message a view which is on
	 * its way out. */
	popUp_accounts = nil;
	button_generate = nil;
	textField_privateKey = nil;
	scrollView_fingerprints = nil;
	tableView_fingerprints = nil;
	button_showFingerprint = nil;
	button_forgetFingerprint = nil;

	fingerprintDictArray = nil;
	privateKeyDescription = nil;
	builtPrivateKeyDescription = nil;

	nibView = nil;
}

/*!
 * @brief Deallocate
 */
- (void)dealloc
{
	//Releases the form and runs -viewWillClose, but only if a view was ever built
	[self closeView];
	//...so tear down again for the pane which never showed itself. -tearDown is idempotent.
	[self tearDown];

	/* Stays here rather than in -tearDown: we outlive the preferences window (the OTR adapter and the
	 * preference controller both hold on to us), and a blanket unregistration on every close would
	 * quietly tear off any observer a future -init registers, with nothing to register it again. */
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark Fingerprint list height

/*!
 * @brief The height the list needs to show every row without scrolling
 *
 * A table view lays itself out as the sum of its row heights plus its intercell spacing per row, so
 * that is what is added up here - the spacing is set to zero in -configureFingerprintList, but
 * reading it rather than assuming it keeps this in step with the table if that ever changes.
 *
 * On top of the rows themselves a table style keeps room above the first row and below the last -
 * NSTableViewStyleInset keeps 10pt at each end. That padding is measured off the table (the top of
 * its first row is exactly it) rather than assumed, and it is added unconditionally: leaving it out
 * is precisely what makes a card 20pt too short for its list, which the user sees as "the list
 * scrolls inside its card". The table then gets the last word through its row rects, so a layout we
 * did not predict still cannot end up with less room than the table laid itself out in.
 */
- (CGFloat)heightOfFingerprintList
{
	CGFloat		spacing = [tableView_fingerprints intercellSpacing].height;
	NSInteger	tableRows = [tableView_fingerprints numberOfRows];

	/* The room the style keeps at each end of the list. Only the table can say what it is, and only
	 * once it has rows; until then the value the inset style uses is the best guess we have. */
	CGFloat		endPadding = INSET_STYLE_PADDING;

	if (tableRows > 0) {
		CGFloat		topInset = NSMinY([tableView_fingerprints rectOfRow:0]);

		if (topInset >= 0.0f) endPadding = topInset;
	}

	//Every row of this table is the same height, and that height is a whole number of points
	CGFloat		height = ((CGFloat)tableRows * ([tableView_fingerprints rowHeight] + spacing)) + (2.0f * endPadding);

	if (tableRows > 0) {
		CGFloat		contentHeight = NSMaxY([tableView_fingerprints rectOfRow:(tableRows - 1)]) + endPadding;

		if (contentHeight > height) height = contentHeight;
	}

	/* A column header is not one of the rows and does not scroll with them. This table has none -
	 * the nib gives it no header view - but reading the height off it rather than assuming zero
	 * keeps the card right if one is ever put back. */
	NSTableHeaderView	*headerView = [tableView_fingerprints headerView];

	if (headerView) height += NSHeight([headerView frame]);

	CGFloat		minimumHeight = [tableView_fingerprints rowHeight] + (2.0f * endPadding);

	return ceil(height < minimumHeight ? minimumHeight : height);
}

/*!
 * @brief Grow or shrink the card around the list to fit its rows
 *
 * The list is the edge to edge row of a card, so its height is the card's height. Handing the new
 * height to the form makes the form resize its card and itself, and the preferences window - which
 * watches the pane's frame - resizes its scrolling column in turn. That is the whole chain: the
 * card grows with the number of fingerprints and the window scrolls, not the list.
 */
- (void)updateFingerprintListHeight
{
	if (!scrollView_fingerprints) return;

	CGFloat		height = [self heightOfFingerprintList];

	if (fabs(NSHeight([scrollView_fingerprints frame]) - height) < 0.5f) return;

	[scrollView_fingerprints setFrameSize:NSMakeSize(NSWidth([scrollView_fingerprints frame]), height)];

	/* The size is set either way - -populateForm: sets it before handing the list over, and the form
	 * reads the height off the view it is given - but the form is only laid out again when the list
	 * is one of its rows. Out of the form it is either mid rebuild (-rebuildForm lays the form out
	 * itself, a line later) or in the empty state, where the card holds a sentence and no list at
	 * all: laying the whole form out for a view it does not contain is work nobody sees. */
	if ([scrollView_fingerprints superview]) [[self settingsForm] noteContentSizeChanged];
}

#pragma mark Updating

/*!
 * @brief Update the fingerprint display
 *
 * Called by the OTR adapter when -otr informs us the fingerprint list changed
 */
/*!
 * @brief Everything OMEMO knows, as rows of the same list
 *
 * OTR and OMEMO answer the same question for the person reading this pane, which is whose keys
 * are known and what has been decided about them, so they belong in one list rather than two.
 * What differs is the shape of the answer: OTR has one key per contact and a yes or no about it,
 * OMEMO has one per device and three states, which is why the row says which of the two it is.
 */
- (void)addOMEMODevicesToList
{
	for (AIAccount *account in adium.accountController.accounts) {
		if (![AIOMEMOController isPossibleForAccount:account]) continue;

		for (NSDictionary *device in [AIOMEMOController devicesKnownToAccount:account]) {
			[fingerprintDictArray addObject:[NSDictionary dictionaryWithObjectsAndKeys:
				device[@"jid"],				@"UID",
				@"OMEMO",					@"Method",
				device[@"fingerprint"],		@"FingerprintString",
				device[@"trust"],			@"OMEMOTrust",
				device[@"device"],			@"OMEMODevice",
				account,					@"AIAccount",
				nil]];
		}
	}
}

- (void)updateFingerprintsList
{
	OtrlUserState   otrg_plugin_userstate = otrg_get_userstate();

	if (viewIsOpen) {
		ConnContext		*context;
		Fingerprint		*fingerprint;

		fingerprintDictArray = [[NSMutableArray alloc] init];

		for (context = (otrg_plugin_userstate ? otrg_plugin_userstate->context_root : NULL); context != NULL;
			 context = context->next) {

			/* Masters only. Version 3 keeps one context per device pair and a
			 * master beside them; the fingerprint list hangs off the master,
			 * so children contribute nothing here - and asking the master
			 * whether it is encrypted always answers no, which is how this
			 * column used to read "Not private" through an open, verified
			 * session. The conversations are the master's children, so each
			 * fingerprint asks every instance below and reports the best state
			 * of one actually using it, the way the reference does. */
			if (context->m_context != context) continue;

			fingerprint = context->fingerprint_root.next;
			/* If there's no fingerprint, don't add it to the known
				* fingerprints list */
			while (fingerprint) {
				char			hash[45];
				NSDictionary	*fingerprintDict;
				NSString		*UID;
				NSString		*state, *fingerprintString;

				UID = [NSString stringWithUTF8String:context->username];

				TrustLevel	bestLevel = TRUST_NOT_PRIVATE;
				BOOL		inUse = NO;

				/* The master itself is in this walk on purpose: a legacy
				 * version 2 peer without instance tags converses on the master
				 * directly. */
				for (ConnContext *instance = context->m_context;
					 instance && instance->m_context == context->m_context;
					 instance = instance->next) {
					if (instance->active_fingerprint != fingerprint) continue;

					TrustLevel thisLevel = otrg_plugin_context_to_trust(instance);

					inUse = YES;
					if (thisLevel == TRUST_PRIVATE) {
						bestLevel = TRUST_PRIVATE;
					} else if (thisLevel == TRUST_UNVERIFIED && bestLevel != TRUST_PRIVATE) {
						bestLevel = TRUST_UNVERIFIED;
					} else if (thisLevel == TRUST_FINISHED && bestLevel == TRUST_NOT_PRIVATE) {
						bestLevel = TRUST_FINISHED;
					}
				}

				if (!inUse) {
					state = AILocalizedString(@"Unused","Word to describe an encryption fingerprint which is not currently being used");
				} else {
					switch (bestLevel) {
						case TRUST_NOT_PRIVATE:
							state = AILocalizedString(@"Not private",nil);
							break;
						case TRUST_UNVERIFIED:
							state = AILocalizedString(@"Unverified",nil);
							break;
						case TRUST_PRIVATE:
							state = AILocalizedString(@"Private",nil);
							break;
						case TRUST_FINISHED:
							state = AILocalizedString(@"Finished",nil);
							break;
						default:
							state = @"";
							break;
					}
				}

				otrl_privkey_hash_to_human(hash, fingerprint->fingerprint);
				fingerprintString = [NSString stringWithUTF8String:hash];

				AIAccount *account = [adium.accountController accountWithInternalObjectID:[NSString stringWithUTF8String:context->accountname]];

				fingerprintDict = [NSDictionary dictionaryWithObjectsAndKeys:
					UID, @"UID",
					@"OTR", @"Method",
					state, @"Status",
					fingerprintString, @"FingerprintString",
					[NSValue valueWithPointer:fingerprint], @"FingerprintValue",
					account, @"AIAccount",
					nil];

				[fingerprintDictArray addObject:fingerprintDict];

				fingerprint = fingerprint->next;
			}
		}

		[self addOMEMODevicesToList];

		[tableView_fingerprints reloadData];

		//A row more or less is a taller or shorter card; the form has to be told
		[self updateFingerprintListHeight];

		/* The selection may have gone with the row it was on - "Forget Fingerprint" removes exactly
		 * the row which is selected - and a reload sends no selection notification, so the two
		 * buttons would stay lit above a list with nothing chosen in it. */
		[self tableViewSelectionDidChange:[NSNotification notificationWithName:@"SelectionChanged" object:nil]];

		//The first fingerprint replaces the empty state card, and the last one brings it back
		[self rebuildFormIfNeeded];
	}
}

/*!
 * @brief Update the key list
 *
 * Called by the OTR adapter when -otr informs us the private key list changed
 */
- (void)updatePrivateKeyList
{
	if (viewIsOpen) {
		NSString		*fingerprintString = nil;
		AIAccount		*account = ([popUp_accounts numberOfItems] ? [[popUp_accounts selectedItem] representedObject] : nil);

		if (account) {
			const char		*accountname = [account.internalObjectID UTF8String];
			const char		*protocol = [account.service.serviceCodeUniqueID UTF8String];
			char			*fingerprint;
			OtrlUserState	otrg_plugin_userstate;

			if ((otrg_plugin_userstate = otrg_get_userstate())){
				char fingerprint_buf[45];
				fingerprint = otrl_privkey_fingerprint(otrg_plugin_userstate,
													   fingerprint_buf, accountname, protocol);

				if (fingerprint) {
					[button_generate setTitle:AILocalizedString(@"Regenerate", nil)];
					fingerprintString = [NSString stringWithFormat:AILocalizedString(@"Fingerprint: %.80s",nil), fingerprint];
				} else {
					[button_generate setTitle:AILocalizedString(@"Generate", nil)];
					fingerprintString = AILocalizedString(@"No private key present", "Message to show in the Encryption OTR preferences when an account is selected which does not have a private key");
				}
			}
		}

		NSString	*description = (fingerprintString ? fingerprintString : @"");

		/* And the account's own OMEMO fingerprint under it, if it has one. This is the line a
		 * person reads out over the telephone while the other side compares it, so it belongs
		 * where the account's own key already is rather than somewhere it has to be hunted for.
		 * Only shown when it exists: an account that has never used OMEMO is not given an
		 * identity merely because somebody opened this window. */
		NSString	*omemoFingerprint = (account ? [AIOMEMOController ownFingerprintForAccount:account] : nil);

		if ([omemoFingerprint length]) {
			NSString *line = [NSString stringWithFormat:
							  AILocalizedString(@"OMEMO fingerprint: %@", "The account's own OMEMO fingerprint in the Encryption preferences"),
							  omemoFingerprint];

			description = ([description length] ? [description stringByAppendingFormat:@"\n%@", line] : line);
		}

		/* The nib's field is not one of the form's rows - the fingerprint is a detail row, which is
		 * the only kind of text the form folds again when the window is resized - but it is still
		 * kept in step: it is where the pane has always put this string, and it is selectable, so a
		 * pane which ever shows it again shows something the user can copy. */
		[textField_privateKey setStringValue:description];

		privateKeyDescription = [description copy];

		/* "Generate" and "Regenerate" are not the same width, and a pop up row lays its accessory
		 * button out at the frame the button carries: refit it and ask for a fresh layout. */
		[button_generate sizeToFit];
		[[self settingsForm] noteContentSizeChanged];

		//A different line under the account row means a different detail row, which means a new card
		[self rebuildFormIfNeeded];
	}
}

#pragma mark Actions

/*!
 * @brief Generate a new private key for the currently selected account
 *
 * Replacing an existing key asks first: the old key is gone for good, and every
 * contact who verified the old fingerprint has to verify the new one. The guard
 * comes from the late Mercurial mainline (adium@66367330), which the git line
 * this fork grew from never received.
 */
- (IBAction)generate:(id)sender
{
	AIAccount	*account = ([popUp_accounts numberOfItems] ? [[popUp_accounts selectedItem] representedObject] : nil);
	if (!account) return;

	BOOL			hasKey = NO;
	OtrlUserState	userstate = otrg_get_userstate();
	if (userstate) {
		char fingerprint_buf[45];
		hasKey = (otrl_privkey_fingerprint(userstate, fingerprint_buf,
										   [account.internalObjectID UTF8String],
										   [account.service.serviceCodeUniqueID UTF8String]) != NULL);
	}

	if (!hasKey) {
		otrg_plugin_create_privkey([account.internalObjectID UTF8String],
								   [account.service.serviceCodeUniqueID UTF8String]);
		return;
	}

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:AILocalizedString(@"Are you sure you want to generate a new OTR key?", nil)];
	[alert setInformativeText:AILocalizedString(@"This will permanently delete your old key and all your contacts will need to verify your fingerprint again.", "Message when regenerating an OTR key")];
	[alert addButtonWithTitle:AILocalizedString(@"Cancel", nil)];
	[alert addButtonWithTitle:AILocalizedString(@"Regenerate", nil)];

	[alert beginSheetModalForWindow:[view window] completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSAlertSecondButtonReturn) {
			otrg_plugin_create_privkey([account.internalObjectID UTF8String],
									   [account.service.serviceCodeUniqueID UTF8String]);
		}
	}];
}

/*!
 * @brief Show the fingerprint for the contact selected in the fingerprints NSTableView
 */
- (IBAction)showFingerprint:(id)sender
{
	NSInteger selectedRow = [tableView_fingerprints selectedRow];
	if (selectedRow != -1) {
		NSDictionary	*fingerprintDict = [fingerprintDictArray objectAtIndex:selectedRow];
		[ESOTRFingerprintDetailsWindowController showDetailsForFingerprintDict:fingerprintDict];
	}
}

/*!
 * @brief Delete the fingerprint for the contact selected in the fingerprints NSTableView
 */

- (IBAction)forgetFingerprint:(id)sender
{
	NSInteger selectedRow = [tableView_fingerprints selectedRow];
	if (selectedRow >= 0) {
		NSDictionary *fingerprintDict = [fingerprintDictArray objectAtIndex:selectedRow];

		/* Only OTR keeps a key it can be told to forget. An OMEMO device is remembered for as
		 * long as it exists, and the decision about it is changed on the row itself, so there is
		 * nothing here for one; the button is dimmed for those rows anyway. */
		if (AIRowIsOMEMO(fingerprintDict)) return;

		Fingerprint	*fingerprint = [[fingerprintDict objectForKey:@"FingerprintValue"] pointerValue];

		otrg_ui_forget_fingerprint(fingerprint);
	}
}

//Fingerprint tableview ------------------------------------------------------------------------------------------------
#pragma mark Fingerprint tableview
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [fingerprintDictArray count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if ((rowIndex >= 0) && (rowIndex < [fingerprintDictArray count])) {
		NSString		*identifier = [aTableColumn identifier];
		NSDictionary	*fingerprintDict = [fingerprintDictArray objectAtIndex:rowIndex];

		if ([identifier isEqualToString:@"UID"]) {
			NSString *who = [fingerprintDict objectForKey:@"UID"];

			/* One person can have several devices, and two rows carrying the same name and the
			 * same decision are otherwise the same row twice as far as anybody can tell. The
			 * start of the fingerprint tells them apart, and it is the part that gets compared
			 * out loud first anyway. */
			if (AIRowIsOMEMO(fingerprintDict)) {
				NSString *print = [fingerprintDict objectForKey:@"FingerprintString"];

				if ([print length] >= 8)
					return [NSString stringWithFormat:@"%@  %@\u2026", who, [print substringToIndex:8]];
			}

			return who;

		} else if ([identifier isEqualToString:@"Method"]) {
			return [fingerprintDict objectForKey:@"Method"];

		} else if ([identifier isEqualToString:@"Status"]) {
			/* An OMEMO row answers with the chosen item of its menu, an OTR row with the words
			 * describing a state it has no say over. */
			if (AIRowIsOMEMO(fingerprintDict))
				return [fingerprintDict objectForKey:@"OMEMOTrust"];

			return [fingerprintDict objectForKey:@"Status"];
		}
	}

	return @"";
}

/*!
 * @brief A decision is something the person makes, so an OMEMO row offers one
 *
 * OTR's state is reported, not chosen: it says what the session is doing, and verifying happens
 * through a dialogue of its own. OMEMO's is a standing decision about a device, which belongs on
 * the row it is about rather than behind a button somewhere else.
 */
- (NSCell *)tableView:(NSTableView *)aTableView
	dataCellForTableColumn:(NSTableColumn *)aTableColumn
					   row:(NSInteger)rowIndex
{
	if (!aTableColumn || rowIndex < 0 || rowIndex >= (NSInteger)[fingerprintDictArray count])
		return nil;

	if (![[aTableColumn identifier] isEqualToString:@"Status"]) return [aTableColumn dataCell];
	if (!AIRowIsOMEMO([fingerprintDictArray objectAtIndex:rowIndex])) return [aTableColumn dataCell];

	NSPopUpButtonCell *choice = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];

	[choice setControlSize:NSControlSizeSmall];
	[choice setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[choice setBordered:NO];
	[choice setArrowPosition:NSPopUpArrowAtBottom];
	/* Against the trailing edge, where the state of every other row already is. Left as it comes,
	 * the words start at the far side of the column while the OTR rows beside them end at it, and
	 * one list reads as two. */
	[choice setAlignment:NSTextAlignmentRight];
	[choice addItemsWithTitles:AIOMEMOTrustTitles()];

	return choice;
}

/*!
 * @brief Only an OMEMO row offers a decision, so only one may be edited
 *
 * The column is editable for the menu's sake. Without this, an OTR row's state, which is
 * reported rather than chosen, could be typed over with anything at all.
 */
- (BOOL)tableView:(NSTableView *)aTableView
shouldEditTableColumn:(NSTableColumn *)aTableColumn
			  row:(NSInteger)rowIndex
{
	if (rowIndex < 0 || rowIndex >= (NSInteger)[fingerprintDictArray count]) return NO;
	if (![[aTableColumn identifier] isEqualToString:@"Status"]) return NO;

	return AIRowIsOMEMO([fingerprintDictArray objectAtIndex:rowIndex]);
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)object
   forTableColumn:(NSTableColumn *)aTableColumn
			  row:(NSInteger)rowIndex
{
	if (rowIndex < 0 || rowIndex >= (NSInteger)[fingerprintDictArray count]) return;
	if (![[aTableColumn identifier] isEqualToString:@"Status"]) return;

	NSDictionary *fingerprintDict = [fingerprintDictArray objectAtIndex:rowIndex];
	if (!AIRowIsOMEMO(fingerprintDict)) return;

	[AIOMEMOController setTrust:[object integerValue]
				 forFingerprint:[fingerprintDict objectForKey:@"FingerprintString"]
					  onAccount:[fingerprintDict objectForKey:@"AIAccount"]];

	[self updateFingerprintsList];
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{

}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	NSInteger	selectedRow = [tableView_fingerprints selectedRow];
	BOOL		isOMEMO = (selectedRow >= 0 && selectedRow < (NSInteger)[fingerprintDictArray count] &&
						   AIRowIsOMEMO([fingerprintDictArray objectAtIndex:selectedRow]));

	[button_showFingerprint setEnabled:(selectedRow != -1)];
	//Forgetting is an OTR idea; an OMEMO device is decided about on its own row
	[button_forgetFingerprint setEnabled:(selectedRow != -1 && !isOMEMO)];
}


//Account menu ---------------------------------------------------------------------------------------------------------
#pragma mark Account menu
/*!
 * @brief Account menu delegate
 */
- (void)accountMenu:(AIAccountMenu *)inAccountMenu didRebuildMenuItems:(NSArray *)menuItems {
	[popUp_accounts setMenu:[inAccountMenu menu]];

	BOOL hasItems = ([[popUp_accounts menu] numberOfItems] > 0);
	[popUp_accounts setEnabled:hasItems];
	[button_generate setEnabled:hasItems];

	/* A rebuilt menu selects its first item, which is not necessarily the account the line below the
	 * row is describing: without this, adding, removing or enabling an account while the pane is open
	 * left the fingerprint of the account which was selected a moment ago standing under the name of
	 * another one. -updatePrivateKeyList notices when the card has to be built again. */
	[self updatePrivateKeyList];

	//The first account brings the account row, and losing the last one takes it away again
	[self rebuildFormIfNeeded];
}

- (void)accountMenu:(AIAccountMenu *)inAccountMenu didSelectAccount:(AIAccount *)inAccount {
	[self updatePrivateKeyList];
}

- (NSControlSize)controlSizeForAccountMenu:(AIAccountMenu *)inAccountMenu
{
	/* Regular, not small as the nib's pop up was: this menu now sits in a form row beside regular
	 * sized labels, and the size given here decides both the menu's font and the size of the
	 * service icons in it. */
	return NSControlSizeRegular;
}

@end
