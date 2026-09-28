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

#import "ESPurpleRequestAbstractWindowController.h"
#import "adiumPurpleRequest.h"

@implementation ESPurpleRequestAbstractWindowController

- (id)initWithWindowNibName:(NSString *)windowNibName
{
	if ((self = [super initWithWindowNibName:windowNibName])) {
		windowIsClosing = NO;
	}
	
	return self;
}

/*!
 * @brief This is where subclasses should generally perform actions they would normally do in windowWillClose:
 *
 * ESPurpleRequestAbstractWindowController calls this method only when windowWillClose: is triggered by user action
 * as opposed to libpurple closing the window.
 */
- (void)doWindowWillClose {};

- (void)windowWillClose:(id)sender
{
	[super windowWillClose:sender];
	
	if (!windowIsClosing) {
		windowIsClosing = YES;
		[self doWindowWillClose];
		
		//Inform libpurple that the request window closed
		[ESPurpleRequestAdapter requestCloseWithHandle:self];
	}
}	

/*!
 * @brief libpurple has been made aware we closed or has informed us we should close
 *
 * Close our window if it's open; then give back the reference libpurple held.
 *
 * The instance is the request's ui_handle. adiumPurpleRequest.m (manual counting) creates it with
 * alloc/init, never releases it, and hands that +1 to libpurple as the return value of the request
 * ui op; libpurple gives it back through adiumPurpleRequestClose, which sends this message. This is
 * the one place that +1 is consumed, for every subclass. Under manual counting it was [self release];
 * the CFRelease acts on the count outside ARC's view exactly as that did. Nothing may touch self
 * after it.
 */
- (void)purpleRequestClose
{
	if (!windowIsClosing) {
		windowIsClosing = YES;
		[self closeWindow:nil];
	}
	
	//The +1 from adiumPurpleRequest.m; see above
	CFRelease((__bridge CFTypeRef)self);
}

@end
