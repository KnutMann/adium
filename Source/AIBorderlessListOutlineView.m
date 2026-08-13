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

#import "AIBorderlessListOutlineView.h"
#import <Adium/AIListGroup.h>
#import <AIUtilities/AIEventAdditions.h>
#import <AIUtilities/AIMultiCellOutlineView.h>

#define FORCED_MINIMUM_HEIGHT 20

/* AIMultiCellOutlineView keeps this hook to its own implementation file, but it is the one place
 * where a disclosure triangle claims a gesture before anyone else sees it, so a view that hands
 * gestures to its window has to be able to speak about it - including to super, which is why the
 * declaration belongs on the class that implements it rather than on ours.
 */
@interface AIMultiCellOutlineView (AIBorderlessListOutlineViewInheritedPrivate)
- (BOOL)handleExpandedStateToggleForEvent:(NSEvent *)theEvent needsExpandCollapseSuppression:(BOOL *)needsExpandCollapseSuppression;
@end

@implementation AIBorderlessListOutlineView

/*!
 * @brief Split mouse gestures between the list and the borderless window
 *
 * The window has no title bar, so it can only be dragged where the list does not want the gesture
 * for itself. Empty background is such a place, but a full contact list leaves hardly any, which is
 * what made the window so hard to move. Group headers are the other one: they are always present and
 * they are wide, so they serve as the handle.
 *
 * Both meanings begin with the same mouse down, so we look at the next event before deciding. The
 * peek does not dequeue, and that is what lets a click be passed on untouched: we simply call
 * through to super, and AIListOutlineView peeks at the very same event and expands, collapses and
 * selects exactly as it did before.
 *
 * The whole width of a group row behaves alike, disclosure triangle included: a gesture that begins
 * there means the same thing as one that begins on the group's name, and splitting the row into two
 * zones only made it unpredictable to use.
 *
 * Command keeps any gesture with the list, as it already did here, and that is how a group is
 * reordered now - dragging one plainly moves the window instead. Reordering is real: every sort
 * controller honours a manual group order unless the user asked for groups to be sorted
 * alphabetically, and no controller can be asked which of the two is in force (canSortManually
 * speaks about contacts, not groups), so we do not guess. What makes command unambiguous here is
 * that a selection can never hold a group together with anything else - see AIAbstractListController.
 *
 * Contacts, bookmarks and metacontacts are untouched: dragging them between groups is their gesture.
 */
- (void)mouseDown:(NSEvent *)theEvent
{
	NSPoint		viewPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	NSInteger	row = [self rowAtPoint:viewPoint];

	/* Only true group headers. AIListBookmark and AIMetaContact are contacts rather than groups, so
	 * they are excluded by the class test; the item standing in the row is an AIProxyListObject,
	 * which answers isKindOfClass: for the object it represents.
	 */
	BOOL rowIsWindowHandle = ((row != -1) && [[self itemAtRow:row] isKindOfClass:[AIListGroup class]]);

	if (((row != -1) && !rowIsWindowHandle) || [theEvent cmdKey]) {
		gestureMovesWindow = NO;
        [super mouseDown:theEvent];

	} else {
		//Wait for the next event to tell a plain click (handled by the list) from a window drag
		NSEvent *nextEvent = [[self window] nextEventMatchingMask:(NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged | NSEventMaskPeriodic)
														untilDate:[NSDate distantFuture]
														   inMode:NSEventTrackingRunLoopMode
														  dequeue:NO];

		//Pass along the event (either to ourself or our window, depending on what it is)
		switch ([nextEvent type]) {
			case NSEventTypeLeftMouseUp:
				gestureMovesWindow = NO;
				[super mouseDown:theEvent];
				/* A group header takes the mouse up out of the queue we left it in, on its own
				 * peek. Empty background has no row to hand it to, so it has to be told.
				 */
				if (!rowIsWindowHandle)
					[super mouseUp:nextEvent];
				break;
			case NSEventTypeLeftMouseDragged:
				gestureMovesWindow = YES;
				[[self window] mouseDown:theEvent];
				[[self window] mouseDragged:nextEvent];
				break;
			default:
				if (rowIsWindowHandle) {
					gestureMovesWindow = NO;
					[super mouseDown:theEvent];
				} else {
					gestureMovesWindow = YES;
					[[self window] mouseDown:theEvent];
				}
				break;
		}
	}
}
- (void)mouseDragged:(NSEvent *)theEvent
{
    if (gestureMovesWindow) {
        [[self window] mouseDragged:theEvent];
	} else {
		[super mouseDragged:theEvent];
	}
}

- (void)mouseUp:(NSEvent *)theEvent
{
    if (gestureMovesWindow) {
		gestureMovesWindow = NO;
        [[self window] mouseUp:theEvent];
	} else {
		[super mouseUp:theEvent];
	}
}

/*!
 * @brief Keep a group's disclosure triangle from swallowing a command-drag
 *
 * The triangle toggles its group the instant the mouse goes down, which is what a click wants but
 * never what a drag wants: with command held the gesture means "reorder this group", and a group
 * that collapses under the pointer cannot be dragged anywhere. Everywhere else on the row the
 * command-drag already reaches NSOutlineView untouched; this lets the triangle do the same.
 * Contacts keep the toggle in every case - only groups are draggable this way.
 */
- (BOOL)handleExpandedStateToggleForEvent:(NSEvent *)theEvent needsExpandCollapseSuppression:(BOOL *)needsExpandCollapseSuppression
{
	if ([theEvent cmdKey]) {
		NSPoint		viewPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
		NSInteger	row = [self rowAtPoint:viewPoint];

		if ((row != -1) && [[self itemAtRow:row] isKindOfClass:[AIListGroup class]]) {
			*needsExpandCollapseSuppression = NO;
			return NO;
		}
	}

	return [super handleExpandedStateToggleForEvent:theEvent needsExpandCollapseSuppression:needsExpandCollapseSuppression];
}

- (NSInteger)desiredHeight
{
	NSInteger height = [super desiredHeight];
	return (height > FORCED_MINIMUM_HEIGHT ? height : FORCED_MINIMUM_HEIGHT);
}

- (NSInteger)totalHeight
{
	return [super totalHeight];
}

@end
