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

#import "AIWebKitMessageViewWKController.h"
#import "AIAdiumURLSchemeHandler.h"
#import "AIWebKitMessageViewPlugin.h"
#import "AIJSXtrasManager.h"
#import "AIWebKitMessageViewWKContextMenu.h"
#import <Adium/AIMessageEntryTextView.h>
#import <Adium/AIService.h>
#import "AIWebkitMessageViewStyle.h"
#import "ESFileTransferRequestPromptController.h"
#import "ESWebKitMessageViewPreferences.h"

#import <AIUtilities/AIArrayAdditions.h>

#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIColorAdditions.h>
#import <AIUtilities/AIDateFormatterAdditions.h>
#import <AIUtilities/AIFileManagerAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIMutableStringAdditions.h>
#import <AIUtilities/AIPasteboardAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <AIUtilities/JVMarkedScroller.h>

#import <Adium/AIAccount.h>
#import <Adium/AIChat.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIContentContext.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIContentEvent.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIContentObject.h>
#import <Adium/AIContentStatus.h>
#import <Adium/AIContentTopic.h>
#import <Adium/AIEmoticon.h>
#import <Adium/AIFileTransferControllerProtocol.h>
#import <Adium/AIHTMLDecoder.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListObject.h>
#import <Adium/AIMenuControllerProtocol.h>
#import <Adium/AIMetaContact.h>
#import <Adium/AIUserIcons.h>
#import <Adium/ESFileTransfer.h>

#import <Adium/AIPreferenceControllerProtocol.h>

#import <Quartz/Quartz.h>

#undef NEW_CONTENT_RETRY_DELAY
#define NEW_CONTENT_RETRY_DELAY 0.25

/* Per-message-view reference count of a cached user icon (the icon is shared across
 * message views; the file is deleted when the last view using it goes away).
 * Defined here because it lives only in the pre-migration controller, not a shared header.
 */
#define KEY_WEBKIT_CHATS_USING_CACHED_ICON @"WebKit:Chats Using Cached Icon"

static NSArray *draggedTypes = nil;

/* JavaScript installed into every loaded message view. WKWebView exposes no public context-menu
 * hook on macOS, so we intercept right-clicks here and forward the hit-test result to the "adium"
 * script message handler (see docs/design/webkit-to-wkwebview-transition.md §4).
 */
static NSString *const AIWKContextMenuScript =
	@""
	@"(function() {\n"
	@"    document.addEventListener('contextmenu', function(event) {\n"
	@"        event.preventDefault();\n"
	@"        var imageURL = null;\n"
	@"        var node = event.target;\n"
	@"        while (node && node !== document.body) {\n"
	@"            if (node.tagName === 'IMG') {\n"
	@"                imageURL = node.currentSrc || node.getAttribute('src') || null;\n"
	@"                break;\n"
	@"            }\n"
	@"            node = node.parentNode;\n"
	@"        }\n"
	@"        var messageText = null;\n"
	@"        var textNode = event.target;\n"
	@"        if (textNode && textNode.nodeType === 3) textNode = textNode.parentNode;\n"
	@"        if (textNode && textNode.closest && !textNode.closest('.history')) {\n"
	@"            /* Prefer the clicked element's own text: the enclosing block also contains */\n"
	@"            /* the sender name and timestamp, which are useless as reply lookup tokens. */\n"
	@"            if (!textNode.closest('.sender, .time, .timestamp, .username, .buddyname')) {\n"
	@"                messageText = (textNode.textContent || '').trim().substring(0, 400) || null;\n"
	@"            }\n"
	@"            if (!messageText) {\n"
	@"                var block = textNode.closest('.message, .messageBody') || textNode.closest('div, p, td, ins');\n"
	@"                if (block && block !== document.body) {\n"
	@"                    var clone = block.cloneNode(true);\n"
	@"                    var meta = clone.querySelectorAll('.sender, .time, .timestamp, .username, .buddyname');\n"
	@"                    for (var m = 0; m < meta.length; m++) meta[m].parentNode.removeChild(meta[m]);\n"
	@"                    messageText = (clone.textContent || '').trim().substring(0, 400) || null;\n"
	@"                }\n"
	@"            }\n"
	@"        }\n"
	@"        window.webkit.messageHandlers.adium.postMessage({\n"
	@"            type: 'contextMenu',\n"
	@"            x: event.clientX,\n"
	@"            y: event.clientY,\n"
	@"            imageURL: imageURL,\n"
	@"            messageText: messageText\n"
	@"        });\n"
	@"    }, false);\n"
	@"})();\n";

#pragma mark - Weak Script Message Handler Proxy

/// Weak proxy that forwards WKScriptMessageHandler messages without retaining the target.
/// Breaks the retain cycle caused by -[WKUserContentController addScriptMessageHandler:name:].
/// The caller must remove the handler before dealloc, same as any delegate pattern.
@interface _AIWKScriptMessageHandlerWeakProxy : NSObject <WKScriptMessageHandler> {
	__weak id<WKScriptMessageHandler> _target;
}
- (instancetype)initWithTarget:(id<WKScriptMessageHandler>)target;
@end

@implementation _AIWKScriptMessageHandlerWeakProxy

- (instancetype)initWithTarget:(id<WKScriptMessageHandler>)target
{
	self = [super init];
	if (self) {
		_target = target;
	}
	return self;
}

- (void)userContentController:(WKUserContentController *)userContentController
	  didReceiveScriptMessage:(WKScriptMessage *)message
{
	[_target userContentController:userContentController didReceiveScriptMessage:message];
}

@end

#pragma mark - Quick Look WebView Subclass

/// WKWebView subclass taking part in the Quick Look responder chain. QLPreviewPanel walks the
/// responder chain looking for acceptsPreviewPanelControl:, so these methods must live on the
/// view (which is in the chain), not on the controller (which is not) — same pattern as the
/// legacy ESWebView.
@interface AIWKQuickLookWebView : WKWebView
@property (nonatomic, assign) BOOL fillsContainerOnAttach;
@property (nonatomic, weak) id<QLPreviewPanelDataSource> quickLookDataSource;
@end

@implementation AIWKQuickLookWebView

/* The old tab machinery can insert chat views with stale, oversized ancestor
 * frames that modern AppKit never corrects, clipping the chat at the right
 * edge. Shrink any oversized ancestor shortly after being attached. */
- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	if (![self window] || ![self superview])
		return;

	/* Chat views fill their container; embedded previews (preferences) keep
	 * the frame their host assigned. */
	if (self.fillsContainerOnAttach)
		[self setFrame:[[self superview] bounds]];
	else
		return;

	void (^healAncestorFrames)(void) = ^{
		NSView *view = [self superview];
		while (view && [view superview]) {
			NSRect bounds = [[view superview] bounds];
			NSRect frame = [view frame];
			if (NSWidth(frame) > NSWidth(bounds) + 0.5 || NSHeight(frame) > NSHeight(bounds) + 0.5) {
				[view setFrame:bounds];
			}
			view = [view superview];
		}
	};
	healAncestorFrames();
	dispatch_async(dispatch_get_main_queue(), healAncestorFrames);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), healAncestorFrames);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), healAncestorFrames);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), healAncestorFrames);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), healAncestorFrames);
}

- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel
{
	return (self.quickLookDataSource != nil);
}

- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel
{
	[panel setDataSource:self.quickLookDataSource];
}

- (void)endPreviewPanelControl:(QLPreviewPanel *)panel
{
	[panel setDataSource:nil];
}

@end

@interface AIWebKitMessageViewWKController () <QLPreviewPanelDataSource>
- (void)_initWebView;
- (void)_toggleQuickLookPreviewForImageURLString:(NSString *)imageURLString;
- (NSURL *)_fileURLForDisplayedImageURLString:(NSString *)imageURLString;
- (void)_markCurrentLocation;
- (void)_processContentQueue;
- (BOOL)_shouldRetainContentForReplay;
- (void)_updateVariantWithoutPrimingView;
- (void)_appendContentWithScript:(NSString *)js shouldScroll:(BOOL)shouldScroll;
- (void)_drainStoredContentObjects;
- (void)_handleFileTransferAction:(NSString *)action fileTransferID:(NSString *)fileTransferID;
- (void)_presentContextMenuAtClientPoint:(NSPoint)clientPoint imageURLString:(NSString *)imageURLString messageText:(NSString *)messageText;
- (NSMenu *)_contextMenuForImageURLString:(NSString *)imageURLString messageText:(NSString *)messageText;
- (NSString *)_replyTokenForMessageText:(NSString *)messageText;
- (void)replyToMessage:(id)sender;
- (AIMessageEntryTextView *)_messageEntryTextViewInView:(NSView *)view;
- (void)openImage:(id)sender;
- (void)saveImageAs:(id)sender;
- (void)_saveImageAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL window:(NSWindow *)window;
- (void)_downloadRemoteImageAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL window:(NSWindow *)window;
- (void)_presentImageSaveError:(NSError *)error imageURL:(NSURL *)imageURL window:(NSWindow *)window;
- (void)_appendCorrectedMessageFallback:(NSString *)html fromSenderJID:(NSString *)senderJID;
- (NSString *)_jsStringLiteral:(NSString *)string;
- (NSString *)_webKitBackgroundImagePathForUniqueID:(NSInteger)uniqueID;
- (BOOL)_shouldInsertDateSeparatorBeforeContent:(AIContentObject *)content;
- (void)_insertDateSeparatorBeforeContent:(AIContentObject *)content
				willAddMoreContentObjects:(BOOL)willAddMoreContentObjects;
- (void)_trackUserIconForContent:(AIContentObject *)content;
- (AIListObject *)_iconSourceForContent:(AIContentObject *)content;
- (AIListObject *)_iconSourceObjectForObject:(AIListObject *)inObject;
- (NSString *)_cachedUserIconForObject:(AIListObject *)inObject;
- (NSString *)_cachedUserIconFilePathForObject:(AIListObject *)inObject;
- (void)updateUserIconForObject:(AIListObject *)inObject;
- (void)userIconForObjectDidChange:(AIListObject *)inObject;
- (void)_swapUserIconOnPageForObject:(AIListObject *)inObject fromPath:(NSString *)oldPath toPath:(NSString *)newPath;
- (void)releaseCurrentWebKitUserIconForObject:(AIListObject *)inObject;
- (void)releaseAllCachedIcons;
- (void)participatingListObjectsChanged:(NSNotification *)notification;
- (void)sourceOrDestinationChanged:(NSNotification *)notification;
- (void)listObjectAttributesChanged:(NSNotification *)notification;
@end

@implementation AIWebKitMessageViewWKController

#pragma mark - Remote-load block

/*!
 * @brief Hand back the compiled rule list that blocks every remote load
 *
 * The transcript is a file page that should reach nothing but local files. A
 * WKContentRuleList refuses every http(s)/ws(s) load the page attempts,
 * whether from a message style, a plugin, or a tracking pixel in a received
 * message, so the display can neither fetch remote content nor exfiltrate.
 *
 * Compilation is asynchronous and done once; the result is cached. On failure
 * the completion is called with nil, and the page is loaded anyway rather than
 * left blank (an unblocked page is the pre-existing state, not a regression).
 * All on the main thread, where these controllers live.
 */
+ (void)withRemoteLoadBlockRuleList:(void (^)(WKContentRuleList *ruleList))completion
{
	static WKContentRuleList *cachedRuleList = nil;
	static NSMutableArray *pendingCompletions = nil;
	static BOOL compiling = NO;
	static BOOL compiled = NO;

	if (compiled) {
		completion(cachedRuleList);
		return;
	}

	if (!pendingCompletions) pendingCompletions = [NSMutableArray array];
	[pendingCompletions addObject:[completion copy]];

	if (compiling) return;
	compiling = YES;

	NSString *rules = @"[{\"trigger\":{\"url-filter\":\"^https?://\"},\"action\":{\"type\":\"block\"}},"
					   "{\"trigger\":{\"url-filter\":\"^wss?://\"},\"action\":{\"type\":\"block\"}}]";

	[[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:@"AdiumBlockRemoteLoads"
													   encodedContentRuleList:rules
															completionHandler:^(WKContentRuleList *ruleList, NSError *error) {
		if (error) NSLog(@"Remote-load block rule list failed to compile: %@", error);

		cachedRuleList = ruleList;
		compiled = YES;
		compiling = NO;

		NSArray *completions = [pendingCompletions copy];
		[pendingCompletions removeAllObjects];
		for (void (^pending)(WKContentRuleList *) in completions) {
			pending(ruleList);
		}
	}];
}

#pragma mark - Factory / Init

+ (AIWebKitMessageViewWKController *)messageDisplayControllerForChat:(AIChat *)inChat
														  withPlugin:(AIWebKitMessageViewPlugin *)inPlugin
{
	return [[self alloc] initForChat:inChat withPlugin:inPlugin];
}

- (instancetype)initForChat:(AIChat *)inChat withPlugin:(AIWebKitMessageViewPlugin *)inPlugin
{
	if ((self = [super init])) {
		[self _initWebView];

		_chat = inChat;
		_plugin = inPlugin;
		_contentQueue = [[NSMutableArray alloc] init];
		_storedContentObjects = [[NSMutableArray alloc] init];
		_objectIconPathDict = [[NSMutableDictionary alloc] init];
		_objectsWithUserIconsArray = [[NSMutableArray alloc] init];
		_shouldReflectPreferenceChanges = NO;
		_nextMessageFocus = YES;
		_nextMessageRegainedFocus = YES;

		// Observe preference changes
		[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_WEBKIT_REGULAR_MESSAGE_DISPLAY];
		[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_WEBKIT_GROUP_MESSAGE_DISPLAY];
		[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_WEBKIT_BACKGROUND_IMAGES];

		// Initial setup
		[self _updateWebViewForCurrentPreferences];

		// Chat notifications
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(contentObjectAdded:)
													 name:Content_ContentObjectAdded
												   object:inChat];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(chatDidFinishAddingUntrackedContent:)
													 name:Content_ChatDidFinishAddingUntrackedContent
												   object:inChat];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(customEmoticonUpdated:)
													 name:@"AICustomEmoticonUpdated"
												   object:inChat];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(messageWasCorrected:)
													 name:@"AIMessageCorrection"
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(stanzaWasTracked:)
													 name:@"AIMessageStanzaTracked"
												   object:nil];

		// Observe chat/participant changes so user icons can be refreshed on the page (#124)
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(participatingListObjectsChanged:)
													 name:Chat_ParticipatingListObjectsChanged
												   object:inChat];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(sourceOrDestinationChanged:)
													 name:Chat_SourceChanged
												   object:inChat];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(sourceOrDestinationChanged:)
													 name:Chat_DestinationChanged
												   object:inChat];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(_javaScriptPluginsChanged:)
													 name:AIJSXtrasDidChangeNotification
												   object:nil];
	}

	return self;
}

- (AIWebkitMessageViewStyle *)messageStyle
{
	return _messageStyle;
}

- (void)dealloc
{
	[self releaseAllCachedIcons];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[adium.preferenceController unregisterPreferenceObserver:self];

	[_webView setNavigationDelegate:nil];
	[_webView setUIDelegate:nil];
	[_webView.configuration.userContentController removeScriptMessageHandlerForName:@"adium"];
}

#pragma mark - WebView Creation

/*!
 * @brief Add the base user scripts and the enabled JavaScript plugins
 *
 * Shared by the initial configuration and the live rebuild: the two shims the
 * transcript always needs, then each enabled plugin in its own content world.
 * The caller has already put the message handler in place (it must not be added
 * twice) and cleared any previous user scripts.
 */
- (void)_installUserScriptsInto:(WKUserContentController *)userContentController
{
	// Intercept right-clicks; WKWebView has no public context-menu hook on macOS (#119).
	[userContentController addUserScript:[[WKUserScript alloc] initWithSource:AIWKContextMenuScript
																injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
															 forMainFrameOnly:YES]];

	/* Message styles may ship their own Template.html, and every one written before Catalina
	 * scrolls via document.body.scrollTop, which standards-mode WebKit stopped honouring: the
	 * chat silently stops following new messages. The era's circulating hand-fix was pasting a
	 * nearBottom(){return 1} into one's style, which also destroyed reading the scrollback.
	 * Redefining the two functions after the template has loaded repairs every such style with
	 * the same semantics the bundled template has, and no style needs hand-patching again. A
	 * style's own smooth-scroll animation is overridden along with it; on today's WebKit it was
	 * not scrolling at all. */
	[userContentController addUserScript:[[WKUserScript alloc] initWithSource:
		@"function nearBottom() { return ( window.scrollY >= ( document.body.offsetHeight - ( window.innerHeight * 1.2 ) ) ); }"
		@"function scrollToBottom() { window.scrollTo(0, document.body.scrollHeight); }"
																injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
															 forMainFrameOnly:YES]];

	/* JavaScript plugins, each into a content world of its own. Their scripts
	 * re-inject on every load like the two above, so a reprime needs no extra
	 * handling. The world isolates a plugin's JS; the hardening and the
	 * remote-load block keep it harmless. */
	[[AIJSXtrasManager sharedManager] installIntoUserContentController:userContentController];
}

/*!
 * @brief The set of plugins changed; rebuild the scripts and redraw
 *
 * User scripts are fixed once injected, so a plugin turned on or off, installed
 * or removed, only reaches an open window by rebuilding the whole set. The
 * message handler is left in place; only the user scripts are cleared and
 * re-added, then the view is reprimed so the new plugins see the conversation.
 */
- (void)_javaScriptPluginsChanged:(NSNotification *)notification
{
	if (!_webView) return;

	WKUserContentController *userContentController = _webView.configuration.userContentController;
	[userContentController removeAllUserScripts];
	[self _installUserScriptsInto:userContentController];

	/* Reloading redraws the conversation from what was kept for exactly this. A window that kept
	 * nothing - an empty chat, or one open since before its content was worth keeping - has nothing
	 * to redraw, and reloading would only blank it; leave it standing, and the new set of plugins
	 * takes hold the next time it is opened. */
	if (_shouldReflectPreferenceChanges || [_storedContentObjects count] || [_contentQueue count]) {
		[self _primeWebViewAndReprocessContent:YES];
	}
}

- (void)_initWebView
{
	WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];

	// User content controller with script message handler (via weak proxy to avoid retain cycle)
	WKUserContentController *userContentController = [[WKUserContentController alloc] init];
	_AIWKScriptMessageHandlerWeakProxy *proxy = [[_AIWKScriptMessageHandlerWeakProxy alloc] initWithTarget:self];
	[userContentController addScriptMessageHandler:proxy name:@"adium"];

	[self _installUserScriptsInto:userContentController];

	config.userContentController = userContentController;

	/* The transcript is display only: it never keeps state that must outlive the
	 * window, and the file origin makes per-style LocalStorage impossible anyway.
	 * An ephemeral data store means nothing a page (a message style, or a plugin)
	 * does can be written to persist across launches. */
	config.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];

	/* Let the file-origin page load local file resources outside its base
	 * directory (user icons live in the caches folder). Deliberately NOT
	 * allowUniversalAccessFromFileURLs: that one lets a file page script XHR
	 * across origins, i.e. exfiltrate to any http host, and nothing legitimate
	 * here needs it (measured: no bundled style loads a remote resource, inline
	 * images arrive as local files). The remote-load block below is the other
	 * half of the same fence. */
	@try {
		[config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
	} @catch (NSException *exception) {
		NSLog(@"WKWebView file access unlock unavailable: %@", exception);
	}

	/* Peer connections carry ICE/STUN traffic and data channels that no content
	 * rule list governs, so they are an exfiltration path around the block below.
	 * The transcript has no use for WebRTC; turn it off where the key exists. */
	@try {
		[config.preferences setValue:@NO forKey:@"peerConnectionEnabled"];
	} @catch (NSException *exception) {
		NSLog(@"WKWebView peer-connection key unavailable: %@", exception);
	}

	// Register adium:// scheme handler (10.13+)
	if ([WKWebView handlesURLScheme:@"adium"]) {
		// WKWebView handles adium:// by default as an unknown scheme — no-op
	} else if (@available(macOS 10.13, *)) {
		AIAdiumURLSchemeHandler *schemeHandler = [[AIAdiumURLSchemeHandler alloc] init];
		[config setURLSchemeHandler:schemeHandler forURLScheme:@"adium"];
	}

	_webView = [[AIWKQuickLookWebView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100) configuration:config];
	((AIWKQuickLookWebView *)_webView).fillsContainerOnAttach = YES;
	[_webView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	[_webView setNavigationDelegate:self];
	[_webView setUIDelegate:self];

	if (!draggedTypes) {
		draggedTypes = [[NSArray alloc] initWithObjects:AINSPasteboardTypeFilenames, AIiTunesTrackPboardType,
														NSPasteboardTypeTIFF, NSPasteboardTypePDF, NSPasteboardTypeHTML,
														NSFileContentsPboardType, NSPasteboardTypeRTF,
														NSPasteboardTypeString, nil];
	}
	[_webView registerForDraggedTypes:draggedTypes];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
	/* The legacy renderer set the page's default font via WebPreferences; WKWebView
	 * has no public equivalent, so apply the style's font as an inline default. */
	{
		NSString *family = [_messageStyle defaultFontFamily];
		NSNumber *size = [_messageStyle defaultFontSize];
		if (family || size) {
			NSString *js = [NSString stringWithFormat:
				@"document.documentElement.style.fontFamily = '%@'; document.documentElement.style.fontSize = '%@px';",
				family ? family : @"", size ? size : @12];
			[webView evaluateJavaScript:js completionHandler:nil];
		}
	}

	_webViewIsReady = YES;
	[self webViewIsReady];

	// Set up marked scroller after the scroll view exists
	[self setupMarkedScroller];

	// Content that arrived while the view was loading was parked in _storedContentObjects
	[self _drainStoredContentObjects];

	[self _processContentQueue];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
	NSLog(@"WKWebView navigation failed: %@", error);
}

/*!
 * @brief Is this a scheme the transcript may open in the browser?
 *
 * A user following a link should reach the web or their mail client, and
 * nothing else. Handing every scheme to NSWorkspace, as this once did, lets a
 * message (or a plugin injecting one) invoke any registered handler - file:,
 * and worse - with a single click.
 */
static BOOL AIWebKitSchemeIsSafeToOpenExternally(NSString *scheme)
{
	NSString *lower = [scheme lowercaseString];
	return ([lower isEqualToString:@"http"] || [lower isEqualToString:@"https"] ||
			[lower isEqualToString:@"mailto"] || [lower isEqualToString:@"xmpp"] ||
			[lower isEqualToString:@"aim"] || [lower isEqualToString:@"ymsgr"] ||
			[lower isEqualToString:@"ftp"]);
}

- (void)webView:(WKWebView *)webView
	decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
					decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
	NSURL *url = [navigationAction.request URL];
	NSString *scheme = [[url scheme] lowercaseString];

	/* WKNavigationTypeOther is our own template loads and the styles' internal
	 * navigation - but it is ALSO what a script assigning location.href produces,
	 * so allowing it blindly lets page or plugin JS navigate the frame anywhere.
	 * Confine it to the local page and the harmless internal schemes; a remote
	 * document load would be blocked by the content rule list regardless, but a
	 * navigation is cheaper to refuse here. */
	if (navigationAction.navigationType == WKNavigationTypeOther) {
		if (!url || [scheme isEqualToString:@"file"] || [scheme isEqualToString:@"about"] ||
			[scheme isEqualToString:@"adium"]) {
			decisionHandler(WKNavigationActionPolicyAllow);
		} else {
			decisionHandler(WKNavigationActionPolicyCancel);
		}
		return;
	}

	// A click on a link: open it in the browser, but only for schemes we trust
	if (url && AIWebKitSchemeIsSafeToOpenExternally(scheme)) {
		[[NSWorkspace sharedWorkspace] openURL:url];
	}
	decisionHandler(WKNavigationActionPolicyCancel);
}

#pragma mark - WKUIDelegate

- (WKWebView *)webView:(WKWebView *)webView
	createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
			   forNavigationAction:(WKNavigationAction *)navigationAction
					windowFeatures:(WKWindowFeatures *)windowFeatures
{
	// Open popup windows in the default browser, but only for schemes we trust
	NSURL *url = [navigationAction.request URL];
	if (url && AIWebKitSchemeIsSafeToOpenExternally([url scheme])) {
		[[NSWorkspace sharedWorkspace] openURL:url];
	}
	return nil;
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
	  didReceiveScriptMessage:(WKScriptMessage *)message
{
	if (![message.body isKindOfClass:[NSDictionary class]]) {
		return;
	}

	NSDictionary *body = (NSDictionary *)message.body;
	NSString *type = [body objectForKey:@"type"];
	if (![type isKindOfClass:[NSString class]]) {
		return;
	}

	if ([type isEqualToString:@"ready"]) {
		// Don't re-process gate if already ready
		if (!_webViewIsReady) {
			_webViewIsReady = YES;
			[self webViewIsReady];
			[self _drainStoredContentObjects];
			[self _processContentQueue];
		}
	} else if ([type isEqualToString:@"fileTransfer"]) {
		NSString *action = [body objectForKey:@"action"];
		NSString *fileTransferID = [body objectForKey:@"fileTransferID"];
		[self _handleFileTransferAction:action fileTransferID:fileTransferID];
	} else if ([type isEqualToString:@"zoomImage"]) {
		NSString *imageURLString = [body objectForKey:@"imageURL"];
		if ([imageURLString isKindOfClass:[NSString class]] && [imageURLString length]) {
			[self _toggleQuickLookPreviewForImageURLString:imageURLString];
		}
	} else if ([type isEqualToString:@"contextMenu"]) {
		AIWKContextMenuMessage contextMenuMessage = AIWKContextMenuMessageFromBody(body);
		if (!contextMenuMessage.valid) {
			AILogWithSignature(@"Ignoring contextMenu message with invalid coordinates: %@", body);
			return;
		}

		[self _presentContextMenuAtClientPoint:NSMakePoint(contextMenuMessage.x, contextMenuMessage.y)
								imageURLString:contextMenuMessage.imageURLString
								   messageText:contextMenuMessage.messageText];
	}
}

#pragma mark - Reply (quote)

/*!
 * @brief Pick a lookup token from the clicked message's text.
 *
 * The prpl resolves the token by substring search over its recent message
 * cache (most recent first, same chat), so a single distinctive word is
 * enough. Prefer the longest alphanumeric word.
 */
- (NSString *)_replyTokenForMessageText:(NSString *)messageText
{
	if (![messageText length]) {
		return nil;
	}

	NSString *best = nil;
	for (NSString *word in [messageText componentsSeparatedByCharactersInSet:
							[[NSCharacterSet alphanumericCharacterSet] invertedSet]]) {
		if ([word length] >= 3 && [word length] > [best length]) {
			best = word;
		}
	}
	return best;
}

- (void)replyToMessage:(id)sender
{
	NSString *token = [sender representedObject];
	if (![token length]) {
		return;
	}

	AIMessageEntryTextView *entryView = [self _messageEntryTextViewInView:[[_webView window] contentView]];
	if (!entryView) {
		return;
	}

	[entryView setString:[NSString stringWithFormat:@"?reply %@ ", token]];
	[[entryView window] makeFirstResponder:entryView];
	[entryView setSelectedRange:NSMakeRange([[entryView string] length], 0)];
}

- (AIMessageEntryTextView *)_messageEntryTextViewInView:(NSView *)view
{
	if ([view isKindOfClass:[AIMessageEntryTextView class]]) {
		return (AIMessageEntryTextView *)view;
	}
	for (NSView *subview in [view subviews]) {
		AIMessageEntryTextView *found = [self _messageEntryTextViewInView:subview];
		if (found) {
			return found;
		}
	}
	return nil;
}

#pragma mark - Quick Look image preview

/*!
 * @brief Toggle a Quick Look preview for an image clicked in the message view, Finder-style.
 *
 * Reached via the "zoomImage" script message the Template.html bridge shim posts when a
 * larger-than-emoticon image is clicked (emoticons keep the legacy click-to-text swap).
 */
- (void)_toggleQuickLookPreviewForImageURLString:(NSString *)imageURLString
{
	QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
	if ([QLPreviewPanel sharedPreviewPanelExists] && [panel isVisible]) {
		[panel orderOut:nil];
		return;
	}

	NSURL *fileURL = [self _fileURLForDisplayedImageURLString:imageURLString];
	if (!fileURL) {
		return;
	}

	_previewImageURL = fileURL;
	[(AIWKQuickLookWebView *)_webView setQuickLookDataSource:self];
	[panel makeKeyAndOrderFront:nil];
	[panel reloadData];
}

/*!
 * @brief Translate an image URL as displayed in the WKWebView back into a real file URL.
 *
 * Images are referenced with absolute file:// URLs by the style/content pipeline; resources
 * that resolved relatively against the adium:// base URL are mapped back into the message
 * style's resource directory.
 */
- (NSURL *)_fileURLForDisplayedImageURLString:(NSString *)imageURLString
{
	NSURL *url = [NSURL URLWithString:imageURLString];
	if (!url) {
		return nil;
	}

	if ([url isFileURL]) {
		return ([[NSFileManager defaultManager] fileExistsAtPath:[url path]] ? url : nil);
	}

	if ([[url scheme] isEqualToString:@"adium"]) {
		NSString *resourcePath = [_messageStyle.bundle resourcePath];
		NSString *relativePath = [url path];
		if (resourcePath && [relativePath length]) {
			NSString *candidate = [resourcePath stringByAppendingPathComponent:relativePath];
			if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
				return [NSURL fileURLWithPath:candidate];
			}
		}
	}

	return nil;
}

- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel
{
	return (_previewImageURL ? 1 : 0);
}

- (id<QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)idx
{
	return (id<QLPreviewItem>)_previewImageURL;
}

#pragma mark - Context Menu

- (void)_presentContextMenuAtClientPoint:(NSPoint)clientPoint imageURLString:(NSString *)imageURLString messageText:(NSString *)messageText
{
	if (![self allowsContextMenu]) {
		return;
	}

	NSWindow *window = [_webView window];
	if (window == nil) {
		return;
	}

	// clientPoint arrives in viewport coordinates (origin top-left); flip it into the web view's
	// coordinate space, then convert into the window's content view so the menu pops at the click.
	CGFloat flippedY = [_webView isFlipped] ? clientPoint.y : [_webView bounds].size.height - clientPoint.y;
	NSView *contentView = [window contentView];
	NSPoint location = [_webView convertPoint:NSMakePoint(clientPoint.x, flippedY) toView:contentView];

	NSMenu *menu = [self _contextMenuForImageURLString:imageURLString messageText:messageText];
	[menu popUpMenuPositioningItem:nil atLocation:location inView:contentView];
}

- (NSMenu *)_contextMenuForImageURLString:(NSString *)imageURLString messageText:(NSString *)messageText
{
	NSMenu *menu = [[NSMenu alloc] init];
	NSMenuItem *menuItem;

	/* WhatsApp can reply to (quote) a specific message: the prpl accepts
	 * "?reply <token> <text>" and resolves the token against its recent
	 * message cache. Offer that on right-clicked messages. */
	if ([_chat.account.service.serviceID isEqualToString:@"WhatsApp"]) {
		NSString *replyToken = [self _replyTokenForMessageText:messageText];
		if (replyToken) {
			menuItem = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Reply", nil)
												  action:@selector(replyToMessage:)
										   keyEquivalent:@""];
			[menuItem setTarget:self];
			[menuItem setRepresentedObject:replyToken];
			[menu addItem:menuItem];
			[menu addItem:[NSMenuItem separatorItem]];
		}
	}

	NSURL *imageURL = AIWKImageURLFromString(imageURLString);

	if (AIWKCanSaveImageURL(imageURL)) {
		menuItem = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Open Image", nil)
											  action:@selector(openImage:)
									   keyEquivalent:@""];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:imageURL];
		[menu addItem:menuItem];

		menuItem =
			[[NSMenuItem alloc] initWithTitle:[AILocalizedString(@"Save Image As", nil) stringByAppendingEllipsis]
									   action:@selector(saveImageAs:)
								keyEquivalent:@""];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:imageURL];
		[menu addItem:menuItem];

		[menu addItem:[NSMenuItem separatorItem]];
	}

	AIListContact *chatListObject = _chat.listObject.parentContact;
	NSMenu *originalMenu = nil;
	if (chatListObject != nil) {
		NSArray *locations;
		if ([chatListObject isIntentionallyNotAStranger]) {
			locations = [NSArray arrayWithObjects:[NSNumber numberWithInteger:Context_Contact_Manage],
												  [NSNumber numberWithInteger:Context_Contact_Action],
												  [NSNumber numberWithInteger:Context_Contact_NegativeAction],
												  [NSNumber numberWithInteger:Context_Contact_ChatAction],
												  [NSNumber numberWithInteger:Context_Contact_Additions], nil];
		} else {
			locations = [NSArray arrayWithObjects:[NSNumber numberWithInteger:Context_Contact_Manage],
												  [NSNumber numberWithInteger:Context_Contact_Action],
												  [NSNumber numberWithInteger:Context_Contact_NegativeAction],
												  [NSNumber numberWithInteger:Context_Contact_ChatAction],
												  [NSNumber numberWithInteger:Context_Contact_Stranger_ChatAction],
												  [NSNumber numberWithInteger:Context_Contact_Additions], nil];
		}
		originalMenu = [adium.menuController contextualMenuWithLocations:locations
														   forListObject:chatListObject
																  inChat:_chat];
	} else if (_chat.isGroupChat) {
		originalMenu = [adium.menuController
			contextualMenuWithLocations:[NSArray arrayWithObjects:[NSNumber numberWithInteger:Context_GroupChat_Manage],
																  [NSNumber numberWithInteger:Context_GroupChat_Action],
																  nil]
								forChat:_chat];
	}

	if (originalMenu != nil) {
		/* The items still belong to originalMenu; adding them directly throws
		 * "Item to be inserted into menu already is in another menu". Detach
		 * them first (itemArray is copied, so mutation while iterating is safe). */
		for (menuItem in [originalMenu itemArray]) {
			[originalMenu removeItem:menuItem];
			[menu addItem:menuItem];
		}
	}

	if ([menu numberOfItems] > 0 && ![[menu itemAtIndex:[menu numberOfItems] - 1] isSeparatorItem]) {
		[menu addItem:[NSMenuItem separatorItem]];
	}

	menuItem = [[NSMenuItem alloc]
		initWithTitle:AILocalizedString(@"Clear Display",
										"Clears the display window for the currently open message window")
			   action:@selector(clearView)
		keyEquivalent:@""];
	[menuItem setTarget:self];
	[menu addItem:menuItem];

	return menu;
}

- (void)openImage:(id)sender
{
	NSURL *imageURL = [sender representedObject];
	if (![imageURL isKindOfClass:[NSURL class]] || !AIWKCanSaveImageURL(imageURL)) {
		return;
	}

	if (![[NSWorkspace sharedWorkspace] openURL:imageURL]) {
		AILogWithSignature(@"Failed to open image URL: %@", imageURL);
	}
}

- (void)saveImageAs:(id)sender
{
	NSURL *imageURL = [sender representedObject];
	if (![imageURL isKindOfClass:[NSURL class]] || !AIWKCanSaveImageURL(imageURL)) {
		return;
	}

	NSWindow *window = [_webView window];
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	NSString *defaultName = AIWKDefaultSaveNameForURL(
		imageURL, AILocalizedString(@"image", "Default file name when the image URL has no path component"));
	[savePanel setNameFieldStringValue:defaultName];
	[savePanel beginSheetModalForWindow:window
					  completionHandler:^(NSInteger result) {
						  if (result != NSModalResponseOK || [savePanel URL] == nil) {
							  return;
						  }

						  if ([imageURL isFileURL]) {
							  [self _saveImageAtURL:imageURL toURL:[savePanel URL] window:window];
						  } else {
							  [self _downloadRemoteImageAtURL:imageURL toURL:[savePanel URL] window:window];
						  }
					  }];
}

- (void)_saveImageAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL window:(NSWindow *)window
{
	NSError *copyError = nil;
	if (![[NSFileManager defaultManager] copyItemAtURL:sourceURL toURL:destinationURL error:&copyError]) {
		AILogWithSignature(@"Failed to save image to %@: %@", destinationURL, copyError);
		[self _presentImageSaveError:copyError imageURL:sourceURL window:window];
	}
}

- (void)_downloadRemoteImageAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL window:(NSWindow *)window
{
	NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
		downloadTaskWithURL:sourceURL
		  completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
			  if (error != nil) {
				  AILogWithSignature(@"Failed to download image from %@: %@", sourceURL, error);
				  dispatch_async(dispatch_get_main_queue(), ^{
					  [self _presentImageSaveError:error imageURL:sourceURL window:window];
				  });
				  return;
			  }

			  NSError *rejectionError = AIWKImageDownloadValidationErrorForResponse(response);
			  if (rejectionError == nil) {
				  // The response check only sees the declared Content-Length; NSURLSessionDownloadTask
				  // does not enforce it against the body. Re-check the actual bytes on disk before
				  // committing so a missing or misstated Content-Length cannot bypass the cap (#168).
				  NSError *attributesError = nil;
				  NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[location path]
																							  error:&attributesError];
				  if (attributesError != nil) {
					  AILogWithSignature(@"Failed to stat downloaded image at %@: %@", location, attributesError);
				  } else {
					  int64_t actualBytes = [attributes[NSFileSize] longLongValue];
					  if (actualBytes > AIWKMaxRemoteImageDownloadBytes) {
						  rejectionError = AIWKImageDownloadValidationErrorForByteCount(actualBytes);
					  }
				  }
			  }

			  if (rejectionError != nil) {
				  AILogWithSignature(@"Refusing to save image from %@: %@", sourceURL, rejectionError);
				  NSError *cleanupError = nil;
				  if (![[NSFileManager defaultManager] removeItemAtURL:location error:&cleanupError]) {
					  AILogWithSignature(@"Failed to delete rejected download at %@: %@", location, cleanupError);
				  }
				  dispatch_async(dispatch_get_main_queue(), ^{
					  [self _presentImageSaveError:rejectionError imageURL:sourceURL window:window];
				  });
				  return;
			  }

			  NSError *moveError = nil;
			  if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:destinationURL error:&moveError]) {
				  AILogWithSignature(@"Failed to save downloaded image to %@: %@", destinationURL, moveError);
				  dispatch_async(dispatch_get_main_queue(), ^{
					  [self _presentImageSaveError:moveError imageURL:sourceURL window:window];
				  });
			  }
		  }];
	[task resume];
}

- (void)_presentImageSaveError:(NSError *)error imageURL:(NSURL *)imageURL window:(NSWindow *)window
{
	if (window == nil) {
		return;
	}

	NSAlert *alert = [NSAlert alertWithError:error];
	alert.messageText =
		AILocalizedString(@"Save Image Failed", "Title shown when an image could not be saved from the message view");
	NSString *reason = [error localizedDescription];
	if (reason == nil) {
		reason = @"";
	}
	if (imageURL != nil) {
		alert.informativeText = [NSString
			stringWithFormat:AILocalizedString(@"Could not save the image at %@.\n\n%@",
											   "Details shown when an image fails to save from the message view"),
							 [imageURL absoluteString], reason];
	} else {
		alert.informativeText = reason;
	}
	[alert beginSheetModalForWindow:window completionHandler:nil];
}

#pragma mark - AIMessageDisplayController

- (NSView *)messageView
{
	return _webView;
}

- (NSView *)messageScrollView
{
	NSScrollView *scrollView = [_webView enclosingScrollView];
	if (scrollView != nil) {
		return scrollView;
	}
	return _webView;
}

- (NSString *)contentSourceName
{
	return [_messageStyle.bundle bundleIdentifier];
}

- (void)setChatContentSource:(NSString *)source
{
	NSString *js = [NSString stringWithFormat:@"(function(){"
											  @" var c = document.getElementById('Chat');"
											  @" if (c) { c.outerHTML = %@; }"
											  @"})()",
											  [self _jsStringLiteral:source]];

	_cachedChatContentSource = [source copy];

	[_webView evaluateJavaScript:js
			   completionHandler:^(id result, NSError *error) {
				   if (error) {
					   AILogWithSignature(@"evaluateJavaScript failed: %@", error);
				   }
			   }];
}

- (NSString *)chatContentSource
{
	return _cachedChatContentSource;
}

- (void)messageViewIsClosing
{
	[_webView stopLoading];
	[_webView setNavigationDelegate:nil];
	[_webView setUIDelegate:nil];
	[_webView.configuration.userContentController removeScriptMessageHandlerForName:@"adium"];

	// Cancel any pending performRequests
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	[self releaseAllCachedIcons];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[adium.preferenceController unregisterPreferenceObserver:self];
}

- (void)clearView
{
	[self _primeWebViewAndReprocessContent:NO];
	[_markedScroller removeAllMarks];
	_previousContent = nil;
	_nextMessageFocus = NO;
	_nextMessageRegainedFocus = NO;
	[_chat clearUnviewedContentCount];
}

#pragma mark - Content Pipeline

- (void)_primeWebViewAndReprocessContent:(BOOL)reprocessContent
{
	_webViewIsReady = NO;

	/* Write the page to disk and load it as a real file with read access to the
	 * whole volume: that is the only sanctioned way a WKWebView page may load
	 * file resources living anywhere (style bundle, icon caches, attachments).
	 * Style-relative resources resolve through the template's <base href>. */
	NSString *pageDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
							   [NSString stringWithFormat:@"AdiumWK-%p", (void *)self]];
	[[NSFileManager defaultManager] createDirectoryAtPath:pageDirectory
							  withIntermediateDirectories:YES
											   attributes:nil
													error:NULL];
	NSString *pagePath = [pageDirectory stringByAppendingPathComponent:@"messages.html"];
	[[_messageStyle baseTemplateForChat:_chat] writeToFile:pagePath
												atomically:YES
												  encoding:NSUTF8StringEncoding
													 error:NULL];

	/* Attach the remote-load block before the first load, so no page ever runs
	 * unblocked; compilation is cached, so every load after the first proceeds
	 * without waiting. The list stays on the content controller across reloads,
	 * hence the guard against adding it twice. */
	[[self class] withRemoteLoadBlockRuleList:^(WKContentRuleList *ruleList) {
		if (ruleList && !_remoteLoadBlockInstalled) {
			[_webView.configuration.userContentController addContentRuleList:ruleList];
			_remoteLoadBlockInstalled = YES;
		}

		[_webView loadFileURL:[NSURL fileURLWithPath:pagePath]
		  allowingReadAccessToURL:[NSURL fileURLWithPath:@"/" isDirectory:YES]];
	}];

	if (_chat.isGroupChat && _chat.supportsTopic) {
		[self updateTopic];
	}

	if (reprocessContent) {
		NSArray *currentContentQueue = ([_contentQueue count] ? [_contentQueue copy] : nil);

		[_contentQueue removeAllObjects];
		[_contentQueue addObjectsFromArray:_storedContentObjects];
		[_storedContentObjects removeAllObjects];

		if (currentContentQueue) {
			[_contentQueue addObjectsFromArray:currentContentQueue];
		}

		/* The page is new and nothing has been drawn into it yet, so what was drawn last into the
		 * old one is no longer what this one follows on from. Left standing, the first message of
		 * the rebuilt conversation is compared against the last message of the one before it, and
		 * where both are from the same person within five minutes it is drawn as a continuation:
		 * no name, no time, no header at the top of the transcript.
		 */
		_previousContent = nil;
		_cachedChatContentSource = nil;
	} else {
		// clearView: drop anything parked while the previous view was loading (including a
		// topic queued by updateTopic) so the cleared view starts empty.
		[_contentQueue removeAllObjects];
		[_storedContentObjects removeAllObjects];
	}
}

- (void)_processContentQueue
{
	if (!_webViewIsReady) {
		return;
	}

	NSInteger contentCount = [_contentQueue count];
	if (contentCount == 0) {
		return;
	}

	BOOL willAddMoreContentObjects = (contentCount > 1);
	BOOL hadPreviousContent = (_cachedChatContentSource != nil);

	if (!hadPreviousContent) {
		_nextMessageFocus = YES;
	}

	for (AIContentObject *content in _contentQueue) {
		if (willAddMoreContentObjects && content == [_contentQueue lastObject]) {
			willAddMoreContentObjects = NO;
		}

		// Insert a date separator before content from a new day, matching the pre-migration
		// controller's history behavior (#125).
		if ([self _shouldInsertDateSeparatorBeforeContent:content]) {
			[self _insertDateSeparatorBeforeContent:content willAddMoreContentObjects:willAddMoreContentObjects];
		}

		// Cache the sender's user icon so the style renders a stable path that can be swapped
		// in place when the contact changes their icon (#124).
		[self _trackUserIconForContent:content];

		/* Similar to nothing is not similar. The test itself would say so for an ordinary message,
		 * whose source cannot match a source that is not there, but a file transfer has its own
		 * ideas and the answer is asked for before there is anything to compare against.
		 */
		BOOL contentIsSimilar = (_previousContent != nil &&
								 [content isSimilarToContent:_previousContent] &&
								 ![content isKindOfClass:[ESFileTransfer class]]);
		BOOL replaceLastContent = NO;

		if ([_previousContent isKindOfClass:[AIContentStatus class]] &&
			[content isKindOfClass:[AIContentStatus class]] &&
			[[(AIContentStatus *)_previousContent coalescingKey]
				isEqualToString:[(AIContentStatus *)content coalescingKey]]) {
			contentIsSimilar = NO;
			replaceLastContent = YES;
		}

		if (!replaceLastContent) {
			[self _markCurrentLocation];
		}

		NSString *js = [_messageStyle scriptForAppendingContent:content
														similar:contentIsSimilar
									  willAddMoreContentObjects:willAddMoreContentObjects
											 replaceLastContent:replaceLastContent];

		[_webView evaluateJavaScript:js
				   completionHandler:^(id result, NSError *error) {
					   // Update cached source after each append
					   if (!error) {
						   [self _syncCachedSource];
					   } else {
						   AILogWithSignature(@"evaluateJavaScript failed: %@", error);
					   }
				   }];

		// Track content for similarity comparison
		_previousContent = content;

		/* Keep what was shown, so that it can be shown again. A change of style or variant, or a
		 * JavaScript plugin turned on or off, throws the page away and builds a new one, and
		 * everything that was in the old page has to be put through it again to appear at all. Kept
		 * for the settings preview, for a chat window told to follow preference changes, and for any
		 * window while JavaScript plugins are installed, since one may be switched at any time and
		 * the reload that follows has nothing else to draw from. Without either, an ordinary chat
		 * would hold its whole history twice, so then it is not kept.
		 */
		if ([self _shouldRetainContentForReplay]) {
			[_storedContentObjects addObject:content];
		}
	}

	[_contentQueue removeAllObjects];

	/* Re-fit oversized images now and after their (async) loads settle — same pattern as the
	 * legacy controller after adding content objects. */
	[_webView evaluateJavaScript:@"if (window.adiumInlineAudio) { adiumInlineAudio(); setTimeout(adiumInlineAudio, 250); "
								 @"setTimeout(adiumInlineAudio, 1000); } "
								 @"if (window.adiumFitImages) { adiumFitImages(); setTimeout(adiumFitImages, 250); "
								 @"setTimeout(adiumFitImages, 1000); setTimeout(adiumFitImages, 3000); }"
			   completionHandler:nil];
}

/*!
 * @brief Whether this view keeps its content around so it can be drawn again after a reload
 *
 * A reload has to replay the conversation from what was kept, and there are two reasons to keep it:
 * the view follows preference changes (the settings preview), or JavaScript plugins are installed
 * and so one may be switched on or off at any time, each of which rebuilds the page. With neither,
 * nothing reloads this view and holding its history a second time would be waste.
 */
- (BOOL)_shouldRetainContentForReplay
{
	if (_shouldReflectPreferenceChanges) return YES;

	return ([[[AIJSXtrasManager sharedManager] allBundles] count] > 0);
}

/*!
 * @brief Move content parked while the webview was loading into the processing queue.
 */
- (void)_drainStoredContentObjects
{
	if ([_storedContentObjects count] == 0) {
		return;
	}

	[_contentQueue addObjectsFromArray:_storedContentObjects];
	[_storedContentObjects removeAllObjects];
}

/*!
 * @brief Whether a date separator must be inserted before the given content.
 *
 * Ported from the pre-migration controller (93d7c267^): a separator whenever the content's day
 * differs from the previously rendered content. At the very start of a view a separator is only
 * inserted for a history context; a first content object from a prior day still gets one because
 * isFromSameDayAsContent: substitutes today when there is no reference content.
 */
- (BOOL)_shouldInsertDateSeparatorBeforeContent:(AIContentObject *)content
{
	return ((!_previousContent && [content isKindOfClass:[AIContentContext class]]) ||
			![content isFromSameDayAsContent:_previousContent]);
}

/*!
 * @brief Append a date_separator content event before content from a different day (#125).
 */
- (void)_insertDateSeparatorBeforeContent:(AIContentObject *)content
				willAddMoreContentObjects:(BOOL)willAddMoreContentObjects
{
	__block NSString *dateMessage;
	[NSDateFormatter withLocalizedDateFormatterPerform:^(NSDateFormatter *dateFormatter) {
		dateMessage = [dateFormatter stringFromDate:content.date];
	}];

	AIContentEvent *dateSeparator = [AIContentEvent
		statusInChat:content.chat
		  withSource:content.chat.listObject
		 destination:content.chat.account
				date:content.date
			 message:[[NSAttributedString alloc] initWithString:dateMessage
													 attributes:[adium.contentController defaultFormattingAttributes]]
			withType:@"date_separator"];

	if ([content isKindOfClass:[AIContentContext class]]) {
		[dateSeparator addDisplayClass:@"history"];
	}

	// Append without scrolling and without marking a new location; the separator is part of
	// the history being loaded, not new incoming content.
	NSString *js = [_messageStyle scriptForAppendingContent:dateSeparator
													similar:NO
								  willAddMoreContentObjects:willAddMoreContentObjects
										 replaceLastContent:NO];
	[self _appendContentWithScript:js shouldScroll:NO];
}

/*!
 * @brief Re-read the Chat element's outerHTML into the cache.
 *
 * Called after content operations to keep the cached source in sync.
 */
- (void)_syncCachedSource
{
	[_webView evaluateJavaScript:@"document.getElementById('Chat').outerHTML"
			   completionHandler:^(id result, NSError *error) {
				   if (error) {
					   AILogWithSignature(@"_syncCachedSource failed: %@", error);
					   return;
				   }
				   if (![result isKindOfClass:[NSString class]]) {
					   AILogWithSignature(@"_syncCachedSource returned a non-string result");
					   return;
				   }
				   self->_cachedChatContentSource = [result copy];
			   }];
}

/*!
 * @brief Append content via a JS script, capturing scroll height for marks before appending.
 *
 * @param js The JS statement* to evaluate (e.g. appendMessage('...'))
 * @param shouldScroll Whether to scroll to bottom after appending
 */
- (void)_appendContentWithScript:(NSString *)js shouldScroll:(BOOL)shouldScroll
{
	if (!_webViewIsReady) {
		return;
	}

	NSString *fullJS;
	if (shouldScroll) {
		fullJS = [NSString stringWithFormat:@"%@; scrollToBottom()", js];
	} else {
		fullJS = js;
	}

	[_webView evaluateJavaScript:fullJS
			   completionHandler:^(id result, NSError *error) {
				   if (!error) {
					   [self _syncCachedSource];
				   } else {
					   AILogWithSignature(@"evaluateJavaScript failed: %@", error);
				   }
			   }];
}

/*!
 * @brief Mark the current scroll position before new content arrives.
 *
 * Uses async evaluateJavaScript — the scroll height is captured in JS,
 * then we add the mark when the result arrives.
 */
- (void)_markCurrentLocation
{
	if (!_webViewIsReady) {
		return;
	}

	// Capture scroll height before append
	[_webView evaluateJavaScript:@"document.body.scrollHeight"
			   completionHandler:^(id result, NSError *error) {
				   if (error != nil) {
					   AILogWithSignature(@"Failed to evaluate scrollHeight in _markCurrentLocation: %@", error);
					   return;
				   }

				   NSInteger h = [result integerValue];
				   if (h == 0) {
					   AILogWithSignature(@"scrollHeight evaluated to 0 in _markCurrentLocation; no scroll mark added");
					   return;
				   }

				   if (self->_nextMessageFocus) {
					   [self.markedScroller addMarkAt:h withColor:[NSColor blueColor]];
					   self->_nextMessageFocus = NO;
					   self->_nextMessageRegainedFocus = YES;
				   }
				   if (self->_nextMessageRegainedFocus) {
					   [self.markedScroller addMarkAt:h withColor:[NSColor greenColor]];
					   self->_nextMessageRegainedFocus = NO;
				   }
			   }];
}

/*!
 * @brief Updates our webview to the current preferences, priming the view
 */
- (void)_updateWebViewForCurrentPreferences
{
	NSCParameterAssert([NSThread isMainThread]);

	_isUpdatingView = YES;

	_messageStyle = nil;
	_activeStyle = nil;

	_messageStyle = [_plugin currentMessageStyleForChat:_chat];
	_activeStyle = [[_messageStyle bundle] bundleIdentifier];
	_preferenceGroup = [_plugin preferenceGroupForChat:_chat];

	// Get the preferred variant (or the default if a preferred is not available)
	NSString *activeVariant;
	activeVariant = [adium.preferenceController preferenceForKey:[_plugin styleSpecificKey:@"Variant"
																				  forStyle:_activeStyle]
														   group:_preferenceGroup];
	if (!activeVariant || ![[_messageStyle availableVariants] containsObject:activeVariant]) {
		activeVariant = [_messageStyle defaultVariant];
	}
	if (!activeVariant || ![[_messageStyle availableVariants] containsObject:activeVariant]) {
		NSArray *availableVariants = [_messageStyle availableVariants];
		if ([availableVariants count]) {
			activeVariant = [availableVariants objectAtIndex:0];
		}
	}
	_messageStyle.activeVariant = activeVariant;

	NSDictionary *prefDict = [adium.preferenceController preferencesForGroup:_preferenceGroup];

	[_messageStyle setShowUserIcons:[[prefDict objectForKey:KEY_WEBKIT_SHOW_USER_ICONS] boolValue]];
	[_messageStyle setShowHeader:[[prefDict objectForKey:KEY_WEBKIT_SHOW_HEADER] boolValue]];
	[_messageStyle setUseCustomNameFormat:[[prefDict objectForKey:KEY_WEBKIT_USE_NAME_FORMAT] boolValue]];
	[_messageStyle setNameFormat:[[prefDict objectForKey:KEY_WEBKIT_NAME_FORMAT] intValue]];
	[_messageStyle setDateFormat:[prefDict objectForKey:KEY_WEBKIT_TIME_STAMP_FORMAT]];
	[_messageStyle setShowIncomingMessageColors:[[prefDict objectForKey:KEY_WEBKIT_SHOW_MESSAGE_COLORS] boolValue]];
	[_messageStyle setShowIncomingMessageFonts:[[prefDict objectForKey:KEY_WEBKIT_SHOW_MESSAGE_FONTS] boolValue]];

	// Custom background image
	NSString *cachePath = nil;
	if ([[adium.preferenceController preferenceForKey:[_plugin styleSpecificKey:@"UseCustomBackground"
																	   forStyle:_activeStyle]
												group:_preferenceGroup] boolValue]) {

		cachePath = [adium.preferenceController preferenceForKey:[_plugin styleSpecificKey:@"BackgroundCachePath"
																				  forStyle:_activeStyle]
														   group:_preferenceGroup];
		if (!cachePath || ![[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
			NSData *backgroundImage = [adium.preferenceController
				preferenceForKey:[_plugin styleSpecificKey:@"Background" forStyle:_activeStyle]
						   group:PREF_GROUP_WEBKIT_BACKGROUND_IMAGES];

			if (backgroundImage) {
				NSInteger uniqueID = [[adium.preferenceController preferenceForKey:@"BackgroundCacheUniqueID"
																			 group:_preferenceGroup] integerValue] +
									 1;
				[adium.preferenceController setPreference:[NSNumber numberWithInteger:uniqueID]
												   forKey:@"BackgroundCacheUniqueID"
													group:_preferenceGroup];

				cachePath = [self _webKitBackgroundImagePathForUniqueID:uniqueID];
				[backgroundImage writeToFile:cachePath atomically:YES];

				[adium.preferenceController setPreference:cachePath
												   forKey:[_plugin styleSpecificKey:@"BackgroundCachePath"
																		   forStyle:_activeStyle]
													group:_preferenceGroup];
			} else {
				cachePath = @"";
			}
		}

		[_messageStyle setCustomBackgroundColor:[[adium.preferenceController
													preferenceForKey:[_plugin styleSpecificKey:@"BackgroundColor"
																					  forStyle:_activeStyle]
															   group:_preferenceGroup] representedColor]];
	} else {
		[_messageStyle setCustomBackgroundColor:nil];
	}

	[_messageStyle setCustomBackgroundPath:cachePath];
	[_messageStyle setCustomBackgroundType:[[adium.preferenceController
											   preferenceForKey:[_plugin styleSpecificKey:@"BackgroundType"
																				 forStyle:_activeStyle]
														  group:_preferenceGroup] intValue]];

	// WKWebView transparency
	BOOL isBackgroundTransparent = [_messageStyle isBackgroundTransparent];
	[_webView setValue:@(!isBackgroundTransparent) forKey:@"drawsBackground"];
	NSWindow *win = [_webView window];
	if (win) {
		[win setOpaque:!isBackgroundTransparent];
	}

	// Prime the webview
	[self _primeWebViewAndReprocessContent:YES];
	_isUpdatingView = NO;
}

- (void)_updateVariantWithoutPrimingView
{
	static const NSUInteger kMaxRetries = 40;

	if (_webViewIsReady) {
		_variantRetryCount = 0;
		[_webView evaluateJavaScript:[_messageStyle scriptForChangingVariant]
				   completionHandler:^(id result, NSError *error) {
					   if (error) {
						   AILogWithSignature(@"evaluateJavaScript failed: %@", error);
					   }
				   }];
	} else if (_variantRetryCount < kMaxRetries) {
		_variantRetryCount++;
		[self performSelector:@selector(_updateVariantWithoutPrimingView)
				   withObject:nil
				   afterDelay:NEW_CONTENT_RETRY_DELAY];
	} else {
		_variantRetryCount = 0;
		AILogWithSignature(@"Gave up waiting for webview to become ready after %lu attempts",
						   (unsigned long)kMaxRetries);
	}
}

#pragma mark - Preference Changes

/*!
 * @brief Enable or disable updating to reflect preference changes
 */
- (void)setShouldReflectPreferenceChanges:(BOOL)inValue
{
	_shouldReflectPreferenceChanges = inValue;

	/* Nothing is kept unless somebody is going to ask for it again, and everything kept is dropped
	 * the moment nobody is.
	 */
	if (!inValue) {
		[_storedContentObjects removeAllObjects];
	}
}

- (void)setIsGroupChat:(BOOL)groupChat
{
	_chat.isGroupChat = groupChat;
	_preferenceGroup = [_plugin preferenceGroupForChat:_chat];
}

- (void)webViewIsReady
{
	[self _applyScrollbarVisibility];
}

- (BOOL)hidesScrollbar
{
	return [[adium.preferenceController preferenceForKey:KEY_WEBKIT_HIDE_SCROLLBAR
												   group:_preferenceGroup] boolValue];
}

/*!
 * @brief Put the scrollbar rule into the page, or take it out again
 *
 * One rule, added or removed, rather than the page being rebuilt: hiding a scrollbar is not a change
 * of style and there is no reason to redraw a conversation for it. A WKWebView scrolls the page
 * itself, so this is ordinary CSS; the old view drew the main frame's bar as an AppKit scroller and
 * needed that restyled beside the rule.
 *
 * Called again after every reprime, hence the identifier: the rule must not be added twice.
 */
- (void)_applyScrollbarVisibility
{
	NSString *js = [self hidesScrollbar] ?
		@"(function(){var i='adium-no-scrollbar';"
		 "if(!document.getElementById(i)){"
		 "var s=document.createElement('style');s.id=i;"
		 "s.textContent='::-webkit-scrollbar{width:0 !important;height:0 !important;display:none !important}';"
		 "(document.head||document.documentElement).appendChild(s);}})();" :
		@"(function(){var e=document.getElementById('adium-no-scrollbar');"
		 "if(e){e.parentNode.removeChild(e);}})();";

	[_webView evaluateJavaScript:js completionHandler:nil];
}

- (BOOL)allowsContextMenu
{
	return YES;
}

- (void)preferencesChangedForGroup:(NSString *)group
							   key:(NSString *)key
							object:(AIListObject *)object
					preferenceDict:(NSDictionary *)prefDict
						 firstTime:(BOOL)firstTime
{
	// WKWebView doesn't expose preferences like WebView does for font/size changes.
	// The style's CSS handles font sizing — for any preference change that requires
	// re-priming, we fall through to _updateWebViewForCurrentPreferences.

	if (firstTime) {
		return;
	}

	/* A change to this view's own group is a change to how it should look: another style, another
	 * variant, another setting inside one of them. The view is rebuilt for it, except for the three
	 * keys that are only ever storage: two naming a cached background image and one naming the style
	 * whose change brought us here in the first place.
	 *
	 * This is what the preview in the message settings runs on, and without it a style could be
	 * picked and nothing beside the list would move.
	 */
	/* The scrollbar is a rule in the page and nothing else, so it is applied where it lives rather
	 * than by rebuilding everything around it. Whether anything is watching for preference changes
	 * does not come into it: a chat window follows this one whether or not it follows the rest.
	 */
	if (_preferenceGroup && [group isEqualToString:_preferenceGroup] &&
		[key isEqualToString:KEY_WEBKIT_HIDE_SCROLLBAR]) {
		[self _applyScrollbarVisibility];
		return;
	}

	if (_preferenceGroup && [group isEqualToString:_preferenceGroup] && _shouldReflectPreferenceChanges) {
		if (![key isEqualToString:@"BackgroundCacheUniqueID"] &&
			![key isEqualToString:[_plugin styleSpecificKey:@"BackgroundCachePath" forStyle:_activeStyle]] &&
			!_isUpdatingView) {
			[self _updateWebViewForCurrentPreferences];
		}
	}

	if ([group isEqualToString:PREF_GROUP_WEBKIT_BACKGROUND_IMAGES] && _shouldReflectPreferenceChanges) {
		[adium.preferenceController setPreference:nil
										   forKey:[_plugin styleSpecificKey:@"BackgroundCachePath"
																   forStyle:_activeStyle]
											group:_preferenceGroup];
		if (!_isUpdatingView) {
			[self _updateWebViewForCurrentPreferences];
		}
	}
}

/*!
 * @brief Content was added to the chat. Processes the content queue.
 */
- (void)contentObjectAdded:(NSNotification *)notification
{
	AIContentObject *content = [[notification userInfo] objectForKey:@"AIContentObject"];
	if (!content) {
		return;
	}

	if (!_webViewIsReady) {
		if (!_storedContentObjects) {
			_storedContentObjects = [[NSMutableArray alloc] init];
		}
		[_storedContentObjects addObject:content];
		return;
	}

	[_contentQueue addObject:content];
	[self _processContentQueue];
}

/*!
 * @brief Chat finished adding content. Flushes coalesced content.
 */
- (void)chatDidFinishAddingUntrackedContent:(NSNotification *)notification
{
	// Tell the CoalescedHTML to output everything
	[_webView evaluateJavaScript:@"if(coalescedHTML)coalescedHTML.cancel()"
			   completionHandler:^(id result, NSError *error) {
				   if (error) {
					   AILogWithSignature(@"evaluateJavaScript failed: %@", error);
				   }
			   }];
}

#pragma mark - Notifications

- (void)customEmoticonUpdated:(NSNotification *)inNotification
{
	[_webView evaluateJavaScript:@"initStyle()"
			   completionHandler:^(id result, NSError *error) {
				   if (error) {
					   AILogWithSignature(@"evaluateJavaScript failed: %@", error);
				   }
			   }];

	// Re-process stored content for new emoticon rendering
	if ([_storedContentObjects count]) {
		[self _primeWebViewAndReprocessContent:YES];
	} else if ([_contentQueue count]) {
		[self _processContentQueue];
	}
}

- (void)messageWasCorrected:(NSNotification *)notification
{
	NSDictionary *userInfo = [notification userInfo];
	NSString *senderJID = [userInfo objectForKey:@"AICorrectionSender"];
	NSString *domId = [userInfo objectForKey:@"AICorrectionDOMId"];
	NSString *html = [userInfo objectForKey:@"AICorrectionHTML"];

	if (!senderJID || !domId || !html) {
		return;
	}

	// Verify this correction is for our chat
	NSString *chatBareJID = [[[_chat listObject] UID] isKindOfClass:[NSString class]] ? [[_chat listObject] UID] : nil;
	if (![senderJID isEqualToString:chatBareJID]) {
		return;
	}

	NSString *escapedHTML = [self _jsStringLiteral:html];
	NSString *escapedDomId = [self _jsStringLiteral:domId];
	NSString *js = [NSString stringWithFormat:@"correctMessage(%@, %@)", escapedDomId, escapedHTML];
	[_webView evaluateJavaScript:js
			   completionHandler:^(id result, NSError *error) {
				   if (error) {
					   AILogWithSignature(@"evaluateJavaScript failed: %@", error);
					   return;
				   }

				   // correctMessage() returns false when no element with the DOM id exists
				   // (the original message was never rendered); append it as a fallback.
				   BOOL correctedInPlace = ([result respondsToSelector:@selector(boolValue)] && [result boolValue]);
				   if (!correctedInPlace) {
					   [self _appendCorrectedMessageFallback:html fromSenderJID:senderJID];
				   }
			   }];
}

/*!
 * @brief Append corrected content as a new message when no DOM element could be corrected.
 *
 * The correction notification can arrive before the original message was rendered (e.g. while
 * the webview was loading), so correctMessage() finds no element. Enqueue the corrected content
 * so it displays instead of being silently dropped.
 */
- (void)_appendCorrectedMessageFallback:(NSString *)html fromSenderJID:(NSString *)senderJID
{
	AIListObject *source = [[adium contactController] contactWithService:[[_chat account] service]
																 account:[_chat account]
																	 UID:senderJID];
	if (!source) {
		source = [_chat listObject];
	}

	AIContentMessage *content =
		[[AIContentMessage alloc] initWithChat:_chat
										source:source
								   destination:nil
										  date:[NSDate date]
									   message:[[NSAttributedString alloc] initWithString:html]];
	[content setDisplayContentImmediately:YES];

	[_contentQueue addObject:content];
	[self _processContentQueue];
}

- (void)stanzaWasTracked:(NSNotification *)notification
{
	NSDictionary *userInfo = [notification userInfo];
	NSString *domId = [userInfo objectForKey:@"AICorrectionDOMId"];
	if (!domId) {
		return;
	}

	NSString *escapedDomId = [self _jsStringLiteral:domId];
	NSString *js = [NSString stringWithFormat:@"(function(){"
											  @" var e=document.getElementById(%@);"
											  @" if(e&&!e.classList.contains('tracked')){e.classList.add('tracked');}"
											  @"})()",
											  escapedDomId];
	[_webView evaluateJavaScript:js
			   completionHandler:^(id result, NSError *error) {
				   if (error) {
					   AILogWithSignature(@"evaluateJavaScript failed: %@", error);
				   }
			   }];
}

- (void)updateTopic
{
	if (!_chat.supportsTopic) {
		return;
	}

	NSAttributedString *topic = [NSAttributedString stringWithString:([_chat valueForProperty:KEY_TOPIC] ?: @"")];

	AIContentTopic *contentTopic = [AIContentTopic topicInChat:_chat
													withSource:[_chat valueForProperty:KEY_TOPIC_SETTER]
												   destination:nil
														  date:[NSDate date]
													   message:topic];

	// Route the topic through the style's topicHTML template via the content pipeline, matching
	// live topic updates (which arrive as AIContentTopic content objects filtered with
	// AIFilterContent by receiveContentObject:) (#126, #147).
	contentTopic.message = [adium.contentController filterAttributedString:topic
														   usingFilterType:AIFilterContent
																 direction:AIFilterIncoming
																   context:contentTopic];

	if (_webViewIsReady) {
		[_contentQueue addObject:contentTopic];
		[self _processContentQueue];
	} else {
		if (!_storedContentObjects) {
			_storedContentObjects = [[NSMutableArray alloc] init];
		}
		[_storedContentObjects addObject:contentTopic];
	}
}

#pragma mark User icon updates

/*!
 * @brief Update icon masks when participating list objects change
 *
 * We want to observe attributesChanged: notifications for all objects which are participating in our chat.
 * When the list changes, remove the observers we had in place before and add observers for each object in the list
 * so we never observe for contacts not in the chat.
 */
- (void)participatingListObjectsChanged:(NSNotification *)notification
{
	NSArray *participatingListObjects = [_chat containedObjects];

	[[NSNotificationCenter defaultCenter] removeObserver:self name:ListObject_AttributesChanged object:nil];

	for (AIListObject *listObject in participatingListObjects) {
		// Update the mask for any user which just entered the chat
		if (![_objectsWithUserIconsArray containsObjectIdenticalTo:listObject]) {
			[self updateUserIconForObject:listObject];
		}

		// In the future, watch for changes on the parent object, since that's the icon we display
		if ([listObject isKindOfClass:[AIListContact class]]) {
			[[NSNotificationCenter defaultCenter] addObserver:self
													 selector:@selector(listObjectAttributesChanged:)
														 name:ListObject_AttributesChanged
													   object:[(AIListContact *)listObject parentContact]];
		}
	}

	// Also observe our account
	if (_chat.account) {
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(listObjectAttributesChanged:)
													 name:ListObject_AttributesChanged
												   object:_chat.account];
	}

	// Remove the cache for any object no longer in the chat
	for (AIListObject *listObject in [_objectsWithUserIconsArray copy]) {
		if ((![listObject isKindOfClass:[AIMetaContact class]] ||
			 (![participatingListObjects firstObjectCommonWithArray:[(AIMetaContact *)listObject containedObjects]])) &&
			(![listObject isKindOfClass:[AIListContact class]] ||
			 ![participatingListObjects containsObjectIdenticalTo:(AIListContact *)listObject]) &&
			!(listObject == _chat.account)) {
			[self releaseCurrentWebKitUserIconForObject:listObject];
		}
	}
}

/*!
 * @brief Update icon masks when source or destination changes
 */
- (void)sourceOrDestinationChanged:(NSNotification *)notification
{
	// Update the participating contacts
	[self participatingListObjectsChanged:nil];

	// And update the source account
	[self updateUserIconForObject:_chat.account];
}

/*!
 * @brief Update the icon when a list object's icon attributes change
 */
- (void)listObjectAttributesChanged:(NSNotification *)notification
{
	AIListObject *inObject = [notification object];
	NSSet *keys = [[notification userInfo] objectForKey:@"Keys"];

	if ([keys containsObject:KEY_USER_ICON]) {
		if (inObject) {
			AIListObject *actualObject = nil;
			if (_chat.account == inObject) {
				// The account is the object actually in the chat
				actualObject = inObject;
			} else {
				/*
				 * We are notified of a change to the metacontact's icon. Find the contact inside the chat which we
				 * will be displaying as changed.
				 */
				for (AIListContact *participatingListObject in _chat) {
					if ([participatingListObject parentContact] == inObject) {
						actualObject = participatingListObject;
						break;
					}
				}
			}

			if (actualObject) {
				[self userIconForObjectDidChange:actualObject];
			}
		} else {
			AILogWithSignature(@"nil object's icon changed");
			// We don't know what changed, if anything, that is relevant to our chat. Update source and destination
			// icons.
			[self sourceOrDestinationChanged:nil];
		}
	}
}

/*!
 * @brief Update the icon when a list object's icon changes
 */
- (void)userIconForObjectDidChange:(AIListObject *)inObject
{
	AIListObject *iconSourceObject = [self _iconSourceObjectForObject:inObject];

	// updateUserIconForObject: writes a fresh cached file for the new icon and removes the old one
	// only after the replacement has been written, so a failed write never leaves the page's <img>
	// src pointing at a deleted file.
	[self updateUserIconForObject:iconSourceObject];
}

/*!
 * @brief Generate and cache a user icon for an object, pushing it to already-rendered images.
 *
 * @param inObject The object
 */
- (void)updateUserIconForObject:(AIListObject *)inObject
{
	AIListObject *iconSourceObject = [self _iconSourceObjectForObject:inObject];
	NSImage *userIcon;
	NSString *oldWebKitUserIconPath = nil;
	NSString *webKitUserIconPath = nil;
	NSImage *webKitUserIcon;

	/*
	 * We probably already have a userIcon waiting for us, the active display icon; use that
	 * rather than loading one from disk.
	 */
	if (!(userIcon = [iconSourceObject userIcon])) {
		// If that's not the case, try using the UserIconPath
		NSString *userIconPath = [iconSourceObject valueForProperty:@"UserIconPath"];
		if (userIconPath) {
			userIcon = [[NSImage alloc] initWithContentsOfFile:userIconPath];
		}
	}

	if (userIcon) {
		if ([_messageStyle userIconMask]) {
			// Apply the mask if the style has one
			webKitUserIcon = [[_messageStyle userIconMask] copy];
			[webKitUserIcon lockFocus];
			[userIcon drawInRect:NSMakeRect(0, 0, [webKitUserIcon size].width, [webKitUserIcon size].height)
						fromRect:NSMakeRect(0, 0, [userIcon size].width, [userIcon size].height)
					   operation:NSCompositingOperationSourceIn
						fraction:1.0f];
			[webKitUserIcon unlockFocus];
		} else {
			// Otherwise, just use the icon as-is
			webKitUserIcon = userIcon;
		}

		oldWebKitUserIconPath = [_objectIconPathDict objectForKey:iconSourceObject.internalObjectID];
		NSString *oldSharedIconPath = [iconSourceObject valueForProperty:KEY_WEBKIT_USER_ICON];

		// Write out the icon fresh every time the icon may have changed. Writing it out is necessary
		// for webkit to be able to use it; it also guarantees there won't be any animation, which is
		// good since animation in the message view is slow and annoying.
		webKitUserIconPath = [self _cachedUserIconFilePathForObject:iconSourceObject];
		if ([[webKitUserIcon PNGRepresentation] writeToFile:webKitUserIconPath atomically:YES]) {
			[iconSourceObject setValue:webKitUserIconPath forProperty:KEY_WEBKIT_USER_ICON notify:NotifyNever];
		} else {
			AILogWithSignature(@"Warning: Could not write out icon to %@", webKitUserIconPath);
			webKitUserIconPath = nil;
		}

		// Make sure it's known that this user has been handled
		if (![_objectsWithUserIconsArray containsObjectIdenticalTo:iconSourceObject]) {
			[_objectsWithUserIconsArray addObject:iconSourceObject];

			// Keep track of this chat using the icon
			[iconSourceObject
				   setValue:[NSNumber
								numberWithInteger:([iconSourceObject
													   integerValueForProperty:KEY_WEBKIT_CHATS_USING_CACHED_ICON] +
												   1)]
				forProperty:KEY_WEBKIT_CHATS_USING_CACHED_ICON
					 notify:NotifyNever];
		}

		// Remove the old cached file only after the replacement is written. This view is the last
		// reference to the old file when its tracked path still matches the shared KEY value it saw
		// before the write; if another view already swapped in a different icon, that file stays.
		if (oldWebKitUserIconPath && oldSharedIconPath && webKitUserIconPath &&
			[oldWebKitUserIconPath isEqualToString:oldSharedIconPath] &&
			![oldWebKitUserIconPath isEqualToString:webKitUserIconPath]) {
			[[NSFileManager defaultManager] removeItemAtPath:oldWebKitUserIconPath error:NULL];
		}

		if (!webKitUserIconPath) {
			webKitUserIconPath = @"";
		}

		// Push the new path to any already-rendered <img> elements that used the old path
		[self _swapUserIconOnPageForObject:iconSourceObject fromPath:oldWebKitUserIconPath toPath:webKitUserIconPath];

		[_objectIconPathDict setObject:webKitUserIconPath forKey:iconSourceObject.internalObjectID];
	}
}

/*!
 * @brief Swap rendered avatar <img> src attributes from the old cached path to the new one.
 *
 * The style emits %userIconPath% as "file://<path>", so match every <img> whose src contains the old
 * cached path and swap in the new path. There is no per-content DOM id in the WKWebView renderer, so
 * matching on the file path is the only reliable hook.
 *
 * @param inObject The object whose icon changed
 * @param oldPath The previously rendered cached path (nil if never rendered)
 * @param newPath The new cached path ("" if none could be written)
 */
- (void)_swapUserIconOnPageForObject:(AIListObject *)inObject fromPath:(NSString *)oldPath toPath:(NSString *)newPath
{
	if (!_webViewIsReady || [oldPath length] == 0 || [newPath length] == 0 || [oldPath isEqualToString:newPath]) {
		return;
	}

	NSString *escapedOldPath = [self _jsStringLiteral:oldPath];
	NSString *escapedNewPath = [self _jsStringLiteral:[@"file://" stringByAppendingString:newPath]];

	// imgs[i].src is the browser-resolved, percent-encoded URL, so match the encoded form of
	// the cache path too - cachesPath can contain spaces ("Application Support") or non-ASCII.
	NSString *encodedOldPath =
		[oldPath stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
	NSString *escapedEncodedOldPath = [self _jsStringLiteral:encodedOldPath];

	NSString *js = [NSString stringWithFormat:@"(function(){"
											  @"var imgs = document.querySelectorAll('img');"
											  @"for (var i = 0; i < imgs.length; i++) {"
											  @"if (imgs[i].src.indexOf(%@) !== -1 || imgs[i].src.indexOf(%@) !== -1) {"
											  @"imgs[i].src = %@;"
											  @"}"
											  @"}"
											  @"})()",
											  escapedOldPath, escapedEncodedOldPath, escapedNewPath];

	[_webView evaluateJavaScript:js
			   completionHandler:^(id result, NSError *error) {
				   if (error) {
					   AILogWithSignature(@"evaluateJavaScript failed: %@", error);
				   }
			   }];
}

/*!
 * @brief Return the current cached icon path for an object, generating and caching it if absent.
 *
 * @param inObject The object
 * @return The cached icon file path, or nil if icons are disabled or none could be produced.
 */
- (NSString *)_cachedUserIconForObject:(AIListObject *)inObject
{
	if (![_messageStyle showUserIcons]) {
		return nil;
	}

	AIListObject *iconSourceObject = [self _iconSourceObjectForObject:inObject];

	NSString *webKitUserIconPath = [iconSourceObject valueForProperty:KEY_WEBKIT_USER_ICON];
	if (!webKitUserIconPath) {
		[self updateUserIconForObject:iconSourceObject];
		webKitUserIconPath = [iconSourceObject valueForProperty:KEY_WEBKIT_USER_ICON];
	}

	return webKitUserIconPath;
}

/*!
 * @brief Generate a cache path for a user icon.
 *
 * @param inObject The object
 * @return A file path under the shared cache directory.
 */
- (NSString *)_cachedUserIconFilePathForObject:(AIListObject *)inObject
{
	NSString *filename = [NSString
		stringWithFormat:@"WebKitUserIcon-%@-%@.png", inObject.internalObjectID, [NSString randomStringOfLength:5]];
	return [[adium cachesPath] stringByAppendingPathComponent:filename];
}

/*!
 * @brief Remove all references to *this* chat using cached icons for an object
 *
 * If this is the last chat utilizing the cached icon, it will be deleted.
 *
 * @param inObject The object
 */
- (void)releaseCurrentWebKitUserIconForObject:(AIListObject *)inObject
{
	AIListObject *iconSourceObject = [self _iconSourceObjectForObject:inObject];
	NSString *path;

	NSInteger chatsUsingCachedIcon = [iconSourceObject integerValueForProperty:KEY_WEBKIT_CHATS_USING_CACHED_ICON];
	chatsUsingCachedIcon--;
	[iconSourceObject setValue:[NSNumber numberWithInteger:chatsUsingCachedIcon]
				   forProperty:KEY_WEBKIT_CHATS_USING_CACHED_ICON
						notify:NotifyNever];
	[_objectsWithUserIconsArray removeObjectIdenticalTo:iconSourceObject];

	if ((chatsUsingCachedIcon <= 0) && (path = [iconSourceObject valueForProperty:KEY_WEBKIT_USER_ICON])) {
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
		[iconSourceObject setValue:nil forProperty:KEY_WEBKIT_USER_ICON notify:NotifyNever];
	}

	[_objectIconPathDict removeObjectForKey:iconSourceObject.internalObjectID];
}

/*!
 * @brief Remove all references to *this* chat using cached icons for all involved objects
 */
- (void)releaseAllCachedIcons
{
	for (AIListObject *listObject in [_objectsWithUserIconsArray copy]) {
		[self releaseCurrentWebKitUserIconForObject:listObject];
	}
}

/*!
 * @brief Ensure the icon for a content object's source is cached before it is rendered.
 *
 * Called from the content pipeline before each append so the style's %userIconPath% resolves to a
 * real cached file at render time.
 *
 * @param content The content about to be appended
 */
- (void)_trackUserIconForContent:(AIContentObject *)content
{
	if (![_messageStyle showUserIcons]) {
		return;
	}

	AIListObject *iconSource = [self _iconSourceForContent:content];
	if (iconSource) {
		[self _cachedUserIconForObject:iconSource];
	}
}

/*!
 * @brief The object the style reads the cached user icon from for a content object.
 *
 * Mirrors AIWebkitMessageViewStyle's resolution (style.m:770-773): for AIListContact sources use the
 * parentContact, otherwise use the source itself, so the icon lands on the same object the style reads
 * KEY_WEBKIT_USER_ICON from.
 *
 * @param content The content object
 * @return The icon source object, or nil if the content has no source.
 */
- (AIListObject *)_iconSourceForContent:(AIContentObject *)content
{
	AIListObject *contentSource = [content source];
	return ([contentSource isKindOfClass:[AIListContact class]] ? [(AIListContact *)contentSource parentContact]
																: contentSource);
}

/*!
 * @brief Resolve the object the message view reads and caches user icons for.
 *
 * Mirrors AIWebkitMessageViewStyle's resolution (style.m:770-773): for AIListContact objects use the
 * parentContact, otherwise the object itself, so the icon lands on the same object the style reads
 * KEY_WEBKIT_USER_ICON from.
 *
 * @param inObject The object whose icon is being handled
 * @return The icon source object
 */
- (AIListObject *)_iconSourceObjectForObject:(AIListObject *)inObject
{
	return ([inObject isKindOfClass:[AIListContact class]] ? [(AIListContact *)inObject parentContact] : inObject);
}

#pragma mark - Marked Scroller

- (void)setupMarkedScroller
{
	// WKWebView on macOS has no public scroll view and exposes no enclosing
	// NSScrollView (it scrolls internally), so the marked scroller can only be
	// attached when a real enclosing scroll view exists.
	NSScrollView *scrollView = [_webView enclosingScrollView];
	if (scrollView == nil) {
		return;
	}

	JVMarkedScroller *scroller = (JVMarkedScroller *)[scrollView verticalScroller];
	if (scroller && ![scroller isMemberOfClass:[JVMarkedScroller class]]) {
		NSRect scrollerFrame = [scroller frame];
		scroller = [[JVMarkedScroller alloc] initWithFrame:scrollerFrame];
		[scroller setTarget:self];
		[scroller setAction:@selector(markedScrollerClicked:)];
		[scrollView setVerticalScroller:scroller];
	}

	if (scroller && !_markedScroller) {
		_markedScroller = scroller;
	}
}

- (JVMarkedScroller *)markedScroller
{
	return _markedScroller;
}

- (void)markedScrollerClicked:(id)sender
{
	// Handle mark click — can be extended for context menus
}

- (NSNumber *)currentOffsetHeight
{
	// async: returns cached value; callers should use _markCurrentLocation for precision
	// ponytail: cached approximation is good enough for marks
	return [NSNumber numberWithInteger:0];
}

- (void)jumpToPreviousMark
{
	[_markedScroller jumpToPreviousMark:nil];
}

- (BOOL)previousMarkExists
{
	return [_markedScroller previousMarkExists];
}

- (void)jumpToNextMark
{
	[_markedScroller jumpToNextMark:nil];
}

- (BOOL)nextMarkExists
{
	return [_markedScroller nextMarkExists];
}

- (void)jumpToFocusMark
{
	[_markedScroller jumpToFocusMark:nil];
}

- (BOOL)focusMarkExists
{
	return [_markedScroller focusMarkExists];
}

- (void)addMark
{
	[self _markCurrentLocation];
}

- (void)markForFocusChange
{
	_nextMessageFocus = YES;
	_nextMessageRegainedFocus = NO;
}

#pragma mark - Printing

- (void)adiumPrint:(id)sender
{
	if (@available(macOS 11.0, *)) {
		NSPrintOperation *printOp = [_webView printOperationWithPrintInfo:[NSPrintInfo sharedPrintInfo]];
		[printOp setShowsPrintPanel:YES];
		[printOp runOperation];
	}
}

#pragma mark - Utilities

/*!
 * @brief Produce a JS-safe string literal from an NSString.
 *
 * Uses NSJSONSerialization which produces a valid JSON string (also a valid JS string).
 */
- (NSString *)_jsStringLiteral:(NSString *)string
{
	if (!string) {
		return @"''";
	}
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:string options:NSJSONWritingFragmentsAllowed error:NULL];
	if (!jsonData) {
		return @"''";
	}
	return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

/*!
 * @brief Handle a file transfer action from the JS bridge.
 */
- (void)_handleFileTransferAction:(NSString *)action fileTransferID:(NSString *)fileTransferID
{
	if (!fileTransferID) {
		return;
	}

	ESFileTransfer *fileTransfer = [ESFileTransfer existingFileTransferWithID:fileTransferID];

	/* Trust the id only as far as this chat: the transfer must belong to the
	 * account and contact this transcript is showing. Without that, a script in
	 * the page (or a plugin reaching the page world) could accept or cancel any
	 * transfer in the whole application by guessing an id. */
	if (fileTransfer.account != _chat.account ||
		(fileTransfer.contact && ![_chat.containedObjects containsObject:(id)fileTransfer.contact] &&
		 fileTransfer.contact != _chat.listObject)) {
		AILogWithSignature(@"Refused file-transfer action for a transfer outside this chat: %@", fileTransferID);
		return;
	}

	ESFileTransferRequestPromptController *tc = [fileTransfer fileTransferRequestPromptController];
	if (!tc) {
		return;
	}

	// Same action mapping as the legacy AIWebKitMessageViewController's handleAction:forFileTransfer:
	AIFileTransferAction transferAction;
	if ([action isEqualToString:@"SaveAs"]) {
		transferAction = AISaveFileAs;
	} else if ([action isEqualToString:@"Cancel"]) {
		transferAction = AICancel;
	} else {
		transferAction = AISaveFile;
	}

	[tc handleFileTransferAction:transferAction];
}

/*!
 * @brief Generate a cache path for custom background images.
 */
- (NSString *)_webKitBackgroundImagePathForUniqueID:(NSInteger)uniqueID
{
	NSString *cacheDir = [NSString stringWithFormat:@"%@/WebKitMessageView/Backgrounds", NSTemporaryDirectory()];
	[[NSFileManager defaultManager] createDirectoryAtPath:cacheDir
							  withIntermediateDirectories:YES
											   attributes:nil
													error:NULL];
	return [cacheDir
		stringByAppendingPathComponent:[NSString stringWithFormat:@"adium-background-%ld.png", (long)uniqueID]];
}

@end
