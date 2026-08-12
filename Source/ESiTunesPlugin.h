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

#import <Adium/AIContentControllerProtocol.h>

typedef enum {
	AUTODISABLES = 0,
	ALWAYS_ENABLED = 1,
	ENABLED_IF_ITUNES_PLAYING = 2,
	RESPONDER_IS_WEBVIEW = 3,
	ENABLED_IF_MUSIC_INSTALLED = 4
} KGiTunesPluginMenuItemKind;

#define Adium_iTunesTrackChangedNotification		@"Adium_iTunesTrackChangedNotification"
#define Adium_CurrentTrackFormatChangedNotification	@"Adium_CurrentTrackFormatChangedNotification"

#define TRIGGER_ALBUM				@"%_album"
#define TRIGGER_ARTIST				@"%_artist"
#define TRIGGER_COMPOSER			@"%_composer"
#define TRIGGER_GENRE				@"%_genre"
#define TRIGGER_STATUS				@"%_status"
#define TRIGGER_TRACK				@"%_track"
#define TRIGGER_YEAR				@"%_year"
#define	TRIGGER_STORE_URL			@"%_iTMS"
#define TRIGGER_MUSIC				@"%_music"
#define TRIGGER_CURRENT_TRACK		@"%_iTunes"

/*!
 * @brief What a player is doing, as far as the plugin knows.
 *
 * Told apart for one caller only: the preview in the Status pane of the Advanced
 * preferences, which has to say something honest when the resolved text comes back
 * empty. Empty means four different things — nobody has ever said anything, the
 * player is stopped, the player is paused, or the format really does resolve to
 * nothing — and the last of those is the only one that points at a mistake the user
 * can put right.
 *
 * "Nothing known" is deliberately not the same as "stopped": the plugin starts out
 * holding a lone "Stopped" (see -installPlugin) precisely so the filter does not
 * mistake silence for playback, and that starting value is indistinguishable from a
 * genuine stop broadcast.
 */
typedef enum {
	AIMusicPreviewNothingKnown = 0,	//No player has ever told us anything
	AIMusicPreviewStopped,			//A player is known to be stopped
	AIMusicPreviewPaused,			//A player is known to be paused
	AIMusicPreviewPlaying			//Something is playing, so the resolved text is what would go out
} AIMusicPreviewState;

#define KEY_TRIGGERS_TOOLBAR		@"iTunesItem"
#define KEY_ITUNES_TRACK_FORMAT		@"Current Track Format"
#define KEY_ITUNES_ALBUM			@"Album"
#define KEY_ITUNES_ARTIST			@"Artist"
#define KEY_ITUNES_COMPOSER			@"Composer"
#define KEY_ITUNES_GENRE			@"Genre"
#define KEY_ITUNES_PLAYER_STATE		@"Player State"
#define KEY_ITUNES_NAME				@"Name"
#define KEY_ITUNES_STREAM_TITLE		@"Stream Title"
#define KEY_ITUNES_STORE_URL		@"Store URL"
#define KEY_ITUNES_TOTAL_TIME		@"Total Time"
#define KEY_ITUNES_YEAR				@"Year"

/*!
 * @class ESiTunesPlugin
 * @brief Replaces the %_ triggers with what Music.app is playing.
 *
 * The class and file name still say iTunes: AICoreComponentLoader loads the class
 * by name and two files of the Purple service import this header, so renaming it
 * would be a rename across components for no gain. Everything the user sees says
 * Music, and so do the identifiers introduced since the port.
 */
@interface ESiTunesPlugin : AIPlugin <AIContentFilter> {
	NSDictionary *iTunesCurrentInfo;
	NSDictionary *lastRawInfo;			//Last broadcast payload, verbatim; see -setiTunesCurrentInfo:

	NSDictionary *substitutionDict;
	NSDictionary *phraseSubstitutionDict;
	BOOL iTunesIsStopped;
	BOOL iTunesIsPaused;

	/* The active query. The broadcast above only ever arrives when something
	 * changes, so until the user next touches a player we know nothing at all;
	 * -requestPlayerQuery asks Music and Spotify directly, but only from a moment
	 * where the user is visibly using the music status.
	 *
	 * One limit is worth stating where it cannot be missed: nothing is sent to an
	 * application which is not running, because the event would launch it — but the
	 * check and the event cannot be made one indivisible step. A player which quits
	 * in the handful of milliseconds between them is relaunched by its own Apple
	 * event. AEDeterminePermissionToAutomateTarget is asked a second time from the
	 * worker for exactly this reason and answers procNotFound for a target that has
	 * gone, which narrows the window to almost nothing; shutting it completely would
	 * mean giving up NSAppleScript and assembling the events by hand, which is not
	 * worth it for the last few milliseconds. See AIQueryPlayer.
	 */
	NSOperationQueue *playerQueryQueue;			//Apple events are sent from here, never from the main thread
	NSMutableSet *playersRefusingAutomation;	//Bundle identifiers the user has denied us; asked once per launch, then left alone
	NSUInteger infoGeneration;					//Counts every payload reaching -setiTunesCurrentInfo:; guards against a stale answer
	NSTimeInterval lastPlayerQueryTime;			//When we last actually sent something, to keep repeated triggers cheap
	BOOL playerQueryInFlight;
	BOOL playerQueryLearnedNothing;				//A query came back empty-handed; see -requestPlayerQueryIfNothingIsKnown
	NSString *infoSourceBundleIdentifier;		//Which player answered for what we hold, or nil when it came over the broadcast
	BOOL musicStatusWasActive;					//Previous state of the Now Playing status, so we can spot it becoming active
}

/*!
 * @brief What the Now Playing status would send if @a format were the stored format.
 *
 * The one thing the preference pane cannot work out for itself: the two-stage
 * replacement lives here, and a second one built next to it would drift apart from
 * this one at the first change. So the pane hands its format over and gets back the
 * text the status would actually carry — this runs the very same replacement the
 * filter runs, over the very same %_iTunes trigger the status message consists of.
 *
 * Reads and returns; nothing at all is written. No preference, no cached dictionary,
 * no bundled update, and — unlike the filter — no player query either: whether
 * looking at the settings is worth an Apple event is the pane's decision to take
 * openly, not a side effect of drawing a line of text. Call it as often as you like.
 *
 * @param format The format to resolve. An empty or nil format falls back to the same
 *               default the plugin itself uses, so the preview shows what an untouched
 *               setting would send rather than nothing.
 * @param outState Filled in with what the player is doing, or NULL. Needed to tell an
 *                 empty result apart from a format which resolves to nothing; see
 *                 AIMusicPreviewState.
 * @result The resolved text. Empty for every state but AIMusicPreviewPlaying — the
 *         status deliberately sends nothing while no music is playing.
 *
 * Main thread only. The filter itself may run anywhere (see -filterAttributedString:context:),
 * but this reads the same information without the filter's excuse for doing so.
 */
- (NSString *)previewOfTrackFormat:(NSString *)format state:(AIMusicPreviewState *)outState;

/*!
 * @brief Ask the running players what they are playing, unless we already know something.
 *
 * Public for one caller besides the filter: a settings pane whose preview of what the
 * music status would send has nothing to show after a launch — the broadcast only
 * arrives when a track changes. Nothing is sent to a player which is not running,
 * nothing is sent twice within a few seconds, and nothing at all is sent once something
 * is known.
 *
 * Cheap is not the same as free, though, and this is not to be called merely because the
 * feature has come into view. What comes back goes through -setiTunesCurrentInfo:fromPlayer:
 * and ends in a dynamic content update, so every account re-publishes its status message:
 * an act of the user's has to be behind it. See -[ESStatusAdvancedPreferences askPlayersOnFirstInteraction]
 * for what counts as one.
 *
 * The deliberate, unconditional -requestPlayerQuery stays private on purpose: it can
 * put an automation dialog on screen, and the moments which have earned that are all
 * in this file.
 */
- (void)requestPlayerQueryIfNothingIsKnown;

@end
