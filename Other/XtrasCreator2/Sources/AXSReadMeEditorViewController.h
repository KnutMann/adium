/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSEditorViewController.h"

/*!
 * @brief Edits the pack's ReadMe
 *
 * Reads ReadMe.rtf or ReadMe.txt, writes ReadMe.rtf. An emptied readme
 * removes the file; Adium then falls back to its own default text.
 */
@interface AXSReadMeEditorViewController : AXSEditorViewController
@end
