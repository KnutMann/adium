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


@interface AIXtraInfo : NSObject {
	NSString		*name;
	NSString		*path;
	NSString		*version;
	NSString		*author;
	NSImage			*icon;
	NSImage			*previewImage;
	NSString		*resourcePath;
	NSString		*type;
	NSString		*readMePath;
	NSBundle		*xtraBundle;
	/* The manifest of an Xtra which keeps its Info.plist at the root rather than in Contents/, where
	 * NSBundle does not look; see -manifestStringForKey:. nil for every other kind. */
	NSDictionary	*flatInfoDictionary;
	/* What a sound set writes about itself in its own Sounds.plist; nil for every other kind */
	NSString		*soundSetInfo;

	BOOL			enabled;
}

+ (AIXtraInfo *) infoWithURL:(NSURL *)url;
- (id) initWithURL:(NSURL *)url;

- (NSString *)type;
- (NSString *)path;
- (NSString *)name;
- (NSString *)version;

/*!
 * @brief Who made it, or nil where the Xtra does not say
 *
 * Read from OriginalAuthor, which is what the Xtras of this world actually carry: half of the ones
 * shipped with Adium name somebody there, and none of them ships the read me where an author would
 * otherwise have to be looked for.
 */
- (NSString *)author;

/*!
 * @brief What the Xtra says it is, in a sentence, or nil where it says nothing
 *
 * Read from XtraDescription, which is where an Xtra that means to describe itself puts it, and
 * failing that from CFBundleGetInfoString - a key which the Xtras of this world fill in with all
 * sorts of things, the version number, the bundle name and the folder name among them, so it is
 * used only where it says something none of those already says.
 *
 * Most Xtras in the wild carry neither, which is why this is allowed to be nil rather than made up
 * out of the fields that are there.
 */
- (NSString *)xtraDescription;

- (NSString *)resourcePath;
- (NSString *)readMePath;
- (NSImage *)icon;
- (NSImage *)previewImage;
- (void)setName:(NSString *)name;
- (NSBundle *)bundle; //returns nil if no bundle is available

- (BOOL)enabled;
- (void)setEnabled:(BOOL)inEnabled;
@end
