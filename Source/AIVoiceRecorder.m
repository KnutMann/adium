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

#import "AIVoiceRecorder.h"
#import "AIOpusEncoder.h"
#import <Adium/AITextAttachmentExtension.h>
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>

#define VOICE_RATE		48000.0		//what opus works in; converting once here beats converting twice later
#define SHORTEST		0.5			//a note shorter than this is somebody who changed their mind

NSString *const AIVoiceRecorderStateDidChangeNotification = @"AIVoiceRecorderStateDidChange";

/* Twenty levels a second. Enough for a picture of the note that moves with the voice, few
 * enough that an hour of talking is a modest array of numbers. */
const NSTimeInterval AIVoiceRecorderLevelInterval = 0.05;
#define LEVEL_SAMPLES	((NSUInteger)(VOICE_RATE * AIVoiceRecorderLevelInterval))

@interface AIVoiceRecorder () <AVAudioPlayerDelegate>
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) NSMutableData *samples;		//int16, mono, 48 kHz; nil when nothing is held
@property (nonatomic, strong) NSMutableArray *levelHistory;	//one number per LEVEL_SAMPLES of samples
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, assign) AIVoiceRecorderState state;
@end

@implementation AIVoiceRecorder {
	/* The level being built up, across tap callbacks. A callback's worth of samples is not a whole
	 * number of level intervals, so the remainder carries over. Written on the audio thread, under
	 * the same lock as the samples. */
	double		 levelSum;
	NSUInteger	 levelCount;
}

+ (AIVoiceRecorder *)sharedRecorder
{
	static AIVoiceRecorder *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [[AIVoiceRecorder alloc] init]; });
	return shared;
}

//State ----------------------------------------------------------------------------------------------------------------
#pragma mark State

- (BOOL)isRecording
{
	return (self.state == AIVoiceRecorderRecording);
}

/*!
 * @brief Whether there is a note
 *
 * Also while the system is still asking about the microphone: the note exists from the moment
 * it was asked for, empty, so that the shelf showing it counts as busy and a cancel in that
 * moment has something to cancel.
 */
- (BOOL)holdsRecording
{
	if (self.state != AIVoiceRecorderIdle) return YES;

	@synchronized (self) {
		return (self.samples != nil);
	}
}

/*!
 * @brief Move to a new state and say so
 *
 * Only ever on the main thread: the audio thread appends samples and nothing else, and playback
 * ending is brought over to the main thread before it lands here.
 */
- (void)becomeState:(AIVoiceRecorderState)newState
{
	if (newState == self.state) return;

	self.state = newState;
	[[NSNotificationCenter defaultCenter] postNotificationName:AIVoiceRecorderStateDidChangeNotification object:self];
}

- (NSTimeInterval)duration
{
	@synchronized (self) {
		return ([self.samples length] / sizeof(int16_t)) / VOICE_RATE;
	}
}

- (NSArray *)levels
{
	@synchronized (self) {
		return [self.levelHistory copy];
	}
}

- (NSTimeInterval)playbackPosition
{
	return (self.state == AIVoiceRecorderPlaying ? [self.player currentTime] : 0.0);
}

//The microphone ---------------------------------------------------------------------------------------------------------
#pragma mark The microphone

- (void)startWithCompletion:(void (^)(BOOL began, NSString *problem))handler
{
	if (self.holdsRecording) {
		if (handler) handler(NO, AILocalizedString(@"Already recording", nil));
		return;
	}

	@synchronized (self) {
		self.samples = [NSMutableData data];
		self.levelHistory = [NSMutableArray array];
		levelSum = 0.0;
		levelCount = 0;
	}

	[self openMicrophone:handler];
}

- (void)pause
{
	if (self.state != AIVoiceRecorderRecording) return;

	[self closeMicrophone];
	[self becomeState:AIVoiceRecorderPaused];
}

- (void)resumeWithCompletion:(void (^)(BOOL began, NSString *problem))handler
{
	if (self.state == AIVoiceRecorderPlaying)
		[self stopPlaying];

	if (self.state != AIVoiceRecorderPaused) {
		if (handler) handler(NO, nil);
		return;
	}

	[self openMicrophone:handler];
}

/*!
 * @brief Ask for the microphone, then open it
 *
 * The first time, the system asks the user. Everything after that answers at once from what they
 * said then, so this is not a dialog on every note, nor on every resume.
 */
- (void)openMicrophone:(void (^)(BOOL began, NSString *problem))handler
{
	[AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
		dispatch_async(dispatch_get_main_queue(), ^{
			/* Cancelled while the system was asking: the shelf closed, or the bin was pressed. The
			 * answer, whichever it was, is for a note nobody wants any more, and a microphone opened
			 * now would stay open with nothing on screen to close it. */
			if (!self.holdsRecording) {
				if (handler) handler(NO, nil);
				return;
			}

			if (!granted) {
				[self abandonOpening];
				if (handler) handler(NO, AILocalizedString(@"Adium has not been allowed to use the microphone.",
														   "Shown when recording a voice note is refused by the system"));
				return;
			}
			[self reallyOpenMicrophone:handler];
		});
	}];
}

- (void)reallyOpenMicrophone:(void (^)(BOOL began, NSString *problem))handler
{
	/* A fresh engine each time rather than one restarted. An engine that has been stopped can be
	 * started again, but its input node keeps whatever tap it had, and a tap installed twice is an
	 * exception. New is simpler than remembering. */
	self.engine = [[AVAudioEngine alloc] init];

	AVAudioInputNode	*input = [self.engine inputNode];
	AVAudioFormat		*hardware = [input outputFormatForBus:0];

	/* What the microphone gives is whatever the device likes: some rate, some channel count,
	 * floating point. What is wanted is one channel of sixteen bit at 48 kHz. Converting here,
	 * once, while it is still arriving, is cheaper and simpler than keeping the original and
	 * converting the lot at the end. */
	AVAudioFormat *wanted = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
															 sampleRate:VOICE_RATE
															   channels:1
															interleaved:YES];
	AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:hardware toFormat:wanted];

	if (!converter || hardware.sampleRate <= 0) {
		[self abandonOpening];
		if (handler) handler(NO, AILocalizedString(@"No microphone could be opened.", nil));
		return;
	}

	__weak __typeof__(self) weakSelf = self;
	[input installTapOnBus:0 bufferSize:4096 format:hardware block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
		__typeof__(self) me = weakSelf;
		if (!me) return;

		AVAudioFrameCount capacity = (AVAudioFrameCount)(buffer.frameLength * VOICE_RATE / hardware.sampleRate) + 1024;
		AVAudioPCMBuffer *converted = [[AVAudioPCMBuffer alloc] initWithPCMFormat:wanted frameCapacity:capacity];
		if (!converted) return;

		__block BOOL handedOver = NO;
		NSError *problem = nil;
		[converter convertToBuffer:converted error:&problem withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount want, AVAudioConverterInputStatus *status) {
			if (handedOver) { *status = AVAudioConverterInputStatus_NoDataNow; return nil; }
			handedOver = YES;
			*status = AVAudioConverterInputStatus_HaveData;
			return buffer;
		}];

		if (converted.frameLength)
			[me takeConvertedSamples:converted.int16ChannelData[0] count:converted.frameLength];
	}];

	NSError *problem = nil;
	if (![self.engine startAndReturnError:&problem]) {
		[input removeTapOnBus:0];
		[self abandonOpening];
		if (handler) handler(NO, [problem localizedDescription] ?: AILocalizedString(@"Recording could not be started.", nil));
		return;
	}

	[self becomeState:AIVoiceRecorderRecording];
	if (handler) handler(YES, nil);
}

/*!
 * @brief What the tap delivers, on the audio thread
 *
 * The samples go on the note. The loudness goes on the levels, one number per interval, as the
 * root of the mean square of the samples in it, which is the measure a meter uses. A callback
 * seldom ends on an interval boundary, so the sum in progress carries over to the next.
 */
- (void)takeConvertedSamples:(const int16_t *)converted count:(NSUInteger)count
{
	@synchronized (self) {
		if (!self.samples) return;		//cancelled under the tap; the last buffer is nobody's

		[self.samples appendBytes:converted length:count * sizeof(int16_t)];

		for (NSUInteger i = 0; i < count; i++) {
			double sample = converted[i] / 32768.0;
			levelSum += sample * sample;
			if (++levelCount == LEVEL_SAMPLES) {
				[self.levelHistory addObject:[NSNumber numberWithDouble:sqrt(levelSum / levelCount)]];
				levelSum = 0.0;
				levelCount = 0;
			}
		}
	}
}

/*!
 * @brief An opening that failed
 *
 * A note that was paused is still there and stays paused. A note that was only just begun is
 * empty, and goes, so that the next attempt starts clean.
 */
- (void)abandonOpening
{
	self.engine = nil;
	if (self.state == AIVoiceRecorderIdle) [self dropEverything];
}

- (void)closeMicrophone
{
	if (!self.engine) return;

	[[self.engine inputNode] removeTapOnBus:0];
	[self.engine stop];
	self.engine = nil;
}

//Playback ---------------------------------------------------------------------------------------------------------------
#pragma mark Playback

/*!
 * @brief The note so far as a WAV file in memory
 *
 * The player reads files, and what the recorder holds is bare samples. Forty-four bytes of
 * header in front of them make a file the player reads without a copy on disk.
 */
- (NSData *)wavData
{
	NSData *sound = nil;
	@synchronized (self) {
		sound = [self.samples copy];
	}
	if (!sound) return nil;

	uint32_t dataLength = (uint32_t)[sound length];
	uint32_t rate = (uint32_t)VOICE_RATE;
	uint16_t channels = 1, bits = 16;
	uint16_t blockAlign = channels * bits / 8;
	uint32_t byteRate = rate * blockAlign;
	uint32_t formatLength = 16, riffLength = 36 + dataLength;
	uint16_t pcm = 1;

	NSMutableData *wav = [NSMutableData dataWithCapacity:44 + dataLength];
	[wav appendBytes:"RIFF" length:4];
	[wav appendBytes:&riffLength length:4];
	[wav appendBytes:"WAVE" length:4];
	[wav appendBytes:"fmt " length:4];
	[wav appendBytes:&formatLength length:4];
	[wav appendBytes:&pcm length:2];
	[wav appendBytes:&channels length:2];
	[wav appendBytes:&rate length:4];
	[wav appendBytes:&byteRate length:4];
	[wav appendBytes:&blockAlign length:2];
	[wav appendBytes:&bits length:2];
	[wav appendBytes:"data" length:4];
	[wav appendBytes:&dataLength length:4];
	[wav appendData:sound];

	return wav;
}

- (void)playFromStart
{
	if (self.state != AIVoiceRecorderPaused) return;

	NSData *wav = [self wavData];
	if (![wav length]) return;

	NSError *problem = nil;
	self.player = [[AVAudioPlayer alloc] initWithData:wav error:&problem];
	self.player.delegate = self;

	if ([self.player play]) {
		[self becomeState:AIVoiceRecorderPlaying];
	} else {
		self.player = nil;
	}
}

- (void)stopPlaying
{
	if (self.state != AIVoiceRecorderPlaying) return;

	[self.player stop];
	self.player = nil;
	[self becomeState:AIVoiceRecorderPaused];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
	//Brought to the main thread; the player does not promise which one it calls from
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.player == player) [self stopPlaying];
	});
}

//Finishing --------------------------------------------------------------------------------------------------------------
#pragma mark Finishing

/*!
 * @brief Let everything go: the microphone, the player, the samples
 *
 * @result The samples, for a caller that still wants them
 */
- (NSData *)dropEverything
{
	NSData *taken = nil;

	[self closeMicrophone];
	[self.player stop];
	self.player = nil;

	@synchronized (self) {
		taken = self.samples;
		self.samples = nil;
		self.levelHistory = nil;
		levelSum = 0.0;
		levelCount = 0;
	}

	[self becomeState:AIVoiceRecorderIdle];

	return taken;
}

- (void)stopAndWrite:(void (^)(NSString *path, NSTimeInterval duration, NSString *problem))handler
{
	NSData	*sound = [self dropEverything];
	NSUInteger count = [sound length] / sizeof(int16_t);

	if (count < (NSUInteger)(VOICE_RATE * SHORTEST)) {
		if (handler) handler(nil, 0, AILocalizedString(@"That was too short to send.",
													  "Shown when a voice note is barely a moment long"));
		return;
	}

	/* Named after what is in it, the way the pictures and the videos are, so that the message
	 * view recognises it and puts a player in its place rather than a link. */
	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1([sound bytes], (CC_LONG)[sound length], digest);

	NSMutableString *name = [NSMutableString stringWithString:AIVoiceNoteFilePrefix];
	for (int i = 0; i < 8; i++) [name appendFormat:@"%02x", digest[i]];
	[name appendString:@".ogg"];

	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];

	//Writing takes a moment for a long note, and the main thread has a window to keep drawing
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *wrote = nil;
		BOOL ok = AIOpusWriteOggFile(path, (const int16_t *)[sound bytes], count, &wrote);

		dispatch_async(dispatch_get_main_queue(), ^{
			if (handler) {
				if (ok) handler(path, count / VOICE_RATE, nil);
				else handler(nil, 0, [wrote localizedDescription] ?: AILocalizedString(@"The recording could not be saved.", nil));
			}
		});
	});
}

- (void)cancel
{
	[self dropEverything];
}

@end
