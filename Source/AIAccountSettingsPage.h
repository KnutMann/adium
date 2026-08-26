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

@class AIAccount, AIAccountPlan, AIAccountPlanFormBuilder, AISettingsFormView;

/*!
 * @class AIAccountSettingsPage
 * @brief One account's settings, as a page inside the accounts pane
 *
 * What the separate account window shows, laid out as cards and slid in over the account list rather
 * than opened beside it.
 *
 * The page owns no knowledge of any service. It asks the account for its plan, hands that to the one
 * form builder there is, and is told which field was changed so it can decide whether the account has
 * to hear about it.
 *
 * There is no OK to wait for, so the plan writes every change where it belongs as it happens. What
 * this page adds is telling the account afterwards, once per burst and only when something really was
 * changed, because that reconfigures a live connection and can bounce it.
 */
@interface AIAccountSettingsPage : NSViewController {
	AIAccount					*account;
	AIAccountPlan				*plan;
	AIAccountPlanFormBuilder	*builder;
	AISettingsFormView			*form;
	__unsafe_unretained id		 backTarget;		//Not retained
	SEL							 backAction;
	BOOL						 committing;
	BOOL						 edited;			//Whether anything on the page was actually changed
}

- (id)initWithAccount:(AIAccount *)inAccount backTarget:(id)inTarget action:(SEL)inAction;

- (AIAccount *)account;

/*!
 * @brief Let go of the account and its plan
 */
- (void)tearDown;

/*!
 * @brief Tell the account that its settings changed, if any did
 *
 * The values themselves are already written. Does nothing at all when nothing was changed, so leaving
 * a page that was only looked at does not bounce a connection.
 */
- (void)commit;

@end
