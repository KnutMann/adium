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

#import <Adium/AITextAttachmentExtension.h>

@interface TestTextAttachmentExtension : XCTestCase
@end

/* A red picture of the given size, with a bitmap behind it so that it can be drawn and saved. */
static NSImage *imageOfSize(NSInteger width, NSInteger height)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
																	pixelsWide:width
																	pixelsHigh:height
																 bitsPerSample:8
															   samplesPerPixel:4
																	  hasAlpha:YES
																	  isPlanar:NO
																colorSpaceName:NSCalibratedRGBColorSpace
																   bytesPerRow:0
																  bitsPerPixel:0];
	for (NSInteger x = 0; x < width; x++) {
		for (NSInteger y = 0; y < height; y++) {
			[rep setColor:[NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:1] atX:x y:y];
		}
	}
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
	[image addRepresentation:rep];
	return image;
}

static NSData *PNGDataOf(NSImage *image)
{
	return [(NSBitmapImageRep *)[[image representations] firstObject] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

@implementation TestTextAttachmentExtension {
	NSString *scratchDirectory;
}

- (void)setUp
{
	[super setUp];
	scratchDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:scratchDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
	[[NSFileManager defaultManager] removeItemAtPath:scratchDirectory error:NULL];
	[super tearDown];
}

- (NSString *)writeFile:(NSString *)name contents:(NSData *)data
{
	NSString *path = [scratchDirectory stringByAppendingPathComponent:name];
	XCTAssertTrue([data writeToFile:path atomically:YES]);
	return path;
}

#pragma mark Plain properties

- (void)testANewAttachmentHasNothingSet
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	XCTAssertFalse(attachment.shouldSaveImageForLogging);
	XCTAssertFalse(attachment.hasAlternate);
	XCTAssertFalse(attachment.shouldAlwaysSendAsText);
	XCTAssertFalse(attachment.leavesLinkWhenSent);
	XCTAssertNil(attachment.imageClass);
	XCTAssertNil(attachment.path);
	XCTAssertNil([attachment image]);
	XCTAssertFalse(attachment.attachesAnImage);
	XCTAssertNil(attachment.iconImage);
}

- (void)testAStringIsMadeUpOnceWhenNoneWasGiven
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	NSString *first = attachment.string;
	XCTAssertGreaterThan([first length], (NSUInteger)0);
	XCTAssertEqualObjects(attachment.string, first);
	XCTAssertNotEqualObjects([[AITextAttachmentExtension alloc] init].string, first);
}

- (void)testTheStringIsCopiedOnTheWayIn
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	NSMutableString *name = [NSMutableString stringWithString:@"picture"];
	attachment.string = name;
	[name appendString:@" changed"];
	XCTAssertEqualObjects(attachment.string, @"picture");
	attachment.imageClass = @"emoticon";
	XCTAssertEqualObjects(attachment.imageClass, @"emoticon");
}

- (void)testACopyCarriesEveryField
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	NSImage *image = imageOfSize(3, 2);
	attachment.string = @"picture";
	attachment.imageClass = @"emoticon";
	attachment.path = @"/nonexistent/picture.png";
	[attachment setImage:image];
	attachment.shouldSaveImageForLogging = YES;
	attachment.hasAlternate = YES;
	attachment.shouldAlwaysSendAsText = YES;
	attachment.leavesLinkWhenSent = YES;

	AITextAttachmentExtension *copy = [attachment copy];
	XCTAssertNotEqual(copy, attachment);
	XCTAssertEqualObjects(copy.string, @"picture");
	XCTAssertEqualObjects(copy.imageClass, @"emoticon");
	XCTAssertEqualObjects(copy.path, @"/nonexistent/picture.png");
	XCTAssertEqual([copy image], image);
	XCTAssertTrue(copy.shouldSaveImageForLogging);
	XCTAssertTrue(copy.hasAlternate);
	XCTAssertTrue(copy.shouldAlwaysSendAsText);
	XCTAssertTrue(copy.leavesLinkWhenSent);
}

#pragma mark Archiving

- (AITextAttachmentExtension *)archiveAndRestore:(AITextAttachmentExtension *)attachment
{
	NSError *error = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:attachment requiringSecureCoding:NO error:&error];
	XCTAssertNotNil(data, @"%@", error);
	NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
	XCTAssertNotNil(unarchiver, @"%@", error);
	unarchiver.requiresSecureCoding = NO;
	AITextAttachmentExtension *restored = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
	[unarchiver finishDecoding];
	return restored;
}

- (void)testKeyedArchivingKeepsTheStringPathAndFlags
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	attachment.string = @"picture";
	attachment.path = @"/nonexistent/picture.png";
	attachment.shouldSaveImageForLogging = YES;
	attachment.hasAlternate = YES;
	attachment.shouldAlwaysSendAsText = YES;

	AITextAttachmentExtension *restored = [self archiveAndRestore:attachment];
	XCTAssertTrue([restored isKindOfClass:[AITextAttachmentExtension class]]);
	XCTAssertEqualObjects(restored.string, @"picture");
	XCTAssertEqualObjects(restored.path, @"/nonexistent/picture.png");
	XCTAssertTrue(restored.shouldSaveImageForLogging);
	XCTAssertTrue(restored.hasAlternate);
	XCTAssertTrue(restored.shouldAlwaysSendAsText);
}

- (void)testKeyedArchivingKeepsTheImageClassAndTheLinkFlag
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	attachment.imageClass = @"emoticon";
	attachment.leavesLinkWhenSent = YES;
	AITextAttachmentExtension *restored = [self archiveAndRestore:attachment];
	XCTAssertEqualObjects(restored.imageClass, @"emoticon");
	XCTAssertTrue(restored.leavesLinkWhenSent);
}

#pragma mark Images and paths

- (void)testAnImageMakesItAnImageAttachment
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	[attachment setImage:imageOfSize(3, 2)];
	XCTAssertTrue(attachment.attachesAnImage);
	XCTAssertTrue(NSEqualSizes([[attachment image] size], NSMakeSize(3, 2)));
}

- (void)testAPathToAPNGIsAnImageAttachmentAndLoadsTheImage
{
	NSString *path = [self writeFile:@"three-by-two.png" contents:PNGDataOf(imageOfSize(3, 2))];
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	attachment.path = path;
	XCTAssertTrue(attachment.attachesAnImage);
	XCTAssertTrue(NSEqualSizes([[attachment image] size], NSMakeSize(3, 2)));
	XCTAssertEqualObjects(attachment.path, path);
}

- (void)testAPathToATextFileIsNotAnImageAttachment
{
	NSString *path = [self writeFile:@"notes.txt" contents:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]];
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	attachment.path = path;
	XCTAssertFalse(attachment.attachesAnImage);
	XCTAssertNil([attachment image]);
	XCTAssertNotNil(attachment.iconImage);
}

- (void)testAnImageWithoutAPathIsWrittenOutWhenThePathIsAskedFor
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	[attachment setImage:imageOfSize(3, 2)];
	attachment.string = @"picture";

	NSString *path = attachment.path;
	XCTAssertNotNil(path);
	XCTAssertTrue([path hasPrefix:NSTemporaryDirectory()], @"%@", path);
	XCTAssertEqualObjects([path lastPathComponent], @"picture.png");
	XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path]);
	XCTAssertEqualObjects(attachment.path, path);
	XCTAssertTrue(NSEqualSizes([[[NSImage alloc] initWithContentsOfFile:path] size], NSMakeSize(3, 2)));
	[[NSFileManager defaultManager] removeItemAtPath:[path stringByDeletingLastPathComponent] error:NULL];
}

- (void)testIconImageIsTheImageItselfWhenSmallEnough
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	NSImage *image = imageOfSize(3, 2);
	[attachment setImage:image];
	NSImage *icon = attachment.iconImage;
	XCTAssertNotEqual(icon, image);
	XCTAssertTrue(NSEqualSizes([icon size], NSMakeSize(3, 2)));
}

- (void)testIconImageIsScaledDownForALargeImage
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	[attachment setImage:imageOfSize(200, 100)];
	NSSize size = [attachment.iconImage size];
	XCTAssertLessThanOrEqual(size.width, 64.0);
	XCTAssertLessThanOrEqual(size.height, 64.0);
	XCTAssertGreaterThan(size.width, 0.0);
}

#pragma mark File wrappers

- (void)testFileWrapperIsMadeFromTheImageAsPNG
{
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	[attachment setImage:imageOfSize(3, 2)];
	NSFileWrapper *wrapper = [attachment fileWrapper];
	XCTAssertTrue([wrapper isRegularFile]);
	XCTAssertTrue([[wrapper preferredFilename] hasSuffix:@".png"]);
	XCTAssertGreaterThan([[wrapper regularFileContents] length], (NSUInteger)0);
	XCTAssertEqual([attachment fileWrapper], wrapper);
}

- (void)testFileWrapperIsMadeFromThePath
{
	NSString *path = [self writeFile:@"three-by-two.png" contents:PNGDataOf(imageOfSize(3, 2))];
	AITextAttachmentExtension *attachment = [[AITextAttachmentExtension alloc] init];
	attachment.path = path;
	NSFileWrapper *wrapper = [attachment fileWrapper];
	XCTAssertEqualObjects([wrapper preferredFilename], @"three-by-two.png");
	XCTAssertEqualObjects([wrapper regularFileContents], [NSData dataWithContentsOfFile:path]);
}

- (void)testMadeFromAPlainTextAttachmentItTakesTheFileNameAndImage
{
	NSFileWrapper *wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:PNGDataOf(imageOfSize(3, 2))];
	wrapper.preferredFilename = @"pasted.png";
	NSTextAttachment *plain = [[NSTextAttachment alloc] initWithFileWrapper:wrapper];

	AITextAttachmentExtension *attachment = [AITextAttachmentExtension textAttachmentExtensionFromTextAttachment:plain];
	XCTAssertEqualObjects(attachment.string, @"pasted.png");
	XCTAssertTrue(attachment.shouldSaveImageForLogging);
	XCTAssertTrue(attachment.attachesAnImage);
	XCTAssertTrue(NSEqualSizes([[attachment image] size], NSMakeSize(3, 2)));
}

@end
