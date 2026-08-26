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

#import "AIXtrasManager.h"
#import "AIXtraInfo.h"
#import "AIXtrasPreferences.h"
#import "AIJSXtrasManager.h"
#import <Adium/AIPathUtilities.h>

@implementation AIXtrasManager

static AIXtrasManager *manager;

+ (AIXtrasManager *)sharedManager
{
	return manager;
}

- (void)installPlugin
{
	manager = self;

	/* The manager is a singleton which lives until Adium quits; a preference pane is built and torn
	 * down again every time the preferences window opens and closes. So the pane is its own object
	 * rather than this one. */
	xtrasPreferences = (AIXtrasPreferences *)[AIXtrasPreferences preferencePaneForPlugin:self];
}

#pragma mark Categories

NSInteger categorySort(id categoryA, id categoryB, void * context)
{
	return [[categoryA objectForKey:@"Name"] caseInsensitiveCompare:[categoryB objectForKey:@"Name"]];
}

- (void)loadXtras
{
	categories = [[NSMutableArray alloc] init];

	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:AIMessageStylesDirectory], @"Directory",
		AILocalizedString(@"Message Styles", "AdiumXtras category name"), @"Name",
		[NSImage imageNamed:@"AdiumMessageStyle"], @"Image", nil]];

	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:AIContactListDirectory], @"Directory",
		AILocalizedString(@"Contact List Themes", "AdiumXtras category name"), @"Name",
		[NSImage imageNamed:@"AdiumListTheme"], @"Image", nil]];


	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:AIStatusIconsDirectory], @"Directory",
		AILocalizedString(@"Status Icons", "AdiumXtras category name"), @"Name",
		[NSImage imageNamed:@"AdiumStatusIcons"], @"Image", nil]];

	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:AISoundsDirectory], @"Directory",
		AILocalizedString(@"Sound Sets", "AdiumXtras category name"), @"Name",
		[NSImage imageNamed:@"AdiumSoundset"], @"Image", nil]];

	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:AIDockIconsDirectory], @"Directory",
		AILocalizedString(@"Dock Icons", "AdiumXtras category name"), @"Name",
		[NSImage imageNamed:@"AdiumIcon"], @"Image", nil]];

	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:AIEmoticonsDirectory], @"Directory",
		AILocalizedString(@"Emoticons", "AdiumXtras category name"), @"Name",
		[NSImage imageNamed:@"AdiumEmoticonset"], @"Image", nil]];

	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:AIScriptsDirectory], @"Directory",
		AILocalizedString(@"Scripts", "AdiumXtras category name"), @"Name",
		[NSImage imageNamed:@"AdiumScripts"], @"Image", nil]];

	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:AIServiceIconsDirectory], @"Directory",
		AILocalizedString(@"Service Icons", "AdiumXtras category name"), @"Name",
		[NSImage imageNamed:@"AdiumServiceIcons"], @"Image", nil]];

	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:AIMenuBarIconsDirectory], @"Directory",
		AILocalizedString(@"Menu Bar Icons", "AdiumXtras category name"), @"Name",
		[NSImage imageNamed:@"AdiumMenuBarIcons"], @"Image", nil]];

	/* JavaScript plugins share the PlugIns folder with compiled ones but are a
	 * different kind of thing, so they get a category of their own and are kept
	 * out of the compiled Plugins one. */
	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						   [NSNumber numberWithInteger:AIPluginsDirectory], @"Directory",
						   AILocalizedString(@"Plugins", "AdiumXtras category name"), @"Name",
						   [NSImage imageNamed:@"AdiumPlugin"], @"Image",
						   [NSNumber numberWithBool:YES], @"ExcludeJavaScript", nil]];

	[categories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						   [NSNumber numberWithInteger:AIPluginsDirectory], @"Directory",
						   AILocalizedString(@"JavaScript Extensions", "AdiumXtras category name"), @"Name",
						   [NSImage imageNamed:@"AdiumPlugin"], @"Image",
						   [NSNumber numberWithBool:YES], @"JavaScriptOnly", nil]];


	[categories sortUsingFunction:categorySort context:NULL];
}

- (NSUInteger)numberOfCategories
{
	if (!categories) [self loadXtras];

	return [categories count];
}

- (NSString *)nameOfCategoryAtIndex:(NSInteger)inIndex
{
	if (inIndex < 0 || inIndex >= (NSInteger)[self numberOfCategories]) return nil;

	return [[categories objectAtIndex:inIndex] objectForKey:@"Name"];
}

- (NSUInteger)directoryOfCategoryAtIndex:(NSInteger)inIndex
{
	if (inIndex < 0 || inIndex >= (NSInteger)[self numberOfCategories]) return 0;

	return [[[categories objectAtIndex:inIndex] objectForKey:@"Directory"] unsignedIntegerValue];
}

- (NSArray *)xtrasForCategoryAtIndex:(NSInteger)inIndex
{
	if (inIndex < 0 || inIndex >= (NSInteger)[self numberOfCategories]) return nil;

	NSDictionary	*xtrasDict = [categories objectAtIndex:inIndex];
	NSArray			*xtras;

	if (!(xtras = [xtrasDict objectForKey:@"Xtras"])) {
		NSArray			*scanned = [self arrayOfXtrasAtPaths:AISearchPathForDirectories([[xtrasDict objectForKey:@"Directory"] integerValue])];
		BOOL			 javaScriptOnly = [[xtrasDict objectForKey:@"JavaScriptOnly"] boolValue];
		BOOL			 excludeJavaScript = [[xtrasDict objectForKey:@"ExcludeJavaScript"] boolValue];
		NSMutableArray	*built = [NSMutableArray array];

		/* Two categories read the same PlugIns folder: one keeps only the JavaScript plugins, the
		 * other keeps everything but them. Every other category takes what it found unchanged. */
		if (javaScriptOnly || excludeJavaScript) {
			for (AIXtraInfo *xtraInfo in scanned) {
				if ([self xtraInfoIsJavaScriptPlugin:xtraInfo] == javaScriptOnly)
					[built addObject:xtraInfo];
			}
		} else {
			[built addObjectsFromArray:scanned];
		}

		if (javaScriptOnly) {
			/* The plugins that ship with Adium sit inside the app, outside every Xtras search path,
			 * so they would never turn up here; add them by hand, and mark each row with the on/off
			 * state the manager keeps, since a JavaScript plugin is switched by preference rather
			 * than by being moved into a "(Disabled)" folder. */
			[self appendBundledJavaScriptPluginsTo:built];

			AIJSXtrasManager *jsManager = [AIJSXtrasManager sharedManager];
			for (AIXtraInfo *xtraInfo in built) {
				NSString *identifier = [[xtraInfo bundle] bundleIdentifier];
				if (identifier)
					[xtraInfo setEnabled:[jsManager isPluginEnabledWithIdentifier:identifier]];
			}
		}

		xtras = built;

		NSMutableDictionary *newDictionary = [xtrasDict mutableCopy];
		[newDictionary setObject:xtras forKey:@"Xtras"];
		[categories replaceObjectAtIndex:inIndex
							  withObject:newDictionary];
	}

	return xtras;
}

/*!
 * @brief Is this xtra a JavaScript plugin rather than a compiled one?
 */
- (BOOL)xtraInfoIsJavaScriptPlugin:(AIXtraInfo *)xtraInfo
{
	return [[[xtraInfo bundle] objectForInfoDictionaryKey:@"AIJavaScriptPlugin"] boolValue];
}

/*!
 * @brief Is the category at this index the one that gathers JavaScript plugins?
 *
 * The Xtras pane asks so it can leave the "restart Adium" footnote off that one card: a JavaScript
 * plugin is injected live and needs no restart, unlike a compiled plug-in.
 */
- (BOOL)categoryAtIndexIsJavaScript:(NSInteger)inIndex
{
	if (inIndex < 0 || inIndex >= (NSInteger)[self numberOfCategories]) return NO;

	return [[[categories objectAtIndex:inIndex] objectForKey:@"JavaScriptOnly"] boolValue];
}

/*!
 * @brief Add the JavaScript plugins that ship inside the app to @a xtras
 *
 * They live in Contents/Resources/JavaScript Plugins, which no Xtras search path reaches, so the
 * one category that shows them has to look there itself.
 */
- (void)appendBundledJavaScriptPluginsTo:(NSMutableArray *)xtras
{
	NSString		*bundledDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"JavaScript Plugins"];
	NSFileManager	*fileManager = [NSFileManager defaultManager];

	for (NSString *name in [fileManager contentsOfDirectoryAtPath:bundledDir error:NULL]) {
		if ([name hasPrefix:@"."]) continue;

		AIXtraInfo *xtraInfo = [AIXtraInfo infoWithURL:[NSURL fileURLWithPath:[bundledDir stringByAppendingPathComponent:name]]];

		if (xtraInfo && [self xtraInfoIsJavaScriptPlugin:xtraInfo])
			[xtras addObject:xtraInfo];
	}
}

/*!
 * @brief Every Xtra below @a paths, plus every Xtra parked beside them
 *
 * A switched off Xtra sits in a "<Folder> (Disabled)" folder next to the folder it belongs in.
 * AISearchPathForDirectories() never returns that folder, which is exactly what makes an Xtra in it
 * invisible to everything in Adium which looks for one; here it is read all the same, so that it can
 * be shown - greyed out, with its switch off - and switched back on again.
 */
- (NSArray *)arrayOfXtrasAtPaths:(NSArray *)paths
{
	NSMutableArray	*contents = [NSMutableArray array];
	NSFileManager	*fileManager = [NSFileManager defaultManager];

	for (NSString *path in paths) {
		for (NSString *xtraName in [fileManager contentsOfDirectoryAtPath:path error:NULL]) {
			if (![xtraName hasPrefix:@"."]) {
				AIXtraInfo *xtraInfo = [AIXtraInfo infoWithURL:[NSURL fileURLWithPath:[path stringByAppendingPathComponent:xtraName]]];

				/* -initWithURL: refuses a path which is not there any more: a dead symlink, which the
				 * directory listing names all the same, or an Xtra which went away between that listing
				 * and this line. nil in an NSArray is an exception, not an empty slot. */
				if (xtraInfo) [contents addObject:xtraInfo];
			}
		}

		NSString *disabledPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:
								  [[path lastPathComponent] stringByAppendingString:@" (Disabled)"]];
		for (NSString *xtraName in [fileManager contentsOfDirectoryAtPath:disabledPath error:NULL]) {
			if (![xtraName hasPrefix:@"."]) {
				AIXtraInfo *xtraInfo = [AIXtraInfo infoWithURL:[NSURL fileURLWithPath:[disabledPath stringByAppendingPathComponent:xtraName]]];

				if (xtraInfo) {
					[xtraInfo setEnabled:NO];
					[contents addObject:xtraInfo];
				}
			}
		}
	}

	return contents;
}

#pragma mark Creating an Xtra

+ (BOOL)createXtraBundleAtPath:(NSString *)path
{
	NSString *contentsPath  = [path stringByAppendingPathComponent:@"Contents"];
	NSString *resourcesPath = [contentsPath stringByAppendingPathComponent:@"Resources"];
	NSString *infoPlistPath = [contentsPath stringByAppendingPathComponent:@"Info.plist"];

	NSFileManager * fileManager = [NSFileManager defaultManager];
	NSString * name = [[path lastPathComponent] stringByDeletingPathExtension];
	if (![fileManager fileExistsAtPath:path]) {
		[fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
		[fileManager createDirectoryAtPath:contentsPath withIntermediateDirectories:YES attributes:nil error:NULL];

		//Info.plist
		[[NSDictionary dictionaryWithObjectsAndKeys:
			@"English", kCFBundleDevelopmentRegionKey,
			name, kCFBundleNameKey,
			@"AdIM", @"CFBundlePackageType",
			[@"com.adiumx." stringByAppendingString:name], kCFBundleIdentifierKey,
			[NSNumber numberWithInteger:1], @"XtraBundleVersion",
			@"1.0", kCFBundleInfoDictionaryVersionKey,
			nil] writeToFile:infoPlistPath atomically:YES];

		//Resources
		[fileManager createDirectoryAtPath:resourcesPath withIntermediateDirectories:YES attributes:nil error:NULL];
	}

	BOOL isDir = NO, success;
	success = [fileManager fileExistsAtPath:resourcesPath isDirectory:&isDir] && isDir;
	if (success)
		success = [fileManager fileExistsAtPath:infoPlistPath isDirectory:&isDir] && !isDir;
	return success;
}

@end
