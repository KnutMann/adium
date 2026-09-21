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

#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIListObject.h>
#import <Adium/AIListContact.h>
#import <Adium/CSNewContactAlertWindowController.h>
#import <Adium/AIContactAlertsControllerProtocol.h>
#import <Adium/ESContactAlertsViewController.h>
#import <AIUtilities/AIAutoScrollView.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIOutlineView.h>
#import <AIUtilities/AIArrayAdditions.h>
#import <AIUtilities/AIAttributedStringAdditions.h>

#define VERTICAL_ROW_PADDING	6
#define MINIMUM_IMAGE_HEIGHT		20.0f
#define MINIMUM_ROW_HEIGHT			/* 32.0f */ 16.0f

//The one column's row: a picture in a slot at the leading edge, the event's name, and under it what happens
#define CELL_INSET					2.0f
#define ICON_SLOT_WIDTH				40.0f		//The image column's width, less the spacing it had beside it
#define TEXT_GAP					6.0f
#define LINE_GAP					1.0f		//Between the name and the line under it
#define MEASURING_ALLOWANCE			20.0f		//What the outline keeps for the disclosure triangle, near enough

/*!
 * @class AIContactAlertCellView
 * @brief One row of the events list: the picture, the event, and under it what happens
 *
 * The three columns the list used to have, in one view: the name in bold, and under it, small and
 * grey, the sentence saying what the event does, the way a settings list puts a subtitle under a
 * title. The same shape whether the event is collapsed or expanded to show its actions, so a row
 * never changes height for being opened. Laid out by hand, since the row's height is decided from
 * the text by the controller, as it was.
 */
@interface AIContactAlertCellView : NSTableCellView {
	NSImageView		*iconView;
	NSTextField		*titleField;
	NSTextField		*summaryField;
	CGFloat			 iconSize;
}
- (void)setImage:(NSImage *)image size:(CGFloat)size title:(NSString *)title font:(NSFont *)font summary:(NSString *)summary;
- (void)layoutFields;
@end

@implementation AIContactAlertCellView

- (id)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		[iconView setImageScaling:NSImageScaleProportionallyDown];
		[iconView setImageAlignment:NSImageAlignCenter];
		[self addSubview:iconView];

		titleField = [NSTextField wrappingLabelWithString:@""];
		[titleField setSelectable:NO];
		[self addSubview:titleField];
		//The table's own outlet, so the highlight recolours the title by itself
		[self setTextField:titleField];

		summaryField = [NSTextField wrappingLabelWithString:@""];
		[summaryField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		[summaryField setTextColor:[NSColor secondaryLabelColor]];
		[summaryField setSelectable:NO];
		[self addSubview:summaryField];
	}

	return self;
}

- (void)setImage:(NSImage *)image size:(CGFloat)size title:(NSString *)title font:(NSFont *)font summary:(NSString *)summary
{
	[iconView setImage:image];
	iconSize = size;
	[titleField setStringValue:(title ? title : @"")];
	[titleField setFont:font];
	[summaryField setStringValue:(summary ? summary : @"")];
	[summaryField setHidden:![summary length]];
	[self layoutFields];
}

//The title the table recolours itself; the small line under it is recoloured here
- (void)setBackgroundStyle:(NSBackgroundStyle)style
{
	[super setBackgroundStyle:style];
	[summaryField setTextColor:((style == NSBackgroundStyleEmphasized) ?
								[NSColor alternateSelectedControlTextColor] :
								[NSColor secondaryLabelColor])];
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

	//The picture, centred in its slot and never taller than the row leaves it
	CGFloat drawnIconSize = MIN(iconSize, MAX(0.0f, height - 4.0f));
	[iconView setFrame:NSMakeRect(CELL_INSET + floor((ICON_SLOT_WIDTH - drawnIconSize) / 2.0f),
								  floor((height - drawnIconSize) / 2.0f),
								  drawnIconSize, drawnIconSize)];

	CGFloat textX = CELL_INSET + ICON_SLOT_WIDTH + TEXT_GAP;
	CGFloat textWidth = MAX(1.0f, NSWidth(bounds) - textX - CELL_INSET);
	CGFloat titleHeight = ceil([[titleField cell] cellSizeForBounds:NSMakeRect(0.0f, 0.0f, textWidth, 10000.0f)].height);
	BOOL	hasSummary = ![summaryField isHidden];
	CGFloat summaryHeight = (hasSummary ? ceil([[summaryField cell] cellSizeForBounds:NSMakeRect(0.0f, 0.0f, textWidth, 10000.0f)].height) : 0.0f);
	CGFloat total = MIN(height, titleHeight + (hasSummary ? (LINE_GAP + summaryHeight) : 0.0f));

	//Not flipped: the name sits at the top of the block, which is the far end of the y axis
	CGFloat top = floor((height - total) / 2.0f);
	CGFloat titleY = height - top - titleHeight;
	[titleField setFrame:NSMakeRect(textX, titleY, textWidth, titleHeight)];

	if (hasSummary) {
		CGFloat summaryTop = titleY - LINE_GAP;
		CGFloat shown = MAX(0.0f, MIN(summaryHeight, summaryTop));

		[summaryField setFrame:NSMakeRect(textX, summaryTop - shown, textWidth, shown)];
	}
}

@end

@interface ESContactAlertsViewController ()
- (id)textOrImageForItem:(id)item column:(NSString *)identifier;
- (NSFont *)titleFontForItem:(id)item;
- (void)configureEventSummaryOutlineView;
- (void)reloadSummaryData;
- (void)deleteContactActionsInArray:(NSArray *)contactEventArray;

- (void)calculateAllHeights;
- (void)calculateHeightForItem:(id)item;

- (IBAction)didDoubleClick:(id)sender;

- (void)addAlert;
- (void)deleteAlert;
@end

int alertAlphabeticalSort(id objectA, id objectB, void *context);
int globalAlertAlphabeticalSort(id objectA, id objectB, void *context);

//#define HEIGHT_DEBUG

@implementation ESContactAlertsViewController

//Configure the preference view
- (void)awakeFromNib
{
	AILogWithSignature(@"");
	expandStateDict = [[NSMutableDictionary alloc] init];
	requiredHeightDict = [[NSMutableDictionary alloc] init];

	//Configure Table view
	[self configureEventSummaryOutlineView];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(outlineViewColumnDidResize:)
									   name:NSOutlineViewColumnDidResizeNotification
									 object:outlineView_summary];
	{
		NSRect newFrame, oldFrame;
		oldFrame = [button_edit frame];
		[button_edit setTitle:AILocalizedStringFromTable(@"Edit", @"Buttons", "Verb 'edit' on a button")];
		[button_edit sizeToFit];
		newFrame = [button_edit frame];
		if (newFrame.size.width < oldFrame.size.width) newFrame.size.width = oldFrame.size.width;
		newFrame.origin.x = oldFrame.origin.x + oldFrame.size.width - newFrame.size.width;
		[button_edit setFrame:newFrame];
	}

	[button_edit setToolTip:AILocalizedString(@"Configure the selected action", nil)];
	[[button_addOrRemoveAlert cell] setToolTip:AILocalizedString(@"Add an action for the selected event", nil) forSegment:0];
	[[button_addOrRemoveAlert cell] setToolTip:AILocalizedString(@"Remove the selected action(s)", nil) forSegment:1];

	[outlineView_summary setAccessibilityLabel:AILocalizedString(@"Events", nil)];

	//Update enable state of our buttons
	[self outlineViewSelectionDidChange:[NSNotification notificationWithName:@"SelectionChanged" object:nil]];
	
	configureForGlobal = NO;
	showEventsInEditSheet = NO;

	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_CONTACT_ALERTS];
}

//Preference view is closing - stop observing preferences immediately, even if we aren't immediately deallocating
- (void)viewWillClose
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[adium.preferenceController unregisterPreferenceObserver:self];
}

- (void)dealloc
{
	//Ensure that we have unregistered as a preference observer
	[adium.preferenceController unregisterPreferenceObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[outlineView_summary setDelegate:nil];
	[outlineView_summary setDataSource:nil];
}

- (void)setDelegate:(id)inDelegate
{
	NSParameterAssert([inDelegate respondsToSelector:@selector(contactAlertsViewController:updatedAlert:oldAlert:)]);
	NSParameterAssert([inDelegate respondsToSelector:@selector(contactAlertsViewController:deletedAlert:)]);
	delegate = inDelegate;
}

- (id)delegate
{
	return delegate;
}

- (void)outlineViewColumnDidResize:(NSNotification *)notification
{
	[self calculateAllHeights];
	[outlineView_summary reloadData];
//	[outlineView_summary noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [outlineView_summary numberOfRows]-1)]];
}

//Configure the pane for a list object
- (void)configureForListObject:(AIListObject *)inObject
{
	[self configureForListObject:inObject showingAlertsForEventID:nil];
}

- (void)configureForListObject:(AIListObject *)inObject showingAlertsForEventID:(NSString *)inTargetEventID
{
	//Cancel any existing edit/add panel, since we're no longer looking at the same object
	if (listObject != inObject) {
		if (editingPanel) {
			[editingPanel cancel:nil];
			editingPanel = nil;
		}

		//Configure for the list object, using the highest-up metacontact if necessary
		listObject = ([inObject isKindOfClass:[AIListContact class]] ?
					  [(AIListContact *)inObject parentContact] :
					  inObject);

		targetEventID = inTargetEventID;
		
		//
		[self preferencesChangedForGroup:nil key:nil object:nil preferenceDict:nil firstTime:NO];
	}
}

//Alerts have changed
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	if (firstTime || (!object || object == listObject)) {
		//Update our list of alerts
		[self reloadSummaryData];
	}
}

//Alert Editing --------------------------------------------------------------------------------------------------------
#pragma mark Actions
- (IBAction)addOrRemoveAlert:(id)sender
{
	NSInteger selectedSegment = [sender selectedSegment];
	
	switch (selectedSegment){
		case 0:
			[self addAlert];
			break;
		case 1:
			[self deleteAlert];
			break;
	}
}

//Add new alert
- (void)addAlert
{
	NSString	*defaultEventID;
	id			item = [outlineView_summary itemAtRow:[outlineView_summary selectedRow]];

	if ([contactAlertsActions containsObjectIdenticalTo:item]) {
		defaultEventID = [contactAlertsEvents objectAtIndex:[contactAlertsActions indexOfObjectIdenticalTo:item]];
		
	} else {
		defaultEventID = [item objectForKey:KEY_EVENT_ID];
	}
	
	editingPanel = [CSNewContactAlertWindowController editAlert:nil
												  forListObject:listObject
													   onWindow:[view window]
												notifyingTarget:self
											 configureForGlobal:configureForGlobal
												 defaultEventID:defaultEventID];
}

//Edit existing alert
- (IBAction)editAlert:(id)sender
{
	NSInteger	selectedRow = [outlineView_summary selectedRow];
	if (selectedRow >= 0 && selectedRow < [outlineView_summary numberOfRows]) {
		NSDictionary	*alert = [outlineView_summary itemAtRow:selectedRow];
		
		editingPanel = [CSNewContactAlertWindowController editAlert:alert
													 forListObject:listObject
														  onWindow:[view window]
												   notifyingTarget:self
												configureForGlobal:configureForGlobal
													defaultEventID:nil];
	}
}

//Delete an alert
- (void)deleteAlert
{
	NSInteger selectedRow = [outlineView_summary selectedRow];
	if (selectedRow != -1) {
		id	item = [outlineView_summary itemAtRow:selectedRow];

		if ([contactAlertsActions containsObjectIdenticalTo:item]) {
			/* Deleting an entire event */
			
			NSArray			*contactEvents = (NSArray *)item;
			NSUInteger	contactEventsCount = [contactEvents count];
			
			if (contactEventsCount > 1) {
				//Warn before deleting more than one event simultaneously
				NSAlert *alert = [[NSAlert alloc] init];
				[alert setMessageText:AILocalizedString(@"Delete Event?", nil)];
				[alert setInformativeText:[NSString stringWithFormat:
										   AILocalizedString(@"Remove the %lu actions associated with this event?", nil), (unsigned long)contactEventsCount]];
				[alert addButtonWithTitle:AILocalizedString(@"OK", nil)];		//NSAlertFirstButtonReturn, was the default button
				[alert addButtonWithTitle:AILocalizedString(@"Cancel", nil)];
				/* The former didEndSelector's contextInfo (contactEvents) is captured and
				 * retained by the completion block. */
				[alert beginSheetModalForWindow:[view window] completionHandler:^(NSModalResponse returnCode) {
					if (returnCode == NSAlertFirstButtonReturn) {
						[self deleteContactActionsInArray:contactEvents];
					}
				}];
			} else {
				//Delete a single event immediately
				[self deleteContactActionsInArray:contactEvents];
			}

		} else {
			/* Deleting a single action */
			[adium.contactAlertsController removeAlert:item
										  fromListObject:listObject];

			if (delegate) {
				[delegate contactAlertsViewController:self
										 deletedAlert:item];
			}
			
			//The deletion changed our selection
			[self outlineViewSelectionDidChange:[NSNotification notificationWithName:@"SelectionChanged" object:nil]];
		}

	} else {
		NSBeep();
	}
}

/*!
 * @brief Warning sheet for deleting multiple events ended
 *
 * If the user pressed OK, go ahead with deleting the events.
 */

//Callback from 'new alert' panel.  (Add the alert, or update existing alert)
- (void)alertUpdated:(NSDictionary *)newAlert oldAlert:(NSDictionary *)oldAlert
{
	if (newAlert) {
		//If this was an edit, remove the old alert first
		if (oldAlert) {
			[adium.contactAlertsController removeAlert:oldAlert fromListObject:listObject];
		}

		//Add the new alert
    	[adium.contactAlertsController addAlert:newAlert toListObject:listObject setAsNewDefaults:YES];

		if (delegate) {
			[delegate contactAlertsViewController:self
									 updatedAlert:newAlert
										 oldAlert:oldAlert];
		}

		//Update all heights, since there's been a change
		[self calculateAllHeights];
	}

	editingPanel = nil;
}

#pragma mark Outline view
/*!
 * @brief Configure the event summary outline view
 */
- (void)configureEventSummaryOutlineView
{
	[outlineView_summary setUsesAlternatingRowBackgroundColors:YES];
	[outlineView_summary setIntercellSpacing:NSMakeSize(6.0f,6.0f)];
	[outlineView_summary setIndentationPerLevel:0];
	[outlineView_summary setTarget:self];
	[outlineView_summary setDelegate:self];
	[outlineView_summary setDataSource:self];
	[outlineView_summary setDoubleAction:@selector(didDoubleClick:)];
}

//A sort which groups actions together.
NSComparisonResult actionSort(id objectA, id objectB, void *context)
{
	return [(NSString *)[objectA objectForKey:KEY_ACTION_ID] compare:(NSString *)[objectB objectForKey:KEY_ACTION_ID]];
}

/*!
 * @brief The width the row's text has, near enough, without asking the outline for a row that may not exist yet
 */
- (CGFloat)widthForRows
{
	NSTableColumn *column = [[outlineView_summary tableColumns] objectAtIndex:0];

	return MAX(1.0f, [column width] - MEASURING_ALLOWANCE);
}

- (void)calculateHeightForItem:(id)item
{
	BOOL		enforceMinimumHeight = ([(NSArray *)item count] > 0);
	CGFloat		rowWidth = [self widthForRows];
	CGFloat		textX = CELL_INSET + ICON_SLOT_WIDTH + TEXT_GAP;
	CGFloat		textWidth = MAX(1.0f, rowWidth - textX - CELL_INSET);
	NSString	*summaryText = [self textOrImageForItem:item column:@"action"];
	CGFloat		necessaryHeight;

	//Measured the way the row lays the text out: the name, and under it what happens
	NSAttributedString *title = [[NSAttributedString alloc] initWithString:[self textOrImageForItem:item column:@"event"]
																attributes:[NSDictionary dictionaryWithObject:[self titleFontForItem:item]
																									   forKey:NSFontAttributeName]];
	necessaryHeight = [title heightWithWidth:textWidth];

	if ([summaryText length]) {
		NSAttributedString	*summary = [[NSAttributedString alloc] initWithString:summaryText
																	  attributes:[NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]
																											 forKey:NSFontAttributeName]];

		necessaryHeight += LINE_GAP + [summary heightWithWidth:textWidth];
	}

	//The picture wants its room as well
	if (necessaryHeight < MINIMUM_IMAGE_HEIGHT) necessaryHeight = MINIMUM_IMAGE_HEIGHT;

	necessaryHeight += VERTICAL_ROW_PADDING;

	[requiredHeightDict setObject:[NSNumber numberWithDouble:(enforceMinimumHeight ? 
															 ((necessaryHeight > MINIMUM_ROW_HEIGHT) ? necessaryHeight : MINIMUM_ROW_HEIGHT) :
															 necessaryHeight)]
						   forKey:[NSValue valueWithPointer:(__bridge const void *)item]];	
}

- (void)calculateAllHeights
{
	requiredHeightDict = [[NSMutableDictionary alloc] init];

	id item;
	for (item in contactAlertsActions) {
		[self calculateHeightForItem:item];
	}
}

/*!
 * @brief Reload the information for our summary table, then update it
 */
- (void)reloadSummaryData
{
	//Get two parallel arrays for event IDs and the array of actions for that event ID
	NSDictionary	*contactAlertsDict;
	NSEnumerator	*enumerator;
	NSString		*eventID;
	NSString		*selectedEventID = nil;
	
	NSInteger		row = [outlineView_summary selectedRow];
	
	if (row != -1) {
		id item = [outlineView_summary itemAtRow:row];

		if ([contactAlertsActions containsObjectIdenticalTo:item]) {
			selectedEventID = [contactAlertsEvents objectAtIndex:[contactAlertsActions indexOfObjectIdenticalTo:item]];

		} else {
			selectedEventID = [item objectForKey:KEY_EVENT_ID];
		}
	}

	contactAlertsDict = [adium.preferenceController preferenceForKey:KEY_CONTACT_ALERTS
																 group:PREF_GROUP_CONTACT_ALERTS
											 objectIgnoringInheritance:listObject];
	contactAlertsEvents = [[NSMutableArray alloc] init];
	contactAlertsActions = [[NSMutableArray alloc] init];
	
	enumerator = [[adium.contactAlertsController sortedArrayOfEventIDsFromArray:[contactAlertsDict allKeys]] objectEnumerator];
	
	while ((eventID = [enumerator nextObject])) {
		[contactAlertsEvents addObject:eventID];
		[contactAlertsActions addObject:[[contactAlertsDict objectForKey:eventID] sortedArrayUsingFunction:actionSort
																								   context:NULL]];
	}

	//Now add events which have no actions at present
	NSArray *sourceEventArray = (listObject ? [adium.contactAlertsController nonGlobalEventIDs] : [adium.contactAlertsController allEventIDs]);
	enumerator = [[adium.contactAlertsController sortedArrayOfEventIDsFromArray:sourceEventArray] objectEnumerator];
	while ((eventID = [enumerator nextObject])) {
		if (![contactAlertsEvents containsObject:eventID]) {
			[contactAlertsEvents addObject:eventID];
			
			//XXX
			//This is explicitly a mutable array because Foundation optimizes all zero-count NSArrays to be the same object, and we need it to be different
			[contactAlertsActions addObject:[NSMutableArray array]];
		}
	}

	[outlineView_summary reloadData];
	[self calculateAllHeights];
	[outlineView_summary noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [outlineView_summary numberOfRows])]];
	
	if (selectedEventID) {
		NSInteger actionsIndex = [contactAlertsEvents indexOfObject:selectedEventID];
		if (actionsIndex != NSNotFound) {			
			NSInteger rowToSelect = [outlineView_summary rowForItem:[contactAlertsActions objectAtIndex:actionsIndex]];
			
			[outlineView_summary selectRowIndexes:[NSIndexSet indexSetWithIndex:rowToSelect]
					  byExtendingSelection:NO];
		}
	}
}

/*!
 * @brief A row in the outline view was double clicked
 *
 * If an event was double clicked, expand or collapse the disclosure triangle. If an action was double clicked, edit it.
 */
- (IBAction)didDoubleClick:(id)sender
{
	NSInteger		row = [outlineView_summary selectedRow];
	
	if (row != -1) {
		id item = [outlineView_summary itemAtRow:row];
		
		if ([contactAlertsActions containsObjectIdenticalTo:item]) {
			if ([item count] == 0) {
				[self addAlert];
			} else if ([outlineView_summary isItemExpanded:item]) {
				[outlineView_summary collapseItem:item];
			} else {
				[outlineView_summary expandItem:item];
			}
		} else {
			[self editAlert:nil];
		}
	}
}

- (id)outlineView:(NSOutlineView *)inOutlineView child:(NSInteger)idx ofItem:(id)item
{
	if (item == nil) item = contactAlertsActions;
	
	//Return an event array from whithin contactAlertsActions
	if (idx < [item count]) {
		return [item objectAtIndex:idx];
	} else {
		return nil;
	}
}

- (NSInteger)outlineView:(NSOutlineView *)inOutlineView numberOfChildrenOfItem:(id)item
{
	if (item == nil) {
		return [contactAlertsActions count];
	} else {
		if ([item isKindOfClass:[NSArray class]] && [contactAlertsActions containsObjectIdenticalTo:item]) {
			return [item count];
		} else {
			return 0;
		}
	}
}

/*!
 * @brief Is an item expandable?
 *
 * Events are expandable.  Actions are not.
 */
- (BOOL)outlineView:(NSOutlineView *)inOutlineView isItemExpandable:(id)item
{
	if ([item isKindOfClass:[NSArray class]] && [contactAlertsActions containsObjectIdenticalTo:item]) {
		return [item count] > 0;
	} else {
		return NO;
	}
}

/*!
 * @brief An item's expanded state was set
 *
 * Cache this so we can use it in outlineView:expandStateOfItem:
 *
 * We cache by the associated Event ID so we can expand/contract the same perceived item, which is actually a different
 * NSArray instance, after a reload.
 */
- (void)outlineView:(NSOutlineView *)outlineView setExpandState:(BOOL)state ofItem:(id)item
{
	[expandStateDict setObject:[NSNumber numberWithBool:state]
						forKey:[contactAlertsEvents objectAtIndex:[contactAlertsActions indexOfObjectIdenticalTo:item]]];

}

/*!
 * @brief Should an item be expanded?
 *
 * Used when reloading to determine if items should be expanded or not.
 *
 * We cache by the associated Event ID so we can expand/contract the same perceived item, which is actually a different
 * NSArray instance, after a reload.
 */
- (BOOL)outlineView:(NSOutlineView *)inOutlineView expandStateOfItem:(id)item
{
	NSNumber	*expandState = [expandStateDict objectForKey:[contactAlertsEvents objectAtIndex:[contactAlertsActions indexOfObjectIdenticalTo:item]]];
	return expandState ? [expandState boolValue] : NO;
}

/*!
 * @brief What a column of the old three said about an item: the event, the action, or the image
 *
 * The three columns are one now, but this is still the way the row's words are made.
 */
- (id)textOrImageForItem:(id)item column:(NSString *)identifier
{

	if ([contactAlertsActions containsObjectIdenticalTo:item]) {
		/* item is an array of contact events */
		NSArray	*contactEvents = (NSArray *)item;
		
		if ([identifier isEqualToString:@"event"]) {
			NSString	*eventID;
			
			eventID = [contactAlertsEvents objectAtIndex:[contactAlertsActions indexOfObjectIdenticalTo:contactEvents]];

			return [adium.contactAlertsController globalShortDescriptionForEventID:eventID];
			
		} else if ([identifier isEqualToString:@"action"]) {
			NSMutableString	*actionDescription = [NSMutableString string];
			NSDictionary		*eventDict;
			BOOL						appended = NO;
			NSUInteger			i, count;
			
			count = [contactEvents count];
			for (i = 0; i < count; i++) {
				NSString				*actionID;
				id <AIActionHandler>	actionHandler;
				
				eventDict = [contactEvents objectAtIndex:i];
				actionID = [eventDict objectForKey:KEY_ACTION_ID];
				actionHandler = [[adium.contactAlertsController actionHandlers] objectForKey:actionID];
				
				if (actionHandler) {
					NSString	*thisDescription;
					
					thisDescription = [actionHandler longDescriptionForActionID:actionID
																	withDetails:[eventDict objectForKey:KEY_ACTION_DETAILS]];
					if (thisDescription && [thisDescription length]) {
						if (appended) {
							/* We are on the second or later action. */
							NSString	*conjunctionIfNeeded;
							NSString	*commaAndSpaceIfNeeded;

							//If we have more than 2 actions, we'll be combining them with commas
							if ((count > 2) && (i != (count - 1))) {
								commaAndSpaceIfNeeded = AILocalizedString(@",", "comma between actions in the events list");
							} else {
								commaAndSpaceIfNeeded = @"";
							}
							
							//If we are on the last action, we'll want to add a conjunction to finish the compound sentence
							if (i == (count - 1)) {
								conjunctionIfNeeded = AILocalizedString(@" and", "conjunction to end a compound sentence");
							} else {
								conjunctionIfNeeded = @"";
							}
							
							/* There used to be a spelling exception here: a description beginning with the
							 * proper noun "Growl" kept its capital letter. No action handler says that
							 * any more - the notification action describes itself as "Display a
							 * notification" - so the exception could never be taken and only pointed at
							 * something that no longer exists. Should an action ever start with a proper
							 * noun again, it needs its own answer; a test on the localized description was
							 * never a reliable one, since it only ever held in English. */
							[actionDescription appendString:[NSString stringWithFormat:@"%@%@ %@%@",
								commaAndSpaceIfNeeded,
								conjunctionIfNeeded,
								[[thisDescription substringToIndex:1] lowercaseString],
								[thisDescription substringFromIndex:1]]];

						} else {
							/* We are on the first action.
							 *
							 * This is easy; just append the description.
							 */
							[actionDescription appendString:thisDescription];
							appended = YES;
						}
						
						if (i == (count - 1)) {
							[actionDescription appendString:AILocalizedString(@".", "period at the end of the Events pane sentence describing actions taken for an event")];
						}
					}
				}
			}
			
			return actionDescription;
			
		} else if ([identifier isEqualToString:@"image"]) {
			NSString	*eventID;
			
			eventID = [contactAlertsEvents objectAtIndex:[contactAlertsActions indexOfObjectIdenticalTo:contactEvents]];
			
			return [adium.contactAlertsController imageForEventID:eventID];
		}
	} else {
		/* item is an individual event */
		if ([identifier isEqualToString:@"event"]) {
			NSDictionary			*alert = (NSDictionary *)item;
			NSString				*actionID = [alert objectForKey:KEY_ACTION_ID];
			id <AIActionHandler>	actionHandler = [[adium.contactAlertsController actionHandlers] objectForKey:actionID];

			return [actionHandler longDescriptionForActionID:actionID
												 withDetails:[alert objectForKey:KEY_ACTION_DETAILS]];
		} else if ([identifier isEqualToString:@"action"]) {
			return @"";

		} else if ([identifier isEqualToString:@"image"]) {
			return nil;
		}
	}

	return @"";
}

//Each row should be tall enough to fit its event and action descriptions as necessary
- (CGFloat)outlineView:(NSOutlineView *)inOutlineView heightOfRowByItem:(id)item
{	
	NSNumber *cachedHeight = [requiredHeightDict objectForKey:[NSValue valueWithPointer:(__bridge const void *)item]];

	if (!cachedHeight) {
		//An action under an event is measured when it is first shown, an event when the list is loaded
		[self calculateHeightForItem:item];
		cachedHeight = [requiredHeightDict objectForKey:[NSValue valueWithPointer:(__bridge const void *)item]];
	}

	return (cachedHeight ? [cachedHeight floatValue] : MINIMUM_ROW_HEIGHT);
}

/*!
 * @brief Bold for an event, bolder still when it has actions; plain for an action under it
 */
- (NSFont *)titleFontForItem:(id)item
{
	if ([contactAlertsActions containsObjectIdenticalTo:item])
		return [NSFont boldSystemFontOfSize:([(NSArray *)item count] ? 12 : 11)];

	return [NSFont systemFontOfSize:11];
}

- (NSView *)outlineView:(NSOutlineView *)inOutlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	AIContactAlertCellView	*view = [inOutlineView makeViewWithIdentifier:@"alert" owner:nil];
	BOOL					isEvent = [contactAlertsActions containsObjectIdenticalTo:item];
	NSImage					*image;

	if (!view) {
		view = [[AIContactAlertCellView alloc] initWithFrame:NSZeroRect];
		[view setIdentifier:@"alert"];
	}

	if (isEvent) {
		image = [self textOrImageForItem:item column:@"image"];
	} else {
		NSDictionary			*alert = (NSDictionary *)item;
		NSString				*actionID = [alert objectForKey:KEY_ACTION_ID];
		id <AIActionHandler>	actionHandler = [[adium.contactAlertsController actionHandlers] objectForKey:actionID];

		image = [actionHandler imageForActionID:actionID];
	}

	[view setImage:image
			  size:(isEvent ? MINIMUM_IMAGE_HEIGHT : MINIMUM_ROW_HEIGHT)
			 title:[self textOrImageForItem:item column:@"event"]
			  font:[self titleFontForItem:item]
		   summary:[self textOrImageForItem:item column:@"action"]];

	return view;
}

/*!
 * @brief Outline view selection changed
 *
 * Update the enabled state of our buttons as appropriate.
 * Also, give action handlers a chance to preview.
 */
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	NSOutlineView	*outlineView = [notification object];
	if (!outlineView || (outlineView == outlineView_summary)) {
		//Enable/disable our configure button
		NSInteger row = [outlineView_summary selectedRow];
		
		if (row != -1) {
			[button_addOrRemoveAlert setEnabled:YES forSegment:0];
			
			id item = [outlineView_summary itemAtRow:row];
			if ([contactAlertsActions containsObjectIdenticalTo:item]) {
				[button_edit setEnabled:NO];
				[button_addOrRemoveAlert setEnabled:([(NSArray *)item count] > 0) forSegment:1];
				
			} else {
				[button_edit setEnabled:YES];
				[button_addOrRemoveAlert setEnabled:YES forSegment:1];
				
				//Preview if possible
				NSDictionary			*eventDict = (NSDictionary *)item;
				NSString				*actionID;
				id <AIActionHandler>	actionHandler;
				
				actionID = [eventDict objectForKey:KEY_ACTION_ID];
				
				actionHandler = [[adium.contactAlertsController actionHandlers] objectForKey:actionID];
				
				if (actionHandler && [actionHandler respondsToSelector:@selector(performPreviewForAlert:)]) {
					[(id)actionHandler performPreviewForAlert:eventDict];
				}				
			}
		} else {
			[button_addOrRemoveAlert setEnabled:NO forSegment:0];
			[button_addOrRemoveAlert setEnabled:NO forSegment:1];
			[button_edit setEnabled:NO];
		
		}
	}
}

- (void)deleteContactActionsInArray:(NSArray *)contactEventArray
{
	NSDictionary	*eventDict;

	[adium.preferenceController delayPreferenceChangedNotifications:YES];
	for (eventDict in [contactEventArray copy]) {
		[adium.contactAlertsController removeAlert:eventDict fromListObject:listObject];
	}
	[adium.preferenceController delayPreferenceChangedNotifications:NO];

	if (delegate) {
		[delegate contactAlertsViewController:self
								 deletedAlert:nil];
	}

	//The deletion may have changed our selection
	[self outlineViewSelectionDidChange:[NSNotification notificationWithName:@"SelectionChanged" object:nil]];
}

- (void)outlineViewDeleteSelectedRows:(NSOutlineView *)inOutlineView
{
	[self deleteAlert];
}

#pragma mark Global configuration
- (void)setConfigureForGlobal:(BOOL)inConfigureForGlobal
{
	configureForGlobal = inConfigureForGlobal;
}

- (void)setShowEventsInEditSheet:(BOOL)inShowEventsInEditSheet
{
	showEventsInEditSheet = inShowEventsInEditSheet;
}

@end
