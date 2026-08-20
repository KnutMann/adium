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

#import "AIMessageViewEmoticonsController.h"
#import <Adium/AIEmoticonControllerProtocol.h>
#import <Adium/AIEmoticonPack.h>
#import <Adium/AIEmoticon.h>
#import <Adium/AIMessageEntryTextView.h>
#import <AIUtilities/AIBundleAdditions.h>
#import <AIUtilities/AIImageDrawingAdditions.h>

//Padding between the smiley button and the opened menu
#define MENU_PADDING    15

@interface AIMessageViewEmoticonsController ()
- (id)initWithNibName:(NSString *)nibName textView:(AIMessageEntryTextView *)aView atPoint:(NSPoint)aPoint;
@end

@implementation AIMessageViewEmoticonsController

@synthesize menu, emoticonsCollectionView, emoticonTitleLabel, emoticonSymbolLabel, alignmentView;
@synthesize textView;
@synthesize emoticons, emoticonTitles, emoticonSymbols;

+ (void)popUpMenuForTextView:(AIMessageEntryTextView *)aTextView atPoint:(NSPoint)aPoint
{
	/* The menu runs synchronously inside the initializer, so by the time the
	 * autorelease pool drains, tracking is over and the controller may go. The
	 * nib's top level objects are handed out unowned (see AIBundleAdditions)
	 * and stay behind; that mirrors the user picture menu, which lives the
	 * same way. */
	[[[self alloc] initWithNibName:@"MessageViewEmoticonsMenu" textView:aTextView atPoint:aPoint] autorelease];
}

/*!
 * @brief Set up and open the menu
 */
- (id)initWithNibName:(NSString *)nibName textView:(AIMessageEntryTextView *)aView atPoint:(NSPoint)aPoint
{
	if (!(self = [super init]))
		return nil;

	if ([NSBundle ai_loadNibNamed:nibName owner:self]) {
		[self setTextView:aView];

		// Set up the collection view
		/* Deprecated grid properties, deliberately kept: this is the legacy cell-based
		 * collection view (itemPrototype + content bindings in the xib), which on current
		 * macOS runs with a nil collectionViewLayout and reads exactly these properties.
		 * Installing an NSCollectionViewGridLayout kills item creation (see the matching
		 * comment in AIImageCollectionView.m). */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		[emoticonsCollectionView setMaxNumberOfColumns:10];
		[emoticonsCollectionView setMinItemSize:NSMakeSize(20.0f, 20.0f)];
		[emoticonsCollectionView setMaxItemSize:NSMakeSize(20.0f, 20.0f)];
#pragma clang diagnostic pop
		[emoticonsCollectionView setHighlightStyle:AIImageCollectionViewHighlightBackgroundStyle];
		[emoticonsCollectionView setHighlightSize:0.0f];
		[emoticonsCollectionView setHighlightCornerRadius:3.0f];

		// Gather the emoticons of every active pack
		NSMutableArray *icons = [NSMutableArray array];
		NSMutableArray *titles = [NSMutableArray array];
		NSMutableArray *symbols = [NSMutableArray array];

		for (AIEmoticonPack *pack in [adium.emoticonController activeEmoticonPacks]) {
			//Pad to the next full row so each pack starts on a row of its own
			while (icons.count % 10 != 0) {
				[icons addObject:@""];
				[titles addObject:@""];
				[symbols addObject:@""];
			}

			for (AIEmoticon *emoticon in [pack enabledEmoticons]) {
				[icons addObject:[[emoticon image] imageByScalingForMenuItem]];
				[titles addObject:[emoticon name]];
				[symbols addObject:[[emoticon textEquivalents] objectAtIndex:0]];
			}
		}

		[self setEmoticons:icons];
		[self setEmoticonTitles:titles];
		[self setEmoticonSymbols:symbols];

		NSSize alignmentSize = NSMakeSize(NSWidth([alignmentView frame]), ceil([icons count] / 10.0) * 20.0);
		[alignmentView setFrameSize:alignmentSize];
		[alignmentView setNeedsDisplay:YES];

		// The point names the button's top right corner; the menu hangs to its left
		aPoint.x -= [menu size].width;

		/* Keep the menu clear of the button: normally it opens just above the point,
		 * but near the bottom of the screen Cocoa would flip it up over the button,
		 * so in that case place it below by hand. */
		NSPoint windowPoint = [[aView superview] convertPoint:aPoint toView:nil];
		NSPoint screenPoint = [[aView window] convertPointToScreen:windowPoint];
		if (screenPoint.y - MENU_PADDING - [menu size].height < 20) {
			aPoint.y = aPoint.y - MENU_PADDING - [menu size].height;
		} else {
			aPoint.y += MENU_PADDING / 2;
		}

		[menu popUpMenuPositioningItem:[menu itemAtIndex:0]
							atLocation:aPoint
								inView:[aView superview]];
	}

	return self;
}

- (void)dealloc
{
	[textView release];
	[emoticons release];
	[emoticonTitles release];
	[emoticonSymbols release];

	[super dealloc];
}

#pragma mark - AIImageCollectionView delegate

- (BOOL)imageCollectionView:(AIImageCollectionView *)collectionView shouldHighlightItemAtIndex:(NSUInteger)anIndex
{
	if (anIndex >= [emoticons count])
		return NO;
	if ([[emoticonSymbols objectAtIndex:anIndex] isEqualToString:@""])
		return NO;
	return YES;
}

- (void)imageCollectionView:(AIImageCollectionView *)collectionView didHighlightItemAtIndex:(NSUInteger)anIndex
{
	if (anIndex < [emoticons count]) {
		// Update title and symbol (text equivalent)
		[emoticonTitleLabel setStringValue:[emoticonTitles objectAtIndex:anIndex]];
		[emoticonSymbolLabel setStringValue:[emoticonSymbols objectAtIndex:anIndex]];
	}
}

- (BOOL)imageCollectionView:(AIImageCollectionView *)imageCollectionView shouldSelectItemAtIndex:(NSUInteger)anIndex
{
	if (anIndex >= [emoticons count])
		return NO;
	if ([[emoticonSymbols objectAtIndex:anIndex] isEqualToString:@""])
		return NO;
	return YES;
}

- (void)imageCollectionView:(AIImageCollectionView *)imageCollectionView didSelectItemAtIndex:(NSUInteger)anIndex
{
	if (anIndex < [emoticons count]) {
		NSString *emoticonString = [emoticonSymbols objectAtIndex:anIndex];

		if (emoticonString && [textView isEditable])
			[textView insertText:emoticonString replacementRange:[textView selectedRange]];
	}

	[menu cancelTracking];
}

- (void)menuDidClose:(NSMenu *)inMenu
{
	[menu setDelegate:nil];
	[emoticonsCollectionView setDelegate:nil];
}

@end
