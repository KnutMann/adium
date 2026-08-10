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

#define AIiTunesTrackPboardType @"CorePasteboardFlavorType 0x6974756E" /* CorePasteboardFlavorType 'itun' */

/* Replacement for the deprecated NSFilenamesPboardType constant (AdiumY pattern).
 * There is no modern 1:1 equivalent: NSPasteboardTypeFileURL carries a single file
 * URL per pasteboard item, while this legacy type carries an array of file paths in
 * one item — which is what Finder still writes for multi-file drags and what all of
 * our drag & drop code expects. Using the literal type string keeps that behavior. */
#define AINSPasteboardTypeFilenames @"NSFilenamesPboardType"

/* Replacement for the deprecated NSURLPboardType constant where the legacy
 * "Apple URL pasteboard type" flavor must be preserved byte-for-byte (e.g. when
 * writing multiple URL strings as a property list, which the modern single-URL
 * NSPasteboardTypeURL cannot represent). */
#define AINSPasteboardTypeLegacyURL @"Apple URL pasteboard type"

@interface NSPasteboard (AIPasteboardAdditions)
- (NSArray *)filesFromITunesDragPasteboard;
@end
