/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSSoundSetEditorViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define SOUND_TABLE_HEIGHT	340.0
#define INFO_HEIGHT			90.0

@interface AXSSoundSetEditorViewController () <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@end

@implementation AXSSoundSetEditorViewController {
	NSTableView *table;
	NSTextView *infoView;
	NSArray<NSString *> *eventKeys;
	AVAudioPlayer *player;
}

- (NSString *)tabTitle
{
	return @"Sounds";
}

- (NSMutableDictionary *)sounds
{
	NSMutableDictionary *payload = self.document.model.payload;
	NSMutableDictionary *sounds = payload[@"Sounds"];

	if (!sounds) {
		sounds = [NSMutableDictionary dictionary];
		payload[@"Sounds"] = sounds;
	}
	return sounds;
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;

	[form addSectionHeader:@"Description"];

	NSScrollView *infoScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 640, INFO_HEIGHT)];
	[infoScroll setHasVerticalScroller:YES];
	[infoScroll setDrawsBackground:NO];

	infoView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 640, INFO_HEIGHT)];
	[infoView setRichText:NO];
	[infoView setEditable:YES];
	[infoView setAllowsUndo:YES];
	[infoView setVerticallyResizable:YES];
	[infoView setAutoresizingMask:NSViewWidthSizable];
	[[infoView textContainer] setWidthTracksTextView:YES];
	[infoView setTextContainerInset:NSMakeSize(8.0, 8.0)];
	[infoView setDelegate:self];
	[infoScroll setDocumentView:infoView];

	[form addEdgeToEdgeRow:infoScroll];
	[form addFootnote:@"Shown when the set is picked in Adium's event settings; "
					  @"usually the maker and a word about the sounds."];

	[form addSectionHeader:@"Sounds"];

	table = [[NSTableView alloc] initWithFrame:NSZeroRect];
	[table setRowHeight:22.0];
	[table setUsesAlternatingRowBackgroundColors:YES];

	NSTableColumn *eventColumn = [[NSTableColumn alloc] initWithIdentifier:@"event"];
	[eventColumn setTitle:@"Event"];
	[eventColumn setWidth:300.0];
	[table addTableColumn:eventColumn];

	NSTableColumn *fileColumn = [[NSTableColumn alloc] initWithIdentifier:@"file"];
	[fileColumn setTitle:@"Sound"];
	[fileColumn setWidth:280.0];
	[table addTableColumn:fileColumn];

	[table setDataSource:self];
	[table setDelegate:self];
	[table setTarget:self];
	[table setDoubleAction:@selector(chooseSoundForClickedRow:)];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 640, SOUND_TABLE_HEIGHT)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDocumentView:table];
	[form addEdgeToEdgeRow:scroll];

	NSButton *choose = [AISettingsFormView pushButtonWithTitle:@"Choose Sound…" target:self action:@selector(chooseSoundForSelection:)];
	NSButton *play = [AISettingsFormView pushButtonWithTitle:@"Play" target:self action:@selector(playSelection:)];
	NSButton *clear = [AISettingsFormView pushButtonWithTitle:@"Clear" target:self action:@selector(clearSelection:)];
	[form addAccessoryView:[AISettingsFormView rowOfViews:@[choose, play, clear]]];

	[form addFootnote:@"Events are named by their English descriptions; that is what the loader "
					  @"maps back to Adium's events. Entries for events this Adium does not know "
					  @"are kept as they are. An event without a sound simply stays silent."];
}

- (void)reloadFromModel
{
	NSString *info = [self.document.model.payload[@"Info"] description];
	[infoView setString:info ?: @""];

	//Catalog events first, then whatever else the set carries
	NSArray *catalogKeys = self.document.format.catalog[@"Sounds"] ?: @[];
	NSMutableArray *rows = [catalogKeys mutableCopy];
	for (NSString *key in [[[self sounds] allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
		if (![rows containsObject:key])
			[rows addObject:key];
	}
	eventKeys = rows;

	[table reloadData];
}

#pragma mark Actions

- (void)assignSoundToKey:(NSString *)key
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setAllowsMultipleSelection:NO];
	if (@available(macOS 11.0, *)) {
		[panel setAllowedContentTypes:@[[UTType typeWithIdentifier:@"public.audio"]]];
	}

	[panel beginSheetModalForWindow:[[self view] window] completionHandler:^(NSModalResponse response) {
		if (response != NSModalResponseOK) return;

		NSURL *url = [[panel URLs] firstObject];
		NSData *data = [NSData dataWithContentsOfURL:url];
		if (!data) return;

		NSString *fileName = [url lastPathComponent];
		NSFileWrapper *resources = self.document.resourcesWrapper;
		NSFileWrapper *existing = [resources fileWrappers][fileName];
		if (existing) [resources removeFileWrapper:existing];
		[resources addRegularFileWithContents:data preferredFilename:fileName];

		[self sounds][key] = fileName;

		[self.document noteEdited];
		[self reloadFromModel];
	}];
}

- (NSString *)selectedKey
{
	NSInteger row = [table selectedRow];
	return (row >= 0 && row < (NSInteger)[eventKeys count]) ? eventKeys[(NSUInteger)row] : nil;
}

- (IBAction)chooseSoundForClickedRow:(NSTableView *)sender
{
	NSInteger row = [table clickedRow];
	if (row >= 0 && row < (NSInteger)[eventKeys count])
		[self assignSoundToKey:eventKeys[(NSUInteger)row]];
}

- (IBAction)chooseSoundForSelection:(id)sender
{
	NSString *key = [self selectedKey];
	if (key) [self assignSoundToKey:key];
	else NSBeep();
}

- (IBAction)playSelection:(id)sender
{
	NSString *key = [self selectedKey];
	NSString *fileName = (key ? [[self sounds][key] description] : nil);
	NSFileWrapper *wrapper = (fileName ? [self.document.resourcesWrapper fileWrappers][fileName] : nil);

	if (!wrapper.regularFile) {
		NSBeep();
		return;
	}

	player = [[AVAudioPlayer alloc] initWithData:[wrapper regularFileContents] error:NULL];
	[player play];
}

- (IBAction)clearSelection:(id)sender
{
	NSString *key = [self selectedKey];
	if (!key) {
		NSBeep();
		return;
	}

	//Only the entry; the file may serve other events and stays in the pack
	[[self sounds] removeObjectForKey:key];
	[self.document noteEdited];
	[self reloadFromModel];
}

#pragma mark Info text

- (void)textDidChange:(NSNotification *)notification
{
	self.document.model.payload[@"Info"] = [[infoView string] copy];
	[self.document noteEdited];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[eventKeys count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *columnID = [tableColumn identifier];
	NSString *key = eventKeys[(NSUInteger)row];
	NSString *fileName = [[self sounds][key] description];
	BOOL inCatalog = [self.document.format.catalog[@"Sounds"] containsObject:key];

	NSTextField *field = [tableView makeViewWithIdentifier:columnID owner:self];
	if (!field) {
		field = [NSTextField labelWithString:@""];
		[field setIdentifier:columnID];
		[field setLineBreakMode:NSLineBreakByTruncatingMiddle];
	}

	if ([columnID isEqualToString:@"event"]) {
		[field setStringValue:(inCatalog ? key : [key stringByAppendingString:@"  (kept)"])];
		[field setTextColor:(inCatalog ? [NSColor labelColor] : [NSColor secondaryLabelColor])];
	} else {
		if (fileName) {
			[field setStringValue:fileName];
			[field setTextColor:[NSColor labelColor]];
		} else {
			[field setStringValue:@"–"];
			[field setTextColor:[NSColor tertiaryLabelColor]];
		}
	}

	return field;
}

@end
