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

#import "ESPersonalPreferences.h"
#import <Adium/AIAccount.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIMessageEntryTextView.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIAutoScrollView.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIImageViewWithImagePicker.h>

//Width the form starts out at; the preferences window resizes it to its column.
#define PERSONAL_PANE_INITIAL_WIDTH		540.0

/* The key the profile is stored under. A string literal rather than a macro from
 * a header, because that is what it has always been: CBPurpleAccount reads the
 * very same literal out of GROUP_ACCOUNT_STATUS to answer a profile request.
 */
#define KEY_TEXT_PROFILE				@"textProfile"

/* How tall the profile card is. A row measures its height from the view it was
 * handed, and an AIMessageEntryTextView grows with its text (it is vertically
 * resizable and the nib gave it a maximum height of ten million points): without
 * a height fixed here the card would grow with every line the user types. The
 * nib's scroll view was 167 points tall; 150 is that height less the space the
 * nib spent on its own border. Shorter now that the profile shares a card and a
 * label column with the row above it rather than filling a card of its own.
 */
#define PROFILE_HEIGHT					96.0

/* How large an icon the picker hands back, unchanged: the size the icon is
 * stored at and the contact list and every service use. Independent of the well
 * it is shown in.
 */
#define USER_ICON_SIDE					128.0

/* How large the picture is shown in the profile header. Smaller than the stored
 * size, and large enough that a face in it is recognisable: this is the portrait
 * the page opens with, not a well beside a label. The form clips it to a circle
 * of exactly this diameter.
 */
#define USER_ICON_WELL_SIDE				96.0

/* How long a text control gathers keystrokes before it stores what was typed.
 *
 * Not zero, and that is a deliberate exception to "every control writes at
 * once": these two preferences are not private to this pane. Every enabled
 * account watches GROUP_ACCOUNT_STATUS (-[AIAbstractAccount
 * preferencesChangedForGroup:...]), and both keys are in its
 * -supportedPropertyKeys, so *each* write runs the filter chain and pushes the
 * result to the server - the display name as an alias, the profile as the
 * account's info. Writing per keystroke would mean one server round trip per
 * letter on every connected account, which is what the nib's delays were for.
 *
 * What the nib got wrong was not the delay but the flushing, and that is what is
 * fixed here: the pending write is not tied to the pane staying on screen. It
 * survives switching panes (nothing cancels it, and the preferences window keeps
 * this pane alive), and it is forced out at every point where it could otherwise
 * be lost - when editing ends, when the window closes and when Adium quits. The
 * nib had only the last of those, and only for the window.
 */
#define SAVE_DELAY				0.4

#define DISPLAY_NAME_TOOLTIP	AILocalizedString(@"Your name, which on supported services will be sent to remote contacts. Substitutions from the Edit->Scripts and Edit->iTunes menus may be used here.", nil)
#define PROFILE_TOOLTIP			AILocalizedString(@"Profile to display when contacts request information about you (not supported by all services). Text may be formatted using the Edit and Format menus.", nil)

@interface ESPersonalPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (void)configureProfile;
- (void)configureImageView;
- (void)saveDisplayName;
- (void)saveProfile;
- (void)flushPendingSaves:(NSNotification *)notification;
@end

/*!
 * @brief A nib label reused as a section header: without its trailing colon.
 *
 * Keeps every existing translation of the old labels usable while matching the
 * System Settings look, where neither a header nor a row label carries a colon.
 */
static NSString *AIRowLabel(NSString *label)
{
	NSCharacterSet	*whitespace = [NSCharacterSet whitespaceCharacterSet];
	/* U+003A and the full width U+FF1A the CJK translations use ("プロフィール：") */
	NSCharacterSet	*colons = [NSCharacterSet characterSetWithCharactersInString:@":："];
	NSString		*trimmed = [label stringByTrimmingCharactersInSet:whitespace];

	while ([trimmed length] > 0 &&
		   [colons characterIsMember:[trimmed characterAtIndex:([trimmed length] - 1)]]) {
		trimmed = [[trimmed substringToIndex:([trimmed length] - 1)] stringByTrimmingCharactersInSet:whitespace];
	}

	return trimmed;
}

@implementation ESPersonalPreferences

/*!
 * @brief Preference pane properties
 */
- (NSString *)paneIdentifier
{
	return @"Personal";
}
- (NSString *)paneName{
    return AILocalizedString(@"Personal","Personal preferences label");
}
- (NSImage *)paneIcon
{
	return [NSImage imageNamed:@"Personal" forClass:[self class]];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads a nib for us.
 * PersonalPreferences.xib, which used to hold this interface, has been deleted along with its entry
 * in the target: nothing loaded it any more, and it still wired outlets this class no longer has,
 * so anything that did load it would have raised rather than fallen back.
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

		view = [form retain];

		[self viewDidLoad];
		[self localizePane];

		/* -viewDidLoad fills the controls through the preference observer; the
		 * icon may have arrived at a size of its own, so the form is measured
		 * once more before the window ever sees it.
		 */
		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Undo everything -view built.
 *
 * -closeView unregisters the preference observer, takes the pane out of the font
 * panel, releases the view and is idempotent. Without it a deallocated pane
 * would leave the preference controller holding a non-retained pointer to us and
 * the font panel one to a freed text view.
 */
- (void)dealloc
{
	[self closeView];
	[super dealloc];
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * A profile page: the picture, the name and the way to change the picture in a
 * header card of their own, and what is left as ordinary rows underneath. Each
 * setting keeps the key and group its nib counterpart was bound to; only the
 * presentation changes - and the moment at which the two text controls save (see
 * -controlTextDidChange: and -textDidChange:).
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:PERSONAL_PANE_INITIAL_WIDTH] autorelease];

	/* The picture. Nothing frames it: the form clips it to a circle and draws the
	 * disc it stands on, so the grey bezel the old well carried would only be a
	 * square corner cut off by that circle. The picker still hands back an icon at
	 * the full stored size; only the portrait it is shown as is smaller. */
	imageView_userIcon = [[[AIImageViewWithImagePicker alloc] initWithFrame:NSMakeRect(0.0, 0.0,
																					   USER_ICON_WELL_SIDE,
																					   USER_ICON_WELL_SIDE)] autorelease];
	[imageView_userIcon setDelegate:self];
	[imageView_userIcon setImageFrameStyle:NSImageFrameNone];
	[imageView_userIcon setImageScaling:NSImageScaleProportionallyUpOrDown];
	[imageView_userIcon setAnimates:YES];
	//As in the nib: the picture is reached by clicking it, not by tabbing through the pane
	[imageView_userIcon setRefusesFirstResponder:YES];
	//The largest icon the picker hands back, not the size it is shown at
	[imageView_userIcon setMaxSize:NSMakeSize(USER_ICON_SIDE, USER_ICON_SIDE)];
	//A picture has no title of its own for VoiceOver to read
	[imageView_userIcon setAccessibilityLabel:AILocalizedString(@"Icon",nil)];

	/* The name, centred under the picture rather than in a labelled row: it is what
	 * the page is about, and every profile page a user of Adium also uses puts it
	 * there. Editable where it stands, so there is no second field elsewhere saying
	 * the same thing. */
	textField_displayName = [AISettingsFormView profileNameFieldWithTarget:self action:@selector(changePreference:)];
	//...and as our delegate it also tells us about every keystroke, see -controlTextDidChange:
	[textField_displayName setDelegate:self];
	/* The nib put this on the label and on the field. There is no label any more,
	 * and no row to hang it on either, so it goes on the field itself. */
	[textField_displayName setToolTip:DISPLAY_NAME_TOOLTIP];
	[textField_displayName setAccessibilityLabel:AIRowLabel(AILocalizedString(@"Name:",nil))];

	/* The address book name, shown in grey while the field is empty, exactly as
	 * the nib did: it is what Adium falls back on, so it belongs in the field as
	 * a promise rather than as text the user would have to delete.
	 */
	NSString	*defaultName = [[[adium.preferenceController defaultPreferenceForKey:KEY_ACCOUNT_DISPLAY_NAME
																			   group:GROUP_ACCOUNT_STATUS
																			  object:nil] attributedString] string];
	[textField_displayName setPlaceholderString:(defaultName ? defaultName : @"")];

	/* The button opens the picker on the picture itself, exactly as the nib wired
	 * it: its action belongs to the image view, and the preference is written when
	 * the view tells us it has a new image (see the delegate methods below).
	 * Pointing it at this pane instead would be a silent loss of function.
	 */
	button_chooseIcon = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Choose Icon...",nil)
														target:imageView_userIcon
														action:@selector(showImagePicker:)];

	[form addProfileHeaderWithImageView:imageView_userIcon
							  nameView:textField_displayName
								button:button_chooseIcon];
	[form endCard];

	/* One card for what is left, no headers: two settings sitting together the way
	 * a System Settings group does rather than each in a card of its own. */

	/* Whether an icon is sent at all: the boolean the KEY_USE_USER_ICON preference
	 * stores, and what the nib's two radio cells and the dropdown after them chose
	 * between. A switch now, because the picture the choice is about is no longer
	 * below the control but above it, where "use this icon" has nothing left to
	 * point at, and because an either/or with no third answer is a switch in System
	 * Settings. */
	switch_useIcon = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show my picture to contacts", "Personal preferences: whether the user's icon is sent to the services they are on")
				  control:switch_useIcon];

	//Profile: a labelled row with the editor as its control, no longer a card of its own
	NSString	*profileLabel = AIRowLabel(AILocalizedString(@"Profile:",nil));

	scrollView_profile = [[[AIAutoScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0,
																			 PERSONAL_PANE_INITIAL_WIDTH,
																			 PROFILE_HEIGHT)] autorelease];
	/* No border of its own: the card around it is the frame now, and a bezel
	 * inside a card would be a second one. The background stays the text
	 * background, so the writing area is still visibly an editable field.
	 */
	[scrollView_profile setBorderType:NSNoBorder];
	[scrollView_profile setDrawsBackground:YES];
	[scrollView_profile setBackgroundColor:[NSColor textBackgroundColor]];
	[scrollView_profile setHasVerticalScroller:YES];
	[scrollView_profile setHasHorizontalScroller:NO];
	[scrollView_profile setAutohidesScrollers:YES];
	//An NSTextView draws no focus ring; the scroll view holding it draws one for it
	[scrollView_profile setAlwaysDrawFocusRingIfFocused:YES];

	/* Built to the size of the area it is about to fill rather than to a size of
	 * its own: a document view wider than the clip view would scroll sideways, and
	 * this one has no horizontal scroller to scroll with.
	 */
	NSRect					 profileFrame = [[scrollView_profile contentView] bounds];
	AIMessageEntryTextView	*profileView = [[[AIMessageEntryTextView alloc] initWithFrame:profileFrame] autorelease];

	/* Everything the nib set on the text view. It is an AIMessageEntryTextView for
	 * the editing it brings - rich text, undo, the ruler, image pasting - but not
	 * for its chat behaviour: nothing here is sent anywhere on Return.
	 */
	[profileView setSendingEnabled:NO];
	[profileView setRichText:YES];
	[profileView setImportsGraphics:YES];
	[profileView setAllowsUndo:YES];
	[profileView setUsesFontPanel:YES];
	[profileView setUsesRuler:YES];
	[profileView setEditable:YES];

	/* Grows downwards with its text and never sideways, so the scroll view scrolls
	 * rather than the text running off the edge. The text container follows the
	 * view's width, which is what makes the text refold when the window is resized.
	 */
	[profileView setVerticallyResizable:YES];
	[profileView setHorizontallyResizable:NO];
	[profileView setMinSize:NSMakeSize(0.0, NSHeight(profileFrame))];
	[profileView setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
	[profileView setAutoresizingMask:NSViewWidthSizable];
	[[profileView textContainer] setContainerSize:NSMakeSize(NSWidth(profileFrame), CGFLOAT_MAX)];
	[[profileView textContainer] setWidthTracksTextView:YES];

	[scrollView_profile setDocumentView:profileView];

	textView_profile = profileView;
	[textView_profile setDelegate:self];
	[scrollView_profile setAccessibilityLabel:profileLabel];

	/* The font panel edits whatever its delegate is; without this, Format->Font
	 * would have nothing to work on. It keeps the delegate without retaining it,
	 * which is why -viewWillClose takes it back out again.
	 */
	[[NSFontPanel sharedFontPanel] setDelegate:(id <NSWindowDelegate>)textView_profile];

	/* Handed to the form directly, not wrapped: a labelled control row is not
	 * clipped to the card's corners the way an edge to edge row is, so the focus
	 * ring the scroll view draws outside its bounds has room - the container and
	 * inset the old card needed for it are gone. Label top-aligned, beside the
	 * first line of the editor rather than floating down its middle. */
	[form addRowWithLabel:profileLabel stretchingControl:scrollView_profile labelTopAligned:YES];

	/* What the nib only offered as a tool tip over the "Profile:" label, and what
	 * an info row carried at the top of the pane until the header took that place.
	 * Under the card it belongs to rather than over it: it explains the row above
	 * it, and a paragraph between the portrait and the settings would separate the
	 * two things the page is made of. */
	[form addFootnote:PROFILE_TOOLTIP];

	return form;
}

#pragma mark Configuration

/*!
 * @brief Configure the view initially
 */
- (void)viewDidLoad
{
	/* The profile has no way back from the preferences (nothing else in Adium
	 * writes it while this pane is open), so it is read once, here.
	 */
	[self configureProfile];

	/* Fills the name field, the picture and the icon switch: the registration itself
	 * calls us back with firstTime YES.
	 */
	[adium.preferenceController registerPreferenceObserver:self forGroup:GROUP_ACCOUNT_STATUS];

	/* Quitting is the one way out which reaches neither the end of an editing
	 * session nor -viewWillClose; a keystroke made half a second before Cmd-Q
	 * would be the one thing left that could go missing.
	 */
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(flushPendingSaves:)
												 name:NSApplicationWillTerminateNotification
											   object:nil];

	[super viewDidLoad];
}

/*!
 * @brief The view is going away
 *
 * The window is closing (the only thing which reaches this method), so anything
 * still waiting has to go out now and nothing may be left scheduled on a view
 * which is about to be released. Unlike the nib's version, this is a last resort
 * rather than the only chance: see SAVE_DELAY.
 */
- (void)viewWillClose
{
	[self flushPendingSaves:nil];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSApplicationWillTerminateNotification
												  object:nil];

	//The controller keeps a non-retained pointer to us
	[adium.preferenceController unregisterPreferenceObserver:self];

	/* The font panel keeps its delegate without retaining it and the text view is
	 * about to be released with the form, so leaving it set points the panel at
	 * freed memory. Only if it is still ours: another pane may have taken it over.
	 */
	if ([NSFontPanel sharedFontPanelExists] &&
		[[NSFontPanel sharedFontPanel] delegate] == (id)textView_profile) {
		[[NSFontPanel sharedFontPanel] setDelegate:nil];
	}

	//Non-retained delegates, all of them pointing at us
	[textView_profile setDelegate:nil];
	[textField_displayName setDelegate:nil];
	[imageView_userIcon setDelegate:nil];
	//The switch's action points at us too; the button's points at the picture, which the form owns
	[switch_useIcon setTarget:nil];

	/* The form owns every control; these are the pane's non-owning references to
	 * them and must not outlive the view.
	 */
	textField_displayName = nil;
	scrollView_profile = nil;
	textView_profile = nil;
	switch_useIcon = nil;
	button_chooseIcon = nil;
	imageView_userIcon = nil;

	[super viewWillClose];
}

/*!
 * @brief Dim what the icon switch turns off
 *
 * The picture and its button follow the switch: they mean nothing while no icon
 * is being sent at all, so they dim with it.
 */
- (void)configureControlDimming
{
	BOOL	enableUserIcon = ([switch_useIcon state] == NSControlStateValueOn);

	[button_chooseIcon setEnabled:enableUserIcon];
	[imageView_userIcon setEnabled:enableUserIcon];
}

#pragma mark Reading the preferences

/*!
 * @brief A preference of our group changed: show it.
 *
 * Also our way in: -registerPreferenceObserver:forGroup: calls this with
 * firstTime YES, which is what fills the controls initially.
 */
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	//Nothing here is set per account; an object-specific update is none of our business
	if (object || ![group isEqualToString:GROUP_ACCOUNT_STATUS]) return;

	if (firstTime || [key isEqualToString:KEY_ACCOUNT_DISPLAY_NAME]) {
		id			 storedName = [prefDict objectForKey:KEY_ACCOUNT_DISPLAY_NAME];
		id			 defaultName = [adium.preferenceController defaultPreferenceForKey:KEY_ACCOUNT_DISPLAY_NAME
																				 group:GROUP_ACCOUNT_STATUS
																				object:nil];
		NSString	*newDisplayName;

		/* prefDict is the set preferences with the defaults merged in
		 * (-[AIPreferenceContainer dictionary]), and AIAddressBookController registers
		 * the name of the "me" card as the default for this key. Put into the field as
		 * text, that name would be text the user has to delete - and could not get rid
		 * of, because an emptied field stores nothing (see -saveDisplayName), which
		 * brings the default straight back through this very observer, on top of the
		 * insertion point. The default belongs in the placeholder the field was built
		 * with, so it is recognised here and the field is left empty for it.
		 *
		 * By comparison rather than by reading the set value on its own: there is no
		 * public way to do the latter - -preferenceForKey:group:objectIgnoringInheritance:
		 * ignores inheritance between list objects, not defaults. A user who types
		 * exactly their address book name gets the placeholder instead of their text,
		 * which reads the same and means the same.
		 */
		if (!storedName || (defaultName && [storedName isEqual:defaultName])) {
			newDisplayName = @"";
		} else {
			newDisplayName = [[storedName attributedString] string];
		}

		/* And the promise itself is renewed here: the address book is read while Adium is already
		 * running, so the default this field was built with may have been none at all.
		 */
		NSString	*defaultNameString = (defaultName ? [[defaultName attributedString] string] : nil);

		[textField_displayName setPlaceholderString:(defaultNameString ? defaultNameString : @"")];

		/* Only when it really differs. The field stores what was typed while the
		 * pane is open, so this observer fires shortly after the user stops typing,
		 * and -setStringValue: on a field still being edited would throw the
		 * insertion point to the end of the line.
		 */
		if (newDisplayName && ![[textField_displayName stringValue] isEqualToString:newDisplayName]) {
			[textField_displayName setStringValue:newDisplayName];
		}
	}

	/* The nib had no way back for this one at all, so a change made elsewhere left
	 * the choice showing the wrong thing. Setting a switch's state sends no action,
	 * so writing the preference and hearing about it cannot loop.
	 */
	if (firstTime || [key isEqualToString:KEY_USE_USER_ICON]) {
		BOOL	useUserIcon = [[prefDict objectForKey:KEY_USE_USER_ICON] boolValue];

		[switch_useIcon setState:(useUserIcon ? NSControlStateValueOn : NSControlStateValueOff)];
	}

	if (firstTime || [key isEqualToString:KEY_USER_ICON] || [key isEqualToString:KEY_DEFAULT_USER_ICON]) {
		[self configureImageView];
	}

	[self configureControlDimming];
}

#pragma mark Changing preferences

/*!
 * @brief Called in response to the preference controls, applies new settings
 *
 * The icon switch writes the moment it is clicked. The preferences window only
 * calls -closeView when it closes - switching to another pane takes the view out
 * with -removeFromSuperview - so a control which waited for that would never be
 * saved at all; what the two text controls do instead is described at SAVE_DELAY.
 */
- (IBAction)changePreference:(id)sender
{
	if (sender == textField_displayName) {
		//Return, Tab or the focus moving away; nothing may be held back after that
		[self saveDisplayName];

	} else if (sender == switch_useIcon) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([switch_useIcon state] == NSControlStateValueOn)]
										   forKey:KEY_USE_USER_ICON
											group:GROUP_ACCOUNT_STATUS];
	}

	[super changePreference:nil];
}

#pragma mark Saving what was typed

/*!
 * @brief Force out whatever is still waiting to be written.
 *
 * Every path which could end this pane's life, or Adium's, before a scheduled
 * write comes due: the window closing (-viewWillClose) and the application
 * quitting (NSApplicationWillTerminateNotification). Switching to another pane
 * needs no entry here - it takes the view out of the window with
 * -removeFromSuperview and leaves this pane, its controls and its scheduled
 * write untouched, so the write happens by itself a moment later.
 *
 * Takes a notification so it can be an observer directly; it is called with nil
 * as well.
 */
- (void)flushPendingSaves:(NSNotification *)notification
{
	if (displayNameSavePending) [self saveDisplayName];
	if (profileSavePending) [self saveProfile];
}

#pragma mark The name

/*!
 * @brief Editing ended: Return, Tab or the focus moving away.
 *
 * The moment the field stops being edited nothing may be held back any more -
 * the user is done with it, and clicking another pane in the sidebar ends the
 * editing session before it takes the view out of the window.
 *
 * The field's cell sends its action on end of editing as well, so -saveDisplayName
 * is reached twice here; it writes only once (see the pending flag there).
 */
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	if ([notification object] == textField_displayName) [self saveDisplayName];
}

/*!
 * @brief A keystroke: write soon, and never mind whether an action follows.
 *
 * The field's action alone would not be enough. Adium never ends the editing
 * session itself; it takes the pane out of the window with -removeFromSuperview
 * and leaves it to AppKit whether an action still follows. See SAVE_DELAY for
 * why this is not written on the spot.
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] != textField_displayName) return;

	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(saveDisplayName)
											   object:nil];
	displayNameSavePending = YES;
	[self performSelector:@selector(saveDisplayName) withObject:nil afterDelay:SAVE_DELAY];
}

- (void)saveDisplayName
{
	NSString	*displayName = [textField_displayName stringValue];

	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(saveDisplayName)
											   object:nil];

	//Never without the field: an empty field means the default name, a missing one means nothing
	if (!textField_displayName) {
		displayNameSavePending = NO;
		return;
	}

	/* Nothing has been typed since the last write, so there is nothing to write. The end of an
	 * editing session reaches this method twice - once through -controlTextDidEndEditing: and once
	 * through the field's action, which its cell sends on end of editing (AISettingsFormView's
	 * +textFieldWithTarget:action:) - and a write which changes nothing is not free: AIPreferenceContainer
	 * tells its observers even when the value is unchanged (deliberately, see -setValue:forKey:), so
	 * every enabled account would run its filter chain and push the alias to its server a second
	 * time. That is exactly the server traffic SAVE_DELAY exists to keep down.
	 *
	 * Safe as a test for "is there an edit to write", because the flag is set by every keystroke
	 * (-controlTextDidChange:, which the field editor posts for pastes and drops as well) and is
	 * cleared only here, right before the value goes out.
	 */
	if (!displayNameSavePending) return;

	displayNameSavePending = NO;

	//An empty field is not an empty name: it means "no name of my own", i.e. the default
	[adium.preferenceController setPreference:((displayName && [displayName length]) ?
											   [[NSAttributedString stringWithString:displayName] dataRepresentation] :
											   nil)
									   forKey:KEY_ACCOUNT_DISPLAY_NAME
										group:GROUP_ACCOUNT_STATUS];
}

#pragma mark The profile

/*!
 * @brief Put the stored profile into the view.
 *
 * Through the text storage rather than through -setString: or
 * -setAttributedString:, both of which post an NSTextDidChangeNotification of
 * their own: filling the view would otherwise read as the user typing, and an
 * empty profile would be written back over the stored one the moment the pane
 * opens. The flag catches anything AppKit posts on top of that.
 */
- (void)configureProfile
{
	NSData				*profileData = [adium.preferenceController preferenceForKey:KEY_TEXT_PROFILE
																			  group:GROUP_ACCOUNT_STATUS];
	NSAttributedString	*profile = (profileData ? [NSAttributedString stringWithData:profileData] : nil);

	configuringProfile = YES;
	[[textView_profile textStorage] setAttributedString:(profile ? profile :
														 [[[NSAttributedString alloc] initWithString:@""] autorelease])];
	configuringProfile = NO;
}

/*!
 * @brief The profile stopped being edited: write it now.
 *
 * A text view has no action to send, so this and -flushPendingSaves: are all
 * there is. It fires when the focus leaves the profile - which is what clicking
 * another pane in the sidebar does first of all.
 */
- (void)textDidEndEditing:(NSNotification *)aNotification
{
	if ([aNotification object] == textView_profile) [self saveProfile];
}

/*!
 * @brief The profile changed: write it soon.
 *
 * See SAVE_DELAY for why "soon" rather than "now"; unlike the nib's version, the
 * write no longer depends on this pane still being on screen when it comes due.
 */
- (void)textDidChange:(NSNotification *)aNotification
{
	//The pane is filling the view itself, which is not the user typing
	if (configuringProfile) return;

	if ([aNotification object] != textView_profile) return;

	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(saveProfile)
											   object:nil];
	profileSavePending = YES;
	[self performSelector:@selector(saveProfile) withObject:nil afterDelay:SAVE_DELAY];
}

- (void)saveProfile
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(saveProfile)
											   object:nil];

	/* Never without the view: an empty text storage is a profile the user wrote,
	 * a missing one is no profile at all, and the second would wipe the first.
	 */
	if (!textView_profile) {
		profileSavePending = NO;
		return;
	}

	/* Nothing written since the last save. As with the name (see -saveDisplayName), a write which
	 * changes nothing still reaches every account's filter chain and its server, and the focus can
	 * leave the profile long after the delayed write has already gone out.
	 */
	if (!profileSavePending) return;

	profileSavePending = NO;

	[adium.preferenceController setPreference:[[textView_profile textStorage] dataRepresentation]
									   forKey:KEY_TEXT_PROFILE
										group:GROUP_ACCOUNT_STATUS];
}

#pragma mark AIImageViewWithImagePicker Delegate

- (void)imageViewWithImagePicker:(AIImageViewWithImagePicker *)sender didChangeToImageData:(NSData *)imageData
{
	[adium.preferenceController setPreference:imageData
									   forKey:KEY_USER_ICON
										group:GROUP_ACCOUNT_STATUS];
}

- (void)deleteInImageViewWithImagePicker:(AIImageViewWithImagePicker *)sender
{
	[adium.preferenceController setPreference:nil
									   forKey:KEY_USER_ICON
										group:GROUP_ACCOUNT_STATUS];

	//User icon - restore to the default icon
	[self configureImageView];
}

- (NSString *)fileNameForImageInImagePicker:(AIImageViewWithImagePicker *)picker
{
	return AILocalizedString(@"Adium Icon", nil);
}

- (void)configureImageView
{
	NSData *imageData = [adium.preferenceController preferenceForKey:KEY_USER_ICON
															   group:GROUP_ACCOUNT_STATUS];
	if (!imageData) {
		imageData = [adium.preferenceController preferenceForKey:KEY_DEFAULT_USER_ICON
														   group:GROUP_ACCOUNT_STATUS];
	}

	[imageView_userIcon setImage:(imageData ? [[[NSImage alloc] initWithData:imageData] autorelease] : nil)];
	[imageView_userIcon setMaxSize:NSMakeSize(USER_ICON_SIDE, USER_ICON_SIDE)];
	[imageView_userIcon setShouldUpdateRecentRepository:YES];
}

@end
