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

#import "ESChatUserListController.h"
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIMessageEntryTextView.h>

@class AIAccount, AIListContact, AIListObject, AIAccountSelectionView, AIMessageTabSplitView;
@class AIMessageWindowController, AIMessageWindowOutgoingScrollView;
@class AIGradientView;

@interface AIMessageViewController : NSObject <AIListControllerDelegate, AIChatViewController, AIMessageEntryTextViewDelegate> {
	IBOutlet	NSView			*view_contents;
	
	//Split views
	IBOutlet	NSSplitView		*splitView_textEntryHorizontal;
	IBOutlet	NSSplitView		*splitView_verticalSplit;

	/* The shelf. Both are nil until something asks for one, so a chat that never opens a shelf keeps
	 * exactly the view tree the nib describes. */
	NSSplitView				*splitView_shelf;
	NSView					*view_shelf;

	//Message Display
	IBOutlet	AIMessageWindowOutgoingScrollView *scrollView_messages;
	IBOutlet	NSView					*view_messages;
	
	//User List
	IBOutlet	NSView					*view_userList;
	IBOutlet	AIAutoScrollView		*scrollView_userList;
    IBOutlet	AIListOutlineView		*userListView;
	ESChatUserListController			*userListController;
	IBOutlet	NSButton				*performAction;
	IBOutlet	NSTextField				*label_userCount;
	IBOutlet	AIGradientView			*actionBarView;

	//Text entry
	IBOutlet	AIMessageEntryTextView	*textView_outgoing;
	IBOutlet	NSScrollView			*scrollView_textEntry;

	//
    NSObject<AIMessageDisplayController>	*messageDisplayController;
	IBOutlet	AIAccountSelectionView		*view_accountSelection;
	AIMessageWindowController				*messageWindowController;
	
	//menuitem
	NSMenuItem				*showHide;

    AIChat					*chat;
	BOOL					accountSelectionVisible;
	BOOL					suppressSendLaterPrompt;
	CGFloat					entryMinHeight;
	
	BOOL					userListOnRight;
	CGFloat					userListMinWidth;

	NSUndoManager			*undoManager;
	
	NSWritingDirection		initialBaseWritingDirection;
}

+ (AIMessageViewController *)messageDisplayControllerForChat:(AIChat *)inChat;
- (void)messageViewWillLeaveWindowController:(AIMessageWindowController *)inWindowController;
- (void)messageViewAddedToWindowController:(AIMessageWindowController *)inWindowController;
- (AIChat *)chat;

- (AIListContact *)listObject;
- (AIListObject *)preferredListObject;
- (NSArray *)selectedListObjects;

//Message Display
- (NSObject<AIMessageDisplayController> *)messageDisplayController;
- (NSView *)view;
- (void)adiumPrint:(id)sender;

//Message Entry
- (IBAction)sendMessage:(id)sender;
- (IBAction)didSendMessage:(id)sender;
- (IBAction)sendMessageLater:(id)sender;

//User List
- (IBAction)showActionMenu:(id)sender;

/*!
 * @brief Put a view on a shelf across the bottom of the conversation, or take it away again
 *
 * The shelf spans the full width of the chat, beneath both the message view and the participant
 * list, and the user can drag its divider. It exists so that a plugin can offer a working area that
 * belongs to one conversation, rather than a panel floating somewhere with no idea which chat it is
 * meant for.
 *
 * There is room for one shelf. A second caller passing a view replaces the first one's, so a plugin
 * should ask what is there before it takes the space.
 *
 * @param inView The view to install, or nil to remove the shelf entirely
 */
- (void)setShelfView:(NSView *)inView;

/*!
 * @brief What is currently on the shelf, or nil
 */
- (NSView *)shelfView;

//Account Selection
- (void)redisplaySourceAndDestinationSelector:(NSNotification *)notification;
- (void)setAccountSelectionMenuVisibleIfNeeded:(BOOL)makeVisible;

//Text Entry
- (AIMessageEntryTextView *)textEntryView;
- (void)makeTextEntryViewFirstResponder;
- (void)clearTextEntryView;
- (void)addToTextEntryView:(NSAttributedString *)inString;
- (void)addDraggedDataToTextEntryView:(id <NSDraggingInfo>)draggingInfo;
 
- (void)tabViewDidChangeVisibility;
- (void)didSelect;
- (void)willDeselect;

@end

