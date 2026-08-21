/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSEmoticonSetEditorViewController.h"
#import "AXSEmoticonSetCodec.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define EMOTICON_TABLE_HEIGHT 380.0

@interface AXSEmoticonSetEditorViewController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@end

@implementation AXSEmoticonSetEditorViewController {
	NSTableView *table;
	NSArray<NSString *> *emoticonKeys;
	NSButton *removeButton;
}

- (NSString *)tabTitle
{
	return @"Emoticons";
}

- (NSMutableDictionary *)emoticons
{
	return self.document.model.payload[@"Emoticons"];
}

- (BOOL)isEditableSet
{
	return [AXSEmoticonSetCodec payloadIsEditable:self.document.model.payload];
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;

	[form addSectionHeader:@"Emoticons"];

	table = [[NSTableView alloc] initWithFrame:NSZeroRect];
	[table setRowHeight:26.0];
	[table setUsesAlternatingRowBackgroundColors:YES];
	[table setAllowsMultipleSelection:YES];

	NSTableColumn *iconColumn = [[NSTableColumn alloc] initWithIdentifier:@"icon"];
	[iconColumn setTitle:@""];
	[iconColumn setWidth:30.0];
	[table addTableColumn:iconColumn];

	NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"Name"];
	[nameColumn setTitle:@"Name"];
	[nameColumn setWidth:170.0];
	[table addTableColumn:nameColumn];

	NSTableColumn *equivColumn = [[NSTableColumn alloc] initWithIdentifier:@"Equivalents"];
	[equivColumn setTitle:@"Text Equivalents"];
	[equivColumn setWidth:210.0];
	[table addTableColumn:equivColumn];

	NSTableColumn *charColumn = [[NSTableColumn alloc] initWithIdentifier:@"Character"];
	[charColumn setTitle:@"Emoji"];
	[charColumn setWidth:60.0];
	[table addTableColumn:charColumn];

	NSTableColumn *fileColumn = [[NSTableColumn alloc] initWithIdentifier:@"file"];
	[fileColumn setTitle:@"File"];
	[fileColumn setWidth:150.0];
	[table addTableColumn:fileColumn];

	[table setDataSource:self];
	[table setDelegate:self];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 660, EMOTICON_TABLE_HEIGHT)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDocumentView:table];
	[form addEdgeToEdgeRow:scroll];

	NSButton *addButton = [AISettingsFormView pushButtonWithTitle:@"Add Images…" target:self action:@selector(addEmoticons:)];
	removeButton = [AISettingsFormView pushButtonWithTitle:@"Remove" target:self action:@selector(removeSelected:)];
	[removeButton setEnabled:NO];
	[form addAccessoryView:[AISettingsFormView rowOfViews:@[addButton, removeButton]]];

	[form addFootnote:@"Name, text equivalents and the emoji column are edited in place; equivalents "
					  @"are separated by commas. An entry with an emoji needs no image: Adium renders "
					  @"the character itself. A set whose every emoticon lacks both image and emoji "
					  @"is dropped by Adium without a word."];
}

- (void)reloadFromModel
{
	emoticonKeys = [[[self emoticons] allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
	[table reloadData];
	[removeButton setEnabled:([table selectedRow] >= 0)];
}

#pragma mark Actions

- (IBAction)addEmoticons:(id)sender
{
	if (![self isEditableSet]) {
		NSBeep();
		return;
	}

	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setAllowsMultipleSelection:YES];
	if (@available(macOS 11.0, *)) {
		[panel setAllowedContentTypes:@[[UTType typeWithIdentifier:@"public.image"]]];
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

			//The dictionary key is the file name; the name starts as the file's own
			if (![self emoticons][fileName]) {
				[self emoticons][fileName] = [NSMutableDictionary dictionaryWithDictionary:@{
					@"Name": [fileName stringByDeletingPathExtension],
					@"Equivalents": @[],
				}];
			}
		}

		[self.document noteEdited];
		[self reloadFromModel];
	}];
}

- (IBAction)removeSelected:(id)sender
{
	NSIndexSet *selection = [table selectedRowIndexes];

	[selection enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		NSString *key = emoticonKeys[idx];
		[[self emoticons] removeObjectForKey:key];

		//The image goes with its entry when nothing else points at it
		NSFileWrapper *wrapper = [self.document.resourcesWrapper fileWrappers][key];
		if (wrapper) [self.document.resourcesWrapper removeFileWrapper:wrapper];
	}];

	[self.document noteEdited];
	[self reloadFromModel];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[emoticonKeys count];
}

- (NSMutableDictionary *)entryForRow:(NSInteger)row
{
	id entry = [self emoticons][emoticonKeys[(NSUInteger)row]];
	return ([entry isKindOfClass:[NSMutableDictionary class]] ? entry : nil);
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *columnID = [tableColumn identifier];
	NSString *key = emoticonKeys[(NSUInteger)row];
	NSDictionary *entry = [self entryForRow:row];

	if ([columnID isEqualToString:@"icon"]) {
		NSImageView *imageView = [tableView makeViewWithIdentifier:@"icon" owner:self];
		if (!imageView) {
			imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 24, 24)];
			[imageView setIdentifier:@"icon"];
			[imageView setImageScaling:NSImageScaleProportionallyDown];
		}

		NSImage *image = nil;
		NSFileWrapper *wrapper = [self.document.resourcesWrapper fileWrappers][key];
		if (wrapper.regularFile)
			image = [[NSImage alloc] initWithData:[wrapper regularFileContents]];
		[imageView setImage:image];
		return imageView;
	}

	if ([columnID isEqualToString:@"file"]) {
		NSTextField *field = [tableView makeViewWithIdentifier:@"file" owner:self];
		if (!field) {
			field = [NSTextField labelWithString:@""];
			[field setIdentifier:@"file"];
			[field setLineBreakMode:NSLineBreakByTruncatingMiddle];
			[field setTextColor:[NSColor secondaryLabelColor]];
		}
		[field setStringValue:key];
		return field;
	}

	//The three editable columns share one construction
	NSTextField *field = [tableView makeViewWithIdentifier:columnID owner:self];
	if (!field) {
		field = [[NSTextField alloc] initWithFrame:NSZeroRect];
		[field setIdentifier:columnID];
		[field setBezeled:NO];
		[field setDrawsBackground:NO];
		[field setEditable:YES];
		[field setLineBreakMode:NSLineBreakByTruncatingTail];
		[field setDelegate:self];
	}

	if ([columnID isEqualToString:@"Name"]) {
		[field setStringValue:[entry[@"Name"] description] ?: @""];
	} else if ([columnID isEqualToString:@"Equivalents"]) {
		NSArray *equivalents = ([entry[@"Equivalents"] isKindOfClass:[NSArray class]] ? entry[@"Equivalents"] : @[]);
		[field setStringValue:[equivalents componentsJoinedByString:@", "]];
	} else {
		[field setStringValue:[entry[@"Character"] description] ?: @""];
	}

	return field;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[removeButton setEnabled:([table selectedRow] >= 0)];
}

/*!
 * @brief An in-table edit ended; write it into the entry
 */
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	NSTextField *field = [notification object];
	NSInteger row = [table rowForView:field];
	if (row < 0) return;

	NSMutableDictionary *entry = [self entryForRow:row];
	if (!entry) return;

	NSString *columnID = [field identifier];
	NSString *value = [field stringValue];

	if ([columnID isEqualToString:@"Name"]) {
		entry[@"Name"] = value;
	} else if ([columnID isEqualToString:@"Equivalents"]) {
		NSMutableArray *equivalents = [NSMutableArray array];
		for (NSString *piece in [value componentsSeparatedByString:@","]) {
			NSString *trimmed = [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if ([trimmed length]) [equivalents addObject:trimmed];
		}
		entry[@"Equivalents"] = equivalents;
	} else if ([columnID isEqualToString:@"Character"]) {
		if ([value length])
			entry[@"Character"] = value;
		else
			[entry removeObjectForKey:@"Character"];
	} else {
		return;
	}

	[self.document noteEdited];
}

@end
