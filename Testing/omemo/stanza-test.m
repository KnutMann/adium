/* Does the stanza look the way other OMEMO clients expect, and does it open again?
 *
 * What is checked here is the XML work itself, against the real xmlnode out of libpurple,
 * because that is exactly where a formatting fault hides: it compiles, it runs, something comes
 * out that looks like a stanza, and the other side shows nothing and says nothing.
 *
 * Under particular scrutiny:
 *   - the plain text has to be GONE, all of it, not only the body;
 *   - anything not on the short list of the harmless has to disappear, including elements
 *     nobody thought of;
 *   - the fallback body for clients without OMEMO has to be there, or they see an empty line;
 *   - while reading, the fallback body has to disappear and the real text take its place.
 */
#import <Foundation/Foundation.h>
#import <libpurple/libpurple.h>
#import "AIOMEMOStore.h"
#import "AIOMEMOStanza.h"

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

#define ALICE	@"alice@example.org"
#define BOB		@"bob@example.org"

static NSString *asText(xmlnode *node)
{
	char *raw = xmlnode_to_str(node, NULL);
	NSString *text = raw ? [NSString stringWithUTF8String:raw] : @"";
	if (raw) g_free(raw);
	return text;
}

static BOOL letTalk(AIOMEMOStore *from, NSString *toJID, AIOMEMOStore *to)
{
	NSNumber *anyPreKey = [[[to preKeys] allKeys] firstObject];
	return [from startSessionWithJID:toJID
							  device:to.deviceIdentifier
						 identityKey:to.identityKey
						signedPreKey:to.signedPreKey
				  signedPreKeyItself:to.signedPreKeyIdentifier
						   signature:to.signedPreKeySignature
							  preKey:[to preKeys][anyPreKey]
						preKeyItself:[anyPreKey unsignedIntValue]];
}

int main(void) { @autoreleasepool {
	NSString *scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:
						 [NSString stringWithFormat:@"adium-omemo-stanza-%d", getpid()]];
	[AIOMEMOStore useDirectory:scratch];

	AIOMEMOStore *alice = [AIOMEMOStore storeForAccount:ALICE];
	AIOMEMOStore *bob = [AIOMEMOStore storeForAccount:BOB];
	check(@"Alice reaches Bob", letTalk(alice, BOB, bob), nil);

	//A message the way Adium otherwise sends one: with a body, a receipt request and a typing
	//notice, plus something that carries content and must therefore not go out in the clear
	NSString *secret = @"The password is Dandelion";

	xmlnode *outgoing = xmlnode_new("message");
	xmlnode_set_attrib(outgoing, "to", [BOB UTF8String]);
	xmlnode_set_attrib(outgoing, "type", "chat");
	xmlnode_set_attrib(outgoing, "id", "abc123");
	xmlnode_insert_data(xmlnode_new_child(outgoing, "body"), [secret UTF8String], -1);
	xmlnode_set_namespace(xmlnode_new_child(outgoing, "request"), "urn:xmpp:receipts");
	xmlnode_set_namespace(xmlnode_new_child(outgoing, "composing"), "http://jabber.org/protocol/chatstates");

	//A quotation repeating the text of the message being answered
	xmlnode *quoted = xmlnode_new_child(outgoing, "reply");
	xmlnode_set_namespace(quoted, "urn:xmpp:reply:0");
	xmlnode_set_attrib(quoted, "to", [BOB UTF8String]);

	//And a formatting that carries the whole text a second time
	xmlnode *formatted = xmlnode_new_child(outgoing, "html");
	xmlnode_set_namespace(formatted, "http://jabber.org/protocol/xhtml-im");
	xmlnode_insert_data(xmlnode_new_child(formatted, "body"), [secret UTF8String], -1);

	NSDictionary *toBob = @{ BOB: @[@(bob.deviceIdentifier)] };
	check(@"The message can be sealed",
		  AIOMEMOSealStanza(outgoing, alice, toBob), nil);

	NSString *onTheWire = asText(outgoing);

	//The most important thing first: nothing of the plain text may be left
	check(@"The plain text is no longer in there",
		  [onTheWire rangeOfString:@"Dandelion"].location == NSNotFound, nil);
	check(@"Nor in the formatting that repeated it",
		  [onTheWire rangeOfString:@"xhtml-im"].location == NSNotFound, nil);
	check(@"And the quotation is gone as well",
		  [onTheWire rangeOfString:@"urn:xmpp:reply"].location == NSNotFound, nil);

	//What is harmless stays
	check(@"The receipt request stays",
		  xmlnode_get_child_with_namespace(outgoing, "request", "urn:xmpp:receipts") != NULL, nil);
	check(@"The typing notice stays",
		  xmlnode_get_child_with_namespace(outgoing, "composing",
										   "http://jabber.org/protocol/chatstates") != NULL, nil);

	//The address and the kind of message survive, or it would arrive nowhere
	check(@"The address is still on it",
		  purple_strequal(xmlnode_get_attrib(outgoing, "to"), [BOB UTF8String]), nil);
	check(@"And so is the kind of message",
		  purple_strequal(xmlnode_get_attrib(outgoing, "type"), "chat"), nil);

	//The shape other clients read
	xmlnode *encrypted = xmlnode_get_child_with_namespace(outgoing, "encrypted", AIOMEMO_NAMESPACE);
	check(@"There is an encrypted element in the right namespace", encrypted != NULL, nil);

	xmlnode *header = encrypted ? xmlnode_get_child(encrypted, "header") : NULL;
	check(@"The header names our device number",
		  AIOMEMONumberIn(header, "sid") == alice.deviceIdentifier, nil);
	check(@"There is an initialisation vector",
		  header && xmlnode_get_child(header, "iv") != NULL, nil);
	check(@"There is a key for Bob's device",
		  header && AIOMEMONumberIn(xmlnode_get_child(header, "key"), "rid") == bob.deviceIdentifier, nil);
	check(@"The first key is marked as opening the session",
		  header && purple_strequal(xmlnode_get_attrib(xmlnode_get_child(header, "key"), "prekey"), "true"),
		  nil);
	check(@"There is a payload",
		  encrypted && xmlnode_get_child(encrypted, "payload") != NULL, nil);

	//The extras, without which it looks bad elsewhere
	check(@"The hint to store it is included",
		  xmlnode_get_child_with_namespace(outgoing, "store", "urn:xmpp:hints") != NULL, nil);
	check(@"It says what it was encrypted with",
		  xmlnode_get_child_with_namespace(outgoing, "encryption", "urn:xmpp:eme:0") != NULL, nil);

	xmlnode *fallback = xmlnode_get_child(outgoing, "body");
	check(@"A fallback body for clients without OMEMO is there", fallback != NULL, nil);

	//And now the other direction: the same stanza, arrived at Bob
	xmlnode *incoming = xmlnode_from_str([onTheWire UTF8String], -1);
	check(@"The stanza can be read back in", incoming != NULL, nil);

	if (incoming) {
		xmlnode_set_attrib(incoming, "from", [[ALICE stringByAppendingString:@"/mac"] UTF8String]);

		check(@"Bob turns it back into a message",
			  AIOMEMOOpenStanza(incoming, bob, ALICE) == AIOMEMOOpenedReadable, nil);

		xmlnode *opened = xmlnode_get_child(incoming, "body");
		char *raw = opened ? xmlnode_get_data(opened) : NULL;
		NSString *read = raw ? [NSString stringWithUTF8String:raw] : nil;
		if (raw) g_free(raw);

		check(@"and the right text is in it", [read isEqualToString:secret], read);

		/* And the body carries jabber:client. That is not a formality: the protocol's parser
		 * skips every child WITHOUT a namespace before it even looks at what the child is.
		 * Without that one line the message is complete, correct and invisible. */
		check(@"The body carries the namespace without which nobody sees it",
			  purple_strequal(xmlnode_get_namespace(opened), "jabber:client"),
			  opened ? [NSString stringWithUTF8String:xmlnode_get_namespace(opened) ?: "none at all"]
					 : @"no body");
		check(@"The fallback body has disappeared",
			  [asText(incoming) rangeOfString:@"doesn't support it"].location == NSNotFound, nil);
		check(@"And so has the encrypted element",
			  xmlnode_get_child_with_namespace(incoming, "encrypted", AIOMEMO_NAMESPACE) == NULL, nil);

		xmlnode_free(incoming);
	}

	//A message to a device we have no session with at all never comes into being
	xmlnode *hopeless = xmlnode_new("message");
	xmlnode_set_attrib(hopeless, "to", "dave@example.org");
	xmlnode_insert_data(xmlnode_new_child(hopeless, "body"), "into the void", -1);
	check(@"Without a session nothing is sealed",
		  !AIOMEMOSealStanza(hopeless, alice, @{ @"dave@example.org": @[@(4711)] }), nil);
	check(@"and the message is left untouched",
		  xmlnode_get_child(hopeless, "body") != NULL, nil);
	xmlnode_free(hopeless);

	/* An encrypted message we can NOT open must not vanish without a trace: either the
	 * sender's fallback body is there, or, if they sent none, one of ours. Vanishing quietly
	 * would be indistinguishable from "never sent", and that is the worse of the two faults. */
	xmlnode *forSomeoneElse = xmlnode_from_str(
		"<message from='c@d' type='chat'>"
		"<encrypted xmlns='" AIOMEMO_NAMESPACE "'><header sid='42'>"
		"<key rid='999'>AAAA</key><iv>AAAAAAAAAAAAAAAA</iv></header>"
		"<payload>AAAA</payload></encrypted></message>", -1);
	check(@"An unreadable message is not swallowed",
		  AIOMEMOOpenStanza(forSomeoneElse, bob, @"c@d") == AIOMEMOOpenedCouldNot, nil);
	check(@"and is given a body if none came with it",
		  xmlnode_get_child(forSomeoneElse, "body") != NULL, nil);
	check(@"which carries the needed namespace as well",
		  purple_strequal(xmlnode_get_namespace(xmlnode_get_child(forSomeoneElse, "body")),
						  "jabber:client"), nil);
	xmlnode_free(forSomeoneElse);

	//If one came with it, the sender's stays
	xmlnode *withFallback = xmlnode_from_str(
		"<message from='c@d' type='chat'><body>I wrote encrypted</body>"
		"<encrypted xmlns='" AIOMEMO_NAMESPACE "'><header sid='42'>"
		"<key rid='999'>AAAA</key><iv>AAAAAAAAAAAAAAAA</iv></header>"
		"<payload>AAAA</payload></encrypted></message>", -1);
	AIOMEMOOpenStanza(withFallback, bob, @"c@d");
	char *kept = xmlnode_get_data(xmlnode_get_child(withFallback, "body"));
	check(@"The sender's fallback body stays if there is one",
		  kept && strcmp(kept, "I wrote encrypted") == 0,
		  kept ? [NSString stringWithUTF8String:kept] : @"none at all");
	if (kept) g_free(kept);
	xmlnode_free(withFallback);

	//A stanza without an encrypted element is left alone
	xmlnode *plain = xmlnode_from_str("<message from='x@y'><body>perfectly ordinary</body></message>", -1);
	check(@"An ordinary message is left alone",
		  AIOMEMOOpenStanza(plain, bob, @"x@y") == AIOMEMOOpenedCouldNot, nil);
	xmlnode_free(plain);

	xmlnode_free(outgoing);
	[[NSFileManager defaultManager] removeItemAtPath:scratch error:NULL];

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
