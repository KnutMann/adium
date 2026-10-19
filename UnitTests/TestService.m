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
#import <Adium/AIService.h>

/* A service that allows letters and spaces and ignores the spaces, the way AIM treated "ad am"
 * as "adam": an ignored character has to be an allowed one, or it is dropped as invalid first. */
@interface TSvcLetterService : AIService
@end

@implementation TSvcLetterService
- (NSCharacterSet *)allowedCharacters
{
	NSMutableCharacterSet *letters = [[NSCharacterSet letterCharacterSet] mutableCopy];
	[letters formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
	return letters;
}
- (NSCharacterSet *)ignoredCharacters { return [NSCharacterSet whitespaceCharacterSet]; }
@end

@interface TSvcCaseSensitiveService : AIService
@end

@implementation TSvcCaseSensitiveService
- (BOOL)caseSensitive { return YES; }
@end

@interface TSvcPasswordlessService : AIService
@end

@implementation TSvcPasswordlessService
- (BOOL)supportsPassword { return NO; }
@end

@interface TSvcPasswordService : AIService
@end

@implementation TSvcPasswordService
- (BOOL)supportsPassword { return YES; }
@end

@interface TestService : XCTestCase
@end

@implementation TestService

#pragma mark Description

- (void)testBaseServiceDescribesItselfAsNothing
{
	AIService *service = [[AIService alloc] init];
	XCTAssertEqualObjects(service.serviceCodeUniqueID, @"");
	XCTAssertEqualObjects(service.serviceID, @"");
	XCTAssertEqualObjects(service.serviceClass, @"");
	XCTAssertEqualObjects(service.shortDescription, @"");
	XCTAssertEqualObjects(service.longDescription, @"");
	XCTAssertEqualObjects(service.UIDPlaceholder, @"");
	XCTAssertEqualObjects(service.defaultUserName, @"");
}

- (void)testContactUserNameLabelFallsBackToTheUserNameLabel
{
	AIService *service = [[AIService alloc] init];
	XCTAssertTrue(service.userNameLabel.length > 0);
	XCTAssertEqualObjects(service.contactUserNameLabel, service.userNameLabel);
}

- (void)testBaseServiceSupportsNoExtras
{
	AIService *service = [[AIService alloc] init];
	XCTAssertEqual(service.serviceImportance, AIServiceUnsupported);
	XCTAssertFalse(service.caseSensitive);
	XCTAssertFalse(service.canCreateGroupChats);
	XCTAssertFalse(service.canRegisterNewAccounts);
	XCTAssertFalse(service.isHidden);
	XCTAssertFalse(service.isSocialNetworkingService);
	XCTAssertFalse(service.userNamesArePhoneNumbers);
	XCTAssertFalse(service.userNamesAreEmailAddresses);
	XCTAssertNil(service.accountClass);
	XCTAssertNil(service.joinChatView);
	XCTAssertNil([service defaultServiceIconOfType:AIServiceIconLarge]);
	XCTAssertNil([service pathForDefaultServiceIconOfType:AIServiceIconLarge]);
}

#pragma mark Passwords

- (void)testServiceSupportsAPasswordByDefault
{
	AIService *service = [[AIService alloc] init];
	XCTAssertTrue(service.supportsPassword);
	XCTAssertTrue(service.requiresPassword);
}

- (void)testRequiresPasswordFollowsSupportsPassword
{
	XCTAssertTrue([[TSvcPasswordService alloc] init].requiresPassword);
	XCTAssertFalse([[TSvcPasswordlessService alloc] init].requiresPassword);
}

#pragma mark Characters and lengths

- (void)testBaseServiceAllowsEverythingButIllegalCharacters
{
	AIService *service = [[AIService alloc] init];
	XCTAssertTrue([service.allowedCharacters characterIsMember:'a']);
	XCTAssertTrue([service.allowedCharacters characterIsMember:0x00FC], @"non-ASCII letters are fine");
	XCTAssertFalse([service.allowedCharacters characterIsMember:0xFFFE], @"a non-character is not");
	XCTAssertNil(service.ignoredCharacters);
	XCTAssertEqual(service.allowedLength, NSUIntegerMax);
}

- (void)testCharacterAndLengthLimitsFallThroughToTheGeneralOnes
{
	TSvcLetterService *service = [[TSvcLetterService alloc] init];
	XCTAssertEqualObjects(service.allowedCharactersForUIDs, service.allowedCharacters);
	XCTAssertEqualObjects(service.allowedCharactersForAccountName, service.allowedCharacters);
	XCTAssertEqual(service.allowedLengthForUIDs, service.allowedLength);
	XCTAssertEqual(service.allowedLengthForAccountName, service.allowedLength);
}

#pragma mark Normalising

- (void)testNormalizeUIDLowercasesForACaseInsensitiveService
{
	AIService *service = [[AIService alloc] init];
	XCTAssertEqualObjects([service normalizeUID:@"AdAm" removeIgnoredCharacters:YES], @"adam");
}

- (void)testNormalizeUIDKeepsCaseForACaseSensitiveService
{
	TSvcCaseSensitiveService *service = [[TSvcCaseSensitiveService alloc] init];
	XCTAssertEqualObjects([service normalizeUID:@"AdAm" removeIgnoredCharacters:YES], @"AdAm");
}

- (void)testNormalizeUIDDropsCharactersTheServiceDoesNotAllow
{
	TSvcLetterService *letters = [[TSvcLetterService alloc] init];
	XCTAssertEqualObjects([letters normalizeUID:@"ad4am!" removeIgnoredCharacters:YES], @"adam");

	AIService *service = [[AIService alloc] init];
	XCTAssertEqualObjects([service normalizeUID:@"ad￾am" removeIgnoredCharacters:YES], @"adam");
}

- (void)testNormalizeUIDRemovesIgnoredCharactersOnlyWhenAsked
{
	TSvcLetterService *service = [[TSvcLetterService alloc] init];
	XCTAssertEqualObjects([service normalizeUID:@"ad am" removeIgnoredCharacters:YES], @"adam");

	NSString *kept = [service normalizeUID:@"ad am" removeIgnoredCharacters:NO];
	XCTAssertEqualObjects([kept lowercaseString], @"ad am", @"the ignored character stays when not asked to remove it");
}

- (void)testNormalizeUIDLeavesAnEmptyStringEmpty
{
	XCTAssertEqualObjects([[[AIService alloc] init] normalizeUID:@"" removeIgnoredCharacters:YES], @"");
	XCTAssertEqualObjects([[[TSvcLetterService alloc] init] normalizeUID:@" " removeIgnoredCharacters:YES], @"");
}

- (void)testNormalizeChatNameLowercases
{
	XCTAssertEqualObjects([[[AIService alloc] init] normalizeChatName:@"Adium@Conference"], @"adium@conference");
}

@end
