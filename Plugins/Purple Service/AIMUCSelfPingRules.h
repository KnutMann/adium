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

#ifndef AI_MUC_SELF_PING_RULES_H
#define AI_MUC_SELF_PING_RULES_H

#include <libpurple/libpurple.h>

/*
 * The decisions behind MUC Self-Ping (XEP-0410) and MUC status code 333, with nothing
 * else attached.
 *
 * These are separate from the plugin that uses them on purpose. Every rule here is a
 * function of one stanza and nothing more, so Testing/xmpp/mucselfping-test.c can compile
 * this very file and put the specification's table to it. The plugin around it needs a
 * connection, a room and a running application, and none of that can be asserted against.
 */

/*!
 * @brief What the answer to a self-ping says about our occupancy
 */
typedef enum {
	/*! Still in the room. Nothing to do. */
	AIMUCSelfPingVerdictJoined = 0,
	/*! Removed from the room without being told. Rejoin. */
	AIMUCSelfPingVerdictNotJoined,
	/*! The answer settles nothing. Ask again later, and above all do not rejoin. */
	AIMUCSelfPingVerdictUnknown
} AIMUCSelfPingVerdict;

/*! The MUC status code for an occupant the service removed over a technical problem */
#define AI_MUC_STATUS_TECHNICAL_REMOVAL	333
/*! The MUC status code that marks a presence as being about ourselves */
#define AI_MUC_STATUS_SELF_PRESENCE		110
/*! The MUC status code for a kick, which 333 overrides */
#define AI_MUC_STATUS_KICK				307

/*!
 * @brief Build the self-ping for one room
 *
 * @param occupantJid Our own occupant JID in the room, room@service/nick
 * @param iqId The id to answer on
 * @result A new iq stanza; the caller owns it
 */
xmlnode *AIMUCSelfPingRequest(const char *occupantJid, const char *iqId);

/*!
 * @brief Read the answer to a self-ping
 *
 * @param iq The reply stanza, of type result or error
 */
AIMUCSelfPingVerdict AIMUCSelfPingVerdictForReply(xmlnode *iq);

/*!
 * @brief The resource half of a JID, or NULL when it has none
 *
 * Points into jid rather than copying.
 */
const char *AIMUCSelfPingResourceOfJID(const char *jid);

/*!
 * @brief The bare half of a JID, newly allocated, or NULL
 */
char *AIMUCSelfPingBareJID(const char *jid);

/*!
 * @brief Does this presence carry the given MUC status code?
 */
gboolean AIMUCSelfPingPresenceHasStatusCode(xmlnode *presence, int code);

/*!
 * @brief Is this presence about us rather than about another occupant?
 *
 * The service says so with status code 110. Services that leave it out are recognised by
 * the nickname in the sender's resource, which is why ownNick is wanted; pass NULL to go
 * by the status code alone.
 */
gboolean AIMUCSelfPingPresenceIsSelf(xmlnode *presence, const char *ownNick);

/*!
 * @brief Did the service remove this occupant because something broke?
 *
 * An unavailable presence carrying status code 333. XEP-0045 calls it "Service removes
 * user because of error response", for instance a server to server link going down.
 */
gboolean AIMUCSelfPingPresenceIsTechnicalRemoval(xmlnode *presence);

/*!
 * @brief The <status code='307'/> child of a technical removal, or NULL
 *
 * XEP-0045 recommends ignoring a kick code that arrives next to a 333, because nobody
 * kicked anybody. Handing back the node lets the caller take it off the stanza.
 */
xmlnode *AIMUCSelfPingPresenceKickStatus(xmlnode *presence);

/*! How many times in a row one room may be rejoined before we stop trying */
#define AI_MUC_REJOIN_MAX_ATTEMPTS		3
/*! How long after an attempt the next one may follow, doubling each time */
#define AI_MUC_REJOIN_BACKOFF_SECONDS	60

/*!
 * @brief May this room be rejoined now?
 *
 * The guard against a room that answers "not joined" to everything: a rejoin waits longer
 * after every attempt, and after AI_MUC_REJOIN_MAX_ATTEMPTS it stops. A room that comes
 * back resets its own counter, so this only ever holds back a losing streak.
 */
gboolean AIMUCSelfPingRejoinAllowed(guint attempts, time_t lastAttempt, time_t now);

#endif /* AI_MUC_SELF_PING_RULES_H */
