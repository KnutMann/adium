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

#import <Cocoa/Cocoa.h>

@class AISettingsNavigationController;

@protocol AISettingsNavigationControllerDelegate <NSObject>
@optional
/*!
 * @brief The stack changed, so whatever draws a back control should ask again
 */
- (void)settingsNavigationControllerDidChangeStack:(AISettingsNavigationController *)controller;
@end

/*!
 * @class AISettingsNavigationController
 * @brief One settings page at a time, with the sideways slide between them
 *
 * The drill down System Settings uses: a list of things, a chevron on each, and the thing's own
 * settings sliding in from the trailing edge. AppKit does the sliding itself through view controller
 * containment, which is what this is: a parent view controller with the pages as its children, and
 * -transitionFromViewController:toViewController:options: between them.
 *
 * What this class adds on top is the one thing containment does not cover here: the height. A
 * preferences pane is laid out by its window, which sets the width and takes whatever height the
 * pane reports, so this reports the height of whichever page is showing and follows it when that
 * page grows. During a slide it reports the taller of the two, so nothing is clipped while both are
 * on screen and the window does not jump twice.
 *
 * A pane hosting one of these has to keep it alive: AIModularPane knows only about a view.
 */
@interface AISettingsNavigationController : NSViewController {
	NSMutableArray	*pageControllers;
	BOOL			 transitioning;
}

@property (assign, nonatomic) id <AISettingsNavigationControllerDelegate> delegate;

/*!
 * @brief The page shown when nothing is pushed on top of it
 */
- (void)setRootViewController:(NSViewController *)rootController;

/*!
 * @brief Slide a page in from the trailing edge
 */
- (void)pushViewController:(NSViewController *)controller animated:(BOOL)animated;

/*!
 * @brief Slide the top page back out, if there is one under it
 */
- (void)popViewControllerAnimated:(BOOL)animated;

/*!
 * @brief Straight back to the root, without animating
 *
 * For the case where the pane is taken off screen underneath us and there is nothing to animate to.
 */
- (void)popToRootViewController;

- (NSViewController *)topViewController;
- (BOOL)canGoBack;

/*!
 * @brief Whether a slide between two pages is running right now
 *
 * A push and a pop both refuse to start while one is, so a host which acts on the stack by itself -
 * throwing a page away because what it described has changed on disk - has to wait for the slide to
 * end rather than reach into it. @c popToRootViewController does not refuse, and rearranging the
 * stack under a running slide leaves the container empty: the slide's own completion still takes
 * away the view it was sliding away from, which by then is the one showing.
 */
- (BOOL)isTransitioning;

/*!
 * @brief The showing page changed its own height
 */
- (void)noteContentHeightChanged;

@end
