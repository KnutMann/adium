/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSMessageStyleEditorViewController.h"
#import "AXSMessageStyleCodec.h"

#define VARIANT_TABLE_HEIGHT 180.0

@interface AXSMessageStyleEditorViewController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation AXSMessageStyleEditorViewController {
	NSTextField *fontFamilyField;
	NSTextField *fontSizeField;
	NSTextField *backgroundColorField;
	NSSwitch *showsUserIconsSwitch;
	NSSwitch *allowTextColorsSwitch;
	NSSwitch *combineSwitch;
	NSSwitch *customBackgroundSwitch;
	NSSwitch *transparentSwitch;
	NSPopUpButton *defaultVariantButton;
	NSTextField *noVariantNameField;
	NSTableView *variantTable;
	NSArray<NSString *> *variantNames;
	NSMutableArray<NSTextField *> *templateStateFields;
	NSArray<NSString *> *expectedTemplates;
}

- (NSString *)tabTitle
{
	return @"Style";
}

- (NSMutableDictionary *)style
{
	return self.document.model.payload;
}

#pragma mark Variants on disk

- (NSFileWrapper *)variantsWrapperCreating:(BOOL)create
{
	NSFileWrapper *resources = self.document.resourcesWrapper;
	NSFileWrapper *variants = [resources fileWrappers][@"Variants"];

	if (!variants.directory && create) {
		variants = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
		[variants setPreferredFilename:@"Variants"];
		[resources addFileWrapper:variants];
	}
	return (variants.directory ? variants : nil);
}

- (NSArray<NSString *> *)variantNamesOnDisk
{
	NSMutableArray *names = [NSMutableArray array];
	NSFileWrapper *variants = [self variantsWrapperCreating:NO];

	for (NSString *fileName in [[[variants fileWrappers] allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
		if ([[fileName pathExtension] caseInsensitiveCompare:@"css"] == NSOrderedSame)
			[names addObject:[fileName stringByDeletingPathExtension]];
	}
	return names;
}

#pragma mark Form

- (void)buildForm
{
	AISettingsFormView *form = self.form;
	[form setSharesLabelColumn:YES];

	[form addSectionHeader:@"Appearance"];

	fontFamilyField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedSetting:)];
	[form addRowWithLabel:@"Default font" stretchingControl:fontFamilyField];
	fontSizeField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedSetting:)];
	[form addRowWithLabel:@"Font size" stretchingControl:fontSizeField];
	backgroundColorField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedSetting:)];
	[form addRowWithLabel:@"Background color" stretchingControl:backgroundColorField];

	showsUserIconsSwitch = [AISettingsFormView switchWithTarget:self action:@selector(changedSetting:)];
	[form addRowWithLabel:@"Show user icons" control:showsUserIconsSwitch];
	allowTextColorsSwitch = [AISettingsFormView switchWithTarget:self action:@selector(changedSetting:)];
	[form addRowWithLabel:@"Allow text colors" control:allowTextColorsSwitch];
	combineSwitch = [AISettingsFormView switchWithTarget:self action:@selector(changedSetting:)];
	[form addRowWithLabel:@"Combine consecutive messages" control:combineSwitch];
	customBackgroundSwitch = [AISettingsFormView switchWithTarget:self action:@selector(changedSetting:)];
	[form addRowWithLabel:@"Allow custom backgrounds" control:customBackgroundSwitch];
	transparentSwitch = [AISettingsFormView switchWithTarget:self action:@selector(changedSetting:)];
	[form addRowWithLabel:@"Background is transparent" control:transparentSwitch];

	[form addSectionHeader:@"Variants"];

	variantTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
	[variantTable setRowHeight:20.0];
	[variantTable setHeaderView:nil];
	NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"variant"];
	[variantTable addTableColumn:nameColumn];
	[variantTable setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[variantTable setDataSource:self];
	[variantTable setDelegate:self];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 640, VARIANT_TABLE_HEIGHT)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDocumentView:variantTable];
	[form addEdgeToEdgeRow:scroll];

	NSButton *add = [AISettingsFormView pushButtonWithTitle:@"Add Variant…" target:self action:@selector(addVariant:)];
	NSButton *remove = [AISettingsFormView pushButtonWithTitle:@"Remove" target:self action:@selector(removeVariant:)];
	[form addAccessoryView:[AISettingsFormView rowOfViews:@[add, remove]]];

	defaultVariantButton = [AISettingsFormView popUpButtonWithTitles:@[] target:self action:@selector(changedDefaultVariant:)];
	[form addRowWithLabel:@"Default variant" popUpButton:defaultVariantButton accessoryButton:nil];
	noVariantNameField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedSetting:)];
	[form addRowWithLabel:@"Name for the plain style" stretchingControl:noVariantNameField];
	[form addFootnote:@"Each variant is a stylesheet in Variants/; a new one starts as a copy "
					  @"of main.css. Variant-scoped setting overrides in the Info.plist are "
					  @"preserved but edited by hand."];

	[form addSectionHeader:@"Templates"];

	expectedTemplates = @[@"Incoming/Content.html", @"Incoming/NextContent.html",
						  @"Outgoing/Content.html", @"Outgoing/NextContent.html",
						  @"Incoming/Context.html", @"Outgoing/Context.html",
						  @"Status.html", @"Topic.html", @"FileTransferRequest.html",
						  @"Template.html", @"main.css"];
	templateStateFields = [NSMutableArray array];

	for (NSString *path in expectedTemplates) {
		NSTextField *state = [NSTextField labelWithString:@""];
		[state setFrame:NSMakeRect(0, 0, 220.0, 17.0)];
		[state setAlignment:NSTextAlignmentRight];
		[templateStateFields addObject:state];
		[form addRowWithLabel:path control:state];
	}

	[form addFootnote:@"The HTML and CSS are authored in your own editor; this page only says "
					  @"what is present. Incoming/Content.html and main.css are the two Adium "
					  @"cannot work without; everything else falls back (Outgoing to Incoming, "
					  @"NextContent to Content, Template.html to Adium's own)."];
}

- (void)reloadFromModel
{
	NSDictionary *style = [self style];

	[fontFamilyField setStringValue:[style[@"DefaultFontFamily"] description] ?: @""];
	[fontSizeField setStringValue:[style[@"DefaultFontSize"] description] ?: @""];
	[backgroundColorField setStringValue:[style[@"DefaultBackgroundColor"] description] ?: @""];

	[showsUserIconsSwitch setState:([style[@"ShowsUserIcons"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff)];
	[allowTextColorsSwitch setState:((style[@"AllowTextColors"] == nil || [style[@"AllowTextColors"] boolValue]) ? NSControlStateValueOn : NSControlStateValueOff)];
	[combineSwitch setState:([style[@"DisableCombineConsecutive"] boolValue] ? NSControlStateValueOff : NSControlStateValueOn)];
	[customBackgroundSwitch setState:([style[@"DisableCustomBackground"] boolValue] ? NSControlStateValueOff : NSControlStateValueOn)];
	[transparentSwitch setState:([style[@"DefaultBackgroundIsTransparent"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff)];

	variantNames = [self variantNamesOnDisk];
	[variantTable reloadData];

	[defaultVariantButton removeAllItems];
	[defaultVariantButton addItemWithTitle:@"(plain style)"];
	for (NSString *name in variantNames)
		[defaultVariantButton addItemWithTitle:name];
	NSString *defaultVariant = [style[@"DefaultVariant"] description];
	if (defaultVariant && [variantNames containsObject:defaultVariant])
		[defaultVariantButton selectItemWithTitle:defaultVariant];
	else
		[defaultVariantButton selectItemAtIndex:0];
	[self.form noteContentSizeChanged];

	[noVariantNameField setStringValue:[style[@"DisplayNameForNoVariant"] description] ?: @""];

	[expectedTemplates enumerateObjectsUsingBlock:^(NSString *path, NSUInteger idx, BOOL *stop) {
		BOOL present = [self hasResourceAtPath:path];
		NSTextField *state = templateStateFields[idx];
		BOOL required = [path isEqualToString:@"Incoming/Content.html"] || [path isEqualToString:@"main.css"];

		[state setStringValue:(present ? @"present" : (required ? @"missing (required)" : @"missing, falls back"))];
		[state setTextColor:(present ? [NSColor secondaryLabelColor]
								     : (required ? [NSColor systemRedColor] : [NSColor tertiaryLabelColor]))];
	}];
}

- (BOOL)hasResourceAtPath:(NSString *)path
{
	NSFileWrapper *node = self.document.resourcesWrapper;
	for (NSString *component in [path pathComponents]) {
		node = [node fileWrappers][component];
		if (!node) return NO;
	}
	return node.regularFile;
}

#pragma mark Settings

- (IBAction)changedSetting:(id)sender
{
	NSMutableDictionary *style = [self style];

	NSString *fontFamily = [fontFamilyField stringValue];
	if ([fontFamily length]) style[@"DefaultFontFamily"] = fontFamily;
	else [style removeObjectForKey:@"DefaultFontFamily"];

	NSString *fontSize = [fontSizeField stringValue];
	if ([fontSize length]) style[@"DefaultFontSize"] = @([fontSize integerValue]);
	else [style removeObjectForKey:@"DefaultFontSize"];

	NSString *background = [backgroundColorField stringValue];
	if ([background length]) style[@"DefaultBackgroundColor"] = background;
	else [style removeObjectForKey:@"DefaultBackgroundColor"];

	style[@"ShowsUserIcons"] = @([showsUserIconsSwitch state] == NSControlStateValueOn);
	style[@"AllowTextColors"] = @([allowTextColorsSwitch state] == NSControlStateValueOn);
	style[@"DisableCombineConsecutive"] = @([combineSwitch state] == NSControlStateValueOff);
	style[@"DisableCustomBackground"] = @([customBackgroundSwitch state] == NSControlStateValueOff);
	style[@"DefaultBackgroundIsTransparent"] = @([transparentSwitch state] == NSControlStateValueOn);

	NSString *noVariantName = [noVariantNameField stringValue];
	if ([noVariantName length]) style[@"DisplayNameForNoVariant"] = noVariantName;
	else [style removeObjectForKey:@"DisplayNameForNoVariant"];

	[self.document noteEdited];
}

- (IBAction)changedDefaultVariant:(id)sender
{
	NSInteger index = [defaultVariantButton indexOfSelectedItem];

	if (index <= 0)
		[[self style] removeObjectForKey:@"DefaultVariant"];
	else
		[self style][@"DefaultVariant"] = [defaultVariantButton titleOfSelectedItem];

	[self.document noteEdited];
}

#pragma mark Variants

- (IBAction)addVariant:(id)sender
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:@"New Variant"];
	[alert setInformativeText:@"The name shown in Adium's variant menu; it becomes Variants/<name>.css."];
	[alert addButtonWithTitle:@"Create"];
	[alert addButtonWithTitle:@"Cancel"];

	NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
	[alert setAccessoryView:nameField];

	[alert beginSheetModalForWindow:[[self view] window] completionHandler:^(NSModalResponse response) {
		if (response != NSAlertFirstButtonReturn) return;

		NSString *name = [[nameField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (![name length] || [name rangeOfString:@"/"].location != NSNotFound) {
			NSBeep();
			return;
		}

		NSFileWrapper *variants = [self variantsWrapperCreating:YES];
		NSString *fileName = [name stringByAppendingPathExtension:@"css"];
		if ([variants fileWrappers][fileName]) {
			NSBeep();
			return;
		}

		//A new variant starts as a copy of main.css, so it renders from the first moment
		NSFileWrapper *mainCSS = [self.document.resourcesWrapper fileWrappers][@"main.css"];
		NSData *seed = (mainCSS.regularFile ? [mainCSS regularFileContents] : [NSData data]);
		[variants addRegularFileWithContents:seed preferredFilename:fileName];

		[self.document noteEdited];
		[self reloadFromModel];
	}];
}

- (IBAction)removeVariant:(id)sender
{
	NSInteger row = [variantTable selectedRow];
	if (row < 0 || row >= (NSInteger)[variantNames count]) {
		NSBeep();
		return;
	}

	NSString *name = variantNames[(NSUInteger)row];
	NSFileWrapper *variants = [self variantsWrapperCreating:NO];
	NSFileWrapper *file = [variants fileWrappers][[name stringByAppendingPathExtension:@"css"]];
	if (file) [variants removeFileWrapper:file];

	if ([[[self style][@"DefaultVariant"] description] isEqualToString:name])
		[[self style] removeObjectForKey:@"DefaultVariant"];

	[self.document noteEdited];
	[self reloadFromModel];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[variantNames count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSTextField *field = [tableView makeViewWithIdentifier:@"variant" owner:self];
	if (!field) {
		field = [NSTextField labelWithString:@""];
		[field setIdentifier:@"variant"];
	}
	[field setStringValue:variantNames[(NSUInteger)row]];
	return field;
}

@end
