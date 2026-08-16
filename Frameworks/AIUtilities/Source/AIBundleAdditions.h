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

@interface NSBundle (AIBundleAdditions)

- (NSString *)name;
- (NSSet *)supportedDocumentExtensions;

/*!
 * @brief Load a nib from this bundle, exactly as -loadNibFile:externalNameTable:withZone: did
 *
 * @param nibName The nib, without extension
 * @param owner The file's owner
 * @result The top level objects, or nil if the nib could not be loaded
 *
 * Every top level object comes back holding one reference that belongs to nobody. That is not an
 * oversight: it is what the two calls this replaces both did, and what the twenty five places in
 * this application that use them are written against. Some of them take that reference over and
 * release it in -dealloc; the rest let it stand and leak the objects for as long as the process
 * runs. Which of the two each one is doing has to be decided per caller, and is a separate job from
 * getting off a pair of calls Apple deprecated in 10.8.
 */
- (NSArray *)ai_loadNibNamed:(NSString *)nibName owner:(id)owner;

/*!
 * @brief Load a nib from the owner's bundle, or failing that the main bundle
 *
 * The search order +loadNibNamed:owner: used. Ownership of the top level objects is as above.
 */
+ (NSArray *)ai_loadNibNamed:(NSString *)nibName owner:(id)owner;

@end
