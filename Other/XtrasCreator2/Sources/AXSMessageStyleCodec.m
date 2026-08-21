/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSMessageStyleCodec.h"
#import "AXSXtraFormat.h"

@implementation AXSMessageStyleCodec

+ (NSArray<NSString *> *)styleKeys
{
	return @[@"MessageViewVersion", @"MessageViewVersion_MinimumCompatible",
			 @"DefaultVariant", @"DisplayNameForNoVariant",
			 @"DefaultFontFamily", @"DefaultFontSize",
			 @"ShowsUserIcons", @"AllowTextColors", @"DisableCombineConsecutive",
			 @"DisableCustomBackground", @"DefaultBackgroundIsTransparent",
			 @"DefaultBackgroundColor", @"ImageMask"];
}

+ (NSDictionary<NSString *, NSString *> *)scaffoldFiles
{
	NSString *content =
	@"<div class=\"message %messageClasses%\">\n"
	@"\t<span class=\"sender\">%sender%</span>\n"
	@"\t<span class=\"time\">%time%</span>\n"
	@"\t<div class=\"body\">%message%</div>\n"
	@"\t<div id=\"insert\"></div>\n"
	@"</div>\n";

	NSString *nextContent =
	@"<div class=\"message consecutive %messageClasses%\">\n"
	@"\t<div class=\"body\">%message%</div>\n"
	@"\t<div id=\"insert\"></div>\n"
	@"</div>\n";

	NSString *status =
	@"<div class=\"status\">\n"
	@"\t%message% <span class=\"time\">%time%</span>\n"
	@"\t<div id=\"insert\"></div>\n"
	@"</div>\n";

	NSString *css =
	@"body { margin: 8px; font-family: -apple-system, sans-serif; }\n"
	@".message { margin-bottom: 6px; }\n"
	@".message.outgoing { color: #246; }\n"
	@".sender { font-weight: bold; }\n"
	@".time { color: #999; font-size: smaller; float: right; }\n"
	@".status { color: #888; font-style: italic; margin: 4px 0; }\n";

	return @{
		@"Incoming/Content.html": content,
		@"Incoming/NextContent.html": nextContent,
		@"Status.html": status,
		@"main.css": css,
	};
}

- (id)readPayloadFromInfoDictionary:(NSDictionary *)infoDict
					   resourcesDir:(NSFileWrapper *)resourcesDir
							 format:(AXSXtraFormat *)format
							  error:(NSError **)outError
{
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];

	for (NSString *key in [AXSMessageStyleCodec styleKeys]) {
		id value = infoDict[key];
		if (value) payload[key] = value;
	}

	return payload;
}

- (BOOL)writePayload:(id)payload
  intoInfoDictionary:(NSMutableDictionary *)infoDict
		resourcesDir:(NSFileWrapper *)resourcesDir
			  format:(AXSXtraFormat *)format
			   error:(NSError **)outError
{
	for (NSString *key in [AXSMessageStyleCodec styleKeys]) {
		id value = payload[key];
		if (value) infoDict[key] = value;
	}

	return YES;
}

- (id)emptyPayloadForFormat:(AXSXtraFormat *)format
{
	return [NSMutableDictionary dictionaryWithDictionary:@{
		@"MessageViewVersion": @4,
		@"ShowsUserIcons": @YES,
		@"AllowTextColors": @YES,
	}];
}

@end
