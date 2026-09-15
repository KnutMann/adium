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

#import <Adium/AIPlugin.h>

/*!
 * @class AIInlineMediaLinkPlugin
 * @brief Shows an XMPP message that is nothing but a media link as the thing itself
 *
 * Modern XMPP clients send a picture, a voice note or a video by uploading it
 * (XEP-0363) and sending its address as the whole message; whether the receiver
 * sees a link or the thing is purely the receiver's choice. In an encrypted
 * conversation the address is an aesgcm one (XEP-0454), where the file on the
 * server is encrypted and the key travels in the address, so the file is
 * decrypted here before anybody sees it.
 *
 * Which of those happen at all is governed by the same say the person already has
 * over file transfers: never, from anyone, or only from contacts of their list.
 */
/*!
 * @brief What to call a message that is nothing but the address of a file, or nil
 *
 * Such a message reads as a picture or a voice note in the conversation window, where the thing
 * itself is shown. Everywhere the words are used instead, a notification, spoken announcement
 * or preview, a line of hexadecimal is no use to anybody, and this gives those places something
 * a person can read. The WhatsApp side arrives already worded that way; this is the same idea
 * for the protocols whose messages really are the address.
 */
NSString *AIMediaNameForMessageText(NSString *text);

@interface AIInlineMediaLinkPlugin : AIPlugin {
	NSURLSession	*session;
}

@end
