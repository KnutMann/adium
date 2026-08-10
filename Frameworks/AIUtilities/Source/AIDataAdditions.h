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

@interface NSData(AIDataAdditions)

- (NSData *)subdataFromIndex:(NSUInteger)start;
- (NSData *)subdataToIndex:(NSUInteger)stop;

@end

/* Replacements for the deprecated +[NSKeyedArchiver archivedDataWithRootObject:] and
 * +[NSKeyedUnarchiver unarchiveObjectWithData:]. They deliberately archive/decode
 * WITHOUT secure coding: the produced archives stay byte-compatible with existing user
 * archives (saved statuses, bookmarks, window states), and requiring secure coding would
 * mean whitelisting every archived class — a migration break for old preference files.
 */
@interface NSKeyedArchiver (AIDataAdditions)
+ (NSData *)archivedDataWithObject:(id)object;
@end

@interface NSKeyedUnarchiver (AIDataAdditions)
+ (id)objectWithArchivedData:(NSData *)data;
@end
