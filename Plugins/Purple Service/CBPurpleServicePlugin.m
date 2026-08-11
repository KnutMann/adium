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
	 * service class. Commenting a line out therefore doesn't mean "temporarily off" - it
	 * means the service stops existing as far as the rest of Adium is concerned, while its
	 * code would still be compiled into AdiumLibpurple and shipped. Drop the code instead.
	 * (Bonjour is a service too, but registers itself in AWBonjourPlugin.)
	 */
    //Install the services
	[ESGaduGaduService registerService];
	[ESIRCService registerService];
	[AITelegramService registerService];
	[AIWhatsAppService registerService];
	[ESSimpleService registerService];
	[ESNovellService registerService];
	[ESJabberService registerService];
	
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
