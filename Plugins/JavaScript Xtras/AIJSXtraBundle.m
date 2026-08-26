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

#define KEY_JS_PLUGIN_SETTINGS		@"AIJavaScriptPluginSettings"

/* Caps on a settings block. Every count a downloaded manifest controls needs a ceiling, for the
 * same reason AIJS_MAX_SOURCE_BYTES has one. Eight settings is more than any plausible extension
 * and far below "a page taller than the display"; eight options is a pop-up menu, five thousand is
 * a menu that takes a second to build. */
#define AIJS_MAX_SETTINGS			8
#define AIJS_MAX_OPTIONS			8
#define AIJS_MAX_TITLE_LENGTH		60
#define AIJS_MAX_DETAIL_LENGTH		160

@interface AIJSXtraSetting ()
@property (readwrite, nonatomic) NSString *key;
@property (readwrite, nonatomic) NSString *title;
@property (readwrite, nonatomic) NSString *detail;
@property (readwrite, nonatomic) NSString *defaultValue;
@property (readwrite, nonatomic) NSArray<NSString *> *optionValues;
@property (readwrite, nonatomic) NSArray<NSString *> *optionTitles;
@end

@implementation AIJSXtraSetting

- (NSString *)coercedValue:(id)value
{
	if ([value isKindOfClass:[NSString class]] && [self.optionValues containsObject:value])
		return value;

	return self.defaultValue;
}

@end

//Every character of a non-empty string is in @a allowed
static BOOL AIJSStringIsMadeOf(NSString *string, NSCharacterSet *allowed)
{
	return ([string length] > 0 &&
			[string rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound);
}

@interface AIJSXtraBundle ()
@property (readwrite, nonatomic) NSString *bundleIdentifier;
@property (readwrite, nonatomic) NSString *displayName;
@property (readwrite, nonatomic) NSString *version;
@property (readwrite, nonatomic) NSString *author;
@property (readwrite, nonatomic) NSString *source;
@property (readwrite, nonatomic) NSString *contentWorldName;
@property (readwrite, nonatomic) NSArray<AIJSXtraSetting *> *settings;
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

	/* nil means malformed, an empty array means none declared - the normal case for three of the
	 * five plugins Adium ships. */
	NSArray *settings = [self validatedSettingsForBundle:bundle info:info identifier:identifier];
	if (!settings) return nil;

	AIJSXtraBundle *xtra = [[self alloc] init];
	xtra.bundleIdentifier = identifier;
	xtra.displayName = info[@"CFBundleName"] ?: [[path lastPathComponent] stringByDeletingPathExtension];
	xtra.version = [info[@"XtraVersion"] description] ?: [info[@"CFBundleVersion"] description] ?: @"";
	xtra.author = [info[@"XtraAuthors"] description] ?: [info[@"OriginalAuthor"] description] ?: @"";
	xtra.source = source;
	xtra.contentWorldName = [@"adium.jsxtra." stringByAppendingString:identifier];
	xtra.settings = settings;

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

/*!
 * @brief The settings the manifest declares, validated, or nil on any fault
 *
 * An empty array where the manifest declares none, which is the normal case. Anything present but
 * malformed refuses the WHOLE bundle rather than dropping the one bad row, the way a bad script
 * path and an oversized script already do; the contract this file keeps is stated in one line at
 * AIJSXtraBundle.h. A silently dropped row would leave the plugin running on a value the user can
 * neither see nor change, which is the very thing settings exist to end.
 *
 * ONE TYPE, deliberately. A setting is a choice among strings the manifest itself listed, and the
 * enumeration IS the validation: every value that ever reaches a plugin is a member of a set
 * written down in a file we already read and checked, so nothing downstream clamps a number,
 * refuses a NaN, or has to know that [@1 isEqual:@YES] is YES in Foundation. It also keeps every
 * value a scalar, which is what makes the preamble's Object.freeze on the settings object a
 * complete freeze rather than a shallow one.
 *
 * A "number" or "switch" type is a later decision, and a deliberately cheap one: a range check
 * here, a row kind in the settings UI. Until an extension has a value that genuinely reads badly
 * as a menu, neither buys anything.
 *
 * There is no free-text type, and there will never be an obscured-text one. A settings page for
 * extensions downloaded off the web is a phishing surface, and a row that looks like a place to
 * type a password is the last thing to put on it. Whoever adds the fourth type should read this
 * paragraph first.
 */
+ (NSArray *)validatedSettingsForBundle:(NSBundle *)bundle info:(NSDictionary *)info identifier:(NSString *)identifier
{
	id declared = info[KEY_JS_PLUGIN_SETTINGS];
	if (!declared) return @[];

	if (![declared isKindOfClass:[NSArray class]]) {
		NSLog(@"JSXtra: %@ declares settings that are not a list", identifier);
		return nil;
	}
	if ([declared count] > AIJS_MAX_SETTINGS) {
		NSLog(@"JSXtra: %@ declares %lu settings, at most %d are read",
			  identifier, (unsigned long)[declared count], AIJS_MAX_SETTINGS);
		return nil;
	}

	static NSSet *settingKeys = nil;
	static NSSet *optionKeys = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		settingKeys = [NSSet setWithObjects:@"Key", @"Type", @"Title", @"Detail", @"Default", @"Options", nil];
		optionKeys = [NSSet setWithObjects:@"Value", @"Title", nil];
	});

	NSMutableArray	*settings = [NSMutableArray array];
	NSMutableSet	*seenKeys = [NSMutableSet set];

	for (id element in declared) {
		if (![element isKindOfClass:[NSDictionary class]]) {
			NSLog(@"JSXtra: %@ declares a setting which is not a dictionary", identifier);
			return nil;
		}
		NSDictionary *declaration = element;

		/* An unrecognised key is a manifest written for a newer Adium, and the API version is how a
		 * manifest says that. Refusing here rather than ignoring is what keeps that the one honest
		 * signal. */
		for (NSString *presentKey in declaration) {
			if (![settingKeys containsObject:presentKey]) {
				NSLog(@"JSXtra: %@ declares a setting with the unknown key %@", identifier, presentKey);
				return nil;
			}
		}

		NSString *key = [self validatedSettingKey:declaration[@"Key"] identifier:identifier];
		if (!key) return nil;

		if ([seenKeys containsObject:key]) {
			//Last-wins would put two rows on the page editing one value
			NSLog(@"JSXtra: %@ declares the setting %@ twice", identifier, key);
			return nil;
		}
		[seenKeys addObject:key];

		if (![declaration[@"Type"] isKindOfClass:[NSString class]] ||
			![declaration[@"Type"] isEqualToString:@"choice"]) {
			NSLog(@"JSXtra: %@ setting %@ declares the unsupported type %@ (this build reads \"choice\")",
				  identifier, key, declaration[@"Type"]);
			return nil;
		}

		NSString *title = [self validatedDisplayText:declaration[@"Title"] bundle:bundle
										   maxLength:AIJS_MAX_TITLE_LENGTH identifier:identifier];
		if (!title) return nil;

		NSString *detail = nil;
		if (declaration[@"Detail"]) {
			detail = [self validatedDisplayText:declaration[@"Detail"] bundle:bundle
									  maxLength:AIJS_MAX_DETAIL_LENGTH identifier:identifier];
			if (!detail) return nil;
		}

		id declaredOptions = declaration[@"Options"];
		if (![declaredOptions isKindOfClass:[NSArray class]] ||
			[declaredOptions count] < 2 || [declaredOptions count] > AIJS_MAX_OPTIONS) {
			//One option is not a choice, and more than eight is not a menu
			NSLog(@"JSXtra: %@ setting %@ offers no usable list of options", identifier, key);
			return nil;
		}

		NSMutableArray	*optionValues = [NSMutableArray array];
		NSMutableArray	*optionTitles = [NSMutableArray array];

		for (id optionElement in declaredOptions) {
			if (![optionElement isKindOfClass:[NSDictionary class]]) {
				NSLog(@"JSXtra: %@ setting %@ has an option which is not a dictionary", identifier, key);
				return nil;
			}
			NSDictionary *option = optionElement;

			for (NSString *presentKey in option) {
				if (![optionKeys containsObject:presentKey]) {
					NSLog(@"JSXtra: %@ setting %@ has an option with the unknown key %@", identifier, key, presentKey);
					return nil;
				}
			}

			NSString *value = [self validatedOptionValue:option[@"Value"] setting:key identifier:identifier];
			if (!value) return nil;

			if ([optionValues containsObject:value]) {
				NSLog(@"JSXtra: %@ setting %@ offers the value %@ twice", identifier, key, value);
				return nil;
			}

			NSString *optionTitle = [self validatedDisplayText:option[@"Title"] bundle:bundle
													 maxLength:AIJS_MAX_TITLE_LENGTH identifier:identifier];
			if (!optionTitle) return nil;

			/* Two options which read alike are not a cosmetic problem: -[NSPopUpButton
			 * addItemWithTitle:] REMOVES an item already carrying that title, so a menu built from
			 * these titles would come out shorter than the list of options behind it and every
			 * position after the collision would name the wrong value. Checked against what will be
			 * displayed, which is why it happens after the localized lookup. */
			if ([optionTitles containsObject:optionTitle]) {
				NSLog(@"JSXtra: %@ setting %@ offers two options both reading \"%@\"", identifier, key, optionTitle);
				return nil;
			}

			[optionValues addObject:value];
			[optionTitles addObject:optionTitle];
		}

		/* A setting with no default, or one it does not offer, has nothing to hand a plugin before
		 * the user has ever opened its page. */
		id defaultValue = declaration[@"Default"];
		if (![defaultValue isKindOfClass:[NSString class]] || ![optionValues containsObject:defaultValue]) {
			NSLog(@"JSXtra: %@ setting %@ defaults to something it does not offer", identifier, key);
			return nil;
		}

		AIJSXtraSetting *setting = [[AIJSXtraSetting alloc] init];
		setting.key = key;
		setting.title = title;
		setting.detail = detail;
		setting.defaultValue = defaultValue;
		setting.optionValues = optionValues;
		setting.optionTitles = optionTitles;

		[settings addObject:setting];
	}

	return settings;
}

/*!
 * @brief A setting's key, or nil
 *
 * A plain JavaScript identifier, so a plugin can write adiumPlugin.settings.placement, and so the
 * same string is safe as a key in Adium's preference plist and in JSON.
 *
 * The leading-letter rule is doing real work rather than decoration: it is what bars "__proto__",
 * which in a JavaScript OBJECT LITERAL is the prototype setter and not a data key. That is the
 * first of three fences and the only one anybody has to remember - the value arrives through
 * JSON.parse, which gives "__proto__" no special meaning, and the preamble copies it onto an object
 * created with no prototype at all - but refusing it here costs nothing and is the one that shows
 * up in a log.
 */
+ (NSString *)validatedSettingKey:(id)candidate identifier:(NSString *)identifier
{
	static NSCharacterSet *head = nil;
	static NSCharacterSet *tail = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		head = [NSCharacterSet characterSetWithCharactersInString:
				@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
		tail = [NSCharacterSet characterSetWithCharactersInString:
				@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"];
	});

	if (![candidate isKindOfClass:[NSString class]] ||
		[candidate length] < 1 || [candidate length] > 32 ||
		![head characterIsMember:[candidate characterAtIndex:0]] ||
		!AIJSStringIsMadeOf(candidate, tail)) {
		NSLog(@"JSXtra: %@ declares a setting whose key is not a plain identifier: %@", identifier, candidate);
		return nil;
	}

	return candidate;
}

/*!
 * @brief One option's value, or nil
 *
 * The token that lands in the plugin's JavaScript and in Adium's preference file. Held to letters,
 * digits, dot, dash and underscore, which is the rule the whole feature rests on: such a token
 * carries no quote, no backslash, no line terminator, no angle bracket, no brace and no direction
 * override, so it is already safe as source text before anything escapes it, and safe in the CSS a
 * careless plugin might splice it into - Read Receipts does exactly that. I cannot audit a
 * third-party plugin's code; I can guarantee what reaches it. Same reasoning as the script filename
 * above, which is refused outright for containing "/" rather than sanitised. Whoever wants a
 * free-text setting is removing this.
 */
+ (NSString *)validatedOptionValue:(id)candidate setting:(NSString *)settingKey identifier:(NSString *)identifier
{
	static NSCharacterSet *allowed = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		allowed = [NSCharacterSet characterSetWithCharactersInString:
				   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"];
	});

	if (![candidate isKindOfClass:[NSString class]] || [candidate length] > 64 ||
		!AIJSStringIsMadeOf(candidate, allowed)) {
		NSLog(@"JSXtra: %@ setting %@ offers the unusable value %@", identifier, settingKey, candidate);
		return nil;
	}

	return candidate;
}

/*!
 * @brief A manifest string fit to put on screen, or nil
 *
 * These are the first manifest strings Adium ever sets as labels in its own settings window, next
 * to labels Adium wrote itself. Three things are refused, each for its own reason:
 *
 *   too long        the Xtra page shares one label column across every card and that column never
 *                   gives width back, so one long title widens the whole page for good; a label
 *                   wraps rather than clipping, so it also grows a row without bound.
 *   control chars   a newline turns one row into several, and NUL, U+2028 and U+2029 have no
 *                   business in a label at all.
 *   bidi overrides  U+202A-202E and U+2066-2069 let a title render as text its author did not
 *                   write. Everywhere else a plugin's deceptions are its own business - it already
 *                   owns everything the transcript shows, which the threat model at the top of
 *                   AIJSXtrasManager.m concedes in as many words - but this is Adium's window, and
 *                   the whole point of putting these rows in a card of their own under a header
 *                   Adium wrote is that the boundary between the two stays visible.
 *
 * The plugin's own Localizable.strings is consulted first, so an author may ship translations of
 * their labels; it returns the string unchanged where there is no table, which is every plugin
 * today. The lookup happens BEFORE the checks on purpose, and the order is the whole rule: a
 * .strings file inside a downloaded bundle is exactly as untrusted as the manifest, so validating
 * the English and then displaying the German would check nothing at all. Only these display strings
 * are looked up; Key, Type, Default and Value never are, because a value injected into a plugin
 * must not differ by system language.
 */
+ (NSString *)validatedDisplayText:(id)candidate bundle:(NSBundle *)bundle
						 maxLength:(NSUInteger)maxLength identifier:(NSString *)identifier
{
	if (![candidate isKindOfClass:[NSString class]]) {
		NSLog(@"JSXtra: %@ declares a setting label which is not text", identifier);
		return nil;
	}

	NSString *text = [bundle localizedStringForKey:candidate value:candidate table:nil];

	if (![[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] ||
		[text length] > maxLength) {
		NSLog(@"JSXtra: %@ declares a setting label of an unusable length (%lu)",
			  identifier, (unsigned long)[text length]);
		return nil;
	}

	static NSCharacterSet *refused = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableCharacterSet *set = [[NSCharacterSet controlCharacterSet] mutableCopy];
		[set formUnionWithCharacterSet:[NSCharacterSet illegalCharacterSet]];
		/* Spelled out rather than left to how Foundation happens to classify them: the line and
		 * paragraph separators are neither control nor format characters, and the direction
		 * overrides are too important to this rule to be covered only by implication. */
		[set addCharactersInString:@"\u2028\u2029\u202A\u202B\u202C\u202D\u202E\u2066\u2067\u2068\u2069"];
		refused = [set copy];
	});

	if ([text rangeOfCharacterFromSet:refused].location != NSNotFound) {
		NSLog(@"JSXtra: %@ declares a setting label carrying a control or direction-override character", identifier);
		return nil;
	}

	return text;
}

@end
