/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSStartingPointsWindowController.h"

#define STARTING_POINTS_WIDTH	460.0
#define STARTING_POINTS_HEIGHT	320.0
#define MARGIN					20.0

@implementation AXSStartingPointsWindowController

- (instancetype)init
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, STARTING_POINTS_WIDTH, STARTING_POINTS_HEIGHT)
												   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
													 backing:NSBackingStoreBuffered
													   defer:YES];
	[window setTitle:@"XtrasCreator"];
	[window center];
	[window setFrameAutosaveName:@"AXSStartingPoints"];

	if ((self = [super initWithWindow:window])) {
		[self buildContent];
	}
	return self;
}

- (void)buildContent
{
	NSView *content = [[self window] contentView];

	NSTextField *heading = [NSTextField labelWithString:@"What would you like to make?"];
	[heading setFont:[NSFont systemFontOfSize:20.0 weight:NSFontWeightSemibold]];
	[heading setFrameOrigin:NSMakePoint(MARGIN, STARTING_POINTS_HEIGHT - MARGIN - 28.0)];
	[heading sizeToFit];
	[heading setAutoresizingMask:(NSViewMinYMargin | NSViewMaxXMargin)];
	[content addSubview:heading];

	/* Placeholder until the document types land: the window earns its list in
	 * the phases that teach the application each xtra type. */
	NSTextField *note = [NSTextField wrappingLabelWithString:
						 @"The starting points list appears here as xtra types are added: "
						 @"emoticon sets, sound sets, icon packs, message styles, scripts and more."];
	[note setFrame:NSMakeRect(MARGIN, MARGIN,
							  STARTING_POINTS_WIDTH - 2 * MARGIN,
							  STARTING_POINTS_HEIGHT - 3 * MARGIN - 28.0)];
	[note setTextColor:[NSColor secondaryLabelColor]];
	[note setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	[content addSubview:note];
}

@end
