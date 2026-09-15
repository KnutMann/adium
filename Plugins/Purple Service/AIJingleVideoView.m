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

#import "AIJingleVideoView.h"

#import <CoreImage/CoreImage.h>
#import <WebRTC/RTCVideoFrame.h>
#import <WebRTC/RTCVideoFrameBuffer.h>
#import <WebRTC/RTCCVPixelBuffer.h>
#import <WebRTC/RTCI420Buffer.h>
#import <WebRTC/RTCYUVPlanarBuffer.h>

@implementation AIJingleVideoView {
	CIContext *imageContext;
	dispatch_queue_t conversionQueue;
	NSInteger blackInARow;			//only ever touched on conversionQueue
	BOOL converting;			//only ever touched on conversionQueue
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		[self setWantsLayer:YES];
		[[self layer] setBackgroundColor:[[NSColor blackColor] CGColor]];
		[[self layer] setContentsGravity:kCAGravityResizeAspect];

		/* TRAP: a layer does not keep its picture to itself. Told to fill rather
		 * than fit, it scales the picture up until the shorter side is covered and
		 * then draws the overhang straight past its own edges, over whatever
		 * happens to be below. In a call window that is the bar with the clock and
		 * the switches, which simply vanished under the other person's face. */
		[[self layer] setMasksToBounds:YES];

		imageContext = [CIContext contextWithOptions:nil];
		conversionQueue = dispatch_queue_create("adium.jingle.video", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

//What the connection hands us -------------------------------------------------------------------
#pragma mark What the connection hands us

- (void)setFillsTheFrame:(BOOL)filling
{
	_fillsTheFrame = filling;
	[[self layer] setContentsGravity:(filling ? kCAGravityResizeAspectFill : kCAGravityResizeAspect)];
}

- (void)setSize:(CGSize)size
{
	//The frames themselves carry their size; nothing to keep here
}

- (void)renderFrame:(RTCVideoFrame *)frame
{
	if (!frame)
		return;

	dispatch_async(conversionQueue, ^{
		/* One frame at a time: a picture nobody has drawn yet is worth less than
		 * the next one, and a queue of them would only add delay. */
		if (self->converting)
			return;
		self->converting = YES;

		CGImageRef image = [self createImageFromFrame:frame];
		CGSize size = CGSizeMake(frame.width, frame.height);

		dispatch_async(dispatch_get_main_queue(), ^{
			if (image) {
				[[self layer] setContents:(__bridge id)image];
				CGImageRelease(image);
				self->_renderedFrames++;
				self->_lastFrameSize = size;
			}
			dispatch_async(self->conversionQueue, ^{
				self->converting = NO;
			});
		});
	});
}

//Is anybody actually there? ----------------------------------------------------------------------
#pragma mark Is anybody actually there?

/*!
 * @brief How many frames in a row have been pure black
 *
 * Guessing from the picture, because the protocol says nothing. A client that
 * switches its camera off does not necessarily say so: XEP-0167 has the words for
 * it and one of the two clients measured against never speaks them, it simply
 * disables its own track. WebRTC then keeps sending, at thirty frames a second,
 * and every one of them is black. From the outside that is indistinguishable from
 * a working camera in an unlit room, which is why this only ever decides what
 * icon to draw and never anything that matters.
 *
 * Pure black means pure: a real dark room carries sensor noise and lands well
 * above this, while a switched-off track is filled with the one exact value.
 */
#define BLACK_ENOUGH		24		//out of 255
#define BLACK_LONG_ENOUGH	20		//frames in a row, so under a second

- (void)noteWhetherItIsBlack:(BOOL)black
{
	if (!black) {
		self->blackInARow = 0;
		self->_looksBlack = NO;
		return;
	}

	if (self->blackInARow < BLACK_LONG_ENOUGH)
		self->blackInARow++;
	else
		self->_looksBlack = YES;
}

/*! @brief A grid of samples rather than every pixel; a black picture is black everywhere */
- (BOOL)pixelBufferIsBlack:(CVPixelBufferRef)pixels
{
	if (!pixels || CVPixelBufferGetPixelFormatType(pixels) != kCVPixelFormatType_32BGRA)
		return NO;			//a format we cannot read cheaply is not worth guessing about

	CVPixelBufferLockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);
	const uint8_t *base = CVPixelBufferGetBaseAddress(pixels);
	size_t stride = CVPixelBufferGetBytesPerRow(pixels);
	size_t width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels);
	BOOL black = (base && width && height);

	for (int down = 0; black && down < 8; down++)
		for (int across = 0; across < 8; across++) {
			const uint8_t *pixel = base + (height * down / 8) * stride + (width * across / 8) * 4;
			if (pixel[0] > BLACK_ENOUGH || pixel[1] > BLACK_ENOUGH || pixel[2] > BLACK_ENOUGH) {
				black = NO;
				break;
			}
		}

	CVPixelBufferUnlockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);
	return black;
}

/*! @brief The same question of the brightness plane, which is the only one that matters here */
- (BOOL)planesAreBlack:(id<RTCI420Buffer>)planes
{
	if (!planes || planes.width <= 0 || planes.height <= 0 || !planes.dataY)
		return NO;

	for (int down = 0; down < 8; down++)
		for (int across = 0; across < 8; across++) {
			int row = planes.height * down / 8, column = planes.width * across / 8;
			if (planes.dataY[row * planes.strideY + column] > BLACK_ENOUGH)
				return NO;
		}
	return YES;
}

//Turning a frame into a picture ------------------------------------------------------------------
#pragma mark Turning a frame into a picture

- (CGImageRef)createImageFromFrame:(RTCVideoFrame *)frame CF_RETURNS_RETAINED
{
	id<RTCVideoFrameBuffer> buffer = frame.buffer;
	CIImage *picture = nil;

	if ([buffer isKindOfClass:[RTCCVPixelBuffer class]]) {
		//What a hardware decoder hands over, and the cheapest road to a picture
		CVPixelBufferRef pixels = [(RTCCVPixelBuffer *)buffer pixelBuffer];
		[self noteWhetherItIsBlack:[self pixelBufferIsBlack:pixels]];
		picture = [CIImage imageWithCVPixelBuffer:pixels];
	} else {
		id<RTCI420Buffer> planes = [buffer toI420];
		[self noteWhetherItIsBlack:[self planesAreBlack:planes]];
		picture = [self imageFromPlanes:planes];
	}

	if (!picture)
		return NULL;

	//The camera says which way up it was held
	switch (frame.rotation) {
		case RTCVideoRotation_90:
			picture = [picture imageByApplyingCGOrientation:kCGImagePropertyOrientationRight];
			break;
		case RTCVideoRotation_180:
			picture = [picture imageByApplyingCGOrientation:kCGImagePropertyOrientationDown];
			break;
		case RTCVideoRotation_270:
			picture = [picture imageByApplyingCGOrientation:kCGImagePropertyOrientationLeft];
			break;
		default:
			break;
	}

	return [imageContext createCGImage:picture fromRect:[picture extent]];
}

/*!
 * @brief Three planes of brightness and colour, made into one picture
 *
 * The road a software decoder's frames take. Done by hand rather than through a
 * helper, because the arithmetic is the standard one and a wrong picture is
 * easier to see than to describe.
 */
- (CIImage *)imageFromPlanes:(id<RTCI420Buffer>)planes
{
	if (!planes)
		return nil;

	int width = planes.width, height = planes.height;
	if (width <= 0 || height <= 0)
		return nil;

	size_t bytesPerRow = (size_t)width * 4;
	NSMutableData *pixels = [NSMutableData dataWithLength:(bytesPerRow * (size_t)height)];
	uint8_t *out = [pixels mutableBytes];

	const uint8_t *y = planes.dataY, *u = planes.dataU, *v = planes.dataV;
	int strideY = planes.strideY, strideU = planes.strideU, strideV = planes.strideV;

	for (int row = 0; row < height; row++) {
		for (int column = 0; column < width; column++) {
			int brightness = y[row * strideY + column] - 16;
			int blueness = u[(row / 2) * strideU + (column / 2)] - 128;
			int redness = v[(row / 2) * strideV + (column / 2)] - 128;

			int red   = (298 * brightness + 409 * redness + 128) >> 8;
			int green = (298 * brightness - 100 * blueness - 208 * redness + 128) >> 8;
			int blue  = (298 * brightness + 516 * blueness + 128) >> 8;

			uint8_t *pixel = out + row * bytesPerRow + column * 4;
			pixel[0] = (uint8_t)MIN(255, MAX(0, red));
			pixel[1] = (uint8_t)MIN(255, MAX(0, green));
			pixel[2] = (uint8_t)MIN(255, MAX(0, blue));
			pixel[3] = 255;
		}
	}

	return [CIImage imageWithBitmapData:pixels
							bytesPerRow:bytesPerRow
									size:CGSizeMake(width, height)
								  format:kCIFormatRGBA8
							  colorSpace:CGColorSpaceCreateDeviceRGB()];
}

@end
