/* Isolation probe: mirrors the message view's real hardening (remote-load block
 * rule list, file access unlock, file:// origin, per-plugin content world) and
 * runs a hostile plugin that tries every escape. Every egress vector must be
 * blocked and the native handler unreachable, or this fails. */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

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
@"  // publish results into the shared DOM for the native side to read\n"
@"  var out = document.createElement('div'); out.id='probe-results'; out.textContent = results.join('\\n'); document.body.appendChild(out);\n"
@"})();";

@interface Probe : NSObject <WKNavigationDelegate>
@property (nonatomic) int fails;
@end

@implementation Probe {
	WKWebView *_web;
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

		// The page-world native handler, exactly as the app registers it
		[ucc addScriptMessageHandler:(id)self name:@"adium"];

		// The probe in its own content world, as the manager injects a plugin
		WKContentWorld *world = [WKContentWorld worldWithName:@"adium.jsxtra.probe"];
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
		NSString *page = [dir stringByAppendingPathComponent:@"p.html"];
		[@"<html><body></body></html>" writeToFile:page atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		[_web loadFileURL:[NSURL fileURLWithPath:page] allowingReadAccessToURL:[NSURL fileURLWithPath:@"/" isDirectory:YES]];
	}];
}

//If the probe ever reaches this, native isolation is broken
- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message
{
	printf("LEAKED: probe reached the native adium handler\n");
	self.fails++;
}

- (void)webView:(WKWebView *)wv didFinishNavigation:(WKNavigation *)nav
{
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[wv evaluateJavaScript:@"(document.getElementById('probe-results')||{}).textContent||'no results'"
			 completionHandler:^(id r, NSError *e) {
			NSString *out = [r isKindOfClass:[NSString class]] ? r : @"(none)";
			printf("%s\n", out.UTF8String);
			for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
				if ([line hasPrefix:@"LEAKED"]) self.fails++;
			}
			printf(self.fails ? "== %d LEAK(S)\n" : "== all vectors blocked\n", self.fails);
			exit(self.fails ? 1 : 0);
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
