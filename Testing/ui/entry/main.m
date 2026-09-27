/* A harness that shows the message field with its accessory buttons, without running Adium.
 *
 * The field asks the program for the preference store and for little else, so a stand-in
 * that answers every question with nothing is enough to put it on screen and photograph
 * it. The buttons are the real class with the real pictures; only their actions go nowhere.
 */
#import <Cocoa/Cocoa.h>

#import <Adium/AISharedAdium.h>
#import <Adium/AIMessageEntryTextView.h>
#import <Adium/AIMessageEntryAccessory.h>

#pragma mark A program that answers nothing

/* Every question is answered with nothing rather than with a crash. The answer has to be
 * written, not left alone: the return buffer of an invocation starts out as whatever was
 * on the stack, so a forwarded call that nobody answers hands back a garbage pointer. */
@interface EntryNothing : NSObject
@end

@implementation EntryNothing
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

@interface EntryAdium : EntryNothing
@property (nonatomic, strong) EntryNothing *preferenceController;
@end

@implementation EntryAdium
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

#pragma mark Runner

static AIMessageEntryAccessory *accessoryNamed(NSString *identifier, NSString *imageName)
{
	return [AIMessageEntryAccessory accessoryWithIdentifier:identifier
													  label:identifier
													toolTip:identifier
													  image:[[NSBundle mainBundle] imageForResource:imageName]
											  preferenceKey:identifier
													  group:@"Harness"
													 target:nil
													 action:NULL];
}

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		NSString *outDir = [[NSProcessInfo processInfo] environment][@"ENTRY_OUT"];
		if (!outDir) { fprintf(stderr, "ENTRY_OUT is missing\n"); return 1; }

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		[NSApp activateIgnoringOtherApps:YES];
		spin(1.0);

		EntryAdium *stub = [[EntryAdium alloc] init];
		stub.preferenceController = [[EntryNothing alloc] init];
		setSharedAdium((id)stub);

		AIMessageEntryAccessory *formula = accessoryNamed(@"FormulaEditor", @"entry_formula");
		AIMessageEntryAccessory *voice = accessoryNamed(@"VoiceNote", @"entry_voice");
		AIMessageEntryAccessory *emoticons = accessoryNamed(@"Emoticons", @"entry_emoticons");

		/* Left to right as the application registers them: the smiley last, so it keeps
		 * the place at the edge it has always had. */
		NSArray *jobs = @[@[@"three", @[formula, voice, emoticons]],
						  @[@"one", @[emoticons]],
						  @[@"none", @[]]];

		NSString *text = @"The field ends where the buttons begin, so a line this long wraps before it "
						 @"reaches them instead of running on underneath.";

		for (NSString *mode in @[@"light", @"dark"]) {
			NSAppearance *appearance = [NSAppearance appearanceNamed:
										([mode isEqualToString:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua)];
			NSApp.appearance = appearance;

			for (NSArray *job in jobs) {
				//The same arrangement as the conversation window: the field in a bordered scroll view
				NSRect content = NSMakeRect(0.0, 0.0, 420.0, 64.0);
				NSWindow *window = [[NSWindow alloc] initWithContentRect:content
															  styleMask:NSWindowStyleMaskTitled
																backing:NSBackingStoreBuffered
																  defer:NO];
				window.title = [NSString stringWithFormat:@"%@ %@", job[0], mode];
				window.appearance = appearance;

				NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSInsetRect(window.contentView.bounds, 8.0, 8.0)];
				scrollView.borderType = NSBezelBorder;
				scrollView.hasVerticalScroller = NO;
				scrollView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);

				AIMessageEntryTextView *field = [[AIMessageEntryTextView alloc] initWithFrame:
												 NSMakeRect(0.0, 0.0, scrollView.contentSize.width, scrollView.contentSize.height)];
				field.autoresizingMask = NSViewWidthSizable;
				[field setVerticallyResizable:YES];
				[field setHorizontallyResizable:NO];
				[field.textContainer setWidthTracksTextView:YES];
				[field setTextContainerInset:NSMakeSize(0, 2)];
				[field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];

				scrollView.documentView = field;
				[window.contentView addSubview:scrollView];

				[NSApp activateIgnoringOtherApps:YES];
				[window setFrameOrigin:NSMakePoint(200.0, 300.0)];
				[window makeKeyAndOrderFront:nil];
				spin(0.4);

				[field setAccessories:job[1]];
				[field setString:text];
				spin(0.6);

				NSArray *accessories = [field accessories];
				fprintf(stderr, "%s/%s: %lu buttons, field %.0f wide in a %.0f wide clip view\n",
						[job[0] UTF8String], [mode UTF8String], (unsigned long)accessories.count,
						NSWidth(field.frame), NSWidth(field.superview.bounds));

				writePNG(window, [outDir stringByAppendingPathComponent:
								  [NSString stringWithFormat:@"entry-%@-%@.png", job[0], mode]]);
				[window orderOut:nil];
			}
		}
	}
	return 0;
}
