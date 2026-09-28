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
#import <Adium/AIMessageEntryAccessory.h>
#import "AIVoiceRecorder.h"

@class AIChat, AIVoiceWaveformView;

/*!
 * @class AIVoiceNoteShelfView
 * @brief The voice recorder that sits on a chat's shelf
 *
 * One row: the bin, then a pill with the state of the note, its length and a picture of its
 * loudness, then the button that pauses or resumes, then the arrow that sends. While the note
 * is being recorded the pill shows a red dot and the picture grows from the right; paused, the
 * dot becomes a play button, the picture is the whole note, and playing it moves a mark across
 * it. That is the recorder people know from their phones, and there is no reason to teach a
 * second one.
 *
 * The view belongs to one conversation, so sending has somewhere unambiguous to send to. The
 * note goes into that conversation's message field as an attachment and out through the same
 * sending a typed message takes, so nothing about how a voice note travels changed when it got
 * a recorder.
 *
 * Nothing in here takes its size from its content. The row is as high as its pill and the pill
 * as wide as the shelf leaves it; a note of any length is drawn into that.
 *
 * The recorder holds the one note there is for the whole application, so this shelf is busy
 * for as long as it is open: nothing replaces it or closes it but its own two ways out, the
 * bin and the arrow.
 */
@interface AIVoiceNoteShelfView : NSView <AIMessageEntryShelf> {
	AIChat					*chat;

	NSButton				*button_discard;
	NSView					*view_pill;
	NSButton				*button_play;
	NSTextField				*textField_time;
	AIVoiceWaveformView		*view_waveform;
	NSButton				*button_pauseResume;
	NSButton				*button_send;

	//The pictures on the buttons, made once; the state decides which is on
	NSImage					*image_dot;
	NSImage					*image_dotDim;
	NSImage					*image_playGlyph;
	NSImage					*image_stopGlyph;
	NSImage					*image_pause;
	NSImage					*image_resume;

	NSTimer					*ticker;
	BOOL					 sending;
}

/*!
 * @brief Create a recorder for one conversation
 *
 * @param inChat The chat whose message field the note goes into and whose send sends it
 */
- (id)initWithChat:(AIChat *)inChat;

/*!
 * @brief Open the microphone and begin
 *
 * Called once the view is on the shelf. If the microphone is refused the reason is shown and the
 * shelf closes again, since a recorder that cannot record has nothing to offer.
 */
- (void)startRecording;

/*! @brief Pause a note that is being recorded, or carry on with one that is paused */
- (IBAction)togglePause:(id)sender;

/*!
 * @brief Show a state without asking the recorder
 *
 * What the view draws is decided here and nowhere else; while a note is in progress a timer
 * calls this with what the recorder says. Anything that wants to see the view without a
 * microphone, a test say, calls it with a state of its own.
 */
- (void)showState:(AIVoiceRecorderState)state
		 duration:(NSTimeInterval)duration
		   levels:(NSArray *)levels
 playbackPosition:(NSTimeInterval)position;

/*!
 * @brief Put a finished note where a message is being written
 *
 * As an attachment, the way a formula is placed, so that the send path that carries pictures
 * and files carries this too. What is drawn in the field is a waveform and the length, since a
 * sound has no picture of its own.
 */
+ (void)placeNoteAtPath:(NSString *)path lasting:(NSTimeInterval)duration into:(NSTextView *)field;

@end
