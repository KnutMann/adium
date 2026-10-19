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

/*
	Delegate method:
		- (void)mutableOwnerArray:(AIMutableOwnerArray *)inArray didSetObject:(id)anObject withOwner:(id)inOwner priorityLevel:(float)priority
*/

#import "AIMutableOwnerArray.h"

@interface AIMutableOwnerArray ()
- (id)_objectWithHighestPriority;
- (void)_moveObjectToFront:(int)objectIndex;
- (void)_createArrays;
- (void)_destroyArrays;
- (void)mutableOwnerArray:(AIMutableOwnerArray *)mutableOwnerArray didSetObject:(id)anObject withOwner:(id)inOwner;
@end

@implementation AIMutableOwnerArray

//Init
- (id)init
{
	if ((self = [super init])) {
		contentArray = nil;
		ownerArray = nil;
		priorityArray = nil;
		valueIsSortedToFront = NO;
		delegate = nil;
	}

	return self;
}

//Dealloc
- (void)dealloc
{
	/* Stays: _destroyArrays is the real teardown and it does more than let go of the arrays. */
	delegate = nil;

	[self _destroyArrays];
}


- (NSString *)description
{
	NSMutableString	*desc = [[NSMutableString alloc] initWithFormat:@"<%@: %p: ", NSStringFromClass([self class]), self];
	NSUInteger	i = 0;
	
	for (id object in self) {
		[desc appendFormat:@"(%@:%@:%@)%@", [ownerArray objectAtIndex:i], object, [priorityArray objectAtIndex:i], (object == [contentArray lastObject] ? @"" : @", ")];
		i++;
	}
	[desc appendString:@">"];
	
	return desc;
}


//Value Storage --------------------------------------------------------------------------------------------------------
#pragma mark Value Storage

- (void)setObject:(id)anObject withOwner:(id)inOwner
{
	[self setObject:anObject withOwner:inOwner priorityLevel:Medium_Priority];
}

- (void)setObject:(id)anObject withOwner:(id)inOwner priorityLevel:(float)priority
{
    NSUInteger	ownerIndex;
	//Keep priority in bounds
	if ((priority < Highest_Priority) || (priority > Lowest_Priority)) priority = Medium_Priority;

	//Remove any existing objects from this owner
	ownerIndex = [ownerArray indexOfObject:inOwner];
	if (ownerArray && (ownerIndex != NSNotFound)) {
		[ownerArray removeObjectAtIndex:ownerIndex];
		[contentArray removeObjectAtIndex:ownerIndex];
		[priorityArray removeObjectAtIndex:ownerIndex];
	}
	
	//Add the new object
	if (anObject) {
		//If we haven't created arrays yet, do so now
		if (!ownerArray) [self _createArrays];
		
		//Add the object
		[ownerArray addObject:inOwner];
		[contentArray addObject:anObject];
		[priorityArray addObject:[NSNumber numberWithFloat:priority]];
	}

	//Our array may no longer have the return value sorted to the front, clear this flag so it can be sorted again
	valueIsSortedToFront = NO;
	
	if (delegate && delegateRespondsToDidSetObjectWithOwnerPriorityLevel) {
		[delegate mutableOwnerArray:self didSetObject:anObject withOwner:inOwner priorityLevel:priority];
	}	
}

//The method the delegate would implement, here to make the compiler happy.
- (void)mutableOwnerArray:(AIMutableOwnerArray *)mutableOwnerArray didSetObject:(id)anObject withOwner:(id)inOwner {};

//Value Retrieval ------------------------------------------------------------------------------------------------------
#pragma mark Value Retrieval

- (id)objectValue
{
    return ((ownerArray && [ownerArray count]) ? [self _objectWithHighestPriority] : nil);
}

/* The searches below start from the first object, not from 0: a set of negative numbers has a greatest member too,
 * and 0 would have won over all of them with an answer that is not even in the array.
 *
 * They also leave the arrays in the order they found them. Only the priority search moves its winner to the front,
 * and valueIsSortedToFront says that it has; when the number and date searches did the same with theirs, one flag
 * stood for several orders, and whichever search ran first decided what the others answered. The arrays are small,
 * one object per owner, so finding the greatest value each time costs nothing worth a cache. */
- (NSNumber *)numberValue
{
	NSUInteger count;
	if (ownerArray && (count = [ownerArray count])) {
		NSNumber	*currentMax = [contentArray objectAtIndex:0];
		NSUInteger	idx;

		//Find the object with the largest value
		for (idx = 1; idx < count; idx++) {
			NSNumber	*value = [contentArray objectAtIndex:idx];

			if ([value compare:currentMax] == NSOrderedDescending) {
				currentMax = value;
			}
		}

		return currentMax;
	}
	return nil;
}

- (NSInteger)intValue
{
	NSUInteger count;
	if (ownerArray && (count = [ownerArray count])) {
		NSInteger	currentMax = [[contentArray objectAtIndex:0] integerValue];
		NSUInteger	idx;

		//Find the object with the largest int value
		for (idx = 1; idx < count; idx++) {
			NSInteger	value = [[contentArray objectAtIndex:idx] integerValue];

			if (value > currentMax) {
				currentMax = value;
			}
		}

		return currentMax;
	}
	return 0;
}

- (double)doubleValue
{
	NSUInteger count;
	if (ownerArray && (count = [ownerArray count])) {
		double		currentMax = [[contentArray objectAtIndex:0] doubleValue];
		NSUInteger	idx;

		//Find the object with the largest double value
		for (idx = 1; idx < count; idx++) {
			double	value = [[contentArray objectAtIndex:idx] doubleValue];

			if (value > currentMax) {
				currentMax = value;
			}
		}

		return currentMax;
	}

	return 0;
}

- (NSDate *)date
{
	NSUInteger count;
	if (ownerArray && (count = [ownerArray count])) {
		NSDate		*currentMax = [contentArray objectAtIndex:0];
		NSUInteger	idx;

		//Find the object with the earliest date
		for (idx = 1; idx < count; idx++) {
			NSDate	*value = [contentArray objectAtIndex:idx];

			if ([currentMax timeIntervalSinceDate:value] > 0) {
				currentMax = value;
			}
		}

		return currentMax;
	}
	return nil;
}

- (id)_objectWithHighestPriority
{
	//If we have more than one object and the object we want is not already in the front of our arrays, 
	//we need to find the object with highest priority and move it to the front
	if ([priorityArray count] != 1 && !valueIsSortedToFront) {
		CGFloat			currentMax = Lowest_Priority;
		int				indexOfMax = 0;
		int				idx = 0;
		
		//Find the object with highest priority
		for (NSNumber *priority in priorityArray) {
			float	value = [priority floatValue];
			if (value < currentMax) {
				currentMax = value;
				indexOfMax = idx;
			}
			idx++;
		}

		//Move the object to the front, so we don't have to find it next time
		[self _moveObjectToFront:indexOfMax];
	}

	return [contentArray objectAtIndex:0]; 
}

//Move an object to the front of our arrays
- (void)_moveObjectToFront:(int)objectIndex
{
	if (objectIndex != 0) {
		[contentArray exchangeObjectAtIndex:objectIndex withObjectAtIndex:0];
		[ownerArray exchangeObjectAtIndex:objectIndex withObjectAtIndex:0];
		[priorityArray exchangeObjectAtIndex:objectIndex withObjectAtIndex:0];
	}
	valueIsSortedToFront = YES;
}


//Returns an object with the specified owner
- (id)objectWithOwner:(id)inOwner
{
    if (ownerArray && contentArray) {
        NSUInteger	idx = [ownerArray indexOfObject:inOwner];
        if (idx != NSNotFound) return [contentArray objectAtIndex:idx];
    }
    
    return nil;
}

- (float)priorityOfObjectWithOwner:(id)inOwner
{
	if (ownerArray && priorityArray) {
        NSUInteger	idx = [ownerArray indexOfObject:inOwner];
		if (idx != NSNotFound) return [[priorityArray objectAtIndex:idx] floatValue];
	}
	return 0.0f;
}

- (id)ownerWithObject:(id)inObject
{
	id			bestOwner = nil;
	float		bestPriority = Lowest_Priority;
	NSUInteger	idx = 0;

	//Several owners may own equal objects; the header promises the one with the highest priority, which is the
	//smallest number: Highest_Priority is 0.
	for (id object in contentArray) {
		float priority = [[priorityArray objectAtIndex:idx] floatValue];

		if ([object isEqual:inObject] && (!bestOwner || priority < bestPriority)) {
			bestOwner = [ownerArray objectAtIndex:idx];
			bestPriority = priority;
		}
		idx++;
	}

    return bestOwner;
}

- (float)priorityOfObject:(id)inObject
{
	if (contentArray && priorityArray) {
        NSUInteger	idx = [contentArray indexOfObject:inObject];
		if (idx != NSNotFound) return [[priorityArray objectAtIndex:idx] floatValue];
	}
	return 0.0f;
}

- (NSEnumerator *)objectEnumerator
{
	return [contentArray objectEnumerator];
}

@synthesize allValues = contentArray;

- (NSUInteger)count
{
    return [contentArray count];
}

//Array creation / Destruction -----------------------------------------------------------------------------------------
#pragma mark Array creation / Destruction
//We don't actually create our arrays until needed.  There are many places where a mutable owner array
//is created and not actually used to store anything, so this saves us a bit of ram.
//Create our storage arrays
- (void)_createArrays
{
	contentArray = [[NSMutableArray alloc] init];
	priorityArray = [[NSMutableArray alloc] init];
	ownerArray = [[NSMutableArray alloc] init];
}

//Destroy our storage arrays
- (void)_destroyArrays
{
	contentArray = nil;
	priorityArray = nil;
	ownerArray = nil;
}

//Delegation -----------------------------------------------------------------------------------------
#pragma mark Delegation
- (void)setDelegate:(id)inDelegate
{
	delegate = inDelegate;
	
	delegateRespondsToDidSetObjectWithOwnerPriorityLevel = [delegate respondsToSelector:@selector(mutableOwnerArray:didSetObject:withOwner:priorityLevel:)];
}

- (id)delegate
{
	return delegate;
}

/* The buffer is unretained by contract. Left unqualified it is taken for an out parameter and
 * assumed to be autoreleasing, which does not match what fast enumeration hands over. */
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(__unsafe_unretained id *)stackbuf count:(NSUInteger)len;
{
	return [contentArray countByEnumeratingWithState:state objects:stackbuf count:len];
}

@end
