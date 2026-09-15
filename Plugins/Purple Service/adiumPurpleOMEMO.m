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

#import "adiumPurpleOMEMO.h"
#import "AIOMEMOStore.h"
#import "AIOMEMOMessage.h"
#import "AIOMEMOStanza.h"
#import <Adium/AILoginControllerProtocol.h>

/*
 * OMEMO (XEP-0384), the half that goes on the wire: saying which devices we have, offering the
 * key material other people need in order to write to us, and collecting the same about them.
 *
 * libpurple 2.x knows nothing of any of this, so it happens where the carbons and the fallback
 * handling already happen: on the raw stanza, before the protocol has made anything of it.
 *
 * The one rule that matters more than the rest is that the device list belongs to the account
 * and not to this copy of Adium. Publishing our own number alone would take every other device
 * of the same account off the list, and each of those would notice only by quietly ceasing to
 * receive anything. So the list is always read before it is written, and what goes back is
 * what was there plus ourselves.
 */

#define NS_OMEMO			"eu.siacs.conversations.axolotl"
#define NODE_DEVICELIST		"eu.siacs.conversations.axolotl.devicelist"
#define NODE_BUNDLES		"eu.siacs.conversations.axolotl.bundles"
#define NS_PUBSUB			"http://jabber.org/protocol/pubsub"
#define NS_PUBSUB_EVENT		"http://jabber.org/protocol/pubsub#event"
#define NS_PUBSUB_OWNER		"http://jabber.org/protocol/pubsub#owner"
#define NS_PUBSUB_ERRORS	"http://jabber.org/protocol/pubsub#errors"
#define NS_DATA				"jabber:x:data"
#define NS_HINTS			"urn:xmpp:hints"
#define NS_EME				"urn:xmpp:eme:0"

/*! @brief Posted when a conversation becomes able to encrypt, or stops being able to */
NSString *const AIOMEMOReadinessChangedNotification = @"AIOMEMOReadinessChanged";

static int adium_purple_omemo_handle;

/*
 * What we are waiting for an answer about. The jabber protocol keeps its own table of pending
 * requests and does not share it, so, as everywhere else in here, the identifier we put on the
 * request is how we recognise the reply.
 */
static NSMutableDictionary *whatWeAsked = nil;		//iq id -> @{@"kind": ..., @"jid": ..., @"device": ...}
#define ASKED_OWN_LIST		@"ownList"
#define ASKED_THEIR_LIST	@"theirList"
#define ASKED_PUBLISH		@"publish"
#define ASKED_CONFIGURE		@"configure"
#define ASKED_BUNDLE		@"bundle"

//What each contact has told us, per account: "account|jid" -> array of device numbers
static NSMutableDictionary *devicesOfContacts = nil;

/*
 * Whose conversations we encrypt: "account|jid" present means yes.
 *
 * Kept on disk, because a decision to encrypt is a decision about a person and not about this
 * run of the application. Quietly going back to the clear after a restart is the sort of thing
 * nobody notices until it matters.
 */
static NSMutableSet *encryptingWith = nil;

//Devices we have already asked about, so a busy conversation asks once rather than each time
static NSMutableSet *bundlesAlreadyAsked = nil;

/*
 * Messages held back because there was nothing to encrypt them with yet. Sending them in the
 * clear instead would be the worst possible answer: the user asked for encryption, the window
 * would show it was sent, and the message would be readable by the server. So they wait, and
 * are let go the moment a session exists.
 */
static NSMutableDictionary *waitingToBeSent = nil;		//"account|jid" -> array of xmlnode copies

#pragma mark Small conveniences

static PurplePlugin *omemo_jabber_prpl(void)
{
	return purple_find_prpl("prpl-jabber");
}

static BOOL omemo_is_jabber(PurpleAccount *account)
{
	return account && purple_strequal(purple_account_get_protocol_id(account), "prpl-jabber");
}

/*!
 * @brief An address without its resource, lowercased, which is how OMEMO names a person
 */
static NSString *omemo_bare_jid(NSString *jid)
{
	if (!jid) return nil;

	NSRange slash = [jid rangeOfString:@"/"];
	if (slash.location != NSNotFound)
		jid = [jid substringToIndex:slash.location];

	return [jid lowercaseString];
}

static NSString *omemo_own_jid(PurpleAccount *account)
{
	const char *username = purple_account_get_username(account);
	return username ? omemo_bare_jid([NSString stringWithUTF8String:username]) : nil;
}

static AIOMEMOStore *omemo_store(PurpleAccount *account)
{
	NSString *own = omemo_own_jid(account);
	return own ? [AIOMEMOStore storeForAccount:own] : nil;
}

/*!
 * @brief Where the list of encrypted conversations is kept
 */
static NSString *omemo_choices_path(void)
{
	return [[[adium.loginController userDirectory] stringByAppendingPathComponent:@"OMEMO"]
			stringByAppendingPathComponent:@"encrypting.plist"];
}

static void omemo_remember_choices(void)
{
	[[encryptingWith allObjects] writeToFile:omemo_choices_path() atomically:YES];
}

static void omemo_recall_choices(void)
{
	NSArray *saved = [NSArray arrayWithContentsOfFile:omemo_choices_path()];
	if (saved) [encryptingWith addObjectsFromArray:saved];
}

static NSString *omemo_contact_key(PurpleAccount *account, NSString *bareJID)
{
	return [NSString stringWithFormat:@"%s|%@", purple_account_get_username(account), bareJID];
}

/*!
 * @brief Put a stanza on the wire the way everything else here does
 *
 * The protocol's own sender sits on this signal at the lowest priority, so emitting it is the
 * sanctioned way in rather than a trick.
 */
static void omemo_send(PurpleConnection *gc, xmlnode *stanza)
{
	PurplePlugin *jabber = omemo_jabber_prpl();
	if (!jabber || !stanza) {
		if (stanza) xmlnode_free(stanza);
		return;
	}

	purple_signal_emit(jabber, "jabber-sending-xmlnode", gc, &stanza);
	if (stanza) xmlnode_free(stanza);
}



static NSString *omemo_next_identifier(NSString *kind)
{
	static unsigned long sequence = 0;
	return [NSString stringWithFormat:@"adium-omemo-%@-%lu", kind, sequence++];
}

/*!
 * @brief The publish options that let anybody read what we publish
 *
 * Without these a server may make the node readable only by people already subscribed to our
 * presence, and somebody who wants to write to us for the first time is exactly somebody who
 * cannot read it yet.
 */
static void omemo_fill_form(xmlnode *form, const char *purpose)
{
	xmlnode_set_namespace(form, NS_DATA);
	xmlnode_set_attrib(form, "type", "submit");

	struct { const char *name; const char *type; const char *value; } fields[] = {
		{ "FORM_TYPE", "hidden", purpose },
		{ "pubsub#persist_items", NULL, "true" },
		{ "pubsub#access_model", NULL, "open" }
	};

	for (int index = 0; index < 3; index++) {
		xmlnode *field = xmlnode_new_child(form, "field");
		xmlnode_set_attrib(field, "var", fields[index].name);
		if (fields[index].type) xmlnode_set_attrib(field, "type", fields[index].type);
		xmlnode_insert_data(xmlnode_new_child(field, "value"), fields[index].value, -1);
	}
}

static void omemo_add_open_access(xmlnode *pubsub)
{
	omemo_fill_form(xmlnode_new_child(xmlnode_new_child(pubsub, "publish-options"), "x"),
					NS_PUBSUB "#publish-options");
}

/*!
 * @brief Change an existing node so that anybody may read it
 *
 * The options attached to a publish are a condition, not an instruction: if the node is already
 * there with a different access model, the server refuses the publish rather than adjusting the
 * node. That is not a rare corner. Any account that has used OMEMO from another client, and any
 * server that creates the node with its own defaults on first use, lands in exactly that state,
 * and the symptom is that nobody can find our keys while everything looks fine from here.
 */
static void omemo_make_node_open(PurpleConnection *gc, NSString *node, NSDictionary *thenRetry)
{
	NSString *identifier = omemo_next_identifier(@"configure");
	whatWeAsked[identifier] = @{ @"kind": ASKED_CONFIGURE, @"retry": thenRetry ?: @{} };

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "id", [identifier UTF8String]);

	xmlnode *pubsub = xmlnode_new_child(iq, "pubsub");
	xmlnode_set_namespace(pubsub, NS_PUBSUB_OWNER);

	xmlnode *configure = xmlnode_new_child(pubsub, "configure");
	xmlnode_set_attrib(configure, "node", [node UTF8String]);

	omemo_fill_form(xmlnode_new_child(configure, "x"), NS_PUBSUB "#node_config");
	omemo_send(gc, iq);
}

static void omemo_publish_device_list(PurpleConnection *gc, NSArray<NSNumber *> *devices);
static void omemo_publish_bundle(PurpleConnection *gc);
static BOOL omemo_can_write_to(PurpleAccount *account, NSString *bareJID);
static void omemo_get_ready_for(PurpleConnection *gc, NSString *bareJID);

#pragma mark Saying which devices we have

/*!
 * @brief Publish a device list holding exactly these numbers
 */
static void omemo_publish_device_list(PurpleConnection *gc, NSArray<NSNumber *> *devices)
{
	NSString *identifier = omemo_next_identifier(@"publish-list");

	/* Remembered so that a refusal can be answered rather than merely ignored, and so that the
	 * same list can be sent again once the node has been put right. */
	whatWeAsked[identifier] = @{ @"kind": ASKED_PUBLISH,
								 @"node": @NODE_DEVICELIST,
								 @"what": @"list",
								 @"devices": devices ?: @[] };

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "id", [identifier UTF8String]);

	xmlnode *pubsub = xmlnode_new_child(iq, "pubsub");
	xmlnode_set_namespace(pubsub, NS_PUBSUB);

	xmlnode *publish = xmlnode_new_child(pubsub, "publish");
	xmlnode_set_attrib(publish, "node", NODE_DEVICELIST);

	xmlnode *item = xmlnode_new_child(publish, "item");
	xmlnode_set_attrib(item, "id", "current");

	xmlnode *list = xmlnode_new_child(item, "list");
	xmlnode_set_namespace(list, NS_OMEMO);

	for (NSNumber *device in devices) {
		xmlnode *entry = xmlnode_new_child(list, "device");
		xmlnode_set_attrib(entry, "id", [[device stringValue] UTF8String]);
	}

	omemo_add_open_access(pubsub);
	omemo_send(gc, iq);
}

/*!
 * @brief Offer the key material somebody needs in order to write to us for the first time
 */
static void omemo_publish_bundle(PurpleConnection *gc)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	AIOMEMOStore *store = omemo_store(account);
	if (!store) return;

	NSString *node = [NSString stringWithFormat:@"%s:%u", NODE_BUNDLES, store.deviceIdentifier];
	NSString *identifier = omemo_next_identifier(@"publish-bundle");

	whatWeAsked[identifier] = @{ @"kind": ASKED_PUBLISH, @"node": node, @"what": @"bundle" };

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "id", [identifier UTF8String]);

	xmlnode *pubsub = xmlnode_new_child(iq, "pubsub");
	xmlnode_set_namespace(pubsub, NS_PUBSUB);

	xmlnode *publish = xmlnode_new_child(pubsub, "publish");
	xmlnode_set_attrib(publish, "node", [node UTF8String]);

	xmlnode *item = xmlnode_new_child(publish, "item");
	xmlnode_set_attrib(item, "id", "current");

	xmlnode *bundle = xmlnode_new_child(item, "bundle");
	xmlnode_set_namespace(bundle, NS_OMEMO);

	xmlnode *signed_key = xmlnode_new_child(bundle, "signedPreKeyPublic");
	xmlnode_set_attrib(signed_key, "signedPreKeyId",
					   [[@(store.signedPreKeyIdentifier) stringValue] UTF8String]);
	xmlnode_insert_data(signed_key, [[store.signedPreKey base64EncodedStringWithOptions:0] UTF8String], -1);

	xmlnode *signature = xmlnode_new_child(bundle, "signedPreKeySignature");
	xmlnode_insert_data(signature, [[store.signedPreKeySignature base64EncodedStringWithOptions:0] UTF8String], -1);

	xmlnode *identity = xmlnode_new_child(bundle, "identityKey");
	xmlnode_insert_data(identity, [[store.identityKey base64EncodedStringWithOptions:0] UTF8String], -1);

	xmlnode *prekeys = xmlnode_new_child(bundle, "prekeys");
	[[store preKeys] enumerateKeysAndObjectsUsingBlock:^(NSNumber *identifier, NSData *key, BOOL *stop) {
		xmlnode *one = xmlnode_new_child(prekeys, "preKeyPublic");
		xmlnode_set_attrib(one, "preKeyId", [[identifier stringValue] UTF8String]);
		xmlnode_insert_data(one, [[key base64EncodedStringWithOptions:0] UTF8String], -1);
	}];

	omemo_add_open_access(pubsub);
	omemo_send(gc, iq);
}

/*!
 * @brief Ask for a device list, ours or somebody else's
 */
static void omemo_ask_for_device_list(PurpleConnection *gc, NSString *bareJID, NSString *kind)
{
	NSString *identifier = omemo_next_identifier(@"list");

	whatWeAsked[identifier] = @{ @"kind": kind, @"jid": bareJID ?: @"" };

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "get");
	xmlnode_set_attrib(iq, "id", [identifier UTF8String]);
	if (bareJID) xmlnode_set_attrib(iq, "to", [bareJID UTF8String]);

	xmlnode *pubsub = xmlnode_new_child(iq, "pubsub");
	xmlnode_set_namespace(pubsub, NS_PUBSUB);

	xmlnode *items = xmlnode_new_child(pubsub, "items");
	xmlnode_set_attrib(items, "node", NODE_DEVICELIST);
	xmlnode_set_attrib(items, "max_items", "1");

	omemo_send(gc, iq);
}

#pragma mark Reading what comes back

/*!
 * @brief The device numbers inside a list element
 */
static NSArray<NSNumber *> *omemo_devices_in_list(xmlnode *list)
{
	NSMutableArray *devices = [NSMutableArray array];
	if (!list) return devices;

	for (xmlnode *entry = xmlnode_get_child(list, "device"); entry;
		 entry = xmlnode_get_next_twin(entry)) {
		const char *identifier = xmlnode_get_attrib(entry, "id");
		if (!identifier) continue;

		long long number = atoll(identifier);
		//A device number is a positive number that fits where the specification says it fits
		if (number <= 0 || number > INT32_MAX) continue;

		NSNumber *device = @((uint32_t)number);
		if (![devices containsObject:device]) [devices addObject:device];
	}
	return devices;
}

/*!
 * @brief Find the list element wherever it is, in a published item or in an event
 */
static xmlnode *omemo_find_list(xmlnode *within)
{
	if (!within) return NULL;

	xmlnode *items = xmlnode_get_child(within, "items");
	if (!items) return NULL;

	xmlnode *item = xmlnode_get_child(items, "item");
	if (!item) return NULL;

	return xmlnode_get_child_with_namespace(item, "list", NS_OMEMO);
}

/*!
 * @brief Our own list came back: make sure we are on it, and say so if we were not
 */
static void omemo_handle_own_device_list(PurpleConnection *gc, NSArray<NSNumber *> *published)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	AIOMEMOStore *store = omemo_store(account);
	if (!store) return;

	NSNumber *ours = @(store.deviceIdentifier);

	if (![published containsObject:ours]) {
		/* Everything already there is kept. Another device of this account is somebody who
		 * would otherwise stop being written to, and would have no way of noticing. */
		NSMutableArray *complete = [published mutableCopy];
		[complete addObject:ours];
		omemo_publish_device_list(gc, complete);
	}

	omemo_publish_bundle(gc);
}

static void omemo_remember_devices(PurpleAccount *account, NSString *bareJID, NSArray<NSNumber *> *devices)
{
	devicesOfContacts[omemo_contact_key(account, bareJID)] = devices;
}

NSArray<NSNumber *> *omemoDevicesForContact(PurpleAccount *account, NSString *bareJID)
{
	NSArray *known = devicesOfContacts[omemo_contact_key(account, omemo_bare_jid(bareJID))];
	return known ?: @[];
}

void omemoAskAboutContact(PurpleAccount *account, NSString *bareJID)
{
	PurpleConnection *gc = purple_account_get_connection(account);
	if (!gc || !omemo_is_jabber(account)) return;

	omemo_ask_for_device_list(gc, omemo_bare_jid(bareJID), ASKED_THEIR_LIST);
}

BOOL omemoIsEncryptingWith(PurpleAccount *account, NSString *bareJID)
{
	return [encryptingWith containsObject:omemo_contact_key(account, omemo_bare_jid(bareJID))];
}

void omemoSetEncrypting(PurpleAccount *account, NSString *bareJID, BOOL encrypting)
{
	NSString *who = omemo_bare_jid(bareJID);
	NSString *key = omemo_contact_key(account, who);

	if (!encrypting) {
		[encryptingWith removeObject:key];
		omemo_remember_choices();
		return;
	}

	[encryptingWith addObject:key];
	omemo_remember_choices();

	//Start collecting what is needed now, so the first message does not have to wait for all of it
	PurpleConnection *gc = purple_account_get_connection(account);
	if (gc && omemo_is_jabber(account))
		omemo_get_ready_for(gc, who);
}

BOOL omemoIsReadyFor(PurpleAccount *account, NSString *bareJID)
{
	return omemo_can_write_to(account, omemo_bare_jid(bareJID));
}

#pragma mark Asking for the key material of one device

/*!
 * @brief Ask for one device's bundle, unless we have already asked
 */
static void omemo_fetch_bundle(PurpleConnection *gc, NSString *bareJID, uint32_t device)
{
	NSString *already = [NSString stringWithFormat:@"%@ %u", bareJID, device];
	if ([bundlesAlreadyAsked containsObject:already]) return;
	[bundlesAlreadyAsked addObject:already];

	NSString *identifier = omemo_next_identifier(@"bundle");
	whatWeAsked[identifier] = @{ @"kind": ASKED_BUNDLE, @"jid": bareJID, @"device": @(device) };

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "get");
	xmlnode_set_attrib(iq, "id", [identifier UTF8String]);
	xmlnode_set_attrib(iq, "to", [bareJID UTF8String]);

	xmlnode *pubsub = xmlnode_new_child(iq, "pubsub");
	xmlnode_set_namespace(pubsub, NS_PUBSUB);

	xmlnode *items = xmlnode_new_child(pubsub, "items");
	xmlnode_set_attrib(items, "node",
					   [[NSString stringWithFormat:@"%s:%u", NODE_BUNDLES, device] UTF8String]);
	xmlnode_set_attrib(items, "max_items", "1");

	omemo_send(gc, iq);
}

/*!
 * @brief Build a session from a bundle that came back
 *
 * The one time key is chosen at random rather than taken from the front, because everybody
 * writing to this person is reading the same hundred keys and taking the first would have them
 * all collide on it.
 */
static BOOL omemo_use_bundle(PurpleConnection *gc, NSString *bareJID, uint32_t device, xmlnode *bundle)
{
	AIOMEMOStore *store = omemo_store(purple_connection_get_account(gc));
	if (!store || !bundle) return NO;

	xmlnode *signedKey = xmlnode_get_child(bundle, "signedPreKeyPublic");
	NSData *signedPreKey = AIOMEMOBase64In(signedKey);
	NSData *signature = AIOMEMOBase64In(xmlnode_get_child(bundle, "signedPreKeySignature"));
	NSData *identity = AIOMEMOBase64In(xmlnode_get_child(bundle, "identityKey"));
	uint32_t signedIdentifier = AIOMEMONumberIn(signedKey, "signedPreKeyId");

	NSMutableArray *offered = [NSMutableArray array];
	xmlnode *prekeys = xmlnode_get_child(bundle, "prekeys");
	for (xmlnode *one = xmlnode_get_child(prekeys, "preKeyPublic"); one;
		 one = xmlnode_get_next_twin(one)) {
		uint32_t identifier = AIOMEMONumberIn(one, "preKeyId");
		NSData *key = AIOMEMOBase64In(one);
		if (identifier && key) [offered addObject:@{ @"id": @(identifier), @"key": key }];
	}

	if (!signedPreKey || !signature || !identity || !signedIdentifier || ![offered count])
		return NO;

	NSDictionary *chosen = offered[arc4random_uniform((uint32_t)[offered count])];

	return [store startSessionWithJID:bareJID
							   device:device
						  identityKey:identity
						 signedPreKey:signedPreKey
				   signedPreKeyItself:signedIdentifier
							signature:signature
							   preKey:chosen[@"key"]
						 preKeyItself:[chosen[@"id"] unsignedIntValue]];
}

#pragma mark Reading an encrypted message



#pragma mark Sending an encrypted message

/*!
 * @brief Everything we should write a copy to: their devices and our own others
 */
static NSDictionary *omemo_recipients(PurpleAccount *account, NSString *bareJID)
{
	NSMutableDictionary *everyone = [NSMutableDictionary dictionary];

	NSArray *theirs = omemoDevicesForContact(account, bareJID);
	if ([theirs count]) everyone[bareJID] = theirs;

	/* Our own other devices belong in here too, or the conversation shows up on them with our
	 * own half of it missing, which looks exactly like messages having been lost. */
	NSString *own = omemo_own_jid(account);
	NSArray *ours = omemoDevicesForContact(account, own);
	if ([ours count] && ![own isEqualToString:bareJID]) everyone[own] = ours;

	return everyone;
}

/*!
 * @brief Do we hold a session with at least one device of this person?
 */
static BOOL omemo_can_write_to(PurpleAccount *account, NSString *bareJID)
{
	AIOMEMOStore *store = omemo_store(account);
	if (!store) return NO;

	NSDictionary *everyone = omemo_recipients(account, bareJID);

	for (NSString *jid in everyone)
		for (NSNumber *device in everyone[jid])
			if ([store hasSessionWithJID:jid device:[device unsignedIntValue]])
				return YES;

	return NO;
}

/*!
 * @brief Ask for whatever is still missing before we can write to somebody
 */
static void omemo_get_ready_for(PurpleConnection *gc, NSString *bareJID)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	AIOMEMOStore *store = omemo_store(account);
	if (!store) return;

	if (![omemoDevicesForContact(account, bareJID) count])
		omemo_ask_for_device_list(gc, bareJID, ASKED_THEIR_LIST);

	NSDictionary *everyone = omemo_recipients(account, bareJID);
	for (NSString *jid in everyone) {
		for (NSNumber *device in everyone[jid]) {
			uint32_t number = [device unsignedIntValue];
			if (jid == store.account && number == store.deviceIdentifier) continue;
			if ([store hasSessionWithJID:jid device:number]) continue;

			omemo_fetch_bundle(gc, jid, number);
		}
	}
}


#pragma mark Holding messages back until there is something to encrypt them with

/*!
 * @brief Tell the conversation that a message could not be sent
 *
 * Said in the window rather than swallowed, because the alternative is a message that the user
 * believes has gone and that never will.
 */
static void omemo_say_it_failed(PurpleConnection *gc, NSString *bareJID, const char *why)
{
	PurpleConversation *conversation =
		purple_find_conversation_with_account(PURPLE_CONV_TYPE_IM, [bareJID UTF8String],
											  purple_connection_get_account(gc));
	if (conversation)
		purple_conversation_write(conversation, NULL, why, PURPLE_MESSAGE_ERROR, time(NULL));
}

/*!
 * @brief Say that a conversation's ability to encrypt has changed
 *
 * The padlock is drawn from that, and nothing else would tell it when the other side's keys
 * finally arrived.
 */
static void omemo_readiness_changed(PurpleAccount *account, NSString *bareJID)
{
	NSDictionary *which = @{ @"account": [NSString stringWithUTF8String:purple_account_get_username(account)],
							 @"contact": bareJID };

	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:AIOMEMOReadinessChangedNotification
															object:nil
														  userInfo:which];
	});
}

/*!
 * @brief Let go of everything held for one person, now that we can encrypt to them
 */
static void omemo_release_waiting(PurpleConnection *gc, NSString *bareJID)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	NSString *key = omemo_contact_key(account, bareJID);

	NSArray *held = waitingToBeSent[key];
	if (![held count]) return;

	[waitingToBeSent removeObjectForKey:key];

	for (NSValue *one in held) {
		xmlnode *stanza = [one pointerValue];

		if (AIOMEMOSealStanza(stanza, omemo_store(account), omemo_recipients(account, bareJID)))
			omemo_send(gc, stanza);
		else {
			omemo_say_it_failed(gc, bareJID,
								"This message was not sent: it could not be encrypted, and "
								"sending it unencrypted was not what you asked for.");
			xmlnode_free(stanza);
		}
	}
}

/*!
 * @brief Give up on anything still held for one person
 */
static gboolean omemo_stop_waiting(gpointer data)
{
	NSString *key = (__bridge_transfer NSString *)data;

	NSArray *held = waitingToBeSent[key];
	if ([held count]) {
		[waitingToBeSent removeObjectForKey:key];
		for (NSValue *one in held)
			xmlnode_free([one pointerValue]);

		NSRange bar = [key rangeOfString:@"|"];
		if (bar.location != NSNotFound) {
			NSString *who = [key substringFromIndex:(bar.location + 1)];
			PurpleAccount *account = purple_accounts_find([[key substringToIndex:bar.location] UTF8String],
														  "prpl-jabber");
			PurpleConnection *gc = account ? purple_account_get_connection(account) : NULL;
			if (gc)
				omemo_say_it_failed(gc, who,
									"This message was not sent: the other side published no keys "
									"to encrypt it with.");
		}
	}
	return FALSE;		//once only
}

static void omemo_hold_back(PurpleConnection *gc, xmlnode *stanza, NSString *bareJID)
{
	NSString *key = omemo_contact_key(purple_connection_get_account(gc), bareJID);

	NSMutableArray *held = waitingToBeSent[key];
	if (!held) {
		held = [NSMutableArray array];
		waitingToBeSent[key] = held;

		/* Not held for ever. Somebody who has never published a bundle is not going to start
		 * because we waited longer, and the user deserves to be told rather than left guessing. */
		purple_timeout_add_seconds(20, omemo_stop_waiting, (__bridge_retained void *)key);
	}

	[held addObject:[NSValue valueWithPointer:xmlnode_copy(stanza)]];
	omemo_get_ready_for(gc, bareJID);
}

#pragma mark On the wire

static gboolean omemo_sending_xmlnode_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	if (!packet || !*packet) return FALSE;

	xmlnode *stanza = *packet;
	PurpleAccount *account = purple_connection_get_account(gc);
	if (!omemo_is_jabber(account)) return FALSE;
	if (!purple_strequal(stanza->name, "message")) return FALSE;

	//Already ours, on its way out for the second time
	if (xmlnode_get_child_with_namespace(stanza, "encrypted", NS_OMEMO)) return FALSE;

	/* Only messages with something to read in them. A receipt, a chat state or a reaction
	 * carries no text, and in this older form of OMEMO none of those are encrypted by anybody,
	 * so encrypting ours would simply make them unreadable to every other client. */
	if (!xmlnode_get_child(stanza, "body")) return FALSE;

	const char *to = xmlnode_get_attrib(stanza, "to");
	if (!to) return FALSE;

	NSString *who = omemo_bare_jid([NSString stringWithUTF8String:to]);
	if (![encryptingWith containsObject:omemo_contact_key(account, who)]) return FALSE;

	if (omemo_can_write_to(account, who)) {
		if (AIOMEMOSealStanza(stanza, omemo_store(account), omemo_recipients(account, who)))
			return FALSE;		//Carry on, now encrypted
	}

	/* Nothing to encrypt with yet. The message waits rather than going out in the clear, which
	 * is the one outcome the user definitely did not ask for. */
	omemo_hold_back(gc, stanza, who);

	xmlnode_free(stanza);
	*packet = NULL;
	return TRUE;
}

static gboolean omemo_receiving_xmlnode_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	if (!packet || !*packet) return FALSE;

	xmlnode *stanza = *packet;
	PurpleAccount *account = purple_connection_get_account(gc);
	if (!omemo_is_jabber(account)) return FALSE;

	const char *name = stanza->name;

	/* An answer to something we asked. The reply carries the identifier we chose, which is the
	 * only thread we have back to the question. */
	if (purple_strequal(name, "iq")) {
		const char *identifier = xmlnode_get_attrib(stanza, "id");
		if (!identifier) return FALSE;

		NSDictionary *asked = whatWeAsked[[NSString stringWithUTF8String:identifier]];
		if (!asked) return FALSE;

		[whatWeAsked removeObjectForKey:[NSString stringWithUTF8String:identifier]];

		const char *type = xmlnode_get_attrib(stanza, "type");
		BOOL worked = purple_strequal(type, "result");
		NSString *kind = asked[@"kind"];

		if ([kind isEqualToString:ASKED_PUBLISH]) {
			/* Only now is the bundle really out there. Clearing the mark when the stanza was
			 * merely handed to the socket would mean a refused bundle is never sent again, and
			 * the one time keys we offer would stay ones we no longer hold. */
			if (worked && [asked[@"what"] isEqualToString:@"bundle"])
				omemo_store(account).bundleNeedsPublishing = NO;

			/* A publish that was refused because the node is already there with a different
			 * access model is the one refusal worth acting on: the node is put right and the
			 * same thing published again. Everything else is left alone, because a server that
			 * will not take our keys at all is not something a retry improves. */
			xmlnode *error = xmlnode_get_child(stanza, "error");
			BOOL nodeIsWrong = error && xmlnode_get_child_with_namespace(error, "precondition-not-met",
																		NS_PUBSUB_ERRORS);
			if (!worked && nodeIsWrong)
				omemo_make_node_open(gc, asked[@"node"], asked);

		} else if ([kind isEqualToString:ASKED_CONFIGURE]) {
			NSDictionary *retry = asked[@"retry"];

			if (worked && [retry[@"what"] isEqualToString:@"list"])
				omemo_publish_device_list(gc, retry[@"devices"]);
			else if (worked && [retry[@"what"] isEqualToString:@"bundle"])
				omemo_publish_bundle(gc);

		} else if ([kind isEqualToString:ASKED_BUNDLE]) {
			NSString *who = asked[@"jid"];

			if (worked) {
				xmlnode *pubsub = xmlnode_get_child_with_namespace(stanza, "pubsub", NS_PUBSUB);
				xmlnode *items = pubsub ? xmlnode_get_child(pubsub, "items") : NULL;
				xmlnode *item = items ? xmlnode_get_child(items, "item") : NULL;
				xmlnode *bundle = item ? xmlnode_get_child_with_namespace(item, "bundle", NS_OMEMO) : NULL;

				omemo_use_bundle(gc, who, [asked[@"device"] unsignedIntValue], bundle);
			}

			/* Whether that worked or not, anything held for this person is dealt with now: if a
			 * session came of it the messages go, and if none did they are refused rather than
			 * left waiting for a device that has nothing to offer. */
			if (omemo_can_write_to(account, who)) {
				omemo_release_waiting(gc, who);
				omemo_readiness_changed(account, who);
			}

		} else {
			/* A node that does not exist is the ordinary answer for somebody who has never used
			 * OMEMO, and for ourselves before the first time. It is not a failure, it means the
			 * list is empty, and for our own list it means we are the first entry on it. */
			NSArray *devices = @[];
			if (worked) {
				xmlnode *pubsub = xmlnode_get_child_with_namespace(stanza, "pubsub", NS_PUBSUB);
				devices = omemo_devices_in_list(omemo_find_list(pubsub));
			}

			if ([kind isEqualToString:ASKED_OWN_LIST]) {
				omemo_handle_own_device_list(gc, devices);
			} else {
				omemo_remember_devices(account, asked[@"jid"], devices);

				//Now that we know which devices there are, we can ask each of them for its keys
				if ([waitingToBeSent[omemo_contact_key(account, asked[@"jid"])] count])
					omemo_get_ready_for(gc, asked[@"jid"]);
			}
		}

		//Handled here and nowhere else: nothing in the protocol asked for it
		xmlnode_free(stanza);
		*packet = NULL;
		return TRUE;
	}

	if (purple_strequal(name, "message")) {
		/* An encrypted message is turned back into an ordinary one here, so that everything
		 * downstream needs to know nothing about OMEMO at all. */
		xmlnode *encrypted = xmlnode_get_child_with_namespace(stanza, "encrypted", NS_OMEMO);
		if (encrypted) {
			AIOMEMOStore *store = omemo_store(account);
			const char *from = xmlnode_get_attrib(stanza, "from");
			NSString *sender = from ? omemo_bare_jid([NSString stringWithUTF8String:from]) : nil;

			/* Somebody wrote to us encrypted, so from here on we answer in kind. Replying in the
			 * clear to an encrypted message is the more surprising of the two, and it undoes
			 * what the other side asked for without saying so. */
			if (sender && ![sender isEqualToString:omemo_own_jid(account)]) {
				[encryptingWith addObject:omemo_contact_key(account, sender)];
				omemo_remember_choices();
			}

			BOOL readable = sender && AIOMEMOOpenStanza(stanza, store, sender);

			/* A one time key of ours may have been spent opening this, so what we published no
			 * longer matches what we hold and has to go out again. */
			if (store.bundleNeedsPublishing)
				omemo_publish_bundle(gc);

			if (readable)
				return FALSE;		//Carry on as the ordinary message it now is

			xmlnode_free(stanza);
			*packet = NULL;
			return TRUE;
		}

		/* Somebody's list changed and the server is telling us. This arrives unasked for anybody
		 * whose presence we see, which is how a new device of a contact becomes known without us
		 * asking again. */
		xmlnode *event = xmlnode_get_child_with_namespace(stanza, "event", NS_PUBSUB_EVENT);
		if (!event) return FALSE;

		xmlnode *items = xmlnode_get_child(event, "items");
		if (!purple_strequal(xmlnode_get_attrib(items, "node"), NODE_DEVICELIST)) return FALSE;

		const char *from = xmlnode_get_attrib(stanza, "from");
		if (!from) return FALSE;

		NSString *who = omemo_bare_jid([NSString stringWithUTF8String:from]);
		NSArray *devices = omemo_devices_in_list(omemo_find_list(event));

		if ([who isEqualToString:omemo_own_jid(account)]) {
			/* Our own list, changed by one of our other devices. If we have fallen off it, we
			 * put ourselves back rather than silently becoming unreachable. */
			omemo_handle_own_device_list(gc, devices);
		} else {
			omemo_remember_devices(account, who, devices);
		}

		xmlnode_free(stanza);
		*packet = NULL;
		return TRUE;
	}

	return FALSE;
}

static void omemo_signed_on_cb(PurpleConnection *gc, gpointer data)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	if (!omemo_is_jabber(account)) return;

	PurplePlugin *jabber = omemo_jabber_prpl();
	if (!jabber) return;

	//Bound on the first jabber sign-on, when the protocol is certainly registered
	static gboolean hooked = FALSE;
	if (!hooked) {
		hooked = TRUE;
		purple_signal_connect(jabber, "jabber-receiving-xmlnode", &adium_purple_omemo_handle,
							  PURPLE_CALLBACK(omemo_receiving_xmlnode_cb), NULL);
		purple_signal_connect(jabber, "jabber-sending-xmlnode", &adium_purple_omemo_handle,
							  PURPLE_CALLBACK(omemo_sending_xmlnode_cb), NULL);
	}

	/* The key material lives beside the other account data rather than wherever the store
	 * would otherwise guess, and this is the first moment at which anybody knows where that
	 * is. Said once; the store keeps it. */
	static dispatch_once_t placed;
	dispatch_once(&placed, ^{
		[AIOMEMOStore useDirectory:[[adium.loginController userDirectory]
									stringByAppendingPathComponent:@"OMEMO"]];
		omemo_recall_choices();
	});

	AIOMEMOStore *store = omemo_store(account);
	if (!store) return;

	/* Ask before announcing. Publishing our number on its own would replace the list rather
	 * than join it, and every other device of this account would fall off it. */
	omemo_ask_for_device_list(gc, nil, ASKED_OWN_LIST);
}

void configureAdiumPurpleOMEMO(void)
{
	whatWeAsked = [NSMutableDictionary dictionary];
	devicesOfContacts = [NSMutableDictionary dictionary];
	encryptingWith = [NSMutableSet set];
	bundlesAlreadyAsked = [NSMutableSet set];
	waitingToBeSent = [NSMutableDictionary dictionary];

	purple_signal_connect(purple_connections_get_handle(), "signed-on", &adium_purple_omemo_handle,
						  PURPLE_CALLBACK(omemo_signed_on_cb), NULL);
}
