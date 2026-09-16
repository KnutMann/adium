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

#import "AdiumSpeech.h"
#import "AISoundController.h"
#import <Adium/AIListObject.h>

#define TEXT_TO_SPEAK			@"Text"
#define VOICE					@"Voice"
#define PITCH					@"Pitch"
#define RATE					@"Rate"

/* What the old speech synthesiser reported for the system default voice, measured rather than
 * remembered: 175 words a minute at a base pitch of 44. The sliders in the announcer settings
 * count in these units and the settings people have saved are in them too, so they stay the
 * middle of the range and everything stored keeps meaning what it meant. AVSpeechSynthesis has
 * nothing to ask for them, which is why they are written down here instead of read.
 *
 * One thing is genuinely lost with them: the old number followed the speaking rate set in
 * System Settings, and this one cannot. Somebody who had slowed all speech down system-wide
 * will find Adium back at the ordinary pace until they move the slider here. */
#define DEFAULT_RATE_WPM		175.0f
#define DEFAULT_PITCH_BASE		44.0f

@interface AdiumSpeech ()
- (AVSpeechSynthesizer *)speaker;
- (void)_speakNext;
- (void)_stopSpeaking;
- (void)workspaceSessionDidBecomeActive:(NSNotification *)notification;
- (void)workspaceSessionDidResignActive:(NSNotification *)notification;
@end

/*! Words a minute, which is how the sliders count, to the nought-to-one an utterance wants */
static float AIUtteranceRateForWordsPerMinute(float wordsPerMinute)
{
	if (wordsPerMinute <= FLT_EPSILON) return AVSpeechUtteranceDefaultSpeechRate;

	float rate = AVSpeechUtteranceDefaultSpeechRate * (wordsPerMinute / DEFAULT_RATE_WPM);

	return MIN(MAX(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate);
}

/*! A base pitch, which is how the sliders count, to a multiple of the voice's own pitch */
static float AIUtterancePitchForBasePitch(float basePitch)
{
	if (basePitch <= FLT_EPSILON) return 1.0f;

	//The multiplier AVSpeechUtterance takes runs from half to double, and refuses anything else
	return MIN(MAX(basePitch / DEFAULT_PITCH_BASE, 0.5f), 2.0f);
}

@implementation AdiumSpeech

/*!
 * @brief Init
 */
- (id)init
{
	if ((self = [super init])) {
		speechArray = [[NSMutableArray alloc] init];
		workspaceSessionIsActive = YES;
		speaking = NO;

		//Observe workspace activity changes so we can mute sounds as necessary
		NSNotificationCenter *workspaceCenter = [[NSWorkspace sharedWorkspace] notificationCenter];

		[workspaceCenter addObserver:self
							selector:@selector(workspaceSessionDidBecomeActive:)
								name:NSWorkspaceSessionDidBecomeActiveNotification
							  object:nil];

		[workspaceCenter addObserver:self
							selector:@selector(workspaceSessionDidResignActive:)
								name:NSWorkspaceSessionDidResignActiveNotification
							  object:nil];
	}

	return self;
}

/*!
 * @brief Close
 */
- (void)dealloc
{
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
	[adium.preferenceController unregisterPreferenceObserver:self];

	[self _stopSpeaking];
}

/*!
* @brief Finish Initing
 *
 * Requires:
 * 1) Preference controller is ready
 */
- (void)controllerDidLoad
{
	//Observe changes
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_SOUNDS];
}

#pragma mark Preferences

/*!
* @brief Preferences changed, adjust to the new values
 */
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	/* Volume belongs to the utterance rather than to the speaker, so there is nothing to go
	 * back and adjust: whatever is being said finishes at the volume it started at, and the
	 * next thing is said at the new one. */
	customVolume = [[prefDict objectForKey:KEY_SOUND_CUSTOM_VOLUME_LEVEL] floatValue];
}

#pragma mark Speech

/*!
 * @brief Speak text with the default values
 *
 * @param text NSString to speak
 */
- (void)speakText:(NSString *)text
{
    [self speakText:text withVoice:nil pitch:0 rate:0];
}

/*!
 * @brief Speak text with a specific voice, pitch, and rate
 *
 * If text is already being spoken, this text will be queued and spoken at the next available opportunity
 * @param text NSString to speak
 * @param voiceString NSString voice identifier
 * @param pitch Speaking pitch
 * @param rate Speaking rate
 */
- (void)speakText:(NSString *)text withVoice:(NSString *)voiceString pitch:(float)pitch rate:(float)rate
{
	if (text && [text length] && workspaceSessionIsActive) {
		NSMutableDictionary *dict = [NSMutableDictionary dictionary];

		if (text) {
			[dict setObject:text forKey:TEXT_TO_SPEAK];
		}

		if (voiceString) [dict setObject:voiceString forKey:VOICE];
		if (pitch > FLT_EPSILON) [dict setObject:[NSNumber numberWithDouble:pitch] forKey:PITCH];
		if (rate  > FLT_EPSILON) [dict setObject:[NSNumber numberWithDouble:rate]  forKey:RATE];
		AILog(@"AdiumSpeech: %@",dict);
		[speechArray addObject:dict];

		[self _speakNext];
	}
}

/*!
 * @brief Speak a sample of how a voice sounds at the passed settings
 *
 * The old synthesiser carried a demonstration sentence for every voice, in that voice's own
 * language, and there is nothing like it any more. So the sentence is ours, which means it
 * arrives in the language Adium is running in rather than the language of the voice being
 * tried. For judging a pitch and a rate, which is what this is for, that is enough.
 *
 * @param voiceString NSString voice identifier
 * @param pitch Speaking pitch
 * @param rate Speaking rate
 */
- (void)speakDemoTextForVoice:(NSString *)voiceString withPitch:(float)pitch andRate:(float)rate
{
	if(workspaceSessionIsActive) {
		[self _stopSpeaking];
		[self speakText:AILocalizedString(@"This is how this voice sounds.", "Sample sentence spoken when trying out a voice in the announcer settings")
			  withVoice:voiceString
				  pitch:pitch
				   rate:rate];
	}
}


//Voices ---------------------------------------------------------------------------------------------------------------
#pragma mark Voices

/*!
 * @brief Returns the rate the sliders treat as ordinary, in words a minute
 */
- (float)defaultRate
{
	return DEFAULT_RATE_WPM;
}

/*!
 * @brief Returns the base pitch the sliders treat as ordinary
 */
- (float)defaultPitch
{
	return DEFAULT_PITCH_BASE;
}

/*!
 * @brief Returns the speaker, creating if necessary
 *
 * One is enough now. There used to be two, because a voice and its settings lived on the
 * synthesiser itself and one of them had to be left alone at the default; they belong to the
 * utterance now, so every one of them can ask for whatever it likes.
 */
- (AVSpeechSynthesizer *)speaker
{
	if (!_speaker) {
		_speaker = [[AVSpeechSynthesizer alloc] init];
		[_speaker setDelegate:self];
	}
	return _speaker;
}


//Speaking -------------------------------------------------------------------------------------------------------------
#pragma mark Speaking
/*!
 * @brief Attempt to speak the next item in the queue
 *
 * This used to hold back while any other application was speaking, waiting a second and asking
 * again. Nothing answers that question any more, so Adium no longer waits its turn: the queue
 * still keeps it from talking over itself, but not over anybody else.
 */
- (void)_speakNext
{
	//we have items left to speak and aren't already speaking
	if (![speechArray count] || speaking) return;

	speaking = YES;

	NSDictionary		*dict = [speechArray objectAtIndex:0];
	NSString			*voiceID = [dict objectForKey:VOICE];
	NSNumber			*pitchNumber = [dict objectForKey:PITCH];
	NSNumber			*rateNumber = [dict objectForKey:RATE];
	AVSpeechUtterance	*utterance = [AVSpeechUtterance speechUtteranceWithString:[dict objectForKey:TEXT_TO_SPEAK]];

	/* A voice nobody has any more leaves this nil, and a nil voice is the system's own choice,
	 * which is the right answer for a setting that named a voice that has since been removed. */
	if (voiceID) [utterance setVoice:[AVSpeechSynthesisVoice voiceWithIdentifier:voiceID]];

	[utterance setRate:AIUtteranceRateForWordsPerMinute(rateNumber ? [rateNumber floatValue] : 0.0f)];
	[utterance setPitchMultiplier:AIUtterancePitchForBasePitch(pitchNumber ? [pitchNumber floatValue] : 0.0f)];
	[utterance setVolume:customVolume];

	[speechArray removeObjectAtIndex:0];

	[[self speaker] speakUtterance:utterance];
}

/*!
 * @brief Speaking has finished, begin speaking the next item in our queue
 */
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance
{
	//Which thread this arrives on is not promised, and the queue is only touched on the main one
	dispatch_async(dispatch_get_main_queue(), ^{
		self->speaking = NO;
		[self _speakNext];
	});
}

/*!
 * @brief Speaking was cut short; whoever cut it short decides what happens next
 */
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance
{
	dispatch_async(dispatch_get_main_queue(), ^{
		self->speaking = NO;
	});
}

/*!
 * @brief Immediately stop speaking
 */
- (void)_stopSpeaking
{
	[speechArray removeAllObjects];

	[_speaker stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
	speaking = NO;
}


//Misc -----------------------------------------------------------------------------------------------------------------
#pragma mark Misc
/*!
 * @brief Workspace activated (Computer switched to our user)
 */
- (void)workspaceSessionDidBecomeActive:(NSNotification *)notification
{
	workspaceSessionIsActive = YES;
}

/*!
 * @brief Workspace resigned (Computer switched to another user)
 */
- (void)workspaceSessionDidResignActive:(NSNotification *)notification
{
	workspaceSessionIsActive = NO;
	[self _stopSpeaking];
}

@end
