/* A harness that shows the voice recorder's shelf without running Adium.
 *
 * The view draws whatever state it is handed, so it is handed three: a note being
 * recorded, the same note paused, and the note being played back part way. The
 * loudness is made up, from a formula, so that the pictures come out the same every
 * time. The microphone is never opened: the recorder is linked but nothing here
 * starts it.
 */
#import <Cocoa/Cocoa.h>

#import <Adium/AISharedAdium.h>

#import "AIVoiceNoteShelfView.h"

#pragma mark A program that answers nothing

/* Every question is answered with nothing rather than with a crash. The answer has to be
 * written, not left alone: the return buffer of an invocation starts out as whatever was
 * on the stack, so a forwarded call that nobody answers hands back a garbage pointer. */
@interface VoiceNothing : NSObject
@end

@implementation VoiceNothing
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
	NSMethodSignature *signature = [super methodSignatureForSelector:selector];
	return signature ?: [NSMethodSignature signatureWithObjCTypes:"@@:@@@@"];
}
- (void)forwardInvocation:(NSInvocation *)invocation
{
	NSUInteger length = invocation.methodSignature.methodReturnLength;
	if (!length) return;

	void *nothing = calloc(1, length);
	[invocation setReturnValue:nothing];
	free(nothing);
}
@end

#pragma mark Picture taking

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void writePNG(NSWindow *window, NSString *path)
{
	[window.contentView setNeedsDisplay:YES];
	[window display];
	spin(0.5);

	for (int attempt = 0; attempt < 2; attempt++) {
		NSTask *capture = [[NSTask alloc] init];
		capture.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
		capture.arguments = @[@"-x", @"-o",
							  [NSString stringWithFormat:@"-l%ld", (long)window.windowNumber],
							  path];
		NSError *launchError = nil;
		if (![capture launchAndReturnError:&launchError]) {
			fprintf(stderr, "screencapture would not start: %s\n",
					launchError.localizedDescription.UTF8String);
			return;
		}
		[capture waitUntilExit];
		spin(0.3);
	}
	fprintf(stdout, "%s\n", path.lastPathComponent.UTF8String);
}

#pragma mark A voice, made up

/* Something that looks like somebody talking: syllables of a fifth of a second or so,
 * louder and quieter in phrases, with a breath between sentences. The same every run. */
static NSArray *madeUpLevels(NSTimeInterval seconds)
{
	NSUInteger count = (NSUInteger)(seconds / AIVoiceRecorderLevelInterval);
	NSMutableArray *levels = [NSMutableArray arrayWithCapacity:count];
	uint32_t seed = 12345;

	for (NSUInteger i = 0; i < count; i++) {
		seed = seed * 1103515245u + 12345u;
		double jitter = ((seed >> 16) & 0x7fff) / 32767.0;
		double t = i * AIVoiceRecorderLevelInterval;
		double syllable = fabs(sin(t * 15.0));
		double phrase = 0.55 + 0.45 * sin(t * 0.9);
		double breath = (fmod(t, 3.2) < 0.4) ? 0.08 : 1.0;
		double level = 0.003 + 0.16 * syllable * phrase * breath * (0.7 + 0.3 * jitter);
		[levels addObject:[NSNumber numberWithDouble:level]];
	}

	return levels;
}

#pragma mark Runner

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		NSString *outDir = [[NSProcessInfo processInfo] environment][@"VOICE_OUT"];
		if (!outDir) { fprintf(stderr, "VOICE_OUT is missing\n"); return 1; }

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		[NSApp activateIgnoringOtherApps:YES];
		spin(1.0);

		setSharedAdium((id)[[VoiceNothing alloc] init]);

		NSTimeInterval recorded = 7.3, paused = 8.1;
		NSArray *scenes = @[
			@{@"name": @"recording", @"state": @(AIVoiceRecorderRecording), @"duration": @(recorded), @"position": @0.0, @"height": @0.0},
			@{@"name": @"recording-tall", @"state": @(AIVoiceRecorderRecording), @"duration": @(recorded), @"position": @0.0, @"height": @80.0},
			@{@"name": @"paused", @"state": @(AIVoiceRecorderPaused), @"duration": @(paused), @"position": @0.0, @"height": @0.0},
			@{@"name": @"playing", @"state": @(AIVoiceRecorderPlaying), @"duration": @(paused), @"position": @3.2, @"height": @0.0},
		];

		for (NSString *mode in @[@"light", @"dark"]) {
			NSAppearance *appearance = [NSAppearance appearanceNamed:
										([mode isEqualToString:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua)];
			NSApp.appearance = appearance;

			for (NSDictionary *scene in scenes) {
				AIVoiceNoteShelfView *shelf = [[AIVoiceNoteShelfView alloc] initWithChat:(id)[[VoiceNothing alloc] init]];
				CGFloat fitting = ceil([shelf fittingSize].height);
				CGFloat height = [scene[@"height"] doubleValue] ?: fitting;

				NSRect content = NSMakeRect(0.0, 0.0, 480.0, height);
				NSWindow *window = [[NSWindow alloc] initWithContentRect:content
															  styleMask:NSWindowStyleMaskTitled
																backing:NSBackingStoreBuffered
																  defer:NO];
				window.title = [NSString stringWithFormat:@"voice recorder %@ %@", scene[@"name"], mode];
				window.appearance = appearance;
				shelf.frame = window.contentView.bounds;
				shelf.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
				[window.contentView addSubview:shelf];

				NSTimeInterval duration = [scene[@"duration"] doubleValue];
				[shelf showState:(AIVoiceRecorderState)[scene[@"state"] integerValue]
						duration:duration
						  levels:madeUpLevels(duration)
				playbackPosition:[scene[@"position"] doubleValue]];

				[NSApp activateIgnoringOtherApps:YES];
				[window setFrameOrigin:NSMakePoint(200.0, 300.0)];
				[window makeKeyAndOrderFront:nil];
				spin(0.5);

				fprintf(stderr, "%s %s at %.0f: fitting height %.0f\n",
						[mode UTF8String], [scene[@"name"] UTF8String], height, fitting);
				writePNG(window, [outDir stringByAppendingPathComponent:
								  [NSString stringWithFormat:@"voice-%@-%@.png", scene[@"name"], mode]]);
				[shelf removeFromSuperview];
				[window orderOut:nil];
			}
		}
	}
	return 0;
}
