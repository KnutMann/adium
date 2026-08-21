/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSDocumentWindowController.h"
#import "AXSXtraDocument.h"
#import "AXSEditorViewController.h"
#import "AXSMetadataEditorViewController.h"
#import "AXSResourcesEditorViewController.h"
#import "AXSReadMeEditorViewController.h"

#define DOCUMENT_WINDOW_WIDTH	760.0
#define DOCUMENT_WINDOW_HEIGHT	560.0

@interface AXSDocumentWindowController () <NSTabViewDelegate>
@end

@implementation AXSDocumentWindowController {
	NSArray<AXSEditorViewController *> *editors;
	NSTabView *tabView;
}

- (instancetype)initWithDocument:(AXSXtraDocument *)document
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, DOCUMENT_WINDOW_WIDTH, DOCUMENT_WINDOW_HEIGHT)
												   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
															  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
													 backing:NSBackingStoreBuffered
													   defer:YES];
	[window setMinSize:NSMakeSize(560.0, 400.0)];
	[window center];

	if ((self = [super initWithWindow:window])) {
		[self setDocument:document];
		[self buildPagesForDocument:document];
	}
	return self;
}

- (void)buildPagesForDocument:(AXSXtraDocument *)document
{
	NSMutableArray *building = [NSMutableArray array];

	//The type's own page leads; a type without one starts on the shared pages
	if (document.format.editorClass)
		[building addObject:[[document.format.editorClass alloc] initWithDocument:document]];

	[building addObject:[[AXSMetadataEditorViewController alloc] initWithDocument:document]];
	[building addObject:[[AXSResourcesEditorViewController alloc] initWithDocument:document]];
	[building addObject:[[AXSReadMeEditorViewController alloc] initWithDocument:document]];

	editors = building;

	tabView = [[NSTabView alloc] initWithFrame:[[[self window] contentView] bounds]];
	[tabView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	[tabView setDelegate:self];

	for (AXSEditorViewController *editor in editors) {
		NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:[editor tabTitle]];
		[item setLabel:[editor tabTitle]];
		[item setView:[editor view]];
		[tabView addTabViewItem:item];
	}

	[[[self window] contentView] addSubview:tabView];
}

/*!
 * @brief Refresh a page when it comes to the front
 *
 * Pages share the model and the resources; one page's edit shows up on the
 * next the moment it is opened.
 */
- (void)tabView:(NSTabView *)aTabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	NSUInteger index = (NSUInteger)[aTabView indexOfTabViewItem:tabViewItem];
	if (index < [editors count])
		[editors[index] reloadFromModel];
}

@end
