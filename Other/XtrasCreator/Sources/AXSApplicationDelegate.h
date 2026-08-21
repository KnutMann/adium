/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Cocoa/Cocoa.h>

/*!
 * @brief The application: menu bar and startup behavior
 *
 * The whole UI is built in code; there is not a nib in the application. The
 * delegate assembles the menu bar before launch finishes and brings up the
 * starting points window in place of an untitled document.
 */
@interface AXSApplicationDelegate : NSObject <NSApplicationDelegate>
@end
