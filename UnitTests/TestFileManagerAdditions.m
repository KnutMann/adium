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
#import <AIUtilities/AIFileManagerAdditions.h>

@interface TestFileManagerAdditions : XCTestCase
{
	NSFileManager *fileManager;
	NSString *workDirectory;
}
@end

@implementation TestFileManagerAdditions

- (void)setUp
{
	[super setUp];
	fileManager = [NSFileManager defaultManager];
	workDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"TestFileManagerAdditions-%@", [[NSUUID UUID] UUIDString]]];
	XCTAssertTrue([fileManager createDirectoryAtPath:workDirectory withIntermediateDirectories:YES attributes:nil error:NULL]);
}

- (void)tearDown
{
	[fileManager removeItemAtPath:workDirectory error:NULL];
	workDirectory = nil;
	[super tearDown];
}

- (NSString *)makeFile:(NSString *)name
{
	NSString *path = [workDirectory stringByAppendingPathComponent:name];
	XCTAssertTrue([@"content" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
	return path;
}

- (NSString *)makeDirectory:(NSString *)name
{
	NSString *path = [workDirectory stringByAppendingPathComponent:name];
	XCTAssertTrue([fileManager createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:NULL]);
	return path;
}

- (NSString *)missingPath
{
	return [workDirectory stringByAppendingPathComponent:@"missing"];
}

- (NSSet *)namesInWorkDirectory
{
	return [NSSet setWithArray:[fileManager contentsOfDirectoryAtPath:workDirectory error:NULL]];
}

#pragma mark pathIf…

- (void)testPathIfExistsReturnsAnExistingFile
{
	NSString *file = [self makeFile:@"file"];
	XCTAssertEqualObjects([fileManager pathIfExists:file], file);
}

- (void)testPathIfExistsReturnsAnExistingDirectory
{
	NSString *directory = [self makeDirectory:@"dir"];
	XCTAssertEqualObjects([fileManager pathIfExists:directory], directory);
}

- (void)testPathIfExistsOfMissingPathIsNil
{
	XCTAssertNil([fileManager pathIfExists:[self missingPath]]);
}

- (void)testPathIfDirectoryReturnsADirectory
{
	NSString *directory = [self makeDirectory:@"dir"];
	XCTAssertEqualObjects([fileManager pathIfDirectory:directory], directory);
}

- (void)testPathIfDirectoryOfAFileIsNil
{
	XCTAssertNil([fileManager pathIfDirectory:[self makeFile:@"file"]]);
}

- (void)testPathIfDirectoryOfMissingPathIsNil
{
	XCTAssertNil([fileManager pathIfDirectory:[self missingPath]]);
}

- (void)testPathIfNotDirectoryReturnsAFile
{
	NSString *file = [self makeFile:@"file"];
	XCTAssertEqualObjects([fileManager pathIfNotDirectory:file], file);
}

- (void)testPathIfNotDirectoryOfADirectoryIsNil
{
	XCTAssertNil([fileManager pathIfNotDirectory:[self makeDirectory:@"dir"]]);
}

- (void)testPathIfNotDirectoryOfMissingPathIsNil
{
	XCTAssertNil([fileManager pathIfNotDirectory:[self missingPath]]);
}

#pragma mark uniquePathForPath:

- (void)testUniquePathForAFreePathIsThatPath
{
	NSString *path = [workDirectory stringByAppendingPathComponent:@"new.txt"];
	XCTAssertEqualObjects([fileManager uniquePathForPath:path], path);
}

- (void)testUniquePathForATakenPathAppendsOneBeforeTheExtension
{
	NSString *taken = [self makeFile:@"photo.jpg"];
	XCTAssertEqualObjects([fileManager uniquePathForPath:taken], [workDirectory stringByAppendingPathComponent:@"photo-1.jpg"]);
}

- (void)testUniquePathCountsPastTakenNumbers
{
	NSString *taken = [self makeFile:@"photo.jpg"];
	[self makeFile:@"photo-1.jpg"];
	[self makeFile:@"photo-2.jpg"];
	XCTAssertEqualObjects([fileManager uniquePathForPath:taken], [workDirectory stringByAppendingPathComponent:@"photo-3.jpg"]);
}

- (void)testUniquePathWithoutExtensionAppendsTheNumberAtTheEnd
{
	NSString *taken = [self makeFile:@"notes"];
	XCTAssertEqualObjects([fileManager uniquePathForPath:taken], [workDirectory stringByAppendingPathComponent:@"notes-1"]);
}

- (void)testUniquePathForATakenDirectory
{
	NSString *taken = [self makeDirectory:@"folder"];
	XCTAssertEqualObjects([fileManager uniquePathForPath:taken], [workDirectory stringByAppendingPathComponent:@"folder-1"]);
}

- (void)testUniquePathDoesNotCreateAnything
{
	NSString *taken = [self makeFile:@"photo.jpg"];
	NSString *unique = [fileManager uniquePathForPath:taken];
	XCTAssertFalse([fileManager fileExistsAtPath:unique]);
}

#pragma mark Well known folders

- (void)testFindFolderOfTypeAnswersTheApplicationSupportFolder
{
	NSString *folder = [fileManager findFolderOfType:NSApplicationSupportDirectory inDomain:NSUserDomainMask createFolder:NO];
	XCTAssertEqualObjects([folder lastPathComponent], @"Application Support");
}

#pragma mark Aliases

- (void)testResolvingANilPathIsNil
{
	XCTAssertNil([fileManager pathByResolvingAlias:nil]);
}

- (void)testResolvingARegularFileReturnsItsOwnPath
{
	NSString *file = [self makeFile:@"plain.txt"];
	XCTAssertEqualObjects([fileManager pathByResolvingAlias:file], file);
}

- (void)testResolvingAMissingPathReturnsIt
{
	XCTAssertEqualObjects([fileManager pathByResolvingAlias:[self missingPath]], [self missingPath]);
}

- (void)testResolvingAnAliasFileReturnsTheOriginal
{
	NSURL *original = [NSURL fileURLWithPath:[self makeFile:@"original.txt"]];
	NSError *error = nil;
	NSData *bookmark = [original bookmarkDataWithOptions:NSURLBookmarkCreationSuitableForBookmarkFile includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
	XCTAssertNotNil(bookmark, @"%@", error);
	NSString *aliasPath = [workDirectory stringByAppendingPathComponent:@"original alias"];
	XCTAssertTrue([NSURL writeBookmarkData:bookmark toURL:[NSURL fileURLWithPath:aliasPath] options:NSURLBookmarkCreationSuitableForBookmarkFile error:&error], @"%@", error);

	NSString *resolved = [fileManager pathByResolvingAlias:aliasPath];
	//The temporary directory is reached through a symbolic link, and a resolved alias may come back canonical.
	XCTAssertEqualObjects([resolved stringByResolvingSymlinksInPath], [[original path] stringByResolvingSymlinksInPath]);
}

/* Foundation counts a symbolic link as an alias file (NSURLIsAliasFileKey says so), so the method
 * follows one the same way it follows a Finder alias. */
- (void)testResolvingASymbolicLinkFollowsIt
{
	NSString *file = [self makeFile:@"target.txt"];
	NSString *link = [workDirectory stringByAppendingPathComponent:@"link.txt"];
	XCTAssertTrue([fileManager createSymbolicLinkAtPath:link withDestinationPath:file error:NULL]);
	XCTAssertEqualObjects([[fileManager pathByResolvingAlias:link] stringByResolvingSymlinksInPath], [file stringByResolvingSymlinksInPath]);
}

#pragma mark Removing by prefix

- (void)testRemovingByPrefixRemovesOnlyMatchingFiles
{
	[self makeFile:@"log-1"];
	[self makeFile:@"log-2"];
	[self makeFile:@"keep-1"];
	[fileManager removeFilesInDirectory:workDirectory withPrefix:@"log-" movingToTrash:NO];
	XCTAssertEqualObjects([self namesInWorkDirectory], [NSSet setWithObject:@"keep-1"]);
}

- (void)testRemovingByPrefixIsCaseSensitive
{
	[self makeFile:@"Log-1"];
	[self makeFile:@"log-2"];
	[fileManager removeFilesInDirectory:workDirectory withPrefix:@"log" movingToTrash:NO];
	XCTAssertEqualObjects([self namesInWorkDirectory], [NSSet setWithObject:@"Log-1"]);
}

- (void)testRemovingWithNilPrefixRemovesEverything
{
	XCTExpectFailure(@"AIFileManagerAdditions.m:49 stands in an empty string for a nil prefix so that every name matches, but -[NSString hasPrefix:] answers NO for an empty prefix, so nothing is removed");
	[self makeFile:@"a"];
	[self makeFile:@"b"];
	[fileManager removeFilesInDirectory:workDirectory withPrefix:nil movingToTrash:NO];
	XCTAssertEqualObjects([self namesInWorkDirectory], [NSSet set]);
	XCTAssertTrue([fileManager fileExistsAtPath:workDirectory], @"The directory itself stays");
}

- (void)testRemovingByPrefixMatchesTheWholePrefix
{
	[self makeFile:@"lo"];
	[self makeFile:@"log"];
	[fileManager removeFilesInDirectory:workDirectory withPrefix:@"log" movingToTrash:NO];
	XCTAssertEqualObjects([self namesInWorkDirectory], [NSSet setWithObject:@"lo"]);
}

- (void)testRemovingByPrefixInAMissingDirectoryDoesNothing
{
	[fileManager removeFilesInDirectory:[self missingPath] withPrefix:@"x" movingToTrash:NO];
}

#pragma mark Trash

- (void)testTrashingAMissingPathCountsAsSuccess
{
	XCTExpectFailure(@"AIFileManagerAdditions.h says YES when the file already does not exist; AIFileManagerAdditions.m:29 starts from NO and only the existing-file branch changes it");
	XCTAssertTrue([fileManager trashFileAtPath:[self missingPath]]);
}

@end
