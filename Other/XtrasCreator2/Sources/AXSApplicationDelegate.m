/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSApplicationDelegate.h"
#import "AXSStartingPointsWindowController.h"
#import "AXSSettingsWindowController.h"
#import "AXSDocumentController.h"

/* undo:/redo: travel the responder chain but are declared in no header;
 * naming them here keeps the compiler's undeclared-selector check honest. */
@interface NSObject (AXSUndoActions)
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;
@end

@implementation AXSApplicationDelegate {
	AXSStartingPointsWindowController *startingPoints;
	AXSSettingsWindowController *settings;
	AXSDocumentController *documentController;
}

- (instancetype)init
{
	if ((self = [super init])) {
		/* The first NSDocumentController to exist becomes the shared one, so
		 * ours has to be born before anything asks for it. */
		documentController = [[AXSDocumentController alloc] init];
	}
	return self;
}

#pragma mark Menu bar

static NSMenuItem *AXSItem(NSString *title, SEL action, NSString *key)
{
	return [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
}

/*!
 * @brief Assemble the entire menu bar
 *
 * Standard selectors go to the responder chain (target nil), so items enable
 * and disable themselves as documents and windows come and go.
 */
- (void)buildMenuBar
{
	NSMenu *menubar = [[NSMenu alloc] init];

	//Application menu; the system renames it after the app
	NSMenuItem *appItem = [menubar addItemWithTitle:@"XtrasCreator" action:NULL keyEquivalent:@""];
	NSMenu *appMenu = [[NSMenu alloc] init];
	[appMenu addItem:AXSItem(@"About XtrasCreator", @selector(orderFrontStandardAboutPanel:), @"")];
	[appMenu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *settingsItem = AXSItem(@"Settings…", @selector(showSettings:), @",");
	[settingsItem setTarget:self];
	[appMenu addItem:settingsItem];
	[appMenu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *servicesItem = [appMenu addItemWithTitle:@"Services" action:NULL keyEquivalent:@""];
	NSMenu *servicesMenu = [[NSMenu alloc] init];
	[servicesItem setSubmenu:servicesMenu];
	[NSApp setServicesMenu:servicesMenu];

	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItem:AXSItem(@"Hide XtrasCreator", @selector(hide:), @"h")];
	NSMenuItem *hideOthers = AXSItem(@"Hide Others", @selector(hideOtherApplications:), @"h");
	[hideOthers setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];
	[appMenu addItem:hideOthers];
	[appMenu addItem:AXSItem(@"Show All", @selector(unhideAllApplications:), @"")];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItem:AXSItem(@"Quit XtrasCreator", @selector(terminate:), @"q")];
	[appItem setSubmenu:appMenu];

	//File
	NSMenuItem *fileItem = [menubar addItemWithTitle:@"File" action:NULL keyEquivalent:@""];
	NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
	[fileMenu addItem:AXSItem(@"New Xtra…", @selector(showStartingPoints:), @"n")];
	[fileMenu addItem:AXSItem(@"Open…", @selector(openDocument:), @"o")];
	[fileMenu addItem:[NSMenuItem separatorItem]];
	[fileMenu addItem:AXSItem(@"Close", @selector(performClose:), @"w")];
	[fileMenu addItem:AXSItem(@"Save", @selector(saveDocument:), @"s")];
	NSMenuItem *saveAs = AXSItem(@"Save As…", @selector(saveDocumentAs:), @"s");
	[saveAs setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];
	[fileMenu addItem:saveAs];
	[fileMenu addItem:AXSItem(@"Revert to Saved", @selector(revertDocumentToSaved:), @"")];
	[fileItem setSubmenu:fileMenu];

	//Edit
	NSMenuItem *editItem = [menubar addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
	NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
	[editMenu addItem:AXSItem(@"Undo", @selector(undo:), @"z")];
	NSMenuItem *redo = AXSItem(@"Redo", @selector(redo:), @"z");
	[redo setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];
	[editMenu addItem:redo];
	[editMenu addItem:[NSMenuItem separatorItem]];
	[editMenu addItem:AXSItem(@"Cut", @selector(cut:), @"x")];
	[editMenu addItem:AXSItem(@"Copy", @selector(copy:), @"c")];
	[editMenu addItem:AXSItem(@"Paste", @selector(paste:), @"v")];
	[editMenu addItem:AXSItem(@"Delete", @selector(delete:), @"")];
	[editMenu addItem:AXSItem(@"Select All", @selector(selectAll:), @"a")];
	[editItem setSubmenu:editMenu];

	//Window
	NSMenuItem *windowItem = [menubar addItemWithTitle:@"Window" action:NULL keyEquivalent:@""];
	NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
	[windowMenu addItem:AXSItem(@"Minimize", @selector(performMiniaturize:), @"m")];
	[windowMenu addItem:AXSItem(@"Zoom", @selector(performZoom:), @"")];
	[windowMenu addItem:[NSMenuItem separatorItem]];
	[windowMenu addItem:AXSItem(@"Bring All to Front", @selector(arrangeInFront:), @"")];
	[windowItem setSubmenu:windowMenu];
	[NSApp setWindowsMenu:windowMenu];

	//Help
	NSMenuItem *helpItem = [menubar addItemWithTitle:@"Help" action:NULL keyEquivalent:@""];
	NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
	[helpItem setSubmenu:helpMenu];
	[NSApp setHelpMenu:helpMenu];

	[NSApp setMainMenu:menubar];
}

#pragma mark Starting points

- (IBAction)showSettings:(id)sender
{
	if (!settings)
		settings = [[AXSSettingsWindowController alloc] init];

	[settings showWindow:sender];
}

- (IBAction)showStartingPoints:(id)sender
{
	if (!startingPoints)
		startingPoints = [[AXSStartingPointsWindowController alloc] init];

	[startingPoints showWindow:sender];
}

#pragma mark NSApplicationDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
	[self buildMenuBar];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	[self showStartingPoints:nil];
}

//The starting points window takes the place of an untitled document
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows
{
	if (!hasVisibleWindows)
		[self showStartingPoints:nil];

	return NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return NO;
}

@end
