//
//  AXCIconPackEntry.m
//  XtrasCreator
//
//  Created by Mac-arena the Bored Zo on 2005-10-30.
//  Copyright 2005 Adium Team. All rights reserved.
//

#import "AXCIconPackEntry.h"

@implementation AXCIconPackEntry

+ (id) entryWithKey:(NSString *)newKey path:(NSString *)newPath
{
	return [[[self alloc] initWithKey:newKey path:newPath] autorelease];
}

- (id) initWithKey:(NSString *)newKey path:(NSString *)newPath
{
	if((self = [super init])) {
		key = [newKey copy];
		displayName = [newKey copy];
		path = [newPath copy];
		supported = YES;
	}
	return self;
}

#pragma mark -

- (NSString *) key
{
	return key;
}

- (NSString *) displayName
{
	return displayName;
}
- (void) setDisplayName:(NSString *)newDisplayName
{
	[displayName release];
	displayName = [newDisplayName copy];
}

- (BOOL) isSupported
{
	return supported;
}
- (void) setSupported:(BOOL)isSupported
{
	supported = isSupported;
}

- (NSString *) path
{
	return path;
}
- (void) setPath:(NSString *)newPath
{
	[path release];
	path = [newPath copy];
}

#pragma mark -

- (void) dealloc
{
	[key release];
	[path release];
	[displayName release];

	[super dealloc];
}

- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %p key:%@ path:%@>", [self class], self, key, path];
}

@end
