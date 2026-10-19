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
#import <Adium/ESObjectWithProperties.h>
#import <Adium/AIListObject.h>
#import <Adium/AIProxyListObject.h>
#import <AIUtilities/AIMutableOwnerArray.h>

/* A subclass that records what the base class tells its subclasses, and carries the three kinds of
 * ivar the property store addresses by name: an object, an NSInteger, and one it cannot read. */
@interface TOWPRecordingObject : ESObjectWithProperties {
	NSString	*objectIvar;
	NSInteger	integerIvar;
	BOOL		boolIvar;
}
@property (nonatomic, readonly) NSMutableArray *modifiedKeySets;
@property (nonatomic, readonly) NSMutableArray *modifiedSilently;
@property (nonatomic, readonly) NSMutableArray *sequence;
@property (nonatomic, readonly) NSUInteger displayArrayCallbacks;
@property (nonatomic, copy) NSString *keyToSetLaterDuringNotification;
@end

@implementation TOWPRecordingObject

- (id)init
{
	if ((self = [super init])) {
		_modifiedKeySets = [NSMutableArray array];
		_modifiedSilently = [NSMutableArray array];
		_sequence = [NSMutableArray array];
	}
	return self;
}

- (void)didModifyProperties:(NSSet *)keys silent:(BOOL)silent
{
	[_modifiedKeySets addObject:keys];
	[_modifiedSilently addObject:@(silent)];
	[_sequence addObject:@"modified"];

	if (self.keyToSetLaterDuringNotification) {
		NSString *key = self.keyToSetLaterDuringNotification;
		self.keyToSetLaterDuringNotification = nil;
		[self setValue:@"queued" forProperty:key notify:NotifyLater];
	}
}

- (void)didNotifyOfChangedPropertiesSilently:(BOOL)silent
{
	[_sequence addObject:@"notified"];
}

- (void)mutableOwnerArray:(AIMutableOwnerArray *)inArray didSetObject:(id)anObject withOwner:(id)inOwner priorityLevel:(float)priority
{
	_displayArrayCallbacks++;
}

@end

@interface TOWPObserver : NSObject
@property (nonatomic, readonly) NSMutableArray *changes;
@end

@implementation TOWPObserver

- (id)init
{
	if ((self = [super init]))
		_changes = [NSMutableArray array];
	return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	[_changes addObject:change];
}

@end

@interface TestObjectWithProperties : XCTestCase
@end

@implementation TestObjectWithProperties

#pragma mark Storage

- (void)testValueForPropertyIsNilWhenNeverSet
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	XCTAssertNil([object valueForProperty:@"never"]);
}

- (void)testSetValueStoresAndReturnsTheValue
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyNever];
	XCTAssertEqualObjects([object valueForProperty:@"colour"], @"blue");
}

- (void)testSettingNilRemovesTheProperty
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyNever];
	[object setValue:nil forProperty:@"colour" notify:NotifyNever];
	XCTAssertNil([object valueForProperty:@"colour"]);
	XCTAssertNil([object.properties objectForKey:@"colour"]);
}

- (void)testPropertiesDictionaryReflectsWhatWasSet
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyNever];
	[object setValue:@3 forProperty:@"count" notify:NotifyNever];
	XCTAssertEqualObjects([object.properties objectForKey:@"colour"], @"blue");
	XCTAssertEqualObjects([object.properties objectForKey:@"count"], @3);
}

- (void)testNumericAccessorsReadANumber
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	[object setValue:@42 forProperty:@"answer" notify:NotifyNever];
	XCTAssertEqual([object integerValueForProperty:@"answer"], (NSInteger)42);
	XCTAssertEqual([object intValueForProperty:@"answer"], 42);
	XCTAssertTrue([object boolValueForProperty:@"answer"]);
	XCTAssertEqualObjects([object numberValueForProperty:@"answer"], @42);
}

- (void)testNumericAccessorsAreZeroWhenUnset
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	XCTAssertEqual([object integerValueForProperty:@"answer"], (NSInteger)0);
	XCTAssertEqual([object intValueForProperty:@"answer"], 0);
	XCTAssertFalse([object boolValueForProperty:@"answer"]);
	XCTAssertNil([object numberValueForProperty:@"answer"]);
}

- (void)testNumericAccessorsIgnoreAValueThatIsNotANumber
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	[object setValue:@"42" forProperty:@"answer" notify:NotifyNever];
	XCTAssertNil([object numberValueForProperty:@"answer"]);
	XCTAssertEqual([object integerValueForProperty:@"answer"], (NSInteger)0);
	XCTAssertEqual([object intValueForProperty:@"answer"], 0);
	XCTAssertFalse([object boolValueForProperty:@"answer"]);
}

#pragma mark Notification timing

- (void)testNotifyNowDeliversTheKeyImmediatelyAndNotSilently
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyNow];
	XCTAssertEqualObjects(object.modifiedKeySets, @[[NSSet setWithObject:@"colour"]]);
	XCTAssertEqualObjects(object.modifiedSilently, @[@NO]);
}

- (void)testNotifyLaterHoldsTheKeyUntilAsked
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyLater];
	XCTAssertEqual(object.modifiedKeySets.count, (NSUInteger)0);

	[object notifyOfChangedPropertiesSilently:NO];
	XCTAssertEqualObjects(object.modifiedKeySets, @[[NSSet setWithObject:@"colour"]]);
}

- (void)testSeveralLaterChangesAreDeliveredAsOneSet
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyLater];
	[object setValue:@"large" forProperty:@"size" notify:NotifyLater];
	[object notifyOfChangedPropertiesSilently:NO];
	XCTAssertEqualObjects(object.modifiedKeySets, (@[[NSSet setWithObjects:@"colour", @"size", nil]]));
}

- (void)testNotifyingSilentlyPassesTheFlagThrough
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyLater];
	[object notifyOfChangedPropertiesSilently:YES];
	XCTAssertEqualObjects(object.modifiedSilently, @[@YES]);
}

- (void)testDidNotifyFollowsDidModify
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyLater];
	[object notifyOfChangedPropertiesSilently:NO];
	NSArray *expected = @[@"modified", @"notified"];
	XCTAssertEqualObjects(object.sequence, expected);
}

- (void)testNothingPendingMeansNoNotification
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	[object notifyOfChangedPropertiesSilently:NO];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyLater];
	[object notifyOfChangedPropertiesSilently:NO];
	[object notifyOfChangedPropertiesSilently:NO];
	XCTAssertEqual(object.sequence.count, (NSUInteger)2, @"one notification for the one change, nothing for the empty rounds");
}

- (void)testNotifyNeverIsNeverDelivered
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyNever];
	[object notifyOfChangedPropertiesSilently:NO];
	XCTAssertEqual(object.sequence.count, (NSUInteger)0);
	XCTAssertEqualObjects([object valueForProperty:@"colour"], @"blue", @"the value is stored all the same");
}

- (void)testSettingTheSameValueAgainDoesNotNotify
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	NSString *value = @"blue";
	[object setValue:value forProperty:@"colour" notify:NotifyNow];
	[object setValue:value forProperty:@"colour" notify:NotifyNow];
	XCTAssertEqual(object.modifiedKeySets.count, (NSUInteger)1);
}

- (void)testSettingNilForAnUnsetPropertyDoesNotNotify
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	[object setValue:nil forProperty:@"colour" notify:NotifyNow];
	XCTAssertEqual(object.modifiedKeySets.count, (NSUInteger)0);
}

- (void)testAChangeOnAnotherObjectIsNotTreatedAsOurOwn
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	ESObjectWithProperties *other = [[ESObjectWithProperties alloc] init];
	[object object:other didChangeValueForProperty:@"colour" notify:NotifyNow];
	[object object:other didChangeValueForProperty:@"colour" notify:NotifyLater];
	[object notifyOfChangedPropertiesSilently:NO];
	XCTAssertEqual(object.sequence.count, (NSUInteger)0);
}

- (void)testAChangeQueuedDuringNotificationWaitsForTheNext
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	object.keyToSetLaterDuringNotification = @"size";
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyLater];

	[object notifyOfChangedPropertiesSilently:NO];
	XCTAssertEqualObjects(object.modifiedKeySets, @[[NSSet setWithObject:@"colour"]]);

	[object notifyOfChangedPropertiesSilently:NO];
	NSArray *expected = @[[NSSet setWithObject:@"colour"], [NSSet setWithObject:@"size"]];
	XCTAssertEqualObjects(object.modifiedKeySets, expected);
}

#pragma mark Key-value coding and observing

- (void)testValueForKeyFallsBackToTheProperty
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	[object setValue:@"blue" forProperty:@"colour" notify:NotifyNever];
	XCTAssertEqualObjects([object valueForKey:@"colour"], @"blue");
	XCTAssertNil([object valueForKey:@"size"]);
}

- (void)testPropertiesAreObservableWithKeyValueObserving
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	TOWPObserver *observer = [[TOWPObserver alloc] init];
	[object addObserver:observer forKeyPath:@"colour" options:NSKeyValueObservingOptionNew context:NULL];

	[object setValue:@"blue" forProperty:@"colour" notify:NotifyNever];
	[object setValue:nil forProperty:@"colour" notify:NotifyNever];

	[object removeObserver:observer forKeyPath:@"colour"];

	XCTAssertEqual(observer.changes.count, (NSUInteger)2);
	XCTAssertEqualObjects([observer.changes[0] objectForKey:NSKeyValueChangeNewKey], @"blue");
	XCTAssertEqualObjects([observer.changes[1] objectForKey:NSKeyValueChangeNewKey], [NSNull null]);
}

#pragma mark Ivar-backed properties

- (void)testAnObjectIvarIsAddressableByName
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	[object setValue:@"stored" forProperty:@"objectIvar" notify:NotifyNever];
	XCTAssertEqualObjects([object valueForProperty:@"objectIvar"], @"stored");
	XCTAssertEqualObjects([object valueForKey:@"objectIvar"], @"stored", @"key-value coding reads the ivar itself");
	XCTAssertNil([object.properties objectForKey:@"objectIvar"], @"an ivar-backed property does not also live in the dictionary");

	[object setValue:nil forProperty:@"objectIvar" notify:NotifyNever];
	XCTAssertNil([object valueForProperty:@"objectIvar"]);
}

- (void)testAnIntegerIvarIsAddressableByNameAsANumber
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	[object setValue:@7 forProperty:@"integerIvar" notify:NotifyNever];
	XCTAssertEqualObjects([object valueForProperty:@"integerIvar"], @7);
	XCTAssertEqual([object integerValueForProperty:@"integerIvar"], (NSInteger)7);
	XCTAssertEqualObjects([object valueForKey:@"integerIvar"], @7);

	[object setValue:nil forProperty:@"integerIvar" notify:NotifyNever];
	XCTAssertEqual([object integerValueForProperty:@"integerIvar"], (NSInteger)0);
}

- (void)testAnIvarThatIsNeitherObjectNorIntegerIsNotReadable
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	XCTAssertNil([object valueForProperty:@"boolIvar"]);
}

#pragma mark Display arrays

- (void)testDisplayArrayIsCreatedOnceAndReused
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	AIMutableOwnerArray *array = [object displayArrayForKey:@"Display Name"];
	XCTAssertNotNil(array);
	XCTAssertTrue(array == [object displayArrayForKey:@"Display Name"]);
	XCTAssertTrue(array == [object displayArrayForKey:@"Display Name" create:YES]);
	XCTAssertFalse(array == [object displayArrayForKey:@"Other" create:YES]);
}

- (void)testDisplayArrayLookupWithoutCreateReturnsNilUntilCreated
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	XCTAssertNil([object displayArrayForKey:@"Display Name" create:NO]);
	AIMutableOwnerArray *array = [object displayArrayForKey:@"Display Name"];
	XCTAssertTrue(array == [object displayArrayForKey:@"Display Name" create:NO]);
}

- (void)testDisplayArrayObjectIsTheArraysCurrentValue
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	XCTAssertNil([object displayArrayObjectForKey:@"Display Name"]);

	AIMutableOwnerArray *array = [object displayArrayForKey:@"Display Name"];
	[array setObject:@"Low" withOwner:@"owner A" priorityLevel:Low_Priority];
	[array setObject:@"High" withOwner:@"owner B" priorityLevel:High_Priority];
	XCTAssertEqualObjects([object displayArrayObjectForKey:@"Display Name"], @"High");

	[array setObject:nil withOwner:@"owner B"];
	XCTAssertEqualObjects([object displayArrayObjectForKey:@"Display Name"], @"Low");
}

- (void)testTheObjectIsTheDelegateOfItsDisplayArrays
{
	TOWPRecordingObject *object = [[TOWPRecordingObject alloc] init];
	AIMutableOwnerArray *array = [object displayArrayForKey:@"Display Name"];
	XCTAssertTrue(array.delegate == object);

	[array setObject:@"Alias" withOwner:@"owner"];
	XCTAssertEqual(object.displayArrayCallbacks, (NSUInteger)1);
}

#pragma mark Naming and proxies

- (void)testDisplayNameAndInternalObjectIDAreEmptyByDefault
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	XCTAssertEqualObjects(object.displayName, @"");
	XCTAssertEqualObjects(object.internalObjectID, @"");
}

- (void)testProxyObjectsAreNilUntilOneIsNoted
{
	ESObjectWithProperties *object = [[ESObjectWithProperties alloc] init];
	XCTAssertNil([object proxyObjects]);

	/* A real proxy, because the object releases every noted proxy when it goes away. */
	AIProxyListObject *proxy = [[AIProxyListObject alloc] init];
	proxy.key = @"TestObjectWithProperties.proxy";
	[object noteProxyObject:proxy];
	[object noteProxyObject:proxy];
	XCTAssertEqualObjects([object proxyObjects], [NSSet setWithObject:proxy]);
}

@end
