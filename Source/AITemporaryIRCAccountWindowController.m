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

#import "AITemporaryIRCAccountWindowController.h"

#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIAccount.h>
#import <Adium/AIService.h>
#import "AIServiceMenu.h"
#import <AIUtilities/AIStringAdditions.h>
#import <AIUtilities/AIStringFormatter.h>

@implementation AITemporaryIRCAccountWindowController


- (void)accountConnected:(NSNotification *)not
{
	[adium.chatController chatWithName:channel
							identifier:nil
							 onAccount:account
					  chatCreationInfo:[NSDictionary dictionaryWithObjectsAndKeys:
										channel, @"channel",
										password, @"password", /* may be nil, so should be last */
										nil]];
	
	[[self window] performClose:nil];
}

@end
