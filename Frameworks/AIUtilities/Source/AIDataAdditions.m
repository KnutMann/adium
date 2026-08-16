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

#import "AIDataAdditions.h"

@implementation NSData(AIDataAdditions)

- (NSData *)subdataFromIndex:(NSUInteger)start {
	return [self subdataWithRange:NSMakeRange(start, [self length] - start)];
}
- (NSData *)subdataToIndex:(NSUInteger)stop {
	return [self subdataWithRange:NSMakeRange(0, stop)];
}

@end

@implementation NSKeyedArchiver (AIDataAdditions)

/* Archives without secure coding so the output stays byte-compatible with the archives
 * the deprecated +archivedDataWithRootObject: produced (existing user statuses,
 * bookmarks, etc. must remain readable by this and older Adium versions).
 */
+ (NSData *)archivedDataWithObject:(id)object
{
	NSError *error = nil;
	NSData *data = [self archivedDataWithRootObject:object requiringSecureCoding:NO error:&error];
	if (!data) {
		NSLog(@"AIDataAdditions: Failed to archive %@: %@", object, error);
	}
	return data;
}

@end

@implementation NSKeyedUnarchiver (AIDataAdditions)

/* Decodes the root object without secure coding, matching the behavior of the deprecated
 * +unarchiveObjectWithData: — requiring secure coding would break loading of existing
 * user archives whose classes are not whitelisted.
 */
+ (id)objectWithArchivedData:(NSData *)data
{
	if (!data) return nil;

	NSError *error = nil;
	NSKeyedUnarchiver *unarchiver = [[self alloc] initForReadingFromData:data error:&error];
	if (!unarchiver) {
		NSLog(@"AIDataAdditions: Failed to create unarchiver: %@", error);
		return nil;
	}
	[unarchiver setRequiresSecureCoding:NO];
	return [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
}

@end
