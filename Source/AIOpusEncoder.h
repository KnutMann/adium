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
 * @header AIOpusEncoder
 * @brief Sound as a voice note is sent: opus packets in an ogg stream
 *
 * Not a matter of taste. A voice note reaches WhatsApp as a voice note, with its waveform
 * and its little play button, only when it arrives as opus in an ogg container; anything
 * else lands as a document nobody plays. The XMPP clients people actually use record the
 * same thing, so one format serves both and there is nothing to choose between.
 *
 * Mono at 48 kHz throughout, which is what the codec wants anyway and what a voice needs.
 */

/*!
 * @brief Write mono 48 kHz samples to an ogg opus file
 *
 * @param path      where to write
 * @param samples   signed 16 bit samples, mono, 48000 per second
 * @param count     how many of them
 * @param error     filled in when the answer is NO
 *
 * @result YES when the file is there and complete
 */
BOOL AIOpusWriteOggFile(NSString *path, const int16_t *samples, NSUInteger count, NSError **error);
