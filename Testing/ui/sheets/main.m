/* A harness that draws Adium's two contact list editor sheets without running
 * Adium. The nibs are loaded with stand-in owners that carry the same outlets,
 * every tab is selected in turn, and each is written out as a PNG in both
 * appearances. Nothing here touches preferences or a running program. */
#import <Cocoa/Cocoa.h>
#import "stubs.h"

static NSTabView *findTabView(NSView *view)
{
	if ([view isKindOfClass:[NSTabView class]]) return (NSTabView *)view;
	for (NSView *child in view.subviews) {
		NSTabView *found = findTabView(child);
		if (found) return found;
	}
	return nil;
}

static void writePNG(NSView *view, NSString *path)
{
	/* Mark every single view dirty: the window's own display only repaints what
	 * asked for it, and a sheet that has never been on screen has views that
	 * never asked. */
	__block void (^dirty)(NSView *) = nil;
	dirty = ^(NSView *one) { [one setNeedsDisplay:YES]; for (NSView *child in one.subviews) dirty(child); };
	dirty(view.window.contentView);

	/* Experiment: hold every custom preview inside its own frame. If the sheet
	 * then draws completely, the missing controls were painted over. */
	if ([[[NSProcessInfo processInfo] environment][@"SHEETS_CLIP"] boolValue]) {
		__block void (^clip)(NSView *) = nil;
		clip = ^(NSView *one) {
			if ([NSStringFromClass([one class]) isEqualToString:@"AITextColorPreviewView"]) one.clipsToBounds = YES;
			for (NSView *child in one.subviews) clip(child);
		};
		clip(view.window.contentView);
		dirty(view.window.contentView);
	}
	[view.window display];
	/* Let the compositor actually put the window up before asking for its
	 * picture; too early and the capture comes back black. */
	for (int spin = 0; spin < 8; spin++)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

	/* The compositor's picture of this one window, and of nothing else on the
	 * screen. Neither caching the view nor printing it shows today's controls:
	 * they hang their appearance in hosted layers that only the compositor
	 * has, and both those paths come back with the labels and empty holes
	 * where every button, well and slider should be. */
	NSWindow *window = view.window;
	NSTask *capture = nil;
	/* By rectangle, not by window id: the id form came back with most controls
	 * missing. The window is alone at this spot and ordered front. */
	NSRect frame = window.frame;
	CGFloat screenHeight = NSMaxY([[NSScreen screens] firstObject].frame);
	/* Three times over: the first shot after a tab change regularly comes back
	 * black, the window server not being done with the window yet. The last one
	 * wins, and a short wait sits between them. */
	for (int attempt = 0; attempt < 2; attempt++) {
		capture = [[NSTask alloc] init];
		capture.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
		capture.arguments = @[@"-x", @"-o",
							  [NSString stringWithFormat:@"-R%.0f,%.0f,%.0f,%.0f",
							   frame.origin.x, screenHeight - NSMaxY(frame), frame.size.width, frame.size.height],
							  path];
		NSError *launchError = nil;
		if (![capture launchAndReturnError:&launchError]) {
			fprintf(stderr, "screencapture liess sich nicht starten: %s\n", launchError.localizedDescription.UTF8String);
			return;
		}
		[capture waitUntilExit];
		if (capture.terminationStatus != 0)
			fprintf(stderr, "screencapture endete mit %d fuer %s\n", capture.terminationStatus, path.UTF8String);
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.35]];
	}

	fprintf(stdout, "%s  %.0fx%.0f\n", path.UTF8String, view.bounds.size.width, view.bounds.size.height);
}

static void dumpTree(NSView *root, NSString *path)
{
	NSMutableString *report = [NSMutableString string];
	__block void (^walk)(NSView *, int) = nil;
	walk = ^(NSView *view, int depth) {
		if ([NSStringFromClass([view class]) hasPrefix:@"_Tt"]) return;
		NSString *title = @"";
		if ([view respondsToSelector:@selector(title)]) title = [(id)view title] ?: @"";
		if (!title.length && [view respondsToSelector:@selector(stringValue)]) title = [(id)view stringValue] ?: @"";
		if (!title.length && [view respondsToSelector:@selector(itemTitles)]) title = [[(id)view itemTitles] componentsJoinedByString:@" | "] ?: @"";
		NSRect inWindow = [view convertRect:view.bounds toView:nil];
		[report appendFormat:@"%*s%@ Fenster(%.0f,%.0f %.0fx%.0f) alpha=%.1f%@ %@\n",
		 depth * 2, "", NSStringFromClass([view class]),
		 inWindow.origin.x, inWindow.origin.y, inWindow.size.width, inWindow.size.height,
		 view.alphaValue,
		 view.isHidden ? @" VERSTECKT" : @"", title.length ? [NSString stringWithFormat:@"\"%@\"", title] : @""];
		for (NSView *child in view.subviews) walk(child, depth + 1);
	};
	walk(root, 0);
	[report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static void shoot(NSString *nibPath, NSString *ownerClassName, NSString *stem, NSString *outDir)
{
	for (NSString *mode in @[@"hell", @"dunkel"]) {
		id owner = [[NSClassFromString(ownerClassName) alloc] init];
		NSData *nibData = [NSData dataWithContentsOfFile:nibPath];
		NSNib *nib = (nibData ? [[NSNib alloc] initWithNibData:nibData bundle:nil] : nil);
		NSArray *objects = nil;

		if (![nib instantiateWithOwner:owner topLevelObjects:&objects]) {
			fprintf(stderr, "Nib %s liess sich nicht laden\n", nibPath.UTF8String);
			return;
		}

		NSWindow *window = [owner window];
		if (!window) {
			for (id object in objects) if ([object isKindOfClass:[NSWindow class]]) window = object;
		}
		if (!window) { fprintf(stderr, "Kein Fenster in %s\n", nibPath.UTF8String); return; }

		window.appearance = [NSAppearance appearanceNamed:([mode isEqualToString:@"dunkel"] ?
														   NSAppearanceNameDarkAqua : NSAppearanceNameAqua)];
		NSView *content = window.contentView;

		/* Ordered in, but parked far off every screen: the tab view only lays
		 * out and draws its pages once the window has really been displayed,
		 * and nothing should flash across the user's screen for that. */
		[window setFrameOrigin:NSMakePoint(420.0, 320.0)];
		[NSApp activateIgnoringOtherApps:YES];
		[window makeKeyAndOrderFront:nil];
		[window displayIfNeeded];
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];
		[window layoutIfNeeded];

		NSTabView *tabView = findTabView(content);
		if (tabView) {
			NSUInteger index = 0;
			for (NSTabViewItem *item in tabView.tabViewItems) {
				[tabView selectTabViewItem:item];
				[window layoutIfNeeded];
				[window displayIfNeeded];
				[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
				NSString *label = item.label ?: [NSString stringWithFormat:@"%lu", (unsigned long)index];
				label = [label stringByReplacingOccurrencesOfString:@" " withString:@"-"];
				writePNG(content, [outDir stringByAppendingPathComponent:
								   [NSString stringWithFormat:@"%@-%@-%lu-%@.png", stem, mode, (unsigned long)index, label]]);
				if ([mode isEqualToString:@"hell"]) dumpTree(content, [outDir stringByAppendingPathComponent:
								   [NSString stringWithFormat:@"%@-aufbau-%lu-%@.txt", stem, (unsigned long)index, label]]);
				index++;
			}
		} else {
			writePNG(content, [outDir stringByAppendingPathComponent:
							   [NSString stringWithFormat:@"%@-%@.png", stem, mode]]);
		}

		[window close];

	}
}

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		[NSApp activateIgnoringOtherApps:YES];

		/* The first window of a freshly launched app is not composited straight
		 * away; without this the first sheet comes back black or half drawn. */
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];

		NSDictionary *env = [[NSProcessInfo processInfo] environment];
		NSString *nibDir = (argc > 1 ? [NSString stringWithUTF8String:argv[1]] : env[@"SHEETS_NIBS"]);
		NSString *outDir = (argc > 2 ? [NSString stringWithUTF8String:argv[2]] : env[@"SHEETS_OUT"]);

		shoot([nibDir stringByAppendingPathComponent:@"ListThemeSheet.nib"],
			  @"AIListThemeWindowController", @"farben", outDir);
		shoot([nibDir stringByAppendingPathComponent:@"ListLayoutSheet.nib"],
			  @"AIListLayoutWindowController", @"layout", outDir);
	}
	return 0;
}
