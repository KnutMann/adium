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

#import <Adium/AIContentControllerProtocol.h>
#import "DCMessageContextDisplayPlugin.h"
#import <AIUtilities/AIDictionaryAdditions.h>
#import <Adium/AIChat.h>
#import <Adium/AIContentContext.h>
#import <Adium/AIContentStatus.h>
#import <Adium/AIService.h>

//Old school
#import <Adium/AIListContact.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <Adium/AIAccountControllerProtocol.h>

//omg crawsslinkz
#import "AILoggerPlugin.h"

#import <AIUtilities/AIStringAdditions.h>
#import <AIUtilities/ISO8601DateFormatter.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIHTMLDecoder.h>

#define RESTORED_CHAT_CONTEXT_LINE_NUMBER 50

static DCMessageContextDisplayPlugin *sharedInstance = nil;

/* How long an account that fetches its own history is given before the
 * transcript excerpt is shown anyway. Long enough for a phone to be woken and
 * answer, short enough that a conversation does not sit empty. */
#define DISPLAY_HISTORY_WAIT	5.0

/**
 * @class DCMessageContextDisplayPlugin
 * @brief Component to display in-window message history
 *
 * The amount of history, and criteria of when to display history, are determined in the Advanced->Message History preferences.
 */
@interface DCMessageContextDisplayPlugin ()
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime;
- (NSArray *)contextForChat:(AIChat *)chat;
- (void)addContextDisplayToWindow:(NSNotification *)notification;
- (void)displayContextForChat:(AIChat *)chat;
- (void)historyDeadlineForChat:(AIChat *)chat;
- (void)contentArrivedInChat:(NSNotification *)notification;
+ (DCMessageContextDisplayPlugin *)sharedInstance;
@end

@implementation DCMessageContextDisplayPlugin

+ (DCMessageContextDisplayPlugin *)sharedInstance
{
	return sharedInstance;
}

/**
 * @brief Install
 */
- (void)installPlugin
{
	isObserving = NO;
	
	//Setup our preferences
    [adium.preferenceController registerDefaults:[NSDictionary dictionaryNamed:CONTEXT_DISPLAY_DEFAULTS
																	  forClass:[self class]] 
										forGroup:PREF_GROUP_CONTEXT_DISPLAY];
	
	//Observe preference changes for whether or not to display message history
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_CONTEXT_DISPLAY];
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_LOGGING];
	
	sharedInstance = self;
	formatter = [[ISO8601DateFormatter alloc] init];

	chatsAwaitingHistory = [[NSMutableSet alloc] init];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(contentArrivedInChat:)
												 name:Content_ContentObjectAdded
											   object:nil];
}

/**
 * @brief Uninstall
 */
- (void)uninstallPlugin
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[chatsAwaitingHistory release]; chatsAwaitingHistory = nil;
	[formatter release];
	[adium.preferenceController unregisterPreferenceObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
								object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	if (!object) {
		if ([group isEqualToString:PREF_GROUP_LOGGING]) {
			shouldDisplay = [[prefDict objectForKey:KEY_LOGGER_ENABLE] boolValue]
				&& [[adium.preferenceController preferenceForKey:KEY_DISPLAY_CONTEXT
														   group:PREF_GROUP_CONTEXT_DISPLAY] boolValue];
		} else if ([group isEqualToString:PREF_GROUP_CONTEXT_DISPLAY]) {
			shouldDisplay = [[prefDict objectForKey:KEY_DISPLAY_CONTEXT] boolValue]
				&& [[adium.preferenceController preferenceForKey:KEY_LOGGER_ENABLE
														  group:PREF_GROUP_LOGGING] boolValue];
			linesToDisplay = [[prefDict objectForKey:KEY_DISPLAY_LINES] integerValue];
		}
		
		if (shouldDisplay && linesToDisplay > 0 && !isObserving) {
			//Observe new message windows only if we aren't already observing them
			isObserving = YES;
			[[NSNotificationCenter defaultCenter] addObserver:self
													 selector:@selector(addContextDisplayToWindow:)
														 name:Chat_DidOpen 
													   object:nil];
			
		} else if (isObserving && (!shouldDisplay || linesToDisplay <= 0)) {
			//Remove observer
			isObserving = NO;
			[[NSNotificationCenter defaultCenter] removeObserver:self name:Chat_DidOpen object:nil];
			
		}
	}
}

/**
 * @brief Retrieve and display in-window message history
 *
 * Called in response to the Chat_DidOpen notification
 */
- (void)addContextDisplayToWindow:(NSNotification *)notification
{
	AIChat	*chat = (AIChat *)[notification object];

	/* An account that fetches the conversation's earlier messages from the
	 * service itself is given a moment to do so, since replaying our transcript
	 * on top of that would show the same lines twice, and ours know nothing of
	 * what was delivered or reacted to. The service answers over the network or
	 * not at all, so this is a wait and not a surrender: if nothing has appeared
	 * by the time it is up, the excerpt is shown after all. */
	if ([chat.account providesConversationHistory]) {
		[chatsAwaitingHistory addObject:chat];
		[self performSelector:@selector(historyDeadlineForChat:)
				   withObject:chat
				   afterDelay:DISPLAY_HISTORY_WAIT];
		return;
	}

	[self displayContextForChat:chat];
}

/*!
 * @brief Something reached the chat, so it is not sitting there empty
 *
 * Whether it is the fetched history or a fresh message makes no difference:
 * either way the excerpt would now be landing underneath content instead of in
 * front of it, which is not what an excerpt is for.
 */
- (void)contentArrivedInChat:(NSNotification *)notification
{
	AIChat *chat = (AIChat *)[notification object];

	if (chat && [chatsAwaitingHistory containsObject:chat]) {
		[chatsAwaitingHistory removeObject:chat];
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(historyDeadlineForChat:)
												   object:chat];
	}
}

/*!
 * @brief The wait for fetched history is over and nothing came
 */
- (void)historyDeadlineForChat:(AIChat *)chat
{
	if (![chatsAwaitingHistory containsObject:chat]) return;

	[chatsAwaitingHistory removeObject:chat];
	[self displayContextForChat:chat];
}

- (void)displayContextForChat:(AIChat *)chat
{
	NSArray	*context = [self contextForChat:chat];

	if (context && [context count] > 0 && shouldDisplay) {
		AIContentContext	*contextMessage;

		for(contextMessage in context) {
			/* Don't display immediately, so the message view can aggregate multiple message history items.
			 * As required, we post Content_ChatDidFinishAddingUntrackedContent when finished adding. */
			[contextMessage setDisplayContentImmediately:NO];
		
			[adium.contentController displayContentObject:contextMessage
										usingContentFilters:YES
												immediately:YES];
		}

		//We finished adding untracked content
		[[NSNotificationCenter defaultCenter] postNotificationName:Content_ChatDidFinishAddingUntrackedContent
												  object:chat];
	}
}
/*!
 * @brief Retrieve the message history for a particular chat
 *
 * Asks AILoggerPlugin for the paths to the right files and reads the newest messages from them.
 */
- (NSArray *)contextForChat:(AIChat *)chat
{
	NSInteger linesLeftToFind = 0;

	if ([chat boolValueForProperty:@"Restored Chat"] && linesToDisplay < RESTORED_CHAT_CONTEXT_LINE_NUMBER) {
		linesLeftToFind = MAX(linesLeftToFind, RESTORED_CHAT_CONTEXT_LINE_NUMBER);
	} else {
		linesLeftToFind = linesToDisplay;		
	}
	
	return [self contextForChat:chat lines:linesLeftToFind alsoStatus:NO];
}

- (NSArray *)contextForChat:(AIChat *)chat lines:(NSInteger)linesLeftToFind alsoStatus:(BOOL)alsoStatus
{
	//If there's no log there, there's no message history. Bail out.
	NSArray *logPaths = [AILoggerPlugin sortedArrayOfLogFilesForChat:chat];

	if(!logPaths || linesLeftToFind == 0) return nil;

	NSString *logObjectUID = chat.name;
	if (!logObjectUID) logObjectUID = chat.listObject.UID;
	logObjectUID = [logObjectUID safeFilenameString];

	AIHTMLDecoder *decoder = [AIHTMLDecoder decoder];

	NSString *baseLogPath = [[AILoggerPlugin logBasePath] stringByAppendingPathComponent:
							 [AILoggerPlugin relativePathForLogWithObject:logObjectUID onAccount:chat.account]];

	//Initialize a place to store found messages
	NSMutableArray *outerFoundContentContexts = [NSMutableArray arrayWithCapacity:linesLeftToFind];

	//Get the service name from the path name
	NSString *serviceName = [[[baseLogPath stringByDeletingLastPathComponent] lastPathComponent] componentsSeparatedByString:@"."].firstObject;
	AIListObject *account = chat.account;
	NSString	 *accountID = [NSString stringWithFormat:@"%@.%@", account.service.serviceID, account.UID];

	//Iterate over the logs, newest first, until enough messages are found
	for (NSString *logFileName in logPaths) {
		if (linesLeftToFind <= 0) break;

		//If it's not a .chatlog, ignore it.
		if (![logFileName hasSuffix:@".chatlog"])
			continue;

		//Stick the base path on to the beginning
		NSString *logPath = [baseLogPath stringByAppendingPathComponent:logFileName];

		//By default, the xmlFilePath is the chat log file/bundle... if we find that the chatlog is a bundle, we'll use the xml file inside.
		NSString *xmlFilePath = logPath;

		BOOL isDir;
		if ([[NSFileManager defaultManager] fileExistsAtPath:logPath isDirectory:&isDir]) {
			/* If we have a chatLog bundle, we want to get the text content for the xml file inside */
			if (isDir) {
				[decoder setBaseURL:logPath];
				xmlFilePath = [logPath stringByAppendingPathComponent:
							   [[[logPath lastPathComponent] stringByDeletingPathExtension] stringByAppendingPathExtension:@"xml"]];
			} else {
				[decoder setBaseURL:nil];
			}
		}

		NSData *xmlData = [NSData dataWithContentsOfFile:xmlFilePath];
		if (![xmlData length]) continue;

		NSXMLDocument *document = [[[NSXMLDocument alloc] initWithData:xmlData
															   options:NSXMLNodePreserveCDATA
																 error:NULL] autorelease];
		if (!document) {
			//The log may be malformed (e.g. truncated after a crash); the tidying parser copes with that
			document = [[[NSXMLDocument alloc] initWithData:xmlData
													options:NSXMLDocumentTidyXML
													  error:NULL] autorelease];
		}
		if (!document) continue;

		NSMutableArray *foundMessages = [NSMutableArray arrayWithCapacity:linesLeftToFind];

		//Walk the top-level elements backwards, collecting the newest messages first
		for (NSXMLNode *node in [[[document rootElement] children] reverseObjectEnumerator]) {
			if ((NSInteger)[foundMessages count] >= linesLeftToFind) break;
			if ([node kind] != NSXMLElementKind) continue;

			NSXMLElement *element = (NSXMLElement *)node;
			NSString *elementName = [element name];

			if ([elementName isEqualToString:@"message"]) {
				NSString *timeString = [[element attributeForName:@"time"] stringValue];
				if (!timeString) {
					NSLog(@"Null message context display time for %@", element);
					continue;
				}

				NSDate		*timeVal = [formatter dateFromString:timeString];
				NSString	*senderUID = [[element attributeForName:@"sender"] stringValue];
				NSString	*autoreplyAttribute = [[element attributeForName:@"auto"] stringValue];
				NSString	*sender = [NSString stringWithFormat:@"%@.%@", serviceName, senderUID];
				BOOL		sentByMe = ([sender isEqualToString:accountID]);

				/*don't fade the messages if they're within the last 5 minutes
				 *since that will be resuming a conversation, not starting a new one.
				 */
				Class messageClass = (-[timeVal timeIntervalSinceNow] > 300.0) ? [AIContentContext class] : [AIContentMessage class];

				AIListContact *listContact = nil;
				if (chat.isGroupChat) {
					listContact = [chat.account contactWithUID:senderUID];
				} else {
					listContact = chat.listObject;
				}

				NSMutableString *innerXML = [NSMutableString string];
				for (NSXMLNode *child in [element children]) {
					[innerXML appendString:[child XMLString]];
				}

				AIContentMessage *message = [messageClass messageInChat:chat
															 withSource:(sentByMe ? account : listContact)
															destination:(sentByMe ? (chat.isGroupChat ? nil : chat.listObject) : account)
																   date:timeVal
																message:[decoder decodeHTML:innerXML]
															  autoreply:(autoreplyAttribute && [autoreplyAttribute caseInsensitiveCompare:@"true"] == NSOrderedSame)];

				//Don't log this object
				[message setPostProcessContent:NO];
				[message setTrackContent:NO];

				//Add it to the array (in front, since we're working backwards, and we want the array in forward order)
				[foundMessages insertObject:message atIndex:0];

			} else if (alsoStatus && [elementName isEqualToString:@"status"]) {
				NSString *timeString = [[element attributeForName:@"time"] stringValue];
				if (timeString) {
					NSDate *timeVal = [formatter dateFromString:timeString];
					AIContentStatus *status = [[[AIContentStatus alloc] initWithChat:chat source:nil destination:nil date:timeVal] autorelease];
					[foundMessages insertObject:status atIndex:0];
				}
			}
		}

		AILog(@"Context: %lu messages from %@", (unsigned long)foundMessages.count, [xmlFilePath lastPathComponent]);
		[outerFoundContentContexts replaceObjectsInRange:NSMakeRange(0, 0) withObjectsFromArray:foundMessages];
		linesLeftToFind -= [foundMessages count];
	}

	if (linesLeftToFind > 0) {
		AILogWithSignature(@"Unable to find %lu logs for %@; we needed %lu more", (unsigned long)linesToDisplay, chat, (unsigned long)linesLeftToFind);
	}

	return outerFoundContentContexts;
}

@end
