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

#import "AIPreferencePane.h"

@class AISettingsFormView;

/*!
 * @class ESFileTransferPreferences
 * @brief The File Transfer preference pane.
 *
 * The pane builds its view programmatically on top of AISettingsFormView (the
 * System Settings style card list); it no longer loads FileTransferPrefs.xib.
 * The former checkboxes are NSSwitches whose title lives in the row label, and
 * every preference keeps the exact binding — same key, same group — and the
 * exact action it had in the nib.
 *
 * The controls below are owned by the view hierarchy, exactly as the nib's
 * outlets were; the ivars hold them as well and let go in -viewWillClose.
 */
@interface ESFileTransferPreferences : AIPreferencePane {
	AISettingsFormView	*settingsForm;			//Our view, typed; -view holds the same object

	NSPopUpButton		*popUp_downloadLocation;
	NSSwitch			*checkBox_autoAcceptFiles;
	NSSwitch			*checkBox_autoAcceptOnlyFromCLList;
	NSSwitch			*checkBox_autoOpenFiles;
	NSSwitch			*checkBox_showProgress;

	NSMutableArray		*establishedBindings;	//NSArrays of (object, binding name), unbound when the view closes
}

@end
