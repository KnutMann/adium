/* A harness that shows the contact list appearance editor without running Adium.
 *
 * The editor asks the program for exactly one thing, the preference store, so a
 * stand-in that keeps the settings in a dictionary is enough to put the whole
 * window on screen and photograph it. Nothing is read from or written to the
 * real preferences.
 */
#import <Cocoa/Cocoa.h>

#import <Adium/AIAbstractListController.h>
#import <Adium/AISharedAdium.h>

#import "AIContactListAppearanceWindowController.h"
#import <Adium/AIContactListPreviewView.h>
#import <Adium/AIListOutlineView.h>
#import <Adium/AIServiceIcons.h>
#import <Adium/AIStatusIcons.h>

#pragma mark A preference store in a dictionary

@interface EditorPreferences : NSObject
@property (nonatomic, strong) NSMutableDictionary *groups;
@end

@implementation EditorPreferences

- (NSMutableDictionary *)groupNamed:(NSString *)group
{
	NSMutableDictionary *dict = self.groups[group];
	if (!dict) {
		dict = [NSMutableDictionary dictionary];
		self.groups[group] = dict;
	}
	return dict;
}

- (id)preferenceForKey:(NSString *)key group:(NSString *)group
{
	return [self groupNamed:group][key];
}

- (NSDictionary *)preferencesForGroup:(NSString *)group
{
	return [[self groupNamed:group] copy];
}

- (void)setPreference:(id)value forKey:(NSString *)key group:(NSString *)group
{
	if (value) [self groupNamed:group][key] = value;
	else [[self groupNamed:group] removeObjectForKey:key];
}

- (void)setPreferences:(NSDictionary *)dict inGroup:(NSString *)group
{
	[[self groupNamed:group] addEntriesFromDictionary:dict];
}

/* Everything else the editor might ask for is answered with nothing rather
 * than with a crash. The answer has to be written, not left alone: the return
 * buffer of an invocation starts out as whatever was on the stack, so a
 * forwarded call that nobody answers hands back a garbage pointer. */
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
	NSMethodSignature *signature = [super methodSignatureForSelector:selector];
	return signature ?: [NSMethodSignature signatureWithObjCTypes:"@@:@@@@"];
}
- (void)forwardInvocation:(NSInvocation *)invocation
{
	NSUInteger length = invocation.methodSignature.methodReturnLength;
	if (!length) return;

	void *nothing = calloc(1, length);
	[invocation setReturnValue:nothing];
	free(nothing);
}

@end

@interface EditorAdium : NSObject
@property (nonatomic, strong) EditorPreferences *preferenceController;
@end

@implementation EditorAdium
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
	NSMethodSignature *signature = [super methodSignatureForSelector:selector];
	return signature ?: [NSMethodSignature signatureWithObjCTypes:"@@:@@@@"];
}
- (void)forwardInvocation:(NSInvocation *)invocation
{
	NSUInteger length = invocation.methodSignature.methodReturnLength;
	if (!length) return;

	void *nothing = calloc(1, length);
	[invocation setReturnValue:nothing];
	free(nothing);
}
@end

#pragma mark Picture taking

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void writePNG(NSWindow *window, NSString *path)
{
	[window.contentView setNeedsDisplay:YES];
	[window display];
	spin(0.5);

	for (int attempt = 0; attempt < 2; attempt++) {
		NSTask *capture = [[NSTask alloc] init];
		capture.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
		capture.arguments = @[@"-x", @"-o",
							  [NSString stringWithFormat:@"-l%ld", (long)window.windowNumber],
							  path];
		NSError *launchError = nil;
		if (![capture launchAndReturnError:&launchError]) {
			fprintf(stderr, "screencapture liess sich nicht starten: %s\n",
					launchError.localizedDescription.UTF8String);
			return;
		}
		[capture waitUntilExit];
		spin(0.3);
	}
	fprintf(stdout, "%s\n", path.lastPathComponent.UTF8String);
}

#pragma mark Runner

static NSDictionary *setNamed(NSString *root, NSString *name, NSString *extension)
{
	NSString *path = [[[root stringByAppendingPathComponent:@"Resources/Contact List"]
					   stringByAppendingPathComponent:name] stringByAppendingPathExtension:extension];
	return [NSDictionary dictionaryWithContentsOfFile:path];
}

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		NSDictionary *env = [[NSProcessInfo processInfo] environment];
		NSString *root = env[@"EDITOR_ROOT"];
		NSString *outDir = env[@"EDITOR_OUT"];
		if (!root || !outDir) { fprintf(stderr, "EDITOR_ROOT und EDITOR_OUT fehlen\n"); return 1; }

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		[NSApp activateIgnoringOtherApps:YES];
		spin(1.2);

		EditorPreferences *prefs = [[EditorPreferences alloc] init];
		prefs.groups = [NSMutableDictionary dictionary];
		[prefs setPreferences:setNamed(root, @"Aqualicious", @"ListLayout") inGroup:PREF_GROUP_LIST_LAYOUT];
		[prefs setPreferences:setNamed(root, @"Aqualicious", @"ListTheme") inGroup:PREF_GROUP_LIST_THEME];
		[prefs setPreferences:[NSDictionary dictionaryWithContentsOfFile:
							   [root stringByAppendingPathComponent:@"Resources/AppearanceDefaults.plist"]]
					  inGroup:@"Appearance"];

		/* Wie im Programm: die Symbolpakete sind aktiv, bevor eine Liste gezeichnet wird. */
		[AIStatusIcons setActiveStatusIconsFromPath:
		 [root stringByAppendingPathComponent:@"Resources/Status Icons/iBubble Status.AdiumStatusIcons"]];
		[AIServiceIcons setActiveServiceIconsFromPath:
		 [root stringByAppendingPathComponent:@"Resources/Service Icons/SimpleKnut Black.AdiumServiceIcons"]];

		EditorAdium *stub = [[EditorAdium alloc] init];
		stub.preferenceController = prefs;
		setSharedAdium((id)stub);

		/* Erst die Vorschau allein, um zu sehen, ob sie mit dem Stellvertreter
		 * genauso zeichnet wie ohne Programm. */
		{
			NSWindow *probe = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,280,300)
														  styleMask:NSWindowStyleMaskTitled
															backing:NSBackingStoreBuffered defer:NO];
			AIContactListPreviewView *solo = [[AIContactListPreviewView alloc] initWithFrame:NSMakeRect(0,0,280,300)];
			solo.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
			probe.contentView = solo;
			[solo applyLayout:[prefs preferencesForGroup:PREF_GROUP_LIST_LAYOUT]
						theme:[prefs preferencesForGroup:PREF_GROUP_LIST_THEME]
				  windowStyle:AIContactListWindowStyleBorderless];
			[probe setFrameOrigin:NSMakePoint(200.0, 160.0)];
			[probe makeKeyAndOrderFront:nil];
			spin(0.6);
			id item = [solo.listView itemAtRow:1];
			id listObject = [item valueForKey:@"listObject"];
			fprintf(stderr, "Probe: %ld Zeilen, Wunschhoehe %.0f, Inhaltszelle %s, Zeile1 %s Name '%s' Farbe %s\n",
					(long)solo.listView.numberOfRows, solo.listHeight,
					[NSStringFromClass([[solo.listView contentCell] class]) UTF8String],
					[NSStringFromClass([listObject class]) UTF8String],
					[[[listObject valueForKey:@"longDisplayName"] description] UTF8String],
					[[[listObject valueForKey:@"textColor"] description] UTF8String]);
			writePNG(probe, [outDir stringByAppendingPathComponent:@"probe-vorschau.png"]);
			[probe orderOut:nil];
		}

		NSArray *jobs = @[@[@"form", @(AIContactListWindowStyleBorderless), @(AIContactListAppearanceSectionShape)],
						  @[@"kontaktzeile", @(AIContactListWindowStyleBorderless), @(AIContactListAppearanceSectionContactRow)],
						  @[@"gruppenzeile", @(AIContactListWindowStyleBorderless), @(AIContactListAppearanceSectionGroupRow)],
						  @[@"farben", @(AIContactListWindowStyleBorderless), @(AIContactListAppearanceSectionColours)],
						  @[@"blasen", @(AIContactListWindowStyleContactBubbles), @(AIContactListAppearanceSectionShape)],
						  @[@"zustandsfarben", @(AIContactListWindowStyleBorderless), @(AIContactListAppearanceSectionColours)]];

		for (NSString *mode in @[@"hell", @"dunkel"]) {
			NSAppearance *appearance = [NSAppearance appearanceNamed:
										([mode isEqualToString:@"dunkel"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua)];
			NSApp.appearance = appearance;

			for (NSArray *job in jobs) {
				[prefs setPreference:job[1] forKey:KEY_LIST_LAYOUT_WINDOW_STYLE group:@"Appearance"];

				AIContactListAppearanceWindowController *editor;
				editor = [[AIContactListAppearanceWindowController alloc] initWithLayoutNamed:@"Aqualicious"
																				  themeNamed:@"Aqualicious"
																					 section:[job[2] intValue]
																			 notifyingTarget:nil];
				editor.window.appearance = appearance;
				[NSApp activateIgnoringOtherApps:YES];
				if ([job[0] isEqualToString:@"zustandsfarben"]) {
					NSRect frame = editor.window.frame;
					frame.size.height = 1000.0;
					[editor.window setFrame:frame display:NO];
				}
				[editor.window setFrameOrigin:NSMakePoint(200.0, 40.0)];
				[editor.window makeKeyAndOrderFront:nil];
				spin(0.8);

				writePNG(editor.window, [outDir stringByAppendingPathComponent:
										 [NSString stringWithFormat:@"editor-%@-%@.png", job[0], mode]]);
				[editor.window orderOut:nil];
			}
		}
	}
	return 0;
}
