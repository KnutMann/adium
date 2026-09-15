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
	BOOL answered;				//the peer said yes; a later ring is stale news
	AIJingleCallController *call;
	NSString *displayName;

	NSTextField *statusLabel;
	NSButton *hangUpButton;
	NSButton *microphoneButton;
	NSButton *cameraButton;
	NSButton *fillButton;
	NSImageView *cameraOffSign;		//shown on the black while the other camera is off
	BOOL fillingTheFrame;
	NSView *stage;						//where the pictures go, once there are any
	AIJingleVideoView *remoteView;
	AIJingleVideoView *previewView;
	NSMutableArray<RTCVideoTrack *> *remoteTracks;	//held, or the renderer goes with them

	NSDate *openedAt;
	BOOL notedFirstRemoteFrame;
	NSTimer *durationTimer;
	NSDate *connectedSince;
	NSString *peerNote;				//what the other side says it has turned off
	BOOL ended;
}

- (id)initWithCallController:(AIJingleCallController *)controller displayName:(NSString *)inDisplayName
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, AUDIO_WIDTH, BAR_HEIGHT)
												   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
															  NSWindowStyleMaskMiniaturizable |
															  NSWindowStyleMaskResizable)
													 backing:NSBackingStoreBuffered
													   defer:NO];

	if ((self = [super initWithWindow:window])) {
		call = controller;
		displayName = [inDisplayName copy];
		remoteTracks = [NSMutableArray array];
		openedAt = [NSDate date];

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

		/* The two switches every other video call has. Pictures rather than words,
		 * because the bar is narrow and because a crossed-out microphone is read
		 * faster than any sentence in any language. */
		microphoneButton = [self switchWithSymbol:@"mic.fill"
										 fallback:@"Mute"
										   action:@selector(toggleMicrophone:)
											  help:AILocalizedString(@"Turn your microphone off", "Tooltip of the button muting one's own microphone in a call")];

		cameraButton = [self switchWithSymbol:@"video.fill"
									 fallback:@"Camera"
									   action:@selector(toggleCamera:)
										  help:AILocalizedString(@"Turn your camera off", "Tooltip of the button switching off one's own camera in a call")];
			/* Asked of the call, not of its camera: the window is built while the other
		 * side is still being rung, and the track does not exist until the
		 * connection is set up a moment later. Hanging the switch on the track
		 * meant it was hidden at that moment and therefore hidden for good, so a
		 * video call had no way to turn its camera off. */
		[cameraButton setHidden:!controller.wantsVideo];

		fillButton = [self switchWithSymbol:@"arrow.up.left.and.arrow.down.right"
								   fallback:@"Fill"
									 action:@selector(toggleFill:)
										help:AILocalizedString(@"Fill the window with the picture", "Tooltip of the button that crops a call's picture to fill the window")];
		[fillButton setHidden:YES];		//only once there is a picture to fill with

		/* All of them in one row, and the row does the arithmetic.
		 *
		 * Chaining them to each other by hand looks the same and is not: a hidden
		 * button keeps every constraint it had, so it keeps its width too, and an
		 * audio call or a picture nobody is filling with left a hole in the row
		 * where a button was merely invisible. A row detaches what is hidden. */
		NSStackView *switches = [NSStackView stackViewWithViews:@[microphoneButton, cameraButton,
																  fillButton, hangUpButton]];
		[switches setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
		[switches setSpacing:6.0];
		[switches setCustomSpacing:MARGIN afterView:fillButton];
		[switches setTranslatesAutoresizingMaskIntoConstraints:NO];
		[content addSubview:switches];

		[NSLayoutConstraint activateConstraints:@[
			[statusLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:MARGIN + 2.0],
			[statusLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-(BAR_HEIGHT / 2.0 - 9.0)],
			[switches.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-MARGIN],
			[switches.centerYAnchor constraintEqualToAnchor:statusLabel.centerYAnchor],
			[statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:switches.leadingAnchor constant:-MARGIN],
		]];

		//Our own camera, when this call sends one, is worth seeing from the start
		if (controller.localVideoTrack)
			[self growStageIfNeeded];

		//Small enough to tuck away, never so small that the switches crush each other
		[self allowTheHeightToChange:NO];

		[window center];
		[window makeKeyAndOrderFront:nil];
	}

	return self;
}

//How big this window may be ---------------------------------------------------------------------
#pragma mark How big this window may be

/*!
 * @brief Let the window grow downwards only while there is a picture in it
 *
 * A call without pictures is one line of text and a few switches, and dragging
 * its bottom edge downwards can only ever produce empty space. So the height is
 * simply not offered; the width still is, because a long name needs room.
 */
- (void)allowTheHeightToChange:(BOOL)mayChange
{
	NSWindow *window = [self window];

	if (!mayChange) {
		[window setContentMinSize:NSMakeSize(AUDIO_WIDTH, BAR_HEIGHT)];
		[window setContentMaxSize:NSMakeSize(CGFLOAT_MAX, BAR_HEIGHT)];
		return;
	}

	[window setContentMinSize:NSMakeSize(AUDIO_WIDTH, 240.0 + BAR_HEIGHT)];
	[window setContentMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
}

//The two switches -------------------------------------------------------------------------------
#pragma mark The two switches

/*! @brief A square button showing a system symbol, or a word where there are none */
- (NSButton *)switchWithSymbol:(NSString *)symbol
					  fallback:(NSString *)word
						action:(SEL)action
						  help:(NSString *)help
{
	NSButton *button = nil;

	if (@available(macOS 11.0, *)) {
		NSImage *picture = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:help];
		if (picture)
			button = [NSButton buttonWithImage:picture target:self action:action];
	}
	if (!button)
		button = [NSButton buttonWithTitle:word target:self action:action];

	[button setBezelStyle:NSBezelStyleRounded];
	[button setToolTip:help];
	[button setTranslatesAutoresizingMaskIntoConstraints:NO];
	return button;
}

- (void)toggleMicrophone:(id)sender
{
	call.microphoneMuted = !call.microphoneMuted;
	[self showWhatIsOn];
}

- (void)toggleCamera:(id)sender
{
	call.cameraOff = !call.cameraOff;
	[self showWhatIsOn];
}

- (void)toggleFill:(id)sender
{
	fillingTheFrame = !fillingTheFrame;
	remoteView.fillsTheFrame = fillingTheFrame;

	NSString *help = (fillingTheFrame ?
		AILocalizedString(@"Fit the whole picture into the window", "Tooltip of the button that shows a call's whole picture, black borders and all") :
		AILocalizedString(@"Fill the window with the picture", "Tooltip of the button that crops a call's picture to fill the window"));
	if (@available(macOS 11.0, *)) {
		NSImage *picture = [NSImage imageWithSystemSymbolName:(fillingTheFrame ?
								@"arrow.down.right.and.arrow.up.left" : @"arrow.up.left.and.arrow.down.right")
									 accessibilityDescription:help];
		if (picture)
			[fillButton setImage:picture];
	}
	[fillButton setToolTip:help];
}

/*!
 * @brief Let the two switches show what they are
 *
 * A crossed-out symbol for what is off, and the tooltip says what pressing would
 * do rather than what the state is, because that is the question somebody hovering
 * over a button is asking.
 */
- (void)showWhatIsOn
{
	struct { NSButton *button; BOOL off; NSString *on; NSString *off_; NSString *help; } both[] = {
		{ microphoneButton, call.microphoneMuted, @"mic.fill", @"mic.slash.fill",
		  call.microphoneMuted ?
			AILocalizedString(@"Turn your microphone on", "Tooltip of the button unmuting one's own microphone in a call") :
			AILocalizedString(@"Turn your microphone off", "Tooltip of the button muting one's own microphone in a call") },
		{ cameraButton, call.cameraOff, @"video.fill", @"video.slash.fill",
		  call.cameraOff ?
			AILocalizedString(@"Turn your camera on", "Tooltip of the button switching one's own camera back on in a call") :
			AILocalizedString(@"Turn your camera off", "Tooltip of the button switching off one's own camera in a call") },
	};

	for (size_t index = 0; index < sizeof(both) / sizeof(both[0]); index++) {
		if (!both[index].button)
			continue;
		if (@available(macOS 11.0, *)) {
			NSImage *picture = [NSImage imageWithSystemSymbolName:(both[index].off ? both[index].off_ : both[index].on)
										 accessibilityDescription:both[index].help];
			if (picture)
				[both[index].button setImage:picture];
		}
		[both[index].button setToolTip:both[index].help];
	}
}

/*! @brief The peer turned something of its own off; say so where the duration is */
- (void)showWhatThePeerSends
{
	if (ended || !connectedSince)
		return;

	NSString *note = nil;
	if (call.peerMicrophoneMuted && call.peerCameraOff)
		note = AILocalizedString(@"microphone and camera off", "Note in a call window: the other side turned both off");
	else if (call.peerMicrophoneMuted)
		note = AILocalizedString(@"microphone off", "Note in a call window: the other side muted its microphone");
	else if (call.peerCameraOff)
		note = AILocalizedString(@"camera off", "Note in a call window: the other side switched off its camera");

	peerNote = [note copy];
	if (connectedSince)
		[self updateDuration];

	[self showOrHideTheDarkenedCamera];
}

/*!
 * @brief A crossed-out camera in the middle of the black, when theirs is off
 *
 * A picture that stops arriving looks exactly like a picture that broke, and the
 * line in the bar is easy to miss while looking at the empty rectangle where a
 * face used to be. So the rectangle says it itself.
 */
- (void)showOrHideTheDarkenedCamera
{
	/* Two ways to know, and one of them is a guess.
	 *
	 * A client that says so in the protocol is believed at once. One that switches
	 * its camera off in silence, which is what the client this was tested against
	 * does, is recognised by what arrives instead: black, thirty times a second,
	 * for a while. A few frames of settling are required first, so the black a
	 * call starts with never counts. */
	BOOL theySaidSo = call.peerCameraOff;
	BOOL itLooksLikeIt = (remoteView.renderedFrames > 30 && remoteView.looksBlack);

	if (!stage || !(theySaidSo || itLooksLikeIt)) {
		[cameraOffSign setHidden:YES];
		return;
	}

	if (!cameraOffSign) {
		NSImage *symbol = nil;
		if (@available(macOS 11.0, *))
			symbol = [NSImage imageWithSystemSymbolName:@"video.slash.fill"
					   accessibilityDescription:AILocalizedString(@"The other side switched off their camera",
																  "Spoken description of the sign shown when the peer's camera is off")];

		cameraOffSign = [NSImageView imageViewWithImage:(symbol ?: [NSImage new])];
		[cameraOffSign setContentTintColor:[NSColor secondaryLabelColor]];
		[cameraOffSign setTranslatesAutoresizingMaskIntoConstraints:NO];
		if (@available(macOS 11.0, *))
			[cameraOffSign setSymbolConfiguration:
				[NSImageSymbolConfiguration configurationWithPointSize:56.0
																weight:NSFontWeightRegular]];

		/* Above the picture, below our own preview: a sign that covered the corner
		 * we watch ourselves in would be its own little annoyance. */
		[stage addSubview:cameraOffSign positioned:NSWindowBelow relativeTo:previewView];
		[NSLayoutConstraint activateConstraints:@[
			[cameraOffSign.centerXAnchor constraintEqualToAnchor:stage.centerXAnchor],
			[cameraOffSign.centerYAnchor constraintEqualToAnchor:stage.centerYAnchor],
		]];
	}

	[cameraOffSign setHidden:NO];
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
	[self allowTheHeightToChange:YES];

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

/*!
 * @brief Take the pictures away again when the call is over
 *
 * A picture that stops moving does not read as "the call ended", it reads as a
 * call that froze, and the other person's face stays in the room until somebody
 * closes the window. So the renderers are let go, the stage is removed and the
 * window shrinks back to the line of text that says what happened.
 */
- (void)takeTheStageAway
{
	for (RTCVideoTrack *track in remoteTracks)
		if (remoteView)
			[track removeRenderer:remoteView];
	[remoteTracks removeAllObjects];

	if (previewView && call.localVideoTrack)
		[call.localVideoTrack removeRenderer:previewView];

	[fillButton setHidden:YES];
	[cameraOffSign removeFromSuperview];
	cameraOffSign = nil;
	[remoteView removeFromSuperview];
	remoteView = nil;
	[previewView removeFromSuperview];
	previewView = nil;

	if (!stage)
		return;

	[stage removeFromSuperview];
	stage = nil;
	[self allowTheHeightToChange:NO];

	//Back to the plain bar, staying where the window's top edge was
	NSWindow *window = [self window];
	NSRect frame = [window frame];
	NSRect shrunk = [window frameRectForContentRect:NSMakeRect(0, 0, AUDIO_WIDTH, BAR_HEIGHT)];
	shrunk.origin.x = NSMidX(frame) - NSWidth(shrunk) / 2.0;
	shrunk.origin.y = NSMaxY(frame) - NSHeight(shrunk);
	[window setFrame:shrunk display:YES animate:YES];
}

- (void)attachRemoteVideoTrack:(RTCVideoTrack *)track
{
	if (ended)
		return;		//a picture arriving after the goodbye has nowhere to go

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
	remoteView.fillsTheFrame = fillingTheFrame;
	[fillButton setHidden:NO];
	[self showOrHideTheDarkenedCamera];
	AILogWithSignature(@"attaching renderer to remote track %@ (enabled=%d, state=%ld)",
					   track.trackId, track.isEnabled, (long)track.readyState);
	[track addRenderer:remoteView];
	[self countWhatIsDrawn:120];
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

	if (remoteView.renderedFrames > 0 && !notedFirstRemoteFrame) {
		notedFirstRemoteFrame = YES;
		AILogWithSignature(@"timeline %+.2fs: their first picture drawn (window)",
						   -[openedAt timeIntervalSinceNow]);
	}

	if ((triesLeft % 4) == 0)
	AILogWithSignature(@"drawn so far: remote=%ld (%@), preview=%ld",
					   (long)remoteView.renderedFrames, NSStringFromSize(remoteView.lastFrameSize),
					   (long)previewView.renderedFrames);

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[self countWhatIsDrawn:(triesLeft - 1)];
	});
}

//States -----------------------------------------------------------------------------------------
#pragma mark States

- (void)noteRinging
{
	if (!ended && !connectedSince && !answered)
		[statusLabel setStringValue:AILocalizedString(@"Ringing…", "State of a call that rings on the other side")];
}

- (void)noteAnswered
{
	answered = YES;
	if (!ended && !connectedSince)
		[statusLabel setStringValue:AILocalizedString(@"Connecting…", "State of an answered call while the media is being set up")];
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
	NSString *line = [NSString stringWithFormat:@"%@ %02ld:%02ld",
					  AILocalizedString(@"Connected", "State of a call in progress"),
					  (long)(seconds / 60), (long)(seconds % 60)];

	//The picture is watched as often as the clock ticks
	[self showOrHideTheDarkenedCamera];

	//What the other side turned off belongs next to the clock, not in a dialog
	if ([peerNote length])
		line = [NSString stringWithFormat:@"%@ (%@)", line, peerNote];

	[statusLabel setStringValue:line];
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

	/* The switches control a call that no longer exists. Left alive they would
	 * look like they still did something, and pressing one would silently do
	 * nothing at all. */
	[microphoneButton setEnabled:NO];
	[cameraButton setEnabled:NO];
	[fillButton setEnabled:NO];

	[self takeTheStageAway];

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
