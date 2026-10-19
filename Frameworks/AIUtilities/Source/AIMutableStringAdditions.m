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

#import "AIMutableStringAdditions.h"

@implementation NSMutableString (AIMutableStringAdditions)

+ (NSMutableString *)stringWithContentsOfASCIIFile:(NSString *)path
{
	//A file that cannot be read is nil, as it is from the UTF-8 reader on NSString; handed nil data, init would make an empty string
	NSData *data = [NSData dataWithContentsOfFile:path];

	return (data ? [[NSMutableString alloc] initWithData:data encoding:NSASCIIStringEncoding] : nil);
}

- (NSMutableString*)mutableString
{
	return self;
}

/*
 * @brief Convert new lines to slashes
 *
 * We first process \r\n into being just \n, then consolidate all duplicate line breaks.
 * All remaining \r and \n characters are converted to " / " as is done with multiple lines of a poem
 * displayed on a single line
 */
- (void)convertNewlinesToSlashes
{
	NSRange fullRange = NSMakeRange(0, [self length]);
	NSUInteger replacements = 0;

	//First, \r\n becomes \n. This has to come before the duplicates are removed: two \r\n in a row have no
	//\r\r or \n\n in them, and only once they are two \n is the run one line break.
	do {
		replacements = [self replaceOccurrencesOfString:@"\r\n"
											 withString:@"\n"
												options:NSLiteralSearch
												  range:fullRange];
		fullRange.length -= replacements;
	} while (replacements > 0);

	//Then we remove duplicate linebreaks.
	do {
		replacements = [self replaceOccurrencesOfString:@"\r\r"
											 withString:@"\r"
												options:NSLiteralSearch
												  range:fullRange];
		fullRange.length -= replacements;
	} while (replacements > 0);

	do {
		replacements = [self replaceOccurrencesOfString:@"\n\n"
											 withString:@"\n"
												options:NSLiteralSearch
												  range:fullRange];
		fullRange.length -= replacements;
	} while (replacements > 0);

	//Now do the slash replacements
	replacements = [self replaceOccurrencesOfString:@"\r"
										 withString:@" / "
											options:NSLiteralSearch
											  range:fullRange];
	fullRange.length += (2 * replacements);
	
	[self replaceOccurrencesOfString:@"\n"
						  withString:@" / "
							 options:NSLiteralSearch
							   range:fullRange];
}

- (NSUInteger)replaceOccurrencesOfString:(NSString *)target withString:(NSString *)replacement options:(NSStringCompareOptions)opts
{
	return [self replaceOccurrencesOfString:target withString:replacement options:opts range:NSMakeRange(0, [self length])];
}

@end
