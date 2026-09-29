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

#import "AIOutlineView.h"
#import "AIOutlineViewAdditions.h"

@interface AIOutlineView ()
- (void)_initOutlineView;
- (void)expandOrCollapseItemsOfItem:(id)rootItem;
- (void)_reloadData;
@end

@interface AIOutlineView (KFTypeSelectTableViewSupport)
- (void)findPrevious:(id)sender;
- (void)findNext:(id)sender;
@end

@implementation AIOutlineView

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super initWithCoder:aDecoder])) {
		[self _initOutlineView];
	}
	return self;
}

- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		[self _initOutlineView];
	}
	return self;
}

- (void)_initOutlineView
{

}

//Allow our delegate to specify context menus
- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    if ([[self delegate] respondsToSelector:@selector(outlineView:menuForEvent:)]) {
        return [(id<AIOutlineViewDelegate>)[self delegate] outlineView:self menuForEvent:theEvent];
    } else {
        return nil;
    }
}

/*!
 * @brief Should we perform type select next/previous on find?
 *
 * @return YES to switch between type-select results. NO to to switch within the responder chain.
 */
- (BOOL)tabPerformsTypeSelectFind
{
	return NO;
}

//Navigate outline view with the keyboard, send select actions to delegate
- (void)keyDown:(NSEvent *)theEvent
{
	if (!([theEvent modifierFlags] & NSEventModifierFlagCommand)) {

		NSString	*charString = [theEvent charactersIgnoringModifiers];
		unichar		pressedChar = 0;
	
		//Get the pressed character
		if ([charString length] == 1) pressedChar = [charString characterAtIndex:0];

    	if (pressedChar == NSDeleteFunctionKey || pressedChar == NSBackspaceCharacter || pressedChar == NSDeleteCharacter) { //Delete
			if ([[self dataSource] respondsToSelector:@selector(outlineViewDeleteSelectedRows:)]) {
				[(id<AIOutlineViewDelegate>)[self dataSource] outlineViewDeleteSelectedRows:self];
			}

		} else if (pressedChar == NSCarriageReturnCharacter || pressedChar == NSEnterCharacter) { //Enter or return
			//doubleAction is NULL by default
			SEL doubleActionSelector = [self doubleAction];
			if (doubleActionSelector) {
				[[self delegate] performSelector:doubleActionSelector withObject:self];
			}

        } else if (pressedChar == NSLeftArrowFunctionKey) { //left
			NSArray *selectedItems = [self arrayOfSelectedItems];
			
			BOOL anyCollapsable = NO;
			for (id object in selectedItems) {
				if ([self isExpandable:object] && [self isItemExpanded:object]) {
					anyCollapsable = YES;
					[self collapseItem:object];
				}
			}
			
			if (!anyCollapsable && selectedItems.count == 1) {
				id parentObject = [self parentForItem:[selectedItems objectAtIndex:0]];
				
				if (parentObject)
					[self selectItemsInArray:[NSArray arrayWithObject:parentObject]];
			}

        } else if (pressedChar == NSRightArrowFunctionKey) { //right
			NSEnumerator *enumerator = [[self arrayOfSelectedItems] objectEnumerator];
			id object;
			while ((object = [enumerator nextObject])) {
				if ([self isExpandable:object] && ![self isItemExpanded:object]) {
					[self expandItem:object];
				}
			}

		} else if (pressedChar == NSUpArrowFunctionKey) { //up
			[super keyDown:theEvent];
		} else if (pressedChar == NSDownArrowFunctionKey) { //down
			[super keyDown:theEvent];
        } else if ((pressedChar == '\031') && // backtab
				   [self respondsToSelector:@selector(findPrevious:)] &&
				   [self tabPerformsTypeSelectFind]) {
			/* KFTypeSelectTableView supports findPrevious; backtab is added to AIOutlineView as a find previous action
			 * if KFTypeSelectTableView is being used via posing */
			[self findPrevious:self];
			
		} else if ((pressedChar == '\t') &&
				   [self respondsToSelector:@selector(findNext:)] &&
				   [self tabPerformsTypeSelectFind]) {
			/* KFTypeSelectTableView supports findNext; tab is added to AIOutlineView as a find next action
			* if KFTypeSelectTableView is being used via posing */
			[self findNext:self];

		} else if ([[self delegate] respondsToSelector:@selector(outlineView:forwardKeyEventToFindPanel:)] && 
				   !([theEvent modifierFlags] & NSEventModifierFlagCommand) && 
				   !([theEvent modifierFlags] & NSEventModifierFlagControl)) {
			//handle any key we have not alredy handled that is a visable character and likely not to be a shortcut key (no command or control key modifiers) by asking the delegate to add it to the search string
			if (![(id<AIOutlineViewDelegate>)[self delegate] outlineView:self forwardKeyEventToFindPanel:theEvent]) {
				//the delegate's find panel could not handle the event, so we just pass it to super
				[super keyDown:theEvent];
			}
		}
			
		else {
			[super keyDown:theEvent];
		}
	} else {
		[super keyDown:theEvent];
	}
}
- (void)performFindPanelAction:(id)sender;
{
	if ([[self delegate] respondsToSelector:@selector(outlineViewToggleFindPanel:)]) {
		[(id<AIOutlineViewDelegate>)[self delegate] outlineViewToggleFindPanel:self];
	}
}

//Collapse/expand memory -----------------------------------------------------------------------------------------------
#pragma mark Collapse/expand memory
//The notifications NSOutlineViewItemDidExpand/Collapse are posted when the outline view is reloaded, making it 
//impossible to tell when a user expanded/collapsed a group (since there will be tons of false notifications sent
//out when reloading).  As a fix, we implement two new notifications that ONLY get posted when THE USER expands
//or collapses a group.
/* The remembered state is written down first and the view told afterwards, which
 * is the other way round from how this used to read. Opening or closing a group
 * changes how many rows there are, and anything that reloads the list in the
 * middle of that reads the remembered state back out and applies it. Written
 * down last, the state still said "open" at that moment, the group sprang back
 * open, and the click looked as though it had been swallowed. Which is why it
 * sometimes took two on the very same pixel. */
- (void)expandItem:(id)item expandChildren:(BOOL)expandChildren
{
	if (!ignoreExpandCollapse && [[self delegate] respondsToSelector:@selector(outlineView:setExpandState:ofItem:)]) {
		[(id<AIOutlineViewDelegate>)[self delegate] outlineView:self setExpandState:YES ofItem:item];
	}

	[super expandItem:item expandChildren:expandChildren];

	if (!ignoreExpandCollapse) {
		//General expand notification
		[[NSNotificationCenter defaultCenter] postNotificationName:AIOutlineViewUserDidExpandItemNotification
															object:self
														  userInfo:[NSDictionary dictionaryWithObject:item forKey:@"Object"]];
	}
}
- (void)collapseItem:(id)item collapseChildren:(BOOL)collapseChildren
{
	if (!ignoreExpandCollapse && [[self delegate] respondsToSelector:@selector(outlineView:setExpandState:ofItem:)]) {
		[(id<AIOutlineViewDelegate>)[self delegate] outlineView:self setExpandState:NO ofItem:item];
	}

	[super collapseItem:item collapseChildren:collapseChildren];

	if (!ignoreExpandCollapse) {
		//General expand notification
		[[NSNotificationCenter defaultCenter] postNotificationName:AIOutlineViewUserDidCollapseItemNotification
															object:self
														  userInfo:[NSDictionary dictionaryWithObject:item forKey:@"Object"]];
	}
}

//Preserve selection and group expansion through a reload
- (void)reloadData
{
	/* This code is to correct what I consider a bug with NSOutlineView.
	Basically, if reloadData is called from 'outlineView:setObjectValue:forTableColumn:byItem:' while the last
	row is edited in a way that will reduce the # of rows in the table view, things will crash within system code.
	This crash is evident in many versions of Adium.  When renaming the last contact on the contact list to the name
	of a contact who already exists on the list, Adium will delete the original contact, reducing the # of rows in
	the outline view in the midst of the cell editing, causing the crash.  The fix is to delay reloading until editing
	of the last row is complete.  As an added benefit, we skip the delayed reloading if the outline view had been
	reloaded since the edit, and the reload is no longer necessary.
	*/
    if ([self numberOfRows] != 0 && ([self editedRow] == [self numberOfRows] - 1) && !needsReload) {
        needsReload = YES;
        [self performSelector:@selector(_reloadData) withObject:nil afterDelay:0.0001];

    } else {
        needsReload = NO;

		[super reloadData];

		/* Current AppKit rebuilds its rows after reloadData returns, not during
		 * it, so opening a group right here happens against a table that is half
		 * torn down. The rows it makes are placed from the old geometry and are
		 * never moved again: measured in the running program, eight rows left
		 * standing where they had been before an account signed on, while the
		 * table had them two hundred and forty three points further down. That
		 * is the overdrawn list that was reported.
		 *
		 * There used to be a synchronous pass here as well as the one below.
		 * Its own comment already said it was discarded. It was not: it left
		 * those rows behind. Only the deferred pass remains. */
		dispatch_async(dispatch_get_main_queue(), ^{
			[self expandOrCollapseItemsOfItem:nil];
			/* Fire the row-count/height change path so observers (e.g. the
			 * contact list's autosizing window) see the expanded rows. */
			[self noteNumberOfRowsChanged];
		});
	}
}

- (void)expandOrCollapseItemsOfItem:(id)rootItem
{
	//After reloading data, we correctly expand/collapse all groups
	if ([[self delegate] respondsToSelector:@selector(outlineView:expandStateOfItem:)]) {
		id<AIOutlineViewDelegate>   delegate = (id<AIOutlineViewDelegate>)[self delegate];
		NSInteger 	numberOfRows = [delegate outlineView:self numberOfChildrenOfItem:rootItem];
		NSInteger 	row;
		
		//go through all items
		for (row = 0; row < numberOfRows; row++) {
			id item = [delegate outlineView:self child:row ofItem:rootItem];

			//If the item is expandable, correctly expand/collapse it
			if (item && [delegate outlineView:self isItemExpandable:item]) {
				ignoreExpandCollapse = YES;
				if ([delegate outlineView:self expandStateOfItem:item]) {
					[self expandItem:item];
					[self expandOrCollapseItemsOfItem:item];
				} else {
					[self collapseItem:item];
				}
				ignoreExpandCollapse = NO;
			}
		}
	}
}

//Here we skip the delayed reload if another reload has already occured before the delay could fire
- (void)_reloadData{
    if (needsReload) [self reloadData];
}

#pragma mark Dragging
//Draging ------------------------------------------
/* Invoked in the dragging source as the drag ends.
 *
 * This used to be -draggedImage:endedAt:operation:, the end of drag callback of
 * the old image based drag API. Measured against macOS 26: AppKit sends the
 * modern -draggingSession:endedAtPoint:operation: to the drag source, and
 * NSTableView's implementation of that calls the old method on itself for
 * compatibility, handing it a nil image. So the delegate has been receiving nil
 * for its image argument all along, and passing nil here is not a change it can
 * see. The argument stays in the delegate method so that implementations keep
 * compiling; the header says it is always nil.
 *
 * The delegate is told first and super second, exactly as before. The one shift
 * is that whatever NSTableView does inside its own modern method now runs after
 * the delegate has been told rather than before. The only implementer of the
 * delegate method, AIAbstractListController, just posts a notification that
 * lifts the tooltip suppression, so nothing observable depends on that order.
 *
 * No protocol declaration is needed here: NSTableView already declares
 * <NSDraggingSource> and this class inherits that conformance. */
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation
{
	if ([[self delegate] respondsToSelector:@selector(outlineView:draggedImage:endedAt:operation:)]) {
		[(id<AIOutlineViewDelegate>)[self delegate] outlineView:self draggedImage:nil endedAt:screenPoint operation:operation];
	}

	[super draggingSession:session endedAtPoint:screenPoint operation:operation];
}

/* Prevent dragging of items to another application.
 *
 * This used to be the deprecated -draggingSourceOperationMaskForLocal:, which
 * answered "isLocal ? NSDragOperationEvery : NSDragOperationNone". The two
 * questions line up exactly, measured against macOS 26: NSTableView's own
 * -draggingSession:sourceOperationMaskForDraggingContext: is a pass through to
 * the old method, and it passes isLocal YES for NSDraggingContextWithinApplication
 * and isLocal NO for NSDraggingContextOutsideApplication. So the answer below is
 * bit for bit the old one.
 *
 * One rule follows for anything built on this class: a subclass must not go back
 * to -draggingSourceOperationMaskForLocal:. This implementation now shadows
 * NSTableView's pass through, so an old style override in a subclass would never
 * be asked and its answer would be dropped in silence. Measured: a subclass
 * answering NSDragOperationCopy|NSDragOperationMove|NSDragOperationPrivate under
 * a base class on the modern method got NSDragOperationEvery instead.
 * AIListOutlineView, the contact list, answers the modern question for that
 * reason. */
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    return (context == NSDraggingContextWithinApplication ? NSDragOperationEvery : NSDragOperationNone);
}

#pragma mark Accessibility

/* This deliberately stays on the deprecated -accessibilityActionNames. It is what
 * puts AXPress and AXShowMenu in front of a screen reader, and a plain
 * NSOutlineView advertises no actions at all, so the two actions really do come
 * from here.
 *
 * The modern accessibility protocol cannot answer for it, measured against
 * macOS 26: overriding -accessibilityPerformPress and -accessibilityPerformShowMenu,
 * with or without an -isAccessibilitySelectorAllowed: that returns YES for both
 * selectors, leaves the advertised action list empty. No other member of the
 * protocol adds an action to that list, so converting this would take both
 * actions away from VoiceOver. */
- (NSArray *)accessibilityActionNames
{
	NSMutableArray *accessibilityActionNames = [[super accessibilityActionNames] mutableCopy];
	
	//These are both handled by NSOutlineView by default but not included in the accessibilityActionNames by default
	[accessibilityActionNames addObject:NSAccessibilityPressAction];
	[accessibilityActionNames addObject:NSAccessibilityShowMenuAction];
	
	return accessibilityActionNames;
}

@end

