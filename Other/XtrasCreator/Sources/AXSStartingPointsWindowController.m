/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSStartingPointsWindowController.h"
#import "AXSXtraFormat.h"
#import "AXSDocumentController.h"

#define STARTING_POINTS_WIDTH	480.0
#define STARTING_POINTS_HEIGHT	460.0
#define MARGIN					20.0
#define ROW_HEIGHT				44.0

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
	/* Without an explicit width the column keeps NSTableColumn's default
	 * hundred points and every row is cut short; the last-column fit below
	 * then follows the table's real width. */
	[column setWidth:STARTING_POINTS_WIDTH];
	[column setResizingMask:NSTableColumnAutoresizingMask];
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
	[table sizeLastColumnToFit];

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

	//The other way in: an existing pack
	NSButton *open = [[NSButton alloc] initWithFrame:NSZeroRect];
	[open setBezelStyle:NSBezelStyleRounded];
	[open setTitle:@"Open…"];
	[open setTarget:nil];
	[open setAction:@selector(openDocument:)];
	[open sizeToFit];
	NSRect openFrame = [open frame];
	openFrame.size.width = MAX(NSWidth(openFrame), 90.0);
	openFrame.origin = NSMakePoint(MARGIN, MARGIN);
	[open setFrame:openFrame];
	[open setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)];
	[content addSubview:open];
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
	NSView *cell = [tableView makeViewWithIdentifier:@"type" owner:self];
	NSImageView *icon = nil;
	NSTextField *name = nil;
	NSTextField *detail = nil;

	if (!cell) {
		cell = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, ROW_HEIGHT)];
		[cell setIdentifier:@"type"];

		icon = [[NSImageView alloc] initWithFrame:NSMakeRect(6, 6, 32, 32)];
		[icon setImageScaling:NSImageScaleProportionallyDown];
		[icon setIdentifier:@"icon"];
		[icon setAutoresizingMask:NSViewMaxXMargin];
		[cell addSubview:icon];

		name = [NSTextField labelWithString:@""];
		[name setFrame:NSMakeRect(46, 23, 340, 17)];
		[name setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold]];
		[name setIdentifier:@"name"];
		[name setLineBreakMode:NSLineBreakByTruncatingTail];
		[name setAutoresizingMask:NSViewWidthSizable];
		[cell addSubview:name];

		detail = [NSTextField labelWithString:@""];
		[detail setFrame:NSMakeRect(46, 5, 340, 15)];
		[detail setFont:[NSFont systemFontOfSize:11.0]];
		[detail setTextColor:[NSColor secondaryLabelColor]];
		[detail setIdentifier:@"detail"];
		[detail setLineBreakMode:NSLineBreakByTruncatingTail];
		[detail setAutoresizingMask:NSViewWidthSizable];
		[cell addSubview:detail];
	} else {
		for (NSView *sub in [cell subviews]) {
			if ([[sub identifier] isEqualToString:@"icon"]) icon = (NSImageView *)sub;
			else if ([[sub identifier] isEqualToString:@"name"]) name = (NSTextField *)sub;
			else if ([[sub identifier] isEqualToString:@"detail"]) detail = (NSTextField *)sub;
		}
	}

	AXSXtraFormat *format = [AXSXtraFormat allFormats][(NSUInteger)row];
	[name setStringValue:format.displayName];
	[detail setStringValue:format.typeDescription ?: @""];
	[icon setImage:(format.iconName ? [NSImage imageNamed:format.iconName] : nil)];

	return cell;
}

@end
