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

#import "ESStatusPreferencesPlugin.h"
#import "ESStatusPreferences.h"
#import <Adium/AIMenuControllerProtocol.h>
#import "AIStatusController.h"
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIDictionaryAdditions.h>
#import <AIUtilities/AIStringAdditions.h>

#define	STATUS_DEFAULT_PREFS @"StatusDefaults"

/* The keys of the second, separate idle stage, which no longer exists. They live here rather than
 * in AIStatusControllerProtocol.h because nothing but the migration below may read them again — and
 * they are deliberately gone from StatusDefaults.plist, so -preferenceForKey: answers nil for them
 * and that nil is itself the mark of "already migrated". */
#define OLD_KEY_STATUS_AUTO_AWAY				@"Auto Away"
#define OLD_KEY_STATUS_AUTO_AWAY_INTERVAL		@"Auto Away Interval"
#define OLD_KEY_STATUS_FUS						@"Fast User Switching Auto Away"
#define OLD_KEY_STATUS_SS						@"ScreenSaver Auto Away"

/* Twenty minutes, the auto-away duration StatusDefaults.plist used to register. It has to be
 * written out here because it is gone from the plist: a user who ticked the checkbox and left the
 * number alone has no stored duration at all, and asking for the key answers nil. Reading that nil
 * as "nothing to carry over" would leave such a user on the reporting duration — ten minutes — and
 * change their status in front of their contacts twice as early as they ever asked for. */
#define OLD_DEFAULT_AUTO_AWAY_INTERVAL			1200.0

@interface ESStatusPreferencesPlugin ()
- (void)showStatusPreferences:(id)sender;
- (void)mergeTheTwoIdleSettings;
@end

/*!
 * @class ESStatusPreferencesPlugin
 * @brief Component to install our status preferences pane
 */
@implementation ESStatusPreferencesPlugin

/*!
 * @brief Install
 *
 * Install our preference pane, and add a menu item to the Status menu which opens it.
 */
- (void)installPlugin
{
	NSMenuItem *menuItem;
	
	/* One pane, not two: the Advanced pane of the same name held only the Now Playing format,
	 * which lives on the main Status pane now, beside the list its status is switched on in. */
    preferences = (ESStatusPreferences *)[ESStatusPreferences preferencePaneForPlugin:self];

	//Add our menu item
	menuItem = [[NSMenuItem alloc] initWithTitle:[AILocalizedString(@"Edit Status Menu",nil) stringByAppendingEllipsis]
																	 target:self
																	 action:@selector(showStatusPreferences:)
															  keyEquivalent:@""];
	[adium.menuController addMenuItem:menuItem toLocation:LOC_Status_Additions];
	
	//Register defaults
    [adium.preferenceController registerDefaults:[NSDictionary dictionaryNamed:STATUS_DEFAULT_PREFS
																		forClass:[self class]]
										  forGroup:PREF_GROUP_STATUS_PREFERENCES];

	/* After the defaults, and before AIAutomaticStatus is loaded (AICoreComponentLoader loads us
	 * first), so that it reads the merged values at its very first preference notification. */
	[self mergeTheTwoIdleSettings];
}

/*!
 * @brief Carry a user's two idle settings over into the one that is left
 *
 * Adium used to have two idle stages: one which told contacts about the idleness and one which,
 * some minutes later, changed the status. On screen they were indistinguishable, and they are one
 * setting now — one switch and one duration, plus a status menu whose "Do not change" is the off
 * switch of the status change.
 *
 * Which of the two durations wins is not a toss-up. Once the auto-away duration had run out, the
 * contact already saw another status with another message: at that moment the user was visibly away
 * anyway, so taking that duration over can never give away more than before — the idle report falls
 * either later than it used to (600 against 1200 in the defaults) or exactly on the moment at which
 * the status changed regardless. The other way round would be a tightening: whoever deliberately set
 * twenty minutes would suddenly go "away" in front of their contacts after ten, without ever having
 * asked for it. With auto-away switched off its duration was never in force and mostly never
 * touched (the default was 1200) — then the reporting duration has to win, or an unused setting
 * would move a used one. A stored number is not what makes the auto-away duration count: whoever
 * ticked the checkbox and left the twenty minutes as they found them stored nothing at all, and
 * those twenty minutes were as much in force as any typed number.
 *
 * The OR on the switch keeps anyone from quietly losing a function they had switched on. Resetting
 * the three status IDs when their old switch was off is not optional either: without it, everyone
 * who once picked a status and then cleared the checkbox would find their status changing from now
 * on, out of the blue.
 */
- (void)mergeTheTwoIdleSettings
{
	NSNumber	*oldAutoAway = [adium.preferenceController preferenceForKey:OLD_KEY_STATUS_AUTO_AWAY
																	  group:PREF_GROUP_STATUS_PREFERENCES];
	NSNumber	*oldAutoAwayInterval = [adium.preferenceController preferenceForKey:OLD_KEY_STATUS_AUTO_AWAY_INTERVAL
																			  group:PREF_GROUP_STATUS_PREFERENCES];
	NSNumber	*oldFUS = [adium.preferenceController preferenceForKey:OLD_KEY_STATUS_FUS
																 group:PREF_GROUP_STATUS_PREFERENCES];
	NSNumber	*oldScreenSaver = [adium.preferenceController preferenceForKey:OLD_KEY_STATUS_SS
																		 group:PREF_GROUP_STATUS_PREFERENCES];

	//Nothing of the old shape left: either migrated already or never seen an older Adium
	if (!oldAutoAway && !oldAutoAwayInterval && !oldFUS && !oldScreenSaver) return;

	BOOL	autoAwayWasOn = [oldAutoAway boolValue];

	if (autoAwayWasOn) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:YES]
										   forKey:KEY_STATUS_REPORT_IDLE
											group:PREF_GROUP_STATUS_PREFERENCES];

		/* Unconditionally, falling back on the duration the old default stood for: the duration
		 * which was in force is what has to be carried over, whether the user typed it or was
		 * given it. */
		[adium.preferenceController setPreference:(oldAutoAwayInterval ?
												   oldAutoAwayInterval :
												   [NSNumber numberWithDouble:OLD_DEFAULT_AUTO_AWAY_INTERVAL])
										   forKey:KEY_STATUS_REPORT_IDLE_INTERVAL
											group:PREF_GROUP_STATUS_PREFERENCES];

	} else {
		//Its status is unreachable from now on, so it must not go on being set
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:STATUS_STATE_ID_NONE]
										   forKey:KEY_STATUS_AUTO_AWAY_STATUS_STATE_ID
											group:PREF_GROUP_STATUS_PREFERENCES];
	}

	//Same for the two which lose their checkbox to the "Do not change" entry of their own menu
	if (oldFUS && ![oldFUS boolValue]) {
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:STATUS_STATE_ID_NONE]
										   forKey:KEY_STATUS_FUS_STATUS_STATE_ID
											group:PREF_GROUP_STATUS_PREFERENCES];
	}

	if (oldScreenSaver && ![oldScreenSaver boolValue]) {
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:STATUS_STATE_ID_NONE]
										   forKey:KEY_STATUS_SS_STATUS_STATE_ID
											group:PREF_GROUP_STATUS_PREFERENCES];
	}

	//Clearing the old keys is what makes this run exactly once
	for (NSString *oldKey in [NSArray arrayWithObjects:
							  OLD_KEY_STATUS_AUTO_AWAY, OLD_KEY_STATUS_AUTO_AWAY_INTERVAL,
							  OLD_KEY_STATUS_FUS, OLD_KEY_STATUS_SS, nil]) {
		[adium.preferenceController setPreference:nil
										   forKey:oldKey
											group:PREF_GROUP_STATUS_PREFERENCES];
	}

	AILogWithSignature(@"Merged the two idle settings into one (auto away was %@)",
					   (autoAwayWasOn ? @"on" : @"off"));
}

/*!
 * Open the preferences to the status pane
 */
- (void)showStatusPreferences:(id)sender
{
	[adium.preferenceController openPreferencesToCategoryWithIdentifier:@"Status"];
}

@end
