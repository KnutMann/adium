/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>
#import "AXSPayloadCodec.h"

/*!
 * @brief Payload codec for the icon-pack family
 *
 * The family shares one shape: named categories, each mapping keys to values,
 * almost always file names. It appears in two places: as an Icons.plist in
 * the resources (status icons, service icons - with AdiumSetVersion = 1), and
 * as dictionaries directly inside the bundle's Info.plist (menu bar icons,
 * group chat status icons). The format descriptor says which; its
 * categoryNames say what to look for.
 *
 * Payload shape: NSMutableDictionary of category name to NSMutableDictionary
 * of key to value. Categories and keys the descriptor does not name are read,
 * kept and written back untouched.
 */
@interface AXSIconPlistCodec : NSObject <AXSPayloadCodec>
@end
