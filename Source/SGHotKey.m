//
//  SGHotKey.m
//  SGHotKeyCenter
//
//  Created by Justin Williams on 7/26/09.
//  Copyright 2009 Second Gear. All rights reserved.
//

#import "SGHotKey.h"
#import "SGKeyCombo.h"

@implementation SGHotKey

@synthesize identifier;
@synthesize name;
@synthesize keyCombo;
@synthesize target;
@synthesize action;
@synthesize hotKeyID;

- (id)init {
  return [self initWithIdentifier:nil keyCombo:nil];
}

- (id)initWithIdentifier:(id)theIdentifier keyCombo:(SGKeyCombo *)theCombo {
  if ((self = [super init])) {
    self.identifier = theIdentifier;
    self.keyCombo = theCombo;
  }
  
  return self;  
}
- (id)initWithIdentifier:(id)theIdentifier keyCombo:(SGKeyCombo *)theCombo target:(id)theTarget action:(SEL)theAction {
  if ((self = [super init])) {
    self.identifier = theIdentifier;
    self.keyCombo = theCombo;
    self.target = theTarget;
    self.action = theAction;
  }
  
  return self;
}

- (BOOL)matchesHotKeyID:(EventHotKeyID)theKeyID {
  return (hotKeyID.id == theKeyID.id) && (hotKeyID.signature == theKeyID.signature);
}

- (void)invoke {
  /* A target/action pair, which returns nothing that could leak. */
  #pragma clang diagnostic push
  #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  [self.target performSelector:self.action withObject:self];
  #pragma clang diagnostic pop
}

- (void)setKeyCombo:(SGKeyCombo *)theKeyCombo {
  if (theKeyCombo == nil)
    theKeyCombo = [SGKeyCombo clearKeyCombo];
  
  keyCombo = theKeyCombo;
}

- (NSString *)description {
	return [NSString stringWithFormat: @"<%@: %@, %@>", 
					NSStringFromClass([self class]), 
					self.identifier, 
					self.keyCombo];
}


@end
