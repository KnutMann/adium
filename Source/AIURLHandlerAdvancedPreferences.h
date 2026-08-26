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

#import <Adium/AIAdvancedPreferencePane.h>
#import "AIURLHandlerPlugin.h"

@class AISettingsFormView;

/*!
 * @class AIURLHandlerAdvancedPreferences
 * @brief The Default Client preference pane.
 *
 * The pane builds its view programmatically on top of AISettingsFormView (the
 * System Settings style card list); it no longer loads AIURLHandlerPreferences.xib.
 * What used to be a table with a service icon per row and an NSPopUpButtonCell
 * beside it is now one ordinary pop up row per scheme — there are two of them,
 * and a two row table was never worth its own height arithmetic.
 *
 * The controls below live in the view hierarchy, exactly as the nib's outlets
 * did; the ivars hold a reference of their own, which -viewWillClose gives up
 * along with the scheme list and the per-scheme cache.
 */
@interface AIURLHandlerAdvancedPreferences : AIAdvancedPreferencePane {
	AISettingsFormView	*settingsForm;			//Our view, typed; -view holds it too

	NSButton			*button_setDefault;
	NSSwitch			*checkBox_enforceDefault;

	NSArray				*servicesList;			//The schemes we offer a row for, in display order
	NSMutableDictionary	*services;				//scheme -> {name, applications, applicationsMenu}
	NSMutableArray		*popUpButtons;			//One pop up button per scheme, parallel to servicesList
}

/*!
 * @brief The default application of one or more schemes changed; show it.
 *
 * Called by -[AIURLHandlerPlugin setDefaultForScheme:toBundleID:] — whoever set
 * it, us or the plugin itself at launch. The name is the one the plugin has
 * always called and predates the table going away; renaming it would touch a
 * file this rebuild has no business in.
 */
- (void)refreshTable;

@end
