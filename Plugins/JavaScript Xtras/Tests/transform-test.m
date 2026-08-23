/* Exercises a bundled JSXtra transform the way the app does: preamble + plugin
 * injected into a content world, message-body spans appended to #Chat, then the
 * resulting DOM read back. Argv: <preamble.js path is fixed> <plugin.js> then
 * pairs of <inputHTML> <expectSubstring|!expectAbsentSubstring>. */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

static NSString *PREAMBLE =
@"(function(){'use strict';var callbacks=[];var seen=new WeakSet();"
@"function collect(root){var out=[];if(!root||root.nodeType!==1)return out;"
@"if(root.matches&&root.matches('span[data-x-adium-msg]'))out.push(root);"
@"if(root.querySelectorAll){var q=root.querySelectorAll('span[data-x-adium-msg]');for(var i=0;i<q.length;i++)out.push(q[i]);}return out;}"
@"function deliver(nodes){var fresh=[];for(var i=0;i<nodes.length;i++){if(!seen.has(nodes[i])){seen.add(nodes[i]);fresh.push(nodes[i]);}}"
@"if(!fresh.length)return;for(var c=0;c<callbacks.length;c++){try{callbacks[c](fresh);}catch(e){if(window.console)console.error(e);}}}"
@"function start(){var t=document.getElementById('Chat')||document.body;if(!t)return;"
@"new MutationObserver(function(muts){var b=[];for(var m=0;m<muts.length;m++){var a=muts[m].addedNodes;for(var n=0;n<a.length;n++){var c=collect(a[n]);for(var k=0;k<c.length;k++)b.push(c[k]);}}if(b.length)deliver(b);}).observe(t,{childList:true,subtree:true});deliver(collect(t));}"
@"var api={apiVersion:1,onMessagesAdded:function(cb){if(typeof cb==='function')callbacks.push(cb);}};"
@"Object.freeze(api);Object.defineProperty(window,'adiumPlugin',{value:api});"
@"if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();})();";

@interface Runner : NSObject <WKNavigationDelegate> @end
@implementation Runner {
	WKWebView *_web;
	NSArray *_cases;   // array of @[inputHTML, assertion]
	int _fails;
}
- (instancetype)initWithPluginSource:(NSString *)pluginSource cases:(NSArray *)cases {
	if ((self = [super init])) {
		_cases = cases;
		WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
		WKUserContentController *ucc = [[WKUserContentController alloc] init];
		WKContentWorld *world = [WKContentWorld worldWithName:@"test"];
		[ucc addUserScript:[[WKUserScript alloc] initWithSource:PREAMBLE injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES inContentWorld:world]];
		[ucc addUserScript:[[WKUserScript alloc] initWithSource:pluginSource injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES inContentWorld:world]];
		cfg.userContentController = ucc;
		_web = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,400,400) configuration:cfg];
		_web.navigationDelegate = self;
		[_web loadHTMLString:@"<html><head></head><body><div id='Chat'></div></body></html>" baseURL:[NSURL fileURLWithPath:@"/tmp/"]];
	}
	return self;
}
- (void)webView:(WKWebView *)wv didFinishNavigation:(WKNavigation *)nav {
	[self runCase:0];
}
- (void)runCase:(NSUInteger)idx {
	if (idx >= _cases.count) {
		printf(_fails ? "== %d FAILURES\n" : "== all good\n", _fails);
		exit(_fails ? 1 : 0);
	}
	NSString *input = _cases[idx][0];
	NSString *assertion = _cases[idx][1];   // "+substr" must be present, "-substr" must be absent
	// Append a wrapper span in the page world, then read back after a tick
	NSString *appendJS = [NSString stringWithFormat:
		@"(function(){var s=document.createElement('span');s.setAttribute('data-x-adium-msg','');"
		@"s.setAttribute('data-x-adium-dir','incoming');s.innerHTML=%@;document.getElementById('Chat').appendChild(s);})();",
		[self jsLiteral:input]];
	[_web evaluateJavaScript:appendJS completionHandler:^(id r, NSError *e) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[_web evaluateJavaScript:@"document.getElementById('Chat').lastChild.outerHTML" completionHandler:^(id html, NSError *e2) {
				NSString *out = [html isKindOfClass:[NSString class]] ? html : @"";
				BOOL want = [assertion hasPrefix:@"+"];
				NSString *needle = [assertion substringFromIndex:1];
				BOOL present = [out rangeOfString:needle].location != NSNotFound;
				BOOL ok = (want == present);
				printf("%s case %lu: %s %s\n    -> %s\n", ok?"ok ":"FAIL", (unsigned long)idx,
					   want?"has":"lacks", [needle UTF8String], [out UTF8String]);
				if (!ok) _fails++;
				[self runCase:idx+1];
			}];
		});
	}];
}
- (NSString *)jsLiteral:(NSString *)s {
	NSData *d = [NSJSONSerialization dataWithJSONObject:@[s] options:0 error:NULL];
	NSString *arr = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
	return [arr substringWithRange:NSMakeRange(1, arr.length-2)];  // strip [ ]
}
@end

int main(int argc, char *argv[]) {
	@autoreleasepool {
		[NSApplication sharedApplication];
		NSString *pluginPath = [NSString stringWithUTF8String:argv[1]];
		NSString *src = [NSString stringWithContentsOfFile:pluginPath encoding:NSUTF8StringEncoding error:NULL];
		NSMutableArray *cases = [NSMutableArray array];
		for (int i = 2; i + 1 < argc; i += 2)
			[cases addObject:@[[NSString stringWithUTF8String:argv[i]], [NSString stringWithUTF8String:argv[i+1]]]];
		Runner *r = [[Runner alloc] initWithPluginSource:src cases:cases];
		(void)r;
		[[NSRunLoop currentRunLoop] run];
	}
	return 0;
}
