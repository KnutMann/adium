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

#import "AIAwayReminderPlugin.h"
#import <Adium/AIAbstractAccount.h>
#import <Adium/AIAccount.h>
#import <Adium/AIListObject.h>
#import <Adium/AIStatus.h>
#import <Adium/AIStatusControllerProtocol.h>
#import <UserNotifications/UserNotifications.h>

/* A constant identifier, so a fresh reminder replaces the previous one instead of
 * stacking, and so we can withdraw it again once the user is back. */
#define AWAY_REMINDER_NOTIFICATION_IDENTIFIER	@"AIAwayReminder"

@interface AIAwayReminderPlugin ()
- (void)processStatusUpdate;
- (void)startReminderTimer;
- (void)stopReminderTimer;
- (void)cancelReminder;
- (void)reminderTimerFired:(NSTimer *)inTimer;
- (void)postReminder;
- (void)returnFromAwayRequested:(NSNotification *)inNotification;
@end

@implementation AIAwayReminderPlugin

/*!
 * @brief Install
 */
- (void)installPlugin
{
	remindWhenAway = NO;
	awayAccounts = [[NSMutableSet alloc] init];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(returnFromAwayRequested:)
												 name:AIAwayReminderReturnRequestedNotification
											   object:nil];

	//Observe preference changes to learn whether, and after how long, we should remind
	[adium.preferenceController registerPreferenceObserver:self
												  forGroup:PREF_GROUP_STATUS_PREFERENCES];
}

- (void)uninstallPlugin
{
	[self cancelReminder];

	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(processStatusUpdate)
											   object:nil];

	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[adium.preferenceController unregisterPreferenceObserver:self];
	[[AIContactObserverManager sharedManager] unregisterListObjectObserver:self];
}

/*!
 * @brief Deallocate
 */
- (void)dealloc
{
	/* A scheduled timer retains its target, so we should never get here with one
	 * running; invalidating anyway keeps this honest if we ever do. */
	[self stopReminderTimer];

	[awayAccounts release]; awayAccounts = nil;

	[super dealloc];
}

#pragma mark Preferences

/*!
 * @brief Preferences changed
 *
 * Note whether we should remind at all and after how long, and start or stop
 * watching the accounts accordingly.
 */
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	BOOL			oldRemindWhenAway = remindWhenAway;
	NSTimeInterval	oldReminderInterval = reminderInterval;

	remindWhenAway = [[prefDict objectForKey:KEY_STATUS_AWAY_REMINDER] boolValue];
	reminderInterval = [[prefDict objectForKey:KEY_STATUS_AWAY_REMINDER_INTERVAL] doubleValue];

	if (remindWhenAway != oldRemindWhenAway) {
		if (remindWhenAway) {
			/* Registering as a list object observer updates every object at once, so
			 * awayAccounts is filled in before -processStatusUpdate is reached. */
			[[AIContactObserverManager sharedManager] registerListObjectObserver:self];
		} else {
			[self cancelReminder];
			[awayAccounts removeAllObjects];
			[[AIContactObserverManager sharedManager] unregisterListObjectObserver:self];
		}

	} else if (remindWhenAway && (reminderInterval != oldReminderInterval)) {
		/* Still on, but the wait was changed. Start it over so a shortened interval
		 * takes effect during this away period rather than the next one. A reminder
		 * already sent stays sent: -processStatusUpdate will not restart the timer. */
		[self stopReminderTimer];
		[self processStatusUpdate];
	}
}

#pragma mark Watching the accounts

/*!
 * @brief Account status changed
 *
 * Collect the accounts which are away; everything else is decided from that set in
 * -processStatusUpdate.
 */
- (NSSet *)updateListObject:(AIListObject *)inObject keys:(NSSet *)inModifiedKeys silent:(BOOL)silent
{
	if ([inObject isKindOfClass:[AIAccount class]] &&
	   (!inModifiedKeys || [inModifiedKeys containsObject:@"accountStatus"] || [inModifiedKeys containsObject:@"isOnline"])) {
		if (inObject.online) {
			if (inObject.statusType != AIAvailableStatusType) {
				[awayAccounts addObject:inObject];
			} else {
				[awayAccounts removeObject:inObject];
			}
		}
		/* Offline we leave the set alone. -statusType is AIOfflineStatusType for every
		 * offline account, so a connection dropping out from under an away user would
		 * otherwise look exactly like the user coming back — the reminder would be
		 * withdrawn and the wait would start over on every reconnect. Whether such an
		 * account still wants to be away is decided in -processStatusUpdate, which can
		 * ask the account itself. */

		/* We wait until the next run loop so we can have processed multiple changing accounts at once before
		 * acting, preventing us from reacting to intermediate states as the global status change modifies
		 * multiple account states in a single invocation.
		 */
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(processStatusUpdate)
												   object:nil];
		[self performSelector:@selector(processStatusUpdate)
				   withObject:nil
				   afterDelay:0];
	}

	//We don't modify any keys
	return nil;
}

/*!
 * @brief Start or drop the reminder for the current away state
 */
- (void)processStatusUpdate
{
	/* Let go of the accounts which went offline and no longer want to be away. We have
	 * to look for ourselves: -setStatusStateAndRemainOffline: changes an offline
	 * account's status without telling any observer, so returning to available while
	 * an account is disconnected never reaches -updateListObject:. -actualStatusState
	 * is the status the account holds regardless of its connection. */
	for (AIAccount *account in [[awayAccounts copy] autorelease]) {
		if (!account.online) {
			AIStatus	*actualStatusState = account.actualStatusState;
			BOOL		stillAway = (actualStatusState && (actualStatusState.statusType != AIAvailableStatusType));

			/* Only a connection which is trying to come back keeps the away period
			 * alive. An account the user signed off deliberately has ended it. */
			if (!stillAway || !account.shouldBeOnline)
				[awayAccounts removeObject:account];
		}
	}

	if ([awayAccounts count]) {
		/* Away. Start the countdown unless it is already running or this away period
		 * has had its reminder; a second account going away must not push the reminder
		 * further out. */
		if (!reminderTimer && !reminderPosted) [self startReminderTimer];

	} else {
		//Back on every account: this away period is over, and so is its reminder
		[self cancelReminder];
	}
}

#pragma mark The reminder

- (void)startReminderTimer
{
	if (!remindWhenAway || (reminderInterval <= 0.0)) return;

	reminderTimer = [[NSTimer scheduledTimerWithTimeInterval:reminderInterval
													  target:self
													selector:@selector(reminderTimerFired:)
													userInfo:nil
													 repeats:NO] retain];
}

- (void)stopReminderTimer
{
	[reminderTimer invalidate];
	[reminderTimer release]; reminderTimer = nil;
}

/*!
 * @brief Forget everything about the current away period
 *
 * The next time an account goes away the wait starts from the beginning.
 */
- (void)cancelReminder
{
	[self stopReminderTimer];

	/* Anything -postReminder still has in flight belongs to the away period we are
	 * ending here and must not be handed to Notification Center any more. */
	reminderGeneration++;

	if (reminderPosted) {
		reminderPosted = NO;

		/* Withdraw the reminder: leaving it in Notification Center would leave a
		 * "Return" button behind for a user who is long since back. */
		UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
		NSArray *identifiers = [NSArray arrayWithObject:AWAY_REMINDER_NOTIFICATION_IDENTIFIER];

		[center removeDeliveredNotificationsWithIdentifiers:identifiers];
		[center removePendingNotificationRequestsWithIdentifiers:identifiers];
	}
}

- (void)reminderTimerFired:(NSTimer *)inTimer
{
	//A non-repeating timer has invalidated itself by now; only our retain is left
	[reminderTimer release]; reminderTimer = nil;

	//The user may have come back in the same run loop that fired us
	if (![awayAccounts count] || !remindWhenAway) return;

	reminderPosted = YES;
	[self postReminder];
}

/*!
 * @brief Post the one reminder
 */
- (void)postReminder
{
	NSInteger	minutes = (NSInteger)round(reminderInterval / 60.0);
	NSString	*title = AILocalizedString(@"Still away", "Title of the notification which reminds the user that they are still away");
	NSString	*body = [NSString stringWithFormat:AILocalizedString(@"You have been away for %ld minutes.", "Body of the away reminder notification. %ld is a number of minutes."),
						 (long)minutes];

	UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

	/* Which away period this reminder belongs to. Asking the system for its settings
	 * takes a trip to another process, and the user may well be back before the
	 * answer arrives; -cancelReminder counts this up, and a reminder whose period is
	 * over is dropped rather than posted to someone who is sitting right there. */
	NSUInteger	generation = reminderGeneration;

	/* Ask, never request: AIUserNotificationPlugin makes the one authorization
	 * request at launch, and asking again risks a second round of dialogs. If the
	 * user said no, we simply say nothing.
	 *
	 * The handler does not run on the main thread, so posting is dispatched back.
	 * The block retains the plugin, which changes nothing: AICoreComponentLoader
	 * holds every component until the process ends.
	 */
	[center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
		if ((settings.authorizationStatus != UNAuthorizationStatusAuthorized) &&
			(settings.authorizationStatus != UNAuthorizationStatusProvisional)) {
			/* Nothing we can do about it, but silence would leave the user with a
			 * ticked checkbox and no reminder and no explanation anywhere. */
			AILogWithSignature(@"Away reminder not posted: notification authorization status is %ld",
							   (long)settings.authorizationStatus);
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			//Still the same away period? (See above.)
			if ((generation != reminderGeneration) || !reminderPosted) return;

			UNMutableNotificationContent *content = [[[UNMutableNotificationContent alloc] init] autorelease];
			content.title = title;
			content.body = body;
			/* The category is what puts the "Return" button on the notification;
			 * it is registered once in -[AIUserNotificationPlugin installPlugin]. */
			content.categoryIdentifier = AWAY_REMINDER_CATEGORY_IDENTIFIER;
			/* No sound: this is a nudge, not an event. */

			UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:AWAY_REMINDER_NOTIFICATION_IDENTIFIER
																				 content:content
																				 trigger:nil];

			[center addNotificationRequest:request
					 withCompletionHandler:^(NSError *error) {
				if (error) {
					AILogWithSignature(@"Error posting away reminder: %@", error);
				}
			}];
		});
	}];
}

/*!
 * @brief The reminder's "Return" button was pressed
 *
 * This is what -[ESAwayStatusWindowController returnFromAway:] did when the away
 * status window still existed. The window could also return only the accounts
 * selected in its table; a notification has no selection, so what is left is the
 * window's no-selection case.
 */
- (void)returnFromAwayRequested:(NSNotification *)inNotification
{
	AIStatus	*availableStatusState = [adium.statusController defaultInitialStatusState];

	/* Put all accounts in the Available status state.
	 * We can perform this on all accounts without fear of bringing them online;
	 * Those that are offline will remain offline since -setActiveStatusState considers this.
	 */
	[adium.statusController setActiveStatusState:availableStatusState];
}

@end
