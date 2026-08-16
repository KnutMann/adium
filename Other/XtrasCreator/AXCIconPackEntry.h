//
//  AXCIconPackEntry.h
//  XtrasCreator
//
//  Created by Mac-arena the Bored Zo on 2005-10-30.
//  Copyright 2005 Adium Team. All rights reserved.
//

@interface AXCIconPackEntry : NSObject {
	NSString *key, *path, *displayName;
	BOOL supported;
}

+ (id) entryWithKey:(NSString *)newKey path:(NSString *)newPath;
- (id) initWithKey:(NSString *)newKey path:(NSString *)newPath;

- (NSString *) key;

//The key is written to Icons.plist. The display name may add UI-only context.
- (NSString *) displayName;
- (void) setDisplayName:(NSString *)newDisplayName;

- (BOOL) isSupported;
- (void) setSupported:(BOOL)isSupported;

- (NSString *) path;
- (void) setPath:(NSString *)newPath;

@end
