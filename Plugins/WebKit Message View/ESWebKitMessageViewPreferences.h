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

#import <Adium/AIPreferencePane.h>
#import "AIWebKitMessageViewPlugin.h"

@class AISettingsFormView, ESWebView, AIContentObject, AIWebKitPreviewMessageViewController;
@class JVFontPreviewField, AIImageViewWithImagePicker;

/*!
 *	@class ESWebKitMessageViewPreferences ESWebKitMessageViewPreferences.h
 *	@brief Handles the messages preference pane
 */
@interface ESWebKitMessageViewPreferences : AIPreferencePane {
	AISettingsFormView	*settingsForm;			//Our view, typed; unretained (-view owns it)

	/* Which of the two per-chat-type preference groups the rows show. The nib's
	 * tab view did not remember its selection either: every pane starts on
	 * regular chats.
	 */
	AIWebkitStyleType	 selectedChatType;

	NSSegmentedControl	*segment_chatType;
	NSSwitch			*checkBox_useRegularChatForGroup;

	NSPopUpButton		*popUp_styles;
	NSPopUpButton		*popUp_variants;
	NSSwitch			*checkBox_showUserIcons;
	NSSwitch			*checkBox_showHeader;
	NSSwitch			*checkBox_hideScrollbar;

	JVFontPreviewField	*fontPreviewField_currentFont;
	NSButton			*button_setFont;
	NSButton			*button_defaultFont;
	NSSwitch			*checkBox_showMessageFonts;
	NSSwitch			*checkBox_showMessageColors;

	NSSwitch			*checkBox_useCustomBackground;
	AIImageViewWithImagePicker	*imageView_backgroundImage;
	NSPopUpButton		*popUp_backgroundImageType;
	NSColorWell			*colorWell_customBackgroundColor;

	//Message preview
	NSView									*view_previewLocation;
	NSMutableDictionary						*previewListObjectsDict;
	AIWebKitPreviewMessageViewController	*previewController;
	ESWebView								*preview;

	BOOL							viewIsOpen;
}

/*!
 *	@brief Rebuild our styles menu when installed message styles change
 */
- (void)messageStyleXtrasDidChange;

/*!
 * @brief Reset display font to the default value
 */
- (IBAction)resetDisplayFontToDefault:(id)sender;

@property (readonly, nonatomic) NSString *preferenceGroupForCurrentTab;
@property (readonly, nonatomic) AIWebkitStyleType currentTab;

@end
