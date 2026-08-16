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

#import "AISettingsNavigationController.h"

@interface AISettingsNavigationView : NSView {
	__unsafe_unretained AISettingsNavigationController *owner;	//Not retained: it owns this view
}
@property (assign, nonatomic) AISettingsNavigationController *owner;
@end

@interface AISettingsNavigationController ()
- (void)layoutShowingPage;
- (void)pageFrameChanged:(NSNotification *)notification;
- (void)observePage:(NSViewController *)controller;
- (void)stopObservingPage:(NSViewController *)controller;
- (void)notifyStackChanged;
@end

@implementation AISettingsNavigationController

@synthesize delegate;

- (id)init
{
	if ((self = [super initWithNibName:nil bundle:nil])) {
		pageControllers = [[NSMutableArray alloc] init];
	}

	return self;
}

- (void)dealloc
{
	for (NSViewController *controller in pageControllers)
		[self stopObservingPage:controller];
}

- (void)loadView
{
	AISettingsNavigationView *container = [[AISettingsNavigationView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 100.0f, 100.0f)];

	[container setOwner:self];
	[container setAutoresizingMask:NSViewWidthSizable];
	/* So a page sliding in from beyond the trailing edge is not seen until it arrives, and the one
	 * leaving is not seen after it has gone. */
	[container setWantsLayer:YES];
	[[container layer] setMasksToBounds:YES];

	[self setView:container];
}

//The stack ------------------------------------------------------------------------------------------------------------
#pragma mark The stack

- (NSViewController *)topViewController
{
	return [pageControllers lastObject];
}

- (BOOL)canGoBack
{
	return ([pageControllers count] > 1);
}

- (void)setRootViewController:(NSViewController *)rootController
{
	if (!rootController)
		return;

	for (NSViewController *controller in [pageControllers copy]) {
		[self stopObservingPage:controller];
		[[controller view] removeFromSuperview];
		[controller removeFromParentViewController];
	}
	[pageControllers removeAllObjects];

	[self addChildViewController:rootController];
	[pageControllers addObject:rootController];
	[[self view] addSubview:[rootController view]];
	[self observePage:rootController];

	[self layoutShowingPage];
	[self notifyStackChanged];
}

- (void)pushViewController:(NSViewController *)controller animated:(BOOL)animated
{
	NSViewController *from = [self topViewController];

	if (!controller || !from || transitioning)
		return;

	[self addChildViewController:controller];
	[pageControllers addObject:controller];
	[self observePage:controller];

	/* Sized before it is shown, so the height below is the height it will really have and the
	 * container does not have to change size again once the slide is over. */
	CGFloat width = NSWidth([[self view] frame]);
	[[controller view] setFrameSize:NSMakeSize(width, NSHeight([[controller view] frame]))];

	/* The taller of the two for as long as both are on screen. Growing once before the slide and
	 * shrinking once after it beats growing a little on every frame, which would send the window
	 * through a full pane layout each time. */
	CGFloat tallest = MAX(NSHeight([[from view] frame]), NSHeight([[controller view] frame]));
	[[self view] setFrameSize:NSMakeSize(width, tallest)];

	if (!animated) {
		[[from view] removeFromSuperview];
		[[self view] addSubview:[controller view]];
		[self layoutShowingPage];
		[self notifyStackChanged];
		return;
	}

	transitioning = YES;
	[self notifyStackChanged];

	[self transitionFromViewController:from
					  toViewController:controller
							   options:NSViewControllerTransitionSlideForward
					 completionHandler:^{
		transitioning = NO;
		[[from view] removeFromSuperview];
		[self layoutShowingPage];
	}];
}

- (void)popViewControllerAnimated:(BOOL)animated
{
	if (![self canGoBack] || transitioning)
		return;

	NSViewController *from = [self topViewController];
	NSViewController *to = [pageControllers objectAtIndex:([pageControllers count] - 2)];

	CGFloat width = NSWidth([[self view] frame]);
	[[to view] setFrameSize:NSMakeSize(width, NSHeight([[to view] frame]))];
	[[self view] setFrameSize:NSMakeSize(width, MAX(NSHeight([[from view] frame]),
													NSHeight([[to view] frame])))];

	if (!animated) {
		[[from view] removeFromSuperview];
		[[self view] addSubview:[to view]];
		[self stopObservingPage:from];
		[pageControllers removeLastObject];
		[from removeFromParentViewController];
		[self layoutShowingPage];
		[self notifyStackChanged];
		return;
	}

	transitioning = YES;

	[self transitionFromViewController:from
					  toViewController:to
							   options:NSViewControllerTransitionSlideBackward
					 completionHandler:^{
		transitioning = NO;
		[[from view] removeFromSuperview];
		[self stopObservingPage:from];
		[pageControllers removeObjectIdenticalTo:from];
		[from removeFromParentViewController];
		[self layoutShowingPage];
		[self notifyStackChanged];
	}];
}

- (void)popToRootViewController
{
	if (![self canGoBack])
		return;

	NSViewController *root = [pageControllers objectAtIndex:0];

	for (NSViewController *controller in [pageControllers copy]) {
		if (controller == root)
			continue;

		[self stopObservingPage:controller];
		[[controller view] removeFromSuperview];
		[controller removeFromParentViewController];
		[pageControllers removeObjectIdenticalTo:controller];
	}

	transitioning = NO;
	if (![[root view] superview])
		[[self view] addSubview:[root view]];

	[self layoutShowingPage];
	[self notifyStackChanged];
}

//Height ---------------------------------------------------------------------------------------------------------------
#pragma mark Height

- (void)noteContentHeightChanged
{
	[self layoutShowingPage];
}

/*!
 * @brief Give the showing page our width and take its height
 *
 * Nothing while a slide is running: both pages are on screen then, the container is already as tall
 * as the taller of them, and resizing underneath a running animation is how a page ends up half a
 * width from where it should be.
 */
- (void)layoutShowingPage
{
	NSViewController *top = [self topViewController];
	if (!top || transitioning)
		return;

	NSView *container = [self view];
	NSView *page = [top view];
	CGFloat width = NSWidth([container frame]);

	if (fabs(NSWidth([page frame]) - width) > 0.5f)
		[page setFrameSize:NSMakeSize(width, NSHeight([page frame]))];

	[page setFrameOrigin:NSZeroPoint];

	CGFloat height = NSHeight([page frame]);
	if (fabs(NSHeight([container frame]) - height) > 0.5f)
		[container setFrameSize:NSMakeSize(width, height)];
}

- (void)observePage:(NSViewController *)controller
{
	[[controller view] setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(pageFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:[controller view]];
}

- (void)stopObservingPage:(NSViewController *)controller
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSViewFrameDidChangeNotification
												  object:[controller view]];
}

/*!
 * @brief A page changed its own height, a list gained a row or a label wrapped
 */
- (void)pageFrameChanged:(NSNotification *)notification
{
	if ([notification object] == [[self topViewController] view])
		[self layoutShowingPage];
}

- (void)notifyStackChanged
{
	if ([delegate respondsToSelector:@selector(settingsNavigationControllerDidChangeStack:)])
		[delegate settingsNavigationControllerDidChangeStack:self];
}

@end

@implementation AISettingsNavigationView

@synthesize owner;

/*!
 * @brief y grows downwards, like the form views this holds
 */
- (BOOL)isFlipped
{
	return YES;
}

/*!
 * @brief The window sets our width; the showing page decides our height
 *
 * Same arrangement the settings form has with its host: the height is not the caller's to choose, so
 * a new width is taken and then answered with whatever the page turns out to need.
 */
- (void)setFrameSize:(NSSize)newSize
{
	BOOL widthChanged = (fabs(newSize.width - NSWidth([self frame])) > 0.5f);

	[super setFrameSize:newSize];

	if (widthChanged)
		[owner layoutShowingPage];
}

@end
