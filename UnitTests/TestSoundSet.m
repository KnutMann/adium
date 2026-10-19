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

#import <Adium/AISoundSet.h>

@interface TestSoundSet : XCTestCase {
	NSString	*scratchDirectory;
}
@end

@implementation TestSoundSet

- (void)setUp
{
	[super setUp];
	scratchDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
						[@"TestSoundSet-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
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

#pragma mark Sets to test with

- (NSString *)fixturePath:(NSString *)name
{
	return [[[NSBundle bundleForClass:[self class]] resourcePath]
			stringByAppendingPathComponent:[@"Fixtures" stringByAppendingPathComponent:name]];
}

- (AISoundSet *)birdsong
{
	return [AISoundSet soundSetWithContentsOfFile:[self fixturePath:@"Birdsong.AdiumSoundset"]];
}

- (NSString *)makeDirectory:(NSString *)name
{
	NSString *path = [scratchDirectory stringByAppendingPathComponent:name];
	[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
	return path;
}

/* A version 1 set written for one test: the Sounds.plist and nothing else, since the set only builds
 * paths and never opens a sound. Sets with a wrong version or no plist are not written here: both
 * put up a modal alert. */
- (NSString *)makeSetNamed:(NSString *)name sounds:(NSDictionary *)sounds locations:(NSArray *)locations
{
	NSString *setPath = [self makeDirectory:[name stringByAppendingPathExtension:@"AdiumSoundset"]];
	NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithObjectsAndKeys:
								  [NSNumber numberWithInt:1], @"AdiumSetVersion",
								  sounds, @"Sounds",
								  nil];
	if (locations) [plist setObject:locations forKey:@"Location"];
	XCTAssertTrue([plist writeToFile:[setPath stringByAppendingPathComponent:@"Sounds.plist"] atomically:YES]);
	return setPath;
}

- (void)touch:(NSString *)path
{
	XCTAssertTrue([[NSData data] writeToFile:path atomically:YES]);
}

#pragma mark Sets that cannot be read

- (void)testSetFromNoPathIsNil
{
	XCTAssertNil([AISoundSet soundSetWithContentsOfFile:nil]);
	XCTAssertNil([AISoundSet soundSetWithContentsOfFile:@""]);
}

- (void)testSetAtAPathThatDoesNotExistIsNil
{
	XCTAssertNil([AISoundSet soundSetWithContentsOfFile:[scratchDirectory stringByAppendingPathComponent:@"Silence.AdiumSoundset"]]);
}

#pragma mark A set kept flat, as every set Adium ships is

- (void)testFlatSetIsNamedAfterItsFolder
{
	XCTAssertEqualObjects([[self birdsong] name], @"Birdsong");
}

- (void)testInfoIsTheSetsOwnProse
{
	XCTAssertEqualObjects([[self birdsong] info],
						  @"Created by Jay Bird.\n\nBird calls for every event.\n\nhttp://example.invalid/birdsong\n");
}

- (void)testSoundsMapEventsToFullPathsInsideTheSet
{
	AISoundSet *set = [self birdsong];

	XCTAssertEqual([[set sounds] count], (NSUInteger)2);
	XCTAssertEqualObjects([[set sounds] objectForKey:@"Message Received"],
						  [[self fixturePath:@"Birdsong.AdiumSoundset"] stringByAppendingPathComponent:@"Chirp.aif"]);
}

- (void)testSoundWhoseFileIsMissingIsStillMappedToWhereItWouldBe
{
	/* With a single location there is nothing to choose between, so the set does not look */
	XCTAssertEqualObjects([[[self birdsong] sounds] objectForKey:@"Contact Signed On"],
						  [[self fixturePath:@"Birdsong.AdiumSoundset"] stringByAppendingPathComponent:@"Missing.aif"]);
}

- (void)testSetWithoutSoundsHasAnEmptyMap
{
	AISoundSet *set = [AISoundSet soundSetWithContentsOfFile:[self makeSetNamed:@"Mute" sounds:[NSDictionary dictionary] locations:nil]];

	XCTAssertNotNil(set);
	XCTAssertNotNil([set sounds]);
	XCTAssertEqual([[set sounds] count], (NSUInteger)0);
	XCTAssertNil([set info]);
}

#pragma mark A set that is a bundle with Contents/

- (void)testBundledSetTakesItsNameFromItsManifest
{
	XCTAssertEqualObjects([[AISoundSet soundSetWithContentsOfFile:[self fixturePath:@"Chirpy.AdiumSoundset"]] name], @"Chirpy Sounds");
}

- (void)testBundledSetFindsItsSoundsUnderResources
{
	AISoundSet *set = [AISoundSet soundSetWithContentsOfFile:[self fixturePath:@"Chirpy.AdiumSoundset"]];

	XCTAssertEqualObjects([[set sounds] objectForKey:@"Message Received"],
						  [[self fixturePath:@"Chirpy.AdiumSoundset"] stringByAppendingPathComponent:@"Contents/Resources/Chirp.aif"]);
	XCTAssertEqualObjects([set info], @"Created by Wren Wrenson\n\nShort chirps.\n");
}

#pragma mark Sounds kept somewhere else

- (void)testSoundIsTakenFromWhicheverLocationHoldsIt
{
	NSString *first = [self makeDirectory:@"First"];
	NSString *second = [self makeDirectory:@"Second"];
	[self touch:[first stringByAppendingPathComponent:@"Hello.aif"]];
	[self touch:[second stringByAppendingPathComponent:@"Goodbye.aif"]];

	NSString *setPath = [self makeSetNamed:@"Scattered"
									sounds:[NSDictionary dictionaryWithObjectsAndKeys:
											@"Hello.aif", @"Contact Signed On",
											@"Goodbye.aif", @"Contact Signed Off",
											nil]
								 locations:[NSArray arrayWithObjects:first, second, nil]];
	AISoundSet *set = [AISoundSet soundSetWithContentsOfFile:setPath];

	XCTAssertEqualObjects([[set sounds] objectForKey:@"Contact Signed On"], [first stringByAppendingPathComponent:@"Hello.aif"]);
	XCTAssertEqualObjects([[set sounds] objectForKey:@"Contact Signed Off"], [second stringByAppendingPathComponent:@"Goodbye.aif"]);
}

- (void)testSoundInNoLocationIsPlacedInTheFirstLocation
{

	NSString *first = [self makeDirectory:@"First"];
	NSString *second = [self makeDirectory:@"Second"];
	NSString *setPath = [self makeSetNamed:@"Lost"
									sounds:[NSDictionary dictionaryWithObject:@"Nowhere.aif" forKey:@"Message Sent"]
								 locations:[NSArray arrayWithObjects:first, second, nil]];
	AISoundSet *set = [AISoundSet soundSetWithContentsOfFile:setPath];

	XCTAssertEqualObjects([[set sounds] objectForKey:@"Message Sent"], [first stringByAppendingPathComponent:@"Nowhere.aif"]);
}

#pragma mark Identity

- (void)testSetsReadFromTheSamePathAreEqual
{
	AISoundSet *one = [self birdsong];
	AISoundSet *another = [self birdsong];

	XCTAssertEqualObjects(one, another);
	XCTAssertEqual([one hash], [another hash]);
}

- (void)testSetsReadFromDifferentPathsAreNotEqual
{
	XCTAssertNotEqualObjects([self birdsong], [AISoundSet soundSetWithContentsOfFile:[self fixturePath:@"Chirpy.AdiumSoundset"]]);
}

@end
