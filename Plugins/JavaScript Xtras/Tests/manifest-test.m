/* Where the manifest rules stop being prose.
 *
 * AIJSXtraBundle reads a file a stranger wrote and decides whether Adium will
 * run it. Until now nothing tested that decision, which is exactly why a
 * setting could sit hardcoded in a shipped plugin for as long as it did. This
 * builds real .AdiumPlugin bundles in a temporary folder and asks
 * +bundleWithPath: about them: one good manifest, whose settings are then
 * checked field by field, and a table of hostile ones which must every one come
 * back nil.
 *
 * The second group tests AIJSXtrasSettingsScript, the one place in this feature
 * where data becomes source text. It is deliberately asserted against inputs
 * the validator would already have refused, so that loosening a rule upstream
 * cannot quietly make it unsafe.
 *
 * No WebView, no Adium: AIJSXtraBundle.m imports nothing but its own header and
 * Cocoa, so this links standalone and runs in milliseconds.
 */
#import <Cocoa/Cocoa.h>

#import "../AIJSXtraBundle.h"
#import "../AIJSXtrasPreamble.h"

static int fails = 0;

static void ok(BOOL condition, const char *what)
{
	printf("%s %s\n", condition ? "ok  " : "FAIL", what);
	if (!condition) fails++;
}

/*!
 * @brief Write a .AdiumPlugin carrying @a info and return its path
 */
static NSString *BundleWithInfo(NSDictionary *info, NSString *name)
{
	NSString		*root = [NSTemporaryDirectory() stringByAppendingPathComponent:
							 [NSString stringWithFormat:@"jsxtra-manifest-test/%@.AdiumPlugin", name]];
	NSString		*resources = [root stringByAppendingPathComponent:@"Contents/Resources"];
	NSFileManager	*files = [NSFileManager defaultManager];

	[files removeItemAtPath:root error:NULL];
	[files createDirectoryAtPath:resources withIntermediateDirectories:YES attributes:nil error:NULL];

	[@"(function(){})();\n" writeToFile:[resources stringByAppendingPathComponent:@"plugin.js"]
							 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[info writeToFile:[root stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];

	return root;
}

/*!
 * @brief A manifest that passes, with @a settings put under the settings key
 */
static NSDictionary *ManifestWithSettings(id settings)
{
	NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
		@"AIJavaScriptPlugin": @YES,
		@"AIJavaScriptPluginFileName": @"plugin.js",
		@"AIJavaScriptPluginAPIVersion": @1,
		@"CFBundleIdentifier": @"com.example.test",
		@"CFBundleName": @"Test",
	}];

	if (settings) info[@"AIJavaScriptPluginSettings"] = settings;

	return info;
}

//One well-formed setting, which the hostile cases below then break one way at a time
static NSDictionary *GoodSetting(void)
{
	return @{
		@"Key": @"placement",
		@"Type": @"choice",
		@"Title": @"Tick position",
		@"Default": @"time-before",
		@"Options": @[
			@{ @"Value": @"time-before", @"Title": @"Before the time" },
			@{ @"Value": @"message", @"Title": @"After the message" },
		],
	};
}

static NSMutableDictionary *SettingBreaking(NSString *key, id value)
{
	NSMutableDictionary *setting = [GoodSetting() mutableCopy];

	if (value) setting[key] = value;
	else [setting removeObjectForKey:key];

	return setting;
}

/*!
 * @brief Assert that a manifest carrying @a settings is refused
 *
 * Every case gets a folder of its own, and that is not tidiness: NSBundle hands back the same
 * cached instance for a path it has already seen, so writing each manifest over the last one would
 * have every case after the first silently re-testing the first one - and passing, which is worse
 * than failing.
 */
static void refuses(id settings, const char *what)
{
	static NSUInteger	 caseNumber = 0;
	NSString			*path = BundleWithInfo(ManifestWithSettings(settings),
											   [NSString stringWithFormat:@"hostile-%lu", (unsigned long)caseNumber++]);

	ok([AIJSXtraBundle bundleWithPath:path] == nil, what);
}

static void testManifests(void)
{
	printf("== a manifest which passes\n");

	NSString		*path = BundleWithInfo(ManifestWithSettings(@[GoodSetting()]), @"good");
	AIJSXtraBundle	*bundle = [AIJSXtraBundle bundleWithPath:path];

	ok(bundle != nil, "the good manifest is accepted");
	ok([bundle.settings count] == 1, "it carries one setting");

	AIJSXtraSetting *setting = [bundle.settings firstObject];

	ok([setting.key isEqualToString:@"placement"], "the key survives");
	ok([setting.title isEqualToString:@"Tick position"], "the title survives");
	ok(setting.detail == nil, "an absent detail stays nil");
	ok([setting.defaultValue isEqualToString:@"time-before"], "the default survives");
	ok([setting.optionValues isEqualToArray:(@[@"time-before", @"message"])], "the values keep the author's order");
	ok([setting.optionTitles isEqualToArray:(@[@"Before the time", @"After the message"])], "so do the titles");
	ok([[setting coercedValue:@"message"] isEqualToString:@"message"], "an offered value is kept");
	ok([[setting coercedValue:@"gone"] isEqualToString:@"time-before"], "one it no longer offers falls back");
	ok([[setting coercedValue:@42] isEqualToString:@"time-before"], "so does something that is not a string");
	ok([[setting coercedValue:nil] isEqualToString:@"time-before"], "and so does nothing at all");

	//A plugin declaring nothing is the normal case and must still load
	path = BundleWithInfo(ManifestWithSettings(nil), @"none");
	bundle = [AIJSXtraBundle bundleWithPath:path];
	ok(bundle != nil && [bundle.settings count] == 0, "a plugin declaring no settings loads with none");

	printf("== manifests which must be refused\n");

	refuses(@{ @"placement": GoodSetting() }, "settings written as a dictionary");
	refuses(@[@"placement"], "a setting which is a string");

	NSMutableArray *nine = [NSMutableArray array];
	for (NSUInteger i = 0; i < 9; i++) {
		NSMutableDictionary *setting = [GoodSetting() mutableCopy];
		setting[@"Key"] = [NSString stringWithFormat:@"key%lu", (unsigned long)i];
		[nine addObject:setting];
	}
	refuses(nine, "nine settings");

	NSMutableDictionary *unknownKey = [GoodSetting() mutableCopy];
	unknownKey[@"Placement"] = @"x";
	refuses(@[unknownKey], "an unknown key inside a setting");

	refuses(@[SettingBreaking(@"Key", @"__proto__")], "the key __proto__");
	refuses(@[SettingBreaking(@"Key", @"1abc")], "a key starting with a digit");
	refuses(@[SettingBreaking(@"Key", @"a-b")], "a key with a dash");
	refuses(@[SettingBreaking(@"Key", [@"" stringByPaddingToLength:40 withString:@"a" startingAtIndex:0])], "a forty character key");
	refuses(@[SettingBreaking(@"Key", nil)], "no key at all");
	refuses((@[GoodSetting(), GoodSetting()]), "two settings sharing a key");

	refuses(@[SettingBreaking(@"Type", @"Choice")], "the type Choice");
	refuses(@[SettingBreaking(@"Type", @"number")], "the type number");
	refuses(@[SettingBreaking(@"Type", nil)], "no type");

	refuses(@[SettingBreaking(@"Title", nil)], "no title");
	refuses(@[SettingBreaking(@"Title", @42)], "a title which is a number");
	refuses(@[SettingBreaking(@"Title", [@"" stringByPaddingToLength:200 withString:@"a" startingAtIndex:0])], "a two hundred character title");
	refuses(@[SettingBreaking(@"Title", @"two\nlines")], "a title with a newline");
	refuses(@[SettingBreaking(@"Title", @"start‮reversed")], "a title with a direction override");
	refuses(@[SettingBreaking(@"Detail", [@"" stringByPaddingToLength:300 withString:@"a" startingAtIndex:0])], "a three hundred character detail");

	refuses(@[SettingBreaking(@"Options", nil)], "no options");
	refuses(@[SettingBreaking(@"Options", @[@{ @"Value": @"a", @"Title": @"A" }])], "a single option");
	refuses(@[SettingBreaking(@"Options", @[@"a", @"b"])], "options which are strings");

	NSMutableArray *nineOptions = [NSMutableArray array];
	for (NSUInteger i = 0; i < 9; i++)
		[nineOptions addObject:@{ @"Value": [NSString stringWithFormat:@"v%lu", (unsigned long)i],
								  @"Title": [NSString stringWithFormat:@"T%lu", (unsigned long)i] }];
	refuses(@[SettingBreaking(@"Options", nineOptions)], "nine options");

	refuses(@[SettingBreaking(@"Options", @[@{ @"Value": @"a", @"Title": @"A", @"Detail": @"x" },
											@{ @"Value": @"b", @"Title": @"B" }])], "an unknown key inside an option");
	refuses(@[SettingBreaking(@"Options", @[@{ @"Value": @"time before", @"Title": @"A" },
											@{ @"Value": @"b", @"Title": @"B" }])], "a value with a space");
	refuses(@[SettingBreaking(@"Options", @[@{ @"Value": @"a\"b", @"Title": @"A" },
											@{ @"Value": @"b", @"Title": @"B" }])], "a value with a quote");
	refuses(@[SettingBreaking(@"Options", @[@{ @"Value": @"a\\b", @"Title": @"A" },
											@{ @"Value": @"b", @"Title": @"B" }])], "a value with a backslash");
	refuses(@[SettingBreaking(@"Options", @[@{ @"Value": @"a", @"Title": @"A" },
											@{ @"Value": @"a", @"Title": @"B" }])], "two options sharing a value");

	/* The one the pop-up menu cannot survive: -[NSPopUpButton addItemWithTitle:] removes an item
	 * already carrying that title, so a menu built from these would be shorter than the options
	 * behind it and every position after the collision would name the wrong value. */
	refuses(@[SettingBreaking(@"Options", @[@{ @"Value": @"a", @"Title": @"Same" },
											@{ @"Value": @"b", @"Title": @"Same" }])], "two options reading alike");

	refuses(@[SettingBreaking(@"Default", nil)], "no default");
	refuses(@[SettingBreaking(@"Default", @42)], "a default which is a number");
	refuses(@[SettingBreaking(@"Default", @"neither")], "a default it does not offer");
}

static void testGenerator(void)
{
	printf("== the one place data becomes source\n");

	NSString	*script = AIJSXtrasSettingsScript(@{ @"placement": @"time-before" });

	ok([script isEqualToString:@"window.__adiumXtraSettings = JSON.parse(\"{\\\"placement\\\":\\\"time-before\\\"}\");\n"],
	   "a plain pair comes out as the one shape there is");

	ok(AIJSXtrasSettingsScript(nil) == nil, "nothing in, nothing out");
	ok(AIJSXtrasSettingsScript(@{}) == nil, "an empty dictionary yields no script");
	ok(AIJSXtrasSettingsScript(@{ @"a": @" " }) == nil, "U+2028, legal in JSON and not in JavaScript, is refused");
	ok(AIJSXtrasSettingsScript(@{ @"a": @"ü" }) == nil, "so is anything else outside printable ASCII");
	ok(AIJSXtrasSettingsScript(@{ @"a": @[@"list"] }) == nil, "so is a value which is not a string");

	/* Neither of these can arrive through a validated manifest, and that is the point: the
	 * generator is asserted safe against exactly what the validator refuses, so loosening a rule
	 * upstream cannot quietly make this unsafe. */
	NSString	*nasty = AIJSXtrasSettingsScript(@{ @"a": @"say \"hi\"\\" });
	BOOL		 printable = ([nasty length] > 0);

	for (NSUInteger i = 0; i < [nasty length]; i++) {
		unichar c = [nasty characterAtIndex:i];

		if ((c < 0x20 || c > 0x7E) && c != '\n') printable = NO;
	}

	ok(printable, "quotes and backslashes come out as printable ASCII");
	ok([nasty rangeOfString:@"\\\\\\\""].location != NSNotFound, "and the quote inside is escaped twice over");
}

int main(void)
{
	@autoreleasepool {
		testManifests();
		testGenerator();

		[[NSFileManager defaultManager] removeItemAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"jsxtra-manifest-test"]
												   error:NULL];

		printf(fails ? "== %d FAILURES\n" : "== all good\n", fails);
	}

	return fails ? 1 : 0;
}
