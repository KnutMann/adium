/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSEmoticonSetCodec.h"
#import "AXSXtraFormat.h"

@implementation AXSEmoticonSetCodec

+ (BOOL)payloadIsEditable:(id)payload
{
	return [payload[@"Emoticons"] isKindOfClass:[NSDictionary class]];
}

- (id)readPayloadFromInfoDictionary:(NSDictionary *)infoDict
					   resourcesDir:(NSFileWrapper *)resourcesDir
							 format:(AXSXtraFormat *)format
							  error:(NSError **)outError
{
	NSFileWrapper *plistWrapper = [resourcesDir fileWrappers][format.payloadFileName];
	NSDictionary *plist = nil;

	if (plistWrapper.regularFile) {
		plist = [NSPropertyListSerialization propertyListWithData:[plistWrapper regularFileContents]
														  options:NSPropertyListImmutable
														   format:NULL
															error:outError];
		if (![plist isKindOfClass:[NSDictionary class]]) plist = nil;
	}

	NSMutableDictionary *payload = [plist mutableCopy] ?: [NSMutableDictionary dictionary];

	//The Adium dialect gets a deep-mutable Emoticons dict; anything else rides verbatim
	if ([plist[@"Emoticons"] isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *emoticons = [NSMutableDictionary dictionary];
		[(NSDictionary *)plist[@"Emoticons"] enumerateKeysAndObjectsUsingBlock:^(NSString *key, id entry, BOOL *stop) {
			emoticons[key] = ([entry isKindOfClass:[NSDictionary class]] ? [entry mutableCopy] : entry);
		}];
		payload[@"Emoticons"] = emoticons;
	}

	return payload;
}

- (BOOL)writePayload:(id)payload
  intoInfoDictionary:(NSMutableDictionary *)infoDict
		resourcesDir:(NSFileWrapper *)resourcesDir
			  format:(AXSXtraFormat *)format
			   error:(NSError **)outError
{
	NSMutableDictionary *plist = [payload mutableCopy] ?: [NSMutableDictionary dictionary];

	/* Only an Adium-dialect set is stamped; a Proteus pack is not rewritten
	 * into claiming a dialect it does not speak. */
	if ([AXSEmoticonSetCodec payloadIsEditable:payload] && !plist[@"AdiumSetVersion"])
		plist[@"AdiumSetVersion"] = @1;

	NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
															  format:NSPropertyListXMLFormat_v1_0
															 options:0
															   error:outError];
	if (!data) return NO;

	NSFileWrapper *existing = [resourcesDir fileWrappers][format.payloadFileName];
	if (existing && [[existing regularFileContents] isEqualToData:data])
		return YES;

	if (existing) [resourcesDir removeFileWrapper:existing];
	[resourcesDir addRegularFileWithContents:data preferredFilename:format.payloadFileName];

	return YES;
}

- (id)emptyPayloadForFormat:(AXSXtraFormat *)format
{
	return [NSMutableDictionary dictionaryWithObject:[NSMutableDictionary dictionary]
											  forKey:@"Emoticons"];
}

@end
