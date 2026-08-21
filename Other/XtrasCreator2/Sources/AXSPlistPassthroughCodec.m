/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSPlistPassthroughCodec.h"
#import "AXSXtraFormat.h"

@implementation AXSPlistPassthroughCodec

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

	return [plist mutableCopy] ?: [NSMutableDictionary dictionary];
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
	return [NSMutableDictionary dictionary];
}

@end
