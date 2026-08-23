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

#import "AIJSXtraBundle.h"

#define KEY_IS_JS_PLUGIN			@"AIJavaScriptPlugin"
#define KEY_JS_PLUGIN_FILENAME		@"AIJavaScriptPluginFileName"
#define KEY_JS_PLUGIN_API_VERSION	@"AIJavaScriptPluginAPIVersion"

//The API version this build injects; a plugin declaring a newer one is refused
#define AIJS_SUPPORTED_API_VERSION	1

//A plugin script larger than this is refused rather than injected
#define AIJS_MAX_SOURCE_BYTES		(512 * 1024)

@interface AIJSXtraBundle ()
@property (readwrite, nonatomic) NSString *bundleIdentifier;
@property (readwrite, nonatomic) NSString *displayName;
@property (readwrite, nonatomic) NSString *version;
@property (readwrite, nonatomic) NSString *author;
@property (readwrite, nonatomic) NSString *source;
@property (readwrite, nonatomic) NSString *contentWorldName;
@end

@implementation AIJSXtraBundle

+ (instancetype)bundleWithPath:(NSString *)path
{
	NSBundle *bundle = [NSBundle bundleWithPath:path];
	if (!bundle) {
		NSLog(@"JSXtra: cannot open bundle at %@", path);
		return nil;
	}

	NSDictionary *info = [bundle infoDictionary];

	if (![info[KEY_IS_JS_PLUGIN] boolValue]) {
		//Not ours: a compiled plugin, handled elsewhere
		return nil;
	}

	NSString *identifier = [bundle bundleIdentifier];
	if (![identifier length]) {
		NSLog(@"JSXtra: %@ has no CFBundleIdentifier", path);
		return nil;
	}

	//API version: refuse anything this build does not speak
	NSInteger apiVersion = [info[KEY_JS_PLUGIN_API_VERSION] integerValue];
	if (apiVersion < 1 || apiVersion > AIJS_SUPPORTED_API_VERSION) {
		NSLog(@"JSXtra: %@ declares unsupported API version %ld", identifier, (long)apiVersion);
		return nil;
	}

	NSString *source = [self validatedSourceForBundle:bundle info:info identifier:identifier];
	if (!source) return nil;

	AIJSXtraBundle *xtra = [[self alloc] init];
	xtra.bundleIdentifier = identifier;
	xtra.displayName = info[@"CFBundleName"] ?: [[path lastPathComponent] stringByDeletingPathExtension];
	xtra.version = [info[@"XtraVersion"] description] ?: [info[@"CFBundleVersion"] description] ?: @"";
	xtra.author = [info[@"XtraAuthors"] description] ?: [info[@"OriginalAuthor"] description] ?: @"";
	xtra.source = source;
	xtra.contentWorldName = [@"adium.jsxtra." stringByAppendingString:identifier];

	return xtra;
}

/*!
 * @brief The script named by the manifest, only if it is genuinely inside Resources/
 *
 * The filename is attacker-controlled data from a downloaded bundle, so it is
 * resolved and checked to sit under the bundle's own Resources directory: an
 * absolute path, a "../" climb, or a symlink out is refused, not followed.
 */
+ (NSString *)validatedSourceForBundle:(NSBundle *)bundle info:(NSDictionary *)info identifier:(NSString *)identifier
{
	NSString *fileName = info[KEY_JS_PLUGIN_FILENAME];
	if (![fileName isKindOfClass:[NSString class]] || ![fileName length]) {
		NSLog(@"JSXtra: %@ names no script file", identifier);
		return nil;
	}

	//No absolute paths, no path separators at all: a plain file name in Resources/
	if ([fileName isAbsolutePath] || [fileName rangeOfString:@"/"].location != NSNotFound ||
		[[fileName pathComponents] containsObject:@".."]) {
		NSLog(@"JSXtra: %@ names an unsafe script path %@", identifier, fileName);
		return nil;
	}

	NSString *resourcePath = [[bundle resourcePath] stringByStandardizingPath];
	NSString *candidate = [[[resourcePath stringByAppendingPathComponent:fileName]
						   stringByResolvingSymlinksInPath] stringByStandardizingPath];

	//After every resolution it must still live directly under Resources/
	NSString *expectedPrefix = [resourcePath stringByAppendingString:@"/"];
	if (![candidate hasPrefix:expectedPrefix] ||
		![[candidate stringByDeletingLastPathComponent] isEqualToString:resourcePath]) {
		NSLog(@"JSXtra: %@ script resolves outside Resources: %@", identifier, candidate);
		return nil;
	}

	NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:candidate error:NULL];
	if (!attributes) {
		NSLog(@"JSXtra: %@ script file is missing: %@", identifier, candidate);
		return nil;
	}
	if ([attributes fileSize] > AIJS_MAX_SOURCE_BYTES) {
		NSLog(@"JSXtra: %@ script is too large (%llu bytes)", identifier, [attributes fileSize]);
		return nil;
	}

	NSData *data = [NSData dataWithContentsOfFile:candidate];
	NSString *source = (data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil);
	if (!source) {
		NSLog(@"JSXtra: %@ script is not valid UTF-8", identifier);
		return nil;
	}

	return source;
}

@end
