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

#import <Adium/AIInterfaceControllerProtocol.h>
#import <WebKit/WebKit.h>

@class AIChat, AIContentObject, AIWebKitMessageViewPlugin, AIWebkitMessageViewStyle, JVMarkedScroller;

@interface AIWebKitMessageViewWKController
	: NSObject <AIMessageDisplayController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler> {
	WKWebView *_webView;
	JVMarkedScroller *_markedScroller;

	AIChat *_chat;
	AIWebKitMessageViewPlugin *_plugin;
	AIWebkitMessageViewStyle *_messageStyle;
	NSString *_activeStyle;
	NSString *_preferenceGroup;

	NSMutableArray *_contentQueue;
	NSMutableArray *_storedContentObjects;
	NSString *_cachedChatContentSource;
	AIContentObject *_previousContent;
	NSMutableDictionary *_objectIconPathDict;
	NSMutableArray *_objectsWithUserIconsArray;

	NSUInteger _variantRetryCount;

	NSURL *_previewImageURL;

	BOOL _webViewIsReady;
	BOOL _shouldReflectPreferenceChanges;
	BOOL _nextMessageFocus;
	BOOL _nextMessageRegainedFocus;
	BOOL _isUpdatingView;
	BOOL _remoteLoadBlockInstalled;
}

+ (instancetype)messageDisplayControllerForChat:(AIChat *)inChat withPlugin:(AIWebKitMessageViewPlugin *)inPlugin;
- (instancetype)initForChat:(AIChat *)inChat withPlugin:(AIWebKitMessageViewPlugin *)inPlugin;

- (AIWebkitMessageViewStyle *)messageStyle;

// Internal content-pipeline helpers
- (void)_appendContentWithScript:(NSString *)js shouldScroll:(BOOL)shouldScroll;
- (void)_processContentQueue;
- (void)_primeWebViewAndReprocessContent:(BOOL)reprocessContent;

- (void)setShouldReflectPreferenceChanges:(BOOL)inValue;

/* Which side of the preference groups this view belongs to. Kept here rather than at the one place
 * that calls it, because the group a chat reads its style from follows from whether it is a group
 * chat, and both facts live in this object.
 */
- (void)setIsGroupChat:(BOOL)groupChat;

/* For subclasses. The page is loaded and can be scripted; called again after every reprime, so
 * anything put into the page from here has to tolerate being applied twice.
 */
- (void)webViewIsReady;

/* For subclasses. Answer NO and a right click does nothing, which is what a preview wants: it shows
 * a conversation that is not real and offers nothing to do with it.
 */
- (BOOL)allowsContextMenu;

/* Whether the scrollbar beside the transcript should be hidden. Answers from the preference by
 * default; the settings preview overrides it, because a scrollbar in a preview reads as chrome that
 * does not belong there whatever the preference says.
 */
- (BOOL)hidesScrollbar;

@end
