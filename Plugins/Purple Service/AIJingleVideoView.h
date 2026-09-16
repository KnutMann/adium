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
#import <WebRTC/RTCVideoRenderer.h>

/*!
 * @class AIJingleVideoView
 * @brief A view that shows what a call carries, and can say whether it did
 *
 * The framework's own Metal view showed nothing here while the decoder counted
 * hundreds of frames, and an opaque component that cannot be questioned is no
 * place to lose a picture. This one is a layer with pictures put into it: every
 * frame it is handed is converted and shown, it counts what it drew, and a test
 * can feed it a frame and read the result back out.
 */
@interface AIJingleVideoView : NSView <RTCVideoRenderer>

/*! @brief How many frames have actually been drawn, for tests and diagnosis */
@property (atomic, readonly) NSInteger renderedFrames;

/*!
 * @brief Has the picture been nothing but black for a while now?
 *
 * A guess from the picture alone, for the case where the other side switches its
 * camera off without saying so. Good enough to draw an icon over, never good
 * enough to decide anything else.
 */
@property (atomic, readonly) BOOL looksBlack;

/*! @brief The size of the last frame drawn */
@property (atomic, readonly) CGSize lastFrameSize;

/*!
 * @brief Fill the whole view, cropping what does not fit, instead of fitting it in
 *
 * A picture from a phone held upright leaves two black columns in a window shaped
 * for a desk, and somebody who would rather see a face than the black chooses this.
 */
@property (nonatomic) BOOL fillsTheFrame;

@end
