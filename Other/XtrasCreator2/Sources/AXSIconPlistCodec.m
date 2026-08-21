/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSIconPlistCodec.h"
#import "AXSXtraFormat.h"

#define ICON_SET_VERSION_KEY @"AdiumSetVersion"

@implementation AXSIconPlistCodec

static NSMutableDictionary *AXSDeepMutableCategories(NSDictionary *source, NSArray *categoryNames)
{
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];

	for (NSString *category in categoryNames) {
		NSDictionary *entries = source[category];
		payload[category] = ([entries isKindOfClass:[NSDictionary class]] ?
							 [entries mutableCopy] : [NSMutableDictionary dictionary]);
	}

	return payload;
}

- (id)readPayloadFromInfoDictionary:(NSDictionary *)infoDict
					   resourcesDir:(NSFileWrapper *)resourcesDir
							 format:(AXSXtraFormat *)format
							  error:(NSError **)outError
{
	if (format.payloadLivesInInfoPlist)
		return AXSDeepMutableCategories(infoDict ?: @{}, format.categoryNames);

	//Icons.plist beside the resources; every top level key except the version marker is a category
	NSFileWrapper *plistWrapper = [resourcesDir fileWrappers][format.payloadFileName];
	NSDictionary *plist = nil;

	if (plistWrapper.regularFile) {
		plist = [NSPropertyListSerialization propertyListWithData:[plistWrapper regularFileContents]
														  options:NSPropertyListImmutable
														   format:NULL
															error:outError];
		if (![plist isKindOfClass:[NSDictionary class]]) plist = nil;
	}

	NSMutableArray *allCategories = [format.categoryNames mutableCopy];
	for (NSString *key in plist) {
		if ([key isEqualToString:ICON_SET_VERSION_KEY]) continue;
		if (![allCategories containsObject:key]) [allCategories addObject:key];
	}

	return AXSDeepMutableCategories(plist ?: @{}, allCategories);
}

- (BOOL)writePayload:(id)payload
  intoInfoDictionary:(NSMutableDictionary *)infoDict
		resourcesDir:(NSFileWrapper *)resourcesDir
			  format:(AXSXtraFormat *)format
			   error:(NSError **)outError
{
	NSDictionary *categories = payload;

	if (format.payloadLivesInInfoPlist) {
		for (NSString *category in categories) {
			infoDict[category] = [categories[category] copy];
		}
		return YES;
	}

	NSMutableDictionary *plist = [NSMutableDictionary dictionary];
	plist[ICON_SET_VERSION_KEY] = @1;
	for (NSString *category in categories) {
		plist[category] = [categories[category] copy];
	}

	NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
															  format:NSPropertyListXMLFormat_v1_0
															 options:0
															   error:outError];
	if (!data) return NO;

	//Only touch the wrapper when the bytes changed, so an untouched pack stays untouched
	NSFileWrapper *existing = [resourcesDir fileWrappers][format.payloadFileName];
	if (existing && [[existing regularFileContents] isEqualToData:data])
		return YES;

	if (existing) [resourcesDir removeFileWrapper:existing];
	[resourcesDir addRegularFileWithContents:data preferredFilename:format.payloadFileName];

	return YES;
}

- (id)emptyPayloadForFormat:(AXSXtraFormat *)format
{
	return AXSDeepMutableCategories(@{}, format.categoryNames);
}

@end
