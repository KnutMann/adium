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

		//Ask the domain once; whatever it names is what calls will use
		NSRange at = [account.UID rangeOfString:@"@"];
		if (at.location != NSNotFound) {
			static unsigned long sequence = 0;
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
	}
	return self;
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
	for (xmlnode *service = xmlnode_get_child(servicesElement, "service"); service;
		 service = xmlnode_get_next_twin(service)) {
		const char *host = xmlnode_get_attrib(service, "host");
		const char *port = xmlnode_get_attrib(service, "port");
		const char *type = xmlnode_get_attrib(service, "type");
		const char *transport = xmlnode_get_attrib(service, "transport");
		const char *username = xmlnode_get_attrib(service, "username");
		const char *password = xmlnode_get_attrib(service, "password");

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
		[services addObject:entry];
	}

	AILog(@"%@: %lu ICE servers from the domain", account, (unsigned long)[services count]);

	/* And now ask each of them whether it is there at all. A host may announce a
	 * server that answers nothing, measured on one that did, and a call which
	 * carries such an address spends seconds knocking on a door nobody opens
	 * before it tries anything else. What does not answer is not offered. */
	for (NSDictionary *service in [[services copy] autorelease]) {
		NSString *host = nil, *port = nil;
		if (![AIJingleCallDiagnostics host:&host port:&port ofIceURL:service[@"urls"]])
			continue;

		[AIJingleCallDiagnostics probeStunHost:host port:port completion:^(BOOL answered) {
			if (answered)
				return;

			AILog(@"%@: dropping %@, it answers nothing", self->account, service[@"urls"]);
			[self->services removeObject:service];
		}];
	}
}

- (NSArray *)iceServerDictionaries
{
	return [[services copy] autorelease];
}

@end
