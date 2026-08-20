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

#import <AIUtilities/AIImageCollectionView.h>

@class AIMessageEntryTextView;

/*!
 * @class AIMessageViewEmoticonsController
 * @brief The emoticon menu behind the smiley button in the message entry view
 *
 * Opens a contextual (pop-up) menu showing the enabled emoticons of every
 * active pack; picking one inserts its text equivalent into the entry view.
 */
@interface AIMessageViewEmoticonsController : NSObject <AIImageCollectionViewDelegate, NSMenuDelegate> {
	IBOutlet NSMenu *menu;
	IBOutlet AIImageCollectionView *emoticonsCollectionView;
	IBOutlet NSTextField *emoticonTitleLabel;
	IBOutlet NSTextField *emoticonSymbolLabel;
	IBOutlet NSView *alignmentView;

	AIMessageEntryTextView *textView;

	NSArray *emoticons;
	NSArray *emoticonTitles;
	NSArray *emoticonSymbols;
}

@property (assign) IBOutlet NSMenu *menu;
@property (assign) IBOutlet AIImageCollectionView *emoticonsCollectionView;
@property (assign) IBOutlet NSTextField *emoticonTitleLabel;
@property (assign) IBOutlet NSTextField *emoticonSymbolLabel;
@property (assign) IBOutlet NSView *alignmentView;

@property (retain) AIMessageEntryTextView *textView;

@property (copy) NSArray *emoticons;
@property (copy) NSArray *emoticonTitles;
@property (copy) NSArray *emoticonSymbols;

/*!
 * @brief Open the menu
 *
 * @param textView	The entry view the chosen emoticon goes into
 * @param aPoint	Near the smiley button, in the coordinates of the entry view's superview
 */
+ (void)popUpMenuForTextView:(AIMessageEntryTextView *)textView atPoint:(NSPoint)aPoint;

@end
