/* A harness that photographs Adium's contact list without running Adium.
 *
 * It links the real Adium framework and shows AIContactListPreviewView, the
 * same small made-up contact list the editor puts in front of the user, once
 * for every window style and every shipped layout and colour set.
 *
 * Why it can work without a program behind it: the shared Adium instance is a
 * plain global that stays nil here, and every place the drawing reaches for it
 * tolerates nil. No preference is read and none is written, and no real contact
 * is ever touched.
 */
#import <Cocoa/Cocoa.h>

#import <Adium/AIAbstractListController.h>
#import <Adium/AIContactListPreviewView.h>
#import <Adium/AIListCell.h>
#import <Adium/AIListOutlineView.h>
#import <Adium/AIServiceIcons.h>
#import <Adium/AIStatusIcons.h>

#pragma mark Picture taking

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

/* The compositor's picture of this one window. Caching the view is not enough:
 * today's controls hang their appearance in layers only the window server has.
 * Same reason and same recipe as Testing/ui/sheet-shots.sh. */
static void writePNG(NSWindow *window, NSString *path)
{
	[window.contentView setNeedsDisplay:YES];
	[window display];
	spin(0.35);

	/* By window number, not by rectangle: a picture of a spot on the screen is
	 * a picture of whatever is at that spot, and a window that slips in front
	 * lands in it. This asks the window server for this one window. */
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
		if (capture.terminationStatus != 0)
			fprintf(stderr, "screencapture endete mit %d fuer %s\n",
					capture.terminationStatus, path.UTF8String);
		spin(0.3);
	}

	if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
		fprintf(stdout, "%s\n", path.lastPathComponent.UTF8String);
		return;
	}

	/* The window server would not give up a picture: the screen is locked, or
	 * recording it is not allowed here. Asking the view to draw into a bitmap
	 * finishes the run instead of ending it with nothing, but it is the second
	 * best picture and says so in its line: what a layer-backed view holds does
	 * not reliably come along, and one run lost the bubble behind every contact
	 * while the next, from the same build, kept it. Good enough to read a name or
	 * a colour off, not to compare pixel by pixel against a photographed run. */
	NSView *content = window.contentView;
	NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
	if (!rep) {
		fprintf(stderr, "weder Fensterserver noch Zwischenspeicher liefern ein Bild fuer %s\n",
				path.lastPathComponent.UTF8String);
		return;
	}
	[content cacheDisplayInRect:content.bounds toBitmapImageRep:rep];

	NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
	if ([png writeToFile:path atomically:YES])
		fprintf(stdout, "%s (gezeichnet, nicht fotografiert)\n", path.lastPathComponent.UTF8String);
	else
		fprintf(stderr, "konnte %s nicht schreiben\n", path.lastPathComponent.UTF8String);
}

#pragma mark Preference sets

static NSDictionary *setNamed(NSString *root, NSString *name, NSString *extension)
{
	NSString *path = [[[root stringByAppendingPathComponent:@"Resources/Contact List"]
					   stringByAppendingPathComponent:name] stringByAppendingPathExtension:extension];
	NSBundle *bundle = [NSBundle bundleWithPath:path];
	if (bundle && [[bundle objectForInfoDictionaryKey:@"XtraBundleVersion"] integerValue] == 1)
		path = [bundle.resourcePath stringByAppendingPathComponent:@"Data.plist"];
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
	if (!dict) fprintf(stderr, "Vorlage %s.%s nicht lesbar\n", name.UTF8String, extension.UTF8String);
	return dict;
}

static NSDictionary *merged(NSDictionary *base, NSDictionary *overlay)
{
	NSMutableDictionary *result = [base mutableCopy];
	[result addEntriesFromDictionary:overlay];
	return result;
}

#pragma mark Runner

/* A borderless window still has to be able to become key, or the list never
 * draws a selected row. */
@interface ShotWindow : NSWindow
@end

@implementation ShotWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

/* The bubble styles paint no background of their own; in the program the
 * desktop shows through there. A flat ground is put behind them instead, so
 * that two pictures taken on different days can still be compared. */
@interface ShotBackdrop : NSView
@property (nonatomic, strong) NSColor *ground;
@property (nonatomic, getter=isOpaque) BOOL opaque;
@end

@implementation ShotBackdrop
@synthesize opaque;
- (BOOL)isOpaque { return opaque; }
- (void)drawRect:(NSRect)dirty
{
	if (!opaque) return;
	[self.ground set];
	NSRectFill(dirty);
}
@end

static NSString *const styleNames[] = { @"Standard", @"Rahmenlos", @"Gruppenblasen", @"Kontaktblasen", @"Kontaktblasen-eng", @"Gruppenchat" };

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		NSDictionary *env = [[NSProcessInfo processInfo] environment];
		NSString *root = env[@"LIST_ROOT"];
		NSString *outDir = env[@"LIST_OUT"];
		if (!root || !outDir) { fprintf(stderr, "LIST_ROOT und LIST_OUT fehlen\n"); return 1; }

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		[NSApp activateIgnoringOtherApps:YES];
		spin(1.2);

		[AIStatusIcons setActiveStatusIconsFromPath:
		 [root stringByAppendingPathComponent:@"Resources/Status Icons/iBubble Status.AdiumStatusIcons"]];
		[AIServiceIcons setActiveServiceIconsFromPath:
		 [root stringByAppendingPathComponent:@"Resources/Service Icons/SimpleKnut Black.AdiumServiceIcons"]];

		NSDictionary *baseLayout = setNamed(root, @"Aqualicious", @"ListLayout");
		NSDictionary *baseTheme = setNamed(root, @"Aqualicious", @"ListTheme");
		if (!baseLayout || !baseTheme) return 1;

		/* What gets photographed. The first block walks the window styles at the
		 * standard set, the second the shipped layouts, the third the shipped
		 * colour sets. Layouts and colour sets are shown at the style Adium
		 * starts with, because the style does not travel inside them.
		 *
		 * The group chat style is left out: it is the participant list of a
		 * group conversation, not the contact list, and its cell asks a chat
		 * and a role icon pack for everything it draws. */
		NSMutableArray *jobs = [NSMutableArray array];
		for (int style = 0; style < AIContactListWindowStyleGroupChat; style++) {
			[jobs addObject:@{ @"stem": [NSString stringWithFormat:@"stil-%d-%@", style, styleNames[style]],
							   @"style": @(style), @"layout": baseLayout, @"theme": baseTheme }];
		}
		for (NSString *name in @[@"Aqualicious", @"Centered", @"Concise", @"Decay 2.0"]) {
			NSDictionary *layout = setNamed(root, name, @"ListLayout");
			if (!layout) continue;
			[jobs addObject:@{ @"stem": [NSString stringWithFormat:@"gestaltung-%@", name],
							   @"style": @(AIContactListWindowStyleBorderless),
							   @"layout": merged(baseLayout, layout), @"theme": baseTheme }];
		}
		for (NSString *name in @[@"Aqualicious", @"Aqualicious Graphite", @"Bright Orange",
								 @"Concise", @"Decay 2.0", @"Pastel Pink"]) {
			NSDictionary *theme = setNamed(root, name, @"ListTheme");
			if (!theme) continue;
			[jobs addObject:@{ @"stem": [NSString stringWithFormat:@"motiv-%@", name],
							   @"style": @(AIContactListWindowStyleBorderless),
							   @"layout": baseLayout, @"theme": merged(baseTheme, theme) }];
		}

		NSMutableString *report = [NSMutableString string];

		for (NSDictionary *job in jobs) {
			for (NSString *mode in @[@"hell", @"dunkel"]) {
				BOOL dark = [mode isEqualToString:@"dunkel"];
				NSAppearance *appearance = [NSAppearance appearanceNamed:
											(dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua)];
				NSApp.appearance = appearance;

				NSRect content = NSMakeRect(0.0, 0.0, 260.0, 400.0);
				ShotWindow *window = [[ShotWindow alloc] initWithContentRect:content
																   styleMask:NSWindowStyleMaskBorderless
																	 backing:NSBackingStoreBuffered
																	   defer:NO];
				window.appearance = appearance;
				window.backgroundColor = (dark ? [NSColor colorWithCalibratedWhite:0.16 alpha:1.0]
											   : [NSColor colorWithCalibratedWhite:0.93 alpha:1.0]);

				/* Mit LIST_TRANSPARENT=1 ist das Fenster durchsichtig, wie die
				 * rahmenlose Kontaktliste es im Programm ist. Ein Fenster, das
				 * seine Bildpunkte nicht selbst fuellt, loescht auch nichts,
				 * was vorher darin stand. */
				BOOL transparent = [[[NSProcessInfo processInfo] environment][@"LIST_TRANSPARENT"] boolValue];
				if (transparent) {
					window.opaque = NO;
					window.backgroundColor = [NSColor clearColor];
				}

				ShotBackdrop *backdrop = [[ShotBackdrop alloc] initWithFrame:content];
				backdrop.ground = (transparent ? [NSColor clearColor] : window.backgroundColor);
				backdrop.opaque = !transparent;
				backdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

				AIContactListPreviewView *preview = [[AIContactListPreviewView alloc] initWithFrame:content];
				preview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
				[backdrop addSubview:preview];
				window.contentView = backdrop;

				if ([[[NSProcessInfo processInfo] environment][@"LIST_CHURN"] boolValue])
					[preview addFillerContacts:24];

				[preview applyLayout:job[@"layout"]
							   theme:job[@"theme"]
						 windowStyle:[job[@"style"] intValue]];

				[NSApp activateIgnoringOtherApps:YES];
				[window makeKeyAndOrderFront:nil];
				spin(0.4);

				CGFloat height = MAX(80.0, MIN(520.0, preview.listHeight + 8.0));
				[window setFrame:NSMakeRect(420.0, 260.0, 260.0, height) display:YES];

				/* One contact picked, so the pictures also show how a chosen row
				 * looks in each style. */
				AIListOutlineView *listView = preview.listView;

				if (listView.numberOfRows > 2)
					[listView selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
				[window makeFirstResponder:listView];
				spin(0.4);
				if (!window.isKeyWindow)
					fprintf(stderr, "Hinweis: kein Tastaturfenster bei %s, die Auswahl wird blass gezeichnet\n",
							[job[@"stem"] UTF8String]);

				/* Mit LIST_CHURN=1 wird die Liste vorher durchgeschuettelt: eine
				 * Gruppe zu, wieder auf, gescrollt. Genau dabei gibt die Tabelle
				 * ihre Zeilenansichten weiter, und genau dort wurde der Fehler
				 * gemeldet, bei dem zwei Namen uebereinander standen. */
				/* Mit LIST_GROW=1 waechst die Liste, waehrend sie schon zu sehen
				 * ist: genau das passiert, wenn ein Konto sich anmeldet und
				 * seine Kontakte nachreicht. Gemeldet wurde der Fehler fuer
				 * genau diesen Augenblick. */
				/* Mit LIST_BRANCH=1 erscheint eine ganze Gruppe samt Kontakten auf
				 * einmal, so wie ein Konto es beim Anmelden nachreicht. */
				if ([[[NSProcessInfo processInfo] environment][@"LIST_BRANCH"] boolValue]) {
					[preview addFilledGroupNamed:@"Shoogee" contacts:18];
					[listView reloadData];
					for (NSInteger row = 0; row < listView.numberOfRows; row++) {
						id item = [listView itemAtRow:row];
						if ([listView isExpandable:item]) [listView expandItem:item];
					}
					CGFloat grown = MAX(80.0, MIN(760.0, preview.listHeight + 8.0));
					[window setFrame:NSMakeRect(420.0, 260.0, 260.0, grown) display:YES];
					spin(0.4);
				}

				if ([[[NSProcessInfo processInfo] environment][@"LIST_GROW"] boolValue]) {
					for (NSUInteger round = 0; round < 12; round++) {
						[preview addFillerContacts:2];

						//Wie der Listen-Controller es tut, wenn ein Kontakt auftaucht
						for (NSInteger row = 0; row < listView.numberOfRows; row++) {
							id item = [listView itemAtRow:row];
							if ([listView isExpandable:item])
								[listView reloadItem:item reloadChildren:YES];
						}
						/* Das Kontaktlistenfenster waechst im Programm mit der Liste
						 * mit, waehrend die Kontakte eintreffen. */
						CGFloat grown = MAX(80.0, MIN(760.0, preview.listHeight + 8.0));
						[window setFrame:NSMakeRect(420.0, 260.0, 260.0, grown) display:YES];
						[window displayIfNeeded];
						spin(0.08);
					}
					spin(0.3);
				}

				if ([[[NSProcessInfo processInfo] environment][@"LIST_CHURN"] boolValue]) {
					/* Erst das Fenster klein machen, damit die Liste wirklich
					 * scrollen muss und die Tabelle ihre Zeilenansichten
					 * weiterreicht. */
					[window setFrame:NSMakeRect(420.0, 260.0, 260.0, 90.0) display:YES];
					spin(0.3);
					for (NSInteger row = 0; row < listView.numberOfRows; row++) {
						[listView scrollRowToVisible:row];
						spin(0.05);
					}
					for (NSInteger row = listView.numberOfRows - 1; row >= 0; row--) {
						[listView scrollRowToVisible:row];
						spin(0.05);
					}
					[window setFrame:NSMakeRect(420.0, 260.0, 260.0, height) display:YES];
					spin(0.3);

					for (NSInteger row = listView.numberOfRows - 1; row >= 0; row--) {
						id item = [listView itemAtRow:row];
						if ([listView isExpandable:item]) [listView collapseItem:item];
					}
					spin(0.2);
					for (NSInteger row = 0; row < listView.numberOfRows; row++) {
						id item = [listView itemAtRow:row];
						if ([listView isExpandable:item]) [listView expandItem:item];
					}
					spin(0.2);
					[listView scrollRowToVisible:listView.numberOfRows - 1];
					spin(0.2);
					[listView scrollRowToVisible:0];
					spin(0.2);
				}

				writePNG(window, [outDir stringByAppendingPathComponent:
								  [NSString stringWithFormat:@"%@-%@.png", job[@"stem"], mode]]);

				if (!dark) {
					AIListCell *contentCell = (AIListCell *)[listView contentCell];
					AIListCell *groupCell = (AIListCell *)[listView groupCell];
					NSArray *shapeNames = @[@"eckig", @"Mockie", @"Blase"];
					[report appendFormat:@"%@\n  Fensterstil %@ | Kontakt: %@%@, %.0f hoch | Gruppe: %@%@, %.0f hoch | Wunschbreite %ld, Wunschhoehe %ld\n",
					 job[@"stem"], styleNames[[job[@"style"] intValue]],
					 shapeNames[contentCell.shape], (contentCell.fitted ? @" eng" : @""), contentCell.cellSize.height,
					 shapeNames[groupCell.shape], (groupCell.fitted ? @" eng" : @""), groupCell.cellSize.height,
					 (long)listView.desiredWidth, (long)listView.desiredHeight];
				}

				[window orderOut:nil];
			}
		}

		[report writeToFile:[outDir stringByAppendingPathComponent:@"aufbau.txt"]
				 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	}
	return 0;
}
