/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Cocoa/Cocoa.h>

@class AXSXtraDocument;

/*!
 * @brief One window per xtra: the type's own page first, then the shared ones
 */
@interface AXSDocumentWindowController : NSWindowController

- (instancetype)initWithDocument:(AXSXtraDocument *)document;

@end
