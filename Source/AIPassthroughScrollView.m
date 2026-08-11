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

#import "AIPassthroughScrollView.h"

@implementation AIPassthroughScrollView

/*!
 * @brief Scroll the pane we sit in, not ourselves
 *
 * The wheel event arrives here because we are the innermost scroll view under the pointer, not
 * because we have anything to scroll: the form gives us the full height of our rows. Walk out to
 * the scroll view holding the pane and let it move instead.
 */
- (void)scrollWheel:(NSEvent *)theEvent
{
	NSView *ancestor = [self superview];

	while (ancestor && ![ancestor isKindOfClass:[NSScrollView class]])
		ancestor = [ancestor superview];

	if (ancestor)
		[ancestor scrollWheel:theEvent];
	else
		[super scrollWheel:theEvent];
}

@end
