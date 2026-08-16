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
 Some useful additions for attributed strings
 */

#import "AIAttributedStringAdditions.h"
#import "AIColorAdditions.h"
#import "AITextAttributes.h"
#import "AIApplicationAdditions.h"
#import "AIStringUtilities.h"

NSString *AIFontFamilyAttributeName = @"AIFontFamily";
NSString *AIFontSizeAttributeName   = @"AIFontSize";
NSString *AIFontWeightAttributeName = @"AIFontWeight";
NSString *AIFontStyleAttributeName  = @"AIFontStyle";

@implementation NSMutableAttributedString (AIAttributedStringAdditions)

//Append a plain string, adding the specified attributes
- (void)appendString:(NSString *)aString withAttributes:(NSDictionary *)attrs
{
    NSAttributedString	*tempString;

    if (attrs) {
        tempString = [[NSAttributedString alloc] initWithString:aString attributes:attrs];
    } else {
        tempString = [[NSAttributedString alloc] initWithString:aString];
    }

    [self appendAttributedString:tempString];
}

- (NSUInteger)replaceOccurrencesOfString:(NSString *)target withString:(NSString*)replacement options:(NSStringCompareOptions)opts range:(NSRange)searchRange
{
    NSRange		theRange;
    NSUInteger	numberOfReplacements = 0, replacementLength = [replacement length];

    while ( (theRange = [[self string] rangeOfString:target 
											 options:opts
											   range:searchRange]).location != NSNotFound ) {
        [self replaceCharactersInRange:theRange withString:replacement];
        numberOfReplacements++;
        searchRange.length = searchRange.length - ((theRange.location + theRange.length) - searchRange.location);
        
        searchRange.location = theRange.location + replacementLength;
        if (searchRange.length - searchRange.location < 1)
            break;
    }
    return numberOfReplacements;
}

- (NSUInteger)replaceOccurrencesOfString:(NSString *)target withString:(NSString*)replacement attributes:(NSDictionary*)attributes options:(NSStringCompareOptions)opts range:(NSRange)searchRange
{
    NSRange				theRange;
    NSUInteger			numberOfReplacements = 0, replacementLength = [replacement length];
    NSAttributedString	*replacementString = [[NSAttributedString alloc] initWithString:replacement 
																			 attributes:attributes];
    
    while ( (theRange = [[self string] rangeOfString:target
											 options:opts
											   range:searchRange]).location != NSNotFound ) {
		
        [self replaceCharactersInRange:theRange withAttributedString:replacementString];
        numberOfReplacements++;
        searchRange.length = searchRange.length - ((theRange.location + theRange.length) - searchRange.location);
        
        searchRange.location = theRange.location + replacementLength;
        if (searchRange.length - searchRange.location < 1)
            break;
    }
    
    
    return numberOfReplacements;
}


//from Adium 1.6 AIAttributedStringFormattingAdditions
//adjust the colors in the string so they're visible on the background
- (void)adjustColorsToShowOnBackground:(NSColor *)backgroundColor
{
    NSUInteger		idx = 0;
    NSUInteger		stringLength = [self length];
    CGFloat	backgroundBrightness, backgroundSum;
    
    //--get the brightness of our background--
    backgroundColor = [backgroundColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    backgroundBrightness = [backgroundColor brightnessComponent];
    backgroundSum = [backgroundColor redComponent] + [backgroundColor greenComponent] + [backgroundColor blueComponent];
    //we need to scan each colored "chunk" of the message - and check to make sure it is a "visible" color
    while (idx < stringLength) {
        NSColor		*fontColor;
        NSRange		effectiveRange;
        CGFloat		brightness, sum;
        CGFloat		deltaBrightness, deltaSum;
        BOOL		colorChanged = NO;
        
        //--get the font color--
        fontColor = [self attribute:NSForegroundColorAttributeName atIndex:idx effectiveRange:&effectiveRange];                
        if (fontColor == nil) fontColor = [NSColor blackColor];
        fontColor = [fontColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
        
        //--check brightness--
        brightness = [fontColor brightnessComponent];
        deltaBrightness = backgroundBrightness - brightness;
        if (deltaBrightness >= 0 && deltaBrightness < 0.4f) { //too close                    
                                                           //change the color
            fontColor = [NSColor colorWithCalibratedHue:[fontColor hueComponent] saturation:[fontColor saturationComponent] brightness:backgroundBrightness - 0.4f alpha:[fontColor alphaComponent]];
            fontColor = [fontColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
                colorChanged = YES;
            
        } else if (deltaBrightness < 0 && deltaBrightness > -0.4f) { //too close
                                                                 //change the color
            fontColor = [NSColor colorWithCalibratedHue:[fontColor hueComponent] saturation:[fontColor saturationComponent] brightness:backgroundBrightness + 0.4f alpha:[fontColor alphaComponent]];
            fontColor = [fontColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
            
            colorChanged = YES;
        }
        
        //--check components--
        sum = [fontColor redComponent] + [fontColor greenComponent] + [fontColor blueComponent];
        deltaSum = backgroundSum - sum;
        if (deltaSum < 1.0f && deltaSum > -1.0f) { //still too similar                    
                                               //just give up and make the color black or white
            if (backgroundBrightness <= 0.5f) {
                fontColor = [[NSColor whiteColor] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
            } else {
                fontColor = [[NSColor blackColor] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
            }
            colorChanged = YES;
        }
        
        if (colorChanged) {
            [self addAttribute:NSForegroundColorAttributeName value:fontColor range:effectiveRange];
        }
        
        idx = effectiveRange.location + effectiveRange.length;
    }
}

//adjust the colors in the string so they're visible on the background, adjusting brightness in proportion to the original background
- (void)adjustColorsToShowOnBackgroundRelativeToOriginalBackground:(NSColor *)backgroundColor
{
    NSUInteger      idx = 0;
    NSUInteger      stringLength = [self length];
    CGFloat         backgroundBrightness=0.0f;
    NSColor         *backColor=nil;
    //--get the brightness of our background--
    if (backgroundColor) {
        backColor = [backgroundColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
        backgroundBrightness = [backColor brightnessComponent];
    }
    
    //we need to scan each colored "chunk" of the message - and check to make sure it is a "visible" color
    while (idx < stringLength) {
        NSColor		*fontColor;
        NSColor         *fontBackColor;

        NSRange		effectiveRange, backgroundRange;
        CGFloat		brightness, newBrightness;
        CGFloat		deltaBrightness, deltaSum;
        BOOL		colorChanged = NO, backgroundIsDark, fontBackIsDark;
        
        //--get the font color--
        fontColor = [self attribute:NSForegroundColorAttributeName atIndex:idx effectiveRange:&effectiveRange];
        //--get the background color in this range
        fontBackColor = [self attribute:NSBackgroundColorAttributeName atIndex:idx effectiveRange:&backgroundRange];
        if (!fontBackColor) {
            //Background coloring
            fontBackColor = [self attribute:AIBodyColorAttributeName atIndex:idx effectiveRange:&backgroundRange];
            if (!fontBackColor) {
                fontBackColor = [NSColor whiteColor];
                fontBackColor = [fontBackColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
            }
        }
        
        //--use the shorter of these two ranges
        if (backgroundRange.length < effectiveRange.length)
            effectiveRange.length = backgroundRange.length;
        
        if (!fontColor) fontColor = [NSColor blackColor];
        fontColor = [fontColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
        
        brightness = [fontColor brightnessComponent];
        
        if (!backgroundColor) {
            backColor = fontBackColor;
            backgroundBrightness = [backColor brightnessComponent];
        } else {
            deltaBrightness = (brightness - [fontBackColor brightnessComponent]);
            backgroundIsDark = [backgroundColor colorIsDark];
            fontBackIsDark = [fontBackColor colorIsDark];
            if (!backgroundIsDark && fontBackIsDark) {
                newBrightness = brightness - (deltaBrightness)/2;
                if (newBrightness <= 0)
                    newBrightness = .2f;
                colorChanged = YES;
            }
            else if (backgroundIsDark && !fontBackIsDark) {
                newBrightness = brightness + (deltaBrightness)/2;
                if (newBrightness >= 1)
                    newBrightness = .8f;
                colorChanged = YES;
            }
            
            if (colorChanged) {
                fontColor = [NSColor colorWithCalibratedHue:[fontColor hueComponent] saturation:[fontColor saturationComponent] brightness:newBrightness alpha:[fontColor alphaComponent]];
                fontColor = [fontColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
            }
        }
                 
        //--check brightness--
        brightness = [fontColor brightnessComponent];
        deltaBrightness = backgroundBrightness - brightness;       
        if (deltaBrightness >= 0 && deltaBrightness <= 0.4f) {    //too close 
            fontColor = [fontColor adjustHue:0.0f saturation:0.0f brightness:-.4f]; //change the color
            colorChanged = YES;
            
        } else if (deltaBrightness >= -0.4f && deltaBrightness <0) { //too close
                                                                 //change the color

            fontColor = [fontColor adjustHue:0.0f saturation:0.0f brightness:.4f];
            
            colorChanged = YES;
        }

        //--check luminance--
        CGFloat hue,saturation;
        CGFloat fontLuminance,backLuminance;
        
        [fontColor getHue:&hue saturation:&saturation brightness:&fontLuminance alpha:NULL];
        [backColor getHue:&hue saturation:&saturation brightness:&backLuminance alpha:NULL];
            
        deltaSum = backLuminance - fontLuminance;
        
        if (deltaSum >= -0.3f && deltaSum <= 0.3f) { //still too similar     
            if (backgroundBrightness <= 0.5f) {
               fontColor = [[NSColor whiteColor] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
            } else {
                fontColor = [[NSColor blackColor] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
            }

            colorChanged = YES;
        }
        
        if (colorChanged) {
            [self addAttribute:NSForegroundColorAttributeName value:fontColor range:effectiveRange];
        }
        
        idx = effectiveRange.location + effectiveRange.length;
    }
}

- (void)addFormattingForLinks
{
	NSRange		searchRange = NSMakeRange(0,0);
	NSUInteger	length = [self length];
	NSColor *calibratedBlueColor = [NSColor blueColor];
	NSNumber *YESBool = [NSNumber numberWithBool:YES];
	
	while (searchRange.location < length) {
		NSDictionary	*attributes = [self attributesAtIndex:searchRange.location effectiveRange:&searchRange];
		if ([attributes objectForKey:NSLinkAttributeName] != nil) {
			[self addAttribute:NSForegroundColorAttributeName value:calibratedBlueColor range:searchRange];
			[self addAttribute:NSUnderlineStyleAttributeName value:YESBool range:searchRange];
		}
		searchRange.location += searchRange.length;
	}
}

- (void)convertAttachmentsToStringsUsingPlaceholder:(NSString *)placeholder
{
    if ([self length] && [self containsAttachments]) {
        NSInteger							currentLocation = 0;
        NSRange						attachmentRange;
		NSString					*attachmentCharacterString = [NSString stringWithFormat:@"%C",(unichar)NSAttachmentCharacter];
		
        //find attachment
        attachmentRange = [[self string] rangeOfString:attachmentCharacterString
											   options:0 
												 range:NSMakeRange(currentLocation,
																   [self length])];
		
        while (attachmentRange.length != 0) { //if we found an attachment
			NSTextAttachment	*attachment = [self attribute:NSAttachmentAttributeName
													  atIndex:attachmentRange.location
											   effectiveRange:nil];
            NSString *replacement = nil;
			if ([attachment respondsToSelector:@selector(string)]) {
				replacement = [attachment performSelector:@selector(string)];
			}
			
            if (!replacement) {
                replacement = placeholder;
            }
			
            //remove the attachment, replacing it with the original text
			[self removeAttribute:NSAttachmentAttributeName range:attachmentRange];
            [self replaceCharactersInRange:attachmentRange withString:replacement];
			
            attachmentRange.length = [replacement length];
			
            currentLocation = attachmentRange.location + attachmentRange.length;
			
            //find the next attachment
            attachmentRange = [[self string] rangeOfString:attachmentCharacterString
												   options:0
													 range:NSMakeRange(currentLocation,
																	   [self length] - currentLocation)];
        }
	}	
}


@end

@implementation NSAttributedString (AIAttributedStringAdditions)

+ (NSSet *)CSSCapableAttributesSet
{
	return [NSSet setWithObjects:
		NSFontAttributeName,
		AIFontFamilyAttributeName,
		AIFontSizeAttributeName,
		AIFontWeightAttributeName,
		AIFontStyleAttributeName,
		NSForegroundColorAttributeName,
		NSBackgroundColorAttributeName,
		NSShadowAttributeName,
		NSCursorAttributeName,
		NSUnderlineStyleAttributeName,
		NSStrikethroughStyleAttributeName,
		NSSuperscriptAttributeName,
		nil];
}
+ (NSString *)CSSStringForTextAttributes:(NSDictionary *)attrs
{
	static NSDictionary *attributeNamesToCSSPropertyNames = nil;
	if (!attributeNamesToCSSPropertyNames) {
		attributeNamesToCSSPropertyNames = [[NSDictionary alloc] initWithObjectsAndKeys:
			@"font",             NSFontAttributeName,
			@"font-family",      AIFontFamilyAttributeName,
			@"font-size",        AIFontSizeAttributeName,
			@"font-weight",      AIFontWeightAttributeName,
			@"font-style",       AIFontStyleAttributeName,
			@"color",            NSForegroundColorAttributeName,
			@"background-color", NSBackgroundColorAttributeName,
			@"text-shadow",      NSShadowAttributeName,
			@"cursor",           NSCursorAttributeName,
			nil];
	}

	NSMutableArray *CSSProperties = [NSMutableArray arrayWithCapacity:[attrs count]];

	BOOL hasLineThrough = NO, hasUnderline = NO;

	NSEnumerator *keysEnum = [attrs keyEnumerator];
	NSString *key;
	while ((key = [keysEnum nextObject])) {
		if ([key isEqualToString:NSUnderlineStyleAttributeName]) {
			hasUnderline = YES;
		} else if ([key isEqualToString:NSStrikethroughStyleAttributeName]) {
			hasLineThrough = YES;
		} else if ([key isEqualToString:NSSuperscriptAttributeName]) {
			[CSSProperties addObject:@"vertical-align: baseline;"];
		} else {
			NSString *CSSPropertyName = [attributeNamesToCSSPropertyNames objectForKey:key];
			id obj = [attrs objectForKey:key];
			if (CSSPropertyName) {
				if ([obj respondsToSelector:@selector(CSSRepresentation)]) {
					obj = [obj CSSRepresentation];
				} else if ([obj respondsToSelector:@selector(stringValue)]) {
					obj = [obj stringValue];
				} else if ([obj respondsToSelector:@selector(absoluteString)]) {
					obj = [obj absoluteString];
				}

				[CSSProperties addObject:[NSString stringWithFormat:@"%@: %@;", CSSPropertyName, obj]];
			}
		}
	}

	if (hasLineThrough && hasUnderline) {
		[CSSProperties addObject:@"text-decoration: line-through underline;"];
	} else if (hasLineThrough) {
		[CSSProperties addObject:@"text-decoration: line-through;"];
	} else if (hasUnderline) {
		[CSSProperties addObject:@"text-decoration: underline;"];
	}

	[CSSProperties sortUsingSelector:@selector(compare:)];

	return [CSSProperties componentsJoinedByString:@" "];
}

//Height of a string
#define FONT_HEIGHT_STRING		@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
+ (CGFloat)stringHeightForAttributes:(NSDictionary *)attributes
{
	NSAttributedString	*string = [[NSAttributedString alloc] initWithString:FONT_HEIGHT_STRING
																   attributes:attributes];
	return [string heightWithWidth:1e7f];
}

+ (NSAttributedString *)stringWithString:(NSString *)inString
{
	NSParameterAssert(inString != nil);
	return [[NSAttributedString alloc] initWithString:inString];
}

+ (NSAttributedString *)attributedStringWithString:(NSString *)inString linkRange:(NSRange)linkRange linkDestination:(id)inLink
{
    NSParameterAssert(inString != nil);

    if ([inLink isKindOfClass:[NSString class]]) {
        inLink = [NSURL URLWithString:inLink];
    }
    NSParameterAssert(inLink != nil);
    NSParameterAssert([inLink isKindOfClass:[NSURL class]]);

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:inString];
    //Throws NSInvalidArgumentException if the range is out-of-range.
    [attributedString addAttribute:NSLinkAttributeName value:inLink range:linkRange];

    return attributedString;
}
+ (NSAttributedString *)attributedStringWithLinkLabel:(NSString *)inString linkDestination:(id)inLink
{
    NSParameterAssert(inString != nil);

    if ([inLink isKindOfClass:[NSString class]]) {
        inLink = [NSURL URLWithString:inLink];
    }
    NSParameterAssert(inLink != nil);
    NSParameterAssert([inLink isKindOfClass:[NSURL class]]);

    NSDictionary *attributes = [NSDictionary dictionaryWithObject:inLink forKey:NSLinkAttributeName];
    return [[self alloc] initWithString:inString attributes:attributes];
}

- (CGFloat)heightWithWidth:(CGFloat)width
{	
    //Setup the layout manager and text container
    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:self];
    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(width, 1e7f)];
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];

    //Configure
    [textContainer setLineFragmentPadding:0.0f];
    [layoutManager addTextContainer:textContainer];
    [textStorage addLayoutManager:layoutManager];

    //Force the layout manager to layout its text
    (void)[layoutManager glyphRangeForTextContainer:textContainer];

	CGFloat height = [layoutManager usedRectForTextContainer:textContainer].size.height;

	
    return height;
}

- (NSData *)dataRepresentation
{
	/* Keyed archive, read back by +stringWithData:. Secure coding stays off because
	 * attributed strings can carry attachment subclasses that only adopt NSCoding.
	 */
	NSError *error = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self
										 requiringSecureCoding:NO
														 error:&error];
	if (!data) {
		NSLog(@"-[NSAttributedString(AIAttributedStringAdditions) dataRepresentation]: archiving failed: %@", error);
	}
	return data;
}

+ (NSAttributedString *)stringWithData:(NSData *)inData
{
	NSAttributedString	*returnValue = nil;
	
	if (!inData || ![inData length]) return nil;
	
	/* Current data is a keyed archive written by -dataRepresentation. If inData is not a
	 * keyed archive, initForReadingFromData:error: returns nil and we fall through to the
	 * legacy formats below. The exception handlers mirror the old code: unarchivers throw
	 * NSInvalidArgumentException when fed invalid data.
	 */
	@try {
		NSKeyedUnarchiver *keyedUnarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:inData error:NULL];
		if (keyedUnarchiver) {
			/* Attributed strings can carry attachment subclasses that only adopt NSCoding,
			 * so secure coding stays off, matching the write side.
			 */
			keyedUnarchiver.requiresSecureCoding = NO;
			id root = [keyedUnarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
			[keyedUnarchiver finishDecoding];
			if ([root isKindOfClass:[NSAttributedString class]]) {
				returnValue = root;
			}
		}
	}
	@catch (id exc) {
		returnValue = nil;
	}
	
	if (!returnValue) {
		/* Legacy data: non-keyed NSArchiver archives written by every earlier version of
		 * Adium still live in the user's preferences (display names, profiles, saved
		 * statuses, message alerts). NSKeyedUnarchiver cannot read those, so NSUnarchiver
		 * stays on as their reader; the deprecation is silenced on purpose.
		 */
		@try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			NSUnarchiver *unarchiver = [[NSUnarchiver alloc] initForReadingWithData:inData];
#pragma clang diagnostic pop
			if (unarchiver) {
				/* NSUnarchiver's decodeObject hands back something the unarchiver owns and gives up
				 * when it is deallocated, which is at the end of this scope; returnValue holds it now.
				 */
				returnValue = (NSAttributedString *)[unarchiver decodeObject];
			}
		}
		@catch (id exc) {
			returnValue = nil;
		}
	}
	
	if (!returnValue) {
		/* Oldest preference data was stored as RTF. This path also serves callers that pass
		 * RTF pasteboard data straight in (see AIListController's drag handling).
		 */
		returnValue = [[NSAttributedString alloc] initWithRTF:inData
										   documentAttributes:nil];
	}
	
	return returnValue;
}

- (NSAttributedString *)attributedStringByConvertingAttachmentsToStrings
{
    if ([self length] && [self containsAttachments]) {
        NSMutableAttributedString	*newAttributedString = [self mutableCopy];
		[newAttributedString convertAttachmentsToStringsUsingPlaceholder:AILocalizedString(@"<<Attachment>>", nil)];

		return newAttributedString;

    } else {
        return self;
    }
}

/* Deprecated */
- (NSAttributedString *)safeString
{
	NSLog(@"%@", @"**** You are using an out of date external Adium plugin [most likely the SQL Logger]. Please recompile and reinstall the plugin. This will crash in a future release. ****");
	return [self attributedStringByConvertingAttachmentsToStrings];
}

- (NSAttributedString *)attributedStringByConvertingLinksToStringsWithTitles:(BOOL)includeTitles
{
	NSMutableAttributedString	*newAttributedString = nil;
	NSUInteger					length = [self length];

	if (length) {
		NSRange						searchRange = NSMakeRange(0,0);
		NSAttributedString			*currentAttributedString = self;

		while (searchRange.location < length) {
			NSURL			*URL = [currentAttributedString attribute:NSLinkAttributeName
														  atIndex:searchRange.location
												   effectiveRange:&searchRange];
			
			if (URL) {
				if (!newAttributedString) {
					newAttributedString = [self mutableCopy];
					currentAttributedString = newAttributedString;
				}

				NSString	*absoluteString = [URL absoluteString];
				NSString	*originalTitle = [[newAttributedString string] substringWithRange:searchRange];
				NSString	*replacementString;
				
				if ([originalTitle caseInsensitiveCompare:absoluteString] == NSOrderedSame) {
					replacementString = originalTitle;

				} else if (includeTitles) {
					replacementString = [NSString stringWithFormat:@"%@ (%@)", originalTitle, absoluteString];
				} else {
					replacementString = absoluteString;
				}

				[newAttributedString replaceCharactersInRange:searchRange 
												   withString:replacementString];
				
				//Modify our searchRange and cached length to reflect the string we just inserted.
				searchRange.length = [replacementString length];
				length = [newAttributedString length];
				
				//Now remove the link attribute
				[newAttributedString removeAttribute:NSLinkAttributeName range:searchRange];
			}

			searchRange.location += searchRange.length;
		}
	}

	return (newAttributedString ? newAttributedString : [self copy]);
}

- (NSAttributedString *)attributedStringByConvertingLinksToStrings
{
	return [self attributedStringByConvertingLinksToStringsWithTitles:YES];
}
- (NSAttributedString *)attributedStringByConvertingLinksToURLStrings
{
	return [self attributedStringByConvertingLinksToStringsWithTitles:NO];
}

- (NSAttributedString *)stringByAddingFormattingForLinks
{
	NSMutableAttributedString  *str = [self mutableCopy];
	[str addFormattingForLinks];
	return str;
}

@end

@implementation NSData (AIAttributedStringAdditions)

- (NSAttributedString *)attributedString
{
	return [NSAttributedString stringWithData:self];
}

@end
