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

#import "AINewGroupWindowController.h"
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIListGroup.h>

#define ADD_GROUP_PROMPT_NIB	@"AddGroup"

@interface AINewGroupWindowController ()
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
@end

/*!
 * @class AINewGroupWindowController
 * @brief Window controller for adding groups
 */
@implementation AINewGroupWindowController

/* The ownership home of every shown window. -showOnWindow: consumes the caller's reference (see
 * the header), so what keeps a shown controller alive is its place in this set; both exits leave
 * it. The same design as ESTextAndButtonsWindowController. */
static NSMutableSet *openNewGroupWindows = nil;

- (id)init
{
	if (self = [super initWithWindowNibName:ADD_GROUP_PROMPT_NIB]) {
		
	}
	
	return self;
}

- (void)showOnWindow:(NSWindow *)parentWindow
{
	if (!openNewGroupWindows) openNewGroupWindows = [[NSMutableSet alloc] init];
	[openNewGroupWindows addObject:self];

	if (parentWindow) {
		[parentWindow beginSheet:self.window
			   completionHandler:^(NSModalResponse returnCode) {
				[self sheetDidEnd:self.window returnCode:returnCode contextInfo:NULL];
			}];
	} else {
		[self showWindow:nil];
	}
}

/*!
 * @brief Setup the window before it is displayed
 */
- (void)windowDidLoad
{
	NSWindow	*window = [self window];
	
	[window setTitle:AILocalizedString(@"Add Group",nil)];
	
	[label_groupName setStringValue:AILocalizedString(@"Enter group name:",nil)];
	[button_add setTitle:AILocalizedString(@"Add",nil)];
	[button_cancel setTitle:AILocalizedString(@"Cancel",nil)];

	[window center];
}

/*!
 * @brief Called as the user list edit sheet closes, dismisses the sheet
 */
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	[[NSNotificationCenter defaultCenter] postNotificationName:@"NewGroupWindowControllerDidEnd"
											  object:sheet];
    [sheet orderOut:nil];

	/* Out of the set, but not before this turn of the run loop ends: both exits are reached from
	 * inside AppKit's own close, which goes on addressing this object afterwards. It also makes the
	 * two harmless should they ever both run, which the pair of autoreleases here would not have
	 * been, since that would have given the same reference back twice.
	 */
	CFAutorelease(CFBridgingRetain(self));
	[openNewGroupWindows removeObject:self];
}

- (void)windowWillClose:(id)sender
{
	[super windowWillClose:sender];

	/* Out of the set, but not before this turn of the run loop ends: both exits are reached from
	 * inside AppKit's own close, which goes on addressing this object afterwards. It also makes the
	 * two harmless should they ever both run, which the pair of autoreleases here would not have
	 * been, since that would have given the same reference back twice.
	 */
	CFAutorelease(CFBridgingRetain(self));
	[openNewGroupWindows removeObject:self];
}

/*!
 * @brief Cancel
 */
- (IBAction)cancel:(id)sender
{
	[self closeWindow:nil];
}

/*!
 * @brief The newly created group
 */
- (AIListGroup *)group
{
	return group;
}

/*!
 * @brief Add the group
 */
- (IBAction)addGroup:(id)sender
{
	group = [adium.contactController groupWithUID:[textField_groupName stringValue]];
	
	//Force this new group to be visible.  Obviously the user created it for a reason, so let's keep
	//it visible and give them time to stick something inside.
	[group setValue:[NSNumber numberWithBool:YES] forProperty:@"New Object" notify:YES];

	[self closeWindow:nil];
}

@end
