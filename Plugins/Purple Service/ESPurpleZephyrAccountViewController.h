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

#import "PurpleAccountViewController.h"

@interface ESPurpleZephyrAccountViewController : PurpleAccountViewController {
	IBOutlet	NSButton	*checkBox_exportAnyone;
	IBOutlet	NSButton	*checkBox_exportSubs;
	IBOutlet	NSButton	*checkBox_launchZhm;
	IBOutlet	NSTextField	*textField_exposure;
	IBOutlet	NSTextField	*textField_encoding;
	IBOutlet	NSTableView	*tableView_servers;
	IBOutlet	NSSegmentedControl *button_addOrRemoveServer;

	IBOutlet	NSTextField	*label_kerberosInfo;
	IBOutlet	NSTextField	*label_exposure;
	IBOutlet	NSTextField	*label_encoding;
	IBOutlet	NSTextField	*label_export;
	IBOutlet	NSTextField	*label_servers;
	IBOutlet	NSTextField	*label_hostManager;
}

- (IBAction)addOrRemoveRowToServerList:(id)sender;
- (void)addRowToServerList;
- (void)removeSelectedRowFromServerList;

@end
