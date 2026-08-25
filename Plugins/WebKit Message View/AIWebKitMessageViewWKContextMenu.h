/*
 * Adium is the property of its developers, whose names are listed in the copyright file included
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

/// Parsed `contextMenu` script message from the WKWebView message bridge (see
/// AIWebKitMessageViewWKController.m). Pure and side-effect-free so it can be
/// unit-tested directly (issue #152).
typedef struct {
	/// clientX from the JS event, in viewport coordinates.
	double x;
	/// clientY from the JS event, in viewport coordinates.
	double y;
	/// The image URL string from the body, or nil when absent or empty.
	NSString *imageURLString;
	/// Plain text of the message block that was right-clicked, or nil; capped at 400 characters.
	NSString *messageText;
	/// The protocol id of the message that was right-clicked, or nil; used to react to it.
	NSString *messageId;
	/// YES when the body is a well-formed contextMenu message; see AIWKContextMenuMessageFromBody.
	BOOL valid;
} AIWKContextMenuMessage;

/// Parses and validates a script-message body for the `contextMenu` handler.
///
/// A body is valid when it is a dictionary whose `type` is the string "contextMenu"
/// and whose `x`/`y` are NSNumber coordinates within [0, AIWKMaxContextMenuCoordinate].
/// JSON booleans (which parse to CFBoolean-backed NSNumbers) are not coordinates and are
/// rejected (issue #170). `imageURL`, when present, must be a non-empty string; it is
/// normalized to nil otherwise. Any other shape yields `valid == NO` with undefined
/// x/y/imageURLString.
///
/// @param body The WKScriptMessage body (nil, a non-dictionary, or a dictionary).
/// @return The parsed message; `valid` indicates whether the fields are meaningful.
AIWKContextMenuMessage AIWKContextMenuMessageFromBody(id body);

/// The inclusive upper bound for context-menu x/y coordinates, in viewport points.
/// Coordinates outside [0, AIWKMaxContextMenuCoordinate] are rejected by
/// AIWKContextMenuMessageFromBody (issue #170).
extern const double AIWKMaxContextMenuCoordinate;

/// Whether a raw double is usable as a context-menu coordinate: finite and within
/// [0, AIWKMaxContextMenuCoordinate]. Non-finite values (INFINITY, NAN) would misposition
/// NSMakePoint and are rejected.
///
/// This is the numeric-range half only. It takes a raw double, so it cannot express the
/// boolean-vs-number distinction: JSON true/false parse to CFBoolean-backed NSNumbers whose
/// doubleValue (1.0/0.0) passes this range check. Reject booleans at the NSNumber layer
/// before calling this, as AIWKContextMenuMessageFromBody does (issue #170).
BOOL AIWKContextMenuCoordinateDoubleIsInRange(double coordinate);

/// Returns the image URL for a context-menu `imageURL` string, or nil when the
/// string does not form a usable URL. Thin wrapper around +[NSURL URLWithString:]
/// extracted so the parse gate can be property-tested (issue #152).
NSURL *AIWKImageURLFromString(NSString *imageURLString);

/// Whether "Save Image As" should be offered for an image URL: file: URLs are
/// copied directly, http(s) URLs are downloaded first (issue #151). Any other
/// scheme — or nil — is not savable.
BOOL AIWKCanSaveImageURL(NSURL *imageURL);

/// The default file name for saving an image from `imageURL`: its last path component when
/// that is a real component (non-empty, not "/", not "." or ".."), else `fallbackName`. The
/// degenerate-component guard is delegated to AIHTTPDownloadSafeSaveName (issue #182).
/// Extracted from `saveImageAs:` so it can be property-tested (issue #169). Pure and
/// side-effect-free.
///
/// @param imageURL The image URL, or nil.
/// @param fallbackName Used when the URL has no usable path component; must be non-nil.
/// @return A non-empty name that is never "/".
NSString *AIWKDefaultSaveNameForURL(NSURL *imageURL, NSString *fallbackName);

/// The domain for errors returned by AIWKImageDownloadValidationErrorForResponse.
FOUNDATION_EXPORT NSString *const AIWKImageDownloadErrorDomain;

/// Reasons a remote image download was rejected before touching the user-picked destination
/// (issue #168).
typedef NS_ENUM(NSInteger, AIWKImageDownloadErrorCode) {
	/// The response was not an NSHTTPURLResponse at all.
	AIWKImageDownloadErrorNotHTTP = 1,
	/// The HTTP status was outside 2xx.
	AIWKImageDownloadErrorBadStatus,
	/// The Content-Type was absent or not an image/*.
	AIWKImageDownloadErrorWrongContentType,
	/// The declared or measured byte count exceeded AIWKMaxRemoteImageDownloadBytes.
	AIWKImageDownloadErrorTooLarge,
};

/// The cap for a remote image download, in bytes, before the user-picked destination is
/// committed. Checked against the declared Content-Length when the response arrives and
/// against the actual downloaded bytes just before the destination is committed, so a server
/// that omits or misstates Content-Length cannot bypass it (issue #168).
extern const int64_t AIWKMaxRemoteImageDownloadBytes;

/// Validates an NSURLSession response before committing a downloaded image to the user-picked
/// destination. Returns nil when the response is acceptable (HTTP 2xx, image/* Content-Type,
/// size at or under AIWKMaxRemoteImageDownloadBytes), or an NSError in
/// AIWKImageDownloadErrorDomain describing the rejection (issue #168).
///
/// A response with an unknown Content-Length (expectedContentLength == -1) passes the size check
/// here — there is no declared length to compare — and is enforced instead against the actual
/// downloaded bytes by the post-download check before the destination is committed.
///
/// @param response The NSURLSession response, possibly nil.
/// @return nil when acceptable; an error describing the violated check otherwise.
NSError *AIWKImageDownloadValidationErrorForResponse(NSURLResponse *response);

/// The TooLarge rejection for a download whose byte count exceeds
/// AIWKMaxRemoteImageDownloadBytes. Shared by the response-time check (declared
/// Content-Length) and the post-download check (actual bytes on disk), so the error the
/// user sees is identical whichever check fires (issue #168).
///
/// @param byteCount The offending byte count, declared or measured.
/// @return An NSError in AIWKImageDownloadErrorDomain with code AIWKImageDownloadErrorTooLarge.
NSError *AIWKImageDownloadValidationErrorForByteCount(int64_t byteCount);
