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

#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import "AIStatusController.h"
#import "ESApplescriptabilityController.h"
#import <AIUtilities/AdiumApplescriptRunner.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <Adium/AIAccount.h>
#import <Adium/AIContentMessage.h>
#import "AIHTMLDecoder.h"
#import <Adium/AIStatus.h>

@implementation ESApplescriptabilityController

- (void)controllerDidLoad
{
	applescriptRunner = [[AdiumApplescriptRunner alloc] init];
}


//close
- (void)controllerWillClose
{
	applescriptRunner = nil;
}

#pragma mark Convenience
- (NSArray *)accounts
{
	return (adium.accountController.accounts);
}
- (NSArray *)contacts
{
	return (adium.contactController.allContacts);
}
- (NSArray *)chats
{
	return ([[adium.chatController openChats] allObjects]);
}

#pragma mark Attributes

- (NSTimeInterval)myIdleTime
{
	NSDate  *idleSince = [adium.preferenceController preferenceForKey:@"idleSince" group:GROUP_ACCOUNT_STATUS];
	return (-[idleSince timeIntervalSinceNow]);
}
- (void)setMyIdleTime:(NSTimeInterval)timeInterval
{
	[[NSNotificationCenter defaultCenter] postNotificationName:Adium_RequestSetManualIdleTime	
											  object:(timeInterval ? [NSNumber numberWithDouble:timeInterval] : nil)
											userInfo:nil];
}

- (NSData *)defaultImageData
{
	return ([adium.preferenceController preferenceForKey:KEY_USER_ICON 
													 group:GROUP_ACCOUNT_STATUS]);
			
}
- (void)setDefaultImageData:(NSData *)newDefaultImageData
{
	[adium.preferenceController setPreference:newDefaultImageData
										 forKey:KEY_USER_ICON 
										  group:GROUP_ACCOUNT_STATUS];	
}

- (AIStatus *)myStatus
{
	return adium.statusController.activeStatusState;
}

//Incomplete - make AIStatus scriptable, pass that in
- (void)setMyStatus:(AIStatus *)newStatus
{
	if ([newStatus isKindOfClass:[AIStatus class]]) {
		[adium.statusController setActiveStatusState:newStatus];
	} else {
		NSLog(@"Applescript error: Tried to set status to %@ which is of class %@.  This method expects an object of class %@.",newStatus, NSStringFromClass([newStatus class]),NSStringFromClass([AIStatus class]));
	}
}

- (AIStatusTypeApplescript)myStatusTypeApplescript
{
	return [[self myStatus] statusTypeApplescript];
	
}

- (void)setMyStatusTypeApplescript:(AIStatusTypeApplescript)newStatusType
{
	AIStatus *newStatus = [[self myStatus] mutableCopy];
	
	[newStatus setStatusTypeApplescript:newStatusType];
	[self setMyStatus:newStatus];
}

- (NSString *)myStatusMessageString
{
	return [[self myStatus] statusMessageString];
}

- (void)setMyStatusMessageString:(NSString *)inString
{
	AIStatus *newStatus = [[self myStatus] mutableCopy];
	
	[newStatus setStatusMessageString:inString];
	[self setMyStatus:newStatus];
}

#pragma mark Controller convenience
- (NSObject <AIInterfaceController> *)interfaceController{
    return adium.interfaceController;
}


- (AIChat *)createChatCommand:(NSScriptCommand *)command 
{
	NSDictionary	*evaluatedArguments = [command evaluatedArguments];
	NSString		*UID = [evaluatedArguments objectForKey:@"UID"];
	NSString		*serviceID = [evaluatedArguments objectForKey:@"serviceID"];
	AIListContact   *contact;
	AIChat			*chat = nil;

	contact = [adium.contactController preferredContactWithUID:UID
													andServiceID:serviceID 
										   forSendingContentType:CONTENT_MESSAGE_TYPE];

	if (contact) {
		//Open the chat and set it as active
		chat = [adium.chatController openChatWithContact:contact onPreferredAccount:YES];
		[adium.interfaceController setActiveChat:chat];
	}

	return chat;
}

#pragma mark Running applescripts

/*!
 * @brief Run an AppleScript, optionally calling a function with arguments, and notifying a target/selector with its output when it is done.
 */
- (void)runApplescriptAtPath:(NSString *)path function:(NSString *)function arguments:(NSArray *)arguments notifyingTarget:(id)target selector:(SEL)selector userInfo:(id)userInfo
{
	/* AdiumApplescriptRunner promises its callers exactly one callback, always -- but every caller
	 * reaches it through here, and after -controllerWillClose the runner is nil. A message to nil
	 * would swallow the whole request without a sound, and the delayed content filter waiting on it
	 * would sit there until its watchdog fires, long after the controllers are gone. So keep the
	 * promise ourselves rather than letting it end at the instance variable.
	 */
	if (!applescriptRunner) {
		NSLog(@"ESApplescriptabilityController: asked to run %@ after the runner was torn down; reporting failure", path);

		if (target && selector) {
			/* Never synchronously: the caller registers what it is waiting for only after we return.
			 * The __block variables are cleared inside the block so that target and userInfo are let
			 * go on the main queue, where the block runs -- a block frees what it captured on
			 * whatever thread destroys it, and userInfo can be an NSTextView.
			 */
			__block id	blockTarget = target;
			__block id	blockUserInfo = userInfo;

			[[NSOperationQueue mainQueue] addOperationWithBlock:^{
				[blockTarget performSelector:selector withObject:blockUserInfo withObject:nil];

				blockTarget = nil;
				blockUserInfo = nil;
			}];
		}

		return;
	}

	[applescriptRunner runApplescriptAtPath:path
								   function:function
								  arguments:arguments
							notifyingTarget:target
								   selector:selector
								   userInfo:userInfo];
}

@end
