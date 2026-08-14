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

#import "AIImageButton.h"
#import "AIFloater.h"
#import "AIImageDrawingAdditions.h"

/* The largest the held down picture is shown at. The floater is built at the size of the picture it
 * is given, and a picture is whatever size its owner uploaded: the newer services hand over several
 * hundred points square, which covers a good part of the screen for as long as the mouse is held. */
#define FLOATER_MAXIMUM_SIDE 350.0f

@interface AIImageButton (PRIVATE)
- (void)destroyImageFloater;
- (NSImage *)imageForFloater;
@end

@implementation AIImageButton

@synthesize cornerRadius;

- (id)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		imageFloater = nil;
	}

	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	AIImageButton *newButton = [super copyWithZone:zone];
	newButton->imageFloater = [imageFloater retain];
	[newButton setCornerRadius:[self cornerRadius]];

	return newButton;
}

- (void)dealloc
{
	[imageFloater close:nil];
	[imageFloater release];

	[super dealloc];
}

#pragma mark Drawing

- (void)drawRect:(NSRect)rect
{
	// Rounded corners
	if (cornerRadius > 0.0f) {
		[[NSBezierPath bezierPathWithRoundedRect:[self bounds] xRadius:[self cornerRadius] yRadius:[self cornerRadius]] addClip];
	}
	
	[super drawRect:rect];
}

//Mouse Tracking -------------------------------------------------------------------------------------------------------
#pragma mark Mouse Tracking
//Custom mouse down tracking to display our image and highlight
- (void)mouseDown:(NSEvent *)theEvent
{
	if ([self isEnabled]) {
		NSWindow	*window = [self window];
		NSImage		*floaterImage = [self imageForFloater];
		CGFloat		maxXOrigin;

		[self highlight:YES];

		//Find our display point, the bottom-left of our button, in screen coordinates
		NSPoint point = [window convertPointToScreen:[self convertPoint:[self bounds].origin toView:nil]];
		point.y -= NSHeight([self frame]) + 2;
		point.x -= 1;

		//Move the display point down by the height of our image
		point.y -= [floaterImage size].height;

		if (imageFloater) {
			[imageFloater close:nil];
			[imageFloater release];
		}

		// Rounded corners
		if ([self cornerRadius] > 0.0f) {
			NSImage *roundedImage = [[NSImage alloc] initWithSize:[floaterImage size]];
			NSRect imageFrame = NSMakeRect(0.0f, 0.0f, [floaterImage size].width, [floaterImage size].height);

			[roundedImage lockFocus];

			[[NSBezierPath bezierPathWithRoundedRect:imageFrame
											 xRadius:[self cornerRadius]
											 yRadius:[self cornerRadius]] addClip];

			[floaterImage drawInRect:imageFrame fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0f];

			[roundedImage unlockFocus];

			[self setImage:roundedImage];
			floaterImage = [[roundedImage retain] autorelease];
			[roundedImage release];
		}

		/* If the image would go off the right side of the screen from its origin, shift the origin left
		 * so it won't.
		 */
		maxXOrigin = NSMaxX([[window screen] frame]) - [floaterImage size].width;
		if (point.x  > maxXOrigin) {
			point.x = maxXOrigin;
		}

		imageFloater = [[AIFloater newFloaterWithImage:floaterImage styleMask:NSWindowStyleMaskBorderless] retain];
		[imageFloater setMaxOpacity:1.0f];
		[imageFloater moveFloaterToPoint:point];
		[imageFloater setVisible:YES animate:NO];
		
		imageFloaterShouldBeOpen = TRUE;
	}
}

//Remove highlight and image on mouse up
- (void)mouseUp:(NSEvent *)theEvent
{
	[self highlight:NO];

	if (imageFloater) {
		[imageFloater setVisible:NO animate:YES];
		imageFloaterShouldBeOpen = FALSE;

		//Let it stay around briefly before closing so the animation fades it out
		[self performSelector:@selector(destroyImageFloater)
				   withObject:nil
				   afterDelay:0.5];
	}

	[super mouseUp:theEvent];
}

/*!
 * @brief The picture to hold up, at a size somebody can look at
 *
 * Only ever smaller: a picture already within the limit is handed back untouched, and one below it
 * is not blown up to reach it.
 */
- (NSImage *)imageForFloater
{
	NSSize size = [bigImage size];

	if (size.width <= FLOATER_MAXIMUM_SIDE && size.height <= FLOATER_MAXIMUM_SIDE)
		return bigImage;

	CGFloat scale = FLOATER_MAXIMUM_SIDE / MAX(size.width, size.height);
	NSSize scaled = NSMakeSize(round(size.width * scale), round(size.height * scale));

	if (scaled.width < 1.0f || scaled.height < 1.0f)
		return bigImage;

	return [bigImage imageByScalingToSize:scaled];
}

- (void)destroyImageFloater
{
	if (!imageFloaterShouldBeOpen) {
		[imageFloater close:nil];
		[imageFloater release]; imageFloater = nil;
	}
}

#pragma mark Accessibility

- (id)accessibilityAttributeValue:(NSString *)attribute
{
	if([attribute isEqualToString:NSAccessibilityRoleAttribute]) {
		return @"AIImageButton";
	} else {
		return [super accessibilityAttributeValue:attribute];
	}
}

@end
