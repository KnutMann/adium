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

#import <Adium/AIImageTextCellView.h>
#import <AIUtilities/AIImageTextCell.h>

@interface AIImageTextCellView ()
- (void)_initImageTextView;
@end

@implementation AIImageTextCellView

-(id)initWithFrame:(NSRect)inFrame
{
	if ((self = [super initWithFrame:inFrame])) {
		[self _initImageTextView];
	}
	
	return self;
}

- (id)initWithCoder:(NSCoder *)encoder
{
	if ((self = [super initWithCoder:encoder])) {
		[self _initImageTextView];		
	}
	
	return self;
}

- (void)_initImageTextView
{
	cell = [[AIImageTextCell alloc] init];
    [cell setFont:[NSFont systemFontOfSize:12]];
}

- (void)dealloc
{
	[cell release]; cell = nil;
	[super dealloc];
}

//NSCell expects to draw into a flipped view
- (BOOL)isFlipped
{
	return YES;
}

//Drawing
- (void)drawRect:(NSRect)inRect
{
	/* Lay the cell out in our bounds, never in the dirty rect: since macOS 14
	 * views no longer clip to their bounds by default, and the dirty rect can
	 * exceed them, using inRect painted the content far outside this view. */
	NSRect	layoutRect = [self bounds];
	NSSize	cellSize = [cell cellSizeForBounds:layoutRect];

	if (cellSize.width < layoutRect.size.width) {
		CGFloat difference = (layoutRect.size.width - cellSize.width)/2.0f;
		layoutRect.size.width -= difference;
		layoutRect.origin.x += difference;
	}

	if (cellSize.height < layoutRect.size.height) {
		CGFloat difference = (layoutRect.size.height - cellSize.height)/2.0f;
		layoutRect.size.height -= difference;
		layoutRect.origin.y += difference;
	}

	[cell drawInteriorWithFrame:layoutRect inView:self];
}

//Cell setting methods
- (void)setStringValue:(NSString *)inString
{
	[cell setStringValue:inString];
	[self setNeedsDisplay:YES];
}

- (void)setImage:(NSImage *)inImage
{
	[cell setImage:inImage];
	[self setNeedsDisplay:YES];
}

- (void)setSubString:(NSString *)inSubString
{
	[cell setSubString:inSubString];
	[self setNeedsDisplay:YES];
}

@end
