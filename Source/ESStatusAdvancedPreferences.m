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
#import "AICoreComponentLoader.h"
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

/* How long before the preview follows the typing. Deliberately far shorter than
 * FORMAT_CHANGE_DELAY and deliberately not the same timer: resolving the format is
 * two passes over a short string and costs nothing, so this delay is only there to
 * stop the line flickering under the caret — the half second above is there because
 * what it triggers is expensive. Hanging the preview off the expensive one would
 * make it visibly lag behind the field.
 */
#define PREVIEW_UPDATE_DELAY				0.2

@interface ESStatusAdvancedPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (NSPopUpButton *)insertTokenPopUpButton;
- (NSTextField *)previewField;
- (ESiTunesPlugin *)musicPlugin;
- (IBAction)changeFormat:(id)sender;
- (void)insertToken:(id)sender;
- (void)askPlayersOnFirstInteraction;
- (NSString *)currentFormat;
- (void)saveFormat;
- (void)postFormatChanged;
- (void)updatePreview;
- (void)setPreviewNeedsUpdate;
- (void)trackChanged:(NSNotification *)notification;
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
 * a nib for us. StatusPreferencesAdvanced.xib, which wired twenty-two outlets
 * this class no longer has, is gone from the target and from the tree along with
 * the away status window it was the last thing still describing.
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
 * One card: what the Now Playing status sends. The nib gave the same thing a
 * token field, a boxed palette of seven drag sources and a line of instructions,
 * which together took two thirds of the pane. A plain field plus a pull down does
 * the same job in one row — and unlike dragging, it can be done from the keyboard.
 *
 * A second card used to hold the two settings of the floating away status window.
 * The window is gone; an away reminder in the main Status pane took its place.
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

	/* What that format currently comes to. A row of its own rather than a detail
	 * line under the field: it shares the label column with Format, so the resolved
	 * text starts on the same line as the text it was made from, and a detail line
	 * offers no way to change its text afterwards.
	 */
	textField_preview = [self previewField];
	[form addRowWithLabel:AILocalizedString(@"Preview", "Title of the row showing what the Now Playing format currently resolves to")
		stretchingControl:textField_preview];

	popUp_insertToken = [self insertTokenPopUpButton];
	[form addTrailingAccessoryView:popUp_insertToken];

	/* Says what the format is for, and warns about the one thing the user would
	 * otherwise take for a fault: Music broadcasts only when something changes, so
	 * after a restart Adium knows nothing until the next track, pause or stop.
	 *
	 * The first touch of the card asks the running players once as well (see
	 * -askPlayersOnFirstInteraction), which fills that hole most of the time — but only
	 * most of the time: a player which is not running, one we have been denied
	 * automation of, and the whole of the time before anything has been touched still
	 * leave the preview waiting for the broadcast, and this sentence is what explains
	 * the wait when it happens.
	 */
	[form addFootnote:AILocalizedString(@"The Music Status and the %_iTunes token are replaced with this. Adium learns what is playing the next time Music starts, pauses or changes the track.",
										"Explanation below the Now Playing format field. %_iTunes is a token and must not be translated.")];

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

/*!
 * @brief The field the resolved format is written into.
 *
 * A read-only field rather than a label, for two reasons: the row's label dims with
 * the enabled state of its control, which only a control has, and a field can be
 * selected, so the result can be copied out of here.
 *
 * One line, truncated at the end, never wrapped. The row is exactly as tall as the
 * control it is handed and re-reads that height at every layout, so a preview allowed
 * to grow would shove the Insert button and the footnote up and down with every
 * keystroke. What does not fit is put in the row's tool tip instead — see
 * -updatePreview.
 *
 * The height is fixed here, once, by measuring a line of the font; nothing set later
 * changes it, because -setStringValue: does not resize a field.
 */
- (NSTextField *)previewField
{
	NSTextField *field = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];

	[field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[field setEditable:NO];
	[field setSelectable:YES];
	[field setBordered:NO];
	[field setBezeled:NO];
	[field setDrawsBackground:NO];
	[field setAlignment:NSTextAlignmentLeft];
	//-setWraps: rewrites the line break mode (clipping when NO), so the mode goes after it
	[[field cell] setWraps:NO];
	[[field cell] setScrollable:NO];
	[field setLineBreakMode:NSLineBreakByTruncatingTail];

	//Measure one line of the font, not of any particular text
	[field setStringValue:@"Xg"];
	[field sizeToFit];
	[field setFrameSize:NSMakeSize(NSWidth([field frame]), ceil(NSHeight([field frame])))];
	[field setStringValue:@""];

	return field;
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

	/* The track only changes every few minutes, so without this the preview would
	 * stand still while the music moved on. Posted by -[ESiTunesPlugin fireUpdateiTunesInfo],
	 * which already coalesces three seconds' worth of changes, so there is nothing
	 * left for us to coalesce.
	 *
	 * The pane's first observer, and it has to be taken off again by hand: -closeView
	 * is not sent when the user switches to another pane, only when the window closes
	 * (-[AIModernPreferencesWindowController windowWillClose:]), so this one lives for
	 * the whole window session and would outlive the pane without -viewWillClose.
	 */
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(trackChanged:)
												 name:Adium_iTunesTrackChangedNotification
											   object:nil];

	[self updatePreview];

	/* Deliberately no player query here; see -askPlayersOnFirstInteraction for where
	 * it went and why merely putting this view on screen is not enough to earn it.
	 */

	[super viewDidLoad];
}

- (void)viewWillClose
{
	/* The preview goes first, and the order matters more than it looks.
	 *
	 * It has nothing to flush — it only ever read — so its pending update is simply
	 * dropped; it would otherwise arrive at a pane whose controls are already nil. But
	 * the announcement below is not fire and forget: -postFormatChanged reaches
	 * -[ESiTunesPlugin currentTrackFormatDidChange:], which comes back out of
	 * -fireUpdateiTunesInfo as Adium_iTunesTrackChangedNotification on this very stack.
	 * A pane still listening at that moment would run a full preview pass in the middle
	 * of its own teardown — and on the -dealloc path it would be a message to an object
	 * already inside dealloc. So the pane is made deaf before anything that can talk
	 * back is allowed to run.
	 */
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updatePreview) object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:Adium_iTunesTrackChangedNotification object:nil];

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
	textField_preview = nil;

	/* The pane object outlives its view, so the next visit gets its own chance to ask.
	 * Not a way around the once-per-visit limit: the plugin's own guards decide whether
	 * anything is actually sent, and they hold for the whole launch.
	 */
	hasAskedPlayers = NO;

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
 * @brief Ask the players what they are playing — once, and only after the user has
 *        taken hold of this card.
 *
 * Without a query somewhere the preview is honest but useless after every launch: Music
 * broadcasts only when something changes, so until the next track the answer to "what
 * would this send?" is "we have no idea" — which is exactly what the footnote under the
 * card has to apologise for.
 *
 * The tempting place for it was -viewDidLoad, and it was there. It is not there any
 * more, for a reason that has nothing to do with the dialog being ugly. The answer does
 * not stop at the preview: it reaches -[ESiTunesPlugin setiTunesCurrentInfo:fromPlayer:],
 * which starts the three second bundle and ends in Adium_RequestImmediateDynamicContentUpdate,
 * and every account re-filters and re-publishes its status message. A user standing on the
 * Now Playing status would have had the text every contact sees change because a settings
 * window came up — and the preferences window reopens on whichever pane was last used
 * (-[AIModernPreferencesWindowController showWindowAndSelectPaneWithIdentifier:]), so ⌘,
 * alone was enough to land there. That is a side effect on the real status with no act
 * behind it, and drawing a line of text may not have one.
 *
 * Hung off a deliberate act instead: the caret going into the format field, or the Insert
 * menu being used. Both are unmistakably somebody working on what the music status sends
 * — the same standard -[ESiTunesPlugin requestPlayerQuery] holds every other caller to —
 * and both come with a card on screen which explains any automation dialog that follows.
 * The cost is that a user who only looks sees "Adium does not know yet what is playing."
 * until they touch something; the footnote says why, and looking stays free.
 *
 * Still the tamer of the two query methods: it returns at once if anything is known or if
 * an earlier attempt already came back empty-handed, sends nothing to a player which is
 * not running, and sends nothing twice within a few seconds. The flag here is only so
 * that a hundred keystrokes do not each walk into those guards.
 */
- (void)askPlayersOnFirstInteraction
{
	if (hasAskedPlayers) return;
	hasAskedPlayers = YES;

	[[self musicPlugin] requestPlayerQueryIfNothingIsKnown];
}

/*!
 * @brief The caret went into the format field.
 *
 * The first deliberate act on this card, and the moment the preview stops being
 * decoration: whoever is editing the format wants to see what it comes to.
 */
- (void)controlTextDidBeginEditing:(NSNotification *)notification
{
	[self askPlayersOnFirstInteraction];
}

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
	[self setPreviewNeedsUpdate];
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

	/* The other deliberate act on this card. Before the insertion rather than after,
	 * so the answer is on its way while the token is being put in; the preview below
	 * redraws itself when it arrives. Making the field first responder further down
	 * would reach this anyway — the flag inside makes sure it costs nothing twice.
	 */
	[self askPlayersOnFirstInteraction];

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

	/* At once, not on the timer: the user has just clicked something and is owed an
	 * answer. Any typing delay still pending would only repeat this a moment later.
	 */
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updatePreview) object:nil];
	[self updatePreview];
}

/*!
 * @brief What stands in the format field right now.
 *
 * While a field is being edited its -stringValue is still the last committed text;
 * only the field editor knows what stands there now.
 *
 * Copied, not just taken: -[NSText string] hands out the field editor's own text
 * storage, and one field editor serves the whole window. Stored as it is, the
 * preference would keep following the editor — through every further keystroke and on
 * into the next field the editor is handed to — and AIPreferenceContainer, finding the
 * very object it already holds, would take each of those keystrokes for no change at
 * all and never write the file.
 *
 * @result The format, or nil once the field is gone.
 */
- (NSString *)currentFormat
{
	if (!textField_format) return nil;

	NSText *editor = [textField_format currentEditor];

	return [[(editor ? [editor string] : [textField_format stringValue]) copy] autorelease];
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
	NSString	*format = [self currentFormat];

	if (!format) return;

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

#pragma mark The preview

/*!
 * @brief The plugin that owns the replacement, or nil if it is not loaded.
 *
 * Asked of the component loader by class name, the way BGICLogImportController and
 * SMContactListShowBehaviorPlugin reach their plugins. Not a new dependency: this
 * pane already imports ESiTunesPlugin.h for the trigger constants and already talks
 * to the plugin through Adium_CurrentTrackFormatChangedNotification. Going through
 * the content filter chain instead was considered and rejected — the chain resolves
 * %_iTunes from the plugin's cached table, which only learns about a new format half
 * a second after the last keystroke, so the preview would visibly trail the field.
 *
 * A class name is a string, so this can come back nil. Every caller has to cope; see
 * -updatePreview, which then says the same thing it says when nothing is known.
 */
- (ESiTunesPlugin *)musicPlugin
{
	return (ESiTunesPlugin *)[adium.componentLoader pluginWithClassName:@"ESiTunesPlugin"];
}

/*!
 * @brief Show what the format in the field would currently send.
 *
 * The resolution is the plugin's, not ours: -previewOfTrackFormat:state: runs the same
 * two-stage replacement over the same %_iTunes trigger the Now Playing status message
 * consists of. Rebuilding that here would be a second implementation of a thing that
 * exists, and the two would disagree the first time either changed.
 *
 * Nothing is written on the way: no preference, no notification, no status change.
 *
 * An empty result would be the one thing worse than no preview at all — it says
 * nothing about why. There are four ways to arrive at one and they call for four
 * different sentences, only the last of which is the user's to fix:
 *
 *  - nothing has ever been heard from a player (or the plugin is missing);
 *  - a player is there and stopped;
 *  - a player is there and paused;
 *  - something really is playing and the format still comes to nothing — every token
 *    in it is one this track has no value for. Spotify, for one, never answers with a
 *    composer or a genre.
 *
 * The first three are set in secondary colour so they cannot be mistaken for a result;
 * only a real preview is drawn in the ordinary label colour.
 */
- (void)updatePreview
{
	AIMusicPreviewState	 state = AIMusicPreviewNothingKnown;
	ESiTunesPlugin		*plugin = [self musicPlugin];
	NSString			*resolved = nil;
	NSString			*text = nil;
	BOOL				 isResult = NO;

	if (!textField_preview) return;

	if (plugin) resolved = [plugin previewOfTrackFormat:[self currentFormat] state:&state];

	switch (state) {
		case AIMusicPreviewPlaying:
			/* Trimmed for the decision, untrimmed for the display: what is shown stays
			 * literally what would be sent, but a result made of nothing but spaces is
			 * counted as the empty one it looks like. It is not a contrived case —
			 * "%_track %_artist" over a payload which says Playing and names neither
			 * (Apple Music radio, a shared library) comes to a single space — and drawn
			 * as a result it would be a blank line in the ordinary colour with a tool tip
			 * of spaces, which is exactly the wordless preview the sentences below exist
			 * to prevent.
			 */
			if ([[resolved stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]) {
				text = resolved;
				isResult = YES;
			} else {
				text = AILocalizedString(@"This format currently produces empty text.",
										 "Shown as the Now Playing preview when something is playing but the format resolves to nothing");
			}
			break;

		case AIMusicPreviewPaused:
			text = AILocalizedString(@"Playback is paused.",
									 "Shown as the Now Playing preview while the music player is paused");
			break;

		case AIMusicPreviewStopped:
			text = AILocalizedString(@"Nothing is playing right now.",
									 "Shown as the Now Playing preview while the music player is stopped");
			break;

		case AIMusicPreviewNothingKnown:
		default:
			text = AILocalizedString(@"Adium does not know yet what is playing.",
									 "Shown as the Now Playing preview before any music player has said anything");
			break;
	}

	[textField_preview setStringValue:text];

	/* The disabled case first, and it is not dead weight. AISettingsFormRow dims a row
	 * by following its control's enabled state, but -updateLabelColor only recolours the
	 * label, the detail and the value — never the control itself. So whoever switches
	 * the music status off and disables this field would find the text recoloured to
	 * full strength again at the next track change, since this method also runs on
	 * Adium_iTunesTrackChangedNotification, without anybody having touched the pane.
	 * One line here rather than a puzzle later.
	 */
	if (![textField_preview isEnabled]) {
		[textField_preview setTextColor:[NSColor disabledControlTextColor]];
	} else {
		[textField_preview setTextColor:(isResult ? [NSColor labelColor] : [NSColor secondaryLabelColor])];
	}

	/* The row is one line and truncates, so a long result would end in an ellipsis
	 * with nowhere to read the rest. The tool tip covers the whole row, label
	 * included. Only for a real result: the four sentences above always fit, and a
	 * tool tip repeating a line that is fully visible is noise.
	 */
	[(AISettingsFormView *)view setToolTip:(isResult ? text : nil) forRowWithControl:textField_preview];
}

/*!
 * @brief Update the preview once the typing settles.
 *
 * Its own short timer rather than -postFormatChanged's half second; PREVIEW_UPDATE_DELAY
 * explains why the two are not the same.
 */
- (void)setPreviewNeedsUpdate
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updatePreview) object:nil];
	[self performSelector:@selector(updatePreview) withObject:nil afterDelay:PREVIEW_UPDATE_DELAY];
}

/*!
 * @brief The track, the player state or the answer to a query changed.
 *
 * On the main thread, and it has to stay that way, because this touches a field: the
 * notification is posted from -[ESiTunesPlugin fireUpdateiTunesInfo], which is reached
 * either from a delayed perform or from the format notification, both of them main
 * thread. Should a third caller ever appear, it is this method that has to hop.
 */
- (void)trackChanged:(NSNotification *)notification
{
	[self updatePreview];
}

@end
