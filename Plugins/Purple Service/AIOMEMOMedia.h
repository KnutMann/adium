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

#import <Foundation/Foundation.h>

/*
 * Encrypted files (XEP-0454), which is how a picture or a voice note travels in an encrypted
 * conversation.
 *
 * Nothing about the file is secret from the server that stores it except its contents: it is
 * uploaded like any other file, and the message carries an aesgcm:// address whose fragment is
 * the key. Anybody who has the message can read the file, and nobody else can, which is exactly
 * the property the conversation already has.
 */

/*!
 * @brief Take an aesgcm:// address apart
 *
 * @param address Where the file really is, which is the same thing over https
 * @param ivAndKey The number used once followed by the key, as the fragment carries them
 * @return NO if this is not such an address, or if what it carries is not a usable length
 */
BOOL AIOMEMOMediaReadLink(NSString *link, NSString **address, NSData **ivAndKey);

/*!
 * @brief Decrypt a file fetched from such an address
 *
 * The authentication tag is the last sixteen bytes of what was fetched, which is where the
 * usual encryption libraries leave it.
 *
 * @return nil when it does not authenticate, which must be treated as a file that did not
 *         arrive rather than as one to show anyway
 */
NSData *AIOMEMOMediaDecrypt(NSData *encrypted, NSData *ivAndKey);
