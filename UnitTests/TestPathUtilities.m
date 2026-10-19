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

#import <Adium/AIPathUtilities.h>

/* The user domain is left out throughout: for every Adium folder it asks the application singleton
 * for its Application Support directory, and there is no application here. */

@interface TestPathUtilities : XCTestCase
@end

@implementation TestPathUtilities

- (NSString *)insideTheApplication:(NSString *)relativePath
{
	return [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:relativePath];
}

- (NSString *)sharedLibrary
{
	return [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSLocalDomainMask, YES) objectAtIndex:0];
}

#pragma mark Inside the application

- (void)testInternalDomainIsTheApplicationsOwnResourceFolder
{
	NSArray *paths = AISearchPathForDirectoriesInDomainsExpanding(AIEmoticonsDirectory, AIInternalDomainMask, YES);

	XCTAssertEqualObjects([paths objectAtIndex:0], [self insideTheApplication:@"Contents/Resources/Emoticons"]);
}

- (void)testInternalDomainAloneYieldsOnlyTheApplicationsFolder
{

	NSArray *paths = AISearchPathForDirectoriesInDomainsExpanding(AIEmoticonsDirectory, AIInternalDomainMask, YES);

	XCTAssertEqualObjects(paths, [NSArray arrayWithObject:[self insideTheApplication:@"Contents/Resources/Emoticons"]]);
}

- (void)testPlugInsLiveBesideResourcesNotInsideThem
{
	NSArray *paths = AISearchPathForDirectoriesInDomainsExpanding(AIPluginsDirectory, AIInternalDomainMask, YES);

	XCTAssertEqualObjects([paths objectAtIndex:0], [self insideTheApplication:@"Contents/PlugIns"]);
}

#pragma mark The shared Library

- (void)testLocalDomainIsTheSharedApplicationSupportFolder
{
	NSArray *paths = AISearchPathForDirectoriesInDomainsExpanding(AIEmoticonsDirectory, NSLocalDomainMask, YES);

	XCTAssertEqualObjects(paths, [NSArray arrayWithObject:
								  [[self sharedLibrary] stringByAppendingPathComponent:@"Application Support/Adium 2.0/Emoticons"]]);
}

- (void)testSystemDomainIsNeverSearchedForAdiumFolders
{
	XCTAssertEqualObjects(AISearchPathForDirectoriesInDomainsExpanding(AIEmoticonsDirectory, NSSystemDomainMask, YES), [NSArray array]);
}

- (void)testEveryKindOfXtraHasItsOwnFolderName
{
	NSDictionary *folderNames = [NSDictionary dictionaryWithObjectsAndKeys:
								 @"PlugIns", [NSNumber numberWithUnsignedInteger:AIPluginsDirectory],
								 @"Contact List", [NSNumber numberWithUnsignedInteger:AIContactListDirectory],
								 @"Dock Icons", [NSNumber numberWithUnsignedInteger:AIDockIconsDirectory],
								 @"Emoticons", [NSNumber numberWithUnsignedInteger:AIEmoticonsDirectory],
								 @"Message Styles", [NSNumber numberWithUnsignedInteger:AIMessageStylesDirectory],
								 @"Scripts", [NSNumber numberWithUnsignedInteger:AIScriptsDirectory],
								 @"Service Icons", [NSNumber numberWithUnsignedInteger:AIServiceIconsDirectory],
								 @"Sounds", [NSNumber numberWithUnsignedInteger:AISoundsDirectory],
								 @"Status Icons", [NSNumber numberWithUnsignedInteger:AIStatusIconsDirectory],
								 @"Menu Bar Icons", [NSNumber numberWithUnsignedInteger:AIMenuBarIconsDirectory],
								 nil];

	for (NSNumber *directory in folderNames) {
		NSArray *paths = AISearchPathForDirectoriesInDomainsExpanding([directory unsignedIntegerValue], NSLocalDomainMask, YES);

		XCTAssertEqualObjects(paths, [NSArray arrayWithObject:
									  [[self sharedLibrary] stringByAppendingPathComponent:
									   [@"Application Support/Adium 2.0" stringByAppendingPathComponent:[folderNames objectForKey:directory]]]],
							  @"Directory %@", directory);
	}
}

#pragma mark Caches

- (void)testCachesFolderIsUnderTheUsersLibrary
{
	XCTAssertEqualObjects(AISearchPathForDirectoriesInDomainsExpanding(AICachesDirectory, NSUserDomainMask, NO),
						  [NSArray arrayWithObject:@"~/Library/Caches/Adium"]);
}

- (void)testCachesFolderExistsOnlyInTheUserDomain
{
	XCTAssertEqualObjects(AISearchPathForDirectoriesInDomainsExpanding(AICachesDirectory, NSLocalDomainMask, NO), [NSArray array]);
	XCTAssertEqualObjects(AISearchPathForDirectoriesInDomainsExpanding(AICachesDirectory, AIAllDomainsMask, NO),
						  [NSArray arrayWithObject:@"~/Library/Caches/Adium"]);
}

- (void)testTildeIsExpandedOnRequest
{
	NSString *expanded = [AISearchPathForDirectoriesInDomainsExpanding(AICachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];

	XCTAssertEqualObjects(expanded, [@"~/Library/Caches/Adium" stringByExpandingTildeInPath]);
}

#pragma mark Foundation's own directories

- (void)testFoundationDirectoriesPassThroughUnchanged
{
	XCTAssertEqualObjects(AISearchPathForDirectoriesInDomainsExpanding(NSLibraryDirectory, NSLocalDomainMask, YES),
						  NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSLocalDomainMask, YES));
	XCTAssertEqualObjects(AISearchPathForDirectoriesInDomainsExpanding(NSApplicationSupportDirectory, NSLocalDomainMask, YES),
						  NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSLocalDomainMask, YES));
}

@end
