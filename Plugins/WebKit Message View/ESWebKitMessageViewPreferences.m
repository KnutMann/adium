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

#import "ESWebKitMessageViewPreferences.h"
#import "AIWebKitMessageViewPlugin.h"
#import "AIWebkitMessageViewStyle.h"
#import "AIWebKitPreviewMessageViewController.h"
#import "AIPreviewChat.h"
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIAccount.h>
#import <Adium/AIChat.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIContentObject.h>
#import <Adium/AIContentEvent.h>
#import <Adium/AIListContact.h>
#import <Adium/AIHTMLDecoder.h>
#import <Adium/AIService.h>
#import <Adium/JVFontPreviewField.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIColorAdditions.h>
#import <AIUtilities/AIFontAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>
#import <AIUtilities/AIBundleAdditions.h>
#import <AIUtilities/AIDateFormatterAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIImageViewWithImagePicker.h>

#import "AIPreviewContentMessage.h"

#define WEBKIT_PREVIEW_CONVERSATION_FILE	@"Preview"
#define	PREF_GROUP_DISPLAYFORMAT			@"Display Format"  //To watch when the contact name display format changes

//Width the form starts out at; the preferences window resizes it to its column.
#define MESSAGES_PANE_INITIAL_WIDTH			540.0

/* Taller than the old pane's 148 point strip: the preview is a card of its own
 * now and is what every other row on this pane is judged against.
 */
#define MESSAGES_PREVIEW_HEIGHT				200.0

//The nib's fixed sizes for the two controls that have no natural size of their own
#define FONT_PREVIEW_FIELD_WIDTH			160.0
#define FONT_PREVIEW_FIELD_HEIGHT			17.0
#define BACKGROUND_IMAGE_WELL_WIDTH			70.0
#define BACKGROUND_IMAGE_WELL_HEIGHT		54.0
#define COLOR_WELL_WIDTH					44.0
#define COLOR_WELL_HEIGHT					23.0

@interface ESWebKitMessageViewPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (NSSegmentedControl *)chatTypeSegmentedControl;
- (void)menusChanged;
- (void)layOutChangedMenus;
- (IBAction)changeChatType:(id)sender;
- (void)configurePreferencesForTab;
- (void)_setBackgroundImage:(NSImage *)image;
- (NSMenu *)_stylesMenu;
- (NSMenu *)_variantsMenu;
- (NSMenu *)_backgroundImageTypeMenu;
- (void)_addBackgroundImageTypeChoice:(NSInteger)tag toMenu:(NSMenu *)menu withTitle:(NSString *)title;
- (void)_configureChatPreview;
- (AIChat *)previewChatWithDictionary:(NSDictionary *)previewDict fromPath:(NSString *)previewPath listObjects:(NSDictionary **)outListObjects;
- (void)_fillContentOfChat:(AIChat *)inChat withDictionary:(NSDictionary *)previewDict fromPath:(NSString *)previewPath listObjects:(NSDictionary *)listObjects;
- (NSMutableDictionary *)_addParticipants:(NSDictionary *)participants toChat:(AIChat *)inChat fromPath:(NSString *)previewPath;
- (void)_applySettings:(NSDictionary *)chatDict toChat:(AIPreviewChat *)inChat withParticipants:(NSDictionary *)participants;
- (void)_addContent:(NSArray *)chatArray toChat:(AIChat *)inChat withParticipants:(NSDictionary *)participants;
- (void)_setDisplayFontFace:(NSString *)face size:(NSNumber *)size;
@end

@class AIPreviewChat;

/*!
 * @brief A nib label reused as a row label: without its trailing colon.
 *
 * Keeps every existing translation of the old labels usable while matching the
 * System Settings look, where row labels carry no colon.
 */
static NSString *AIRowLabel(NSString *label)
{
	NSCharacterSet	*whitespace = [NSCharacterSet whitespaceCharacterSet];
	/* U+003A and the full width U+FF1A the CJK translations use */
	NSCharacterSet	*colons = [NSCharacterSet characterSetWithCharactersInString:@":："];
	NSString		*trimmed = [label stringByTrimmingCharactersInSet:whitespace];

	while ([trimmed length] > 0 &&
		   [colons characterIsMember:[trimmed characterAtIndex:([trimmed length] - 1)]]) {
		trimmed = [[trimmed substringToIndex:([trimmed length] - 1)] stringByTrimmingCharactersInSet:whitespace];
	}

	return trimmed;
}

@implementation ESWebKitMessageViewPreferences

- (NSString *)paneIdentifier
{
	return @"Messages";
}
- (NSString *)paneName{
	return AILocalizedString(@"Messages", "Title of the messages preferences");
}
- (NSImage *)paneIcon
{
	return [NSImage imageNamed:@"pref-messages"];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads
 * a nib for us. WebKitPreferencesView.xib is dead — and it must stay unloaded:
 * it still wires outlets this class no longer has (tabView_messageType, the
 * label fields, …), so loading it would raise NSUnknownKeyException rather than
 * fall back to the old interface. Removing it from the target needs project
 * file access this plugin's sources do not carry.
 */

#pragma mark View

/*!
 * @brief Build our view instead of loading a nib.
 *
 * Mirrors -[AIModularPane view] so the subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		AISettingsFormView	*form = [self buildSettingsForm];

		settingsForm = form;
		view = [form retain];

		[self viewDidLoad];
		[self localizePane];

		/* -viewDidLoad filled the style menu and selected the stored values; the
		 * pop up rows measure their buttons in this last layout pass.
		 */
		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Undo everything -view built.
 *
 * -closeView tears the preview's WebView down (see -viewWillClose) and releases
 * the form; it is idempotent, so a pane the plugin releases after the window
 * already closed does not tear anything down twice.
 */
- (void)dealloc
{
	[self closeView];
	[super dealloc];
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * The live preview is the heart of this pane and gets a card of its own: an
 * edge to edge row, so the rendered conversation *is* the card. Below it, the
 * cards follow the nib's blocks — the style, the text display, the background —
 * while the nib's two-tab view becomes a segmented control row: the rows below
 * never change with the chat type, only the values in them.
 *
 * Each control keeps the preference key and group its nib counterpart had.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:MESSAGES_PANE_INITIAL_WIDTH] autorelease];

	//What this pane is about, and the one caveat that spans all of it
	[form addInfoRow:AILocalizedString(@"Style changes take effect for new message windows.", nil)
		   withImage:[self paneIcon]];
	[form endCard];

	//Which of the two per-chat-type preference sets the rows below show
	segment_chatType = [self chatTypeSegmentedControl];
	[form addRowWithLabel:AILocalizedString(@"Settings for", "Label of the control choosing which kind of chat the message settings below apply to")
				  control:segment_chatType];

	checkBox_useRegularChatForGroup = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Use regular chat style settings", nil)
				  control:checkBox_useRegularChatForGroup
				   detail:AILocalizedString(@"Applies to group chats.", "Explanation that a setting only affects group chats")];

	//The live preview: the card is the rendered conversation
	[form addSectionHeader:AILocalizedString(@"Preview", "Section header above the live message style preview")];

	/* A plain container rather than the WebView itself: the message view is
	 * created later (-_configureChatPreview needs the styles loaded first) and
	 * has been replaced wholesale by style reloads in the past, so the row hosts
	 * a stable placeholder the WebView is dropped into, exactly as the nib did.
	 */
	view_previewLocation = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0,
																	 MESSAGES_PANE_INITIAL_WIDTH,
																	 MESSAGES_PREVIEW_HEIGHT)] autorelease];
	[view_previewLocation setAutoresizesSubviews:YES];
	[form addEdgeToEdgeRow:view_previewLocation];

	//Message style
	[form addSectionHeader:AIRowLabel(AILocalizedString(@"Message Style:", nil))];

	/* Pop up rows, not control rows: both menus are rebuilt at run time — the
	 * styles when Xtras change, the variants whenever the style does — and a pop
	 * up row re-measures its button at every layout.
	 */
	popUp_styles = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Style", "Label of the menu choosing the message style")
			  popUpButton:popUp_styles
		  accessoryButton:nil];

	popUp_variants = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Variant:", nil))
			  popUpButton:popUp_variants
		  accessoryButton:nil];

	checkBox_showUserIcons = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show user icons", nil)
				  control:checkBox_showUserIcons];

	checkBox_showHeader = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show header", nil)
				  control:checkBox_showHeader];

	checkBox_hideScrollbar = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Hide scrollbar", nil)
				  control:checkBox_hideScrollbar];

	//Text display
	[form addSectionHeader:AIRowLabel(AILocalizedString(@"Text Display:", nil))];

	/* The font field shows the choice, the buttons change it. The field gets the
	 * nib's fixed frame because a text field in a row of views keeps whatever
	 * frame it brought along.
	 */
	fontPreviewField_currentFont = [[[JVFontPreviewField alloc] initWithFrame:NSMakeRect(0.0, 0.0,
																						 FONT_PREVIEW_FIELD_WIDTH,
																						 FONT_PREVIEW_FIELD_HEIGHT)] autorelease];
	[fontPreviewField_currentFont setBezeled:NO];
	[fontPreviewField_currentFont setDrawsBackground:NO];
	[[fontPreviewField_currentFont cell] setLineBreakMode:NSLineBreakByTruncatingTail];
	[fontPreviewField_currentFont setShowFontFace:YES];
	[fontPreviewField_currentFont setShowPointSize:YES];
	//Its text is a font name, not a title, so VoiceOver needs to be told what it is
	[fontPreviewField_currentFont setAccessibilityLabel:AILocalizedString(@"Font", "Label of the row showing the current message display font")];
	//As in the nib: -fontPreviewField:didChangeToFont: saves the user's choice
	[fontPreviewField_currentFont setDelegate:(id<NSTextFieldDelegate>)self];

	/* The button opens the font panel on the field itself, exactly as the nib
	 * wired it: the field owns the panel session and hands the result to its
	 * delegate. NSControl holds its target weakly, and the field outlives the
	 * button — the form owns both.
	 */
	button_setFont = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Set Font…", nil)
													  target:fontPreviewField_currentFont
													  action:@selector(chooseFontWithFontPanel:)];
	button_defaultFont = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Default", nil)
														  target:self
														  action:@selector(resetDisplayFontToDefault:)];

	[form addRowWithLabel:AILocalizedString(@"Font", "Label of the row showing the current message display font")
				  control:[AISettingsFormView rowOfViews:[NSArray arrayWithObjects:
														  fontPreviewField_currentFont, button_setFont, button_defaultFont, nil]]];

	checkBox_showMessageFonts = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show received message fonts", nil)
				  control:checkBox_showMessageFonts];

	checkBox_showMessageColors = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show received message colors", nil)
				  control:checkBox_showMessageColors
				   detail:AILocalizedString(@"Message background colors are not supported by all styles", nil)];

	//Background
	[form addSectionHeader:AIRowLabel(AILocalizedString(@"Background:", nil))];

	checkBox_useCustomBackground = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Use custom background", nil)
				  control:checkBox_useCustomBackground];

	/* The image well keeps the nib's frame — an image view has no natural size —
	 * and stays clickable: clicking it opens the open panel, dragging an image
	 * in and pressing delete work as before (see the delegate methods below).
	 */
	imageView_backgroundImage = [[[AIImageViewWithImagePicker alloc] initWithFrame:NSMakeRect(0.0, 0.0,
																							  BACKGROUND_IMAGE_WELL_WIDTH,
																							  BACKGROUND_IMAGE_WELL_HEIGHT)] autorelease];
	[imageView_backgroundImage setDelegate:self];
	[imageView_backgroundImage setImageFrameStyle:NSImageFrameGrayBezel];
	[imageView_backgroundImage setImageScaling:NSImageScaleProportionallyDown];
	//As in the nib: the well is reached by clicking it, not by tabbing through the pane
	[imageView_backgroundImage setRefusesFirstResponder:YES];
	//We want to be able to obtain bigger images than the image picker will feed us
	[imageView_backgroundImage setUsePictureTaker:NO];
	//A well shows a picture and has no title of its own for VoiceOver to read
	[imageView_backgroundImage setAccessibilityLabel:AIRowLabel(AILocalizedString(@"Image:", nil))];

	/* This menu is fixed, so unlike the style menus it is built once, right
	 * here: the pop up sits inside a row of views, which keeps the size a
	 * control has when the row is created.
	 */
	popUp_backgroundImageType = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[popUp_backgroundImageType setMenu:[self _backgroundImageTypeMenu]];
	[popUp_backgroundImageType sizeToFit];

	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Image:", nil))
				  control:[AISettingsFormView rowOfViews:[NSArray arrayWithObjects:
														  imageView_backgroundImage, popUp_backgroundImageType, nil]]];

	colorWell_customBackgroundColor = [[[NSColorWell alloc] initWithFrame:NSMakeRect(0.0, 0.0,
																					 COLOR_WELL_WIDTH,
																					 COLOR_WELL_HEIGHT)] autorelease];
	[colorWell_customBackgroundColor setTarget:self];
	[colorWell_customBackgroundColor setAction:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Color:", nil))
				  control:colorWell_customBackgroundColor];

	return form;
}

/*!
 * @brief The switch between the regular chat and the group chat settings.
 *
 * The nib's tab view, minus the tabs: a two-segment control keeps both choices
 * visible without putting a frame around half the pane. The titles are the ones
 * the tabs carried, so every existing translation applies.
 */
- (NSSegmentedControl *)chatTypeSegmentedControl
{
	NSSegmentedControl	*segment = [[[NSSegmentedControl alloc] initWithFrame:NSZeroRect] autorelease];

	[segment setSegmentCount:2];
	[segment setSegmentStyle:NSSegmentStyleAutomatic];
	[segment setTrackingMode:NSSegmentSwitchTrackingSelectOne];
	[segment setLabel:AILocalizedString(@"Regular Chats", "Tab in the messages preferences: settings for one-on-one chats")
		   forSegment:AIWebkitRegularChat];
	[segment setLabel:AILocalizedString(@"Group Chat", "Tab in the messages preferences: settings for group chats")
		   forSegment:AIWebkitGroupChat];
	[segment setSelectedSegment:AIWebkitRegularChat];
	[segment setTarget:self];
	[segment setAction:@selector(changeChatType:)];
	[segment sizeToFit];

	return segment;
}

/*!
 * @brief A pop up menu was (re)built or reselected; let the form measure again.
 *
 * A pop up row sizes its button to the title it shows, so a rebuilt menu or a
 * new selection is a new button width. Coalesced into the next run loop pass:
 * one preference change can rebuild the variant menu and reselect two buttons
 * in a row, and a menu must not be re-measured while it is still tracking.
 */
- (void)menusChanged
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(layOutChangedMenus) object:nil];
	[self performSelector:@selector(layOutChangedMenus) withObject:nil afterDelay:0.0];
}

- (void)layOutChangedMenus
{
	[settingsForm noteContentSizeChanged];
}

/*!
 * @brief Configure the preference view
 */
- (void)viewDidLoad
{
	viewIsOpen = YES;
	previewListObjectsDict = nil;

	[popUp_styles setMenu:[self _stylesMenu]];

	//Configure the chat preview
	[self _configureChatPreview];

	selectedChatType = AIWebkitRegularChat;
	[segment_chatType setSelectedSegment:AIWebkitRegularChat];

	[self configurePreferencesForTab];
}

/*!
 * @brief Close the preference view
 */
- (void)viewWillClose
{
	//Hide the alpha component
	[[NSColorPanel sharedColorPanel] setShowsAlpha:NO];

	[[NSNotificationCenter defaultCenter] removeObserver:self];
	//A relayout scheduled by -menusChanged must not reach a closed pane
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[previewListObjectsDict release]; previewListObjectsDict = nil;

	[previewController messageViewIsClosing];
	[previewController release]; previewController = nil;
	[preview removeFromSuperview];
	[preview release]; preview = nil;
	//Matches the retain performed in -[ESWebKitMessageViewPreferences _configureChatPreview]
	[view_previewLocation release];

	/* The form owns every control; these are the pane's non-owning references to
	 * them and must not outlive the view.
	 */
	settingsForm = nil;
	segment_chatType = nil;
	checkBox_useRegularChatForGroup = nil;
	popUp_styles = nil;
	popUp_variants = nil;
	checkBox_showUserIcons = nil;
	checkBox_showHeader = nil;
	checkBox_hideScrollbar = nil;
	fontPreviewField_currentFont = nil;
	button_setFont = nil;
	button_defaultFont = nil;
	checkBox_showMessageFonts = nil;
	checkBox_showMessageColors = nil;
	checkBox_useCustomBackground = nil;
	imageView_backgroundImage = nil;
	popUp_backgroundImageType = nil;
	colorWell_customBackgroundColor = nil;
	view_previewLocation = nil;

	viewIsOpen = NO;
}

- (void)messageStyleXtrasDidChange
{
	if (viewIsOpen) {
		NSDictionary *prefDict = [adium.preferenceController preferencesForGroup:self.preferenceGroupForCurrentTab];

		[popUp_styles setMenu:[self _stylesMenu]];
		[popUp_styles selectItemWithRepresentedObject:[prefDict objectForKey:KEY_WEBKIT_STYLE]];

		[self menusChanged];
	}
}

//Preferences ----------------------------------------------------------------------------------------------------------
#pragma mark Preferences
- (AIWebkitStyleType)currentTab
{
	/* Read from the ivar rather than from the control: a stray action arriving
	 * after -viewWillClose still has to know which group it was writing to.
	 */
	return selectedChatType;
}

- (NSString *)preferenceGroupForCurrentTab
{
	NSString *prefGroup = nil;

	switch(self.currentTab) {
		case AIWebkitRegularChat:
			prefGroup = PREF_GROUP_WEBKIT_REGULAR_MESSAGE_DISPLAY;
			break;

		case AIWebkitGroupChat:
			prefGroup = PREF_GROUP_WEBKIT_GROUP_MESSAGE_DISPLAY;
			break;
	}

	return prefGroup;
}

/*!
 * @brief The user switched between regular and group chats.
 *
 * Only the values in the rows change, never the rows themselves — a card that
 * gained or lost a row here would jump under the pointer. Nothing is written:
 * which of the two sets is on screen is not a preference.
 */
- (IBAction)changeChatType:(id)sender
{
	selectedChatType = (([sender selectedSegment] == AIWebkitGroupChat) ? AIWebkitGroupChat : AIWebkitRegularChat);

	[self configurePreferencesForTab];

	//The other chat type's values may need wider or narrower pop up buttons
	[self menusChanged];
}

- (void)configurePreferencesForTab
{
	//Configure our controls to represent the global preferences

	NSDictionary *prefDict = [adium.preferenceController preferencesForGroup:self.preferenceGroupForCurrentTab];

	[checkBox_showUserIcons setState:([[previewController messageStyle] allowsUserIcons] ?
									  ([[prefDict objectForKey:KEY_WEBKIT_SHOW_USER_ICONS] boolValue] ?
									   NSControlStateValueOn : NSControlStateValueOff) :
									  NSControlStateValueOff)];
	[checkBox_showHeader setState:([[prefDict objectForKey:KEY_WEBKIT_SHOW_HEADER] boolValue] ?
								   NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_hideScrollbar setState:([[prefDict objectForKey:KEY_WEBKIT_HIDE_SCROLLBAR] boolValue] ?
									  NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_showMessageColors setState:([[previewController messageStyle] allowsColors] ?
										  ([[prefDict objectForKey:KEY_WEBKIT_SHOW_MESSAGE_COLORS] boolValue] ?
										   NSControlStateValueOn : NSControlStateValueOff) :
										  NSControlStateValueOff)];
	[checkBox_showMessageFonts setState:([[prefDict objectForKey:KEY_WEBKIT_SHOW_MESSAGE_FONTS] boolValue] ?
										 NSControlStateValueOn : NSControlStateValueOff)];

	/* Always the group chat group: the switch means "group chats follow the
	 * regular settings". In the nib it lived on the group chat tab and so always
	 * read from there; here it is visible on both, so the group is spelled out.
	 */
	[checkBox_useRegularChatForGroup setState:([[adium.preferenceController preferenceForKey:KEY_WEBKIT_USE_REGULAR_PREFERENCES
																					   group:PREF_GROUP_WEBKIT_GROUP_MESSAGE_DISPLAY] boolValue] ?
											   NSControlStateValueOn : NSControlStateValueOff)];

	//Allow the alpha component to be set for our background color
	[[NSColorPanel sharedColorPanel] setShowsAlpha:YES];

	[previewController setIsGroupChat:(self.currentTab == AIWebkitGroupChat)];

	// The preview controller will send us a preferences changed message also.
	[previewController preferencesChangedForGroup:self.preferenceGroupForCurrentTab
											  key:nil
										   object:nil
								   preferenceDict:[adium.preferenceController preferencesForGroup:self.preferenceGroupForCurrentTab]
										firstTime:NO];
}

/*!
 * @brief Update our preference view to reflect changed preferences
 */
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key object:(AIListObject *)object
					preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	if (!viewIsOpen) return;

	if ([group isEqualToString:self.preferenceGroupForCurrentTab]) {
		NSString	*style;
		NSString	*variant;

		//Ensure our style/variant menus are showing the correct selection
		style = [prefDict objectForKey:KEY_WEBKIT_STYLE];
		if (!style || ![popUp_styles selectItemWithRepresentedObject:style]) {
			style = [[plugin messageStyleBundleWithIdentifier:style] bundleIdentifier];
			[popUp_styles selectItemWithRepresentedObject:style];
		}

		//When the active style changes, rebuild our variant menu for the new style
		if (!key || [key isEqualToString:KEY_WEBKIT_STYLE]) {
			[popUp_variants setMenu:[self _variantsMenu]];
		}

		variant = [prefDict objectForKey:[plugin styleSpecificKey:@"Variant" forStyle:style]];
		if (!variant || ![popUp_variants selectItemWithRepresentedObject:variant]) {
			variant = [AIWebkitMessageViewStyle defaultVariantForBundle:[plugin messageStyleBundleWithIdentifier:style]];
			[popUp_variants selectItemWithRepresentedObject:variant];
		}

		[popUp_variants synchronizeTitleAndSelectedItem];

		//Configure our style-specific controls to represent the current style
		NSString	*fontFamily = [prefDict objectForKey:[plugin styleSpecificKey:@"FontFamily" forStyle:style]];
		if (!fontFamily) fontFamily = [[plugin messageStyleBundleWithIdentifier:style] objectForInfoDictionaryKey:KEY_WEBKIT_DEFAULT_FONT_FAMILY];
		if (!fontFamily) fontFamily = [[NSFont systemFontOfSize:0] familyName];

		NSNumber	*fontSize = [prefDict objectForKey:[plugin styleSpecificKey:@"FontSize" forStyle:style]];
		if (!fontSize) fontSize = [[plugin messageStyleBundleWithIdentifier:style] objectForInfoDictionaryKey:KEY_WEBKIT_DEFAULT_FONT_SIZE];
		if (!fontSize) fontSize = [NSNumber numberWithInteger:[[NSFont systemFontOfSize:0] pointSize]];

		NSFont	*defaultFont = [NSFont cachedFontWithName:fontFamily size:[fontSize integerValue]];
		[fontPreviewField_currentFont setFont:defaultFont];

		//Style-specific background prefs
		NSData	*backgroundImage = [adium.preferenceController preferenceForKey:[plugin styleSpecificKey:@"Background" forStyle:style]
																		   group:PREF_GROUP_WEBKIT_BACKGROUND_IMAGES];
		if (backgroundImage) {
			[imageView_backgroundImage setImage:[[[NSImage alloc] initWithData:backgroundImage] autorelease]];
		} else {
			[imageView_backgroundImage setImage:nil];
		}

		NSColor	*backgroundColor = [[prefDict objectForKey:[plugin styleSpecificKey:@"BackgroundColor" forStyle:style]] representedColor];
		[colorWell_customBackgroundColor setColor:(backgroundColor ? backgroundColor : [NSColor whiteColor])] ;

		[checkBox_useCustomBackground setState:([[prefDict objectForKey:[plugin styleSpecificKey:@"UseCustomBackground" forStyle:style]] boolValue] ?
												NSControlStateValueOn : NSControlStateValueOff)];
		[popUp_backgroundImageType selectItemWithTag:[[prefDict objectForKey:[plugin styleSpecificKey:@"BackgroundType" forStyle:style]] integerValue]];

		[self configureControlDimming];

		//A rebuilt variant menu and reselected buttons are new button widths
		[self menusChanged];
	}
}

/* Every control writes at once. The preference window only calls -closeView when
 * the whole window closes — switching to another pane merely takes our view out
 * of it — so anything kept back until then would be kept back for good.
 */

/*!
 * @brief Save changed preferences
 */
- (IBAction)changePreference:(id)sender
{
	if (viewIsOpen) {
		if (sender == checkBox_showUserIcons) {
			[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
												 forKey:KEY_WEBKIT_SHOW_USER_ICONS
												  group:self.preferenceGroupForCurrentTab];

		} else if (sender == checkBox_hideScrollbar) {
			[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
												 forKey:KEY_WEBKIT_HIDE_SCROLLBAR
												  group:self.preferenceGroupForCurrentTab];

		} else if (sender == checkBox_showHeader) {
			[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
												 forKey:KEY_WEBKIT_SHOW_HEADER
												  group:self.preferenceGroupForCurrentTab];

		} else if (sender == checkBox_showMessageColors) {
			[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
												 forKey:KEY_WEBKIT_SHOW_MESSAGE_COLORS
												  group:self.preferenceGroupForCurrentTab];

		} else if (sender == checkBox_showMessageFonts) {
			[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
												 forKey:KEY_WEBKIT_SHOW_MESSAGE_FONTS
												  group:self.preferenceGroupForCurrentTab];
		} else if (sender == checkBox_useCustomBackground) {
			[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
												 forKey:[plugin styleSpecificKey:@"UseCustomBackground"
																		forStyle:[[popUp_styles selectedItem] representedObject]]
												  group:self.preferenceGroupForCurrentTab];
		} else if (sender == checkBox_useRegularChatForGroup) {
			/* Dimmed unless the group chat settings are on screen, and always
			 * written to the group chat group — see -configurePreferencesForTab.
			 */
			[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
												 forKey:KEY_WEBKIT_USE_REGULAR_PREFERENCES
												  group:PREF_GROUP_WEBKIT_GROUP_MESSAGE_DISPLAY];

			[self configurePreferencesForTab];
		} else if (sender == colorWell_customBackgroundColor) {
			[adium.preferenceController setPreference:[[colorWell_customBackgroundColor color] stringRepresentation]
												 forKey:[plugin styleSpecificKey:@"BackgroundColor"
																		forStyle:[[popUp_styles selectedItem] representedObject]]
												  group:self.preferenceGroupForCurrentTab];

		} else if (sender == popUp_backgroundImageType) {
			[adium.preferenceController setPreference:[NSNumber numberWithInteger:[[popUp_backgroundImageType selectedItem] tag]]
												 forKey:[plugin styleSpecificKey:@"BackgroundType"
																		forStyle:[[popUp_styles selectedItem] representedObject]]
												  group:self.preferenceGroupForCurrentTab];

		} else if (sender == popUp_styles) {
			[adium.preferenceController setPreference:[[sender selectedItem] representedObject]
												 forKey:KEY_WEBKIT_STYLE
												  group:self.preferenceGroupForCurrentTab];

		} else if (sender == popUp_variants) {
			NSString *activeStyle = [adium.preferenceController preferenceForKey:KEY_WEBKIT_STYLE
																		   group:self.preferenceGroupForCurrentTab];

			[adium.preferenceController setPreference:[[sender selectedItem] representedObject]
												 forKey:[plugin styleSpecificKey:@"Variant" forStyle:activeStyle]
												  group:self.preferenceGroupForCurrentTab];
		}

		[self configureControlDimming];

		//A menu selection is a new button title and therefore a new button width
		if ([sender isKindOfClass:[NSPopUpButton class]]) [self menusChanged];
	}
}

- (void)configureControlDimming
{
	// Controls are enabled if we're the regular chat tab, or we're not using regular preferences.
	BOOL useRegularPreferences = [[adium.preferenceController preferenceForKey:KEY_WEBKIT_USE_REGULAR_PREFERENCES
																		 group:PREF_GROUP_WEBKIT_GROUP_MESSAGE_DISPLAY] boolValue];
	BOOL anyControlsEnabled = (self.currentTab == AIWebkitRegularChat || !useRegularPreferences);

	/* The nib only showed this checkbox on the group chat tab; here the row is
	 * always visible — rows cannot come and go without the card jumping — and is
	 * dimmed instead while the regular chat settings are on screen.
	 */
	[checkBox_useRegularChatForGroup setEnabled:(self.currentTab == AIWebkitGroupChat)];

	// General controls with no other qualifiers.
	[popUp_styles setEnabled:anyControlsEnabled];
	[fontPreviewField_currentFont setEnabled:anyControlsEnabled];
	[checkBox_showMessageFonts setEnabled:anyControlsEnabled];
	[button_setFont setEnabled:anyControlsEnabled];
	[button_defaultFont setEnabled:anyControlsEnabled];

	//Only enable if there are multiple variant choices
	[popUp_variants setEnabled:[popUp_variants numberOfItems] > 0 && anyControlsEnabled];

	//Disable the custom background controls if the style doesn't support them
	AIWebkitMessageViewStyle *messageStyle = [previewController messageStyle];
	BOOL	allowCustomBackground = [messageStyle allowsCustomBackground] && anyControlsEnabled;
	[checkBox_useCustomBackground setEnabled:allowCustomBackground];

	allowCustomBackground = allowCustomBackground && ([checkBox_useCustomBackground state] == NSControlStateValueOn);

	[colorWell_customBackgroundColor setEnabled:allowCustomBackground];
	[popUp_backgroundImageType setEnabled:allowCustomBackground];
	[imageView_backgroundImage setEnabled:allowCustomBackground];

	//Disable the header control if this style doesn't have a header or topic
	if (self.currentTab == AIWebkitGroupChat)
		[checkBox_showHeader setEnabled:[messageStyle hasTopic] && anyControlsEnabled];
	else
		[checkBox_showHeader setEnabled:[messageStyle hasHeader] || ([messageStyle hasTopic] && useRegularPreferences)];

	//Disable user icon toggling if the style doesn't support them
	[checkBox_showUserIcons setEnabled:[messageStyle allowsUserIcons] && anyControlsEnabled];

	[checkBox_showMessageColors setEnabled:[messageStyle allowsColors] && anyControlsEnabled];
}

/*!
 * @brief Save changes to the font field
 */
- (void)fontPreviewField:(JVFontPreviewField *)field didChangeToFont:(NSFont *)font
{
	[self _setDisplayFontFace:[font fontName] size:[NSNumber numberWithInteger:[font pointSize]]];
}

- (IBAction)resetDisplayFontToDefault:(id)sender
{
	[self _setDisplayFontFace:nil size:nil];
}

/*!
 * @brief Set the display font of the active style.
 *
 * @param face New font face, nil to remove custom font
 * @param size New font size, nil to remove custom size
 */
- (void)_setDisplayFontFace:(NSString *)face size:(NSNumber *)size
{
	NSString *activeStyle = [adium.preferenceController preferenceForKey:KEY_WEBKIT_STYLE
																	group:self.preferenceGroupForCurrentTab];

	[adium.preferenceController setPreference:face
										 forKey:[plugin styleSpecificKey:@"FontFamily" forStyle:activeStyle]
										  group:self.preferenceGroupForCurrentTab];
	[adium.preferenceController setPreference:size
										 forKey:[plugin styleSpecificKey:@"FontSize" forStyle:activeStyle]
										  group:self.preferenceGroupForCurrentTab];

}

/*!
 * @brief Save changes to the background image
 */
- (void)imageViewWithImagePicker:(AIImageViewWithImagePicker *)picker didChangeToImage:(NSImage *)image
{
	[self _setBackgroundImage:image];
}

/*!
 * @brief Remove the background image
 */
- (void)deleteInImageViewWithImagePicker:(AIImageViewWithImagePicker *)picker
{
	[self _setBackgroundImage:nil];
}

/*!
 * @brief Set the background image of the active style.
 *
 * @param image New background image, nil to remove background image
 */
- (void)_setBackgroundImage:(NSImage *)image
{
	NSString	*style = [[popUp_styles selectedItem] representedObject];

	/* Save the new image.  We store the images in a separate preference group since they may get big.
	 * This will let loading other groups not be affected by its presence.
	 */
	[adium.preferenceController setPreference:[image PNGRepresentation]
										 forKey:[plugin styleSpecificKey:@"Background" forStyle:style]
										  group:PREF_GROUP_WEBKIT_BACKGROUND_IMAGES];
}

/*!
 * @brief Builds and returns a menu of available styles
 */
- (NSMenu *)_stylesMenu
{
	NSMenu			*menu = [[NSMenu alloc] initWithTitle:@""];
	NSMutableArray	*menuItemArray = [NSMutableArray array];
	NSArray			*availableStyles = [[plugin availableMessageStyles] allValues];
	NSMenuItem		*menuItem;

	for (NSBundle *style in availableStyles) {
		menuItem = [[NSMenuItem alloc] initWithTitle:[style name]
																		target:nil
																		action:nil
																 keyEquivalent:@""];
		[menuItem setRepresentedObject:[style bundleIdentifier]];
		[menuItemArray addObject:menuItem];
		[menuItem release];
	}

	[menuItemArray sortUsingSelector:@selector(titleCompare:)];

	for (menuItem in menuItemArray) {
		[menu addItem:menuItem];
	}

	return [menu autorelease];
}

/*!
 * @brief Build & return a menu of variants for the passed style
 */
- (NSMenu *)_variantsMenu
{
	NSMenu			*menu = [[NSMenu alloc] initWithTitle:@""];

	//Add a menu item for each variant
	for (NSString *variant in previewController.messageStyle.availableVariants) {
		[menu addItemWithTitle:variant
						target:nil
						action:nil
				 keyEquivalent:@""
			 representedObject:variant];
	}

	return [menu autorelease];
}

/*!
 * @brief Build & return a menu of choices for background display
 */
- (NSMenu *)_backgroundImageTypeMenu
{
	NSMenu	*menu = [[NSMenu alloc] init];

	[self _addBackgroundImageTypeChoice:BackgroundNormal toMenu:menu withTitle:AILocalizedString(@"Normal","Background image display preference: The image will be displayed normally")];
	[self _addBackgroundImageTypeChoice:BackgroundCenter toMenu:menu withTitle:AILocalizedString(@"Centered","Background image display preference: The image will be centered in the window")];
	[self _addBackgroundImageTypeChoice:BackgroundTile toMenu:menu withTitle:AILocalizedString(@"Tiled","Background image display preference: The image will be tiled (repeated) in the window to fill available space")];
	[self _addBackgroundImageTypeChoice:BackgroundTileCenter toMenu:menu withTitle:AILocalizedString(@"Tiled (Centered)","Background image display preference: The image will be tiled and centered in the window")];
	[self _addBackgroundImageTypeChoice:BackgroundScale toMenu:menu withTitle:AILocalizedString(@"Scaled", "Background image display preference: The image will be increased or decreased in size to fit the window")];

	return [menu autorelease];
}
- (void)_addBackgroundImageTypeChoice:(NSInteger)tag toMenu:(NSMenu *)menu withTitle:(NSString *)title
{
	NSMenuItem	*menuItem = [[NSMenuItem alloc] initWithTitle:title
																				 action:nil
																		  keyEquivalent:@""];
	[menuItem setTag:tag];
	[menu addItem:menuItem];
	[menuItem release];
}


//Chat Preview ---------------------------------------------------------------------------------------------------------
#pragma mark Chat Preview
/*!
 * @brief Configure our chat preview
 */
- (void)_configureChatPreview
{
	NSDictionary	*previewDict;
	NSString		*previewFilePath;
	NSString		*previewPath;
	AIChat			*previewChat;

	//Create our fake chat and message controller for the live preview
	previewFilePath = [[NSBundle bundleForClass:[self class]] pathForResource:WEBKIT_PREVIEW_CONVERSATION_FILE ofType:@"plist"];
	previewDict = [[NSDictionary alloc] initWithContentsOfFile:previewFilePath];
	previewPath = [previewFilePath stringByDeletingLastPathComponent];

	NSDictionary *listObjects;
	previewChat = [self previewChatWithDictionary:previewDict fromPath:previewPath listObjects:&listObjects];
	previewController = [(AIWebKitPreviewMessageViewController *)[AIWebKitPreviewMessageViewController messageDisplayControllerForChat:previewChat
																					withPlugin:plugin] retain];

	//Enable live refreshing of our preview
	[previewController setShouldReflectPreferenceChanges:YES];
	[previewController setPreferencesChangedDelegate:self];

	//Add fake users and content to our chat
	[self _fillContentOfChat:previewChat withDictionary:previewDict fromPath:previewPath listObjects:listObjects];
	[previewDict release];

	//Place the preview chat in our view: fill the placeholder and track its size
	preview = [[previewController messageView] retain];
	@try {
		[preview setValue:[NSNumber numberWithBool:NO] forKey:@"fillsContainerOnAttach"];
	} @catch (NSException *exception) {}
	[preview setFrame:[view_previewLocation bounds]];
	[preview setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	if ([view_previewLocation respondsToSelector:@selector(setClipsToBounds:)])
		[view_previewLocation setClipsToBounds:YES];
	[view_previewLocation addSubview:preview];
	[view_previewLocation retain]; //matched in viewWillClose

	/* Three things the old view needed telling and this one does not. Dropping something onto the
	 * sample conversation did something on a WebView and does nothing on a WKWebView, which handles
	 * drags in its own process and drops them unless a page asks for them. Events are no longer
	 * forwarded past the view, so the responder chain in the settings works without being asked.
	 * And the preview still scrolls with its scrollbar out of sight, which is now one CSS rule in
	 * -[AIWebKitPreviewMessageViewController webViewIsReady] rather than a rule plus an AppKit
	 * scroller to restyle beside it.
	 */
}

- (AIChat *)previewChatWithDictionary:(NSDictionary *)previewDict fromPath:(NSString *)previewPath listObjects:(NSDictionary **)outListObjects
{
	AIPreviewChat *previewChat = [AIPreviewChat previewChat];
	[previewChat setDisplayName:AILocalizedString(@"Sample Conversation", "Title for the sample conversation")];

	//Process and create all participants
	*outListObjects = [self _addParticipants:[previewDict objectForKey:@"Participants"]
									  toChat:previewChat fromPath:previewPath];

	//Setup the chat, and its source/destination
	[self _applySettings:[previewDict objectForKey:@"Chat"]
				  toChat:previewChat withParticipants:*outListObjects];

	return previewChat;
}

/*!
 * @brief Fill the content of the specified chat using content archived in the dictionary
 */
- (void)_fillContentOfChat:(AIChat *)inChat withDictionary:(NSDictionary *)previewDict fromPath:(NSString *)previewPath listObjects:(NSDictionary *)listObjects
{
	//Add the archived chat content
	[self _addContent:[previewDict objectForKey:@"Preview Messages"]
			   toChat:inChat withParticipants:listObjects];
}

/*!
 * @brief Add participants
 */
- (NSMutableDictionary *)_addParticipants:(NSDictionary *)participants toChat:(AIChat *)inChat fromPath:(NSString *)previewPath
{
	NSMutableDictionary	*listObjectDict = [NSMutableDictionary dictionary];

	/* Somebody has to be on some service for the sample conversation to be drawn, and it never
	 * mattered which: nothing about the preview depends on it. It asked for AIM, which has been gone
	 * for a while, so every participant was built without a service at all and anything that later
	 * asked one of them which service they were on got nothing back. Jabber is asked for first
	 * because it is the one service Adium always has, and failing that whichever service there is. */
	AIService			*previewService = [adium.accountController firstServiceWithServiceID:@"Jabber"];

	if (!previewService)
		previewService = [[adium.accountController services] firstObject];

	for (NSDictionary *participant in participants) {
		NSString		*UID, *alias, *userIconName;
		AIListContact	*listContact;

		//Create object
		UID = [participant objectForKey:@"UID"];
		listContact = [[AIListContact alloc] initWithUID:UID service:previewService];

		//Display name
		if ((alias = [participant objectForKey:@"Display Name"])) {
			[[NSNotificationCenter defaultCenter] postNotificationName:Contact_ApplyDisplayName
													  object:listContact
													userInfo:[NSDictionary dictionaryWithObject:alias forKey:@"Alias"]];
		}

		//User icon
		if ((userIconName = [participant objectForKey:@"UserIcon Name"])) {
			[listContact setValue:[previewPath stringByAppendingPathComponent:userIconName]
								  forProperty:@"UserIconPath"
								  notify:YES];
		}

		[listObjectDict setObject:listContact forKey:UID];
		[listContact release];
	}

	return listObjectDict;
}

/*!
 * @brief Chat settings
 */
/*!
 * @brief The format every date in Preview.plist is written in
 *
 * They used to be read by asking for a date in natural language, which guesses, and guesses
 * differently depending on what language the machine is set to. The file is ours and its dates all
 * look like 2004-04-19 12:45:48 -0500, so it can simply be read.
 */
+ (NSDateFormatter *)previewDateFormatter
{
	static NSDateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSDateFormatter ai_fixedFormatterWithFormat:@"yyyy-MM-dd HH:mm:ss ZZZ" timeZone:nil] retain];
	});
	return formatter;
}

- (void)_applySettings:(NSDictionary *)chatDict toChat:(AIPreviewChat *)inChat withParticipants:(NSDictionary *)participants
{
	NSString			*dateOpened, *type, *name, *UID;

	//Date opened
	if ((dateOpened = [chatDict objectForKey:@"Date Opened"])) {
		[inChat setDateOpened:[[[self class] previewDateFormatter] dateFromString:dateOpened]];
	}

	//Source/Destination
	type = [chatDict objectForKey:@"Type"];
	if ([type isEqualToString:@"IM"]) {
		if ((UID = [chatDict objectForKey:@"Destination UID"])) {
			[inChat addParticipatingListObject:[participants objectForKey:UID] notify:YES];
		}
		if ((UID = [chatDict objectForKey:@"Source UID"])) {
			[inChat setAccount:(AIAccount *)[participants objectForKey:UID]];
		}
	} else {
		if ((name = [chatDict objectForKey:@"Name"])) {
			[inChat setName:name];
		}
	}

	//We don't want the interface controller to try to open this fake chat
	[inChat setIsOpen:YES];
}

/*!
 * @brief Chat content
 */
- (void)_addContent:(NSArray *)chatArray toChat:(AIChat *)inChat withParticipants:(NSDictionary *)participants
{
	NSDictionary		*messageDict;

	for (messageDict in chatArray) {
		AIContentObject		*content = nil;
		AIListObject		*source;
		NSString			*from, *msgType;
		NSAttributedString  *message;

		msgType = [messageDict objectForKey:@"Type"];
		from = [messageDict objectForKey:@"From"];

		source = (from ? [participants objectForKey:from] : nil);

		if ([msgType isEqualToString:CONTENT_MESSAGE_TYPE]) {
			//Create message content object
			AIListObject		*dest;
			NSString			*to;
			BOOL				outgoing;

			message = [AIHTMLDecoder decodeHTML:[messageDict objectForKey:@"Message"]];
			to = [messageDict objectForKey:@"To"];
			outgoing = [[messageDict objectForKey:@"Outgoing"] boolValue];

			//The other person is always the one we're chatting with right now
			dest = [participants objectForKey:to];
			content = [AIPreviewContentMessage messageInChat:inChat
												  withSource:source
												 destination:dest
														date:[[[self class] previewDateFormatter] dateFromString:[messageDict objectForKey:@"Date"]]
													 message:message
												   autoreply:[[messageDict objectForKey:@"Autoreply"] boolValue]];

			//AIContentMessage won't know whether the message is outgoing unless we tell it since neither our source
			//nor our destination are AIAccount objects.
			[(AIPreviewContentMessage *)content setIsOutgoing:outgoing];

		} else if ([msgType isEqualToString:CONTENT_STATUS_TYPE]) {
			//Create status content object
			NSString			*statusMessageType;

			message = [AIHTMLDecoder decodeHTML:[messageDict objectForKey:@"Message"]];
			statusMessageType = [messageDict objectForKey:@"Status Message Type"];

			//Create our content object
			content = [AIContentEvent eventInChat:inChat
									   withSource:source
									  destination:nil
											 date:[[[self class] previewDateFormatter] dateFromString:[messageDict objectForKey:@"Date"]]
										  message:message
										 withType:statusMessageType];
		}

		if (content) {
			[content setTrackContent:NO];
			[content setPostProcessContent:NO];
			[content setDisplayContentImmediately:NO];

			[adium.contentController displayContentObject:content
										usingContentFilters:YES
												immediately:YES];
		}
	}

	//We finished adding untracked content
	[[NSNotificationCenter defaultCenter] postNotificationName:Content_ChatDidFinishAddingUntrackedContent
											  object:inChat];
}

@end
