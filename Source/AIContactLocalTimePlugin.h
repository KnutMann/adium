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
#import <Adium/AIInterfaceControllerProtocol.h>

/*!
 * @class AIContactLocalTimePlugin
 * @brief What time it is where the other person is
 *
 * Worth knowing before writing rather than after: whether the message that is about to go out
 * will arrive in somebody's afternoon or wake them. Shown in the tooltip, which is where
 * Adium keeps what is true of a contact rather than of a message, and only when the contact
 * has said, which is the ordinary case for XMPP and for nothing else so far.
 */
@interface AIContactLocalTimePlugin : AIPlugin <AIContactListTooltipEntry> {
}

@end
