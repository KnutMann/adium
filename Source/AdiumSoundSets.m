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

#import "AdiumSoundSets.h"
#import "AISoundController.h"
#import "AISoundSet.h"

#define SOUNDSET_RESOURCE_PATH			@"Sounds"

#define	SOUND_PACK_PATHNAME				@"AdiumSetPathname_Private"
#define	SOUND_PACK_VERSION				@"AdiumSetVersion"
#define SOUND_NAMES						@"Sounds"
#define SOUND_SET_PATH_EXTENSION		@"AdiumSoundSet"

@implementation AdiumSoundSets

/*!
 * @brief Init
 */
- (id)init {
	if ((self = [super init])) {
		//Create a custom sounds directory ~/Library/Application Support/Adium 2.0/Sounds
		[adium createResourcePathForName:SOUNDSET_RESOURCE_PATH];
	}
	
	return self;
}

/*!
 * @brief Returns all available soundsets
 *
 * @return NSArray of AISoundSet objects
 */
- (NSArray *)soundSets
{
	NSFileManager	*mgr = [NSFileManager defaultManager];
    NSMutableArray	*soundSets = [NSMutableArray array];
	
	/* One name, one set. Adium ships Tokyo Train Station, and installing the copy from the
	 * Xtras site put the same name in the menu twice with no way to tell them apart.
	 * -resourcePathsForName: hands us the user's folder first and the bundle last, so keeping
	 * the first of a name lets the installed copy win - the right one, because it is the copy
	 * the Xtras pane can switch off or throw away.
	 *
	 * Deliberately after -soundSetWithContentsOfFile: has returned something: a damaged copy in
	 * the user's folder must not hide the working one in the bundle, which is what deciding by
	 * file name alone would do. */
	NSMutableSet *seenNames = [NSMutableSet set];

	for (NSString *path in [adium resourcePathsForName:SOUNDSET_RESOURCE_PATH]) {
		for (NSString *file in [mgr contentsOfDirectoryAtPath:path error:NULL]) {
			if([[file pathExtension] caseInsensitiveCompare:SOUND_SET_PATH_EXTENSION] == NSOrderedSame){
				NSString	*fullPath = [path stringByAppendingPathComponent:file];
				AISoundSet	*soundSet = [AISoundSet soundSetWithContentsOfFile:fullPath];
				if (soundSet) {
					/* Compared by the name the menu shows, folded and case-insensitively: the
					 * file systems this runs on are, and a name typed on one machine may be
					 * composed differently from the same name unpacked from an archive. */
					NSString *key = [[soundSet name] ?: [file stringByDeletingPathExtension] precomposedStringWithCanonicalMapping].lowercaseString;

					if (![seenNames containsObject:key]) {
						[seenNames addObject:key];
						[soundSets addObject:soundSet];
					}
				}
			}
		}
	}
    
    return soundSets;
}

@end
