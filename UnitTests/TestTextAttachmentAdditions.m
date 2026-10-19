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
#import <AIUtilities/AITextAttachmentAdditions.h>

@interface TestTextAttachmentAdditions : XCTestCase
@end

@implementation TestTextAttachmentAdditions

- (BOOL)isImageExtension:(NSString *)extension
{
	return [[[NSTextAttachment alloc] init] consideredImageForHFSType:0 pathExtension:extension];
}

- (NSTextAttachment *)attachmentWrappingAFileNamed:(NSString *)name
{
	NSFileWrapper *wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:[NSData data]];
	wrapper.preferredFilename = name;
	wrapper.filename = name;
	return [[NSTextAttachment alloc] initWithFileWrapper:wrapper];
}

#pragma mark Extensions

- (void)testBitmapExtensionsAreImages
{
	XCTAssertTrue([self isImageExtension:@"png"]);
	XCTAssertTrue([self isImageExtension:@"jpg"]);
	XCTAssertTrue([self isImageExtension:@"jpeg"]);
	XCTAssertTrue([self isImageExtension:@"gif"]);
	XCTAssertTrue([self isImageExtension:@"tiff"]);
	XCTAssertTrue([self isImageExtension:@"bmp"]);
}

- (void)testExtensionIsMatchedCaseInsensitively
{
	XCTAssertTrue([self isImageExtension:@"PNG"]);
	XCTAssertTrue([self isImageExtension:@"Jpg"]);
}

- (void)testPDFIsNotAnImageAlthoughNSImageOpensIt
{
	XCTAssertFalse([self isImageExtension:@"pdf"]);
}

- (void)testPhotoshopDocumentIsNotAnImage
{
	XCTAssertFalse([self isImageExtension:@"psd"]);
}

- (void)testTextAndArchivesAreNotImages
{
	XCTAssertFalse([self isImageExtension:@"txt"]);
	XCTAssertFalse([self isImageExtension:@"zip"]);
	XCTAssertFalse([self isImageExtension:@"html"]);
}

- (void)testMissingExtensionIsNotAnImage
{
	XCTAssertFalse([self isImageExtension:@""]);
	XCTAssertFalse([self isImageExtension:nil]);
}

- (void)testUnknownExtensionIsNotAnImage
{
	XCTAssertFalse([self isImageExtension:@"zzqxv"]);
}

- (void)testHFSTypeCodeIsIgnored
{
	NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
	XCTAssertFalse([attachment consideredImageForHFSType:'PNGf' pathExtension:nil], @"A type code without an extension is no image");
	XCTAssertTrue([attachment consideredImageForHFSType:'TEXT' pathExtension:@"png"], @"The extension decides");
}

#pragma mark Wrapped files

- (void)testAttachmentWithoutAFileWrapperWrapsNoImage
{
	XCTAssertFalse([[[NSTextAttachment alloc] init] wrapsImage]);
}

- (void)testWrapsImageFollowsTheWrappedFileName
{
	XCTAssertTrue([[self attachmentWrappingAFileNamed:@"photo.png"] wrapsImage]);
	XCTAssertTrue([[self attachmentWrappingAFileNamed:@"Scan.JPG"] wrapsImage]);
	XCTAssertFalse([[self attachmentWrappingAFileNamed:@"notes.txt"] wrapsImage]);
	XCTAssertFalse([[self attachmentWrappingAFileNamed:@"paper.pdf"] wrapsImage]);
	XCTAssertFalse([[self attachmentWrappingAFileNamed:@"README"] wrapsImage]);
}

@end
