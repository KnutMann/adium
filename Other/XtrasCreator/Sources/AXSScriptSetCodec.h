/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>
#import "AXSPayloadCodec.h"

/*!
 * @brief Payload codec for script packs
 *
 * The Info.plist carries a Set name and a Scripts array; each entry names a
 * compiled AppleScript by basename plus the keyword that triggers it, its
 * menu title, comma separated arguments, and whether it fires only as a
 * prefix. The .scpt files themselves come from Script Editor.
 */
@interface AXSScriptSetCodec : NSObject <AXSPayloadCodec>
@end
