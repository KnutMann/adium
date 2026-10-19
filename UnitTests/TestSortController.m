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
#import <Adium/AISortController.h>
#import <Adium/AIListObject.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListGroup.h>

static id<AIContainingObject> TSCLastContainer;

static NSComparisonResult TSCAlphabeticalSort(id objectA, id objectB, BOOL groups, id<AIContainingObject> container)
{
	TSCLastContainer = container;
	return [[objectA UID] compare:[objectB UID]];
}

/* The base class sorts with no function at all; the smallest real controller orders by UID. */
@interface TSCAlphabeticalSortController : AISortController
@property (nonatomic, readonly) NSUInteger firstTimeCount;
@end

@implementation TSCAlphabeticalSortController
- (sortfunc)sortFunction { return TSCAlphabeticalSort; }
- (NSSet *)statusKeysRequiringResort { return [NSSet setWithObject:@"isOnline"]; }
- (NSSet *)attributeKeysRequiringResort { return [NSSet setWithObject:@"Display Name"]; }
- (NSString *)configureSortWindowTitle { return @"Sort Alphabetically"; }
- (void)didBecomeActiveFirstTime { _firstTimeCount++; }
@end

static AIListContact *TSCContact(NSString *UID)
{
	return [[AIListContact alloc] initWithUID:UID account:nil service:nil];
}

@interface TestSortController : XCTestCase
@end

@implementation TestSortController

- (void)tearDown
{
	TSCLastContainer = nil;
	[super tearDown];
}

#pragma mark What a controller declares

- (void)testBaseControllerDeclaresNothing
{
	AISortController *controller = [[AISortController alloc] init];
	XCTAssertNil(controller.identifier);
	XCTAssertNil(controller.displayName);
	XCTAssertNil(controller.statusKeysRequiringResort);
	XCTAssertNil(controller.attributeKeysRequiringResort);
	XCTAssertTrue(controller.sortFunction == NULL);
	XCTAssertNil(controller.configureSortWindowTitle);
	XCTAssertNil(controller.configureSortMenuItemTitle);
	XCTAssertNil(controller.configureNibName);
}

- (void)testShouldSortForStatusKeysWhenTheyIntersect
{
	TSCAlphabeticalSortController *controller = [[TSCAlphabeticalSortController alloc] init];
	XCTAssertTrue([controller shouldSortForModifiedStatusKeys:([NSSet setWithObjects:@"isOnline", @"idle", nil])]);
	XCTAssertFalse([controller shouldSortForModifiedStatusKeys:[NSSet setWithObject:@"idle"]]);
	XCTAssertFalse([controller shouldSortForModifiedStatusKeys:[NSSet set]]);

	AISortController *base = [[AISortController alloc] init];
	XCTAssertFalse([base shouldSortForModifiedStatusKeys:[NSSet setWithObject:@"isOnline"]], @"a controller that names no keys never asks for a resort");
}

- (void)testShouldSortForAttributeKeysWhenTheyIntersect
{
	TSCAlphabeticalSortController *controller = [[TSCAlphabeticalSortController alloc] init];
	XCTAssertTrue([controller shouldSortForModifiedAttributeKeys:[NSSet setWithObject:@"Display Name"]]);
	XCTAssertFalse([controller shouldSortForModifiedAttributeKeys:[NSSet setWithObject:@"Text Color"]]);

	AISortController *base = [[AISortController alloc] init];
	XCTAssertFalse([base shouldSortForModifiedAttributeKeys:[NSSet setWithObject:@"Display Name"]]);
}

- (void)testGroupsSortToTopByDefaultAndManualSortingIsOff
{
	AISortController *controller = [[AISortController alloc] init];
	XCTAssertTrue(controller.alwaysSortGroupsToTopByDefault);
	XCTAssertFalse(controller.canSortManually);
}

- (void)testConfigureMenuItemTitleIsTheWindowTitleWithAnEllipsis
{
	TSCAlphabeticalSortController *controller = [[TSCAlphabeticalSortController alloc] init];
	NSString *title = controller.configureSortMenuItemTitle;
	XCTAssertTrue([title hasPrefix:@"Sort Alphabetically"]);
	XCTAssertEqual([title characterAtIndex:title.length - 1], (unichar)0x2026);
}

- (void)testDidBecomeActiveFirstTimeHappensOnce
{
	TSCAlphabeticalSortController *controller = [[TSCAlphabeticalSortController alloc] init];
	[controller didBecomeActive];
	[controller didBecomeActive];
	XCTAssertEqual(controller.firstTimeCount, (NSUInteger)1);
}

- (void)testRegisteredControllersAreAvailable
{
	TSCAlphabeticalSortController *controller = [[TSCAlphabeticalSortController alloc] init];
	[AISortController registerSortController:controller];
	XCTAssertTrue([[AISortController availableSortControllers] containsObject:controller]);
}

#pragma mark Where an object goes

- (void)testIndexForInsertingIntoAnEmptyArrayIsZero
{
	TSCAlphabeticalSortController *controller = [[TSCAlphabeticalSortController alloc] init];
	XCTAssertEqual([controller indexForInserting:TSCContact(@"m") intoObjects:@[] inContainer:nil], 0);
}

- (void)testIndexForInsertingFollowsTheSortFunction
{
	TSCAlphabeticalSortController *controller = [[TSCAlphabeticalSortController alloc] init];
	NSArray *objects = @[TSCContact(@"b"), TSCContact(@"d")];
	XCTAssertEqual([controller indexForInserting:TSCContact(@"a") intoObjects:objects inContainer:nil], 0);
	XCTAssertEqual([controller indexForInserting:TSCContact(@"c") intoObjects:objects inContainer:nil], 1);
	XCTAssertEqual([controller indexForInserting:TSCContact(@"e") intoObjects:objects inContainer:nil], 2);
}

- (void)testIndexForInsertingPutsAGroupBeforeContacts
{
	TSCAlphabeticalSortController *controller = [[TSCAlphabeticalSortController alloc] init];
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"zzz"];
	NSArray *contacts = @[TSCContact(@"a"), TSCContact(@"c")];
	XCTAssertEqual([controller indexForInserting:group intoObjects:contacts inContainer:nil], 0, @"a group goes above every contact whatever its name");

	NSArray *mixed = @[group, TSCContact(@"c")];
	XCTAssertEqual([controller indexForInserting:TSCContact(@"a") intoObjects:mixed inContainer:nil], 1, @"a contact goes below every group whatever its name");
}

- (void)testForcingIgnoringOfGroupsSortsThemAlongsideContacts
{
	TSCAlphabeticalSortController *controller = [[TSCAlphabeticalSortController alloc] init];
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"m"];
	NSArray *contacts = @[TSCContact(@"a"), TSCContact(@"z")];

	[controller forceIgnoringOfGroups:YES];
	XCTAssertEqual([controller indexForInserting:group intoObjects:contacts inContainer:nil], 1);

	[controller forceIgnoringOfGroups:NO];
	XCTAssertEqual([controller indexForInserting:group intoObjects:contacts inContainer:nil], 0, @"the default behaviour returns");
}

- (void)testSortFunctionReceivesTheContainer
{
	TSCAlphabeticalSortController *controller = [[TSCAlphabeticalSortController alloc] init];
	AIListGroup *container = [[AIListGroup alloc] initWithUID:@"Friends"];
	[controller indexForInserting:TSCContact(@"b") intoObjects:@[TSCContact(@"a")] inContainer:container];
	XCTAssertTrue(TSCLastContainer == container);
}

@end
