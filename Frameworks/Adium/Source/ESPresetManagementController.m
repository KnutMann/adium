/* 
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 * 
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import <Adium/ESPresetManagementController.h>
#import <AIUtilities/AITableViewAdditions.h>

#define	PRESET_DRAG_TYPE @"com.adium.preset-row"		//A pasteboard type is a UTI now

@interface ESPresetManagementController ()
- (void)configureControlDimming;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSModalResponse)returnCode contextInfo:(void *)contextInfo;
@end

/* The preset management sheets currently on screen.
 *
 * -showOnWindow: is declared ns_consumes_self. Under manual counting that was decoration; counted
 * automatically it means what it says: the caller's one reference is handed over at the call and
 * given up when the method returns, so with nothing else holding on, the controller would die as
 * its sheet appeared. This set is that something else, and it takes the place of a scheme in which
 * the object was its own owner and handed itself to the pool on the way out.
 */
static NSMutableSet *openPresetManagementControllers = nil;

/*!
 * @class ESPresetManagementController
 * @brief Generic controller for managing presets
 */
@implementation ESPresetManagementController

- (void)showOnWindow:(NSWindow *)parentWindow
{
	if (!openPresetManagementControllers) openPresetManagementControllers = [[NSMutableSet alloc] init];
	[openPresetManagementControllers addObject:self];

	if (parentWindow) {
		[parentWindow beginSheet:self.window
			   completionHandler:^(NSModalResponse returnCode) {
				[self sheetDidEnd:self.window returnCode:returnCode contextInfo:NULL];
			}];

	} else {
		[self showWindow:nil];
		[self.window makeKeyAndOrderFront:nil];
		[NSApp activateIgnoringOtherApps:YES];
	}
}


/*!
 * @brief Begin managing presets
 *
 * @param inPresets An array of either NSString or NSDictionary objects.
 * @param inNameKey If inPresets contains NSDictionary objects, the key used to look up the name ot present to the user.
 * @param inDelegate The delegate for preset management.  It must implement all methods in the ESPresetManagementControllerDelegate informal protocol.
 */
- (id)initWithPresets:(NSArray *)inPresets namedByKey:(NSString *)inNameKey withDelegate:(id)inDelegate
{
	
	NSParameterAssert([inDelegate respondsToSelector:@selector(renamePreset:toName:inPresets:renamedPreset:)]);
	NSParameterAssert([inDelegate respondsToSelector:@selector(duplicatePreset:inPresets:createdDuplicate:)]);
	NSParameterAssert([inDelegate respondsToSelector:@selector(deletePreset:inPresets:)]);
	
    if ((self = [super initWithWindowNibName:@"PresetManagement"])) {
		presets = inPresets;
		nameKey = inNameKey;
		delegate = inDelegate;
	}

	return self;
}

/*!
 * @brief Window did load
 */
- (void)windowDidLoad
{
	//Enable dragging of presets
	[tableView_presets registerForDraggedTypes:[NSArray arrayWithObject:PRESET_DRAG_TYPE]];

	//The nib names the column nothing, and rows are reused by the column's name
	[[[tableView_presets tableColumns] firstObject] setIdentifier:@"preset"];
	[tableView_presets setUsesAlternatingRowBackgroundColors:YES];

	[label_editPresets setStringValue:AILocalizedString(@"Edit presets:", nil)];

	[button_duplicate setTitle:AILocalizedString(@"Duplicate", "Button which duplicates the selection")];
	[button_delete setTitle:AILocalizedString(@"Delete", "Button which deletes the selection")];
	[button_rename setTitle:AILocalizedString(@"Rename", "Button which renames the selection")];
	[button_done setTitle:AILocalizedString(@"Done", "Button which indicates that the editing sheet is done")];
	
	[self configureControlDimming];
}

/*!
 * @brief Okay
 *
 * Close the window
 */
- (IBAction)okay:(id)sender
{
	
	[self closeWindow:nil];
}

/*!
 * Invoked as the sheet closes, dismiss the sheet
 */
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSModalResponse)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:nil];

	/* Out of the set, but not before this turn of the run loop ends: both exits are reached from
	 * inside AppKit's own close, which goes on addressing this object afterwards. It also makes the
	 * two harmless should they ever both run, which the pair of autoreleases here would not have
	 * been, since that would have given the same reference back twice.
	 */
	CFAutorelease(CFBridgingRetain(self));
	[openPresetManagementControllers removeObject:self];
}

/*!
 * @brief As the window closes, leave the set of open controllers
 */
- (void)windowWillClose:(id)sender
{
	[super windowWillClose:sender];

	/* Out of the set, but not before this turn of the run loop ends: both exits are reached from
	 * inside AppKit's own close, which goes on addressing this object afterwards. It also makes the
	 * two harmless should they ever both run, which the pair of autoreleases here would not have
	 * been, since that would have given the same reference back twice.
	 */
	CFAutorelease(CFBridgingRetain(self));
	[openPresetManagementControllers removeObject:self];
}

/*!
 * @brief Duplicate the selected preset
 */
- (IBAction)duplicatePreset:(id)sender
{
	//Finish any editing before continuing: a rename still being typed goes in first, and may move the row
	[self endEditing];

	NSInteger selectedRow = [tableView_presets selectedRow];
	if (selectedRow != -1) {
		id duplicatePreset, selectedPreset;
		NSInteger duplicatePresetIndex;

		selectedPreset = [presets objectAtIndex:selectedRow];
		
		//Inform the delegate of the duplicate request
		NSArray	*newPresets;
		newPresets = [delegate duplicatePreset:selectedPreset
									 inPresets:presets
							  createdDuplicate:&duplicatePreset];

		presets = newPresets;
		
		//The delegate returned a potentially changed presets array; reload table data
		[tableView_presets reloadData];

		//Set up for a rename of the new duplicate if possible
		if (duplicatePreset) {
			duplicatePresetIndex = [presets indexOfObject:duplicatePreset];
			if (duplicatePresetIndex != NSNotFound) {
				[tableView_presets selectRowIndexes:[NSIndexSet indexSetWithIndex:duplicatePresetIndex] byExtendingSelection:NO];
				[tableView_presets editColumn:0
										  row:duplicatePresetIndex
									withEvent:nil
									   select:YES];
			}
		} else {
			NSLog(@"Failed to retrieve duplicate preset while duplicating %@ in %@",selectedPreset,presets);
		}
	}	
}

/*!
 * @brief Delete the selected preset
 */
- (IBAction)deletePreset:(id)sender
{
	//Finish any editing before continuing, so the row about to go is the one that is selected
	[self endEditing];

	NSInteger selectedRow = [tableView_presets selectedRow];
	if (selectedRow != -1) {
		id selectedPreset = [presets objectAtIndex:selectedRow];

		//Inform the delegate of the deletion
		NSArray	*newPresets;
		newPresets = [delegate deletePreset:selectedPreset inPresets:presets];
		presets = newPresets;
		
		//The delegate returned a potentially changed presets array; reload table data
		[tableView_presets reloadData];
		
		//Reloading after the deletion changed our selection
		[self tableViewSelectionDidChange:[NSNotification notificationWithName:@"SelectionChanged" object:nil]];
	}
}

/*!
 * @brief Rename the selected preset
 */
- (IBAction)renamePreset:(id)sender
{
	NSInteger selectedRow = [tableView_presets selectedRow];
	if (selectedRow != -1) {
		[tableView_presets editColumn:0 row:selectedRow withEvent:nil select:YES];
	}
}

/*!
 * @brief Configure control dimming
 */
- (void)configureControlDimming
{
	NSInteger selectedRow = [tableView_presets selectedRow];
	
	if (selectedRow != -1) {
		id	preset = [presets objectAtIndex:selectedRow];
		BOOL	allowDelete = (![delegate respondsToSelector:@selector(allowDeleteOfPreset:)] ||
							   [delegate allowDeleteOfPreset:preset]);
		BOOL	allowRename = (![delegate respondsToSelector:@selector(allowRenameOfPreset:)] ||
							   [delegate allowRenameOfPreset:preset]);

		[button_delete setEnabled:allowDelete];
		[button_rename setEnabled:allowRename];
		
		//Always allow duplication
		[button_duplicate setEnabled:YES];
		
	} else {
		[button_duplicate setEnabled:NO];
		[button_delete setEnabled:NO];
		[button_rename setEnabled:NO];
	}
}

#pragma mark Table view data source and delegate

//State List Table Delegate --------------------------------------------------------------------------------------------
#pragma mark State List (Table Delegate)
/*!
 * @brief Number of rows
 */
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [presets count];
}

/*!
 * @brief Table values
 */
- (NSString *)nameForRow:(NSInteger)row
{
	id	preset = [presets objectAtIndex:row];

	if ([preset isKindOfClass:[NSDictionary class]]) {
		return [preset objectForKey:(nameKey ? nameKey : @"Name")];
		
	} else if ([preset isKindOfClass:[NSString class]]) {
		return preset;
	}
	
	return @"";
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[presets count])
		return nil;

	NSTableCellView	*view = [tableView ai_labelCellViewForColumn:tableColumn value:[self nameForRow:row]];
	NSTextField		*field = [view textField];

	//Renamed in place: the label is the field, and its action is the rename
	[field setEditable:YES];
	[field setTarget:self];
	[field setAction:@selector(presetNameEdited:)];
	[[field cell] setSendsActionOnEndEditing:YES];

	return view;
}

/*!
 * @brief Whatever is still being typed goes in now
 */
- (void)endEditing
{
	[[tableView_presets window] makeFirstResponder:tableView_presets];
}

- (void)presetNameEdited:(id)sender
{
	NSInteger	row = [tableView_presets rowForView:sender];
	id			anObject = [sender stringValue];

	if (row < 0 || row >= (NSInteger)[presets count])
		return;

	if ([anObject isKindOfClass:[NSString class]]) {
		id			preset = [presets objectAtIndex:row];
		NSString	*oldName = nil;

		if ([preset isKindOfClass:[NSDictionary class]]) {
			oldName = [preset objectForKey:(nameKey ? nameKey : @"Name")];

		} else if ([preset isKindOfClass:[NSString class]]) {
			oldName = preset;
		}

		if (![(NSString *)anObject isEqualToString:oldName]) {
			//Inform the delegate of the rename
			NSArray	*newPresets;
			id			renamedPreset;
			
			newPresets = [delegate renamePreset:preset toName:(NSString *)anObject inPresets:presets renamedPreset:&renamedPreset];
			presets = newPresets;
			
			//The delegate returned a potentially changed presets array; reload table data
			[tableView_presets reloadData];
						
			//Select the new row
			[tableView_presets selectRowIndexes:[NSIndexSet indexSetWithIndex:[presets indexOfObjectIdenticalTo:renamedPreset]] byExtendingSelection:NO];
		}
	}		
}

/*!
 * @brief Delete the selected row
 */
- (void)tableViewDeleteSelectedRows:(NSTableView *)tableView
{
    [self deletePreset:nil];
}

/*!
 * @brief Selection change
 */
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self configureControlDimming];
}

/*!
 * @brief Drag start
 *
 * Only allow the drag to start if the delegate responds to @selector(movePreset:toIndex:inPresets:)
 */
- (id <NSPasteboardWriting>)tableView:(NSTableView *)tv pasteboardWriterForRow:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[presets count] ||
		![delegate respondsToSelector:@selector(movePreset:toIndex:inPresets:presetAfterMove:)])
		return nil;

	tempDragPreset = [presets objectAtIndex:row];

	NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
	[item setString:@"Preset" forType:PRESET_DRAG_TYPE]; //Arbitrary state

	return item;
}

/*!
 * @brief Drag validate
 */
- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op
{
    if (op == NSTableViewDropAbove && row != -1) {
        return NSDragOperationPrivate;
    } else {
        return NSDragOperationNone;
    }
}

/*!
 * @brief Drag complete
 */
- (BOOL)tableView:(NSTableView*)tv acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)op
{
    NSString	*availableType = [[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:PRESET_DRAG_TYPE]];
	BOOL		success = NO;
    if ([availableType isEqualToString:PRESET_DRAG_TYPE]) {		
		NSDictionary	*presetAfterMove = tempDragPreset;
		
		//Inform the delegate of the move; it may pass back a changed preset by reference
		NSArray	*newPresets;
		newPresets = [delegate movePreset:tempDragPreset toIndex:row inPresets:presets presetAfterMove:&presetAfterMove];
		presets = newPresets;

		//Reload with the new data
		[tableView_presets reloadData];
		
		//Reselect the moved preset if possible
		NSInteger movedPresetIndex = [presets indexOfObject:presetAfterMove];
		if (movedPresetIndex != NSNotFound) {
			[tableView_presets selectRowIndexes:[NSIndexSet indexSetWithIndex:movedPresetIndex] byExtendingSelection:NO];
		}

        success = YES;
    }
	
	tempDragPreset = nil;

	return success;
}

@end
