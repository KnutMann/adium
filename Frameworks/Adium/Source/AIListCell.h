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

#import "AIProxyListObject.h"

@class AIListObject, AIListOutlineView, AIAdium;

#define DROP_HIGHLIGHT_WIDTH_MARGIN 5.0f
#define DROP_HIGHLIGHT_HEIGHT_MARGIN 1.0f

#define MOCKIE_RADIUS		6		//Radius of the rounded mockie corners
#define BUBBLE_EDGE_INDENT	4		//Extra padding that makes room for a bubble's round edge

/*!
 * @brief The shape a row is drawn in
 *
 * What used to be six cell classes. Plain is the square row of the standard and
 * borderless layouts, Mockie the rounded block where a group rounds its top and
 * the last contact under it its bottom, Bubble one rounded pill per row.
 */
typedef enum {
	AIListRowShapePlain = 0,
	AIListRowShapeMockie,
	AIListRowShapeBubble
} AIListRowShape;

@interface AIListCell : NSCell {
	__unsafe_unretained AIListOutlineView	*outlineControlView;	//The view that owns this cell; matches the assign property
    AIProxyListObject	*proxyObject;
    BOOL				isGroup;
	
	NSTextAlignment		textAlignment;
	CGFloat					labelFontHeight;
	
	CGFloat					topSpacing;
	CGFloat					bottomSpacing;
	CGFloat					topPadding;
	CGFloat					bottomPadding;

	CGFloat					leftPadding;
	CGFloat					rightPadding;
	CGFloat					leftSpacing;
	CGFloat					rightSpacing;
	
	CGFloat					indentation;

	NSColor				*textColor;
	NSColor				*invertedTextColor;
	
	NSFont				*font;
	
	BOOL				useAliasesAsRequested;
	NSMutableDictionary *labelAttributes;

	AIListRowShape		shape;
	BOOL				fitted;
}

- (void)setProxyListObject:(AIProxyListObject *)inObject;
@property (readonly, nonatomic) BOOL isGroup;
@property (readwrite, assign, nonatomic) AIListOutlineView *outlineControlView;

//Display options
/*!
 * @brief The shape this row is drawn in
 */
@property (readwrite, nonatomic) AIListRowShape shape;
/*!
 * @brief Whether a bubble is drawn only as wide as its contents
 */
@property (readwrite, nonatomic) BOOL fitted;
@property (readwrite, nonatomic) NSTextAlignment textAlignment;
@property (readwrite, retain, nonatomic) NSColor *textColor;
@property (readwrite, retain, nonatomic) NSColor *invertedTextColor;

//Cell sizing and padding
- (void) setSplitVerticalSpacing:(int) inSpacing;
- (void) setSplitVerticalPadding:(int) inPadding;
@property (readonly, nonatomic) NSSize cellSize;
@property (readonly, nonatomic) CGFloat cellWidth;
@property (readwrite, nonatomic) CGFloat rightSpacing;
@property (readwrite, nonatomic) CGFloat leftSpacing;
@property (readwrite, nonatomic) CGFloat topSpacing;
@property (readwrite, nonatomic) CGFloat bottomSpacing;
@property (readwrite, nonatomic) CGFloat rightPadding;
@property (readwrite, nonatomic) CGFloat leftPadding;
@property (readwrite, nonatomic) CGFloat topPadding;
@property (readwrite, nonatomic) CGFloat bottomPadding;
@property (readwrite, nonatomic) CGFloat indentation;

//Drawing
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (void)_drawHighlightWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (void)drawSelectionWithFrame:(NSRect)rect;
- (void)drawBackgroundWithFrame:(NSRect)rect;
- (void)drawContentWithFrame:(NSRect)rect;
- (void)drawDropHighlightWithFrame:(NSRect)rect;
@property (readonly, nonatomic) NSAttributedString *displayName;
@property (readonly, nonatomic) NSSize displayNameSize;
- (NSRect)drawDisplayNameWithFrame:(NSRect)inRect;
@property (readonly, nonatomic) NSString *labelString;
@property (readonly, nonatomic) NSMutableDictionary *labelAttributes;
@property (readonly, nonatomic) NSDictionary *additionalLabelAttributes;
@property (readonly, nonatomic) BOOL cellIsSelected;
@property (readonly, nonatomic) BOOL drawGridBehindCell;
@property (readonly, nonatomic) NSColor *backgroundColor;

@property (readwrite, nonatomic) BOOL shouldShowAlias;

//What a reader says about this row
@property (readonly, nonatomic) NSString *spokenDescription;

@end
