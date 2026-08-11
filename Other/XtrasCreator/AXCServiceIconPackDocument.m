//
//  AXCServiceIconPackDocument.m
//  XtrasCreator
//
//  Created by Mac-arena the Bored Zo on 2005-10-30.
//  Copyright 2005 Adium Team. All rights reserved.
//

#import "AXCServiceIconPackDocument.h"
#import "AXCIconPackEntry.h"

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
	return [NSArray arrayWithObjects:
		[AXCIconPackEntry entryWithKey:@"AIM"          path:nil],
		[AXCIconPackEntry entryWithKey:@"Bonjour"      path:nil],
		[AXCIconPackEntry entryWithKey:@"Gadu-Gadu"    path:nil],
		[AXCIconPackEntry entryWithKey:@"GroupWise"    path:nil],
		[AXCIconPackEntry entryWithKey:@"GTalk"        path:nil],
		[AXCIconPackEntry entryWithKey:@"ICQ"          path:nil],
		[AXCIconPackEntry entryWithKey:@"Jabber"       path:nil],
		[AXCIconPackEntry entryWithKey:@"Mac"          path:nil],
		[AXCIconPackEntry entryWithKey:@"MSN"          path:nil],
		[AXCIconPackEntry entryWithKey:@"Napster"      path:nil],
		[AXCIconPackEntry entryWithKey:@"Sametime"     path:nil],
		[AXCIconPackEntry entryWithKey:@"Stress Test"  path:nil],
		[AXCIconPackEntry entryWithKey:@"Trepia"       path:nil],
		[AXCIconPackEntry entryWithKey:@"Yahoo!"       path:nil],
		[AXCIconPackEntry entryWithKey:@"Yahoo! Japan" path:nil],
		/* TODO ADIUM-UNUSED: Zephyr, to be dropped with the rest of the Zephyr set (see
		 * CBPurpleServicePlugin.m, inventory in Other/ADIUM-UNUSED.txt). This tool isn't part
		 * of Adium.xcodeproj, so removing the entry has no effect on the app build; it only
		 * keeps XtrasCreator from offering an icon slot for a service that no longer exists.
		 */
		[AXCIconPackEntry entryWithKey:@"Zephyr"       path:nil],
		nil];
}

@end
