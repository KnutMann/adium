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

#import <AdiumLibpurple/PurpleCommon.h>

/*!
 * @brief A raw server console for IRC, after the pattern of the XMPP XML console
 *
 * Shows everything sent to and received from the IRC server, and takes raw
 * lines to send. Works for the built-in IRC protocol and the IRCv3 plugin
 * alike; both emit the same signals.
 *
 * The window is the XML console's nib, retitled: the outlet and action names
 * below are dictated by that nib and shared with AMXMLConsoleController.
 */
@interface AIIRCConsoleController : NSObject {
    IBOutlet NSWindow *xmlConsoleWindow;
    IBOutlet NSTextView *xmlLogView;
    IBOutlet NSTextView *xmlInjectView;
    IBOutlet NSButton *sendButton;

    PurpleConnection *gc;
}

- (IBAction)sendXML:(id)sender;
- (IBAction)clearLog:(id)sender;
- (IBAction)showWindow:(id)sender;
- (void)close;

- (void)setPurpleConnection:(PurpleConnection *)gc;
@end
