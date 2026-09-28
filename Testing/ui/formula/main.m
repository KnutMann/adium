/* A harness that shows the formula editor without running Adium.
 *
 * The editor asks the program for the remembered formulas and for nothing else it
 * cannot do without, so a stand-in that answers that one question and every other
 * with nothing is enough to put it on screen and photograph it. The pictures in it
 * are rendered by Typst, as they are in the application. There is no conversation
 * behind it, so the preview is put there by hand from a rendered formula.
 */
#import <Cocoa/Cocoa.h>

#import <Adium/AISharedAdium.h>

#import "AITypstEditorView.h"
#import "AITypstRenderer.h"

#pragma mark A program that answers nothing

/* Every question is answered with nothing rather than with a crash. The answer has to be
 * written, not left alone: the return buffer of an invocation starts out as whatever was
 * on the stack, so a forwarded call that nobody answers hands back a garbage pointer. */
@interface FormulaNothing : NSObject
@end

@implementation FormulaNothing
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

//The preference store: the remembered formulas, and nothing else
@interface FormulaPreferences : FormulaNothing
@property (nonatomic, strong) NSArray *formulas;
@end

@implementation FormulaPreferences
- (id)preferenceForKey:(NSString *)key group:(NSString *)group
{
	return ([key isEqualToString:@"Formula History"] ? self.formulas : nil);
}
- (void)setPreference:(id)value forKey:(NSString *)key group:(NSString *)group
{
	if ([key isEqualToString:@"Formula History"]) self.formulas = value;
}
@end

@interface FormulaAdium : FormulaNothing
@property (nonatomic, strong) FormulaPreferences *preferenceController;
@end

@implementation FormulaAdium
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

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		NSString *outDir = [[NSProcessInfo processInfo] environment][@"FORMULA_OUT"];
		if (!outDir) { fprintf(stderr, "FORMULA_OUT is missing\n"); return 1; }
		if (![AITypstRenderer typstIsAvailable]) { fprintf(stderr, "Typst is not installed\n"); return 1; }

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		[NSApp activateIgnoringOtherApps:YES];
		spin(1.0);

		FormulaPreferences *prefs = [[FormulaPreferences alloc] init];
		prefs.formulas = @[@"sum_(i=1)^n x_i^2 / n",
						   @"integral_0^oo e^(-x^2) dif x = sqrt(pi) / 2",
						   @"E = m c^2",
						   @"lim_(n -> oo) (1 + 1/n)^n = e",
						   @"a^2 + b^2 = c^2"];
		FormulaAdium *stub = [[FormulaAdium alloc] init];
		stub.preferenceController = prefs;
		setSharedAdium((id)stub);

		/* The preview, rendered once; the editor has no conversation to follow here */
		__block NSImage *preview = nil;
		__block BOOL rendered = NO;
		[AITypstRenderer renderFormula:@"sum_(i=1)^n x_i^2 / n = sigma^2 + mu^2"
							 pointSize:0.0
							completion:^(NSString *path, NSString *errorMessage) {
			if (path) {
				preview = [[NSImage alloc] initWithContentsOfFile:path];
				NSImageRep *rep = [[preview representations] lastObject];
				if (rep) [preview setSize:[AITypstRenderer naturalSizeForPixelSize:NSMakeSize(rep.pixelsWide, rep.pixelsHigh)]];
			} else {
				fprintf(stderr, "no preview: %s\n", errorMessage.UTF8String);
			}
			rendered = YES;
		}];
		while (!rendered) spin(0.1);

		/* Two heights: the one a shelf opens at today, and the one the editor asks for */
		for (NSString *mode in @[@"light", @"dark"]) {
			NSAppearance *appearance = [NSAppearance appearanceNamed:
										([mode isEqualToString:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua)];
			NSApp.appearance = appearance;

			AITypstEditorView *editor = [[AITypstEditorView alloc] initWithChat:(id)[[FormulaNothing alloc] init]];
			CGFloat fitting = ceil([editor fittingSize].height);
			NSArray *heights = @[@260.0, @(MAX(120.0, fitting))];

			for (NSNumber *height in heights) {
				NSRect content = NSMakeRect(0.0, 0.0, 480.0, [height doubleValue]);
				NSWindow *window = [[NSWindow alloc] initWithContentRect:content
															  styleMask:NSWindowStyleMaskTitled
																backing:NSBackingStoreBuffered
																  defer:NO];
				window.title = [NSString stringWithFormat:@"formula editor %@ %@", height, mode];
				window.appearance = appearance;
				editor.frame = window.contentView.bounds;
				editor.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
				[window.contentView addSubview:editor];

				[[editor valueForKey:@"imageView_preview"] setImage:preview];
				[[editor valueForKey:@"button_send"] setEnabled:(preview != nil)];
				[[editor valueForKey:@"textField_placeholder"] setHidden:(preview != nil)];

				[NSApp activateIgnoringOtherApps:YES];
				[window setFrameOrigin:NSMakePoint(200.0, 300.0)];
				[window makeKeyAndOrderFront:nil];
				spin(2.5);		//the thumbnails render one after another

				fprintf(stderr, "%s at %.0f: fitting height %.0f\n", [mode UTF8String], [height doubleValue], fitting);
				writePNG(window, [outDir stringByAppendingPathComponent:
								  [NSString stringWithFormat:@"formula-%@-%@.png", height, mode]]);
				[editor removeFromSuperview];
				[window orderOut:nil];
			}
		}
	}
	return 0;
}
