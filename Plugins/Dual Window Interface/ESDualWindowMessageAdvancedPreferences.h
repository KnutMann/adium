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

#import <Adium/AIAdvancedPreferencePane.h>
#import "AIWebKitMessageViewPlugin.h"

@class AISettingsFormView;

@interface ESDualWindowMessageAdvancedPreferences : AIAdvancedPreferencePane {
	__unsafe_unretained AISettingsFormView	*settingsForm;	//Our view, typed; unretained (-view owns it)

	/* Which of the two sets of per-chat-type preferences the rows show. The nib's
	 * tab view did not remember its selection either, so this is not a preference
	 * of its own: every pane starts on regular chats.
	 */
	AIWebkitStyleType	 selectedChatType;

	//The form's view tree owns every control below; -viewWillClose clears them
	__unsafe_unretained NSSegmentedControl	*segment_chatType;

	//Per chat type: regular chats and group chats keep separate values
	__unsafe_unretained NSSwitch			*checkBox_customNameFormatting;
	__unsafe_unretained NSPopUpButton		*popUp_nameFormat;
	__unsafe_unretained NSPopUpButton		*popUp_timeStampFormat;
	__unsafe_unretained NSPopUpButton		*popUp_minimumFontSize;
	__unsafe_unretained NSSwitch			*checkBox_showTabCount;
	__unsafe_unretained NSSwitch			*checkBox_unreadMentionCount;

	//Tabs

	//Window handling
	__unsafe_unretained NSSwitch			*checkBox_hide;
	__unsafe_unretained NSSwitch			*checkBox_psychicOpen;
	__unsafe_unretained NSPopUpButton		*popUp_windowPosition;
}

@property (readonly, nonatomic) NSString *preferenceGroupForCurrentTab;
@property (readonly, nonatomic) AIWebkitStyleType currentTab;

@end
