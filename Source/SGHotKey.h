//
//  SGHotKey.h
//  SGHotKeyCenter
//
//  Created by Justin Williams on 7/26/09.
//  Copyright 2009 Second Gear. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "SGKeyCombo.h"

@interface SGHotKey : NSObject {
  NSString *identifier;
  NSString *name;
  
  SGKeyCombo *keyCombo;
  __unsafe_unretained id target;	//A hot key is never an owner of what it fires at
  SEL action;
  
  EventHotKeyID hotKeyID;
}

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, retain) SGKeyCombo *keyCombo;
@property (nonatomic, assign) id target;
@property (nonatomic, assign) SEL action;
@property (nonatomic, assign) EventHotKeyID hotKeyID;

- (id)initWithIdentifier:(id)theIdentifier keyCombo:(SGKeyCombo *)theCombo;
- (id)initWithIdentifier:(id)theIdentifier keyCombo:(SGKeyCombo *)theCombo target:(id)theTarget action:(SEL)theAction;
- (BOOL)matchesHotKeyID:(EventHotKeyID)theKeyID;
- (void)invoke;

@end
