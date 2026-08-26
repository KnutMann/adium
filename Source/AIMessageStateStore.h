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
 * @class AIMessageStateStore
 * @brief What became of a message after it was said
 *
 * A transcript records what was said and by whom. What happened to a message
 * afterwards, that it reached the other side, was read there, was reacted to,
 * arrives later and belongs to no single line of text, so it is kept here
 * instead, under the id the protocol gave the message.
 *
 * A conversation reopened days later is rebuilt from the transcript, and the
 * excerpt it replays asks this store what it knows about each message it
 * carries. Without it the ticks and the reactions live only as long as the
 * window does.
 *
 * Only messages that have an id can be remembered, which today means the
 * protocols that carry one.
 */
@interface AIMessageStateStore : NSObject {
	NSMutableDictionary	*states;
	BOOL				 saveScheduled;
}

+ (AIMessageStateStore *)sharedStore;

/*!
 * @brief Remember how far a message travelled
 * @param confirmation 0 nothing confirmed, 1 the server accepted it, 2 delivered, 3 read
 */
- (void)setConfirmation:(NSInteger)confirmation forMessageId:(NSString *)messageId;

/*!
 * @brief Remember the emoji one sender put on a message
 *
 * The whole set for that sender, as the message view holds it: an empty array
 * means the sender took their reaction back.
 */
- (void)setReactions:(NSArray *)reactions forSender:(NSString *)sender messageId:(NSString *)messageId;

- (NSInteger)confirmationForMessageId:(NSString *)messageId;
- (NSDictionary *)reactionsForMessageId:(NSString *)messageId;

@end
