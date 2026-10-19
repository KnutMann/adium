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

#import <AIUtilities/AIImageAdditions.h>
#import <ImageIO/ImageIO.h>

@interface TestImageAdditions : XCTestCase
@end

/* Every image a test starts from is drawn here: an sRGB bitmap at one pixel per point, so what
 * a test reads back owes nothing to the display's scale factor or profile. The representations
 * the category produces through lockFocus do follow the main screen, which is why the tests on
 * those only ever look at colours and aspect ratios, never at pixel counts. */
static NSImage *AIImageDrawnBy(NSInteger width, NSInteger height, void (^draw)(void))
{
	CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
												 (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGColorSpaceRelease(space);

	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO]];
	draw();
	[NSGraphicsContext restoreGraphicsState];

	CGImageRef cgImage = CGBitmapContextCreateImage(context);
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
	[rep setSize:NSMakeSize(width, height)];
	CGImageRelease(cgImage);
	CGContextRelease(context);

	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
	[image addRepresentation:rep];
	return image;
}

static NSImage *AISolidImage(NSInteger width, NSInteger height, NSColor *color)
{
	return AIImageDrawnBy(width, height, ^{
		[color set];
		NSRectFill(NSMakeRect(0, 0, width, height));
	});
}

static NSColor *AIRed(void)  { return [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1]; }
static NSColor *AIBlue(void) { return [NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:1]; }

/* Noise compresses badly, which is what the byte-limit tests need: a solid colour fits any limit. */
static NSImage *AINoiseImage(NSInteger side)
{
	return AIImageDrawnBy(side, side, ^{
		uint32_t state = 12345;
		for (NSInteger y = 0; y < side; y++) {
			for (NSInteger x = 0; x < side; x++) {
				state = state * 1103515245u + 12345u;
				[[NSColor colorWithSRGBRed:((state >> 16) & 0xff) / 255.0
									 green:((state >> 8) & 0xff) / 255.0
									  blue:(state & 0xff) / 255.0
									 alpha:1] set];
				NSRectFill(NSMakeRect(x, y, 1, 1));
			}
		}
	});
}

/* A two frame animation, red for half a second and then blue for a whole one, written by ImageIO
 * so that the bytes are what any other program would hand the category. */
static NSData *AITwoFrameGIF(void)
{
	NSMutableData *data = [NSMutableData data];
	CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,
																		 CFSTR("com.compuserve.gif"), 2, NULL);
	CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)@{
		(id)kCGImagePropertyGIFDictionary: @{ (id)kCGImagePropertyGIFLoopCount: @0 }
	});

	NSArray<NSColor *> *colors = @[AIRed(), AIBlue()];
	NSArray<NSNumber *> *delays = @[@0.5, @1.0];
	for (NSUInteger i = 0; i < 2; i++) {
		NSBitmapImageRep *frame = (NSBitmapImageRep *)[[AISolidImage(8, 8, colors[i]) representations] firstObject];
		CGImageDestinationAddImage(destination, [frame CGImage], (__bridge CFDictionaryRef)@{
			(id)kCGImagePropertyGIFDictionary: @{ (id)kCGImagePropertyGIFDelayTime: delays[i] }
		});
	}
	CGImageDestinationFinalize(destination);
	CFRelease(destination);
	return data;
}

static NSImage *AIAnimatedImage(void)
{
	return [[NSImage alloc] initWithData:AITwoFrameGIF()];
}

static NSData *AIBytes(const char *bytes, NSUInteger length)
{
	return [NSData dataWithBytes:bytes length:length];
}

static NSBitmapImageRep *AIDecode(NSData *data)
{
	return [NSBitmapImageRep imageRepWithData:data];
}

/* The components as the representation stores them, in its own colour space: a PNG or GIF
 * carries what was written, and these tests use colours that are the same in every RGB space.
 * GIF quantisation and PNG rounding move a channel by a step or two, nowhere near a quarter. */
#define AIAssertColor(color, r, g, b, a) do { \
	NSColor *read = (color); \
	XCTAssertNotNil(read); \
	XCTAssertEqualWithAccuracy([read redComponent], (r), 0.25); \
	XCTAssertEqualWithAccuracy([read greenComponent], (g), 0.25); \
	XCTAssertEqualWithAccuracy([read blueComponent], (b), 0.25); \
	XCTAssertEqualWithAccuracy([read alphaComponent], (a), 0.25); \
} while (0)

@implementation TestImageAdditions

#pragma mark File types

- (void)testFileTypeOfDataRecognisesGIF
{
	XCTAssertEqual([NSImage fileTypeOfData:AIBytes("GIF89a\x01\x00", 8)], AIGIFFileType);
	XCTAssertEqual([NSImage fileTypeOfData:AITwoFrameGIF()], AIGIFFileType);
}

- (void)testFileTypeOfDataRecognisesJPEG
{
	XCTAssertEqual([NSImage fileTypeOfData:AIBytes("\xff\xd8\xff\xe0", 4)], AIJPEGFileType);
	XCTAssertEqual([NSImage fileTypeOfData:AIBytes("\xff\xd8\xff\xe1", 4)], AIJPEGFileType, @"any APPn marker may follow the SOI");
	XCTAssertEqual([NSImage fileTypeOfData:[AISolidImage(4, 4, AIRed()) JPEGRepresentation]], AIJPEGFileType);
}

- (void)testFileTypeOfDataRecognisesPNG
{
	XCTAssertEqual([NSImage fileTypeOfData:AIBytes("\x89PNG\r\n\x1a\n", 8)], AIPNGFileType);
	XCTAssertEqual([NSImage fileTypeOfData:[AISolidImage(4, 4, AIRed()) PNGRepresentation]], AIPNGFileType);
}

- (void)testFileTypeOfDataRecognisesTIFFInEitherByteOrder
{
	XCTAssertEqual([NSImage fileTypeOfData:AIBytes("MM\x00\x2a", 4)], AITIFFFileType);
	XCTAssertEqual([NSImage fileTypeOfData:AIBytes("II\x2a\x00", 4)], AITIFFFileType);
}

- (void)testFileTypeOfDataRecognisesBMP
{
	XCTAssertEqual([NSImage fileTypeOfData:AIBytes("BM\x36\x00", 4)], AIBMPFileType);
	XCTAssertEqual([NSImage fileTypeOfData:[AISolidImage(4, 4, AIRed()) BMPRepresentation]], AIBMPFileType);
}

- (void)testFileTypeOfDataIsUnknownForAnythingElse
{
	XCTAssertEqual([NSImage fileTypeOfData:AIBytes("ABCD", 4)], AIUnknownFileType);
	XCTAssertEqual([NSImage fileTypeOfData:AIBytes("BM", 2)], AIUnknownFileType, @"fewer than four bytes is no picture");
	XCTAssertEqual([NSImage fileTypeOfData:[NSData data]], AIUnknownFileType);
	XCTAssertEqual([NSImage fileTypeOfData:nil], AIUnknownFileType);
}

- (void)testExtensionForBitmapImageFileTypeNamesEveryType
{
	XCTAssertEqualObjects([NSImage extensionForBitmapImageFileType:AITIFFFileType], @"tif");
	XCTAssertEqualObjects([NSImage extensionForBitmapImageFileType:AIBMPFileType], @"bmp");
	XCTAssertEqualObjects([NSImage extensionForBitmapImageFileType:AIGIFFileType], @"gif");
	XCTAssertEqualObjects([NSImage extensionForBitmapImageFileType:AIJPEGFileType], @"jpg");
	XCTAssertEqualObjects([NSImage extensionForBitmapImageFileType:AIPNGFileType], @"png");
	XCTAssertEqualObjects([NSImage extensionForBitmapImageFileType:AIJPEG2000FileType], @"jp2");
}

- (void)testExtensionForUnknownFileTypeIsNil
{
	XCTAssertNil([NSImage extensionForBitmapImageFileType:AIUnknownFileType]);
}

#pragma mark Loading

- (void)testImageNamedForClassIsNilWhenTheBundleHasNoSuchPicture
{
	XCTAssertNil([NSImage imageNamed:@"AIThereIsNoPictureOfThisName" forClass:[self class]]);
	XCTAssertNil([NSImage imageNamed:@"AIThereIsNoPictureOfThisName" forClass:[self class] loadLazily:YES]);
}

- (void)testImageForSSLIsASmallValidIconHandedOutOnce
{
	NSImage *icon = [NSImage imageForSSL];

	XCTAssertNotNil(icon);
	XCTAssertTrue([icon isValid]);
	XCTAssertGreaterThan([icon size].height, 0);
	XCTAssertLessThanOrEqual([icon size].height, 16.0, @"capped so that menu titles beside it keep their height");
	XCTAssertTrue(icon == [NSImage imageForSSL], @"the icon is cached");
}

#pragma mark Representations

- (void)testLargestBitmapImageRepIsTheWidestOfSeveral
{
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
	NSBitmapImageRep *small = (NSBitmapImageRep *)[[AISolidImage(16, 16, AIRed()) representations] firstObject];
	NSBitmapImageRep *large = (NSBitmapImageRep *)[[AISolidImage(32, 32, AIRed()) representations] firstObject];
	[image addRepresentation:large];
	[image addRepresentation:small];

	XCTAssertTrue([image largestBitmapImageRep] == large);
}

- (void)testLargestBitmapImageRepIsForgedWhenTheImageHasNoBitmap
{
	NSImage *drawn = [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect rect) {
		[AIRed() set];
		NSRectFill(rect);
		return YES;
	}];
	XCTAssertFalse([[[drawn representations] firstObject] isKindOfClass:[NSBitmapImageRep class]], @"precondition");

	NSBitmapImageRep *rep = [drawn largestBitmapImageRep];
	XCTAssertTrue([rep isKindOfClass:[NSBitmapImageRep class]]);
	XCTAssertGreaterThan([rep pixelsWide], 0);
}

- (void)testJPEGRepresentationDecodesWithTheImagesAspectRatio
{
	NSBitmapImageRep *decoded = AIDecode([AISolidImage(20, 10, AIRed()) JPEGRepresentation]);

	XCTAssertNotNil(decoded);
	XCTAssertEqual([decoded pixelsWide], 2 * [decoded pixelsHigh]);
	/* The JPEG is drawn through lockFocus, in the main display's profile, and the profile is
	 * then stripped: the red that comes back is the display's, so only its dominance is pinned. */
	NSColor *middle = [decoded colorAtX:5 y:5];
	XCTAssertGreaterThan([middle redComponent], 0.6);
	XCTAssertLessThan([middle greenComponent], 0.4);
	XCTAssertLessThan([middle blueComponent], 0.4);
}

- (void)testJPEGRepresentationReplacesTransparencyWithWhite
{
	NSImage *transparent = AIImageDrawnBy(8, 8, ^{});

	NSBitmapImageRep *decoded = AIDecode([transparent JPEGRepresentation]);
	XCTAssertNotNil(decoded);
	AIAssertColor([decoded colorAtX:2 y:2], 1, 1, 1, 1);
}

- (void)testJPEGRepresentationWithALowerCompressionFactorIsNotLarger
{
	NSImage *noise = AINoiseImage(64);

	NSData *fine = [noise JPEGRepresentationWithCompressionFactor:1.0f];
	NSData *coarse = [noise JPEGRepresentationWithCompressionFactor:0.3f];
	XCTAssertNotNil(fine);
	XCTAssertNotNil(coarse);
	XCTAssertLessThan([coarse length], [fine length]);
	XCTAssertEqual([NSImage fileTypeOfData:coarse], AIJPEGFileType);
}

- (void)testJPEGRepresentationWithMaximumByteSizeStaysWithinTheLimit
{
	NSImage *noise = AINoiseImage(64);
	NSUInteger limit = [[noise JPEGRepresentation] length] / 2;

	NSData *limited = [noise JPEGRepresentationWithMaximumByteSize:limit];
	XCTAssertNotNil(limited);
	XCTAssertLessThanOrEqual([limited length], limit);

	NSBitmapImageRep *decoded = AIDecode(limited);
	XCTAssertEqual([decoded pixelsWide], [decoded pixelsHigh], @"the dimensions are unchanged, only the quality drops");
}

- (void)testJPEGRepresentationWithMaximumByteSizeIsNilWhenNoCompressionFits
{
	XCTAssertNil([AINoiseImage(64) JPEGRepresentationWithMaximumByteSize:10]);
}

- (void)testPNGRepresentationKeepsPixelsAndAlpha
{
	NSImage *image = AIImageDrawnBy(4, 4, ^{
		[[NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:0.5] set];
		NSRectFill(NSMakeRect(0, 0, 2, 4));
		[[NSColor colorWithSRGBRed:0 green:1 blue:0 alpha:1] set];
		NSRectFill(NSMakeRect(2, 0, 2, 4));
	});

	NSData *png = [image PNGRepresentation];
	XCTAssertEqual([NSImage fileTypeOfData:png], AIPNGFileType);

	NSBitmapImageRep *decoded = AIDecode(png);
	XCTAssertEqual([decoded pixelsWide], 4);
	XCTAssertEqual([decoded pixelsHigh], 4);
	AIAssertColor([decoded colorAtX:0 y:0], 0, 0, 1, 0.5);
	AIAssertColor([decoded colorAtX:3 y:3], 0, 1, 0, 1);
}

- (void)testBMPRepresentationReplacesTransparencyWithWhite
{
	NSData *bmp = [AIImageDrawnBy(8, 8, ^{}) BMPRepresentation];

	XCTAssertEqual([NSImage fileTypeOfData:bmp], AIBMPFileType);
	AIAssertColor([AIDecode(bmp) colorAtX:4 y:4], 1, 1, 1, 1);
}

- (void)testGIFRepresentationOfAStillImageIsASingleFrameGIF
{
	NSData *gif = [AISolidImage(8, 8, AIRed()) GIFRepresentation];

	XCTAssertEqual([NSImage fileTypeOfData:gif], AIGIFFileType);
	NSBitmapImageRep *decoded = AIDecode(gif);
	XCTAssertEqual([decoded pixelsWide], 8);
	XCTAssertLessThanOrEqual([[decoded valueForProperty:NSImageFrameCount] intValue], 1);
	AIAssertColor([decoded colorAtX:4 y:4], 1, 0, 0, 1);
}

- (void)testGIFRepresentationOfAnAnimationKeepsEveryFrameInOrder
{
	NSBitmapImageRep *decoded = AIDecode([AIAnimatedImage() GIFRepresentation]);

	XCTAssertEqual([[decoded valueForProperty:NSImageFrameCount] intValue], 2);
	[decoded setProperty:NSImageCurrentFrame withValue:@0];
	AIAssertColor([decoded colorAtX:4 y:4], 1, 0, 0, 1);
	[decoded setProperty:NSImageCurrentFrame withValue:@1];
	AIAssertColor([decoded colorAtX:4 y:4], 0, 0, 1, 1);
}

- (void)testGIFRepresentationOfAnAnimationKeepsEachFramesDuration
{
	XCTExpectFailure(@"writeGIFExtensionBlocksInData:forRepresenation: (AIImageAdditions.m, the while loop over the graphic control blocks) searches the blocks from the end but reads the durations from the start, so frame i is given the duration of frame count-1-i: the red frame comes back with the blue frame's second");
	NSBitmapImageRep *decoded = AIDecode([AIAnimatedImage() GIFRepresentation]);

	[decoded setProperty:NSImageCurrentFrame withValue:@0];
	XCTAssertEqualWithAccuracy([[decoded valueForProperty:NSImageCurrentFrameDuration] doubleValue], 0.5, 0.02);
	[decoded setProperty:NSImageCurrentFrame withValue:@1];
	XCTAssertEqualWithAccuracy([[decoded valueForProperty:NSImageCurrentFrameDuration] doubleValue], 1.0, 0.02);
}

- (void)testGIFRepresentationIsNilForAnImageWithoutRepresentations
{
	XCTAssertNil([[[NSImage alloc] initWithSize:NSMakeSize(8, 8)] GIFRepresentation]);
}

- (void)testBestRepresentationByTypeIsPNGForAStillImage
{
	XCTAssertEqual([NSImage fileTypeOfData:[AISolidImage(8, 8, AIRed()) bestRepresentationByType]], AIPNGFileType);
}

- (void)testBestRepresentationByTypeIsGIFForAnAnimation
{
	NSData *data = [AIAnimatedImage() bestRepresentationByType];

	XCTAssertEqual([NSImage fileTypeOfData:data], AIGIFFileType);
	XCTAssertEqual([[AIDecode(data) valueForProperty:NSImageFrameCount] intValue], 2);
}

- (void)testBestRepresentationByTypeIsNilForAnImageWithoutRepresentations
{
	XCTExpectFailure(@"bestRepresentationByType (AIImageAdditions.m) asks the empty representations array for objectAtIndex:0 and raises NSRangeException; GIFRepresentation was fixed for the same case and answers nil");
	NSImage *empty = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];

	@try {
		XCTAssertNil([empty bestRepresentationByType]);
	} @catch (NSException *exception) {
		XCTFail(@"raised %@: %@", [exception name], [exception reason]);
	}
}

- (void)testRepresentationWithFileTypeWithoutALimitIsTheFullSizePicture
{
	NSData *bmp = [AISolidImage(400, 200, AIRed()) representationWithFileType:NSBitmapImageFileTypeBMP maximumFileSize:0];

	XCTAssertEqual([NSImage fileTypeOfData:bmp], AIBMPFileType);
	XCTAssertEqual([AIDecode(bmp) pixelsWide], 400);
	XCTAssertEqual([AIDecode(bmp) pixelsHigh], 200);
}

- (void)testRepresentationWithFileTypeShrinksToTheLimitKeepingTheAspectRatio
{
	NSImage *image = AISolidImage(400, 200, AIRed());
	/* BMP is uncompressed, so the size is the pixel count and one step of the shrinking is
	 * exactly what one byte less than the full picture asks for. */
	NSUInteger full = [[image representationWithFileType:NSBitmapImageFileTypeBMP maximumFileSize:0] length];

	NSData *smaller = [image representationWithFileType:NSBitmapImageFileTypeBMP maximumFileSize:full - 1];
	XCTAssertNotNil(smaller);
	XCTAssertLessThan([smaller length], full);
	NSBitmapImageRep *decoded = AIDecode(smaller);
	XCTAssertLessThan([decoded pixelsWide], 400);
	XCTAssertEqual([decoded pixelsWide], 2 * [decoded pixelsHigh]);
}

- (void)testGIFPropertiesForRepresentationCarryTheFrameCountAndStartAtTheFirstFrame
{
	NSImage *animated = AIAnimatedImage();
	NSBitmapImageRep *rep = (NSBitmapImageRep *)[[animated representations] firstObject];

	NSDictionary *properties = [animated GIFPropertiesForRepresentation:rep];
	XCTAssertEqualObjects(properties[NSImageFrameCount], @2);
	XCTAssertEqualObjects(properties[NSImageCurrentFrame], @0);
}

- (void)testGIFPropertiesForAStillRepresentationSayOneFrame
{
	NSImage *still = AISolidImage(8, 8, AIRed());
	NSBitmapImageRep *rep = (NSBitmapImageRep *)[[still representations] firstObject];

	XCTAssertEqualObjects([still GIFPropertiesForRepresentation:rep][NSImageFrameCount], @1);
}

@end
