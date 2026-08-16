//
//	NSMutableArrayAdditions.m
//	Growl
//
//	Created by Mac-arena the Bored Zo on 2005-09-12.
//  Copyright 2005 The Growl Project. All rights reserved.
//
// This file is under the BSD License, refer to License.txt for details

#import "NSMutableArrayAdditions.h"
static inline NSComparisonResult compareObjectsWithSelector(id a, id b, SEL cmd);

@implementation NSMutableArray (NSMutableArrayAdditions)

- (NSUInteger) indexForInsortingObject:(id)obj usingSelector:(SEL)compareCmd {
	NSUInteger lowerBound = 0U;
	NSUInteger upperBound = [self count];

	while (lowerBound < upperBound) {
		NSUInteger index = lowerBound + ((upperBound - lowerBound) / 2U);
		NSComparisonResult comparison = compareObjectsWithSelector(obj, [self objectAtIndex:index], compareCmd);
		if (comparison == NSOrderedSame)
			return index;
		if (comparison == NSOrderedAscending)
			upperBound = index;
		else
			lowerBound = index + 1U;
	}

	return lowerBound;
}

@end

static inline NSComparisonResult compareObjectsWithSelector(id a, id b, SEL cmd) {
	typedef NSComparisonResult (*ComparisonIMP)(id, SEL, id);
	ComparisonIMP comparison = (ComparisonIMP)[a methodForSelector:cmd];
	return comparison(a, cmd, b);
}
