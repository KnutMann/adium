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

#import <Adium/AIContactObserverManager.h>

/* The notification's category and its one action button. AIUserNotificationPlugin
 * owns the single UNUserNotificationCenter delegate and the single
 * -setNotificationCategories: call, so it registers these on our behalf; we only
 * stamp the category onto the reminder we post.
 */
#define AWAY_REMINDER_CATEGORY_IDENTIFIER		@"AIAwayReminderCategory"
#define AWAY_REMINDER_ACTION_RETURN				@"AIAwayReminderReturn"

/* Posted by AIUserNotificationPlugin when the reminder's "Return" button was
 * pressed. Going through the notification centre keeps the status logic here,
 * where the feature lives, instead of in the plugin that happens to own the
 * delegate.
 */
#define AIAwayReminderReturnRequestedNotification	@"AIAwayReminderReturnRequested"

/*!
 * @class AIAwayReminderPlugin
 * @brief Reminds the user, once, that they have been away for a while
 *
 * Successor to the floating away status window: the menu bar item already
 * mirrors the status and carries the whole status menu, and the dock icon
 * overlays it, so all that was left of the window was the nudge.
 */
@interface AIAwayReminderPlugin : AIPlugin <AIListObjectObserver> {
	BOOL			remindWhenAway;
	NSTimeInterval	reminderInterval;		//Seconds, like every other interval in this preference group

	NSMutableSet	*awayAccounts;
	NSTimer			*reminderTimer;
	BOOL			reminderPosted;			//One reminder per away period, not one per minute
	NSUInteger		reminderGeneration;		//Counts away periods, so a reminder in flight can be recognised as stale
}

@end
