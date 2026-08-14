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

@class AIChat, AITypstRenderer;

/*!
 * @class AITypstEditorView
 * @brief The formula editor that sits on a chat's shelf
 *
 * Source at the top, the picture it produces underneath, and the formulas used before along the
 * bottom. Everything it needs is in one view, and the view belongs to one conversation, so pressing
 * insert has somewhere unambiguous to put the result.
 *
 * There is no palette of symbols. Typst's own documentation is better than any list that could be
 * put here, and unlike a copy it does not go out of date, so the bottom bar links to it instead.
 *
 * The view owns its own logic rather than having a separate controller. That is not laziness: it has
 * no model of its own beyond the text in its field, its lifetime is exactly the lifetime of the
 * shelf it sits on, and letting the view hierarchy own it means closing the shelf disposes of
 * everything with no bookkeeping anywhere else.
 */
@interface AITypstEditorView : NSView <NSTextViewDelegate> {
	AIChat			*chat;

	NSTextView		*textView_source;
	NSImageView		*imageView_preview;
	NSTextField		*textField_error;
	NSButton		*button_insert;
	NSStackView		*view_historyStrip;
	NSScrollView	*scrollView_history;

	AITypstRenderer	*activeRender;
	NSUInteger		 renderGeneration;
	NSString		*renderedPath;
	NSString		*renderedFormula;
	BOOL			 renderedPathWasInserted;

	NSMutableArray	*pendingThumbnails;
	AITypstRenderer	*thumbnailRender;
}

/*!
 * @brief Create an editor for one conversation
 *
 * @param inChat The chat whose entry field the insert button writes into
 */
- (id)initWithChat:(AIChat *)inChat;

/*!
 * @brief Put the keyboard in the source field
 *
 * Called when the shelf opens, so that the shortcut leads straight to typing.
 */
- (void)takeFocus;

@end
