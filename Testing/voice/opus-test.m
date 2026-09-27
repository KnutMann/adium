/* Checks the Opus encoder against exactly the reader that decides on acceptance or refusal.
 *
 * A voice note arrives at WhatsApp as a voice note, with a waveform and a play button, only if
 * it arrives as Opus in an Ogg container. The plugin checks that before sending with
 * `opusfile_get_info`, and whoever's file comes out of that with a negative length is sent as a
 * document. So what is checked here is not whether our file is "somehow" right, but whether
 * THAT reader accepts it and gets out the length that went in.
 */
#import <Foundation/Foundation.h>
#import "AIOpusEncoder.h"
#include <opusfile.h>

static int checks = 0, failures = 0;

static void Check(BOOL condition, const char *what)
{
	checks++;
	if (!condition) { failures++; printf("FAILED  %s\n", what); }
}

/* A tone, so there is something real to encode; the encoder would swallow silence
   too, but silence does not exercise the waveform. */
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
		Check(wrote, "Three seconds can be written");
		if (!wrote) { printf("        %s\n", [[error localizedDescription] UTF8String]); return 1; }

		NSData *data = [NSData dataWithContentsOfFile:path];
		Check(data && [data length] > 0, "The file is not empty");

		//Exactly the path the plugin takes before sending
		int opusError = 0;
		OggOpusFile *of = op_open_memory([data bytes], [data length], &opusError);
		Check(of != NULL, "The plugin's reader opens it");

		if (of) {
			ogg_int64_t samples = op_pcm_total(of, -1);
			double seconds = samples / 48000.0;
			Check(fabs(seconds - 3.0) < 0.1, "The length is right to a tenth of a second");
			if (fabs(seconds - 3.0) >= 0.1)
				printf("        measured %.3f s instead of 3.000 s\n", seconds);

			Check(op_channel_count(of, -1) == 1, "It has one channel");

			/* And it really has to decode, not merely open */
			float pcm[960];
			int read = op_read_float(of, pcm, 960, NULL);
			Check(read > 0, "It decodes");

			op_free(of);
		}

		//The short case: less than one frame
		NSString *tiny = [NSTemporaryDirectory() stringByAppendingPathComponent:@"adium-opus-tiny.ogg"];
		int16_t few[100] = {0};
		Check(AIOpusWriteOggFile(tiny, few, 100, NULL), "Less than one frame works too");
		NSData *tinyData = [NSData dataWithContentsOfFile:tiny];
		OggOpusFile *tinyFile = tinyData ? op_open_memory([tinyData bytes], [tinyData length], &opusError) : NULL;
		Check(tinyFile != NULL, "And is readable all the same");
		if (tinyFile) op_free(tinyFile);

		//And what must not work
		Check(!AIOpusWriteOggFile(path, NULL, 0, NULL), "Nothing to write is refused");

		free(tone);
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
		[[NSFileManager defaultManager] removeItemAtPath:tiny error:NULL];

		printf("%d checks, %d failures\n", checks, failures);
	}
	return failures ? 1 : 0;
}
