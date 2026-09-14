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

#import <AppKit/AppKit.h>
#import "AIJingleCallManager.h"

/*!
 * @class AIJingleCallUI
 * @brief The visible side of calls: the menu entries, the ringing, the windows
 *
 * Puts Call and Video Call into the Contact menu and the contact's context menu
 * for XMPP contacts, rings with a small panel when somebody calls, and keeps one
 * call window per running call. The manager stays the only one who talks Jingle;
 * this class only ever talks to the manager.
 */
@interface AIJingleCallUI : NSObject <AIJingleCallManagerUI>

+ (void)install;

@end
