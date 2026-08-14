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

#import "AITypstPlugin.h"
#import "AITypstRenderer.h"
#import "AITypstEditorView.h"

#import <Adium/AIChat.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIMenuControllerProtocol.h>
#import <Adium/AIToolbarControllerProtocol.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIStringUtilities.h>
#import <AIUtilities/AIToolbarUtilities.h>
#import <AIUtilities/AIImageAdditions.h>

#import "AIMessageViewController.h"

#define TITLE_SHOW_EDITOR		AILocalizedString(@"Formula Editor", "Menu item which opens and closes the Typst formula editor at the bottom of a chat")
#define TITLE_RENDER_FORMULA	AILocalizedString(@"Render Formula", "Menu item which replaces the selected Typst source with the picture it renders to")

@interface AITypstPlugin ()
- (void)toggleEditor:(id)sender;
- (void)renderSelection:(id)sender;
- (NSTextView *)activeEditableTextView;
- (AIChat *)chatForToolbar:(NSToolbarItem *)senderItem;
- (void)setEditorVisible:(BOOL)visible forChat:(AIChat *)chat;
- (BOOL)editorIsVisibleForChat:(AIChat *)chat;
@end

@implementation AITypstPlugin

- (void)installPlugin
{
	menuItem_showEditor = [[NSMenuItem alloc] initWithTitle:TITLE_SHOW_EDITOR
													 target:self
													 action:@selector(toggleEditor:)
											  keyEquivalent:@"t"];
	[menuItem_showEditor setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];
	[adium.menuController addMenuItem:menuItem_showEditor toLocation:LOC_Edit_Additions];

	/* No key equivalent for this one. It is the quicker of the two, but the editor is the one worth
	 * spending a shortcut on, and a second formula shortcut a modifier apart would be a good way to
	 * hit the wrong one. */
	menuItem_renderSelection = [[NSMenuItem alloc] initWithTitle:TITLE_RENDER_FORMULA
														 target:self
														 action:@selector(renderSelection:)
												  keyEquivalent:@""];
	[adium.menuController addMenuItem:menuItem_renderSelection toLocation:LOC_Edit_Additions];

	/* An image item rather than a view based one. NSToolbarItem forwards target and action to a custom
	 * view that responds to them, and AIToolbarUtilities sets the target while the view is still nil,
	 * so a view based item ends up with an action and no target. Image items also validate, which view
	 * based ones never do. */
	NSImage *icon = [NSImage imageWithSystemSymbolName:@"function" accessibilityDescription:TITLE_SHOW_EDITOR];
	if (!icon) icon = [NSImage imageNamed:NSImageNameAdvanced];

	toolbarItem_editor = [[AIToolbarUtilities toolbarItemWithIdentifier:@"FormulaEditor"
																 label:AILocalizedString(@"Formula", "Toolbar item which opens the formula editor")
														  paletteLabel:AILocalizedString(@"Formula Editor", nil)
															   toolTip:AILocalizedString(@"Show or hide the formula editor", nil)
																target:self
													   settingSelector:@selector(setImage:)
														   itemContent:icon
																action:@selector(toggleEditor:)
																  menu:nil] retain];

	[adium.toolbarController registerToolbarItem:toolbarItem_editor forToolbarType:@"TextEntry"];
}

- (void)uninstallPlugin
{
	[adium.menuController removeMenuItem:menuItem_showEditor];
	[adium.menuController removeMenuItem:menuItem_renderSelection];
	[adium.toolbarController unregisterToolbarItem:toolbarItem_editor forToolbarType:@"TextEntry"];

	[menuItem_showEditor release];		menuItem_showEditor = nil;
	[menuItem_renderSelection release];	menuItem_renderSelection = nil;
	[toolbarItem_editor release];		toolbarItem_editor = nil;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if (menuItem == menuItem_showEditor) {
		if (![AITypstRenderer typstIsAvailable])
			return NO;

		AIChat *chat = adium.interfaceController.activeChat;
		[menuItem setState:([self editorIsVisibleForChat:chat] ? NSControlStateValueOn : NSControlStateValueOff)];

		return (chat != nil);
	}

	if (menuItem == menuItem_renderSelection) {
		if (![AITypstRenderer typstIsAvailable])
			return NO;

		NSTextView *textView = [self activeEditableTextView];
		return (textView && [textView selectedRange].length > 0);
	}

	return YES;
}

//The editor -----------------------------------------------------------------------------------------------------------
#pragma mark The editor

- (void)toggleEditor:(id)sender
{
	AIChat *chat = nil;

	/* A toolbar item is answered from its own window, not from whichever chat happens to be frontmost.
	 * A toolbar in a window that is not key can still be clicked, and taking the active chat then
	 * opens the editor on the wrong conversation. */
	if ([sender isKindOfClass:[NSToolbarItem class]])
		chat = [self chatForToolbar:(NSToolbarItem *)sender];
	else
		chat = adium.interfaceController.activeChat;

	if (!chat) return;

	[self setEditorVisible:![self editorIsVisibleForChat:chat] forChat:chat];
}

- (BOOL)editorIsVisibleForChat:(AIChat *)chat
{
	if (!chat) return NO;

	return [[chat.chatContainer.messageViewController shelfView] isKindOfClass:[AITypstEditorView class]];
}

- (void)setEditorVisible:(BOOL)visible forChat:(AIChat *)chat
{
	AIMessageViewController *messageViewController = chat.chatContainer.messageViewController;
	if (!messageViewController) return;

	if (!visible) {
		[messageViewController setShelfView:nil];
		return;
	}

	AITypstEditorView *editor = [[AITypstEditorView alloc] initWithChat:chat];
	[messageViewController setShelfView:editor];
	[editor takeFocus];
	[editor release];
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

//The direct command ---------------------------------------------------------------------------------------------------
#pragma mark The direct command

/*!
 * @brief The text view the user is typing in, if that is where they are
 *
 * Deliberately the first responder rather than the active chat's entry view: the command applies to a
 * selection, so it only makes sense where the selection is, and this way it cannot act on a window
 * the user is not looking at.
 */
- (NSTextView *)activeEditableTextView
{
	NSResponder *responder = [[NSApp keyWindow] firstResponder];

	if ([responder isKindOfClass:[NSTextView class]] && [(NSTextView *)responder isEditable])
		return (NSTextView *)responder;

	return nil;
}

- (void)renderSelection:(id)sender
{
	NSTextView *textView = [self activeEditableTextView];
	if (!textView) return;

	NSRange range = [textView selectedRange];
	if (!range.length) return;

	NSString *formula = [[[textView string] substringWithRange:range] stringByTrimmingCharactersInSet:
						 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (![formula length]) return;

	/* Held onto so that the range is still meaningful when the render comes back. The user may have
	 * typed on in the meantime, which is why the insertion checks the text before replacing it. */
	NSString *capturedFormula = [[formula copy] autorelease];

	[AITypstRenderer renderFormula:formula
						 pointSize:0.0
						completion:^(NSString *path, NSString *errorMessage) {
		if (path) {
			[self insertImageAtPath:path
						 forFormula:capturedFormula
					   intoTextView:textView
						  overRange:range];
		} else {
			NSAlert *alert = [[[NSAlert alloc] init] autorelease];
			[alert setMessageText:AILocalizedString(@"That formula could not be rendered", nil)];
			[alert setInformativeText:errorMessage];
			[alert runModal];
		}
	}];
}

/*!
 * @brief Put the rendered image where the formula was
 */
- (void)insertImageAtPath:(NSString *)path
			   forFormula:(NSString *)formula
			 intoTextView:(NSTextView *)textView
				overRange:(NSRange)range
{
	NSAttributedString *attachment = [AITypstRenderer attachmentStringForImageAtPath:path formula:formula];
	if (!attachment) return;

	/* The selection may have moved or the text changed while typst was running. Replace only if what
	 * is there is still what was asked about; otherwise put the image at the insertion point and let
	 * the user place it. */
	NSRange targetRange = range;
	if (NSMaxRange(range) > [[textView string] length] ||
		![[[textView string] substringWithRange:range] hasSuffix:formula]) {
		targetRange = [textView selectedRange];
	}

	if ([textView shouldChangeTextInRange:targetRange replacementString:nil]) {
		[[textView textStorage] replaceCharactersInRange:targetRange withAttributedString:attachment];
		[textView didChangeText];
	}
}

- (void)dealloc
{
	[menuItem_showEditor release];
	[menuItem_renderSelection release];
	[toolbarItem_editor release];

	[super dealloc];
}

@end
