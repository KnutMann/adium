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

#import "AITextAttachmentAdditions.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation NSTextAttachment (AITextAttachmentAdditions)

- (BOOL)consideredImageForHFSType:(OSType)HFSTypeCode
					pathExtension:(NSString *)pathExtension
{
	/* What NSImage can open, minus PDF and Photoshop: those are "images" to NSImage but are
	 * meant to travel as files, not be inlined, which is what the callers use this answer for.
	 *
	 * The old check searched the deprecated -imageFileTypes list, a mixture of filename
	 * extensions and HFS type code strings. The type code went with that list: the modern type
	 * system has no OSType tag any more, files have not carried one in many years, and a file
	 * with neither an extension nor a type code was no image to the old check either.
	 */
	if (![pathExtension length]) return NO;

	UTType *type = [UTType typeWithFilenameExtension:pathExtension];
	if (!type) return NO;

	if ([type conformsToType:UTTypePDF] ||
		[type.identifier isEqualToString:@"com.adobe.photoshop-image"]) return NO;

	return ([[NSImage imageTypes] containsObject:type.identifier] || [type conformsToType:UTTypeImage]);
}

- (BOOL)wrapsImage
{
	NSFileWrapper	*fileWrapper = [self fileWrapper];	
	return ([self consideredImageForHFSType:[[fileWrapper fileAttributes] fileHFSTypeCode]
							  pathExtension:[[fileWrapper filename] pathExtension]]);
}

@end
