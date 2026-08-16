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

#import "AIWebKitPreviewMessageViewController.h"
#import "AIWebKitMessageViewPlugin.h"
#import <Adium/AIChat.h>
#import <WebKit/WebKit.h>

@implementation AIWebKitPreviewMessageViewController

- (BOOL)allowsContextMenu
{
	return NO;
}

- (void)setPreferencesChangedDelegate:(id)inDelegate
{
	if (inDelegate != preferencesChangedDelegate) {
		preferencesChangedDelegate = inDelegate;

		[preferencesChangedDelegate preferencesChangedForGroup:PREF_GROUP_WEBKIT_REGULAR_MESSAGE_DISPLAY
														   key:nil
														object:nil
												preferenceDict:[adium.preferenceController preferencesForGroup:PREF_GROUP_WEBKIT_REGULAR_MESSAGE_DISPLAY]
													 firstTime:YES];

		[preferencesChangedDelegate preferencesChangedForGroup:PREF_GROUP_WEBKIT_GROUP_MESSAGE_DISPLAY
														   key:nil
														object:nil
												preferenceDict:[adium.preferenceController preferencesForGroup:PREF_GROUP_WEBKIT_GROUP_MESSAGE_DISPLAY]
													 firstTime:YES];

		[preferencesChangedDelegate preferencesChangedForGroup:PREF_GROUP_WEBKIT_BACKGROUND_IMAGES
														   key:nil
														object:nil
												preferenceDict:[adium.preferenceController preferencesForGroup:PREF_GROUP_WEBKIT_BACKGROUND_IMAGES]
													 firstTime:YES];
	}
}

- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key object:(AIListObject *)object
					preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	[super preferencesChangedForGroup:group key:key object:object preferenceDict:prefDict firstTime:firstTime];

	if (preferencesChangedDelegate) {
		[preferencesChangedDelegate preferencesChangedForGroup:group
														   key:key
														object:object
												preferenceDict:prefDict
													 firstTime:firstTime];
	}
}

/*!
 * @brief The preview never shows a scrollbar, whatever the preference says
 *
 * The sample conversation can run past the box, so it must scroll; a scrollbar in a settings preview
 * reads as chrome that does not belong, and drawn beside the content it clips the card's rounded
 * corners. The rule itself is the controller's, and it goes into this page alone.
 */
- (BOOL)hidesScrollbar
{
	return YES;
}

@end
