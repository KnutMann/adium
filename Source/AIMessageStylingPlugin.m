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

#import "AIMessageStylingPlugin.h"
#import "AIMessageStyling.h"
#import <AppKit/AppKit.h>

@implementation AIMessageStylingPlugin

/*!
 * @brief Install
 *
 * Display only, and both ways. Our own message is marked up on our own screen the way the
 * other side will mark it up on theirs, while what goes over the wire stays the characters
 * that were typed, which is the whole point of writing markup in plain text.
 */
- (void)installPlugin
{
	[adium.contentController registerContentFilter:self ofType:AIFilterMessageDisplay direction:AIFilterIncoming];
	[adium.contentController registerContentFilter:self ofType:AIFilterMessageDisplay direction:AIFilterOutgoing];
}

- (void)uninstallPlugin
{
	[adium.contentController unregisterContentFilter:self];
}

/*!
 * @brief Add a trait to whatever font is already in this range
 *
 * Whatever the message style chose stays chosen; only the one trait is added. A range that
 * already carries several, which is how *_both_* comes out, ends up with all of them.
 */
- (void)addTrait:(NSFontTraitMask)trait toString:(NSMutableAttributedString *)string range:(NSRange)range
{
	NSFontManager *manager = [NSFontManager sharedFontManager];

	[string enumerateAttribute:NSFontAttributeName
					   inRange:range
					   options:0
					usingBlock:^(id value, NSRange found, BOOL *stop) {
		NSFont *font = value ?: [NSFont messageFontOfSize:0];
		[string addAttribute:NSFontAttributeName
					   value:[manager convertFont:font toHaveTrait:trait]
					   range:found];
	}];
}

/*!
 * @brief Put the range into a fixed width face, keeping its size
 */
- (void)makeMonospaced:(NSMutableAttributedString *)string range:(NSRange)range
{
	[string enumerateAttribute:NSFontAttributeName
					   inRange:range
					   options:0
					usingBlock:^(id value, NSRange found, BOOL *stop) {
		CGFloat size = value ? [(NSFont *)value pointSize] : [NSFont systemFontSize];
		NSFont *fixed = [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
		if (fixed) [string addAttribute:NSFontAttributeName value:fixed range:found];
	}];
}

/*!
 * @brief Mark up a message the way its writer meant it
 */
- (NSAttributedString *)filterAttributedString:(NSAttributedString *)inAttributedString context:(id)context
{
	if (![inAttributedString length]) return inAttributedString;

	NSArray *spans = AIMessageStylingSpans([inAttributedString string]);
	if (![spans count]) return inAttributedString;

	NSMutableAttributedString	*styled = [inAttributedString mutableCopy];
	NSUInteger					 length = [styled length];

	for (AIMessageStyleSpan *span in spans) {
		NSRange range = span.range;
		if (NSMaxRange(range) > length) continue;		//the string changed under us; leave it alone

		/* A link is somebody's address and not ours to restyle. The specification's rule
		 * about what may open a directive keeps most of them out of reach already; this is
		 * for the rest, and for whatever order the filters happen to run in. */
		__block BOOL isLink = NO;
		[styled enumerateAttribute:NSLinkAttributeName
						   inRange:range
						   options:0
						usingBlock:^(id value, NSRange found, BOOL *stop) {
			if (value) { isLink = YES; *stop = YES; }
		}];
		if (isLink) continue;

		switch (span.kind) {
			case AIMessageStyleEmphasis:
				[self addTrait:NSItalicFontMask toString:styled range:range];
				break;

			case AIMessageStyleStrong:
				[self addTrait:NSBoldFontMask toString:styled range:range];
				break;

			case AIMessageStyleStrikethrough:
				[styled addAttribute:NSStrikethroughStyleAttributeName
							   value:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
							   range:range];
				break;

			case AIMessageStylePreformatted:
				[self makeMonospaced:styled range:range];
				break;

			case AIMessageStyleQuotation:
				/* Marked by its colour rather than by an indent: the line keeps the '>' it
				 * was written with, and a quotation drawn as a block would have to survive
				 * a trip through attributes and back, which it cannot. */
				[styled addAttribute:NSForegroundColorAttributeName
							   value:[NSColor secondaryLabelColor]
							   range:range];
				break;
		}
	}

	return styled;
}

/*!
 * @brief Run late, so that whatever finds links and emoticons has already had its say
 */
- (CGFloat)filterPriority
{
	return LOWEST_FILTER_PRIORITY;
}

@end
