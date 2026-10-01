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

#include "AIMUCSelfPingRules.h"

#include <string.h>

#define NS_PING			"urn:xmpp:ping"
#define NS_MUC_USER		"http://jabber.org/protocol/muc#user"
#define NS_STANZAS		"urn:ietf:params:xml:ns:xmpp-stanzas"

xmlnode *AIMUCSelfPingRequest(const char *occupantJid, const char *iqId)
{
	xmlnode *iq, *ping;

	if (occupantJid == NULL || iqId == NULL)
		return NULL;

	iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "get");
	xmlnode_set_attrib(iq, "to", occupantJid);
	xmlnode_set_attrib(iq, "id", iqId);

	ping = xmlnode_new_child(iq, "ping");
	xmlnode_set_namespace(ping, NS_PING);

	return iq;
}

AIMUCSelfPingVerdict AIMUCSelfPingVerdictForReply(xmlnode *iq)
{
	const char	*type;
	xmlnode		*error;
	size_t		 i;

	/* An error condition that still means we are in the room. The first two are the
	   answer of our own other client, which was handed the ping and does not speak
	   XEP-0199. The third is a nickname change that overtook the ping: the occupant JID
	   we pinged is gone because we are now called something else, which is a report about
	   the nickname and not about the room. */
	static const char * const joinedConditions[] = {
		"service-unavailable",
		"feature-not-implemented",
		"item-not-found",
	};

	/* The remote server could not be reached. XEP-0410 is explicit that this decides
	   nothing and is to be treated like a timeout, because a link that is down says
	   nothing about whether the room still lists us. */
	static const char * const unknownConditions[] = {
		"remote-server-not-found",
		"remote-server-timeout",
	};

	if (iq == NULL)
		return AIMUCSelfPingVerdictUnknown;

	type = xmlnode_get_attrib(iq, "type");

	if (purple_strequal(type, "result"))
		return AIMUCSelfPingVerdictJoined;

	if (!purple_strequal(type, "error"))
		return AIMUCSelfPingVerdictUnknown;

	error = xmlnode_get_child(iq, "error");
	if (error == NULL) {
		/* RFC 6120 requires an error stanza to carry a condition. One that does not is
		   broken rather than a service being idiosyncratic, so it is not the "any other
		   error" the specification means, and guessing would mean a rejoin on nonsense. */
		return AIMUCSelfPingVerdictUnknown;
	}

	for (i = 0; i < G_N_ELEMENTS(joinedConditions); i++) {
		if (xmlnode_get_child_with_namespace(error, joinedConditions[i], NS_STANZAS))
			return AIMUCSelfPingVerdictJoined;
	}

	for (i = 0; i < G_N_ELEMENTS(unknownConditions); i++) {
		if (xmlnode_get_child_with_namespace(error, unknownConditions[i], NS_STANZAS))
			return AIMUCSelfPingVerdictUnknown;
	}

	/* Everything else is "probably not joined any more". The specification recommends
	   <not-acceptable/> and names <not-allowed/> and <bad-request/> as the ones services
	   actually send, so there is no list to match against here: what is left is a no. */
	return AIMUCSelfPingVerdictNotJoined;
}

const char *AIMUCSelfPingResourceOfJID(const char *jid)
{
	const char *slash;

	if (jid == NULL)
		return NULL;

	slash = strchr(jid, '/');
	if (slash == NULL || *(slash + 1) == '\0')
		return NULL;

	return slash + 1;
}

char *AIMUCSelfPingBareJID(const char *jid)
{
	const char *slash;

	if (jid == NULL)
		return NULL;

	slash = strchr(jid, '/');
	return (slash ? g_strndup(jid, (gsize)(slash - jid)) : g_strdup(jid));
}

/*!
 * @brief The muc#user payload of a presence, where the status codes live
 */
static xmlnode *AIMUCSelfPingUserPayload(xmlnode *presence)
{
	if (presence == NULL || !purple_strequal(presence->name, "presence"))
		return NULL;

	return xmlnode_get_child_with_namespace(presence, "x", NS_MUC_USER);
}

/*!
 * @brief The <status/> child carrying one code, or NULL
 */
static xmlnode *AIMUCSelfPingStatusNode(xmlnode *presence, int code)
{
	xmlnode	*x = AIMUCSelfPingUserPayload(presence);
	xmlnode	*status;
	char	 wanted[16];

	if (x == NULL)
		return NULL;

	g_snprintf(wanted, sizeof(wanted), "%d", code);

	for (status = xmlnode_get_child(x, "status"); status; status = xmlnode_get_next_twin(status)) {
		if (purple_strequal(xmlnode_get_attrib(status, "code"), wanted))
			return status;
	}

	return NULL;
}

gboolean AIMUCSelfPingPresenceHasStatusCode(xmlnode *presence, int code)
{
	return (AIMUCSelfPingStatusNode(presence, code) != NULL);
}

gboolean AIMUCSelfPingPresenceIsSelf(xmlnode *presence, const char *ownNick)
{
	const char *from, *resource;

	if (AIMUCSelfPingPresenceHasStatusCode(presence, AI_MUC_STATUS_SELF_PRESENCE))
		return TRUE;

	if (ownNick == NULL || presence == NULL)
		return FALSE;

	/* Status code 110 is the right answer and most services send it. Falling back on the
	   nickname covers the ones that do not, and costs nothing: a presence from our own
	   occupant JID is about us whether the service says so or not. */
	from = xmlnode_get_attrib(presence, "from");
	resource = AIMUCSelfPingResourceOfJID(from);

	return (resource != NULL && purple_strequal(resource, ownNick));
}

gboolean AIMUCSelfPingPresenceIsTechnicalRemoval(xmlnode *presence)
{
	if (presence == NULL || !purple_strequal(xmlnode_get_attrib(presence, "type"), "unavailable"))
		return FALSE;

	return AIMUCSelfPingPresenceHasStatusCode(presence, AI_MUC_STATUS_TECHNICAL_REMOVAL);
}

xmlnode *AIMUCSelfPingPresenceKickStatus(xmlnode *presence)
{
	if (!AIMUCSelfPingPresenceIsTechnicalRemoval(presence))
		return NULL;

	return AIMUCSelfPingStatusNode(presence, AI_MUC_STATUS_KICK);
}

gboolean AIMUCSelfPingRejoinAllowed(guint attempts, time_t lastAttempt, time_t now)
{
	time_t wait;

	if (attempts == 0)
		return TRUE;

	if (attempts >= AI_MUC_REJOIN_MAX_ATTEMPTS)
		return FALSE;

	/* 60 seconds after the first attempt, 120 after the second. Long enough that a room
	   which answers "not joined" to every ping is tried three times and then left alone,
	   rather than being hammered once per sweep forever. */
	wait = (time_t)AI_MUC_REJOIN_BACKOFF_SECONDS << (attempts - 1);

	/* A clock that moved backwards leaves lastAttempt in the future. Waiting is the safe
	   reading of that: the alternative is a rejoin on every sweep until the clock catches
	   up, which is the loop this function exists to prevent. */
	if (now < lastAttempt)
		return FALSE;

	return ((now - lastAttempt) >= wait);
}
