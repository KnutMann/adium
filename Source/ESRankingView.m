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

#import "ESRankingView.h"
#import <AIUtilities/AIColorAdditions.h>

@implementation ESRankingView

- (void)setPercentage:(CGFloat)inPercentage
{
	if (percentage != inPercentage) {
		percentage = inPercentage;
		[self setNeedsDisplay:YES];
	}
}

- (void)drawRect:(NSRect)rect
{
	if (percentage == 0)
		return;

	NSRect bar = [self bounds];

	//2 points left, 4 points right
	bar.size.width -= 6;
	bar.origin.x += 2;

	//3 points top, 3 points bottom
	bar.size.height -= 6;
	bar.origin.y += 3;

	//A horizontal share of the row equal to the rank
	bar.size.width *= percentage;

	//Asked for on every draw rather than kept: the accent colour can change while the window is open
	[[[NSColor selectedContentBackgroundColor] darkenAndAdjustSaturationBy:0.2f] set];
	[[NSBezierPath bezierPathWithRect:bar] fill];
}

@end
