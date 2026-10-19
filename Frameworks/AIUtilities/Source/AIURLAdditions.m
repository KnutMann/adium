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

#import "AIURLAdditions.h"

@implementation NSURL (AIURLAdditions)

- (NSUInteger)length
{
	return [[self absoluteString] length];
}

- (NSString *)queryArgumentForKey:(NSString *)key withDelimiter:(NSString *)delimiter
{
	for (NSString *obj in [[self query] componentsSeparatedByString:delimiter]) {
		//Only the first '=' divides key from value; the value keeps any further ones (base64 padding, a nested pair).
		//The key is matched exactly, as the header says; keys in a query string are case-sensitive.
		NSRange equals = [obj rangeOfString:@"="];

		if ((equals.location != NSNotFound) && [[obj substringToIndex:equals.location] isEqualToString:key]) {
			return [obj substringFromIndex:NSMaxRange(equals)];
		}
	}
	
	return nil;
}

- (NSString *)queryArgumentForKey:(NSString *)key
{
	NSString		*delimiter;
	
	// The arguments in query strings can be delimited with a semicolon (';') or an ampersand ('&'). Since it's not
	// likely a single URL would use both types of delimeters, we'll attempt to pick one and use it.
	if ([[self query] rangeOfString:@";"].location != NSNotFound) {
		delimiter = @";";
	} else {
		// Assume '&' by default, since that's more common
		delimiter = @"&";
	}
	
	return [self queryArgumentForKey:key withDelimiter:delimiter];
}

@end
