/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>
#import "AXSPayloadCodec.h"

/*!
 * @brief Payload codec for xtras that are a preference dictionary
 *
 * Contact list themes and layouts: the payload is one flat dictionary of
 * preference keys. In the bundle form it sits at Contents/Resources/Data.plist;
 * in the flat form the xtra file is the dictionary itself, which the document
 * layer reads and writes directly.
 */
@interface AXSPlistPassthroughCodec : NSObject <AXSPayloadCodec>
@end
