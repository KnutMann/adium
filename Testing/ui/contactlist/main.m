/* A harness that photographs Adium's contact list without running Adium.
 *
 * It links the real Adium framework, builds a made-up contact list out of real
 * AIListGroup and AIListContact objects, hands it to a real
 * AIAbstractListController with a real AIListOutlineView, and takes a picture
 * for every window style and every shipped layout and colour set.
 *
 * Why it can work without a program behind it: the shared Adium instance is a
 * plain global that stays nil here, and every place the drawing reaches for it
 * tolerates nil. No preference is read and none is written, and no real contact
 * is ever touched: every name below is invented for this harness.
 */
#import <Cocoa/Cocoa.h>

#import <Adium/AIAbstractListController.h>
#import <Adium/AIContactList.h>
#import <Adium/AIListCell.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListGroup.h>
#import <Adium/AIListObject.h>
#import <Adium/AIListOutlineView.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <Adium/AIService.h>
#import <Adium/AIServiceIcons.h>
#import <Adium/AIStatusIcons.h>
#import <Adium/AIStatusControllerProtocol.h>
#import <Adium/AIUserIcons.h>
#import <AIUtilities/AIAutoScrollView.h>
#import <AIUtilities/AIColorAdditions.h>

#pragma mark Stand-ins

/* A service exists only so that the service icon packs have a name to look up. */
@interface ShotService : AIService
@property (nonatomic, copy) NSString *ident;
@end

@implementation ShotService
- (NSString *)serviceID { return self.ident; }
- (NSString *)serviceCodeUniqueID { return [@"libpurple-" stringByAppendingString:self.ident]; }
- (NSString *)serviceClass { return self.ident; }
- (NSString *)shortDescription { return self.ident; }
- (NSString *)longDescription { return self.ident; }
@end

/* The owner recorded for an injected user icon. AIUserIcons refuses an icon
 * that comes without one. */
@interface ShotIconSource : NSObject <AIUserIconSource>
@end

@implementation ShotIconSource
- (AIUserIconSourceQueryResult)updateUserIconForObject:(AIListObject *)inObject { return AIUserIconSourceDidNotFindIcon; }
- (AIUserIconPriority)priority { return AIUserIconHighestPriority; }
@end

@interface ShotDelegate : NSObject <AIListControllerDelegate>
@end

@implementation ShotDelegate
- (IBAction)performDefaultActionOnSelectedObject:(AIListObject *)selectedObject sender:(NSOutlineView *)sender { }
@end

/* The window style normally comes out of the preferences. Here it is simply
 * told to us, which is the only thing the list controller asks of its subclass
 * besides three fixed answers. */
@interface ShotController : AIAbstractListController
@property (nonatomic) AIContactListWindowStyle style;
@end

@implementation ShotController
- (AIContactListWindowStyle)windowStyle { return self.style; }
- (BOOL)useAliasesInContactListAsRequested { return YES; }
- (BOOL)shouldUseContactTextColors { return YES; }
- (BOOL)useStatusMessageAsExtendedStatus { return NO; }
@end

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
@end

@implementation ShotBackdrop
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirty { [self.ground set]; NSRectFill(dirty); }
@end

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
	fprintf(stdout, "%s\n", path.lastPathComponent.UTF8String);
}

#pragma mark The made-up contact list

static ShotService *serviceNamed(NSString *ident)
{
	static NSMutableDictionary *services = nil;
	if (!services) services = [NSMutableDictionary dictionary];
	ShotService *service = services[ident];
	if (!service) {
		service = [[ShotService alloc] init];
		service.ident = ident;
		services[ident] = service;
	}
	return service;
}

/* A drawn stand-in for a user picture: initials on a coloured disc. Nothing is
 * read from disk, so the pictures stay the same on every machine. */
static NSImage *placeholderIcon(NSString *name, NSColor *tint)
{
	NSSize size = NSMakeSize(64.0, 64.0);
	NSImage *image = [[NSImage alloc] initWithSize:size];
	[image lockFocus];
	[tint set];
	[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, size.width, size.height)] fill];

	NSMutableString *initials = [NSMutableString string];
	for (NSString *word in [name componentsSeparatedByString:@" "]) {
		if (word.length && initials.length < 2) [initials appendString:[[word substringToIndex:1] uppercaseString]];
	}
	NSDictionary *attributes = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:26.0],
								  NSForegroundColorAttributeName: [NSColor whiteColor] };
	NSSize drawn = [initials sizeWithAttributes:attributes];
	[initials drawAtPoint:NSMakePoint((size.width - drawn.width) / 2.0, (size.height - drawn.height) / 2.0)
		   withAttributes:attributes];
	[image unlockFocus];
	return image;
}

static AIListContact *makeContact(NSString *uid, NSString *name, NSString *serviceID,
								  BOOL online, AIStatusType statusType,
								  NSString *statusMessage, NSString *idleReadable,
								  NSColor *labelColor, NSColor *textColor,
								  ShotIconSource *iconSource, NSColor *iconTint)
{
	AIListContact *contact = [[AIListContact alloc] initWithUID:uid
														account:nil
														service:serviceNamed(serviceID)];
	/* The delayed preference read that AIListObject schedules for itself has
	 * nothing to read here, so it is dropped rather than left to fire. */
	[NSObject cancelPreviousPerformRequestsWithTarget:contact];

	/* setDisplayName: writes an alias into the preferences, which there are
	 * none of here. The drawn name falls back to the formatted UID, so that is
	 * where the made-up name goes. */
	[contact setValue:name forProperty:KEY_FORMATTED_UID notify:NotifyNever];
	[contact setValue:@(online) forProperty:@"isOnline" notify:NotifyNever];
	[contact setValue:@(statusType) forProperty:@"listObjectStatusType" notify:NotifyNever];
	/* Without this the drawing paints every icon at zero opacity. In the
	 * program it is the status colouring plugin that sets it. */
	[contact setValue:@1.0 forProperty:@"imageOpacity" notify:NotifyNever];

	if (statusMessage.length) {
		[contact setValue:[[NSAttributedString alloc] initWithString:statusMessage]
			  forProperty:@"listObjectStatusMessage" notify:NotifyNever];
		[contact setValue:statusMessage forProperty:@"extendedStatus" notify:NotifyNever];
	}
	if (idleReadable.length) {
		[contact setValue:idleReadable forProperty:@"idleReadable" notify:NotifyNever];
		[contact setValue:@(3600 * 2) forProperty:@"idle" notify:NotifyNever];
	}
	if (labelColor) [contact setValue:labelColor forProperty:@"harnessEventLabelColor" notify:NotifyNever];
	if (textColor) [contact setValue:textColor forProperty:@"harnessEventTextColor" notify:NotifyNever];

	if (iconTint) {
		[AIUserIcons setActualUserIcon:placeholderIcon(name, iconTint)
							 andSource:iconSource
							 forObject:contact];
	}
	return contact;
}

/* The colours a contact is drawn in come from the colour set, by way of
 * AIContactStatusColoringPlugin. Without that plugin every name would fall back
 * to the system label colour, which is nearly white in the dark and so tells
 * nothing about the set being photographed. This does the same work by hand. */
static void applyThemeColours(NSArray *contacts, NSDictionary *themeDict)
{
	for (AIListContact *contact in contacts) {
		NSString *colourKey = nil, *labelKey = nil, *enabledKey = nil;

		if ([contact valueForProperty:@"harnessEventTextColor"] ||
			[contact valueForProperty:@"harnessEventLabelColor"]) {
			colourKey = @"Unviewed Content Color";
			labelKey = @"Unviewed Content Label Color";
			enabledKey = @"Unviewed Content Enabled";
		} else if (!contact.online) {
			colourKey = @"Offline Color"; labelKey = @"Offline Label Color"; enabledKey = @"Offline Enabled";
		} else if (contact.statusType == AIAwayStatusType) {
			colourKey = @"Away Color"; labelKey = @"Away Label Color"; enabledKey = @"Away Enabled";
		} else {
			colourKey = @"Online Color"; labelKey = @"Online Label Color"; enabledKey = @"Online Enabled";
		}

		BOOL enabled = [[themeDict objectForKey:enabledKey] boolValue];
		[contact setValue:(enabled ? [[themeDict objectForKey:colourKey] representedColor] : nil)
			  forProperty:@"textColor" notify:NotifyNever];
		[contact setValue:(enabled ? [[themeDict objectForKey:labelKey] representedColor] : nil)
			  forProperty:@"labelColor" notify:NotifyNever];
		[contact setValue:@(enabled && [colourKey isEqualToString:@"Unviewed Content Color"])
			  forProperty:@"isEvent" notify:NotifyNever];
	}
}

/* The status icon normally arrives as a property from the tab icon plugin.
 * Filling it here is what makes the shipped icon pack show up. */
static void fillStatusIcons(NSArray *contacts)
{
	for (AIListContact *contact in contacts) {
		NSImage *icon = [AIStatusIcons statusIconForListObject:contact
														  type:AIStatusIconList
													 direction:AIIconNormal];
		if (icon) [contact setValue:icon forProperty:@"listStatusIcon" notify:NotifyNever];
	}
}

static AIContactList *buildContactList(NSMutableArray *allContacts)
{
	ShotIconSource *iconSource = [[ShotIconSource alloc] init];
	AIContactList *root = [[AIContactList alloc] initWithUID:@"Prüfstand"];

	AIListGroup *work = [[AIListGroup alloc] initWithUID:@"Arbeit"];
	AIListGroup *friends = [[AIListGroup alloc] initWithUID:@"Freunde"];

	NSArray *inWork = @[
		makeContact(@"tanja@beispiel.invalid", @"Tanja Berg", @"Jabber",
					YES, AIAvailableStatusType, @"Schreibt am Bericht", nil,
					nil, nil, iconSource, [NSColor colorWithCalibratedRed:0.20 green:0.45 blue:0.72 alpha:1.0]),
		makeContact(@"ruben@beispiel.invalid", @"Ruben Faust", @"Jabber",
					YES, AIAwayStatusType, @"Mittagspause", @"2 Std.",
					nil, nil, iconSource, [NSColor colorWithCalibratedRed:0.63 green:0.35 blue:0.16 alpha:1.0]),
		makeContact(@"milan@beispiel.invalid", @"Milan Oster", @"WhatsApp",
					NO, AIOfflineStatusType, nil, nil,
					nil, nil, iconSource, [NSColor colorWithCalibratedRed:0.42 green:0.42 blue:0.45 alpha:1.0]),
	];
	NSArray *inFriends = @[
		makeContact(@"nora@beispiel.invalid", @"Nora Weiss", @"Telegram",
					YES, AIAvailableStatusType, @"Ungelesene Nachricht", nil,
					[NSColor colorWithCalibratedRed:1.0 green:0.87 blue:0.45 alpha:1.0], nil,
					iconSource, [NSColor colorWithCalibratedRed:0.55 green:0.25 blue:0.55 alpha:1.0]),
		makeContact(@"pepe@beispiel.invalid", @"Pepe Lindt", @"Bonjour",
					YES, AIAvailableStatusType, nil, nil,
					nil, nil, iconSource, [NSColor colorWithCalibratedRed:0.19 green:0.55 blue:0.36 alpha:1.0]),
	];

	/* Added back to front: without a sort controller the group keeps the
	 * reverse of the order it was filled in. */
	for (AIListContact *contact in inWork.reverseObjectEnumerator) [work addObject:contact];
	for (AIListContact *contact in inFriends.reverseObjectEnumerator) [friends addObject:contact];
	[allContacts addObjectsFromArray:inWork];
	[allContacts addObjectsFromArray:inFriends];

	[work setValue:@YES forProperty:@"showCount" notify:NotifyNever];
	[work setValue:@"2/3" forProperty:@"countText" notify:NotifyNever];
	[friends setValue:@YES forProperty:@"showCount" notify:NotifyNever];
	[friends setValue:@"2/2" forProperty:@"countText" notify:NotifyNever];

	[root addObject:friends];
	[root addObject:work];
	return root;
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

		NSMutableArray *allContacts = [NSMutableArray array];
		AIContactList *contactList = buildContactList(allContacts);
		fillStatusIcons(allContacts);

		NSDictionary *baseLayout = setNamed(root, @"Aqualicious", @"ListLayout");
		NSDictionary *baseTheme = setNamed(root, @"Aqualicious", @"ListTheme");
		if (!baseLayout || !baseTheme) return 1;

		/* What gets photographed. The first block walks the window styles at the
		 * standard set, the second the shipped layouts, the third the shipped
		 * colour sets. Layouts and colour sets are shown at the style Adium
		 * starts with, because the style does not travel inside them. */
		/* The group chat style is left out: it is the participant list of a
		 * group conversation, not the contact list, and its cell asks a chat
		 * and a role icon pack for everything it draws. Neither exists here. */
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
		ShotDelegate *delegate = [[ShotDelegate alloc] init];

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
				/* The bubble styles draw no background of their own, so the
				 * window has to supply one or the pictures show the desktop. */
				window.backgroundColor = (dark ? [NSColor colorWithCalibratedWhite:0.16 alpha:1.0]
											   : [NSColor colorWithCalibratedWhite:0.93 alpha:1.0]);

				ShotBackdrop *backdrop = [[ShotBackdrop alloc] initWithFrame:content];
				backdrop.ground = window.backgroundColor;
				backdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

				AIAutoScrollView *scrollView = [[AIAutoScrollView alloc] initWithFrame:content];
				AIListOutlineView *outlineView = [[AIListOutlineView alloc] initWithFrame:content];
				NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"contacts"];
				column.width = content.size.width;
				[outlineView addTableColumn:column];
				outlineView.outlineTableColumn = column;
				outlineView.headerView = nil;
				scrollView.documentView = outlineView;
				scrollView.hasVerticalScroller = NO;
				scrollView.borderType = NSNoBorder;
				scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
				[backdrop addSubview:scrollView];
				window.contentView = backdrop;

				ShotController *controller = [[ShotController alloc] initWithContactListView:outlineView
																			   inScrollView:scrollView
																				   delegate:delegate];
				controller.style = [job[@"style"] intValue];
				[controller setContactListRoot:contactList];
				applyThemeColours(allContacts, job[@"theme"]);
				[controller updateLayoutFromPrefDict:job[@"layout"] andThemeFromPrefDict:job[@"theme"]];
				/* In the program this arrives from the preference observer, which
				 * has nobody to speak for it here. Without it the row stripe does
				 * not restart under a group. */
				[outlineView preferencesChangedForGroup:PREF_GROUP_LIST_THEME
													key:nil
												 object:nil
										 preferenceDict:job[@"theme"]
											  firstTime:YES];

				[outlineView reloadData];
				/* Only the groups open; asking a contact to expand ends in
				 * setExpanded: on an object that has no such thing. */
				for (NSInteger row = 0; row < outlineView.numberOfRows; row++) {
					id item = [outlineView itemAtRow:row];
					if ([outlineView isExpandable:item]) [outlineView expandItem:item];
				}
				[outlineView reloadData];

				[window setFrameOrigin:NSMakePoint(420.0, 260.0)];
				/* Key and active, or the selected row is drawn in the pale
				 * unemphasized colour instead of the real one. */
				[NSApp activateIgnoringOtherApps:YES];
				[window makeKeyAndOrderFront:nil];
				spin(0.4);

				CGFloat height = MAX(80.0, MIN(520.0, (CGFloat)outlineView.desiredHeight + 8.0));
				[window setFrame:NSMakeRect(420.0, 260.0, 260.0, height) display:YES];

				/* One contact selected, so the pictures also show how a picked
				 * row looks in each style. The list has to hold the keyboard for
				 * that, or the pale out-of-focus colour is drawn instead. */
				if (outlineView.numberOfRows > 2)
					[outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
				[window makeFirstResponder:outlineView];
				spin(0.4);
				if (!window.isKeyWindow)
					fprintf(stderr, "Hinweis: kein Tastaturfenster bei %s, die Auswahl wird blass gezeichnet\n",
							[job[@"stem"] UTF8String]);

				writePNG(window, [outDir stringByAppendingPathComponent:
								  [NSString stringWithFormat:@"%@-%@.png", job[@"stem"], mode]]);

				if (!dark) {
					AIListCell *contentCell = (AIListCell *)[outlineView contentCell];
					AIListCell *groupCell = (AIListCell *)[outlineView groupCell];
					NSArray *shapeNames = @[@"eckig", @"Mockie", @"Blase"];
					[report appendFormat:@"%@\n  Fensterstil %@ | Kontakt: %@%@, %.0f hoch | Gruppe: %@%@, %.0f hoch | Wunschbreite %ld, Wunschhoehe %ld\n",
					 job[@"stem"], styleNames[[job[@"style"] intValue]],
					 shapeNames[contentCell.shape], (contentCell.fitted ? @" eng" : @""), contentCell.cellSize.height,
					 shapeNames[groupCell.shape], (groupCell.fitted ? @" eng" : @""), groupCell.cellSize.height,
					 (long)outlineView.desiredWidth, (long)outlineView.desiredHeight];
				}

				[window orderOut:nil];
				[outlineView setDelegate:nil];
				[outlineView setDataSource:nil];
			}
		}

		[report writeToFile:[outDir stringByAppendingPathComponent:@"aufbau.txt"]
				 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	}
	return 0;
}
