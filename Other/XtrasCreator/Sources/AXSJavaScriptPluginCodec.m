/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSJavaScriptPluginCodec.h"
#import "AXSXtraFormat.h"

#define DEFAULT_SCRIPT_FILENAME @"plugin.js"

@implementation AXSJavaScriptPluginCodec

+ (NSArray<NSString *> *)manifestKeys
{
	return @[@"AIJavaScriptPlugin", @"AIJavaScriptPluginFileName",
			 @"AIJavaScriptPluginAPIVersion", @"AIMinimumAdiumVersionRequirement"];
}

+ (NSString *)scaffoldSource
{
	return
	@"// A JavaScript plugin reshapes how messages are displayed. It runs walled\n"
	@"// off from the page and cannot reach the network or your files.\n"
	@"//\n"
	@"// You are handed the message-body elements as they appear. Transform only\n"
	@"// what you are given, and build any new nodes with createElement and\n"
	@"// textContent - never feed message text to innerHTML, or markup in a\n"
	@"// message would be interpreted.\n"
	@"\n"
	@"(function () {\n"
	@"\t'use strict';\n"
	@"\n"
	@"\tadiumPlugin.onMessagesAdded(function (nodes) {\n"
	@"\t\tnodes.forEach(function (messageBody) {\n"
	@"\t\t\t// messageBody is a <span data-x-adium-msg> element; change its display here.\n"
	@"\t\t});\n"
	@"\t});\n"
	@"})();\n";
}

- (id)readPayloadFromInfoDictionary:(NSDictionary *)infoDict
					   resourcesDir:(NSFileWrapper *)resourcesDir
							 format:(AXSXtraFormat *)format
							  error:(NSError **)outError
{
	/* The extension is shared with compiled plugins, which this tool must not
	 * touch. Refuse anything that is not plainly a JavaScript plugin, and
	 * anything that carries an executable. */
	if (![infoDict[@"AIJavaScriptPlugin"] boolValue]) {
		if (outError) *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
												  userInfo:@{NSLocalizedDescriptionKey:
															 @"This is not a JavaScript plugin. XtrasCreator can only author JavaScript plugins, not compiled ones."}];
		return nil;
	}
	if (infoDict[@"CFBundleExecutable"]) {
		if (outError) *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
												  userInfo:@{NSLocalizedDescriptionKey:
															 @"This plugin carries compiled code. XtrasCreator can only author JavaScript plugins."}];
		return nil;
	}

	NSString *fileName = [infoDict[@"AIJavaScriptPluginFileName"] description] ?: DEFAULT_SCRIPT_FILENAME;

	NSString *source = @"";
	NSFileWrapper *scriptWrapper = [resourcesDir fileWrappers][fileName];
	if (scriptWrapper.regularFile) {
		source = [[NSString alloc] initWithData:[scriptWrapper regularFileContents] encoding:NSUTF8StringEncoding] ?: @"";
	}

	NSInteger apiVersion = infoDict[@"AIJavaScriptPluginAPIVersion"] ? [infoDict[@"AIJavaScriptPluginAPIVersion"] integerValue] : 1;

	return [NSMutableDictionary dictionaryWithDictionary:@{
		@"fileName": fileName,
		@"source": source,
		@"apiVersion": @(apiVersion),
	}];
}

- (BOOL)writePayload:(id)payload
  intoInfoDictionary:(NSMutableDictionary *)infoDict
		resourcesDir:(NSFileWrapper *)resourcesDir
			  format:(AXSXtraFormat *)format
			   error:(NSError **)outError
{
	NSDictionary *dict = payload;
	NSString *fileName = [dict[@"fileName"] length] ? dict[@"fileName"] : DEFAULT_SCRIPT_FILENAME;
	NSString *source = dict[@"source"] ?: @"";

	infoDict[@"AIJavaScriptPlugin"] = @YES;
	infoDict[@"AIJavaScriptPluginFileName"] = fileName;
	infoDict[@"AIJavaScriptPluginAPIVersion"] = dict[@"apiVersion"] ?: @1;
	if (!infoDict[@"AIMinimumAdiumVersionRequirement"])
		infoDict[@"AIMinimumAdiumVersionRequirement"] = @"1.8.0";

	NSData *data = [source dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];

	NSFileWrapper *existing = [resourcesDir fileWrappers][fileName];
	if (existing && [[existing regularFileContents] isEqualToData:data])
		return YES;

	if (existing) [resourcesDir removeFileWrapper:existing];
	[resourcesDir addRegularFileWithContents:data preferredFilename:fileName];

	return YES;
}

- (id)emptyPayloadForFormat:(AXSXtraFormat *)format
{
	return [NSMutableDictionary dictionaryWithDictionary:@{
		@"fileName": DEFAULT_SCRIPT_FILENAME,
		@"source": [AXSJavaScriptPluginCodec scaffoldSource],
		@"apiVersion": @1,
	}];
}

@end
