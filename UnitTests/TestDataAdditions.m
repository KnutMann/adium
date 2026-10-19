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
#import "TestDataAdditions.h"
#import "AIUnitTestUtilities.h"

#import <AIUtilities/AIDataAdditions.h>

enum {
	lengthForSubdataTests = 6U,
	fromIndexForSubdataTests = 3U,
	toIndexForSubdataTests = 3U,
	subdataLengthForSubdataTests = 3U
};
#define lengthForSubdataTests 6U
#define fromIndexForSubdataTests 3U
#define toIndexForSubdataTests 3U
#define subdataLengthForSubdataTests 3U
static char bytesForSubdataTests[lengthForSubdataTests] = { 'f', 'o', 'o', 'b', 'a', 'r' };

/* Adopts NSCoding and not NSSecureCoding: the header says the pair below archives and decodes
 * without secure coding so that old user archives stay readable, and only such a class shows it. */
@interface AIDataAdditionsPlainCoder : NSObject <NSCoding>
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSInteger number;
@end

@implementation AIDataAdditionsPlainCoder
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:self.name forKey:@"name"];
	[coder encodeInteger:self.number forKey:@"number"];
}
- (id)initWithCoder:(NSCoder *)coder
{
	if ((self = [super init])) {
		_name = [[coder decodeObjectForKey:@"name"] copy];
		_number = [coder decodeIntegerForKey:@"number"];
	}
	return self;
}
@end

@implementation TestDataAdditions

- (void)testSubdataFromIndex {
	NSData *data = [NSData dataWithBytesNoCopy:bytesForSubdataTests length:lengthForSubdataTests freeWhenDone:NO];

	NSData *subdata = [data subdataFromIndex:fromIndexForSubdataTests];
	XCTAssertEqual([subdata length], (NSUInteger)subdataLengthForSubdataTests, @"Subdata was not of expected length");

	const char *bytes = [subdata bytes];
	//Cast explanation: Character literals are of type int. XCTAssertEqual compares with ==, and const char is not int, so the literals are cast to const char to keep both sides the same type.
	XCTAssertEqual(bytes[0], (const char)'b', @"Unexpected first byte of subdata: 0x%x %c", bytes[0], bytes[0]);
	XCTAssertEqual(bytes[1], (const char)'a', @"Unexpected second byte of subdata: 0x%x %c", bytes[1], bytes[1]);
	XCTAssertEqual(bytes[2], (const char)'r', @"Unexpected third byte of subdata: 0x%x %c", bytes[2], bytes[2]);
}
- (void)testSubdataToIndex {
	NSData *data = [NSData dataWithBytesNoCopy:bytesForSubdataTests length:lengthForSubdataTests freeWhenDone:NO];

	NSData *subdata = [data subdataToIndex:toIndexForSubdataTests];
	XCTAssertEqual([subdata length], (NSUInteger)subdataLengthForSubdataTests, @"Subdata was not of expected length");

	const char *bytes = [subdata bytes];
	//Cast explanation: Character literals are of type int. XCTAssertEqual compares with ==, and const char is not int, so the literals are cast to const char to keep both sides the same type.
	XCTAssertEqual(bytes[0], (const char)'f', @"Unexpected first byte of subdata: 0x%x %c", bytes[0], bytes[0]);
	XCTAssertEqual(bytes[1], (const char)'o', @"Unexpected second byte of subdata: 0x%x %c", bytes[1], bytes[1]);
	XCTAssertEqual(bytes[2], (const char)'o', @"Unexpected third byte of subdata: 0x%x %c", bytes[2], bytes[2]);
}

#pragma mark Subdata boundaries

- (NSData *)foobar
{
	return [@"foobar" dataUsingEncoding:NSASCIIStringEncoding];
}

- (void)testSubdataFromIndexZeroIsTheWholeData
{
	XCTAssertEqualObjects([[self foobar] subdataFromIndex:0], [self foobar]);
}

- (void)testSubdataFromTheLengthIsEmpty
{
	XCTAssertEqual([[[self foobar] subdataFromIndex:6] length], (NSUInteger)0);
}

- (void)testSubdataFromBeyondTheLengthThrows
{
	XCTAssertThrowsSpecificNamed([[self foobar] subdataFromIndex:7], NSException, NSRangeException);
}

- (void)testSubdataToIndexZeroIsEmpty
{
	XCTAssertEqual([[[self foobar] subdataToIndex:0] length], (NSUInteger)0);
}

- (void)testSubdataToTheLengthIsTheWholeData
{
	XCTAssertEqualObjects([[self foobar] subdataToIndex:6], [self foobar]);
}

- (void)testSubdataToBeyondTheLengthThrows
{
	XCTAssertThrowsSpecificNamed([[self foobar] subdataToIndex:7], NSException, NSRangeException);
}

- (void)testSubdataToAndFromAnIndexAreComplementary
{
	NSMutableData *joined = [[[self foobar] subdataToIndex:2] mutableCopy];
	[joined appendData:[[self foobar] subdataFromIndex:2]];
	XCTAssertEqualObjects(joined, [self foobar]);
}

#pragma mark Keyed archives

- (void)testArchiveRoundTripsPropertyListValues
{
	NSDictionary *object = @{@"string": @"caf\u00e9", @"number": @42, @"date": [NSDate dateWithTimeIntervalSinceReferenceDate:1234.5], @"list": @[@1, @2], @"data": [@"bytes" dataUsingEncoding:NSUTF8StringEncoding]};
	NSData *archive = [NSKeyedArchiver archivedDataWithObject:object];
	XCTAssertNotNil(archive);
	XCTAssertEqualObjects([NSKeyedUnarchiver objectWithArchivedData:archive], object);
}

- (void)testArchiveRoundTripsAClassWithoutSecureCoding
{
	AIDataAdditionsPlainCoder *original = [[AIDataAdditionsPlainCoder alloc] init];
	original.name = @"plain";
	original.number = -7;
	NSData *archive = [NSKeyedArchiver archivedDataWithObject:original];
	XCTAssertNotNil(archive);

	AIDataAdditionsPlainCoder *decoded = [NSKeyedUnarchiver objectWithArchivedData:archive];
	XCTAssertTrue([decoded isKindOfClass:[AIDataAdditionsPlainCoder class]]);
	XCTAssertEqualObjects(decoded.name, @"plain");
	XCTAssertEqual(decoded.number, (NSInteger)-7);
}

- (void)testArchivedDataIsAKeyedArchive
{
	NSData *archive = [NSKeyedArchiver archivedDataWithObject:@"x"];
	NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:archive options:0 format:NULL error:NULL];
	XCTAssertEqualObjects([plist objectForKey:@"$archiver"], @"NSKeyedArchiver");
}

/* The two deprecated calls are used on purpose: the header's promise is byte compatibility with
 * what they wrote and read, and only they can check it. */
- (void)testArchiveIsReadableByTheDeprecatedUnarchiver
{
	NSData *archive = [NSKeyedArchiver archivedDataWithObject:@[@"a", @1]];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	id decoded = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
#pragma clang diagnostic pop
	XCTAssertEqualObjects(decoded, (@[@"a", @1]));
}

- (void)testDeprecatedArchiveIsReadableByTheNewUnarchiver
{
	AIDataAdditionsPlainCoder *original = [[AIDataAdditionsPlainCoder alloc] init];
	original.name = @"legacy";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:original];
#pragma clang diagnostic pop
	AIDataAdditionsPlainCoder *decoded = [NSKeyedUnarchiver objectWithArchivedData:archive];
	XCTAssertEqualObjects(decoded.name, @"legacy");
}

- (void)testUnarchivingNilIsNil
{
	XCTAssertNil([NSKeyedUnarchiver objectWithArchivedData:nil]);
}

- (void)testUnarchivingGarbageIsNil
{
	XCTAssertNil([NSKeyedUnarchiver objectWithArchivedData:[@"garbage" dataUsingEncoding:NSUTF8StringEncoding]]);
}

- (void)testUnarchivingEmptyDataIsNil
{
	XCTAssertNil([NSKeyedUnarchiver objectWithArchivedData:[NSData data]]);
}

@end
