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

#import <Adium/AIServiceIcons.h>

/* The Flags fixture lists five services and carries artwork for two of them: Jabber and Bonjour, at
 * 32 pixels for the small and list icons and 96 for the large ones. Without an application there is
 * no service to ask for a default icon, so what the pack does not supply is simply missing. */

@interface TestServiceIcons : XCTestCase {
	NSString	*scratchDirectory;
}
@end

@implementation TestServiceIcons

- (NSString *)flagsPackPath
{
	return [[[NSBundle bundleForClass:[self class]] resourcePath]
			stringByAppendingPathComponent:@"Fixtures/Flags.AdiumServiceIcons"];
}

/* The active pack is process-wide state, so every test starts from the fixture */
- (void)setUp
{
	[super setUp];
	scratchDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
						[@"TestServiceIcons-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
	[[NSFileManager defaultManager] createDirectoryAtPath:scratchDirectory
							  withIntermediateDirectories:YES
											   attributes:nil
													error:NULL];
	XCTAssertTrue([AIServiceIcons setActiveServiceIconsFromPath:[self flagsPackPath]]);
}

- (void)tearDown
{
	[[NSFileManager defaultManager] removeItemAtPath:scratchDirectory error:NULL];
	[super tearDown];
}

- (NSImage *)iconFor:(NSString *)serviceID type:(AIServiceIconType)type
{
	return [AIServiceIcons serviceIconForServiceID:serviceID type:type direction:AIIconNormal];
}

- (NSInteger)pixelsAcross:(NSImage *)image
{
	return [[[image representations] objectAtIndex:0] pixelsWide];
}

/* A pack listing the given services, every one of them shown with the fixture's Jabber artwork
 * unless no file name is given at all, in which case the entries name files that do not exist */
- (NSString *)makePackListing:(NSArray *)serviceIDs usingImage:(NSString *)imageName
{
	NSString *packPath = [scratchDirectory stringByAppendingPathComponent:
						  [[[NSUUID UUID] UUIDString] stringByAppendingPathComponent:@"Made.AdiumServiceIcons"]];
	NSMutableDictionary *names = [NSMutableDictionary dictionary];
	NSString *fileName = (imageName ? imageName : @"absent.png");

	for (NSString *serviceID in serviceIDs) [names setObject:fileName forKey:serviceID];

	NSDictionary *plist = [NSDictionary dictionaryWithObjectsAndKeys:
						   [NSNumber numberWithInt:1], @"AdiumSetVersion",
						   names, @"Interface-Small",
						   names, @"Interface-Large",
						   names, @"List",
						   nil];

	[[NSFileManager defaultManager] createDirectoryAtPath:packPath withIntermediateDirectories:YES attributes:nil error:NULL];
	XCTAssertTrue([plist writeToFile:[packPath stringByAppendingPathComponent:@"Icons.plist"] atomically:YES]);
	if (imageName) {
		XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:[[self flagsPackPath] stringByAppendingPathComponent:imageName]
															  toPath:[packPath stringByAppendingPathComponent:imageName]
															   error:NULL]);
	}
	return packPath;
}

#pragma mark Choosing a pack

- (void)testPackWithoutAnIconsListIsRejected
{
	XCTAssertFalse([AIServiceIcons setActiveServiceIconsFromPath:[scratchDirectory stringByAppendingPathComponent:@"None.AdiumServiceIcons"]]);
}

- (void)testChangingThePackIsAnnounced
{
	__block NSUInteger announcements = 0;
	id observer = [[NSNotificationCenter defaultCenter] addObserverForName:AIServiceIconSetDidChangeNotification
																	object:nil
																	 queue:nil
																usingBlock:^(NSNotification *note) { announcements++; }];

	[AIServiceIcons setActiveServiceIconsFromPath:[self flagsPackPath]];
	[[NSNotificationCenter defaultCenter] removeObserver:observer];

	XCTAssertEqual(announcements, (NSUInteger)1);
}

- (void)testSwitchingPacksReplacesTheIcons
{
	XCTAssertEqual([self pixelsAcross:[self iconFor:@"Jabber" type:AIServiceIconSmall]], (NSInteger)32);

	NSString *otherPack = [self makePackListing:[NSArray arrayWithObject:@"Jabber"] usingImage:@"jabber.png"];
	XCTAssertTrue([AIServiceIcons setActiveServiceIconsFromPath:otherPack]);

	XCTAssertEqual([self pixelsAcross:[self iconFor:@"Jabber" type:AIServiceIconSmall]], (NSInteger)96);
}

#pragma mark The size an icon is shown at

- (void)testSmallIconIsShownAtSixteenPointsWhateverItsPixels
{
	NSImage *icon = [self iconFor:@"Jabber" type:AIServiceIconSmall];

	XCTAssertTrue(NSEqualSizes([icon size], NSMakeSize(16, 16)), @"Got %@", NSStringFromSize([icon size]));
	XCTAssertEqual([self pixelsAcross:icon], (NSInteger)32, @"The pixels stay for sharper displays");
}

- (void)testListIconIsShownAtSixteenPoints
{
	XCTAssertTrue(NSEqualSizes([[self iconFor:@"Bonjour" type:AIServiceIconList] size], NSMakeSize(16, 16)));
}

- (void)testLargeIconIsShownAtFortyEightPoints
{
	NSImage *icon = [self iconFor:@"Jabber" type:AIServiceIconLarge];

	XCTAssertTrue(NSEqualSizes([icon size], NSMakeSize(48, 48)), @"Got %@", NSStringFromSize([icon size]));
	XCTAssertEqual([self pixelsAcross:icon], (NSInteger)96);
}

#pragma mark Finding an icon

- (void)testPathOfAnIconIsItsFileInsideThePack
{
	XCTAssertEqualObjects([AIServiceIcons pathForServiceIconForServiceID:@"Jabber" type:AIServiceIconSmall],
						  [[self flagsPackPath] stringByAppendingPathComponent:@"jabber-small.png"]);
	XCTAssertEqualObjects([AIServiceIcons pathForServiceIconForServiceID:@"Bonjour" type:AIServiceIconLarge],
						  [[self flagsPackPath] stringByAppendingPathComponent:@"bonjour.png"]);
}

- (void)testServiceThePackDoesNotListHasNoPathInIt
{
	XCTAssertNil([AIServiceIcons pathForServiceIconForServiceID:@"Dodo" type:AIServiceIconSmall]);
}

#pragma mark The preview in the menu

- (void)testPreviewOfAPackWithoutAnIconsListIsNil
{
	XCTAssertNil([AIServiceIcons previewMenuImageForIconPackAtPath:[scratchDirectory stringByAppendingPathComponent:@"None.AdiumServiceIcons"]]);
}

- (void)testPreviewOfAPackListingNoServicesIsNil
{
	XCTAssertNil([AIServiceIcons previewMenuImageForIconPackAtPath:[self makePackListing:[NSArray array] usingImage:nil]]);
}

- (void)testPreviewIsOnlyAsWideAsTheServicesItShows
{
	NSImage *two = [AIServiceIcons previewMenuImageForIconPackAtPath:
					[self makePackListing:[NSArray arrayWithObjects:@"Jabber", @"Bonjour", nil] usingImage:@"jabber-small.png"]];
	NSImage *four = [AIServiceIcons previewMenuImageForIconPackAtPath:
					 [self makePackListing:[NSArray arrayWithObjects:@"Jabber", @"Bonjour", @"IRC", @"Telegram", nil] usingImage:@"jabber-small.png"]];

	XCTAssertNotNil(two);
	XCTAssertLessThan([two size].width, [four size].width);
	XCTAssertEqual([two size].height, [four size].height);
}

- (void)testPreviewShowsAtMostFourServices
{
	NSImage *four = [AIServiceIcons previewMenuImageForIconPackAtPath:
					 [self makePackListing:[NSArray arrayWithObjects:@"Jabber", @"Bonjour", @"IRC", @"Telegram", nil] usingImage:@"jabber-small.png"]];
	NSImage *five = [AIServiceIcons previewMenuImageForIconPackAtPath:[self flagsPackPath]];

	XCTAssertEqual([five size].width, [four size].width);
}

- (void)testPreviewStillHasRoomForServicesWhoseFilesAreMissing
{
	NSImage *withArt = [AIServiceIcons previewMenuImageForIconPackAtPath:
						[self makePackListing:[NSArray arrayWithObjects:@"Jabber", @"Bonjour", nil] usingImage:@"jabber-small.png"]];
	NSImage *withoutArt = [AIServiceIcons previewMenuImageForIconPackAtPath:
						   [self makePackListing:[NSArray arrayWithObjects:@"Jabber", @"Bonjour", nil] usingImage:nil]];

	XCTAssertEqual([withoutArt size].width, [withArt size].width, @"The icons stay in step whether or not every file is there");
}

@end
