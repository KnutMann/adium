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

#import <Adium/AIEmoticon.h>
#import <Adium/AIEmoticonPack.h>

@interface TestEmoticonPack : XCTestCase {
	NSString	*scratchDirectory;
}
@end

@implementation TestEmoticonPack

- (void)setUp
{
	[super setUp];
	scratchDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
						[@"TestEmoticonPack-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
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

#pragma mark Packs to test with

- (NSString *)birdsPackPath
{
	return [[[NSBundle bundleForClass:[self class]] resourcePath]
			stringByAppendingPathComponent:@"Fixtures/Birds.AdiumEmoticonset"];
}

- (AIEmoticonPack *)birds
{
	return [AIEmoticonPack emoticonPackFromPath:[self birdsPackPath]];
}

- (AIEmoticon *)emoticonNamed:(NSString *)name inPack:(AIEmoticonPack *)pack
{
	for (AIEmoticon *emoticon in [pack emoticons]) {
		if ([[emoticon name] isEqualToString:name]) return emoticon;
	}
	return nil;
}

- (NSArray *)namesInPack:(AIEmoticonPack *)pack
{
	return [[pack emoticons] valueForKey:@"name"];
}

/* A pack written for one test, in a folder of its own: NSBundle remembers what it saw at a path for
 * the life of the process, so two packs must never share one. */
- (NSString *)makePackNamed:(NSString *)name plist:(NSDictionary *)plist images:(NSArray *)imageNames
{
	NSString *packPath = [scratchDirectory stringByAppendingPathComponent:
						  [[[NSUUID UUID] UUIDString] stringByAppendingPathComponent:
						   [name stringByAppendingPathExtension:@"AdiumEmoticonset"]]];
	NSFileManager *manager = [NSFileManager defaultManager];

	[manager createDirectoryAtPath:packPath withIntermediateDirectories:YES attributes:nil error:NULL];
	XCTAssertTrue([plist writeToFile:[packPath stringByAppendingPathComponent:@"Emoticons.plist"] atomically:YES]);
	for (NSString *imageName in imageNames) {
		XCTAssertTrue([manager copyItemAtPath:[[self birdsPackPath] stringByAppendingPathComponent:@"owl.png"]
									   toPath:[packPath stringByAppendingPathComponent:imageName]
										error:NULL]);
	}
	return packPath;
}

- (NSDictionary *)entryNamed:(NSString *)name equivalents:(NSArray *)equivalents
{
	return [NSDictionary dictionaryWithObjectsAndKeys:name, @"Name", equivalents, @"Equivalents", nil];
}

- (NSDictionary *)versionOnePlistWithEmoticons:(NSDictionary *)emoticons
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:1], @"AdiumSetVersion",
			emoticons, @"Emoticons",
			nil];
}

#pragma mark Reading a pack

- (void)testPackIsNamedAfterItsFolder
{
	AIEmoticonPack *pack = [self birds];

	XCTAssertEqualObjects([pack name], @"Birds");
	XCTAssertEqualObjects([pack path], [self birdsPackPath]);
}

- (void)testPackLoadsEveryEmoticonItDeclares
{
	NSSet *names = [NSSet setWithArray:[self namesInPack:[self birds]]];

	XCTAssertEqualObjects(names, ([NSSet setWithObjects:@"Albatross", @"Ghost", @"Hoot", @"owl", @"Quail", @"Raven", nil]));
}

- (void)testEmoticonsAreOrderedByNameIgnoringCase
{
	XCTAssertEqualObjects([self namesInPack:[self birds]],
						  ([NSArray arrayWithObjects:@"Albatross", @"Ghost", @"Hoot", @"owl", @"Quail", @"Raven", nil]),
						  @"A case-sensitive sort would put the lower case owl last");
}

- (void)testEmoticonKeepsAllItsEquivalentsInTheOrderWritten
{
	AIEmoticon *owl = [self emoticonNamed:@"owl" inPack:[self birds]];

	XCTAssertEqualObjects([owl textEquivalents], ([NSArray arrayWithObjects:@":))", @":-))", @"(owl)", nil]));
}

- (void)testEquivalentsThatExtendEachOtherStayWithTheirOwnEmoticons
{
	AIEmoticonPack *pack = [self birds];

	XCTAssertEqualObjects([[self emoticonNamed:@"Albatross" inPack:pack] textEquivalents], ([NSArray arrayWithObjects:@":)", @":-)", nil]));
	XCTAssertTrue([[[self emoticonNamed:@"owl" inPack:pack] textEquivalents] containsObject:@":))"]);
	XCTAssertFalse([[[self emoticonNamed:@"Albatross" inPack:pack] textEquivalents] containsObject:@":))"]);
}

- (void)testEquivalentsDifferingOnlyInCaseAreBothKept
{
	XCTAssertEqualObjects([[self emoticonNamed:@"Raven" inPack:[self birds]] textEquivalents],
						  ([NSArray arrayWithObjects:@":P", @":p", nil]));
}

- (void)testEquivalentsOutsideASCIISurviveLoading
{
	XCTAssertEqualObjects([[self emoticonNamed:@"Quail" inPack:[self birds]] textEquivalents],
						  ([NSArray arrayWithObjects:@"☺", @"♥", nil]));
}

- (void)testImageEmoticonPointsAtItsFileInsideThePack
{
	AIEmoticon *albatross = [self emoticonNamed:@"Albatross" inPack:[self birds]];

	XCTAssertEqualObjects([albatross path], [[self birdsPackPath] stringByAppendingPathComponent:@"albatross.png"]);
	XCTAssertTrue([albatross isDisplayable]);
}

- (void)testEmoticonWhoseImageFileIsMissingIsListedButNotDisplayable
{
	AIEmoticon *ghost = [self emoticonNamed:@"Ghost" inPack:[self birds]];

	XCTAssertNotNil(ghost, @"The definition is still part of the pack");
	XCTAssertNil([ghost path]);
	XCTAssertFalse([ghost isDisplayable]);
}

- (void)testCharacterKeyMakesACharacterEmoticon
{
	AIEmoticon *hoot = [self emoticonNamed:@"Hoot" inPack:[self birds]];

	XCTAssertEqualObjects([hoot character], @"\U0001F989");
	XCTAssertNil([hoot path]);
	XCTAssertTrue([hoot isDisplayable]);
	XCTAssertEqualObjects([hoot textEquivalents], [NSArray arrayWithObject:@"(hoot)"]);
}

- (void)testEmoticonNamesGoThroughTheFrameworkTranslationTable
{
	NSString *packPath = [self makePackNamed:@"Single"
									   plist:[self versionOnePlistWithEmoticons:
											  [NSDictionary dictionaryWithObject:[self entryNamed:@"Smile" equivalents:[NSArray arrayWithObject:@":)"]]
																		  forKey:@"owl.png"]]
									  images:[NSArray arrayWithObject:@"owl.png"]];
	AIEmoticonPack *pack = [AIEmoticonPack emoticonPackFromPath:packPath];
	NSString *translated = [[NSBundle bundleForClass:[AIEmoticonPack class]] localizedStringForKey:@"Smile"
																							 value:@"Smile"
																							 table:@"EmoticonNames"];

	XCTAssertEqual([[pack emoticons] count], (NSUInteger)1);
	XCTAssertEqualObjects([[[pack emoticons] objectAtIndex:0] name], translated);
}

- (void)testProteusPackIsReadWithItsOwnKeys
{
	NSDictionary *proteus = [NSDictionary dictionaryWithObject:
							 [NSDictionary dictionaryWithObjectsAndKeys:
							  [NSArray arrayWithObject:@"(owl)"], @"String Representations",
							  @"Owl", @"Meaning",
							  nil]
													 forKey:@"owl.png"];
	NSString *packPath = [self makePackNamed:@"Proteus" plist:proteus images:[NSArray arrayWithObject:@"owl.png"]];
	AIEmoticonPack *pack = [AIEmoticonPack emoticonPackFromPath:packPath];
	AIEmoticon *owl = [[pack emoticons] lastObject];

	XCTAssertEqual([[pack emoticons] count], (NSUInteger)1);
	XCTAssertEqualObjects([owl name], @"Owl");
	XCTAssertEqualObjects([owl textEquivalents], [NSArray arrayWithObject:@"(owl)"]);
	XCTAssertEqualObjects([owl path], [packPath stringByAppendingPathComponent:@"owl.png"]);
}

#pragma mark Where the images are

- (void)testImagesMayLiveInALocationOutsideThePack
{
	NSString *imagesDirectory = [scratchDirectory stringByAppendingPathComponent:@"Artwork"];
	NSFileManager *manager = [NSFileManager defaultManager];

	[manager createDirectoryAtPath:imagesDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
	[manager copyItemAtPath:[[self birdsPackPath] stringByAppendingPathComponent:@"owl.png"]
					 toPath:[imagesDirectory stringByAppendingPathComponent:@"owl.png"]
					  error:NULL];

	NSMutableDictionary *plist = [[self versionOnePlistWithEmoticons:
								   [NSDictionary dictionaryWithObject:[self entryNamed:@"Owl" equivalents:[NSArray arrayWithObject:@"(owl)"]]
															   forKey:@"owl.png"]] mutableCopy];
	[plist setObject:imagesDirectory forKey:@"Location"];
	NSString *packPath = [self makePackNamed:@"Elsewhere" plist:plist images:[NSArray array]];
	AIEmoticon *owl = [[[AIEmoticonPack emoticonPackFromPath:packPath] emoticons] lastObject];

	XCTAssertEqualObjects([owl path], [imagesDirectory stringByAppendingPathComponent:@"owl.png"]);
}

- (void)testLocationThatDoesNotExistFallsBackToThePackItself
{
	NSMutableDictionary *plist = [[self versionOnePlistWithEmoticons:
								   [NSDictionary dictionaryWithObject:[self entryNamed:@"Owl" equivalents:[NSArray arrayWithObject:@"(owl)"]]
															   forKey:@"owl.png"]] mutableCopy];
	[plist setObject:[NSArray arrayWithObject:[scratchDirectory stringByAppendingPathComponent:@"Nowhere"]] forKey:@"Location"];
	NSString *packPath = [self makePackNamed:@"Homebody" plist:plist images:[NSArray arrayWithObject:@"owl.png"]];
	AIEmoticon *owl = [[[AIEmoticonPack emoticonPackFromPath:packPath] emoticons] lastObject];

	XCTAssertEqualObjects([owl path], [packPath stringByAppendingPathComponent:@"owl.png"]);
}

#pragma mark Displayability

- (void)testPackWithAnyDisplayableEmoticonIsDisplayable
{
	XCTAssertTrue([[self birds] hasDisplayableEmoticons]);
}

- (void)testPackWhoseImagesAreAllMissingIsNotDisplayable
{
	NSString *packPath = [self makePackNamed:@"Gone"
									   plist:[self versionOnePlistWithEmoticons:
											  [NSDictionary dictionaryWithObjectsAndKeys:
											   [self entryNamed:@"Owl" equivalents:[NSArray arrayWithObject:@"(owl)"]], @"owl.png",
											   [self entryNamed:@"Raven" equivalents:[NSArray arrayWithObject:@"(raven)"]], @"raven.png",
											   nil]]
									  images:[NSArray array]];
	AIEmoticonPack *pack = [AIEmoticonPack emoticonPackFromPath:packPath];

	XCTAssertEqual([[pack emoticons] count], (NSUInteger)2, @"The definitions are read all the same");
	XCTAssertFalse([pack hasDisplayableEmoticons]);
}

#pragma mark Enabling and disabling

- (void)testDisablingNothingEnablesEveryEmoticon
{
	AIEmoticonPack *pack = [self birds];

	[pack setDisabledEmoticons:[NSArray array]];

	XCTAssertEqual([[pack enabledEmoticons] count], [[pack emoticons] count]);
	for (AIEmoticon *emoticon in [pack emoticons]) {
		XCTAssertTrue([emoticon isEnabled], @"%@", [emoticon name]);
	}
}

- (void)testDisablingByNameLeavesThatEmoticonOutOfTheEnabledOnes
{
	AIEmoticonPack *pack = [self birds];

	[pack setDisabledEmoticons:[NSArray arrayWithObject:@"owl"]];

	XCTAssertFalse([[self emoticonNamed:@"owl" inPack:pack] isEnabled]);
	XCTAssertEqual([[pack enabledEmoticons] count], [[pack emoticons] count] - 1);
	XCTAssertFalse([[[pack enabledEmoticons] valueForKey:@"name"] containsObject:@"owl"]);
	XCTAssertTrue([[[pack enabledEmoticons] valueForKey:@"name"] containsObject:@"Raven"]);
}

- (void)testEnabledEmoticonsFollowTheLatestDisabledList
{
	AIEmoticonPack *pack = [self birds];

	[pack setDisabledEmoticons:[NSArray arrayWithObject:@"owl"]];
	[pack setDisabledEmoticons:[NSArray arrayWithObject:@"Raven"]];

	XCTAssertTrue([[self emoticonNamed:@"owl" inPack:pack] isEnabled]);
	XCTAssertFalse([[self emoticonNamed:@"Raven" inPack:pack] isEnabled]);
	XCTAssertTrue([[[pack enabledEmoticons] valueForKey:@"name"] containsObject:@"owl"]);
	XCTAssertFalse([[[pack enabledEmoticons] valueForKey:@"name"] containsObject:@"Raven"]);
}

- (void)testDisablingANameThePackDoesNotHaveChangesNothing
{
	AIEmoticonPack *pack = [self birds];

	[pack setDisabledEmoticons:[NSArray arrayWithObject:@"Dodo"]];

	XCTAssertEqual([[pack enabledEmoticons] count], [[pack emoticons] count]);
}

- (void)testPackEnabledStateFollowsTheSetter
{
	AIEmoticonPack *pack = [self birds];

	[pack setIsEnabled:YES];
	XCTAssertTrue([pack isEnabled]);
	[pack setIsEnabled:NO];
	XCTAssertFalse([pack isEnabled]);
}

#pragma mark Service class

- (void)testPackNamingNoServiceClassSuitsEveryService
{
	AIEmoticonPack *pack = [self birds];

	XCTAssertNil([pack serviceClass]);
	XCTAssertTrue([[self emoticonNamed:@"owl" inPack:pack] isAppropriateForServiceClass:@"Jabber"]);
	XCTAssertTrue([[self emoticonNamed:@"owl" inPack:pack] isAppropriateForServiceClass:@"IRC"]);
}

- (void)testPackNamingAServiceClassSuitsOnlyThatService
{
	NSMutableDictionary *plist = [[self versionOnePlistWithEmoticons:
								   [NSDictionary dictionaryWithObject:[self entryNamed:@"Owl" equivalents:[NSArray arrayWithObject:@"(owl)"]]
															   forKey:@"owl.png"]] mutableCopy];
	[plist setObject:@"Jabber" forKey:@"Service Class"];
	NSString *packPath = [self makePackNamed:@"Jabbery" plist:plist images:[NSArray arrayWithObject:@"owl.png"]];
	AIEmoticonPack *pack = [AIEmoticonPack emoticonPackFromPath:packPath];
	AIEmoticon *owl = [[pack emoticons] lastObject];

	XCTAssertEqualObjects([pack serviceClass], @"Jabber");
	XCTAssertTrue([owl isAppropriateForServiceClass:@"Jabber"]);
	XCTAssertFalse([owl isAppropriateForServiceClass:@"IRC"]);
	XCTAssertFalse([owl isAppropriateForServiceClass:nil]);
}

#pragma mark Packs that are not quite right

- (void)testPackOfAVersionNobodyKnowsHasNoEmoticons
{
	NSString *packPath = [self makePackNamed:@"Future"
									   plist:[NSDictionary dictionaryWithObjectsAndKeys:
											  [NSNumber numberWithInt:7], @"AdiumSetVersion",
											  [NSDictionary dictionaryWithObject:[self entryNamed:@"Owl" equivalents:[NSArray arrayWithObject:@"(owl)"]]
																		  forKey:@"owl.png"], @"Emoticons",
											  nil]
									  images:[NSArray arrayWithObject:@"owl.png"]];
	AIEmoticonPack *pack = [AIEmoticonPack emoticonPackFromPath:packPath];

	XCTAssertNotNil([pack emoticons]);
	XCTAssertEqual([[pack emoticons] count], (NSUInteger)0);
	XCTAssertFalse([pack hasDisplayableEmoticons]);
}

- (void)testPackWithoutAnEmoticonsListHasNoEmoticons
{
	NSString *packPath = [self makePackNamed:@"Empty"
									   plist:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:1] forKey:@"AdiumSetVersion"]
									  images:[NSArray array]];
	AIEmoticonPack *pack = [AIEmoticonPack emoticonPackFromPath:packPath];

	XCTAssertNotNil([pack emoticons]);
	XCTAssertEqual([[pack emoticons] count], (NSUInteger)0);
	XCTAssertNil([pack menuPreviewImage]);
}

- (void)testEntriesThatAreNotDictionariesAreSkipped
{
	NSString *packPath = [self makePackNamed:@"Mixed"
									   plist:[self versionOnePlistWithEmoticons:
											  [NSDictionary dictionaryWithObjectsAndKeys:
											   @"not an emoticon", @"owl.png",
											   [self entryNamed:@"Raven" equivalents:[NSArray arrayWithObject:@"(raven)"]], @"raven.png",
											   nil]]
									  images:[NSArray arrayWithObjects:@"owl.png", @"raven.png", nil]];
	AIEmoticonPack *pack = [AIEmoticonPack emoticonPackFromPath:packPath];

	XCTAssertEqualObjects([self namesInPack:pack], [NSArray arrayWithObject:@"Raven"]);
}

- (void)testPackAtAPathThatDoesNotExistHasNoEmoticons
{
	NSString *packPath = [scratchDirectory stringByAppendingPathComponent:@"Phantom.AdiumEmoticonset"];
	AIEmoticonPack *pack = [AIEmoticonPack emoticonPackFromPath:packPath];

	XCTAssertEqualObjects([pack name], @"Phantom");
	XCTAssertNotNil([pack emoticons]);
	XCTAssertEqual([[pack emoticons] count], (NSUInteger)0);
	XCTAssertFalse([pack hasDisplayableEmoticons]);
}

#pragma mark Menu preview and copying

- (void)testMenuPreviewIsAMenuSizedImage
{
	NSImage *preview = [[self birds] menuPreviewImage];

	XCTAssertNotNil(preview);
	XCTAssertTrue(NSEqualSizes([preview size], NSMakeSize(16, 16)), @"Got %@", NSStringFromSize([preview size]));
}

- (void)testMenuPreviewPrefersTheSmileOverTheFirstEmoticon
{
	/* Aardvark sorts first and has no image; only the smile can produce a preview */
	NSString *packPath = [self makePackNamed:@"Smiles"
									   plist:[self versionOnePlistWithEmoticons:
											  [NSDictionary dictionaryWithObjectsAndKeys:
											   [self entryNamed:@"Aardvark" equivalents:[NSArray arrayWithObject:@"(aardvark)"]], @"aardvark.png",
											   [self entryNamed:@"Owl" equivalents:[NSArray arrayWithObject:@":)"]], @"owl.png",
											   nil]]
									  images:[NSArray arrayWithObject:@"owl.png"]];

	XCTAssertNotNil([[AIEmoticonPack emoticonPackFromPath:packPath] menuPreviewImage]);
}

- (void)testCopyKeepsNamePathAndEmoticons
{
	AIEmoticonPack *pack = [self birds];
	AIEmoticonPack *copy = [pack copy];

	XCTAssertEqualObjects([copy name], [pack name]);
	XCTAssertEqualObjects([copy path], [pack path]);
	XCTAssertEqualObjects([self namesInPack:copy], [self namesInPack:pack]);
}

@end
