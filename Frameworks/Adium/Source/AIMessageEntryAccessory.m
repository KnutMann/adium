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

#import "AIMessageEntryAccessory.h"
#import <Adium/AISharedAdium.h>
#import <Adium/AIPreferenceControllerProtocol.h>

@interface AIMessageEntryAccessory ()
@property (readwrite, nonatomic, copy) NSString *identifier;
@property (readwrite, nonatomic, copy) NSString *label;
@property (readwrite, nonatomic, copy) NSString *toolTip;
@property (readwrite, nonatomic, strong) NSImage *image;
@property (readwrite, nonatomic, copy) NSString *preferenceKey;
@property (readwrite, nonatomic, copy) NSString *preferenceGroup;
@property (readwrite, nonatomic, weak) id target;
@property (readwrite, nonatomic) SEL action;
@end

@implementation AIMessageEntryAccessory

/* One list for the whole program. Features register at launch, long before a message
 * field exists, so nobody has to be told when the list changes. */
static NSMutableArray *registeredAccessories = nil;

+ (instancetype)accessoryWithIdentifier:(NSString *)identifier
								  label:(NSString *)label
								toolTip:(NSString *)toolTip
								  image:(NSImage *)image
						  preferenceKey:(NSString *)preferenceKey
								  group:(NSString *)preferenceGroup
								 target:(id)target
								 action:(SEL)action
{
	AIMessageEntryAccessory *accessory = [[self alloc] init];

	accessory.identifier = identifier;
	accessory.label = label;
	accessory.toolTip = toolTip;
	accessory.image = image;
	accessory.preferenceKey = preferenceKey;
	accessory.preferenceGroup = preferenceGroup;
	accessory.target = target;
	accessory.action = action;

	return accessory;
}

- (BOOL)isEnabled
{
	return [[adium.preferenceController preferenceForKey:self.preferenceKey group:self.preferenceGroup] boolValue];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %@ (%@ in %@)>", NSStringFromClass([self class]), self.identifier, self.preferenceKey, self.preferenceGroup];
}

#pragma mark The list

+ (void)registerAccessory:(AIMessageEntryAccessory *)accessory
{
	if (!accessory.identifier || !accessory.preferenceKey || !accessory.preferenceGroup) {
		NSLog(@"AIMessageEntryAccessory: %@ is missing its identifier or preference and was not registered", accessory);
		return;
	}

	if (!registeredAccessories) registeredAccessories = [[NSMutableArray alloc] init];

	//Registered twice is the same button twice; the newer description wins the place of the older
	[self unregisterAccessoryWithIdentifier:accessory.identifier];
	[registeredAccessories addObject:accessory];
}

+ (void)unregisterAccessoryWithIdentifier:(NSString *)identifier
{
	for (AIMessageEntryAccessory *accessory in [registeredAccessories copy]) {
		if ([accessory.identifier isEqualToString:identifier])
			[registeredAccessories removeObject:accessory];
	}
}

+ (NSArray *)registeredAccessories
{
	return (registeredAccessories ? [registeredAccessories copy] : @[]);
}

+ (NSArray *)enabledAccessories
{
	NSMutableArray *enabled = [NSMutableArray array];

	for (AIMessageEntryAccessory *accessory in registeredAccessories) {
		if (accessory.enabled) [enabled addObject:accessory];
	}

	return enabled;
}

+ (NSSet *)preferenceGroups
{
	NSMutableSet *groups = [NSMutableSet set];

	for (AIMessageEntryAccessory *accessory in registeredAccessories) {
		[groups addObject:accessory.preferenceGroup];
	}

	return groups;
}

@end

#pragma mark -

@interface AIMessageEntryAccessoryButton ()
@property (readwrite, nonatomic, strong) AIMessageEntryAccessory *accessory;
@end

@implementation AIMessageEntryAccessoryButton

/*!
 * @brief A borderless picture button the size of its picture
 *
 * The same button the smiley was: no border, the picture drawn at its own size, an arrow
 * cursor over it rather than the text cursor of the field it stands in, and a darkened
 * copy of the picture for while the mouse is down.
 */
- (instancetype)initWithAccessory:(AIMessageEntryAccessory *)accessory
{
	NSImage *image = accessory.image;

	if (!(self = [super initWithFrame:NSMakeRect(0, 0, image.size.width, image.size.height)]))
		return nil;

	self.accessory = accessory;

	[self setAutoresizingMask:NSViewMinXMargin];
	[self setButtonType:NSButtonTypeMomentaryChange];
	[self setCursor:[NSCursor arrowCursor]];
	[self setBordered:NO];
	[self setToolTip:accessory.toolTip];
	[self setTarget:accessory.target];
	[self setAction:accessory.action];
	[[self cell] setImageScaling:NSImageScaleNone];
	[self setImage:image];

	if (image) {
		NSImage *pressed = [image copy];
		[pressed lockFocus];
		[image drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositingOperationPlusDarker fraction:0.5f];
		[pressed unlockFocus];
		[self setAlternateImage:pressed];
	}

	return self;
}

@end
