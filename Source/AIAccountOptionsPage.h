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

@class AIAccountPlanFormBuilder, AISettingsFormView;

/*!
 * @class AIAccountOptionsPage
 * @brief The options nobody curated, on a page of their own
 *
 * What a protocol declares and no plan file mentions. There can be a dozen of them, they are named
 * the way the protocol names them, and most accounts never need one, so putting them behind a row
 * with a chevron keeps them reachable without meeting them first.
 *
 * The page shares the builder with the account page it was opened from, so a field changed here goes
 * to the same plan and is reported to the same target.
 */
@interface AIAccountOptionsPage : NSViewController {
	AIAccountPlanFormBuilder	*builder;
	AISettingsFormView			*form;
	NSString					*cardIdentifier;
}

- (id)initWithBuilder:(AIAccountPlanFormBuilder *)inBuilder card:(NSString *)inCardIdentifier;

@end
