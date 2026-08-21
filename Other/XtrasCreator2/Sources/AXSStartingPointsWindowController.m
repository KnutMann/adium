/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSStartingPointsWindowController.h"
#import "AXSXtraFormat.h"
#import "AXSDocumentController.h"

#define STARTING_POINTS_WIDTH	460.0
#define STARTING_POINTS_HEIGHT	320.0
#define MARGIN					20.0
#define ROW_HEIGHT				30.0

@interface AXSStartingPointsWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation AXSStartingPointsWindowController {
	NSTableView *table;
}

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

	table = [[NSTableView alloc] initWithFrame:NSZeroRect];
	[table setHeaderView:nil];
	[table setRowHeight:ROW_HEIGHT];
	[table setTarget:self];
	[table setDoubleAction:@selector(createChosenXtra:)];

	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"type"];
	[table addTableColumn:column];
	[table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[table setDataSource:self];
	[table setDelegate:self];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(MARGIN, MARGIN + 44.0,
																		  STARTING_POINTS_WIDTH - 2 * MARGIN,
																		  STARTING_POINTS_HEIGHT - 3 * MARGIN - 28.0 - 44.0 + MARGIN)];
	[scroll setHasVerticalScroller:YES];
	[scroll setBorderType:NSBezelBorder];
	[scroll setDocumentView:table];
	[scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	[content addSubview:scroll];

	NSButton *create = [[NSButton alloc] initWithFrame:NSZeroRect];
	[create setBezelStyle:NSBezelStyleRounded];
	[create setTitle:@"Create"];
	[create setKeyEquivalent:@"\r"];
	[create setTarget:self];
	[create setAction:@selector(createChosenXtra:)];
	[create sizeToFit];
	NSRect createFrame = [create frame];
	createFrame.size.width = MAX(NSWidth(createFrame), 90.0);
	createFrame.origin = NSMakePoint(STARTING_POINTS_WIDTH - MARGIN - NSWidth(createFrame), MARGIN);
	[create setFrame:createFrame];
	[create setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
	[content addSubview:create];
}

- (IBAction)createChosenXtra:(id)sender
{
	NSInteger row = [table selectedRow];
	NSArray *formats = [AXSXtraFormat allFormats];

	if (row < 0 || row >= (NSInteger)[formats count]) return;

	[(AXSDocumentController *)[NSDocumentController sharedDocumentController] newDocumentOfFormat:formats[(NSUInteger)row]];
	[[self window] close];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[[AXSXtraFormat allFormats] count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSTextField *field = [tableView makeViewWithIdentifier:@"type" owner:self];
	if (!field) {
		field = [NSTextField labelWithString:@""];
		[field setIdentifier:@"type"];
	}

	AXSXtraFormat *format = [AXSXtraFormat allFormats][(NSUInteger)row];
	[field setStringValue:format.displayName];

	return field;
}

@end
