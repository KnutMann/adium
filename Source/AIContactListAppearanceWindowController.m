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

#import "AIContactListAppearanceWindowController.h"
#import "AISettingsFormView.h"

#import <Adium/AIAbstractListController.h>
#import <Adium/AISharedAdium.h>
#import <Adium/AIContactListPreviewView.h>
#import <Adium/AIDockControllerProtocol.h>
#import <Adium/AIListOutlineView.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <AIUtilities/AIColorAdditions.h>
#import <AIUtilities/AIStringUtilities.h>
#import <AIUtilities/AIFontAdditions.h>
#import <AIUtilities/AITableViewAdditions.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

/*!
 * @brief A label written for a nib, reused as a row label: without its colon
 *
 * Keeps every existing translation usable while matching the System Settings
 * look, where row labels carry no colon. Same helper as the appearance pane's.
 */
static NSString *AIRowLabel(NSString *label)
{
	NSCharacterSet	*whitespace = [NSCharacterSet whitespaceCharacterSet];
	NSString		*trimmed = [label stringByTrimmingCharactersInSet:whitespace];

	while ([trimmed hasSuffix:@":"]) {
		trimmed = [[trimmed substringToIndex:([trimmed length] - 1)] stringByTrimmingCharactersInSet:whitespace];
	}

	return trimmed;
}

#define PREVIEW_WIDTH		280.0
#define FORM_WIDTH			430.0
#define WINDOW_HEIGHT		560.0
#define OUTER_MARGIN		16.0
#define BUTTON_BAR_HEIGHT	52.0

/*!
 * @brief What one control writes
 */
typedef enum {
	AIBindingBool = 0,
	AIBindingInteger,
	AIBindingFloat,
	AIBindingColour,
	AIBindingFont,
	AIBindingPath
} AIBindingKind;

@interface AIBinding : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *group;
@property (nonatomic) AIBindingKind kind;
@end

@implementation AIBinding
+ (AIBinding *)bindingWithKey:(NSString *)key group:(NSString *)group kind:(AIBindingKind)kind
{
	AIBinding *binding = [[AIBinding alloc] init];
	binding.key = key;
	binding.group = group;
	binding.kind = kind;
	return binding;
}
@end

/*!
 * @brief One line of the state colour table
 */
@interface AIStateColourRow : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *enabledKey;
@property (nonatomic, copy) NSString *textColourKey;
@property (nonatomic, copy) NSString *areaColourKey;
@end

@implementation AIStateColourRow
@end

@interface AIContactListAppearanceWindowController () <NSTableViewDelegate, NSTableViewDataSource, NSFontChanging>
@end

/*!
 * @brief Where an open editor lives
 *
 * -showOnWindow: gives up the caller's reference; without something else
 * holding on, the editor would die as its sheet appeared.
 */
static NSMutableSet *openAppearanceEditors = nil;

@implementation AIContactListAppearanceWindowController {
	NSString						*layoutName;
	NSString						*themeName;
	AIContactListAppearanceSection	 initialSection;
	__weak id						 target;

	//What the preferences looked like when the editor opened, so Cancel can put them back
	NSDictionary					*savedLayout;
	NSDictionary					*savedTheme;
	NSNumber						*savedWindowStyle;

	AIContactListPreviewView		*previewView;
	AISettingsFormView				*form;
	NSScrollView					*formScrollView;
	NSTableView						*stateColourTable;
	NSArray							*stateColourRows;

	NSMapTable						*bindings;
	NSMutableDictionary				*sectionAnchors;
	NSString						*activeFontKey;
	BOOL							 rebuilding;
}

#pragma mark Opening and closing

- (instancetype)initWithLayoutNamed:(NSString *)inLayoutName
						 themeNamed:(NSString *)inThemeName
							section:(AIContactListAppearanceSection)inSection
					notifyingTarget:(id)inTarget
{
	NSRect contentRect = NSMakeRect(0.0, 0.0,
									PREVIEW_WIDTH + FORM_WIDTH + (OUTER_MARGIN * 3.0),
									WINDOW_HEIGHT);
	NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
												  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskResizable)
													backing:NSBackingStoreBuffered
													  defer:NO];
	window.title = AILocalizedString(@"Contact List Appearance", "Title of the window in which the contact list's layout and colours are set");
	window.minSize = NSMakeSize(contentRect.size.width, 420.0);

	if ((self = [super initWithWindow:window])) {
		layoutName = inLayoutName;
		themeName = inThemeName;
		initialSection = inSection;
		target = inTarget;

		bindings = [NSMapTable strongToStrongObjectsMapTable];
		sectionAnchors = [NSMutableDictionary dictionary];
		stateColourRows = [self buildStateColourRows];

		savedLayout = [[adium.preferenceController preferencesForGroup:PREF_GROUP_LIST_LAYOUT] copy];
		savedTheme = [[adium.preferenceController preferencesForGroup:PREF_GROUP_LIST_THEME] copy];
		savedWindowStyle = [adium.preferenceController preferenceForKey:KEY_LIST_LAYOUT_WINDOW_STYLE
																  group:PREF_GROUP_APPEARANCE];

		[self buildWindowContents];
		[self rebuildForm];
		[self scrollToSection:initialSection];
	}

	return self;
}

- (void)showOnWindow:(NSWindow *)parentWindow
{
	if (!openAppearanceEditors) openAppearanceEditors = [[NSMutableSet alloc] init];
	[openAppearanceEditors addObject:self];

	/* Alpha in the colour pickers: several of these colours are meant to be
	 * seen through. */
	[[NSColorPanel sharedColorPanel] setShowsAlpha:YES];

	if (parentWindow) {
		[parentWindow beginSheet:self.window completionHandler:^(NSModalResponse returnCode) {
			[self editorDidEnd];
		}];
	} else {
		[self showWindow:nil];
	}

	/* Only now does the form know how wide it is, and only then can a section
	 * be scrolled to. */
	[self.window layoutIfNeeded];
	[self scrollToSection:initialSection];
}

- (void)editorDidEnd
{
	[self.window orderOut:nil];
	[[NSColorPanel sharedColorPanel] close];
	[[NSColorPanel sharedColorPanel] setShowsAlpha:NO];

	/* Out of the set, but not before this turn of the run loop ends: the exit is
	 * reached from inside AppKit's own close, which goes on addressing this
	 * object afterwards. */
	CFAutorelease(CFBridgingRetain(self));
	[openAppearanceEditors removeObject:self];
}

- (IBAction)cancel:(id)sender
{
	//Put back exactly what was there when the editor opened
	[adium.preferenceController setPreferences:savedLayout inGroup:PREF_GROUP_LIST_LAYOUT];
	[adium.preferenceController setPreferences:savedTheme inGroup:PREF_GROUP_LIST_THEME];
	if (savedWindowStyle) {
		[adium.preferenceController setPreference:savedWindowStyle
										   forKey:KEY_LIST_LAYOUT_WINDOW_STYLE
											group:PREF_GROUP_APPEARANCE];
	}

	[target listLayoutEditorWillCloseWithChanges:NO forLayoutNamed:layoutName];
	[target listThemeEditorWillCloseWithChanges:NO forThemeNamed:themeName];
	[self closeEditor];
}

- (IBAction)save:(id)sender
{
	[target listLayoutEditorWillCloseWithChanges:YES forLayoutNamed:layoutName];
	[target listThemeEditorWillCloseWithChanges:YES forThemeNamed:themeName];
	[self closeEditor];
}

- (void)closeEditor
{
	if (self.window.sheetParent) {
		[self.window.sheetParent endSheet:self.window];
	} else {
		[self.window close];
		[self editorDidEnd];
	}
}

#pragma mark The window

- (void)buildWindowContents
{
	NSView *content = self.window.contentView;

	//The preview, on the left, in a box of its own
	NSBox *previewBox = [[NSBox alloc] initWithFrame:NSZeroRect];
	previewBox.title = AILocalizedString(@"Preview", "Title above the small sample contact list in the appearance editor");
	previewBox.translatesAutoresizingMaskIntoConstraints = NO;
	[content addSubview:previewBox];

	previewView = [[AIContactListPreviewView alloc] initWithFrame:NSMakeRect(0, 0, PREVIEW_WIDTH, 300)];
	previewView.translatesAutoresizingMaskIntoConstraints = NO;
	[previewBox.contentView addSubview:previewView];

	//The settings, on the right, in a scroll view
	form = [[AISettingsFormView alloc] initWithWidth:FORM_WIDTH];
	formScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	formScrollView.translatesAutoresizingMaskIntoConstraints = NO;
	formScrollView.hasVerticalScroller = YES;
	formScrollView.drawsBackground = NO;
	formScrollView.borderType = NSNoBorder;
	formScrollView.documentView = form;
	[content addSubview:formScrollView];

	NSButton *cancelButton = [NSButton buttonWithTitle:AILocalizedString(@"Cancel", nil)
												target:self action:@selector(cancel:)];
	cancelButton.keyEquivalent = @"\033";
	cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
	[content addSubview:cancelButton];

	NSButton *saveButton = [NSButton buttonWithTitle:AILocalizedString(@"Save", "Button that keeps the changes made in the contact list appearance editor")
											  target:self action:@selector(save:)];
	saveButton.keyEquivalent = @"\r";
	saveButton.translatesAutoresizingMaskIntoConstraints = NO;
	[content addSubview:saveButton];

	[NSLayoutConstraint activateConstraints:@[
		[previewBox.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:OUTER_MARGIN],
		[previewBox.topAnchor constraintEqualToAnchor:content.topAnchor constant:OUTER_MARGIN],
		[previewBox.widthAnchor constraintEqualToConstant:PREVIEW_WIDTH],
		[previewBox.bottomAnchor constraintEqualToAnchor:cancelButton.topAnchor constant:-OUTER_MARGIN],

		[previewView.leadingAnchor constraintEqualToAnchor:previewBox.contentView.leadingAnchor],
		[previewView.trailingAnchor constraintEqualToAnchor:previewBox.contentView.trailingAnchor],
		[previewView.topAnchor constraintEqualToAnchor:previewBox.contentView.topAnchor],
		[previewView.bottomAnchor constraintEqualToAnchor:previewBox.contentView.bottomAnchor],

		[formScrollView.leadingAnchor constraintEqualToAnchor:previewBox.trailingAnchor constant:OUTER_MARGIN],
		[formScrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-OUTER_MARGIN],
		[formScrollView.topAnchor constraintEqualToAnchor:content.topAnchor constant:OUTER_MARGIN],
		[formScrollView.bottomAnchor constraintEqualToAnchor:cancelButton.topAnchor constant:-OUTER_MARGIN],

		[saveButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-OUTER_MARGIN],
		[saveButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-OUTER_MARGIN],
		[cancelButton.trailingAnchor constraintEqualToAnchor:saveButton.leadingAnchor constant:-12.0],
		[cancelButton.bottomAnchor constraintEqualToAnchor:saveButton.bottomAnchor],
	]];
}

#pragma mark Building the form

- (AIContactListWindowStyle)windowStyle
{
	return [[adium.preferenceController preferenceForKey:KEY_LIST_LAYOUT_WINDOW_STYLE
												   group:PREF_GROUP_APPEARANCE] intValue];
}

- (void)rebuildForm
{
	rebuilding = YES;

	[bindings removeAllObjects];
	[sectionAnchors removeAllObjects];
	[form removeAllSections];

	AIContactListWindowStyle style = [self windowStyle];
	BOOL bubbles = (style == AIContactListWindowStyleContactBubbles ||
					style == AIContactListWindowStyleContactBubbles_Fitted);
	BOOL mockie = (style == AIContactListWindowStyleGroupBubbles);

	[self addShapeSection:style bubbles:bubbles];
	[self addContactRowSection:style];
	[self addGroupRowSection:mockie];
	[self addColourSection:bubbles || mockie];

	[form layoutForWidth:FORM_WIDTH];
	[form noteContentSizeChanged];

	rebuilding = NO;
	[self refreshControls];
}

- (void)addShapeSection:(AIContactListWindowStyle)style bubbles:(BOOL)bubbles
{
	[form addSectionHeader:AILocalizedString(@"Shape", "Section of the contact list appearance editor holding the window style")];

	NSPopUpButton *stylePopUp = [self popUpWithTitlesAndTags:@[
		AILocalizedString(@"Regular window", nil), @(AIContactListWindowStyleStandard),
		AILocalizedString(@"Borderless window", nil), @(AIContactListWindowStyleBorderless),
		AILocalizedString(@"Group bubbles", nil), @(AIContactListWindowStyleGroupBubbles),
		AILocalizedString(@"Contact bubbles", nil), @(AIContactListWindowStyleContactBubbles),
		AILocalizedString(@"Contact bubbles (to fit)", nil), @(AIContactListWindowStyleContactBubbles_Fitted)]
														 key:KEY_LIST_LAYOUT_WINDOW_STYLE
													   group:PREF_GROUP_APPEARANCE];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Window Style:", nil))
			  popUpButton:stylePopUp
		  accessoryButton:nil];
	sectionAnchors[@(AIContactListAppearanceSectionShape)] = stylePopUp;

	if (!bubbles) return;

	[form addRowWithLabel:AILocalizedString(@"Outline the bubbles", nil)
				  control:[self switchForKey:KEY_LIST_LAYOUT_OUTLINE_BUBBLE group:PREF_GROUP_LIST_LAYOUT]];

	NSSlider *outlineWidth = [self sliderFrom:1.0 to:10.0
										  key:KEY_LIST_LAYOUT_OUTLINE_BUBBLE_WIDTH
										group:PREF_GROUP_LIST_LAYOUT
										 kind:AIBindingInteger];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Outline Width:", nil))
				   slider:outlineWidth
			   valueLabel:[self valueLabelFor:outlineWidth suffix:AILocalizedString(@"px", "Abbreviation for pixels, after a number")]];

	[form addRowWithLabel:AILocalizedString(@"Fill the contact bubbles with a gradient", nil)
				  control:[self switchForKey:KEY_LIST_LAYOUT_CONTACT_BUBBLE_GRADIENT group:PREF_GROUP_LIST_LAYOUT]
				   detail:AILocalizedString(@"Noticeably slower to draw", nil)];

	[form addRowWithLabel:AILocalizedString(@"Hide the group bubbles", nil)
				  control:[self switchForKey:KEY_LIST_LAYOUT_GROUP_HIDE_BUBBLE group:PREF_GROUP_LIST_LAYOUT]];
}

- (void)addContactRowSection:(AIContactListWindowStyle)style
{
	[form addSectionHeader:AILocalizedString(@"Contact Row", "Section of the contact list appearance editor holding everything about a contact's row")];

	NSButton *contactFont = [self fontButtonForKey:KEY_LIST_LAYOUT_CONTACT_FONT];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Name Font:", nil)) stretchingControl:contactFont];
	sectionAnchors[@(AIContactListAppearanceSectionContactRow)] = contactFont;

	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Status Font:", nil))
		stretchingControl:[self fontButtonForKey:KEY_LIST_LAYOUT_STATUS_FONT]];

	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Alignment:", nil))
			  popUpButton:[self alignmentPopUpForKey:KEY_LIST_LAYOUT_ALIGNMENT]
		  accessoryButton:nil];

	//What is shown beside the name
	[form addRowWithLabel:AILocalizedString(@"Show the user's picture", nil)
				  control:[self switchForKey:KEY_LIST_LAYOUT_SHOW_ICON group:PREF_GROUP_LIST_LAYOUT]];

	NSSlider *iconSize = [self sliderFrom:12.0 to:64.0
									  key:KEY_LIST_LAYOUT_USER_ICON_SIZE
									group:PREF_GROUP_LIST_LAYOUT
									 kind:AIBindingInteger];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Picture Size:", nil))
				   slider:iconSize
			   valueLabel:[self valueLabelFor:iconSize suffix:AILocalizedString(@"px", "Abbreviation for pixels, after a number")]];

	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Picture Position:", nil))
			  popUpButton:[self positionPopUpForKey:KEY_LIST_LAYOUT_USER_ICON_POSITION withBadges:NO]
		  accessoryButton:nil];

	[form addRowWithLabel:AILocalizedString(@"Show the status icon", nil)
				  control:[self switchForKey:KEY_LIST_LAYOUT_SHOW_STATUS_ICONS group:PREF_GROUP_LIST_LAYOUT]];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Status Icon Position:", nil))
			  popUpButton:[self positionPopUpForKey:KEY_LIST_LAYOUT_STATUS_ICON_POSITION withBadges:YES]
		  accessoryButton:nil];

	[form addRowWithLabel:AILocalizedString(@"Show the service icon", nil)
				  control:[self switchForKey:KEY_LIST_LAYOUT_SHOW_SERVICE_ICONS group:PREF_GROUP_LIST_LAYOUT]];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Service Icon Position:", nil))
			  popUpButton:[self positionPopUpForKey:KEY_LIST_LAYOUT_SERVICE_ICON_POSITION withBadges:YES]
		  accessoryButton:nil];

	if (style != AIContactListWindowStyleContactBubbles_Fitted) {
		[form addRowWithLabel:AILocalizedString(@"Show a second line", nil)
					  control:[self switchForKey:KEY_LIST_LAYOUT_SHOW_EXT_STATUS group:PREF_GROUP_LIST_LAYOUT]];

		[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Second Line Shows:", nil))
				  popUpButton:[self popUpWithTitlesAndTags:@[
									AILocalizedString(@"Status message", nil), @(STATUS_ONLY),
									AILocalizedString(@"Idle time", nil), @(IDLE_ONLY),
									AILocalizedString(@"Idle time and status message", nil), @(IDLE_AND_STATUS)]
													   key:KEY_LIST_LAYOUT_EXTENDED_STATUS_STYLE
													 group:PREF_GROUP_LIST_LAYOUT]
			  accessoryButton:nil];

		[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Second Line Sits:", nil))
				  popUpButton:[self popUpWithTitlesAndTags:@[
									AILocalizedString(@"Below the name", nil), @(EXTENDED_STATUS_POSITION_BELOW_NAME),
									AILocalizedString(@"Beside the name", nil), @(EXTENDED_STATUS_POSITION_BESIDE_NAME),
									AILocalizedString(@"Idle time beside, status message below", nil), @(EXTENDED_STATUS_POSITION_BOTH)]
													   key:KEY_LIST_LAYOUT_EXTENDED_STATUS_POSITION
													 group:PREF_GROUP_LIST_LAYOUT]
			  accessoryButton:nil];
	}

	//Room around a row
	NSSlider *spacing = [self sliderFrom:0.0 to:20.0
									 key:KEY_LIST_LAYOUT_CONTACT_SPACING
								   group:PREF_GROUP_LIST_LAYOUT
									kind:AIBindingInteger];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Row Spacing:", nil))
				   slider:spacing
			   valueLabel:[self valueLabelFor:spacing suffix:AILocalizedString(@"px", "Abbreviation for pixels, after a number")]];

	NSSlider *leftIndent = [self sliderFrom:0.0 to:40.0
										key:KEY_LIST_LAYOUT_CONTACT_LEFT_INDENT
									  group:PREF_GROUP_LIST_LAYOUT
									   kind:AIBindingInteger];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Left Margin:", nil))
				   slider:leftIndent
			   valueLabel:[self valueLabelFor:leftIndent suffix:AILocalizedString(@"px", "Abbreviation for pixels, after a number")]];

	NSSlider *rightIndent = [self sliderFrom:0.0 to:40.0
										 key:KEY_LIST_LAYOUT_CONTACT_RIGHT_INDENT
									   group:PREF_GROUP_LIST_LAYOUT
										kind:AIBindingInteger];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Right Margin:", nil))
				   slider:rightIndent
			   valueLabel:[self valueLabelFor:rightIndent suffix:AILocalizedString(@"px", "Abbreviation for pixels, after a number")]];
}

- (void)addGroupRowSection:(BOOL)mockie
{
	[form addSectionHeader:AILocalizedString(@"Group Row", "Section of the contact list appearance editor holding everything about a group's row")];

	NSButton *groupFont = [self fontButtonForKey:KEY_LIST_LAYOUT_GROUP_FONT];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Group Font:", nil)) stretchingControl:groupFont];
	sectionAnchors[@(AIContactListAppearanceSectionGroupRow)] = groupFont;

	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Alignment:", nil))
			  popUpButton:[self alignmentPopUpForKey:KEY_LIST_LAYOUT_GROUP_ALIGNMENT]
		  accessoryButton:nil];

	if (mockie) {
		NSSlider *topSpacing = [self sliderFrom:0.0 to:20.0
											key:KEY_LIST_LAYOUT_GROUP_TOP_SPACING
										  group:PREF_GROUP_LIST_LAYOUT
										   kind:AIBindingInteger];
		[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Space Above a Group:", nil))
					   slider:topSpacing
				   valueLabel:[self valueLabelFor:topSpacing suffix:AILocalizedString(@"px", "Abbreviation for pixels, after a number")]];
	}

	[form addRowWithLabel:AILocalizedString(@"Give groups a background", nil)
				  control:[self switchForKey:KEY_LIST_THEME_GROUP_GRADIENT group:PREF_GROUP_LIST_THEME]];

	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Background:", nil))
				  control:[AISettingsFormView rowOfViews:@[
							   [self colourWellForKey:KEY_LIST_THEME_GROUP_BACKGROUND group:PREF_GROUP_LIST_THEME],
							   [self captionWithText:AILocalizedString(@"to", "Between the two colours of a gradient")],
							   [self colourWellForKey:KEY_LIST_THEME_GROUP_BACKGROUND_GRADIENT group:PREF_GROUP_LIST_THEME]]]];

	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Text:", nil))
				  control:[self colourWellForKey:KEY_LIST_THEME_GROUP_TEXT_COLOR group:PREF_GROUP_LIST_THEME]];

	[form addRowWithLabel:AILocalizedString(@"Give the group name a shadow", nil)
				  control:[self switchForKey:KEY_LIST_THEME_GROUP_SHADOW group:PREF_GROUP_LIST_THEME]];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Shadow:", nil))
				  control:[self colourWellForKey:KEY_LIST_THEME_GROUP_SHADOW_COLOR group:PREF_GROUP_LIST_THEME]];
}

- (void)addColourSection:(BOOL)shaped
{
	[form addSectionHeader:AILocalizedString(@"Colours", "Section of the contact list appearance editor holding the window and state colours")];

	NSColorWell *background = [self colourWellForKey:KEY_LIST_THEME_BACKGROUND_COLOR group:PREF_GROUP_LIST_THEME];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Window Background:", nil)) control:background];
	sectionAnchors[@(AIContactListAppearanceSectionColours)] = background;

	if (!shaped) {
		[form addRowWithLabel:AILocalizedString(@"Show a background picture", nil)
					  control:[self switchForKey:KEY_LIST_THEME_BACKGROUND_IMAGE_ENABLED group:PREF_GROUP_LIST_THEME]];

		[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Picture:", nil))
					  control:[AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Choose…", nil)
															   target:self
															   action:@selector(chooseBackgroundImage:)]];

		[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Picture Style:", nil))
				  popUpButton:[self popUpWithTitlesAndTags:@[
									AILocalizedString(@"Normal", nil), @(AINormalBackground),
									AILocalizedString(@"Stretched", nil), @(AIFillProportionatelyBackground),
									AILocalizedString(@"Tiled", nil), @(AITileBackground)]
													   key:KEY_LIST_THEME_BACKGROUND_IMAGE_STYLE
													 group:PREF_GROUP_LIST_THEME]
			  accessoryButton:nil];

		NSSlider *fade = [self sliderFrom:0.0 to:100.0
									  key:KEY_LIST_THEME_BACKGROUND_FADE
									group:PREF_GROUP_LIST_THEME
									 kind:AIBindingFloat];
		[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Picture Strength:", nil))
					   slider:fade
				   valueLabel:[self valueLabelFor:fade suffix:@"%"]];

		[form addRowWithLabel:AILocalizedString(@"Colour every other row", nil)
					  control:[self switchForKey:KEY_LIST_THEME_GRID_ENABLED group:PREF_GROUP_LIST_THEME]];
		[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Every Other Row:", nil))
					  control:[self colourWellForKey:KEY_LIST_THEME_GRID_COLOR group:PREF_GROUP_LIST_THEME]];
	}

	[form addRowWithLabel:AILocalizedString(@"Use a colour of your own for the selected row", nil)
				  control:[self switchForKey:KEY_LIST_THEME_HIGHLIGHT_ENABLED group:PREF_GROUP_LIST_THEME]];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Selected Row:", nil))
				  control:[self colourWellForKey:KEY_LIST_THEME_HIGHLIGHT_COLOR group:PREF_GROUP_LIST_THEME]];

	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Second Line:", "Colour of the smaller line under a contact's name"))
				  control:[self colourWellForKey:KEY_LIST_THEME_CONTACT_STATUS_COLOR group:PREF_GROUP_LIST_THEME]];

	//The state colours
	[form addSectionHeader:AILocalizedString(@"Colours by State", "Section of the contact list appearance editor holding one colour per contact state")];

	[form addRowWithLabel:AILocalizedString(@"Colour the row, not the name", nil)
				  control:[self switchForKey:KEY_LIST_THEME_BACKGROUND_AS_STATUS group:PREF_GROUP_LIST_THEME]
				   detail:AILocalizedString(@"Applies to the states a contact is in", nil)];
	[form addRowWithLabel:AILocalizedString(@"Colour the row for events as well", nil)
				  control:[self switchForKey:KEY_LIST_THEME_BACKGROUND_AS_EVENTS group:PREF_GROUP_LIST_THEME]];
	[form addRowWithLabel:AILocalizedString(@"Dim the pictures of contacts who are offline", nil)
				  control:[self switchForKey:KEY_LIST_THEME_FADE_OFFLINE_IMAGES group:PREF_GROUP_LIST_THEME]];

	[form addFullWidthRow:[self buildStateColourTable] stretch:YES];
}

#pragma mark The state colour table

- (NSArray *)buildStateColourRows
{
	NSArray *spec = @[
		@[AILocalizedString(@"Online", nil), KEY_ONLINE_ENABLED, KEY_ONLINE_COLOR, KEY_LABEL_ONLINE_COLOR],
		@[AILocalizedString(@"Offline", nil), KEY_OFFLINE_ENABLED, KEY_OFFLINE_COLOR, KEY_LABEL_OFFLINE_COLOR],
		@[AILocalizedString(@"Away", nil), KEY_AWAY_ENABLED, KEY_AWAY_COLOR, KEY_LABEL_AWAY_COLOR],
		@[AILocalizedString(@"Idle", nil), KEY_IDLE_ENABLED, KEY_IDLE_COLOR, KEY_LABEL_IDLE_COLOR],
		@[AILocalizedString(@"Idle and away", nil), KEY_IDLE_AWAY_ENABLED, KEY_IDLE_AWAY_COLOR, KEY_LABEL_IDLE_AWAY_COLOR],
		@[AILocalizedString(@"Mobile", nil), KEY_MOBILE_ENABLED, KEY_MOBILE_COLOR, KEY_LABEL_MOBILE_COLOR],
		@[AILocalizedString(@"Just came online", nil), KEY_SIGNED_ON_ENABLED, KEY_SIGNED_ON_COLOR, KEY_LABEL_SIGNED_ON_COLOR],
		@[AILocalizedString(@"Just went offline", nil), KEY_SIGNED_OFF_ENABLED, KEY_SIGNED_OFF_COLOR, KEY_LABEL_SIGNED_OFF_COLOR],
		@[AILocalizedString(@"Typing", nil), KEY_TYPING_ENABLED, KEY_TYPING_COLOR, KEY_LABEL_TYPING_COLOR],
		@[AILocalizedString(@"Unread message", nil), KEY_UNVIEWED_ENABLED, KEY_UNVIEWED_COLOR, KEY_LABEL_UNVIEWED_COLOR],
	];

	NSMutableArray *rows = [NSMutableArray array];
	for (NSArray *entry in spec) {
		AIStateColourRow *row = [[AIStateColourRow alloc] init];
		row.label = entry[0];
		row.enabledKey = entry[1];
		row.textColourKey = entry[2];
		row.areaColourKey = entry[3];
		[rows addObject:row];
	}
	return rows;
}

- (NSView *)buildStateColourTable
{
	stateColourTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, FORM_WIDTH - 100.0, 240.0)];
	stateColourTable.rowHeight = 24.0;
	stateColourTable.allowsEmptySelection = YES;
	stateColourTable.headerView = [[NSTableHeaderView alloc] init];

	NSArray *titles = @[AILocalizedString(@"State", "Column of the state colour table"),
						AILocalizedString(@"On", "Column of the state colour table saying whether a colour is used"),
						AILocalizedString(@"Name", "Column of the state colour table holding the colour a name is written in"),
						AILocalizedString(@"Row", "Column of the state colour table holding the colour a whole row is filled with")];
	NSArray *widths = @[@150.0, @44.0, @60.0, @60.0];

	for (NSUInteger i = 0; i < titles.count; i++) {
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"c%lu", (unsigned long)i]];
		column.title = titles[i];
		column.width = [widths[i] doubleValue];
		[stateColourTable addTableColumn:column];
	}

	//The name column takes whatever width is left over
	stateColourTable.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
	stateColourTable.delegate = self;
	stateColourTable.dataSource = self;

	/* No scroller of its own: ten rows are few enough to show at once, and a
	 * list that scrolls inside a page that scrolls is a trap. */
	CGFloat height = (stateColourRows.count * (stateColourTable.rowHeight + stateColourTable.intercellSpacing.height)) + 40.0;
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, FORM_WIDTH - 100.0, height)];
	scroll.documentView = stateColourTable;
	scroll.hasVerticalScroller = NO;
	scroll.borderType = NSNoBorder;
	scroll.drawsBackground = NO;
	[scroll.heightAnchor constraintEqualToConstant:height].active = YES;

	return scroll;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return stateColourRows.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	AIStateColourRow *entry = stateColourRows[row];
	NSString *identifier = tableColumn.identifier;

	if ([identifier isEqualToString:@"c0"]) {
		return [tableView ai_labelCellViewForColumn:tableColumn value:entry.label];
	}

	NSTableCellView *cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, tableView.rowHeight)];
	NSView *control;

	if ([identifier isEqualToString:@"c1"]) {
		control = [self switchForKey:entry.enabledKey group:PREF_GROUP_LIST_THEME];
	} else if ([identifier isEqualToString:@"c2"]) {
		control = [self colourWellForKey:entry.textColourKey group:PREF_GROUP_LIST_THEME];
	} else {
		control = [self colourWellForKey:entry.areaColourKey group:PREF_GROUP_LIST_THEME];
	}

	control.translatesAutoresizingMaskIntoConstraints = NO;
	[cellView addSubview:control];
	[NSLayoutConstraint activateConstraints:@[
		[control.centerXAnchor constraintEqualToAnchor:cellView.centerXAnchor],
		[control.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor],
	]];

	return cellView;
}

#pragma mark Controls

- (NSTextField *)captionWithText:(NSString *)text
{
	NSTextField *label = [NSTextField labelWithString:text];
	label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	label.textColor = [NSColor secondaryLabelColor];
	return label;
}

- (NSSwitch *)switchForKey:(NSString *)key group:(NSString *)group
{
	NSSwitch *control = [AISettingsFormView switchWithTarget:self action:@selector(controlChanged:)];
	[bindings setObject:[AIBinding bindingWithKey:key group:group kind:AIBindingBool] forKey:control];
	return control;
}

- (NSColorWell *)colourWellForKey:(NSString *)key group:(NSString *)group
{
	NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 52.0, 24.0)];
	well.target = self;
	well.action = @selector(controlChanged:);
	well.continuous = YES;
	[bindings setObject:[AIBinding bindingWithKey:key group:group kind:AIBindingColour] forKey:well];
	return well;
}

- (NSSlider *)sliderFrom:(double)minValue to:(double)maxValue key:(NSString *)key group:(NSString *)group kind:(AIBindingKind)kind
{
	NSSlider *slider = [AISettingsFormView sliderWithMinValue:minValue maxValue:maxValue
													   target:self action:@selector(controlChanged:)];
	slider.continuous = YES;
	[bindings setObject:[AIBinding bindingWithKey:key group:group kind:kind] forKey:slider];
	return slider;
}

- (NSTextField *)valueLabelFor:(NSSlider *)slider suffix:(NSString *)suffix
{
	NSTextField *label = [AISettingsFormView valueLabelForWidestValue:[@"000" stringByAppendingString:suffix]];
	[bindings setObject:slider forKey:label];
	return label;
}

- (NSPopUpButton *)popUpWithTitlesAndTags:(NSArray *)titlesAndTags key:(NSString *)key group:(NSString *)group
{
	NSPopUpButton *popUp = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(controlChanged:)];
	NSMenu *menu = [[NSMenu alloc] init];

	for (NSUInteger i = 0; i + 1 < titlesAndTags.count; i += 2) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titlesAndTags[i] action:nil keyEquivalent:@""];
		item.tag = [titlesAndTags[i + 1] integerValue];
		[menu addItem:item];
	}
	popUp.menu = menu;

	[bindings setObject:[AIBinding bindingWithKey:key group:group kind:AIBindingInteger] forKey:popUp];
	return popUp;
}

- (NSPopUpButton *)alignmentPopUpForKey:(NSString *)key
{
	return [self popUpWithTitlesAndTags:@[AILocalizedString(@"Left", nil), @(NSTextAlignmentLeft),
										  AILocalizedString(@"Centered", nil), @(NSTextAlignmentCenter),
										  AILocalizedString(@"Right", nil), @(NSTextAlignmentRight)]
									 key:key
								   group:PREF_GROUP_LIST_LAYOUT];
}

- (NSPopUpButton *)positionPopUpForKey:(NSString *)key withBadges:(BOOL)withBadges
{
	NSMutableArray *entries = [NSMutableArray arrayWithArray:@[
		AILocalizedString(@"Far left", nil), @(LIST_POSITION_FAR_LEFT),
		AILocalizedString(@"Left", nil), @(LIST_POSITION_LEFT),
		AILocalizedString(@"Right", nil), @(LIST_POSITION_RIGHT),
		AILocalizedString(@"Far right", nil), @(LIST_POSITION_FAR_RIGHT)]];

	if (withBadges) {
		[entries addObjectsFromArray:@[AILocalizedString(@"On the picture, bottom left", nil), @(LIST_POSITION_BADGE_LEFT),
									   AILocalizedString(@"On the picture, bottom right", nil), @(LIST_POSITION_BADGE_RIGHT)]];
	}

	return [self popUpWithTitlesAndTags:entries key:key group:PREF_GROUP_LIST_LAYOUT];
}

- (NSButton *)fontButtonForKey:(NSString *)key
{
	NSButton *button = [AISettingsFormView pushButtonWithTitle:@"" target:self action:@selector(chooseFont:)];
	[bindings setObject:[AIBinding bindingWithKey:key group:PREF_GROUP_LIST_LAYOUT kind:AIBindingFont] forKey:button];
	return button;
}

#pragma mark Reading and writing

- (void)refreshControls
{
	NSDictionary *layoutDict = [adium.preferenceController preferencesForGroup:PREF_GROUP_LIST_LAYOUT];
	NSDictionary *themeDict = [adium.preferenceController preferencesForGroup:PREF_GROUP_LIST_THEME];

	for (id control in bindings.keyEnumerator.allObjects) {
		id entry = [bindings objectForKey:control];
		if (![entry isKindOfClass:[AIBinding class]]) continue;

		AIBinding *binding = entry;
		id value = ([binding.group isEqualToString:PREF_GROUP_LIST_LAYOUT] ? layoutDict[binding.key] :
					([binding.group isEqualToString:PREF_GROUP_LIST_THEME] ? themeDict[binding.key] :
					 [adium.preferenceController preferenceForKey:binding.key group:binding.group]));

		switch (binding.kind) {
			case AIBindingBool:
				[(NSSwitch *)control setState:([value boolValue] ? NSControlStateValueOn : NSControlStateValueOff)];
				break;
			case AIBindingInteger:
				if ([control isKindOfClass:[NSPopUpButton class]])
					[(NSPopUpButton *)control selectItemWithTag:[value integerValue]];
				else
					[(NSSlider *)control setIntegerValue:[value integerValue]];
				break;
			case AIBindingFloat:
				[(NSSlider *)control setDoubleValue:[value doubleValue] * 100.0];
				break;
			case AIBindingColour:
				[(NSColorWell *)control setColor:([value representedColor] ?: [NSColor textBackgroundColor])];
				break;
			case AIBindingFont: {
				NSFont *font = [value representedFont] ?: [NSFont systemFontOfSize:12.0];
				[(NSButton *)control setTitle:[NSString stringWithFormat:@"%@ %.0f", font.displayName, font.pointSize]];
				break;
			}
			case AIBindingPath:
				break;
		}
	}

	//The value labels follow their slider
	for (id control in bindings.keyEnumerator.allObjects) {
		if (![control isKindOfClass:[NSTextField class]]) continue;
		NSSlider *slider = [bindings objectForKey:control];
		if (![slider isKindOfClass:[NSSlider class]]) continue;
		[(NSTextField *)control setStringValue:[NSString stringWithFormat:@"%ld", (long)lround(slider.doubleValue)]];
	}

	[self refreshPreview];
}

- (IBAction)controlChanged:(id)sender
{
	if (rebuilding) return;

	AIBinding *binding = [bindings objectForKey:sender];
	if (!binding) return;

	id value = nil;
	switch (binding.kind) {
		case AIBindingBool:
			value = @([(NSSwitch *)sender state] == NSControlStateValueOn);
			break;
		case AIBindingInteger:
			value = @([sender isKindOfClass:[NSPopUpButton class]] ?
					  [[(NSPopUpButton *)sender selectedItem] tag] :
					  lround([(NSSlider *)sender doubleValue]));
			break;
		case AIBindingFloat:
			value = @(lround([(NSSlider *)sender doubleValue]) / 100.0);
			break;
		case AIBindingColour:
			value = [[(NSColorWell *)sender color] stringRepresentation];
			break;
		case AIBindingFont:
		case AIBindingPath:
			return;
	}

	[adium.preferenceController setPreference:value forKey:binding.key group:binding.group];

	/* The window style decides which settings even apply, so the form is built
	 * again when it changes. */
	if ([binding.key isEqualToString:KEY_LIST_LAYOUT_WINDOW_STYLE]) {
		[self rebuildForm];
		return;
	}

	[self refreshControls];
}

- (void)refreshPreview
{
	[previewView applyLayout:[adium.preferenceController preferencesForGroup:PREF_GROUP_LIST_LAYOUT]
					   theme:[adium.preferenceController preferencesForGroup:PREF_GROUP_LIST_THEME]
				 windowStyle:[self windowStyle]];
}

#pragma mark Fonts and pictures

- (IBAction)chooseFont:(id)sender
{
	AIBinding *binding = [bindings objectForKey:sender];
	if (!binding) return;

	activeFontKey = binding.key;

	NSFont *font = [[adium.preferenceController preferenceForKey:binding.key
														  group:PREF_GROUP_LIST_LAYOUT] representedFont];
	NSFontManager *manager = [NSFontManager sharedFontManager];
	[manager setTarget:self];
	[manager setSelectedFont:(font ?: [NSFont systemFontOfSize:12.0]) isMultiple:NO];
	[[manager fontPanel:YES] makeKeyAndOrderFront:nil];
}

- (void)changeFont:(id)sender
{
	if (!activeFontKey) return;

	NSFont *font = [[adium.preferenceController preferenceForKey:activeFontKey
														  group:PREF_GROUP_LIST_LAYOUT] representedFont];
	font = [sender convertFont:(font ?: [NSFont systemFontOfSize:12.0])];

	[adium.preferenceController setPreference:[font stringRepresentation]
									   forKey:activeFontKey
										group:PREF_GROUP_LIST_LAYOUT];
	[self refreshControls];
}

- (IBAction)chooseBackgroundImage:(id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.allowsMultipleSelection = NO;
	panel.canChooseDirectories = NO;
	panel.allowedContentTypes = @[UTTypeImage];

	[panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;

		[adium.preferenceController setPreference:panel.URL.path
										   forKey:KEY_LIST_THEME_BACKGROUND_IMAGE_PATH
											group:PREF_GROUP_LIST_THEME];
		[adium.preferenceController setPreference:@YES
										   forKey:KEY_LIST_THEME_BACKGROUND_IMAGE_ENABLED
											group:PREF_GROUP_LIST_THEME];
		[self refreshControls];
	}];
}

#pragma mark Sections

- (void)scrollToSection:(AIContactListAppearanceSection)section
{
	NSView *anchor = sectionAnchors[@(section)];
	if (!anchor || !anchor.superview) return;

	NSRect inForm = [anchor convertRect:anchor.bounds toView:form];
	//A little above the row, so the section's heading comes along
	CGFloat top = MAX(0.0, NSMinY(inForm) - 44.0);
	[(NSView *)formScrollView.documentView scrollPoint:NSMakePoint(0.0, top)];
}

@end
