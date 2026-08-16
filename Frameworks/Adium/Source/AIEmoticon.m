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

#import <Adium/AIEmoticon.h>
#import <Adium/AIEmoticonPack.h>
#import <Adium/AITextAttachmentExtension.h>

/* Size of the image rendered for a character emoticon. The emoticon sets we ship draw their
 * emoticons at 16x16, so matching that keeps character emoticons the same size as image ones
 * everywhere and lets -imageByScalingForMenuItem pass the image through untouched.
 */
#define EMOTICON_CHARACTER_IMAGE_SIZE	16.0f

/* Fraction of the image's edge length used as the point size of the glyph. The emoji font's line
 * height is noticeably taller than its point size, so asking for the full edge length would clip.
 */
#define EMOTICON_CHARACTER_FONT_FRACTION	0.8f

@interface AIEmoticon ()
- (AIEmoticon *)initWithIconPath:(NSString *)inPath character:(NSString *)inCharacter equivalents:(NSArray *)inTextEquivalents name:(NSString *)inName pack:(AIEmoticonPack *)inPack;
- (NSImage *)imageOfCharacterWithSize:(NSSize)inSize;
@end

@implementation AIEmoticon

/*!
 * @brief Create an autoreleased emoticon object
 *
 * An AIEmoticon has a path to an image, an array of string equivalents, a localized (if possible) name, and a parent
 * <tt>AIEmoticonPack</tt> which contains it.
 *
 * @param inPath A full path to an image to display for this emoticon
 * @param inTextEquivalents An <tt>NSArray</tt> of text equivalents for this emoticon
 * @param inName A human readable name for the emoticon
 * @param inPack The AIEmoticonPack which contains this emoticon
 */
+ (id)emoticonWithIconPath:(NSString *)inPath equivalents:(NSArray *)inTextEquivalents name:(NSString *)inName pack:(AIEmoticonPack *)inPack
{
    return [[self alloc] initWithIconPath:inPath character:nil equivalents:inTextEquivalents name:inName pack:inPack];
}

/*!
 * @brief Create an autoreleased emoticon object which displays a character rather than an image
 *
 * A character emoticon carries the text it should be displayed as - typically a system emoji - instead of
 * a path to an image file. It is shown as plain text, which means it needs no bundled artwork and follows
 * the font size and color of the text surrounding it.
 *
 * @param inCharacter The text to display in place of the text equivalents, e.g. an emoji
 * @param inTextEquivalents An <tt>NSArray</tt> of text equivalents for this emoticon
 * @param inName A human readable name for the emoticon
 * @param inPack The AIEmoticonPack which contains this emoticon
 */
+ (id)emoticonWithCharacter:(NSString *)inCharacter equivalents:(NSArray *)inTextEquivalents name:(NSString *)inName pack:(AIEmoticonPack *)inPack
{
    return [[self alloc] initWithIconPath:nil character:inCharacter equivalents:inTextEquivalents name:inName pack:inPack];
}

//Init
- (AIEmoticon *)initWithIconPath:(NSString *)inPath character:(NSString *)inCharacter equivalents:(NSArray *)inTextEquivalents name:(NSString *)inName pack:(AIEmoticonPack *)inPack
{
    if ((self = [super init])) {
		path = inPath;
		character = [inCharacter copy];
		name = inName;
		textEquivalents = inTextEquivalents;
		pack = inPack;
		imageLoaded = NO;
		_cachedAttributedString = nil;
		_cachedCharacterImage = nil;
    }

    return self;
}

/*!
 * @brief Returns an array of the text equivalents for this emoticon
 *
 * @result An <tt>NSArray</tt> of <tt>NSStrings</tt> which are the equivalents for the emoticon
 */
- (NSArray *)textEquivalents
{
    return textEquivalents;
}

/*!
 * @brief Flush any cached data
 *
 * This releases image attachment strings which were cached by the emoticon. It is primarily used
 * after display previews of emoticon packs which are not enabled, since there is no reason to maintain a cache that
 * will not be used.
 */
- (void)flushEmoticonImageCache
{
	imageLoaded = NO;
    _cachedAttributedString = nil;
    _cachedCharacterImage = nil;
}

/*!
 * @brief Returns the display name of this emoticon
 *
 * @result The display name of the emoticon
 */
- (NSString *)name
{
    return name;
}

/*!
 * @brief Enable/Disable this emoticon
 *
 * Individual emoticons within an emoticon pack may be enabled or disabled.
 *
 * @param inEnabled The new enabled state
 */
- (void)setEnabled:(BOOL)inEnabled
{
    enabled = inEnabled;
}

/*!
 * @brief Return the enabled state
 *
 * @result The enabled state
 */
- (BOOL)isEnabled{
    return enabled;
}

/*!
 * @brief Returns the image for this emoticon
 *
 * A character emoticon has no image file, so its character is drawn into an image. That way every
 * place which previews emoticons - the emoticon menu, the preference tables, the pack previews -
 * keeps working without having to know that character emoticons exist. Note that this image is
 * only used for those previews: in messages a character emoticon is inserted as text.
 *
 * @result The image for this emoticon, or nil if it has neither an image file nor a character
 */
- (NSImage *)image
{
	if (character) {
		if (!_cachedCharacterImage) {
			_cachedCharacterImage = [self imageOfCharacterWithSize:NSMakeSize(EMOTICON_CHARACTER_IMAGE_SIZE,
																			  EMOTICON_CHARACTER_IMAGE_SIZE)];
		}

		return _cachedCharacterImage;
	}

	//Packs referencing images which aren't there leave us without a path; don't hand nil to NSImage
	return (path ? [[NSImage alloc] initWithContentsOfFile:path] : nil);
}

/*!
 * @brief Draw this emoticon's character into an image
 *
 * Drawn through a drawing handler rather than into a bitmap of our own: the handler is re-run for
 * whatever resolution the image is displayed at, so the glyph stays sharp on Retina displays instead
 * of being frozen at one scale factor.
 *
 * @param inSize The size of the image to create
 * @result An autoreleased <tt>NSImage</tt> showing the character, centered
 */
- (NSImage *)imageOfCharacterWithSize:(NSSize)inSize
{
	/* The drawing handler is copied and outlives this call, and the image it returns is cached in an
	 * ivar; capture the character in a local so that the block doesn't capture (and retain) self.
	 */
	NSString	*emoticonCharacter = [character copy];

	return [NSImage imageWithSize:inSize flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
		/* No font is named explicitly: the system font substitutes the color emoji font for emoji code
		 * points, which also resolves variation selector sequences the way the rest of the system does.
		 */
		NSDictionary	*attributes = [NSDictionary dictionaryWithObjectsAndKeys:
									   [NSFont systemFontOfSize:(dstRect.size.height * EMOTICON_CHARACTER_FONT_FRACTION)], NSFontAttributeName,
									   nil];
		NSSize			characterSize = [emoticonCharacter sizeWithAttributes:attributes];

		[emoticonCharacter drawAtPoint:NSMakePoint(NSMidX(dstRect) - (characterSize.width / 2.0f),
												   NSMidY(dstRect) - (characterSize.height / 2.0f))
						withAttributes:attributes];

		return YES;
	}];
}

/*!
 * @brief Change the path to the image for this emoticon
 */
- (void)setPath:(NSString *)inPath
{
	if (path != inPath) {
		path = inPath;

		_cachedAttributedString = nil;
	}
}

- (NSString *)path
{
	return path;
}

/*!
 * @brief The text this emoticon is displayed as, if it is a character emoticon
 *
 * @result The character (typically an emoji), or nil if this emoticon is displayed as an image
 */
- (NSString *)character
{
	return character;
}

/*!
 * @brief Can this emoticon actually be shown to the user?
 *
 * An emoticon needs either an image file or a character; one without both would silently replace the
 * text it matches with nothing at all.
 *
 * Deliberately does not consult -image: answering this question must not load the image of every
 * emoticon of every installed pack.
 *
 * @result YES if this emoticon has something to display
 */
- (BOOL)isDisplayable
{
	return ((path != nil) || ([character length] > 0));
}

/*!
 * @brief Returns an attributed string containing this emoticon
 *
 * The attributed string contains an <tt>AITextAttachmentExtension</tt> which has both the emoticon image
 * and the passed text equivalent available.  The hard work is cached, although each call results in a new
 * NSMutableAttributedString being returned.
 *
 * A character emoticon has no image and therefore no attachment: it returns its character as plain text.
 *
 * @param textEquivalent The text equivalent for this attributed string
 * @param attach If YES, an image cell is immediately attached. If NO, no attachment cell is made.
 *               Meaningless for character emoticons, which are text in every context.
 *
 * @result The attributed string with the emoticon
 */
- (NSMutableAttributedString *)attributedStringWithTextEquivalent:(NSString *)textEquivalent attachImages:(BOOL)attach
{
	static dispatch_queue_t cacheQueue;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		cacheQueue = dispatch_queue_create("im.adium.AIEmoticon.cachedAttributedStringQueue", 0);
	});
	__block NSMutableAttributedString   *attributedString;
	dispatch_sync(cacheQueue, ^{
		@autoreleasepool {
			AITextAttachmentExtension   *attachment;

			/* A character emoticon is simply text, so branch out before any of the attachment handling below:
			 * it must never take the !path branch, which would build an empty image cell for it, and it has
			 * no image whose loading the cache would have to track.
			 *
			 * The string intentionally carries no attributes of its own. Our caller applies the attributes of
			 * the text being replaced, which is what makes the character follow the font size and color of the
			 * surrounding message.
			 */
			if (character) {
				if (!_cachedAttributedString) {
					_cachedAttributedString = [[NSAttributedString alloc] initWithString:character];
				}

				//Owned, exactly as in the image case below: the pool must not be this string's last owner
				attributedString = [_cachedAttributedString mutableCopy];

				return;
			}

			//Cache this attachment for ourself if we don't already have a cache, or if our cache needs to have an image attached

			if (!_cachedAttributedString || (!imageLoaded && attach)) {
				AITextAttachmentExtension   *emoticonAttachment = [[AITextAttachmentExtension alloc] init];
				if(!path || attach) {
					NSTextAttachmentCell		*cell = [[NSTextAttachmentCell alloc] initImageCell:[self image]];
					[emoticonAttachment setAttachmentCell:cell];
					imageLoaded = YES;
				}

				[emoticonAttachment setPath:path];
				[emoticonAttachment setHasAlternate:YES];
				[emoticonAttachment setImageClass:@"emoticon"];

				//Emoticons should not ever be sent out as images
				[emoticonAttachment setShouldAlwaysSendAsText:YES];

				_cachedAttributedString = [NSAttributedString attributedStringWithAttachment:emoticonAttachment];
			}


			//Create a copy of our cached string, and update it for the new text equivalent
			attributedString = [_cachedAttributedString mutableCopy];
			attachment = [[attributedString attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL] copy];
			[attributedString addAttribute:NSAttachmentAttributeName value:attachment range:NSMakeRange(0, [attributedString length])];
			[attachment setString:textEquivalent];
		}
    });
    return attributedString;
}


/*!
 * @brief Is this emoticon appropriate for a service class?
 *
 * @result YES if this emoticon is not associated with any service class or is associated with the passed one.
 */
- (BOOL)isAppropriateForServiceClass:(NSString *)inServiceClass
{
	NSString	*ourServiceClass = pack.serviceClass;
	return !ourServiceClass || [ourServiceClass isEqualToString:inServiceClass];
}

/*!
 * @brief A more useful debug description
 */
- (NSString *)description
{
    return [NSString stringWithFormat:@"%@<%p> (Equivalents: %@) [in %@]",name,self,[self textEquivalents],pack];
}

/*!
 * @brief Compare two emoticons
 *
 * @result The result of comparing the display names of the emoticons, case insensitively
 */
- (NSComparisonResult)compare:(AIEmoticon *)otherEmoticon
{
	return [name caseInsensitiveCompare:[otherEmoticon name]];
}

@end
