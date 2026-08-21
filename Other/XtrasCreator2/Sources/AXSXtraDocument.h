/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Cocoa/Cocoa.h>
#import "AXSXtraFormat.h"
#import "AXSXtraModel.h"

/*!
 * @brief The one document class behind every xtra type
 *
 * Which type it is comes from the format registry; what differs per type -
 * payload serialization and the editor page - hangs off the descriptor. The
 * document itself owns the common metadata, the readme and the file wrapper
 * tree.
 *
 * It reads both on-disk forms: the bundle (Contents/Info.plist plus
 * Contents/Resources) and the flat pack (payload beside the resources at the
 * root). Saving keeps the form a pack arrived in; new documents are born as
 * bundles. The loaded wrapper tree is kept and only edited nodes are
 * replaced, so files this application does not understand survive a round
 * trip byte for byte.
 */
@interface AXSXtraDocument : NSDocument

@property (readonly, nonatomic) AXSXtraFormat *format;
@property (readonly, nonatomic) AXSXtraModel *model;

//YES when the pack arrived in the flat form and will be saved back flat
@property (readonly, nonatomic) BOOL isFlatForm;

//The directory the payload and resource files live in (Contents/Resources, or the root when flat)
@property (readonly, nonatomic) NSFileWrapper *resourcesWrapper;

//Editors call this after changing the model or the wrappers
- (void)noteEdited;

@end
