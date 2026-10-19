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
#import "TestDictionaryAdditions.h"

#import <AIUtilities/AIDictionaryAdditions.h>

@interface TestDictionaryAdditions ()
{
	NSString *workDirectory;
}
@end

@implementation TestDictionaryAdditions

- (NSMutableDictionary *)startingDictionary {
	return [NSMutableDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:0U], @"Foo",
		[NSNumber numberWithUnsignedInteger:1U], @"Bar",
		[NSNumber numberWithUnsignedInteger:2U], @"Baz",
		nil];
}
- (NSDictionary *)translation {
	return [NSDictionary dictionaryWithObjectsAndKeys:
		@"Green", @"Foo",
		@"Red",   @"Bar",
		@"Blue",  @"Baz",
		nil];
}
- (NSDictionary *)addition {
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:3U], @"Qux",
		[NSNumber numberWithUnsignedInteger:4U], @"Quux",
		[NSNumber numberWithUnsignedInteger:5U], @"Quuux",
		nil];
}
- (NSSet *)deletia {
	return [NSSet setWithObjects:
		@"Foo",
		@"Bar",
		@"Baz",
		nil];
}

#pragma mark Test case methods

- (void)testTranslateAddRemove_translate {
	NSMutableDictionary *dict = [self startingDictionary];
	NSDictionary *translation = [self translation];

	[dict translate:translation
				add:nil
			 remove:nil];

	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Foo"]], @"translate:add:remove: method failed to translate %@ to %@", @"Foo", [translation objectForKey:@"Foo"]);
	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Bar"]], @"translate:add:remove: method failed to translate %@ to %@", @"Bar", [translation objectForKey:@"Bar"]);
	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Baz"]], @"translate:add:remove: method failed to translate %@ to %@", @"Baz", [translation objectForKey:@"Baz"]);
}

- (void)testTranslateAddRemove_add {
	NSMutableDictionary *dict = [self startingDictionary];

	[dict translate:nil
				add:[self addition]
			 remove:nil];

	XCTAssertNotNil([dict objectForKey:@"Foo"],   @"translate:add:remove: method failed to keep %@", @"Foo");
	XCTAssertNotNil([dict objectForKey:@"Bar"],   @"translate:add:remove: method failed to keep %@", @"Bar");
	XCTAssertNotNil([dict objectForKey:@"Baz"],   @"translate:add:remove: method failed to keep %@", @"Baz");
	XCTAssertNotNil([dict objectForKey:@"Qux"],   @"translate:add:remove: method failed to add %@", @"Qux");
	XCTAssertNotNil([dict objectForKey:@"Quux"],  @"translate:add:remove: method failed to add %@", @"Quux");
	XCTAssertNotNil([dict objectForKey:@"Quuux"], @"translate:add:remove: method failed to add %@", @"Quuux");
}

- (void)testTranslateAddRemove_remove {
	NSMutableDictionary *dict = [self startingDictionary];

	[dict translate:nil
				add:nil
			 remove:[self deletia]];

	XCTAssertNil([dict objectForKey:@"Foo"], @"translate:add:remove: method failed to remove %@", @"Foo");
	XCTAssertNil([dict objectForKey:@"Bar"], @"translate:add:remove: method failed to remove %@", @"Bar");
	XCTAssertNil([dict objectForKey:@"Baz"], @"translate:add:remove: method failed to remove %@", @"Baz");
}

#pragma mark -

- (void)testTranslateAddRemove_translateAdd {
	NSMutableDictionary *dict = [self startingDictionary];
	NSDictionary *translation = [self translation];

	[dict translate:translation
				add:[self addition]
			 remove:nil];

	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Foo"]], @"translate:add:remove: method failed to translate %@ to %@", @"Foo", [translation objectForKey:@"Foo"]);
	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Bar"]], @"translate:add:remove: method failed to translate %@ to %@", @"Bar", [translation objectForKey:@"Bar"]);
	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Baz"]], @"translate:add:remove: method failed to translate %@ to %@", @"Baz", [translation objectForKey:@"Baz"]);

	XCTAssertNotNil([dict objectForKey:@"Foo"],   @"translate:add:remove: method failed to keep %@", @"Foo");
	XCTAssertNotNil([dict objectForKey:@"Bar"],   @"translate:add:remove: method failed to keep %@", @"Bar");
	XCTAssertNotNil([dict objectForKey:@"Baz"],   @"translate:add:remove: method failed to keep %@", @"Baz");
	XCTAssertNotNil([dict objectForKey:@"Qux"],   @"translate:add:remove: method failed to add %@", @"Qux");
	XCTAssertNotNil([dict objectForKey:@"Quux"],  @"translate:add:remove: method failed to add %@", @"Quux");
	XCTAssertNotNil([dict objectForKey:@"Quuux"], @"translate:add:remove: method failed to add %@", @"Quuux");
}

- (void)testTranslateAddRemove_translateRemove {
	NSMutableDictionary *dict = [self startingDictionary];
	NSDictionary *translation = [self translation];

	[dict translate:translation
				add:nil
			 remove:[self deletia]];

	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Foo"]], @"translate:add:remove: method failed to translate %@ to %@", @"Foo", [translation objectForKey:@"Foo"]);
	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Bar"]], @"translate:add:remove: method failed to translate %@ to %@", @"Bar", [translation objectForKey:@"Bar"]);
	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Baz"]], @"translate:add:remove: method failed to translate %@ to %@", @"Baz", [translation objectForKey:@"Baz"]);

	XCTAssertNil([dict objectForKey:@"Foo"], @"translate:add:remove: method failed to remove %@", @"Foo");
	XCTAssertNil([dict objectForKey:@"Bar"], @"translate:add:remove: method failed to remove %@", @"Bar");
	XCTAssertNil([dict objectForKey:@"Baz"], @"translate:add:remove: method failed to remove %@", @"Baz");
}

- (void)testTranslateAddRemove_addRemove {
	NSMutableDictionary *dict = [self startingDictionary];

	[dict translate:nil
				add:[self addition]
			 remove:[self deletia]];

	XCTAssertNotNil([dict objectForKey:@"Qux"],   @"translate:add:remove: method failed to add %@", @"Qux");
	XCTAssertNotNil([dict objectForKey:@"Quux"],  @"translate:add:remove: method failed to add %@", @"Quux");
	XCTAssertNotNil([dict objectForKey:@"Quuux"], @"translate:add:remove: method failed to add %@", @"Quuux");

	XCTAssertNil([dict objectForKey:@"Foo"], @"translate:add:remove: method failed to remove %@", @"Foo");
	XCTAssertNil([dict objectForKey:@"Bar"], @"translate:add:remove: method failed to remove %@", @"Bar");
	XCTAssertNil([dict objectForKey:@"Baz"], @"translate:add:remove: method failed to remove %@", @"Baz");
}

#pragma mark -

- (void)testTranslateAddRemove_translateAddRemove {
	NSMutableDictionary *dict = [self startingDictionary];
	NSDictionary *translation = [self translation];

	[dict translate:translation
				add:[self addition]
			 remove:[self deletia]];

	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Foo"]], @"translate:add:remove: method failed to translate %@ to %@", @"Foo", [translation objectForKey:@"Foo"]);
	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Bar"]], @"translate:add:remove: method failed to translate %@ to %@", @"Bar", [translation objectForKey:@"Bar"]);
	XCTAssertNotNil([dict objectForKey:[translation objectForKey:@"Baz"]], @"translate:add:remove: method failed to translate %@ to %@", @"Baz", [translation objectForKey:@"Baz"]);

	XCTAssertNotNil([dict objectForKey:@"Qux"],   @"translate:add:remove: method failed to add %@", @"Qux");
	XCTAssertNotNil([dict objectForKey:@"Quux"],  @"translate:add:remove: method failed to add %@", @"Quux");
	XCTAssertNotNil([dict objectForKey:@"Quuux"], @"translate:add:remove: method failed to add %@", @"Quuux");

	XCTAssertNil([dict objectForKey:@"Foo"], @"translate:add:remove: method failed to remove %@", @"Foo");
	XCTAssertNil([dict objectForKey:@"Bar"], @"translate:add:remove: method failed to remove %@", @"Bar");
	XCTAssertNil([dict objectForKey:@"Baz"], @"translate:add:remove: method failed to remove %@", @"Baz");
}

#pragma mark Set-up for the file tests

- (void)setUp
{
	[super setUp];
	workDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"TestDictionaryAdditions-%@", [[NSUUID UUID] UUIDString]]];
	XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:workDirectory withIntermediateDirectories:YES attributes:nil error:NULL]);
}

- (void)tearDown
{
	[[NSFileManager defaultManager] removeItemAtPath:workDirectory error:NULL];
	workDirectory = nil;
	[super tearDown];
}

#pragma mark Translation details

- (void)testTranslatedValueAppearsUnderTheNewKey
{
	NSMutableDictionary *dict = [self startingDictionary];
	[dict translate:[self translation] add:nil remove:nil];
	XCTAssertEqualObjects([dict objectForKey:@"Green"], @0U);
	XCTAssertEqualObjects([dict objectForKey:@"Red"], @1U);
	XCTAssertEqualObjects([dict objectForKey:@"Blue"], @2U);
}

- (void)testAdditionsInTheRemovalSetAreNotAdded
{
	NSMutableDictionary *dict = [self startingDictionary];
	[dict translate:nil add:[self addition] remove:[NSSet setWithObject:@"Qux"]];
	XCTAssertNil([dict objectForKey:@"Qux"]);
	XCTAssertNotNil([dict objectForKey:@"Quux"]);
}

- (void)testAnAdditionOverwritesAnExistingValue
{
	NSMutableDictionary *dict = [self startingDictionary];
	[dict translate:nil add:@{@"Foo": @"new"} remove:nil];
	XCTAssertEqualObjects([dict objectForKey:@"Foo"], @"new");
}

- (void)testTranslatingWithNothingToDoChangesNothing
{
	NSMutableDictionary *dict = [self startingDictionary];
	[dict translate:nil add:nil remove:nil];
	XCTAssertEqualObjects(dict, [self startingDictionary]);
}

- (void)testDictionaryByTranslatingLeavesTheReceiverAlone
{
	NSDictionary *original = [self startingDictionary];
	NSDictionary *before = [original copy];
	NSDictionary *result = [original dictionaryByTranslating:[self translation] adding:[self addition] removing:[self deletia]];
	XCTAssertEqualObjects(original, before);
	XCTAssertEqualObjects(result, (@{@"Green": @0U, @"Red": @1U, @"Blue": @2U, @"Qux": @3U, @"Quux": @4U, @"Quuux": @5U}));
}

- (void)testDictionaryByTranslatingWithNothingToDoIsEqualToTheReceiver
{
	NSDictionary *original = [self startingDictionary];
	XCTAssertEqualObjects([original dictionaryByTranslating:nil adding:nil removing:nil], original);
}

#pragma mark Key sets

- (void)testAllKeysSetHoldsEveryKey
{
	XCTAssertEqualObjects([[self startingDictionary] allKeysSet], ([NSSet setWithObjects:@"Foo", @"Bar", @"Baz", nil]));
}

- (void)testAllKeysMutableSetIsMutable
{
	NSMutableSet *keys = [[self startingDictionary] allKeysMutableSet];
	XCTAssertEqualObjects(keys, ([NSSet setWithObjects:@"Foo", @"Bar", @"Baz", nil]));
	[keys addObject:@"Qux"];
	XCTAssertEqual([keys count], (NSUInteger)4);
}

- (void)testAllKeysSetOfAnEmptyDictionaryIsEmpty
{
	XCTAssertEqualObjects([@{} allKeysSet], [NSSet set]);
	XCTAssertEqualObjects([@{} allKeysMutableSet], [NSSet set]);
}

#pragma mark Comparing with a prior dictionary

- (void)testComparedWithNoPriorEverythingIsAdded
{
	NSSet *added = nil, *removed = nil;
	[[self startingDictionary] compareWithPriorDictionary:nil getAddedKeys:&added getRemovedKeys:&removed includeChangedKeys:NO];
	XCTAssertEqualObjects(added, ([NSSet setWithObjects:@"Foo", @"Bar", @"Baz", nil]));
	XCTAssertEqualObjects(removed, [NSSet set]);
}

- (void)testComparedWithAnEqualPriorNothingChanged
{
	NSSet *added = nil, *removed = nil;
	[[self startingDictionary] compareWithPriorDictionary:[self startingDictionary] getAddedKeys:&added getRemovedKeys:&removed includeChangedKeys:YES];
	XCTAssertEqualObjects(added, [NSSet set]);
	XCTAssertEqualObjects(removed, [NSSet set]);
}

- (void)testAnAddedKeyIsReportedAsAdded
{
	NSSet *added = nil, *removed = nil;
	[@{@"a": @1, @"b": @2} compareWithPriorDictionary:@{@"a": @1} getAddedKeys:&added getRemovedKeys:&removed includeChangedKeys:YES];
	XCTAssertEqualObjects(added, [NSSet setWithObject:@"b"]);
	XCTAssertEqualObjects(removed, [NSSet set]);
}

- (void)testARemovedKeyIsReportedAsRemoved
{
	NSSet *added = nil, *removed = nil;
	[@{@"a": @1} compareWithPriorDictionary:@{@"a": @1, @"b": @2} getAddedKeys:&added getRemovedKeys:&removed includeChangedKeys:YES];
	XCTAssertEqualObjects(added, [NSSet set]);
	XCTAssertEqualObjects(removed, [NSSet setWithObject:@"b"]);
}

- (void)testAChangedValueIsInBothSetsWhenAsked
{
	NSSet *added = nil, *removed = nil;
	[@{@"a": @2} compareWithPriorDictionary:@{@"a": @1} getAddedKeys:&added getRemovedKeys:&removed includeChangedKeys:YES];
	XCTAssertEqualObjects(added, [NSSet setWithObject:@"a"]);
	XCTAssertEqualObjects(removed, [NSSet setWithObject:@"a"]);
}

- (void)testAChangedValueIsIgnoredWhenNotAsked
{
	NSSet *added = nil, *removed = nil;
	[@{@"a": @2} compareWithPriorDictionary:@{@"a": @1} getAddedKeys:&added getRemovedKeys:&removed includeChangedKeys:NO];
	XCTAssertEqualObjects(added, [NSSet set]);
	XCTAssertEqualObjects(removed, [NSSet set]);
}

- (void)testAddedRemovedAndChangedKeysTogether
{
	NSSet *added = nil, *removed = nil;
	[@{@"a": @1, @"b": @2, @"d": @1} compareWithPriorDictionary:@{@"a": @1, @"b": @1, @"c": @1} getAddedKeys:&added getRemovedKeys:&removed includeChangedKeys:YES];
	XCTAssertEqualObjects(added, ([NSSet setWithObjects:@"b", @"d", nil]));
	XCTAssertEqualObjects(removed, ([NSSet setWithObjects:@"b", @"c", nil]));
}

- (void)testNullOutParametersAreAccepted
{
	NSSet *removed = nil;
	[@{@"a": @1} compareWithPriorDictionary:@{@"b": @1} getAddedKeys:NULL getRemovedKeys:&removed includeChangedKeys:YES];
	XCTAssertEqualObjects(removed, [NSSet setWithObject:@"b"]);
	[@{@"a": @1} compareWithPriorDictionary:@{@"b": @1} getAddedKeys:NULL getRemovedKeys:NULL includeChangedKeys:YES];
	[@{@"a": @1} compareWithPriorDictionary:nil getAddedKeys:NULL getRemovedKeys:NULL includeChangedKeys:NO];
}

#pragma mark Intersection and difference

- (void)testIntersectionKeepsOnlyTheListedKeys
{
	NSDictionary *result = [[self startingDictionary] dictionaryWithIntersectionWithSetOfKeys:[NSSet setWithObjects:@"Foo", @"Baz", @"NotThere", nil]];
	XCTAssertEqualObjects(result, (@{@"Foo": @0U, @"Baz": @2U}));
}

- (void)testIntersectionWithAnEmptySetIsEmpty
{
	XCTAssertEqualObjects([[self startingDictionary] dictionaryWithIntersectionWithSetOfKeys:[NSSet set]], @{});
}

- (void)testDifferenceDropsTheListedKeys
{
	NSDictionary *result = [[self startingDictionary] dictionaryWithDifferenceWithSetOfKeys:[NSSet setWithObjects:@"Foo", @"NotThere", nil]];
	XCTAssertEqualObjects(result, (@{@"Bar": @1U, @"Baz": @2U}));
}

- (void)testDifferenceWithAnEmptySetIsTheWholeDictionary
{
	XCTAssertEqualObjects([[self startingDictionary] dictionaryWithDifferenceWithSetOfKeys:[NSSet set]], [self startingDictionary]);
}

- (void)testIntersectionAndDifferenceLeaveTheReceiverAlone
{
	NSMutableDictionary *dict = [self startingDictionary];
	[dict dictionaryWithIntersectionWithSetOfKeys:[NSSet setWithObject:@"Foo"]];
	[dict dictionaryWithDifferenceWithSetOfKeys:[NSSet setWithObject:@"Foo"]];
	XCTAssertEqualObjects(dict, [self startingDictionary]);
}

- (void)testIntersectSetOfKeysInPlace
{
	NSMutableDictionary *dict = [self startingDictionary];
	[dict intersectSetOfKeys:[NSSet setWithObject:@"Bar"]];
	XCTAssertEqualObjects(dict, @{@"Bar": @1U});
}

- (void)testMinusSetOfKeysInPlace
{
	NSMutableDictionary *dict = [self startingDictionary];
	[dict minusSetOfKeys:[NSSet setWithObjects:@"Bar", @"Baz", nil]];
	XCTAssertEqualObjects(dict, @{@"Foo": @0U});
}

#pragma mark CSS

- (void)testCSSStringOfOneProperty
{
	XCTAssertEqualObjects([@{@"font-size": @"12pt"} CSSString], @"font-size: 12pt;");
}

- (void)testCSSStringOfAnEmptyDictionaryIsEmpty
{
	XCTAssertEqualObjects([@{} CSSString], @"");
}

- (void)testCSSStringListsEveryPropertyOnce
{
	//Enumeration order is not fixed, so each declaration is looked for by itself and the length rules out repeats.
	NSString *css = [@{@"font-family": @"Helvetica", @"font-weight": @"bold"} CSSString];
	XCTAssertTrue([css containsString:@"font-family: Helvetica;"], @"%@", css);
	XCTAssertTrue([css containsString:@"font-weight: bold;"], @"%@", css);
	XCTAssertEqual([css length], [@"font-family: Helvetica; font-weight: bold;" length]);
}

#pragma mark Property list validation

- (void)testPropertyListTypesValidate
{
	NSDictionary *dict = @{@"s": @"x", @"n": @1, @"d": [NSDate dateWithTimeIntervalSinceReferenceDate:0], @"b": [NSData data], @"a": @[@"y"], @"m": @{@"k": @"v"}};
	XCTAssertTrue([dict validateAsPropertyList]);
}

- (void)testAnEmptyDictionaryValidates
{
	XCTAssertTrue([@{} validateAsPropertyList]);
}

- (void)testANonStringKeyFailsValidation
{
	XCTAssertFalse([@{@1: @"x"} validateAsPropertyList]);
}

- (void)testANullValueFailsValidation
{
	XCTAssertFalse([@{@"k": [NSNull null]} validateAsPropertyList]);
}

- (void)testAnInvalidNestedDictionaryFailsValidation
{
	XCTAssertFalse([@{@"k": @{@"inner": [NSNull null]}} validateAsPropertyList]);
}

- (void)testAnInvalidNestedArrayFailsValidation
{
	XCTAssertFalse([@{@"k": @[[NSNull null]]} validateAsPropertyList]);
}

#pragma mark Files

- (NSString *)writtenPlistPathForName:(NSString *)name
{
	return [[workDirectory stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"plist"];
}

- (void)testAWrittenDictionaryReadsBack
{
	NSDictionary *dict = @{@"string": @"caf\u00e9", @"number": @42, @"list": @[@1, @2]};
	XCTAssertTrue([dict writeToPath:workDirectory withName:@"Prefs"]);
	XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[self writtenPlistPathForName:@"Prefs"]]);
	XCTAssertEqualObjects([NSDictionary dictionaryAtPath:workDirectory withName:@"Prefs" create:NO], dict);
}

- (void)testWritingCreatesMissingDirectories
{
	NSString *deep = [workDirectory stringByAppendingPathComponent:@"a/b/c"];
	XCTAssertTrue([@{@"k": @"v"} writeToPath:deep withName:@"Prefs"]);
	XCTAssertEqualObjects([NSDictionary dictionaryAtPath:deep withName:@"Prefs" create:NO], @{@"k": @"v"});
}

- (void)testTheWrittenFileIsABinaryPropertyList
{
	XCTAssertTrue([@{@"k": @"v"} writeToPath:workDirectory withName:@"Prefs"]);
	NSData *data = [NSData dataWithContentsOfFile:[self writtenPlistPathForName:@"Prefs"]];
	NSPropertyListFormat format = 0;
	XCTAssertNotNil([NSPropertyListSerialization propertyListWithData:data options:0 format:&format error:NULL]);
	XCTAssertEqual(format, NSPropertyListBinaryFormat_v1_0);
}

- (void)testWritingSomethingThatIsNotAPropertyListFails
{
	XCTAssertFalse([@{@"k": [NSNull null]} writeToPath:workDirectory withName:@"Bad"]);
	XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[self writtenPlistPathForName:@"Bad"]]);
}

- (void)testAMissingDictionaryWithCreateIsEmpty
{
	NSDictionary *dict = [NSDictionary dictionaryAtPath:workDirectory withName:@"Missing" create:YES];
	XCTAssertNotNil(dict);
	XCTAssertEqual([dict count], (NSUInteger)0);
}

- (void)testAMissingDictionaryWithoutCreateIsNil
{
	XCTAssertNil([NSDictionary dictionaryAtPath:workDirectory withName:@"Missing" create:NO]);
	XCTAssertNil([NSMutableDictionary dictionaryAtPath:workDirectory withName:@"Missing" create:NO]);
}

- (void)testAMissingMutableDictionaryWithCreateIsMutableAndEmpty
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryAtPath:workDirectory withName:@"Missing" create:YES];
	XCTAssertTrue([dict isKindOfClass:[NSMutableDictionary class]]);
	XCTAssertEqual([dict count], (NSUInteger)0);
	[dict setObject:@"v" forKey:@"k"];
}

- (void)testAMutableDictionaryReadFromDiskHasMutableContainers
{
	XCTAssertTrue(([@{@"nested": @{@"k": @"v"}, @"list": @[@"a"]} writeToPath:workDirectory withName:@"Prefs"]));
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryAtPath:workDirectory withName:@"Prefs" create:NO];
	XCTAssertTrue([dict isKindOfClass:[NSMutableDictionary class]]);
	XCTAssertTrue([[dict objectForKey:@"nested"] isKindOfClass:[NSMutableDictionary class]]);
	XCTAssertTrue([[dict objectForKey:@"list"] isKindOfClass:[NSMutableArray class]]);
	[[dict objectForKey:@"nested"] setObject:@"w" forKey:@"k2"];
	[[dict objectForKey:@"list"] addObject:@"b"];
}

- (void)testDictionaryNamedWithoutSuchResourceIsNil
{
	XCTAssertNil([NSDictionary dictionaryNamed:@"NoSuchDictionaryResource" forClass:[self class]]);
}

@end
