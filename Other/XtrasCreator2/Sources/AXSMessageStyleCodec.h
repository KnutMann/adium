/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>
#import "AXSPayloadCodec.h"

/*!
 * @brief Payload codec for message styles
 *
 * A style's settings are keys in its own Info.plist; its substance is the
 * template and stylesheet tree, which stays in the resources and is authored
 * outside this tool. The codec carries the documented setting keys; variant
 * scoped overrides ("Key:Variant Name") and anything else ride through with
 * the unmanaged keys.
 */
@interface AXSMessageStyleCodec : NSObject <AXSPayloadCodec>

//The documented setting keys, in the order the editor shows them
+ (NSArray<NSString *> *)styleKeys;

//A minimal working style, filename to file content, for a new document
+ (NSDictionary<NSString *, NSString *> *)scaffoldFiles;

@end
