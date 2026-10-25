/*
 * Photographs a message style without running Adium.
 *
 * The style's own templates are filled the way AIWebkitMessageViewStyle fills them, for a
 * short made-up conversation, loaded into a WKWebView in a window that is never shown, and
 * snapshotted once per appearance and font size. The base template is the plugin's own
 * Template.html, so the page is built as the application builds it; what this leaves out is
 * the application itself: no account, no contact, no filters, so %sender% is a name and
 * %message% is text. Enough to judge colours, spacing and type.
 *
 * Environment, set by style-shots.sh:
 *   STYLE_PATH     the .AdiumMessageStyle bundle
 *   STYLE_TEMPLATE the plugin's Template.html
 *   STYLE_VARIANT  the variant name, without .css
 *   STYLE_SIZES    font sizes, space separated
 *   STYLE_OUT      the folder the pictures go to
 */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

typedef struct { NSString *appearance; NSInteger size; BOOL groupChat; } Shot;

@interface StyleShooter : NSObject <WKNavigationDelegate>
@property (strong) NSWindow *window;
@property (strong) WKWebView *webView;
@property (strong) NSString *stylePath, *resourcesPath, *templateHTML, *variant, *fontFamily, *out, *styleName;
@property (strong) NSMutableArray *shots;
@property (assign) NSUInteger index;
@end

@implementation StyleShooter

- (NSString *)read:(NSString *)relative
{
	NSString *path = [self.resourcesPath stringByAppendingPathComponent:relative];
	return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

/* Outgoing templates fall back to the incoming ones, as the application's loader does. */
- (NSString *)template:(NSString *)name outgoing:(BOOL)outgoing
{
	NSString *html = outgoing ? [self read:[@"Outgoing" stringByAppendingPathComponent:name]] : nil;
	return html ?: [self read:[@"Incoming" stringByAppendingPathComponent:name]];
}

- (NSString *)fill:(NSString *)html with:(NSDictionary *)values
{
	NSMutableString *s = [html mutableCopy];
	for (NSString *key in values)
		[s replaceOccurrencesOfString:key withString:values[key] options:0 range:NSMakeRange(0, s.length)];
	return s;
}

- (NSDictionary *)valuesForSender:(NSString *)sender message:(NSString *)message classes:(NSString *)classes time:(NSString *)time outgoing:(BOOL)outgoing
{
	NSString *icon = [NSString stringWithFormat:@"%@/buddy_icon.png", outgoing ? @"Outgoing" : @"Incoming"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:[self.resourcesPath stringByAppendingPathComponent:icon]])
		icon = @"Incoming/buddy_icon.png";
	return @{ @"%sender%": sender, @"%message%": message, @"%messageClasses%": classes, @"%time%": time,
			  @"%time{dd MMM yyyy}%": @"25 Oct 2026", @"%userIconPath%": icon, @"%userIcons%": @"showIcons",
			  @"%service%": @"Jabber", @"%messageDirection%": @"ltr", @"%senderScreenName%": sender,
			  @"%senderColor%": @"#3b5998", @"%senderStatusIcon%": @"", @"%textbackgroundcolor{}%": @"" };
}

/* A NextContent chunk goes where the previous chunk left its insert marker; anything else is
 * appended, with the marker of what came before taken out, as the template's script does. */
- (void)append:(NSString *)chunk to:(NSMutableString *)body consecutive:(BOOL)consecutive
{
	NSRange insert = [body rangeOfString:@"<div id=\"insert\"></div>" options:NSBackwardsSearch];
	if (insert.location != NSNotFound) {
		if (consecutive) { [body replaceCharactersInRange:insert withString:chunk]; return; }
		[body deleteCharactersInRange:insert];
	}
	[body appendString:chunk];
}

- (NSString *)pageForGroupChat:(BOOL)groupChat
{
	NSMutableString *body = [NSMutableString string];
	NSString *content = [self template:@"Content.html" outgoing:NO], *next = [self template:@"NextContent.html" outgoing:NO];
	NSString *outContent = [self template:@"Content.html" outgoing:YES], *outNext = [self template:@"NextContent.html" outgoing:YES];
	NSString *status = [self read:@"Status.html"];
	NSString *other = groupChat ? @"Lena" : @"Jonas", *me = @"Christian";

	[self append:[self fill:status with:[self valuesForSender:@"" message:@"Jonas is now available" classes:@"status online" time:@"14:28" outgoing:NO]] to:body consecutive:NO];
	[self append:[self fill:content with:[self valuesForSender:other message:@"Hey, did you see the new Stockholm? Dark mode at last." classes:@"message incoming" time:@"14:31" outgoing:NO]] to:body consecutive:NO];
	[self append:[self fill:next with:[self valuesForSender:other message:@"The link: <a href=\"https://adium.im/\">adium.im</a>, and some <b>bold</b> and <i>italic</i> text, plus an umlaut: Grüße!" classes:@"message incoming consecutive" time:@"14:31" outgoing:NO]] to:body consecutive:YES];
	[self append:[self fill:outContent with:[self valuesForSender:me message:@"Looks good. Let me check the time stamps and the consecutive messages." classes:@"message outgoing" time:@"14:32" outgoing:YES]] to:body consecutive:NO];
	[self append:[self fill:outNext with:[self valuesForSender:me message:@"And a second line from me." classes:@"message outgoing consecutive" time:@"14:33" outgoing:YES]] to:body consecutive:YES];
	if (groupChat)
		[self append:[self fill:content with:[self valuesForSender:@"Mara" message:@"Mentioning @Christian so the mention plate shows." classes:@"message incoming mention" time:@"14:35" outgoing:NO]] to:body consecutive:NO];
	[self append:[self fill:content with:[self valuesForSender:other message:@"History headers are dimmed too; this one is a regular message again." classes:@"message incoming" time:@"14:36" outgoing:NO]] to:body consecutive:NO];
	[self append:[self fill:status with:[self valuesForSender:@"" message:@"Jonas went away" classes:@"status away" time:@"14:40" outgoing:NO]] to:body consecutive:NO];
	[body replaceOccurrencesOfString:@"<div id=\"insert\"></div>" withString:@"" options:0 range:NSMakeRange(0, body.length)];

	NSString *header = @"";
	if (groupChat) {
		NSString *topic = [self read:@"Topic.html"];
		header = [NSString stringWithFormat:@"<div id=\"topic\">%@</div>",
				  topic ? [self fill:topic with:@{ @"%topic%": @"<span id=\"topicEdit\">Release planning, and whether 11 or 14 points</span>", @"%messageDirection%": @"ltr" }] : @""];
	}
	NSString *base = [[NSURL fileURLWithPath:self.resourcesPath isDirectory:YES] absoluteString];
	NSString *page = [NSString stringWithFormat:self.templateHTML, base, @"@import url( \"main.css\" );",
					  [NSString stringWithFormat:@"Variants/%@.css", self.variant], header, @""];
	page = [page stringByReplacingOccurrencesOfString:@"==bodyBackground==" withString:@""];
	NSRange chat = [page rangeOfString:@"<div id=\"Chat\">"];
	return [page stringByReplacingCharactersInRange:NSMakeRange(NSMaxRange(chat), 0) withString:body];
}

- (void)shoot
{
	if (self.index >= self.shots.count) { [NSApp terminate:nil]; return; }
	NSDictionary *shot = self.shots[self.index];
	BOOL groupChat = [shot[@"group"] boolValue];
	self.window.appearance = [NSAppearance appearanceNamed:shot[@"appearance"]];
	NSString *html = [self pageForGroupChat:groupChat];
	NSString *file = [self.out stringByAppendingPathComponent:@"page.html"];
	[html writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[self.webView loadFileURL:[NSURL fileURLWithPath:file] allowingReadAccessToURL:[NSURL fileURLWithPath:@"/"]];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
	NSDictionary *shot = self.shots[self.index];
	/* The same inline default the application applies after a load. */
	NSString *js = [NSString stringWithFormat:@"document.documentElement.style.fontFamily = '%@'; document.documentElement.style.fontSize = '%@px';",
					self.fontFamily ?: @"", shot[@"size"]];
	[webView evaluateJavaScript:js completionHandler:nil];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[webView takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *error) {
			NSString *name = [NSString stringWithFormat:@"%@ - %@ - %@ - %@pt%@.png", self.styleName, self.variant,
							  [shot[@"appearance"] isEqualToString:NSAppearanceNameDarkAqua] ? @"dark" : @"light",
							  shot[@"size"], [shot[@"group"] boolValue] ? @" - group" : @""];
			NSData *png = [[[NSBitmapImageRep alloc] initWithData:[image TIFFRepresentation]] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
			[png writeToFile:[self.out stringByAppendingPathComponent:name] atomically:YES];
			printf("%s\n", name.UTF8String);
			self.index++;
			[self shoot];
		}];
	});
}

@end

int main(int argc, char **argv)
{
	@autoreleasepool {
		NSDictionary *env = [[NSProcessInfo processInfo] environment];
		StyleShooter *shooter = [StyleShooter new];
		shooter.stylePath = env[@"STYLE_PATH"];
		shooter.resourcesPath = [shooter.stylePath stringByAppendingPathComponent:@"Contents/Resources"];
		shooter.templateHTML = [NSString stringWithContentsOfFile:env[@"STYLE_TEMPLATE"] encoding:NSUTF8StringEncoding error:NULL];
		shooter.variant = env[@"STYLE_VARIANT"];
		shooter.out = env[@"STYLE_OUT"];
		shooter.styleName = [[shooter.stylePath lastPathComponent] stringByDeletingPathExtension];
		NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[shooter.stylePath stringByAppendingPathComponent:@"Contents/Info.plist"]];
		shooter.fontFamily = info[@"DefaultFontFamily"];
		shooter.shots = [NSMutableArray array];
		for (NSString *size in [env[@"STYLE_SIZES"] componentsSeparatedByString:@" "]) {
			if (!size.length) continue;
			for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
				[shooter.shots addObject:@{ @"appearance": appearance, @"size": size, @"group": @NO }];
				[shooter.shots addObject:@{ @"appearance": appearance, @"size": size, @"group": @YES }];
			}
		}
		if (!shooter.templateHTML || !shooter.variant || !shooter.out) { fprintf(stderr, "missing environment\n"); return 2; }

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
		NSRect frame = NSMakeRect(0, 0, 560, 520);
		shooter.window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
		shooter.webView = [[WKWebView alloc] initWithFrame:frame configuration:[WKWebViewConfiguration new]];
		shooter.webView.navigationDelegate = shooter;
		shooter.window.contentView = shooter.webView;
		[shooter shoot];
		[NSApp run];
	}
	return 0;
}
