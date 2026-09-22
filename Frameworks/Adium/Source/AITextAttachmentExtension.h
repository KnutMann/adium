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

/*!
 * @brief What a voice note's file is called
 *
 * Recorded notes are named after this, and the message view knows it: a link to a file with this
 * in its name becomes a player rather than a link. Spelled here so that the recorder, the chat
 * and the protocol side all mean the same thing by it.
 */
#define AIVoiceNoteFilePrefix		@"AdiumVoice_"

@interface AITextAttachmentExtension : NSTextAttachment <NSCopying> {
	NSString	*stringRepresentation;
	BOOL	shouldSaveImageForLogging;
	BOOL	hasAlternate;
	NSString	*path;
	NSImage		*image;
	NSString	*imageClass; //set as class attribute in html, used to tell images apart for CSS
	BOOL		shouldAlwaysSendAsText;
	BOOL		leavesLinkWhenSent;
}

+ (AITextAttachmentExtension *)textAttachmentExtensionFromTextAttachment:(NSTextAttachment *)textAttachment;

@property (readwrite, nonatomic, copy) NSString *string;
@property (readwrite, nonatomic, copy) NSString *imageClass;
@property (readwrite, nonatomic) BOOL shouldSaveImageForLogging;
@property (readwrite, nonatomic) BOOL hasAlternate;
@property (readwrite, nonatomic, copy) NSString *path;
@property (readonly, nonatomic) NSImage *iconImage;
@property (readonly, nonatomic) BOOL attachesAnImage;
@property (readwrite, nonatomic) BOOL shouldAlwaysSendAsText;
/*!
 * @brief Whether the chat keeps a link to the file once this has been sent as one
 *
 * An attachment sent as a file is taken out of the message, and for most of them that is right:
 * the transfer is the event, and the window that lists transfers is where it belongs. A voice
 * note is not like that. It is a thing said, it belongs in the conversation beside what else was
 * said, and the person who recorded it should be able to play it back there. So the chat is shown
 * a link to the file it was sent from, which the message view turns into a player.
 */
@property (readwrite, nonatomic) BOOL leavesLinkWhenSent;
@end
