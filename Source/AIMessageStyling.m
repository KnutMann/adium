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

#import "AIMessageStyling.h"

@implementation AIMessageStyleSpan

+ (instancetype)spanOfKind:(AIMessageStyleKind)kind range:(NSRange)range
{
	AIMessageStyleSpan *span = [[self alloc] init];
	if (span) {
		span->_kind = kind;
		span->_range = range;
	}
	return span;
}

- (NSString *)description
{
	static const char *names[] = { "emphasis", "strong", "strikethrough", "preformatted", "quotation" };
	return [NSString stringWithFormat:@"<%s %lu..%lu>", names[_kind],
			(unsigned long)_range.location, (unsigned long)NSMaxRange(_range)];
}

@end

static BOOL AIIsWhitespace(unichar c)
{
	return (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 0x0B || c == 0x0C);
}

static AIMessageStyleKind AIKindForDirective(unichar c, BOOL *found)
{
	*found = YES;
	switch (c) {
		case '_':	return AIMessageStyleEmphasis;
		case '*':	return AIMessageStyleStrong;
		case '~':	return AIMessageStyleStrikethrough;
		case '`':	return AIMessageStylePreformatted;
	}
	*found = NO;
	return AIMessageStyleEmphasis;
}

/*!
 * @brief Read the spans of one stretch of plain text, directives inside directives included
 *
 * The rules are the specification's, and every one of them is there to stop ordinary writing
 * from being read as markup. An opener stands at the start, after a space, or directly after
 * another opener, and is not followed by a space; a closer is not preceded by one; and there
 * has to be something between the two. Between them, that is what keeps an address like
 * example.com/a_b_c from turning half a sentence italic.
 */
static void AIScanSpans(NSString *body, NSRange area, NSMutableArray *into, BOOL insidePreformatted)
{
	NSUInteger	 end = NSMaxRange(area);
	unichar		 previous = 0;			//what stood before the character being looked at

	for (NSUInteger i = area.location; i < end; i++) {
		unichar	 c = [body characterAtIndex:i];
		BOOL	 isDirective = NO;
		AIMessageStyleKind kind = AIKindForDirective(c, &isDirective);

		if (!isDirective) {
			previous = c;
			continue;
		}

		//Inside a preformatted span nothing is markup but the span's own closing directive
		if (insidePreformatted) {
			previous = c;
			continue;
		}

		BOOL opensHere = (i == area.location || AIIsWhitespace(previous));
		if (!opensHere) {
			//...or directly after another opener, which is how *_both_* is written
			BOOL wasDirective = NO;
			AIKindForDirective(previous, &wasDirective);
			opensHere = wasDirective;
		}
		if (!opensHere || i + 1 >= end || AIIsWhitespace([body characterAtIndex:i + 1])) {
			previous = c;
			continue;
		}

		//Look for the closer: the same character, not preceded by a space, before the block ends
		NSUInteger close = NSNotFound;
		for (NSUInteger j = i + 1; j < end; j++) {
			if ([body characterAtIndex:j] != c) continue;
			if (AIIsWhitespace([body characterAtIndex:j - 1])) continue;
			if (j == i + 1) continue;			//nothing between the two, so neither counts
			close = j;
			break;
		}

		if (close == NSNotFound) {
			previous = c;
			continue;
		}

		NSRange whole = NSMakeRange(i, close - i + 1);
		[into addObject:[AIMessageStyleSpan spanOfKind:kind range:whole]];

		//What it marks may itself be marked, unless this was preformatted
		if (close > i + 1) {
			AIScanSpans(body, NSMakeRange(i + 1, close - i - 1), into,
						(kind == AIMessageStylePreformatted));
		}

		i = close;
		previous = c;
	}
}

NSArray<AIMessageStyleSpan *> *AIMessageStylingSpans(NSString *body)
{
	if (![body length]) return @[];

	NSMutableArray	*spans = [NSMutableArray array];
	NSUInteger		 length = [body length];
	NSUInteger		 lineStart = 0;
	BOOL			 inBlock = NO;
	NSUInteger		 blockStart = 0;

	while (lineStart <= length) {
		NSRange		 rest = NSMakeRange(lineStart, length - lineStart);
		NSRange		 newline = [body rangeOfString:@"\n" options:0 range:rest];
		NSUInteger	 lineEnd = (newline.location == NSNotFound) ? length : newline.location;
		NSRange		 line = NSMakeRange(lineStart, lineEnd - lineStart);

		BOOL fence = (line.length >= 3 && [[body substringWithRange:NSMakeRange(line.location, 3)] isEqualToString:@"```"]);

		if (inBlock) {
			/* A block runs until a line of three accents, or until the message stops. The
			 * whole of it is one span and nothing inside it is read as anything. */
			if (fence) {
				[spans addObject:[AIMessageStyleSpan spanOfKind:AIMessageStylePreformatted
														  range:NSMakeRange(blockStart, lineEnd - blockStart)]];
				inBlock = NO;
			} else if (lineEnd == length) {
				[spans addObject:[AIMessageStyleSpan spanOfKind:AIMessageStylePreformatted
														  range:NSMakeRange(blockStart, length - blockStart)]];
				inBlock = NO;
			}
		} else if (fence) {
			inBlock = YES;
			blockStart = line.location;
		} else {
			if (line.length && [body characterAtIndex:line.location] == '>') {
				[spans addObject:[AIMessageStyleSpan spanOfKind:AIMessageStyleQuotation range:line]];
			}
			AIScanSpans(body, line, spans, NO);
		}

		if (newline.location == NSNotFound) break;
		lineStart = newline.location + 1;
	}

	return spans;
}
