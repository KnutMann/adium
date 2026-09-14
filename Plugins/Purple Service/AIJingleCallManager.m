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

@implementation AIJingleCallManager {
	NSMutableDictionary<NSString *, AIJingleCallController *> *controllersBySid;
	NSMutableDictionary<NSString *, CBPurpleAccount *> *accountsBySid;
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

	/* A call nobody expected. Until the ringing interface exists, it is taken only
	 * while the hidden switch says so; otherwise it stays untouched and the protocol
	 * answers service-unavailable, exactly as it did before any of this was built. */
	if ([action isEqualToString:@"session-initiate"] &&
		[[NSUserDefaults standardUserDefaults] boolForKey:@"AIJingleAutoAcceptCalls"]) {
		AILog(@"Jingle: auto-accepting incoming call %@ from %@", sid, fromJid);

		AIJingleCallController *incoming =
			[[AIJingleCallController alloc] initAsResponderFrom:[self localJidForAccount:account]
															 to:fromJid];
		incoming.peerFullJid = fromJid;
		incoming.delegate = self;
		controllersBySid[sid] = incoming;
		accountsBySid[sid] = account;
		[incoming handleRemoteJingleElement:jingleXML];
		return YES;
	}

	return NO;
}

//Starting ---------------------------------------------------------------------------------------
#pragma mark Starting

- (AIJingleCallController *)startCallToJid:(NSString *)peerFullJid onAccount:(CBPurpleAccount *)account
{
	AIJingleCallController *controller =
		[[AIJingleCallController alloc] initAsInitiatorFrom:[self localJidForAccount:account]
														 to:peerFullJid];
	controller.peerFullJid = peerFullJid;
	controller.delegate = self;
	controllersBySid[controller.machine.sid] = controller;
	accountsBySid[controller.machine.sid] = account;

	[controller start];
	return controller;
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
}

@end
