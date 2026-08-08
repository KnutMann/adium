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
#import <libpurple/libpurple.h>

/*!
 * @brief Window for purple field requests that contain an image
 *
 * Presents title, texts, the string field values (e.g. a pairing code)
 * and the image (e.g. a WhatsApp login QR code) in a simple non-modal
 * panel. Used because the generic HTML-form based request controller
 * cannot handle image fields.
 */
@interface AIPurpleImageRequestController : NSObject {
	NSPanel					*panel;
	PurpleRequestFields		*fields;
	GCallback				okCb;
	GCallback				cancelCb;
	void					*userData;
	BOOL					callbackInvoked;
}

+ (instancetype)showImageRequestWithTitle:(NSString *)title
								  primary:(NSString *)primary
								secondary:(NSString *)secondary
									fields:(PurpleRequestFields *)fields
								   okText:(NSString *)okText
									 okCb:(GCallback)okCb
							   cancelText:(NSString *)cancelText
								 cancelCb:(GCallback)cancelCb
								 userData:(void *)userData;

- (void)purpleRequestClose;

@end
