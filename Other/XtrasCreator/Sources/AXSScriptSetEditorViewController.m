/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSScriptSetEditorViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define SCRIPT_TABLE_HEIGHT 340.0

@interface AXSScriptSetEditorViewController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@end

@implementation AXSScriptSetEditorViewController {
	NSTextField *setNameField;
	NSTableView *table;
	NSButton *removeButton;
}

- (NSString *)tabTitle
{
	return @"Scripts";
}

- (NSMutableArray *)scripts
{
	NSMutableDictionary *payload = self.document.model.payload;
	NSMutableArray *scripts = payload[@"Scripts"];
	if (![scripts isKindOfClass:[NSMutableArray class]]) {
		scripts = [NSMutableArray array];
		payload[@"Scripts"] = scripts;
	}
	return scripts;
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;
	[form setSharesLabelColumn:YES];

	[form addSectionHeader:@"Script Set"];

	setNameField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedSetName:)];
	[form addRowWithLabel:@"Menu group" stretchingControl:setNameField];
	[form addFootnote:@"The heading the scripts appear under in Adium's Insert Script menu."];

	[form addSectionHeader:@"Scripts"];

	table = [[NSTableView alloc] initWithFrame:NSZeroRect];
	[table setRowHeight:22.0];
	[table setUsesAlternatingRowBackgroundColors:YES];

	struct { NSString *identifier; NSString *title; CGFloat width; } columns[] = {
		{ @"Keyword", @"Keyword", 120.0 },
		{ @"Title", @"Title", 180.0 },
		{ @"File", @"Script File", 150.0 },
		{ @"Arguments", @"Arguments", 130.0 },
		{ @"Prefix Only", @"Prefix", 50.0 },
	};
	for (unsigned i = 0; i < sizeof(columns) / sizeof(*columns); i++) {
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:columns[i].identifier];
		[column setTitle:columns[i].title];
		[column setWidth:columns[i].width];
		[table addTableColumn:column];
	}

	[table setDataSource:self];
	[table setDelegate:self];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 660, SCRIPT_TABLE_HEIGHT)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDocumentView:table];
	[form addEdgeToEdgeRow:scroll];

	NSButton *add = [AISettingsFormView pushButtonWithTitle:@"Add Script…" target:self action:@selector(addScript:)];
	removeButton = [AISettingsFormView pushButtonWithTitle:@"Remove" target:self action:@selector(removeSelected:)];
	[removeButton setEnabled:NO];
	[form addAccessoryView:[AISettingsFormView rowOfViews:@[add, removeButton]]];

	[form addFootnote:@"A script is a compiled .scpt from Script Editor with an on substitute() "
					  @"handler; typing its keyword in a chat replaces it with the handler's "
					  @"answer. Arguments are comma separated; a prefix-only keyword fires just "
					  @"at the start of a message."];
}

- (void)reloadFromModel
{
	[setNameField setStringValue:[self.document.model.payload[@"Set"] description] ?: @""];
	[table reloadData];
	[removeButton setEnabled:([table selectedRow] >= 0)];
}

#pragma mark Actions

- (IBAction)changedSetName:(id)sender
{
	self.document.model.payload[@"Set"] = [setNameField stringValue];
	[self.document noteEdited];
}

- (IBAction)addScript:(id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setAllowsMultipleSelection:YES];
	if (@available(macOS 11.0, *)) {
		[panel setAllowedContentTypes:@[[UTType typeWithIdentifier:@"com.apple.applescript.script"]]];
	}

	[panel beginSheetModalForWindow:[[self view] window] completionHandler:^(NSModalResponse response) {
		if (response != NSModalResponseOK) return;

		NSFileWrapper *resources = self.document.resourcesWrapper;

		for (NSURL *url in [panel URLs]) {
			NSData *data = [NSData dataWithContentsOfURL:url];
			if (!data) continue;

			NSString *fileName = [url lastPathComponent];
			NSFileWrapper *existing = [resources fileWrappers][fileName];
			if (existing) [resources removeFileWrapper:existing];
			[resources addRegularFileWithContents:data preferredFilename:fileName];

			NSString *base = [fileName stringByDeletingPathExtension];
			[[self scripts] addObject:[NSMutableDictionary dictionaryWithDictionary:@{
				@"File": base,
				@"Keyword": [NSString stringWithFormat:@"/%@", [base lowercaseString]],
				@"Title": base,
				@"Arguments": @"",
				@"Prefix Only": @YES,
			}]];
		}

		[self.document noteEdited];
		[self reloadFromModel];
	}];
}

- (IBAction)removeSelected:(id)sender
{
	NSInteger row = [table selectedRow];
	if (row < 0 || row >= (NSInteger)[[self scripts] count]) {
		NSBeep();
		return;
	}

	//The entry goes; its .scpt stays, in case another entry names it
	[[self scripts] removeObjectAtIndex:(NSUInteger)row];
	[self.document noteEdited];
	[self reloadFromModel];
}

- (IBAction)toggledPrefix:(NSButton *)sender
{
	NSInteger row = [table rowForView:sender];
	if (row < 0 || row >= (NSInteger)[[self scripts] count]) return;

	NSMutableDictionary *entry = [self scripts][(NSUInteger)row];
	if (![entry isKindOfClass:[NSMutableDictionary class]]) return;

	entry[@"Prefix Only"] = @([sender state] == NSControlStateValueOn);
	[self.document noteEdited];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[[self scripts] count];
}

- (NSMutableDictionary *)entryForRow:(NSInteger)row
{
	id entry = [self scripts][(NSUInteger)row];
	return ([entry isKindOfClass:[NSMutableDictionary class]] ? entry : nil);
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *columnID = [tableColumn identifier];
	NSDictionary *entry = [self entryForRow:row];

	if ([columnID isEqualToString:@"Prefix Only"]) {
		NSButton *box = [tableView makeViewWithIdentifier:@"Prefix Only" owner:self];
		if (!box) {
			box = [[NSButton alloc] initWithFrame:NSZeroRect];
			[box setButtonType:NSButtonTypeSwitch];
			[box setTitle:@""];
			[box setIdentifier:@"Prefix Only"];
			[box setTarget:self];
			[box setAction:@selector(toggledPrefix:)];
		}
		//Absent means: prefix-only when the keyword starts with a slash, matching the loader
		id value = entry[@"Prefix Only"];
		BOOL prefixOnly = (value ? [value boolValue] : [[entry[@"Keyword"] description] hasPrefix:@"/"]);
		[box setState:(prefixOnly ? NSControlStateValueOn : NSControlStateValueOff)];
		return box;
	}

	BOOL editable = ![columnID isEqualToString:@"File"];
	NSTextField *field = [tableView makeViewWithIdentifier:columnID owner:self];
	if (!field) {
		field = [[NSTextField alloc] initWithFrame:NSZeroRect];
		[field setIdentifier:columnID];
		[field setBezeled:NO];
		[field setDrawsBackground:NO];
		[field setLineBreakMode:NSLineBreakByTruncatingTail];
		[field setDelegate:self];
	}

	[field setEditable:editable];
	[field setStringValue:[entry[columnID] description] ?: @""];
	[field setTextColor:(editable ? [NSColor labelColor] : [NSColor secondaryLabelColor])];

	return field;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[removeButton setEnabled:([table selectedRow] >= 0)];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	NSTextField *field = [notification object];
	if (field == setNameField) return;

	NSInteger row = [table rowForView:field];
	NSMutableDictionary *entry = (row >= 0 ? [self entryForRow:row] : nil);
	if (!entry) return;

	entry[[field identifier]] = [field stringValue];
	[self.document noteEdited];
}

@end
