/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSJavaScriptPluginEditorViewController.h"
#import "AXSJavaScriptPluginCodec.h"

#define SOURCE_HEIGHT 420.0

@interface AXSJavaScriptPluginEditorViewController () <NSTextViewDelegate, NSTextFieldDelegate>
@end

@implementation AXSJavaScriptPluginEditorViewController {
	NSTextField *fileNameField;
	NSTextView *sourceView;
}

- (NSString *)tabTitle
{
	return @"Script";
}

- (NSMutableDictionary *)payload
{
	return self.document.model.payload;
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;
	[form setSharesLabelColumn:YES];

	[form addSectionHeader:@"Script File"];
	fileNameField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedFileName:)];
	[form addRowWithLabel:@"File name" stretchingControl:fileNameField];
	[form addFootnote:@"A plain file name, stored in the plugin's Resources."];

	[form addSectionHeader:@"Script"];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 660, SOURCE_HEIGHT)];
	[scroll setHasVerticalScroller:YES];
	[scroll setHasHorizontalScroller:YES];
	[scroll setDrawsBackground:NO];

	sourceView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 660, SOURCE_HEIGHT)];
	[sourceView setRichText:NO];
	[sourceView setEditable:YES];
	[sourceView setAllowsUndo:YES];
	[sourceView setAutomaticQuoteSubstitutionEnabled:NO];
	[sourceView setAutomaticDashSubstitutionEnabled:NO];
	[sourceView setFont:[NSFont userFixedPitchFontOfSize:12.0]];
	[sourceView setVerticallyResizable:YES];
	[sourceView setHorizontallyResizable:YES];
	[[sourceView textContainer] setWidthTracksTextView:NO];
	[[sourceView textContainer] setContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
	[sourceView setTextContainerInset:NSMakeSize(8.0, 8.0)];
	[sourceView setDelegate:self];
	[scroll setDocumentView:sourceView];

	[form addEdgeToEdgeRow:scroll];

	NSButton *scaffold = [AISettingsFormView pushButtonWithTitle:@"Insert Scaffold" target:self action:@selector(insertScaffold:)];
	[form addAccessoryView:[AISettingsFormView rowOfViews:@[scaffold]]];
	[form addFootnote:@"The plugin is handed each message body as it appears and changes its display. "
					  @"It runs walled off: no network, no files. Build nodes with createElement and "
					  @"textContent, never innerHTML."];
}

- (void)reloadFromModel
{
	[fileNameField setStringValue:[[self payload][@"fileName"] description] ?: @"plugin.js"];
	[sourceView setString:[[self payload][@"source"] description] ?: @""];
}

#pragma mark Actions

- (IBAction)changedFileName:(id)sender
{
	NSString *name = [[fileNameField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (![name length]) name = @"plugin.js";
	[self payload][@"fileName"] = name;
	[self.document noteEdited];
}

- (IBAction)insertScaffold:(id)sender
{
	if ([[sourceView string] length]) {
		NSBeep();	//Only into an empty editor, so nothing is clobbered
		return;
	}
	[sourceView setString:[AXSJavaScriptPluginCodec scaffoldSource]];
	[self payload][@"source"] = [AXSJavaScriptPluginCodec scaffoldSource];
	[self.document noteEdited];
}

- (void)textDidChange:(NSNotification *)notification
{
	[self payload][@"source"] = [[sourceView string] copy];
	[self.document noteEdited];
}

@end
