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

#import "AIVoiceNotePlugin.h"
#import "AIVoiceNoteShelfView.h"
#import "AIVoiceRecorder.h"
#import "AIMessageViewController.h"
#import <Adium/AIChat.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIToolbarControllerProtocol.h>
#import <Adium/AIMessageEntryAccessory.h>
#import <Adium/AIMessageEntryTextView.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIToolbarUtilities.h>

#define KEY_VOICE_NOTE_BUTTON @"Voice Note Button"

@interface AIVoiceNotePlugin ()
- (void)registerToolbarItem;
- (IBAction)toggleRecorder:(id)sender;
- (AIChat *)chatForSender:(id)sender;
- (AIChat *)chatForToolbar:(NSToolbarItem *)senderItem;
- (void)recorderStateDidChange:(NSNotification *)notification;
@end

@implementation AIVoiceNotePlugin

- (void)installPlugin
{
	[self registerToolbarItem];

	//The same button in the message field itself, off until it is asked for
	[adium.preferenceController registerDefaults:@{KEY_VOICE_NOTE_BUTTON: @NO} forGroup:PREF_GROUP_MESSAGE_ENTRY];
	[AIMessageEntryAccessory registerAccessory:
	 [AIMessageEntryAccessory accessoryWithIdentifier:VOICE_ITEM_IDENTIFIER
												 label:AILocalizedString(@"Record Voice Note", nil)
											   toolTip:AILocalizedString(@"Record a voice note", nil)
												 image:[NSImage imageNamed:@"entry_voice" forClass:[self class]]
										 preferenceKey:KEY_VOICE_NOTE_BUTTON
												 group:PREF_GROUP_MESSAGE_ENTRY
												target:self
												action:@selector(toggleRecorder:)]];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(recorderStateDidChange:)
												 name:AIVoiceRecorderStateDidChangeNotification
											   object:nil];
}

- (void)uninstallPlugin
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[ticker invalidate];
	ticker = nil;
	[AIMessageEntryAccessory unregisterAccessoryWithIdentifier:VOICE_ITEM_IDENTIFIER];

	if (toolbarItem) {
		[adium.toolbarController unregisterToolbarItem:toolbarItem forToolbarType:@"TextEntry"];
		toolbarItem = nil;
	}
}

/*!
 * @brief The microphone, with the red dot on it while it is listening
 *
 * There is no system symbol for a microphone that is recording, so the dot is put on the one there
 * is. Drawn each time it is asked for rather than kept: the microphone is drawn in the label
 * colour, which is not the same colour in a dark window as in a light one, and a picture made once
 * would keep whichever colour it was made in.
 */
- (NSImage *)microphoneRecording:(BOOL)recording
{
	NSString	*description = (recording ?
								AILocalizedString(@"Recording a voice note", "The microphone button while it is listening") :
								AILocalizedString(@"Record Voice Note", nil));
	NSImage		*microphone = [NSImage imageWithSystemSymbolName:@"mic" accessibilityDescription:description];

	if (!recording || !microphone)
		return microphone;

	//A template is drawn black wherever it is put; asked for in the label colour, it follows the window
	NSImage *shown = [microphone imageWithSymbolConfiguration:
					  [NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor labelColor]]];

	return [self recordingDotOn:(shown ? shown : microphone) described:description];
}

/*!
 * @brief A red dot in the top right corner of @a image, the sign that it is listening
 */
- (NSImage *)recordingDotOn:(NSImage *)image described:(NSString *)description
{
	NSImage *badged = [NSImage imageWithSize:[image size]
									 flipped:NO
							  drawingHandler:^BOOL(NSRect rect) {
		[image drawInRect:rect
				 fromRect:NSZeroRect
				operation:NSCompositingOperationSourceOver
				 fraction:1.0];

		CGFloat	size = MAX(4.0, floor(NSWidth(rect) / 3.0));
		NSRect	dot = NSMakeRect(NSMaxX(rect) - size, NSMaxY(rect) - size, size, size);

		[[NSColor systemRedColor] setFill];
		[[NSBezierPath bezierPathWithOvalInRect:dot] fill];

		return YES;
	}];

	[badged setAccessibilityDescription:description];

	return badged;
}

- (void)registerToolbarItem
{
	NSImage *microphone = [self microphoneRecording:NO];

	toolbarItem = [AIToolbarUtilities toolbarItemWithIdentifier:VOICE_ITEM_IDENTIFIER
														  label:AILocalizedString(@"Voice", "Toolbar button that records a voice note")
												   paletteLabel:AILocalizedString(@"Record Voice Note", nil)
														toolTip:AILocalizedString(@"Record a voice note", nil)
														 target:self
												settingSelector:@selector(setImage:)
													itemContent:microphone
														 action:@selector(toggleRecorder:)
														   menu:nil];

	[adium.toolbarController registerToolbarItem:toolbarItem forToolbarType:@"TextEntry"];
}

//Opening the recorder ---------------------------------------------------------------------------------------------------
#pragma mark Opening the recorder

/*!
 * @brief Which conversation a click means
 *
 * A button in a message field belongs to that field's chat, and a toolbar item is answered from
 * its own window, not from whichever chat happens to be frontmost. Either can be clicked in a
 * window that is not key, and taking the active chat then would open the recorder on the wrong
 * conversation.
 */
- (AIChat *)chatForSender:(id)sender
{
	if ([sender isKindOfClass:[AIMessageEntryAccessoryButton class]])
		return [(AIMessageEntryAccessoryButton *)sender messageEntryTextView].chat;
	else if ([sender isKindOfClass:[NSToolbarItem class]])
		return [self chatForToolbar:(NSToolbarItem *)sender];
	else
		return adium.interfaceController.activeChat;
}

- (AIChat *)chatForToolbar:(NSToolbarItem *)senderItem
{
	NSToolbar *senderToolbar = [senderItem toolbar];

	for (NSWindow *currentWindow in [NSApp windows]) {
		if ([currentWindow toolbar] && ([currentWindow toolbar] == senderToolbar))
			return [adium.interfaceController activeChatInWindow:currentWindow];
	}

	return nil;
}

/*!
 * @brief The microphone button was pressed
 *
 * With no recorder open in that conversation it opens one and starts recording. With one open
 * the same button pauses and resumes, and never closes: a note is only ever thrown away by the
 * bin on the shelf, which is a deliberate act, not a second click on the button that began it.
 *
 * There is one recorder for the whole application, so a note under way in another conversation
 * is not interrupted from here; it is said where the other one is.
 */
- (IBAction)toggleRecorder:(id)sender
{
	AIChat *chat = [self chatForSender:sender];
	AIMessageViewController *messageViewController = chat.chatContainer.messageViewController;
	if (!messageViewController) return;

	NSView *shelf = [messageViewController shelfView];
	if ([shelf isKindOfClass:[AIVoiceNoteShelfView class]]) {
		[(AIVoiceNoteShelfView *)shelf togglePause:sender];
		return;
	}

	if ([[AIVoiceRecorder sharedRecorder] holdsRecording]) {
		[adium.interfaceController handleErrorMessage:AILocalizedString(@"Voice note", nil)
									  withDescription:AILocalizedString(@"A voice note is already being recorded in another conversation.", nil)];
		return;
	}

	if ([messageViewController shelfIsBusy]) {
		NSBeep();
		return;
	}

	AIVoiceNoteShelfView *recorder = [[AIVoiceNoteShelfView alloc] initWithChat:chat];
	[messageViewController setShelfView:recorder];
	[recorder startRecording];
}

//Keeping the buttons in step --------------------------------------------------------------------------------------------
#pragma mark Keeping the buttons in step

/*!
 * @brief The recorder began, paused, resumed or finished
 *
 * The toolbar item shows the dot and counts while the microphone is open, in every window, since
 * a toolbar cannot tell which conversation is recording. The button in a message field shows the
 * dot only in the conversation whose shelf holds the recorder, which is the one it belongs to.
 */
- (void)recorderStateDidChange:(NSNotification *)notification
{
	BOOL recording = [[AIVoiceRecorder sharedRecorder] isRecording];

	[toolbarItem setImage:[self microphoneRecording:recording]];
	if (recording) {
		if (!ticker) {
			ticker = [NSTimer scheduledTimerWithTimeInterval:1.0
													  target:self
													selector:@selector(showElapsed)
													userInfo:nil
													 repeats:YES];
		}
		[self showElapsed];
	} else {
		[ticker invalidate];
		ticker = nil;
		[toolbarItem setLabel:AILocalizedString(@"Voice", "Toolbar button that records a voice note")];
	}

	for (AIChat *chat in adium.interfaceController.openChats) {
		AIMessageViewController *messageViewController = chat.chatContainer.messageViewController;
		AIMessageEntryAccessoryButton *button = [[messageViewController textEntryView] accessoryButtonWithIdentifier:VOICE_ITEM_IDENTIFIER];
		if (!button) continue;

		BOOL here = (recording && [[messageViewController shelfView] isKindOfClass:[AIVoiceNoteShelfView class]]);
		[button setImage:(here ?
						  [self recordingDotOn:button.accessory.image
									 described:AILocalizedString(@"Recording a voice note", "The microphone button while it is listening")] :
						  button.accessory.image)];
	}
}

- (void)showElapsed
{
	AIVoiceRecorder *recorder = [AIVoiceRecorder sharedRecorder];
	if (!recorder.recording) return;

	NSInteger seconds = (NSInteger)recorder.duration;
	[toolbarItem setLabel:[NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)]];
}

@end
