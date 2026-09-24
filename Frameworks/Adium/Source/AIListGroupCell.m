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

#import <Adium/AIListGroupCell.h>
#import <Adium/AIListOutlineView.h>
#import <Adium/ESObjectWithProperties.h>
#import <AIUtilities/AIBezierPathAdditions.h>
#import <AIUtilities/AIColorAdditions.h>
#import <AIUtilities/AIGradientAdditions.h>
#import <AIUtilities/AIParagraphStyleAdditions.h>
#import <Adium/AIListObject.h>

#define FLIPPY_TEXT_PADDING		4
#define GROUP_COUNT_PADDING		4

@implementation AIListGroupCell

//Copy
//Init
- (id)init
{
	if ((self = [super init])) {
		shadowColor = nil;
		groupBackgroundColor = nil;
		gradientColor = nil;
		for (int i = 0; i < NUMBER_OF_GROUP_STATES; i++) _gradient[i] = nil;
		drawsGradientEdges = NO;
		outlineBubble = NO;
		outlineBubbleLineWidth = 1.0f;
		drawBubble = YES;
		layoutManager = [[NSLayoutManager alloc] init];
	}
	
	return self;
}

//Display Options ------------------------------------------------------------------------------------------------------
#pragma mark Display Options
//Color of our display name shadow
- (void)setShadowColor:(NSColor *)inColor
{
	if (inColor != shadowColor) {
		shadowColor = inColor;
	}
	labelAttributes = nil;
}
- (NSColor *)shadowColor{
	return shadowColor;
}

- (void)setDrawsBackground:(BOOL)inValue
{
	drawsBackground = inValue;
}

//Set the background color and alternate/gradient background color of this group
- (void)setBackgroundColor:(NSColor *)inBackgroundColor gradientColor:(NSColor *)inGradientColor
{
	if (inBackgroundColor != groupBackgroundColor) {
		groupBackgroundColor = inBackgroundColor;
	}
	if (inGradientColor != gradientColor) {
		gradientColor = inGradientColor;
	}
	
	//Reset gradient cache
	[self flushGradientCache];
}

- (void)setDrawsGradientEdges:(BOOL)inValue
{
	drawsGradientEdges = inValue;
}

//Sizing & Padding -----------------------------------------------------------------------------------------------------
#pragma mark Sizing & Padding
//Padding.  Gives our cell a bit of extra padding for the group name and flippy triangle (disclosure triangle)
- (CGFloat)topPadding{
	return [super topPadding] + 1;
}
- (CGFloat)bottomPadding{
	return [super bottomPadding] + 1;
}
- (CGFloat)leftPadding{
	return [super leftPadding] + 2 + (shape == AIListRowShapeBubble ? BUBBLE_EDGE_INDENT : 0);
}
- (CGFloat)rightPadding{
	return [super rightPadding] + 4 + (shape == AIListRowShapeBubble ? BUBBLE_EDGE_INDENT : 0);
}

//Cell height and width
- (NSSize)cellSize
{
	NSSize	size = [super cellSize];
	return NSMakeSize(0, [layoutManager defaultLineHeightForFont:[self font]] + size.height);
}
- (CGFloat)cellWidth
{
	AIListObject    *listObject = [proxyObject listObject];
	CGFloat			width = [super cellWidth] + [self flippyIndent] + GROUP_COUNT_PADDING;
	
	//Get the size of our display name
	width += AIceil(self.displayNameSize.width) + 1;
	
	if ([listObject boolValueForProperty:@"showCount"] && 
		[listObject valueForProperty:@"countText"]) {
		NSAttributedString *countText = [[NSAttributedString alloc] initWithString:[listObject valueForProperty:@"countText"]
																		attributes:[self labelAttributes]];
		width += AIceil([countText size].width) + 1;

		//A fitted bubble writes the count into the name, in brackets
		if (shape == AIListRowShapeBubble && fitted) {
			NSAttributedString *brackets = [[NSAttributedString alloc] initWithString:@" ()"
																		   attributes:[self labelAttributes]];
			width += AIceil([brackets size].width);
		}
	}
	
	return width + 1;
}

/*!
 * @brief The name as it is drawn
 *
 * A fitted bubble has no room to the right for a count, so it is added to the
 * name instead.
 */
- (NSAttributedString *)displayName
{
	NSString *countText;
	AIListObject *listObject = [proxyObject listObject];

	if (shape == AIListRowShapeBubble && fitted &&
		[listObject boolValueForProperty:@"showCount"] &&
		(countText = [listObject valueForProperty:@"countText"])) {
		return [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ (%@)", [self labelString], countText]
											   attributes:[self labelAttributes]];
	}

	return super.displayName;
}

/*!
 * @brief Get the distance from left margin to our display name.
 *
 * This is the space used by the flippy triangle (disclosure triangle)... more or less.
 */
- (CGFloat)flippyIndent
{
//	if ([self textAlignment] != NSTextAlignmentCenter) {
		NSSize size = [self cellSize];
		return size.height*0.4f + size.height*0.2f + FLIPPY_TEXT_PADDING;
/*	} else {
		return 0;
	}
*/
}


//Drawing --------------------------------------------------------------------------------------------------------------
#pragma mark Drawing
//Draw content of our cell
- (void)drawContentWithFrame:(NSRect)rect
{
    AIListObject *listObject = [proxyObject listObject];
    
	//Draw flippy triangle (disclosure triangle)
	[[self flippyColor] set];
	
	NSBezierPath	*arrowPath = [NSBezierPath bezierPath];
	NSPoint			center = NSMakePoint(rect.origin.x + rect.size.height*0.4f, rect.origin.y + (rect.size.height/2.0f));

	if ([self.outlineControlView isItemExpanded:proxyObject]) {
		[arrowPath moveToPoint:NSMakePoint(center.x - rect.size.height*0.3f, center.y - rect.size.height*0.15f)];
		[arrowPath relativeLineToPoint:NSMakePoint( rect.size.height*0.6f, 0)];
		[arrowPath relativeLineToPoint:NSMakePoint(-rect.size.height*0.3f, rect.size.height*0.4f)];		
	} else {
		[arrowPath moveToPoint:NSMakePoint(center.x - rect.size.height*0.2f, center.y - rect.size.height*0.3f)];
		[arrowPath relativeLineToPoint:NSMakePoint( 0, rect.size.height*0.6f)];
		[arrowPath relativeLineToPoint:NSMakePoint( rect.size.height*0.4f, -rect.size.height*0.3f)];		
	}
		
	[arrowPath closePath];
	[arrowPath fill];

//	if ([self textAlignment] != NSTextAlignmentCenter) {
		rect.origin.x += rect.size.height*0.4f + rect.size.height*0.2f + FLIPPY_TEXT_PADDING;
		rect.size.width -= rect.size.height*0.4f + rect.size.height*0.2f + FLIPPY_TEXT_PADDING;
//	}
	
	if ([listObject boolValueForProperty:@"showCount"]) {
		rect = [self drawGroupCountWithFrame:rect];
	}
	
	[self drawDisplayNameWithFrame:rect];
}

- (NSRect)drawGroupCountWithFrame:(NSRect)inRect
{
    AIListObject *listObject = [proxyObject listObject];

	/* A fitted bubble carries the count inside the name, flush with it. Drawing
	 * it right justified as well would put it outside the bubble. */
	if (shape == AIListRowShapeBubble && fitted) return inRect;

	if ([listObject valueForProperty:@"countText"]) {
		NSAttributedString	*groupCount = [[NSAttributedString alloc] initWithString:[listObject valueForProperty:@"countText"]
																		  attributes:[self labelAttributes]];
		
		NSSize				countSize = [groupCount size];
		NSRect				rect = inRect;
		
		if (countSize.width + GROUP_COUNT_PADDING > rect.size.width) countSize.width = rect.size.width;
		if (countSize.height > rect.size.height) countSize.height = rect.size.height;
		
		if ([self textAlignment] == NSTextAlignmentRight) {
			// If the alignment is on the left, we need to move the original rect's x origin to the right.
			inRect.origin.x += countSize.width + GROUP_COUNT_PADDING;
		} else {
			// If alignment is on the left or center, we need to move our drawing x origin to the right.
			rect.origin.x += (rect.size.width - countSize.width);
		}
		
		CGFloat half = AIceil((rect.size.height - labelFontHeight) / 2.0f);
		[groupCount drawInRect:NSMakeRect(rect.origin.x,
										  rect.origin.y + half,
										  rect.size.width,
										  countSize.height)];

		inRect.size.width -= countSize.width + GROUP_COUNT_PADDING;
	}
	
	return inRect;
}

#pragma mark Shape

/*!
 * @brief The rectangle the shape is drawn in
 *
 * The whole frame, unless the bubble is fitted, in which case it is pulled in
 * around the name.
 */
- (NSRect)bubbleRectForFrame:(NSRect)rect
{
	if (shape != AIListRowShapeBubble || !fitted) return rect;

	NSSize	nameSize = [self.displayName size];
	CGFloat	originalWidth = rect.size.width;
	CGFloat	originalX = rect.origin.x;

	//Alignment
	switch ([self textAlignment]) {
		case NSTextAlignmentCenter:
			rect.origin.x += ((rect.size.width - nameSize.width) / 2.0f) - [self leftPadding];
		break;
		case NSTextAlignmentRight:
			rect.origin.x += (rect.size.width - nameSize.width) - [self leftPadding] - [self rightPadding];
		break;
		default:
		break;
	}

	//Fit the bubble to their name
	rect.size.width = nameSize.width + [self leftPadding] + [self rightPadding];

	//Until we get right aligned/centered flippies, this will do
	if ([self textAlignment] == NSTextAlignmentLeft) {
		rect.size.width += [self flippyIndent];
	}

	//Don't let the bubble try to draw larger than the width we were passed, which was the full width possible
	if (rect.size.width > originalWidth) rect.size.width = originalWidth;
	if (rect.origin.x < originalX) rect.origin.x = originalX;

	return rect;
}

/*!
 * @brief The Mockie shape of a group
 *
 * An open group rounds only its top, so that it runs into the contact below it;
 * a closed one is a block of its own and rounds all four corners.
 */
- (NSBezierPath *)mockieBackgroundPathForFrame:(NSRect)rect
{
	return ([self.outlineControlView isItemExpanded:proxyObject] ?
			[NSBezierPath bezierPathWithRoundedTopCorners:rect radius:MOCKIE_RADIUS] :
			[NSBezierPath bezierPathWithRoundedRect:rect radius:MOCKIE_RADIUS]);
}

//Draw the cached gradient picture, which is where the colour set's group colours end up
- (void)drawGradientBackgroundInFrame:(NSRect)rect
{
	if (![self cellIsSelected] && drawsBackground) {
		[[self cachedGradient:rect.size] drawInRect:rect
										   fromRect:NSMakeRect(0,0,rect.size.width,rect.size.height)
										  operation:NSCompositingOperationCopy
										   fraction:1.0f];
	}
}

//Draw the background of our cell
- (void)drawBackgroundWithFrame:(NSRect)rect
{
	switch (shape) {
		case AIListRowShapePlain:
			[self drawGradientBackgroundInFrame:rect];
			break;

		case AIListRowShapeMockie:
			if (drawsBackground) {
				[self drawGradientBackgroundInFrame:rect];
			} else if (![self cellIsSelected]) {
				[[self backgroundColor] set];
				[[self mockieBackgroundPathForFrame:rect] fill];
			}
			break;

		case AIListRowShapeBubble:
			if (!drawBubble) break;
			if (drawsBackground) {
				[self drawGradientBackgroundInFrame:[self bubbleRectForFrame:rect]];
			} else if (![self cellIsSelected]) {
				NSBezierPath *bezierPath = [NSBezierPath bezierPathWithRoundedRect:[self bubbleRectForFrame:rect]];

				[[self backgroundColor] set];
				[bezierPath fill];

				if (outlineBubble) {
					[bezierPath setLineWidth:outlineBubbleLineWidth];
					[[self textColor] set];
					[bezierPath stroke];
				}
			}
			break;
	}
}

//Draw a custom selection
- (void)drawSelectionWithFrame:(NSRect)cellFrame
{
	if (shape == AIListRowShapePlain || ![self cellIsSelected]) return;

	NSColor *highlightColor = [self.outlineControlView highlightColor];
	NSGradient *gradient = (highlightColor ?
							[[NSGradient alloc] initWithStartingColor:highlightColor
														  endingColor:[highlightColor darkenAndAdjustSaturationBy:0.4f]] :
							[NSGradient selectedControlGradient]);

	/* The two shapes have always run their gradient in opposite directions.
	 * Kept as it was; it belongs on the list for the colour round. */
	if (shape == AIListRowShapeMockie) {
		[gradient drawInBezierPath:[self mockieBackgroundPathForFrame:cellFrame] angle:90.0f];
	} else {
		[gradient drawInBezierPath:[NSBezierPath bezierPathWithRoundedRect:[self bubbleRectForFrame:cellFrame]] angle:270.0f];
	}
}

- (void)drawDropHighlightWithFrame:(NSRect)rect
{
	if (shape == AIListRowShapePlain) {
		[super drawDropHighlightWithFrame:rect];
		return;
	}

	[NSGraphicsContext saveGraphicsState];

	//Ensure we don't draw outside our rect
	[[NSBezierPath bezierPathWithRect:rect] addClip];

	//Cell spacing
	rect.origin.y += [self topSpacing];
	rect.size.height -= [self bottomSpacing] + [self topSpacing];
	rect.origin.x += [self leftSpacing];
	rect.size.width -= [self rightSpacing] + [self leftSpacing];

	//Margin for the drop highlight
	rect.size.width -= DROP_HIGHLIGHT_WIDTH_MARGIN;
	rect.origin.x += DROP_HIGHLIGHT_WIDTH_MARGIN / 2.0f;

	rect.size.height -= DROP_HIGHLIGHT_HEIGHT_MARGIN;
	rect.origin.y += DROP_HIGHLIGHT_HEIGHT_MARGIN / 2.0f;

	NSBezierPath *path = (shape == AIListRowShapeMockie ?
						  [self mockieBackgroundPathForFrame:rect] :
						  [NSBezierPath bezierPathWithRoundedRect:[self bubbleRectForFrame:rect]]);

	[[[NSColor blueColor] colorWithAlphaComponent:0.2f] set];
	[path fill];

	[[[NSColor blueColor] colorWithAlphaComponent:0.8f] set];
	[path setLineWidth:2.0f];
	[path stroke];

	[NSGraphicsContext restoreGraphicsState];
}

- (void)setOutlineBubble:(BOOL)flag
{
	outlineBubble = flag;
}
- (void)setOutlineBubbleLineWidth:(float)inWidth
{
	outlineBubbleLineWidth = inWidth;
}
- (void)setHideBubble:(BOOL)flag
{
	drawBubble = !(flag);
}

//Color of our flippy triangle (disclosure triangle).  By default we use the cell's text color.
- (NSColor *)flippyColor
{
	return [self textColor];
}

/*!
 * @brief Additional label attributes
 *
 * We override the paragraph style to be truncating middle.
 * The user's layout preferences may have indicated to add a shadow to the text.
 */
- (NSMutableDictionary *)labelAttributes
{
	if (!labelAttributes) {
		labelAttributes = super.labelAttributes;
		
		if (shadowColor) {
			NSShadow	*textShadow = [[NSShadow alloc] init];
			
			[textShadow setShadowOffset:NSMakeSize(0.0f, -1.0f)];
			[textShadow setShadowBlurRadius:2.0f];
			[textShadow setShadowColor:shadowColor];
			
			[labelAttributes setObject:textShadow forKey:NSShadowAttributeName];
		}
	}
	
	static NSMutableParagraphStyle *leftParagraphStyleWithTruncatingMiddle = nil;
	if (!leftParagraphStyleWithTruncatingMiddle) {
		leftParagraphStyleWithTruncatingMiddle = [NSMutableParagraphStyle styleWithAlignment:NSTextAlignmentLeft
																			  lineBreakMode:NSLineBreakByTruncatingMiddle];
	}

	[leftParagraphStyleWithTruncatingMiddle setMaximumLineHeight:(float)labelFontHeight];

	[labelAttributes setObject:leftParagraphStyleWithTruncatingMiddle
								  forKey:NSParagraphStyleAttributeName];
	
	return labelAttributes;
}


//Gradient -------------------------------------------------------------------------------------------------------------
#pragma mark Gradient
//Generates and caches an NSImage containing the group background gradient
/* Two pictures, not one: a Mockie group is drawn with its bottom corners round
 * when it is closed and square when it is open, so the two states cannot share
 * a cache. */
- (NSImage *)cachedGradient:(NSSize)inSize
{
	AIGroupState state = ([self.outlineControlView isItemExpanded:proxyObject] ? AIGroupExpanded : AIGroupCollapsed);

	if (!_gradient[state] || !NSEqualSizes(inSize, _gradientSize[state])) {
		_gradient[state] = [[NSImage alloc] initWithSize:inSize];
		_gradientSize[state] = inSize;

		[_gradient[state] lockFocus];
		[self drawBackgroundGradientInRect:NSMakeRect(0,0,inSize.width,inSize.height)];
		[_gradient[state] unlockFocus];
	}

	return _gradient[state];
}

//Draw our background gradient
- (void)drawBackgroundGradientInRect:(NSRect)inRect
{
	CGFloat backgroundL;
	CGFloat gradientL;

	/* The two rounded shapes take the gradient in their own outline and leave it
	 * at that; the sealing lines below belong to the square row. */
	if (shape == AIListRowShapeMockie) {
		[[self backgroundGradient] drawInBezierPath:[self mockieBackgroundPathForFrame:inRect] angle:90.0f];
		return;
	}

	if (shape == AIListRowShapeBubble) {
		if (!drawBubble) return;

		NSBezierPath *bezierPath = [NSBezierPath bezierPathWithRoundedRect:[self bubbleRectForFrame:inRect]];
		[[self backgroundGradient] drawInBezierPath:bezierPath angle:90.0f];

		if (outlineBubble) {
			[bezierPath setLineWidth:outlineBubbleLineWidth];
			[[self textColor] set];
			[bezierPath stroke];
		}
		return;
	}

	//Gradient
	[[self backgroundGradient] drawInRect:inRect angle:90.0f];
	
	//Add a sealing line at the light side of the gradient to make it look more polished.  Apple does this with
	//most gradients in OS X.
	[groupBackgroundColor getHue:NULL saturation:NULL brightness:&backgroundL alpha:NULL];
	[gradientColor   getHue:NULL saturation:NULL brightness:&gradientL   alpha:NULL];
	
	if (gradientL < backgroundL) { //Seal the top
		[gradientColor set];
		[NSBezierPath fillRect:NSMakeRect(inRect.origin.x, inRect.origin.y, inRect.size.width, 1)];
	} else { //Seal the bottom
		[groupBackgroundColor set];
		[NSBezierPath fillRect:NSMakeRect(inRect.origin.x, inRect.origin.y + inRect.size.height - 1, inRect.size.width, 1)];
	}
	
	//Seal the edges
	if (drawsGradientEdges) {
		[NSBezierPath fillRect:NSMakeRect(inRect.origin.x, inRect.origin.y, 1, inRect.size.height)];
		[NSBezierPath fillRect:NSMakeRect(inRect.origin.x+inRect.size.width-1, inRect.origin.y, 1, inRect.size.height)];
	}
}

//Group background gradient
- (NSGradient *)backgroundGradient
{
	return [[NSGradient alloc] initWithStartingColor:groupBackgroundColor endingColor:gradientColor];
}

//Reset gradient cache
- (void)flushGradientCache
{
	for (int i = 0; i < NUMBER_OF_GROUP_STATES; i++) {
		_gradient[i] = nil;
		_gradientSize[i] = NSMakeSize(0,0);
	}
}

@end
