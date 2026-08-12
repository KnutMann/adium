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

#import <Adium/AIAccount.h>
#import <Adium/AIEditStateWindowController.h>
#import <Adium/AIStatus.h>
#import <Adium/AIStatusControllerProtocol.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIAutoScrollView.h>
#import <AIUtilities/AIStringFormatter.h>
#import <AIUtilities/AITextAttributes.h>
#import <AIUtilities/AIWindowAdditions.h>
#import <Adium/AIMessageEntryTextView.h>

#define	SEND_ON_ENTER					@"Send On Enter"

/* The window is not resizable, so its size is a matter of arithmetic rather than of a saved frame:
 * the form says how tall it is, the button bar and the margins are added to that. 480 points of
 * content leave the cards 440 wide, which is enough for a label column of the intended width. */
#define WINDOW_CONTENT_WIDTH			480.0
#define WINDOW_MARGIN					20.0
//Between the form and the button bar
#define BUTTON_BAR_GAP					20.0
#define BUTTON_MINIMUM_WIDTH			84.0
//Height of the status message field. Deliberately fixed: four or five lines of a status message
#define STATUS_MESSAGE_HEIGHT			76.0

@interface AIEditStateWindowController ()
- (id)initWithWindowNibName:(NSString *)windowNibName forType:(AIStatusType)inStatusType andAccount:(AIAccount *)inAccount customState:(AIStatus *)inStatusState notifyingTarget:(id)inTarget showSaveCheckbox:(BOOL)inShowSaveCheckbox;
- (void)configureStateMenu;
- (void)buildForm;
- (void)layoutWindowContents;
- (void)synchronizeStatusMessageTextViewSize;
- (void)finishEditing;

- (void)setOriginalStatusState:(AIStatus *)inState forType:(AIStatusType)inStatusType;
- (void)setAccount:(AIAccount *)inAccount;
- (void)configureForAccountAndWorkingStatusState;

- (void)notifyOfStateChange;
@end

/*!
 * @class AIEditStateWindowController
 * @brief Interface for editing a status state
 *
 * This class provides an interface for editing a status state dictionary's properties.
 */
@implementation AIEditStateWindowController

static	NSMutableDictionary	*controllerDict = nil;

/*!
 * @brief Open a custom state editor window or sheet
 *
 * Open either a sheet or window containing a state editor.  The state editor will be primed with the passed state
 * dictionary.  When the user successfully closes the editor, the target will be notified and passed the updated
 * state dictionary.  Only one window will be shown per target at a time.
 *
 * @param inStatusState Initial AIStatus
 * @param inStatusType AIStatusType to use initially if inStatusState is nil
 * @param inAccount The account which to configure the custom state window; nil to configure globally
 * @param inShowSaveCheckbox YES if the save checkbox should be shown; NO if it should not. If YES, the title on an incoming status will be cleared to make it auto-update.
 * @param parentWindow Parent window for a sheet, nil for a stand alone editor
 * @param inTarget Target object to notify when editing is complete
 */
+ (id)editCustomState:(AIStatus *)inStatusState forType:(AIStatusType)inStatusType andAccount:(AIAccount *)inAccount withSaveOption:(BOOL)inShowSaveCheckbox onWindow:(id)parentWindow notifyingTarget:(id)inTarget
{
	AIEditStateWindowController	*controller;

	NSNumber	*targetHash = [NSNumber numberWithUnsignedInteger:[inTarget hash]];

	if ((controller = [controllerDict objectForKey:targetHash])) {
		[controller setAccount:inAccount];

		if ([[controller currentConfiguration] statusType] != inStatusType) {
			//It's not currently editing a status of the type requested; configure based on the passed status
			[controller setOriginalStatusState:inStatusState forType:inStatusType];
			[controller configureForAccountAndWorkingStatusState];
		}

	} else {
		controller = [[self alloc] initWithWindowNibName:@"EditStateSheet"
												 forType:inStatusType
											  andAccount:inAccount
											 customState:inStatusState
										 notifyingTarget:inTarget
										showSaveCheckbox:inShowSaveCheckbox];
		if (!controllerDict) controllerDict = [[NSMutableDictionary alloc] init];
		[controllerDict setObject:controller forKey:targetHash];
	}

	if (parentWindow) {
		/* The completion handler is the only place a sheet is ever cleaned up: -windowWillClose: is
		 * not sent for a sheet which is ended rather than closed, which is why the old sheet path
		 * leaked a whole controller every time a status was edited from the preferences. The block
		 * holds on to the controller for us until it has run. */
		[(NSWindow *)parentWindow beginSheet:[controller window]
						   completionHandler:^(NSModalResponse returnCode) {
			[[controller window] orderOut:nil];
			[controller finishEditing];
		}];

	} else {
		[controller showWindow:nil];
		[[controller window] makeKeyAndOrderFront:nil];

		//-activate took over from -activateIgnoringOtherApps: in macOS 14; we still run on 11
		if (@available(macOS 14.0, *)) {
			[NSApp activate];
		} else {
			[NSApp activateIgnoringOtherApps:YES];
		}
	}

	return controller;
}

/*!
 * @brief Init the window controller
 */
- (id)initWithWindowNibName:(NSString *)windowNibName forType:(AIStatusType)inStatusType andAccount:(AIAccount *)inAccount customState:(AIStatus *)inStatusState notifyingTarget:(id)inTarget showSaveCheckbox:(BOOL)inShowSaveCheckbox
{
    if ((self = [super initWithWindowNibName:windowNibName])) {
		target = inTarget;
		showSaveCheckbox = inShowSaveCheckbox;

		[self setOriginalStatusState:inStatusState forType:inStatusType];
		[self setAccount:inAccount];
	}

	return self;
}

/*!
 * @brief Set our status state
 *
 * Also create the working state if we don't have one or the original status state is of the wrong statusType.
 * If showSaveCheckbox is YES, clear workingStatusState's title so it will autoupdate.
 */
- (void)setOriginalStatusState:(AIStatus *)inStatusState forType:(AIStatusType)inStatusType
{
	if (originalStatusState != inStatusState) {
		[originalStatusState release];
		originalStatusState = [inStatusState retain];
	}

	[workingStatusState release];
	workingStatusState = (originalStatusState ?
						  [originalStatusState mutableCopy] :
						  [[AIStatus statusOfType:inStatusType] retain]);

	/* Reset to the default for this status type if we're not on it already */
	if (workingStatusState.statusType != inStatusType) {
		[workingStatusState setStatusType:inStatusType];
		[workingStatusState setStatusName:[[adium statusController] defaultStatusNameForType:inStatusType]];
	}

	//Clear the title if the save checkbox is showing so it will autoupdate.
	if (showSaveCheckbox) [workingStatusState setTitle:nil];
}

- (void)setAccount:(AIAccount *)inAccount
{
	if (inAccount != account) {
		[account release];
		account = [inAccount retain];
	}
}

/*!
 * Deallocate
 */
- (void)dealloc
{
	[originalStatusState release];
	[workingStatusState release];
	[account release];

	[super dealloc];
}

//Window setup ---------------------------------------------------------------------------------------------------------
#pragma mark Window setup

/*!
 * @brief Configure the window after it loads
 */
- (void)windowDidLoad
{
	BOOL				sendOnEnter;

	[[self window] setTitle:AILocalizedString(@"Custom Status", nil)];

	sendOnEnter = [[adium.preferenceController preferenceForKey:SEND_ON_ENTER
															group:PREF_GROUP_GENERAL] boolValue];

	[scrollView_statusMessage setAutohidesScrollers:YES];
	[scrollView_statusMessage setAlwaysDrawFocusRingIfFocused:YES];
	[textView_statusMessage setTarget:self action:@selector(okay:)];
	[textView_statusMessage setDelegate:self];

	[textView_statusMessage setAllowsDocumentBackgroundColorChange:YES];

	//Return inserts a new line; enter follows the user's preference, so by default it says OK
	[textView_statusMessage setSendOnReturn:NO];
	[textView_statusMessage setSendOnEnter:sendOnEnter];

	if ([textView_statusMessage isKindOfClass:[AIMessageEntryTextView class]]) {
		[(AIMessageEntryTextView *)textView_statusMessage setClearOnEscape:NO];
		[(AIMessageEntryTextView *)textView_statusMessage setPushPopEnabled:NO];
		[(AIMessageEntryTextView *)textView_statusMessage setHistoryEnabled:NO];
	}

	[self buildForm];

	[self configureForAccountAndWorkingStatusState];

	[textView_statusMessage setTypingAttributes:[adium.contentController defaultFormattingAttributes]];

	NSMutableCharacterSet *noNewlinesCharacterSet;
	noNewlinesCharacterSet = [[[NSCharacterSet characterSetWithCharactersInString:@""] invertedSet] mutableCopy];
	[noNewlinesCharacterSet removeCharactersInString:@"\n\r"];
	[textField_title setFormatter:[AIStringFormatter stringFormatterAllowingCharacters:noNewlinesCharacterSet
																				length:0 /* No length limit */
																		 caseSensitive:NO
																		  errorMessage:nil]];
	[noNewlinesCharacterSet release];

	[self layoutWindowContents];

	/* Built in code, so the key loop is worked out from where the controls actually are rather than
	 * from a chain saved in a nib. The message is what one comes here to write - it keeps the focus
	 * the nib used to give it, and -configureForState: selects the text already in it. */
	[[self window] setAutorecalculatesKeyViewLoop:YES];
	[[self window] setInitialFirstResponder:textView_statusMessage];

	[super windowDidLoad];
}

/*!
 * @brief Build the body of the window
 *
 * A settings form, the same one the rest of the converted interface is made of. It is a plain
 * NSView with no notion of a preference pane, so a window may host it just as well - and the cards
 * count on the window background being what it is, which is why nothing here sets a background of
 * its own.
 */
- (void)buildForm
{
	form = [[AISettingsFormView alloc] initWithWidth:WINDOW_CONTENT_WIDTH];
	[form autorelease];

	//Card 1: what this status is called and which state it is
	textField_title = [AISettingsFormView textFieldWithTarget:nil action:NULL];
	[textField_title setDelegate:(id<NSTextFieldDelegate>)self];
	[form addRowWithLabel:AILocalizedString(@"Title","Label of the field holding the name of a status")
		stretchingControl:textField_title];

	/* Says out loud what -controlTextDidEndEditing: does and what nothing else on screen would
	 * betray: an empty field is not a status without a name, it is a status named after itself. */
	[form addDetailRow:AILocalizedString(@"Clear the field to let Adium name this status after its message.","Explanation under the title field of the status editor")];

	popUp_state = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];
	[popUp_state setFont:[NSFont menuFontOfSize:0.0]];
	[form addRowWithLabel:AILocalizedString(@"Status","Label of the menu holding the kind of status - available, away and so on")
			  popUpButton:popUp_state
		  accessoryButton:nil];

	//Card 2: the message contacts are shown. The section header is its label, so it carries none
	[form addSectionHeader:AILocalizedString(@"Status Message",nil)];
	[scrollView_statusMessage setFrameSize:NSMakeSize(NSWidth([scrollView_statusMessage frame]),
													  STATUS_MESSAGE_HEIGHT)];
	[form addFullWidthRow:scrollView_statusMessage];

	/* Card 3: the two silences. They differ in more than their wording, and the two explanations
	 * are the whole point of the card: muting sounds is a property of the accounts wearing this
	 * status and covers alert sounds as well as spoken messages, while silencing notifications is
	 * global and only holds back Notification Center, and only while this status is the active
	 * one. Both belong to the status rather than to being idle: whoever picks "Do not disturb" by
	 * hand is not idle at all, and a silence tied to idleness would not apply to them. */
	[form addSectionHeader:AILocalizedString(@"Quiet","Section title above the mute switches of the status editor")];

	switch_muteSounds = [AISettingsFormView switchWithTarget:self action:@selector(statusControlChanged:)];
	[form addRowWithLabel:AILocalizedString(@"Mute Sounds",nil)
				  control:switch_muteSounds
				   detail:AILocalizedString(@"No sounds and no spoken messages for this account's contacts.","Explanation of the mute sounds switch of the status editor")];

	switch_silenceNotifications = [AISettingsFormView switchWithTarget:self action:@selector(statusControlChanged:)];
	[form addRowWithLabel:AILocalizedString(@"Silence Notifications",nil)
				  control:switch_silenceNotifications
				   detail:AILocalizedString(@"No notifications in Notification Center while this status is active.","Explanation of the silence notifications switch of the status editor")];

	/* Card 4: only where the caller offered it. It decides between an editable and a temporary
	 * status, and with that whether a status written from the status menu joins the saved list. */
	if (showSaveCheckbox) {
		[form endCard];

		switch_save = [AISettingsFormView switchWithTarget:self action:@selector(statusControlChanged:)];
		[form addRowWithLabel:AILocalizedString(@"Save Custom Status",nil)
					  control:switch_save];
		[form addFootnote:AILocalizedString(@"Saved statuses appear in the status menu.","Footnote under the save switch of the status editor")];
	}

	[[[self window] contentView] addSubview:form];

	//The buttons live outside the form, in the window's own bottom bar
	button_cancel = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Cancel", nil)
													 target:self
													 action:@selector(cancel:)];
	button_okay = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"OK", nil)
												   target:self
												   action:@selector(okay:)];

	[button_cancel setKeyEquivalent:@"\033"];
	[button_okay setKeyEquivalent:@"\r"];

	for (NSButton *button in [NSArray arrayWithObjects:button_cancel, button_okay, nil]) {
		if (NSWidth([button frame]) < BUTTON_MINIMUM_WIDTH) {
			[button setFrameSize:NSMakeSize(BUTTON_MINIMUM_WIDTH, NSHeight([button frame]))];
		}

		[[[self window] contentView] addSubview:button];
	}
}

/*!
 * @brief Lay the form and the button bar out, and make the window as tall as they are
 *
 * The window is not resizable, so this is the only place its height is decided. Called again
 * whenever something changed the height of the form - the state menu being rebuilt, above all.
 */
- (void)layoutWindowContents
{
	NSWindow	*window = [self window];

	[form layoutForWidth:WINDOW_CONTENT_WIDTH];

	CGFloat		buttonHeight = NSHeight([button_okay frame]);
	CGFloat		formHeight = [form totalHeight];
	CGFloat		contentHeight = ceil(WINDOW_MARGIN + formHeight + BUTTON_BAR_GAP +
									 buttonHeight + WINDOW_MARGIN);

	[window setContentSize:NSMakeSize(WINDOW_CONTENT_WIDTH, contentHeight)];

	//The content view is not flipped: the button bar sits at the bottom, the form above it
	[button_okay setFrameOrigin:NSMakePoint(WINDOW_CONTENT_WIDTH - WINDOW_MARGIN - NSWidth([button_okay frame]),
											WINDOW_MARGIN)];
	[button_cancel setFrameOrigin:NSMakePoint(NSMinX([button_okay frame]) - [AISettingsFormView standardControlGap] - NSWidth([button_cancel frame]),
											  WINDOW_MARGIN)];

	[form setFrame:NSMakeRect(0.0, contentHeight - WINDOW_MARGIN - formHeight,
							  WINDOW_CONTENT_WIDTH, formHeight)];

	[self synchronizeStatusMessageTextViewSize];
}

/*!
 * @brief Let the message text view fill the space the card gives its scroll view
 *
 * An NSTextView is never shorter than its minSize, and it is the text view rather than the scroll
 * view which draws the white behind the message. The nib cannot know how wide the card will be, so
 * the size is taken from the clip view once the form has laid itself out - otherwise an empty
 * message would show a scroller, or a strip of the wrong colour under the first line.
 */
- (void)synchronizeStatusMessageTextViewSize
{
	NSSize	visibleSize = [[scrollView_statusMessage contentView] bounds].size;

	if ((visibleSize.width < 1.0) || (visibleSize.height < 1.0)) return;

	[textView_statusMessage setMinSize:NSMakeSize(0.0, visibleSize.height)];
	[textView_statusMessage setMaxSize:NSMakeSize(visibleSize.width, CGFLOAT_MAX)];

	if (NSHeight([textView_statusMessage frame]) < visibleSize.height) {
		[textView_statusMessage setFrameSize:NSMakeSize(NSWidth([textView_statusMessage frame]),
														visibleSize.height)];
	}
}

/*!
 * @brief Configure for our account and working status state
 *
 * This means updating the state menu to be appropriate for our account's service as well as setting up
 * the rest of the fields.
 */
- (void)configureForAccountAndWorkingStatusState
{
	[self configureStateMenu];

	//Configure our editor for the working state
	[self configureForState:workingStatusState];
}

/*!
 * @brief Configure the state menu with a fresh menu of active statuses
 *
 * The layout is not optional. A pop up row is measured afresh at every layout instead of being
 * pinned to the width it once had, so a button whose menu has just been exchanged keeps the width
 * the old menu earned it until something lays the form out again - and this editor is reused for
 * one account after another (see +editCustomState:…), so the menu it is given the second time may
 * be a different service's, with longer titles than the first one had room for. -layoutWindowContents
 * rather than -noteContentSizeChanged: the window is not resizable and its height is decided
 * nowhere else. Before -buildForm has run there is no form to lay out; -windowDidLoad lays out once
 * more of its own accord afterwards.
 */
- (void)configureStateMenu
{
	[popUp_state setMenu:[adium.statusController menuOfStatusesForService:(account ? account.service : nil)
																 withTarget:self]];
	needToRebuildPopUpState = NO;

	if (form) [self layoutWindowContents];
}

//Closing --------------------------------------------------------------------------------------------------------------
#pragma mark Closing

/*!
 * @brief Called before the window is closed
 */
- (void)windowWillClose:(id)sender
{
	[super windowWillClose:sender];

	[self finishEditing];
}

/*!
 * @brief Stop tracking this editor and give up the reference which keeps it alive
 *
 * Reached from the sheet's completion handler and from -windowWillClose:, and for one and the same
 * editor both of them may run; releasing twice would be a crash, hence didFinish.
 */
- (void)finishEditing
{
	if (didFinish) return;
	didFinish = YES;

	NSNumber	*targetHash = [NSNumber numberWithUnsignedInteger:[target hash]];

	//Survive the dictionary letting go of us before we get to our own autorelease
	[[self retain] autorelease];

	if ([controllerDict objectForKey:targetHash] == self) {
		[controllerDict removeObjectForKey:targetHash];
	}

	[self autorelease];
}

/*!
 * @brief Close the window, or end it if it is a sheet
 *
 * AIWindowController's version reaches for the long deprecated -[NSApp endSheet:], which knows
 * nothing of the completion handler this editor is dismissed through.
 */
- (IBAction)closeWindow:(id)sender
{
	if (![self windowShouldClose:nil]) return;

	NSWindow	*window = [self window];
	NSWindow	*parentWindow = [window sheetParent];

	if (parentWindow) {
		[parentWindow endSheet:window];
	} else {
		[window close];
	}
}

//Behavior -------------------------------------------------------------------------------------------------------------
#pragma mark Behavior
/*!
 * @brief Okay
 *
 * Save changes, notify our target of the new configuration, and close the editor.
 */
- (IBAction)okay:(id)sender
{
	if (target && [target respondsToSelector:@selector(customStatusState:changedTo:forAccount:)]) {
		//Perform on a delay so the sheet can begin closing immediately.
		[self performSelector:@selector(notifyOfStateChange)
				   withObject:nil
				   afterDelay:0];
	}

	[self closeWindow:nil];
}

/*!
 * @brief Notify our target of the state changing
 *
 * Called by -[self okay:]
 */
- (void)notifyOfStateChange
{
	[target customStatusState:originalStatusState changedTo:[self currentConfiguration] forAccount:account];
}

/*!
 * @brief Cancel
 *
 * Close the editor without saving changes.
 */
- (IBAction)cancel:(id)sender
{
	[self closeWindow:nil];
}

- (void)textViewDidCancel:(NSTextView *)inTextView
{
	[self cancel:inTextView];
}

/*!
 * @brief Update the display of the status's title in the window
 */
- (void)updateTitleDisplay
{
	[textField_title setStringValue:[workingStatusState title]];
}

/*!
 * @brief Invoked when a control value is changed
 *
 * Every switch writes into the working status the moment it is touched; only the title and the
 * mutability are gathered up at OK.
 */
- (IBAction)statusControlChanged:(id)sender
{
	if (sender == switch_muteSounds)
		[workingStatusState setMutesSound:([switch_muteSounds state] == NSControlStateValueOn)];
	else if (sender == switch_silenceNotifications)
		[workingStatusState setSilencesNotifications:([switch_silenceNotifications state] == NSControlStateValueOn)];

	[self updateTitleDisplay];
}

/*!
 * @brief NSTextField changed
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	id sender = [notification object];

	if (sender == textField_title) {
		NSString	*newTitle = [textField_title stringValue];

		if ([newTitle length]) [workingStatusState setTitle:newTitle];
	}
}

/*!
 * @brief NSTextView changed
 */
- (void)textDidChange:(NSNotification *)notification
{
	id sender = [notification object];

	if (sender == textView_statusMessage) {
		[workingStatusState setStatusMessage:[[[textView_statusMessage textStorage] copy] autorelease]];
	}

	[self updateTitleDisplay];
}

/*!
 * @brief NSTextField ended editing
 *
 * If our title is cleared out, restore it to using the default title for the rest of the configuration
 */
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	id sender = [notification object];

	if (sender == textField_title) {
		NSString	*newTitle = [textField_title stringValue];

		//Set to nil if the field is cleared to get back to the automatically generated value
		if (![newTitle length]) {
			[workingStatusState setTitle:nil];

			[self updateTitleDisplay];
		}
	}
}

/*!
 * @brief Invoked when a new status type is selected
 */
- (IBAction)selectStatus:(id)sender
{
	NSDictionary	*stateDict = [[popUp_state selectedItem] representedObject];
	if (stateDict) {
		[workingStatusState setStatusType:[[stateDict objectForKey:KEY_STATUS_TYPE] intValue]];
		[workingStatusState setStatusName:[stateDict objectForKey:KEY_STATUS_NAME]];
	}

	[self updateTitleDisplay];
}

//Configuration --------------------------------------------------------------------------------------------------------
#pragma mark Configuration
/*!
 * @brief Configure the editor for a state
 *
 * Configured the editor's controls to represent the passed state dictionary.
 * @param statusState A NSDictionary containing status state keys and values
 */
- (void)configureForState:(AIStatus *)statusState
{
	//State menu
	NSString	*description;
	NSUInteger			idx;
	BOOL				stateMenuTitleChanged = NO;

	if (needToRebuildPopUpState) {
		[self configureStateMenu];
	}

	description = [adium.statusController descriptionForStateOfStatus:statusState];
	idx = (description ? [popUp_state indexOfItemWithTitle:description] : -1);
	if (idx != -1) {
		[popUp_state selectItemAtIndex:idx];

	} else {
		if (description) {
			[popUp_state setTitle:[NSString stringWithFormat:@"%@ (%@)",
				description,
				AILocalizedString(@"No compatible accounts connected", nil)]];

		} else {
			[popUp_state setTitle:AILocalizedString(@"Unknown", nil)];
		}

		/* A title set by hand is longer than any menu entry, and a pop up row is measured afresh at
		 * every layout - so the form has to be told that a layout is due. */
		stateMenuTitleChanged = YES;
		needToRebuildPopUpState = YES;
	}

	//Toggles
	[switch_muteSounds setState:([statusState mutesSound] ? NSControlStateValueOn : NSControlStateValueOff)];
	[switch_silenceNotifications setState:([statusState silencesNotifications] ? NSControlStateValueOn : NSControlStateValueOff)];

	//Strings
	NSAttributedString	*statusMessage = statusState.statusMessage;

	if (!statusMessage) statusMessage = [NSAttributedString stringWithString:@""];
	[[textView_statusMessage textStorage] setAttributedString:statusMessage];
	[textView_statusMessage setSelectedRange:NSMakeRange(0, [statusMessage length])];

	//Set Background Colors. Asking an empty string for the attributes at index 0 is out of bounds
	if([statusMessage length] &&
	   [statusMessage attribute:AIBodyColorAttributeName atIndex:0 effectiveRange:nil]) {
			[textView_statusMessage setBackgroundColor:[statusMessage attribute:AIBodyColorAttributeName atIndex:0 effectiveRange:nil]];
	}

	//Disallow an undo to before this point
	[[textView_statusMessage undoManager] removeAllActions];

	if (stateMenuTitleChanged && form) [self layoutWindowContents];

	//Update our title
	[self updateTitleDisplay];
}

/*!
 * @brief Returns the current state
 *
 * Builds and returns a state dictionary representation of the current editor values.  If no controls have been
 * modified since the editor was configured, the returned state will be identical in content to the one passed
 * to configureForState:.
 */
- (AIStatus *)currentConfiguration
{
	[workingStatusState setMutabilityType:((!showSaveCheckbox || ([switch_save state] == NSControlStateValueOn)) ?
										   AIEditableStatusState :
										   AITemporaryEditableStatusState)];

	//Set the title if necessary
	if (textField_title &&
		![[workingStatusState title] isEqualToString:[textField_title stringValue]]) {
		[workingStatusState setTitle:[textField_title stringValue]];
	}

	//Do not allow the creation of a Now Playing status
	if ([workingStatusState specialStatusType] == AINowPlayingSpecialStatusType) {
		[workingStatusState setSpecialStatusType:AINoSpecialStatusType];
	}

	return workingStatusState;
}

@end

