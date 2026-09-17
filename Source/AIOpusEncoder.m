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

#import "AIOpusEncoder.h"
#include <opus.h>
#include <ogg/ogg.h>

#define SAMPLE_RATE		48000
#define CHANNELS		1
#define FRAME_SAMPLES	960		//20 ms, the length everything that records speech uses
#define MAX_PACKET		4000	//more than a 20 ms frame can ever need

static NSError *AIOpusError(NSInteger code, NSString *what)
{
	return [NSError errorWithDomain:@"AIOpusEncoder"
							   code:code
						   userInfo:@{ NSLocalizedDescriptionKey: what }];
}

/*!
 * @brief Put one packet into the stream and write out whatever pages are finished
 */
static BOOL AIOpusFlushPages(ogg_stream_state *stream, NSFileHandle *file, BOOL flushAll)
{
	ogg_page page;

	while (flushAll ? ogg_stream_flush(stream, &page) : ogg_stream_pageout(stream, &page)) {
		@try {
			[file writeData:[NSData dataWithBytesNoCopy:page.header length:page.header_len freeWhenDone:NO]];
			[file writeData:[NSData dataWithBytesNoCopy:page.body length:page.body_len freeWhenDone:NO]];
		} @catch (NSException *problem) {
			return NO;
		}
	}
	return YES;
}

BOOL AIOpusWriteOggFile(NSString *path, const int16_t *samples, NSUInteger count, NSError **error)
{
	if (![path length] || !samples || !count) {
		if (error) *error = AIOpusError(1, @"nothing to write");
		return NO;
	}

	int opusError = OPUS_OK;
	OpusEncoder *encoder = opus_encoder_create(SAMPLE_RATE, CHANNELS, OPUS_APPLICATION_VOIP, &opusError);
	if (!encoder || opusError != OPUS_OK) {
		if (error) *error = AIOpusError(2, @"the encoder would not start");
		return NO;
	}

	/* What the encoder swallows before it produces anything, in samples. It goes into the
	 * header so that a player knows to throw the same amount away again; get it wrong and
	 * every note starts a few milliseconds late, which nobody notices and everybody's
	 * waveform is then off by the same amount. */
	opus_int32 lookahead = 0;
	opus_encoder_ctl(encoder, OPUS_GET_LOOKAHEAD(&lookahead));

	[[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
	NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
	if (!file) {
		opus_encoder_destroy(encoder);
		if (error) *error = AIOpusError(3, @"the file could not be made");
		return NO;
	}

	ogg_stream_state stream;
	ogg_stream_init(&stream, (int)arc4random());

	BOOL ok = YES;

	/* The first packet says what the stream is: OpusHead, as the container demands, and it
	 * must sit alone on the first page. */
	{
		unsigned char head[19] = {0};
		memcpy(head, "OpusHead", 8);
		head[8] = 1;										//version
		head[9] = CHANNELS;
		head[10] = lookahead & 0xFF;						//pre-skip, little endian
		head[11] = (lookahead >> 8) & 0xFF;
		head[12] = SAMPLE_RATE & 0xFF;						//the rate of what went in
		head[13] = (SAMPLE_RATE >> 8) & 0xFF;
		head[14] = (SAMPLE_RATE >> 16) & 0xFF;
		head[15] = (SAMPLE_RATE >> 24) & 0xFF;
		//gain 0, mapping family 0: the rest stays zero

		ogg_packet packet = { .packet = head, .bytes = sizeof(head), .b_o_s = 1, .granulepos = 0, .packetno = 0 };
		ogg_stream_packetin(&stream, &packet);
		ok = AIOpusFlushPages(&stream, file, YES);
	}

	//The second says who wrote it, and carries no comments
	if (ok) {
		const char *vendor = "Adium";
		unsigned char tags[8 + 4 + 5 + 4];
		memset(tags, 0, sizeof(tags));
		memcpy(tags, "OpusTags", 8);
		tags[8] = (unsigned char)strlen(vendor);
		memcpy(tags + 12, vendor, strlen(vendor));
		//comment count stays zero

		ogg_packet packet = { .packet = tags, .bytes = sizeof(tags), .granulepos = 0, .packetno = 1 };
		ogg_stream_packetin(&stream, &packet);
		ok = AIOpusFlushPages(&stream, file, YES);
	}

	/* Then the sound, in frames of a fixed length. The last frame is padded with silence
	 * rather than shortened: opus encodes only the lengths it knows, and the granule
	 * position tells the player how much of it was real. */
	unsigned char	 packetBytes[MAX_PACKET];
	int16_t			 frame[FRAME_SAMPLES];
	ogg_int64_t		 granule = 0;
	ogg_int64_t		 packetNumber = 2;
	NSUInteger		 offset = 0;

	while (ok && offset < count) {
		NSUInteger have = MIN((NSUInteger)FRAME_SAMPLES, count - offset);
		memcpy(frame, samples + offset, have * sizeof(int16_t));
		if (have < FRAME_SAMPLES)
			memset(frame + have, 0, (FRAME_SAMPLES - have) * sizeof(int16_t));

		opus_int32 written = opus_encode(encoder, frame, FRAME_SAMPLES, packetBytes, sizeof(packetBytes));
		if (written < 0) {
			if (error) *error = AIOpusError(4, @"a frame could not be encoded");
			ok = NO;
			break;
		}

		offset += have;
		granule += FRAME_SAMPLES;

		BOOL last = (offset >= count);
		ogg_packet packet = {
			.packet = packetBytes,
			.bytes = written,
			.e_o_s = last ? 1 : 0,
			/* Counted in samples at 48 kHz, and it includes what the encoder swallowed, so
			 * the length a player works out is the length that was spoken. */
			.granulepos = last ? (ogg_int64_t)(count + lookahead) : granule,
			.packetno = packetNumber++
		};
		ogg_stream_packetin(&stream, &packet);
		ok = AIOpusFlushPages(&stream, file, last);
	}

	ogg_stream_clear(&stream);
	opus_encoder_destroy(encoder);
	[file closeFile];

	if (!ok) {
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
		if (error && !*error) *error = AIOpusError(5, @"the file could not be written");
	}

	return ok;
}
