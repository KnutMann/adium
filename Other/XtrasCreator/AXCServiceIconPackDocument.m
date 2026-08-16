//
//  AXCServiceIconPackDocument.m
//  XtrasCreator
//
//  Created by Mac-arena the Bored Zo on 2005-10-30.
//  Copyright 2005 Adium Team. All rights reserved.
//

#import "AXCServiceIconPackDocument.h"
#import "AXCIconPackEntry.h"

typedef struct {
	NSString *serviceID;
	NSString *displayName;
	BOOL supported;
} AXCServiceDefinition;

/*
 * Keep these service IDs aligned with the registrations in
 * Plugins/Purple Service/CBPurpleServicePlugin.m and the descriptors copied by
 * the "Copy Purple Plugins" build phase. Service IDs, not display names, are
 * the keys that AIServiceIcons looks up in Icons.plist.
 */
static const AXCServiceDefinition serviceDefinitions[] = {
	{ @"Gadu-Gadu",    @"Gadu-Gadu",             YES },
	{ @"GroupWise",    @"GroupWise",             YES },
	{ @"IRCv3",        @"IRC (v3)",              YES },
	{ @"Jabber",       @"Jabber",                YES },
	{ @"SIMPLE",       @"SIMPLE",                YES },
	{ @"Signal",       @"Signal",                YES },
	{ @"Telegram",     @"Telegram",              YES },
	{ @"Teams",        @"Teams",                 YES },
	{ @"TeamsPersonal", @"Teams (Personal)",     YES },
	{ @"WhatsApp",     @"WhatsApp",              YES },

	/* Retain recognised historic IDs for maintaining old sets, but do not
	 * present them as services that a current Adium build can use. */
	{ @"AIM",          @"AIM (unsupported)",          NO },
	{ @"Bonjour",      @"Bonjour (unsupported)",      NO },
	{ @"Facebook",     @"Facebook (unsupported)",     NO },
	{ @"GTalk",        @"GTalk (unsupported)",        NO },
	{ @"ICQ",          @"ICQ (unsupported)",          NO },
	{ @"IRC",          @"IRC (unsupported)",          NO },
	{ @"LiveJournal",  @"LiveJournal (unsupported)",  NO },
	{ @"Mac",          @"Mac (unsupported)",          NO },
	{ @"MSN",          @"MSN (unsupported)",          NO },
	{ @"MySpace",      @"MySpace (unsupported)",      NO },
	{ @"Napster",      @"Napster (unsupported)",      NO },
	{ @"QQ",           @"QQ (unsupported)",           NO },
	{ @"Sametime",     @"Sametime (unsupported)",     NO },
	{ @"Skype",        @"Skype (unsupported)",        NO },
	{ @"Stress Test",  @"Stress Test (unsupported)",  NO },
	{ @"Trepia",       @"Trepia (unsupported)",       NO },
	{ @"Xfire",        @"Xfire (unsupported)",        NO },
	{ @"Yahoo!",       @"Yahoo! (unsupported)",       NO },
	{ @"Yahoo! Japan", @"Yahoo! Japan (unsupported)", NO },
	{ @"Zephyr",       @"Zephyr (unsupported)",       NO }
};

static const NSUInteger serviceDefinitionCount = sizeof(serviceDefinitions) / sizeof(serviceDefinitions[0]);

static const AXCServiceDefinition *serviceDefinitionForID(NSString *serviceID)
{
	for (NSUInteger index = 0; index < serviceDefinitionCount; index++) {
		if ([serviceID isEqualToString:serviceDefinitions[index].serviceID])
			return &serviceDefinitions[index];
	}

	return NULL;
}

@interface AXCServiceIconPackDocument ()
- (AXCIconPackEntry *)entryForServiceID:(NSString *)serviceID path:(NSString *)path;
@end

@implementation AXCServiceIconPackDocument

- (NSString *) OSType {
	return @"AISr";
}
- (NSString *) pathExtension {
	return @"AdiumServiceIcons";
}
- (NSString *) uniformTypeIdentifier {
	return @"com.adiumx.serviceicons";
}

- (NSArray *) categoryNames {
	return [NSArray arrayWithObjects:
		@"Interface-Large", @"Interface-Small", @"List",
		nil];
}

- (NSArray *) entriesForNewDocumentInCategory:(NSString *)categoryName {
	NSMutableArray *entries = [NSMutableArray arrayWithCapacity:serviceDefinitionCount];
	for (NSUInteger index = 0; index < serviceDefinitionCount; index++) {
		[entries addObject:[self entryForServiceID:serviceDefinitions[index].serviceID path:nil]];
	}

	return entries;
}

- (BOOL)readFromFile:(NSString *)path ofType:(NSString *)type
{
	if (![super readFromFile:path ofType:type])
		return NO;

	for (NSString *categoryName in categoryNames) {
		for (AXCIconPackEntry *entry in [categoryStorage objectForKey:categoryName]) {
			const AXCServiceDefinition *definition = serviceDefinitionForID([entry key]);
			if (definition) {
				[entry setDisplayName:definition->displayName];
				[entry setSupported:definition->supported];
			}
		}
	}

	return YES;
}

- (AXCIconPackEntry *)entryForServiceID:(NSString *)serviceID path:(NSString *)path
{
	AXCIconPackEntry *entry = [AXCIconPackEntry entryWithKey:serviceID path:path];
	const AXCServiceDefinition *definition = serviceDefinitionForID(serviceID);
	if (definition) {
		[entry setDisplayName:definition->displayName];
		[entry setSupported:definition->supported];
	}

	return entry;
}

@end
