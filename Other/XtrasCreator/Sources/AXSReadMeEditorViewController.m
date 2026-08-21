/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSReadMeEditorViewController.h"

#define READ_ME_HEIGHT 420.0

@interface AXSReadMeEditorViewController () <NSTextViewDelegate>
@end

@implementation AXSReadMeEditorViewController {
	NSTextView *textView;
}

- (NSString *)tabTitle
{
	return @"Read Me";
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;

	[form addSectionHeader:@"Read Me"];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 640, READ_ME_HEIGHT)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDrawsBackground:NO];

	textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 640, READ_ME_HEIGHT)];
	[textView setRichText:YES];
	[textView setEditable:YES];
	[textView setAllowsUndo:YES];
	[textView setVerticallyResizable:YES];
	[textView setAutoresizingMask:NSViewWidthSizable];
	[[textView textContainer] setWidthTracksTextView:YES];
	[textView setTextContainerInset:NSMakeSize(8.0, 8.0)];
	[textView setDelegate:self];
	[scroll setDocumentView:textView];

	[form addEdgeToEdgeRow:scroll];
	[form addFootnote:@"Shown in Adium's Xtras manager. Leave empty for Adium's standard text."];
}

- (void)reloadFromModel
{
	NSAttributedString *readMe = self.document.model.readMe;

	if (readMe)
		[[textView textStorage] setAttributedString:readMe];
	else
		[textView setString:@""];
}

- (void)textDidChange:(NSNotification *)notification
{
	self.document.model.readMe = [[textView textStorage] copy];
	[self.document noteEdited];
}

@end
