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

@class ESPurpleJabberAccount;

/*!
 * @class AMPurpleJabberMAM
 * @brief XEP-0313, the conversation as the server remembers it
 *
 * Adium has always shown the end of a conversation when a window opens, taken from the log it
 * wrote itself. That log only knows what this machine saw: everything said while it was closed,
 * or said from a phone, is simply missing, and nothing marks the gap.
 *
 * The server knows. Asking it costs one exchange when a window opens, and what comes back is
 * shown the same way the local log is, faded and untracked, so that nothing is logged twice and
 * nothing rings a second time.
 */
@interface AMPurpleJabberMAM : NSObject {
	ESPurpleJabberAccount	*account;
	BOOL					 available;
	NSUInteger				 counter;

	NSMutableDictionary		*gathering;	//query id -> the messages arrived under it so far
	NSMutableDictionary		*chats;		//query id -> the chat that asked
	NSMutableSet			*asked;		//chats already asked for, so a window reopening is quiet
}

- (id)initWithAccount:(ESPurpleJabberAccount *)inAccount;

/*! @brief Whether the server said it keeps an archive */
- (BOOL)isAvailable;

@end
