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
#import <Adium/JVFontPreviewField.h>

@interface AIListLayoutWindowController : AIWindowController <JVFontPreviewFieldDelegate> {

	IBOutlet		NSButton			*button_okay;
	IBOutlet		NSButton			*button_cancel;

	IBOutlet		NSTabViewItem		*tabViewItem_contacts;
	IBOutlet		NSTabViewItem		*tabViewItem_groups;
	IBOutlet		NSTabViewItem		*tabViewItem_spacing;

	IBOutlet		NSPopUpButton		*popUp_contactTextAlignment;
	IBOutlet		NSTextField			*label_contactAlignment;
	IBOutlet		NSPopUpButton		*popUp_groupTextAlignment;
	IBOutlet		NSTextField			*label_groupAlignment;
	IBOutlet		NSPopUpButton		*popUp_extendedStatusStyle;
	IBOutlet		NSPopUpButton		*popUp_extendedStatusPosition;
	IBOutlet		NSPopUpButton		*popUp_userIconPosition;
	IBOutlet		NSPopUpButton		*popUp_statusIconPosition;
	IBOutlet		NSPopUpButton		*popUp_serviceIconPosition;

	IBOutlet		NSButton			*checkBox_userIconVisible;
	IBOutlet		NSButton			*checkBox_extendedStatusVisible;
	IBOutlet		NSButton			*checkBox_statusIconsVisible;
	IBOutlet		NSButton			*checkBox_serviceIconsVisible;

	IBOutlet		NSSlider			*slider_userIconSize;
	IBOutlet		NSTextField			*textField_userIconSize;
	IBOutlet		NSTextField			*label_userIconSize;
	IBOutlet		NSSlider			*slider_contactSpacing;
	IBOutlet		NSTextField			*textField_contactSpacing;
	IBOutlet		NSTextField			*label_contactSpacing;
	IBOutlet		NSSlider			*slider_groupTopSpacing;
	IBOutlet		NSTextField			*textField_groupTopSpacing;
	IBOutlet		NSTextField			*label_groupTopSpacing;
	IBOutlet		NSSlider			*slider_contactLeftIndent;
	IBOutlet		NSTextField			*textField_contactLeftIndent;
	IBOutlet		NSTextField			*label_contactLeftIndent;
	IBOutlet		NSSlider			*slider_contactRightIndent;
	IBOutlet		NSTextField			*textField_contactRightIndent;
	IBOutlet		NSTextField			*label_contactRightIndent;

	IBOutlet		JVFontPreviewField	*fontField_contact;
	IBOutlet		NSTextField			*label_contactFont;
	IBOutlet		NSButton			*button_setContactFont;
	IBOutlet		JVFontPreviewField	*fontField_status;
	IBOutlet		NSTextField			*label_statusFont;
	IBOutlet		NSButton			*button_setStatusFont;
	IBOutlet		JVFontPreviewField	*fontField_group;
	IBOutlet		NSTextField			*label_groupFont;
	IBOutlet		NSButton			*button_setGroupFont;

	IBOutlet		NSTabView			*tabView_preferences;
	
	// Advanced contact bubble options
	IBOutlet		NSTabViewItem		*tabViewItem_advancedContactBubbles;
	IBOutlet		NSButton			*checkBox_outlineBubbles;
	IBOutlet		NSButton			*checkBox_drawContactBubblesWithGraadient;
	IBOutlet		NSButton			*checkBox_showGroupBubbles;
	IBOutlet		NSSlider			*slider_outlineWidth;
	IBOutlet		NSTextField			*textField_outlineWidthIndicator;
	IBOutlet		NSTextField			*label_gradientNote;
	
	id				target;
	NSString		*layoutName;	
}

- (void)showOnWindow:(NSWindow *)parentWindow __attribute__((ns_consumes_self));
- (id)initWithName:(NSString *)inName notifyingTarget:(id)inTarget;
- (IBAction)cancel:(id)sender;
- (IBAction)okay:(id)sender;
- (void)preferenceChanged:(id)sender;

@end

@interface NSObject (AIListLayoutWindowTarget)

- (void)listLayoutEditorWillCloseWithChanges:(BOOL)changes forLayoutNamed:(NSString *)name;

@end
