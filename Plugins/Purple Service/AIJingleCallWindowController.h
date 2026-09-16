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

#import <AppKit/AppKit.h>
#import "AIJingleCallController.h"

/*!
 * @class AIJingleCallWindowController
 * @brief One call's window: who, how long, hang up, and the pictures when there are any
 *
 * Built in code like the pairing panel. An audio call is a slim bar with the name,
 * the state and the hang up button; the moment a video track arrives, the window
 * grows a stage for it, with our own camera as a small corner preview. Closing the
 * window hangs up.
 */
@interface AIJingleCallWindowController : NSWindowController <NSWindowDelegate>

- (id)initWithCallController:(AIJingleCallController *)controller displayName:(NSString *)displayName;

/*!
 * @brief Run when the window really closes
 *
 * A finished call stays readable, so its window outlives the call itself. Nobody
 * else holds the controller then, and a controller nobody holds takes its
 * buttons' targets with it: the Close button did nothing while the title bar's
 * own close still worked. Whoever keeps us alive for the epilogue lets go here.
 */
@property (nonatomic, copy) void (^whenClosed)(void);

- (void)noteRinging;
- (void)noteAnswered;
- (void)noteConnected;

/*! @brief The peer turned its own microphone or camera off, or on again */
- (void)showWhatThePeerSends;
- (void)noteEndedWithReason:(NSString *)reason locally:(BOOL)locally;
- (void)attachRemoteVideoTrack:(RTCVideoTrack *)track;

@end
