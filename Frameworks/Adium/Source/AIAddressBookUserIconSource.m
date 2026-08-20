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

#import "AIAddressBookUserIconSource.h"
#import "AIAddressBookController.h"
#import <Adium/AIUserIcons.h>
#import <Adium/AIMetaContact.h>
#import <AIUtilities/AIImageDrawingAdditions.h>

@implementation AIAddressBookUserIconSource

/*!
 * @brief Where the picture fetches run
 *
 * One serial queue for all of them: card pictures come off the local store, so
 * the win is not parallelism but keeping the main thread out of it.
 */
static dispatch_queue_t AIAddressBookImageQueue(void)
{
	static dispatch_queue_t queue = NULL;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		queue = dispatch_queue_create("im.adium.addressbook.images", DISPATCH_QUEUE_SERIAL);
	});
	return queue;
}

- (id)init
{
	if ((self = [super init])) {
		pendingObjectsByUniqueId = [[NSMutableDictionary alloc] init];
		priority = AIUserIconLowPriority;

		[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_ADDRESSBOOK];
	}

	return self;
}

- (void)dealloc
{
	[adium.preferenceController unregisterPreferenceObserver:self];
}

/*!
 * @brief AIUserIcons wants this source to update its user icon for an object
 *
 * The picture is fetched off the main thread; one fetch serves every object
 * waiting on the same card.
 *
 * @result An AIUserIconSourceQueryResult indicating the result
 */
- (AIUserIconSourceQueryResult)updateUserIconForObject:(AIListObject *)inObject
{
	if (!useABImages)
		return AIUserIconSourceDidNotFindIcon;

	AIAddressBookPerson *person = [AIAddressBookController personForListObject:inObject];

	if (!person)
		return AIUserIconSourceDidNotFindIcon;

	/* Some mild complexity here. If inObject is a metacontact, we should only proceed if
	 * none of its contained contacts have a higher-priority user icon than we will be.
	 * This prevents a metacontact-associated address book image from overriding a serverside
	 * contained-contact image if that isn't the sort of thing that the user might be into.
	 */
	if ([inObject isKindOfClass:[AIMetaContact class]]) {
		for (AIListContact *listContact in ((AIMetaContact *)inObject).uniqueContainedObjects) {
			if (![AIUserIcons userIconSource:self changeWouldBeRelevantForObject:listContact])
				return AIUserIconSourceDidNotFindIcon;
		}
	}

	NSString		*uniqueId = person.uniqueId;
	NSMutableSet	*waiting = [pendingObjectsByUniqueId objectForKey:uniqueId];

	if (waiting) {
		//A fetch for this card is already on its way; join it
		[waiting addObject:inObject];
		return AIUserIconSourceLookingUpIconAsynchronously;
	}

	[pendingObjectsByUniqueId setObject:[NSMutableSet setWithObject:inObject]
								 forKey:uniqueId];

	dispatch_async(AIAddressBookImageQueue(), ^{
		NSData *imageData = [person imageData];

		dispatch_async(dispatch_get_main_queue(), ^{
			[self deliverImageData:imageData forUniqueId:uniqueId];
		});
	});

	return AIUserIconSourceLookingUpIconAsynchronously;
}

/*!
 * @brief A picture arrived (or turned out not to exist); hand it to everyone waiting
 */
- (void)deliverImageData:(NSData *)imageData forUniqueId:(NSString *)uniqueId
{
	NSSet *waiting = [pendingObjectsByUniqueId objectForKey:uniqueId];
	[pendingObjectsByUniqueId removeObjectForKey:uniqueId];

	if (!useABImages || ![waiting count])
		return;

	NSImage *image = (imageData ? [[NSImage alloc] initWithData:imageData] : nil);

	//Address book can feed us giant images, which we really don't want to keep around
	if (image) {
		NSSize size = [image size];
		if (size.width > 96 || size.height > 96)
			image = [image imageByScalingToSize:NSMakeSize(96, 96)];
	}

	for (AIListObject *listObject in waiting) {
		[AIUserIcons userIconSource:self
			   didDetermineUserIcon:image
					 asynchronously:YES
						  forObject:listObject];
	}
}

/*!
 * @brief The priority at which this source should be used. See the #defines in AIUserIcons.h for posible values.
 */
- (AIUserIconPriority)priority
{
	return priority;
}

#pragma mark -

- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	if (object) {
		[AIUserIcons userIconSource:self didChangeForObject:object];

	} else {
		AIUserIconPriority oldPriority = priority;
		BOOL oldUseABImages = useABImages;

		preferAddressBookImages = [[prefDict objectForKey:KEY_AB_PREFER_ADDRESS_BOOK_IMAGES] boolValue];
		useABImages = [[prefDict objectForKey:KEY_AB_USE_IMAGES] boolValue];

		priority = (preferAddressBookImages ? AIUserIconHighPriority : AIUserIconLowPriority);
		if ((priority != oldPriority) || (oldUseABImages != useABImages)) {
			[AIUserIcons userIconSource:self priorityDidChange:priority fromPriority:oldPriority];
		}
	}
}

@end
