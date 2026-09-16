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

#import "AMPurpleJabberExternalServices.h"
#import "ESPurpleJabberAccount.h"
#import "AIJingleCallDiagnostics.h"

#import <libpurple/jabber.h>

#define NS_EXTDISCO		"urn:xmpp:extdisco:2"

@interface AMPurpleJabberExternalServices ()
- (void)handleServicesElement:(xmlnode *)servicesElement;
- (void)ask;
- (void)askAgainBeforeAnythingExpires;
@end

@implementation AMPurpleJabberExternalServices

static void AMPurpleJabberExternalServices_received_cb(PurpleConnection *gc, xmlnode **packet, gpointer this)
{
	if (!packet || !*packet)
		return;

	AMPurpleJabberExternalServices *self = this;
	if (purple_account_get_connection([self->account purpleAccount]) != gc ||
		strcmp((*packet)->name, "iq"))
		return;

	const char *idattr = xmlnode_get_attrib(*packet, "id");
	if (!idattr || !self->iqId || strcmp(idattr, [self->iqId UTF8String]))
		return;

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	const char *type = xmlnode_get_attrib(*packet, "type");
	if (type && !strcmp(type, "result")) {
		xmlnode *servicesElement = xmlnode_get_child_with_namespace(*packet, "services", NS_EXTDISCO);
		if (servicesElement)
			[self handleServicesElement:servicesElement];
	}
	//An error answer means a server without the feature; the empty list stands

	xmlnode_free(*packet);
	*packet = NULL;

	[pool release];
}

- (id)initWithAccount:(ESPurpleJabberAccount *)inAccount
{
	if ((self = [super init])) {
		account = inAccount;
		services = [[NSMutableArray alloc] init];

		PurplePlugin *jabber = purple_find_prpl("prpl-jabber");
		PurpleConnection *gc = purple_account_get_connection([account purpleAccount]);
		if (!jabber || !gc) {
			[self release];
			return nil;
		}

		purple_signal_connect(jabber, "jabber-receiving-xmlnode", self,
							  PURPLE_CALLBACK(AMPurpleJabberExternalServices_received_cb), self);
		[self ask];
	}
	return self;
}

/*!
 * @brief Ask the domain what it offers
 *
 * Asked at login and again before the answer goes stale, because a relay's
 * credentials are lent, not given: the one measured here came with ten minutes on
 * it, and a call placed in the eleventh minute carries a password the relay no
 * longer knows. Nothing says so out loud, the relay simply refuses and the call
 * quietly has one way home fewer.
 */
- (void)ask
{
	PurplePlugin *jabber = purple_find_prpl("prpl-jabber");
	PurpleConnection *gc = purple_account_get_connection([account purpleAccount]);
	if (!jabber || !gc)
		return;

	NSRange at = [account.UID rangeOfString:@"@"];
	if (at.location == NSNotFound)
		return;

	static unsigned long sequence = 0;
	[iqId release];
	iqId = [[NSString alloc] initWithFormat:@"adium-extdisco-%lu", sequence++];

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "get");
	xmlnode_set_attrib(iq, "to", [[account.UID substringFromIndex:(at.location + 1)] UTF8String]);
	xmlnode_set_attrib(iq, "id", [iqId UTF8String]);
	xmlnode_set_namespace(xmlnode_new_child(iq, "services"), NS_EXTDISCO);

	purple_signal_emit(jabber, "jabber-sending-xmlnode", gc, &iq);
	if (iq)
		xmlnode_free(iq);
}

- (void)dealloc
{
	purple_signals_disconnect_by_handle(self);
	[services release];
	[iqId release];
	[super dealloc];
}

- (void)handleServicesElement:(xmlnode *)servicesElement
{
	//A fresh answer replaces the old one whole; the host is the authority on its own list
	[services removeAllObjects];

	for (xmlnode *service = xmlnode_get_child(servicesElement, "service"); service;
		 service = xmlnode_get_next_twin(service)) {
		const char *host = xmlnode_get_attrib(service, "host");
		const char *port = xmlnode_get_attrib(service, "port");
		const char *type = xmlnode_get_attrib(service, "type");
		const char *transport = xmlnode_get_attrib(service, "transport");
		const char *username = xmlnode_get_attrib(service, "username");
		const char *password = xmlnode_get_attrib(service, "password");
		const char *expires = xmlnode_get_attrib(service, "expires");

		if (!host || !type)
			continue;

		//The spelling WebRTC's ICE wants
		NSString *url = nil;
		if (!strcmp(type, "stun") || !strcmp(type, "stuns")) {
			url = [NSString stringWithFormat:@"%s:%s%s%s", type, host,
				   (port ? ":" : ""), (port ? port : "")];
		} else if (!strcmp(type, "turn") || !strcmp(type, "turns")) {
			url = [NSString stringWithFormat:@"%s:%s%s%s?transport=%s", type, host,
				   (port ? ":" : ""), (port ? port : ""),
				   (transport ? transport : "udp")];
		} else {
			continue;
		}

		NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObject:url forKey:@"urls"];
		if (username)
			[entry setObject:[NSString stringWithUTF8String:username] forKey:@"username"];
		if (password)
			[entry setObject:[NSString stringWithUTF8String:password] forKey:@"credential"];
		if (expires) {
			NSISO8601DateFormatter *reader = [[[NSISO8601DateFormatter alloc] init] autorelease];
			NSDate *when = [reader dateFromString:[NSString stringWithUTF8String:expires]];
			if (when)
				[entry setObject:when forKey:@"expires"];
		}
		[services addObject:entry];
	}

	AILog(@"%@: %lu ICE servers from the domain", account, (unsigned long)[services count]);

	/* Ask each of them whether it is there at all, and write down what is not.
	 *
	 * Nothing is thrown away over it. A server that ignores this question can
	 * still be the one that carries the call: a relay built to carry and nothing
	 * else may refuse to answer questions about addresses, and losing it costs
	 * far more than keeping a dead address in a list nobody waits on. The answer
	 * is for the person to read in the self test, not for the call to act on. */
	for (NSDictionary *service in [[services copy] autorelease]) {
		NSString *host = nil, *port = nil;
		if (![AIJingleCallDiagnostics host:&host port:&port ofIceURL:service[@"urls"]])
			continue;

		[AIJingleCallDiagnostics probeStunHost:host port:port completion:^(BOOL answered) {
			if (answered)
				return;

			AILog(@"%@: %@ answers nothing", self->account, service[@"urls"]);
		}];
	}

	[self askAgainBeforeAnythingExpires];
}

/*!
 * @brief Ask again shortly before the lent credentials run out
 *
 * XEP-0215 lets a host put a clock on what it hands over, and the one measured
 * here gave ten minutes. Asking once at login therefore buys a working relay for
 * exactly as long as somebody places a call quickly, and nothing at all after
 * that. So the clock is read and the question repeated just before it runs out.
 */
- (void)askAgainBeforeAnythingExpires
{
	NSDate *earliest = nil;
	for (NSDictionary *service in services) {
		NSDate *when = service[@"expires"];
		if (when && (!earliest || [when compare:earliest] == NSOrderedAscending))
			earliest = when;
	}
	if (!earliest)
		return;

	//A little early, and never in a tight loop however odd the answer
	NSTimeInterval seconds = MAX(60.0, [earliest timeIntervalSinceNow] - 30.0);
	AILog(@"%@: asking again in %.0f seconds, before the credentials run out", account, seconds);

	generation++;
	unsigned long mine = generation;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		if (self->generation == mine)
			[self ask];
	});
}

- (NSArray *)iceServerDictionaries
{
	//What has run out is not offered; credentials nobody honours are worse than none
	NSMutableArray *living = [NSMutableArray array];
	for (NSDictionary *service in services) {
		NSDate *when = service[@"expires"];
		if (when && [when timeIntervalSinceNow] <= 0) {
			AILog(@"%@: %@ ran out at %@", account, service[@"urls"], when);
			continue;
		}
		[living addObject:service];
	}
	return living;
}

@end
