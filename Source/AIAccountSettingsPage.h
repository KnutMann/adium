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

@class AIAccount, AIAccountViewController, AISettingsFormView;

/*!
 * @class AIAccountSettingsPage
 * @brief One account's settings, as a page inside the accounts pane
 *
 * What the separate account window shows, laid out as cards and slid in over the account list rather
 * than opened beside it.
 *
 * The service's own views are hosted whole rather than rebuilt as rows. Nine services vend those
 * views out of their own nibs; rebuilding them here would mean forking all nine, and the tabs they
 * are arranged in today are the only thing that has to go, because a page of cards has no tabs.
 *
 * This does not save anything yet. The window it replaces saves on OK and discards on Cancel, and a
 * pane has neither, so an embedded editor has to write as it goes. That comes next, and separately,
 * because saveConfiguration renames accounts and forgets keychain passwords and would go from
 * running once per OK to running on every change.
 */
@interface AIAccountSettingsPage : NSViewController {
	AIAccount				*account;
	AIAccountViewController	*accountViewController;
	AISettingsFormView		*form;
	id						 backTarget;			//Not retained
	SEL						 backAction;
}

- (id)initWithAccount:(AIAccount *)inAccount backTarget:(id)inTarget action:(SEL)inAction;

- (AIAccount *)account;

/*!
 * @brief Let go of the account and the service's views
 */
- (void)tearDown;

@end
