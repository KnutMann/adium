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
 * @class AIInlineImageLinkPlugin
 * @brief Shows an XMPP message that is an image link as the image itself
 *
 * Modern XMPP clients send a picture by uploading it (XEP-0363) and sending its
 * address as the message; whether the receiver sees a link or the picture is
 * purely the receiver's choice. This fetches such pictures and has the message
 * view embed them, governed by the same say the person already has over file
 * transfers: never, from anyone, or only from contacts of their list.
 */
@interface AIInlineImageLinkPlugin : AIPlugin {
	NSURLSession	*session;
}

@end
