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
#import <AIUtilities/AIBundleAdditions.h>

@interface TestBundleAdditions : XCTestCase
{
	NSString *workDirectory;
}
@end

@implementation TestBundleAdditions

- (void)setUp
{
	[super setUp];
	workDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"TestBundleAdditions-%@", [[NSUUID UUID] UUIDString]]];
	XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:workDirectory withIntermediateDirectories:YES attributes:nil error:NULL]);
}

- (void)tearDown
{
	[[NSFileManager defaultManager] removeItemAtPath:workDirectory error:NULL];
	workDirectory = nil;
	[super tearDown];
}

/* A bundle is a folder with Contents/Info.plist; NSBundle reads one anywhere, so the fixtures are
 * built on the spot with exactly the keys each test is about. */
- (NSBundle *)bundleNamed:(NSString *)name withInfo:(NSDictionary *)info
{
	NSString *path = [workDirectory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"bundle"]];
	NSString *contents = [path stringByAppendingPathComponent:@"Contents"];
	XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:contents withIntermediateDirectories:YES attributes:nil error:NULL]);
	XCTAssertTrue([info writeToFile:[contents stringByAppendingPathComponent:@"Info.plist"] atomically:YES]);
	NSBundle *bundle = [NSBundle bundleWithPath:path];
	XCTAssertNotNil(bundle);
	return bundle;
}

#pragma mark name

- (void)testNameIsTheBundleName
{
	NSBundle *bundle = [self bundleNamed:@"Named" withInfo:@{@"CFBundleIdentifier": @"com.example.named", @"CFBundleName": @"Pretty Name"}];
	XCTAssertEqualObjects([bundle name], @"Pretty Name");
}

- (void)testNameFallsBackToTheIdentifier
{
	NSBundle *bundle = [self bundleNamed:@"Unnamed" withInfo:@{@"CFBundleIdentifier": @"com.example.unnamed"}];
	XCTAssertEqualObjects([bundle name], @"com.example.unnamed");
}

#pragma mark supportedDocumentExtensions

- (void)testSupportedDocumentExtensionsUnionsEveryDocumentType
{
	NSBundle *bundle = [self bundleNamed:@"Docs" withInfo:@{
		@"CFBundleIdentifier": @"com.example.docs",
		@"CFBundleDocumentTypes": @[
			@{@"CFBundleTypeName": @"Text", @"CFBundleTypeExtensions": @[@"txt", @"text"]},
			@{@"CFBundleTypeName": @"Markdown", @"CFBundleTypeExtensions": @[@"md", @"txt"]},
		]}];
	NSSet *expected = [NSSet setWithObjects:@"txt", @"text", @"md", nil];
	XCTAssertEqualObjects([bundle supportedDocumentExtensions], expected);
}

- (void)testDocumentTypeWithoutExtensionsContributesNothing
{
	NSBundle *bundle = [self bundleNamed:@"UTIOnly" withInfo:@{
		@"CFBundleIdentifier": @"com.example.utionly",
		@"CFBundleDocumentTypes": @[
			@{@"CFBundleTypeName": @"Image", @"LSItemContentTypes": @[@"public.png"]},
			@{@"CFBundleTypeName": @"Text", @"CFBundleTypeExtensions": @[@"txt"]},
		]}];
	XCTAssertEqualObjects([bundle supportedDocumentExtensions], [NSSet setWithObject:@"txt"]);
}

- (void)testBundleWithoutDocumentTypesSupportsNoExtensions
{
	NSBundle *bundle = [self bundleNamed:@"NoDocs" withInfo:@{@"CFBundleIdentifier": @"com.example.nodocs"}];
	XCTAssertEqualObjects([bundle supportedDocumentExtensions], [NSSet set]);
}

#pragma mark Nibs

- (void)testLoadingAMissingNibFromABundleIsNil
{
	NSBundle *bundle = [self bundleNamed:@"Empty" withInfo:@{@"CFBundleIdentifier": @"com.example.empty"}];
	XCTAssertNil([bundle ai_loadNibNamed:@"NoSuchNib" owner:self]);
}

- (void)testLoadingAMissingNibForAnOwnerIsNil
{
	XCTAssertNil([NSBundle ai_loadNibNamed:@"NoSuchNib" owner:self]);
}

@end
