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

#import "ESOTRUnknownFingerprintController.h"
#import "ESTextAndButtonsWindowController.h"
#import <Adium/AIAccount.h>
#import <Adium/AIService.h>
#import "AIHTMLDecoder.h"
#import <Adium/AIServiceIcons.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIListContact.h>

#import "AdiumOTREncryption.h"

@interface ESOTRUnknownFingerprintController ()
+ (void)showFingerprintPromptWithMessageString:(NSString *)messageString 
								  acceptButton:(NSString *)acceptButton
									denyButton:(NSString *)denyButton
								  responseInfo:(NSDictionary *)responseInfo;
+ (void)unknownFingerprintResponseInfo:(NSDictionary *)responseInfo wasAccepted:(BOOL)fingerprintAccepted;
@end

@implementation ESOTRUnknownFingerprintController

+ (void)showUnknownFingerprintPromptWithResponseInfo:(NSDictionary *)responseInfo
{
	NSString	*messageString;
	AIAccount	*account = [responseInfo objectForKey:@"AIAccount"];
	NSString	*who = [responseInfo objectForKey:@"who"];
	NSString	*ourHash = [responseInfo objectForKey:@"Our Fingerprint"];
	NSString	*theirHash = [responseInfo objectForKey:@"Their Fingerprint"];
	
	messageString = [NSString stringWithFormat:
		AILocalizedString(@"%@ has sent you (%@) an unknown encryption fingerprint.\n\n"
						  "Fingerprint for you: %@\n\n"
						  "Purported fingerprint for %@: %@\n\n"
						  "Accept this fingerprint as verified?",nil),
		who,
		account.formattedUID,
		ourHash,
		who,
		theirHash];
	
	[self showFingerprintPromptWithMessageString:messageString 
									acceptButton:AILocalizedString(@"Accept",nil)
									  denyButton:AILocalizedString(@"Verify Later",nil)
									responseInfo:responseInfo];
}

+ (void)showVerifyFingerprintPromptWithResponseInfo:(NSDictionary *)responseInfo
{
	NSString	*messageString;
	AIAccount	*account = [responseInfo objectForKey:@"AIAccount"];
	NSString	*who = [responseInfo objectForKey:@"who"];
	NSString	*ourHash = [responseInfo objectForKey:@"Our Fingerprint"];
	NSString	*theirHash = [responseInfo objectForKey:@"Their Fingerprint"];

	messageString = [NSString stringWithFormat:
		AILocalizedString(@"Fingerprint for you (%@): %@\n\n"
						  "Purported fingerprint for %@: %@\n\n"
						  "Is this the verifiably correct fingerprint for %@?",nil),
		account.formattedUID,
		ourHash,
		who,
		theirHash,
		who];

	[self showFingerprintPromptWithMessageString:messageString
									acceptButton:AILocalizedString(@"Yes",nil)
									  denyButton:AILocalizedString(@"No",nil)
									responseInfo:responseInfo];
}

+ (void)showFingerprintPromptWithMessageString:(NSString *)messageString 
								  acceptButton:(NSString *)acceptButton
									denyButton:(NSString *)denyButton
								  responseInfo:(NSDictionary *)responseInfo
{
	AIAccount	*account = [responseInfo objectForKey:@"AIAccount"];

	NSImage		*serviceImage = nil;
	
	if (account) {
		serviceImage = [AIServiceIcons serviceIconForObject:account
													   type:AIServiceIconLarge
												  direction:AIIconNormal];
	}
	
	ESTextAndButtonsWindowController *textAndButtonsWindowController = [[ESTextAndButtonsWindowController alloc] initWithTitle:AILocalizedString(@"OTR Fingerprint Verification",nil)
																												 defaultButton:acceptButton
																											   alternateButton:denyButton
																												   otherButton:AILocalizedString(@"Help", nil)
																												   suppression:nil
																											 withMessageHeader:nil
																													andMessage:[AIHTMLDecoder decodeHTML:messageString]
																														 image:serviceImage
																														target:self
																													  userInfo:responseInfo];
	[textAndButtonsWindowController showOnWindow:nil];
}

/*!
* @brief Window was closed, either by a button being clicked or the user closing it
 */
+ (BOOL)textAndButtonsWindowDidEnd:(NSWindow *)window returnCode:(AITextAndButtonsReturnCode)returnCode suppression:(BOOL)suppression userInfo:(id)userInfo
{
	BOOL	shouldCloseWindow = YES;
	
	if (userInfo && [userInfo objectForKey:@"Their Fingerprint"]) {
		BOOL	fingerprintAccepted;
		
		if (returnCode == AITextAndButtonsOtherReturn) {
			NSString			*who = [userInfo objectForKey:@"who"];
			
			NSString *message = [NSString stringWithFormat:AILocalizedString(@"A fingerprint is a unique identifier "
																			 "that you should use to verify the identity of %@.\n\nTo verify the fingerprint, contact %@ via some "
																			 "other authenticated channel such as the telephone or GPG-signed email. "
																			 "Each of you should tell your fingerprint to the other.", nil),
				who,
				who];
			
			ESTextAndButtonsWindowController *textAndButtonsWindowController = [[ESTextAndButtonsWindowController alloc] initWithTitle:nil
																  defaultButton:nil
																alternateButton:nil
																	otherButton:nil
															  withMessageHeader:AILocalizedString(@"Fingerprint Help", nil)
																	 andMessage:[[NSAttributedString alloc] initWithString:message]
																		 target:self
																	   userInfo:nil];
			[textAndButtonsWindowController showOnWindow:window];
			
			//Don't close the original window if the help button is pressed
			shouldCloseWindow = NO;
			
		} else {
			fingerprintAccepted = ((returnCode == AITextAndButtonsDefaultReturn) ? YES : NO);
			
			[self unknownFingerprintResponseInfo:userInfo
									 wasAccepted:fingerprintAccepted];
		}
	}
	
	return shouldCloseWindow;
}

+ (void)unknownFingerprintResponseInfo:(NSDictionary *)responseInfo wasAccepted:(BOOL)fingerprintAccepted
{
	AIAccount	*account = [responseInfo objectForKey:@"AIAccount"];
	NSString	*who = [responseInfo objectForKey:@"who"];
	NSData		*shownFingerprint = [responseInfo objectForKey:@"Their Fingerprint Bytes"];

	if ([shownFingerprint length] != 20) {
		AILog(@"Warning: ESOTRUnknownFingerprintController: no pinned fingerprint in %@", responseInfo);
		return;
	}

	/* The MASTER context: version 3 keeps the fingerprint list there, one list
	 * for all of a contact's devices, and trust is a property of the key, not
	 * of whichever conversation happens to be up. */
	ConnContext *context = otrl_context_find(otrg_get_userstate(),
											 [who UTF8String], [account.internalObjectID UTF8String],
											 [account.service.serviceCodeUniqueID UTF8String],
											 OTRL_INSTAG_MASTER, 0, NULL, NULL, NULL);

    if (context == NULL) {
		AILog(@"Warning: ESOTRUnknownFingerprintController: NULL context for %@",responseInfo);
		return;
	}

	/* Exactly the key the user read, or nothing. The context's
	 * active_fingerprint at answer time is whatever a re-handshake or a second
	 * device has made active since the window opened; writing trust there would
	 * verify a key nobody ever looked at. If the shown key has meanwhile been
	 * forgotten, the honest answer is to do nothing rather than to guess. */
	Fingerprint *fprint = otrl_context_find_fingerprint(context,
														(unsigned char *)[shownFingerprint bytes],
														0, NULL);

    if (fprint == NULL) {
		AILog(@"Warning: ESOTRUnknownFingerprintController: the shown fingerprint is gone from %@", who);
		return;
	}

    BOOL oldtrust = (fprint->trust && fprint->trust[0]);

    /* See if anything's changed */
    if (fingerprintAccepted != oldtrust) {
		otrl_context_set_trust(fprint, fingerprintAccepted ? "verified" : "");
		//Write the new info to disk, redraw the UI
		otrg_plugin_write_fingerprints();
		otrg_ui_update_keylist();

		/* And the open conversation: its lock reads Unverified until somebody
		 * recomputes it, and the trust that just changed is exactly what it is
		 * computed from. */
		AIListContact	*contact = [adium.contactController contactWithService:account.service
																	   account:account
																		   UID:who];
		AIChat			*chat = (contact ? [adium.chatController existingChatWithContact:contact] : nil);

		if (chat) update_security_details_for_chat(chat);
    }	
}

@end
