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
#import <Adium/AIListBookmark.h>

/* A bookmark without an account: its names, grouping and chat all go through controllers that do
 * not exist under the test runner, so only what it stores for itself is reachable here. */
static AIListBookmark *TLBBookmark(NSString *name, NSDictionary *dictionary)
{
	return [[AIListBookmark alloc] initWithUID:[@"Bookmark:" stringByAppendingString:name]
									   account:nil
									   service:nil
									dictionary:dictionary
										  name:name];
}

@interface TestListBookmark : XCTestCase
@end

@implementation TestListBookmark

- (void)testBookmarkKeepsItsName
{
	AIListBookmark *bookmark = TLBBookmark(@"adium@conference.example.org", nil);
	XCTAssertEqualObjects(bookmark.name, @"adium@conference.example.org");
	XCTAssertEqualObjects(bookmark.UID, @"Bookmark:adium@conference.example.org");
}

- (void)testBookmarkCopiesTheChatCreationDictionary
{
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithObject:@"adium" forKey:@"room"];
	AIListBookmark *bookmark = TLBBookmark(@"adium@conference.example.org", dictionary);
	[dictionary setObject:@"other" forKey:@"room"];
	XCTAssertEqualObjects(bookmark.chatCreationDictionary, @{ @"room": @"adium" });
}

- (void)testBookmarkWithoutADictionaryHasNone
{
	XCTAssertNil(TLBBookmark(@"adium@conference.example.org", nil).chatCreationDictionary);
}

- (void)testBookmarkPasswordRoundTrips
{
	AIListBookmark *bookmark = TLBBookmark(@"adium@conference.example.org", nil);
	XCTAssertNil(bookmark.password);
	bookmark.password = @"secret";
	XCTAssertEqualObjects(bookmark.password, @"secret");
}

- (void)testBookmarkDoesNotExistServerside
{
	XCTAssertFalse(TLBBookmark(@"adium@conference.example.org", nil).existsServerside);
}

- (void)testLogDescriptionKeepsOnlyTheTailOfTheRoom
{
	AIListBookmark *bookmark = TLBBookmark(@"4912345678-1600000000@g.us", nil);
	NSString *description = bookmark.logDescription;
	XCTAssertTrue([description containsString:@"0000@g.us"], @"enough to tell two rooms apart: %@", description);
	XCTAssertFalse([description containsString:@"4912345678"], @"the phone number is gone: %@", description);
	XCTAssertFalse([description containsString:@"1600000000"], @"and so is the rest of the local part: %@", description);
}

- (void)testLogDescriptionLeavesAShortRoomNameWhole
{
	AIListBookmark *bookmark = TLBBookmark(@"dev@c.example", nil);
	XCTAssertTrue([bookmark.logDescription containsString:@"dev@c.example"]);
}

@end
