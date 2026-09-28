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

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, AIVoiceRecorderState) {
	AIVoiceRecorderIdle = 0,	//nothing is held
	AIVoiceRecorderRecording,	//the microphone is open and the note is growing
	AIVoiceRecorderPaused,		//the microphone is closed and the note so far is kept
	AIVoiceRecorderPlaying		//paused, and playing the note so far back
};

//! Posted on the main thread whenever the state changes; the object is the recorder
extern NSString *const AIVoiceRecorderStateDidChangeNotification;

//! How much of the note one entry of the levels stands for, in seconds
extern const NSTimeInterval AIVoiceRecorderLevelInterval;

/*!
 * @class AIVoiceRecorder
 * @brief Takes what the microphone hears and leaves a voice note behind
 *
 * One at a time, for the whole application: two recordings at once would be two people
 * talking over each other into the same file, and there is no window in which anybody would
 * want that.
 *
 * A note is recorded in stretches. Paused, it keeps what it has and lets the microphone go;
 * resumed, it opens the microphone again and carries on where it was; and while it is paused
 * it can be played back, so that what is about to be sent can be heard first. Everything the
 * recorder says about time is counted in samples, not read off a clock, so a pause is not
 * part of the note's length.
 */
@interface AIVoiceRecorder : NSObject

+ (AIVoiceRecorder *)sharedRecorder;

@property (readonly, nonatomic) AIVoiceRecorderState state;

//! YES while the microphone is open
@property (readonly, nonatomic, getter=isRecording) BOOL recording;

//! YES while there is a note, growing, paused or playing, that has not been written or thrown away
@property (readonly, nonatomic) BOOL holdsRecording;

/*! @brief How long the note is so far, in seconds */
@property (readonly, nonatomic) NSTimeInterval duration;

/*!
 * @brief How loud the note has been, oldest first
 *
 * One number for each AIVoiceRecorderLevelInterval of the note, between 0 and 1, so that a
 * picture of the whole can be drawn while it is still being spoken.
 */
@property (readonly, nonatomic, copy) NSArray *levels;

/*! @brief How far playback has got, in seconds, while playing */
@property (readonly, nonatomic) NSTimeInterval playbackPosition;

/*!
 * @brief Begin a new note, asking for the microphone first if nobody has asked yet
 *
 * The handler runs on the main thread, once, and says whether anything is being recorded.
 */
- (void)startWithCompletion:(void (^)(BOOL began, NSString *problem))handler;

/*! @brief Let the microphone go and keep the note so far */
- (void)pause;

/*!
 * @brief Open the microphone again and carry on with the note
 *
 * Playback, if it is running, stops first. The handler runs on the main thread, once.
 */
- (void)resumeWithCompletion:(void (^)(BOOL began, NSString *problem))handler;

/*! @brief Play the note so far from its beginning; only while paused */
- (void)playFromStart;

/*! @brief Stop playing and be paused again */
- (void)stopPlaying;

/*!
 * @brief Finish, and write the note as an ogg opus file
 *
 * The handler runs on the main thread with the path of a file in the temporary directory,
 * or with a reason it has none. A recording of almost nothing counts as a reason: a note
 * shorter than half a second is somebody who changed their mind. Either way the recorder
 * holds nothing afterwards.
 */
- (void)stopAndWrite:(void (^)(NSString *path, NSTimeInterval duration, NSString *problem))handler;

/*! @brief Stop and throw away */
- (void)cancel;

@end
