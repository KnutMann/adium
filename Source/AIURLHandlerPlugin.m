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

#import "AIURLHandlerPlugin.h"
#import "AIURLHandlerAdvancedPreferences.h"

#import "AINewContactWindowController.h"
#import "XtrasInstaller.h"

#import "AITemporaryIRCAccountWindowController.h"

#import <AIUtilities/AIURLAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <AIUtilities/AIWindowAdditions.h>

#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIService.h>
#import <Adium/AIAccount.h>

@interface AIURLHandlerPlugin()
- (void)checkHandledSchemes;

- (void)handleURL:(NSNotification *)notification;

- (void)_openChatToContactWithName:(NSString *)name onService:(NSString *)serviceIdentifier withMessage:(NSString *)body;
- (void)_openXMPPGroupChat:(NSString *)name onServer:(NSString *)server withPassword:(NSString *)inPassword;
- (void)_openIRCGroupChat:(NSString *)name onServer:(NSString *)server withPort:(NSInteger)port andPassword:(NSString *)password;
@end

/*!
 * @class AIURLHandlerPlugin
 *
 * The URL handler plugin handles URL events sent to us.
 *
 * For example, it will convert xmpp:fuark@jabber.org?message to open a chat window with
 * the user "fuark" on the first available Jabber account.
 *
 * This plugin also manages the default application settings for the schemes we support.
 * Note that we never claim a service scheme unless the user asks us to.
 */
@implementation AIURLHandlerPlugin
/*!
 * @brief Install plugin
 *
 * This sets up our advanced preferences view and checks our defaults.
 */
- (void)installPlugin
{
	preferences = [(AIURLHandlerAdvancedPreferences *)[AIURLHandlerAdvancedPreferences preferencePaneForPlugin:self] retain];
	
	[self checkHandledSchemes];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(handleURL:)
												 name:AIURLHandleNotification
											   object:nil];
}

/*!
 * @brief Unisntall
 */
- (void)uninstallPlugin
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[preferences release];
}

#pragma mark Scheme enforcement
/*!
 * @brief Set Adium as the default for all handled schemes
 *
 * For all service schemes (and their aliases), set ourself as their default bundle ID.
 */
- (void)setAdiumAsDefault
{
	for (NSString *scheme in self.uniqueSchemes) {
		[self setDefaultForScheme:scheme toBundleID:ADIUM_BUNDLE_ID];
	}	
}

/*!
 * @brief Check our handled schemes
 *
 * We do not claim a service scheme on our own initiative. Adium used to grab every scheme it
 * knew on the very first launch, which silently took xmpp: and irc: away from whatever the user
 * had chosen before. A service scheme is now only claimed when the user asks for it: either one
 * at a time in the Default Client preferences, or through the "Always set Adium as the default"
 * checkbox, which we re-apply on every launch.
 *
 * Always set ourself as the default for our helper schemes (such as adiumxtra).
 */
- (void)checkHandledSchemes
{
	if ([[adium.preferenceController preferenceForKey:PREF_KEY_ENFORCE_DEFAULT
												group:GROUP_URL_HANDLING] boolValue]) {
		[self setAdiumAsDefault];
	}
	
	for (NSString *scheme in self.helperSchemes) {
		[self setDefaultForScheme:scheme toBundleID:ADIUM_BUNDLE_ID];
	}
}

#pragma mark Schemes
/*!
 * @brief Get a service ID from a scheme
 *
 * Asking for the service ID of an unknown scheme will return nil.
 *
 * @param scheme One of our supported schemes
 * @returns The serviceID for the service which uses the scheme given
 */
- (NSString *)serviceIDForScheme:(NSString *)scheme
{
	static NSDictionary	*schemeToServiceDict = nil;
	if (!schemeToServiceDict) {
		schemeToServiceDict = [[NSDictionary alloc] initWithObjectsAndKeys:
							   @"Jabber",  @"xmpp",
							   @"Jabber",  @"jabber",
							   @"IRC",	   @"irc",
							   nil];
	}
	
	return [schemeToServiceDict objectForKey:scheme];
}

/*!
 * @brief All of the schemes similar to a given scheme
 *
 * Several services (such as Jabber) have several scheme
 * aliases which are possible schemes for them. Instead of having multiple
 * entries each, we simply use a reference one and apply to all aliases.
 *
 * @param scheme A reference scheme (see -uniqueSchemes)
 * @returns An NSArray of all schemes similar to the given one.
 */
- (NSArray *)allSchemesLikeScheme:(NSString *)scheme
{
	if ([scheme isEqualToString:@"xmpp"]) {
		//gtalk: used to ride along with xmpp: here. There is no GTalk service anymore, so claiming
		//the scheme alongside xmpp: only took it away from clients which can still act on it.
		return [NSArray arrayWithObjects:@"xmpp", @"jabber", nil];
	} else {
		return [NSArray arrayWithObject:scheme];
	}
}

/*!
 * @brief Unique schemes we support
 *
 * @returns An NSArray of all of the schemes we support.
 */
- (NSArray *)uniqueSchemes
{
	//aim: is gone: AOL shut the service down in December 2017 and the AIM service has been
	//removed from Adium, so there is no longer anything to hand an aim: URL to.
	return [NSArray arrayWithObjects:@"irc", @"xmpp", nil];
}

/*!
 * @brief Helper schemes
 *
 * Helper schemes are schemes which we should always be registered as the default application
 * for. adiumxtra:// is the installer for Adium Xtras; nothing else handles it, so claiming it
 * takes nothing away from anybody.
 *
 * (twitterreply:// used to live here. The Twitter plugin is gone, so we were claiming a scheme
 * we could no longer act upon.)
 *
 * @returns An NSArray of all of the helper schemes we support.
 */
- (NSArray *)helperSchemes
{
	return [NSArray arrayWithObject:@"adiumxtra"];
}

#pragma mark Default Bundle
/*!
 * @brief Set an application as the default for a scheme
 *
 * @param inScheme The scheme to set the default for
 * @param bundleID The bundle ID of an application to set as the default for the given scheme
 */
- (void)setDefaultForScheme:(NSString *)inScheme toBundleID:(NSString *)bundleID
{
	for (NSString *scheme in [self allSchemesLikeScheme:inScheme]) {
		LSSetDefaultHandlerForURLScheme((CFStringRef)scheme, (CFStringRef)bundleID);
	}
	
	[preferences refreshTable];
}

/*!
 * @brief Default application bundle ID for a scheme
 *
 * @param scheme The scheme to determine the default application for
 * @returns An NSString bundle ID for the default application of a scheme
 */
- (NSString *)defaultApplicationBundleIDForScheme:(NSString *)scheme
{
	return [[(NSString *)LSCopyDefaultHandlerForURLScheme((CFStringRef)scheme) autorelease] lowercaseString];
}

#pragma mark URL Handling
/*!
 * @brief Handle a URL notification
 *
 * @param notification An NSNotification whose -object is the NSString of a URL.
 */
- (void)handleURL:(NSNotification *)notification
{
	NSString *urlString = notification.object;
	NSURL *url = [NSURL URLWithString:urlString];
	
	if (!url)
		return;
	
	NSString	*scheme, *newScheme;
	NSString	*serviceID;
	
	//make sure we have the // in ://, as it simplifies later processing.
	if (![[url resourceSpecifier] hasPrefix:@"//"]) {
		urlString = [NSString stringWithFormat:@"%@://%@", [url scheme], ([url resourceSpecifier] ?: @"")];
		url = [NSURL URLWithString:urlString];
	}
	
	scheme = [url scheme];
	
	//map schemes to common aliases (like jabber: for xmpp:).
	static NSDictionary *schemeMappingDict = nil;
	if (!schemeMappingDict) {
		schemeMappingDict = [[NSDictionary alloc] initWithObjectsAndKeys:
							 @"xmpp", @"jabber",
							 nil];
	}
	
	newScheme = [schemeMappingDict objectForKey:scheme];
	if (newScheme) {
		scheme = newScheme;
		urlString = [NSString stringWithFormat:@"%@:%@", scheme, [url resourceSpecifier]];
		url = [NSURL URLWithString:urlString];
	}

	if ((serviceID = [self serviceIDForScheme:scheme])) {
		NSString *host = [url host];
		NSString *query = [url query];
		
		if ([scheme isEqualToString:@"xmpp"]) {
			if ([query rangeOfString:@"message"].location == 0) {
				//xmpp:johndoe@jabber.org?message;subject=Subject;body=Body
				//xmpp:jabber.org?message;subject=Subject;body=Body
				NSString *msg = [[url queryArgumentForKey:@"body"] stringByDecodingURLEscapes];
				
				if ([url user]) {
					[self _openChatToContactWithName:[NSString stringWithFormat:@"%@@%@", [url user], [url host]]
										   onService:serviceID
										 withMessage:msg];
				} else {
					[self _openChatToContactWithName:[url host]
										   onService:serviceID
										 withMessage:msg];
					
				}
			} else if ([query rangeOfString:@"roster"].location == 0
					   || [query rangeOfString:@"subscribe"].location == 0) {
				//xmpp:johndoe@jabber.org?roster;name=John%20Doe;group=Friends
				//xmpp:johndoe@jabber.org?subscribe
				
				//Group specification and name specification is currently ignored,
				//due to limitations in the AINewContactWindowController API.
				
				AIService *jabberService;
				
				jabberService = [adium.accountController firstServiceWithServiceID:@"Jabber"];
				
				AINewContactWindowController *newContactWindowController = [[AINewContactWindowController alloc] initWithContactName:[NSString stringWithFormat:@"%@@%@", [url user], [url host]]
																															 service:jabberService
																															 account:nil];
				[newContactWindowController showOnWindow:nil];
			} else if ([query rangeOfString:@"remove"].location == 0
					   || [query rangeOfString:@"unsubscribe"].location == 0) {
				// xmpp:johndoe@jabber.org?remove
				// xmpp:johndoe@jabber.org?unsubscribe
				
			} else if ([query rangeOfString:@"join"].location == 0) {
				NSString *password = [[url queryArgumentForKey:@"password"] stringByDecodingURLEscapes];
				
				[self _openXMPPGroupChat:[url user]
								onServer:[url host]
							withPassword:password];
				
				//TODO: 
			}
		} else if ([scheme caseInsensitiveCompare:@"irc"] == NSOrderedSame) {
			// irc://server:port/channel?password
			NSString *channelName = [url fragment];
			NSNumber *portNumber = [url port];
			NSInteger port;
			
			if (!channelName.length && (!url.path.lastPathComponent || [url.path.lastPathComponent isEqualToString:@"/"])) {
				channelName = @"#";
			} else if (!channelName.length) {
				channelName = url.path.lastPathComponent;
			}
			
			if (![channelName hasPrefix:@"#"] && ![channelName hasPrefix:@"&"]) {
				channelName = [@"#" stringByAppendingString:channelName];
			}
			
			if (portNumber == nil) {
				port = -1;
			} else {
				port = [portNumber integerValue];
			}
			
			if (!host) {
				host = @"";
			}
			
			channelName = [channelName stringByRemovingPercentEncoding];
			
			[self _openIRCGroupChat:channelName onServer:host withPort:port andPassword:[url query]];
		} else {
			//Fallback for any scheme in -serviceIDForScheme: which has no branch of its own:
			//open the host as a contact name.
			NSString	*user = [url user];
			NSString	*name;
			if (user && [user length]) {
				//jabber://tekjew@jabber.org
				name = [NSString stringWithFormat:@"%@@%@",[url user],[url host]];
			} else {
				name = [url host];
			}

			[self _openChatToContactWithName:[name compactedString]
								   onService:serviceID
								 withMessage:nil];
		}
		
	} else if ([scheme isEqualToString:@"adiumxtra"]) {
		//Installs an adium extra
		// adiumxtra://xtras.adium.im/path/to/xtra.zip
		
		[[XtrasInstaller installer] installXtraAtURL:url];
	}
}

#pragma mark Chat openers

- (void)_openChatToContactWithName:(NSString *)UID onService:(NSString *)serviceID withMessage:(NSString *)message
{
	AIListContact		*contact = [adium.contactController preferredContactWithUID:UID
									andServiceID:serviceID 
									forSendingContentType:CONTENT_MESSAGE_TYPE];
	if (contact) {
		//Open the chat and set it as active
		[adium.interfaceController setActiveChat:[adium.chatController openChatWithContact:contact
												  onPreferredAccount:YES]];

		//Insert the message text as if the user had typed it after opening the chat
		NSResponder *responder = [[NSApp keyWindow] earliestResponderOfClass:[NSTextView class]];
		if (message && [responder isKindOfClass:[NSTextView class]] && [(NSTextView *)responder isEditable]) {
			[responder insertText:message];
		}
		
	} else {
		NSBeep();
	}
}

- (void)_openIRCGroupChat:(NSString *)name onServer:(NSString *)server withPort:(NSInteger)port andPassword:(NSString *)password
{
	AIAccount *ircAccount = nil;
	
	for (AIAccount *account in adium.accountController.accounts) {
		if ([account.service.serviceClass isEqualToString:@"IRC"] && [account.host isEqualToString:server] && (port == -1 || account.port == port)) {
			ircAccount = account;
			break;
		}
	}
	
	if (!ircAccount) {
		AITemporaryIRCAccountWindowController *temporaryIRCAccountWindowController = [[AITemporaryIRCAccountWindowController alloc] initWithChannel:name server:server port:port andPassword:password];
		[temporaryIRCAccountWindowController show];
	} else if (name) {
		[adium.chatController chatWithName:name
		 identifier:nil
		 onAccount:ircAccount
		 chatCreationInfo:[NSDictionary dictionaryWithObjectsAndKeys:
						   name, @"channel",
						   password, @"password", /* may be nil, so should be last */
						   nil]];
	} else {
		NSBeep();
	}
}

- (void)_openXMPPGroupChat:(NSString *)name onServer:(NSString *)server withPassword:(NSString *)password
{
	AIAccount		*account = nil;
	
	//Find an XMPP-compatible online account which can create group chats
	for (account in adium.accountController.accounts) {
		if (account.online &&
			[account.service.serviceClass isEqualToString:@"Jabber"] &&
			[account.service canCreateGroupChats]) {
			break;
		}
	}
	
	if (name && account) {
		[adium.chatController chatWithName:[NSString stringWithFormat:@"%@@%@", name, server]
								identifier:nil
								 onAccount:account
						  chatCreationInfo:[NSDictionary dictionaryWithObjectsAndKeys:
											name, @"room",
											server, @"server",
											account.displayName, @"handle",
											password, @"password", /* may be nil, so should be last */
											nil]];
	} else {
		NSBeep();
	}
}

@end
