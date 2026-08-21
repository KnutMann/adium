/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>
#import "AXSPayloadCodec.h"

/*!
 * @brief Payload codec for emoticon sets
 *
 * Emoticons.plist: an Emoticons dict whose keys are image file names (or bare
 * identifiers for the image-less emoji kind), each entry carrying Equivalents,
 * Name and optionally Character. AdiumSetVersion 1 marks the Adium dialect;
 * a pack in the older Proteus dialect is carried through untouched rather
 * than rewritten into something its author never made.
 */
@interface AXSEmoticonSetCodec : NSObject <AXSPayloadCodec>

//YES when the payload is an Adium-dialect set this editor can work on
+ (BOOL)payloadIsEditable:(id)payload;

@end
