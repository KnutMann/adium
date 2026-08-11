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

#import "CBPurpleServicePlugin.h"
#import "PurpleServices.h"
#import "SLPurpleCocoaAdapter.h"
#import <Adium/AIAccount.h>
#import <AIUtilities/AIDictionaryAdditions.h>
#import <AdiumLibpurple/SLPurpleCocoaAdapter.h>
#import "AMPurpleTuneTooltip.h"
#import "AIIRCServicesPasswordPlugin.h"
#import "AIAnnoyingIRCMessagesHiderPlugin.h"

@implementation CBPurpleServicePlugin

#pragma mark Plugin Installation
//  Plugin Installation ------------------------------------------------------------------------------------------------

#define PURPLE_DEFAULTS   @"PurpleServiceDefaults"

- (void)installPlugin
{
	//Register our defaults
    [adium.preferenceController registerDefaults:[NSDictionary dictionaryNamed:PURPLE_DEFAULTS
																		forClass:[self class]]
										  forGroup:GROUP_ACCOUNT_STATUS];
	
	/* This list is the only thing that makes a libpurple service reachable: +registerService
	 * hands the instance to AdiumServices, and nothing else in the tree ever instantiates a
	 * service class. A commented-out line therefore doesn't mean "temporarily off" - it means
	 * the service does not exist as far as the rest of Adium is concerned, even though its
	 * code is still compiled into AdiumLibpurple and shipped. Such leftovers carry the token
	 * ADIUM-UNUSED wherever a comment can live, so that `git grep -In ADIUM-UNUSED` finds
	 * them. That is the source files, not the whole removal set: the project file entries,
	 * the localized strings and the binary leftovers cannot carry a comment and are listed
	 * in Other/ADIUM-UNUSED.txt instead, which is where a removal should start.
	 * (Bonjour is a service too, but registers itself in AWBonjourPlugin.)
	 */
    //Install the services
	[ESGaduGaduService registerService];
	[ESIRCService registerService];
	[AITelegramService registerService];
	[AIWhatsAppService registerService];
	/* TODO ADIUM-UNUSED: QQ. Nothing is left to remove here except the line below and this
	 * comment - the service class, its account classes, icons, defaults and localizations are
	 * already gone from the tree. Before dropping the line, present to users who had a QQ
	 * account a message that it's no longer supported.
	 */
	//[ESQQService registerService];
	[ESSimpleService registerService];
	[ESNovellService registerService];
	[ESJabberService registerService];
	/* TODO ADIUM-UNUSED: Zephyr. Not registered, and scheduled for removal along with all of
	 * its files. Zephyr is the campus messaging system Athena was built around, and reaching a
	 * server means going through the zephyr host manager. zhm is in no copy-resources phase,
	 * so looking it up returns nil, and the copy checked into the tree is i386/ppc besides -
	 * uncommenting this line would produce a service that cannot connect. The inventory of
	 * every file, resource and project entry involved is in Other/ADIUM-UNUSED.txt.
	 */
	//[ESZephyrService registerService];
	
	[SLPurpleCocoaAdapter pluginDidLoad];
	
	//tooltip for tunes
	tunetooltip = [[AMPurpleTuneTooltip alloc] init];
	[adium.interfaceController registerContactListTooltipEntry:tunetooltip secondaryEntry:YES];
	
	ircPasswordPlugin = [[AIIRCServicesPasswordPlugin alloc] init];
	[ircPasswordPlugin installPlugin];
	
	messageHiderPlugin = [[AIAnnoyingIRCMessagesHiderPlugin alloc] init];
	[messageHiderPlugin installPlugin];
}

- (void)uninstallPlugin
{
	[adium.interfaceController unregisterContactListTooltipEntry:tunetooltip secondaryEntry:YES];
	[tunetooltip release];
	tunetooltip = nil;	
	
	[ircPasswordPlugin uninstallPlugin];
	[ircPasswordPlugin release];
	
	[messageHiderPlugin uninstallPlugin];
	[messageHiderPlugin release];
}

@end
