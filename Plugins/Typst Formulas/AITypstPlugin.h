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

/*!
 * @class AITypstPlugin
 * @brief Formulas, written in Typst and sent as pictures
 *
 * Two ways in, for two different situations.
 *
 * The editor, on a shelf across the bottom of the chat, is the one to reach for when the formula
 * needs looking at before it goes: it shows the picture as it is typed and keeps the formulas used
 * before. It belongs to one conversation, which is why it lives in the chat window rather than in a
 * window of its own with no idea where its output is meant to go.
 *
 * The direct command renders whatever is selected in the message field and puts the picture in its
 * place. For a formula short enough to type in one go, opening an editor for it would be a nuisance.
 */
@interface AITypstPlugin : AIPlugin <NSMenuItemValidation> {
	NSMenuItem		*menuItem_showEditor;
	NSMenuItem		*menuItem_renderSelection;
	NSToolbarItem	*toolbarItem_editor;
}

@end
