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
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>

#define VOICE_RATE		48000.0		//what opus works in; converting once here beats converting twice later
#define SHORTEST		0.5			//a note shorter than this is somebody who changed their mind

@interface AIVoiceRecorder ()
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) NSMutableData *samples;		//int16, mono, 48 kHz
@property (nonatomic, strong) NSDate *began;
@end

@implementation AIVoiceRecorder

+ (AIVoiceRecorder *)sharedRecorder
{
	static AIVoiceRecorder *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [[AIVoiceRecorder alloc] init]; });
	return shared;
}

- (BOOL)isRecording
{
	return (self.engine != nil);
}

- (NSTimeInterval)elapsed
{
	return self.began ? [[NSDate date] timeIntervalSinceDate:self.began] : 0.0;
}

- (void)startWithCompletion:(void (^)(BOOL began, NSString *problem))handler
{
	if (self.recording) {
		if (handler) handler(NO, AILocalizedString(@"Already recording", nil));
		return;
	}

	/* The first time, the system asks the user. Everything after that answers at once from
	 * what they said then, so this is not a dialog on every note. */
	[AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!granted) {
				if (handler) handler(NO, AILocalizedString(@"Adium has not been allowed to use the microphone.",
														   "Shown when recording a voice note is refused by the system"));
				return;
			}
			[self reallyStart:handler];
		});
	}];
}

- (void)reallyStart:(void (^)(BOOL began, NSString *problem))handler
{
	self.samples = [NSMutableData data];
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
		self.engine = nil;
		self.samples = nil;
		if (handler) handler(NO, AILocalizedString(@"No microphone could be opened.", nil));
		return;
	}

	__weak __typeof__(self) weakSelf = self;
	[input installTapOnBus:0 bufferSize:4096 format:hardware usingBlock:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
		__typeof__(self) me = weakSelf;
		if (!me || !me.samples) return;

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

		if (converted.frameLength) {
			@synchronized (me) {
				[me.samples appendBytes:converted.int16ChannelData[0]
								 length:converted.frameLength * sizeof(int16_t)];
			}
		}
	}];

	NSError *problem = nil;
	if (![self.engine startAndReturnError:&problem]) {
		[input removeTapOnBus:0];
		self.engine = nil;
		self.samples = nil;
		if (handler) handler(NO, [problem localizedDescription] ?: AILocalizedString(@"Recording could not be started.", nil));
		return;
	}

	self.began = [NSDate date];
	if (handler) handler(YES, nil);
}

- (NSData *)takeSamples
{
	NSData *taken = nil;

	if (self.engine) {
		[[self.engine inputNode] removeTapOnBus:0];
		[self.engine stop];
		self.engine = nil;
	}

	@synchronized (self) {
		taken = self.samples;
		self.samples = nil;
	}
	self.began = nil;

	return taken;
}

- (void)stopAndWrite:(void (^)(NSString *path, NSTimeInterval duration, NSString *problem))handler
{
	NSData	*sound = [self takeSamples];
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

	NSMutableString *name = [NSMutableString stringWithString:@"AdiumVoice_"];
	for (int i = 0; i < 8; i++) [name appendFormat:@"%02x", digest[i]];
	[name appendString:@".ogg"];

	NSString	*path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	NSError		*problem = nil;

	//Writing takes a moment for a long note, and the main thread has a button to keep drawing
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

	(void)problem;
}

- (void)cancel
{
	[self takeSamples];
}

@end
