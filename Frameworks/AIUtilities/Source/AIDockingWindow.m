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

#import "AIDockingWindow.h"
#import "AIEventAdditions.h"
#import <AIUtilities/AIOSCompatibility.h>

#define WINDOW_DOCKING_DISTANCE 	12	//Distance in pixels before the window is snapped to an edge
#define IGNORED_X_RESISTS			3
#define IGNORED_Y_RESISTS			3

/* The snapping itself, and the little memory it needs, kept out of both classes so that
 * the window and the panel are the same behaviour rather than two copies of it. */
typedef struct {
	NSRect			oldWindowFrame;
	unsigned int	resisted_XMotion;
	unsigned int	resisted_YMotion;
	BOOL			alreadyMoving;
	BOOL			dockingEnabled;
} AIDockingState;

static void AIDockingStateInit(AIDockingState *state);
static void AIDockingWindowDidMove(NSWindow *window, AIDockingState *state);
static NSRect AIDockedFrame(NSRect windowFrame, NSRect screenFrame);

@interface AIDockingWindow ()
- (void)_initDockingWindow;
@end

@interface AIDockingPanel ()
- (void)_initDockingPanel;
@end

@interface NSWindow (AIUNDOCUMENTED)
- (void)_toolbarPillButtonClicked:(id)sender;
@end

@interface NSObject (FriendsDontLetFriendsUsePrivateNSWindowDelegateMethods)
- (void)windowDidToggleToolbarShown:(id)sender;
@end

@implementation AIDockingWindow

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backingStoreType defer:(BOOL)flag
{
	if ((self = [super initWithContentRect:contentRect styleMask:style backing:backingStoreType defer:flag])) {
		[self _initDockingWindow];
	}

	return self;
}
- (id)initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super initWithCoder:aDecoder])) {
		[self _initDockingWindow];
	}

	return self;
}
- (id)init
{
	if ((self = [super init])) {
		[self _initDockingWindow];
	}
	return self;
}

//Observe window movement
- (void)_initDockingWindow
{
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(windowDidMove:)
												 name:NSWindowDidMoveNotification 
											   object:self];
	resisted_XMotion = 0;
	resisted_YMotion = 0;
	oldWindowFrame = NSMakeRect(0,0,0,0);
	alreadyMoving = NO;
	dockingEnabled = YES;
	
	// Disable Lion windows restore feature
	// XXX - Remove the check on 10.7+
	if ([self respondsToSelector:@selector(setRestorable:)]) {
        [self setRestorable:NO]; // Remove on UI rewrite
    }
}

//Stop observing movement
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSWindowDidMoveNotification
												  object:self];
}

//Watch the window move.  If it gets near an edge, dock it to that edge
- (void)windowDidMove:(NSNotification *)notification
{
	AIDockingState state = { oldWindowFrame, resisted_XMotion, resisted_YMotion, alreadyMoving, dockingEnabled };
	AIDockingWindowDidMove(self, &state);
	oldWindowFrame = state.oldWindowFrame;
	resisted_XMotion = state.resisted_XMotion;
	resisted_YMotion = state.resisted_YMotion;
}


- (void)toggleToolbarShown:(id)sender
{
	[super toggleToolbarShown:sender];
	
	if ([self delegate] && [[self delegate] respondsToSelector:@selector(windowDidToggleToolbarShown:)]) {
		[[self delegate] performSelector:@selector(windowDidToggleToolbarShown:)
							  withObject:self];
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:AIWindowToolbarDidToggleVisibility
														object:self];
}

- (void)_toolbarPillButtonClicked:(id)sender
{
	[super _toolbarPillButtonClicked:sender];
	
	if ([self delegate] && [[self delegate] respondsToSelector:@selector(windowDidToggleToolbarShown:)]) {
		[[self delegate] performSelector:@selector(windowDidToggleToolbarShown:)
							  withObject:self];
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:AIWindowToolbarDidToggleVisibility
														object:self];
}

- (void)setDockingEnabled:(BOOL)inEnabled
{
	dockingEnabled = inEnabled;
}

@end

/* --- The snapping, shared by both --------------------------------------------------- */

static void AIDockingStateInit(AIDockingState *state)
{
	state->oldWindowFrame = NSMakeRect(0, 0, 0, 0);
	state->resisted_XMotion = 0;
	state->resisted_YMotion = 0;
	state->alreadyMoving = NO;
	state->dockingEnabled = YES;
}

//Dock the passed window frame if it's close enough to the screen edges
static NSRect AIDockedFrame(NSRect windowFrame, NSRect screenFrame)
{
	//Left
	if (fabs(NSMinX(windowFrame) - NSMinX(screenFrame)) < WINDOW_DOCKING_DISTANCE) {
		windowFrame.origin.x = screenFrame.origin.x;
	}

	//Bottom
	if (fabs(NSMinY(windowFrame) - NSMinY(screenFrame)) < WINDOW_DOCKING_DISTANCE) {
		windowFrame.origin.y = screenFrame.origin.y;
	}

	//Right
	if (fabs(NSMaxX(windowFrame) - NSMaxX(screenFrame)) < WINDOW_DOCKING_DISTANCE) {
		windowFrame.origin.x -= NSMaxX(windowFrame) - NSMaxX(screenFrame);
	}

	//Top
	if (fabs(NSMaxY(windowFrame) - NSMaxY(screenFrame)) < WINDOW_DOCKING_DISTANCE) {
		windowFrame.origin.y -= NSMaxY(windowFrame) - NSMaxY(screenFrame);
	}

	return windowFrame;
}

static void AIDockingWindowDidMove(NSWindow *window, AIDockingState *state)
{
	//Our setFrame call below will cause a re-entry into this function, we must guard against this
	if (state->alreadyMoving || !state->dockingEnabled || [NSEvent shiftKey])
		return;

	state->alreadyMoving = YES;

	//Attempt to dock this window to the visible frame first, and then to the screen frame
	NSRect	newWindowFrame = [window frame];
	NSRect	dockedWindowFrame = AIDockedFrame(newWindowFrame, [[window screen] visibleFrame]);
	dockedWindowFrame = AIDockedFrame(dockedWindowFrame, [[window screen] frame]);

	//If the window wants to dock, animate it into place
	if (!NSEqualRects(newWindowFrame, dockedWindowFrame)) {

		if (!NSIsEmptyRect(state->oldWindowFrame)) {
			BOOL	user_XMovingLeft = ((state->oldWindowFrame.origin.x - newWindowFrame.origin.x) >= 0);
			BOOL	docking_XMovingLeft = ((newWindowFrame.origin.x - dockedWindowFrame.origin.x) >= 0);

			//If the user is trying to move in the opposite X direction as the docking movement, use the user's movement
			if ((user_XMovingLeft && !docking_XMovingLeft) || (!user_XMovingLeft && docking_XMovingLeft)) {
				if (state->resisted_XMotion <= IGNORED_X_RESISTS) {
					dockedWindowFrame.origin.x = newWindowFrame.origin.x;
					state->resisted_XMotion = 0;
				} else {
					state->resisted_XMotion++;
				}
			} else {
				//They went with the flow
				state->resisted_XMotion = 0;
			}

			BOOL	user_YMovingDown = ((state->oldWindowFrame.origin.y - newWindowFrame.origin.y) >= 0);
			BOOL	docking_YMovingDown = ((newWindowFrame.origin.y - dockedWindowFrame.origin.y) >= 0);

			//If the user is trying to move in the opposite Y direction as the docking movement, use the user's movement
			if ((user_YMovingDown && !docking_YMovingDown) || (!user_YMovingDown && docking_YMovingDown)) {
				if (state->resisted_YMotion <= IGNORED_Y_RESISTS) {
					dockedWindowFrame.origin.y = newWindowFrame.origin.y;
					state->resisted_YMotion = 0;
				} else {
					state->resisted_YMotion++;
				}
			} else {
				state->resisted_YMotion = 0;
			}
		}

		[window setFrame:dockedWindowFrame display:YES animate:YES];
		state->oldWindowFrame = dockedWindowFrame;

	} else {
		state->resisted_XMotion = 0;
		state->resisted_YMotion = 0;
		state->oldWindowFrame = NSMakeRect(0, 0, 0, 0);
	}

	state->alreadyMoving = NO; //Clear the guard, we are now safe
}

/* --- The same window with the short title bar ---------------------------------------- */

@implementation AIDockingPanel

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backingStoreType defer:(BOOL)flag
{
	if ((self = [super initWithContentRect:contentRect styleMask:style backing:backingStoreType defer:flag]))
		[self _initDockingPanel];

	return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super initWithCoder:aDecoder]))
		[self _initDockingPanel];

	return self;
}

- (id)init
{
	if ((self = [super init]))
		[self _initDockingPanel];

	return self;
}

- (void)_initDockingPanel
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(windowDidMove:)
												 name:NSWindowDidMoveNotification
											   object:self];

	AIDockingState state;
	AIDockingStateInit(&state);
	oldWindowFrame = state.oldWindowFrame;
	resisted_XMotion = state.resisted_XMotion;
	resisted_YMotion = state.resisted_YMotion;
	alreadyMoving = state.alreadyMoving;
	dockingEnabled = state.dockingEnabled;

	[self setRestorable:NO];

	/* A utility panel takes itself away when the application is deactivated. For an
	 * inspector that is the point; for the contact list it would mean the list vanishes
	 * every time somebody clicks another application. */
	[self setHidesOnDeactivate:NO];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
												   name:NSWindowDidMoveNotification
												 object:self];
}

- (void)windowDidMove:(NSNotification *)notification
{
	AIDockingState state = { oldWindowFrame, resisted_XMotion, resisted_YMotion, alreadyMoving, dockingEnabled };
	AIDockingWindowDidMove(self, &state);
	oldWindowFrame = state.oldWindowFrame;
	resisted_XMotion = state.resisted_XMotion;
	resisted_YMotion = state.resisted_YMotion;
}

/* Panels decline this, and the contact list is the only window Adium has open much of the
 * time; without it the application would have no main window at all. */
- (BOOL)canBecomeMainWindow
{
	return YES;
}

- (void)setDockingEnabled:(BOOL)inEnabled
{
	dockingEnabled = inEnabled;
}

@end
