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

#import <Adium/AIXtraInfo.h>

@interface TestXtraInfo : XCTestCase {
	NSString	*scratchDirectory;
}
@end

@implementation TestXtraInfo

- (void)setUp
{
	[super setUp];
	scratchDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
						[@"TestXtraInfo-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
	[[NSFileManager defaultManager] createDirectoryAtPath:scratchDirectory
							  withIntermediateDirectories:YES
											   attributes:nil
													error:NULL];
}

- (void)tearDown
{
	[[NSFileManager defaultManager] removeItemAtPath:scratchDirectory error:NULL];
	[super tearDown];
}

#pragma mark Xtras to test with

- (NSString *)fixturePath:(NSString *)name
{
	return [[[NSBundle bundleForClass:[self class]] resourcePath]
			stringByAppendingPathComponent:[@"Fixtures" stringByAppendingPathComponent:name]];
}

- (AIXtraInfo *)fixture:(NSString *)name
{
	return [AIXtraInfo infoWithURL:[NSURL fileURLWithPath:[self fixturePath:name]]];
}

/* An Xtra written for one test, with its manifest at the root the way the script packs keep theirs.
 * Each gets a folder of its own, since NSBundle remembers a path for the life of the process. */
- (AIXtraInfo *)xtraNamed:(NSString *)name manifest:(NSDictionary *)manifest
{
	NSString *path = [scratchDirectory stringByAppendingPathComponent:
					  [[[NSUUID UUID] UUIDString] stringByAppendingPathComponent:name]];

	[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
	if (manifest) {
		XCTAssertTrue([manifest writeToFile:[path stringByAppendingPathComponent:@"Info.plist"] atomically:YES]);
	}
	return [AIXtraInfo infoWithURL:[NSURL fileURLWithPath:path]];
}

#pragma mark Kind and place

- (void)testTypeIsTheLowercasedExtension
{
	XCTAssertEqualObjects([[self fixture:@"Birds.AdiumEmoticonset"] type], @"adiumemoticonset");
	XCTAssertEqualObjects([[self fixture:@"Trivia.AdiumScripts"] type], @"adiumscripts");
}

- (void)testPathIsWhereTheXtraWasFound
{
	XCTAssertEqualObjects([[self fixture:@"Birds.AdiumEmoticonset"] path], [self fixturePath:@"Birds.AdiumEmoticonset"]);
}

- (void)testXtraThatDoesNotExistIsNil
{
	XCTAssertNil([AIXtraInfo infoWithURL:[NSURL fileURLWithPath:[scratchDirectory stringByAppendingPathComponent:@"Nothing.AdiumEmoticonset"]]]);
}

- (void)testBundleIsTheXtrasOwn
{
	AIXtraInfo *info = [self fixture:@"Birds.AdiumEmoticonset"];

	XCTAssertEqualObjects([[info bundle] bundlePath], [self fixturePath:@"Birds.AdiumEmoticonset"]);
}

#pragma mark An Xtra with no manifest

- (void)testXtraWithoutManifestIsNamedAfterItsFolder
{
	AIXtraInfo *info = [self fixture:@"Birds.AdiumEmoticonset"];

	XCTAssertEqualObjects([info name], @"Birds");
	XCTAssertNil([info version]);
	XCTAssertNil([info author]);
	XCTAssertNil([info xtraDescription]);
}

- (void)testXtraWithoutManifestKeepsItsResourcesAtItsRoot
{
	XCTAssertEqualObjects([[self fixture:@"Birds.AdiumEmoticonset"] resourcePath], [self fixturePath:@"Birds.AdiumEmoticonset"]);
}

- (void)testXtraWithoutAnIconFileStillHasAnIcon
{
	XCTAssertNotNil([[self fixture:@"Birds.AdiumEmoticonset"] icon], @"The icon of its kind stands in");
}

#pragma mark A manifest kept at the root

- (void)testRootManifestSuppliesVersionAndAuthor
{
	AIXtraInfo *info = [self fixture:@"Trivia.AdiumScripts"];

	XCTAssertEqualObjects([info version], @"0.9");
	XCTAssertEqualObjects([info author], @"Robin Redbreast");
}

- (void)testScriptPackIsNamedAfterItsSet
{
	XCTAssertEqualObjects([[self fixture:@"Trivia.AdiumScripts"] name], @"Trivia Questions");
}

- (void)testRootManifestNameWinsOverTheFolderName
{
	AIXtraInfo *info = [self xtraNamed:@"folder.AdiumMessageStyle"
							  manifest:[NSDictionary dictionaryWithObject:@"Pretty Name" forKey:@"CFBundleName"]];

	XCTAssertEqualObjects([info name], @"Pretty Name");
}

- (void)testGetInfoStringThatSaysSomethingIsTheDescription
{
	XCTAssertEqualObjects([[self fixture:@"Trivia.AdiumScripts"] xtraDescription], @"Trivia Scripts");
}

- (void)testGetInfoStringThatOnlyRepeatsTheVersionIsNoDescription
{
	AIXtraInfo *info = [self xtraNamed:@"Mocked.AdiumMessageStyle"
							  manifest:[NSDictionary dictionaryWithObjectsAndKeys:
										@"2.0", @"CFBundleVersion",
										@"2.0", @"CFBundleGetInfoString",
										nil]];

	XCTAssertEqualObjects([info version], @"2.0", @"CFBundleVersion stands in where XtraVersion is missing");
	XCTAssertNil([info xtraDescription]);
}

- (void)testGetInfoStringThatOnlyRepeatsTheNameIsNoDescription
{
	AIXtraInfo *info = [self xtraNamed:@"Echo.AdiumMessageStyle"
							  manifest:[NSDictionary dictionaryWithObjectsAndKeys:
										@"Echo", @"CFBundleName",
										@"Echo", @"CFBundleGetInfoString",
										nil]];

	XCTAssertNil([info xtraDescription]);
}

- (void)testManifestValueThatIsNotAStringIsIgnored
{
	AIXtraInfo *info = [self xtraNamed:@"Numeric.AdiumMessageStyle"
							  manifest:[NSDictionary dictionaryWithObjectsAndKeys:
										[NSNumber numberWithInt:3], @"XtraVersion",
										[NSNumber numberWithInt:7], @"XtraAuthors",
										nil]];

	XCTAssertNil([info version]);
	XCTAssertNil([info author]);
}

#pragma mark A bundle with Contents/

- (void)testBundledXtraIsNamedFromItsManifest
{
	XCTAssertEqualObjects([[self fixture:@"Chirpy.AdiumSoundset"] name], @"Chirpy Sounds");
}

- (void)testBundledXtraKeepsItsResourcesUnderContents
{
	XCTAssertEqualObjects([[self fixture:@"Chirpy.AdiumSoundset"] resourcePath],
						  [[self fixturePath:@"Chirpy.AdiumSoundset"] stringByAppendingPathComponent:@"Contents/Resources"]);
}

- (void)testBundledXtraShowsItsOwnIconFile
{
	NSImage *icon = [[self fixture:@"Chirpy.AdiumSoundset"] icon];

	XCTAssertTrue([icon isValid], @"Icon.icns in Resources is the Xtra's icon");
}

- (void)testBundledXtraReadMeIsItsOwnFile
{
	XCTAssertEqualObjects([[self fixture:@"Chirpy.AdiumSoundset"] readMePath],
						  [[self fixturePath:@"Chirpy.AdiumSoundset"] stringByAppendingPathComponent:@"Contents/Resources/ReadMe.rtf"]);
}

- (void)testBundledXtraPreviewIsItsPreviewImage
{
	NSImage *preview = [[self fixture:@"Chirpy.AdiumSoundset"] previewImage];

	XCTAssertTrue([preview isValid]);
	XCTAssertTrue(NSEqualSizes([preview size], NSMakeSize(24, 24)), @"Got %@", NSStringFromSize([preview size]));
}

- (void)testXtraAuthorsNamesTheAuthor
{
	XCTAssertEqualObjects([[self fixture:@"Chirpy.AdiumSoundset"] author], @"Wren Wrenson");
}

- (void)testXtraDescriptionIsPreferredToEverythingElse
{
	/* The manifest also carries a GetInfoString and the Sounds.plist its own prose; neither is used */
	XCTAssertEqualObjects([[self fixture:@"Chirpy.AdiumSoundset"] xtraDescription], @"Short chirps for a quiet desk.");
}

#pragma mark What a sound set says about itself

- (void)testSoundSetAuthorIsTheCreatorLineOfItsProse
{
	XCTAssertEqualObjects([[self fixture:@"Birdsong.AdiumSoundset"] author], @"Jay Bird", @"Without the trailing full stop");
}

- (void)testSoundSetDescriptionIsItsProseWithoutTheCreatorLine
{
	XCTAssertEqualObjects([[self fixture:@"Birdsong.AdiumSoundset"] xtraDescription],
						  @"Bird calls for every event.\n\nhttp://example.invalid/birdsong");
}

- (void)testSoundSetProseThatNamesNoCreatorIsAllDescription
{
	NSString *path = [scratchDirectory stringByAppendingPathComponent:@"Quiet.AdiumSoundset"];
	NSDictionary *sounds = [NSDictionary dictionaryWithObjectsAndKeys:
							[NSNumber numberWithInt:1], @"AdiumSetVersion",
							@"No sounds.", @"Info",
							[NSDictionary dictionary], @"Sounds",
							nil];

	[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
	XCTAssertTrue([sounds writeToFile:[path stringByAppendingPathComponent:@"Sounds.plist"] atomically:YES]);
	AIXtraInfo *info = [AIXtraInfo infoWithURL:[NSURL fileURLWithPath:path]];

	XCTAssertNil([info author]);
	XCTAssertEqualObjects([info xtraDescription], @"No sounds.");
}

#pragma mark A dock icon's own list

- (void)testDockIconAuthorComesFromItsIconPackList
{
	NSString *path = [scratchDirectory stringByAppendingPathComponent:@"Finches.AdiumIcon"];
	NSDictionary *iconPack = [NSDictionary dictionaryWithObject:
							  [NSDictionary dictionaryWithObject:@"Created by Finch" forKey:@"Creator"]
													 forKey:@"Description"];

	[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
	XCTAssertTrue([iconPack writeToFile:[path stringByAppendingPathComponent:@"IconPack.plist"] atomically:YES]);

	XCTAssertEqualObjects([[AIXtraInfo infoWithURL:[NSURL fileURLWithPath:path]] author], @"Finch", @"Without the Created by the list writes in front");
}

#pragma mark State

- (void)testXtraIsEnabledUntilToldOtherwise
{
	AIXtraInfo *info = [self fixture:@"Birds.AdiumEmoticonset"];

	XCTAssertTrue([info enabled]);
	[info setEnabled:NO];
	XCTAssertFalse([info enabled]);
}

- (void)testXtraWithoutANameIsCalledUnnamed
{
	AIXtraInfo *info = [self fixture:@"Birds.AdiumEmoticonset"];

	[info setName:nil];

	XCTAssertEqualObjects([info name], @"Unnamed Xtra");
}

@end
