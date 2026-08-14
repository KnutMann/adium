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

#import "AIProxyListObject.h"
#import <Adium/ESObjectWithProperties.h>
#import <Adium/AIListObject.h>

@interface NSObject (PublicAPIMissingFromHeadersAndDocsButInTheReleaseNotesGoshDarnit)
- (id)forwardingTargetForSelector:(SEL)aSelector;
@end

@implementation AIProxyListObject

@synthesize key, cachedDisplayName, cachedDisplayNameString, cachedLabelAttributes, cachedDisplayNameSize;
@synthesize listObject, containingObject;


static inline NSMutableDictionary *_getProxyDict() {
    static NSMutableDictionary *proxyDict;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        proxyDict = [[NSMutableDictionary alloc] init];
    });
    return proxyDict;
}

#define proxyDict _getProxyDict()

+ (AIProxyListObject *)existingProxyListObjectForListObject:(AIListObject *)inListObject
											   inListObject:(ESObjectWithProperties <AIContainingObject>*)inContainingObject
{
	NSString *key = (inContainingObject ? 
					 [NSString stringWithFormat:@"%@-%@", inListObject.internalObjectID, inContainingObject.internalObjectID] :
					 inListObject.internalObjectID);
	
	return [proxyDict objectForKey:key];
}

+ (AIProxyListObject *)proxyListObjectForListObject:(AIListObject *)inListObject
									   inListObject:(ESObjectWithProperties <AIContainingObject>*)inContainingObject
{
	AIProxyListObject *proxy;
	NSString *key = (inContainingObject ? 
					 [NSString stringWithFormat:@"%@-%@", inListObject.internalObjectID, inContainingObject.internalObjectID] :
					 inListObject.internalObjectID);

	proxy = [proxyDict objectForKey:key];

	if (proxy && proxy.listObject != inListObject) {
        /* This is generally a memory management failure; AIContactController stopped tracking a list object, but it never deallocated and
		 * so never called [AIProxyListObject releaseProxyObject:]. -evands 8/28/11
		 */
		AILogWithSignature(@"%@ was leaked! Meh. We'll recreate the proxy for %@.", proxy.listObject, proxy.key);
		[self releaseProxyObject:proxy];
		proxy = nil;
	}

	if (!proxy) {
		proxy = [[AIProxyListObject alloc] init];
		proxy.listObject = inListObject;
		proxy.containingObject = inContainingObject;
		proxy.key = key;
		[inListObject noteProxyObject:proxy];
		[proxyDict setObject:proxy
					  forKey:key];
		[proxy release];
	}

	return proxy;
}

- (void)flushCache
{
	self.cachedDisplayName = nil;
	self.cachedDisplayNameString = nil;
	self.cachedLabelAttributes = nil;
}

/*!
 * @brief Called when an AIListObject is done with an AIProxyListObject to remove it from the global dictionary
 *
 * This should be called only by AIListObject when it deallocates, for each of its proxy objects
 */
+ (void)releaseProxyObject:(AIProxyListObject *)proxyObject
{
	[[proxyObject retain] autorelease];
	proxyObject.listObject = nil;
	[proxyObject flushCache];
	[proxyDict removeObjectForKey:proxyObject.key];
}

- (void)dealloc
{
	AILogWithSignature(@"%@", self);
	self.key = nil;

    [self flushCache];
	
	[super dealloc];
}

/* Pretend to be our listObject. I suspect being an NSProxy subclass could do this more cleanly, but my initial attempt
 * failed and this works fine.
 */
- (Class)class
{
	return [[self listObject] class];
}

- (BOOL)isKindOfClass:(Class)class
{
	return [[self listObject] isKindOfClass:class];
}

- (BOOL)isMemberOfClass:(Class)class
{
	return [[self listObject] isMemberOfClass:class];
}

/*!
 * @brief A proxy answers for its list object, and for itself
 *
 * The forwarding is the point of the class: code holding a proxy compares it against a list object
 * and expects a match. What was missing is the first line, and it is not a nicety. Without it a proxy
 * is not equal to itself, because the question asked is whether the LIST OBJECT equals the proxy, and
 * it does not.
 *
 * NSOutlineView finds its items by equality. So -rowForItem: answered -1 for every contact list row,
 * every time, and -redisplayItem: therefore redrew nothing: measured, ninety-five announcements in
 * three minutes and not one row found. Single row redraws had never worked. What kept the list
 * looking correct was the delayed update timer, which repaints everything, so changes appeared
 * whenever it next came around and looked like an arbitrary delay of up to a minute.
 */
- (BOOL)isEqual:(id)inObject
{
	if (inObject == self)
		return YES;

	return [[self listObject] isEqual:inObject];
}

/*!
 * @brief Hash as the object we answer for
 *
 * Equal objects must hash alike, and this one reports itself equal to its list object. Inherited
 * NSObject hashing broke that the moment -isEqual: was overridden, which is what leaves an object
 * findable by pointer and unfindable by lookup.
 */
- (NSUInteger)hash
{
	return [[self listObject] hash];
}

- (id)forwardingTargetForSelector:(SEL)aSelector
{
	return [self listObject];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<AIProxyListObject %p -> %@>", self, [self listObject]];
}

@end
