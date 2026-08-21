/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>

@class AXSXtraFormat;

/*!
 * @brief Reads and writes the payload of one xtra type
 *
 * The payload is whatever sits beside the common metadata: an Icons.plist, an
 * Emoticons.plist, keys inside the bundle's own Info.plist. A codec receives
 * the resources directory wrapper (the bundle's Contents/Resources, or the
 * pack's root in the flat form) and the Info.plist dictionary, and works out
 * its payload from there.
 *
 * The one rule every codec follows: what it does not understand it leaves
 * word for word alone. Foreign keys, files it never heard of, service IDs of
 * networks long gone - they all survive a round trip.
 */
@protocol AXSPayloadCodec <NSObject>

/*!
 * @brief Read the payload; the returned object becomes the model's payload
 */
- (id)readPayloadFromInfoDictionary:(NSDictionary *)infoDict
					   resourcesDir:(NSFileWrapper *)resourcesDir
							 format:(AXSXtraFormat *)format
							  error:(NSError **)outError;

/*!
 * @brief Write the payload back
 *
 * @param infoDict The Info.plist under construction; codecs whose payload
 *                 lives there add their keys to it
 * @param resourcesDir The directory wrapper payload files belong in
 */
- (BOOL)writePayload:(id)payload
  intoInfoDictionary:(NSMutableDictionary *)infoDict
		resourcesDir:(NSFileWrapper *)resourcesDir
			  format:(AXSXtraFormat *)format
			   error:(NSError **)outError;

/*!
 * @brief A fresh, empty payload for a new document
 */
- (id)emptyPayloadForFormat:(AXSXtraFormat *)format;

@end
