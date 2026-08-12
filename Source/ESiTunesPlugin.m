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
// Thanks to GrowlTunes from the Growl project for demonstrating how to receive notifications when
// the track changes.

#import "ESiTunesPlugin.h"
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIToolbarControllerProtocol.h>
#import "AIStatusController.h"
#import <Adium/AIMenuControllerProtocol.h>
#import <Adium/AIAccount.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIToolbarUtilities.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/MVMenuButton.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIWindowAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <Adium/AIHTMLDecoder.h>
#import <Adium/AIStatus.h>
#import <WebKit/WebKit.h>
/* For AEDeterminePermissionToAutomateTarget and the errAE… numbers: the active
 * query has to be able to tell "the user said no" apart from "nothing is playing".
 */
#import <CoreServices/CoreServices.h>

#define STRING_TRIGGERS_MENU		AILocalizedString(@"Insert Music Token", "Label used for edit and contextual menus of Music triggers")
#define STRING_TRIGGERS_TOOLBAR		AILocalizedString(@"Music","Label for the Music toolbar item. The name of Music.app.")
#define STRING_ALBUM				AILocalizedString(@"Album", "Album of current song")
#define STRING_ARTIST				AILocalizedString(@"Artist", "Artist of current song")
#define STRING_COMPOSER				AILocalizedString(@"Composer", "Composer of current song")
#define STRING_GENRE				AILocalizedString(@"Genre", "Genre of current song")
#define STRING_STATUS				AILocalizedString(@"Player State", "Playing-status of current song (e.g. paused, playing)")
#define STRING_TRACK				AILocalizedString(@"Track", "Track name of current song")
#define STRING_YEAR					AILocalizedString(@"Year", "Year of current song")
#define	STRING_STORE_URL			AILocalizedString(@"Apple Music Link", "Apple Music link for the current song")
#define STRING_MUSIC				AILocalizedString(@"Listening Status", "Listening status string (*is listening to XXX by YYY)")
#define STRING_CURRENT_TRACK		AILocalizedString(@"Music Status", "Current track information (Track - Artist)")

#pragma mark -

#define MUSIC_BUNDLE_IDENTIFIER		@"com.apple.Music"
/* The store moved to the web years ago; itms://itunes.com/link? and
 * itms://phobos.apple.com/… are both dead and answer nothing at all. */
#define MUSIC_SEARCH_URL			@"https://music.apple.com/search?term=%@"

#pragma mark -

#define	KEY_ITUNES_PLAYING			@"Playing"
#define	KEY_ITUNES_PAUSED			@"Paused"
#define	KEY_ITUNES_STOPPED			@"Stopped"

#pragma mark -

#define SPOTIFY_BUNDLE_IDENTIFIER	@"com.spotify.client"

/* Spotify answers with a URI for its own application — spotify:track:<id> — which is
 * of no use to the person on the other end of the conversation: it is not a link
 * anywhere, most clients will not even make it clickable, and without Spotify
 * installed it does nothing at all. The web address is the same identifier, and
 * that one opens for everybody.
 */
#define SPOTIFY_TRACK_URI_PREFIX	@"spotify:track:"
#define SPOTIFY_TRACK_WEB_URL		@"https://open.spotify.com/track/%@"

/* Several of the moments below can fire in quick succession — selecting the Now
 * Playing status changes the status of every account, and the filter runs over every
 * outgoing message. One Apple event round trip per five seconds is plenty: a real
 * track change arrives over the broadcast anyway, the query only has to fill the
 * hole the broadcast leaves after launch.
 */
#define PLAYER_QUERY_MINIMUM_INTERVAL	5.0

/* Both scripts answer with a list of exactly ten strings, always the same length and
 * always in the same order, empty where the player does not know something. A fixed
 * shape rather than a delimited string on purpose: track names contain commas,
 * quotes and newlines, and no separator would survive them.
 */
#define PLAYER_QUERY_FIELD_COUNT	10
enum {
	AIPlayerFieldPlayerState	= 1,
	AIPlayerFieldName			= 2,
	AIPlayerFieldArtist			= 3,
	AIPlayerFieldAlbum			= 4,
	AIPlayerFieldComposer		= 5,
	AIPlayerFieldGenre			= 6,
	AIPlayerFieldYear			= 7,
	AIPlayerFieldTotalTime		= 8,
	AIPlayerFieldStoreURL		= 9,
	AIPlayerFieldStreamTitle	= 10
};

/* Every property is fetched inside its own try. Music raises -1728 for the whole of
 * 'current track' when the track is not in the library — Apple Music radio, a shared
 * library — and individual properties can fail on their own; one bad property must
 * not cost us the other nine.
 *
 * The player state is compared against the enumerators rather than coerced with
 * 'as text': the coercion fails outright in some cases, and comparing lets the script
 * hand back Adium's own spelling, so nothing has to be translated on the way in.
 * Fast forwarding and rewinding count as playing — sound is still coming out.
 *
 * Every variable is adium-prefixed. Both applications define enormous vocabularies
 * and a short name such as "st" collides with Spotify's terminology and fails to
 * compile; "adium" appears in neither dictionary.
 *
 * Music reports 'duration' in seconds and the broadcast carries milliseconds, so it
 * is scaled here. Spotify's dictionary claims seconds but measurably answers in
 * milliseconds already, so its value is passed on untouched.
 *
 * The store URL slot stays empty for Music, and that is not an oversight. Music has
 * no scriptable store address at all: 'address' belongs to its URL track class and
 * holds the address of an internet radio stream, so asking for it would fill the
 * field precisely the wrong way round — empty for the catalogue tracks which do have
 * a store link, and carrying a raw stream address for the ones which do not. That
 * address would then go out labelled as an Apple Music link and be published to
 * every contact as the tune URL. The link the broadcast carries is the real one, and
 * -finishPlayerQueryWithResults:refusals:requestGeneration: keeps it.
 */
static NSString * const AIMusicQueryScript = @"\
tell application id \"com.apple.Music\"\n\
	set adiumState to \"Stopped\"\n\
	try\n\
		set adiumPS to player state\n\
		if adiumPS is playing or adiumPS is fast forwarding or adiumPS is rewinding then\n\
			set adiumState to \"Playing\"\n\
		else if adiumPS is paused then\n\
			set adiumState to \"Paused\"\n\
		end if\n\
	end try\n\
	set adiumName to \"\"\n\
	set adiumArtist to \"\"\n\
	set adiumAlbum to \"\"\n\
	set adiumComposer to \"\"\n\
	set adiumGenre to \"\"\n\
	set adiumYear to \"\"\n\
	set adiumTime to \"\"\n\
	set adiumURL to \"\"\n\
	set adiumStream to \"\"\n\
	if adiumState is not \"Stopped\" then\n\
		try\n\
			set adiumTrack to current track\n\
			try\n\
				set adiumName to (name of adiumTrack) as text\n\
			end try\n\
			try\n\
				set adiumArtist to (artist of adiumTrack) as text\n\
			end try\n\
			try\n\
				set adiumAlbum to (album of adiumTrack) as text\n\
			end try\n\
			try\n\
				set adiumComposer to (composer of adiumTrack) as text\n\
			end try\n\
			try\n\
				set adiumGenre to (genre of adiumTrack) as text\n\
			end try\n\
			try\n\
				set adiumYearNum to (year of adiumTrack) as integer\n\
				if adiumYearNum > 0 then set adiumYear to adiumYearNum as text\n\
			end try\n\
			try\n\
				set adiumDur to duration of adiumTrack\n\
				if adiumDur > 0 then set adiumTime to ((round (adiumDur * 1000)) as text)\n\
			end try\n\
		end try\n\
		try\n\
			set adiumStream to (current stream title) as text\n\
		end try\n\
	end if\n\
	return {adiumState, adiumName, adiumArtist, adiumAlbum, adiumComposer, adiumGenre, adiumYear, adiumTime, adiumURL, adiumStream}\n\
end tell";

/* Spotify's dictionary has no composer, no genre, no year and no stream title. Those
 * four slots stay empty rather than being filled with something plausible — an empty
 * %_genre is the truth, a guessed one is not.
 */
static NSString * const AISpotifyQueryScript = @"\
tell application id \"com.spotify.client\"\n\
	set adiumState to \"Stopped\"\n\
	try\n\
		set adiumPS to player state\n\
		if adiumPS is playing then\n\
			set adiumState to \"Playing\"\n\
		else if adiumPS is paused then\n\
			set adiumState to \"Paused\"\n\
		end if\n\
	end try\n\
	set adiumName to \"\"\n\
	set adiumArtist to \"\"\n\
	set adiumAlbum to \"\"\n\
	set adiumTime to \"\"\n\
	set adiumURL to \"\"\n\
	if adiumState is not \"Stopped\" then\n\
		try\n\
			set adiumTrack to current track\n\
			try\n\
				set adiumName to (name of adiumTrack) as text\n\
			end try\n\
			try\n\
				set adiumArtist to (artist of adiumTrack) as text\n\
			end try\n\
			try\n\
				set adiumAlbum to (album of adiumTrack) as text\n\
			end try\n\
			try\n\
				set adiumDur to (duration of adiumTrack) as integer\n\
				if adiumDur > 0 then set adiumTime to adiumDur as text\n\
			end try\n\
			try\n\
				set adiumURL to (spotify url of adiumTrack) as text\n\
			end try\n\
		end try\n\
	end if\n\
	return {adiumState, adiumName, adiumArtist, adiumAlbum, \"\", \"\", \"\", adiumTime, adiumURL, \"\"}\n\
end tell";

#pragma mark -

/*!
 * @brief @a string with the four characters an <A> tag cannot carry, escaped.
 *
 * Track and artist names are somebody else's text — "Sunday Bloody Sunday <Live>",
 * "AC/DC & Friends" — and go straight into markup which AIHTMLDecoder parses back.
 * Unescaped, the tag falls apart and the link arrives as plain text.
 */
static NSString *AIEscapedForHTML(NSString *string)
{
	NSMutableString *escaped = [[string mutableCopy] autorelease];

	//Ampersand first, or it would escape the ampersands the others introduce
	[escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange(0, [escaped length])];
	[escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange(0, [escaped length])];
	[escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:NSLiteralSearch range:NSMakeRange(0, [escaped length])];
	[escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:NSLiteralSearch range:NSMakeRange(0, [escaped length])];

	return escaped;
}

#pragma mark -
#pragma mark Asking a player directly

/*!
 * @brief Is an application with this bundle identifier running right now?
 *
 * Asked before every single Apple event, and it is not a nicety: an Apple event to an
 * application which is not running LAUNCHES it. Adium must never be the reason Music
 * or Spotify starts up.
 */
static BOOL AIPlayerIsRunning(NSString *bundleIdentifier)
{
	return ([[NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier] count] > 0);
}

/*!
 * @brief The @a index'th string of an Apple event list, or nil if it is empty
 *
 * Indices are one-based, as everywhere in Apple event lists. "Empty" and "absent" are
 * the same thing to us: the scripts return a fixed number of slots and fill the ones
 * they cannot answer with @"".
 */
static NSString *AIStringAtIndex(NSAppleEventDescriptor *list, NSInteger index)
{
	NSString *string = [[list descriptorAtIndex:index] stringValue];

	return ([string length] ? string : nil);
}

/*!
 * @brief How much a player state is worth: making sound beats holding a track beats nothing
 *
 * Used for both questions the answers raise — which player speaks for the user, and
 * whether an answer may replace what we already hold.
 */
static NSInteger AIPlayerStateRank(NSString *playerState)
{
	if ([playerState isEqualToString:KEY_ITUNES_PLAYING]) return 2;
	if ([playerState isEqualToString:KEY_ITUNES_PAUSED]) return 1;

	return 0;
}

/*!
 * @brief An https link to a Spotify track, or nil if that is not what we were given
 *
 * spotify:track:1jqAIYg9qcDpUOkHWpPcIb becomes
 * https://open.spotify.com/track/1jqAIYg9qcDpUOkHWpPcIb — the identifier is the same,
 * only the form differs. Anything that is not a plain track URI (a local file, a
 * podcast episode, a future kind of thing) yields nil rather than a guess: an empty
 * store URL costs nothing, since -insertiTMSLink then falls back to a search, while a
 * broken link would go out into somebody's conversation.
 */
static NSString *AISpotifyWebURLFromURI(NSString *uri)
{
	if (![uri hasPrefix:SPOTIFY_TRACK_URI_PREFIX]) return nil;

	NSString *trackIdentifier = [uri substringFromIndex:[SPOTIFY_TRACK_URI_PREFIX length]];

	//A remaining colon would mean this is not the simple track URI we think it is
	if (![trackIdentifier length] || ([trackIdentifier rangeOfString:@":"].location != NSNotFound)) return nil;

	return [NSString stringWithFormat:SPOTIFY_TRACK_WEB_URL, trackIdentifier];
}

/*!
 * @brief Turn a script's answer into a dictionary of the shape the broadcast has
 *
 * Shape matters: a key we invent, or an empty placeholder for something the player
 * does not know, would be one more thing the rest of the file has to think about.
 * Absent means absent, exactly as in the broadcast.
 *
 * What this shape does NOT buy is the duplicate check in -setiTunesCurrentInfo:. That
 * one compares against lastRawInfo, the broadcast payload as it arrived, and Music
 * sends Total Time and Year as numbers — the loop in -setiTunesCurrentInfo: exists to
 * turn them into strings. Everything here is a string, so an answer about a track we
 * already know can never compare equal to the broadcast that told us about it.
 * -finishPlayerQueryWithResults:refusals:requestGeneration: does that comparison
 * itself, against the stringified copy, and it has to.
 *
 * @result The track information, or nil if the answer was not usable at all.
 */
static NSDictionary *AITrackInfoFromDescriptor(NSAppleEventDescriptor *result, NSString *bundleIdentifier)
{
	//Not our ten-slot list: something else answered, or the script was changed and this was not
	if ([result numberOfItems] != PLAYER_QUERY_FIELD_COUNT) return nil;

	NSString *playerState = AIStringAtIndex(result, AIPlayerFieldPlayerState);

	/* The scripts already speak in Adium's spelling. Insisting on it is worth the two
	 * lines: CBPurpleAccount compares the player state against @"Playing" letter for
	 * letter, and Spotify's own word for it is lowercase.
	 */
	if (!([playerState isEqualToString:KEY_ITUNES_PLAYING] ||
		  [playerState isEqualToString:KEY_ITUNES_PAUSED] ||
		  [playerState isEqualToString:KEY_ITUNES_STOPPED])) {
		return nil;
	}

	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	[info setObject:playerState forKey:KEY_ITUNES_PLAYER_STATE];

	//Nothing playing: a lone player state, which is precisely what a stop broadcast carries
	if ([playerState isEqualToString:KEY_ITUNES_STOPPED]) return [[info copy] autorelease];

	/* Playing, but not a word about what: Music does this for anything outside the
	 * user's own library, where 'current track' raises -1728 while the player state
	 * happily reports playing. -setiTunesCurrentInfo: has no defence against it — it
	 * only guards against an empty payload — and the filter would send out the
	 * half-empty track line the guard there exists to prevent. A query which learned
	 * nothing must look exactly like a query which never happened.
	 *
	 * A stream title on its own is enough, though. The script fetches it outside the
	 * 'current track' block on purpose, so it can arrive when the track did not, and
	 * -setiTunesCurrentInfo: promotes it to the track name — which is how the
	 * broadcast has always been treated. Only both being empty means we learned
	 * nothing.
	 */
	NSString *name = AIStringAtIndex(result, AIPlayerFieldName);
	NSString *streamTitle = AIStringAtIndex(result, AIPlayerFieldStreamTitle);
	if (!name && !streamTitle) return nil;

	if (name) [info setObject:name forKey:KEY_ITUNES_NAME];

	NSDictionary *keysByField = [NSDictionary dictionaryWithObjectsAndKeys:
								 KEY_ITUNES_ARTIST,       [NSNumber numberWithInteger:AIPlayerFieldArtist],
								 KEY_ITUNES_ALBUM,        [NSNumber numberWithInteger:AIPlayerFieldAlbum],
								 KEY_ITUNES_COMPOSER,     [NSNumber numberWithInteger:AIPlayerFieldComposer],
								 KEY_ITUNES_GENRE,        [NSNumber numberWithInteger:AIPlayerFieldGenre],
								 KEY_ITUNES_YEAR,         [NSNumber numberWithInteger:AIPlayerFieldYear],
								 /* No trigger and no place in substitutionDict — but CBPurpleAccount
								  * reads it, so it has to be here even though nothing in a status
								  * message ever shows it.
								  */
								 KEY_ITUNES_TOTAL_TIME,   [NSNumber numberWithInteger:AIPlayerFieldTotalTime],
								 KEY_ITUNES_STREAM_TITLE, [NSNumber numberWithInteger:AIPlayerFieldStreamTitle],
								 nil];

	for (NSNumber *field in keysByField) {
		NSString *value = AIStringAtIndex(result, [field integerValue]);
		if (value) [info setObject:value forKey:[keysByField objectForKey:field]];
	}

	/* Only ever Spotify's, and only in its own scheme: the Music script leaves this slot
	 * empty on purpose (see AIMusicQueryScript), because the only address Music can be
	 * asked for is a radio stream's, not a store link.
	 */
	NSString *storeURL = AIStringAtIndex(result, AIPlayerFieldStoreURL);
	if (storeURL && [bundleIdentifier isEqualToString:SPOTIFY_BUNDLE_IDENTIFIER]) {
		storeURL = AISpotifyWebURLFromURI(storeURL);
	}
	if (storeURL) [info setObject:storeURL forKey:KEY_ITUNES_STORE_URL];

	return [[info copy] autorelease];
}

/*!
 * @brief Ask one player what it is playing. Runs on a worker thread, never on the main one.
 *
 * @param outConsentRefused Set to YES if the user has denied us automation of this player.
 * @result The track information, or nil if we learned nothing — for any reason at all.
 */
static NSDictionary *AIQueryPlayer(NSString *bundleIdentifier, NSString *scriptSource, BOOL *outConsentRefused)
{
	NSAppleEventDescriptor	*target = [NSAppleEventDescriptor descriptorWithBundleIdentifier:bundleIdentifier];

	/* Ask the system what it thinks before sending anything. With askUserIfNeeded set
	 * to false this reports the state of the permission without showing a dialog and
	 * without an event ever leaving the process — which is the only way to tell "the
	 * user said no once" from "the user has never been asked". typeWildCard for class
	 * and ID asks about automation of the target in general, which is what we want.
	 * It must not be called on the main thread; it can block for as long as a dialog
	 * is up.
	 */
	OSStatus permission = AEDeterminePermissionToAutomateTarget([target aeDesc], typeWildCard, typeWildCard, false);

	//The user has said no. Take the answer and stop bothering them for the rest of this launch.
	if (permission == errAEEventNotPermitted) {
		if (outConsentRefused) *outConsentRefused = YES;
		return nil;
	}

	/* Quit between the runningApplications check and here. Sending now would start it
	 * up again, which is the one thing this must never do.
	 */
	if (permission == procNotFound) return nil;

	/* Everything else — noErr, or errAEEventWouldRequireUserConsent because this is
	 * the first time — goes ahead, and the dialog, if there is one, appears now. Only
	 * the moments in -requestPlayerQuery get this far, and every one of them is
	 * something the user just did with the music status — picked the status, inserted
	 * a track token, or started editing the format in Advanced › Status — so the dialog
	 * has a visible cause. Somebody who never touches the feature never reaches this
	 * line; note that merely opening a preference pane is not enough, which is why
	 * -[ESStatusPreferences askPlayersOnFirstInteraction] waits for the caret
	 * or the Insert menu rather than asking from -viewDidLoad.
	 */
	/* Autoreleased into the worker's pool rather than released at the end: the caller
	 * treats an exception out of here as possible and catches it, and an unwind would
	 * walk straight past a manual release. The compiled script and its descriptor are
	 * not small, and -requestPlayerQueryIfNothingIsKnown will come back again, so a
	 * reproducible raise would leak one of these per attempt for the whole launch.
	 */
	NSDictionary			*errorInfo = nil;
	NSAppleScript			*script = [[[NSAppleScript alloc] initWithSource:scriptSource] autorelease];
	NSAppleEventDescriptor	*result = [script executeAndReturnError:&errorInfo];
	NSDictionary			*info = nil;

	if (result) {
		/* An answer came back, so it is trustworthy: every "nothing is playing" case
		 * is handled inside the script and returns normally with a player state of
		 * Stopped. It never reaches us as an error.
		 */
		info = AITrackInfoFromDescriptor(result, bundleIdentifier);

	} else {
		/* No answer. Refused consent (-1743), the player quitting mid-query (-600), a
		 * timeout (-1712), a script the running version of the application no longer
		 * understands — all of them mean the same thing to us: we learned nothing.
		 * Nothing is written and the state we had stands. Writing "stopped" here would
		 * let a refused permission wipe perfectly good broadcast information.
		 */
		NSInteger errorNumber = [[errorInfo objectForKey:NSAppleScriptErrorNumber] integerValue];

		if ((errorNumber == errAEEventNotPermitted) && outConsentRefused) *outConsentRefused = YES;
	}

	return info;
}

#pragma mark -

@interface ESiTunesPlugin ()
- (NSMenuItem *)menuItemWithTitle:(NSString *)title action:(SEL)action representedObject:(id)representedObject kind:(KGiTunesPluginMenuItemKind)itemKind;
- (void)createiTunesCurrentTrackStatusState;
- (void)updateiTunesCurrentTrackFormat;
- (NSDictionary *)phraseSubstitutionDictionaryForFormat:(NSString *)format;
- (NSMutableAttributedString *)attributedStringByReplacingMusicTriggersIn:(NSAttributedString *)inAttributedString
													  phraseSubstitutions:(NSDictionary *)phrases
														  sawMusicTrigger:(BOOL *)outSawMusicTrigger
													wantsStoreLinkSubtext:(BOOL *)outWantsStoreLinkSubtext;
- (void)createMusicToolbarItem;
- (void)createiTunesToolbarItemMenuItems:(NSMenu *)iTunesMenu;
- (NSMenu *)createTriggerMenu;
- (void)insertTriggerMenu;
- (void)insertStringIntoMessageEntryView:(NSString *)inString;
- (void)insertAttributedStringIntoMessageEntryView:(NSAttributedString *)inString;

- (void)insertFilteredString:(id)sender;
- (void)filterAndInsertString:(NSString *)inString;
- (NSAttributedString *)filterAttributedString:(NSAttributedString *)inAttributedString context:(id)context;
- (CGFloat)filterPriority;

- (void)fireUpdateiTunesInfo;
- (void)iTunesUpdate:(NSNotification *)aNotification;
- (void)currentTrackFormatDidChange:(NSNotification *)aNotification;
- (void)insertUnfilteredString:(id)sender;
- (void)insertiTMSLink;
- (void)gatherSelection;
- (void)bringMusicToFront;
- (NSURL *)musicApplicationURL;
- (NSString *)musicSearchURLForTerms:(NSString *)terms;

- (void)setiTunesCurrentInfo:(NSDictionary *)newInfo fromPlayer:(NSString *)bundleIdentifier;
- (void)finishPlayerQueryWithResults:(NSDictionary *)resultsByBundleIdentifier
							refusals:(NSSet *)refusals
				   requestGeneration:(NSUInteger)requestGeneration;
- (NSString *)bestPlayerOfResults:(NSDictionary *)resultsByBundleIdentifier;
- (void)activeStatusStateDidChange:(NSNotification *)aNotification;
@end

/*!
 * @class ESiTunesPlugin
 * @brief Filtering component to provide triggers which are replaced by information from the current Music track
 */
@implementation ESiTunesPlugin

#pragma mark -
#pragma mark Accessor Methods

/*!
 * @brief Is Music stopped?
 *
 * Never asks a player itself: -installPlugin starts this out as "stopped", and from
 * then on only something arriving at -setiTunesCurrentInfo: changes it — the
 * broadcast, or the answer to a query we asked for in -requestPlayerQuery.
 */
- (BOOL)iTunesIsStopped
{
	return iTunesIsStopped;
}

/*!
 * @brief Set if Music is stopped
 */
- (void)setiTunesIsStopped:(BOOL)yesOrNo
{
	iTunesIsStopped = yesOrNo;
}

/*!
 * @brief Is Music paused?
 */
- (BOOL)iTunesIsPaused
{
	return iTunesIsPaused;
}

/*!
 * @brief Set if Music is paused
 */
- (void)setiTunesIsPaused:(BOOL)yesOrNo
{
  iTunesIsPaused = yesOrNo;
}


/*!
 * @brief Get current track info dictionary
 */
- (NSDictionary *)iTunesCurrentInfo
{
	return iTunesCurrentInfo;
}

/*!
 * @brief Store local copy of the track information
 *
 * Retains new information, requests immediate content update and lets the plugin know what Music is doing.
 */
- (void)setiTunesCurrentInfo:(NSDictionary *)newInfo
{
	//The broadcast does not say who sent it, and does not have to; see -setiTunesCurrentInfo:fromPlayer:
	[self setiTunesCurrentInfo:newInfo fromPlayer:nil];
}

/*!
 * @brief Store track information and remember which player it describes
 *
 * @param bundleIdentifier The player we asked, or nil when this came over the broadcast.
 *
 * The source is worth keeping for one decision only: whether a later "nothing is
 * playing" may be believed. A player can only speak about itself, so a stop from
 * somewhere else says nothing about what we are holding — see
 * -finishPlayerQueryWithResults:refusals:requestGeneration:.
 */
- (void)setiTunesCurrentInfo:(NSDictionary *)newInfo fromPlayer:(NSString *)bundleIdentifier
{
	/* The broadcast is an open channel (see -installPlugin), so a sender that posts
	 * no payload at all can get here. That would leave us with neither track
	 * information nor a player state — which the filter reads as "playing" and sends
	 * out as a half-empty track line — and nothing would put it right again, since
	 * nobody ever asks Music. Fall back to what -installPlugin starts out with.
	 */
	if (![newInfo count]) {
		newInfo = [NSDictionary dictionaryWithObject:KEY_ITUNES_STOPPED forKey:KEY_ITUNES_PLAYER_STATE];
	}

	/* Anything reaching this method — a broadcast, or the answer to a query we sent
	 * ourselves — makes whatever a query still in flight is about to report older than
	 * what we know now. The query notes this count before it sends and
	 * -finishPlayerQueryWithResults:refusals:requestGeneration: throws its answer away
	 * if the count has moved on since. Both ends run on the main thread — a
	 * distributed notification is delivered on the run loop of the thread which
	 * registered for it, and that is the main thread in -installPlugin, while the
	 * query hands its answer back on the main queue — so noting and comparing cannot
	 * interleave and no lock is needed.
	 *
	 * Counted before the duplicate check below rather than after: a repeat means the
	 * broadcast is alive and saying the same thing, which is exactly the situation in
	 * which an older answer must not be let in.
	 */
	infoGeneration++;

	/* Something real has arrived, so whatever a fruitless query concluded a moment ago
	 * is out of date. Cleared before the duplicate check below rather than after: a
	 * repeat still means a player is talking to us, which is precisely what that
	 * conclusion was about.
	 */
	playerQueryLearnedNothing = NO;

	[infoSourceBundleIdentifier release];
	infoSourceBundleIdentifier = [bundleIdentifier copy];

	/* Every change arrives twice: Music broadcasts under its own name and under
	 * the one iTunes used, and we listen for both (see -installPlugin). The
	 * pointer comparison below cannot tell the copies apart — they are two
	 * separate dictionaries with equal contents — so compare the payload itself
	 * and drop the repeat before it costs a filter run over every open chat.
	 */
	if (lastRawInfo && [lastRawInfo isEqualToDictionary:newInfo]) return;

	[lastRawInfo release];
	lastRawInfo = [newInfo copy];

 	if (newInfo != iTunesCurrentInfo) {
 		[iTunesCurrentInfo release];
 		NSMutableDictionary *mutableNewInfo = [newInfo mutableCopy];

		//If we get a stream title, use that as the track name
		if ([mutableNewInfo objectForKey:KEY_ITUNES_STREAM_TITLE] && [(NSString *)[mutableNewInfo objectForKey:KEY_ITUNES_STREAM_TITLE] length])
			[mutableNewInfo setObject:[mutableNewInfo objectForKey:KEY_ITUNES_STREAM_TITLE]
							   forKey:KEY_ITUNES_NAME];

		NSEnumerator *enumerator = [newInfo keyEnumerator];
		NSString *key;
		while ((key = [enumerator nextObject])) {
			//Music sends some values as numbers rather than strings. Change these to strings for our use.
			id value = [newInfo objectForKey:key];
			if (![value isKindOfClass:[NSString class]]) {
				if ([value respondsToSelector:@selector(stringValue)]) {
					[mutableNewInfo setObject:[value stringValue]
									   forKey:key];
				} else {
					//A future version might send some other data entirely.  Drop it rather than having non-strings in the dict.
					[mutableNewInfo removeObjectForKey:key];
				}
			}
		}

		iTunesCurrentInfo = mutableNewInfo;
 		[self setiTunesIsStopped:[[iTunesCurrentInfo objectForKey:KEY_ITUNES_PLAYER_STATE]
								  isEqualToString:KEY_ITUNES_STOPPED]];
 		[self setiTunesIsPaused:[[iTunesCurrentInfo objectForKey:KEY_ITUNES_PLAYER_STATE]
								 isEqualToString:KEY_ITUNES_PAUSED]];

        //Cancel any requests we had to fire updates.
        [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(fireUpdateiTunesInfo) object:nil];
        //fire a track update in three seconds.
        [self performSelector:@selector(fireUpdateiTunesInfo) withObject:nil afterDelay:3.0];
 	}
}

- (void)fireUpdateiTunesInfo
{
	/* First, note that the track changed; code elsewhere cares, promise. */
	[[NSNotificationCenter defaultCenter] postNotificationName:Adium_iTunesTrackChangedNotification object:iTunesCurrentInfo];

	/* Next, update any dynamic content which includes our triggers, including the Now Playing status itself */
	[[NSNotificationCenter defaultCenter] postNotificationName:Adium_RequestImmediateDynamicContentUpdate object:nil];
}

#pragma mark -
#pragma mark Asking the players

/*!
 * @brief Ask the running players what they are playing, unless we already know something
 *
 * The query moments which are not deliberate acts. Two of them:
 *
 * The filter has just run over text which really does contain a music token, and
 * nothing has ever reached -setiTunesCurrentInfo:. That is the case this whole thing
 * exists for — after a launch the Now Playing status is restored from the saved
 * preference and filtered the moment an account connects, without the user clicking
 * anything, and until the next track change the line goes out empty.
 *
 * Or somebody has just started working on the format in the Status pane of the Advanced
 * preferences — the caret has gone into the field, or the Insert menu has been used —
 * and the preview there would otherwise have nothing to show after a launch. Opening
 * that pane is deliberately not one of these moments: the preferences window reopens on
 * whichever pane was last used, so it can happen without an act behind it, and the
 * answer does not stop at the preview but re-publishes every account's status message
 * through -fireUpdateiTunesInfo. See -[ESStatusPreferences askPlayersOnFirstInteraction],
 * and note that it is this method it calls and never -requestPlayerQuery.
 *
 * lastRawInfo is the only honest marker for "we have never heard anything":
 * -installPlugin fills in iTunesCurrentInfo and both flags but deliberately leaves
 * lastRawInfo alone, and nothing but a real payload ever sets it. iTunesCurrentInfo
 * would not do — its starting value is a lone "Stopped", which is exactly what a
 * genuine stop broadcast looks like.
 *
 * That marker alone would keep this going forever, though, because a query which
 * learns nothing writes nothing and so never sets it. Music playing an Apple Music
 * radio station is exactly that case — 'current track' raises -1728, the answer is
 * unusable — and this method is reached from every filter run, which for an
 * auto-refreshing status message is every thirty seconds for as long as that station
 * plays. The second marker says "we asked, and asking again would tell us the same",
 * and only a real payload clears it. The deliberate moments call -requestPlayerQuery
 * directly and are not affected: if the user picks the status again, they get a fresh
 * attempt.
 */
- (void)requestPlayerQueryIfNothingIsKnown
{
	if (![NSThread isMainThread]) {
		[self performSelectorOnMainThread:@selector(requestPlayerQueryIfNothingIsKnown) withObject:nil waitUntilDone:NO];
		return;
	}

	if (lastRawInfo || playerQueryLearnedNothing) return;

	[self requestPlayerQuery];
}

/*!
 * @brief Ask every running player what it is playing
 *
 * Only ever called from a moment where the user is visibly using the music status —
 * see -requestPlayerQueryIfNothingIsKnown, -activeStatusStateDidChange:, and the two
 * insertion actions the menus actually reach, -insertUnfilteredString: and
 * -insertiTMSLink. Somebody who never touches the feature never gets here, and so
 * never sees an automation dialog. The preference pane is held to the same standard
 * and does not get here by being shown; it waits for the format field or the Insert
 * menu, which is why its first touch calls -requestPlayerQueryIfNothingIsKnown and
 * not this.
 *
 * One outside caller earns the unconditional form all the same: the refresh button
 * next to the pane's preview. This asks whether or not anything is known, which is
 * exactly what a click on refresh means — what is known may be stale — and a click
 * on a button is as deliberate as an act gets. The header says what that costs.
 */
- (void)requestPlayerQuery
{
	if (![NSThread isMainThread]) {
		[self performSelectorOnMainThread:@selector(requestPlayerQuery) withObject:nil waitUntilDone:NO];
		return;
	}

	//-uninstallPlugin drops the queue; a trigger arriving afterwards is simply ignored
	if (!playerQueryQueue) return;

	//One at a time. A player which has stopped answering must not pile queries up behind it.
	if (playerQueryInFlight) return;

	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	if ((lastPlayerQueryTime > 0.0) && ((now - lastPlayerQueryTime) < PLAYER_QUERY_MINIMUM_INTERVAL)) return;

	/* Decided here, on the main thread, and passed to the worker as a finished list:
	 * an application which is not running must not be sent anything, because the event
	 * would launch it. There is a gap of a few milliseconds between this check and the
	 * event which no public interface closes — NSAppleScript has no "do not launch"
	 * setting — so AIQueryPlayer checks a second time through the permission call,
	 * which reports procNotFound for a target that has gone away. That narrows the
	 * window; it does not quite shut it, and pretending otherwise would be worse than
	 * saying so.
	 */
	NSMutableArray *bundleIdentifiers = [NSMutableArray array];
	for (NSString *bundleIdentifier in [NSArray arrayWithObjects:MUSIC_BUNDLE_IDENTIFIER, SPOTIFY_BUNDLE_IDENTIFIER, nil]) {
		if ([playersRefusingAutomation containsObject:bundleIdentifier]) continue;
		if (!AIPlayerIsRunning(bundleIdentifier)) continue;

		[bundleIdentifiers addObject:bundleIdentifier];
	}

	//Nothing is running: nothing is sent, and so no dialog can appear either
	if (![bundleIdentifiers count]) return;

	lastPlayerQueryTime = now;
	playerQueryInFlight = YES;

	NSUInteger	 generationAtRequest = infoGeneration;
	NSArray		*targets = [[bundleIdentifiers copy] autorelease];

	/* Held by hand rather than captured, exactly as AdiumApplescriptRunner does it:
	 * under manual retain/release a __block object variable is not retained by the
	 * block, so this pair is the only claim on the plugin, and it is given up on the
	 * main thread. An Apple event can take seconds; the plugin must not be able to go
	 * away underneath the answer.
	 */
	__block id blockSelf = [self retain];

	[playerQueryQueue addOperationWithBlock:^{
		NSAutoreleasePool	*pool = [[NSAutoreleasePool alloc] init];
		NSMutableDictionary	*results = [NSMutableDictionary dictionary];
		NSMutableSet		*refusals = [NSMutableSet set];

		for (NSString *bundleIdentifier in targets) {
			/* Swallowed rather than rethrown, and deliberately not @finally: unwinding
			 * out of here would take the worker thread with it, and the callback below
			 * has to happen whatever else does — it is what clears playerQueryInFlight.
			 * Inside the loop rather than around it, so that one player raising costs
			 * us that player's answer and not the other one's.
			 */
			@try {
				BOOL			 consentRefused = NO;
				NSString		*scriptSource = ([bundleIdentifier isEqualToString:SPOTIFY_BUNDLE_IDENTIFIER] ?
												 AISpotifyQueryScript : AIMusicQueryScript);
				NSDictionary	*info = AIQueryPlayer(bundleIdentifier, scriptSource, &consentRefused);

				if (consentRefused) [refusals addObject:bundleIdentifier];
				if (info) [results setObject:info forKey:bundleIdentifier];

				/* Someone is playing, and -bestPlayerOfResults: settles ties in favour of
				 * whoever came first — in the same order this loop walks. Nothing a later
				 * player could say would be chosen over this, so asking it would be an
				 * Apple event whose answer is thrown away, and, the first time, an
				 * automation dialog for a player we had no reason to disturb.
				 */
				if ([[info objectForKey:KEY_ITUNES_PLAYER_STATE] isEqualToString:KEY_ITUNES_PLAYING]) break;
			}
			@catch (NSException *exception) {
				//Quietly, into the log: a failed query is not something to trouble the user with
				NSLog(@"ESiTunesPlugin: asking %@ failed: %@: %@", bundleIdentifier, [exception name], [exception reason]);
			}
		}

		/* Back to the main thread. Copying this block retains results and refusals, so
		 * they outlive the pool released below.
		 */
		[[NSOperationQueue mainQueue] addOperationWithBlock:^{
			[blockSelf finishPlayerQueryWithResults:results
										   refusals:refusals
								  requestGeneration:generationAtRequest];

			[blockSelf release]; blockSelf = nil;
		}];

		[pool release];
	}];
}

/*!
 * @brief Take in what the players answered. Main thread.
 */
- (void)finishPlayerQueryWithResults:(NSDictionary *)resultsByBundleIdentifier
							refusals:(NSSet *)refusals
				   requestGeneration:(NSUInteger)requestGeneration
{
	playerQueryInFlight = NO;

	/* Noted even when the answer itself is stale or the plugin has been uninstalled: a
	 * refusal is a fact about this launch, not about this query, and remembering it is
	 * what stops us from walking into the same wall again.
	 */
	if ([refusals count]) [playersRefusingAutomation unionSet:refusals];

	/* Somebody was quicker. A track change broadcast while the Apple event was in the
	 * air, or -uninstallPlugin invalidated us; either way what we are holding is older
	 * than what is already stored, and older information must never be written over
	 * newer. See -setiTunesCurrentInfo: for the other half of this.
	 */
	if (requestGeneration != infoGeneration) {
		/* Deliberately without the marker below: something newer arrived, so this query
		 * did not fail to learn anything — it was simply overtaken.
		 */
		return;
	}

	NSString		*bestPlayer = [self bestPlayerOfResults:resultsByBundleIdentifier];
	NSDictionary	*info = (bestPlayer ? [resultsByBundleIdentifier objectForKey:bestPlayer] : nil);

	//Nothing usable came back. Indistinguishable, on purpose, from a query never sent.
	if (!info) {
		playerQueryLearnedNothing = YES;
		return;
	}

	NSString	*queriedState = [info objectForKey:KEY_ITUNES_PLAYER_STATE];
	NSString	*knownState = [iTunesCurrentInfo objectForKey:KEY_ITUNES_PLAYER_STATE];

	//Did what we are holding come from the very player that has just answered?
	BOOL sameSource = (infoSourceBundleIdentifier && [infoSourceBundleIdentifier isEqualToString:bestPlayer]);

	/* A stop — or a pause — from the wrong player. Each of them can only speak about
	 * itself, and the set we get to ask is smaller than the set that can put something
	 * in here: a player whose automation the user refused is skipped, one that is not
	 * running is skipped, Music raises for anything outside its library, and the
	 * broadcast is an open channel other players send on as well. So "nothing is playing
	 * here" and "we could not reach whoever is playing" arrive looking exactly alike,
	 * and reading it the first way is how a Spotify sitting idle in the background comes
	 * to overwrite a track Music is audibly still playing — the status flips to "is
	 * listening to nothing" while the music plays on.
	 *
	 * So an answer may say that more is going on than we thought, never that less is,
	 * unless it comes from the player we heard it from in the first place. That one
	 * taking its own words back is believed, and has to be: it is the only way we ever
	 * hear that Spotify stopped, since Spotify does not broadcast at all. For Music the
	 * broadcast reports its own stop anyway.
	 */
	if ((AIPlayerStateRank(queriedState) < AIPlayerStateRank(knownState)) && !sameSource) {
		playerQueryLearnedNothing = YES;
		return;
	}

	/* The same track we are already holding. The broadcast says more than any query can
	 * — the store link above all, which Music has no scriptable property for at all —
	 * and writing the answer over it would take those keys away: the Apple Music link
	 * in the toolbar menu would fall back to a search, and the tune URL published to
	 * every contact would go out empty. So for a track we already know the query is
	 * allowed to update the player state and to fill in what nobody has told us yet,
	 * and nothing else.
	 *
	 * The comparison is against iTunesCurrentInfo rather than lastRawInfo because the
	 * latter is the broadcast payload as it arrived, numbers and all, and an answer is
	 * strings throughout — see AITrackInfoFromDescriptor. If the result of all this is
	 * what we already had, it is not news, and news costs a filter run over every open
	 * conversation and a status push on every account.
	 */
	NSString	*knownName = [iTunesCurrentInfo objectForKey:KEY_ITUNES_NAME];
	//What the answer will end up being called: a stream title becomes the name, as it does for the broadcast
	NSString	*queriedName = ([info objectForKey:KEY_ITUNES_NAME] ?: [info objectForKey:KEY_ITUNES_STREAM_TITLE]);
	NSString	*knownArtist = [iTunesCurrentInfo objectForKey:KEY_ITUNES_ARTIST];
	NSString	*queriedArtist = [info objectForKey:KEY_ITUNES_ARTIST];

	//Two absent artists are the same artist; -isEqualToString: would say no to both of them
	BOOL		 sameArtist = ((knownArtist == queriedArtist) ||
							   (knownArtist && queriedArtist && [knownArtist isEqualToString:queriedArtist]));

	if (knownName && queriedName && [knownName isEqualToString:queriedName] && sameArtist) {
		NSMutableDictionary *merged = [[iTunesCurrentInfo mutableCopy] autorelease];

		[merged setObject:queriedState forKey:KEY_ITUNES_PLAYER_STATE];

		for (NSString *key in info) {
			if (![merged objectForKey:key]) [merged setObject:[info objectForKey:key] forKey:key];
		}

		if ([merged isEqualToDictionary:iTunesCurrentInfo]) {
			//Nothing learned, but we did reach a player and it did answer; no marker
			return;
		}

		info = merged;
	}

	[self setiTunesCurrentInfo:info fromPlayer:bestPlayer];
}

/*!
 * @brief Which of the players gets to speak for the user
 *
 * Playing beats paused beats stopped: whatever is actually making sound is what the
 * user would say they are listening to. Should both be playing at once, Music wins —
 * not by seniority, but because Music is the one which also broadcasts. Preferring it
 * keeps the query saying what the next broadcast will say anyway, whereas preferring
 * Spotify would produce a visible flip the moment Music sent its next update.
 *
 * @result The bundle identifier of the player whose answer counts, or nil if there is none.
 */
- (NSString *)bestPlayerOfResults:(NSDictionary *)resultsByBundleIdentifier
{
	NSString		*best = nil;
	NSInteger		 bestRank = -1;

	for (NSString *bundleIdentifier in [NSArray arrayWithObjects:MUSIC_BUNDLE_IDENTIFIER, SPOTIFY_BUNDLE_IDENTIFIER, nil]) {
		NSDictionary	*info = [resultsByBundleIdentifier objectForKey:bundleIdentifier];
		if (!info) continue;

		NSInteger		 rank = AIPlayerStateRank([info objectForKey:KEY_ITUNES_PLAYER_STATE]);

		//Strictly greater, so that the first of the two — Music — keeps a tie
		if (rank > bestRank) {
			bestRank = rank;
			best = bundleIdentifier;
		}
	}

	return best;
}

/*!
 * @brief The active status changed
 *
 * The clearest query moment there is: the user has just picked the Now Playing status
 * out of the status menu, which is as plain a way of saying "send what I am listening
 * to" as there is. If an automation dialog appears it does so directly after their own
 * choice, where it makes sense.
 *
 * The notification itself is no such signal — it is posted whenever any account
 * changes status, several times over during a connect — so the special status type is
 * what is actually asked about, and only the edge from off to on counts.
 */
- (void)activeStatusStateDidChange:(NSNotification *)aNotification
{
	BOOL musicStatusIsActive = ([[adium.statusController activeStatusState] specialStatusType] == AINowPlayingSpecialStatusType);

	if (musicStatusIsActive && !musicStatusWasActive) [self requestPlayerQuery];

	musicStatusWasActive = musicStatusIsActive;
}

#pragma mark -
#pragma mark Plugin Methods

/*!
 * @brief Install
 *
 * Everything below is installed whether or not Music.app is on the disk. Three
 * reasons: the Now Playing status is looked up by its uniqueStatusID at every
 * launch and the user would silently come online under a different status if it
 * were missing; the %_ triggers live in saved status messages and in the display
 * name and would go out verbatim without a filter to replace them; and the
 * broadcast is an open channel other players send on as well.
 */
- (void)installPlugin
{
	/* Music only broadcasts when something changes, so nothing at all arrives
	 * until the user next starts, pauses or changes a track. Start out as "stopped"
	 * rather than as nothing: with no player state at all the filter takes Music for
	 * playing and sends a half-empty track line. -requestPlayerQuery fills the gap
	 * later on, but only once the user shows they want it — asking here, at every
	 * launch, would put an automation dialog in front of people who never use the
	 * music status at all.
	 */
	iTunesCurrentInfo = [[NSDictionary alloc] initWithObjectsAndKeys:KEY_ITUNES_STOPPED, KEY_ITUNES_PLAYER_STATE, nil];
	[self setiTunesIsStopped:YES];
	[self setiTunesIsPaused:NO];

	/* One at a time and off the main thread. An Apple event to a player which is busy
	 * or beachballed takes as long as it takes, and AEDeterminePermissionToAutomateTarget
	 * must not be called on the main thread at all — it blocks for as long as a
	 * consent dialog is on screen.
	 */
	playerQueryQueue = [[NSOperationQueue alloc] init];
	[playerQueryQueue setName:@"im.adium.musicquery"];
	[playerQueryQueue setMaxConcurrentOperationCount:1];
	[playerQueryQueue setQualityOfService:NSQualityOfServiceUtility];

	playersRefusingAutomation = [[NSMutableSet alloc] init];

	//Perform substitutions on outgoing content
	[adium.contentController registerContentFilter:self
											ofType:AIFilterContent
										 direction:AIFilterOutgoing];

	/* Both names. Music posts under its own and, for everything ever written for
	 * iTunes, under the old one as well; third-party players only know the old one.
	 * The duplicate that follows from listening for both costs nothing:
	 * -setiTunesCurrentInfo: drops a payload it has already seen.
	 */
	for (NSString *notificationName in [NSArray arrayWithObjects:@"com.apple.Music.playerInfo", @"com.apple.iTunes.playerInfo", nil]) {
		[[NSDistributedNotificationCenter defaultCenter] addObserver:self
														   selector:@selector(iTunesUpdate:)
															   name:notificationName
															 object:nil];
	}

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(currentTrackFormatDidChange:)
												 name:Adium_CurrentTrackFormatChangedNotification
											   object:nil];

	//So we can notice the Now Playing status being selected; see -activeStatusStateDidChange:
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(activeStatusStateDidChange:)
												 name:AIStatusActiveStateChangedNotification
											   object:nil];

	/* The values are the keys Music puts into the broadcast; they are not ours to
	 * choose. CBPurpleAccount reads six of them through the same macros.
	 */
	substitutionDict = [[NSDictionary alloc] initWithObjectsAndKeys:
		KEY_ITUNES_ALBUM, TRIGGER_ALBUM,
		KEY_ITUNES_ARTIST, TRIGGER_ARTIST,
		KEY_ITUNES_COMPOSER, TRIGGER_COMPOSER,
		KEY_ITUNES_GENRE, TRIGGER_GENRE,
		KEY_ITUNES_PLAYER_STATE, TRIGGER_STATUS,
		KEY_ITUNES_NAME, TRIGGER_TRACK,
		KEY_ITUNES_YEAR, TRIGGER_YEAR,
		KEY_ITUNES_STORE_URL, TRIGGER_STORE_URL,
		nil];

	//Update the format for the current track
	[self updateiTunesCurrentTrackFormat];

	//Create the current track status item
	[self createiTunesCurrentTrackStatusState];

	//Create the toolbar item
	[self createMusicToolbarItem];

	//Create the Edit > Insert and contextual menus
	[self insertTriggerMenu];
}

/*!
 * @brief Uninstall
 */
- (void)uninstallPlugin
{
	[adium.contentController unregisterContentFilter:self];

	//Both centres: -installPlugin registered with each of them
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	/* A query still in the air cannot be recalled — the Apple event is with the other
	 * application — but its answer can be made worthless. Moving the count on is
	 * exactly the invalidation -finishPlayerQueryWithResults:refusals:requestGeneration:
	 * already checks for, so nothing it brings back will be written. Dropping the queue
	 * stops any further query from starting; the operation which is running holds the
	 * queue alive until it is finished with it, and the plugin itself is held by the
	 * retain in -requestPlayerQuery.
	 */
	infoGeneration++;
	[playerQueryQueue release]; playerQueryQueue = nil;
}

#pragma mark -
#pragma mark Status item creation

/*!
 * @brief Create an available status state
 *
 * Create a Status which uses the current track data as it's message
 */
- (void)createiTunesCurrentTrackStatusState
{
	//create a Now Playing status of state "Available" with default available status settings
	AIStatus		   *currentiTunesStatusState = [[AIStatus statusOfType:AIAvailableStatusType] retain];
	
	//set status attributes
	NSAttributedString *trackAndArtist = [NSAttributedString stringWithString:TRIGGER_CURRENT_TRACK];
	[currentiTunesStatusState setStatusMessage:trackAndArtist];
	[currentiTunesStatusState setTitle:STRING_CURRENT_TRACK];
	[currentiTunesStatusState setMutabilityType:AISecondaryLockedStatusState];
	[currentiTunesStatusState setUniqueStatusID:[NSNumber numberWithInteger:ITUNES_STATUS_ID]];
	[currentiTunesStatusState setSpecialStatusType:AINowPlayingSpecialStatusType];

	//give it to the AIStatusController
	[adium.statusController addStatusState:currentiTunesStatusState];
	[currentiTunesStatusState release];
}

/*!
 * @brief The first-stage replacement table for a given track format.
 *
 * Stage one of the filter turns %_music and %_iTunes into strings made of the simple
 * triggers; stage two turns those into values. This builds stage one's table, and it
 * takes the format rather than reading it so that the preview in the preference pane
 * can ask about a format which is being typed and has not been stored yet. One
 * implementation, two callers: a table built anywhere else would answer differently
 * from the filter the moment either side was touched.
 *
 * Reads nothing and writes nothing; the returned dictionary is autoreleased and the
 * caller owns nothing.
 */
- (NSDictionary *)phraseSubstitutionDictionaryForFormat:(NSString *)format
{
	NSDictionary	*slashMusicDict = nil;
	NSDictionary	*conditionalArtistTrackDict = nil;

	slashMusicDict = [NSDictionary dictionaryWithObjectsAndKeys:
					  [NSString stringWithFormat:AILocalizedString(@"*is listening to %@ by %@*","Phrase sent in response to %_music.  The first %%@ is the track; the second %%@ is the artist."), TRIGGER_TRACK, TRIGGER_ARTIST],
					  KEY_ITUNES_PLAYING,
					  AILocalizedString(@"*is listening to nothing*","Phrase sent in response to %_music when nothing is playing."),
					  KEY_ITUNES_STOPPED,
					  nil];

	/* An empty format is not hardcoded away in the preference (see
	 * -updateiTunesCurrentTrackFormat) but filled in here, so that a default
	 * installation does not have its format broken when the locale switches — the
	 * format specifiers are themselves localized.
	 */
	if (![format length]) {
		format = [NSString stringWithFormat:@"%@ - %@", TRIGGER_TRACK, TRIGGER_ARTIST];
	}

	conditionalArtistTrackDict = [NSDictionary dictionaryWithObjectsAndKeys:
								  format,
								  KEY_ITUNES_PLAYING,
								  @"",
								  KEY_ITUNES_STOPPED,
								  nil];

	return [NSDictionary dictionaryWithObjectsAndKeys:
			slashMusicDict,
			TRIGGER_MUSIC,
			conditionalArtistTrackDict,
			TRIGGER_CURRENT_TRACK,
			nil];
}

- (void)updateiTunesCurrentTrackFormat
{
	NSString	*currentITunesTrackFormat = nil;

	/* Provide flexibility with the %_iTunes substitution. By default, just store @"" for this key.
	 * But still not hardcoded to a particular format.
	 */
	currentITunesTrackFormat = [adium.preferenceController preferenceForKey:KEY_ITUNES_TRACK_FORMAT
																	  group:PREF_GROUP_STATUS_PREFERENCES];
	if (!currentITunesTrackFormat) {
		[adium.preferenceController setPreference:@""
										   forKey:KEY_ITUNES_TRACK_FORMAT
											group:PREF_GROUP_STATUS_PREFERENCES];
		currentITunesTrackFormat = @"";
	}

	/* The preference pane now writes while the user types, so this runs far more
	 * often than once per launch: without the release the old dictionary leaked
	 * on every rebuild.
	 *
	 * Built first, swapped in, and only then released — never released first. The
	 * ivar is read without a lock by -filterAttributedString:context:, which may run
	 * off the main thread (see the comment there), and it hands the pointer on to
	 * -attributedStringByReplacingMusicTriggersIn:… for the whole two-stage
	 * replacement. Releasing before building would leave the ivar pointing at freed
	 * memory for the length of -phraseSubstitutionDictionaryForFormat: — two bundle
	 * lookups and three dictionaries — on every burst of typing. In this order the
	 * ivar only ever holds a live object, and the one being let go of is held by the
	 * local until the last reader has moved on.
	 */
	NSDictionary	*newPhraseSubstitutionDict = [[self phraseSubstitutionDictionaryForFormat:currentITunesTrackFormat] retain];
	NSDictionary	*oldPhraseSubstitutionDict = phraseSubstitutionDict;

	phraseSubstitutionDict = newPhraseSubstitutionDict;
	[oldPhraseSubstitutionDict release];

    [self fireUpdateiTunesInfo];
}

#pragma mark -
#pragma mark Filter Protocol methods

/*!
 * @brief Filter and insert the current song's display into message entry
 *
 * Toolbar method. Take the trigger and filter it with real values
 *
 * @param sender An NSMenuItem whose representedObject is the appropriate trigger to filter
 */
- (void)insertFilteredString:(id)sender
{
	[self filterAndInsertString:[sender representedObject]];	
}

/*!
 * @brief The two-stage replacement itself, without any of the filter's consequences.
 *
 * Split out of -filterAttributedString:context: so that the preview in the preference
 * pane can go through this very code rather than through an imitation of it — see
 * -previewOfTrackFormat:state:. The phrase table is a parameter for the same reason:
 * the preview asks about a format the user is still typing, which is not the one in
 * phraseSubstitutionDict yet.
 *
 * Everything that is not replacement stays with the caller — the player query, the
 * store link subtext — because those are things the filter may do and the preview may
 * not.
 *
 * @param outSawMusicTrigger Set to YES if any music trigger was found at all; may be NULL.
 * @param outWantsStoreLinkSubtext Set to YES if the Now Playing trigger was replaced while
 *        something was playing, which is when the store link is worth carrying; may be NULL.
 * @result The replaced string, autoreleased, or nil if there was nothing to replace —
 *         the caller then keeps the string it already had rather than a copy of it.
 */
- (NSMutableAttributedString *)attributedStringByReplacingMusicTriggersIn:(NSAttributedString *)inAttributedString
													  phraseSubstitutions:(NSDictionary *)phrases
														  sawMusicTrigger:(BOOL *)outSawMusicTrigger
													wantsStoreLinkSubtext:(BOOL *)outWantsStoreLinkSubtext
{
    NSMutableAttributedString	*filteredMessage = nil;
	NSString					*stringMessage;

	if (outSawMusicTrigger) *outSawMusicTrigger = NO;
	if (outWantsStoreLinkSubtext) *outWantsStoreLinkSubtext = NO;

	//get the attributed string as a regular string so we can do string processing
	if ((stringMessage = [inAttributedString string])) {
		NSEnumerator	*enumerator;
		NSString		*trigger;

		/* Replace the phrases with the string containing the triggers.
		 * For example, /music will become *is listening to %_track by %_artist*.
		 * This will then become the actual track information in the next while().
		 */
		enumerator = [phrases keyEnumerator];

		while ((trigger = [enumerator nextObject])) {
			//search for phrase in the string that needs to be filtered
			if (([stringMessage rangeOfString:trigger options:(NSLiteralSearch | NSCaseInsensitiveSearch)].location != NSNotFound)) {
				NSDictionary	*replacementDict;
				NSString		*replacement;

				if (outSawMusicTrigger) *outSawMusicTrigger = YES;

				//get the format for the current trigger
				replacementDict = [phrases objectForKey:trigger];

				//replacement of phrase should reflect the player state
				if (![self iTunesIsStopped] && ![self iTunesIsPaused]) {
					replacement = [replacementDict objectForKey:KEY_ITUNES_PLAYING];

					/* If the trigger is the trigger used for the Now Playing status, we'll want to add a subtext of the store link
					 * so account code can send it out later on.
					 */
					if ([trigger isEqualToString:TRIGGER_CURRENT_TRACK]) {
						if (outWantsStoreLinkSubtext) *outWantsStoreLinkSubtext = YES;
					}

				} else {
					replacement = [replacementDict objectForKey:KEY_ITUNES_STOPPED];
				}

				//create a attributedstring if it hasn't been created already
				if (!filteredMessage) filteredMessage = [[inAttributedString mutableCopy] autorelease];

				//Perform the replacement
				[filteredMessage replaceOccurrencesOfString:trigger
												 withString:replacement
													options:(NSLiteralSearch | NSCaseInsensitiveSearch)
													  range:NSMakeRange(0, [filteredMessage length])];
			}
		}

		if (filteredMessage) {
			//Update our string for the simple trigger replacement process so we can replace the %_ tokens
			stringMessage = [filteredMessage string];
		}

		//Substitute simple triggers as appropriate
		enumerator = [substitutionDict keyEnumerator];
		while ((trigger = [enumerator nextObject])) {

			//Find if the current trigger is in the string
			if (([stringMessage rangeOfString:trigger options:(NSLiteralSearch | NSCaseInsensitiveSearch)].location != NSNotFound)) {
				NSString *replacement = [iTunesCurrentInfo objectForKey:[substitutionDict objectForKey:trigger]];

				if (outSawMusicTrigger) *outSawMusicTrigger = YES;

				if (replacement == nil) {
					//If no replacement is found, replace the trigger with an empty string
					replacement = @"";
				}

				//if a mutable attributed string for the string to be filtered doesn't exist, create it.
				if (filteredMessage == nil) {
					filteredMessage = [[inAttributedString mutableCopy] autorelease];
				}

				//Replace the current trigger with the value we found above
				[filteredMessage replaceOccurrencesOfString:trigger
												 withString:replacement
													options:(NSLiteralSearch | NSCaseInsensitiveSearch)
													  range:NSMakeRange(0, [filteredMessage length])];
			}
		}
	}

	return filteredMessage;
}

/*!
 * @brief Filter messages for keywords to replace
 *
 * Replace any track triggers with the appropriate information
 */
- (NSAttributedString *)filterAttributedString:(NSAttributedString *)inAttributedString context:(id)context
{
	BOOL						 addStoreLinkAsSubtext = NO;
	BOOL						 sawMusicTrigger = NO;
	NSMutableAttributedString	*filteredMessage = [self attributedStringByReplacingMusicTriggersIn:inAttributedString
																			   phraseSubstitutions:phraseSubstitutionDict
																				   sawMusicTrigger:&sawMusicTrigger
																			 wantsStoreLinkSubtext:&addStoreLinkAsSubtext];

	/* A music token really was in the text and we have never heard a thing. This
	 * filter run is already lost — it is a plain AIContentFilter and runs
	 * synchronously, so it cannot wait for an Apple event — but the answer puts
	 * itself right through -setiTunesCurrentInfo: and the update it triggers, and
	 * the user sees the empty line only once.
	 *
	 * Filtering can happen off the main thread (see AdiumContentFiltering), so the
	 * two reads here are only a cheap way of not bothering; the binding decision is
	 * taken again on the main thread, inside -requestPlayerQueryIfNothingIsKnown,
	 * which is also where the second of them is explained.
	 */
	if (sawMusicTrigger && !lastRawInfo && !playerQueryLearnedNothing) [self requestPlayerQueryIfNothingIsKnown];

	if (addStoreLinkAsSubtext && filteredMessage) {
		NSString *storeLinkForSubtext = [iTunesCurrentInfo objectForKey:[substitutionDict objectForKey:TRIGGER_STORE_URL]];
		if (storeLinkForSubtext) {
			[filteredMessage addAttribute:@"AIMessageSubtext"
									value:storeLinkForSubtext
									range:NSMakeRange(0, [filteredMessage length])];
		}
	}

	//Give back the processed string
	return (filteredMessage ? filteredMessage : inAttributedString);
}

/*!
 * @brief What the Now Playing status would send with @a format; see the header.
 */
- (NSString *)previewOfTrackFormat:(NSString *)format state:(AIMusicPreviewState *)outState
{
	NSAttributedString	*trigger;
	NSAttributedString	*resolved;

	if (outState) {
		/* lastRawInfo before the two flags, and that order is the whole point:
		 * -installPlugin sets iTunesIsStopped without anybody having said anything,
		 * so the flags cannot tell "stopped" from "we have never heard a word". Only
		 * a real payload ever sets lastRawInfo.
		 */
		if (!lastRawInfo)			*outState = AIMusicPreviewNothingKnown;
		else if (iTunesIsStopped)	*outState = AIMusicPreviewStopped;
		else if (iTunesIsPaused)	*outState = AIMusicPreviewPaused;
		else						*outState = AIMusicPreviewPlaying;
	}

	/* Exactly the string the Now Playing status carries as its message — see
	 * -createiTunesCurrentTrackStatusState — so the question being asked is literally
	 * "what becomes of %_iTunes?" and not some approximation of it.
	 */
	trigger = [NSAttributedString stringWithString:TRIGGER_CURRENT_TRACK];
	resolved = [self attributedStringByReplacingMusicTriggersIn:trigger
											phraseSubstitutions:[self phraseSubstitutionDictionaryForFormat:format]
												sawMusicTrigger:NULL
										  wantsStoreLinkSubtext:NULL];

	/* nil means nothing was replaced, which for this input cannot happen; be honest
	 * about it anyway.
	 *
	 * Copied, not handed straight out: -[NSMutableAttributedString string] gives back
	 * the receiver's own backing store rather than a snapshot of it. The header promises
	 * callers "the resolved text", so what they get has to be a string that is theirs
	 * and cannot change underneath them.
	 */
	return [[[(resolved ?: trigger) string] copy] autorelease];
}

/*!
 * @brief Filter priority
 *
 * Filter at default priority
 */
- (CGFloat)filterPriority
{
	return DEFAULT_FILTER_PRIORITY;
}

#pragma mark -
#pragma mark Notification Selector

/*!
 * @brief The song changed
 *
 * The accessor method caches the information and then requst an immediate update to dynamic content
 */
- (void)iTunesUpdate:(NSNotification *)aNotification
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	NSDictionary *newInfo = [aNotification userInfo];
	[self setiTunesCurrentInfo:newInfo];
	
	[pool release];
}

/*!
 * @brief The CurrentTrack format changed
 */
- (void)currentTrackFormatDidChange:(NSNotification *)aNotification
{
	[self updateiTunesCurrentTrackFormat];
}


#pragma mark -
#pragma mark Toolbar Item Methods

/*!
 * @brief Create the toolbar item
 *
 * Create toolbar item and it's menu
 */
- (void)createMusicToolbarItem
{
	NSMenu		  *menu = [[NSMenu alloc] init];
	MVMenuButton  *button = [[MVMenuButton alloc] initWithFrame:NSMakeRect(0,0,32,32)];

	/* A symbol rather than Music.app's own icon, which is what the item used to
	 * show: the item is registered whether or not Music is installed (see
	 * -installPlugin), and -iconForFile: on a missing application yields the
	 * generic document icon — an empty-looking hole in the toolbar. A symbol is
	 * always there and follows the toolbar's own tint.
	 *
	 * MVMenuButton only ever scales an image *down* to its control size, so a
	 * symbol left at its natural ~16 points would sit lost in a 32 point item;
	 * ask for one drawn at 22.
	 */
	NSImage *icon = [NSImage imageWithSystemSymbolName:@"music.note" accessibilityDescription:STRING_TRIGGERS_TOOLBAR];
	if (icon) {
		icon = [icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:22.0
																								  weight:NSFontWeightRegular]];
		[icon setTemplate:YES];
		[button setImage:icon];
	}

	[self createiTunesToolbarItemMenuItems:menu];

	NSToolbarItem * iTunesItem = [AIToolbarUtilities toolbarItemWithIdentifier:KEY_TRIGGERS_TOOLBAR
																		 label:STRING_TRIGGERS_TOOLBAR
																  paletteLabel:STRING_TRIGGERS_TOOLBAR
																	   toolTip:AILocalizedString(@"Insert current Music track information.","Tool tip of the Music toolbar item.")
																		target:self
															   settingSelector:@selector(setView:)
																   itemContent:button
																		action:NULL
																		  menu:nil];
	//configure the toolbar and button for use
	[[iTunesItem view] setMenu:menu];
	[iTunesItem setMinSize:NSMakeSize(32,32)];
	[iTunesItem setMaxSize:NSMakeSize(32,32)];
	[button setToolbarItem:iTunesItem];
	
	//Add menu to toolbar item (for text mode)
	NSMenuItem	*mItem = [[[NSMenuItem alloc] init] autorelease];
	[mItem setSubmenu:menu];
	[mItem setTitle:STRING_TRIGGERS_TOOLBAR];
	[iTunesItem setMenuFormRepresentation:mItem];
	
	//give it to adium to use
	[adium.toolbarController registerToolbarItem:iTunesItem forToolbarType:@"TextEntry"];
	[button release];
	[menu release];
}

/*!
 * @brief Create the toolbar item's menu
 *
 * Populate a menu with menu items that will insert appropriate values of the currently playing song.
 */

- (void)createiTunesToolbarItemMenuItems:(NSMenu *)iTunesMenu
{


	//submenu of actions related to a track
	NSMenuItem *submenuRoot = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Track Information","Submenu for the Music toolbar item menu for inserting current track information.")
														 action:NULL
												  keyEquivalent:@""];
	[iTunesMenu addItem:submenuRoot];
	[iTunesMenu setSubmenu:[self createTriggerMenu] forItem:submenuRoot];
	[iTunesMenu addItem:[NSMenuItem separatorItem]];

	//Searches the selected text in the store; the ellipsis promises the browser opening
	[iTunesMenu addItem:[self menuItemWithTitle:[AILocalizedString(@"Search Selection in Music Store","iTunes toolbar menu item title to search selection in iTMS.") stringByAppendingEllipsis]
										 action:@selector(gatherSelection)
							  representedObject:nil
										   kind:RESPONDER_IS_WEBVIEW]];
	[iTunesMenu addItem:[NSMenuItem separatorItem]];

	/* No ellipsis: the item switches applications, it does not ask anything first.
	 * It is the only item here that needs Music to actually be installed.
	 */
	[iTunesMenu addItem:[self menuItemWithTitle:AILocalizedString(@"Bring Music to Front","Music toolbar menu item title to make Music the frontmost app.")
										 action:@selector(bringMusicToFront)
							  representedObject:nil
										   kind:ENABLED_IF_MUSIC_INSTALLED]];


	[submenuRoot release];
}

/*!
 * @brief Create a menu item
 *
 * create a menu item targeting this plugin. Determine if it should disable itself when firstResponder != [textView class].
 */
- (NSMenuItem *)menuItemWithTitle:(NSString *)title action:(SEL)action representedObject:(id)representedObject kind:(KGiTunesPluginMenuItemKind)itemKind
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
	[item setTarget:self];
	[item setTag:itemKind];
	[item setRepresentedObject:representedObject];
	[item setEnabled:YES];

	return [item autorelease];
}

#pragma mark -
#pragma mark Toolbar Item actions

/*!
 * @brief An Apple Music search for @a terms, or nil for nothing worth searching
 *
 * URLQueryAllowedCharacterSet leaves the sub-delimiters alone, so an artist like
 * "Simon & Garfunkel" would end the query parameter halfway through the name.
 */
- (NSString *)musicSearchURLForTerms:(NSString *)terms
{
	NSMutableCharacterSet	*allowed = [[[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy] autorelease];

	terms = [terms stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (![terms length]) return nil;

	[allowed removeCharactersInString:@"&+=?#"];

	return [NSString stringWithFormat:MUSIC_SEARCH_URL, [terms stringByAddingPercentEncodingWithAllowedCharacters:allowed]];
}

/*!
 * @brief Insert a link to the current song
 *
 * Music sends a store URL along with everything from its own catalogue. A local
 * file or a stream has none, so all that is left is a search for what we do know
 * about it.
 */
- (void)insertiTMSLink
{
	/* Worth asking here more than anywhere else: without track information this method
	 * has nothing to do but beep. The answer comes too late for this click, but a
	 * second attempt then works instead of beeping again.
	 */
	[self requestPlayerQuery];

	NSString	*artist = [iTunesCurrentInfo objectForKey:[substitutionDict objectForKey:TRIGGER_ARTIST]];
	NSString	*trackName = [iTunesCurrentInfo objectForKey:[substitutionDict objectForKey:TRIGGER_TRACK]];
	NSString	*storeURL = [iTunesCurrentInfo objectForKey:[substitutionDict objectForKey:TRIGGER_STORE_URL]];
	NSString	*url = nil;

	if ([storeURL length]) {
		url = storeURL;

	} else if (![self iTunesIsStopped] && ![self iTunesIsPaused]) {
		/* Was "|| !paused", which is only false for a player both stopped and
		 * paused at once, i.e. never: the branch ran even with nothing playing.
		 */
		url = [self musicSearchURLForTerms:[[NSArray arrayWithObjects:(trackName ?: @""), (artist ?: @""), nil]
											componentsJoinedByString:@" "]];
	}

	if (!url) {
		//Nothing is playing, or nothing about it we could even search for
		NSBeep();
		return;
	}

	//Whatever of the two we have; the dash only when both are there
	NSMutableArray *labelParts = [NSMutableArray array];
	if ([trackName length]) [labelParts addObject:trackName];
	if ([artist length]) [labelParts addObject:artist];

	NSString			*urlLabel = ([labelParts count] ? [labelParts componentsJoinedByString:@" - "] : url);
	NSAttributedString	*attributedLink = [[NSAttributedString alloc] initWithAttributedString:
										   [AIHTMLDecoder decodeHTML:[NSString stringWithFormat:@"<A HREF=\"%@\">%@</A>",
																	  url, AIEscapedForHTML(urlLabel)]]];

	[self insertAttributedStringIntoMessageEntryView:attributedLink];
	[attributedLink release];
}

/*!
 * @brief Search Apple Music for the given text
 *
 * Build the necessary url and execute it
 */
- (void)searchMusicStoreWithSelection:(NSString *)selectedText
{
	NSString *url = [self musicSearchURLForTerms:(selectedText ?: @"")];

	if (url) [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
}


/*!
 * @brief Get the selection from the webmessageview
 *
 * Get the selected text in the messageview and search Apple Music for it
 */
- (void)gatherSelection
{
	id responder = [[[NSApplication sharedApplication] keyWindow] firstResponder];

	if ([responder respondsToSelector:@selector(selectedString)]) {
		[self searchMusicStoreWithSelection:[responder selectedString]];
	}
}

/*!
 * @brief Where Music.app is, or nil when it is not installed
 *
 * Asked for at every use rather than looked up once at launch: Music can be
 * removed, moved or installed while Adium runs, and -validateMenuItem: has to
 * tell the truth about it every time the menu opens.
 */
- (NSURL *)musicApplicationURL
{
	return [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:MUSIC_BUNDLE_IDENTIFIER];
}

/*!
 * @brief Bring Music to the foreground
 */
- (void)bringMusicToFront
{
	NSURL *applicationURL = [self musicApplicationURL];

	//-validateMenuItem: disables the item without Music, but a key equivalent could still get here
	if (!applicationURL) {
		NSBeep();
		return;
	}

	[[NSWorkspace sharedWorkspace] openApplicationAtURL:applicationURL
										  configuration:[NSWorkspaceOpenConfiguration configuration]
									  completionHandler:nil];
}

#pragma mark -
#pragma mark Edit/Contextual menu item actions

/*!
 * @brief Insert triggers into message entry
 *
 * Used in the "Edit" and contextual menus.
 * @param sender An NSMenuItem whose representedObject is the appropriate trigger to insert
 */
- (void)insertUnfilteredString:(id)sender
{
	/* The token goes into the text unfiltered, so this insertion needs nothing from
	 * the players — but the user has just said, with a menu, that they want their
	 * music in a message. Asking now means the information is there by the time the
	 * message is sent, and any dialog appears while they are still looking at the menu
	 * they used.
	 */
	[self requestPlayerQuery];

	[self insertStringIntoMessageEntryView:[sender representedObject]];
}

#pragma mark -
#pragma mark Text Insertion methods

/*!
 * @brief Filter and Insert plain string
 *
 * Converts the string to an attributed string and filters it, then inserting it into the message entry view
 * Used by all the toolbar item actions.
 */
- (void)filterAndInsertString:(NSString *)inString
{
	/* Nothing calls this, or -insertFilteredString: above it: every item the toolbar
	 * menu and the Edit menu build inserts the token itself, through
	 * -insertUnfilteredString:, or is the store link item. Left as it stands because it
	 * is upstream's, but deliberately without the player query the two live insertion
	 * paths do — a query belongs where a user action really reaches it, and this is not
	 * one of those places.
	 */
	id responder = [[[NSApplication sharedApplication] keyWindow] firstResponder];
	if (responder && [responder isKindOfClass:[NSTextView class]]) {
		NSAttributedString *attributedResult = [[NSAttributedString alloc] initWithString:inString
																			   attributes:[(NSTextView *)responder typingAttributes]];
		NSAttributedString *filteredString = [self filterAttributedString:attributedResult context:nil];
		
		if (filteredString && [filteredString length] > 0) {
			[self insertAttributedStringIntoMessageEntryView:filteredString];
		}
		
		[attributedResult release];
	}
}

/*!
 * @brief Insert raw string into message view
 *
 * Converts the string to an attributed string and inserts it into the message entry view.
 * Used with the insertUnfiltered... methods which are used by edit and contextual menus.
 */
- (void)insertStringIntoMessageEntryView:(NSString *)inString
{
	id responder = [[[NSApplication sharedApplication] keyWindow] firstResponder];
	if (responder && [responder isKindOfClass:[NSTextView class]]) {
		NSAttributedString *attributedResult = [[NSAttributedString alloc] initWithString:inString 
																			   attributes:[(NSTextView *)responder typingAttributes]];
		[self insertAttributedStringIntoMessageEntryView:attributedResult];
		[attributedResult release];
	}
}

/*!
 * @brief Insert attributed string into message view
 *
 * Inserts an attributed string it into the message entry view.
 * Don't check to see if the responder is of class NSTextView because the validateMenuItem method checks.
 */

- (void)insertAttributedStringIntoMessageEntryView:(NSAttributedString *)inString
{
	NSResponder *textView = [[[NSApplication sharedApplication] keyWindow] firstResponder];
	[textView insertText:inString];
	
	if (![inString length]) {
		NSBeep();
	}
}

#pragma mark -
#pragma mark Edit/Contextual menu methods

/*!
 * @brief Create Edit and Contextual menus of the track triggers
 *
 * Build the menus for the track triggers that autodisables when a first responder isn't a textView
 */

- (NSMenu *)createTriggerMenu
{
	NSMenu *triggersMenu = [[NSMenu alloc] init];

	[triggersMenu addItem:[self menuItemWithTitle:STRING_CURRENT_TRACK 
										   action:@selector(insertUnfilteredString:)
								representedObject:TRIGGER_CURRENT_TRACK
											 kind:AUTODISABLES]];
	[triggersMenu addItem:[self menuItemWithTitle:STRING_MUSIC
										   action:@selector(insertUnfilteredString:)
								representedObject:TRIGGER_MUSIC
											 kind:AUTODISABLES]];

	[triggersMenu addItem:[NSMenuItem separatorItem]];
	
	[triggersMenu addItem:[self menuItemWithTitle:STRING_TRACK
										   action:@selector(insertUnfilteredString:)
								representedObject:TRIGGER_TRACK
											 kind:AUTODISABLES]];
	[triggersMenu addItem:[self menuItemWithTitle:STRING_ARTIST
										   action:@selector(insertUnfilteredString:)
								representedObject:TRIGGER_ARTIST
											 kind:AUTODISABLES]];
	[triggersMenu addItem:[self menuItemWithTitle:STRING_COMPOSER
										   action:@selector(insertUnfilteredString:)
								representedObject:TRIGGER_COMPOSER
											 kind:AUTODISABLES]];
	[triggersMenu addItem:[self menuItemWithTitle:STRING_ALBUM
										   action:@selector(insertUnfilteredString:)
								representedObject:TRIGGER_ALBUM
											 kind:AUTODISABLES]];
	[triggersMenu addItem:[self menuItemWithTitle:STRING_GENRE
										   action:@selector(insertUnfilteredString:)
								representedObject:TRIGGER_GENRE
											 kind:AUTODISABLES]];
	[triggersMenu addItem:[self menuItemWithTitle:STRING_YEAR
										   action:@selector(insertUnfilteredString:)
								representedObject:TRIGGER_YEAR
											 kind:AUTODISABLES]];
	[triggersMenu addItem:[self menuItemWithTitle:STRING_STATUS
										   action:@selector(insertUnfilteredString:)
								representedObject:TRIGGER_STATUS
											 kind:AUTODISABLES]];
	[triggersMenu addItem:[self menuItemWithTitle:STRING_STORE_URL
										   action:@selector(insertiTMSLink)
								representedObject:TRIGGER_STORE_URL
											 kind:AUTODISABLES]];
	
	return [triggersMenu autorelease];
}

/*!
 * @brief Create Edit and Contextual menus of the track triggers
 *
 * Users can then insert %_&lt;token name&gt; into any text view
 */
- (void)insertTriggerMenu
{
	NSMenuItem	*menuItem = [[NSMenuItem alloc] initWithTitle:STRING_TRIGGERS_MENU target:self action:NULL keyEquivalent:@""];
	NSMenu		*menuOfTriggers = [self createTriggerMenu];
	
	[menuItem setSubmenu:menuOfTriggers];
	[adium.menuController addMenuItem:menuItem toLocation:LOC_Edit_Additions];
	[menuItem release];
	
	menuItem = [[NSMenuItem alloc] initWithTitle:STRING_TRIGGERS_MENU target:self action:NULL keyEquivalent:@""];
	[menuItem setSubmenu:[[menuOfTriggers copy] autorelease]];
	[adium.menuController addContextualMenuItem:menuItem toLocation:Context_TextView_Edit];
	[menuItem release];
}

/*!
 * @brief Configure accessibility of menu items
 *
 * Depending on whether the responder is a textview and if it should be enabled when nothing is playing
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	NSResponder					*responder = [[[NSApplication sharedApplication] keyWindow] firstResponder];
	KGiTunesPluginMenuItemKind	tag = (KGiTunesPluginMenuItemKind)[menuItem tag];
	BOOL						enable;

	/* Music may not be installed at all — everything else here works off the
	 * broadcast and off saved track information, but switching to an application
	 * that is not there cannot. Decided before the responder is even looked at:
	 * the item points at another application, not at the text being edited.
	 */
	if (tag == ENABLED_IF_MUSIC_INSTALLED) return ([self musicApplicationURL] != nil);

	//we only insert things into textviews
	if (responder && [responder isKindOfClass:[NSTextView class]]) {

		//some menu items are only enabled if something is playing
		if ((([self iTunesIsStopped] || [self iTunesIsPaused]) && (tag == ENABLED_IF_ITUNES_PLAYING)) || (tag == RESPONDER_IS_WEBVIEW)) {
			enable = NO;
		} else {
			enable = [(NSTextView *)responder isEditable];
		}

	} else if (tag == RESPONDER_IS_WEBVIEW) {
		
		if ([responder respondsToSelector:@selector(selectedString)]) {
			NSString	*selectedString = [(id)responder selectedString];
			
			if (selectedString && [selectedString length]) {
				enable = YES;
			} else {
				enable = NO;
			}

		} else {
			enable = NO;			
		}
		
	} else {
		// enable it if it is always supposed to be on, disable if otherwise
		enable = (tag == ALWAYS_ENABLED);
	}
	
	return enable;
}


#pragma mark -
#pragma mark Deallocation

- (void)dealloc
{
	/* Both centres: -installPlugin observes the distributed one for the player
	 * broadcast and the local one for the format change, and only the first of
	 * the two used to be undone here.
	 */
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	//A delayed update still in flight would message a freed plugin
	[[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(fireUpdateiTunesInfo) object:nil];

	/* Not waited on: a player which never answers must not be able to hold up
	 * quitting. -uninstallPlugin has normally dropped this already; a plugin torn down
	 * without it still gets here.
	 */
	[playerQueryQueue release]; playerQueryQueue = nil;
	[playersRefusingAutomation release]; playersRefusingAutomation = nil;
	[infoSourceBundleIdentifier release]; infoSourceBundleIdentifier = nil;

	//Release class variables
	if (iTunesCurrentInfo) [iTunesCurrentInfo release];
	if (lastRawInfo) [lastRawInfo release];
	if (substitutionDict) [substitutionDict release];
	if (phraseSubstitutionDict) [phraseSubstitutionDict release];

	[super dealloc];
}

@end
