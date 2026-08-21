/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSPlistTableEditorViewController.h"

#define PLIST_TABLE_HEIGHT 440.0

/*!
 * @brief Does this look like the "r,g,b" color notation the themes use
 */
static NSColor *AXSThemeColorFromValue(id value)
{
	if (![value isKindOfClass:[NSString class]]) return nil;

	NSArray *parts = [value componentsSeparatedByString:@","];
	if ([parts count] != 3 && [parts count] != 4) return nil;

	for (NSString *part in parts) {
		NSScanner *scanner = [NSScanner scannerWithString:part];
		double number;
		if (![scanner scanDouble:&number] || ![scanner isAtEnd]) return nil;
	}

	return [NSColor colorWithSRGBRed:[parts[0] doubleValue] / 255.0
							   green:[parts[1] doubleValue] / 255.0
								blue:[parts[2] doubleValue] / 255.0
							   alpha:1.0];
}

@interface AXSPlistTableEditorViewController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@end

@implementation AXSPlistTableEditorViewController {
	NSTableView *table;
	NSArray<NSString *> *keys;
	NSString *colorEditingKey;
}

- (NSString *)tabTitle
{
	return self.document.format.displayName;
}

- (NSMutableDictionary *)plist
{
	return self.document.model.payload;
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;

	[form addSectionHeader:@"Settings"];

	table = [[NSTableView alloc] initWithFrame:NSZeroRect];
	[table setRowHeight:22.0];
	[table setUsesAlternatingRowBackgroundColors:YES];

	NSTableColumn *keyColumn = [[NSTableColumn alloc] initWithIdentifier:@"key"];
	[keyColumn setTitle:@"Setting"];
	[keyColumn setWidth:320.0];
	[table addTableColumn:keyColumn];

	NSTableColumn *swatchColumn = [[NSTableColumn alloc] initWithIdentifier:@"swatch"];
	[swatchColumn setTitle:@""];
	[swatchColumn setWidth:26.0];
	[table addTableColumn:swatchColumn];

	NSTableColumn *valueColumn = [[NSTableColumn alloc] initWithIdentifier:@"value"];
	[valueColumn setTitle:@"Value"];
	[valueColumn setWidth:280.0];
	[table addTableColumn:valueColumn];

	[table setDataSource:self];
	[table setDelegate:self];
	[table setTarget:self];
	[table setDoubleAction:@selector(editClickedRow:)];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 660, PLIST_TABLE_HEIGHT)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDocumentView:table];
	[form addEdgeToEdgeRow:scroll];

	[form addFootnote:@"The dictionary Adium applies when the set is picked. Colors are the "
					  @"comma notation out of 255 and open the color panel on double click; "
					  @"text and numbers are edited in the value column; anything else is "
					  @"shown and left exactly as it is."];
}

- (void)reloadFromModel
{
	keys = [[[self plist] allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
	[table reloadData];
}

#pragma mark Editing

- (IBAction)editClickedRow:(NSTableView *)sender
{
	NSInteger row = [table clickedRow];
	if (row < 0 || row >= (NSInteger)[keys count]) return;

	NSString *key = keys[(NSUInteger)row];
	NSColor *color = AXSThemeColorFromValue([self plist][key]);
	if (!color) return;	//non-colors edit through the value column

	colorEditingKey = key;
	NSColorPanel *panel = [NSColorPanel sharedColorPanel];
	[panel setColor:color];
	[panel setTarget:self];
	[panel setAction:@selector(colorPicked:)];
	[panel makeKeyAndOrderFront:nil];
}

- (IBAction)colorPicked:(NSColorPanel *)panel
{
	if (!colorEditingKey) return;

	NSColor *color = [[panel color] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	[self plist][colorEditingKey] = [NSString stringWithFormat:@"%d,%d,%d",
									 (int)round([color redComponent] * 255.0),
									 (int)round([color greenComponent] * 255.0),
									 (int)round([color blueComponent] * 255.0)];
	[self.document noteEdited];
	[self reloadFromModel];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	NSTextField *field = [notification object];
	NSInteger row = [table rowForView:field];
	if (row < 0 || row >= (NSInteger)[keys count]) return;

	NSString *key = keys[(NSUInteger)row];
	id oldValue = [self plist][key];
	NSString *text = [field stringValue];
	id newValue = nil;

	//The new value keeps the type the old one had
	if ([oldValue isKindOfClass:[NSString class]]) {
		newValue = text;
	} else if ([oldValue isKindOfClass:[NSNumber class]]) {
		if (!strcmp([oldValue objCType], @encode(BOOL)) || oldValue == (id)kCFBooleanTrue || oldValue == (id)kCFBooleanFalse) {
			if ([text caseInsensitiveCompare:@"true"] == NSOrderedSame || [text isEqualToString:@"1"])
				newValue = @YES;
			else if ([text caseInsensitiveCompare:@"false"] == NSOrderedSame || [text isEqualToString:@"0"])
				newValue = @NO;
		} else {
			NSScanner *scanner = [NSScanner scannerWithString:text];
			double number;
			if ([scanner scanDouble:&number] && [scanner isAtEnd])
				newValue = @(number);
		}
	}

	if (newValue && ![newValue isEqual:oldValue]) {
		[self plist][key] = newValue;
		[self.document noteEdited];
	}

	[table reloadData];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[keys count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *columnID = [tableColumn identifier];
	NSString *key = keys[(NSUInteger)row];
	id value = [self plist][key];

	if ([columnID isEqualToString:@"swatch"]) {
		NSImageView *imageView = [tableView makeViewWithIdentifier:@"swatch" owner:self];
		if (!imageView) {
			imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 18, 18)];
			[imageView setIdentifier:@"swatch"];
		}

		NSColor *color = AXSThemeColorFromValue(value);
		NSImage *image = nil;
		if (color) {
			image = [NSImage imageWithSize:NSMakeSize(14, 14) flipped:NO drawingHandler:^BOOL(NSRect rect) {
				[color setFill];
				[[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3] fill];
				return YES;
			}];
		}
		[imageView setImage:image];
		return imageView;
	}

	if ([columnID isEqualToString:@"key"]) {
		NSTextField *field = [tableView makeViewWithIdentifier:@"key" owner:self];
		if (!field) {
			field = [NSTextField labelWithString:@""];
			[field setIdentifier:@"key"];
			[field setLineBreakMode:NSLineBreakByTruncatingMiddle];
		}
		[field setStringValue:key];
		return field;
	}

	//Value column: editable for the types the end-editing handler can write back
	BOOL editable = [value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]];

	NSTextField *field = [tableView makeViewWithIdentifier:@"value" owner:self];
	if (!field) {
		field = [[NSTextField alloc] initWithFrame:NSZeroRect];
		[field setIdentifier:@"value"];
		[field setBezeled:NO];
		[field setDrawsBackground:NO];
		[field setLineBreakMode:NSLineBreakByTruncatingTail];
		[field setDelegate:self];
	}

	NSString *display;
	if (value == (id)kCFBooleanTrue)		display = @"true";
	else if (value == (id)kCFBooleanFalse)	display = @"false";
	else if ([value isKindOfClass:[NSArray class]])	display = [NSString stringWithFormat:@"(%lu items)", (unsigned long)[value count]];
	else if ([value isKindOfClass:[NSData class]])	display = [NSString stringWithFormat:@"(%lu bytes)", (unsigned long)[value length]];
	else display = [value description] ?: @"";

	[field setStringValue:display];
	[field setEditable:editable];
	[field setTextColor:(editable ? [NSColor labelColor] : [NSColor secondaryLabelColor])];

	return field;
}

@end
