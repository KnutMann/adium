/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSProblemsViewController.h"
#import "AXSLintEngine.h"

#define PROBLEMS_TABLE_HEIGHT 420.0

@interface AXSProblemsViewController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation AXSProblemsViewController {
	NSTableView *table;
	NSArray<AXSLintIssue *> *issues;
}

- (NSString *)tabTitle
{
	return @"Problems";
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;

	[form addSectionHeader:@"Problems"];

	table = [[NSTableView alloc] initWithFrame:NSZeroRect];
	[table setRowHeight:22.0];
	[table setUsesAlternatingRowBackgroundColors:YES];

	NSTableColumn *levelColumn = [[NSTableColumn alloc] initWithIdentifier:@"level"];
	[levelColumn setTitle:@""];
	[levelColumn setWidth:26.0];
	[table addTableColumn:levelColumn];

	NSTableColumn *messageColumn = [[NSTableColumn alloc] initWithIdentifier:@"message"];
	[messageColumn setTitle:@"Finding"];
	[messageColumn setWidth:560.0];
	[table addTableColumn:messageColumn];

	[table setDataSource:self];
	[table setDelegate:self];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 640, PROBLEMS_TABLE_HEIGHT)];
	[scroll setHasVerticalScroller:YES];
	[scroll setDocumentView:table];
	[form addEdgeToEdgeRow:scroll];

	[form addFootnote:@"Held against what Adium's loaders demand. Errors mean Adium refuses or "
					  @"resets the pack; warnings mean something silently will not show."];
}

- (void)reloadFromModel
{
	issues = [AXSLintEngine lintDocument:self.document];
	[table reloadData];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)MAX([issues count], (NSUInteger)1);
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *columnID = [tableColumn identifier];

	if ([columnID isEqualToString:@"level"]) {
		NSImageView *imageView = [tableView makeViewWithIdentifier:@"level" owner:self];
		if (!imageView) {
			imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 18, 18)];
			[imageView setIdentifier:@"level"];
			[imageView setImageScaling:NSImageScaleProportionallyDown];
		}

		NSImage *image = nil;
		if ((NSUInteger)row < [issues count]) {
			switch (issues[(NSUInteger)row].level) {
				case AXSLintLevelError:
					image = [NSImage imageWithSystemSymbolName:@"xmark.octagon.fill" accessibilityDescription:@"Error"];
					break;
				case AXSLintLevelWarning:
					image = [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill" accessibilityDescription:@"Warning"];
					break;
				case AXSLintLevelInfo:
					image = [NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:@"Note"];
					break;
			}
		}
		[imageView setImage:image];
		return imageView;
	}

	NSTextField *field = [tableView makeViewWithIdentifier:@"message" owner:self];
	if (!field) {
		field = [NSTextField labelWithString:@""];
		[field setIdentifier:@"message"];
		[field setLineBreakMode:NSLineBreakByTruncatingTail];
	}

	if ((NSUInteger)row < [issues count]) {
		[field setStringValue:issues[(NSUInteger)row].message];
		[field setTextColor:[NSColor labelColor]];
	} else {
		[field setStringValue:@"Nothing to object to."];
		[field setTextColor:[NSColor secondaryLabelColor]];
	}

	return field;
}

@end
