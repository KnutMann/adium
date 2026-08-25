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

#import <AdiumLibpurple/SLPurpleCocoaAdapter.h>

void configureAdiumPurpleSignals(void);

/* Read and clear the id stashed for the message just delivered from this sender, so the message
 * that follows it can be tagged with the protocol's id. nil when there is none. */
NSString *adiumTakePendingIncomingMessageId(PurpleAccount *account, const char *from);

@class AIContentMessage;

/* Name the message an account is about to send, so the id minted during the send can be hung on it.
 * Set it before the send and clear it (nil) after. */
void adiumSetPendingOutgoingContentMessage(AIContentMessage *message);

/* Send our reaction (a set of emoji; empty clears it) to a message by its id, on a jabber account.
 * A no-op on any other protocol. */
void adiumJabberSendReaction(PurpleAccount *account, const char *to, const char *target_id, NSArray *emojis);
