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

#import "AIOMEMOStanza.h"
#import "AIOMEMOStore.h"
#import "AIOMEMOMessage.h"

/*
 * Rearranging XML is where a format mistake hides. It compiles, it runs, it produces something
 * that looks like a stanza, and the other client shows nothing and says nothing. So this lives
 * apart from the rest, depending on nothing but the stanza and the key material, and is checked
 * against the real xmlnode in Testing/omemo/stanza-test.sh.
 */

#define NS_HINTS	"urn:xmpp:hints"
#define NS_EME		"urn:xmpp:eme:0"
#define NS_CLIENT	"jabber:client"

/*!
 * @brief Put a body on a message we are handing back to the protocol
 *
 * The namespace is not decoration here, it decides whether the message is seen at all. A stanza
 * that came off the wire has jabber:client on every child, inherited from the stream, and the
 * protocol's parser skips any child that carries no namespace before it ever looks at what the
 * child is. A body built here starts with none, so without this line the message is complete,
 * correct, and silently invisible: the receipt goes out, the ratchet advances, and nothing is
 * ever shown.
 */
static void omemo_give_body(xmlnode *stanza, const char *text)
{
	xmlnode *body = xmlnode_new_child(stanza, "body");
	xmlnode_set_namespace(body, NS_CLIENT);
	xmlnode_insert_data(body, text, -1);
}

#pragma mark Reading values out of a stanza

/*!
 * @brief Read one base64 value out of an element, refusing anything that is not one
 */
NSData *AIOMEMOBase64In(xmlnode *element)
{
	if (!element) return nil;

	char *text = xmlnode_get_data(element);
	if (!text) return nil;

	NSString *encoded = [NSString stringWithUTF8String:text];
	g_free(text);

	//Whitespace inside base64 is allowed and several clients put it there
	return [[NSData alloc] initWithBase64EncodedString:encoded
											   options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

uint32_t AIOMEMONumberIn(xmlnode *element, const char *attribute)
{
	const char *text = element ? xmlnode_get_attrib(element, attribute) : NULL;
	if (!text) return 0;

	long long number = atoll(text);
	return (number > 0 && number <= INT32_MAX) ? (uint32_t)number : 0;
}

/*!
 * @brief Every wrapped key in the header
 *
 * The marker saying a key opens a new session is written as "true" by most clients and as "1"
 * by some, and both mean the same thing. Reading only one of them means the first message from
 * half the ecosystem cannot be opened at all.
 */
static NSArray<AIOMEMOKeyForDevice *> *omemo_keys_in(xmlnode *header)
{
	NSMutableArray *keys = [NSMutableArray array];

	for (xmlnode *key = xmlnode_get_child(header, "key"); key; key = xmlnode_get_next_twin(key)) {
		uint32_t device = AIOMEMONumberIn(key, "rid");
		NSData *wrapped = AIOMEMOBase64In(key);
		if (!device || !wrapped) continue;

		const char *marker = xmlnode_get_attrib(key, "prekey");
		BOOL startsASession = marker && (purple_strequal(marker, "true") || purple_strequal(marker, "1"));

		[keys addObject:[AIOMEMOMessage keyForDevice:device startsASession:startsASession wrapped:wrapped]];
	}
	return keys;
}


#pragma mark Opening and sealing

/*!
 * @brief Turn an encrypted message into the message it was, in place
 *
 * Rewriting the stanza rather than handling it ourselves means everything downstream, the
 * conversation window, the logs, the carbons, the notifications, sees an ordinary message and
 * needs to know nothing about any of this.
 *
 * @return NO when the stanza should be dropped rather than passed on
 */
AIOMEMOOpened AIOMEMOOpenStanza(xmlnode *stanza, AIOMEMOStore *store, NSString *fromBareJID)
{
	if (!store || !fromBareJID) return AIOMEMOOpenedCouldNot;

	xmlnode *encrypted = xmlnode_get_child_with_namespace(stanza, "encrypted", AIOMEMO_NAMESPACE);
	if (!encrypted) return AIOMEMOOpenedCouldNot;

	xmlnode *header = xmlnode_get_child(encrypted, "header");
	uint32_t sender = AIOMEMONumberIn(header, "sid");
	if (!sender) {
		purple_debug_warning("OMEMO", "message from %s has no sender device, leaving it alone\n",
							 [fromBareJID UTF8String]);
		return AIOMEMOOpenedCouldNot;
	}

	NSData *vector = AIOMEMOBase64In(xmlnode_get_child(header, "iv"));
	NSData *payload = AIOMEMOBase64In(xmlnode_get_child(encrypted, "payload"));
	NSArray *keys = omemo_keys_in(header);

	/* Said out loud because the alternative is a message that vanishes. Every number here has
	 * cost somebody an evening at some point: which device wrote, how long the vector is, how
	 * many devices it was addressed to, and whether ours is among them. */
	purple_debug_info("OMEMO", "message from %s device %u: %lu keys, %lu byte vector, "
							   "%lu byte payload, our device is %u\n",
					  [fromBareJID UTF8String], sender, (unsigned long)[keys count],
					  (unsigned long)[vector length], (unsigned long)[payload length],
					  store.deviceIdentifier);

	AIOMEMOTrouble trouble = AIOMEMOTroubleNone;
	NSString *text = [AIOMEMOMessage textFromPayload:(payload ?: [NSData data])
								initialisationVector:vector
												keys:keys
											sentFrom:fromBareJID
											  device:sender
										   withStore:store
											 trouble:&trouble];

	/* Nothing to show is not the same as nothing happened. A message with no payload exists only
	 * to let the ratchet step after a long one sided conversation, and showing an empty line for
	 * it would be worse than silence. */
	if (text && ![text length]) {
		purple_debug_info("OMEMO", "nothing in it to show, which is how a ratchet step looks\n");
		return AIOMEMOOpenedNothingToShow;
	}

	if (!text) {
		purple_debug_warning("OMEMO", "could not open it: %s. Passing it on, so that the sender's "
									  "own fallback line is at least shown\n",
							 [AIOMEMOMessage nameOfTrouble:trouble]);

		/* Most senders attach a line for clients that cannot read this, and passing the message
		 * on shows it. Some attach nothing, and then passing it on is as silent as dropping it
		 * would have been. So if there is nothing to show, we say so ourselves. Whatever else
		 * happens, a message that arrived must leave some trace. */
		if (!xmlnode_get_child(stanza, "body"))
			omemo_give_body(stanza, "[An encrypted message arrived that could not be read. "
									"The sending device may not be known here yet.]");

		return AIOMEMOOpenedCouldNot;
	}

	/* The body that was there is the sender's apology to clients that cannot read this, and it
	 * is now wrong. It goes, and the real text takes its place. */
	xmlnode *body;
	while ((body = xmlnode_get_child(stanza, "body")))
		xmlnode_free(body);

	xmlnode_free(encrypted);
	omemo_give_body(stanza, [text UTF8String]);

	return AIOMEMOOpenedReadable;
}

/*!
 * @brief Replace a message's readable parts with their encrypted form
 *
 * Everything that was in the stanza and is not on the short list below is taken out. That list
 * is deliberately a list of what may stay rather than of what must go: an element nobody
 * thought about is then dropped rather than sent in the clear, and this client sends several
 * that carry content, among them reactions and the marker on a corrected message.
 *
 * @return NO when it could not be encrypted, and the caller must not send it
 */
BOOL AIOMEMOSealStanza(xmlnode *stanza, AIOMEMOStore *store,
					   NSDictionary<NSString *, NSArray<NSNumber *> *> *devicesByJID)
{
	if (!store) return NO;

	xmlnode *body = xmlnode_get_child(stanza, "body");
	if (!body) return NO;

	char *text = xmlnode_get_data(body);
	if (!text) return NO;

	NSString *said = [NSString stringWithUTF8String:text];
	g_free(text);

	AIOMEMOMessage *message = [AIOMEMOMessage encrypting:said
											   withStore:store
											  forDevices:devicesByJID];
	if (!message) return NO;

	/* Out goes everything, and back in comes only what is harmless in the clear. Anything else
	 * would travel beside the encrypted text saying what the conversation is about. */
	static const struct { const char *name; const char *xmlns; } mayStay[] = {
		{ "request",	"urn:xmpp:receipts" },
		{ "markable",	"urn:xmpp:chat-markers:0" },
		{ "origin-id",	"urn:xmpp:sid:0" },
		{ "replace",	"urn:xmpp:message-correct:0" },	//names a message, says nothing about either
		{ "active",		"http://jabber.org/protocol/chatstates" },
		{ "composing",	"http://jabber.org/protocol/chatstates" },
		{ "paused",		"http://jabber.org/protocol/chatstates" },
		{ "inactive",	"http://jabber.org/protocol/chatstates" },
		{ "gone",		"http://jabber.org/protocol/chatstates" },
	};

	NSMutableArray *kept = [NSMutableArray array];
	for (unsigned index = 0; index < sizeof(mayStay) / sizeof(mayStay[0]); index++) {
		xmlnode *one = xmlnode_get_child_with_namespace(stanza, mayStay[index].name, mayStay[index].xmlns);
		if (one) [kept addObject:[NSValue valueWithPointer:xmlnode_copy(one)]];
	}

	/* Only the elements, and the stray text between them. NOT the attributes: libpurple keeps
	 * those as children too, so emptying the child list wholesale takes the address and the
	 * type of the message with it, and what goes out is an encrypted message addressed to
	 * nobody. It looks perfectly well formed while doing it. */
	xmlnode *child = stanza->child;
	while (child) {
		xmlnode *next = child->next;
		if (child->type != XMLNODE_TYPE_ATTRIB)
			xmlnode_free(child);
		child = next;
	}

	xmlnode *encrypted = xmlnode_new_child(stanza, "encrypted");
	xmlnode_set_namespace(encrypted, AIOMEMO_NAMESPACE);

	xmlnode *header = xmlnode_new_child(encrypted, "header");
	xmlnode_set_attrib(header, "sid", [[@(message.sender) stringValue] UTF8String]);

	for (AIOMEMOKeyForDevice *one in message.keys) {
		xmlnode *key = xmlnode_new_child(header, "key");
		xmlnode_set_attrib(key, "rid", [[@(one.device) stringValue] UTF8String]);
		if (one.startsASession) xmlnode_set_attrib(key, "prekey", "true");
		xmlnode_insert_data(key, [[one.wrapped base64EncodedStringWithOptions:0] UTF8String], -1);
	}

	xmlnode_insert_data(xmlnode_new_child(header, "iv"),
						[[message.initialisationVector base64EncodedStringWithOptions:0] UTF8String], -1);
	xmlnode_insert_data(xmlnode_new_child(encrypted, "payload"),
						[[message.payload base64EncodedStringWithOptions:0] UTF8String], -1);

	for (NSValue *held in kept)
		xmlnode_insert_child(stanza, [held pointerValue]);

	/* Told to keep it even though it has no body, or servers that archive by body alone will
	 * drop it, and the conversation will have holes in it on the other devices. */
	xmlnode_set_namespace(xmlnode_new_child(stanza, "store"), NS_HINTS);

	//Says what this is encrypted with, so a client that cannot read it can say so usefully
	xmlnode *which = xmlnode_new_child(stanza, "encryption");
	xmlnode_set_namespace(which, NS_EME);
	xmlnode_set_attrib(which, "namespace", AIOMEMO_NAMESPACE);

	/* And the sentence a client that does not do OMEMO will show instead. Every other client
	 * sends one, and without it such a client shows an empty message and no explanation. */
	xmlnode_insert_data(xmlnode_new_child(stanza, "body"),
						"I sent you an OMEMO encrypted message but your client doesn't support it.", -1);

	return YES;
}
