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

#import "DCPurpleZephyrJoinChatViewController.h"
#import "DCJoinChatWindowController.h"
#import <Adium/AIAccount.h>

@interface DCPurpleZephyrJoinChatViewController ()
- (void)validateEnteredText;
@end

@implementation DCPurpleZephyrJoinChatViewController

- (NSString *)nibName
{
	return @"DCPurpleZephyrJoinChatView";
}

//The xib is monolingual (English); set all visible strings from code
- (void)awakeFromNib
{
	[label_class setStringValue:AILocalizedString(@"Class:", nil)];
	[label_instance setStringValue:AILocalizedString(@"Instance:", nil)];
	[label_recipient setStringValue:AILocalizedString(@"Recipient:", nil)];
}

- (void)configureForAccount:(AIAccount *)inAccount
{
	[self validateEnteredText];

	[[view window] makeFirstResponder:textField_class];
	
	[super configureForAccount:inAccount];
}

/*
 Zephyr uses "class" "instance" and "recipient".  Instance and Recipient are optional and will become "*" if
 they are not specified; we show this default value automatically for clarity.
 */

- (void)joinChatWithAccount:(AIAccount *)inAccount
{	
	NSString			*class;
	NSString			*instance;
	NSString			*recipient;
	NSDictionary		*chatCreationInfo;
	
	class = [textField_class stringValue];
	instance = [textField_instance stringValue];
	recipient = [textField_recipient stringValue];
	
	if (!instance || ![instance length]) instance = @"*";
	if (!recipient || ![recipient length]) recipient = @"*";
	
	if (class && [class length]) {
		NSString	*name;

		//The chatCreationInfo has keys corresponding to the GHashTable keys and values to match them.
		chatCreationInfo = [NSDictionary dictionaryWithObjectsAndKeys:class,@"class",instance,@"instance",recipient,@"recipient",nil];
		
		name = [NSString stringWithFormat:@"%@,%@,%@",class,instance,recipient];
		
		[self doJoinChatWithName:name
					   onAccount:inAccount
				chatCreationInfo:chatCreationInfo
				invitingContacts:nil
		   withInvitationMessage:nil];
	}
}

//Entered text is changing
- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] == textField_class) {
		[self validateEnteredText];
	}
}

- (void)validateEnteredText
{
	if (delegate)
		[(DCJoinChatWindowController *)delegate setJoinChatEnabled:[textField_class stringValue].length > 0];
}

@end
