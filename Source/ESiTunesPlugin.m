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

#define ITUNES_STATUS_ID			-8000
#define MUSIC_BUNDLE_IDENTIFIER		@"com.apple.Music"
/* The store moved to the web years ago; itms://itunes.com/link? and
 * itms://phobos.apple.com/… are both dead and answer nothing at all. */
#define MUSIC_SEARCH_URL			@"https://music.apple.com/search?term=%@"

#pragma mark -

#define	KEY_ITUNES_PLAYING			@"Playing"
#define	KEY_ITUNES_PAUSED			@"Paused"
#define	KEY_ITUNES_STOPPED			@"Stopped"

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

@interface ESiTunesPlugin ()
- (NSMenuItem *)menuItemWithTitle:(NSString *)title action:(SEL)action representedObject:(id)representedObject kind:(KGiTunesPluginMenuItemKind)itemKind;
- (void)createiTunesCurrentTrackStatusState;
- (void)updateiTunesCurrentTrackFormat;
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
 * Never asks Music itself: -installPlugin starts this out as "stopped", and from
 * then on only the broadcast changes it.
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
	/* The broadcast is an open channel (see -installPlugin), so a sender that posts
	 * no payload at all can get here. That would leave us with neither track
	 * information nor a player state — which the filter reads as "playing" and sends
	 * out as a half-empty track line — and nothing would put it right again, since
	 * nobody ever asks Music. Fall back to what -installPlugin starts out with.
	 */
	if (![newInfo count]) {
		newInfo = [NSDictionary dictionaryWithObject:KEY_ITUNES_STOPPED forKey:KEY_ITUNES_PLAYER_STATE];
	}

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
	 * until the user next starts, pauses or changes a track — there is no way to
	 * ask without an Apple event, and asking would cost an automation prompt. Start
	 * out as "stopped" rather than as nothing: with no player state at all the
	 * filter takes Music for playing and sends a half-empty track line.
	 */
	iTunesCurrentInfo = [[NSDictionary alloc] initWithObjectsAndKeys:KEY_ITUNES_STOPPED, KEY_ITUNES_PLAYER_STATE, nil];
	[self setiTunesIsStopped:YES];
	[self setiTunesIsPaused:NO];

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

- (void)updateiTunesCurrentTrackFormat
{
	NSDictionary	*slashMusicDict = nil;
	NSDictionary	*conditionalArtistTrackDict = nil;
	NSString		*currentITunesTrackFormat = nil;
	
	slashMusicDict = [[NSDictionary alloc] initWithObjectsAndKeys:
					  [NSString stringWithFormat:AILocalizedString(@"*is listening to %@ by %@*","Phrase sent in response to %_music.  The first %%@ is the track; the second %%@ is the artist."), TRIGGER_TRACK, TRIGGER_ARTIST],
					  KEY_ITUNES_PLAYING,
					  AILocalizedString(@"*is listening to nothing*","Phrase sent in response to %_music when nothing is playing."),
					  KEY_ITUNES_STOPPED,
					  nil];
	
	/* Provide flexibility with the %_iTunes substitution. By default, just store @"" for this key.
	 * But still not hardcoded to a particular format. This is done so that a default installation 
	 * doesn't have its format broken if the locale switches...
	 * since the format specifiers are themselves localized.
	 */
	currentITunesTrackFormat = [adium.preferenceController preferenceForKey:KEY_ITUNES_TRACK_FORMAT
																	  group:PREF_GROUP_STATUS_PREFERENCES];
	if (!currentITunesTrackFormat) {
		[adium.preferenceController setPreference:@""
										   forKey:KEY_ITUNES_TRACK_FORMAT
											group:PREF_GROUP_STATUS_PREFERENCES];
		currentITunesTrackFormat = @"";
	}
	
	if (![currentITunesTrackFormat length]) {
		currentITunesTrackFormat  = [NSString stringWithFormat:@"%@ - %@", TRIGGER_TRACK, TRIGGER_ARTIST];
	}
	
	conditionalArtistTrackDict = [[NSDictionary alloc] initWithObjectsAndKeys:
								  currentITunesTrackFormat,
								  KEY_ITUNES_PLAYING,
								  @"",
								  KEY_ITUNES_STOPPED,
								  nil];

	/* The preference pane now writes while the user types, so this runs far more
	 * often than once per launch: without the release the old dictionary leaked
	 * on every rebuild.
	 */
	[phraseSubstitutionDict release];
	phraseSubstitutionDict = [[NSDictionary alloc] initWithObjectsAndKeys:
							  slashMusicDict,
							  TRIGGER_MUSIC,
							  conditionalArtistTrackDict,
							  TRIGGER_CURRENT_TRACK,
							  nil];

    [self fireUpdateiTunesInfo];

	[slashMusicDict release];
	[conditionalArtistTrackDict release];
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
 * @brief Filter messages for keywords to replace
 *
 * Replace any track triggers with the appropriate information
 */
- (NSAttributedString *)filterAttributedString:(NSAttributedString *)inAttributedString context:(id)context
{
    NSMutableAttributedString	*filteredMessage = nil;
	NSString					*stringMessage;
	
	//get the attributed string as a regular string so we can do string processing
	if ((stringMessage = [inAttributedString string])) {
		NSEnumerator	*enumerator;
		NSString		*trigger;
		BOOL			addStoreLinkAsSubtext = NO;
		
		/* Replace the phrases with the string containing the triggers.
		 * For example, /music will become *is listening to %_track by %_artist*.
		 * This will then become the actual track information in the next while().
		 */
		enumerator = [phraseSubstitutionDict keyEnumerator];
		
		while ((trigger = [enumerator nextObject])) {
			//search for phrase in the string that needs to be filtered
			if (([stringMessage rangeOfString:trigger options:(NSLiteralSearch | NSCaseInsensitiveSearch)].location != NSNotFound)) {
				NSDictionary	*replacementDict;
				NSString		*replacement;
				
				//get the format for the current trigger
				replacementDict = [phraseSubstitutionDict objectForKey:trigger];

				//replacement of phrase should reflect the player state
				if (![self iTunesIsStopped] && ![self iTunesIsPaused]) {
					replacement = [replacementDict objectForKey:KEY_ITUNES_PLAYING];

					/* If the trigger is the trigger used for the Now Playing status, we'll want to add a subtext of the store link
					 * so account code can send it out later on.
					 */
					if ([trigger isEqualToString:TRIGGER_CURRENT_TRACK]) {
						addStoreLinkAsSubtext = YES;
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
		
		if (addStoreLinkAsSubtext && filteredMessage) {
			NSString *storeLinkForSubtext = [iTunesCurrentInfo objectForKey:[substitutionDict objectForKey:TRIGGER_STORE_URL]];
			if (storeLinkForSubtext) {
				[filteredMessage addAttribute:@"AIMessageSubtext"
										value:storeLinkForSubtext
										range:NSMakeRange(0, [filteredMessage length])];
			}
		}
	}
	
	//Give back the processed string
	return (filteredMessage ? filteredMessage : inAttributedString);
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

	//Release class variables
	if (iTunesCurrentInfo) [iTunesCurrentInfo release];
	if (lastRawInfo) [lastRawInfo release];
	if (substitutionDict) [substitutionDict release];
	if (phraseSubstitutionDict) [phraseSubstitutionDict release];

	[super dealloc];
}

@end
