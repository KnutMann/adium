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

#import <Adium/AIStatusGroup.h>
#import <Adium/AIStatus.h>
#import <Adium/AIStatusControllerProtocol.h>

@implementation AIStatusGroup

NSComparisonResult statusArraySort(id objectA, id objectB, void *context);

+ (id)statusGroup
{
	return [[[self alloc] init] autorelease];
}

+ (id)statusGroupWithContainedStatusItems:(NSArray *)inContainedObjects
{
	AIStatusGroup *statusGroup = [self statusGroup];
	[statusGroup setContainedStatusItems:inContainedObjects];

	//Let 'em know where they stand
	[inContainedObjects makeObjectsPerformSelector:@selector(setContainingStatusGroup:)
										withObject:statusGroup];

	return statusGroup;
}

- (id)init
{
	if ((self = [super init])) {
		containedStatusItems = [[NSMutableArray alloc] init];
		_flatStatusSet = nil;
	}
	
	return self;
}

- (void)dealloc
{
	[containedStatusItems release];
	[_flatStatusSet release];

	[super dealloc];
}

/*!
 * @brief Encode with Coder
 */
- (void)encodeWithCoder:(NSCoder *)encoder
{
	[super encodeWithCoder:encoder];

	if ([encoder allowsKeyedCoding]) {
        [encoder encodeObject:containedStatusItems forKey:@"ContainedStatusItems"];

    } else {
        [encoder encodeObject:containedStatusItems];
    }
}

/*!
* @brief Initialize with coder
 */
- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder]))
	{
		if ([decoder allowsKeyedCoding]) {
			//Can decode keys in any order		
			containedStatusItems = [[decoder decodeObjectForKey:@"ContainedStatusItems"] mutableCopy];

			//Let 'em know where they stand
			[containedStatusItems makeObjectsPerformSelector:@selector(setContainingStatusGroup:)
												  withObject:self];

		} else {
			//Must decode keys in same order as encodeWithCoder:		
			containedStatusItems = [[decoder decodeObject] mutableCopy];
		}

		if (!containedStatusItems) containedStatusItems = [[NSMutableArray alloc] init];
	}
	
	return self;
}

#pragma mark Access to contents
- (NSSet *)flatStatusSet
{
	if (!_flatStatusSet) {
		_flatStatusSet = [[NSMutableSet alloc] init];
		
		/* Nothing but statuses can be in here. A group decoded from an older archive is dissolved
		 * by -[AIStatusController rootStateGroup] right after decoding, which is long before anyone
		 * asks for this set for the first time. */
		for (id statusItem in containedStatusItems) {
			if ([statusItem isKindOfClass:[AIStatus class]]) {
				[_flatStatusSet addObject:(AIStatus *)statusItem];
			}
		}
	}
	
	return _flatStatusSet;
}

- (NSArray *)containedStatusItems
{
	return containedStatusItems;
}

#pragma mark Modifying contents
- (void)setContainedStatusItems:(NSArray *)inContainedStatusItems
{
	if (containedStatusItems != inContainedStatusItems) {
		[containedStatusItems release];
		containedStatusItems = [inContainedStatusItems mutableCopy];

		//Everything the flat set was built from is gone; it is rebuilt from the new contents on demand
		[_flatStatusSet release]; _flatStatusSet = nil;
	}
}

/*!
 * @brief Our contents changed
 *
 * The root has no containing group, so every change lands at the status controller - and that is
 * the write to disk. Anything which changes what is in here has to come through this method, or the
 * change is only in memory until Adium is quit.
 */
- (void)containedStatusesChanged
{
	[adium.statusController savedStatusesChanged];
}

#pragma mark -

/*!
 * @brief Add a status item to this group
 *
 * @param inStatusItem The item to add
 * @param index The index at which to add it, or -1 to add it at the end
 */
- (void)addStatusItem:(AIStatusItem *)inStatusItem atIndex:(NSUInteger)idx
{
	if (idx != NSNotFound && idx < [containedStatusItems count]) {
		[containedStatusItems insertObject:inStatusItem atIndex:idx];
	} else {
		[containedStatusItems addObject:inStatusItem];		
	}

	[inStatusItem setContainingStatusGroup:self];

	/* Keep the flat set in step, but only if there is one: a nil set means nobody has asked yet, and
	 * building one here would leave a set holding this one status and nothing else - which -flatStatusSet
	 * would then hand out as complete. Nil stays nil so the lazy build stays the single source. */
	if (_flatStatusSet && [inStatusItem isKindOfClass:[AIStatus class]]) {
		[_flatStatusSet addObject:(AIStatus *)inStatusItem];
	}

	[self containedStatusesChanged];
}

- (void)removeStatusItem:(AIStatusItem *)inStatusItem
{
	[containedStatusItems removeObjectIdenticalTo:inStatusItem];

	//Remove this item from our flat status set
	if ([inStatusItem isKindOfClass:[AIStatus class]]) {
		[_flatStatusSet removeObject:(AIStatus *)inStatusItem];
	}

	[self containedStatusesChanged];
}

/*!
* @brief Replace a state
 *
 * Replace a state in Adium's state array with another state.
 *
 * @param oldStatusState AIStatus state that is in Adium's state array
 * @param newStatusState AIStatus state with which to replace oldState
 */
- (void)replaceExistingStatusState:(AIStatus *)oldStatusState withStatusState:(AIStatus *)newStatusState
{
	if (oldStatusState != newStatusState) {
		NSUInteger idx = [containedStatusItems indexOfObject:oldStatusState];

		if (idx != NSNotFound && idx < [containedStatusItems count]) {
			[containedStatusItems replaceObjectAtIndex:idx withObject:newStatusState];
		}

		/* The flat set has to be swapped too, and this is the place which used to forget it: an edit
		 * hands the new status the old one's unique ID, so -statusStateWithUniqueStatusID: searching
		 * a stale set went on answering with the status as it read before the edit - and an automatic
		 * status, which knows nothing but that ID, went on setting that. */
		if (_flatStatusSet) {
			[_flatStatusSet removeObject:oldStatusState];

			if ([newStatusState isKindOfClass:[AIStatus class]]) {
				[_flatStatusSet addObject:newStatusState];
			}
		}

		[newStatusState setContainingStatusGroup:self];

		[self containedStatusesChanged];
	}
}

#pragma mark Sorting
//Sort the status array
NSComparisonResult statusArraySort(id objectA, id objectB, void *context)
{
	AIStatusType statusTypeA = [objectA statusType];
	AIStatusType statusTypeB = [objectB statusType];
	
	//We treat Invisible statuses as being the same as Away for purposes of the menu
	if (statusTypeA == AIInvisibleStatusType) statusTypeA = AIAwayStatusType;
	if (statusTypeB == AIInvisibleStatusType) statusTypeB = AIAwayStatusType;
	
	if (statusTypeA > statusTypeB) {
		return NSOrderedDescending;
	} else if (statusTypeB > statusTypeA) {
		return NSOrderedAscending;
	} else {
		AIStatusMutabilityType	mutabilityTypeA = [objectA mutabilityType];
		AIStatusMutabilityType	mutabilityTypeB = [objectB mutabilityType];
		BOOL					isLockedMutabilityTypeA = (mutabilityTypeA == AILockedStatusState);
		BOOL					isLockedMutabilityTypeB = (mutabilityTypeB == AILockedStatusState);
		
		//Put locked (built in) statuses at the top
		if (isLockedMutabilityTypeA && !isLockedMutabilityTypeB) {
			return NSOrderedAscending;
			
		} else if (!isLockedMutabilityTypeA && isLockedMutabilityTypeB) {
			return NSOrderedDescending;
			
		} else {
			/* Check to see if either is temporary; temporary items go above saved ones and below
			* built-in ones.
			*/
			BOOL	isTemporaryA = (mutabilityTypeA == AITemporaryEditableStatusState);
			BOOL	isTemporaryB = (mutabilityTypeB == AITemporaryEditableStatusState);
			
			if (isTemporaryA && !isTemporaryB) {
				return NSOrderedAscending;
				
			} else if (isTemporaryB && !isTemporaryA) {
				return NSOrderedDescending;
				
			} else {
				BOOL	isSecondaryMutabilityTypeA = (mutabilityTypeA == AISecondaryLockedStatusState);
				BOOL	isSecondaryMutabilityTypeB = (mutabilityTypeB == AISecondaryLockedStatusState);
				
				//Put secondary locked statuses at the bottom
				if (isSecondaryMutabilityTypeA && !isSecondaryMutabilityTypeB) {
					return NSOrderedDescending;
					
				} else if (!isSecondaryMutabilityTypeA && isSecondaryMutabilityTypeB) {
					return NSOrderedAscending;
					
				} else {
					NSArray	*originalArray = (NSArray *)context;
					
					//Return them in the same relative order as the original array if they are of the same type
					NSUInteger indexA = [originalArray indexOfObjectIdenticalTo:objectA];
					NSUInteger indexB = [originalArray indexOfObjectIdenticalTo:objectB];
					
					if (indexA > indexB) {
						return NSOrderedDescending;
					} else {
						return NSOrderedAscending;
					}
				}
			}
		}
	}
}

+ (void)sortArrayOfStatusItems:(NSMutableArray *)inArray context:(void *)context
{
	[inArray sortUsingFunction:statusArraySort context:context];	
}

@end
