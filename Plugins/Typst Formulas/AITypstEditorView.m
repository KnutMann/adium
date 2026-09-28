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

#import "AITypstEditorView.h"
#import "AITypstRenderer.h"
#import "AITypstHistory.h"
#import "AITypstPlugin.h"

#import <Adium/AIChat.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <AIUtilities/AIStringUtilities.h>

#import "AIMessageViewController.h"

/* Long enough that typing a formula does not start a render per keystroke, short enough that the
 * picture appears to follow the typing rather than lag behind it. A render takes about twenty
 * milliseconds, so this is the whole of the delay the user perceives. */
#define PREVIEW_DELAY				0.25

#define EDITOR_MARGIN				8.0f
#define BAR_PADDING					6.0f
#define PREVIEW_MINIMUM_HEIGHT		72.0f
#define THUMBNAIL_POINT_SIZE		11.0
#define THUMBNAIL_MAXIMUM_WIDTH		200.0f
#define SEND_SYMBOL_POINT_SIZE		20.0
#define HELP_SYMBOL_POINT_SIZE		18.0

@interface AITypstEditorView ()
- (void)buildInterface;
- (NSImage *)sendButtonImage;
- (void)entryDidChange:(NSNotification *)notification;
- (void)schedulePreview;
- (AIMessageEntryTextView *)entryTextView;
- (NSRange)formulaRange;
- (NSString *)currentFormula;
- (void)renderPreview;
- (void)showError:(NSString *)message;
- (void)takeOverSending;
- (void)handSendingBack;
- (void)sendFormula:(id)sender;
- (void)sendEnteredMessage:(id)sender;
- (BOOL)insertRenderedFormula;
- (void)showHelpMenu:(id)sender;
- (void)openDocumentation:(id)sender;
- (void)recallFormula:(id)sender;
- (void)forgetFormula:(id)sender;
- (void)clearHistory:(id)sender;
- (void)historyDidChange:(NSNotification *)notification;
- (void)reloadHistory;
- (void)renderNextThumbnail;
@end


@implementation AITypstEditorView

/*!
 * @brief Thumbnails already rendered, shared by every editor
 *
 * Kept for the lifetime of the process rather than written anywhere. A thumbnail is cheap to make
 * and worthless once the render template changes, so a cache that dies with the application is
 * exactly the right lifetime.
 */
static NSMutableDictionary *thumbnailCache = nil;

+ (void)initialize
{
	if (self == [AITypstEditorView class])
		thumbnailCache = [[NSMutableDictionary alloc] init];
}

- (id)initWithChat:(AIChat *)inChat
{
	if ((self = [super initWithFrame:NSMakeRect(0.0f, 0.0f, 480.0f, 260.0f)])) {
		chat = inChat;

		[self buildInterface];
		[self reloadHistory];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(historyDidChange:)
													 name:AITypstHistoryDidChangeNotification
												   object:nil];

		/* The formula is written in the chat's own message entry, so that is what the preview
		 * follows. Both notifications matter: typing changes what the formula is, and moving the
		 * selection changes which part of the field counts as the formula. */
		NSTextView *entry = [self entryTextView];
		if (entry) {
			[[NSNotificationCenter defaultCenter] addObserver:self
													 selector:@selector(entryDidChange:)
														 name:NSTextDidChangeNotification
													   object:entry];
			[[NSNotificationCenter defaultCenter] addObserver:self
													 selector:@selector(entryDidChange:)
														 name:NSTextViewDidChangeSelectionNotification
													   object:entry];
			[self takeOverSending];
			[self schedulePreview];
		}
	}

	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	[self handSendingBack];

	[activeRender cancel];
	[thumbnailRender cancel];

	//A preview nobody used is just a file in the temporary folder
	if (renderedPath && !renderedPathWasInserted)
		[AITypstRenderer discardRenderAtPath:renderedPath];
}

- (void)takeFocus
{
	NSTextView *entry = [self entryTextView];

	[[entry window] makeFirstResponder:entry];
}

/*!
 * @brief The chat's own message entry, which is where a formula is written
 *
 * Resolved on each use rather than kept: the chain to it runs through the chat's container, which is
 * nil before the tab exists and nil again once the chat closes, and a stale pointer through there is
 * a crash rather than a blank panel.
 */
- (AIMessageEntryTextView *)entryTextView
{
	return chat.chatContainer.messageViewController.textEntryView;
}

/*!
 * @brief What is being written, and where it sits
 *
 * The selection if there is one, the whole field otherwise. One rule, used both for what the preview
 * shows and for what the insert replaces, because two rules here would mean a picture landing
 * somewhere other than where the user was looking.
 */
- (NSRange)formulaRange
{
	NSTextView *entry = [self entryTextView];
	if (!entry) return NSMakeRange(NSNotFound, 0);

	NSRange selected = [entry selectedRange];

	return (selected.length ? selected : NSMakeRange(0, [[entry string] length]));
}

- (NSString *)currentFormula
{
	NSTextView *entry = [self entryTextView];
	NSRange range = [self formulaRange];
	if (!entry || range.location == NSNotFound || NSMaxRange(range) > [[entry string] length])
		return nil;

	return [[[entry string] substringWithRange:range] stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

//Interface ------------------------------------------------------------------------------------------------------------
#pragma mark Interface

/*!
 * @brief Build the whole thing in code
 *
 * The picture above, a bar below: the formulas used before and the help on the left, the button
 * that sends on the right. Layout inside here is Auto Layout, which is safe because this subtree
 * is self contained and its own root keeps its autoresizing mask: the chat window around it
 * positions views by writing frames and would fight constraints reaching outside.
 *
 * Nothing here takes its size from its content. The picture is scaled into the space it is
 * given, and asks for none; the menu is as wide as its title. A formula that grows by a line
 * must not move the bar, and a menu must not widen as its pictures come in.
 */
- (void)buildInterface
{
	imageView_preview = [[NSImageView alloc] initWithFrame:NSZeroRect];
	[imageView_preview setImageScaling:NSImageScaleProportionallyDown];
	[imageView_preview setImageAlignment:NSImageAlignCenter];
	[imageView_preview setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
												forOrientation:NSLayoutConstraintOrientationHorizontal];
	[imageView_preview setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
												forOrientation:NSLayoutConstraintOrientationVertical];
	[imageView_preview setContentHuggingPriority:NSLayoutPriorityDefaultLow
								  forOrientation:NSLayoutConstraintOrientationHorizontal];
	[imageView_preview setContentHuggingPriority:NSLayoutPriorityDefaultLow
								  forOrientation:NSLayoutConstraintOrientationVertical];
	[imageView_preview setTranslatesAutoresizingMaskIntoConstraints:NO];

	/* Until there is a formula the space says what it is for, so that an empty panel is never taken
	 * for a picture that failed to appear. */
	textField_placeholder = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[textField_placeholder setEditable:NO];
	[textField_placeholder setBordered:NO];
	[textField_placeholder setDrawsBackground:NO];
	[textField_placeholder setAlignment:NSTextAlignmentCenter];
	[textField_placeholder setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[textField_placeholder setTextColor:[NSColor secondaryLabelColor]];
	[textField_placeholder setStringValue:AILocalizedString(@"Type a formula in the message field", "Shown in the formula editor's empty preview")];
	[textField_placeholder setTranslatesAutoresizingMaskIntoConstraints:NO];

	textField_error = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[textField_error setEditable:NO];
	[textField_error setBordered:NO];
	[textField_error setDrawsBackground:NO];
	[textField_error setAlignment:NSTextAlignmentCenter];
	[textField_error setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[textField_error setTextColor:[NSColor systemRedColor]];
	[textField_error setLineBreakMode:NSLineBreakByWordWrapping];
	[[textField_error cell] setWraps:YES];
	[textField_error setHidden:YES];
	[textField_error setTranslatesAutoresizingMaskIntoConstraints:NO];

	/* The formulas used before, as a menu of their pictures. A menu rather than a strip: it holds
	 * forty without scrolling, it costs no height, and a picture in a menu is recognised as quickly
	 * as one in a row. The first item of a pull down is its title. */
	popUp_history = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
	[popUp_history setControlSize:NSControlSizeSmall];
	[popUp_history setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[popUp_history addItemWithTitle:AILocalizedString(@"Recently Used", "Title of the menu of formulas used before, in the formula editor")];
	[popUp_history setTranslatesAutoresizingMaskIntoConstraints:NO];
	/* Measured now, with the title as its only item, and held there. A pop up button otherwise
	 * takes its width from the widest of its items, and the items here are pictures that arrive
	 * one after another, which would have the button growing as they came. */
	[popUp_history sizeToFit];
	CGFloat menuWidth = AIceil(NSWidth([popUp_history frame]));

	/* A question mark from the system's symbols rather than the help bezel: the bezel comes in
	 * three sizes and draws its mark large in all of them, and beside a menu in small type the
	 * mark has to be as light as that type. The filled circle at the bezel's size, the mark cut
	 * out of it at the symbol's own proportion, the circle in the lighter of the two shades. */
	button_help = [[NSButton alloc] initWithFrame:NSZeroRect];
	NSImageSymbolConfiguration *helpLook = [[NSImageSymbolConfiguration configurationWithPointSize:HELP_SYMBOL_POINT_SIZE
																				 weight:NSFontWeightRegular]
											 configurationByApplyingConfiguration:
											 [NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor secondaryLabelColor]]];
	[button_help setImage:[[NSImage imageWithSystemSymbolName:@"questionmark.circle.fill"
								accessibilityDescription:AILocalizedString(@"Help", nil)]
						   imageWithSymbolConfiguration:helpLook]];
	[button_help setImagePosition:NSImageOnly];
	[button_help setBordered:NO];
	[button_help setTitle:@""];
	[button_help setToolTip:AILocalizedString(@"Help", nil)];
	[button_help setTarget:self];
	[button_help setAction:@selector(showHelpMenu:)];
	[button_help setTranslatesAutoresizingMaskIntoConstraints:NO];

	button_send = [[NSButton alloc] initWithFrame:NSZeroRect];
	[button_send setImage:[self sendButtonImage]];
	[button_send setImagePosition:NSImageOnly];
	[button_send setBordered:NO];
	[button_send setContentTintColor:[NSColor systemBlueColor]];
	[button_send setToolTip:AILocalizedString(@"Send", "Button in the formula editor which sends the rendered formula")];
	[button_send setTarget:self];
	[button_send setAction:@selector(sendFormula:)];
	/* No key equivalent of its own. Command and return already arrives at the message field, whose
	 * send this editor has taken over, so claiming the same key here would put two views in the window
	 * in a race for one event. */
	[button_send setEnabled:NO];
	[button_send setTranslatesAutoresizingMaskIntoConstraints:NO];

	NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
	[separator setBoxType:NSBoxSeparator];
	[separator setTranslatesAutoresizingMaskIntoConstraints:NO];

	[self addSubview:imageView_preview];
	[self addSubview:textField_placeholder];
	[self addSubview:textField_error];
	[self addSubview:separator];
	[self addSubview:popUp_history];
	[self addSubview:button_help];
	[self addSubview:button_send];

	NSDictionary *views = NSDictionaryOfVariableBindings(imageView_preview, textField_placeholder,
														textField_error, separator,
														popUp_history, button_help, button_send);
	NSDictionary *metrics = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithFloat:EDITOR_MARGIN], @"margin",
							 [NSNumber numberWithFloat:BAR_PADDING], @"barPadding",
							 [NSNumber numberWithFloat:PREVIEW_MINIMUM_HEIGHT], @"previewMin",
							 [NSNumber numberWithFloat:menuWidth], @"menuWidth",
							 nil];

	NSMutableArray *constraints = [NSMutableArray array];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[imageView_preview]-margin-|"
											 options:0 metrics:metrics views:views]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[separator]|"
											 options:0 metrics:metrics views:views]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[popUp_history(menuWidth)]-barPadding-[button_help]-(>=margin)-[button_send]-margin-|"
											 options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
	/* The picture's space is the minimum, or more if the person drags the shelf taller; it is never
	 * the picture that decides, since a taller formula is scaled to fit rather than given room. */
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:
	  @"V:|-margin-[imageView_preview(>=previewMin)]-margin-[separator]-barPadding-[popUp_history]-barPadding-|"
											 options:0 metrics:metrics views:views]];

	/* The placeholder and the complaint occupy the picture's space rather than a row of their own.
	 * There is never more than one of the three, and a row that is empty most of the time would take
	 * height from the picture and make the panel jump every time a formula was briefly incomplete. */
	for (NSView *label in [NSArray arrayWithObjects:textField_placeholder, textField_error, nil]) {
		for (NSNumber *attribute in [NSArray arrayWithObjects:
									 [NSNumber numberWithInteger:NSLayoutAttributeLeading],
									 [NSNumber numberWithInteger:NSLayoutAttributeTrailing],
									 [NSNumber numberWithInteger:NSLayoutAttributeCenterY], nil]) {
			[constraints addObject:[NSLayoutConstraint constraintWithItem:label
															   attribute:[attribute integerValue]
															   relatedBy:NSLayoutRelationEqual
																  toItem:imageView_preview
															   attribute:[attribute integerValue]
															  multiplier:1.0f
																constant:0.0f]];
		}
	}

	[NSLayoutConstraint activateConstraints:constraints];
}

/*!
 * @brief The arrow in the blue circle
 *
 * The same picture the rest of the system puts on a send button, taken from the system's own symbols
 * rather than drawn or bundled here, so that it keeps in step with whatever the system does to it.
 * The circle is filled and the arrow is cut out of it, which is why the button is tinted rather than
 * coloured: the arrow takes the colour of whatever is behind the button.
 */
- (NSImage *)sendButtonImage
{
	NSImage *image = [NSImage imageWithSystemSymbolName:@"arrow.up.circle.fill"
							   accessibilityDescription:AILocalizedString(@"Send", "Button in the formula editor which sends the rendered formula")];

	return [image imageWithSymbolConfiguration:
			[NSImageSymbolConfiguration configurationWithPointSize:SEND_SYMBOL_POINT_SIZE
														   weight:NSFontWeightRegular]];
}

/*!
 * @brief The help: Typst's own documentation, opened from a menu under the question mark
 *
 * Built each time it is asked for. Three items are not worth keeping, and a menu that exists only
 * while it is open has nothing to keep in step.
 */
- (void)showHelpMenu:(id)sender
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
	NSArray *links = [NSArray arrayWithObjects:
					  [NSArray arrayWithObjects:AILocalizedString(@"Math reference", "Link to the Typst documentation, from the formula editor"),
					   @"https://typst.app/docs/reference/math/", nil],
					  [NSArray arrayWithObjects:AILocalizedString(@"Symbols", "Link to Typst's list of symbols, from the formula editor"),
					   @"https://typst.app/docs/reference/symbols/sym/", nil],
					  [NSArray arrayWithObjects:AILocalizedString(@"Coming from LaTeX", "Link to Typst's guide for LaTeX users, from the formula editor"),
					   @"https://typst.app/docs/guides/for-latex-users/", nil],
					  nil];

	for (NSArray *link in links) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[link objectAtIndex:0]
													  action:@selector(openDocumentation:)
											   keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:[link objectAtIndex:1]];
		[item setToolTip:[link objectAtIndex:1]];
		[menu addItem:item];
	}

	//Above the button: the bar is at the bottom of the window, and a menu has more room upwards
	[menu popUpMenuPositioningItem:nil
						atLocation:NSMakePoint(0.0f, NSHeight([button_help bounds]) + 4.0f)
							inView:button_help];
}

- (void)openDocumentation:(id)sender
{
	NSURL *url = [NSURL URLWithString:[sender representedObject]];

	if (url)
		[[NSWorkspace sharedWorkspace] openURL:url];
}

//Preview --------------------------------------------------------------------------------------------------------------
#pragma mark Preview

- (void)entryDidChange:(NSNotification *)notification
{
	[self schedulePreview];
}

- (void)schedulePreview
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(renderPreview) object:nil];
	[self performSelector:@selector(renderPreview) withObject:nil afterDelay:PREVIEW_DELAY];
}

- (void)renderPreview
{
	NSString *formula = [self currentFormula];

	if (![formula length]) {
		[imageView_preview setImage:nil];
		[textField_error setHidden:YES];
		[textField_placeholder setHidden:NO];
		[button_send setEnabled:NO];
		return;
	}

	if (![AITypstRenderer typstIsAvailable]) {
		[self showError:AILocalizedString(@"Typst is not installed. Install it with \"brew install typst\".", nil)];
		return;
	}

	/* Every render carries the number it was started with, and only the newest one is allowed to
	 * change anything. Without that, a slow render of a half typed formula can land after a fast
	 * render of the finished one and put the wrong picture on screen. */
	renderGeneration++;
	NSUInteger thisGeneration = renderGeneration;

	[activeRender cancel];

	activeRender = [AITypstRenderer renderFormula:formula
										pointSize:0.0
									   completion:^(NSString *path, NSString *errorMessage) {
		if (thisGeneration != self->renderGeneration) return;

		if (path) {
			NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
			NSImageRep *rep = [[image representations] lastObject];
			if (rep) {
				[image setSize:[AITypstRenderer naturalSizeForPixelSize:NSMakeSize((CGFloat)[rep pixelsWide],
																				   (CGFloat)[rep pixelsHigh])]];
			}

			[self->imageView_preview setImage:image];
			[self->textField_error setHidden:YES];
			[self->textField_placeholder setHidden:(image != nil)];
			[self->button_send setEnabled:(image != nil)];

			/* The picture this one replaces is not needed any more, unless it went into a message: an
			 * attachment refers to its file by name, and that file has to still be there when the
			 * message is sent. Without this, typing a formula would leave one directory in the
			 * temporary folder per pause in the typing. */
			if (self->renderedPath && !self->renderedPathWasInserted)
				[AITypstRenderer discardRenderAtPath:self->renderedPath];

			self->renderedPath = path;
			self->renderedFormula = formula;
			self->renderedPathWasInserted = NO;
		} else {
			[self showError:errorMessage];
		}
	}];
}

- (void)showError:(NSString *)message
{
	[imageView_preview setImage:nil];
	[textField_placeholder setHidden:YES];
	[textField_error setStringValue:(message ? message : @"")];
	[textField_error setHidden:NO];
	[button_send setEnabled:NO];
}

//Sending --------------------------------------------------------------------------------------------------------------
#pragma mark Sending

/*!
 * @brief Take the message field's sending over for as long as this editor is open
 *
 * Two things change. The send keys stop sending, because the field is where the formula is written
 * and a formula runs to several lines often enough that the return key is needed for the text. And
 * the send itself comes here first, so that however the user asks for it, by the button below or by
 * command and return in the field, what goes out is the picture and not the source it was made from.
 *
 * What was there before is read rather than assumed. The field belongs to the conversation and not to
 * this editor: it was set up before the shelf opened and has to be handed back as it was found.
 */
- (void)takeOverSending
{
	AIMessageEntryTextView *entry = [self entryTextView];
	if (!entry) return;

	previousSendTarget = [entry sendTarget];
	previousSendAction = [entry sendAction];
	previousSendOnReturn = [entry sendOnReturn];
	previousSendOnEnter = [entry sendOnEnter];

	[entry setTarget:self action:@selector(sendEnteredMessage:)];
	[entry setSendOnReturn:NO];
	[entry setSendOnEnter:NO];

	sendingWasTakenOver = YES;
}

- (void)handSendingBack
{
	AIMessageEntryTextView *entry = [self entryTextView];

	/* Nothing to hand back if nothing was taken. The field is reached through the conversation's
	 * window, so an editor built before that window exists finds none, and writing the remembered
	 * nothing into a field that turned up later would leave it unable to send at all. */
	if (!entry || !sendingWasTakenOver) return;

	/* Only if it is still ours to hand back. Nothing else takes the send over today, but putting a
	 * remembered target back over a newer one would be the kind of fault that shows up much later. */
	if ([entry sendTarget] == self)
		[entry setTarget:previousSendTarget action:previousSendAction];

	[entry setSendOnReturn:previousSendOnReturn];
	[entry setSendOnEnter:previousSendOnEnter];
}

/*!
 * @brief The send button was pressed
 *
 * Through the field's own send rather than straight into sendEnteredMessage:, so that a formula sent
 * from here goes the same way a typed message does, into the message history and past whatever else
 * the field does on its way out. availableForSending is what a send key asks, so a conversation that
 * is refusing messages refuses this one too.
 */
- (void)sendFormula:(id)sender
{
	AIMessageEntryTextView *entry = [self entryTextView];

	if (entry && [entry availableForSending])
		[entry sendContent:nil];
}

/*!
 * @brief A message is being sent from the conversation this editor belongs to
 *
 * Installed as the message field's send action while the editor is open, so this runs whichever way
 * the send was asked for.
 *
 * The picture takes the place of its source in the field and the send then carries on to where it was
 * going before, which is the ordinary path with its filters, its offline handling and its file
 * transfers. Handing the picture to the account from here would be a shorter route and would miss all
 * of it, which is why the insert stayed even though nothing is called insert any more.
 */
- (void)sendEnteredMessage:(id)sender
{
	/* Sending closes the editor and closing it is what releases it, so the receiver has to be kept
	 * alive for the rest of this method. */
	CFAutorelease(CFBridgingRetain(self));

	[self insertRenderedFormula];

	if (previousSendTarget && previousSendAction)
		/* The original send action returns void; nothing to leak. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[previousSendTarget performSelector:previousSendAction withObject:sender];
#pragma clang diagnostic pop

	/* Closed once the message is gone rather than left standing: people do not talk in formulas alone,
	 * and the next thing typed into that field is far more likely to be a sentence. */
	[chat.chatContainer.messageViewController setShelfView:nil];
}

/*!
 * @brief Put the rendered formula into the message being written
 *
 * @result YES if the field now holds the picture
 */
- (BOOL)insertRenderedFormula
{
	if (!renderedPath || !renderedFormula) return NO;

	NSAttributedString *attachment = [AITypstRenderer attachmentStringForImageAtPath:renderedPath
																			formula:renderedFormula];
	if (!attachment) return NO;

	NSTextView *entry = [self entryTextView];
	NSRange range = [self formulaRange];
	if (!entry || range.location == NSNotFound || NSMaxRange(range) > [[entry string] length])
		return NO;

	/* Replacing rather than appending: the source is in the field, and it is the thing the picture is
	 * a rendering of. Leaving it behind would send the formula twice, once as text and once as an
	 * image. The range is the same one the preview was made from, so what disappears is what the user
	 * has been watching. */
	if (![entry shouldChangeTextInRange:range replacementString:nil])
		return NO;

	[[entry textStorage] replaceCharactersInRange:range withAttributedString:attachment];
	[entry didChangeText];
	[entry setSelectedRange:NSMakeRange(range.location + [attachment length], 0)];

	renderedPathWasInserted = YES;

	[AITypstHistory rememberFormula:renderedFormula];

	return YES;
}

//History --------------------------------------------------------------------------------------------------------------
#pragma mark History

- (void)historyDidChange:(NSNotification *)notification
{
	[self reloadHistory];
}

/*!
 * @brief Fill the menu with the formulas used before, most recent first
 *
 * Each formula is one item showing its picture, or its source until the picture has been rendered,
 * which is also what a formula that no longer renders shows for good. Held with option, the same
 * entry offers to forget the formula instead. The last item empties the list.
 */
- (void)reloadHistory
{
	NSMenu *menu = [popUp_history menu];
	NSString *forgetTitle = AILocalizedString(@"Remove from History", "Menu item, shown with the option key held, which drops one formula from the formula editor's history");

	//The first item is the title of the pull down; everything after it is ours to replace
	while ([menu numberOfItems] > 1)
		[menu removeItemAtIndex:1];

	pendingThumbnails = [[NSMutableArray alloc] init];

	NSArray *formulas = [AITypstHistory formulas];
	for (NSString *formula in formulas) {
		NSImage *thumbnail = [thumbnailCache objectForKey:formula];

		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(recallFormula:) keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:formula];
		[item setToolTip:formula];
		[item setKeyEquivalentModifierMask:0];
		if (thumbnail) {
			[item setImage:thumbnail];
		} else {
			[item setAttributedTitle:[[NSAttributedString alloc] initWithString:formula attributes:
									  [NSDictionary dictionaryWithObject:[NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular]
																  forKey:NSFontAttributeName]]];
			[pendingThumbnails addObject:formula];
		}
		[menu addItem:item];

		NSMenuItem *forget = [[NSMenuItem alloc] initWithTitle:forgetTitle action:@selector(forgetFormula:) keyEquivalent:@""];
		[forget setTarget:self];
		[forget setRepresentedObject:formula];
		[forget setImage:thumbnail];
		[forget setAlternate:YES];
		[forget setKeyEquivalentModifierMask:NSEventModifierFlagOption];
		[menu addItem:forget];
	}

	if ([formulas count]) {
		[menu addItem:[NSMenuItem separatorItem]];

		NSMenuItem *clear = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Clear History", "Menu item which empties the formula editor's list of formulas used before")
													   action:@selector(clearHistory:)
												keyEquivalent:@""];
		[clear setTarget:self];
		[menu addItem:clear];
	}

	[popUp_history setEnabled:([formulas count] > 0)];

	[self renderNextThumbnail];
}

/*!
 * @brief Render the thumbnails one after another
 *
 * One at a time on purpose. Each render is a separate process, and starting forty of them because
 * the history happens to be full would be a burst of work for a menu that may never be opened.
 */
- (void)renderNextThumbnail
{
	if (![pendingThumbnails count]) return;
	if (![AITypstRenderer typstIsAvailable]) return;

	NSString *formula = [pendingThumbnails objectAtIndex:0];
	[pendingThumbnails removeObjectAtIndex:0];

	/* This can run inside the previous renderer's own completion handler. Replacing the ivar under
	 * it is safe: whatever invoked the handler keeps that renderer alive until the handler returns. */
	thumbnailRender = [AITypstRenderer renderFormula:formula
										   pointSize:THUMBNAIL_POINT_SIZE
										  completion:^(NSString *path, NSString *errorMessage) {
		if (path) {
			NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
			NSImageRep *rep = [[image representations] lastObject];
			if (image && rep) {
				[image setSize:[AITypstRenderer naturalSizeForPixelSize:NSMakeSize((CGFloat)[rep pixelsWide],
																				   (CGFloat)[rep pixelsHigh])]];
				[thumbnailCache setObject:image forKey:formula];

				//The picture is in memory now, so the file has done its job
				[AITypstRenderer discardRenderAtPath:path];

				for (NSMenuItem *item in [[self->popUp_history menu] itemArray]) {
					if ([[item representedObject] isEqualToString:formula]) {
						[item setImage:image];
						if (![item isAlternate]) {
							[item setAttributedTitle:nil];
							[item setTitle:@""];
						}
					}
				}
			}
		}

		[self renderNextThumbnail];
	}];
}

- (void)recallFormula:(id)sender
{
	NSString *formula = [sender representedObject];
	if (!formula) return;

	NSTextView *entry = [self entryTextView];
	if (!entry) return;

	NSRange range = [self formulaRange];
	if (range.location != NSNotFound && [entry shouldChangeTextInRange:range replacementString:formula]) {
		[[entry textStorage] replaceCharactersInRange:range withAttributedString:
		 [[NSAttributedString alloc] initWithString:formula attributes:[entry typingAttributes]]];
		[entry didChangeText];
		[entry setSelectedRange:NSMakeRange(range.location, [formula length])];
	}

	[self renderPreview];
	[[entry window] makeFirstResponder:entry];
}

- (void)forgetFormula:(id)sender
{
	[AITypstHistory forgetFormula:[sender representedObject]];
}

- (void)clearHistory:(id)sender
{
	[AITypstHistory forgetAllFormulas];
}

//The button in the message field that opened this editor; it stays usable, to close it again
- (NSString *)messageEntryAccessoryIdentifier
{
	return FORMULA_ITEM_IDENTIFIER;
}

@end
