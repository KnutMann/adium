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

#import <Adium/ESPresetNameSheetController.h>

#define	PRESET_NAME_SHEET	@"PresetNameSheet"

@interface ESPresetNameSheetController ()
- (void)configureExplanatoryTextWithString:(NSString *)inExplanatoryText;
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
@end

/* The name sheets currently on screen.
 *
 * -showOnWindow: is declared ns_consumes_self. Under manual counting that was decoration; counted
 * automatically it means what it says: the caller's one reference is handed over at the call and
 * given up when the method returns, so with nothing else holding on, the controller would die as
 * its sheet appeared. This set is that something else, and it takes the place of a scheme in which
 * the object was its own owner and handed itself to the pool on the way out.
 */
static NSMutableSet *openPresetNameSheets = nil;

@implementation ESPresetNameSheetController

- (void)showOnWindow:(NSWindow *)parentWindow
{
	//Must be called on a window
	NSParameterAssert(parentWindow != nil);

	if (!openPresetNameSheets) openPresetNameSheets = [[NSMutableSet alloc] init];
	[openPresetNameSheets addObject:self];

	[parentWindow beginSheet:self.window
		   completionHandler:^(NSModalResponse returnCode) {
			[self sheetDidEnd:self.window returnCode:returnCode contextInfo:NULL];
		}];
}

- (id)initWithDefaultName:(NSString *)inDefaultName explanatoryText:(NSString *)inExplanatoryText notifyingTarget:(id)inTarget userInfo:(id)inUserInfo
{
	//Target must respond to the ending selector
	NSParameterAssert([inTarget respondsToSelector:@selector(presetNameSheetControllerDidEnd:returnCode:newName:userInfo:)]);
	
	if ((self = [super initWithWindowNibName:PRESET_NAME_SHEET])) {
		defaultName = inDefaultName;
		explanatoryText = inExplanatoryText;
		target = inTarget;
		userInfo = inUserInfo;
	}
	
	return self;
}

/*!
 * @brief Invoked as the sheet closes, dismiss the sheet
 */
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:nil];

	/* Out of the set, but not before this turn of the run loop ends: both exits are reached from
	 * inside AppKit's own close, which goes on addressing this object afterwards. It also makes the
	 * two harmless should they ever both run, which the pair of autoreleases here would not have
	 * been, since that would have given the same reference back twice.
	 */
	CFAutorelease(CFBridgingRetain(self));
	[openPresetNameSheets removeObject:self];
}

/*!
 * @brief As the window closes, leave the set of open sheets
 */
- (void)windowWillClose:(id)sender
{
	[super windowWillClose:sender];

	/* Out of the set, but not before this turn of the run loop ends: both exits are reached from
	 * inside AppKit's own close, which goes on addressing this object afterwards. It also makes the
	 * two harmless should they ever both run, which the pair of autoreleases here would not have
	 * been, since that would have given the same reference back twice.
	 */
	CFAutorelease(CFBridgingRetain(self));
	[openPresetNameSheets removeObject:self];
}

- (IBAction)okay:(id)sender
{
	NSString	*newName = [textField_name stringValue];
	
	if (![target respondsToSelector:@selector(presetNameSheetController:shouldAcceptNewName:userInfo:)] ||
	   [target presetNameSheetController:self
					 shouldAcceptNewName:newName
								userInfo:userInfo]) {
		
		[target presetNameSheetControllerDidEnd:self 
									 returnCode:ESPresetNameSheetOkayReturn 
										newName:newName
									   userInfo:userInfo];
		
		[self closeWindow:nil];

	} else {
		NSString	*nameInUseText;
		
		nameInUseText = [NSString stringWithFormat:AILocalizedString(@"\"%@\" is already in use.", nil), newName];
		[self configureExplanatoryTextWithString:[NSString stringWithFormat:@"%@\n\n%@", explanatoryText, nameInUseText]];

		NSBeep();
	}
}

- (IBAction)cancel:(id)sender
{
	[target presetNameSheetControllerDidEnd:self
								 returnCode:ESPresetNameSheetCancelReturn
									newName:nil
								   userInfo:userInfo];

	[self closeWindow:nil];	
}

- (void)windowDidLoad
{
	[textView_explanatoryText setHorizontallyResizable:NO];
    [textView_explanatoryText setVerticallyResizable:YES];
    [textView_explanatoryText setDrawsBackground:NO];
    [scrollView_explanatoryText setDrawsBackground:NO];

	//Set the default name
	[textField_name setStringValue:defaultName];
	[label_name setStringValue:AILocalizedString(@"Title:", "Label in front of the title for a preset")];
	[button_ok setTitle:AILocalizedString(@"OK", nil)];
	[button_cancel setTitle:AILocalizedString(@"Cancel", nil)];
	
	[self configureExplanatoryTextWithString:explanatoryText];
}

- (void)configureExplanatoryTextWithString:(NSString *)inExplanatoryText
{
	NSRect	frame = [[self window] frame];
	CGFloat		heightChange = 0;
		
	//Set the explanatory text and resize as needed
	[textView_explanatoryText setString:inExplanatoryText];
	   
	//Resize the window frame to fit the error title
	[textView_explanatoryText sizeToFit];
	heightChange += [textView_explanatoryText frame].size.height - [scrollView_explanatoryText documentVisibleRect].size.height;
	   
	frame.size.height += heightChange;
	frame.origin.y -= heightChange;
	
	//Perform the window resizing as needed
	[[self window] setFrame:frame display:YES animate:YES];
}

@end
