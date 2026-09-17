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

#import <Foundation/Foundation.h>

/*!
 * @header AIMessageStyling
 * @brief XEP-0393: the markup people type, read as markup
 *
 * Nothing about this is specific to one service. The characters are what everybody has typed
 * at each other since long before there was a document about it, and WhatsApp reads the same
 * ones, so what is found here is found in every conversation.
 *
 * The directives stay in the text. That is what the specification recommends, formatted like
 * what they mark, and it is also what keeps everything else working: ranges are all that come
 * out of here, never a changed string, so the text a message was shown with is the text it
 * was sent with, and the id lookups, the quote matching and the transcripts go on agreeing
 * with each other.
 */

typedef NS_ENUM(NSInteger, AIMessageStyleKind) {
	AIMessageStyleEmphasis,			//_like this_
	AIMessageStyleStrong,			//*like this*
	AIMessageStyleStrikethrough,	//~like this~
	AIMessageStylePreformatted,		//`like this` and ```blocks like this```
	AIMessageStyleQuotation			//> lines like this
};

/*!
 * @class AIMessageStyleSpan
 * @brief One stretch of text and what it was marked as
 */
@interface AIMessageStyleSpan : NSObject

@property (readonly, nonatomic) AIMessageStyleKind kind;
@property (readonly, nonatomic) NSRange range;		//the whole stretch, directives included

+ (instancetype)spanOfKind:(AIMessageStyleKind)kind range:(NSRange)range;

@end

/*!
 * @brief Read the styling directives out of a message body
 *
 * Returns the spans found, outermost first, each one covering its directives as well as what
 * they mark. Ranges count in the same units NSString does, so an emoji before a directive
 * moves it by two.
 */
NSArray<AIMessageStyleSpan *> *AIMessageStylingSpans(NSString *body);
