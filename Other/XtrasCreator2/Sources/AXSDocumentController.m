/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSDocumentController.h"

@implementation AXSDocumentController

- (void)newDocumentOfFormat:(AXSXtraFormat *)format
{
	NSError *error = nil;
	NSDocument *document = [self makeUntitledDocumentOfType:format.typeName error:&error];

	if (!document) {
		[self presentError:error];
		return;
	}

	[self addDocument:document];
	[document makeWindowControllers];
	[document showWindows];
}

@end
