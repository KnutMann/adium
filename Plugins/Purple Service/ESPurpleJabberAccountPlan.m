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

#import "ESPurpleJabberAccountPlan.h"
#import "ESPurpleJabberAccount.h"

#import <Adium/AIAccount.h>
#import <AIUtilities/AIStringUtilities.h>
#import <SystemConfiguration/SystemConfiguration.h>

@implementation ESPurpleJabberAccountPlan

/*!
 * @brief Two switches become the one choice the protocol has always had
 *
 * Adium kept "Require TLS" and "Force Old SSL" apart and turned them into a single
 * connection_security value on every connect. That rule is read here once, so that the row shows what
 * the account is actually running on rather than the protocol's own default. Neither switch has had a
 * place in the interface since the options came from the protocol.
 */
- (void)migrateLegacy
{
	[super migrateLegacy];

	NSString *key = [self preferenceKeyForSetting:@"connection_security"];

	//Only ever once: a chosen value is not something to overwrite with a derived one
	if ([[self account] preferenceForKey:key group:GROUP_ACCOUNT_STATUS])
		return;

	NSString *security;

	if ([[[self account] preferenceForKey:KEY_JABBER_FORCE_OLD_SSL group:GROUP_ACCOUNT_STATUS] boolValue])
		security = @"old_ssl";
	else if ([[[self account] preferenceForKey:KEY_JABBER_REQUIRE_TLS group:GROUP_ACCOUNT_STATUS] boolValue])
		security = @"require_tls";
	else
		security = @"opportunistic_tls";

	[[self account] setPreference:security forKey:key group:GROUP_ACCOUNT_STATUS];
}

/*!
 * @brief The settings Adium keeps for an XMPP account itself
 *
 * None of these is a protocol option: the account code reads each of them from Adium's own
 * preferences when it connects or when a status is set, so they are not in the file and were not
 * offered anywhere since the old account sheet went. The row's key is the one the code reads.
 */
- (void)describe
{
	[super describe];

	//The name this connection goes by beside the account's other connections; empty is this computer's
	AIAccountPlanField *resource = [AIAccountPlanField fieldNamed:@"resource" kind:AIAccountFieldText];
	[resource setStore:AIAccountFieldStorePreference];
	[resource setPreferenceKey:KEY_JABBER_RESOURCE];
	[resource setLabel:AILocalizedString(@"Resource", "XMPP account row: the name this connection goes by beside the account's other connections")];
	[resource setPlaceholder:[(NSString *)SCDynamicStoreCopyLocalHostName(NULL) autorelease]];
	[resource setWidth:160.0];
	[self addField:resource toCard:AIAccountCardOptions];

	/* Which of the account's connections a message goes to when the sender does not say: the
	 * higher wins. One while available and one while away, both 0 unless set. */
	AIAccountPlanField *availablePriority = [AIAccountPlanField fieldNamed:@"priorityAvailable" kind:AIAccountFieldNumber];
	[availablePriority setStore:AIAccountFieldStorePreference];
	[availablePriority setPreferenceKey:KEY_JABBER_PRIORITY_AVAILABLE];
	[availablePriority setLabel:AILocalizedString(@"Priority when available", "XMPP account row: the connection's priority while the status is available")];
	[availablePriority setPlaceholder:@"0"];
	[self addField:availablePriority toCard:AIAccountCardOptions];

	AIAccountPlanField *awayPriority = [AIAccountPlanField fieldNamed:@"priorityAway" kind:AIAccountFieldNumber];
	[awayPriority setStore:AIAccountFieldStorePreference];
	[awayPriority setPreferenceKey:KEY_JABBER_PRIORITY_AWAY];
	[awayPriority setLabel:AILocalizedString(@"Priority when away", "XMPP account row: the connection's priority while the status is away")];
	[awayPriority setPlaceholder:@"0"];
	[self addField:awayPriority toCard:AIAccountCardOptions];

	//On by default, and the account reads an untouched setting as on; the row shows it that way
	AIAccountPlanField *verify = [AIAccountPlanField fieldNamed:@"verifyCertificates" kind:AIAccountFieldSwitch];
	[verify setStore:AIAccountFieldStorePreference];
	[verify setPreferenceKey:KEY_JABBER_VERIFY_CERTS];
	[verify setDefaultValue:[NSNumber numberWithBool:YES]];
	[verify setLabel:AILocalizedString(@"Do strict certificate checks", nil)];
	[self addField:verify toCard:AIAccountCardOptions];

	/* What to do when somebody asks to see this account's status. The values are the ones the
	 * account code switches on, in the order the old menu had them. */
	AIAccountPlanField *subscriptions = [AIAccountPlanField fieldNamed:@"subscriptions" kind:AIAccountFieldChoice];
	[subscriptions setStore:AIAccountFieldStorePreference];
	[subscriptions setPreferenceKey:KEY_JABBER_SUBSCRIPTION_BEHAVIOR];
	[subscriptions setChoiceTitles:[NSArray arrayWithObjects:
									AILocalizedString(@"Ask What To Do", nil),
									AILocalizedString(@"Accept", nil),
									AILocalizedString(@"Accept and Add To List", nil),
									AILocalizedString(@"Deny", nil),
									nil]];
	[subscriptions setChoiceValues:[NSArray arrayWithObjects:
									[NSNumber numberWithInteger:0],
									[NSNumber numberWithInteger:1],
									[NSNumber numberWithInteger:2],
									[NSNumber numberWithInteger:3],
									nil]];
	[subscriptions setDefaultValue:[NSNumber numberWithInteger:0]];
	[subscriptions setLabel:AILocalizedString(@"When someone asks to see my status", "XMPP privacy row: what happens to a request to see this account's status")];
	[self addField:subscriptions toCard:AIAccountCardPrivacy];

	AIAccountPlanField *group = [AIAccountPlanField fieldNamed:@"subscriptionGroup" kind:AIAccountFieldText];
	[group setStore:AIAccountFieldStorePreference];
	[group setPreferenceKey:KEY_JABBER_SUBSCRIPTION_GROUP];
	[group setLabel:AILocalizedString(@"Group for added contacts", "XMPP privacy row: the contact list group a contact accepted and added goes into")];
	[group setDetail:AILocalizedString(@"Only when a request is accepted and the contact added to the list.", "Under the group row: when the group is used")];
	[group setWidth:160.0];
	[self addField:group toCard:AIAccountCardPrivacy];

	//The song playing goes out with the status (XEP-0118), if this is on
	AIAccountPlanField *nowPlaying = [AIAccountPlanField fieldNamed:@"nowPlaying" kind:AIAccountFieldSwitch];
	[nowPlaying setStore:AIAccountFieldStorePreference];
	[nowPlaying setPreferenceKey:KEY_BROADCAST_MUSIC_INFO];
	[nowPlaying setDefaultValue:[NSNumber numberWithBool:NO]];
	[nowPlaying setLabel:AILocalizedString(@"Let others know what I am listening to", "XMPP privacy row: whether the song playing is sent along with the status")];
	[self addField:nowPlaying toCard:AIAccountCardPrivacy];
}

@end
