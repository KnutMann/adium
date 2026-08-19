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

#import "AIListContactGroupChatCell.h"
#import <Adium/AIChat.h>
#import <Adium/AIGroupChatStatusIcons.h>
#import <Adium/AIStatusIcons.h>

@implementation AIListContactGroupChatCell

@synthesize chat;

- (NSString *)labelString
{
	AIListObject *listObject = [proxyObject listObject];
	NSString *label;
	
	if (chat && [chat displayNameForContact:listObject]) {
		label = [chat displayNameForContact:listObject];
	} else {
		label = [super labelString];
	}
	
	return label;
}

- (NSImage *)statusImage
{
    AIListObject    *listObject = [proxyObject listObject];
	return [[AIGroupChatStatusIcons sharedIcons] imageForFlag:[chat flagsForContact:listObject]];
}

- (NSImage *)serviceImage
{
	// We can't use [listObject statusIcon] because it will show unknown for strangers.
    AIListObject    *listObject = [proxyObject listObject];
	return [AIStatusIcons statusIconForListObject:listObject
											 type:AIStatusIconTab
										direction:AIIconNormal];
}

- (NSColor *)textColor
{
	AIListObject		*listObject = [proxyObject listObject];
	AIGroupChatFlags	 flags = [chat flagsForContact:listObject];

	/* A plain member carries no role, and the role palette has nothing to say about
	 * one: its None entry is ink black, drawn for a light list, and it overrode the
	 * list's text color on every appearance. The list's own color knows better.
	 */
	if (flags == AIGroupChatNone) return [super textColor];

	NSColor *roleColor = [[AIGroupChatStatusIcons sharedIcons] colorForFlag:flags];

	/* The role colors are inks for a light ground too; on a dark one they nearly
	 * vanish. Lifting them toward white keeps the hues apart and the names legible.
	 */
	NSAppearance *appearance = [self.outlineControlView effectiveAppearance] ?: [NSApp effectiveAppearance];
	NSString *match = [appearance bestMatchFromAppearancesWithNames:
					   [NSArray arrayWithObjects:NSAppearanceNameAqua, NSAppearanceNameDarkAqua, nil]];

	if ([match isEqualToString:NSAppearanceNameDarkAqua]) {
		roleColor = [roleColor blendedColorWithFraction:0.6f ofColor:[NSColor whiteColor]] ?: roleColor;
	}

	return roleColor;
}

- (float)imageOpacityForDrawing
{
	return 1.0f;
}

@end
