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

#import "SetupAssistantBoxBackgroundView.h"


@implementation SetupAssistantBoxBackgroundView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    return self;
}

- (void)drawRect:(NSRect)rect {
	/* The colour the system uses behind text, rather than the plain white this filled with since
	 * the days when that was the same thing. In dark mode it was a bright white slab, and the
	 * texts drawn on it keep their own colour - so the welcome text, the closing text and the
	 * field labels of the very first launch stood white on white. */
	[[NSColor textBackgroundColor] set];
	NSRectFill(rect);
}

@end

