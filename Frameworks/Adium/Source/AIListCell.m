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

#import <Adium/AIListCell.h>

#import <Adium/AIListGroup.h>
#import <Adium/AIListObject.h>
#import <Adium/AIProxyListObject.h>
#import <Adium/AIListBookmark.h>
#import <Adium/AIListOutlineView.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIBezierPathAdditions.h>
#import <AIUtilities/AIMutableOwnerArray.h>
#import <AIUtilities/AIParagraphStyleAdditions.h>

#import <Adium/AIStatusControllerProtocol.h>


//#define	ORDERING_DEBUG

@implementation AIListCell

static NSMutableParagraphStyle	*leftParagraphStyleWithTruncatingTail = nil;

//Init
- (id)init
{
    if ((self = [super init]))
	{
		   topSpacing = 
		bottomSpacing = 
		  leftSpacing = 
		 rightSpacing = 0;

		   topPadding = 
		bottomPadding = 
		  leftPadding = 
		 rightPadding = 0;
		
		font = [NSFont systemFontOfSize:12];
		/* No colour of its own: -textColor works one out from the ground this row
		 * is drawn on. Only the colour set knows that ground, so a fixed fallback
		 * here, or a semantic one that follows the system appearance instead of
		 * the set, produces white on white. */
		textColor = nil;
		invertedTextColor = [NSColor alternateSelectedControlTextColor];

		useAliasesAsRequested = YES;

		if (!leftParagraphStyleWithTruncatingTail) {
			leftParagraphStyleWithTruncatingTail = [NSMutableParagraphStyle styleWithAlignment:NSTextAlignmentLeft
																				 lineBreakMode:NSLineBreakByTruncatingTail];
		}
		
	}
		
    return self;
}

//Copy
- (id)copyWithZone:(NSZone *)zone
{
	AIListCell *newCell = [super copyWithZone:zone];

	/* The copy arrives holding everything this cell holds, and holding it properly:
	 * a counted class has the runtime retain its object ivars as it copies them,
	 * so there is nothing here to hand over. Only the cache is dropped, since the
	 * new cell rebuilds it from whatever it is asked to draw. */
	newCell->labelAttributes = nil;

	return newCell;
}

//Set the list object being drawn
- (void)setProxyListObject:(AIProxyListObject *)inProxyObject
{
	if (proxyObject != inProxyObject) {
		proxyObject = inProxyObject;
	}

	isGroup = [[proxyObject listObject] isKindOfClass:[AIListGroup class]];
}

@synthesize isGroup, outlineControlView;

//Return that this cell is draggable
- (NSCellHitResult)hitTestForEvent:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(NSView *)controlView
{
	return NSCellHitContentArea;
}

//Display options ------------------------------------------------------------------------------------------------------
#pragma mark Display options
//Font used to display label
- (void)setFont:(NSFont *)inFont
{
	if (inFont != font) {
		font = inFont;
	}

	//Calculate and cache the height of this font
	labelFontHeight = [[[NSLayoutManager alloc] init] defaultLineHeightForFont:[self font]];
	labelAttributes = nil;
}
- (NSFont *)font{
	return font;
}

@synthesize textAlignment, textColor, invertedTextColor;

/*!
 * @brief The colour the label is written in
 *
 * A colour set may leave this to us, for a contact whose state it does not
 * colour. The ground underneath comes from that same set and has nothing to do
 * with the system appearance, so the answer is worked out from the ground:
 * light ground, dark ink. Only where there is no ground at all does the system
 * colour, which does follow the appearance, get the last word.
 */
- (NSColor *)textColor
{
	if (textColor) return textColor;

	/* A row that is picked but whose list does not hold the keyboard keeps its
	 * ordinary ink today, and that ink has to hold up against the pale
	 * selection, not against the row colour underneath it. */
	NSColor *under = [self backgroundColor];
	if ([self isHighlighted] && [self.outlineControlView drawsSelectedRowHighlight]) {
		under = ([self cellIsSelected] ?
				 [NSColor selectedContentBackgroundColor] :
				 [NSColor unemphasizedSelectedContentBackgroundColor]);
	}

	/* Asking a system colour for its components resolves it against whatever
	 * appearance happens to be current, which outside a drawing pass is the
	 * one the Mac is set to, not the one this list is drawn in. So the answer
	 * is taken under the list's own appearance. */
	NSAppearance *appearance = (self.outlineControlView.effectiveAppearance ?:
								[NSAppearance currentDrawingAppearance]);
	__block NSColor *ground = nil;
	[appearance performAsCurrentDrawingAppearance:^{
		ground = [under colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
	}];
	if (!ground || ground.alphaComponent < 0.5f) return [NSColor labelColor];

	CGFloat luminance = (0.299f * ground.redComponent +
						 0.587f * ground.greenComponent +
						 0.114f * ground.blueComponent);
	return (luminance < 0.5f ? [NSColor whiteColor] : [NSColor blackColor]);
}

//Cell sizing and padding ----------------------------------------------------------------------------------------------
#pragma mark Cell sizing and padding
//Default cell size just contains our padding and spacing
- (NSSize)cellSize
{
	return NSMakeSize(0, [self topSpacing] + [self topPadding] + [self bottomPadding] + [self bottomSpacing]);
}

- (CGFloat)cellWidth
{
	return [self leftSpacing] + [self leftPadding] + [self rightPadding] + [self rightSpacing];
}

//User-defined spacing offsets.  A cell may adjust these values to to obtain a more desirable default. 
//These are offsets, they may be negative!  Spacing is the distance between cells (Spacing gaps are not filled).
- (void)setSplitVerticalSpacing:(int)inSpacing{
	self.topSpacing = inSpacing / 2;
	self.bottomSpacing = (inSpacing + 1) / 2;
}

//User-defined padding offsets.  A cell may adjust these values to to obtain a more desirable default.
//These are offsets, they may be negative!  Padding is the distance between cell edges and their content.
- (void)setSplitVerticalPadding:(int)inPadding{
	self.topPadding = inPadding / 2;
	self.bottomPadding = (inPadding + 1) / 2;
}

@synthesize rightPadding, leftPadding, topPadding, bottomPadding, indentation, rightSpacing, leftSpacing, topSpacing, bottomSpacing;

//Drawing --------------------------------------------------------------------------------------------------------------
#pragma mark Drawing
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)inControlView{
    [self drawInteriorWithFrame:cellFrame inView:inControlView];
}
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)inControlView
{	
	if ([proxyObject listObject]) {
		//Cell spacing
		cellFrame.origin.y += [self topSpacing];
		cellFrame.size.height -= [self bottomSpacing] + [self topSpacing];
		cellFrame.origin.x += [self leftSpacing];
		cellFrame.size.width -= [self rightSpacing] + [self leftSpacing];
		
		[self drawBackgroundWithFrame:cellFrame];

		//Padding
		cellFrame.origin.y += [self topPadding];
		cellFrame.size.height -= [self bottomPadding] + [self topPadding];
		cellFrame.origin.x += [self leftPadding];
		cellFrame.size.width -= [self rightPadding] + [self leftPadding];

		switch ([self textAlignment]) {
			case NSTextAlignmentRight:
				//Right alignment indents on the right
				cellFrame.size.width -= [self indentation];
				break;
			default:
				//All other alignments indent on the left
				cellFrame.origin.x += [self indentation];
				cellFrame.size.width -= [self indentation];
				break;
		}
		[self drawContentWithFrame:cellFrame];
	}
}

/* Custom highlighting (This is a private cell method we're overriding that handles selection drawing)
 * Bubble and Mockie Cells depend upon drawSelectionWithFrame: being called from here; perhaps we could call that
 * from elsewhere.
 */
- (void)_drawHighlightWithFrame:(NSRect)cellFrame inView:(NSView *)inControlView
{
	//Cell spacing
	cellFrame.origin.y += [self topSpacing];
	cellFrame.size.height -= [self bottomSpacing] + [self topSpacing];
	cellFrame.origin.x += [self leftSpacing];
	cellFrame.size.width -= [self rightSpacing] + [self leftSpacing];
	
	[self drawSelectionWithFrame:cellFrame];
}

//Draw Selection
- (void)drawSelectionWithFrame:(NSRect)rect {}
	
//Draw the background of our cell
- (void)drawBackgroundWithFrame:(NSRect)rect {}

//Draw content of our cell
- (void)drawContentWithFrame:(NSRect)rect
{
	[self drawDisplayNameWithFrame:rect];
}

- (void)drawDropHighlightWithFrame:(NSRect)rect
{	
	[NSGraphicsContext saveGraphicsState];

	//Ensure we don't draw outside our rect
	[[NSBezierPath bezierPathWithRect:rect] addClip];
	
	rect.size.width -= DROP_HIGHLIGHT_WIDTH_MARGIN;
	rect.origin.x += DROP_HIGHLIGHT_WIDTH_MARGIN / 2.0f;
	
	rect.size.height -= DROP_HIGHLIGHT_HEIGHT_MARGIN;
	rect.origin.y += DROP_HIGHLIGHT_HEIGHT_MARGIN / 2.0f;

	NSBezierPath	*path = [NSBezierPath bezierPathWithRoundedRect:rect radius:4.0f];

	[[[NSColor blueColor] colorWithAlphaComponent:0.2f] set];
	[path fill];
	
	[[[NSColor blueColor] colorWithAlphaComponent:0.8f] set];
	[path setLineWidth:2.0f];
	[path stroke];

	[NSGraphicsContext restoreGraphicsState];	
}

/*!
 * @brief Return the attributed string to be displayed as the primary text of the cell
 */
- (NSAttributedString *)displayName
{
	NSDictionary *attributes = self.labelAttributes;
	NSString *labelString = self.labelString;
	if (![labelAttributes isEqualToDictionary:proxyObject.cachedLabelAttributes] || ![labelString isEqualToString:proxyObject.cachedDisplayNameString]) {
		proxyObject.cachedDisplayName = [[NSAttributedString alloc] initWithString:labelString
																		attributes:attributes];
		proxyObject.cachedDisplayNameString = labelString;
		proxyObject.cachedLabelAttributes = attributes;
		proxyObject.cachedDisplayNameSize = NSZeroSize;
	}
	
	return proxyObject.cachedDisplayName;
}

- (NSSize) displayNameSize
{
	NSSize size = proxyObject.cachedDisplayNameSize;
	if(NSEqualSizes(size, NSZeroSize)) {
		size = [self.displayName size];
		proxyObject.cachedDisplayNameSize = size; 
	}

	return size;
}

//Draw our display name
- (NSRect)drawDisplayNameWithFrame:(NSRect)inRect
{
	NSAttributedString	*displayName = self.displayName;
	NSSize				nameSize = self.displayNameSize;
	NSRect				rect = inRect;

	if (nameSize.width > rect.size.width) nameSize.width = rect.size.width;
	if (nameSize.height > rect.size.height) nameSize.height = rect.size.height;

	//Alignment
	switch ([self textAlignment]) {
		case NSTextAlignmentCenter:
			rect.origin.x += (rect.size.width - nameSize.width) / 2.0f;
		break;
		case NSTextAlignmentRight:
			rect.origin.x += (rect.size.width - nameSize.width);
		break;
		default:
		break;
	}

	//Draw (centered vertical)
	CGFloat half = AIceil((rect.size.height - labelFontHeight) / 2.0f);
	[displayName drawInRect:NSMakeRect(rect.origin.x,
									   rect.origin.y + half,
									   rect.size.width,
									   nameSize.height)];

	//Adjust the drawing rect
	switch ([self textAlignment]) {
		case NSTextAlignmentRight:
			inRect.size.width -= nameSize.width;
		break;
		case NSTextAlignmentLeft:
			inRect.origin.x += nameSize.width;
			inRect.size.width -= nameSize.width;
		break;
		default:
		break;
	}
	
	return inRect;
}

//Display string for our list object
- (NSString *)labelString
{
	NSString *label =  ([self shouldShowAlias] ? 
						[[proxyObject listObject] longDisplayName] :
						([proxyObject listObject].formattedUID ? [proxyObject listObject].formattedUID : [[proxyObject listObject] longDisplayName]));
	if (!label) {
		AILog(@"Couldn't get a labelString for contact %@", [proxyObject listObject]);
		return @"";
	}
	return label;
}

@synthesize shouldShowAlias = useAliasesAsRequested;

//Attributes for displaying the label string
//Cache is invalidated on font changes, 
- (NSMutableDictionary *)labelAttributes
{
	if (!labelAttributes) {
		labelAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
												leftParagraphStyleWithTruncatingTail, NSParagraphStyleAttributeName,
												[self font], NSFontAttributeName,
												nil];

	}
	
	[leftParagraphStyleWithTruncatingTail setMaximumLineHeight:(float)labelFontHeight];
	NSColor				*currentTextColor = ([self cellIsSelected] ? [self invertedTextColor] : [self textColor]);
	[labelAttributes setObject:currentTextColor forKey:NSForegroundColorAttributeName];
	
	return labelAttributes;
}

//Additional attributes to apply to our label string (For Sub-Classes)
- (NSDictionary *)additionalLabelAttributes
{
	return nil;
}

//YES if our cell is currently selected
- (BOOL)cellIsSelected
{
	return ([self isHighlighted] &&
		   [[self.outlineControlView window] isKeyWindow] &&
		   [[self.outlineControlView window] firstResponder] == self.outlineControlView);
}

//YES if a grid would be visible behind this cell (needs to be drawn)
- (BOOL)drawGridBehindCell
{
	return YES;
}

//The background color for this cell.  This will either be [controlView backgroundColor] or [controlView alternatingGridColor]
- (NSColor *)backgroundColor
{
	//We could just call backgroundColorForRow: but it's best to avoid doing a rowForItem lookup if there is no grid
	if ([self.outlineControlView usesAlternatingRowBackgroundColors]) {
		return [self.outlineControlView backgroundColorForRow:[self.outlineControlView rowForItem:proxyObject]];
	} else {
		return [self.outlineControlView backgroundColor];
	}
}

#pragma mark Accessibility

- (NSArray *)accessibilityAttributeNames
{
	NSMutableArray *attributeNames = [[super accessibilityAttributeNames] mutableCopy];
	[attributeNames addObject:NSAccessibilityValueAttribute];

	return attributeNames;
}

- (id)accessibilityAttributeValue:(NSString *)attribute
{
	id value;

	if ([attribute isEqualToString:NSAccessibilityRoleAttribute]) {
		value = NSAccessibilityStaticTextRole;
		
	} else if ([attribute isEqualToString:NSAccessibilityValueAttribute]) {
		value = [self spokenDescription];

	} else if ([attribute isEqualToString:NSAccessibilityTitleAttribute]) {
		value = [self labelString];
		
	} else if ([attribute isEqualToString:NSAccessibilityWindowAttribute]) {
		value = [self.outlineControlView window];
                
	} else {
		value = [super accessibilityAttributeValue:attribute];
	}

	return value;
}

/*!
 * @brief What a reader says about this row
 *
 * Kept apart from the attribute lookup above because the view that hosts this
 * cell answers for it now, through the current accessibility API.
 */
- (NSString *)spokenDescription
{
	AIListObject *listObject = [proxyObject listObject];
	if (!listObject) return @"";

	if ([listObject isKindOfClass:[AIListGroup class]]) {
		return [NSString stringWithFormat:AILocalizedString(@"contact group %@", "%@ will be the name of a group in the contact list"), [listObject longDisplayName]];
	}

	if ([listObject isKindOfClass:[AIListBookmark class]]) {
		return [NSString stringWithFormat:AILocalizedString(@"group chat bookmark %@", "%@ will be the name of a bookmark"), [listObject longDisplayName]];
	}

	NSString *statusDescription = [adium.statusController localizedDescriptionForStatusName:(listObject.statusName ?
																							listObject.statusName :
																							[adium.statusController defaultStatusNameForType:listObject.statusType])
																				statusType:listObject.statusType];
	NSString *statusMessage = [listObject statusMessageString];

	NSMutableString *value = [[listObject longDisplayName] mutableCopy];
	if (statusDescription) [value appendFormat:@"; %@", statusDescription];
	if (statusMessage) [value appendFormat:AILocalizedString(@"; status message %@", "please keep the semicolon at the start of the line. %@ will be replaced by a status message. This is used when reading an entry in the contact list aloud, such as 'Evan Schoenberg; status message I am bouncing up and down'"), statusMessage];

	return value;
}

@end
