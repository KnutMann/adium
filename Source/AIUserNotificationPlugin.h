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

#import <Adium/AIContactAlertsControllerProtocol.h>
#import <UserNotifications/UserNotifications.h>

/* The one global gate above all per-event alerts. Absent means on: the preference is
 * only ever written when the switch on the Events pane is turned off.
 */
#define PREF_GROUP_NOTIFICATIONS	@"Notifications"
#define KEY_NOTIFICATIONS_ENABLED	@"Show Notifications"

@interface AIUserNotificationPlugin : AIPlugin <AIActionHandler, UNUserNotificationCenterDelegate> {
	NSMutableDictionary	*queuedEvents;
}

@end
