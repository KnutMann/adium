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

#import "NSString+AIBidi.h"

@implementation NSString (AIBidi)

- (NSWritingDirection)baseWritingDirection
{
	NSUInteger length = self.length;

	for (NSUInteger i = 0; i < length; i++) {
		unichar c = [self characterAtIndex:i];

		// Strong right-to-left ranges: Hebrew through Arabic Extended,
		// plus the Hebrew/Arabic presentation forms
		if ((c >= 0x0590 && c <= 0x08FF) ||
			(c >= 0xFB1D && c <= 0xFDFF) ||
			(c >= 0xFE70 && c <= 0xFEFF)) {
			return NSWritingDirectionRightToLeft;
		}

		// Strong left-to-right: Latin, Greek, Cyrillic, most other scripts.
		// Digits, punctuation and whitespace are direction-neutral and skipped.
		if ((c >= 0x0041 && c <= 0x005A) ||
			(c >= 0x0061 && c <= 0x007A) ||
			(c >= 0x00C0 && c <= 0x058F) ||
			(c >= 0x0900 && c <= 0x1FFF) ||
			(c >= 0x2C00 && c <= 0xD7FF) ||
			(c >= 0xF900 && c <= 0xFB16)) {
			return NSWritingDirectionLeftToRight;
		}
	}

	return NSWritingDirectionNatural;
}

@end
