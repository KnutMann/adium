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

#import "AIXtraInfo.h"
#import <Adium/AIDockControllerProtocol.h>
#import "AIIconState.h"

@interface AIXtraInfo ()
- (NSString *)manifestStringForKey:(NSString *)key;
- (NSString *)soundSetCreator;
- (NSString *)soundSetDescription;
@end

@implementation AIXtraInfo

- (NSString *)type
{
	return type;
}

- (NSString *)name
{
	return name;
}

- (NSString *)version
{
	return version;
}

- (void) setName:(NSString *)inName
{
	if(!inName) name = @"Unnamed Xtra";
	else {
		name = inName;
	}
}

- (NSString *) description
{
	return [NSString stringWithFormat:@"%@, %@, %@", [self name], [self path], [self type]];
}

+ (AIXtraInfo *) infoWithURL:(NSURL *)url
{
	return [[self alloc] initWithURL:url];
}

- (id) initWithURL:(NSURL *)url
{
	if((self = [super init]))
	{
		path = [url path];
		type = [[[url path] pathExtension] lowercaseString];
		xtraBundle = [[NSBundle alloc] initWithPath:path];

		/* An Xtra can keep its Info.plist at the root of its folder rather than in Contents/, where
		 * NSBundle is the only thing that ever looks. The script packs Adium itself ships are built
		 * that way, and GBApplescriptFiltersPlugin reads their plist by hand for exactly this
		 * reason; without the same step here such an Xtra would name no author, no version and no
		 * description, however carefully its maker filled them in. */
		if (![[xtraBundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey] length]) {
			flatInfoDictionary = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
		}

		/* XtraVersion and XtraAuthors are what the XtrasCreator writes and what packs in the
		 * wild carry; the other two names appear in a handful of older packs. */
		version = [self manifestStringForKey:@"XtraVersion"];
		if (![version length]) version = [self manifestStringForKey:@"CFBundleVersion"];
		author = [self manifestStringForKey:@"XtraAuthors"];
		if (![author length]) author = [self manifestStringForKey:@"OriginalAuthor"];
		if (xtraBundle && ([[xtraBundle objectForInfoDictionaryKey:@"XtraBundleVersion"] integerValue] == 1)) { //This checks for a new-style xtra
			[self setName:[xtraBundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey]];
			resourcePath = [xtraBundle resourcePath];
			icon = [[NSImage alloc] initByReferencingFile:[xtraBundle pathForResource:@"Icon" ofType:@"icns"]];
			readMePath = [xtraBundle pathForResource:@"ReadMe" ofType:@"rtf"];
			NSString *previewImagePath = [xtraBundle pathForImageResource:@"PreviewImage"];
			if(previewImagePath)
				previewImage = [[NSImage alloc] initByReferencingFile:previewImagePath];
		}
		else {
			if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
				return nil;
			}
			[self setName:[[path lastPathComponent] stringByDeletingPathExtension]];
			resourcePath = [path copy];//root of the xtra
		}

		/* The name its maker wrote, whether or not the Xtra is new-style. Only an Xtra declaring
		 * XtraBundleVersion 1 was ever asked, so a message style whose folder is called
		 * "renkooNaked" was listed here as "renkooNaked" while the style chooser two windows away
		 * called it "Renkoo Naked" - the chooser asks -[NSBundle name], which reads the localized
		 * CFBundleName first and the plain one second, and AISoundSet reads the same key. The
		 * fallback stays the file name rather than -[NSBundle name]'s bundle identifier, which is
		 * no name to show anybody.
		 *
		 * Emoticon packs are the one kind that names itself after its folder no matter what
		 * (AIEmoticonPack.m); none of the ones in the wild carries CFBundleName, so there is
		 * nothing here for the two to disagree about yet. */
		NSString	*written = [[xtraBundle localizedInfoDictionary] objectForKey:(NSString *)kCFBundleNameKey];

		if (![written isKindOfClass:[NSString class]])
			written = [self manifestStringForKey:(NSString *)kCFBundleNameKey];

		if ([written length]) [self setName:written];

		/* A sound set writes what it says about itself into its own Sounds.plist rather than into a
		 * bundle manifest, as one block of prose: who made it, what it is, and where it came from,
		 * in that order and separated by blank lines. Every set Adium ships is written that way and
		 * so is every one on the Xtras site. Read once here, because both the author and the
		 * description are cut out of it. */
		if ([type isEqualToString:@"adiumsoundset"]) {
			NSDictionary	*soundSet = [NSDictionary dictionaryWithContentsOfFile:[resourcePath stringByAppendingPathComponent:@"Sounds.plist"]];
			id				 prose = [soundSet objectForKey:@"Info"];

			if ([prose isKindOfClass:[NSString class]]) soundSetInfo = prose;
		}

		if (!readMePath)
			readMePath = [[NSBundle mainBundle] pathForResource:@"DefaultXtraReadme" ofType:@"rtf"];
		if (!icon) {
			if ([[path pathExtension] caseInsensitiveCompare:@"AdiumIcon"] == NSOrderedSame) {
                AIIconState *previewState = [adium.dockController previewStateForIconPackAtPath:path];
				icon = [previewState image];

			} else {
				icon = [[NSWorkspace sharedWorkspace] iconForFileType:[path pathExtension]];
			}
		}
		if(!previewImage)
			previewImage = icon;
		
		/* A script pack's real name is the name of the SET its scripts go into. That is what Adium
		 * puts in the script menu (GBApplescriptFiltersPlugin reads the same key), so a pack whose
		 * folder happens to be called "chuck" is listed here as "chuck" while the menu calls it
		 * "Chuck Norris Random Fact Generator". The set name is the one the maker wrote for people
		 * to read, so it wins - for script packs, which are the only kind carrying the key. */
		if ([type isEqualToString:@"adiumscripts"]) {
			NSString	*setName = [[xtraBundle localizedInfoDictionary] objectForKey:@"Set"];

			if (![setName isKindOfClass:[NSString class]]) setName = [self manifestStringForKey:@"Set"];
			if ([setName length]) [self setName:setName];
		}

		/* Enabled by default */
		enabled = YES;
	}
	return self;
}

- (NSImage *) icon
{
	return icon;
}

- (NSString *)resourcePath
{
	return resourcePath;
}

- (NSString *)path
{
	return path;
}

- (NSString *)readMePath
{
	return readMePath;
}

- (NSString *)author
{
	/* A dock icon pack keeps who made it in its own list rather than in the bundle's, under a key
	 * of its own, and every one of them fills it in where hardly any other kind does. Some write
	 * "Created by" in front of the name, which would read twice over once the line says "by". */
	if (!author) author = [self soundSetCreator];

	if (!author) {
		NSDictionary	*iconPack = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"IconPack.plist"]];
		NSString		*creator = [[iconPack objectForKey:@"Description"] objectForKey:@"Creator"];

		if ([creator length]) {
			NSString	*prefix = @"created by ";

			if (([creator length] > [prefix length]) &&
				([[creator substringToIndex:[prefix length]] caseInsensitiveCompare:prefix] == NSOrderedSame))
				creator = [creator substringFromIndex:[prefix length]];

			author = [creator stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		}
	}

	return author;
}

/*!
 * @brief Who a sound set says made it, or nil where it does not say
 *
 * The first line of its prose, and only when that line really is the sentence every set writes
 * there: a set whose text opens with something else keeps all of it as its description rather than
 * having its opening line taken away and shown as somebody's name. The trailing full stop of
 * "Created by America Online." goes; a name does not end in one.
 */
- (NSString *)soundSetCreator
{
	if (![soundSetInfo length]) return nil;

	NSRange		 firstBreak = [soundSetInfo rangeOfString:@"\n"];
	NSString	*firstLine = ((firstBreak.location == NSNotFound) ?
							  soundSetInfo :
							  [soundSetInfo substringToIndex:firstBreak.location]);
	NSString	*prefix = @"created by ";

	if (([firstLine length] <= [prefix length]) ||
		([[firstLine substringToIndex:[prefix length]] caseInsensitiveCompare:prefix] != NSOrderedSame))
		return nil;

	NSString	*creator = [[firstLine substringFromIndex:[prefix length]]
						    stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t."]];

	return ([creator length] ? creator : nil);
}

/*!
 * @brief What a sound set says it is, or nil where it says nothing
 *
 * Its prose without the line naming its maker, which -soundSetCreator has already taken for the
 * author. What is left is a sentence and, usually, the address the set came from; both belong in a
 * description, and neither is written anywhere else.
 */
- (NSString *)soundSetDescription
{
	if (![soundSetInfo length]) return nil;

	NSString	*remainder = soundSetInfo;

	if ([self soundSetCreator]) {
		NSRange	firstBreak = [soundSetInfo rangeOfString:@"\n"];

		remainder = ((firstBreak.location == NSNotFound) ?
					 @"" :
					 [soundSetInfo substringFromIndex:NSMaxRange(firstBreak)]);
	}

	remainder = [remainder stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	return ([remainder length] ? remainder : nil);
}

/*!
 * @brief A manifest key as a string, wherever this Xtra keeps its manifest and whatever it wrote
 *
 * Asked for as an id and checked rather than asked for as an NSString: the manifest belongs to
 * whoever made the Xtra, and a key written as a number where a string belongs would otherwise be
 * sent -length. The flat Info.plist is consulted for the Xtras which keep one; see -initWithURL:.
 */
- (NSString *)manifestStringForKey:(NSString *)key
{
	id	written = [xtraBundle objectForInfoDictionaryKey:key];

	if (![written isKindOfClass:[NSString class]]) written = [flatInfoDictionary objectForKey:key];

	return ([written isKindOfClass:[NSString class]] ? written : nil);
}

/*!
 * @brief What the Xtra says it is; see the header for where it is read from
 */
- (NSString *)xtraDescription
{
	NSString	*summary = [self manifestStringForKey:@"XtraDescription"];

	if ([summary length]) return summary;

	//A sound set's own prose, which is the only place it ever describes itself
	summary = [self soundSetDescription];

	if ([summary length]) return summary;

	summary = [self manifestStringForKey:@"CFBundleGetInfoString"];

	if (![summary length]) return nil;

	/* Half of the message styles Adium ships write their version number in here, and a script pack
	 * writes the folder it lives in; either would be a sentence which says nothing, standing where
	 * the description belongs. The rest of them say something real, so the key is worth reading,
	 * just not worth believing on its own: anything which merely repeats a name or a number this
	 * Xtra already carries somewhere else is thrown away.
	 *
	 * The file name is among them because a pack can be listed under a name of its own now - the
	 * set name of a script pack, say - which leaves the folder name free to turn up here and read
	 * as a description. */
	NSArray		*saidElsewhere = [NSArray arrayWithObjects:
								  ([self version] ?: @""),
								  ([self manifestStringForKey:@"CFBundleVersion"] ?: @""),
								  ([self name] ?: @""),
								  ([self manifestStringForKey:(NSString *)kCFBundleNameKey] ?: @""),
								  ([[path lastPathComponent] stringByDeletingPathExtension] ?: @""),
								  nil];

	if ([saidElsewhere containsObject:summary]) return nil;

	return summary;
}

- (NSBundle *)bundle
{
	return xtraBundle;
}

- (NSImage *)previewImage
{
	return previewImage;
}

- (BOOL)enabled
{
	return enabled;
}

- (void)setEnabled:(BOOL)inEnabled
{
	enabled = inEnabled;
}

@end
