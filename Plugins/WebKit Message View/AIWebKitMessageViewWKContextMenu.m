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

#import "AIWebKitMessageViewWKContextMenu.h"

#import <math.h>

// Upstream AdiumY declares AIHTTPDownloadSafeSaveName in its Adium framework
// (Frameworks/Adium/Source/AIHTTPDownloadValidation.h). Our tree does not have that
// file, so the small leaf-name sanitizer is implemented locally here instead.

// YES iff name's last path component is a real, non-degenerate leaf: non-empty, not ".", "..",
// "/", and not whitespace-only.
static NSString *AIWKSafeLeafForName(NSString *name)
{
	NSString *leaf = [name lastPathComponent];
	if (leaf == nil || [leaf length] == 0 || [leaf isEqualToString:@"."] || [leaf isEqualToString:@".."] ||
		[leaf isEqualToString:@"/"] ||
		([[leaf stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0)) {
		return nil;
	}
	return leaf;
}

static NSString *AIHTTPDownloadSafeSaveName(NSString *remotePath, NSString *fallbackName)
{
	NSString *safeName = AIWKSafeLeafForName(remotePath);
	if (safeName != nil) {
		return safeName;
	}

	// The fallback must satisfy the same leaf-safety contract, not pass through verbatim.
	safeName = AIWKSafeLeafForName(fallbackName);
	return (safeName != nil) ? safeName : @"";
}

const double AIWKMaxContextMenuCoordinate = 100000.0;

NSString *const AIWKImageDownloadErrorDomain = @"AIWKImageDownloadErrorDomain";

const int64_t AIWKMaxRemoteImageDownloadBytes = 50 * 1024 * 1024;

// JSON true/false parse to CFBoolean-backed NSNumbers whose doubleValue is 1.0/0.0 — numerically
// in range, but a boolean is not a coordinate. Reject them at the object layer, since the
// exposed double predicate cannot express the distinction (issue #170).
static BOOL AIWKContextMenuCoordinateNumberIsValid(NSNumber *coordinate)
{
	if (CFGetTypeID((__bridge CFTypeRef)coordinate) == CFBooleanGetTypeID()) {
		return NO;
	}
	return AIWKContextMenuCoordinateDoubleIsInRange([coordinate doubleValue]);
}

AIWKContextMenuMessage AIWKContextMenuMessageFromBody(id body)
{
	AIWKContextMenuMessage message = {0};

	if (![body isKindOfClass:[NSDictionary class]]) {
		return message;
	}

	NSDictionary *dict = (NSDictionary *)body;
	NSString *type = [dict objectForKey:@"type"];
	if (![type isKindOfClass:[NSString class]] || ![type isEqualToString:@"contextMenu"]) {
		return message;
	}

	NSNumber *clientX = [dict objectForKey:@"x"];
	NSNumber *clientY = [dict objectForKey:@"y"];
	if (![clientX isKindOfClass:[NSNumber class]] || ![clientY isKindOfClass:[NSNumber class]] ||
		!AIWKContextMenuCoordinateNumberIsValid(clientX) || !AIWKContextMenuCoordinateNumberIsValid(clientY)) {
		return message;
	}

	NSString *imageURLString = [dict objectForKey:@"imageURL"];
	if (![imageURLString isKindOfClass:[NSString class]] || [imageURLString length] == 0) {
		imageURLString = nil;
	}

	message.x = [clientX doubleValue];
	message.y = [clientY doubleValue];
	message.imageURLString = imageURLString;
	message.valid = YES;
	return message;
}

NSURL *AIWKImageURLFromString(NSString *imageURLString)
{
	if (imageURLString == nil) {
		return nil;
	}

	return [NSURL URLWithString:imageURLString];
}

BOOL AIWKCanSaveImageURL(NSURL *imageURL)
{
	if (imageURL == nil) {
		return NO;
	}

	if ([imageURL isFileURL]) {
		return YES;
	}

	NSString *scheme = [imageURL scheme];
	return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

BOOL AIWKContextMenuCoordinateDoubleIsInRange(double coordinate)
{
	return isfinite(coordinate) && coordinate >= 0.0 && coordinate <= AIWKMaxContextMenuCoordinate;
}

NSString *AIWKDefaultSaveNameForURL(NSURL *imageURL, NSString *fallbackName)
{
	if (imageURL == nil) {
		return fallbackName;
	}
	// Delegate the degenerate-component guard (nil, empty, "/", ".", "..", whitespace) to the
	// shared download-path sanitizer (issue #182).
	return AIHTTPDownloadSafeSaveName([imageURL lastPathComponent], fallbackName);
}

static NSError *AIWKImageDownloadValidationError(AIWKImageDownloadErrorCode code, NSString *reason)
{
	return [NSError errorWithDomain:AIWKImageDownloadErrorDomain
							   code:code
						   userInfo:@{NSLocalizedDescriptionKey : reason}];
}

NSError *AIWKImageDownloadValidationErrorForResponse(NSURLResponse *response)
{
	if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
		return AIWKImageDownloadValidationError(AIWKImageDownloadErrorNotHTTP,
												@"Remote image download: response is not HTTP; refusing to save.");
	}

	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
	NSInteger statusCode = [httpResponse statusCode];
	if (statusCode < 200 || statusCode > 299) {
		return AIWKImageDownloadValidationError(
			AIWKImageDownloadErrorBadStatus,
			[NSString stringWithFormat:@"Remote image download: HTTP status %ld; refusing to save.", (long)statusCode]);
	}

	NSString *contentType = [[httpResponse MIMEType] lowercaseString];
	// Accept only "image/<subtype>": a bare "image/" prefix with no subtype (e.g. a server
	// sending just "image/") is not an image content type. sizeof("image/") - 1 is the prefix
	// length, so anything at or under it has no subtype after the slash.
	if (contentType == nil || ![contentType hasPrefix:@"image/"] || [contentType length] <= sizeof("image/") - 1) {
		// The server's Content-Type may be absent entirely; show "<none>" rather than Foundation's
		// "(null)" so the alert reads cleanly.
		NSString *displayContentType = (contentType != nil) ? contentType : @"<none>";
		return AIWKImageDownloadValidationError(
			AIWKImageDownloadErrorWrongContentType,
			[NSString stringWithFormat:@"Remote image download: content type \"%@\" is not an image; refusing to save.",
									   displayContentType]);
	}

	int64_t contentLength = [httpResponse expectedContentLength];
	if (contentLength > AIWKMaxRemoteImageDownloadBytes) {
		return AIWKImageDownloadValidationErrorForByteCount(contentLength);
	}

	return nil;
}

NSError *AIWKImageDownloadValidationErrorForByteCount(int64_t byteCount)
{
	return AIWKImageDownloadValidationError(
		AIWKImageDownloadErrorTooLarge,
		[NSString stringWithFormat:@"Remote image download: %lld bytes exceeds the %lld byte cap; refusing to save.",
								   byteCount, AIWKMaxRemoteImageDownloadBytes]);
}
