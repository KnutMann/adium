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

#import <Adium/AIChat.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <AIUtilities/AIStringUtilities.h>

#import "AIMessageViewController.h"

/* Long enough that typing a formula does not start a render per keystroke, short enough that the
 * picture appears to follow the typing rather than lag behind it. A render takes about twenty
 * milliseconds, so this is the whole of the delay the user perceives. */
#define PREVIEW_DELAY				0.25

#define EDITOR_MARGIN				8.0f
#define PREVIEW_MINIMUM_HEIGHT		56.0f
#define HISTORY_STRIP_HEIGHT		48.0f
#define THUMBNAIL_POINT_SIZE		11.0
#define THUMBNAIL_MAXIMUM_WIDTH		200.0f
#define SEND_SYMBOL_POINT_SIZE		20.0

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
- (void)openDocumentation:(id)sender;
- (void)recallFormula:(id)sender;
- (void)forgetFormula:(id)sender;
- (void)historyDidChange:(NSNotification *)notification;
- (void)reloadHistory;
- (void)renderNextThumbnail;
- (NSButton *)linkButtonWithTitle:(NSString *)title url:(NSString *)url;
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
 * Layout inside here is Auto Layout, which is safe because this subtree is self contained and its
 * own root keeps its autoresizing mask: the chat window around it positions views by writing frames
 * and would fight constraints reaching outside.
 */
- (void)buildInterface
{
	imageView_preview = [[NSImageView alloc] initWithFrame:NSZeroRect];
	[imageView_preview setImageScaling:NSImageScaleProportionallyDown];
	[imageView_preview setImageAlignment:NSImageAlignCenter];
	[imageView_preview setTranslatesAutoresizingMaskIntoConstraints:NO];

	textField_error = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[textField_error setEditable:NO];
	[textField_error setBordered:NO];
	[textField_error setDrawsBackground:NO];
	[textField_error setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[textField_error setTextColor:[NSColor systemRedColor]];
	[textField_error setLineBreakMode:NSLineBreakByWordWrapping];
	[[textField_error cell] setWraps:YES];
	[textField_error setHidden:YES];
	[textField_error setTranslatesAutoresizingMaskIntoConstraints:NO];

	scrollView_history = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	[scrollView_history setHasHorizontalScroller:YES];
	[scrollView_history setHasVerticalScroller:NO];
	[scrollView_history setBorderType:NSNoBorder];
	[scrollView_history setDrawsBackground:NO];
	[scrollView_history setTranslatesAutoresizingMaskIntoConstraints:NO];

	NSStackView *stack_history = [[NSStackView alloc] initWithFrame:NSZeroRect];
	[stack_history setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[stack_history setSpacing:6.0f];
	[stack_history setTranslatesAutoresizingMaskIntoConstraints:NO];
	[scrollView_history setDocumentView:stack_history];
	view_historyStrip = stack_history;

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

	NSStackView *stack_links = [[NSStackView alloc] initWithFrame:NSZeroRect];
	[stack_links setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[stack_links setSpacing:12.0f];
	[stack_links setTranslatesAutoresizingMaskIntoConstraints:NO];
	[stack_links addView:[self linkButtonWithTitle:AILocalizedString(@"Math reference", "Link to the Typst documentation, from the formula editor")
											   url:@"https://typst.app/docs/reference/math/"]
			   inGravity:NSStackViewGravityLeading];
	[stack_links addView:[self linkButtonWithTitle:AILocalizedString(@"Symbols", "Link to Typst's list of symbols, from the formula editor")
											   url:@"https://typst.app/docs/reference/symbols/sym/"]
			   inGravity:NSStackViewGravityLeading];
	[stack_links addView:[self linkButtonWithTitle:AILocalizedString(@"Coming from LaTeX", "Link to Typst's guide for LaTeX users, from the formula editor")
											   url:@"https://typst.app/docs/guides/for-latex-users/"]
			   inGravity:NSStackViewGravityLeading];

	[self addSubview:imageView_preview];
	[self addSubview:textField_error];
	[self addSubview:scrollView_history];
	[self addSubview:stack_links];
	[self addSubview:button_send];

	NSDictionary *views = NSDictionaryOfVariableBindings(imageView_preview,
														textField_error, scrollView_history,
														stack_links, button_send);
	NSDictionary *metrics = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithFloat:EDITOR_MARGIN], @"margin",
							 [NSNumber numberWithFloat:PREVIEW_MINIMUM_HEIGHT], @"previewMin",
							 [NSNumber numberWithFloat:HISTORY_STRIP_HEIGHT], @"stripHeight",
							 nil];

	NSMutableArray *constraints = [NSMutableArray array];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[imageView_preview]-margin-|"
											 options:0 metrics:metrics views:views]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[scrollView_history]-margin-|"
											 options:0 metrics:metrics views:views]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[stack_links]-(>=margin)-[button_send]-margin-|"
											 options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:
	  @"V:|-margin-[imageView_preview(>=previewMin)]-margin-[scrollView_history(stripHeight)]-margin-[button_send]-margin-|"
											 options:0 metrics:metrics views:views]];

	/* The complaint occupies the same space as the picture rather than a row of its own. There is
	 * never both, and a row that is empty most of the time would take height from the two things that
	 * need it and make the panel jump every time a formula was briefly incomplete. */
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[textField_error]-margin-|"
											 options:0 metrics:metrics views:views]];
	[constraints addObject:[NSLayoutConstraint constraintWithItem:textField_error
													   attribute:NSLayoutAttributeCenterY
													   relatedBy:NSLayoutRelationEqual
														  toItem:imageView_preview
													   attribute:NSLayoutAttributeCenterY
													  multiplier:1.0f
														constant:0.0f]];

	/* The strip's content decides its own width; it is the clip view's height it has to match. */
	[constraints addObject:[NSLayoutConstraint constraintWithItem:view_historyStrip
													   attribute:NSLayoutAttributeHeight
													   relatedBy:NSLayoutRelationEqual
														  toItem:[scrollView_history contentView]
													   attribute:NSLayoutAttributeHeight
													  multiplier:1.0f
														constant:0.0f]];

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

- (NSButton *)linkButtonWithTitle:(NSString *)title url:(NSString *)url
{
	NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];

	NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
								[NSColor linkColor], NSForegroundColorAttributeName,
								[NSNumber numberWithInteger:NSUnderlineStyleSingle], NSUnderlineStyleAttributeName,
								[NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
								nil];

	[button setAttributedTitle:[[NSAttributedString alloc] initWithString:title attributes:attributes]];
	[button setBordered:NO];
	[button setTarget:self];
	[button setAction:@selector(openDocumentation:)];
	[button setToolTip:url];
	[button setTranslatesAutoresizingMaskIntoConstraints:NO];

	return button;
}

- (void)openDocumentation:(id)sender
{
	NSURL *url = [NSURL URLWithString:[sender toolTip]];

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

- (void)reloadHistory
{
	for (NSView *view in [[[view_historyStrip subviews] copy] reverseObjectEnumerator])
		[(NSStackView *)view_historyStrip removeView:view];

	pendingThumbnails = [[NSMutableArray alloc] init];

	for (NSString *formula in [AITypstHistory formulas]) {
		NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
		[button setBordered:NO];
		[button setTarget:self];
		[button setAction:@selector(recallFormula:)];
		[button setToolTip:formula];
		[button setTranslatesAutoresizingMaskIntoConstraints:NO];

		NSImage *thumbnail = [thumbnailCache objectForKey:formula];
		if (thumbnail) {
			[button setImage:thumbnail];
			[button setImagePosition:NSImageOnly];
		} else {
			/* Until the picture arrives the source is shown, which is also what happens permanently
			 * for a formula that no longer renders. */
			[button setTitle:formula];
			[button setFont:[NSFont monospacedSystemFontOfSize:10.0 weight:NSFontWeightRegular]];
			[pendingThumbnails addObject:formula];
		}

		NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
		NSMenuItem *forget = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Remove from History", "Context menu item on a formula in the formula editor's history strip")
														action:@selector(forgetFormula:)
												 keyEquivalent:@""];
		[forget setTarget:self];
		[forget setRepresentedObject:formula];
		[menu addItem:forget];
		[button setMenu:menu];

		[(NSStackView *)view_historyStrip addView:button inGravity:NSStackViewGravityLeading];
	}

	[self renderNextThumbnail];
}

/*!
 * @brief Render the thumbnails one after another
 *
 * One at a time on purpose. Each render is a separate process, and starting forty of them because
 * the history happens to be full would be a burst of work for a strip most of which is scrolled out
 * of sight.
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

				for (NSView *view in [self->view_historyStrip subviews]) {
					if ([view isKindOfClass:[NSButton class]] &&
						[[(NSButton *)view toolTip] isEqualToString:formula]) {
						[(NSButton *)view setImage:image];
						[(NSButton *)view setImagePosition:NSImageOnly];
					}
				}
			}
		}

		[self renderNextThumbnail];
	}];
}

- (void)recallFormula:(id)sender
{
	NSString *formula = [sender toolTip];
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

@end
