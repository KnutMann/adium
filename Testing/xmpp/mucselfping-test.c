/* Does Adium read a MUC self-ping answer the way XEP-0410 says, and does it know a 333?
 *
 * The interesting half of MUC Self-Ping is not the ping, it is the reading of the answer, and
 * that reading is counter-intuitive enough that a plain summary of the specification gets it
 * wrong. <item-not-found/> means we are STILL in the room: the ping was answered about an
 * occupant JID that no longer exists because our own nickname changed under us, which is a
 * statement about the nickname and not about the room. <remote-server-timeout/> decides
 * NOTHING and may not cause a rejoin. Only the leftovers, <not-acceptable/> foremost, mean we
 * were removed. Rejoining on the wrong one of these throws away a working room, or sits in a
 * dead one forever.
 *
 * So what is checked here is that table, against the REAL file the application ships, plus the
 * recognition of XEP-0045's status code 333 and the guard that stops a room which refuses
 * every rejoin from being rejoined forever.
 *
 * Needs nothing but the application's own libpurple: no server, no account, no Adium.
 */
#include <glib.h>
#include <stdio.h>
#include <string.h>

#include "AIMUCSelfPingRules.h"

static int failures = 0;

static void check(const char *name, int ok, const char *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name,
	       (!ok && detail) ? "  " : "", (!ok && detail) ? detail : "");
	if (!ok) failures++;
}

static const char *verdictName(AIMUCSelfPingVerdict v)
{
	switch (v) {
		case AIMUCSelfPingVerdictJoined:    return "joined";
		case AIMUCSelfPingVerdictNotJoined: return "not joined";
		case AIMUCSelfPingVerdictUnknown:   return "unknown";
	}
	return "?";
}

static xmlnode *parse(const char *xml)
{
	xmlnode *node = xmlnode_from_str(xml, -1);

	if (node == NULL) {
		printf("FAIL  the test's own stanza would not parse: %s\n", xml);
		failures++;
	}
	return node;
}

/* One error reply, built around a condition, as a service would send it. */
static void checkError(const char *condition, const char *ns, AIMUCSelfPingVerdict want, const char *name)
{
	char	*xml = g_strdup_printf(
				"<iq from='characters@chat.shakespeare.lit/JuliC' id='s2c1' type='error'"
				"    to='juliet@capulet.lit/client'>"
				"  <error type='cancel' by='characters@chat.shakespeare.lit'>"
				"    <%s%s%s%s/>"
				"  </error>"
				"</iq>",
				condition, ns ? " xmlns='" : "", ns ? ns : "", ns ? "'" : "");
	xmlnode	*iq = parse(xml);

	if (iq != NULL) {
		AIMUCSelfPingVerdict got = AIMUCSelfPingVerdictForReply(iq);
		check(name, got == want, verdictName(got));
		xmlnode_free(iq);
	}
	g_free(xml);
}

#define STANZAS "urn:ietf:params:xml:ns:xmpp-stanzas"
#define MUCUSER "http://jabber.org/protocol/muc#user"

int main(void)
{
	xmlnode	*node;
	char	*text;

	printf("MUC Self-Ping (XEP-0410) and MUC status code 333\n\n");

	/* --- The answer to a ping: XEP-0410 section 3.2's own list ------------------------- */

	node = parse("<iq from='characters@chat.shakespeare.lit/JuliC' id='s2c1' type='result'"
	             "    to='juliet@capulet.lit/client'/>");
	if (node) {
		check("A result means we are still in the room",
		      AIMUCSelfPingVerdictForReply(node) == AIMUCSelfPingVerdictJoined,
		      verdictName(AIMUCSelfPingVerdictForReply(node)));
		xmlnode_free(node);
	}

	/* "the client is joined, but the pinged client does not implement XMPP Ping" */
	checkError("service-unavailable", STANZAS, AIMUCSelfPingVerdictJoined,
	           "service-unavailable means joined, our own client just does not answer pings");
	checkError("feature-not-implemented", STANZAS, AIMUCSelfPingVerdictJoined,
	           "feature-not-implemented means joined, for the same reason");

	/* "the client is joined, but the occupant just changed their name". The one everybody
	   gets backwards, including the brief this was built from. */
	checkError("item-not-found", STANZAS, AIMUCSelfPingVerdictJoined,
	           "item-not-found means joined, our nickname changed under the ping");

	/* "No decision can be made based on this; Treat like a timeout" */
	checkError("remote-server-not-found", STANZAS, AIMUCSelfPingVerdictUnknown,
	           "remote-server-not-found decides nothing");
	checkError("remote-server-timeout", STANZAS, AIMUCSelfPingVerdictUnknown,
	           "remote-server-timeout decides nothing");

	/* "Any other error: the client is probably not joined any more." The note names the
	   three a service actually sends. */
	checkError("not-acceptable", STANZAS, AIMUCSelfPingVerdictNotJoined,
	           "not-acceptable, the recommended answer, means removed");
	checkError("not-allowed", STANZAS, AIMUCSelfPingVerdictNotJoined,
	           "not-allowed means removed too");
	checkError("bad-request", STANZAS, AIMUCSelfPingVerdictNotJoined,
	           "bad-request means removed too");
	checkError("forbidden", STANZAS, AIMUCSelfPingVerdictNotJoined,
	           "a condition nobody listed still means removed");

	/* A condition is only that condition in the stanzas namespace. Without it the name is
	   somebody else's element and must not be mistaken for the good news. */
	checkError("item-not-found", NULL, AIMUCSelfPingVerdictNotJoined,
	           "item-not-found outside the stanzas namespace is not item-not-found");

	node = parse("<iq id='s2c1' type='error'><error type='cancel'>"
	             "<not-acceptable xmlns='" STANZAS "'/>"
	             "<text xmlns='" STANZAS "'>You are not in the room</text>"
	             "</error></iq>");
	if (node) {
		check("A human readable text beside the condition changes nothing",
		      AIMUCSelfPingVerdictForReply(node) == AIMUCSelfPingVerdictNotJoined, NULL);
		xmlnode_free(node);
	}

	node = parse("<iq id='s2c1' type='error'/>");
	if (node) {
		check("An error without a condition is broken, not a verdict",
		      AIMUCSelfPingVerdictForReply(node) == AIMUCSelfPingVerdictUnknown, NULL);
		xmlnode_free(node);
	}

	node = parse("<iq id='s2c1' type='get'><ping xmlns='urn:xmpp:ping'/></iq>");
	if (node) {
		check("A request is not an answer",
		      AIMUCSelfPingVerdictForReply(node) == AIMUCSelfPingVerdictUnknown, NULL);
		xmlnode_free(node);
	}

	check("No stanza at all decides nothing",
	      AIMUCSelfPingVerdictForReply(NULL) == AIMUCSelfPingVerdictUnknown, NULL);

	/* --- The ping itself -------------------------------------------------------------- */

	node = AIMUCSelfPingRequest("characters@chat.shakespeare.lit/JuliC", "s2c1");
	if (node == NULL) {
		check("A ping is built at all", 0, NULL);
	} else {
		xmlnode *ping = xmlnode_get_child_with_namespace(node, "ping", "urn:xmpp:ping");

		check("The ping is an iq get", purple_strequal(xmlnode_get_attrib(node, "type"), "get"),
		      xmlnode_get_attrib(node, "type"));
		check("It goes to our own occupant JID in the room",
		      purple_strequal(xmlnode_get_attrib(node, "to"), "characters@chat.shakespeare.lit/JuliC"),
		      xmlnode_get_attrib(node, "to"));
		check("It carries the id the answer is matched on",
		      purple_strequal(xmlnode_get_attrib(node, "id"), "s2c1"), NULL);
		check("And a ping in urn:xmpp:ping", ping != NULL, NULL);
		xmlnode_free(node);
	}

	check("A ping without a destination is not built",
	      AIMUCSelfPingRequest(NULL, "s2c1") == NULL, NULL);

	/* --- Taking a JID apart ----------------------------------------------------------- */

	check("The nickname is the resource half",
	      purple_strequal(AIMUCSelfPingResourceOfJID("characters@chat.shakespeare.lit/JuliC"), "JuliC"),
	      AIMUCSelfPingResourceOfJID("characters@chat.shakespeare.lit/JuliC"));
	check("A bare room JID has no nickname",
	      AIMUCSelfPingResourceOfJID("characters@chat.shakespeare.lit") == NULL, NULL);
	check("A trailing slash is not a nickname",
	      AIMUCSelfPingResourceOfJID("characters@chat.shakespeare.lit/") == NULL, NULL);

	text = AIMUCSelfPingBareJID("characters@chat.shakespeare.lit/JuliC");
	check("The room is the bare half",
	      purple_strequal(text, "characters@chat.shakespeare.lit"), text);
	g_free(text);

	/* --- Status code 333, XEP-0045 section 10.3 --------------------------------------- */

	node = parse("<presence from='harfleur@chat.shakespeare.lit/pistol'"
	             "          to='pistol@shakespeare.lit/harfleur' type='unavailable'>"
	             "  <x xmlns='" MUCUSER "'>"
	             "    <item affiliation='none' role='none'/>"
	             "    <status code='110'/><status code='333'/>"
	             "  </x>"
	             "</presence>");
	if (node) {
		check("An unavailable presence with 333 is a removal by the service",
		      AIMUCSelfPingPresenceIsTechnicalRemoval(node), NULL);
		check("Status code 110 makes it ours",
		      AIMUCSelfPingPresenceIsSelf(node, NULL), NULL);
		check("There is no kick code to take off this one",
		      AIMUCSelfPingPresenceKickStatus(node) == NULL, NULL);
		xmlnode_free(node);
	}

	/* The copy other occupants get has no 110. Then the nickname decides, and it must
	   decide against us when the occupant is somebody else. */
	node = parse("<presence from='harfleur@chat.shakespeare.lit/pistol'"
	             "          to='gower@shakespeare.lit/cell' type='unavailable'>"
	             "  <x xmlns='" MUCUSER "'><item affiliation='none' role='none'/>"
	             "  <status code='333'/></x>"
	             "</presence>");
	if (node) {
		check("Without 110, our own nickname still makes it ours",
		      AIMUCSelfPingPresenceIsSelf(node, "pistol"), NULL);
		check("Another occupant's removal is not ours",
		      !AIMUCSelfPingPresenceIsSelf(node, "gower"), NULL);
		check("And with no nickname to compare, it is not claimed as ours",
		      !AIMUCSelfPingPresenceIsSelf(node, NULL), NULL);
		xmlnode_free(node);
	}

	node = parse("<presence from='harfleur@chat.shakespeare.lit/pistol' type='unavailable'>"
	             "  <x xmlns='" MUCUSER "'><status code='110'/></x></presence>");
	if (node) {
		check("An ordinary departure is not a removal by the service",
		      !AIMUCSelfPingPresenceIsTechnicalRemoval(node), NULL);
		xmlnode_free(node);
	}

	node = parse("<presence from='harfleur@chat.shakespeare.lit/pistol'>"
	             "  <x xmlns='" MUCUSER "'><status code='110'/><status code='333'/></x></presence>");
	if (node) {
		check("A 333 on an available presence removes nobody",
		      !AIMUCSelfPingPresenceIsTechnicalRemoval(node), NULL);
		check("But 110 on it is still how a room confirms us",
		      AIMUCSelfPingPresenceHasStatusCode(node, AI_MUC_STATUS_SELF_PRESENCE), NULL);
		xmlnode_free(node);
	}

	node = parse("<presence from='harfleur@chat.shakespeare.lit/pistol' type='unavailable'>"
	             "  <x><status code='333'/></x></presence>");
	if (node) {
		check("A status outside muc#user is not a MUC status",
		      !AIMUCSelfPingPresenceIsTechnicalRemoval(node), NULL);
		xmlnode_free(node);
	}

	/* "it is recommended for the client to ignore the 307 code if a 333 status code is
	   present", because nobody kicked anybody and libpurple would say they had. */
	node = parse("<presence from='harfleur@chat.shakespeare.lit/pistol' type='unavailable'>"
	             "  <x xmlns='" MUCUSER "'>"
	             "    <status code='110'/><status code='307'/><status code='333'/></x>"
	             "</presence>");
	if (node) {
		xmlnode *kick = AIMUCSelfPingPresenceKickStatus(node);

		check("A kick code next to a 333 is found so it can be ignored", kick != NULL, NULL);
		if (kick)
			xmlnode_free(kick);
		check("Taking it off leaves the removal itself standing",
		      AIMUCSelfPingPresenceIsTechnicalRemoval(node), NULL);
		check("And the kick is really gone",
		      !AIMUCSelfPingPresenceHasStatusCode(node, AI_MUC_STATUS_KICK), NULL);
		check("While the self presence marker is untouched",
		      AIMUCSelfPingPresenceHasStatusCode(node, AI_MUC_STATUS_SELF_PRESENCE), NULL);
		xmlnode_free(node);
	}

	node = parse("<presence from='harfleur@chat.shakespeare.lit/pistol' type='unavailable'>"
	             "  <x xmlns='" MUCUSER "'><status code='110'/><status code='307'/></x>"
	             "</presence>");
	if (node) {
		check("A real kick is left alone, there is no 333 to override it",
		      AIMUCSelfPingPresenceKickStatus(node) == NULL, NULL);
		xmlnode_free(node);
	}

	/* --- The guard against rejoining the same room forever ---------------------------- */

	check("The first rejoin needs no permission",
	      AIMUCSelfPingRejoinAllowed(0, 0, 1000), NULL);
	check("A second one straight away is held back",
	      !AIMUCSelfPingRejoinAllowed(1, 1000, 1000), NULL);
	check("A minute later it may go",
	      AIMUCSelfPingRejoinAllowed(1, 1000, 1000 + 60), NULL);
	check("After two attempts a minute is no longer enough",
	      !AIMUCSelfPingRejoinAllowed(2, 1000, 1000 + 60), NULL);
	check("Two minutes are",
	      AIMUCSelfPingRejoinAllowed(2, 1000, 1000 + 120), NULL);
	check("After three the room is left alone however long one waits",
	      !AIMUCSelfPingRejoinAllowed(AI_MUC_REJOIN_MAX_ATTEMPTS, 1000, 1000 + 100000), NULL);
	check("A clock that moved backwards is not a licence to retry",
	      !AIMUCSelfPingRejoinAllowed(1, 2000, 1000), NULL);

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
}
