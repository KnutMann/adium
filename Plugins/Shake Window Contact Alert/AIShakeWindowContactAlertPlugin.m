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

#import <QuartzCore/QuartzCore.h>

#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIContactAlertsControllerProtocol.h>
#import <Adium/AIChat.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListObject.h>
#import <AIUtilities/AIImageAdditions.h>

#import "AIShakeWindowContactAlertPlugin.h"

#define SHAKE_ALERT_SHORT	AILocalizedString(@"Shake the message window", "Name of the event action that shakes a message window from side to side")

/* How far to either side, how often, and over how long. Three swings across half a second is
 * six a second, which is the rate the window of a wrong password moves at and slow enough that
 * the eye follows the window rather than seeing it blur. Four across four tenths, which is where
 * this started, is half again as fast and reads as a shudder instead of a shake.
 *
 * The distance is a fixed twenty points rather than a share of the width. A share is what the
 * usual implementation takes, and it suits a password dialog, but a conversation window is twice
 * as wide as one and the same share would fling it across the desk. */
#define SHAKE_WIDTH			20.0
#define SHAKE_COUNT			3
#define SHAKE_DURATION		0.5

@implementation AIShakeWindowContactAlertPlugin

- (void)installPlugin
{
	[adium.contactAlertsController registerActionID:SHAKE_WINDOW_ALERT_IDENTIFIER withHandler:self];
}

#pragma mark Describing the action

- (NSString *)shortDescriptionForActionID:(NSString *)actionID
{
	return SHAKE_ALERT_SHORT;
}

- (NSString *)longDescriptionForActionID:(NSString *)actionID withDetails:(NSDictionary *)details
{
	return SHAKE_ALERT_SHORT;
}

- (NSImage *)imageForActionID:(NSString *)actionID
{
	return [NSImage imageNamed:@"events-window-alert" forClass:[self class]];
}

- (AIActionDetailsPane *)detailsPaneForActionID:(NSString *)actionID
{
	return nil;
}

- (BOOL)allowMultipleActionsWithID:(NSString *)actionID
{
	return NO;
}

#pragma mark Finding the window

/*!
 * @brief The window showing a conversation with this object, if one is open
 *
 * The action can be hung on any event, and most events name a contact rather than a conversation.
 * A window is only shaken if it is already there: opening one in order to shake it would be a far
 * louder answer than anyone asked for.
 */
- (NSWindow *)windowForListObject:(AIListObject *)listObject
{
	AIChat	*chat = nil;

	/* A group conversation raises its events without naming anybody, and so does anything global.
	 * Without this the search below would match the first conversation it finds, because that one
	 * has no list object either, and a window would shake that has nothing to do with what
	 * happened. */
	if (!listObject)
		return nil;

	if ([listObject isKindOfClass:[AIListContact class]])
		chat = [adium.chatController existingChatWithContact:(AIListContact *)listObject];

	if (!chat) {
		//A group conversation names a room, not a contact, and is only found by looking through
		//what is open.
		for (AIChat *openChat in adium.chatController.openChats) {
			if (openChat.listObject == listObject) {
				chat = openChat;
				break;
			}
		}
	}

	return chat ? [adium.interfaceController windowForChat:chat] : nil;
}

#pragma mark Shaking

- (BOOL)performActionID:(NSString *)actionID
		  forListObject:(AIListObject *)listObject
			withDetails:(NSDictionary *)details
	  triggeringEventID:(NSString *)eventID
			   userInfo:(id)userInfo
{
	NSWindow	*window = [self windowForListObject:listObject];

	//Someone who has asked the system for less movement has asked for this, too.
	if ([[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion])
		return NO;

	if (!window || !window.isVisible || window.isMiniaturized)
		return NO;

	NSRect				frame = window.frame;
	CGMutablePathRef	path = CGPathCreateMutable();

	CGPathMoveToPoint(path, NULL, NSMinX(frame), NSMinY(frame));
	for (NSUInteger i = 0; i < SHAKE_COUNT; i++) {
		CGPathAddLineToPoint(path, NULL, NSMinX(frame) - SHAKE_WIDTH, NSMinY(frame));
		CGPathAddLineToPoint(path, NULL, NSMinX(frame) + SHAKE_WIDTH, NSMinY(frame));
	}
	CGPathAddLineToPoint(path, NULL, NSMinX(frame), NSMinY(frame));

	CAKeyframeAnimation *shake = [CAKeyframeAnimation animation];
	shake.path = path;
	shake.duration = SHAKE_DURATION;
	CGPathRelease(path);

	/* The window keeps whatever is put here, so anything that animates its position later would
	 * shake instead of moving. The old set is put back as soon as the animation has been asked
	 * for; an animation already under way is not disturbed by that. */
	NSDictionary *previous = window.animations;
	window.animations = [NSDictionary dictionaryWithObject:shake forKey:@"frameOrigin"];
	[[window animator] setFrameOrigin:frame.origin];
	window.animations = (previous ? previous : [NSDictionary dictionary]);

	return YES;
}

@end
