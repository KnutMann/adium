/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>
#import "AXSPayloadCodec.h"

/*!
 * @brief Payload codec for JavaScript plugins
 *
 * A JavaScript plugin is an .AdiumPlugin bundle carrying no code, only a script
 * the message view injects. The extension is shared with compiled plugins, so
 * this refuses anything that is not a JavaScript plugin - XtrasCreator authors
 * the scriptable kind, never a binary one.
 *
 * The payload is the manifest fields plus the script source.
 */
@interface AXSJavaScriptPluginCodec : NSObject <AXSPayloadCodec>

//The Info.plist keys the codec owns
+ (NSArray<NSString *> *)manifestKeys;

//A minimal working plugin, for a new document
+ (NSString *)scaffoldSource;

@end
