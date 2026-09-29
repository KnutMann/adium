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

#import "ESPurpleNotifyEmailController.h"
#import "adiumPurpleNotify.h"
#import <AdiumLibpurple/SLPurpleCocoaAdapter.h>
#import <AIUtilities/AIObjectAdditions.h>
#import "AMPurpleSearchResultsController.h"

static void *adiumPurpleNotifyMessage(PurpleNotifyMsgType type, const char *title, const char *primary, const char *secondary)
{
	void *res = NULL;

	@autoreleasepool {
		AILog(@"adiumPurpleNotifyMessage: type: %i\n%s\n%s\n%s ",
			  type,
			  (title ? title : ""),
			  (primary ? primary : ""),
			  (secondary ? secondary : ""));

		res = [[SLPurpleCocoaAdapter sharedInstance] handleNotifyMessageOfType:type
		                                                             withTitle:title
		                                                               primary:primary
		                                                             secondary:secondary];
	}

	return res;
}

static void *adiumPurpleNotifyEmails(PurpleConnection *gc, size_t count, gboolean detailed, const char **subjects, const char **froms, const char **tos, const char **urls)
{
	// Don't notify that 0 emails are present.
	if (!count)
		return NULL;
	void *res = NULL;

	@autoreleasepool {
		//Values passed can be null
		AIAccount	*account = (PURPLE_CONNECTION_IS_VALID(gc) ?
							  accountLookup(purple_connection_get_account(gc)) :
							  nil);

		res = [ESPurpleNotifyEmailController handleNotifyEmailsForAccount:account
		                                                            count:count
		                                                         detailed:detailed
		                                                         subjects:subjects
		                                                            froms:froms
		                                                              tos:tos
		                                                             urls:urls];
	}

	return res;
}

static void *adiumPurpleNotifyEmail(PurpleConnection *gc, const char *subject, const char *from, const char *to, const char *url)
{
	return adiumPurpleNotifyEmails(gc,
								 1,
								 TRUE,
								 (subject ? &subject : NULL),
								 (from ? &from : NULL),
								 (to ? &to : NULL),
								 (url ? &url : NULL));
}

static void *adiumPurpleNotifyFormatted(const char *title, const char *primary, const char *secondary, const char *text)
{
	void *res = NULL;

	@autoreleasepool {
		AILog(@"adiumPurpleNotifyFormatted: %s\n%s\n%s\n%s ",
			  (title ? title : ""),
			  (primary ? primary : ""),
			  (secondary ? secondary : ""),
			  (text ? text : ""));

		res = [[SLPurpleCocoaAdapter sharedInstance] handleNotifyFormattedWithTitle:title
		                                                                    primary:primary
		                                                                  secondary:secondary
		                                                                       text:text];
	}

	return res;
}

static void *adiumPurpleNotifySearchResults(PurpleConnection *gc, const char *title,
										  const char *primary, const char *secondary,
										  PurpleNotifySearchResults *results, gpointer user_data)
{
	void *res = NULL;

	@autoreleasepool {
		AILog(@"**** returning search results");

		AMPurpleSearchResultsController *controller =
			[[AMPurpleSearchResultsController alloc] initWithPurpleConnection:gc
			                                                            title:(title ? [NSString stringWithUTF8String:title] : nil)
			                                                      primaryText:(primary ? [NSString stringWithUTF8String:primary] : nil)
			                                                    secondaryText:(secondary ? [NSString stringWithUTF8String:secondary] : nil)
			                                                    searchResults:results
			                                                         userData:user_data];

		/* The controller is the notification's ui_handle. ARC holds the alloc/init +1 in the
		 * local; the bridge hands that one reference to libpurple, which gives it back through
		 * adiumPurpleNotifyClose() -> -purpleRequestClose, the single consumer. */
		res = (__bridge_retained void *)controller;
	}

	return res;
}

static void adiumPurpleNotifySearchResultsNewRows(PurpleConnection *gc,
												 PurpleNotifySearchResults *results,
												 void *data)
{
	@autoreleasepool {
		if ([(__bridge id)data isKindOfClass:[AMPurpleSearchResultsController class]]) {
			[(__bridge AMPurpleSearchResultsController *)data addResults:results];
		}
	}
}

static void *adiumPurpleNotifyUserinfo(PurpleConnection *gc, const char *who,
									 PurpleNotifyUserInfo *user_info)
{	
	@autoreleasepool {

		if (PURPLE_CONNECTION_IS_VALID(gc)) {
			PurpleAccount		*account = purple_connection_get_account(gc);
			PurpleBuddy		*buddy = purple_find_buddy(account, who);
			CBPurpleAccount	*adiumAccount = accountLookup(account);
			AIListContact	*contact;

			contact = contactLookupFromBuddy(buddy);
			if (!contact) {
				NSString *UID = [NSString stringWithUTF8String:purple_normalize(account, who)];

				contact = [accountLookup(account) contactWithUID:UID];
			}

			[adiumAccount updateUserInfo:contact
								withData:user_info];
		}
	}

	return NULL;
}

static void *adiumPurpleNotifyUri(const char *uri)
{
	@autoreleasepool {

		AILogWithSignature(@"Opening URI %s",uri);

		if (uri) {
			NSString *passedURI = [NSString stringWithUTF8String:uri];

			if ([passedURI hasPrefix:[NSString stringWithUTF8String:g_get_tmp_dir()]] ||
				[passedURI hasPrefix:NSTemporaryDirectory()]) {
				NSString *actualURI = passedURI;

				if (![[passedURI pathExtension] length]) {
					actualURI = [passedURI stringByAppendingPathExtension:@"htm"];
					[[NSFileManager defaultManager] copyItemAtPath:passedURI
													  toPath:actualURI
													 error:NULL];
				}
		
				/* Open the HTML file with a web browser, not with an HTML editor: what opens a file of
				 * this kind is often an editor, so the browser is asked for by what it does with web
				 * addresses and then handed the file.
				 *
				 * Three Carbon calls and a structure became one message. The old ones spoke in file
				 * references, which are a way of naming files that the system stopped keeping up with
				 * years ago, and the launch specification existed only to tie them together.
				 */
				NSURL *browserURL = [[NSWorkspace sharedWorkspace]
										URLForApplicationToOpenURL:[NSURL URLWithString:@"http://google.com"]];

				if (browserURL) {
					[[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:actualURI]]
									   withApplicationAtURL:browserURL
											  configuration:[NSWorkspaceOpenConfiguration configuration]
										  completionHandler:nil];
				}
			} else {
				/* Not right away: a protocol that shows a code and opens the browser in the same
				 * breath, as the Teams device sign-in does, has its browser cover the window carrying
				 * the code before anyone saw it; a user then takes the sign-in page for an
				 * authenticator prompt. A moment's pause lets the code window appear first. */
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
							   dispatch_get_main_queue(), ^{
					[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:passedURI]];
				});
			}
		}
	}

	return NULL;
}

static void adiumPurpleNotifyClose(PurpleNotifyType type,void *uiHandle)
{
	@autoreleasepool {
		id ourHandle = (__bridge id)uiHandle;
		AILogWithSignature(@"Closing %p (%i)",ourHandle,type);

		if ([ourHandle respondsToSelector:@selector(purpleRequestClose)]) {
			/* -purpleRequestClose gives back the one reference the notify op handed libpurple;
			 * nothing may touch the handle after it. */
			[ourHandle performSelector:@selector(purpleRequestClose)];
		} else if ([ourHandle respondsToSelector:@selector(closeWindow:)]) {
			[ourHandle performSelector:@selector(closeWindow:)
							withObject:nil];
		}
	}
}

static PurpleNotifyUiOps adiumPurpleNotifyOps = {
    adiumPurpleNotifyMessage,
    adiumPurpleNotifyEmail,
    adiumPurpleNotifyEmails,
    adiumPurpleNotifyFormatted,
	adiumPurpleNotifySearchResults,
	adiumPurpleNotifySearchResultsNewRows,
	adiumPurpleNotifyUserinfo,
    adiumPurpleNotifyUri,
    adiumPurpleNotifyClose,
	
	/* _purple_reserved 1-4 */
	NULL, NULL, NULL, NULL
};

PurpleNotifyUiOps *adium_purple_notify_get_ui_ops(void)
{
	return &adiumPurpleNotifyOps;
}
