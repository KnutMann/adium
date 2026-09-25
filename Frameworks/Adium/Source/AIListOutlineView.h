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

#import <AIUtilities/AIMultiCellOutlineView.h>
#import <Adium/AIAbstractListController.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIListOutlineView+Drawing.h>

@class AIListObject;

typedef enum {
	AINormalBackground = 0,
	AITileBackground,
	AIFillProportionatelyBackground,
	AIFillStretchBackground
} AIBackgroundStyle;

@interface AIListOutlineView : AIMultiCellOutlineView <ContactListOutlineView> {    
	BOOL				groupsHaveBackground;
	BOOL				updateShadowsWhileDrawing;	

	NSImage				*backgroundImage;
	CGFloat				backgroundFade;
	BOOL				_drawBackground;
	AIBackgroundStyle	backgroundStyle;
	AIContactListWindowStyle windowStyle;
	
	NSColor				*backgroundColor;
	NSColor				*_backgroundColorWithOpacity;
	CGFloat				backgroundOpacity;
	
	NSColor				*highlightColor;

	NSColor				*rowColor;
	NSColor				*_rowColorWithOpacity;
	
	CGFloat				minimumDesiredWidth;
	BOOL	 			desiredHeightPadding;

	NSArray				*draggedItems;
}

@property (readonly, nonatomic) NSInteger desiredHeight;
@property (readonly, nonatomic) NSInteger desiredWidth;

// Contact menu
@property (readonly, nonatomic) AIListObject *listObject;
@property (readonly, nonatomic) NSArray *arrayOfListObjects;
@property (readonly, nonatomic) NSArray *arrayOfListObjectsWithGroups;
@property (readonly, nonatomic) AIListContact *firstVisibleListContact;

// Contacts

/*!
 * @brief Index of the first visible list contact
 *
 * @result The index, or -1 if no list contact is visible
 */
@property (readonly, nonatomic) int indexOfFirstVisibleListContact;

- (void)setMinimumDesiredWidth:(CGFloat)inMinimumDesiredWidth;
- (void)setDesiredHeightPadding:(int)inPadding;

@end

@interface AIListOutlineView (AIListOutlineView_Drawing)

- (void)setWindowOpaque:(BOOL)opaque;

@property (readwrite, nonatomic, retain) NSColor *backgroundColor;
@property (readwrite, nonatomic, retain) NSColor *highlightColor;
@property (readwrite, nonatomic, retain) NSColor *alternatingRowColor;

// Shadows
- (void)setUpdateShadowsWhileDrawing:(BOOL)update;

// Backgrounds
- (void)setBackgroundImage:(NSImage *)inImage;
- (void)setBackgroundStyle:(AIBackgroundStyle)inBackgroundStyle;
- (void)setBackgroundOpacity:(CGFloat)opacity forWindowStyle:(AIContactListWindowStyle)windowStyle;
- (void)setBackgroundFade:(CGFloat)fade;

@end

/*!
 * @brief A tape measure for the list, laid against it while the program runs
 *
 * It was reported that entries are drawn on top of one another for about a
 * second, while an account signs on and its contacts arrive. It lasts too short
 * a time to catch by hand and the harness has never reproduced it, so this reads
 * out what the table and its views actually are at that moment instead.
 *
 * It answers one question: whether the rows are where the table says they should
 * be and hold what the table says they hold. If they are, the two names in one
 * line are old pixels nobody rubbed out, and the window being see through is the
 * reason. If they are not, it is the rows themselves that are wrong, and no
 * amount of redrawing will help.
 *
 * Nothing is written unless something is wrong, or unless it is asked for from
 * the Debug menu, and nothing at all happens unless debug logging is on.
 */
@interface AIListOutlineView (AIListProbe)

/*!
 * @brief Every contact list on screen, for a menu item that has no other handle on one
 */
+ (NSArray *)ai_listViewsOnScreen;

/*!
 * @brief Measure, and write the result down whether or not anything is wrong
 */
- (void)ai_logProbeAlways:(NSString *)occasion;

/*!
 * @brief Measure now and again shortly after, and write only what is wrong
 *
 * The later passes say whether the list heals itself, which is what was reported.
 * They are coalesced, so a hundred contacts arriving still measure twice.
 */
- (void)ai_scheduleProbes;

@end
