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

#import <Adium/AIPlugin.h>

//The toolbar item and the button in the message field, and the name the recorder's shelf answers with
#define VOICE_ITEM_IDENTIFIER		@"VoiceNote"

/*!
 * @class AIVoiceNotePlugin
 * @brief A button that opens the recorder on the conversation's shelf
 *
 * The recorder itself is AIVoiceNoteShelfView. It belongs to one conversation, records, pauses,
 * plays back and sends; the button here opens it, and while it is open the same button pauses
 * and resumes. The toolbar item is the same button for people who keep the message field bare.
 */
@interface AIVoiceNotePlugin : AIPlugin {
	NSToolbarItem	*toolbarItem;
	NSTimer			*ticker;
}

@end
