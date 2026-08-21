/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSResourcesEditorViewController.h"

#define FILE_TABLE_HEIGHT 380.0

@interface AXSResourcesEditorViewController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation AXSResourcesEditorViewController {
	NSTableView *table;
	NSScrollView *tableScroll;
	NSArray<NSString *> *fileNames;
	NSButton *removeButton;
}

- (NSString *)tabTitle
{
	return @"Resources";
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;

	[form addSectionHeader:@"Resources"];

	table = [[NSTableView alloc] initWithFrame:NSZeroRect];
	[table setAllowsMultipleSelection:YES];
	[table setUsesAlternatingRowBackgroundColors:YES];

	NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	[nameColumn setTitle:@"File"];
	[nameColumn setWidth:420.0];
	[table addTableColumn:nameColumn];

	NSTableColumn *sizeColumn = [[NSTableColumn alloc] initWithIdentifier:@"dimensions"];
	[sizeColumn setTitle:@"Size"];
	[sizeColumn setWidth:110.0];
	[table addTableColumn:sizeColumn];

	[table setDataSource:self];
	[table setDelegate:self];

	tableScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 640, FILE_TABLE_HEIGHT)];
	[tableScroll setHasVerticalScroller:YES];
	[tableScroll setDocumentView:table];

	[form addEdgeToEdgeRow:tableScroll];

	NSButton *addButton = [AISettingsFormView pushButtonWithTitle:@"Add…" target:self action:@selector(addFiles:)];
	removeButton = [AISettingsFormView pushButtonWithTitle:@"Remove" target:self action:@selector(removeSelectedFiles:)];
	[removeButton setEnabled:NO];
	[form addAccessoryView:[AISettingsFormView rowOfViews:@[addButton, removeButton]]];

	[form addFootnote:@"Everything inside the pack's resources, including files added by other tools. "
					  @"Images the pack's entries point at are managed on the pack's own page."];
}

- (void)reloadFromModel
{
	[self reloadFileList];
}

- (void)reloadFileList
{
	fileNames = [[[self.document.resourcesWrapper fileWrappers] allKeys]
				 sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
	[table reloadData];
	[removeButton setEnabled:([table selectedRow] >= 0)];
}

#pragma mark Actions

- (IBAction)addFiles:(id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setAllowsMultipleSelection:YES];
	[panel setCanChooseDirectories:NO];

	[panel beginSheetModalForWindow:[[self view] window] completionHandler:^(NSModalResponse response) {
		if (response != NSModalResponseOK) return;

		NSFileWrapper *resources = self.document.resourcesWrapper;

		for (NSURL *url in [panel URLs]) {
			NSData *data = [NSData dataWithContentsOfURL:url];
			if (!data) continue;

			NSString *name = [url lastPathComponent];
			NSFileWrapper *existing = [resources fileWrappers][name];
			if (existing) [resources removeFileWrapper:existing];

			[resources addRegularFileWithContents:data preferredFilename:name];
		}

		[self.document noteEdited];
		[self reloadFileList];
	}];
}

- (IBAction)removeSelectedFiles:(id)sender
{
	NSFileWrapper *resources = self.document.resourcesWrapper;
	NSIndexSet *selection = [table selectedRowIndexes];

	[selection enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		NSFileWrapper *wrapper = [resources fileWrappers][fileNames[idx]];
		if (wrapper) [resources removeFileWrapper:wrapper];
	}];

	[self.document noteEdited];
	[self reloadFileList];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[fileNames count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *identifier = [tableColumn identifier];
	NSTextField *field = [tableView makeViewWithIdentifier:identifier owner:self];

	if (!field) {
		field = [NSTextField labelWithString:@""];
		[field setIdentifier:identifier];
		[field setLineBreakMode:NSLineBreakByTruncatingMiddle];
	}

	NSString *name = fileNames[(NSUInteger)row];

	if ([identifier isEqualToString:@"name"]) {
		[field setStringValue:name];
		[field setAlignment:NSTextAlignmentNatural];
	} else {
		[field setStringValue:[self dimensionsStringForFile:name]];
		[field setAlignment:NSTextAlignmentRight];
		[field setTextColor:[NSColor secondaryLabelColor]];
	}

	return field;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[removeButton setEnabled:([table selectedRow] >= 0)];
}

/*!
 * @brief True pixel dimensions of an image file, or nothing for the rest
 */
- (NSString *)dimensionsStringForFile:(NSString *)name
{
	NSFileWrapper *wrapper = [self.document.resourcesWrapper fileWrappers][name];
	if (!wrapper.regularFile) return @"";

	NSImage *image = [[NSImage alloc] initWithData:[wrapper regularFileContents]];
	if (!image) return @"";

	NSInteger pixelsWide = 0, pixelsHigh = 0;
	for (NSImageRep *rep in [image representations]) {
		if ([rep pixelsWide] > pixelsWide) {
			pixelsWide = [rep pixelsWide];
			pixelsHigh = [rep pixelsHigh];
		}
	}

	if (pixelsWide <= 0) return @"";

	return [NSString stringWithFormat:@"%ld × %ld px", (long)pixelsWide, (long)pixelsHigh];
}

@end
