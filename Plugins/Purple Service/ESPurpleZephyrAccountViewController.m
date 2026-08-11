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

/* TODO ADIUM-UNUSED: part of the Zephyr set. Its registration in CBPurpleServicePlugin.m is
 * commented out, so the service never reaches the account controller. Uncommenting it would not
 * help: the bundled prpl-zephyr is built without Kerberos, leaving the zephyr host manager as its
 * only route to a server, and zhm is in no copy phase - the checked-in binary is i386/ppc besides.
 * This file is scheduled for removal - the full inventory is in Other/ADIUM-UNUSED.txt.
 */

#import "ESPurpleZephyrAccountViewController.h"
#import "ESPurpleZephyrAccount.h"
#import <Adium/AIAccount.h>

@implementation ESPurpleZephyrAccountViewController

- (NSString *)nibName{
    return @"ESPurpleZephyrAccountView";
}

/*!
 * @brief Update control enabledness based on current state.
 */
- (void)updateControlAvailability
{
    BOOL selection = ([tableView_servers selectedRow] != -1);
	[button_addOrRemoveServer setEnabled:selection forSegment:1];
}

//Configure our controls
- (void)configureForAccount:(AIAccount *)inAccount
{
    [super configureForAccount:inAccount];

	[checkBox_exportAnyone setState:[[account preferenceForKey:KEY_ZEPHYR_EXPORT_ANYONE group:GROUP_ACCOUNT_STATUS] boolValue]];
	[checkBox_exportSubs setState:[[account preferenceForKey:KEY_ZEPHYR_EXPORT_SUBS group:GROUP_ACCOUNT_STATUS] boolValue]];

	[checkBox_launchZhm setState:[[account preferenceForKey:KEY_ZEPHYR_LAUNCH_ZHM group:GROUP_ACCOUNT_STATUS] boolValue]];

	[textField_exposure setStringValue:[account preferenceForKey:KEY_ZEPHYR_EXPOSURE group:GROUP_ACCOUNT_STATUS]];
	[textField_encoding setStringValue:[account preferenceForKey:KEY_ZEPHYR_ENCODING group:GROUP_ACCOUNT_STATUS]];

    [self updateControlAvailability];
}

- (IBAction)changedPreference:(id)sender
{	
	if (sender == checkBox_exportAnyone) {
		[account setPreference:[NSNumber numberWithBool:[sender state]]
						forKey:KEY_ZEPHYR_EXPORT_ANYONE
						 group:GROUP_ACCOUNT_STATUS];

	} else if (sender == checkBox_exportSubs) {
		[account setPreference:[NSNumber numberWithBool:[sender state]]
						forKey:KEY_ZEPHYR_EXPORT_SUBS
						 group:GROUP_ACCOUNT_STATUS];

	} else if (sender == checkBox_launchZhm) {
		[account setPreference:[NSNumber numberWithBool:[sender state]]
						forKey:KEY_ZEPHYR_LAUNCH_ZHM
						 group:GROUP_ACCOUNT_STATUS];

	} else if (sender == textField_exposure) {
		NSString *exposure = [sender stringValue];
		[account setPreference:([exposure length] ? exposure : nil)
						forKey:KEY_ZEPHYR_EXPOSURE
						 group:GROUP_ACCOUNT_STATUS];

	} else if (sender == textField_encoding) {
		NSString *encoding = [sender stringValue];

		[account setPreference:([encoding length] ? encoding : nil)
						forKey:KEY_ZEPHYR_ENCODING
						 group:GROUP_ACCOUNT_STATUS];

	} else {
		[super changedPreference:sender];
	}
}

// We are the data source for the table we use to show server names
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSArray *ray = [account preferenceForKey:KEY_ZEPHYR_SERVERS group:GROUP_ACCOUNT_STATUS];
    NSParameterAssert(rowIndex >= 0 && rowIndex < [ray count]);

    return [ray objectAtIndex:rowIndex];
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSMutableArray *ray = [[account preferenceForKey:KEY_ZEPHYR_SERVERS group:GROUP_ACCOUNT_STATUS] mutableCopy];
    NSParameterAssert(rowIndex >= 0 && rowIndex < [ray count]);

    [ray replaceObjectAtIndex:rowIndex withObject:anObject];

    [account setPreference:ray
                    forKey:KEY_ZEPHYR_SERVERS
                     group:GROUP_ACCOUNT_STATUS];
    [ray release];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [[account preferenceForKey:KEY_ZEPHYR_SERVERS group:GROUP_ACCOUNT_STATUS] count];
}

- (IBAction)addOrRemoveRowToServerList:(id)sender {
	NSInteger selectedSegment = [sender selectedSegment];
	
	switch (selectedSegment) {
		case 0:
			[self addRowToServerList];
			break;
		case 1:
			[self removeSelectedRowFromServerList];
			break;
	}
}

/*!
 * @brief Add a new server to the list of servers.
 */
- (void)addRowToServerList {
    NSArray *ray = [[account preferenceForKey:KEY_ZEPHYR_SERVERS group:GROUP_ACCOUNT_STATUS] retain];

    [account setPreference:[ray arrayByAddingObject:@""]
                    forKey:KEY_ZEPHYR_SERVERS
                     group:GROUP_ACCOUNT_STATUS];

    [tableView_servers reloadData];
    [tableView_servers selectRowIndexes:[NSIndexSet indexSetWithIndex:[ray count]] byExtendingSelection:NO];
    [tableView_servers editColumn:0 row:[ray count] withEvent:nil select:YES];

    [ray release];
}

/*!
 * @brief Remove the selected row from the list of servers.
 */
- (void)removeSelectedRowFromServerList {
    NSInteger idx = [tableView_servers selectedRow];
    if (idx != -1) {
        NSMutableArray *ray = [[account preferenceForKey:KEY_ZEPHYR_SERVERS group:GROUP_ACCOUNT_STATUS] mutableCopy];
        
        [ray removeObjectAtIndex:idx];
        
        [account setPreference:ray
                        forKey:KEY_ZEPHYR_SERVERS
                         group:GROUP_ACCOUNT_STATUS];
        [ray release];
        [tableView_servers reloadData];
    }
}

/*!
 * @brief Selection change
 */
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self updateControlAvailability];
}

#pragma mark Localization
//The xib is monolingual (English); set all visible strings from code
- (void)localizeStrings
{
	[super localizeStrings];

	[label_kerberosInfo setStringValue:AILocalizedString(@"Zephyr requires a proper Kerberos configuration.  Zephyr uses your UNIX UID or your Kerberos name; the user name above is solely for internal Adium use.  Only one simultaneous Zephyr connection is recommended.  Using the internal host manager will conflict with any other 'zhm' instances running on this machine.", nil)];
	[label_exposure setStringValue:AILocalizedString(@"Exposure:", nil)];
	[label_encoding setStringValue:AILocalizedString(@"Encoding:", nil)];
	[label_export setStringValue:AILocalizedString(@"Export:", nil)];
	[checkBox_exportAnyone setTitle:AILocalizedString(@"Export to .anyone", nil)];
	[checkBox_exportSubs setTitle:AILocalizedString(@"Export to .zephyr.subs", nil)];
	[label_servers setStringValue:AILocalizedString(@"Servers:", nil)];
	[[[[tableView_servers tableColumns] objectAtIndex:0] headerCell] setStringValue:AILocalizedString(@"Server", "Header of the Zephyr server list column in the account preferences")];
	[label_hostManager setStringValue:AILocalizedString(@"Host Manager:", nil)];
	[checkBox_launchZhm setTitle:AILocalizedString(@"Use internal host manager", nil)];
}

@end
