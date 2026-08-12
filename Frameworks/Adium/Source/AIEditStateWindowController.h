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

#import <Adium/AIWindowController.h>
#import <Adium/AIStatus.h>

@class AIAccount, AITextViewWithPlaceholder, AIService, AIAutoScrollView, AISendingTextView, AISettingsFormView;

/*!
 * @class AIEditStateWindowController
 * @brief The editor for a single status: title, state, message and the two silences
 *
 * Everything but the message text view is built in code on an AISettingsFormView, so this window
 * reads like the rest of the converted interface. The nib holds the window and that one control;
 * see EditStateSheet.xib.
 */
@interface AIEditStateWindowController : AIWindowController <NSTextViewDelegate> {
	//Out of the nib
	IBOutlet	AISendingTextView		*textView_statusMessage;
	IBOutlet	AIAutoScrollView		*scrollView_statusMessage;

	//Built in -windowDidLoad; the form owns them, these references do not retain
	AISettingsFormView	*form;
	NSTextField			*textField_title;
	NSPopUpButton		*popUp_state;
	NSSwitch			*switch_muteSounds;
	NSSwitch			*switch_silenceNotifications;
	NSSwitch			*switch_save;
	NSButton			*button_okay;
	NSButton			*button_cancel;

	BOOL		needToRebuildPopUpState;

	AIStatus	*originalStatusState;
	AIStatus	*workingStatusState;
	AIAccount	*account;

	id			target;

	BOOL		showSaveCheckbox;

	/* A sheet is cleaned up from its completion handler, a window from -windowWillClose:. Both may
	 * run for one and the same editor, and releasing twice would be a crash. */
	BOOL		didFinish;
}

+ (id)editCustomState:(AIStatus *)inStatusState forType:(AIStatusType)inStatusType andAccount:(AIAccount *)inAccount withSaveOption:(BOOL)allowSave onWindow:(id)parentWindow notifyingTarget:(id)inTarget;

- (IBAction)cancel:(id)sender;
- (IBAction)okay:(id)sender;
- (IBAction)statusControlChanged:(id)sender;

- (void)configureForState:(AIStatus *)state;
- (AIStatus *)currentConfiguration;

@end

@interface NSObject (AICustomStatusWindowTarget)
- (void)customStatusState:(AIStatus *)originalState changedTo:(AIStatus *)newState forAccount:(AIAccount *)account;
@end
