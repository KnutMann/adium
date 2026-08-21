/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Cocoa/Cocoa.h>
#import "AXSXtraFormat.h"

/*!
 * @brief Document controller that speaks in xtra formats
 *
 * New documents come from the starting points window, one per format, rather
 * than from an untitled-document shortcut.
 */
@interface AXSDocumentController : NSDocumentController

- (void)newDocumentOfFormat:(AXSXtraFormat *)format;

@end
