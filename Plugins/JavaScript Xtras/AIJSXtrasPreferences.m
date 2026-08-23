/*
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 *
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import "AIJSXtrasPreferences.h"
#import "AIJSXtrasManager.h"
#import "AIJSXtraBundle.h"
#import <Adium/AISettingsFormView.h>

#define PLUGIN_TABLE_HEIGHT 220.0

@implementation AIJSXtrasPreferences {
	NSView *_view;
	NSSwitch *_masterSwitch;
	NSTableView *_table;
	NSArray<AIJSXtraBundle *> *_bundles;
}

#pragma mark Pane properties

- (AIPreferenceCategory)category { return AIPref_Advanced; }
- (NSString *)paneIdentifier { return @"JavaScript Plugins"; }
- (NSString *)label { return AILocalizedString(@"JavaScript Plugins", nil); }
- (NSImage *)image { return [NSImage imageNamed:NSImageNameActionTemplate]; }

#pragma mark View

- (NSView *)view
{
	if (!_view) {
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(pluginsChanged:)
													 name:AIJSXtrasDidChangeNotification
												   object:nil];

		AISettingsFormView *form = [[AISettingsFormView alloc] initWithWidth:0.0f];
		[self populateForm:form];
		_view = form;
		[form layoutForWidth:NSWidth([form frame])];
		if (![self resizable]) [_view setAutoresizingMask:NSViewMaxYMargin];
	}
	return _view;
}

- (void)populateForm:(AISettingsFormView *)form
{
	_bundles = [[AIJSXtrasManager sharedManager] allBundles];

	[form addSectionHeader:AILocalizedString(@"JavaScript Plugins", nil)];

	_masterSwitch = [AISettingsFormView switchWithTarget:self action:@selector(toggledMaster:)];
	[_masterSwitch setState:([[AIJSXtrasManager sharedManager] masterEnabled] ? NSControlStateValueOn : NSControlStateValueOff)];
	[form addRowWithLabel:AILocalizedString(@"Enable JavaScript plugins", nil) control:_masterSwitch];
	[form addDetailRow:AILocalizedString(@"Plugins reshape how messages are displayed. They run walled off from the page and cannot reach the network or your files.", nil)];

	[form addSectionHeader:AILocalizedString(@"Installed Plugins", nil)];

	if ([_bundles count]) {
		_table = [[NSTableView alloc] initWithFrame:NSZeroRect];
		[_table setRowHeight:22.0];
		[_table setHeaderView:nil];
		[_table setUsesAlternatingRowBackgroundColors:YES];

		NSTableColumn *enabledColumn = [[NSTableColumn alloc] initWithIdentifier:@"enabled"];
		[enabledColumn setWidth:24.0];
		[_table addTableColumn:enabledColumn];

		NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
		[nameColumn setWidth:520.0];
		[_table addTableColumn:nameColumn];

		[_table setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
		[_table setDataSource:self];
		[_table setDelegate:self];

		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 560, PLUGIN_TABLE_HEIGHT)];
		[scroll setHasVerticalScroller:YES];
		[scroll setDocumentView:_table];
		[form addEdgeToEdgeRow:scroll];
	} else {
		[form addEmptyStateRow:AILocalizedString(@"No JavaScript plugins are installed.", nil)];
	}
}

- (AISettingsFormView *)settingsForm
{
	return ([_view isKindOfClass:[AISettingsFormView class]] ? (AISettingsFormView *)_view : nil);
}

- (void)pluginsChanged:(NSNotification *)notification
{
	//Rebuild the form when the set of plugins changes underfoot
	AISettingsFormView *form = [self settingsForm];
	if (!form) return;
	[form removeAllSections];
	[self populateForm:form];
	[form layoutForWidth:NSWidth([form frame])];
}

#pragma mark Actions

- (IBAction)toggledMaster:(id)sender
{
	[[AIJSXtrasManager sharedManager] setMasterEnabled:([_masterSwitch state] == NSControlStateValueOn)];
}

- (IBAction)toggledPlugin:(NSButton *)sender
{
	NSInteger row = [_table rowForView:sender];
	if (row < 0 || row >= (NSInteger)[_bundles count]) return;
	[[AIJSXtrasManager sharedManager] setBundle:_bundles[(NSUInteger)row] enabled:([sender state] == NSControlStateValueOn)];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[_bundles count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	AIJSXtraBundle *bundle = _bundles[(NSUInteger)row];

	if ([[tableColumn identifier] isEqualToString:@"enabled"]) {
		NSButton *box = [tableView makeViewWithIdentifier:@"enabled" owner:self];
		if (!box) {
			box = [[NSButton alloc] initWithFrame:NSZeroRect];
			[box setButtonType:NSButtonTypeSwitch];
			[box setTitle:@""];
			[box setIdentifier:@"enabled"];
			[box setTarget:self];
			[box setAction:@selector(toggledPlugin:)];
		}
		[box setState:([[AIJSXtrasManager sharedManager] isBundleEnabled:bundle] ? NSControlStateValueOn : NSControlStateValueOff)];
		[box setEnabled:[[AIJSXtrasManager sharedManager] masterEnabled]];
		return box;
	}

	NSTextField *field = [tableView makeViewWithIdentifier:@"name" owner:self];
	if (!field) {
		field = [NSTextField labelWithString:@""];
		[field setIdentifier:@"name"];
		[field setLineBreakMode:NSLineBreakByTruncatingTail];
	}

	NSString *detail = ([bundle.version length] ? [NSString stringWithFormat:@"%@ %@", bundle.displayName, bundle.version] : bundle.displayName);
	if ([bundle.author length]) detail = [NSString stringWithFormat:@"%@ — %@", detail, bundle.author];
	[field setStringValue:detail];

	return field;
}

@end
