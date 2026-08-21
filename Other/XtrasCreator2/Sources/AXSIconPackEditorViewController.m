/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSIconPackEditorViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define ICON_ROW_HEIGHT		24.0
#define ICON_TABLE_HEIGHT	260.0

@interface AXSIconPackEditorViewController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation AXSIconPackEditorViewController {
	NSMutableDictionary<NSString *, NSTableView *> *tablesByCategory;
	NSMutableDictionary<NSString *, NSArray<NSString *> *> *rowKeysByCategory;
	NSString *colorEditingCategory;		//Which Colors row the color panel is aimed at
	NSString *colorEditingKey;
}

/*!
 * @brief A category whose values are "r,g,b" strings rather than file names
 */
static BOOL AXSIsColorCategory(NSString *category)
{
	return [category isEqualToString:@"Colors"];
}

static NSColor *AXSColorFromString(NSString *string)
{
	NSArray *parts = [string componentsSeparatedByString:@","];
	if ([parts count] < 3) return nil;

	return [NSColor colorWithSRGBRed:[parts[0] doubleValue] / 255.0
							   green:[parts[1] doubleValue] / 255.0
								blue:[parts[2] doubleValue] / 255.0
							   alpha:1.0];
}

- (NSString *)tabTitle
{
	return self.document.format.displayName;
}

- (NSMutableDictionary *)entriesForCategory:(NSString *)category
{
	NSMutableDictionary *payload = self.document.model.payload;
	NSMutableDictionary *entries = payload[category];

	if (!entries) {
		entries = [NSMutableDictionary dictionary];
		payload[category] = entries;
	}
	return entries;
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;
	AXSXtraFormat *format = self.document.format;

	tablesByCategory = [NSMutableDictionary dictionary];
	rowKeysByCategory = [NSMutableDictionary dictionary];

	//Payload categories beyond the format's own are shown too, at the end
	NSMutableArray *categories = [format.categoryNames mutableCopy];
	NSDictionary *payload = self.document.model.payload;
	for (NSString *category in [[payload allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
		//Scalar passthrough values (version markers) are not categories
		if (![payload[category] isKindOfClass:[NSDictionary class]]) continue;
		if (![categories containsObject:category])
			[categories addObject:category];
	}

	for (NSString *category in categories) {
		[form addSectionHeader:category];

		NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
		[table setRowHeight:ICON_ROW_HEIGHT];
		[table setIdentifier:category];
		[table setUsesAlternatingRowBackgroundColors:YES];
		[table setAllowsMultipleSelection:NO];

		NSTableColumn *keyColumn = [[NSTableColumn alloc] initWithIdentifier:@"key"];
		[keyColumn setTitle:@"Key"];
		[keyColumn setWidth:200.0];
		[table addTableColumn:keyColumn];

		NSTableColumn *iconColumn = [[NSTableColumn alloc] initWithIdentifier:@"icon"];
		[iconColumn setTitle:@""];
		[iconColumn setWidth:28.0];
		[table addTableColumn:iconColumn];

		NSTableColumn *fileColumn = [[NSTableColumn alloc] initWithIdentifier:@"file"];
		[fileColumn setTitle:@"File"];
		[fileColumn setWidth:250.0];
		[table addTableColumn:fileColumn];

		NSTableColumn *sizeColumn = [[NSTableColumn alloc] initWithIdentifier:@"dimensions"];
		[sizeColumn setTitle:@"Size"];
		[sizeColumn setWidth:90.0];
		[table addTableColumn:sizeColumn];

		[table setDataSource:self];
		[table setDelegate:self];
		[table setTarget:self];
		[table setDoubleAction:@selector(chooseImageForClickedRow:)];

		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 640, ICON_TABLE_HEIGHT)];
		[scroll setHasVerticalScroller:YES];
		[scroll setDocumentView:table];
		[form addEdgeToEdgeRow:scroll];

		NSButton *choose = [AISettingsFormView pushButtonWithTitle:(AXSIsColorCategory(category) ? @"Choose Color…" : @"Choose Image…")
															target:self
															action:@selector(chooseImageForSelection:)];
		[choose setIdentifier:category];
		NSButton *clear = [AISettingsFormView pushButtonWithTitle:@"Clear" target:self action:@selector(clearSelection:)];
		[clear setIdentifier:category];
		[form addAccessoryView:[AISettingsFormView rowOfViews:@[choose, clear]]];

		tablesByCategory[category] = table;
	}

	[form addFootnote:@"Double-click a row to pick its image; the file joins the pack's resources. "
					  @"Keys the pack must carry are marked when empty. Entries for services Adium "
					  @"no longer runs are kept untouched."];
}

- (void)reloadFromModel
{
	for (NSString *category in tablesByCategory) {
		[self rebuildRowKeysForCategory:category];
		[tablesByCategory[category] reloadData];
	}
}

/*!
 * @brief Catalog keys first, in their order; whatever else the pack carries after
 */
- (void)rebuildRowKeysForCategory:(NSString *)category
{
	NSArray *catalogKeys = self.document.format.catalog[category] ?: @[];
	NSMutableArray *rows = [catalogKeys mutableCopy];

	NSDictionary *entries = [self entriesForCategory:category];
	for (NSString *key in [[entries allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
		if (![rows containsObject:key])
			[rows addObject:key];
	}

	rowKeysByCategory[category] = rows;
}

#pragma mark Actions

- (void)assignImageToKey:(NSString *)key category:(NSString *)category
{
	if (AXSIsColorCategory(category)) {
		[self pickColorForKey:key category:category];
		return;
	}

	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setAllowsMultipleSelection:NO];
	if (@available(macOS 11.0, *)) {
		[panel setAllowedContentTypes:@[[UTType typeWithIdentifier:@"public.image"]]];
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

		[self entriesForCategory:category][key] = fileName;

		[self.document noteEdited];
		[self reloadFromModel];
	}];
}

- (void)pickColorForKey:(NSString *)key category:(NSString *)category
{
	colorEditingCategory = category;
	colorEditingKey = key;

	NSColorPanel *panel = [NSColorPanel sharedColorPanel];
	NSColor *current = AXSColorFromString([[self entriesForCategory:category][key] description]);
	if (current) [panel setColor:current];

	[panel setTarget:self];
	[panel setAction:@selector(colorPicked:)];
	[panel makeKeyAndOrderFront:nil];
}

- (IBAction)colorPicked:(NSColorPanel *)panel
{
	if (!colorEditingKey) return;

	NSColor *color = [[panel color] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	NSString *value = [NSString stringWithFormat:@"%d,%d,%d",
					   (int)round([color redComponent] * 255.0),
					   (int)round([color greenComponent] * 255.0),
					   (int)round([color blueComponent] * 255.0)];

	[self entriesForCategory:colorEditingCategory][colorEditingKey] = value;
	[self.document noteEdited];
	[self reloadFromModel];
}

- (IBAction)chooseImageForClickedRow:(NSTableView *)table
{
	NSString *category = [table identifier];
	NSInteger row = [table clickedRow];
	NSArray *rows = rowKeysByCategory[category];

	if (row >= 0 && row < (NSInteger)[rows count])
		[self assignImageToKey:rows[(NSUInteger)row] category:category];
}

- (IBAction)chooseImageForSelection:(NSButton *)sender
{
	NSString *category = [sender identifier];
	NSTableView *table = tablesByCategory[category];
	NSInteger row = [table selectedRow];
	NSArray *rows = rowKeysByCategory[category];

	if (row >= 0 && row < (NSInteger)[rows count])
		[self assignImageToKey:rows[(NSUInteger)row] category:category];
	else
		NSBeep();
}

- (IBAction)clearSelection:(NSButton *)sender
{
	NSString *category = [sender identifier];
	NSTableView *table = tablesByCategory[category];
	NSInteger row = [table selectedRow];
	NSArray *rows = rowKeysByCategory[category];

	if (row < 0 || row >= (NSInteger)[rows count]) {
		NSBeep();
		return;
	}

	//Only the entry goes; the image file may serve other keys and stays
	[[self entriesForCategory:category] removeObjectForKey:rows[(NSUInteger)row]];
	[self.document noteEdited];
	[self reloadFromModel];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[rowKeysByCategory[[tableView identifier]] count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *category = [tableView identifier];
	NSString *key = rowKeysByCategory[category][(NSUInteger)row];
	NSString *columnID = [tableColumn identifier];
	NSString *fileName = [[self entriesForCategory:category][key] description];

	if ([columnID isEqualToString:@"icon"]) {
		NSImageView *imageView = [tableView makeViewWithIdentifier:@"icon" owner:self];
		if (!imageView) {
			imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 22, 22)];
			[imageView setIdentifier:@"icon"];
			[imageView setImageScaling:NSImageScaleProportionallyDown];
		}

		NSImage *image = nil;
		if (AXSIsColorCategory(category)) {
			NSColor *color = AXSColorFromString(fileName);
			if (color) {
				image = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect rect) {
					[color setFill];
					[[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3] fill];
					return YES;
				}];
			}
		} else if (fileName) {
			NSFileWrapper *wrapper = [self.document.resourcesWrapper fileWrappers][fileName];
			if (wrapper.regularFile)
				image = [[NSImage alloc] initWithData:[wrapper regularFileContents]];
		}
		[imageView setImage:image];
		return imageView;
	}

	NSTextField *field = [tableView makeViewWithIdentifier:columnID owner:self];
	if (!field) {
		field = [NSTextField labelWithString:@""];
		[field setIdentifier:columnID];
		[field setLineBreakMode:NSLineBreakByTruncatingMiddle];
	}

	BOOL inCatalog = [self.document.format.catalog[category] containsObject:key];
	BOOL required = [self.document.format.requiredCatalog[category] containsObject:key];

	if ([columnID isEqualToString:@"key"]) {
		[field setStringValue:(inCatalog ? key : [key stringByAppendingString:@"  (kept)"])];
		[field setTextColor:(inCatalog ? [NSColor labelColor] : [NSColor secondaryLabelColor])];
	} else if ([columnID isEqualToString:@"file"]) {
		if (fileName) {
			[field setStringValue:fileName];
			[field setTextColor:[NSColor labelColor]];
		} else {
			[field setStringValue:(required ? @"missing (required)" : @"–")];
			[field setTextColor:(required ? [NSColor systemRedColor] : [NSColor tertiaryLabelColor])];
		}
	} else {
		[field setStringValue:(AXSIsColorCategory(category) ? @"" : [self dimensionsStringForFile:fileName])];
		[field setAlignment:NSTextAlignmentRight];
		[field setTextColor:[NSColor secondaryLabelColor]];
	}

	return field;
}

- (NSString *)dimensionsStringForFile:(NSString *)fileName
{
	if (!fileName) return @"";

	NSFileWrapper *wrapper = [self.document.resourcesWrapper fileWrappers][fileName];
	if (!wrapper.regularFile) return @"missing file";

	NSImage *image = [[NSImage alloc] initWithData:[wrapper regularFileContents]];
	NSInteger wide = 0, high = 0;
	for (NSImageRep *rep in [image representations]) {
		if ([rep pixelsWide] > wide) {
			wide = [rep pixelsWide];
			high = [rep pixelsHigh];
		}
	}

	return (wide > 0 ? [NSString stringWithFormat:@"%ld × %ld px", (long)wide, (long)high] : @"");
}

@end
