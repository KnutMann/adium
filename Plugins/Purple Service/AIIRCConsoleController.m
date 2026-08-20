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

#import "AIIRCConsoleController.h"
#import <AIUtilities/AIAutoScrollView.h>
#import <AIUtilities/AIBundleAdditions.h>

/* Ported from the never-merged IRCServerConsole branch of the Mercurial
 * mainline (Thijs Alkemade, 2012), reshaped to match our XML console. */

static NSDictionary *AIConsoleAttributes(BOOL outgoing)
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSFont userFixedPitchFontOfSize:11.0f], NSFontAttributeName,
			(outgoing ? [NSColor systemBlueColor] : [NSColor labelColor]), NSForegroundColorAttributeName,
			nil];
}

static void
text_received_cb(PurpleConnection *gc, char **text, gpointer this)
{
	if (!text || !*text)
		return;

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	AIIRCConsoleController *self = (AIIRCConsoleController *)this;

	if (!this || [self gc] != gc) {
		[pool release];
		return;
	}

	//The server may send anything; salvage whatever is not valid UTF-8
	char *salvaged = purple_utf8_salvage(*text);
	NSString *sstr = [[NSString stringWithUTF8String:salvaged] stringByAppendingString:@"\n"];
	g_free(salvaged);

	NSAttributedString *astr = [[NSAttributedString alloc] initWithString:sstr
															   attributes:AIConsoleAttributes(NO)];
	[self appendToLog:astr];
	[astr release];

	[pool release];
}

static void
text_sent_cb(PurpleConnection *gc, char **text, gpointer this)
{
	if (!text || !*text)
		return;

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	AIIRCConsoleController *self = (AIIRCConsoleController *)this;

	if (!this || [self gc] != gc) {
		[pool release];
		return;
	}

	char *salvaged = purple_utf8_salvage(*text);
	//Sent lines already carry their line ending
	NSString *sstr = [NSString stringWithUTF8String:salvaged];
	g_free(salvaged);

	NSAttributedString *astr = [[NSAttributedString alloc] initWithString:sstr
															   attributes:AIConsoleAttributes(YES)];
	[self appendToLog:astr];
	[astr release];

	[pool release];
}

@interface AIIRCConsoleController ()
- (void)appendToLog:(NSAttributedString *)astr;
- (PurpleConnection *)gc;
@end

@implementation AIIRCConsoleController

- (void)dealloc {
    purple_signals_disconnect_by_handle(self);

    [super dealloc];
}

- (IBAction)sendXML:(id)sender {
	if (!gc) {
		NSBeep();
		return;
	}

	/* Raw sending goes through the protocol's own send_raw, which both IRC
	 * variants provide. The line ending is ours to add: raw means raw. */
	PurplePlugin *prpl = purple_connection_get_prpl(gc);
	PurplePluginProtocolInfo *prplInfo = (prpl ? PURPLE_PLUGIN_PROTOCOL_INFO(prpl) : NULL);

	if (!prplInfo || !prplInfo->send_raw) {
		NSBeep();
		return;
	}

	NSString *line = [[xmlInjectView string] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	NSData *rawData = [[line stringByAppendingString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding];
	NSAssert( INT_MAX >= [rawData length],
			 @"Sending more IRC data than libpurple can handle.  Abort." );

	prplInfo->send_raw(gc, [rawData bytes], (int)[rawData length]);

    // remove from text field
    [xmlInjectView setString:@""];
}

- (IBAction)clearLog:(id)sender {
    [xmlLogView setString:@""];
}

- (IBAction)showWindow:(id)sender {
	if (!xmlConsoleWindow) {
		//The XML console's window fits unchanged; only its wording is XMPP's
		[NSBundle ai_loadNibNamed:@"AMPurpleJabberXMLConsole" owner:self];
		if (!xmlConsoleWindow) AILog(@"Unable to load AMPurpleJabberXMLConsole!");

		[xmlConsoleWindow setTitle:AILocalizedString(@"IRC Server Console", nil)];
		[sendButton setTitle:AILocalizedString(@"Send", nil)];

		/* Connect to the signals for updating the window. Both IRC protocol
		 * plugins emit the same pair; hook whichever of them is loaded. The
		 * callbacks sort out whose traffic it is by connection. */
		const char *prplIDs[] = { "prpl-irc", "prpl-eionrobb-ircv3", NULL };
		BOOL found = NO;

		for (int i = 0; prplIDs[i]; i++) {
			PurplePlugin *prpl = purple_find_prpl(prplIDs[i]);
			if (!prpl) continue;

			purple_signal_connect(prpl, "irc-receiving-text", self,
								  PURPLE_CALLBACK(text_received_cb), self);
			purple_signal_connect(prpl, "irc-sending-text", self,
								  PURPLE_CALLBACK(text_sent_cb), self);
			found = YES;
		}

		if (!found) AILog(@"Unable to locate any IRC prpl");
	}

    [xmlConsoleWindow makeKeyAndOrderFront:sender];
	[(AIAutoScrollView *)[xmlLogView enclosingScrollView] setAutoScrollToBottom:YES];
}

- (void)windowWillClose:(NSNotification *)notification
{
	xmlConsoleWindow = nil;

	//We don't need to watch the signals with the window closed
	purple_signals_disconnect_by_handle(self);
}

- (void)close
{
	[xmlConsoleWindow close];
}

- (void)appendToLog:(NSAttributedString *)astr {
	[[xmlLogView textStorage] appendAttributedString:astr];
}

- (PurpleConnection *)gc {
    return gc;
}

- (void)setPurpleConnection:(PurpleConnection *)inGc
{
	gc = inGc;
}

@end
