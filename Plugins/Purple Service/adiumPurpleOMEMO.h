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
 * @brief OMEMO (XEP-0384): announce this device and learn about other people's
 */
void configureAdiumPurpleOMEMO(void);

/*!
 * @brief The devices we know a contact has, newest knowledge first
 *
 * Empty when the contact has never announced any, which is how a contact without OMEMO looks
 * and is not an error.
 */
NSArray<NSNumber *> *omemoDevicesForContact(PurpleAccount *account, NSString *bareJID);

/*!
 * @brief Ask a contact's server which devices they have, if we have not already been told
 */
void omemoAskAboutContact(PurpleAccount *account, NSString *bareJID);

/*!
 * @brief Are we encrypting what we send to this contact?
 *
 * Turns itself on when they write to us encrypted, because answering an encrypted message in
 * the clear undoes what the other side asked for without telling anybody.
 */
BOOL omemoIsEncryptingWith(PurpleAccount *account, NSString *bareJID);

/*!
 * @brief Start or stop encrypting to a contact
 *
 * Switching it on also starts collecting whatever is needed to do so, which takes a moment;
 * messages sent in the meantime wait rather than going out in the clear.
 */
void omemoSetEncrypting(PurpleAccount *account, NSString *bareJID, BOOL encrypting);

/*!
 * @brief Can we encrypt to this contact right now?
 *
 * Distinct from whether we mean to: the interface should be able to tell the difference between
 * a conversation that is encrypted and one that is waiting to become so.
 */
BOOL omemoIsReadyFor(PurpleAccount *account, NSString *bareJID);
