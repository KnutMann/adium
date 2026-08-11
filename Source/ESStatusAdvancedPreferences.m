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

#import "ESStatusAdvancedPreferences.h"
#import "AIStatusController.h"
#import "ESiTunesPlugin.h"
#import "AIPreferenceWindowController.h"
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIImageAdditions.h>

//Width the form starts out at; the preferences window resizes it to its column.
#define STATUS_ADVANCED_PANE_INITIAL_WIDTH	540.0

/* How long the typing has to stop before the plugin is told. Announcing the
 * format makes every account rebuild its dynamic content, which is far too much
 * to do once per keystroke. */
#define FORMAT_CHANGE_DELAY					0.5

@interface ESStatusAdvancedPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (NSPopUpButton *)insertTokenPopUpButton;
- (IBAction)changeFormat:(id)sender;
- (void)insertToken:(id)sender;
- (void)saveFormat;
- (void)postFormatChanged;
- (void)bindObject:(id)object binding:(NSString *)binding keyPath:(NSString *)keyPath options:(NSDictionary *)options;
- (NSString *)keyPathForGroup:(NSString *)group key:(NSString *)key;
@end

@implementation ESStatusAdvancedPreferences
#pragma mark Preference pane settings
- (AIPreferenceCategory)category{
    return AIPref_Advanced;
}
- (NSString *)label{
    return AILocalizedString(@"Status",nil);
}
- (NSImage *)image{
	return [NSImage imageNamed:@"pref-status" forClass:[AIPreferenceWindowController class]];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads
 * a nib for us. StatusPreferencesAdvanced.xib is dead — and it must stay
 * unloaded: it still wires twenty-two outlets this class no longer has
 * (tokenField_album, box_itunesElements, label_instructions, …), so loading it
 * would raise NSUnknownKeyException rather than fall back to the old interface.
 * Removing it from the target needs project file access we do not have here.
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

		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Undo everything -view built.
 *
 * -bind:toObject:withKeyPath:options: retains us, so every live binding is a
 * retain cycle the pane only escapes through -viewWillClose. -closeView unbinds
 * and releases the view, and is idempotent.
 */
- (void)dealloc
{
	[self closeView];
	[establishedBindings release];
	[super dealloc];
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * Two cards. The first is what the Now Playing status sends; the nib gave the
 * same thing a token field, a boxed palette of seven drag sources and a line of
 * instructions, which together took two thirds of the pane. A plain field plus a
 * pull down does the same job in one row — and unlike dragging, it can be done
 * from the keyboard.
 *
 * The second card is the away status window, whose two settings have nothing to
 * do with music and keep the titles, keys and bindings they had in the nib.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:STATUS_ADVANCED_PANE_INITIAL_WIDTH] autorelease];

	//What the Now Playing status and the %_iTunes token are replaced with
	[form addSectionHeader:AILocalizedString(@"Now Playing", "Section title of the settings for what the Now Playing status sends")];

	textField_format = [AISettingsFormView textFieldWithTarget:self action:@selector(changeFormat:)];
	[textField_format setDelegate:self];
	[form addRowWithLabel:AILocalizedString(@"Format", "Title of the Format menu")
		stretchingControl:textField_format];

	popUp_insertToken = [self insertTokenPopUpButton];
	[form addTrailingAccessoryView:popUp_insertToken];

	/* Says what the format is for, and warns about the one thing the user would
	 * otherwise take for a fault: Music broadcasts only when something changes, so
	 * after a restart Adium knows nothing until the next track, pause or stop. We
	 * deliberately do not ask Music — asking means an Apple event and an automation
	 * prompt for a piece of decoration.
	 */
	[form addFootnote:AILocalizedString(@"The Music Status and the %_iTunes token are replaced with this. Adium learns what is playing the next time Music starts, pauses or changes the track.",
										"Explanation below the Now Playing format field. %_iTunes is a token and must not be translated.")];

	[form addSectionHeader:AILocalizedString(@"Away Status Window", nil)];

	//Both keep the exact binding — same key, same group — they had in the nib
	switch_statusWindowAlwaysOnTop = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:switch_statusWindowAlwaysOnTop
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_STATUS_PREFERENCES key:KEY_STATUS_STATUS_WINDOW_ON_TOP]
			 options:nil];
	[form addRowWithLabel:AILocalizedString(@"Show the status window above other windows", nil)
				  control:switch_statusWindowAlwaysOnTop];

	switch_statusWindowHideInBackground = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:switch_statusWindowHideInBackground
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_STATUS_PREFERENCES key:KEY_STATUS_STATUS_WINDOW_HIDE_IN_BACKGROUND]
			 options:nil];
	[form addRowWithLabel:AILocalizedString(@"Hide the status window when Adium is not active", nil)
				  control:switch_statusWindowHideInBackground];

	return form;
}

/*!
 * @brief The "Insert" menu of tokens, sitting under the format card.
 *
 * A pull down rather than a pop up: the button is a verb, not a choice that
 * stays selected, so its title never changes. Its first item is that title and
 * is never chosen. Each token carries its own action, so the button itself needs
 * none.
 *
 * The titles are the ones the nib labelled its palette with — same strings, same
 * order — so every existing translation still applies.
 */
- (NSPopUpButton *)insertTokenPopUpButton
{
	NSPopUpButton	*popUp = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES] autorelease];
	NSArray			*titles = [NSArray arrayWithObjects:
							   AILocalizedString(@"Title", nil),
							   AILocalizedString(@"Artist", nil),
							   AILocalizedString(@"Album", nil),
							   AILocalizedString(@"Composer", nil),
							   AILocalizedString(@"Genre", nil),
							   AILocalizedString(@"Year", nil),
							   AILocalizedString(@"Player State", nil),
							   nil];
	NSArray			*tokens = [NSArray arrayWithObjects:
							   TRIGGER_TRACK,
							   TRIGGER_ARTIST,
							   TRIGGER_ALBUM,
							   TRIGGER_COMPOSER,
							   TRIGGER_GENRE,
							   TRIGGER_YEAR,
							   TRIGGER_STATUS,
							   nil];

	[popUp addItemWithTitle:AILocalizedString(@"Insert", nil)];

	for (NSUInteger i = 0; i < [tokens count]; i++) {
		NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:[titles objectAtIndex:i]
													  action:@selector(insertToken:)
											   keyEquivalent:@""] autorelease];

		[item setTarget:self];
		[item setRepresentedObject:[tokens objectAtIndex:i]];
		[[popUp menu] addItem:item];
	}

	[popUp sizeToFit];

	return popUp;
}

#pragma mark Configuration

//Configure the preference view
- (void)viewDidLoad
{
	NSString *displayFormat = [adium.preferenceController preferenceForKey:KEY_ITUNES_TRACK_FORMAT
																	 group:PREF_GROUP_STATUS_PREFERENCES];

	/* The plugin falls back to the same default for an empty preference, so show
	 * it rather than an empty field — but do not write it: an untouched setting
	 * stays untouched, and the fallback is allowed to change with the locale.
	 */
	if (![displayFormat length]) {
		displayFormat = [NSString stringWithFormat:@"%@ - %@", TRIGGER_TRACK, TRIGGER_ARTIST];
	}
	[textField_format setStringValue:displayFormat];

	[super viewDidLoad];
}

- (void)viewWillClose
{
	//Whatever was typed last still has to reach the plugin
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(postFormatChanged) object:nil];
	if (formatChangePending) [self postFormatChanged];

	for (NSArray *boundPair in establishedBindings) {
		[[boundPair objectAtIndex:0] unbind:[boundPair objectAtIndex:1]];
	}
	[establishedBindings release]; establishedBindings = nil;

	[textField_format setDelegate:nil];

	textField_format = nil;
	popUp_insertToken = nil;
	switch_statusWindowAlwaysOnTop = nil;
	switch_statusWindowHideInBackground = nil;

	[super viewWillClose];
}

#pragma mark Bindings

/*!
 * @brief The key path a preference has when bound through the shared controller.
 */
- (NSString *)keyPathForGroup:(NSString *)group key:(NSString *)key
{
	return [NSString stringWithFormat:@"adium.preferenceController.%@.%@", group, key];
}

/*!
 * @brief Bind @a object to ourselves, remembering the binding so we can undo it.
 */
- (void)bindObject:(id)object binding:(NSString *)binding keyPath:(NSString *)keyPath options:(NSDictionary *)options
{
	if (!object) return;

	[object bind:binding toObject:self withKeyPath:keyPath options:options];

	if (!establishedBindings) establishedBindings = [[NSMutableArray alloc] init];
	[establishedBindings addObject:[NSArray arrayWithObjects:object, binding, nil]];
}

#pragma mark The format

/*!
 * @brief The field finished editing: Return, Tab or the focus moving away.
 */
- (IBAction)changeFormat:(id)sender
{
	[self saveFormat];
}

/*!
 * @brief Write the format the moment it changes.
 *
 * The action alone would not be enough. Adium never ends the editing session
 * itself; it takes the pane out of the window with -removeFromSuperview
 * (-[AIModernPreferencesWindowController selectPane:] and -windowWillClose:) and
 * leaves it to AppKit whether an action still follows. Storing at every keystroke
 * means nothing typed depends on that.
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	[self saveFormat];
}

/*!
 * @brief Editing ended: remember where the caret was.
 *
 * Clicking the pull down may take the focus off the field. The token still has
 * to be inserted where the user left off, not at the end and not over the whole
 * text — which is what a field freshly made first responder would offer.
 */
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	NSText *editor = [[notification userInfo] objectForKey:@"NSFieldEditor"];

	if (editor) {
		savedSelectedRange = [editor selectedRange];
		hasSavedSelectedRange = YES;
	}
}

/*!
 * @brief Put a token where the caret is.
 *
 * Through the field editor rather than through -setStringValue:, so the token
 * lands at the caret, replaces a selection, can be undone, and does not throw
 * away an edit in progress.
 */
- (void)insertToken:(id)sender
{
	NSString	*token = [sender representedObject];
	NSText		*editor = [textField_format currentEditor];

	if (![token length]) return;

	/* -currentEditor is nil unless this very field is being edited; asking the
	 * window for a field editor would also hand back one that belongs to somebody
	 * else. Start editing, then put the caret back where it was: making a text
	 * field first responder selects all of its text, and inserting would replace
	 * the whole format.
	 */
	if (!editor) {
		[[textField_format window] makeFirstResponder:textField_format];
		editor = [textField_format currentEditor];

		if (editor) {
			NSUInteger	length = [[editor string] length];
			NSRange		range = (hasSavedSelectedRange ? savedSelectedRange : NSMakeRange(length, 0));

			//The text may have been shortened since the range was remembered
			if (NSMaxRange(range) > length) range = NSMakeRange(length, 0);
			[editor setSelectedRange:range];
		}
	}

	if ([editor isKindOfClass:[NSTextView class]]) {
		[(NSTextView *)editor insertText:token replacementRange:[editor selectedRange]];
	} else {
		//No window to edit in; appending beats losing the token
		[textField_format setStringValue:[[textField_format stringValue] stringByAppendingString:token]];
	}

	[self saveFormat];
}

/*!
 * @brief Store the format at once, announce it once the typing stops.
 */
- (void)saveFormat
{
	/* The field sends its action whenever an editing session ends, and that is not
	 * always the user's doing: the closing window pulls the view out from under the
	 * field editor, and it does so after -viewWillClose has already let go of the
	 * field. Without the field there is nothing to read, and writing nil removes the
	 * key rather than setting it. There is nothing left to save either — every
	 * keystroke went through -controlTextDidChange: — so the stray action may run
	 * out into nothing.
	 */
	if (!textField_format) return;

	NSText		*editor = [textField_format currentEditor];
	/* While a field is being edited its -stringValue is still the last committed
	 * text; only the field editor knows what stands there now.
	 *
	 * Copied, not just taken: -[NSText string] hands out the field editor's own
	 * text storage, and one field editor serves the whole window. Stored as it is,
	 * the preference would keep following the editor — through every further
	 * keystroke and on into the next field the editor is handed to — and
	 * AIPreferenceContainer, finding the very object it already holds, would take
	 * each of those keystrokes for no change at all and never write the file.
	 */
	NSString	*format = [[(editor ? [editor string] : [textField_format stringValue]) copy] autorelease];

	[adium.preferenceController setPreference:format
									   forKey:KEY_ITUNES_TRACK_FORMAT
										group:PREF_GROUP_STATUS_PREFERENCES];

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(postFormatChanged) object:nil];
	[self performSelector:@selector(postFormatChanged) withObject:nil afterDelay:FORMAT_CHANGE_DELAY];
	formatChangePending = YES;
}

/*!
 * @brief Tell the plugin the format changed.
 *
 * Reads the stored value rather than the field, so this is safe to fire while
 * the pane is being taken apart.
 */
- (void)postFormatChanged
{
	formatChangePending = NO;

	[[NSNotificationCenter defaultCenter] postNotificationName:Adium_CurrentTrackFormatChangedNotification
													   object:[adium.preferenceController preferenceForKey:KEY_ITUNES_TRACK_FORMAT
																								     group:PREF_GROUP_STATUS_PREFERENCES]];
}

@end
