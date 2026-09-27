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
#import "AIVoiceRecorder.h"
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIToolbarControllerProtocol.h>
#import <Adium/AITextAttachmentExtension.h>
#import <Adium/AIMessageEntryAccessory.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIToolbarUtilities.h>
#import <AIUtilities/AIWindowAdditions.h>

#define VOICE_ITEM_IDENTIFIER @"VoiceNote"
#define KEY_VOICE_NOTE_BUTTON @"Voice Note Button"

@interface AIVoiceNotePlugin ()
- (void)registerToolbarItem;
- (IBAction)toggleRecording:(id)sender;
- (NSTextView *)entryFieldForSender:(id)sender;
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
											   toolTip:AILocalizedString(@"Record a voice note; click again to stop", nil)
												 image:[NSImage imageNamed:@"entry_voice" forClass:[self class]]
										 preferenceKey:KEY_VOICE_NOTE_BUTTON
												 group:PREF_GROUP_MESSAGE_ENTRY
												target:self
												action:@selector(toggleRecording:)]];
}

- (void)uninstallPlugin
{
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
														toolTip:AILocalizedString(@"Record a voice note; click again to stop", nil)
														 target:self
												settingSelector:@selector(setImage:)
													itemContent:microphone
														 action:@selector(toggleRecording:)
														   menu:nil];

	[adium.toolbarController registerToolbarItem:toolbarItem forToolbarType:@"TextEntry"];
}

/*!
 * @brief Where a message is being written right now
 *
 * A button in a message field says which field it stands in. A toolbar item does not, and asks
 * the same question the link editor asks, with the same answer: the field the key window is
 * typing into. Between start and stop the button that started the recording is remembered, so
 * the note lands in the conversation it was spoken for even if another has become key since.
 */
- (NSTextView *)entryFieldForSender:(id)sender
{
	if ([sender isKindOfClass:[AIMessageEntryAccessoryButton class]])
		return (NSTextView *)[(AIMessageEntryAccessoryButton *)sender messageEntryTextView];

	NSWindow *key = [NSApp keyWindow];
	return (NSTextView *)[key earliestResponderOfClass:[NSTextView class]];
}

- (void)showElapsed
{
	AIVoiceRecorder *recorder = [AIVoiceRecorder sharedRecorder];
	if (!recorder.recording) return;

	NSInteger seconds = (NSInteger)recorder.elapsed;
	[toolbarItem setLabel:[NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)]];
}

- (void)stopTicking
{
	[ticker invalidate];
	ticker = nil;
	[toolbarItem setLabel:AILocalizedString(@"Voice", "Toolbar button that records a voice note")];
	[toolbarItem setImage:[self microphoneRecording:NO]];
	[recordingButton setImage:recordingButton.accessory.image];
	recordingButton = nil;
}

- (IBAction)toggleRecording:(id)sender
{
	AIVoiceRecorder *recorder = [AIVoiceRecorder sharedRecorder];

	if (recorder.recording) {
		AIMessageEntryAccessoryButton *startedFrom = recordingButton;
		[self stopTicking];

		__weak __typeof__(self) weakSelf = self;
		[recorder stopAndWrite:^(NSString *path, NSTimeInterval duration, NSString *problem) {
			if (!path) {
				if (problem) [adium.interfaceController handleErrorMessage:AILocalizedString(@"Voice note", nil)
														  withDescription:problem];
				return;
			}
			[weakSelf placeNoteAtPath:path lasting:duration into:[weakSelf entryFieldForSender:(startedFrom ? startedFrom : sender)]];
		}];
		return;
	}

	if (![self entryFieldForSender:sender]) return;			//nothing to put it in, so nothing to record

	[recorder startWithCompletion:^(BOOL began, NSString *problem) {
		if (!began) {
			if (problem) [adium.interfaceController handleErrorMessage:AILocalizedString(@"Voice note", nil)
													  withDescription:problem];
			return;
		}

		[self->toolbarItem setImage:[self microphoneRecording:YES]];
		if ([sender isKindOfClass:[AIMessageEntryAccessoryButton class]]) {
			self->recordingButton = sender;
			[self->recordingButton setImage:[self recordingDotOn:self->recordingButton.accessory.image
														   described:AILocalizedString(@"Recording a voice note", "The microphone button while it is listening")]];
		}
		self->ticker = [NSTimer scheduledTimerWithTimeInterval:1.0
														target:self
													  selector:@selector(showElapsed)
													  userInfo:nil
													   repeats:YES];
	}];
}

/*!
 * @brief Put the finished note where the message is being written
 *
 * As an attachment, the way a formula is placed, so that the send path that carries pictures
 * and files carries this too and there is nothing new to go wrong. What is drawn in the field
 * is a microphone and the length, since a sound has no picture of its own.
 */
- (void)placeNoteAtPath:(NSString *)path lasting:(NSTimeInterval)duration into:(NSTextView *)field
{
	if (!field) return;

	NSString *shown = [NSString stringWithFormat:AILocalizedString(@"Voice note (%ld:%02ld)",
								"A recorded voice note in the entry field, with its length"),
					   (long)(duration / 60), (long)((NSInteger)duration % 60)];

	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	[attachment setPath:path];
	[attachment setString:shown];
	[attachment setShouldSaveImageForLogging:NO];
	//A note said is part of the conversation, so the chat keeps a player for it once it is sent
	[attachment setLeavesLinkWhenSent:YES];

	NSImage *icon = [NSImage imageWithSystemSymbolName:@"waveform" accessibilityDescription:shown];
	if (icon) {
		[icon setSize:NSMakeSize(18, 18)];
		[attachment setImage:icon];
		[attachment setAttachmentCell:[[NSTextAttachmentCell alloc] initImageCell:icon]];
	}

	[field insertText:[NSAttributedString attributedStringWithAttachment:attachment]
	 replacementRange:[field selectedRange]];
}

@end
