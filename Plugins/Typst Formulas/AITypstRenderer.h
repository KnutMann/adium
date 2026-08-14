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

/*!
 * @class AITypstRenderer
 * @brief Turns a line of Typst math into a PNG on disk
 *
 * Rendering is asynchronous because it runs a separate program, and it is quick enough to drive a live
 * preview: a formula of ordinary length takes on the order of twenty milliseconds. Every render writes
 * a fresh file into a directory of its own under the temporary directory, so that two renders never
 * race for the same name and so that the caller can hand the path straight to something that wants to
 * keep it, such as a message attachment.
 */
@interface AITypstRenderer : NSObject {
	NSTask			*task;
	NSPipe			*errorPipe;
	NSString		*outputPath;
	NSString		*sourceDirectory;
	void			(^completion)(NSString *path, NSString *errorMessage);
}

/*!
 * @brief Is the typst binary present?
 *
 * Answered from a cached lookup, so this is cheap to call repeatedly, for instance to keep a button
 * enabled or disabled.
 */
+ (BOOL)typstIsAvailable;

/*!
 * @brief Where the typst binary was found, or nil
 *
 * Useful for telling the user what to install and where it was looked for.
 */
+ (NSString *)typstPath;

/*!
 * @brief Render one formula
 *
 * The picture is always black on opaque white. There is deliberately no way to ask for anything else:
 * it is going to be sent, and once it has been sent the background it is shown against belongs to
 * somebody else's client and somebody else's choice of theme. Colours picked to suit the window the
 * formula was typed in are exactly the ones that fail at the other end.
 *
 * @param formula Typst math syntax, without the surrounding dollar signs
 * @param pointSize Size of the type before the resolution factor is applied, or 0 for the default
 * @param handler Called on the main thread with the path to a PNG, or with nil and a message describing
 *                what typst objected to. Exactly one of the two is non-nil.
 *
 * @result An object which owns the running task. Keep it if you want to be able to cancel; it stays
 *         alive on its own until the render finishes either way.
 */
+ (AITypstRenderer *)renderFormula:(NSString *)formula
						 pointSize:(CGFloat)pointSize
						completion:(void (^)(NSString *path, NSString *errorMessage))handler;

/*!
 * @brief The size the picture should be drawn at, given how many pixels it has
 *
 * A rendered formula has more pixels than it has points, because it is rendered above screen
 * resolution so that it survives being enlarged at the far end. Anything drawing it has to be told
 * that, since the file itself does not say: typst writes no physical resolution into the PNG, so a
 * reader left to itself assumes one pixel is one point and draws the formula several times too
 * large. Pass an image's pixel dimensions and set the result as the image's size.
 *
 * @param pixelSize The representation's pixel dimensions
 * @result The same picture measured in points
 */
+ (NSSize)naturalSizeForPixelSize:(NSSize)pixelSize;

/*!
 * @brief Wrap a rendered formula so that it can be put into a message
 *
 * The attachment carries the path, which is what the send path hands to the account, and the formula
 * as its text, which is what gets logged and what a protocol unable to carry a picture falls back
 * to. Setting the path is not optional: an attachment without one is dropped from the message rather
 * than sent.
 *
 * @param path A PNG written by this class
 * @param formula The source it was rendered from
 * @result An attributed string of length one holding the attachment, or nil if the file will not load
 */
+ (NSAttributedString *)attachmentStringForImageAtPath:(NSString *)path formula:(NSString *)formula;

/*!
 * @brief Throw away a finished render
 *
 * A render that succeeded leaves its picture on disk, because the caller may be about to hand that
 * path to a message and nothing else knows when it has finished with it. Anything that produced a
 * picture it then decided not to use should say so here.
 *
 * Do not call this for a path that has been put into a message. The attachment refers to the file by
 * name and the file has to still be there when the message is sent.
 *
 * @param path A path returned by a completion handler
 */
+ (void)discardRenderAtPath:(NSString *)path;

/*!
 * @brief Abandon a render whose result is no longer wanted
 *
 * The completion handler is not called afterwards. A live preview does this on every keystroke.
 */
- (void)cancel;

@end
