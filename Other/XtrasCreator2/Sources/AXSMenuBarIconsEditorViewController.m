/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSMenuBarIconsEditorViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define PREVIEW_SIDE 22.0

@implementation AXSMenuBarIconsEditorViewController {
	NSMutableDictionary<NSString *, NSImageView *> *previewsByKey;
	NSMutableDictionary<NSString *, NSTextField *> *fileLabelsByKey;
}

- (NSString *)tabTitle
{
	return @"Icons";
}

- (NSMutableDictionary *)iconsCategory
{
	NSMutableDictionary *payload = self.document.model.payload;
	NSMutableDictionary *icons = payload[@"Icons"];

	if (!icons) {
		icons = [NSMutableDictionary dictionary];
		payload[@"Icons"] = icons;
	}
	return icons;
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;

	previewsByKey = [NSMutableDictionary dictionary];
	fileLabelsByKey = [NSMutableDictionary dictionary];

	[form addSectionHeader:@"Menu Bar Icons"];

	for (NSString *key in self.document.format.catalog[@"Icons"]) {
		NSImageView *preview = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, PREVIEW_SIDE, PREVIEW_SIDE)];
		[preview setImageScaling:NSImageScaleProportionallyDown];
		previewsByKey[key] = preview;

		NSTextField *fileLabel = [NSTextField labelWithString:@""];
		[fileLabel setTextColor:[NSColor secondaryLabelColor]];
		[fileLabel setFrame:NSMakeRect(0, 0, 220.0, 17.0)];
		[fileLabel setLineBreakMode:NSLineBreakByTruncatingMiddle];
		fileLabelsByKey[key] = fileLabel;

		NSButton *choose = [AISettingsFormView pushButtonWithTitle:@"Choose…" target:self action:@selector(chooseImage:)];
		[choose setIdentifier:key];

		[form addRowWithLabel:key
					  control:[AISettingsFormView rowOfViews:@[fileLabel, preview, choose]]];
	}

	[form addFootnote:@"Shown in the menu bar next to the clock. Small template-style images "
					  @"(black with transparency, about 18 pixels tall) fit best. Online and "
					  @"Offline are required; any state left empty falls back to Online."];
}

- (void)reloadFromModel
{
	NSDictionary *icons = [self iconsCategory];

	for (NSString *key in previewsByKey) {
		NSString *fileName = [icons[key] description];
		[fileLabelsByKey[key] setStringValue:fileName ?: @"none"];

		NSImage *image = nil;
		if (fileName) {
			NSFileWrapper *wrapper = [self.document.resourcesWrapper fileWrappers][fileName];
			if (wrapper.regularFile)
				image = [[NSImage alloc] initWithData:[wrapper regularFileContents]];
		}
		[previewsByKey[key] setImage:image];
	}
}

#pragma mark Actions

- (IBAction)chooseImage:(NSButton *)sender
{
	NSString *key = [sender identifier];

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

		//The image joins the pack's resources under its own name
		NSString *fileName = [url lastPathComponent];
		NSFileWrapper *resources = self.document.resourcesWrapper;
		NSFileWrapper *existing = [resources fileWrappers][fileName];
		if (existing) [resources removeFileWrapper:existing];
		[resources addRegularFileWithContents:data preferredFilename:fileName];

		[self iconsCategory][key] = fileName;

		[self.document noteEdited];
		[self reloadFromModel];
	}];
}

@end
