/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSScriptSetCodec.h"
#import "AXSXtraFormat.h"

@implementation AXSScriptSetCodec

- (id)readPayloadFromInfoDictionary:(NSDictionary *)infoDict
					   resourcesDir:(NSFileWrapper *)resourcesDir
							 format:(AXSXtraFormat *)format
							  error:(NSError **)outError
{
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];

	if (infoDict[@"Set"])
		payload[@"Set"] = infoDict[@"Set"];

	NSMutableArray *scripts = [NSMutableArray array];
	if ([infoDict[@"Scripts"] isKindOfClass:[NSArray class]]) {
		for (id entry in infoDict[@"Scripts"]) {
			[scripts addObject:([entry isKindOfClass:[NSDictionary class]] ? [entry mutableCopy] : entry)];
		}
	}
	payload[@"Scripts"] = scripts;

	return payload;
}

- (BOOL)writePayload:(id)payload
  intoInfoDictionary:(NSMutableDictionary *)infoDict
		resourcesDir:(NSFileWrapper *)resourcesDir
			  format:(AXSXtraFormat *)format
			   error:(NSError **)outError
{
	if (payload[@"Set"])
		infoDict[@"Set"] = payload[@"Set"];
	infoDict[@"Scripts"] = [payload[@"Scripts"] copy] ?: @[];

	return YES;
}

- (id)emptyPayloadForFormat:(AXSXtraFormat *)format
{
	return [NSMutableDictionary dictionaryWithDictionary:@{
		@"Scripts": [NSMutableArray array],
	}];
}

@end
