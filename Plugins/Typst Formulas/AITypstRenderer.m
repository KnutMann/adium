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

#import "AITypstRenderer.h"
#import <Adium/AITextAttachmentExtension.h>
#import <AIUtilities/AIStringUtilities.h>

/* Rendered at this many dots per inch and drawn at this size, a formula of ordinary length comes out
 * a few hundred pixels wide. Twice the nominal 72 gives a picture that still holds up when the
 * recipient's phone scales it onto a display finer than the one it was made on.
 *
 * This number decides sharpness and nothing else. typst writes no pHYs chunk, so the PNG carries no
 * physical resolution of its own, and a reader that is handed only the file has to assume 72 dots to
 * the inch, which would make the pixel count the display size as well. Callers therefore ask for the
 * size separately, with naturalSizeForPixelSize, and raising the resolution here no longer makes the
 * formula grow on screen. */
#define TYPST_RENDER_PPI		150
#define TYPST_DEFAULT_POINTSIZE	32.0

/*!
 * @brief The document every formula is compiled inside
 *
 * Every line earns its place.
 *
 * "width: auto, height: auto" makes the page shrink to its contents, which is what produces a tight
 * crop rather than a formula adrift on a sheet of paper.
 *
 * Black on an opaque white page, deliberately, and not the colour of wherever the formula was typed.
 * A transparent picture takes on the background of whatever displays it, and that background is out of
 * our hands the moment the file leaves: a formula drawn in the entry field's own colour arrives as
 * black on black in a phone's dark theme, or vanishes entirely. Carrying its own contrast is the only
 * way the image reads the same everywhere. The margin is wide enough that the glyphs do not touch the
 * edge of that white card.
 *
 * The show rule is the one that looks superfluous and is not. Without it the page is measured against
 * the font's metrics rather than the glyphs that were actually drawn, and anything reaching beyond
 * them is sliced off: the same formula measures 198 pixels tall instead of 303, cutting through the
 * summation sign and the fraction bar.
 *
 * eval with mode "math" is what lets the caller pass bare math syntax without the surrounding dollar
 * signs, and sys.inputs is what keeps the formula out of the command line, so nothing has to be
 * escaped and a stray quote cannot break the document.
 */
static NSString * const AITypstDocumentTemplate =
	@"#set page(width: auto, height: auto, margin: 0.6em, fill: white)\n"
	@"#set text(size: %.1fpt, fill: black)\n"
	@"#show math.equation: set text(top-edge: \"bounds\", bottom-edge: \"bounds\")\n"
	@"#eval(sys.inputs.eq, mode: \"math\")\n";

@interface AITypstRenderer ()
- (BOOL)beginRenderingFormula:(NSString *)formula
					pointSize:(CGFloat)pointSize
				   completion:(void (^)(NSString *path, NSString *errorMessage))handler;
- (void)taskDidFinish;
- (void)cleanUpSourceDirectory;
@end

@implementation AITypstRenderer

+ (NSString *)typstPath
{
	static NSString *cachedPath = nil;
	static BOOL		 didLook = NO;

	if (!didLook) {
		didLook = YES;

		/* Absolute paths only. A GUI application is started by launchd and inherits a PATH that has
		 * never seen a shell profile, so /opt/homebrew/bin is simply not in it and looking the name
		 * up would fail on exactly the machines where typst is installed. The order is the one a
		 * person is most likely to have used. */
		NSArray *candidates = [NSArray arrayWithObjects:
							   @"/opt/homebrew/bin/typst",
							   @"/usr/local/bin/typst",
							   [NSHomeDirectory() stringByAppendingPathComponent:@".cargo/bin/typst"],
							   @"/opt/local/bin/typst",
							   nil];

		for (NSString *candidate in candidates) {
			if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
				cachedPath = candidate;
				break;
			}
		}
	}

	return cachedPath;
}

+ (BOOL)typstIsAvailable
{
	return ([self typstPath] != nil);
}

+ (NSSize)naturalSizeForPixelSize:(NSSize)pixelSize
{
	CGFloat scale = 72.0 / (CGFloat)TYPST_RENDER_PPI;

	return NSMakeSize(pixelSize.width * scale, pixelSize.height * scale);
}

+ (void)discardRenderAtPath:(NSString *)path
{
	if (![path length]) return;

	/* A render owns the directory it was given, so removing the directory is what removes the render,
	 * document and picture together. Guarding on the file name keeps a path from somewhere else, or a
	 * path that has already been discarded, from taking a directory with it. */
	if (![[path lastPathComponent] isEqualToString:@"formula.png"]) return;

	NSString *directory = [path stringByDeletingLastPathComponent];

	/* Both sides standardized the same way, or the comparison fails on a machine where the temporary
	 * directory is reached through a symbolic link, which is the usual case: /var is a link to
	 * /private/var, and only one of the two strings would have been resolved. */
	NSString *parent = [[directory stringByDeletingLastPathComponent] stringByStandardizingPath];
	NSString *temporary = [NSTemporaryDirectory() stringByStandardizingPath];

	if ([parent isEqualToString:temporary])
		[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

+ (NSAttributedString *)attachmentStringForImageAtPath:(NSString *)path formula:(NSString *)formula
{
	NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
	if (!image) return nil;

	/* Tell the image how large it is meant to be drawn. Left alone it answers with its pixel count,
	 * because the file says nothing about resolution, and the formula then fills the entry field and
	 * runs off the right hand edge. This changes only how it is drawn: the representation keeps every
	 * pixel, and the pixels are what gets sent. */
	NSImageRep *rep = [[image representations] lastObject];
	if (rep) {
		[image setSize:[self naturalSizeForPixelSize:NSMakeSize((CGFloat)[rep pixelsWide],
																(CGFloat)[rep pixelsHigh])]];
	}

	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	[attachment setPath:path];
	[attachment setString:formula];
	[attachment setShouldSaveImageForLogging:YES];
	[attachment setImage:image];

	/* The same image object goes to the attachment and to the cell on purpose. The entry field takes
	 * its layout from the cell, the message view writes its width and height from the attachment's
	 * image, and the log writes them from the cell. Two images of differing sizes would make those
	 * three disagree. */
	[attachment setAttachmentCell:[[NSTextAttachmentCell alloc] initImageCell:image]];

	return [NSAttributedString attributedStringWithAttachment:attachment];
}

+ (AITypstRenderer *)renderFormula:(NSString *)formula
						 pointSize:(CGFloat)pointSize
						completion:(void (^)(NSString *path, NSString *errorMessage))handler
{
	AITypstRenderer *renderer = [[AITypstRenderer alloc] init];

	if (![renderer beginRenderingFormula:formula pointSize:pointSize completion:handler])
		return nil;

	return renderer;
}

- (BOOL)beginRenderingFormula:(NSString *)formula
					pointSize:(CGFloat)pointSize
				   completion:(void (^)(NSString *path, NSString *errorMessage))handler
{
	NSString *typst = [AITypstRenderer typstPath];
	if (!typst) {
		if (handler)
			handler(nil, AILocalizedString(@"Typst is not installed. Install it with \"brew install typst\".", nil));
		return NO;
	}

	completion = [handler copy];

	if (pointSize <= 0.0) pointSize = TYPST_DEFAULT_POINTSIZE;

	/* A directory per render. The document and its output live together and are removed together, and
	 * two renders started a keystroke apart cannot collide. */
	NSString *unique = [[NSProcessInfo processInfo] globallyUniqueString];
	sourceDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:unique];

	NSError *error = nil;
	if (![[NSFileManager defaultManager] createDirectoryAtPath:sourceDirectory
								  withIntermediateDirectories:YES
												   attributes:nil
														error:&error]) {
		if (completion)
			completion(nil, [error localizedDescription]);
		return NO;
	}

	NSString *documentPath = [sourceDirectory stringByAppendingPathComponent:@"formula.typ"];
	outputPath = [sourceDirectory stringByAppendingPathComponent:@"formula.png"];

	NSString *document = [NSString stringWithFormat:AITypstDocumentTemplate, (double)pointSize];
	if (![document writeToFile:documentPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
		if (completion)
			completion(nil, [error localizedDescription]);
		return NO;
	}

	task = [[NSTask alloc] init];
	[task setLaunchPath:typst];
	[task setArguments:[NSArray arrayWithObjects:
						@"compile", documentPath, outputPath,
						@"--ppi", [NSString stringWithFormat:@"%d", TYPST_RENDER_PPI],
						/* typst carries its own fonts, so ignoring the system's makes the result the
						 * same on every machine and skips a scan of the font directories. */
						@"--ignore-system-fonts",
						@"--diagnostic-format", @"short",
						@"--input", [NSString stringWithFormat:@"eq=%@", (formula ? formula : @"")],
						nil]];

	errorPipe = [[NSPipe alloc] init];
	[task setStandardError:errorPipe];
	[task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];

	/* A termination handler rather than NSTaskDidTerminateNotification. That notification is only
	 * delivered on the run loop of the thread which launched the task, and here it never arrived at
	 * all: typst ran, wrote its PNG and exited, and nothing was ever called back. The handler is
	 * called on a queue of NSTask's choosing whatever the caller was doing, which is why the work is
	 * hopped to the main thread below rather than assumed to be on it.
	 *
	 * The block retains self, and self owns the task which owns the block, so the handler clears
	 * itself once it has run. Without that the renderer would never be deallocated. */
	[task setTerminationHandler:^(NSTask *finishedTask) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self taskDidFinish];
			[finishedTask setTerminationHandler:nil];
		});
	}];

	@try {
		[task launch];
	} @catch (NSException *exception) {
		[task setTerminationHandler:nil];
		if (completion)
			completion(nil, [exception reason]);
		return NO;
	}

	return YES;
}

- (void)taskDidFinish
{
	NSData	 *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
	NSString *errorText = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];

	/* The file, not the exit status, is what says whether this worked. typst reports its own failures
	 * on standard error and simply writes nothing, and there is no sense in handing back a path to a
	 * file that is not there. */
	BOOL didProduceImage = [[NSFileManager defaultManager] fileExistsAtPath:outputPath];

	if (completion) {
		if (didProduceImage) {
			completion(outputPath, nil);
		} else {
			/* typst points at the line and column inside our own template, which means nothing to
			 * somebody who typed a formula. Keep the description, drop the position. */
			NSString *message = [errorText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			NSRange   errorWord = [message rangeOfString:@"error: "];
			if (errorWord.location != NSNotFound)
				message = [message substringFromIndex:NSMaxRange(errorWord)];
			if (![message length])
				message = AILocalizedString(@"Typst could not render this formula.", nil);

			[self cleanUpSourceDirectory];
			completion(nil, message);
		}

		completion = nil;
	}
}

- (void)cancel
{
	if (!task) return;

	[task setTerminationHandler:nil];

	if ([task isRunning])
		[task terminate];

	completion = nil;

	[self cleanUpSourceDirectory];
}

- (void)cleanUpSourceDirectory
{
	if (sourceDirectory)
		[[NSFileManager defaultManager] removeItemAtPath:sourceDirectory error:NULL];
}

@end
