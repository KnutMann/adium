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

#import "AIJSXtrasPlugin.h"
#import "AIJSXtrasManager.h"
#import "AIJSXtrasPreferences.h"

@implementation AIJSXtrasPlugin {
	AIJSXtrasPreferences *_preferences;
}

- (void)installPlugin
{
	//The feature is on out of the box; the shipped plugins are ours and reach neither network nor disk
	[adium.preferenceController registerDefaults:@{ KEY_JSXTRAS_MASTER_ENABLED: @YES }
										forGroup:PREF_GROUP_JSXTRAS];

	//Bring the manager up now so its scan has run before the first chat opens
	[AIJSXtrasManager sharedManager];

	_preferences = [AIJSXtrasPreferences preferencePane];

	//A newly installed or removed plugin is picked up without a restart
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(xtrasChanged:)
												 name:AIXtrasDidChangeNotification
											   object:nil];
}

- (void)uninstallPlugin
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)xtrasChanged:(NSNotification *)notification
{
	//Only a plugin install/remove matters; the manager re-scans and tells the views
	if (!notification.object || [notification.object isEqualToString:@"AdiumPlugin"]) {
		[[AIJSXtrasManager sharedManager] rescan];
	}
}

@end
