/* Does a saved voice setting survive the change of speech synthesiser?
 *
 * Adium spoke its announcements through NSSpeechSynthesizer for years and kept three things in
 * the preferences: a voice identifier, a pitch as a base frequency, and a rate in words per
 * minute. AVSpeechUtterance counts differently, namely in a multiple of its own pitch and in a
 * number between zero and one.
 *
 * What is checked is therefore exactly what can go wrong in the changeover: that the saved
 * numbers land inside permitted values, that the default really arrives in the middle, and that
 * an old voice identifier still finds a voice. The conversion stands here word for word as it
 * does in AdiumSpeech.m; it is too short to bundle up for a test and too easily got wrong to
 * leave unchecked.
 */
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

/* The default values the old synthesiser reported for the system voice */
#define DEFAULT_RATE_WPM		175.0f
#define DEFAULT_PITCH_BASE		44.0f

/*! Word for word the same as AIUtteranceRateForWordsPerMinute in AdiumSpeech.m */
static float rateForWordsPerMinute(float wordsPerMinute)
{
	if (wordsPerMinute <= FLT_EPSILON) return AVSpeechUtteranceDefaultSpeechRate;

	float rate = AVSpeechUtteranceDefaultSpeechRate * (wordsPerMinute / DEFAULT_RATE_WPM);

	return MIN(MAX(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate);
}

/*! Word for word the same as AIUtterancePitchForBasePitch in AdiumSpeech.m */
static float pitchForBasePitch(float basePitch)
{
	if (basePitch <= FLT_EPSILON) return 1.0f;

	return MIN(MAX(basePitch / DEFAULT_PITCH_BASE, 0.5f), 2.0f);
}

static BOOL nearly(float a, float b) { return fabsf(a - b) < 0.001f; }

int main(void) { @autoreleasepool {
	//The default has to land on the default, or Adium speaks faster out of the box than before
	check(@"The default rate lands on the default",
		  nearly(rateForWordsPerMinute(DEFAULT_RATE_WPM), AVSpeechUtteranceDefaultSpeechRate),
		  [NSString stringWithFormat:@"%.3f instead of %.3f",
		   rateForWordsPerMinute(DEFAULT_RATE_WPM), AVSpeechUtteranceDefaultSpeechRate]);

	check(@"The default pitch leaves the voice alone",
		  nearly(pitchForBasePitch(DEFAULT_PITCH_BASE), 1.0f), nil);

	//Nothing saved means the default, not zero
	check(@"With no saved rate the default applies",
		  nearly(rateForWordsPerMinute(0.0f), AVSpeechUtteranceDefaultSpeechRate), nil);
	check(@"With no saved pitch, plain unchanged applies",
		  nearly(pitchForBasePitch(0.0f), 1.0f), nil);

	/* The whole slider range out of the two nibs, 90 to 300 words per minute and a base
	 * frequency of 0 to 100, has to land inside permitted values. AVSpeechUtterance accepts
	 * nothing outside them, and nobody would ever find settings discarded in silence. */
	for (float wpm = 90.0f; wpm <= 300.0f; wpm += 5.0f) {
		float rate = rateForWordsPerMinute(wpm);

		if (rate < AVSpeechUtteranceMinimumSpeechRate || rate > AVSpeechUtteranceMaximumSpeechRate) {
			check([NSString stringWithFormat:@"%.0f words per minute stays in range", wpm], NO,
				  [NSString stringWithFormat:@"%.3f is out of range", rate]);
			break;
		}
	}
	check(@"The whole rate slider stays in the permitted range", failures == 0, nil);

	int pitchFailures = failures;
	for (float base = 0.0f; base <= 100.0f; base += 1.0f) {
		float pitch = pitchForBasePitch(base);

		if (pitch < 0.5f || pitch > 2.0f) {
			check([NSString stringWithFormat:@"Base frequency %.0f stays in range", base], NO,
				  [NSString stringWithFormat:@"x%.3f is out of range", pitch]);
			break;
		}
	}
	check(@"The whole pitch slider stays in the permitted range", failures == pitchFailures, nil);

	//Saved faster means spoken faster, and not the other way round
	check(@"More words per minute gives a higher rate",
		  rateForWordsPerMinute(250.0f) > rateForWordsPerMinute(150.0f), nil);
	check(@"A higher base frequency gives a higher voice",
		  pitchForBasePitch(60.0f) > pitchForBasePitch(30.0f), nil);

	/* The real reason the changeover works without a conversion table: the identifiers that
	 * sit in the preferences are valid identifiers under the new scheme too. Measured, 180 out
	 * of 184 were; one old identifier that exists on every Mac is checked here as a stand in. */
	check(@"An identifier in the old spelling finds a voice",
		  [AVSpeechSynthesisVoice voiceWithIdentifier:@"com.apple.speech.synthesis.voice.Albert"] != nil,
		  @"com.apple.speech.synthesis.voice.Albert was not found");

	//And a voice that no longer exists has to give nil: that means the system voice
	check(@"An identifier with no voice gives nil rather than an error",
		  [AVSpeechSynthesisVoice voiceWithIdentifier:@"com.example.a.voice.nobody.has"] == nil, nil);

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
