/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>
#import "AXSPayloadCodec.h"

/*!
 * @brief Payload codec for dock icon packs
 *
 * IconPack.plist: a Description dict (Title, Creator, LinkURL) and a State
 * dict whose entries are still images or animations - Image or Images,
 * Delay, Looping, Overlay, Animated. An image path starting with
 * "../Shared Images/" is not a path at all but Adium's shared artwork
 * folder, and travels through untouched.
 */
@interface AXSDockIconCodec : NSObject <AXSPayloadCodec>
@end
