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

#import "AIEmoticon.h"
#import "AIEmoticonPack.h"
#import "AIEmoticonPreferences.h"
#import "AIEmoticonController.h"
#import <AIUtilities/AITableViewAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIArrayAdditions.h>

#import <Adium/AIListObject.h>

#define	EMOTICON_PACK_DRAG_TYPE         @"com.adium.emoticon-pack-row"		//A pasteboard type is a UTI now
#define EMOTICON_MIN_ROW_HEIGHT         17
#define EMOTICON_MAX_ROW_HEIGHT			64
#define EMOTICON_PACKS_TOOLTIP          AILocalizedString(@"Reorder emoticon packs by dragging. Packs are used in the order listed.",nil)

//The pack row: the checkbox with the name beside it, and under them a strip of the pack's first emoticons
#define PACK_PREVIEW_MAX_SIZE			20.0f
#define PACK_PREVIEW_SPACING			4.0f
#define PACK_INSET						4.0f
#define PACK_TITLE_HEIGHT				18.0f

/*!
 * @class AIEmoticonPackStripView
 * @brief A row of a pack's first emoticons, as many as fit
 *
 * What the old preview nib drew, without the nib: each picture no larger than twenty points, on an
 * even grid, so the strips of the packs line up under one another.
 */
@interface AIEmoticonPackStripView : NSView {
	AIEmoticonPack	*emoticonPack;
}
- (void)setEmoticonPack:(AIEmoticonPack *)inPack;
@end

@implementation AIEmoticonPackStripView

- (void)setEmoticonPack:(AIEmoticonPack *)inPack
{
	emoticonPack = inPack;
	[self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect
{
	NSRect	bounds = [self bounds];
	CGFloat	x = 0.0f;

	for (AIEmoticon *emoticon in [emoticonPack emoticons]) {
		NSImage	*image = [emoticon image];
		NSSize	drawn = [image size];

		if (drawn.width <= 0.0f || drawn.height <= 0.0f)
			continue;

		//Scaled down to fit the strip, keeping its proportions; never scaled up
		if (drawn.width > PACK_PREVIEW_MAX_SIZE) {
			drawn.height *= PACK_PREVIEW_MAX_SIZE / drawn.width;
			drawn.width = PACK_PREVIEW_MAX_SIZE;
		}
		if (drawn.height > PACK_PREVIEW_MAX_SIZE) {
			drawn.width *= PACK_PREVIEW_MAX_SIZE / drawn.height;
			drawn.height = PACK_PREVIEW_MAX_SIZE;
		}

		//Only whole pictures: one cut off at the edge says less than none
		if (x + drawn.width > NSWidth(bounds))
			break;

		[image drawInRect:NSMakeRect(x, floor((NSHeight(bounds) - drawn.height) / 2.0f), drawn.width, drawn.height)
				 fromRect:NSZeroRect
				operation:NSCompositingOperationSourceOver
				 fraction:1.0f
		   respectFlipped:YES
					hints:nil];

		x += PACK_PREVIEW_MAX_SIZE + PACK_PREVIEW_SPACING;
	}
}

@end

/*!
 * @class AIEmoticonPackCellView
 * @brief One row of the packs list: switched on or off, named, and shown
 */
@interface AIEmoticonPackCellView : NSTableCellView {
	NSButton				*checkbox;
	NSTextField				*nameField;
	AIEmoticonPackStripView	*strip;
}
@property (nonatomic, readonly) NSButton *checkbox;
- (void)setPack:(AIEmoticonPack *)pack;
- (void)layoutFields;
@end

@implementation AIEmoticonPackCellView

@synthesize checkbox;

- (id)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		checkbox = [[NSButton alloc] initWithFrame:NSZeroRect];
		[checkbox setButtonType:NSButtonTypeSwitch];
		[checkbox setTitle:@""];
		[checkbox setImagePosition:NSImageOnly];
		[checkbox setControlSize:NSControlSizeSmall];
		[checkbox sizeToFit];
		[self addSubview:checkbox];

		nameField = [NSTextField labelWithString:@""];
		[nameField setFont:[NSFont systemFontOfSize:12]];
		[nameField setLineBreakMode:NSLineBreakByTruncatingTail];
		[self addSubview:nameField];
		//The table's own outlet, so the highlight recolours the name by itself
		[self setTextField:nameField];

		strip = [[AIEmoticonPackStripView alloc] initWithFrame:NSZeroRect];
		[self addSubview:strip];
	}

	return self;
}

- (void)setPack:(AIEmoticonPack *)pack
{
	[checkbox setState:([pack isEnabled] ? NSControlStateValueOn : NSControlStateValueOff)];
	[nameField setStringValue:([pack name] ? [pack name] : @"")];
	[strip setEmoticonPack:pack];
	[self layoutFields];
}

- (void)layout
{
	[super layout];
	[self layoutFields];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
	[super resizeSubviewsWithOldSize:oldSize];
	[self layoutFields];
}

- (void)layoutFields
{
	NSRect	bounds = [self bounds];
	CGFloat	height = NSHeight(bounds);
	NSSize	checkSize = [checkbox frame].size;
	CGFloat	titleY = height - PACK_INSET - PACK_TITLE_HEIGHT;

	//The switch and the name on the upper line
	[checkbox setFrameOrigin:NSMakePoint(PACK_INSET, titleY + floor((PACK_TITLE_HEIGHT - checkSize.height) / 2.0f))];

	CGFloat nameX = PACK_INSET + checkSize.width + 2.0f;
	[nameField setFrame:NSMakeRect(nameX, titleY, MAX(1.0f, NSWidth(bounds) - nameX - PACK_INSET), PACK_TITLE_HEIGHT)];

	//The strip on the lower one, aligned with the name
	[strip setFrame:NSMakeRect(nameX, 2.0f, MAX(1.0f, NSWidth(bounds) - nameX - PACK_INSET), MAX(1.0f, titleY - 2.0f))];
}

@end

@interface AIEmoticonPreferences ()
- (void)_configureEmoticonListForSelection;
- (void)moveSelectedPacksToTrash;
- (void)reloadPacks;
- (void)fitColumnsOfTable:(NSTableView *)table;
- (void)listWidthChanged:(NSNotification *)notification;
- (void)packToggled:(id)sender;
- (void)emoticonToggled:(id)sender;
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
@end

/* The preference sheets currently on screen.
 *
 * -openOnWindow: is declared ns_consumes_self. Under manual counting that was decoration, quieting
 * the analyser about AIAppearancePreferences allocating this object and walking away. Counted
 * automatically it means what it says: the one reference is handed over at the call and given up
 * when the method returns, so with nothing else holding on, the sheet would die as it appeared.
 * This set holds it instead, in place of an object that used to be its own owner.
 */
static NSMutableSet *openEmoticonPreferences = nil;

@implementation AIEmoticonPreferences

- (id)init
{
	if (self = [super initWithWindowNibName:@"EmoticonPrefs"]) {
		
	}
	
	return self;
}

- (void)openOnWindow:(NSWindow *)parentWindow
{
	if (!openEmoticonPreferences) openEmoticonPreferences = [[NSMutableSet alloc] init];
	[openEmoticonPreferences addObject:self];

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
* Invoked as the sheet closes, dismiss the sheet
 */
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	[sheet orderOut:nil];
	
	viewIsOpen = NO;
	
	[adium.preferenceController unregisterPreferenceObserver:self];
	//The lists' widths are no longer this window's business
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:nil];
    [adium.emoticonController flushEmoticonImageCache];

	/* Out of the set, but not before this turn of the run loop ends: both exits are reached from
	 * inside AppKit's own close, which goes on addressing this object afterwards. It also makes the
	 * two harmless should they ever both run, which the pair of autoreleases here would not have
	 * been, since that would have given the same reference back twice.
	 */
	CFAutorelease(CFBridgingRetain(self));
	[openEmoticonPreferences removeObject:self];
}

//Configure the preference view
//- (void)viewDidLoad
- (void)windowDidLoad
{
	//Pack table
	[table_emoticonPacks registerForDraggedTypes:[NSArray arrayWithObject:EMOTICON_PACK_DRAG_TYPE]];
	[table_emoticonPacks setToolTip:EMOTICON_PACKS_TOOLTIP];
	[table_emoticonPacks setDelegate:self];
	[table_emoticonPacks setDataSource:self];
	[table_emoticonPacks setUsesAlternatingRowBackgroundColors:YES];
	[self reloadPacks];
	[table_emoticonPacks selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

	//Emoticons table
	selectedEmoticonPack = nil;
	[table_emoticons setUsesAlternatingRowBackgroundColors:YES];

	/* Neither list has anything to show sideways, and neither should give when pushed that way.
	 * Sizing the columns is what settles it: a table is as wide as its columns make it, and the
	 * nib leaves both with columns wider than the room they have. The clip view changes width
	 * whenever the scroller comes or goes, so the fitting is done again whenever it does. */
	for (NSTableView *table in [NSArray arrayWithObjects:table_emoticonPacks, table_emoticons, nil]) {
		NSScrollView *scrollView = [table enclosingScrollView];
		NSClipView *clipView = [scrollView contentView];

		[scrollView setHorizontalScrollElasticity:NSScrollElasticityNone];
		[table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
		[table setAutoresizingMask:NSViewWidthSizable];

		//What the nib meant each column to be; every fitting starts again from these
		if (!nibColumnWidths)
			nibColumnWidths = [[NSMutableDictionary alloc] init];

		for (NSTableColumn *column in [table tableColumns]) {
			[nibColumnWidths setObject:[NSNumber numberWithDouble:[column width]]
								forKey:[column identifier]];
		}

		[clipView setPostsFrameChangedNotifications:YES];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(listWidthChanged:)
													 name:NSViewFrameDidChangeNotification
												   object:clipView];
		[self fitColumnsOfTable:table];
	}

	//Observe prefs
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_EMOTICONS];

	//Configure the right pane to display the emoticons for the current selection
	[self _configureEmoticonListForSelection];

	[button_OK setTitle:AILocalizedStringFromTable(@"Close", @"Buttons", nil)];

	viewIsOpen = YES;
}

- (void)windowWillClose:(id)sender
{
	viewIsOpen = NO;
	
	[super windowWillClose:sender];
	
	[adium.preferenceController unregisterPreferenceObserver:self];
	//The lists' widths are no longer this window's business
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:nil];
    [adium.emoticonController flushEmoticonImageCache];

	/* Out of the set, but not before this turn of the run loop ends: both exits are reached from
	 * inside AppKit's own close, which goes on addressing this object afterwards. It also makes the
	 * two harmless should they ever both run, which the pair of autoreleases here would not have
	 * been, since that would have given the same reference back twice.
	 */
	CFAutorelease(CFBridgingRetain(self));
	[openEmoticonPreferences removeObject:self];
}

/*!
 * @brief Take the columns in until the table is no wider than the room it has
 *
 * A table is as wide as its columns make it, plus whatever padding its style keeps, and a table
 * wider than its clip view scrolls sideways. Rather than reckon that padding, the overflow is
 * measured and taken off whichever column has the most room to give, so that a narrow column
 * holding something short, an emoticon's text among them, keeps the width it was given while a
 * wide one gives way.
 *
 * Every fitting starts again from the widths the nib set. Taking the overflow off what a previous
 * fitting left would be a ratchet: the scroller comes and goes as packs are switched between, and
 * the columns would walk down to their minimums over an afternoon and never come back.
 */
- (void)fitColumnsOfTable:(NSTableView *)table
{
	NSScrollView *scrollView = [table enclosingScrollView];

	if (!scrollView)
		return;

	for (NSTableColumn *column in [table tableColumns]) {
		NSNumber *width = [nibColumnWidths objectForKey:[column identifier]];

		if (width)
			[column setWidth:[width doubleValue]];
	}

	[table tile];

	CGFloat room = NSWidth([[scrollView contentView] bounds]);

	for (NSUInteger pass = 0; pass < 4; pass++) {
		CGFloat			overflow = NSWidth([table frame]) - room;
		NSTableColumn	*widest = nil;
		CGFloat			mostRoomToGive = 0.5;

		if (overflow < 1.0)
			break;

		for (NSTableColumn *column in [table tableColumns]) {
			CGFloat roomToGive = [column width] - [column minWidth];

			if (roomToGive > mostRoomToGive) {
				mostRoomToGive = roomToGive;
				widest = column;
			}
		}

		//Every column already at its minimum: nothing more to take, and the table stays too wide
		if (!widest)
			break;

		[widest setWidth:([widest width] - MIN(overflow, mostRoomToGive))];
		[table tile];
	}
}

/*!
 * @brief The room a list has changed, because its scroller came or went
 */
- (void)listWidthChanged:(NSNotification *)notification
{
	for (NSTableView *table in [NSArray arrayWithObjects:table_emoticonPacks, table_emoticons, nil]) {
		if ([[table enclosingScrollView] contentView] == [notification object])
			[self fitColumnsOfTable:table];
	}
}

/*!
 * @brief The packs, in the order they are used, straight from the controller
 */
- (void)reloadPacks
{
	emoticonPacks = [adium.emoticonController availableEmoticonPacks];
	[table_emoticonPacks reloadData];
}

//Configure the emoticon table view for the currently selected pack
- (void)_configureEmoticonListForSelection
{
	NSInteger	rowHeight = EMOTICON_MIN_ROW_HEIGHT;
	NSInteger	selectedRow = [table_emoticonPacks selectedRow];

	//Remember the selected pack
	if ([table_emoticonPacks numberOfSelectedRows] == 1 &&
		((selectedRow != -1) && (selectedRow < (NSInteger)[emoticonPacks count]))) {
		selectedEmoticonPack = [emoticonPacks objectAtIndex:selectedRow];
	} else {
		selectedEmoticonPack = nil;
	}

	//Set the row height to the average height of the emoticons
	if (selectedEmoticonPack && [[selectedEmoticonPack emoticons] count]) {
		NSInteger totalHeight = 0;

		for (AIEmoticon *emoticon in [selectedEmoticonPack emoticons])
			totalHeight += [[emoticon image] size].height;

		rowHeight = totalHeight / [[selectedEmoticonPack emoticons] count];
		if (rowHeight < EMOTICON_MIN_ROW_HEIGHT) rowHeight = EMOTICON_MIN_ROW_HEIGHT;
		if (rowHeight > EMOTICON_MAX_ROW_HEIGHT) rowHeight = EMOTICON_MAX_ROW_HEIGHT;
	}

	emoticonImageCache = [[NSMutableDictionary alloc] init];

	//Update the table
	[table_emoticons setRowHeight:rowHeight];
	[table_emoticons reloadData];

	//Update header
	if (selectedEmoticonPack) {
		[textField_packTitle setStringValue:[NSString stringWithFormat:AILocalizedString(@"Emoticons in %@","Emoticons in <an emoticon pack name>"),[selectedEmoticonPack name]]];
	} else {
		[textField_packTitle setStringValue:@""];
	}
}

//Reflect new preferences in view
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	/* Refresh our emoticon tables, keeping the selected pack: a view based table drops its
	 * selection on a reload, where the cell based one it replaced kept it, and the emoticons on
	 * the right are the selected pack's. Without this, switching one emoticon off emptied them. */
	AIEmoticonPack	*wasSelected = selectedEmoticonPack;

	[self reloadPacks];

	NSUInteger index = (wasSelected ? [emoticonPacks indexOfObjectIdenticalTo:wasSelected] : NSNotFound);

	if (index != NSNotFound)
		[table_emoticonPacks selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];

	[self _configureEmoticonListForSelection];
}


#pragma mark Table view data source
//Emoticon table view
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == table_emoticonPacks) {
		return [emoticonPacks count];
	} else {
		return [[selectedEmoticonPack emoticons] count];
	}
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (tableView == table_emoticonPacks) {
		if (row < 0 || row >= (NSInteger)[emoticonPacks count])
			return nil;

		AIEmoticonPackCellView *view = [tableView makeViewWithIdentifier:@"pack" owner:nil];

		if (!view) {
			view = [[AIEmoticonPackCellView alloc] initWithFrame:NSZeroRect];
			[view setIdentifier:@"pack"];
			[[view checkbox] setTarget:self];
			[[view checkbox] setAction:@selector(packToggled:)];
		}

		[view setPack:[emoticonPacks objectAtIndex:row]];
		return view;
	}

	NSArray *emoticons = [selectedEmoticonPack emoticons];

	if (row < 0 || row >= (NSInteger)[emoticons count])
		return nil;

	NSString	*identifier = [tableColumn identifier];
	AIEmoticon	*emoticon = [emoticons objectAtIndex:row];
	BOOL		packEnabled = selectedEmoticonPack.isEnabled;

	if ([identifier isEqualToString:@"Enabled"]) {
		//An emoticon in a switched off pack cannot be switched on by itself
		return [tableView ai_checkboxCellViewForColumn:tableColumn
													on:emoticon.isEnabled
											   enabled:packEnabled
												target:self
												action:@selector(emoticonToggled:)];
	}

	if ([identifier isEqualToString:@"Image"]) {
		NSNumber	*key = [NSNumber numberWithUnsignedInteger:[emoticon hash]];
		NSImage		*image = [emoticonImageCache objectForKey:key];

		if (!image) {
			image = [emoticon image];
			if (image)
				[emoticonImageCache setObject:image forKey:key];
		}

		return [tableView ai_imageCellViewForColumn:tableColumn image:image];
	}

	NSString *text;

	if ([identifier isEqualToString:@"Name"]) {
		text = emoticon.name;
	} else {
		NSArray *textEquivalents = [emoticon textEquivalents];

		text = ([textEquivalents count] ? [textEquivalents objectAtIndex:0] : @"");
	}

	NSTableCellView *view = [tableView ai_labelCellViewForColumn:tableColumn value:text];

	//An emoticon that is off, or in a pack that is off, is greyed out
	[[view textField] setTextColor:((packEnabled && emoticon.isEnabled) ? [NSColor labelColor] : [NSColor secondaryLabelColor])];
	[[view textField] setAlignment:([identifier isEqualToString:@"String"] ? NSTextAlignmentCenter : NSTextAlignmentNatural)];

	return view;
}

//The emoticons list is a list of switches, not of things to select
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	return (tableView == table_emoticonPacks);
}

- (void)packToggled:(id)sender
{
	NSInteger row = [table_emoticonPacks rowForView:sender];

	if (row < 0 || row >= (NSInteger)[emoticonPacks count])
		return;

	[adium.emoticonController setEmoticonPack:[emoticonPacks objectAtIndex:row]
									  enabled:([sender state] == NSControlStateValueOn)];
	[table_emoticonPacks selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

- (void)emoticonToggled:(id)sender
{
	NSInteger	row = [table_emoticons rowForView:sender];
	NSArray		*emoticons = [selectedEmoticonPack emoticons];

	if (row < 0 || row >= (NSInteger)[emoticons count])
		return;

	[adium.emoticonController setEmoticon:[emoticons objectAtIndex:row]
								   inPack:selectedEmoticonPack
								  enabled:([sender state] == NSControlStateValueOn)];
}

#pragma mark Drag and Drop


- (id <NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
	if (tableView != table_emoticonPacks)
		return nil;

	NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
	[item setString:@"dragPack" forType:EMOTICON_PACK_DRAG_TYPE];

	return item;
}

//Which rows a drag took along; the drop moves the packs of these
- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forRowIndexes:(NSIndexSet *)rowIndexes
{
	if (tableView == table_emoticonPacks)
		dragRows = rowIndexes;
}

- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op;
{
	if (tableView == table_emoticonPacks && op == NSTableViewDropAbove && row != -1)
		return NSDragOperationMove;
	
	return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView*)tableView acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)op;
{
	if (tableView != table_emoticonPacks)
		return NO;

	NSString	*availableType = [[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:EMOTICON_PACK_DRAG_TYPE]];

	if (![availableType isEqualToString:EMOTICON_PACK_DRAG_TYPE])
		return NO;

	//Move
	NSMutableArray  *movedPacks = [NSMutableArray array]; //Keep track of the packs we've moved
	NSArray			*packsBeforeMove = emoticonPacks;
	[dragRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
		if (idx < [packsBeforeMove count])
			[movedPacks addObject:[packsBeforeMove objectAtIndex:idx]];
	}];
	dragRows = nil;
	[adium.emoticonController moveEmoticonPacks:movedPacks toIndex:row];
	[self reloadPacks];

	//Select the moved packs, wherever they are now
	[tableView deselectAll:nil];
	for (AIEmoticonPack *emoticonPack in emoticonPacks) {
		if ([movedPacks containsObjectIdenticalTo:emoticonPack]) {
			[tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:[emoticonPacks indexOfObjectIdenticalTo:emoticonPack]] byExtendingSelection:NO];
		}
	}

	return YES;
}

#pragma mark Deletion


- (void)tableViewDeleteSelectedRows:(NSTableView *)tableView
{
	//Prevent deleting included packs
	NSRange range = [selectedEmoticonPack.path rangeOfString:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Emoticons"]];
	if (range.length > 0)
		NSBeep();
	else
		[self moveSelectedPacksToTrash];
}

-(void)moveSelectedPacksToTrash
{
	NSString	*name = [selectedEmoticonPack.name copy];
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:AILocalizedString(@"Delete Emoticon Pack",nil)];
	[alert setInformativeText:[NSString stringWithFormat:
							   AILocalizedString(@"Are you sure you want to delete the %@ Emoticon Pack? It will be moved to the Trash.",nil), name]];
	[alert addButtonWithTitle:AILocalizedString(@"Delete",nil)];	//NSAlertFirstButtonReturn, was the default button (old return value 1 == NSModalResponseOK)
	[alert addButtonWithTitle:AILocalizedString(@"Cancel",nil)];
	[alert beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse returnCode) {
		if (returnCode != NSAlertFirstButtonReturn)
			return;

		for (AIEmoticonPack *pack in [self->table_emoticonPacks selectedItemsFromArray:self->emoticonPacks]) {
			[[NSFileManager defaultManager] trashFileAtPath:pack.path];
		}

		[self->table_emoticonPacks deselectAll:nil];
		//Note the changed packs
		[adium.emoticonController xtrasChanged:nil];
	}];
}

#pragma mark Selection changes
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	if ([notification object] == table_emoticonPacks)
		[self _configureEmoticonListForSelection];
}

- (void)emoticonXtrasDidChange
{
	if (viewIsOpen)
		[self reloadPacks];
}

@end
