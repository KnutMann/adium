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

#import "AIUserNotificationPlugin.h"
#import "AIAwayReminderPlugin.h"
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIContactAlertsControllerProtocol.h>
#import <Adium/AIStatusControllerProtocol.h>
#import <Adium/AIAccount.h>
#import <Adium/AIChat.h>
#import <Adium/AIContentObject.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListObject.h>
#import <Adium/AIStatus.h>
#import <Adium/ESFileTransfer.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIStringAdditions.h>

/* Keep the historical Growl action and detail keys so existing user alert
 * configurations continue to work with Notification Center. */
#define NOTIFICATION_EVENT_ALERT_IDENTIFIER	@"Growl"
#define KEY_ALERT_TIME_STAMP				@"Growl Time Stamp"

#define NOTIFICATION_ALERT					AILocalizedString(@"Display a notification",nil)
#define NOTIFICATION_TIME_STAMP_ALERT		AILocalizedString(@"Display a notification with a time stamp", nil)

#define EVENT_QUEUE_WAIT		0.75 // Seconds to wait before clearing an event type's queue
#define EVENT_QUEUE_POST_COUNT	5

#define KEY_FILE_TRANSFER_ID	@"fileTransferUniqueID"
#define KEY_CHAT_ID				@"uniqueChatID"
#define KEY_LIST_OBJECT_ID		@"internalObjectID"

@interface AIUserNotificationPlugin ()
- (NSString *)eventQueueKeyForEventID:(NSString *)eventID
							   inChat:(AIChat *)chat;

- (void)postSingleEventID:(NSString *)eventID
			forListObject:(AIListObject *)listObject
			  withDetails:(NSDictionary *)details
				 userInfo:(id)userInfo;

- (void)postMultipleEventID:(NSString *)eventID
			  forListObject:(AIListObject *)listObject
					forChat:(AIChat *)chat
				  withCount:(NSUInteger)count;

- (void)postNotificationWithTitle:(NSString *)title
							 body:(NSString *)body
					 clickContext:(NSDictionary *)clickContext
					   identifier:(NSString *)identifier;

- (void)adiumFinishedLaunching:(NSNotification *)notification;
- (void)beginNotifying;
- (void)registerNotificationCategories:(UNUserNotificationCenter *)center;
- (void)clearQueue:(NSDictionary *)callDict;
- (void)handleNotificationClickWithContext:(NSDictionary *)clickContext;
@end

/*!
 * @class AIUserNotificationPlugin
 * @brief Posts Adium events to macOS Notification Center
 *
 * Replacement for the retired Growl plugin. It registers under the historical
 * "Growl" action ID so existing per-event alert configurations keep working,
 * and displays notifications via UNUserNotificationCenter.
 */
@implementation AIUserNotificationPlugin

/*!
 * @brief Initialize the plugin
 *
 * Waits for Adium to finish launching before we perform further actions so all events are registered.
 */
- (void)installPlugin
{
	/* The delegate and the categories must be in place before the application has
	 * finished launching: if the user presses a button on a notification which is
	 * still lying in Notification Center, the system delivers that response as we
	 * come up, and a response arriving before there is a delegate is simply dropped.
	 * We run inside -applicationDidFinishLaunching:, which is early enough;
	 * everything that may wait (asking for permission) waits in -beginNotifying.
	 */
	UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
	center.delegate = self;
	[self registerNotificationCategories:center];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(adiumFinishedLaunching:)
												 name:AIApplicationDidFinishLoadingNotification
											   object:nil];

	queuedEvents = [[NSMutableDictionary alloc] init];
}

- (void)uninstallPlugin
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dealloc
{
	[queuedEvents release]; queuedEvents = nil;

	[super dealloc];
}

- (void)adiumFinishedLaunching:(NSNotification *)notification
{
	[self performSelector:@selector(beginNotifying)
			   withObject:nil
			   afterDelay:0];

	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:AIApplicationDidFinishLoadingNotification
												  object:nil];
}

/*!
 * @brief Request notification permission and register our contact alert
 */
- (void)beginNotifying
{
	UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

	/* The delegate and our categories are already in place; see -installPlugin.
	 * What is left here is what may safely wait until the events exist. */
	/* The badge belongs in here even though nothing in this plugin draws one: the unread count
	 * the dock controller writes with -[NSDockTile setBadgeLabel:] is only ever shown while the
	 * application holds badge authorization. Without asking for it, -badgeLabel answers the
	 * count and the Dock quietly draws nothing at all.
	 */
	[center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert |
											 UNAuthorizationOptionSound |
											 UNAuthorizationOptionBadge)
						  completionHandler:^(BOOL granted, NSError *error) {
		if (!granted) {
			AILogWithSignature(@"Notification authorization not granted: %@", error);
		}
	}];

	//Install our contact alert
	[adium.contactAlertsController registerActionID:NOTIFICATION_EVENT_ALERT_IDENTIFIER withHandler:self];
}

/*!
 * @brief Register every notification category Adium uses
 *
 * There is exactly one place for this, and this is it: -setNotificationCategories:
 * replaces the whole set, so a second caller elsewhere would silently drop
 * whatever the first one registered. Anything that wants a button on a
 * notification adds its category here and stamps the identifier onto its own
 * content.
 */
- (void)registerNotificationCategories:(UNUserNotificationCenter *)center
{
	/* UNNotificationActionOptionNone: the button does its work in the background.
	 * Coming back from away is not a reason to pull Adium in front of whatever the
	 * user is doing — the old window's button did not do that either. */
	UNNotificationAction *returnAction = [UNNotificationAction actionWithIdentifier:AWAY_REMINDER_ACTION_RETURN
																			 title:AILocalizedStringFromTableInBundle(@"Return",
																													  @"Buttons",
																													  [NSBundle bundleForClass:[self class]],
																													  "Button on the away reminder notification which sets every account back to available")
																		   options:UNNotificationActionOptionNone];

	UNNotificationCategory *awayReminderCategory = [UNNotificationCategory categoryWithIdentifier:AWAY_REMINDER_CATEGORY_IDENTIFIER
																						 actions:[NSArray arrayWithObject:returnAction]
																			   intentIdentifiers:[NSArray array]
																						 options:UNNotificationCategoryOptionNone];

	[center setNotificationCategories:[NSSet setWithObject:awayReminderCategory]];
}

#pragma mark AIActionHandler

- (NSString *)shortDescriptionForActionID:(NSString *)actionID
{
	return NOTIFICATION_ALERT;
}

- (NSString *)longDescriptionForActionID:(NSString *)actionID withDetails:(NSDictionary *)details
{
	if ([[details objectForKey:KEY_ALERT_TIME_STAMP] boolValue]) {
		return NOTIFICATION_TIME_STAMP_ALERT;
	} else {
		return NOTIFICATION_ALERT;
	}
}

- (NSImage *)imageForActionID:(NSString *)actionID
{
	return [NSImage imageNamed:@"events-notification" forClass:[self class]];
}

/*!
 * @brief Queue a notification for display
 *
 * Events are queued briefly so that bursts (e.g. many contacts signing on at
 * once) are combined into a single notification instead of flooding the
 * Notification Center.
 */
- (BOOL)performActionID:(NSString *)actionID forListObject:(AIListObject *)listObject withDetails:(NSDictionary *)details triggeringEventID:(NSString *)eventID userInfo:(id)userInfo
{
	// Don't post notifications if the active status says to silence them.
	if ([adium.statusController.activeStatusState silencesGrowl]) {
		return NO;
	}

	// Get the chat if it's appropriate.
	AIChat *chat = nil;

	if ([userInfo respondsToSelector:@selector(objectForKey:)]) {
		chat = [userInfo objectForKey:@"AIChat"];
		AIContentObject *contentObject = [userInfo objectForKey:@"AIContentObject"];
		if (contentObject.source) {
			listObject = contentObject.source;
		}
	}

	// Add this event to the queue.
	NSString *queueKey = [self eventQueueKeyForEventID:eventID inChat:chat];

	NSMutableArray *events = [queuedEvents objectForKey:queueKey];

	if (!events)
		events = [NSMutableArray array];

	NSMutableDictionary *eventDetails = [NSMutableDictionary dictionary];

	if (listObject)
		[eventDetails setValue:listObject forKey:@"AIListObject"];

	if (userInfo)
		[eventDetails setValue:userInfo forKey:@"UserInfo"];

	if (details)
		[eventDetails setValue:details forKey:@"Details"];

	[events addObject:eventDetails];

	[queuedEvents setValue:events forKey:queueKey];

	// chat may be nil
	NSDictionary *queueCall = [NSDictionary dictionaryWithObjectsAndKeys:eventID, @"EventID", chat, @"AIChat", nil];

	// Trigger the queue to be cleared in EVENT_QUEUE_WAIT seconds.
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(clearQueue:)
											   object:queueCall];

	[self performSelector:@selector(clearQueue:)
			   withObject:queueCall
			   afterDelay:EVENT_QUEUE_WAIT];

	// If the queue has <EVENT_QUEUE_POST_COUNT entries already, post this one immediately.
	if (events.count < EVENT_QUEUE_POST_COUNT) {
		[self postSingleEventID:eventID
				  forListObject:listObject
					withDetails:details
					   userInfo:userInfo];
	}

	return YES;
}

/*!
 * @brief No configuration pane; the system Notification Center settings apply
 */
- (AIActionDetailsPane *)detailsPaneForActionID:(NSString *)actionID
{
	return nil;
}

- (BOOL)allowMultipleActionsWithID:(NSString *)actionID
{
	return NO;
}

#pragma mark Event Queue

- (NSString *)eventQueueKeyForEventID:(NSString *)eventID
							   inChat:(AIChat *)chat
{
	if (chat) {
		return [NSString stringWithFormat:@"%@-%@", eventID, chat.internalObjectID];
	} else {
		return eventID;
	}
}

- (void)clearQueue:(NSDictionary *)callDict
{
	NSString *eventID = [callDict objectForKey:@"EventID"];
	AIChat *chat = [callDict objectForKey:@"AIChat"];

	NSString *queueKey = [self eventQueueKeyForEventID:eventID inChat:chat];
	NSMutableArray *events = [queuedEvents objectForKey:queueKey];

	if (!events.count) {
		AILogWithSignature(@"Called to clear queue with no events. EventID: %@ chat: %@", eventID, chat);
		return;
	}

	// Remove the first EVENT_QUEUE_POST_COUNT entries, since we've already posted about them.
	NSRange removeRange = NSMakeRange(0,
									  (events.count > EVENT_QUEUE_POST_COUNT ? EVENT_QUEUE_POST_COUNT : events.count));

	[events removeObjectsInRange:removeRange];

	if (events.count == 1) {
		// Seeing "1 message" is just silly!

		NSDictionary *event = [events objectAtIndex:0];

		[self postSingleEventID:eventID
				  forListObject:[event objectForKey:@"AIListObject"]
					withDetails:[event objectForKey:@"Details"]
					   userInfo:[event objectForKey:@"UserInfo"]];

	} else if (events.count) {
		// We have a bunch of events; let's combine them.
		AIListObject *overallListObject = nil;

		// If all events are from the same listObject, let's use that one in the message.
		NSArray *listObjects = [events valueForKeyPath:@"@distinctUnionOfObjects.AIListObject"];

		if (listObjects.count == 1) {
			overallListObject = [listObjects objectAtIndex:0];
		}

		[self postMultipleEventID:eventID
					forListObject:overallListObject
						  forChat:chat
						withCount:events.count];
	}

	// Clear our queue; we're done.
	[queuedEvents setValue:nil forKey:queueKey];
}

#pragma mark Posting

- (void)postSingleEventID:(NSString *)eventID
			forListObject:(AIListObject *)listObject
			  withDetails:(NSDictionary *)details
				 userInfo:(id)userInfo
{
	NSString			*title, *description;
	AIChat				*chat = nil;
	AIContentObject		*contentObject = nil;
	NSMutableDictionary	*clickContext = [NSMutableDictionary dictionary];
	NSString			*identifier = nil;

	//For a message event, listObject should become whoever sent the message
	if ([adium.contactAlertsController isMessageEvent:eventID] &&
		[userInfo respondsToSelector:@selector(objectForKey:)] &&
		[userInfo objectForKey:@"AIContentObject"]) {
		contentObject = [userInfo objectForKey:@"AIContentObject"];
		chat = [userInfo objectForKey:@"AIChat"];

		if (contentObject.source) listObject = contentObject.source;
	}

	[clickContext setObject:eventID
					 forKey:@"eventID"];

	if (listObject) {
		if ([listObject isKindOfClass:[AIListContact class]]) {
			//Use the parent
			listObject = [(AIListContact *)listObject parentContact];
			title = [listObject longDisplayName];
		} else {
			title = listObject.displayName;
		}

		if (chat) {
			[clickContext setObject:chat.uniqueChatID
							 forKey:KEY_CHAT_ID];

			if ([chat isGroupChat]) {
				title = [NSString stringWithFormat:@"%@ (%@)", title, [chat displayName]];
			}

		} else {
			if ([userInfo isKindOfClass:[ESFileTransfer class]] &&
				[eventID isEqualToString:FILE_TRANSFER_COMPLETE]) {
				[clickContext setObject:[(ESFileTransfer *)userInfo uniqueID]
								 forKey:KEY_FILE_TRANSFER_ID];

			} else {
				[clickContext setObject:listObject.internalObjectID
								 forKey:KEY_LIST_OBJECT_ID];
			}
		}

	} else {
		if (chat) {
			title = chat.displayName;

			[clickContext setObject:chat.uniqueChatID
							 forKey:KEY_CHAT_ID];

		} else {
			title = @"Adium";
		}
	}

	description = [adium.contactAlertsController naturalLanguageDescriptionForEventID:eventID
																		   listObject:listObject
																			 userInfo:userInfo
																	   includeSubject:NO];

	// Append event time stamp if preference is set
	if ([[details objectForKey:KEY_ALERT_TIME_STAMP] boolValue]) {
		NSDateFormatter *timeStampFormatter = [[NSDateFormatter alloc] init];
		[timeStampFormatter setFormatterBehavior:NSDateFormatterBehaviorDefault];

		// Set the format to the user's system defined short style
		[timeStampFormatter setTimeStyle:NSDateFormatterShortStyle];

		// For a message event use the contentObject's date otherwise use the current date
		NSDate *dateStamp = (contentObject) ? [contentObject date] : [NSDate date];

		description = [NSString stringWithFormat:AILocalizedString(@"[%@] %@", "A notification with a timestamp. The first %@ is the timestamp, the second is the main string"), [timeStampFormatter stringFromDate:dateStamp], description];

		[timeStampFormatter release];
	}

	if (([eventID isEqualToString:CONTACT_STATUS_ONLINE_YES] ||
		 [eventID isEqualToString:CONTACT_STATUS_ONLINE_NO] ||
		 [eventID isEqualToString:CONTACT_STATUS_AWAY_YES] ||
		 [eventID isEqualToString:CONTACT_SEEN_ONLINE_YES] ||
		 [eventID isEqualToString:CONTACT_SEEN_ONLINE_NO]) &&
		[(AIListContact *)listObject contactListStatusMessage]) {
		NSString *statusMessage = [[adium.contentController filterAttributedString:[(AIListContact *)listObject contactListStatusMessage]
																   usingFilterType:AIFilterContactList
																		 direction:AIFilterIncoming
																		   context:listObject] string];
		statusMessage = [statusMessage stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

		/* If the message contains line breaks, start it on a new line */
		description = [NSString stringWithFormat:@"%@:%@%@",
					   description,
					   (([statusMessage rangeOfLineBreakCharacter].location != NSNotFound) ? @"\n" : @" "),
					   statusMessage];
	}

	if (listObject && [adium.contactAlertsController isContactStatusEvent:eventID]) {
		identifier = listObject.internalObjectID;
	}

	AILog(@"Posting notification: Event ID: %@, listObject: %@, chat: %@, description: %@",
		  eventID, listObject, chat, description);

	[self postNotificationWithTitle:title
							   body:description
					   clickContext:clickContext
						 identifier:identifier];
}

- (void)postMultipleEventID:(NSString *)eventID
			  forListObject:(AIListObject *)listObject
					forChat:(AIChat *)chat
				  withCount:(NSUInteger)count
{
	NSString			*title, *description;
	NSMutableDictionary	*clickContext = [NSMutableDictionary dictionary];
	NSString			*identifier = nil;

	[clickContext setObject:eventID
					 forKey:@"eventID"];

	if (listObject) {
		if ([listObject isKindOfClass:[AIListContact class]]) {
			//Use the parent
			listObject = [(AIListContact *)listObject parentContact];
			title = [listObject longDisplayName];
		} else {
			title = listObject.displayName;
		}

		if (chat) {
			[clickContext setObject:chat.uniqueChatID
							 forKey:KEY_CHAT_ID];

		} else {
			[clickContext setObject:listObject.internalObjectID
							 forKey:KEY_LIST_OBJECT_ID];
		}

	} else {
		if (chat) {
			title = chat.displayName;

			[clickContext setObject:chat.uniqueChatID
							 forKey:KEY_CHAT_ID];

		} else {
			title = @"Adium";
		}
	}

	description = [adium.contactAlertsController descriptionForCombinedEventID:eventID
																 forListObject:listObject
																	   forChat:chat
																	 withCount:count];

	if (listObject && [adium.contactAlertsController isContactStatusEvent:eventID]) {
		identifier = listObject.internalObjectID;
	}

	AILog(@"Posting combined notification: Event ID: %@, listObject: %@, chat: %@, description: %@",
		  eventID, listObject, chat, description);

	[self postNotificationWithTitle:title
							   body:description
					   clickContext:clickContext
						 identifier:identifier];
}

- (void)postNotificationWithTitle:(NSString *)title
							 body:(NSString *)body
					 clickContext:(NSDictionary *)clickContext
					   identifier:(NSString *)identifier
{
	UNMutableNotificationContent *content = [[[UNMutableNotificationContent alloc] init] autorelease];
	content.title = title ? title : @"Adium";
	content.body = body ? body : @"";
	content.userInfo = clickContext;
	/* No sound: Adium's own "Play a sound" alert action handles audio. */

	if (!identifier)
		identifier = [[NSProcessInfo processInfo] globallyUniqueString];

	UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
																		  content:content
																		  trigger:nil];

	[[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
														   withCompletionHandler:^(NSError *error) {
		if (error) {
			AILogWithSignature(@"Error posting notification: %@", error);
		}
	}];
}

#pragma mark UNUserNotificationCenterDelegate

/*!
 * @brief Show notifications even while Adium is the active application
 *
 * This matches the behavior of the old Growl plugin; per-event configuration
 * still decides which events notify at all.
 */
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
	   willPresentNotification:(UNNotification *)notification
		 withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
{
	completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
}

/*!
 * @brief Called when a notification is clicked or one of its buttons is pressed
 *
 * A click opens the chat or reveals the file the notification was about; an
 * action button does its own thing and nothing else. The distinction matters:
 * -handleNotificationClickWithContext: ends by pulling Adium to the front, which
 * is right for a message and wrong for a button that merely changes the status.
 */
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
		 withCompletionHandler:(void (^)(void))completionHandler
{
	NSString		*actionIdentifier = response.actionIdentifier;
	NSDictionary	*clickContext = response.notification.request.content.userInfo;

	if ([actionIdentifier isEqualToString:AWAY_REMINDER_ACTION_RETURN]) {
		//The away reminder's "Return" button; AIAwayReminderPlugin knows what to do with it
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:AIAwayReminderReturnRequestedNotification
																object:nil];
		});

	} else if ([actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self handleNotificationClickWithContext:clickContext];
		});
	}
	//UNNotificationDismissActionIdentifier and any future action: nothing to do

	completionHandler();
}

- (void)handleNotificationClickWithContext:(NSDictionary *)clickContext
{
	NSString		*internalObjectID, *uniqueChatID;
	AIListObject	*listObject;
	AIChat			*chat = nil;

	if ((internalObjectID = [clickContext objectForKey:KEY_LIST_OBJECT_ID])) {
		if ((listObject = [adium.contactController existingListObjectWithUniqueID:internalObjectID]) &&
			([listObject isKindOfClass:[AIListContact class]])) {

			//First look for an existing chat to avoid changing anything
			if (!(chat = [adium.chatController existingChatWithContact:(AIListContact *)listObject])) {
				//If we don't find one, create one
				chat = [adium.chatController openChatWithContact:(AIListContact *)listObject
											  onPreferredAccount:YES];
			}
		}

	} else if ((uniqueChatID = [clickContext objectForKey:KEY_CHAT_ID])) {
		chat = [adium.chatController existingChatWithUniqueChatID:uniqueChatID];

		//If we didn't find a chat, it may have closed since the notification was posted.
		//If we have an appropriate existing list object, we can create a new chat.
		if ((!chat) &&
			(listObject = [adium.contactController existingListObjectWithUniqueID:uniqueChatID]) &&
			([listObject isKindOfClass:[AIListContact class]])) {

			//If the uniqueChatID led us to an existing contact, create a chat with it
			chat = [adium.chatController openChatWithContact:(AIListContact *)listObject
										  onPreferredAccount:YES];
		}
	}

	NSString *fileTransferID;
	if ((fileTransferID = [clickContext objectForKey:KEY_FILE_TRANSFER_ID])) {
		//If a file transfer notification is clicked, reveal the file
		[[ESFileTransfer existingFileTransferWithID:fileTransferID] reveal];
	}

	if (chat) {
		//Make the chat active
		[adium.interfaceController setActiveChat:chat];
	}

	//Make Adium active (needed if, for example, our notification was clicked with another app active)
	[NSApp activateIgnoringOtherApps:YES];
}

@end
