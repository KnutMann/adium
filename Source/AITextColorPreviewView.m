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

#import "AITextColorPreviewView.h"
#import <AIUtilities/AIParagraphStyleAdditions.h>

@interface AITextColorPreviewView ()

- (void)AI_initTextColorPreviewView;

@end

@implementation AITextColorPreviewView

/* The backgroundColor outlet collides with NSView's own backgroundColor
 * property (added in macOS 14): nib loading now goes through this setter,
 * passing the connected NSColorWell, instead of setting the ivar directly.
 * NSColor's -copy on the well then crashed the theme editor sheet. */
- (void)setBackgroundColor:(id)inColorWell
{
	backgroundColor = inColorWell;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [super initWithCoder:aDecoder])) {
    	[self AI_initTextColorPreviewView];
	}

    return self;
}

- (id)initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect])) {
    	[self AI_initTextColorPreviewView];
	}

    return self;
}

- (void)AI_initTextColorPreviewView
{
	backColorOverride = nil;

	/* Stay inside the frame. Until macOS 14 a view was clipped to its own
	 * bounds whether it asked to be or not; now it is not, and this one paints
	 * a filled rectangle. Without this the swatch covers the sheet it sits in,
	 * and everything drawn before it disappears, buttons included. */
	self.clipsToBounds = YES;
}

- (void)drawRect:(NSRect)rect
{
	NSMutableDictionary	*attributes;
	NSAttributedString	*sample;
	NSShadow			*textShadow = nil;
	NSSize				sampleSize;
	
	/* The swatch is the whole view, every time. What arrives as rect is only the
	 * part that needs repainting, which is smaller whenever something overlapped
	 * this view a moment ago; filling that instead used to leave a half painted
	 * swatch with the sample word off to one side. */
	NSRect swatch = self.bounds;

	// Background
	if (([backgroundEnabled state] != NSControlStateValueOff) && backgroundGradientColor) {
		[[[NSGradient alloc] initWithStartingColor:[backgroundGradientColor color] endingColor:[backgroundColor color]] drawInRect:swatch angle:90.0f];
	} else {
		NSColor *backColor = (backColorOverride ? backColorOverride : [backgroundColor color]);
		
		if (backColor) {
			[backColor set];
			[NSBezierPath fillRect:swatch];
		}
	}

	// Shadow
	if (([textShadowColorEnabled state] != NSControlStateValueOff) && [textShadowColor color]) {
		textShadow = [[NSShadow alloc] init];
		[textShadow setShadowOffset:NSMakeSize(0.0f, -1.0f)];
		[textShadow setShadowBlurRadius:2.0f];
		[textShadow setShadowColor:[textShadowColor color]];
	}

	// Text
	NSColor *colorForText = [textColor color];
	
	if (colorForText) {
		// If we have a checkbox and it's unchecked, change to black.
		if (textColorEnabled && ([textColorEnabled state] == NSControlStateValueOff)) {
			colorForText = [NSColor blackColor];
		}
	}
	
	attributes = [NSMutableDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize:12], NSFontAttributeName,
																	[NSParagraphStyle styleWithAlignment:NSTextAlignmentCenter], NSParagraphStyleAttributeName,
																	colorForText, NSForegroundColorAttributeName,
																	textShadow, NSShadowAttributeName,
																	nil];
	
	sample = [[NSAttributedString alloc] initWithString:AILocalizedString(@"Sample",nil)
											 attributes:attributes];
	sampleSize = [sample size];

	[sample drawInRect:NSIntegralRect(NSMakeRect(swatch.origin.x + ((swatch.size.width - sampleSize.width) / 2.0f),
												 swatch.origin.y + ((swatch.size.height - sampleSize.height) / 2.0f),
												 sampleSize.width,
												 sampleSize.height))];
}

// Overrides. Pass nil to disable
- (void)setBackColorOverride:(NSColor *)inColor
{
	backColorOverride = inColor;
}

@end
