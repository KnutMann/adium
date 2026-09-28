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

#import "AIVoiceNoteShelfView.h"
#import "AIVoiceNotePlugin.h"
#import "AIMessageViewController.h"

#import <Adium/AIChat.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AITextAttachmentExtension.h>

#define SHELF_MARGIN				8.0f
#define BAR_PADDING					6.0f
#define PILL_HEIGHT					32.0f
#define PILL_PADDING				10.0f		//inside the pill, at both ends
#define PILL_GAP					6.0f
#define GLYPH_WIDTH					16.0f		//the dot or the play button; fixed, so the time does not move
#define WAVEFORM_HEIGHT				20.0f
#define DOT_SIZE					10.0f
#define SYMBOL_POINT_SIZE			18.0		//the bin, pause, the microphone
#define GLYPH_POINT_SIZE			13.0		//play and stop, inside the pill
#define SEND_SYMBOL_POINT_SIZE		20.0		//the same arrow the formula editor sends with
#define TIME_POINT_SIZE				13.0

/* Fifteen pictures a second. The waveform grows by one bar every fiftieth of a second, so
 * drawing more often would show nothing new, and the clock only changes once a second. */
#define TICK_INTERVAL				(1.0 / 15.0)

//A note shorter than this is refused by the recorder, so the arrow does not offer it
#define SHORTEST_TO_SEND			0.5

/*!
 * @class AIVoicePillView
 * @brief The rounded field the state, the time and the waveform sit in
 */
@interface AIVoicePillView : NSView
@end

/*!
 * @class AIVoiceWaveformView
 * @brief The loudness of the note, as bars
 *
 * While the note is being recorded the newest bar is at the right and the picture moves left as
 * it grows, the way a meter with memory does. Once it is paused the whole note is fitted into
 * the width, and playing it colours the bars that have been played.
 */
@interface AIVoiceWaveformView : NSView
@property (nonatomic, copy) NSArray *levels;
@property (nonatomic) BOOL scrolling;
@property (nonatomic) CGFloat playedFraction;		//below zero: nothing is being played
@end


@interface AIVoiceNoteShelfView ()
- (void)buildInterface;
- (NSImage *)symbol:(NSString *)name pointSize:(CGFloat)pointSize described:(NSString *)description;
- (NSImage *)recordingDotDimmed:(BOOL)dimmed;
- (void)startTicking;
- (void)stopTicking;
- (void)tick;
- (AIMessageEntryTextView *)entryTextView;
- (void)closeShelf;
- (IBAction)discard:(id)sender;
- (IBAction)togglePlayback:(id)sender;
- (IBAction)sendNote:(id)sender;
@end


@implementation AIVoiceNoteShelfView

- (id)initWithChat:(AIChat *)inChat
{
	if ((self = [super initWithFrame:NSMakeRect(0.0f, 0.0f, 480.0f, 48.0f)])) {
		chat = inChat;
		[self buildInterface];
		[self showState:AIVoiceRecorderIdle duration:0.0 levels:nil playbackPosition:0.0];
	}

	return self;
}

- (void)dealloc
{
	[self stopTicking];

	/* This view is the only sign that the microphone is open. If it goes, by the window closing
	 * or the chat going away, the microphone must not stay open unseen, and a note nobody can
	 * send is no use kept. The two deliberate ways out, the bin and the arrow, have emptied the
	 * recorder before they close the shelf, so this only ever reaches a note that was abandoned.
	 *
	 * A turn of the run loop later, not now. Cancelling announces the change of state, and the
	 * plugin answers by looking at every open chat's window; when this dealloc is the window
	 * closing, that is a controller in the middle of its own dealloc. Nothing captured here but
	 * the recorder, which outlives everything. */
	AIVoiceRecorder *recorder = [AIVoiceRecorder sharedRecorder];
	if (recorder.holdsRecording) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (recorder.holdsRecording) [recorder cancel];
		});
	}
}

//Interface ------------------------------------------------------------------------------------------------------------
#pragma mark Interface

/*!
 * @brief Build the whole thing in code
 *
 * One row, laid out with constraints inside a root that keeps its autoresizing mask, as the
 * formula editor is: the chat window positions views by writing frames and would fight
 * constraints reaching outside. The pill is as high as it is and as wide as what is left; the
 * buttons are as wide as their pictures. Nothing here takes its size from the note.
 */
- (void)buildInterface
{
	button_discard = [[NSButton alloc] initWithFrame:NSZeroRect];
	[button_discard setImage:[self symbol:@"trash" pointSize:SYMBOL_POINT_SIZE
								described:AILocalizedString(@"Discard the recording", "Button in the voice recorder which throws the recording away")]];
	[button_discard setImagePosition:NSImageOnly];
	[button_discard setBordered:NO];
	[button_discard setTitle:@""];
	[button_discard setContentTintColor:[NSColor secondaryLabelColor]];
	[button_discard setToolTip:AILocalizedString(@"Discard the recording", "Button in the voice recorder which throws the recording away")];
	[button_discard setTarget:self];
	[button_discard setAction:@selector(discard:)];
	[button_discard setTranslatesAutoresizingMaskIntoConstraints:NO];

	view_pill = [[AIVoicePillView alloc] initWithFrame:NSZeroRect];
	[view_pill setTranslatesAutoresizingMaskIntoConstraints:NO];

	/* Inside the pill: the dot that says it is listening, which becomes the play button once it
	 * is not, then the time, then the waveform. */
	image_dot = [self recordingDotDimmed:NO];
	image_dotDim = [self recordingDotDimmed:YES];
	image_playGlyph = [self symbol:@"play.fill" pointSize:GLYPH_POINT_SIZE
						 described:AILocalizedString(@"Play", "Button in the voice recorder which plays the recording back")];
	image_stopGlyph = [self symbol:@"stop.fill" pointSize:GLYPH_POINT_SIZE
						 described:AILocalizedString(@"Stop", "Button in the voice recorder which stops playing the recording back")];

	button_play = [[NSButton alloc] initWithFrame:NSZeroRect];
	[button_play setImagePosition:NSImageOnly];
	[button_play setBordered:NO];
	[button_play setTitle:@""];
	[button_play setTarget:self];
	[button_play setAction:@selector(togglePlayback:)];
	[button_play setTranslatesAutoresizingMaskIntoConstraints:NO];

	textField_time = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[textField_time setEditable:NO];
	[textField_time setSelectable:NO];
	[textField_time setBordered:NO];
	[textField_time setDrawsBackground:NO];
	[textField_time setAlignment:NSTextAlignmentLeft];
	[textField_time setFont:[NSFont monospacedDigitSystemFontOfSize:TIME_POINT_SIZE weight:NSFontWeightMedium]];
	[textField_time setTextColor:[NSColor labelColor]];
	[textField_time setTranslatesAutoresizingMaskIntoConstraints:NO];
	/* Measured once with the widest time it will show, and held there, so that the waveform does
	 * not shift when the note passes ten minutes. Digits of one width, so it does not shift on
	 * the way there either. */
	[textField_time setStringValue:@"00:00"];
	[textField_time sizeToFit];
	CGFloat timeWidth = AIceil(NSWidth([textField_time frame]));

	view_waveform = [[AIVoiceWaveformView alloc] initWithFrame:NSZeroRect];
	[view_waveform setContentHuggingPriority:NSLayoutPriorityDefaultLow
							  forOrientation:NSLayoutConstraintOrientationHorizontal];
	[view_waveform setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
											forOrientation:NSLayoutConstraintOrientationHorizontal];
	[view_waveform setTranslatesAutoresizingMaskIntoConstraints:NO];

	[view_pill addSubview:button_play];
	[view_pill addSubview:textField_time];
	[view_pill addSubview:view_waveform];

	image_pause = [self symbol:@"pause.fill" pointSize:SYMBOL_POINT_SIZE
					 described:AILocalizedString(@"Pause", "Button in the voice recorder which pauses the recording")];
	image_resume = [self symbol:@"mic.fill" pointSize:SYMBOL_POINT_SIZE
					  described:AILocalizedString(@"Resume", "Button in the voice recorder which carries on with a paused recording")];

	button_pauseResume = [[NSButton alloc] initWithFrame:NSZeroRect];
	[button_pauseResume setImagePosition:NSImageOnly];
	[button_pauseResume setBordered:NO];
	[button_pauseResume setTitle:@""];
	[button_pauseResume setTarget:self];
	[button_pauseResume setAction:@selector(togglePause:)];
	[button_pauseResume setTranslatesAutoresizingMaskIntoConstraints:NO];

	button_send = [[NSButton alloc] initWithFrame:NSZeroRect];
	[button_send setImage:[self symbol:@"arrow.up.circle.fill" pointSize:SEND_SYMBOL_POINT_SIZE
							 described:AILocalizedString(@"Send", nil)]];
	[button_send setImagePosition:NSImageOnly];
	[button_send setBordered:NO];
	[button_send setTitle:@""];
	[button_send setContentTintColor:[NSColor systemBlueColor]];
	[button_send setToolTip:AILocalizedString(@"Send", nil)];
	[button_send setTarget:self];
	[button_send setAction:@selector(sendNote:)];
	[button_send setTranslatesAutoresizingMaskIntoConstraints:NO];

	[self addSubview:button_discard];
	[self addSubview:view_pill];
	[self addSubview:button_pauseResume];
	[self addSubview:button_send];

	NSDictionary *views = NSDictionaryOfVariableBindings(button_discard, view_pill, button_play, textField_time,
														view_waveform, button_pauseResume, button_send);
	NSDictionary *metrics = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithFloat:SHELF_MARGIN], @"margin",
							 [NSNumber numberWithFloat:BAR_PADDING], @"barPadding",
							 [NSNumber numberWithFloat:PILL_HEIGHT], @"pillHeight",
							 [NSNumber numberWithFloat:PILL_PADDING], @"pillPadding",
							 [NSNumber numberWithFloat:PILL_GAP], @"pillGap",
							 [NSNumber numberWithFloat:GLYPH_WIDTH], @"glyphWidth",
							 [NSNumber numberWithFloat:WAVEFORM_HEIGHT], @"waveformHeight",
							 [NSNumber numberWithFloat:timeWidth], @"timeWidth",
							 nil];

	NSMutableArray *constraints = [NSMutableArray array];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-margin-[button_discard]-barPadding-[view_pill]-barPadding-[button_pauseResume]-barPadding-[button_send]-margin-|"
											 options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
	/* The pill's height is the row's height. The margins are what the row asks for and the least
	 * it accepts: dragged taller, the shelf keeps the row in its middle rather than breaking a
	 * constraint to fill the space. */
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(>=margin)-[view_pill(pillHeight)]-(>=margin)-|"
											 options:0 metrics:metrics views:views]];
	[constraints addObject:[NSLayoutConstraint constraintWithItem:view_pill attribute:NSLayoutAttributeCenterY
													   relatedBy:NSLayoutRelationEqual
														  toItem:self attribute:NSLayoutAttributeCenterY
													  multiplier:1.0f constant:0.0f]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-pillPadding-[button_play(glyphWidth)]-pillGap-[textField_time(timeWidth)]-pillGap-[view_waveform]-pillPadding-|"
											 options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
	[constraints addObjectsFromArray:
	 [NSLayoutConstraint constraintsWithVisualFormat:@"V:[view_waveform(waveformHeight)]"
											 options:0 metrics:metrics views:views]];
	[constraints addObject:[NSLayoutConstraint constraintWithItem:view_waveform attribute:NSLayoutAttributeCenterY
													   relatedBy:NSLayoutRelationEqual
														  toItem:view_pill attribute:NSLayoutAttributeCenterY
													  multiplier:1.0f constant:0.0f]];

	/* The row asks to be exactly as high as its pill and margins. Without this the two >= margins
	 * leave the height free, and fittingSize would answer with the least of everything, which is
	 * the pill alone. */
	NSLayoutConstraint *height = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeHeight
															 relatedBy:NSLayoutRelationEqual
																toItem:nil attribute:NSLayoutAttributeNotAnAttribute
															multiplier:1.0f constant:(PILL_HEIGHT + 2.0f * SHELF_MARGIN)];
	[height setPriority:NSLayoutPriorityDefaultHigh];
	[constraints addObject:height];

	[NSLayoutConstraint activateConstraints:constraints];
}

/*!
 * @brief One of the system's symbols at a size
 *
 * Left as a template, so the button's tint colours it, and the tint is a colour that follows
 * the window into the dark.
 */
- (NSImage *)symbol:(NSString *)name pointSize:(CGFloat)pointSize described:(NSString *)description
{
	NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];

	return [image imageWithSymbolConfiguration:
			[NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:NSFontWeightRegular]];
}

/*!
 * @brief The red dot that says the microphone is open
 *
 * Two of them, one paler, shown in turn so that the dot blinks; a steady dot is easily taken
 * for a decoration.
 */
- (NSImage *)recordingDotDimmed:(BOOL)dimmed
{
	NSString *description = AILocalizedString(@"Recording a voice note", "The microphone button while it is listening");

	NSImage *dot = [NSImage imageWithSize:NSMakeSize(GLYPH_WIDTH, GLYPH_WIDTH)
								  flipped:NO
						   drawingHandler:^BOOL(NSRect rect) {
		NSRect circle = NSMakeRect(NSMidX(rect) - DOT_SIZE / 2.0f, NSMidY(rect) - DOT_SIZE / 2.0f, DOT_SIZE, DOT_SIZE);
		[[[NSColor systemRedColor] colorWithAlphaComponent:(dimmed ? 0.35f : 1.0f)] setFill];
		[[NSBezierPath bezierPathWithOvalInRect:circle] fill];
		return YES;
	}];
	[dot setAccessibilityDescription:description];

	return dot;
}

//What is shown -----------------------------------------------------------------------------------------------------------
#pragma mark What is shown

- (void)startTicking
{
	if (ticker) return;

	__weak __typeof__(self) weakSelf = self;
	ticker = [NSTimer timerWithTimeInterval:TICK_INTERVAL repeats:YES block:^(NSTimer *timer) {
		[weakSelf tick];
	}];
	//In the common modes, so the picture keeps moving while a menu is open or a divider is dragged
	[[NSRunLoop mainRunLoop] addTimer:ticker forMode:NSRunLoopCommonModes];
}

- (void)stopTicking
{
	[ticker invalidate];
	ticker = nil;
}

- (void)tick
{
	AIVoiceRecorder *recorder = [AIVoiceRecorder sharedRecorder];

	[self showState:recorder.state
		   duration:recorder.duration
			 levels:recorder.levels
   playbackPosition:recorder.playbackPosition];
}

+ (NSString *)clockStringForSeconds:(NSTimeInterval)seconds
{
	NSInteger whole = (NSInteger)seconds;

	return [NSString stringWithFormat:@"%ld:%02ld", (long)(whole / 60), (long)(whole % 60)];
}

- (void)showState:(AIVoiceRecorderState)state
		 duration:(NSTimeInterval)duration
		   levels:(NSArray *)levels
 playbackPosition:(NSTimeInterval)position
{
	BOOL recording = (state == AIVoiceRecorderRecording);
	BOOL playing = (state == AIVoiceRecorderPlaying);
	BOOL held = (state != AIVoiceRecorderIdle);

	//The clock follows playback while there is any, and the note's length otherwise
	[textField_time setStringValue:[AIVoiceNoteShelfView clockStringForSeconds:(playing ? position : duration)]];

	[view_waveform setLevels:levels];
	[view_waveform setScrolling:recording];
	[view_waveform setPlayedFraction:((playing && duration > 0.0) ? (CGFloat)(position / duration) : -1.0f)];
	[view_waveform setNeedsDisplay:YES];

	if (recording) {
		//Blinking on the note's own clock, so a pause stops it mid blink and a picture of it is repeatable
		[button_play setImage:((fmod(duration, 1.0) < 0.5) ? image_dot : image_dotDim)];
		[button_play setToolTip:nil];
	} else if (playing) {
		[button_play setImage:image_stopGlyph];
		[button_play setToolTip:AILocalizedString(@"Stop", "Button in the voice recorder which stops playing the recording back")];
	} else {
		[button_play setImage:image_playGlyph];
		[button_play setToolTip:AILocalizedString(@"Play", "Button in the voice recorder which plays the recording back")];
	}
	[button_play setEnabled:(held && !sending)];

	[button_pauseResume setImage:(recording ? image_pause : image_resume)];
	[button_pauseResume setToolTip:(recording ?
									AILocalizedString(@"Pause", "Button in the voice recorder which pauses the recording") :
									AILocalizedString(@"Resume", "Button in the voice recorder which carries on with a paused recording"))];
	[button_pauseResume setEnabled:(held && !sending)];

	[button_send setEnabled:(held && !sending && duration >= SHORTEST_TO_SEND)];
	[button_discard setEnabled:!sending];
}

//Recording ---------------------------------------------------------------------------------------------------------------
#pragma mark Recording

- (void)startRecording
{
	//Following the recorder from now on; until the microphone answers that is the idle look
	[self startTicking];

	__weak __typeof__(self) weakSelf = self;
	[[AIVoiceRecorder sharedRecorder] startWithCompletion:^(BOOL began, NSString *problem) {
		__typeof__(self) me = weakSelf;
		if (!me || began) return;

		if (problem) {
			[adium.interfaceController handleErrorMessage:AILocalizedString(@"Voice note", nil)
										  withDescription:problem];
		}
		[me closeShelf];
	}];
}

- (IBAction)togglePause:(id)sender
{
	AIVoiceRecorder *recorder = [AIVoiceRecorder sharedRecorder];

	switch (recorder.state) {
		case AIVoiceRecorderRecording: {
			[recorder pause];
			break;
		}
		case AIVoiceRecorderPaused:
		case AIVoiceRecorderPlaying: {
			[recorder resumeWithCompletion:^(BOOL began, NSString *problem) {
				if (!began && problem) {
					[adium.interfaceController handleErrorMessage:AILocalizedString(@"Voice note", nil)
												  withDescription:problem];
				}
			}];
			break;
		}
		case AIVoiceRecorderIdle:
			break;
	}

	[self tick];
}

- (IBAction)togglePlayback:(id)sender
{
	AIVoiceRecorder *recorder = [AIVoiceRecorder sharedRecorder];

	if (recorder.state == AIVoiceRecorderPaused)
		[recorder playFromStart];
	else if (recorder.state == AIVoiceRecorderPlaying)
		[recorder stopPlaying];

	[self tick];
}

- (IBAction)discard:(id)sender
{
	[self stopTicking];
	[[AIVoiceRecorder sharedRecorder] cancel];
	[self closeShelf];
}

//Sending -----------------------------------------------------------------------------------------------------------------
#pragma mark Sending

/*!
 * @brief The chat's own message field, which is where the note goes
 *
 * Resolved on each use rather than kept: the chain to it runs through the chat's container, which
 * is nil once the chat closes, and a stale pointer through there is a crash rather than a blank.
 */
- (AIMessageEntryTextView *)entryTextView
{
	return chat.chatContainer.messageViewController.textEntryView;
}

- (void)closeShelf
{
	[self stopTicking];
	[chat.chatContainer.messageViewController setShelfView:nil];
}

/*!
 * @brief The arrow was pressed
 *
 * The note is finished and written, put into the message field, and sent through the field's own
 * send, so that it goes the same way a typed message does, into the history and past whatever else
 * the field does on the way out. availableForSending is what a send key asks, so a conversation
 * that is refusing messages keeps the note in its field for later rather than losing it.
 */
- (IBAction)sendNote:(id)sender
{
	AIVoiceRecorder *recorder = [AIVoiceRecorder sharedRecorder];
	if (sending || !recorder.holdsRecording) return;

	sending = YES;
	[self stopTicking];
	[self showState:recorder.state duration:recorder.duration levels:recorder.levels playbackPosition:0.0];

	/* The conversation, held, and not the view: the file takes a moment to write, and the note
	 * belongs in that conversation whether or not this shelf is still standing when it is done. */
	AIChat *destination = chat;
	__weak __typeof__(self) weakSelf = self;
	[recorder stopAndWrite:^(NSString *path, NSTimeInterval duration, NSString *problem) {
		if (path) {
			AIMessageEntryTextView *entry = destination.chatContainer.messageViewController.textEntryView;
			[AIVoiceNoteShelfView placeNoteAtPath:path lasting:duration into:entry];
			if (entry && [entry availableForSending])
				[entry sendContent:nil];
		} else if (problem) {
			[adium.interfaceController handleErrorMessage:AILocalizedString(@"Voice note", nil)
										  withDescription:problem];
		}

		//Sent or lost, the note is gone from the recorder either way, and the shelf with it
		__typeof__(self) me = weakSelf;
		if (me) {
			me->sending = NO;		//not busy any more, or the shelf would refuse to close
			[me closeShelf];
		}
	}];
}

+ (void)placeNoteAtPath:(NSString *)path lasting:(NSTimeInterval)duration into:(NSTextView *)field
{
	if (!field) return;

	NSString *shown = [NSString stringWithFormat:AILocalizedString(@"Voice note (%ld:%02ld)",
								"A recorded voice note in the entry field, with its length"),
					   (long)(duration / 60), (long)((NSInteger)duration % 60)];

	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	[attachment setPath:path];
	[attachment setString:shown];
	[attachment setShouldSaveImageForLogging:NO];
	//A note said is part of the conversation, so the chat keeps a player for it once it is sent
	[attachment setLeavesLinkWhenSent:YES];

	NSImage *icon = [NSImage imageWithSystemSymbolName:@"waveform" accessibilityDescription:shown];
	if (icon) {
		[icon setSize:NSMakeSize(18, 18)];
		[attachment setImage:icon];
		[attachment setAttachmentCell:[[NSTextAttachmentCell alloc] initImageCell:icon]];
	}

	[field insertText:[NSAttributedString attributedStringWithAttachment:attachment]
	 replacementRange:[field selectedRange]];
}

//The shelf ---------------------------------------------------------------------------------------------------------------
#pragma mark The shelf

//The button in the message field that opened this recorder; it stays usable, to pause and resume
- (NSString *)messageEntryAccessoryIdentifier
{
	return VOICE_ITEM_IDENTIFIER;
}

//Busy for as long as there is a note, or one being written: replacing the shelf would lose it
- (BOOL)messageEntryShelfIsBusy
{
	return (sending || [[AIVoiceRecorder sharedRecorder] holdsRecording]);
}

@end


@implementation AIVoicePillView

- (void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];
	CGFloat radius = NSHeight(bounds) / 2.0f;

	//A shade of the text colour, so it is a little darker than a light window and a little lighter than a dark one
	[[[NSColor labelColor] colorWithAlphaComponent:0.08f] setFill];
	[[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius] fill];
}

@end


@implementation AIVoiceWaveformView

#define BAR_WIDTH		2.0f
#define BAR_STEP		3.0f
#define QUIETEST_DB		-50.0		//a level this quiet is drawn as the shortest bar

- (id)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame]))
		_playedFraction = -1.0f;

	return self;
}

/*!
 * @brief How tall a level is drawn, between 0 and 1
 *
 * On a decibel scale, as a meter is: a voice at a comfortable distance is a small fraction of
 * full scale, and drawn as that fraction it would barely show. Fifty decibels of range put
 * ordinary speech in the middle and a raised voice near the top.
 */
static CGFloat heightForLevel(double level)
{
	if (level <= 0.0) return 0.0f;

	double decibels = 20.0 * log10(level);
	double fraction = (decibels - QUIETEST_DB) / -QUIETEST_DB;

	return (CGFloat)MIN(1.0, MAX(0.0, fraction));
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSRect	bounds = [self bounds];
	NSUInteger room = (NSUInteger)(NSWidth(bounds) / BAR_STEP);
	NSUInteger count = [self.levels count];
	if (!room) return;

	/* Which levels stand where. Recording, the newest bar is at the right and older ones move
	 * left, and the bars there are stand at the right as well, so the picture grows leftwards
	 * from the clock. Paused, the whole note is fitted in, each bar the loudest of its share. */
	NSUInteger bars = (self.scrolling ? MIN(count, room) : room);
	CGFloat left = (self.scrolling ? NSWidth(bounds) - bars * BAR_STEP : 0.0f);
	NSColor *quiet = [NSColor secondaryLabelColor];
	NSColor *played = [NSColor controlAccentColor];

	for (NSUInteger bar = 0; bar < bars; bar++) {
		double level = 0.0;

		if (self.scrolling) {
			level = [[self.levels objectAtIndex:(count - bars + bar)] doubleValue];
		} else if (count) {
			NSUInteger from = bar * count / bars;
			NSUInteger to = MAX(from + 1, (bar + 1) * count / bars);
			for (NSUInteger i = from; i < to && i < count; i++)
				level = MAX(level, [[self.levels objectAtIndex:i] doubleValue]);
		}

		CGFloat height = MAX(BAR_WIDTH, AIround(heightForLevel(level) * NSHeight(bounds)));
		NSRect	rect = NSMakeRect(left + bar * BAR_STEP, AIround((NSHeight(bounds) - height) / 2.0f), BAR_WIDTH, height);
		BOOL	done = (self.playedFraction >= 0.0f && (NSMidX(rect) / NSWidth(bounds)) <= self.playedFraction);

		[(done ? played : quiet) setFill];
		[[NSBezierPath bezierPathWithRoundedRect:rect xRadius:(BAR_WIDTH / 2.0f) yRadius:(BAR_WIDTH / 2.0f)] fill];
	}
}

@end
