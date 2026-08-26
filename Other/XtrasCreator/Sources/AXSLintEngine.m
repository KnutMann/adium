/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSLintEngine.h"
#import "AXSXtraDocument.h"

/*!
 * @brief Does the pack carry this file, following slashes into subfolders
 */
static BOOL AXSPackHasFile(NSFileWrapper *root, NSString *relativePath)
{
	NSFileWrapper *node = root;

	for (NSString *component in [relativePath pathComponents]) {
		if ([component isEqualToString:@"/"]) continue;
		node = [node fileWrappers][component];
		if (!node) return NO;
	}

	return YES;
}

@interface AXSLintIssue ()
@property (readwrite, nonatomic) AXSLintLevel level;
@property (readwrite, nonatomic) NSString *message;
@end

@implementation AXSLintIssue

+ (instancetype)issueWithLevel:(AXSLintLevel)level message:(NSString *)message
{
	AXSLintIssue *issue = [[self alloc] init];
	issue.level = level;
	issue.message = message;
	return issue;
}

@end

@implementation AXSLintEngine

+ (NSArray<AXSLintIssue *> *)lintDocument:(AXSXtraDocument *)document
{
	NSMutableArray *issues = [NSMutableArray array];
	AXSXtraFormat *format = document.format;
	NSDictionary *payload = document.model.payload;
	NSDictionary *resourceFiles = [document.resourcesWrapper fileWrappers];

	//Required keys, per category: without them Adium refuses or resets the pack
	for (NSString *category in format.requiredCatalog) {
		NSDictionary *entries = payload[category];
		for (NSString *key in format.requiredCatalog[category]) {
			id entry = entries[key];
			BOOL missing = (!entry || ([entry isKindOfClass:[NSString class]] && ![entry length]));

			if (missing) {
				[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelError
													   message:[NSString stringWithFormat:
																@"%@ is missing the required entry \"%@\".", category, key]]];
			}
		}
	}

	if ([payload isKindOfClass:[NSDictionary class]]) {
		//Entries naming files the pack does not carry, in the categories this format declares
		for (NSString *category in format.categoryNames) {
			if ([category isEqualToString:@"Colors"]) continue;	//color strings, not files

			NSDictionary *entries = payload[category];
			if (![entries isKindOfClass:[NSDictionary class]]) continue;

			for (NSString *key in entries) {
				id value = entries[key];
				if (![value isKindOfClass:[NSString class]] || ![value length]) continue;

				if (!AXSPackHasFile(document.resourcesWrapper, value)) {
					[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
														   message:[NSString stringWithFormat:
																	@"%@/%@ points at \"%@\", which is not in the pack.",
																	category, key, value]]];
				}
			}
		}

		//What the catalog does not know is kept, but worth a word
		NSMutableArray *foreignKeys = [NSMutableArray array];
		for (NSString *category in format.categoryNames) {
			NSDictionary *entries = payload[category];
			for (NSString *key in entries) {
				if (![format.catalog[category] containsObject:key] && ![foreignKeys containsObject:key])
					[foreignKeys addObject:key];
			}
		}
		if ([foreignKeys count]) {
			[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelInfo
												   message:[NSString stringWithFormat:
															@"Entries outside today's catalog are kept as they are: %@.",
															[foreignKeys componentsJoinedByString:@", "]]]];
		}
	}

	//Dock icons: every state's images, shared artwork excepted
	if ([format.extension isEqualToString:@"AdiumIcon"]) {
		NSDictionary *states = payload[@"State"];
		BOOL usesSharedImages = NO;

		if ([states isKindOfClass:[NSDictionary class]]) {
			for (NSString *name in states) {
				NSDictionary *entry = states[name];
				if (![entry isKindOfClass:[NSDictionary class]]) continue;

				NSArray *imageNames = ([entry[@"Images"] isKindOfClass:[NSArray class]] ? entry[@"Images"] :
									   ([entry[@"Image"] isKindOfClass:[NSString class]] ? @[entry[@"Image"]] : @[]));

				for (NSString *imageName in imageNames) {
					if ([imageName hasPrefix:@"../Shared Images/"]) {
						usesSharedImages = YES;
						continue;
					}
					if (!AXSPackHasFile(document.resourcesWrapper, imageName)) {
						[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
															   message:[NSString stringWithFormat:
																		@"State %@ points at \"%@\", which is not in the pack.",
																		name, imageName]]];
					}
				}
			}
		}

		if (usesSharedImages) {
			[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelInfo
												   message:@"Uses images from Adium's shared artwork (\"../Shared Images/\"); they live in Adium, not in the pack."]];
		}
	}

	//Script packs: every entry needs its compiled script and a keyword to trigger it
	if ([format.extension isEqualToString:@"AdiumScripts"]) {
		NSArray *scripts = payload[@"Scripts"];
		NSUInteger withoutKeyword = 0;

		if ([scripts isKindOfClass:[NSArray class]]) {
			for (NSDictionary *entry in scripts) {
				if (![entry isKindOfClass:[NSDictionary class]]) continue;

				NSString *file = [entry[@"File"] description];
				if ([file length]) {
					NSString *scptName = [file stringByAppendingPathExtension:@"scpt"];
					if (!AXSPackHasFile(document.resourcesWrapper, scptName) &&
						!AXSPackHasFile(document.resourcesWrapper, [@"Resources" stringByAppendingPathComponent:scptName])) {
						[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
															   message:[NSString stringWithFormat:
																		@"Script \"%@\" names %@, which is not in the pack.",
																		[entry[@"Title"] description] ?: file, scptName]]];
					}
				}

				if (![[entry[@"Keyword"] description] length])
					withoutKeyword++;
			}
		}

		if (withoutKeyword) {
			[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
												   message:[NSString stringWithFormat:
															@"%lu script(s) have no keyword and can never be triggered.",
															(unsigned long)withoutKeyword]]];
		}
	}

	//Sound sets: the loader raises on any version but 1
	if ([format.extension caseInsensitiveCompare:@"AdiumSoundset"] == NSOrderedSame) {
		id setVersion = payload[@"AdiumSetVersion"];
		if (setVersion && [setVersion intValue] != 1) {
			[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelError
												   message:[NSString stringWithFormat:
															@"AdiumSetVersion is %@; Adium refuses any sound set whose version is not 1.",
															setVersion]]];
		}
	}

	//Emoticon sets: what Adium's loader would silently drop or never trigger
	if ([format.extension isEqualToString:@"AdiumEmoticonset"]) {
		NSDictionary *emoticons = payload[@"Emoticons"];

		if (![emoticons isKindOfClass:[NSDictionary class]]) {
			[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelInfo
												   message:@"Not an Adium-dialect set (no Emoticons dictionary); carried through untouched."]];
		} else {
			NSUInteger displayable = 0, withoutEquivalents = 0;

			for (NSString *key in emoticons) {
				NSDictionary *entry = emoticons[key];
				if (![entry isKindOfClass:[NSDictionary class]]) continue;

				BOOL hasCharacter = [entry[@"Character"] isKindOfClass:[NSString class]] && [entry[@"Character"] length];
				BOOL hasImage = (resourceFiles[key] != nil);
				if (hasCharacter || hasImage) displayable++;

				NSArray *equivalents = entry[@"Equivalents"];
				if (![equivalents isKindOfClass:[NSArray class]] || ![equivalents count])
					withoutEquivalents++;
			}

			if ([emoticons count] && !displayable) {
				[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelError
													   message:@"No emoticon has an image or an emoji; Adium drops such a set without a word."]];
			}
			if (withoutEquivalents) {
				[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
													   message:[NSString stringWithFormat:
																@"%lu emoticon(s) have no text equivalent and can never be typed.",
																(unsigned long)withoutEquivalents]]];
			}
			if (![emoticons count]) {
				[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
													   message:@"The set is empty."]];
			}
		}
	}

	//Adium's installer refuses a status pack that shadows its default's name
	if ([format.extension isEqualToString:@"AdiumStatusIcons"]) {
		NSString *savedName = [[document.fileURL lastPathComponent] stringByDeletingPathExtension];
		if ([document.model.bundleName isEqualToString:@"Gems"] || [savedName isEqualToString:@"Gems"]) {
			[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelError
												   message:@"A status icon pack must not be called \"Gems\"; Adium refuses to install one."]];
		}
	}

	//Adium's installer has no branch for this type; the pack goes in by hand
	if ([format.extension isEqualToString:@"AdiumGroupChatStatusIcons"]) {
		[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelInfo
											   message:@"Adium cannot install this type by double click; place it in "
														 "~/Library/Application Support/Adium 2.0/Group Chat Status Icons yourself."]];
	}

	//A message style without its own identifier is invisible or clobbers another
	if (format.requiresBundleIdentifier && ![document.model.bundleIdentifier length]) {
		[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
											   message:@"No bundle identifier yet; a stable one is minted on the first save."]];
	}

	//JavaScript plugins: the source, and the one habit that would let message text become markup
	if ([format.typeName isEqualToString:@"com.adiumx.javascriptplugin"]) {
		NSString *source = [payload[@"source"] description] ?: @"";

		if (![[source stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]) {
			[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
												   message:@"The script is empty; the plugin does nothing."]];
		}

		for (NSString *sink in @[@"innerHTML", @"outerHTML", @"insertAdjacentHTML"]) {
			if ([source rangeOfString:sink].location != NSNotFound) {
				[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
													   message:[NSString stringWithFormat:
																@"The script uses %@; message text assigned to it becomes markup. Build nodes with createElement and textContent instead.", sink]]];
			}
		}
	}

	//Message styles: the two files nothing falls back for, and a default variant that exists
	if ([format.extension isEqualToString:@"AdiumMessageStyle"]) {
		for (NSString *required in @[@"Incoming/Content.html", @"main.css"]) {
			if (!AXSPackHasFile(document.resourcesWrapper, required)) {
				[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelError
													   message:[NSString stringWithFormat:
																@"%@ is missing; the style cannot render without it.", required]]];
			}
		}

		NSString *defaultVariant = [payload[@"DefaultVariant"] description];
		if ([defaultVariant length]) {
			NSString *variantPath = [NSString stringWithFormat:@"Variants/%@.css", defaultVariant];
			if (!AXSPackHasFile(document.resourcesWrapper, variantPath)) {
				[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
													   message:[NSString stringWithFormat:
																@"DefaultVariant \"%@\" has no stylesheet at %@.",
																defaultVariant, variantPath]]];
			}
		}

		if (!payload[@"MessageViewVersion"]) {
			[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelWarning
												   message:@"No MessageViewVersion; Adium treats the style as the ancient version 1."]];
		}
	}

	return issues;
}

@end
