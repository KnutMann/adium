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

@class AIAccount;

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

/*!
 * @brief Is this account on a status which was set for it automatically?
 *
 * YES only while we really hold the account: we stored what it was before, and it is still on the
 * status the automatic reason called for. Whoever picks another status by hand while automatically
 * away has taken the account back, and the answer is NO from then on - a status one chose oneself
 * is one you can forget you are on, and that is what the away reminder is there for.
 *
 * Both halves are needed. The stored status alone would go on calling an away status automatic
 * after the user had replaced it by hand; the status comparison alone would call a hand-picked
 * away automatic as soon as it happened to be the very status idleness is set to.
 *
 * One blur remains: choose by hand exactly the status the automatic reason uses, and we cannot
 * tell the two apart - we only ever remember one status ID. No reminder then, which is bearable,
 * because that status is cleared by the next keystroke anyway.
 */
- (BOOL)hasAutomaticStatusForAccount:(AIAccount *)account;

@end
