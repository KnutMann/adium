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

#import <Adium/AIContactListPreviewView.h>

#import <Adium/AIContactList.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListGroup.h>
#import <Adium/AIListObject.h>
#import <Adium/AIListOutlineView.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <Adium/AIService.h>
#import <Adium/AIStatusIcons.h>
#import <Adium/AIUserIcons.h>
#import <AIUtilities/AIAutoScrollView.h>
#import <AIUtilities/AIColorAdditions.h>

#pragma mark Stand-ins

/*!
 * @brief A service that exists only so the service icon packs have a name to look up
 */
@interface AIPreviewService : AIService
@property (nonatomic, copy) NSString *ident;
@end

@implementation AIPreviewService
- (NSString *)serviceID { return self.ident; }
- (NSString *)serviceCodeUniqueID { return [@"preview-" stringByAppendingString:self.ident]; }
- (NSString *)serviceClass { return self.ident; }
- (NSString *)shortDescription { return self.ident; }
- (NSString *)longDescription { return self.ident; }
@end

/*!
 * @brief The owner recorded for an injected picture
 *
 * AIUserIcons refuses an icon that arrives without a source.
 */
@interface AIPreviewIconSource : NSObject <AIUserIconSource>
@end

@implementation AIPreviewIconSource
- (AIUserIconSourceQueryResult)updateUserIconForObject:(AIListObject *)inObject { return AIUserIconSourceDidNotFindIcon; }
- (AIUserIconPriority)priority { return AIUserIconHighestPriority; }
@end

@interface AIPreviewListDelegate : NSObject <AIListControllerDelegate>
@end

@implementation AIPreviewListDelegate
- (IBAction)performDefaultActionOnSelectedObject:(AIListObject *)selectedObject sender:(NSOutlineView *)sender { }
@end

/*!
 * @brief A list controller that is told its window style instead of reading it
 */
@interface AIPreviewListController : AIAbstractListController
@property (nonatomic) AIContactListWindowStyle style;
@end

@implementation AIPreviewListController
@synthesize style;
- (AIContactListWindowStyle)windowStyle { return style; }
- (BOOL)useAliasesInContactListAsRequested { return YES; }
- (BOOL)shouldUseContactTextColors { return YES; }
- (BOOL)useStatusMessageAsExtendedStatus { return NO; }
- (void)contactListDesiredSizeChanged { }
@end

#pragma mark The preview

@implementation AIContactListPreviewView {
	AIAutoScrollView		*scrollView;
	AIListOutlineView		*outlineView;
	AIPreviewListController	*listController;
	AIPreviewListDelegate	*listDelegate;
	AIContactList			*contactList;
	NSMutableArray			*previewContacts;
}

@synthesize listView = outlineView;

- (instancetype)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		previewContacts = [[NSMutableArray alloc] init];
		contactList = [self buildContactList];

		outlineView = [[AIListOutlineView alloc] initWithFrame:self.bounds];
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"contacts"];
		column.width = NSWidth(self.bounds);
		[outlineView addTableColumn:column];
		outlineView.outlineTableColumn = column;
		outlineView.headerView = nil;

		scrollView = [[AIAutoScrollView alloc] initWithFrame:self.bounds];
		scrollView.documentView = outlineView;
		scrollView.hasVerticalScroller = NO;
		scrollView.borderType = NSNoBorder;
		scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		[self addSubview:scrollView];

		listDelegate = [[AIPreviewListDelegate alloc] init];
		listController = [[AIPreviewListController alloc] initWithContactListView:outlineView
																	inScrollView:scrollView
																		delegate:listDelegate];
		[listController setContactListRoot:contactList];
	}

	return self;
}

- (void)dealloc
{
	[outlineView setDelegate:nil];
	[outlineView setDataSource:nil];
}

#pragma mark The invented contacts

/*!
 * @brief A drawn stand-in for a user picture
 *
 * Initials on a coloured disc. Nothing is read from disk, so the preview looks
 * the same on every machine and pulls in nobody's photograph.
 */
static NSImage *previewIcon(NSString *name, NSColor *tint)
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

- (AIService *)serviceNamed:(NSString *)ident
{
	static NSMutableDictionary *services = nil;
	if (!services) services = [NSMutableDictionary dictionary];

	AIPreviewService *service = services[ident];
	if (!service) {
		service = [[AIPreviewService alloc] init];
		service.ident = ident;
		services[ident] = service;
	}
	return service;
}

- (AIListContact *)contactWithUID:(NSString *)uid
							 name:(NSString *)name
						  service:(NSString *)serviceID
						   online:(BOOL)online
					   statusType:(AIStatusType)statusType
					statusMessage:(NSString *)statusMessage
					 idleReadable:(NSString *)idleReadable
						  isEvent:(BOOL)isEvent
						 iconTint:(NSColor *)iconTint
					   iconSource:(AIPreviewIconSource *)iconSource
{
	AIListContact *contact = [[AIListContact alloc] initWithUID:uid
													   account:nil
													   service:[self serviceNamed:serviceID]];
	/* The delayed preference read AIListObject schedules for itself has nothing
	 * to say about an invented contact. */
	[NSObject cancelPreviousPerformRequestsWithTarget:contact];

	/* The drawn name: setDisplayName: would write an alias into the
	 * preferences, and an invented contact has no business doing that. */
	[contact setValue:name forProperty:KEY_FORMATTED_UID notify:NotifyNever];
	[contact setValue:@(online) forProperty:@"isOnline" notify:NotifyNever];
	[contact setValue:@(statusType) forProperty:@"listObjectStatusType" notify:NotifyNever];
	/* Without this every icon is drawn at no opacity at all. */
	[contact setValue:@1.0 forProperty:@"imageOpacity" notify:NotifyNever];
	[contact setValue:@(isEvent) forProperty:@"previewIsEvent" notify:NotifyNever];

	if (statusMessage.length) {
		[contact setValue:[[NSAttributedString alloc] initWithString:statusMessage]
			  forProperty:@"listObjectStatusMessage" notify:NotifyNever];
		[contact setValue:statusMessage forProperty:@"extendedStatus" notify:NotifyNever];
	}
	if (idleReadable.length) {
		[contact setValue:idleReadable forProperty:@"idleReadable" notify:NotifyNever];
		[contact setValue:@(3600 * 2) forProperty:@"idle" notify:NotifyNever];
	}
	if (iconTint) {
		[AIUserIcons setActualUserIcon:previewIcon(name, iconTint) andSource:iconSource forObject:contact];
	}

	[previewContacts addObject:contact];
	return contact;
}

- (AIContactList *)buildContactList
{
	AIPreviewIconSource *iconSource = [[AIPreviewIconSource alloc] init];
	AIContactList *root = [[AIContactList alloc] initWithUID:@"Vorschau"];

	AIListGroup *work = [[AIListGroup alloc] initWithUID:AILocalizedString(@"Work", "Name of a made-up group in the contact list preview")];
	AIListGroup *friends = [[AIListGroup alloc] initWithUID:AILocalizedString(@"Friends", "Name of a made-up group in the contact list preview")];

	NSArray *inWork = @[
		[self contactWithUID:@"tanja@beispiel.invalid" name:@"Tanja Berg" service:@"Jabber"
					  online:YES statusType:AIAvailableStatusType
			   statusMessage:AILocalizedString(@"Writing the report", "Made-up status message in the contact list preview")
				idleReadable:nil isEvent:NO
					iconTint:[NSColor colorWithCalibratedRed:0.20 green:0.45 blue:0.72 alpha:1.0]
				  iconSource:iconSource],
		[self contactWithUID:@"ruben@beispiel.invalid" name:@"Ruben Faust" service:@"Jabber"
					  online:YES statusType:AIAwayStatusType
			   statusMessage:AILocalizedString(@"Out to lunch", "Made-up status message in the contact list preview")
				idleReadable:AILocalizedString(@"2 hrs", "Made-up idle time in the contact list preview")
					 isEvent:NO
					iconTint:[NSColor colorWithCalibratedRed:0.63 green:0.35 blue:0.16 alpha:1.0]
				  iconSource:iconSource],
		[self contactWithUID:@"milan@beispiel.invalid" name:@"Milan Oster" service:@"WhatsApp"
					  online:NO statusType:AIOfflineStatusType
			   statusMessage:nil idleReadable:nil isEvent:NO
					iconTint:[NSColor colorWithCalibratedRed:0.42 green:0.42 blue:0.45 alpha:1.0]
				  iconSource:iconSource],
	];
	NSArray *inFriends = @[
		[self contactWithUID:@"nora@beispiel.invalid" name:@"Nora Weiss" service:@"Telegram"
					  online:YES statusType:AIAvailableStatusType
			   statusMessage:AILocalizedString(@"Unread message", "Made-up status message in the contact list preview")
				idleReadable:nil isEvent:YES
					iconTint:[NSColor colorWithCalibratedRed:0.55 green:0.25 blue:0.55 alpha:1.0]
				  iconSource:iconSource],
		[self contactWithUID:@"pepe@beispiel.invalid" name:@"Pepe Lindt" service:@"Bonjour"
					  online:YES statusType:AIAvailableStatusType
			   statusMessage:nil idleReadable:nil isEvent:NO
					iconTint:[NSColor colorWithCalibratedRed:0.19 green:0.55 blue:0.36 alpha:1.0]
				  iconSource:iconSource],
	];

	/* Added back to front: with no sort controller of its own a group keeps the
	 * reverse of the order it was filled in. */
	for (AIListContact *contact in inWork.reverseObjectEnumerator) [work addObject:contact];
	for (AIListContact *contact in inFriends.reverseObjectEnumerator) [friends addObject:contact];

	[work setValue:@YES forProperty:@"showCount" notify:NotifyNever];
	[work setValue:@"2/3" forProperty:@"countText" notify:NotifyNever];
	[friends setValue:@YES forProperty:@"showCount" notify:NotifyNever];
	[friends setValue:@"2/2" forProperty:@"countText" notify:NotifyNever];

	[root addObject:friends];
	[root addObject:work];

	return root;
}

- (void)addFillerContacts:(NSUInteger)count
{
	AIPreviewIconSource *iconSource = [[AIPreviewIconSource alloc] init];
	AIListGroup *group = nil;
	for (AIListObject *object in contactList.containedObjects) {
		if ([object isKindOfClass:[AIListGroup class]]) { group = (AIListGroup *)object; break; }
	}
	if (!group) return;

	static NSString *const stems[] = { @"Anke", @"Bodo", @"Cara", @"Dilek", @"Emre", @"Fiona",
									   @"Gero", @"Hanna", @"Ilja", @"Jana", @"Kai", @"Lena" };
	for (NSUInteger i = 0; i < count; i++) {
		NSString *name = [NSString stringWithFormat:@"%@ Muster %lu",
						  stems[i % (sizeof(stems) / sizeof(stems[0]))], (unsigned long)(i + 1)];
		AIListContact *contact = [self contactWithUID:[NSString stringWithFormat:@"fuell%lu@beispiel.invalid", (unsigned long)i]
												 name:name
											  service:@"Jabber"
											   online:((i % 3) != 0)
										   statusType:((i % 4) == 1 ? AIAwayStatusType : AIAvailableStatusType)
										statusMessage:((i % 2) ? @"…" : nil)
										 idleReadable:nil
											  isEvent:NO
											 iconTint:[NSColor colorWithCalibratedHue:((i % 12) / 12.0)
																		   saturation:0.5 brightness:0.6 alpha:1.0]
										   iconSource:iconSource];
		[group addObject:contact];
	}
}

#pragma mark Showing a set

/*!
 * @brief Colour the invented contacts the way the colour set asks
 */
- (void)applyThemeColours:(NSDictionary *)themeDict
{
	for (AIListContact *contact in previewContacts) {
		NSString *colourKey, *labelKey, *enabledKey;

		if ([contact boolValueForProperty:@"previewIsEvent"]) {
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
		[contact setValue:@(enabled && [contact boolValueForProperty:@"previewIsEvent"])
			  forProperty:@"isEvent" notify:NotifyNever];

		/* The status icon normally arrives as a property from the tab icon
		 * plugin, which has nothing to say about an invented contact. */
		NSImage *icon = [AIStatusIcons statusIconForListObject:contact
														  type:AIStatusIconList
													 direction:AIIconNormal];
		if (icon) [contact setValue:icon forProperty:@"listStatusIcon" notify:NotifyNever];
	}
}

- (void)applyLayout:(NSDictionary *)layoutDict
			  theme:(NSDictionary *)themeDict
		windowStyle:(AIContactListWindowStyle)windowStyle
{
	listController.style = windowStyle;
	[self applyThemeColours:themeDict];
	[listController updateLayoutFromPrefDict:layoutDict andThemeFromPrefDict:themeDict];

	/* In the program this arrives from the preference observer, which has
	 * nothing to observe here. Without it the row stripe does not restart under
	 * a group. */
	[outlineView preferencesChangedForGroup:PREF_GROUP_LIST_THEME
										key:nil
									 object:nil
							 preferenceDict:themeDict
								  firstTime:YES];

	[outlineView reloadData];
	for (NSInteger row = 0; row < outlineView.numberOfRows; row++) {
		id item = [outlineView itemAtRow:row];
		if ([outlineView isExpandable:item]) [outlineView expandItem:item];
	}
	[outlineView reloadData];
	[outlineView setNeedsDisplay:YES];
}

- (CGFloat)listHeight
{
	return (CGFloat)outlineView.desiredHeight;
}

@end
