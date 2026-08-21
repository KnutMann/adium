/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSLintEngine.h"
#import "AXSXtraDocument.h"

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
			if (![entries[key] isKindOfClass:[NSString class]] || ![entries[key] length]) {
				[issues addObject:[AXSLintIssue issueWithLevel:AXSLintLevelError
													   message:[NSString stringWithFormat:
																@"%@ is missing the required entry \"%@\".", category, key]]];
			}
		}
	}

	if ([payload isKindOfClass:[NSDictionary class]]) {
		//Entries naming files the pack does not carry
		for (NSString *category in payload) {
			if ([category isEqualToString:@"Colors"]) continue;	//color strings, not files

			NSDictionary *entries = payload[category];
			if (![entries isKindOfClass:[NSDictionary class]]) continue;

			for (NSString *key in entries) {
				id value = entries[key];
				if (![value isKindOfClass:[NSString class]] || ![value length]) continue;

				if (!resourceFiles[value]) {
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

	return issues;
}

@end
