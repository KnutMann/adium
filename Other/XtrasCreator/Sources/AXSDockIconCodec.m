/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSDockIconCodec.h"
#import "AXSXtraFormat.h"

@implementation AXSDockIconCodec

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

	if ([plist[@"Description"] isKindOfClass:[NSDictionary class]])
		payload[@"Description"] = [plist[@"Description"] mutableCopy];

	if ([plist[@"State"] isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *states = [NSMutableDictionary dictionary];
		[(NSDictionary *)plist[@"State"] enumerateKeysAndObjectsUsingBlock:^(NSString *name, id entry, BOOL *stop) {
			states[name] = ([entry isKindOfClass:[NSDictionary class]] ? [entry mutableCopy] : entry);
		}];
		payload[@"State"] = states;
	}

	return payload;
}

- (BOOL)writePayload:(id)payload
  intoInfoDictionary:(NSMutableDictionary *)infoDict
		resourcesDir:(NSFileWrapper *)resourcesDir
			  format:(AXSXtraFormat *)format
			   error:(NSError **)outError
{
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:payload
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
	return [NSMutableDictionary dictionaryWithDictionary:@{
		@"Description": [NSMutableDictionary dictionary],
		@"State": [NSMutableDictionary dictionary],
	}];
}

@end
