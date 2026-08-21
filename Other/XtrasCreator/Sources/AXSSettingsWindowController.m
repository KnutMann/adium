/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSSettingsWindowController.h"
#import "AISettingsFormView.h"

#define SETTINGS_WIDTH	420.0
#define SETTINGS_HEIGHT	140.0

@implementation AXSSettingsWindowController {
	NSTextField *authorField;
}

- (instancetype)init
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, SETTINGS_WIDTH, SETTINGS_HEIGHT)
												   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
													 backing:NSBackingStoreBuffered
													   defer:YES];
	[window setTitle:@"Settings"];
	[window center];

	if ((self = [super initWithWindow:window])) {
		AISettingsFormView *form = [[AISettingsFormView alloc] initWithWidth:SETTINGS_WIDTH - 32.0];

		[form addSectionHeader:@"New Xtras"];
		authorField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedAuthor:)];
		[authorField setStringValue:[[NSUserDefaults standardUserDefaults] stringForKey:AXSDefaultAuthorKey] ?: @""];
		[form addRowWithLabel:@"Author" stretchingControl:authorField];
		[form addFootnote:@"Filled into every new xtra; each one can still say otherwise."];

		[form setFrameOrigin:NSMakePoint(16.0, 0)];
		[[window contentView] addSubview:form];
		[form layoutForWidth:SETTINGS_WIDTH - 32.0];

		//The form stacks from y = 0 downwards in its flipped world; place it at the top
		NSRect frame = [form frame];
		frame.origin.y = SETTINGS_HEIGHT - NSHeight(frame) - 8.0;
		[form setFrame:frame];
	}
	return self;
}

- (IBAction)changedAuthor:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setObject:[authorField stringValue] forKey:AXSDefaultAuthorKey];
}

@end
