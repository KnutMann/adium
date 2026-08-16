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


#import "AIContactListUserPictureMenuController.h"
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIContactControllerProtocol.h>
#import "AIStandardListWindowController.h"
#import "AIContactListImagePicker.h"
#import <Adium/AIAccount.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <AIUtilities/AIOSCompatibility.h>

#import <AIUtilities/IKRecentPicture.h> //10.5+, private
#import <AIUtilities/AIBundleAdditions.h>

#pragma mark AIContactListUserPictureMenuController

@interface AIContactListUserPictureMenuController ()

- (id)initWithNibName:(NSString *)nibName imagePicker:(AIContactListImagePicker *)picker;

// IKRecentPicture related
- (NSArray *)recentPictures;
- (NSMutableArray *)recentSmallPictures;

// Menu actions
- (void)choosePicture:(id)sender;
- (void)clearRecentPictures:(id)sender;

@end


@implementation AIContactListUserPictureMenuController

@synthesize menu, imageCollectionView;
@synthesize imagePicker, images;


+ (void)popUpMenuForImagePicker:(AIContactListImagePicker *)picker
{
	[[[self alloc] initWithNibName:@"ContactListChangeUserPictureMenu" imagePicker:picker] autorelease];
}

/*!
 * @brief Set-up and open the menu
 */
- (id)initWithNibName:(NSString *)nibName imagePicker:(AIContactListImagePicker *)picker
{
	/* AI_topLevelObjects was handed to the nib loader as the array to fill and was never created,
	 * so it stayed nil, nothing was collected into it, and the release below and the one in -dealloc
	 * both did nothing. The objects have been leaking since this was written.
	 *
	 * They still are, and on purpose. +popUpMenuForImagePicker: throws this controller into the
	 * autorelease pool the moment it has built the menu, so the menu outlives it by a wide margin.
	 * The unowned reference each top level object carries is the only thing keeping the menu on
	 * screen. Giving the array ownership of them, which is plainly what was meant here, would take
	 * the menu apart at the next drain.
	 */
	AI_topLevelObjects = [[[NSBundle mainBundle] ai_loadNibNamed:nibName owner:self] mutableCopy];

	if (AI_topLevelObjects) {
		
		[self setImagePicker:picker];
		[imagePicker setMaxSize:NSMakeSize(128.0f, 128.0f)];

		// Set-up collection view
		/* Deprecated grid properties, deliberately kept: this is the legacy cell-based
		 * collection view (itemPrototype + content bindings in the xib), which on current
		 * macOS runs with a nil collectionViewLayout and reads exactly these properties.
		 * Installing an NSCollectionViewGridLayout kills item creation (see the matching
		 * comment in AIImageCollectionView.m). */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		[imageCollectionView setMaxNumberOfColumns:5];
		[imageCollectionView setMaxNumberOfRows:2];
		[imageCollectionView setMaxItemSize:NSMakeSize(36.0f, 36.0f)];
#pragma clang diagnostic pop
		// Disable elastic scroll
		// Remove the check on 10.7+
		if ([[imageCollectionView enclosingScrollView] respondsToSelector:@selector(setVerticalScrollElasticity:)]) {
			[[imageCollectionView enclosingScrollView] setVerticalScrollElasticity:1]; // Swap 1 with NSScrollElasticityNone on 10.7+
		}
		
		NSMutableArray *pictures = [self recentSmallPictures];
		NSSize pictureSize = NSMakeSize(32.0f, 32.0f);
		
		// Resize pictures
		for (NSImage *picture in pictures) {
			[picture setSize:pictureSize];
		}
		
		if ([pictures count] < 10) {
			// Create an "empty" image, placeholder icon
			NSImage	*emptyPicture = [[NSImage alloc] initWithSize:pictureSize];
			
			[emptyPicture lockFocus];
			[[NSColor unemphasizedSelectedContentBackgroundColor] set];
			NSRectFill(NSMakeRect(0.0f, 0.0f, 32.0f, 32.0f));
			[emptyPicture unlockFocus];
			
			// Add placeholders to images
			for (NSUInteger i = [pictures count]; i < 10; ++i) {
				[pictures addObject:emptyPicture];
			}
			
			[emptyPicture release];
		}
		
		[self setImages:pictures];

		[menu popUpMenuPositioningItem:[menu itemAtIndex:0] atLocation:NSMakePoint(2.0f, -4.0f) inView:imagePicker];
	}
	
	return self;
}

- (void)dealloc
{
	[imagePicker release];
	[images release];
	[AI_topLevelObjects release];
	
	[super dealloc];
}

#pragma mark -

- (NSArray *)recentPictures
{
	NSArray *recentPictures = [(IKPictureTakerRecentPictureRepository *)[IKPictureTakerRecentPictureRepository recentRepository] recentPictures];
    
    if (recentPictures.count > 10)
        return [recentPictures subarrayWithRange:NSMakeRange(0, 10)];
    else
        return recentPictures;
}

/*!
 * @brief Small icons for recent pictures
 */
- (NSMutableArray *)recentSmallPictures
{
    NSArray *recentPictures = [self recentPictures];

    NSMutableArray *array = [[recentPictures valueForKey:@"smallIcon"] mutableCopy];
    for (NSInteger i = (array.count-1); i >= 0; i--) {
        id imageOrNull = [array objectAtIndex:i];

        /* Not all icons have a small icon */
        if (imageOrNull == [NSNull null]) {
            IKPictureTakerRecentPicture *picture = [recentPictures objectAtIndex:i];
            
            [array replaceObjectAtIndex:i
                             withObject:[picture editedImage]];
        }
    }
    
    return [array autorelease];
}

#pragma mark - NSMenu delegate

- (void)menuNeedsUpdate:(NSMenu *)aMenu
{
	NSMenuItem *menuItem;
	
	menuItem = [aMenu itemAtIndex:0];
	[menuItem setTitle:AILocalizedString(@"Recent Icons:", "Label at the top of the recent icons picker shown in the contact list")];
	
	menuItem = [[NSMenuItem alloc] initWithTitle:[AILocalizedString(@"Choose Icon", nil) stringByAppendingEllipsis]
										  target:self
										  action:@selector(choosePicture:)
								   keyEquivalent:@""];
	
	[aMenu addItem:menuItem];
	[menuItem release];
	
	menuItem = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Clear Recent Pictures", nil)
										  target:self
										  action:@selector(clearRecentPictures:)
								   keyEquivalent:@""];
	
	[aMenu addItem:menuItem];
	[menuItem release];
}

#pragma mark - AIImageCollectionView delegate

- (BOOL)imageCollectionView:(AIImageCollectionView *)collectionView shouldHighlightItemAtIndex:(NSUInteger)anIndex
{	
	return (anIndex < [[self recentPictures] count]);
}

- (BOOL)imageCollectionView:(AIImageCollectionView *)imageCollectionView shouldSelectItemAtIndex:(NSUInteger)anIndex
{
	return (anIndex < [[self recentPictures] count]);
}

- (void)imageCollectionView:(AIImageCollectionView *)imageCollectionView didSelectItemAtIndex:(NSUInteger)anIndex
{
	NSArray *recentPictures = [self recentPictures];
	
	if (anIndex < [recentPictures count]) {
		id recentPicture = [recentPictures objectAtIndex:anIndex];
		NSData *imageData = nil;

        /* XXX Check for and use the cropped image? */
		if ([recentPicture respondsToSelector:@selector(smallIcon)] && ([recentPicture smallIcon] != [NSNull null])) {
			imageData = [[recentPicture smallIcon] bestRepresentationByType];
		} else if ([recentPicture respondsToSelector:@selector(originalImagePath)]) {
			imageData = [NSData dataWithContentsOfFile:[recentPicture originalImagePath]];
		}
		
		// Notify as if the image had been selected in the picker
		[[[self imagePicker] delegate] imageViewWithImagePicker:imagePicker
										   didChangeToImageData:imageData];

		// Now pass on the actual recent picture for use if possible
		[[self imagePicker] setRecentPictureAsImageInput:recentPicture];
	}
	
	[menu cancelTracking];
}

#pragma mark - Menu Actions

- (void)choosePicture:(id)sender
{
	[imagePicker showImagePicker:nil];
}

- (void)clearRecentPictures:(id)sender
{
	[[IKPictureTakerRecentPictureRepository recentRepository] clearRecents:YES];
}

@end
