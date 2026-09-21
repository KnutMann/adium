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

#import <Cocoa/Cocoa.h>

@class AIAccount, AISettingsFormView;

/*!
 * @class AIAccountRegistrationPage
 * @brief Have the service create the account, on a page of its own
 *
 * For a service that registers accounts in band (XMPP does, XEP-0077): a server, a name and a
 * password, and the server makes the account. Opened from the account's own page and slid in over
 * it; on success it slides back out, and the account behind it carries the new name and password.
 *
 * The list of public servers is the one the XMPP Providers project keeps, fetched when the page
 * opens and narrowed to servers that let anyone register from within a client without a captcha,
 * because a captcha is a picture the registration form here cannot show. A server that is not on
 * the list can be typed in.
 */
@interface AIAccountRegistrationPage : NSViewController <NSTableViewDataSource, NSTableViewDelegate> {
	AIAccount				*account;
	AISettingsFormView		*form;

	NSTextField				*serverField;
	NSTextField				*usernameField;
	NSSecureTextField		*passwordField;
	NSButton				*requestButton;
	NSButton				*homepageButton;
	NSProgressIndicator		*spinner;
	NSTextField				*statusLabel;

	NSScrollView			*scrollView;
	NSTableView				*tableView;
	NSArray					*servers;			//One dictionary per server: jid, location, website (may be absent)
	NSURLSessionDataTask	*fetchTask;

	BOOL					 offersServerList;	//Whether this service has public servers to pick from
	BOOL					 loading;			//The list is on its way
	BOOL					 registering;		//A request is out and no answer is in yet
	NSString				*problem;			//What went wrong the last time, or nil
}

- (id)initWithAccount:(AIAccount *)inAccount;

@end
