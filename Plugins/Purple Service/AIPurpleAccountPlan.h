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

#import <Adium/AIAccountPlan.h>

/*!
 * @class AIPurpleAccountPlan
 * @brief What a libpurple account offers, read from the protocol and from one file
 *
 * A protocol declares each of its options: the name it is stored under, what it is called, its type,
 * its default and, for a choice, the choices. That is everything a row needs, so no option is ever
 * described twice.
 *
 * What the protocol cannot say is which of its options belong in front of a person and in what order.
 * That is what the file next to this class says, one per protocol, named after the protocol and
 * holding nothing but names:
 *
 * <pre>
 * {
 *   "class":   "ESJabberAccountPlan",
 *   "account": { "server": true, "port": true, "options": ["connect_server"] },
 *   "options": ["connection_security", "ft_proxies"],
 *   "hidden":  ["auth_plain_in_clear"],
 *   "legacy":  { "Jabber:Connect Server": "connect_server" }
 * }
 * </pre>
 *
 * Everything the protocol declares that no file mentions lands in a card of its own at the end, rather
 * than being dropped: a protocol that gains an option in an update would otherwise offer it to nobody
 * until somebody noticed.
 *
 * A protocol with no file at all still gets every one of its options. That is what lets a service be
 * added without writing any code, which is how Telegram, Signal and IRCv3 are bound today.
 */
@interface AIPurpleAccountPlan : AIAccountPlan {
	NSDictionary *description;		//What the file says, or nil
}

/*!
 * @brief The plan for this account, of whichever class its file names
 */
+ (AIAccountPlan *)planForAccount:(AIAccount *)account;

/*!
 * @brief What the protocol calls itself
 */
- (const char *)protocolPlugin;

/*!
 * @brief What an option shows when nothing is stored and the protocol's own default will not do
 *
 * Override for a value that has to be worked out rather than written down. Return nil to leave the
 * protocol's default in place.
 */
- (id)defaultForOption:(NSString *)setting;

/*!
 * @brief A migration that a key mapping cannot express
 *
 * Called once before any row is built, so that a row shows the migrated value rather than a default.
 * Override to write a value that has to be worked out from more than one old setting. A plain move
 * from one key to another belongs in the file instead.
 */
- (void)migrateLegacy;

/*!
 * @brief Where an option's value is kept
 *
 * Namespaced by protocol, because two protocols naming a setting "server" mean two different servers
 * and an account belongs to one of them.
 */
- (NSString *)preferenceKeyForSetting:(NSString *)setting;

@end
