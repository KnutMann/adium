/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>
#import "AXSPayloadCodec.h"

/*!
 * @brief Everything the application knows about one xtra type
 *
 * One immutable descriptor per type, defined in code: the file extension and
 * OSType, which forms exist on disk (bundle, flat directory, bare plist),
 * where the payload lives, the key catalogs the editors offer, the codec that
 * reads and writes the payload, and the view controller class that edits it.
 *
 * The type name doubles as the UTI declared in the application's Info.plist;
 * NSDocumentController speaks in these.
 */
@interface AXSXtraFormat : NSObject

@property (readonly, nonatomic) NSString *typeName;			//UTI, e.g. com.adiumx.menubaricons
@property (readonly, nonatomic) NSString *extension;		//e.g. AdiumMenuBarIcons
@property (readonly, nonatomic) NSString *osType;			//e.g. AdMB
@property (readonly, nonatomic) NSString *displayName;		//e.g. Menu Bar Icons

@property (readonly, nonatomic) BOOL supportsFlatForm;		//flat directory beside the bundle form
@property (readonly, nonatomic) BOOL flatFormIsBarePlist;	//the xtra is a single plist file (list themes)
@property (readonly, nonatomic) BOOL payloadLivesInInfoPlist;
@property (readonly, nonatomic) BOOL requiresBundleIdentifier;

//Name of the payload file inside the resources directory, nil when the payload lives in Info.plist
@property (readonly, nonatomic) NSString *payloadFileName;

/*!
 * @brief Ordered payload categories and the keys each one offers
 *
 * For icon-family types: category name -> ordered array of expected keys.
 * Editors mark these as expected; codecs never drop keys outside of them.
 */
@property (readonly, nonatomic) NSArray<NSString *> *categoryNames;
@property (readonly, nonatomic) NSDictionary<NSString *, NSArray<NSString *> *> *catalog;

//The keys a pack cannot do without: Adium refuses or resets without them
@property (readonly, nonatomic) NSDictionary<NSString *, NSArray<NSString *> *> *requiredCatalog;

@property (readonly, nonatomic) id<AXSPayloadCodec> codec;
@property (readonly, nonatomic) Class editorClass;

+ (NSArray<AXSXtraFormat *> *)allFormats;
+ (AXSXtraFormat *)formatForTypeName:(NSString *)typeName;
+ (AXSXtraFormat *)formatForExtension:(NSString *)extension;

@end
