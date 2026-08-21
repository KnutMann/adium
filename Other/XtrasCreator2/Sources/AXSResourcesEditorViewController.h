/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSEditorViewController.h"

/*!
 * @brief Lists the files inside the pack's resources and lets them be managed
 *
 * Shows every file the resources directory holds - including ones this
 * application did not put there - with pixel dimensions for images. Files can
 * be added and removed; what an editor references by name is added here.
 */
@interface AXSResourcesEditorViewController : AXSEditorViewController

//Other pages changed the file set; refresh the table
- (void)reloadFileList;

@end
