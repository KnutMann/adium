/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSDockIconEditorViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define STATE_TABLE_HEIGHT	280.0
#define PREVIEW_SIDE		96.0
#define SHARED_IMAGES_PREFIX @"../Shared Images/"

@interface AXSDockIconEditorViewController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation AXSDockIconEditorViewController {
	NSTextField *titleField;
	NSTextField *creatorField;
	NSTextField *linkField;
	NSTableView *table;
	NSArray<NSString *> *stateNames;
	NSImageView *previewView;
	NSTimer *animationTimer;
	NSArray<NSImage *> *animationFrames;
	NSUInteger animationIndex;
}

- (NSString *)tabTitle
{
	return @"Dock Icon";
}

- (NSMutableDictionary *)descriptionDict
{
	NSMutableDictionary *payload = self.document.model.payload;
	NSMutableDictionary *description = payload[@"Description"];
	if (![description isKindOfClass:[NSMutableDictionary class]]) {
		description = [NSMutableDictionary dictionary];
		payload[@"Description"] = description;
	}
	return description;
}

- (NSMutableDictionary *)states
{
	NSMutableDictionary *payload = self.document.model.payload;
	NSMutableDictionary *states = payload[@"State"];
	if (![states isKindOfClass:[NSMutableDictionary class]]) {
		states = [NSMutableDictionary dictionary];
		payload[@"State"] = states;
	}
	return states;
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;
	[form setSharesLabelColumn:YES];

	[form addSectionHeader:@"Description"];

	titleField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedDescription:)];
	[form addRowWithLabel:@"Title" stretchingControl:titleField];
	creatorField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedDescription:)];
	[form addRowWithLabel:@"Creator" stretchingControl:creatorField];
	linkField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedDescription:)];
	[form addRowWithLabel:@"Link" stretchingControl:linkField];

	[form addSectionHeader:@"States"];

	table = [[NSTableView alloc] initWithFrame:NSZeroRect];
	[table setRowHeight:24.0];
	[table setUsesAlternatingRowBackgroundColors:YES];

	NSTableColumn *stateColumn = [[NSTableColumn alloc] initWithIdentifier:@"state"];
	[stateColumn setTitle:@"State"];
	[stateColumn setWidth:170.0];
	[table addTableColumn:stateColumn];

	NSTableColumn *imagesColumn = [[NSTableColumn alloc] initWithIdentifier:@"images"];
	[imagesColumn setTitle:@"Images"];
	[imagesColumn setWidth:330.0];
	[table addTableColumn:imagesColumn];

	NSTableColumn *flagsColumn = [[NSTableColumn alloc] initWithIdentifier:@"flags"];
	[flagsColumn setTitle:@""];
	[flagsColumn setWidth:120.0];
	[table addTableColumn:flagsColumn];

	[table setDataSource:self];
	[table setDelegate:self];
	[table setTarget:self];
	[table setDoubleAction:@selector(chooseImagesForClickedRow:)];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 640, STATE_TABLE_HEIGHT)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDocumentView:table];
	[form addEdgeToEdgeRow:scroll];

	NSButton *choose = [AISettingsFormView pushButtonWithTitle:@"Choose Images…" target:self action:@selector(chooseImagesForSelection:)];
	NSButton *clear = [AISettingsFormView pushButtonWithTitle:@"Clear" target:self action:@selector(clearSelection:)];
	[form addAccessoryView:[AISettingsFormView rowOfViews:@[choose, clear]]];

	[form addSectionHeader:@"Preview"];

	previewView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, PREVIEW_SIDE, PREVIEW_SIDE)];
	[previewView setImageScaling:NSImageScaleProportionallyUpOrDown];
	[form addRowWithLabel:@"Selected state" control:previewView];

	[form addFootnote:@"One image makes a still state; several make an animation running at the "
					  @"state's delay. Base is the icon itself and must exist; Preview is what "
					  @"pickers show; Alert flaps on unread messages; the away and idle states "
					  @"draw over Base. Images from \"../Shared Images/\" are Adium's shared "
					  @"artwork and are left exactly as written."];
}

- (void)reloadFromModel
{
	NSDictionary *description = [self descriptionDict];
	[titleField setStringValue:[description[@"Title"] description] ?: @""];
	[creatorField setStringValue:[description[@"Creator"] description] ?: @""];
	[linkField setStringValue:[description[@"LinkURL"] description] ?: @""];

	NSArray *catalogStates = self.document.format.catalog[@"State"] ?: @[];
	NSMutableArray *rows = [catalogStates mutableCopy];
	for (NSString *name in [[[self states] allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
		if (![rows containsObject:name])
			[rows addObject:name];
	}
	stateNames = rows;

	[table reloadData];
	[self updatePreview];
}

#pragma mark Description

- (IBAction)changedDescription:(id)sender
{
	NSMutableDictionary *description = [self descriptionDict];
	description[@"Title"] = [titleField stringValue];
	description[@"Creator"] = [creatorField stringValue];
	description[@"LinkURL"] = [linkField stringValue];
	[self.document noteEdited];
}

#pragma mark Images

- (NSImage *)imageNamed:(NSString *)fileName
{
	if ([fileName hasPrefix:SHARED_IMAGES_PREFIX])
		return nil;	//lives in Adium, not in the pack

	NSFileWrapper *wrapper = [self.document.resourcesWrapper fileWrappers][fileName];
	return (wrapper.regularFile ? [[NSImage alloc] initWithData:[wrapper regularFileContents]] : nil);
}

- (NSArray<NSString *> *)imageNamesForState:(NSString *)name
{
	NSDictionary *entry = [self states][name];
	if (![entry isKindOfClass:[NSDictionary class]]) return @[];

	if ([entry[@"Images"] isKindOfClass:[NSArray class]])
		return entry[@"Images"];
	if ([entry[@"Image"] isKindOfClass:[NSString class]])
		return @[entry[@"Image"]];
	return @[];
}

- (void)assignImagesToState:(NSString *)name
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setAllowsMultipleSelection:YES];
	if (@available(macOS 11.0, *)) {
		[panel setAllowedContentTypes:@[[UTType typeWithIdentifier:@"public.image"]]];
	}

	[panel beginSheetModalForWindow:[[self view] window] completionHandler:^(NSModalResponse response) {
		if (response != NSModalResponseOK || ![[panel URLs] count]) return;

		NSFileWrapper *resources = self.document.resourcesWrapper;
		NSMutableArray *names = [NSMutableArray array];

		for (NSURL *url in [panel URLs]) {
			NSData *data = [NSData dataWithContentsOfURL:url];
			if (!data) continue;

			NSString *fileName = [url lastPathComponent];
			NSFileWrapper *existing = [resources fileWrappers][fileName];
			if (existing) [resources removeFileWrapper:existing];
			[resources addRegularFileWithContents:data preferredFilename:fileName];
			[names addObject:fileName];
		}

		if (![names count]) return;

		NSMutableDictionary *entry = [self states][name];
		if (![entry isKindOfClass:[NSMutableDictionary class]]) {
			entry = [NSMutableDictionary dictionary];
			[self states][name] = entry;
		}

		if ([names count] == 1) {
			entry[@"Animated"] = @NO;
			entry[@"Image"] = names[0];
			[entry removeObjectForKey:@"Images"];
			[entry removeObjectForKey:@"Delay"];
		} else {
			entry[@"Animated"] = @YES;
			entry[@"Images"] = names;
			if (!entry[@"Delay"]) entry[@"Delay"] = @0.5;
			[entry removeObjectForKey:@"Image"];
		}
		if (!entry[@"Overlay"])
			entry[@"Overlay"] = @NO;

		[self.document noteEdited];
		[self reloadFromModel];
	}];
}

- (NSString *)selectedStateName
{
	NSInteger row = [table selectedRow];
	return (row >= 0 && row < (NSInteger)[stateNames count]) ? stateNames[(NSUInteger)row] : nil;
}

- (IBAction)chooseImagesForClickedRow:(NSTableView *)sender
{
	NSInteger row = [table clickedRow];
	if (row >= 0 && row < (NSInteger)[stateNames count])
		[self assignImagesToState:stateNames[(NSUInteger)row]];
}

- (IBAction)chooseImagesForSelection:(id)sender
{
	NSString *name = [self selectedStateName];
	if (name) [self assignImagesToState:name];
	else NSBeep();
}

- (IBAction)clearSelection:(id)sender
{
	NSString *name = [self selectedStateName];
	if (!name) {
		NSBeep();
		return;
	}

	[[self states] removeObjectForKey:name];
	[self.document noteEdited];
	[self reloadFromModel];
}

#pragma mark Preview

- (void)updatePreview
{
	[animationTimer invalidate];
	animationTimer = nil;
	animationFrames = nil;

	NSString *name = [self selectedStateName];
	if (!name) {
		[previewView setImage:nil];
		return;
	}

	NSMutableArray *frames = [NSMutableArray array];
	for (NSString *fileName in [self imageNamesForState:name]) {
		NSImage *image = [self imageNamed:fileName];
		if (image) [frames addObject:image];
	}

	if (![frames count]) {
		[previewView setImage:nil];
		return;
	}

	[previewView setImage:frames[0]];

	if ([frames count] > 1) {
		NSDictionary *entry = [self states][name];
		NSTimeInterval delay = [entry[@"Delay"] doubleValue];
		if (delay <= 0) delay = 0.5;

		animationFrames = frames;
		animationIndex = 0;
		animationTimer = [NSTimer scheduledTimerWithTimeInterval:delay
														  target:self
														selector:@selector(advanceAnimation:)
														userInfo:nil
														 repeats:YES];
	}
}

- (void)advanceAnimation:(NSTimer *)timer
{
	animationIndex = (animationIndex + 1) % [animationFrames count];
	[previewView setImage:animationFrames[animationIndex]];
}

- (void)viewWillDisappear
{
	[super viewWillDisappear];
	[animationTimer invalidate];
	animationTimer = nil;
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[stateNames count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *columnID = [tableColumn identifier];
	NSString *name = stateNames[(NSUInteger)row];
	NSDictionary *entry = [self states][name];
	BOOL inCatalog = [self.document.format.catalog[@"State"] containsObject:name];
	BOOL required = [self.document.format.requiredCatalog[@"State"] containsObject:name];

	NSTextField *field = [tableView makeViewWithIdentifier:columnID owner:self];
	if (!field) {
		field = [NSTextField labelWithString:@""];
		[field setIdentifier:columnID];
		[field setLineBreakMode:NSLineBreakByTruncatingMiddle];
	}

	if ([columnID isEqualToString:@"state"]) {
		[field setStringValue:(inCatalog ? name : [name stringByAppendingString:@"  (kept)"])];
		[field setTextColor:(inCatalog ? [NSColor labelColor] : [NSColor secondaryLabelColor])];
	} else if ([columnID isEqualToString:@"images"]) {
		NSArray *names = [self imageNamesForState:name];
		if ([names count]) {
			[field setStringValue:[names componentsJoinedByString:@", "]];
			[field setTextColor:[NSColor labelColor]];
		} else {
			[field setStringValue:(required ? @"missing (required)" : @"–")];
			[field setTextColor:(required ? [NSColor systemRedColor] : [NSColor tertiaryLabelColor])];
		}
	} else {
		NSMutableArray *flags = [NSMutableArray array];
		if ([entry[@"Animated"] boolValue]) {
			double delay = [entry[@"Delay"] doubleValue];
			[flags addObject:(delay > 0 ? [NSString stringWithFormat:@"animated %.2gs", delay] : @"animated")];
		}
		if ([entry[@"Overlay"] boolValue]) [flags addObject:@"overlay"];
		[field setStringValue:[flags componentsJoinedByString:@", "]];
		[field setTextColor:[NSColor secondaryLabelColor]];
	}

	return field;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self updatePreview];
}

@end
