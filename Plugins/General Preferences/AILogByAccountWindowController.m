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

#import "AILogByAccountWindowController.h"
#import <AIUtilities/AITableViewAdditions.h>

#import "AIAccountControllerProtocol.h"
#import "AILoggerPlugin.h"
#import <Adium/AIServiceIcons.h>
#import "AIAccount.h"

@implementation AILogByAccountWindowController

- (id)initWithWindowNibName:(NSString *)windowNibName
{
	if((self = [super initWithWindowNibName:windowNibName])) {
		accounts = adium.accountController.accounts;
	}
	return self;
}

- (void)windowDidLoad
{
	[super windowDidLoad];

	//The xib ships without localized strings; localize the only visible title here
	[button_done setTitle:AILocalizedString(@"Close", nil)];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [accounts count];
}

- (NSView *)tableView:(NSTableView *)aTableView viewForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if (rowIndex < 0 || rowIndex >= (NSInteger)[accounts count])
		return nil;

	AIAccount	*account = [accounts objectAtIndex:rowIndex];
	NSString	*identifier = aTableColumn.identifier;

	if ([identifier isEqualToString:@"checkbox"]) {
		BOOL disabled = [[account preferenceForKey:KEY_LOGGER_OBJECT_DISABLE group:PREF_GROUP_LOGGING] boolValue];
		AICheckboxTableCellView *view = [aTableView ai_checkboxCellViewForColumn:aTableColumn
																			  on:!disabled
																		 enabled:YES
																		  target:self
																		  action:@selector(loggingToggled:)];
		[[view checkbox] setAccessibilityLabel:[account explicitFormattedUID]];
		return view;

	} else if ([identifier isEqualToString:@"icon"]) {
		return [aTableView ai_imageCellViewForColumn:aTableColumn
											   image:[AIServiceIcons serviceIconForObject:account
																					 type:AIServiceIconLarge
																				direction:AIIconNormal]];
	}

	return [aTableView ai_labelCellViewForColumn:aTableColumn value:[account explicitFormattedUID]];
}

- (void)loggingToggled:(id)sender
{
	NSInteger rowIndex = [tableView_accounts rowForView:sender];

	if (rowIndex < 0 || rowIndex >= (NSInteger)[accounts count])
		return;

	[[accounts objectAtIndex:rowIndex] setPreference:[NSNumber numberWithBool:([sender state] != NSControlStateValueOn)]
											  forKey:KEY_LOGGER_OBJECT_DISABLE
											   group:PREF_GROUP_LOGGING];
}

- (IBAction)done:(id)sender
{
	[[self.window sheetParent] endSheet:self.window];
}

@end
