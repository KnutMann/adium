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

#import "AIJingleCallWindowController.h"

#import <Adium/ESDebugAILog.h>
#import <AIUtilities/AIStringUtilities.h>
#import "AIJingleVideoView.h"

#import <WebRTC/WebRTC.h>

#define BAR_HEIGHT		56.0
#define AUDIO_WIDTH		360.0
#define VIDEO_WIDTH		640.0
#define VIDEO_HEIGHT	480.0
#define PREVIEW_WIDTH	160.0
#define PREVIEW_HEIGHT	120.0
#define MARGIN			12.0

@implementation AIJingleCallWindowController {
	AIJingleCallController *call;
	NSString *displayName;

	NSTextField *statusLabel;
	NSButton *hangUpButton;
	NSView *stage;						//where the pictures go, once there are any
	AIJingleVideoView *remoteView;
	AIJingleVideoView *previewView;
	NSMutableArray<RTCVideoTrack *> *remoteTracks;	//held, or the renderer goes with them

	NSTimer *durationTimer;
	NSDate *connectedSince;
	BOOL ended;
}

- (id)initWithCallController:(AIJingleCallController *)controller displayName:(NSString *)inDisplayName
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, AUDIO_WIDTH, BAR_HEIGHT)
												   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
															  NSWindowStyleMaskMiniaturizable)
													 backing:NSBackingStoreBuffered
													   defer:NO];

	if ((self = [super initWithWindow:window])) {
		call = controller;
		displayName = [inDisplayName copy];
		remoteTracks = [NSMutableArray array];

		[window setTitle:[NSString stringWithFormat:AILocalizedString(@"Call with %@", "Title of a call window; %@ is the contact"), displayName]];
		[window setReleasedWhenClosed:NO];
		[window setDelegate:self];

		NSView *content = [window contentView];

		statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
		[statusLabel setEditable:NO];
		[statusLabel setSelectable:NO];
		[statusLabel setBezeled:NO];
		[statusLabel setDrawsBackground:NO];
		[statusLabel setFont:[NSFont systemFontOfSize:13.0]];
		[statusLabel setTextColor:[NSColor secondaryLabelColor]];
		/* A call that reached us is not one we are placing: saying "Calling" at
		 * somebody who just answered their phone reads as nonsense. */
		[statusLabel setStringValue:(controller.machine.isInitiator ?
			AILocalizedString(@"Calling…", "State of a call that was just started") :
			AILocalizedString(@"Connecting…", "State of an answered call while the media is being set up"))];
		[statusLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
		[content addSubview:statusLabel];

		hangUpButton = [NSButton buttonWithTitle:AILocalizedString(@"Hang Up", "Button ending a call")
										  target:self
										  action:@selector(hangUp:)];
		[hangUpButton setBezelStyle:NSBezelStyleRounded];
		[hangUpButton setKeyEquivalent:@"\e"];
		[hangUpButton setTranslatesAutoresizingMaskIntoConstraints:NO];
		[content addSubview:hangUpButton];

		[NSLayoutConstraint activateConstraints:@[
			[statusLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:MARGIN + 2.0],
			[statusLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-(BAR_HEIGHT / 2.0 - 9.0)],
			[hangUpButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-MARGIN],
			[hangUpButton.centerYAnchor constraintEqualToAnchor:statusLabel.centerYAnchor],
			[statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:hangUpButton.leadingAnchor constant:-MARGIN],
		]];

		//Our own camera, when this call sends one, is worth seeing from the start
		if (controller.localVideoTrack)
			[self growStageIfNeeded];

		[window center];
		[window makeKeyAndOrderFront:nil];
	}

	return self;
}

//The stage --------------------------------------------------------------------------------------
#pragma mark The stage

/*! @brief Give the window its picture area, once; safe to ask again */
- (void)growStageIfNeeded
{
	if (stage)
		return;

	NSWindow *window = [self window];
	NSView *content = [window contentView];

	NSRect frame = [window frame];
	NSRect grown = [window frameRectForContentRect:NSMakeRect(0, 0, VIDEO_WIDTH, VIDEO_HEIGHT + BAR_HEIGHT)];
	grown.origin.x = NSMidX(frame) - NSWidth(grown) / 2.0;
	grown.origin.y = NSMaxY(frame) - NSHeight(grown);
	[window setFrame:grown display:YES animate:YES];

	stage = [[NSView alloc] initWithFrame:NSZeroRect];
	[stage setWantsLayer:YES];
	[[stage layer] setBackgroundColor:[[NSColor blackColor] CGColor]];
	[stage setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:stage];

	[NSLayoutConstraint activateConstraints:@[
		[stage.topAnchor constraintEqualToAnchor:content.topAnchor],
		[stage.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
		[stage.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
		[stage.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-BAR_HEIGHT],
	]];

	if (call.localVideoTrack) {
		previewView = [[AIJingleVideoView alloc] initWithFrame:NSZeroRect];
		[previewView setTranslatesAutoresizingMaskIntoConstraints:NO];
		[stage addSubview:previewView];
		[NSLayoutConstraint activateConstraints:@[
			[previewView.trailingAnchor constraintEqualToAnchor:stage.trailingAnchor constant:-MARGIN],
			[previewView.bottomAnchor constraintEqualToAnchor:stage.bottomAnchor constant:-MARGIN],
			[previewView.widthAnchor constraintEqualToConstant:PREVIEW_WIDTH],
			[previewView.heightAnchor constraintEqualToConstant:PREVIEW_HEIGHT],
		]];
		[call.localVideoTrack addRenderer:previewView];
	}
}

- (void)attachRemoteVideoTrack:(RTCVideoTrack *)track
{
	[self growStageIfNeeded];

	/* Held for as long as the window lives.
	 *
	 * TRAP, and it cost an evening of black pictures: a receiver hands out a new
	 * wrapper around its track every time it is asked, and a renderer is attached
	 * to the wrapper. Let the wrapper go and it takes the renderer with it, so the
	 * frames arrive at a connection nobody is listening to any more, which looks
	 * from the outside exactly like a decoder that produces nothing. Our own
	 * camera never showed this because the controller holds its track. */
	[remoteTracks addObject:track];

	if (remoteView) {
		//A second track: hang the same view on it too rather than choosing blindly
		AILogWithSignature(@"also attaching renderer to remote track %@", track.trackId);
		[track addRenderer:remoteView];
		return;
	}

	remoteView = [[AIJingleVideoView alloc] initWithFrame:NSZeroRect];
	[remoteView setTranslatesAutoresizingMaskIntoConstraints:NO];
	[stage addSubview:remoteView positioned:NSWindowBelow relativeTo:previewView];
	[NSLayoutConstraint activateConstraints:@[
		[remoteView.topAnchor constraintEqualToAnchor:stage.topAnchor],
		[remoteView.leadingAnchor constraintEqualToAnchor:stage.leadingAnchor],
		[remoteView.trailingAnchor constraintEqualToAnchor:stage.trailingAnchor],
		[remoteView.bottomAnchor constraintEqualToAnchor:stage.bottomAnchor],
	]];
	AILogWithSignature(@"attaching renderer to remote track %@ (enabled=%d, state=%ld)",
					   track.trackId, track.isEnabled, (long)track.readyState);
	[track addRenderer:remoteView];
	[self countWhatIsDrawn:10];
}

/*!
 * @brief Say what each view has actually drawn
 *
 * A black rectangle can mean a view that never received a frame or one that
 * received them and drew nothing; the counters tell those apart, and the
 * decoder's own count in the call log says whether frames existed at all.
 */
- (void)countWhatIsDrawn:(NSInteger)triesLeft
{
	if (triesLeft <= 0 || ended)
		return;

	AILogWithSignature(@"drawn so far: remote=%ld (%@), preview=%ld",
					   (long)remoteView.renderedFrames, NSStringFromSize(remoteView.lastFrameSize),
					   (long)previewView.renderedFrames);

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[self countWhatIsDrawn:(triesLeft - 1)];
	});
}

//States -----------------------------------------------------------------------------------------
#pragma mark States

- (void)noteRinging
{
	if (!ended && !connectedSince)
		[statusLabel setStringValue:AILocalizedString(@"Ringing…", "State of a call that rings on the other side")];
}

- (void)noteConnected
{
	connectedSince = [NSDate date];
	[self updateDuration];

	durationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
													 target:self
												   selector:@selector(updateDuration)
												   userInfo:nil
													repeats:YES];
}

- (void)updateDuration
{
	NSInteger seconds = (NSInteger)(-[connectedSince timeIntervalSinceNow]);
	[statusLabel setStringValue:[NSString stringWithFormat:@"%@ %02ld:%02ld",
								 AILocalizedString(@"Connected", "State of a call in progress"),
								 (long)(seconds / 60), (long)(seconds % 60)]];
}

- (void)noteEndedWithReason:(NSString *)reason locally:(BOOL)locally
{
	if (ended)
		return;	//the closing window already said goodbye; saying it twice would close twice
	ended = YES;
	[durationTimer invalidate];
	durationTimer = nil;

	//A call the person ended themselves needs no epitaph
	if (locally && [reason isEqualToString:@"success"]) {
		[[self window] close];
		return;
	}

	NSString *text;
	if ([reason isEqualToString:@"decline"])
		text = AILocalizedString(@"Call declined", "State of a call the other side turned away");
	else if ([reason isEqualToString:@"success"])
		text = AILocalizedString(@"Call ended", "State of a call that is over");
	else
		text = [NSString stringWithFormat:AILocalizedString(@"Call failed (%@)", "State of a call that broke; %@ names the reason"), reason];
	[statusLabel setStringValue:text];
	[hangUpButton setTitle:AILocalizedString(@"Close", "Button closing the window of a finished call")];

	/* A call the other side ended stays on screen until the person closes it, so
	 * the ending is actually seen; nothing vanishes under their cursor. */
}

//Leaving ----------------------------------------------------------------------------------------
#pragma mark Leaving

- (void)hangUp:(id)sender
{
	if (ended) {
		[[self window] close];
		return;
	}
	[call hangUpWithReason:@"success"];
	//The window closes through noteEndedWithReason -> the person pressing Close
}

- (void)windowWillClose:(NSNotification *)notification
{
	if (!ended) {
		//Marked first: the hangup reports back through the manager while this window is closing
		ended = YES;
		[call hangUpWithReason:@"success"];
	}
	[durationTimer invalidate];
	durationTimer = nil;

	//Whoever kept us alive for the epilogue may let go now
	if (self.whenClosed) {
		void (^goodbye)(void) = self.whenClosed;
		self.whenClosed = nil;
		goodbye();
	}
}

@end
