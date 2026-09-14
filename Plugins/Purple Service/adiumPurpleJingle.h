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

/*!
 * @brief What a call manager must offer to receive the stream's Jingle traffic
 *
 * Stanzas arrive as strings, the shape the session machines and the engine speak.
 */
@protocol AdiumJingleStanzaHandler <NSObject>
/*! @brief A jingle iq arrived; return YES to own it (it gets ACKed and swallowed), NO to leave it alone */
- (BOOL)handleJingleElement:(NSString *)jingleXML
					   from:(NSString *)fromJid
					 action:(NSString *)action
				  onAccount:(CBPurpleAccount *)account;

@optional
/*! @brief A jingle-message (XEP-0353) arrived: propose, proceed, reject, retract or accept */
- (BOOL)handleJingleMessageOfKind:(NSString *)kind
							  sid:(NSString *)sid
							 from:(NSString *)fromJid
					  offersVideo:(BOOL)offersVideo
						onAccount:(CBPurpleAccount *)account;
@end

/*!
 * @brief Route the stream's Jingle IQs to a handler, and send Jingle back out
 *
 * Until a handler registers, nothing is touched at all: the jabber protocol keeps
 * answering Jingle with service-unavailable exactly as before, so carrying this
 * code changes no behavior on its own.
 */
void configureAdiumPurpleJingle(void);
void adiumPurpleJingleSetHandler(id<AdiumJingleStanzaHandler> handler);

/*! @brief Wrap a jingle element in an iq of its own and send it on the account's stream */
void adiumPurpleJingleSendElement(CBPurpleAccount *adiumAccount, NSString *toJid, NSString *jingleXML);

/*!
 * @brief Send a jingle-message (XEP-0353): the ringing language of calls
 *
 * A propose names what it offers through audio and video; every other kind
 * carries only the id. Sent as a chat message with a store hint, so every
 * device of the peer hears it ring.
 */
void adiumPurpleJingleSendMessage(CBPurpleAccount *adiumAccount, NSString *toJid, NSString *kind,
								  NSString *sid, BOOL audio, BOOL video);
