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

/*!
 * @class AIVoiceRecorder
 * @brief Takes what the microphone hears and leaves a voice note behind
 *
 * One at a time, for the whole application: two recordings at once would be two people
 * talking over each other into the same file, and there is no window in which anybody would
 * want that.
 */
@interface AIVoiceRecorder : NSObject

+ (AIVoiceRecorder *)sharedRecorder;

@property (readonly, nonatomic, getter=isRecording) BOOL recording;

/*! @brief How long the recording has been running, in seconds */
@property (readonly, nonatomic) NSTimeInterval elapsed;

/*!
 * @brief Begin, asking for the microphone first if nobody has asked yet
 *
 * The handler runs on the main thread, once, and says whether anything is being recorded.
 */
- (void)startWithCompletion:(void (^)(BOOL began, NSString *problem))handler;

/*!
 * @brief Stop, and write what was heard as an ogg opus file
 *
 * The handler runs on the main thread with the path of a file in the temporary directory,
 * or with a reason it has none. A recording of almost nothing counts as a reason: a note
 * shorter than half a second is somebody who changed their mind.
 */
- (void)stopAndWrite:(void (^)(NSString *path, NSTimeInterval duration, NSString *problem))handler;

/*! @brief Stop and throw away */
- (void)cancel;

@end
