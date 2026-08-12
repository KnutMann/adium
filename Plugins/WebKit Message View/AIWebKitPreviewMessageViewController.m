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
#import "ESWebView.h"
#import "AIWebKitMessageViewPlugin.h"
#import <Adium/AIChat.h>

@implementation AIWebKitPreviewMessageViewController

- (NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems
{
	return [NSArray array];
}

- (void)dealloc
{
	[preferencesChangedDelegate release]; preferencesChangedDelegate = nil;

	[super dealloc];
}

- (void)setIsGroupChat:(BOOL)groupChat
{
	chat.isGroupChat = groupChat;
	preferenceGroup = [[plugin preferenceGroupForChat:chat] retain];
}

- (void)setPreferencesChangedDelegate:(id)inDelegate
{
	if (inDelegate != preferencesChangedDelegate) {
		[preferencesChangedDelegate release];
		preferencesChangedDelegate = [inDelegate retain];
		
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
 * @brief Let the preview scroll, but keep its scrollbar out of the way.
 *
 * The sample conversation can run past the box, so it must be scrollable; a scrollbar in a
 * settings preview, though, reads as chrome that does not belong, and drawn beside the content
 * it clips the card's rounded corners.
 *
 * Two scrollbars can appear, and each needs its own handle. One is CSS: any overflow element in
 * the page draws a ::-webkit-scrollbar, hidden here with a rule dropped into this one web view -
 * not onto the WebPreferences the controller shares with real chat windows, so their bars are
 * untouched. The other is the main frame's, which WebKit1 draws as an AppKit scroller, not from
 * CSS; made an overlay it sits over the content inside the corners and fades when the pointer is
 * not scrolling. -webViewIsReady fires again after every reprime (a style or variant change), so
 * both are reapplied here, the CSS guarded against being added twice.
 */
- (void)webViewIsReady
{
	[super webViewIsReady];

	[webView stringByEvaluatingJavaScriptFromString:
		@"(function(){var i='adium-preview-no-scrollbar';"
		 "if(!document.getElementById(i)){"
		 "var s=document.createElement('style');s.id=i;"
		 "s.textContent='::-webkit-scrollbar{width:0 !important;height:0 !important;display:none !important}';"
		 "(document.head||document.documentElement).appendChild(s);}})();"];

	NSScrollView *frameScroll = [[[[webView mainFrame] frameView] documentView] enclosingScrollView];
	[frameScroll setScrollerStyle:NSScrollerStyleOverlay];
	[frameScroll setAutohidesScrollers:YES];
}

@end
