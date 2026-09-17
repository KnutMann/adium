/* Prueft den Opus-Kodierer gegen genau den Leser, der ueber Annahme oder Ablehnung entscheidet.
 *
 * Eine Sprachnotiz kommt bei WhatsApp nur dann als Sprachnotiz an, mit Wellenform und
 * Abspielknopf, wenn sie als Opus in einem Ogg-Behaelter ankommt. Das Plugin prueft das vor
 * dem Senden mit `opusfile_get_info`, und wessen Datei dort eine negative Laenge ergibt, wird
 * als Dokument verschickt. Also wird hier nicht geprueft, ob unsere Datei "irgendwie" stimmt,
 * sondern ob DIESER Leser sie annimmt und die Laenge herausbekommt, die hineingegangen ist.
 */
#import <Foundation/Foundation.h>
#import "AIOpusEncoder.h"
#include <opusfile.h>

static int checks = 0, failures = 0;

static void Check(BOOL condition, const char *what)
{
	checks++;
	if (!condition) { failures++; printf("FEHLER  %s\n", what); }
}

/* Ein Ton, damit etwas Echtes zu kodieren da ist; Stille wuerde der Kodierer zwar
   auch schlucken, aber sie prueft die Wellenform nicht. */
static int16_t *MakeTone(NSUInteger seconds, NSUInteger *countOut)
{
	NSUInteger count = seconds * 48000;
	int16_t *samples = malloc(count * sizeof(int16_t));
	for (NSUInteger i = 0; i < count; i++)
		samples[i] = (int16_t)(12000.0 * sin(2.0 * M_PI * 440.0 * i / 48000.0));
	*countOut = count;
	return samples;
}

int main(void)
{
	@autoreleasepool {
		NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"adium-opus-test.ogg"];
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

		NSUInteger count = 0;
		int16_t *tone = MakeTone(3, &count);

		NSError *error = nil;
		BOOL wrote = AIOpusWriteOggFile(path, tone, count, &error);
		Check(wrote, "Drei Sekunden lassen sich schreiben");
		if (!wrote) { printf("        %s\n", [[error localizedDescription] UTF8String]); return 1; }

		NSData *data = [NSData dataWithContentsOfFile:path];
		Check(data && [data length] > 0, "Die Datei ist nicht leer");

		//Genau der Weg, den das Plugin vor dem Senden geht
		int opusError = 0;
		OggOpusFile *of = op_open_memory([data bytes], [data length], &opusError);
		Check(of != NULL, "Der Leser des Plugins oeffnet sie");

		if (of) {
			ogg_int64_t samples = op_pcm_total(of, -1);
			double seconds = samples / 48000.0;
			Check(fabs(seconds - 3.0) < 0.1, "Die Laenge stimmt auf eine Zehntelsekunde");
			if (fabs(seconds - 3.0) >= 0.1)
				printf("        gemessen %.3f s statt 3.000 s\n", seconds);

			Check(op_channel_count(of, -1) == 1, "Sie ist einkanalig");

			/* Und sie muss sich auch wirklich dekodieren lassen, nicht nur oeffnen */
			float pcm[960];
			int read = op_read_float(of, pcm, 960, NULL);
			Check(read > 0, "Sie laesst sich dekodieren");

			op_free(of);
		}

		//Der kurze Fall: weniger als ein Rahmen
		NSString *tiny = [NSTemporaryDirectory() stringByAppendingPathComponent:@"adium-opus-tiny.ogg"];
		int16_t few[100] = {0};
		Check(AIOpusWriteOggFile(tiny, few, 100, NULL), "Auch weniger als ein Rahmen geht");
		NSData *tinyData = [NSData dataWithContentsOfFile:tiny];
		OggOpusFile *tinyFile = tinyData ? op_open_memory([tinyData bytes], [tinyData length], &opusError) : NULL;
		Check(tinyFile != NULL, "Und ist trotzdem lesbar");
		if (tinyFile) op_free(tinyFile);

		//Und das, was nicht gehen darf
		Check(!AIOpusWriteOggFile(path, NULL, 0, NULL), "Nichts zu schreiben wird abgelehnt");

		free(tone);
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
		[[NSFileManager defaultManager] removeItemAtPath:tiny error:NULL];

		printf("%d Pruefungen, %d Fehler\n", checks, failures);
	}
	return failures ? 1 : 0;
}
