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
#import <AIUtilities/AIEventAdditions.h>

#define FORCED_MINIMUM_HEIGHT 20

@implementation AIBorderlessListOutlineView

/*!
 * @brief Split mouse gestures between the list and the borderless window
 *
 * The window has no title bar, so dragging its empty background is the only way to move it.
 * A gesture that starts on a row, however, belongs to the list: selection, expanding groups,
 * double-click actions, and dragging contacts or bookmarks between groups. Deciding by the
 * hit row at mouse down (and remembering that decision for the rest of the gesture) keeps
 * both behaviors available at once.
 */
- (void)mouseDown:(NSEvent *)theEvent
{
	NSPoint viewPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];

	if (([self rowAtPoint:viewPoint] != -1) || [theEvent cmdKey]) {
		gestureMovesWindow = NO;
        [super mouseDown:theEvent];

	} else {
		gestureMovesWindow = YES;

		//Wait for the next event to tell a plain click (handled by the list) from a window drag
		NSEvent *nextEvent = [[self window] nextEventMatchingMask:(NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged | NSEventMaskPeriodic)
														untilDate:[NSDate distantFuture]
														   inMode:NSEventTrackingRunLoopMode
														  dequeue:NO];

		//Pass along the event (either to ourself or our window, depending on what it is)
		switch ([nextEvent type]) {
			case NSEventTypeLeftMouseUp:
				[super mouseDown:theEvent];
				[super mouseUp:nextEvent];
				break;
			case NSEventTypeLeftMouseDragged:
				[[self window] mouseDown:theEvent];
				[[self window] mouseDragged:nextEvent];
				break;
			default:
				[[self window] mouseDown:theEvent];
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
