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
 * @class AIPassthroughScrollView
 * @brief A scroll view for lists that are sized to their content, and so never scroll themselves
 *
 * A table hosted in a preference pane by @c -[AISettingsFormView addEdgeToEdgeRow:] is laid out at
 * the full height of its rows: it has no scrollers, no elasticity and nothing to scroll to. But an
 * @c NSScrollView handles @c -scrollWheel: whether or not it has anywhere to go, so the pane behind
 * it would stop scrolling for as long as the pointer rested over the list - the wheel event reaches
 * the innermost scroll view and dies there.
 *
 * This subclass hands those events to the enclosing scroll view instead, so the pane keeps scrolling
 * under the pointer wherever it happens to be. Use it for any list the form sizes to its content;
 * a scroll view that genuinely scrolls must not use it, as it would never scroll at all.
 */
@interface AIPassthroughScrollView : NSScrollView {
}

@end
