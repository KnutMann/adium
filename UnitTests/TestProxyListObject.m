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
#import <Adium/AIListObject.h>
#import <Adium/AIListGroup.h>
#import <Adium/AIProxyListObject.h>
#import <Adium/AIService.h>

/* The proxy registry is global and keyed by internalObjectID, which is service ID plus UID. A
 * service of this file's own keeps these keys apart from every other test's. */
@interface TPLOService : AIService
@end

@implementation TPLOService
- (NSString *)serviceID { return @"ProxyTest"; }
@end

static AIListObject *TPLOObject(NSString *UID)
{
	static TPLOService *service = nil;
	if (!service) service = [[TPLOService alloc] init];
	return [[AIListObject alloc] initWithUID:UID service:service];
}

@interface TestProxyListObject : XCTestCase
@end

@implementation TestProxyListObject

- (void)testProxyKeyIsTheObjectIDWhenThereIsNoContainer
{
	AIListObject *object = TPLOObject(@"keyless");
	AIProxyListObject *proxy = [AIProxyListObject proxyListObjectForListObject:object inListObject:nil];
	XCTAssertEqualObjects(proxy.key, @"ProxyTest.keyless");
	XCTAssertTrue(proxy.listObject == object);
	XCTAssertNil(proxy.containingObject);
}

- (void)testProxyKeyCombinesObjectAndContainer
{
	AIListObject *object = TPLOObject(@"contained");
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"ProxyGroup"];
	AIProxyListObject *proxy = [AIProxyListObject proxyListObjectForListObject:object inListObject:group];
	XCTAssertEqualObjects(proxy.key, @"ProxyTest.contained-Group.ProxyGroup");
	XCTAssertTrue(proxy.containingObject == group);
}

- (void)testTheSameProxyIsHandedOutForTheSamePair
{
	AIListObject *object = TPLOObject(@"shared");
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"ProxyGroupA"];
	AIListGroup *otherGroup = [[AIListGroup alloc] initWithUID:@"ProxyGroupB"];

	AIProxyListObject *proxy = [AIProxyListObject proxyListObjectForListObject:object inListObject:group];
	XCTAssertTrue(proxy == [AIProxyListObject proxyListObjectForListObject:object inListObject:group]);
	XCTAssertFalse(proxy == [AIProxyListObject proxyListObjectForListObject:object inListObject:otherGroup], @"one proxy per place the object appears in");
	XCTAssertFalse(proxy == [AIProxyListObject proxyListObjectForListObject:object inListObject:nil]);
}

- (void)testExistingProxyIsNilUntilOneIsMade
{
	AIListObject *object = TPLOObject(@"unproxied");
	XCTAssertNil([AIProxyListObject existingProxyListObjectForListObject:object inListObject:nil]);

	AIProxyListObject *proxy = [AIProxyListObject proxyListObjectForListObject:object inListObject:nil];
	XCTAssertTrue([AIProxyListObject existingProxyListObjectForListObject:object inListObject:nil] == proxy);
}

- (void)testProxyIsEqualToItselfAndToItsListObject
{
	AIListObject *object = TPLOObject(@"equal");
	AIProxyListObject *proxy = [AIProxyListObject proxyListObjectForListObject:object inListObject:nil];
	XCTAssertTrue([proxy isEqual:proxy]);
	XCTAssertTrue([proxy isEqual:object]);
	XCTAssertEqual(proxy.hash, object.hash);
	XCTAssertFalse([proxy isEqual:TPLOObject(@"other")]);
}

- (void)testProxyAnswersForItsListObjectsClass
{
	AIListObject *object = TPLOObject(@"classy");
	AIProxyListObject *proxy = [AIProxyListObject proxyListObjectForListObject:object inListObject:nil];
	XCTAssertTrue([proxy class] == [AIListObject class]);
	XCTAssertTrue([proxy isKindOfClass:[AIListObject class]]);
	XCTAssertTrue([proxy isMemberOfClass:[AIListObject class]]);
	XCTAssertFalse([proxy isKindOfClass:[AIListGroup class]]);
}

- (void)testUnknownMessagesAreForwardedToTheListObject
{
	AIListObject *object = TPLOObject(@"forwarded");
	id proxy = [AIProxyListObject proxyListObjectForListObject:object inListObject:nil];
	XCTAssertEqualObjects([proxy UID], @"forwarded");
	XCTAssertEqualObjects([proxy internalObjectID], @"ProxyTest.forwarded");
}

- (void)testFlushCacheClearsTheCachedDisplayValues
{
	AIProxyListObject *proxy = [AIProxyListObject proxyListObjectForListObject:TPLOObject(@"cached") inListObject:nil];
	proxy.cachedDisplayNameString = @"Cached";
	proxy.cachedDisplayName = [[NSAttributedString alloc] initWithString:@"Cached"];
	proxy.cachedLabelAttributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:12] };

	[proxy flushCache];
	XCTAssertNil(proxy.cachedDisplayNameString);
	XCTAssertNil(proxy.cachedDisplayName);
	XCTAssertNil(proxy.cachedLabelAttributes);
}

- (void)testReleasingAProxyRemovesItFromTheRegistryAndForgetsItsObject
{
	AIListObject *object = TPLOObject(@"released");
	AIProxyListObject *proxy = [AIProxyListObject proxyListObjectForListObject:object inListObject:nil];
	proxy.cachedDisplayNameString = @"Cached";

	[AIProxyListObject releaseProxyObject:proxy];
	XCTAssertNil([AIProxyListObject existingProxyListObjectForListObject:object inListObject:nil]);
	XCTAssertNil(proxy.listObject);
	XCTAssertNil(proxy.cachedDisplayNameString);
}

- (void)testAListObjectRemembersItsProxies
{
	AIListObject *object = TPLOObject(@"remembered");
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"ProxyGroupC"];
	AIProxyListObject *bare = [AIProxyListObject proxyListObjectForListObject:object inListObject:nil];
	AIProxyListObject *grouped = [AIProxyListObject proxyListObjectForListObject:object inListObject:group];
	XCTAssertEqualObjects(object.proxyObjects, ([NSSet setWithObjects:bare, grouped, nil]));
}

- (void)testAProxyForAnotherObjectWithTheSameIDIsReplaced
{
	AIListObject *first = TPLOObject(@"twin");
	AIListObject *second = TPLOObject(@"twin");
	AIProxyListObject *firstProxy = [AIProxyListObject proxyListObjectForListObject:first inListObject:nil];

	AIProxyListObject *secondProxy = [AIProxyListObject proxyListObjectForListObject:second inListObject:nil];
	XCTAssertFalse(secondProxy == firstProxy);
	XCTAssertTrue(secondProxy.listObject == second);
	XCTAssertNil(firstProxy.listObject, @"the stale proxy was released on the way");
}

- (void)testADeallocatedListObjectTakesItsProxiesWithIt
{
	__weak AIListObject *weakObject = nil;
	@autoreleasepool {
		AIListObject *object = TPLOObject(@"mortal");
		/* The initialiser schedules a delayed message to itself; the run loop would hold the object
		 * until it fires, and nothing runs the loop here. */
		[NSObject cancelPreviousPerformRequestsWithTarget:object];
		[AIProxyListObject proxyListObjectForListObject:object inListObject:nil];
		weakObject = object;
	}
	XCTAssertNil(weakObject, @"nothing else may be keeping the object alive, or the test proves nothing");
	XCTAssertNil([AIProxyListObject existingProxyListObjectForListObject:TPLOObject(@"mortal") inListObject:nil]);
}

@end
