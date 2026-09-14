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

#import "AIJingleCallManager.h"

#import <Adium/AIListContact.h>
#import <libpurple/jabber.h>

/*! @brief A ringing call nobody answered yet: everything needed to take it or turn it away */
@interface AIJinglePendingCall : NSObject
@property (nonatomic, copy) NSString *jingleXML;
@property (nonatomic, copy) NSString *fromJid;
@property (nonatomic, strong) CBPurpleAccount *account;
@end
@implementation AIJinglePendingCall
@end

@implementation AIJingleCallManager {
	NSMutableDictionary<NSString *, AIJingleCallController *> *controllersBySid;
	NSMutableDictionary<NSString *, CBPurpleAccount *> *accountsBySid;
	NSMutableDictionary<NSString *, AIJinglePendingCall *> *pendingBySid;
}

+ (AIJingleCallManager *)sharedManager
{
	static AIJingleCallManager *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [[AIJingleCallManager alloc] init];
	});
	return shared;
}

+ (void)install
{
	adiumPurpleJingleSetHandler([self sharedManager]);
}

- (id)init
{
	if ((self = [super init])) {
		controllersBySid = [NSMutableDictionary dictionary];
		accountsBySid = [NSMutableDictionary dictionary];
		pendingBySid = [NSMutableDictionary dictionary];
	}
	return self;
}

/*! @brief The sid attribute of a jingle element, without parsing the whole thing */
static NSString *sidOfElement(NSString *jingleXML)
{
	NSRange marker = [jingleXML rangeOfString:@"sid=\""];
	if (marker.location == NSNotFound)
		return nil;

	NSUInteger start = marker.location + marker.length;
	NSRange quote = [jingleXML rangeOfString:@"\"" options:0
									   range:NSMakeRange(start, [jingleXML length] - start)];
	return (quote.location == NSNotFound ? nil :
			[jingleXML substringWithRange:NSMakeRange(start, quote.location - start)]);
}

- (NSString *)localJidForAccount:(CBPurpleAccount *)account
{
	PurpleAccount *purpleAccount = accountLookupFromAdiumAccount(account);
	const char *username = (purpleAccount ? purple_account_get_username(purpleAccount) : NULL);
	return (username ? [NSString stringWithUTF8String:username] : @"");
}

//The stream's questions -------------------------------------------------------------------------
#pragma mark The stream's questions

- (BOOL)handleJingleElement:(NSString *)jingleXML
					   from:(NSString *)fromJid
					 action:(NSString *)action
				  onAccount:(CBPurpleAccount *)account
{
	NSString *sid = sidOfElement(jingleXML);
	if (![sid length])
		return NO;

	AIJingleCallController *controller = controllersBySid[sid];
	if (controller) {
		[controller handleRemoteJingleElement:jingleXML];
		return YES;
	}

	//A caller may withdraw while we are still ringing
	AIJinglePendingCall *pending = pendingBySid[sid];
	if (pending) {
		if ([action isEqualToString:@"session-terminate"]) {
			[pendingBySid removeObjectForKey:sid];
			[self.uiDelegate manager:self incomingCallWithdrawn:sid];
		}
		return YES;
	}

	if ([action isEqualToString:@"session-initiate"]) {
		/* The debug switch takes the call at once; otherwise the interface rings.
		 * With neither around, the stanza stays untouched and the protocol answers
		 * service-unavailable, exactly as before any of this was built. */
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AIJingleAutoAcceptCalls"]) {
			AILog(@"Jingle: auto-accepting incoming call %@ from %@", sid, fromJid);
			[self beginIncomingCallWithSid:sid jingleXML:jingleXML from:fromJid
								 onAccount:account withVideo:NO];
			return YES;
		}

		if (self.uiDelegate) {
			AIJinglePendingCall *ringing = [[AIJinglePendingCall alloc] init];
			ringing.jingleXML = jingleXML;
			ringing.fromJid = fromJid;
			ringing.account = account;
			pendingBySid[sid] = ringing;

			[self.uiDelegate manager:self
	   promptForIncomingCallWithSid:sid
								from:fromJid
						   onAccount:account
						 offersVideo:[jingleXML containsString:@"media=\"video\""]];
			return YES;
		}
	}

	return NO;
}

- (AIJingleCallController *)beginIncomingCallWithSid:(NSString *)sid
										   jingleXML:(NSString *)jingleXML
												from:(NSString *)fromJid
										   onAccount:(CBPurpleAccount *)account
										   withVideo:(BOOL)withVideo
{
	AIJingleCallController *incoming =
		[[AIJingleCallController alloc] initAsResponderFrom:[self localJidForAccount:account]
														 to:fromJid];
	incoming.peerFullJid = fromJid;
	incoming.wantsVideo = withVideo;
	incoming.delegate = self;
	controllersBySid[sid] = incoming;
	accountsBySid[sid] = account;

	[self.uiDelegate manager:self callBegan:incoming];
	[incoming handleRemoteJingleElement:jingleXML];
	return incoming;
}

- (AIJingleCallController *)acceptIncomingCallWithSid:(NSString *)sid withVideo:(BOOL)withVideo
{
	AIJinglePendingCall *pending = pendingBySid[sid];
	if (!pending)
		return nil;

	[pendingBySid removeObjectForKey:sid];
	return [self beginIncomingCallWithSid:sid jingleXML:pending.jingleXML from:pending.fromJid
								onAccount:pending.account withVideo:withVideo];
}

- (void)declineIncomingCallWithSid:(NSString *)sid
{
	AIJinglePendingCall *pending = pendingBySid[sid];
	if (!pending)
		return;

	[pendingBySid removeObjectForKey:sid];

	//The initiate was ACKed already; the refusal is a session-terminate of its own
	NSMutableString *safeSid = [sid mutableCopy];
	[safeSid replaceOccurrencesOfString:@"&" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange(0, [safeSid length])];
	[safeSid replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange(0, [safeSid length])];
	[safeSid replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:NSLiteralSearch range:NSMakeRange(0, [safeSid length])];
	NSString *terminate = [NSString stringWithFormat:
		@"<jingle xmlns=\"urn:xmpp:jingle:1\" action=\"session-terminate\" sid=\"%@\">"
		@"<reason><decline/></reason></jingle>", safeSid];

	adiumPurpleJingleSendElement(pending.account, pending.fromJid, terminate);
}

//Starting ---------------------------------------------------------------------------------------
#pragma mark Starting

- (AIJingleCallController *)startCallToJid:(NSString *)peerFullJid
								 onAccount:(CBPurpleAccount *)account
								 withVideo:(BOOL)withVideo
{
	AIJingleCallController *controller =
		[[AIJingleCallController alloc] initAsInitiatorFrom:[self localJidForAccount:account]
														 to:peerFullJid];
	controller.peerFullJid = peerFullJid;
	controller.wantsVideo = withVideo;
	controller.delegate = self;
	controllersBySid[controller.machine.sid] = controller;
	accountsBySid[controller.machine.sid] = account;

	[self.uiDelegate manager:self callBegan:controller];
	[controller start];
	return controller;
}

/*!
 * @brief The full JID of a contact's best resource
 *
 * A Jingle session lives between two full JIDs. The protocol keeps every resource
 * it has seen presence from; the one it would deliver a message to, its first, is
 * the one worth calling. Nil while nobody is signed in there.
 */
- (NSString *)fullJidForContact:(AIListContact *)contact
{
	CBPurpleAccount *adiumAccount = (CBPurpleAccount *)contact.account;
	PurpleAccount *account = accountLookupFromAdiumAccount(adiumAccount);
	PurpleConnection *gc = (account ? purple_account_get_connection(account) : NULL);

	if (!gc || !PURPLE_CONNECTION_IS_CONNECTED(gc))
		return nil;

	JabberStream *js = gc->proto_data;
	JabberBuddy *jb = (js ? jabber_buddy_find(js, [contact.UID UTF8String], FALSE) : NULL);
	JabberBuddyResource *jbr = (jb ? jabber_buddy_find_resource(jb, NULL) : NULL);

	if (!jbr || !jbr->name || !*jbr->name)
		return nil;

	return [NSString stringWithFormat:@"%@/%s", contact.UID, jbr->name];
}

//What a call reports ----------------------------------------------------------------------------
#pragma mark What a call reports

- (void)callController:(AIJingleCallController *)controller sendJingleElement:(NSString *)jingleXML
{
	NSString *sid = controller.machine.sid;
	CBPurpleAccount *account = accountsBySid[sid];

	if (account && [controller.peerFullJid length])
		adiumPurpleJingleSendElement(account, controller.peerFullJid, jingleXML);
}

- (void)callControllerConnected:(AIJingleCallController *)controller
{
	AILog(@"Jingle: call %@ with %@ connected", controller.machine.sid, controller.peerFullJid);
	[self.uiDelegate manager:self callConnected:controller];
}

- (void)callController:(AIJingleCallController *)controller hasRemoteVideoTrack:(RTCVideoTrack *)track
{
	[self.uiDelegate manager:self call:controller hasRemoteVideoTrack:track];
}

- (void)callController:(AIJingleCallController *)controller endedWithReason:(NSString *)reason locally:(BOOL)locally
{
	AILog(@"Jingle: call %@ with %@ ended (%@, %@)", controller.machine.sid, controller.peerFullJid,
		  reason, locally ? @"locally" : @"by the peer");

	NSString *sid = controller.machine.sid;
	if (sid) {
		[controllersBySid removeObjectForKey:sid];
		[accountsBySid removeObjectForKey:sid];
	}
	[self.uiDelegate manager:self call:controller endedWithReason:reason locally:locally];
}

@end
