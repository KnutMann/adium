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

/* AIBoolToControlTextColorTransformer.h is not among the framework's public headers; the class has
 * nothing to declare beyond what NSValueTransformer does. */
@interface AIBoolToControlTextColorTransformer : NSValueTransformer
@end

@interface TestBoolToControlTextColorTransformer : XCTestCase
@end

@implementation TestBoolToControlTextColorTransformer {
	AIBoolToControlTextColorTransformer *transformer;
}

- (void)setUp
{
	[super setUp];
	transformer = [[AIBoolToControlTextColorTransformer alloc] init];
}

- (void)testProducesColoursAndOnlyForwards
{
	XCTAssertEqual([AIBoolToControlTextColorTransformer transformedValueClass], [NSColor class]);
	XCTAssertFalse([AIBoolToControlTextColorTransformer allowsReverseTransformation]);
}

- (void)testYesIsTheControlTextColour
{
	XCTAssertEqualObjects([transformer transformedValue:@YES], [NSColor controlTextColor]);
}

- (void)testNoIsTheDisabledControlTextColour
{
	XCTAssertEqualObjects([transformer transformedValue:@NO], [NSColor disabledControlTextColor]);
}

- (void)testAnythingWithABoolValueIsRead
{
	XCTAssertEqualObjects([transformer transformedValue:@"YES"], [NSColor controlTextColor]);
	XCTAssertEqualObjects([transformer transformedValue:@"0"], [NSColor disabledControlTextColor]);
	XCTAssertEqualObjects([transformer transformedValue:@2], [NSColor controlTextColor]);
}

- (void)testNilAndObjectsWithoutABoolValueGiveNothing
{
	XCTAssertNil([transformer transformedValue:nil]);
	XCTAssertNil([transformer transformedValue:[[NSObject alloc] init]]);
	XCTAssertNil([transformer transformedValue:[NSDate dateWithTimeIntervalSince1970:0]]);
}

@end
