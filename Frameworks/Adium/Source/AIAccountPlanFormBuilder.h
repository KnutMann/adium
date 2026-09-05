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

@class AIAccountPlan, AIAccountPlanField, AISettingsFormView;

/*!
 * @class AIAccountPlanFormBuilder
 * @brief Turns a plan into rows, and is the only thing that does
 *
 * Every account's settings are built here, so no service can end up looking different from another,
 * and no plan ever touches a view. A control is wired to this builder, which writes what was changed
 * through the plan and then tells its target which field it was.
 *
 * Values are written as they change, because a settings pane has no OK to wait for.
 */
@interface AIAccountPlanFormBuilder : NSObject {
	AIAccountPlan		*plan;
	NSMutableDictionary	*fieldsByName;
	NSMutableDictionary	*controlsByName;
	__unsafe_unretained id	 changeTarget;		//Not retained
	SEL					 changeAction;
}

- (id)initWithPlan:(AIAccountPlan *)inPlan;

/*!
 * @brief Who to tell when a field was changed
 *
 * The action takes the AIAccountPlanField that was written, so a host can decide whether the change
 * is one the account has to be told about.
 */
- (void)setChangeTarget:(id)target action:(SEL)action;

/*!
 * @brief Add every card of the plan to @a form
 */
- (void)buildInForm:(AISettingsFormView *)form;

/*!
 * @brief Put the value the plan really holds back into a field's control
 *
 * After a commit the two can differ: an account name is filtered, a phone number normalized or
 * refused. Text fields only.
 */
- (void)reloadValueForField:(AIAccountPlanField *)field;

/*!
 * @brief As above, without one card, which is going somewhere else
 */
- (void)buildInForm:(AISettingsFormView *)form skippingCard:(NSString *)cardIdentifier;

/*!
 * @brief Add one card of the plan to @a form
 *
 * For a card that belongs on a page of its own. The same builder does both, so a field written on
 * either page reaches the same plan and reports to the same target.
 */
- (void)buildCard:(NSString *)cardIdentifier inForm:(AISettingsFormView *)form;

/*!
 * @brief Whether that card would put anything on a page at all
 */
- (BOOL)hasFieldsInCard:(NSString *)cardIdentifier;

/*!
 * @brief Add a row leading somewhere else to the end of a card
 *
 * For the way to a card that is shown on a page of its own. Opens the card first where it has no
 * rows to sit under, so that the row cannot land in whatever card came before it.
 */
- (void)addNavigationRowTo:(NSString *)cardIdentifier
					inForm:(AISettingsFormView *)form
					 label:(NSString *)label
					target:(id)target
					action:(SEL)action;

@end
