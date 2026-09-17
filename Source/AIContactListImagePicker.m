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

#import "AIContactListImagePicker.h"
#import <Adium/AIAccount.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIContactControllerProtocol.h>
#import "AIContactListUserPictureMenuController.h"
#import <AIUtilities/AIBezierPathAdditions.h>

#define ARROW_WIDTH		8
#define ARROW_HEIGHT	(ARROW_WIDTH/2.0)
#define ARROW_XOFFSET	6		//from the right edge; two left the arrow sitting on it
#define ARROW_YOFFSET	3

@interface AIContactListImagePicker ()

- (void)frameDidChange:(NSNotification *)inNotification;

@end

@implementation AIContactListImagePicker

- (void)configureTracking
{
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(frameDidChange:)
												 name:NSViewFrameDidChangeNotification
											   object:self];
	[self setPostsFrameChangedNotifications:YES];
	
	trackingTag = -1;
	[self resetCursorRects];
	
	[self setPresentPictureTakerAsSheet:NO];
}

- (id)initWithFrame:(NSRect)inFrame
{
	if ((self = [super initWithFrame:inFrame])) {
		[self configureTracking];
		imageMenu = nil;
		maxSize = NSMakeSize(256.0f, 256.0f);
		shouldUpdateRecentRepository = YES;
	}
	
	return self;
}

- (void)awakeFromNib
{
	if ([[self superclass] instancesRespondToSelector:@selector(awakeFromNib)]) {
        [super awakeFromNib];
	}

	[self configureTracking];
	
	maxSize = NSMakeSize(256.0f, 256.0f);
	shouldUpdateRecentRepository = YES;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	if (trackingTag != -1) {
		[self removeTrackingRect:trackingTag];
		trackingTag = -1;
	}
}

#pragma mark Drawing

- (void)drawRect:(NSRect)inRect
{
	[NSGraphicsContext saveGraphicsState];

	/* Drawn to what this view is, not to the rect it was handed. That rect says which part
	 * of the view is dirty, and since macOS 14 a view no longer clips its drawing to itself
	 * unless it is asked to, so the rect can name an area far larger than the view: measured
	 * here at 217 by 815 points inside a view of 36 by 36, which is the whole window. Taken
	 * as geometry, the shade that marks the picture as hoverable became a curtain over the
	 * entire window, one point short of its edges on every side.
	 *
	 * It read that way for as long as the code has existed and was harmless for all of it,
	 * because a view used to clip itself. */
	NSRect			drawRect = NSInsetRect([self bounds], 1, 1);
	NSBezierPath	*clipPath = [NSBezierPath bezierPathWithRoundedRect:drawRect radius:3];

	[[NSColor separatorColor] set];
	[clipPath setLineWidth:1];
	[clipPath stroke];

	// Ensure we have an even/odd winding rule in effect
	[clipPath setWindingRule:NSWindingRuleEvenOdd];
	[clipPath addClip];
	
	[super drawRect:inRect];

	if (hovered) {
		//Enough to say the picture is a button, not enough to hide the picture
		[[[NSColor blackColor] colorWithAlphaComponent:0.20f] set];
		[clipPath fill];

		// Draw the arrow
		NSBezierPath	*arrowPath = [NSBezierPath bezierPath];
		NSRect			frame = [self bounds];	//where we draw, not where we sit
		[arrowPath moveToPoint:NSMakePoint(frame.size.width - ARROW_XOFFSET - ARROW_WIDTH, 
										   (ARROW_YOFFSET + (CGFloat)ARROW_HEIGHT))];
		[arrowPath relativeLineToPoint:NSMakePoint(ARROW_WIDTH, 0)];
		[arrowPath relativeLineToPoint:NSMakePoint(-(ARROW_WIDTH/2.0f), -((CGFloat)ARROW_HEIGHT))];
		
		[[NSColor whiteColor] set];
		[arrowPath fill];
	}

	[NSGraphicsContext restoreGraphicsState];
}

#pragma mark Mouse movement

- (void)setHovered:(BOOL)inHovered
{
	hovered = inHovered;
	
	[self setNeedsDisplay:YES];
}

- (void)mouseEntered:(NSEvent *)inEvent
{
	[self setHovered:YES];
	
	[super mouseEntered:inEvent];	
}

- (void)mouseExited:(NSEvent *)inEvent
{
	[self setHovered:NO];
	
	[super mouseExited:inEvent];
}


- (void)displayPicturePopUpForEvent:(NSEvent *)theEvent
{
	[AIContactListUserPictureMenuController popUpMenuForImagePicker:self];
}

// Custom mouse down tracking to display our menu and highlight
- (void)mouseDown:(NSEvent *)theEvent
{
	[self displayPicturePopUpForEvent:theEvent];
}

#pragma mark Tracking rects

// Remove old tracking rects when we change superviews
- (void)viewWillMoveToSuperview:(NSView *)newSuperview
{
	if (trackingTag != -1) {
		[self removeTrackingRect:trackingTag];
		trackingTag = -1;
	}
	
	[super viewWillMoveToSuperview:newSuperview];
}

- (void)viewDidMoveToSuperview
{
	[super viewDidMoveToSuperview];
	
	[self resetCursorRects];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
	if (trackingTag != -1) {
		[self removeTrackingRect:trackingTag];
		trackingTag = -1;
	}
	
	[super viewWillMoveToWindow:newWindow];
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];

	/* Belt and braces beside the rect in -drawRect:: from macOS 14 a view draws outside
	 * itself unless it says otherwise, and nothing here has any business doing that. */
	if ([self respondsToSelector:@selector(setClipsToBounds:)])
		[self setClipsToBounds:YES];

	[self resetCursorRects];
}

- (void)frameDidChange:(NSNotification *)inNotification
{
	[self resetCursorRects];
}

// Reset our cursor tracking
- (void)resetCursorRects
{
	// Stop any existing tracking
	if (trackingTag != -1) {
		[self removeTrackingRect:trackingTag];
		trackingTag = -1;
	}
	
	// Add a tracking rect if our superview and window are ready
	if ([self superview] && [self window]) {
		NSRect	myFrame = [self frame];
		NSRect	trackRect = NSMakeRect(0, 0, myFrame.size.width, myFrame.size.height);
		
		if (trackRect.size.width > myFrame.size.width) {
			trackRect.size.width = myFrame.size.width;
		}
		
		NSPoint screenPoint = [NSEvent mouseLocation];
		NSPoint localPoint = [self convertPoint:[[self window] convertRectFromScreen:NSMakeRect(screenPoint.x, screenPoint.y, 0.0, 0.0)].origin
									   fromView:nil];
		BOOL	mouseInside = NSPointInRect(localPoint, myFrame);

		trackingTag = [self addTrackingRect:trackRect owner:self userData:nil assumeInside:mouseInside];
		if (mouseInside) [self mouseEntered:[[NSEvent alloc] init]];
	}
}

@end
