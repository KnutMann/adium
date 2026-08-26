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

#import "AISearchFieldCell.h"
#import <AIUtilities/AIBezierPathAdditions.h>

@implementation AISearchFieldCell

/*!
 * @brief NSCell's copy is memberwise
 *
 * The new cell comes back holding our colour in its slot without owning it, and a counted store
 * into that slot would give up a reference nobody took. The cast clears it without releasing;
 * the assignment then retains properly.
 */
- (id)copyWithZone:(NSZone *)zone
{
	AISearchFieldCell *newCell = [super copyWithZone:zone];

	*(__unsafe_unretained id *)(void *)&newCell->backgroundColor = nil;
	newCell->backgroundColor = backgroundColor;

	return newCell;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	if (backgroundColor) {
		[backgroundColor setFill];
		[[NSBezierPath bezierPathWithRoundedRect:cellFrame] fill];
	}

	[super drawInteriorWithFrame:cellFrame inView:controlView];
}

- (void)setTextColor:(NSColor *)inTextColor backgroundColor:(NSColor *)inBackgroundColor
{
	NSSearchField	*searchField = (NSSearchField *)[self controlView];

	[searchField setTextColor:(inTextColor ? inTextColor : [NSColor blackColor])];

	backgroundColor = inBackgroundColor;
}

@end
