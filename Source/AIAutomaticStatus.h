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


#define	AIScreensaverDidStartNotification		@"com.apple.screensaver.didstart"
#define AIScreensaverDidStopNotification		@"com.apple.screensaver.didstop"

#define AIScreenLockDidStartNotification		@"com.apple.screenIsLocked"
#define AIScreenLockDidStopNotification			@"com.apple.screenIsUnlocked"

@interface AIAutomaticStatus : AIPlugin {
	NSNumber						*fastUserSwitchID;
	NSNumber						*screenSaverID;
	NSNumber						*idleStatusID;
	
	NSNumber						*oldStatusID;
	
	NSMutableDictionary				*previousStatus;
	NSMutableSet					*accountsToReconnect;

	/* One switch and one duration carry both halves of being idle now: the contacts are told about
	 * it, and if a status was chosen, that status is set. Fast user switching and the screen saver
	 * have no switch of their own any more - their menu standing on "Do not change" is their off. */
	BOOL							idleEnabled;
	double							idleInterval;

	unsigned						automaticStatusBitMap;
}

@end
