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
#define SOURCE_MINIMUM_HEIGHT		44.0f
#define PREVIEW_MINIMUM_HEIGHT		56.0f
#define HISTORY_STRIP_HEIGHT		48.0f
#define THUMBNAIL_POINT_SIZE		11.0
#define THUMBNAIL_MAXIMUM_WIDTH		200.0f

@interface AITypstEditorView ()
- (void)buildInterface;
- (void)schedulePreview;
- (void)renderPreview;
- (void)showError:(NSString *)message;
- (void)insertFormula:(id)sender;
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
		chat = [inChat retain];

		[self buildInterface];
		[self reloadHistory];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(historyDidChange:)
													 name:AITypstHistoryDidChangeNotification
												   object:nil];
	}

	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	[activeRender cancel];
	[activeRender release];
	[thumbnailRender cancel];
	[thumbnailRender release];

	//A preview nobody used is just a file in the temporary folder
	if (renderedPath && !renderedPathWasInserted)
		[AITypstRenderer discardRenderAtPath:renderedPath];

	[pendingThumbnails release];
	[renderedPath release];
	[renderedFormula release];
	[chat release];

	[super dealloc];
}

- (void)takeFocus
{
	[[self window] makeFirstResponder:textView_source];
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
	NSScrollView *scrollView_source = [[[NSScrollView alloc] initWithFrame:NSZeroRect] autorelease];
	[scrollView_source setHasVerticalScroller:YES];
	[scrollView_source setBorderType:NSBezelBorder];
	[scrollView_source setTranslatesAutoresizingMaskIntoConstraints:NO];

	textView_source = [[[NSTextView alloc] initWithFrame:NSZeroRect] autorelease];
	[textView_source setFont:[NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular]];
	[textView_source setAutomaticQuoteSubstitutionEnabled:NO];
	[textView_source setAutomaticDashSubstitutionEnabled:NO];
	[textView_source setAutomaticTextReplacementEnabled:NO];
	[textView_source setAutomaticSpellingCorrectionEnabled:NO];
	[textView_source setContinuousSpellCheckingEnabled:NO];
	[textView_source setAllowsUndo:YES];
	[textView_source setDelegate:self];
	[scrollView_source setDocumentView:textView_source];

	imageView_preview = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
	[imageView_preview setImageScaling:NSImageScaleProportionallyDown];
	[imageView_preview setImageAlignment:NSImageAlignCenter];
	[imageView_preview setTranslatesAutoresizingMaskIntoConstraints:NO];

	textField_error = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
	[textField_error setEditable:NO];
	[textField_error setBordered:NO];
	[textField_error setDrawsBackground:NO];
	[textField_error setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[textField_error setTextColor:[NSColor systemRedColor]];
	[textField_error setLineBreakMode:NSLineBreakByWordWrapping];
	[[textField_error cell] setWraps:YES];
	[textField_error setHidden:YES];
	[textField_error setTranslatesAutoresizingMaskIntoConstraints:NO];

	scrollView_history = [[[NSScrollView alloc] initWithFrame:NSZeroRect] autorelease];
	[scrollView_history setHasHorizontalScroller:YES];
	[scrollView_history setHasVerticalScroller:NO];
	[scrollView_history setBorderType:NSNoBorder];
	[scrollView_history setDrawsBackground:NO];
	[scrollView_history setTranslatesAutoresizingMaskIntoConstraints:NO];

	NSStackView *stack_history = [[[NSStackView alloc] initWithFrame:NSZeroRect] autorelease];
	[stack_history setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
	[stack_history setSpacing:6.0f];
	[stack_history setTranslatesAutoresizingMaskIntoConstraints:NO];
	[scrollView_history setDocumentView:stack_history];
	view_historyStrip = stack_history;

	button_insert = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
	[button_insert setTitle:AILocalizedString(@"Insert", "Button in the formula editor which puts the rendered formula into the message being written")];
	[button_insert setBezelStyle:NSBezelStyleRounded];
	[button_insert setTarget:self];
	[button_insert setAction:@selector(insertFormula:)];
	/* Command and return rather than return alone: a formula may well run to several lines, and the
	 * source field needs the plain return key for that. */
	[button_insert setKeyEquivalent:@"\r"];
	[button_insert setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
	[button_insert setEnabled:NO];
	[button_insert setTranslatesAutoresizingMaskIntoConstraints:NO];

	NSStackView *stack_links = [[[NSStackView alloc] initWithFrame:NSZeroRect] autorelease];
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

	[self addSubview:scrollView_source];
	[self addSubview:imageView_preview];
	[self addSubview:textField_error];
	[self addSubview:scrollView_history];
	[self addSubview:stack_links];
	[self addSubview:button_insert];

	NSDictionary *views = NSDictionaryOfVariableBindings(scrollView_source, imageView_preview,
														textField_error, scrollView_history,
														stack_links, button_insert);
	NSDictionary *metrics = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithFloat:EDITOR_MARGIN], @"margin",
							 [NSNumber numberWithFloat:SOURCE_MINIMUM_HEIGHT], @"sourceMin",
							 [NSNumber numberWithFloat:PREVIEW_MINIMUM_HEIGHT], @"previewMin",
							 [NSNumber numberWithFloat:HISTORY_STRIP_HEIGHT], @"stripHeight",
							 nil];

	NSMutableArray *constraints = [NSMutableArray array];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[scrollView_source]-margin-|"
											 options:0 metrics:metrics views:views]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[imageView_preview]-margin-|"
											 options:0 metrics:metrics views:views]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[scrollView_history]-margin-|"
											 options:0 metrics:metrics views:views]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[stack_links]-(>=margin)-[button_insert]-margin-|"
											 options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:
	  @"V:|-margin-[scrollView_source(>=sourceMin)]-margin-[imageView_preview(>=previewMin)]-margin-[scrollView_history(stripHeight)]-margin-[button_insert]-margin-|"
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

	/* The picture gets rather more of the height than the source does. A formula is short to type and
	 * worth looking at closely, and this is the ratio that keeps both usable when the shelf is
	 * dragged smaller. */
	[constraints addObject:[NSLayoutConstraint constraintWithItem:imageView_preview
													   attribute:NSLayoutAttributeHeight
													   relatedBy:NSLayoutRelationEqual
														  toItem:scrollView_source
													   attribute:NSLayoutAttributeHeight
													  multiplier:1.4f
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

- (NSButton *)linkButtonWithTitle:(NSString *)title url:(NSString *)url
{
	NSButton *button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];

	NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
								[NSColor linkColor], NSForegroundColorAttributeName,
								[NSNumber numberWithInteger:NSUnderlineStyleSingle], NSUnderlineStyleAttributeName,
								[NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
								nil];

	[button setAttributedTitle:[[[NSAttributedString alloc] initWithString:title attributes:attributes] autorelease]];
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

- (void)textDidChange:(NSNotification *)notification
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
	NSString *formula = [[textView_source string] stringByTrimmingCharactersInSet:
						 [NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if (![formula length]) {
		[imageView_preview setImage:nil];
		[textField_error setHidden:YES];
		[button_insert setEnabled:NO];
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
	[activeRender autorelease];

	activeRender = [[AITypstRenderer renderFormula:formula
										 pointSize:0.0
										completion:^(NSString *path, NSString *errorMessage) {
		if (thisGeneration != renderGeneration) return;

		if (path) {
			NSImage *image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
			NSImageRep *rep = [[image representations] lastObject];
			if (rep) {
				[image setSize:[AITypstRenderer naturalSizeForPixelSize:NSMakeSize((CGFloat)[rep pixelsWide],
																				   (CGFloat)[rep pixelsHigh])]];
			}

			[imageView_preview setImage:image];
			[textField_error setHidden:YES];
			[button_insert setEnabled:(image != nil)];

			/* The picture this one replaces is not needed any more, unless it went into a message: an
			 * attachment refers to its file by name, and that file has to still be there when the
			 * message is sent. Without this, typing a formula would leave one directory in the
			 * temporary folder per pause in the typing. */
			if (renderedPath && !renderedPathWasInserted)
				[AITypstRenderer discardRenderAtPath:renderedPath];

			[renderedPath release];	   renderedPath = [path retain];
			[renderedFormula release]; renderedFormula = [formula retain];
			renderedPathWasInserted = NO;
		} else {
			[self showError:errorMessage];
		}
	}] retain];
}

- (void)showError:(NSString *)message
{
	[imageView_preview setImage:nil];
	[textField_error setStringValue:(message ? message : @"")];
	[textField_error setHidden:NO];
	[button_insert setEnabled:NO];
}

//Insertion ------------------------------------------------------------------------------------------------------------
#pragma mark Insertion

/*!
 * @brief Put the rendered formula into the message being written
 *
 * Into the entry field rather than straight out to the contact, so that a sentence can be written
 * around it and so that the ordinary send path, with its filters and its file transfer handling,
 * is the one that carries it.
 */
- (void)insertFormula:(id)sender
{
	if (!renderedPath || !renderedFormula) return;

	NSAttributedString *attachment = [AITypstRenderer attachmentStringForImageAtPath:renderedPath
																			formula:renderedFormula];
	if (!attachment) return;

	AIMessageViewController *messageViewController = chat.chatContainer.messageViewController;
	if (!messageViewController) return;

	[messageViewController addToTextEntryView:attachment];
	renderedPathWasInserted = YES;

	[AITypstHistory rememberFormula:renderedFormula];
	[messageViewController makeTextEntryViewFirstResponder];
}

//History --------------------------------------------------------------------------------------------------------------
#pragma mark History

- (void)historyDidChange:(NSNotification *)notification
{
	[self reloadHistory];
}

- (void)reloadHistory
{
	for (NSView *view in [[[[view_historyStrip subviews] copy] autorelease] reverseObjectEnumerator])
		[(NSStackView *)view_historyStrip removeView:view];

	[pendingThumbnails release];
	pendingThumbnails = [[NSMutableArray alloc] init];

	for (NSString *formula in [AITypstHistory formulas]) {
		NSButton *button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
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

		NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
		NSMenuItem *forget = [[[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Remove from History", "Context menu item on a formula in the formula editor's history strip")
														 action:@selector(forgetFormula:)
												  keyEquivalent:@""] autorelease];
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

	NSString *formula = [[[pendingThumbnails objectAtIndex:0] retain] autorelease];
	[pendingThumbnails removeObjectAtIndex:0];

	/* Autorelease rather than release: the call that lands here comes from the previous thumbnail's
	 * own completion handler, so this is the object whose block is running. */
	[thumbnailRender autorelease];
	thumbnailRender = [[AITypstRenderer renderFormula:formula
											pointSize:THUMBNAIL_POINT_SIZE
										   completion:^(NSString *path, NSString *errorMessage) {
		if (path) {
			NSImage *image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
			NSImageRep *rep = [[image representations] lastObject];
			if (image && rep) {
				[image setSize:[AITypstRenderer naturalSizeForPixelSize:NSMakeSize((CGFloat)[rep pixelsWide],
																				   (CGFloat)[rep pixelsHigh])]];
				[thumbnailCache setObject:image forKey:formula];

				//The picture is in memory now, so the file has done its job
				[AITypstRenderer discardRenderAtPath:path];

				for (NSView *view in [view_historyStrip subviews]) {
					if ([view isKindOfClass:[NSButton class]] &&
						[[(NSButton *)view toolTip] isEqualToString:formula]) {
						[(NSButton *)view setImage:image];
						[(NSButton *)view setImagePosition:NSImageOnly];
					}
				}
			}
		}

		[self renderNextThumbnail];
	}] retain];
}

- (void)recallFormula:(id)sender
{
	NSString *formula = [sender toolTip];
	if (!formula) return;

	[textView_source setString:formula];
	[self renderPreview];
	[[self window] makeFirstResponder:textView_source];
}

- (void)forgetFormula:(id)sender
{
	[AITypstHistory forgetFormula:[sender representedObject]];
}

@end
