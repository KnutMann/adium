/* Ueberlebt eine gespeicherte Stimmeinstellung den Wechsel des Sprachsynthesizers?
 *
 * Adium hat seine Ansagen jahrelang ueber NSSpeechSynthesizer gesprochen und in den
 * Einstellungen drei Dinge abgelegt: eine Stimmkennung, eine Tonhoehe als Grundfrequenz und
 * eine Rate in Woertern je Minute. AVSpeechUtterance zaehlt anders, naemlich in einem
 * Vielfachen der eigenen Tonhoehe und in einer Zahl zwischen null und eins.
 *
 * Geprueft wird deshalb genau das, was beim Umstieg schiefgehen kann: dass die gespeicherten
 * Zahlen in erlaubten Werten landen, dass die Vorgabe wirklich in der Mitte ankommt, und dass
 * eine alte Stimmkennung auch neu eine Stimme findet. Die Umrechnung steht hier wortgleich wie
 * in AdiumSpeech.m; sie ist zu kurz, um sie fuer einen Test zu buendeln, und zu leicht falsch,
 * um sie ungeprueft zu lassen.
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

/* Die Vorgabewerte, die der alte Synthesizer fuer die Systemstimme meldete */
#define DEFAULT_RATE_WPM		175.0f
#define DEFAULT_PITCH_BASE		44.0f

/*! Wortgleich mit AIUtteranceRateForWordsPerMinute in AdiumSpeech.m */
static float rateForWordsPerMinute(float wordsPerMinute)
{
	if (wordsPerMinute <= FLT_EPSILON) return AVSpeechUtteranceDefaultSpeechRate;

	float rate = AVSpeechUtteranceDefaultSpeechRate * (wordsPerMinute / DEFAULT_RATE_WPM);

	return MIN(MAX(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate);
}

/*! Wortgleich mit AIUtterancePitchForBasePitch in AdiumSpeech.m */
static float pitchForBasePitch(float basePitch)
{
	if (basePitch <= FLT_EPSILON) return 1.0f;

	return MIN(MAX(basePitch / DEFAULT_PITCH_BASE, 0.5f), 2.0f);
}

static BOOL nearly(float a, float b) { return fabsf(a - b) < 0.001f; }

int main(void) { @autoreleasepool {
	//Die Vorgabe muss auf die Vorgabe fallen, sonst spricht Adium ab Werk schneller als vorher
	check(@"Die Vorgaberate landet auf der Vorgabe",
		  nearly(rateForWordsPerMinute(DEFAULT_RATE_WPM), AVSpeechUtteranceDefaultSpeechRate),
		  [NSString stringWithFormat:@"%.3f statt %.3f",
		   rateForWordsPerMinute(DEFAULT_RATE_WPM), AVSpeechUtteranceDefaultSpeechRate]);

	check(@"Die Vorgabetonhoehe laesst die Stimme in Ruhe",
		  nearly(pitchForBasePitch(DEFAULT_PITCH_BASE), 1.0f), nil);

	//Nichts gespeichert heisst Vorgabe, nicht null
	check(@"Ohne gespeicherte Rate gilt die Vorgabe",
		  nearly(rateForWordsPerMinute(0.0f), AVSpeechUtteranceDefaultSpeechRate), nil);
	check(@"Ohne gespeicherte Tonhoehe gilt das Einfache",
		  nearly(pitchForBasePitch(0.0f), 1.0f), nil);

	/* Der ganze Reglerbereich aus den beiden Nibs, 90 bis 300 Woerter je Minute und eine
	 * Grundfrequenz von 0 bis 100, muss in erlaubten Werten landen. AVSpeechUtterance nimmt
	 * ausserhalb nichts an, und stillschweigend verworfene Einstellungen faende niemand. */
	for (float wpm = 90.0f; wpm <= 300.0f; wpm += 5.0f) {
		float rate = rateForWordsPerMinute(wpm);

		if (rate < AVSpeechUtteranceMinimumSpeechRate || rate > AVSpeechUtteranceMaximumSpeechRate) {
			check([NSString stringWithFormat:@"%.0f Woerter je Minute bleibt im Rahmen", wpm], NO,
				  [NSString stringWithFormat:@"%.3f liegt ausserhalb", rate]);
			break;
		}
	}
	check(@"Der ganze Ratenregler bleibt im erlaubten Rahmen", failures == 0, nil);

	int pitchFailures = failures;
	for (float base = 0.0f; base <= 100.0f; base += 1.0f) {
		float pitch = pitchForBasePitch(base);

		if (pitch < 0.5f || pitch > 2.0f) {
			check([NSString stringWithFormat:@"Grundfrequenz %.0f bleibt im Rahmen", base], NO,
				  [NSString stringWithFormat:@"x%.3f liegt ausserhalb", pitch]);
			break;
		}
	}
	check(@"Der ganze Tonhoehenregler bleibt im erlaubten Rahmen", failures == pitchFailures, nil);

	//Schneller gespeichert heisst schneller gesprochen, und nicht andersherum
	check(@"Mehr Woerter je Minute ergibt eine hoehere Rate",
		  rateForWordsPerMinute(250.0f) > rateForWordsPerMinute(150.0f), nil);
	check(@"Eine hoehere Grundfrequenz ergibt eine hoehere Stimme",
		  pitchForBasePitch(60.0f) > pitchForBasePitch(30.0f), nil);

	/* Der eigentliche Grund, warum der Umstieg ohne Umsetzungstabelle geht: die Kennungen, die
	 * in den Einstellungen liegen, sind auch neu gueltige Kennungen. Gemessen waren es 180 von
	 * 184; hier wird stellvertretend eine alte Kennung geprueft, die es auf jedem Mac gibt. */
	check(@"Eine Kennung alter Schreibweise findet eine Stimme",
		  [AVSpeechSynthesisVoice voiceWithIdentifier:@"com.apple.speech.synthesis.voice.Albert"] != nil,
		  @"com.apple.speech.synthesis.voice.Albert wurde nicht gefunden");

	//Und eine Stimme, die es nicht mehr gibt, muss nil ergeben: das ist die Systemstimme
	check(@"Eine Kennung ohne Stimme ergibt nil statt eines Fehlers",
		  [AVSpeechSynthesisVoice voiceWithIdentifier:@"com.example.a.voice.nobody.has"] == nil, nil);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
