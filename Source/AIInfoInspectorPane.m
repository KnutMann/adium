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

#import "AIInfoInspectorPane.h"
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIHTMLDecoder.h>
#import <AIUtilities/AIDateFormatterAdditions.h>
#import <Contacts/Contacts.h>
#import <Adium/AIAddressBookController.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIStatusIcons.h>
#import <Adium/AIListGroup.h>
#import <Adium/AIListObject.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListBookmark.h>
#import <Adium/AIMetaContact.h>
#import <Adium/AIService.h>
#import <Adium/AIServiceIcons.h>
#import <Adium/AIContentControllerProtocol.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <AIUtilities/AITextAttributes.h>
#import "AIContactInfoImageViewWithImagePicker.h"
#import <AIUtilities/AIDelayedTextField.h>
#import <AIUtilities/AIBundleAdditions.h>

#define WIDTH_PROFILE_HEADER	 100.0f

@interface AIInfoInspectorPane ()
- (void)updateUserIcon:(AIListObject *)inObject;
- (void)updateAccountName:(AIListObject *)inObject;
- (void)updateStatusIcon:(AIListObject *)inObject;
- (void)updateAlias:(AIListObject *)inObject;
- (void)addAddressBookInfoToProfileArray:(NSMutableArray *)profileArray forContact:(AIListContact *)inContact;
- (void)addTooltipEntriesToProfileArray:(NSMutableArray *)profileArray forContact:(AIListContact *)inContact;
- (NSAttributedString *)attributedStringProfileForListObject:(AIListObject *)inObject;
- (void)updateProfile:(NSAttributedString *)infoString context:(AIListObject *)object;
- (void)setAttributedString:(NSAttributedString *)infoString intoTextView:(NSTextView *)textView;
@end

@implementation AIInfoInspectorPane

- (id) init
{
	self = [super init];
	if (self != nil) {
		//Load Bundle
		[NSBundle ai_loadNibNamed:[self nibName] owner:self];
		/* The loader hands every top level object one reference that belongs to nobody
		 * (see AIBundleAdditions.h); the outlet above already holds its own, so the stray
		 * one is given up here, once, or every closed inspector leaks its view tree. */
		if (inspectorContentView) CFRelease((__bridge CFTypeRef)inspectorContentView);
		//Register as AIListObjectObserver
		[[AIContactObserverManager sharedManager] registerListObjectObserver:self];
		//Setup for userIcon
		[userIcon setAnimates:YES];
		[userIcon setMaxSize:NSMakeSize(256,256)];
		[userIcon setDelegate:self];
		
		[aliasLabel setStringValue:AILocalizedString(@"Alias:","Label beside the field for a contact's alias in the settings tab of the Get Info window")];
	}
	return self;
}

- (void) dealloc
{
	[[AIContactObserverManager sharedManager] unregisterListObjectObserver:self];
}


-(NSView *)inspectorContentView
{
	return inspectorContentView;
}

-(NSString *)nibName
{
	return @"AIInfoInspectorPane";
}

-(void)updateForListObject:(AIListObject *)inObject
{
	[contactAlias fireImmediately];
	
	displayedObject = inObject;
	
	[self updateProfile:nil
				context:inObject];
	
	[self updateUserIcon:inObject];
	[self updateAccountName:inObject];
	[self updateStatusIcon:inObject];
	[self updateAlias:inObject];
	
	if ([inObject isKindOfClass:[AIListContact class]] && ![inObject isKindOfClass:[AIListBookmark class]]) {
		[[AIContactObserverManager sharedManager] updateListContactStatus:(AIListContact *)inObject];
		
		[profileProgress startAnimation:self];
		[profileProgress setHidden:NO];
		
		[self updateProfile:[self attributedStringProfileForListObject:inObject]
					context:inObject];
	}
}

- (void)updateUserIcon:(AIListObject *)inObject
{
	NSImage		*currentIcon;
	NSSize		userIconSize, imagePickerSize;

	//User Icon
	BOOL usingPlaceholder = ((currentIcon = [inObject userIcon]) == nil);
	if (usingPlaceholder) {
		currentIcon = [NSImage imageNamed:@"default-icon" forClass:[self class]];
	}
	[userIcon setSquareCorners:usingPlaceholder];
	
	/* NSImageScaleProportionallyDown will lock an animated GIF into a single frame.  We therefore use NSImageScaleNone if
	 * we are already at the right size or smaller than the right size; otherwise we scale proportionally to
	 * fit the frame.
	 */
	userIconSize = [currentIcon size];
	imagePickerSize = [userIcon frame].size;
	
	[userIcon setImageScaling:(((userIconSize.width <= imagePickerSize.width) && (userIconSize.height <= imagePickerSize.height)) ?
										 NSImageScaleNone :
										 NSImageScaleProportionallyDown)];
	[userIcon setImage:currentIcon];
	[userIcon setTitle:(inObject ?
								  [NSString stringWithFormat:AILocalizedString(@"%@'s Image",nil),inObject.displayName] :
								  AILocalizedString(@"Image Picker",nil))];

	//Show the reset image button if a preference is set on this object, overriding its serverside icon
	[userIcon setShowResetImageButton:([inObject preferenceForKey:KEY_USER_ICON
															group:PREF_GROUP_USERICONS] != nil)];
}

/*!
 * @brief The line under the picture, naming whoever is being looked at
 *
 * Normally the account name, because on most services that is what somebody is known by and what
 * one would type to reach them. Where the service says its names are numbers it is not: WhatsApp
 * and its like hand out machine identities, and lately not even a number but an opaque lid, which
 * tells a person nothing about who they are looking at. There the name the protocol reports is
 * shown instead, and the identity moves to the tooltip rather than disappearing.
 */
-(void)updateAccountName:(AIListObject *)inObject
{
	if(!inObject) {
		[accountName setStringValue:@""];
		[accountName setToolTip:nil];
		return;
	}

	NSString *identity = inObject.formattedUID;
	NSString *shown = identity;
	NSString *tooltip = nil;

	if (!shown) {
		shown = inObject.displayName;

	} else if (inObject.service.userNamesArePhoneNumbers &&
			   [inObject.displayName length] &&
			   ![inObject.displayName isEqualToString:identity]) {
		shown = inObject.displayName;
		tooltip = identity;
	}

	[accountName setStringValue:(shown ? shown : @"")];
	[accountName setToolTip:tooltip];
}

-(void)updateStatusIcon:(AIListObject *)inObject
{
	if([inObject isKindOfClass:[AIListGroup class]]) {
		[statusImage setHidden:YES];
	} else {
		[statusImage setHidden:NO];
		[statusImage setImage:[AIStatusIcons statusIconForListObject:inObject type:AIStatusIconList direction:AIIconNormal]];
	}
}

#define KEY_KEY		@"Key"
#define KEY_VALUE	@"Value"
#define KEY_TYPE	@"Type"

- (void)addAttributedString:(NSAttributedString *)string
					toTable:(NSTextTable *)table
						row:(NSInteger)row
						col:(NSInteger)col
					colspan:(NSInteger)colspan
					 header:(BOOL)header
					  color:(NSColor *)color
				  alignment:(NSTextAlignment)alignment
		 toAttributedString:(NSMutableAttributedString *)text
{
	NSTextTableBlock		*block = [[NSTextTableBlock alloc] initWithTable:table
														   startingRow:row
															   rowSpan:1
														startingColumn:col
															columnSpan:colspan];
	NSMutableParagraphStyle	*style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	
	NSInteger textLength = [text length];

    [block setVerticalAlignment:NSTextBlockTopAlignment];
	
    [block setWidth:5.0f type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding edge:NSMinYEdge];
    [block setWidth:5.0f type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding edge:NSMaxYEdge];
    [block setWidth:1.0f type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding edge:NSMinXEdge];
    [block setWidth:5.0f type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding edge:NSMaxXEdge];

	if (col == 0 && !header && colspan == 1) {
		[block setValue:WIDTH_PROFILE_HEADER
				   type:NSTextBlockAbsoluteValueType
		   forDimension:NSTextBlockWidth];
	}
	
    [style setTextBlocks:[NSArray arrayWithObject:block]];
	
	[style setAlignment:alignment];
	
	[text appendAttributedString:string];
	[text appendAttributedString:[NSAttributedString stringWithString:@"\n"]];
	
	if (header) {
		[text addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:13] range:NSMakeRange(textLength, [text length] - textLength)];
		[block setWidth:1.0f type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder edge:NSMaxYEdge];
		[block setBorderColor:[NSColor separatorColor]];
	} 
	
	if (color) {
		[text addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(textLength, [text length] - textLength)];
	}
    [text addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(textLength, [text length] - textLength)];

}


- (NSMutableArray *)metaContactProfileArrayForContact:(AIMetaContact *)metaContact
{
	NSMutableArray		*array = [NSMutableArray array];
	NSMutableDictionary	*addedKeysDict = [NSMutableDictionary dictionary];
	NSMutableDictionary *ownershipDict = [NSMutableDictionary dictionary];

	NSArray *contacts = metaContact.online ? metaContact.uniqueContainedObjects :
	metaContact.listContactsIncludingOfflineAccounts;
	
	for (AIListContact *listContact in contacts) {
		//If one or more contacts are online, skip offline ones
		if (metaContact.online && !listContact.online) continue;

		for (NSDictionary * __strong lineDict in listContact.profileArray) {
			NSString *key = [lineDict objectForKey:KEY_KEY];
			AIUserInfoEntryType entryType = [[lineDict objectForKey:KEY_TYPE] intValue];
			NSInteger insertionIndex = -1;
	
			switch (entryType) {
				case AIUserInfoSectionBreak:
					/* Skip double section breaks */
					if ([[[array lastObject] objectForKey:KEY_TYPE] integerValue] == AIUserInfoSectionBreak)
						continue;
					break;
				case AIUserInfoSectionHeader:
					/* Use the most recent header if we have multiple headers in a row */
					if ([[[array lastObject] objectForKey:KEY_TYPE] integerValue] == AIUserInfoSectionHeader)
						[array removeLastObject];
					break;
				case AIUserInfoLabelValuePair:
						/* No action needed */
					break;
			}
			
			if (key) {
				NSMutableSet *previousDictValuesOnThisKey = [addedKeysDict objectForKey:key];
				if (previousDictValuesOnThisKey) {
					/* If any previously added dictionary has the same key and value as the this new one, skip this new one entirely */
					NSSet *existingValues = [previousDictValuesOnThisKey valueForKeyPath:[@"nonretainedObjectValue." stringByAppendingString:KEY_VALUE]];
					if ([existingValues containsObject:[lineDict valueForKey:KEY_VALUE]])
						continue;

					for (NSValue *prevDictValue in [previousDictValuesOnThisKey copy]) {
						NSDictionary		*prevDict = [prevDictValue nonretainedObjectValue];
						NSMutableDictionary *newDict = [prevDict mutableCopy];
						AIListContact *ownerOfPrevDict = [[ownershipDict objectForKey:prevDictValue] nonretainedObjectValue];
						if (ownerOfPrevDict) {
							[newDict setObject:[NSString stringWithFormat:AILocalizedString(@"%@'s %@", nil),
												ownerOfPrevDict.formattedUID,
												key]
										forKey:KEY_KEY];
						}
						
						//Array of dicts which will be returned
						insertionIndex = [array indexOfObjectIdenticalTo:prevDict];
						[array replaceObjectAtIndex:insertionIndex
										 withObject:newDict];
						
						//Known dictionaries on this key
						[previousDictValuesOnThisKey removeObject:prevDictValue];
						[previousDictValuesOnThisKey addObject:[NSValue valueWithNonretainedObject:newDict]];

						//Ownership of new dictionary
						[ownershipDict removeObjectForKey:prevDictValue];
						[ownershipDict setObject:[NSValue valueWithNonretainedObject:newDict]
										  forKey:[NSValue valueWithNonretainedObject:ownerOfPrevDict]];
					}
					
					NSMutableDictionary *newDict = [lineDict mutableCopy];
					[newDict setObject:[NSString stringWithFormat:AILocalizedString(@"%@'s %@", "(name)'s (information type), e.g. tekjew's status"),
										listContact.formattedUID,
										key]
								forKey:KEY_KEY];
					lineDict = newDict;
					
					[previousDictValuesOnThisKey addObject:[NSValue valueWithNonretainedObject:lineDict]];

				} else {
					[addedKeysDict setObject:[NSMutableSet setWithObject:[NSValue valueWithNonretainedObject:lineDict]]
									  forKey:key];
				}
			}
			
			if (lineDict) {
				if (insertionIndex != -1) {
					//Group items with the same key together
					if ([[[array objectAtIndex:insertionIndex] objectForKey:KEY_KEY] compare:
						[lineDict objectForKey:KEY_KEY]] == NSOrderedAscending)
						insertionIndex++;

					[array insertObject:lineDict atIndex:insertionIndex];					
				} else {
					[array addObject:lineDict];
				}
				
				[ownershipDict setObject:[NSValue valueWithNonretainedObject:listContact]
								  forKey:[NSValue valueWithNonretainedObject:lineDict]];
			}
		}
	}

	return array;
}

- (void)removeDuplicateEntriesFromProfileArray:(NSMutableArray *)array
{
	NSInteger i;
	NSUInteger count = [array count];
	for (i = 0; i < (count - 1); i++) {
		NSDictionary *lineDict = [array objectAtIndex:i];
		//Look only for label/value pairs
		if ([[lineDict objectForKey:KEY_TYPE] integerValue] == AIUserInfoLabelValuePair) {
			NSInteger j;
			NSString *thisKey = [[lineDict objectForKey:KEY_KEY] lowercaseString];
			for (j = i + 1; j < count; j++) {
				NSDictionary *otherLineDict = [array objectAtIndex:j];

				if (([[otherLineDict objectForKey:KEY_TYPE] integerValue] == AIUserInfoLabelValuePair) &&
					[[[otherLineDict objectForKey:KEY_KEY] lowercaseString] isEqualToString:thisKey]) {
					/* Same key. Compare values, which may be NSString or NSAttributedString objects */
					id thisValue = [lineDict objectForKey:KEY_VALUE];
					id otherValue = [otherLineDict objectForKey:KEY_VALUE];
					
					if ([thisValue isKindOfClass:[otherValue class]]) {
						/* Same class. Compare directly. */
						if ([thisValue isEqual:otherValue]) {
							[array removeObjectAtIndex:j];
							count--;
						}
					} else {
						/* Different class. Go to NSAttributedString to compare. */
						NSAttributedString *thisAttributedValue = ([thisValue isKindOfClass:[NSAttributedString class]] ?
																   thisValue :
																   (thisValue ? [NSAttributedString stringWithString:thisValue] : nil));
						NSAttributedString *otherAttributedValue = ([otherValue isKindOfClass:[NSAttributedString class]] ?
																   otherValue :
																	(otherValue ? [NSAttributedString stringWithString:otherValue] : nil));
						if ([thisAttributedValue isEqualToAttributedString:otherAttributedValue]) {
							[array removeObjectAtIndex:j];
							count--;
						}
					}
				}					
			}
		}
	}
}

- (NSAttributedString *)attributedStringProfileForListObject:(AIListObject *)inObject
{	
	NSMutableArray *profileArray;

	// We don't know what to do for non-list contacts.
	if (![inObject isKindOfClass:[AIListContact class]]) {
		return [NSAttributedString stringWithString:@""];
	}
	
	// XXX Case out if we only have HTML (nothing currently does this)
	
	if ([inObject isKindOfClass:[AIMetaContact class]]) {
		profileArray = [self metaContactProfileArrayForContact:(AIMetaContact *)inObject];
	} else {
		profileArray = [[(AIListContact *)inObject profileArray] mutableCopy];
	}

	if (!profileArray) profileArray = [NSMutableArray array];

	[self addTooltipEntriesToProfileArray:profileArray forContact:(AIListContact *)inObject];
	[self addAddressBookInfoToProfileArray:profileArray forContact:(AIListContact *)inObject];

	// Don't do anything if we have nothing to display.
	if ([profileArray count] == 0) {
		AILogWithSignature(@"No profile array items found for %@", inObject);
		return [NSAttributedString stringWithString:@""];
	}
	
	[self removeDuplicateEntriesFromProfileArray:profileArray];
	
	// Create the table
	NSTextTable		*table = [[NSTextTable alloc] init];
	
	[table setNumberOfColumns:2];
    [table setLayoutAlgorithm:NSTextTableAutomaticLayoutAlgorithm];
    [table setHidesEmptyCells:YES];

	NSMutableAttributedString		*result = [[NSMutableAttributedString alloc] init];
	NSEnumerator					*enumerator = [profileArray objectEnumerator];
	NSDictionary					*lineDict;
	
	BOOL							shownAnyContent = NO;
	
	for (NSInteger row = 0; (lineDict = [enumerator nextObject]); row++) {
		if ([[lineDict objectForKey:KEY_TYPE] integerValue] == AIUserInfoSectionBreak && shownAnyContent == NO) {
			continue;
		}
		
		NSAttributedString *value = nil, *key = nil;
		
		if ([lineDict objectForKey:KEY_VALUE]) {
			id theValue = [lineDict objectForKey:KEY_VALUE];
			if ([theValue isKindOfClass:[NSString class]]) {
				value = [AIHTMLDecoder decodeHTML:(NSString *)theValue];
			} else if ([theValue isKindOfClass:[NSAttributedString class]]) {
				value = (NSAttributedString *)theValue;
			} else {
				NSLog(@"*** WARNING! Invalid value passed in profile array: %@", lineDict);
			}

			value = [adium.contentController filterAttributedString:value
												usingFilterType:AIFilterDisplay
													  direction:AIFilterIncoming
														context:inObject];
		}
		
		if ([lineDict objectForKey:KEY_KEY]) {
			// We don't need to filter the key.
			key = [NSAttributedString stringWithString:[[lineDict objectForKey:KEY_KEY] lowercaseString]];
		}
		
		switch ([[lineDict objectForKey:KEY_TYPE] integerValue]) {
			case AIUserInfoLabelValuePair:
				if (key) {
					[self addAttributedString:key
									  toTable:table
										  row:row
										  col:0
									  colspan:1
									   header:NO
										color:[NSColor secondaryLabelColor]
									alignment:NSTextAlignmentRight
						   toAttributedString:result];
				}
				
				if (value) {
					[self addAttributedString:value
									  toTable:table
										  row:row
										  col:(key ? 1 : 0)
									  colspan:(key ? 1 : 2) /* If there's no key, we need to fill both columns. */
									   header:NO
										color:nil
									alignment:NSTextAlignmentLeft
						   toAttributedString:result];
				}
				break;
				
			case AIUserInfoSectionHeader:
				[self addAttributedString:key
								  toTable:table
									  row:row
									  col:0
								  colspan:2
								   header:YES
									color:[NSColor labelColor]
								alignment:NSTextAlignmentLeft
					   toAttributedString:result];
				break;
				
				
			case AIUserInfoSectionBreak:
				[self addAttributedString:[NSAttributedString stringWithString:@" "]
								  toTable:table
									  row:row
									  col:0
								  colspan:2
								   header:NO
									color:[NSColor controlTextColor]
								alignment:NSTextAlignmentLeft
					   toAttributedString:result];
				break;
		}
		
		shownAnyContent = YES;
	}
	
	return result;
}

- (void)updateAlias:(AIListObject *)inObject
{
	NSString *currentAlias = nil;
	
	
	if ([inObject isKindOfClass:[AIListContact class]]) {
		AIListContact *parentContact = [(AIListContact *)inObject parentContact];
	
		currentAlias = [parentContact preferenceForKey:@"Alias"
												 group:PREF_GROUP_ALIASES];
		
		if (inObject == parentContact) {
			AILogWithSignature(@"%@: current alias %@.",
							   inObject, currentAlias);
			
		} else {
			AILogWithSignature(@"updating alias for %@; parent %@ --> current alias %@.",
							   inObject, [(AIListContact *)inObject parentContact], currentAlias);
		}
	} else {
		currentAlias = [inObject preferenceForKey:@"Alias"
											group:PREF_GROUP_ALIASES];		
	}
	
	if (!currentAlias && ![inObject.displayName isEqualToString:inObject.formattedUID]) {
		[[contactAlias cell] setPlaceholderString:inObject.displayName];
	} else {
		[[contactAlias cell] setPlaceholderString:nil];
	}
	
	//Fill in the current alias
	if (currentAlias) {
		[contactAlias setStringValue:currentAlias];
	} else {
		[contactAlias setStringValue:@""];
	}
}

- (IBAction)setAlias:(id)sender
{
	if(!displayedObject)
		return;
	
	AIListObject *contactToUpdate = displayedObject;
	
	if ([contactToUpdate isKindOfClass:[AIListContact class]]) {
		contactToUpdate = [(AIListContact *)contactToUpdate parentContact];
	}
	
	NSString *currentAlias = [contactAlias stringValue];
	[contactToUpdate setDisplayName:currentAlias];
	
	[self updateAccountName:displayedObject];
}

- (void)updateProfile:(NSAttributedString *)infoString context:(AIListObject *)object
{
	if (infoString) {
		[profileProgress stopAnimation:self];
		[profileProgress setHidden:YES];
	}
	
	[self setAttributedString:infoString intoTextView:profileView];
}

- (void)setAttributedString:(NSAttributedString *)infoString intoTextView:(NSTextView *)textView
{
	NSColor		*backgroundColor = nil;

	if (infoString && [infoString length]) {
		[[textView textStorage] setAttributedString:infoString];
		backgroundColor = [infoString attribute:AIBodyColorAttributeName
										atIndex:0
						  longestEffectiveRange:nil
										inRange:NSMakeRange(0,[infoString length])];

		/* Most profiles carry no colors at all, and a run without a foreground color is
		 * drawn black whatever the appearance — invisible on the semantic background
		 * below. Only the colorless runs get the label color; a profile that chose its
		 * colors chose its background too and keeps both.
		 */
		if (!backgroundColor) {
			NSTextStorage *storage = [textView textStorage];
			[storage enumerateAttribute:NSForegroundColorAttributeName
								inRange:NSMakeRange(0, [storage length])
								options:0
							 usingBlock:^(id color, NSRange range, BOOL *stop) {
				if (!color) [storage addAttribute:NSForegroundColorAttributeName value:[NSColor labelColor] range:range];
			}];
		}
	} else {
		[[textView textStorage] setAttributedString:[NSAttributedString stringWithString:@""]];
	}
	[textView setInsertionPointColor:(backgroundColor ? backgroundColor : [NSColor textBackgroundColor])];
	[textView setBackgroundColor:(backgroundColor ? backgroundColor : [NSColor textBackgroundColor])];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTextDidChangeNotification object:textView];
}

- (NSSet *)updateListObject:(AIListObject *)inObject keys:(NSSet *)inModifiedKeys silent:(BOOL)silent
{
	//Update if our object or an object contained by our metacontact (if applicable) was updated
	if ([displayedObject isKindOfClass:[AIMetaContact class]] &&
		((inObject != displayedObject) && ![(AIMetaContact *)displayedObject containsObject:inObject]))
		return nil;
	else if (inObject != displayedObject)
		return nil;
	
	// Update the status icon if it changes.
	if (inModifiedKeys == nil ||
		[inModifiedKeys containsObject:@"isOnline"] ||
		[inModifiedKeys containsObject:@"idleSince"] ||
		[inModifiedKeys containsObject:@"signedOff"] ||
		[inModifiedKeys containsObject:@"isMobile"] ||
		[inModifiedKeys containsObject:@"IsBlocked"] ||
		[inModifiedKeys containsObject:@"listObjectStatusType"]) {
		[self updateStatusIcon:displayedObject];
	}
	
	// Update the profile if it changes.	
	if (inModifiedKeys == nil ||
		[inModifiedKeys containsObject:@"ProfileArray"]) {
		[self updateProfile:[self attributedStringProfileForListObject:displayedObject]
					context:displayedObject];
	}
	
	// Cause everything to update if everything's probably changed.
	if ([inModifiedKeys containsObject:@"notAStranger"] ||
		[inModifiedKeys containsObject:@"serverDisplayName"]) {
		[self updateForListObject:displayedObject];
	}
	
	return nil;
}

#pragma mark AIImageViewWithImagePicker Delegate
// AIImageViewWithImagePicker Delegate ---------------------------------------------------------------------
- (void)imageViewWithImagePicker:(AIImageViewWithImagePicker *)sender didChangeToImageData:(NSData *)imageData
{
	if (displayedObject) {
		[displayedObject setUserIconData:imageData];
	}
	
	[self updateUserIcon:displayedObject];
}

- (void)deleteInImageViewWithImagePicker:(AIImageViewWithImagePicker *)sender
{
	if (displayedObject) {
		//Remove the preference
		[displayedObject setUserIconData:nil];

		[self updateUserIcon:displayedObject];
	}
}

/*
 If the userIcon was bigger than our image view's frame, it will have been clipped before being passed
 to the AIImageViewWithImagePicker.  This delegate method lets us pass the original, unmodified userIcon.
 */
- (NSImage *)imageForImageViewWithImagePicker:(AIImageViewWithImagePicker *)picker
{
	return ([displayedObject userIcon]);
}

- (NSImage *)emptyPictureImageForImageViewWithImagePicker:(AIImageViewWithImagePicker *)picker
{
	return [AIServiceIcons serviceIconForObject:displayedObject type:AIServiceIconLarge direction:AIIconNormal];
}

- (NSString *)fileNameForImageInImagePicker:(AIImageViewWithImagePicker *)picker
{
	NSString *fileName = [displayedObject.displayName safeFilenameString];
	if ([fileName hasPrefix:@"."]) {
		fileName = [fileName substringFromIndex:1];
	}
	return fileName;
}

#pragma mark Address Book

/*!
 * @brief One profile line, if the value has anything to say
 */
static void AIAddProfileLine(NSMutableArray *profileArray, NSString *label, NSString *value)
{
	if (![value length]) return;

	[profileArray addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							 label, KEY_KEY,
							 value, KEY_VALUE,
							 nil]];
}

/*!
 * @brief The address book's side of a contact's profile
 *
 * The card is fetched fresh with the richer key set this display wants; the cached card
 * carries only what the lookups need. The note stays off the list deliberately: reading
 * notes needs an entitlement Apple hands out case by case, and a chat client has no
 * business asking for it.
 */
- (void)addAddressBookInfoToProfileArray:(NSMutableArray *)profileArray forContact:(AIListContact *)inContact
{
	AIAddressBookPerson *person = [inContact addressBookPerson];
	if (!person) return;

	NSArray *keys = [NSArray arrayWithObjects:
					 [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName],
					 CNContactJobTitleKey,
					 CNContactDepartmentNameKey,
					 CNContactOrganizationNameKey,
					 CNContactUrlAddressesKey,
					 CNContactEmailAddressesKey,
					 CNContactPhoneNumbersKey,
					 CNContactPostalAddressesKey,
					 CNContactBirthdayKey,
					 CNContactDatesKey,
					 nil];
	CNContact *card = [[[CNContactStore alloc] init] unifiedContactWithIdentifier:person.uniqueId
																	 keysToFetch:keys
																		   error:NULL];
	if (!card) return;

	AIAddProfileLine(profileArray, AILocalizedString(@"Full Name", nil),
					 [CNContactFormatter stringFromContact:card style:CNContactFormatterStyleFullName]);

	AIAddProfileLine(profileArray, AILocalizedString(@"Job Title", nil), card.jobTitle);
	AIAddProfileLine(profileArray, AILocalizedString(@"Department", nil), card.departmentName);
	AIAddProfileLine(profileArray, AILocalizedString(@"Company", nil), card.organizationName);

	for (CNLabeledValue *labeled in card.urlAddresses) {
		AIAddProfileLine(profileArray,
						 [CNLabeledValue localizedStringForLabel:(labeled.label ?: CNLabelURLAddressHomePage)],
						 (NSString *)labeled.value);
	}

	for (CNLabeledValue *labeled in card.emailAddresses) {
		AIAddProfileLine(profileArray,
						 [NSString stringWithFormat:@"%@ (%@)", AILocalizedString(@"Email", nil),
						  [CNLabeledValue localizedStringForLabel:(labeled.label ?: CNLabelOther)]],
						 (NSString *)labeled.value);
	}

	for (CNLabeledValue *labeled in card.phoneNumbers) {
		AIAddProfileLine(profileArray,
						 [NSString stringWithFormat:@"%@ (%@)", AILocalizedString(@"Phone", nil),
						  [CNLabeledValue localizedStringForLabel:(labeled.label ?: CNLabelOther)]],
						 [(CNPhoneNumber *)labeled.value stringValue]);
	}

	for (CNLabeledValue *labeled in card.postalAddresses) {
		NSString *address = [CNPostalAddressFormatter stringFromPostalAddress:(CNPostalAddress *)labeled.value
																		style:CNPostalAddressFormatterStyleMailingAddress];
		AIAddProfileLine(profileArray,
						 [NSString stringWithFormat:@"%@ (%@)", AILocalizedString(@"Address", nil),
						  [CNLabeledValue localizedStringForLabel:(labeled.label ?: CNLabelOther)]],
						 [address stringByReplacingOccurrencesOfString:@"\n" withString:@", "]);
	}

	NSDateComponents *birthday = card.birthday;
	if (birthday) {
		NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:birthday];
		if (date) {
			[NSDateFormatter withLocalizedDateFormatterPerform:^(NSDateFormatter *dateFormatter){
				AIAddProfileLine(profileArray, AILocalizedString(@"Birthday", nil), [dateFormatter stringFromDate:date]);
			}];
		}
	}

	for (CNLabeledValue *labeled in card.dates) {
		NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:(NSDateComponents *)labeled.value];
		if (!date) continue;

		[NSDateFormatter withLocalizedDateFormatterPerform:^(NSDateFormatter *dateFormatter){
			AIAddProfileLine(profileArray,
							 [CNLabeledValue localizedStringForLabel:(labeled.label ?: CNLabelOther)],
							 [dateFormatter stringFromDate:date]);
		}];
	}
}

- (void)addTooltipEntriesToProfileArray:(NSMutableArray *)profileArray forContact:(AIListContact *)inContact
{
	NSArray *tooltipEntries = [[adium.interfaceController contactListTooltipPrimaryEntries] arrayByAddingObjectsFromArray:[adium.interfaceController contactListTooltipSecondaryEntries]];
	for (id <AIContactListTooltipEntry> tooltipEntry in tooltipEntries) {
		if ([tooltipEntry shouldDisplayInContactInspector]) {
			id label, value;
			if ((label = [tooltipEntry labelForObject:inContact]) &&
				(value = [tooltipEntry entryForObject:inContact])) {
				[profileArray addObject:[NSDictionary dictionaryWithObjectsAndKeys:
										 label, KEY_KEY,
										 value, KEY_VALUE,
										 nil]];
			}	
		}
	}
}

@end
