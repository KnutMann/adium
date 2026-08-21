/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Cocoa/Cocoa.h>
#import "AXSApplicationDelegate.h"

/* Held here, not inside the pool: NSApplication keeps only a weak reference
 * to its delegate, so somebody has to own it for the app's lifetime. */
static AXSApplicationDelegate *applicationDelegate;

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		[NSApplication sharedApplication];

		applicationDelegate = [[AXSApplicationDelegate alloc] init];
		[NSApp setDelegate:applicationDelegate];
	}

	return NSApplicationMain(argc, argv);
}
