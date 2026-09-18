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
#import <Adium/AIContactAlertsControllerProtocol.h>

#define SHAKE_WINDOW_ALERT_IDENTIFIER	@"ShakeMessageWindow"

/*!
 * @class AIShakeWindowContactAlertPlugin
 * @brief An event action that shakes the message window from side to side
 *
 * Every other action Adium offers speaks to someone who is looking elsewhere: the dock bounces,
 * a notification slides in, a sound plays. None of them says anything to someone who is already
 * looking at the window, and that is exactly who an attention request is usually aimed at.
 *
 * The gesture is the one the login window makes when a password is wrong, and it is borrowed here
 * for the same reason it works there: it is impossible to miss and impossible to mistake for
 * anything else, and it is over in half a second.
 */
@interface AIShakeWindowContactAlertPlugin : AIPlugin <AIActionHandler> {
}

@end
