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
#import "AIMentionEventPlugin.h"
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIContentObject.h>
#import <Adium/AIListObject.h>
#import <Adium/AIListContact.h>
#import <Adium/AIAccount.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIChat.h>
#import <Adium/AIContactAlertsControllerProtocol.h>
#import "AIContentTopic.h"


/*!
 * @class AIMentionEventPlugin
 * @brief Simple content filter to generate events when incoming messages mention the user, and tag them with a special display class
 */
@implementation AIMentionEventPlugin

@synthesize mentionPredicates;

/*!
 * @brief Install
 */
- (void)installPlugin
{
	[adium.contentController registerContentFilter:self
											  ofType:AIFilterContent 
										   direction:AIFilterIncoming];
	
	[adium.preferenceController registerPreferenceObserver:self 
												  forGroup:PREF_GROUP_GENERAL];

	advancedPreferences = [(AIMentionAdvancedPreferences *)[AIMentionAdvancedPreferences preferencePaneForPlugin:self] retain];
}

- (void)uninstallPlugin
{
	[adium.contentController unregisterContentFilter:self];
	[adium.preferenceController unregisterPreferenceObserver:self];
}

#pragma mark -
/*!
 * @brief Filter
 */
- (NSAttributedString *)filterAttributedString:(NSAttributedString *)inAttributedString context:(id)context;
{
	if(![context isKindOfClass:[AIContentMessage class]] || [context isKindOfClass:[AIContentTopic class]])
		return inAttributedString;
	
	AIContentMessage *message = (AIContentMessage *)context;
	AIChat *chat = message.chat;
	
	if(!chat.isGroupChat || message.isOutgoing)
		return inAttributedString;
		
	NSString *messageString = [inAttributedString string];
			
	AIAccount *account = (AIAccount *)message.destination;
	NSString *contactAlias = [chat aliasForContact:[account contactWithUID:account.UID]];
	
	// XXX When we fix user lists to contain accounts, fix this too.
	NSArray *myPredicates = [NSArray arrayWithObjects:
							 [NSPredicate predicateWithFormat:@"SELF MATCHES[cd] %@", [NSString stringWithFormat:@".*\\b%@\\b.*", [account.UID stringByEscapingForRegexp]]], 
							 [NSPredicate predicateWithFormat:@"SELF MATCHES[cd] %@", [NSString stringWithFormat:@".*\\b%@\\b.*", [account.displayName stringByEscapingForRegexp]]], 
							 /* can be nil */ contactAlias? [NSPredicate predicateWithFormat:@"SELF MATCHES[cd] %@", [NSString stringWithFormat:@".*\\b%@\\b.*", [contactAlias stringByEscapingForRegexp]]] : nil,
							 nil];
	
	myPredicates = [myPredicates arrayByAddingObjectsFromArray:self.mentionPredicates];
	
	for(NSPredicate *predicate in myPredicates) {
		if([predicate evaluateWithObject:messageString]) {
			if(message.trackContent && adium.interfaceController.activeChat != chat) {
				[chat incrementUnviewedMentionCount];
			}
			[message addDisplayClass:@"mention"];
			break;
		}
	}

	return inAttributedString;
}

/*!
 * @brief Filter priority
 */
- (CGFloat)filterPriority
{
	return LOWEST_FILTER_PRIORITY;
}

#pragma mark What a term means

+ (BOOL)termIsRegularExpression:(NSString *)term
{
	if (![term length]) return NO;

	static NSPredicate *regexFormPredicate = nil;

	if (!regexFormPredicate)
		regexFormPredicate = [[NSPredicate predicateWithFormat:@"SELF MATCHES '/.*/'"] retain];

	return [regexFormPredicate evaluateWithObject:term];
}

+ (NSPredicate *)predicateForTerm:(NSString *)term error:(NSError **)outError
{
	if (outError) *outError = nil;

	//A row which was only just added has nothing in it to match on yet
	if (![term length]) return nil;

	if ([self termIsRegularExpression:term]) {
		NSString	*inner = [term substringWithRange:NSMakeRange(1, [term length]-2)];
		NSString	*pattern = [NSString stringWithFormat:@".*%@.*", inner];
		NSError		*patternError = nil;

		/* A term of the /.../ form is used as the user wrote it, so it can be a regular
		 * expression which does not compile - and more easily than one might think, because the
		 * preference pane stores every keystroke (it has to: switching panes in the
		 * preferences window would otherwise lose what was typed), so half typed states such
		 * as "/a\/" reach us as well. NSPredicate compiles its pattern not here but at
		 * -evaluateWithObject:, which happens in -filterAttributedString:context: on an
		 * incoming message: an ICU error would raise NSInvalidArgumentException there, out of
		 * reach of anything that could handle it. Compile it here instead and answer with
		 * nothing at all - the term simply does not match until it is finished. The pane's
		 * switch rests on this same answer, but the net stays where it is: a term left half
		 * typed behind a pane change never reaches the switch, and it must not reach the filter
		 * either.
		 *
		 * What the user wrote is compiled first, and only then what we made of it. The two are not
		 * the same question: the ".*" we append can be eaten by whatever the term ends on, and a
		 * term which is plainly unfinished then comes back as a good one. "/a\/" - the very state
		 * named above - is exactly that case: wrapped it reads ".*a\.*", where the trailing
		 * backslash escapes our own dot, so it compiles and would go on to match every message
		 * ending in an "a". Asked about the user's own "a\" instead, ICU says what it is: a
		 * trailing backslash. The term is refused rather than quietly turned into something nobody
		 * asked for. */
		if (![NSRegularExpression regularExpressionWithPattern:inner options:0 error:&patternError] ||
			![NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&patternError]) {
			if (outError) *outError = patternError;
			return nil;
		}

		return [NSPredicate predicateWithFormat:@"SELF MATCHES[cd] %@", pattern];
	}

	//A plain word is matched as itself, whatever characters it is made of
	return [NSPredicate predicateWithFormat:@"SELF MATCHES[cd] %@",
			[NSString stringWithFormat:@".*\\b%@\\b.*", [term stringByEscapingForRegexp]]];
}

+ (BOOL)termIsValid:(NSString *)term
{
	if (![term length] || ![self termIsRegularExpression:term]) return YES;

	return ([self predicateForTerm:term error:NULL] != nil);
}

/*!
 * @brief Rebuild predicates on preference saves.
 */
#pragma mark Preference Observing
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	/* The switches are a key of their own, and the preference controller tells its observers about
	 * one key at a time - without naming it here, throwing a switch would change nothing. */
	if(firstTime || [key isEqualToString:PREF_KEY_MENTIONS] || [key isEqualToString:PREF_KEY_MENTIONS_ENABLED]) {
		NSArray *allMentions = [adium.preferenceController preferenceForKey:PREF_KEY_MENTIONS group:PREF_GROUP_GENERAL];
		/* Index for index with the terms. It is allowed to be missing or short: that is what every
		 * list looked like before there were switches, and it has to go on meaning "all of them on". */
		NSArray *mentionsEnabled = [adium.preferenceController preferenceForKey:PREF_KEY_MENTIONS_ENABLED group:PREF_GROUP_GENERAL];
		NSMutableArray *predicates = [NSMutableArray arrayWithCapacity:[allMentions count]];
		NSUInteger termIndex = 0;

		for (NSString *mention in allMentions) {
			id			flag = (termIndex < [mentionsEnabled count] ? [mentionsEnabled objectAtIndex:termIndex] : nil);
			BOOL		enabled = (([flag respondsToSelector:@selector(boolValue)]) ? [flag boolValue] : YES);

			termIndex++;

			/* A term which is switched off is not applied at all: no expression and no word predicate
			 * is built for it, so it cannot match anything anywhere. */
			if (!enabled) continue;

			NSPredicate *predicate = [AIMentionEventPlugin predicateForTerm:mention error:NULL];

			if (predicate) [predicates addObject:predicate];
		}
		self.mentionPredicates = predicates;
	}
}

@end
