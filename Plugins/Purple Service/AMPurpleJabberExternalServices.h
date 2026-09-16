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

@class ESPurpleJabberAccount;

/*!
 * @class AMPurpleJabberExternalServices
 * @brief The STUN and TURN servers the XMPP server offers its users (XEP-0215)
 *
 * Asked when the account connects and again before the answer runs out, because a
 * host may lend its relay for a few minutes at a time. Calls read the answer when
 * they build their connection. Two hosts on one network meet without any of this,
 * which is why an empty answer is no failure: the call tries with what it has.
 */
@interface AMPurpleJabberExternalServices : NSObject {
	ESPurpleJabberAccount	*account;		//not retained; owns us
	NSMutableArray			*services;		//dictionaries: urls, username, credential
	NSString				*iqId;
	unsigned long			generation;		//so an old timer cannot speak for a new answer
}

- (id)initWithAccount:(ESPurpleJabberAccount *)inAccount;

/*! @brief One dictionary per server: urls (string), username and credential where given */
- (NSArray *)iceServerDictionaries;

@end
