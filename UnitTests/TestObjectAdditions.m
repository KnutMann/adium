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
#import <AIUtilities/AIObjectAdditions.h>

@interface TestObjectAdditions : XCTestCase
{
	NSMutableArray *received;
}
- (void)noteNothing;
- (void)noteOne:(id)a;
- (void)noteOne:(id)a two:(id)b;
- (void)noteOne:(id)a two:(id)b three:(id)c;
- (void)noteOne:(id)a two:(id)b three:(id)c four:(id)d;
- (NSString *)constantName;
- (NSString *)constantNameFor:(id)a;
- (NSString *)constantNameFor:(id)a and:(id)b;
@end

@implementation TestObjectAdditions

- (void)setUp
{
	[super setUp];
	received = [NSMutableArray array];
	XCTAssertTrue([NSThread isMainThread], @"These tests rely on running on the main thread, where a waited-for main-thread perform happens before the call returns");
}

- (id)boxed:(id)object
{
	return object ?: [NSNull null];
}

- (void)noteNothing { [received addObject:@"nothing"]; }
- (void)noteOne:(id)a { [received addObject:@[[self boxed:a]]]; }
- (void)noteOne:(id)a two:(id)b { [received addObject:@[[self boxed:a], [self boxed:b]]]; }
- (void)noteOne:(id)a two:(id)b three:(id)c { [received addObject:@[[self boxed:a], [self boxed:b], [self boxed:c]]]; }
- (void)noteOne:(id)a two:(id)b three:(id)c four:(id)d { [received addObject:@[[self boxed:a], [self boxed:b], [self boxed:c], [self boxed:d]]]; }
- (NSString *)constantName { return @"constant"; }
- (NSString *)constantNameFor:(id)a { return @"constant-one"; }
- (NSString *)constantNameFor:(id)a and:(id)b { return @"constant-two"; }

#pragma mark Main thread, waiting

- (void)testWaitedMainPerformWithoutArgumentsHasRunOnReturn
{
	[self mainPerformSelector:@selector(noteNothing) waitUntilDone:YES];
	XCTAssertEqualObjects(received, @[@"nothing"]);
}

- (void)testWaitedMainPerformWithOneArgumentDeliversIt
{
	[self mainPerformSelector:@selector(noteOne:) withObject:@"a" waitUntilDone:YES];
	XCTAssertEqualObjects(received, @[@[@"a"]]);
}

- (void)testWaitedMainPerformWithTwoArgumentsDeliversBothInOrder
{
	[self mainPerformSelector:@selector(noteOne:two:) withObject:@"a" withObject:@"b" waitUntilDone:YES];
	XCTAssertEqualObjects(received, (@[@[@"a", @"b"]]));
}

- (void)testWaitedMainPerformWithThreeArgumentsDeliversAllInOrder
{
	[self mainPerformSelector:@selector(noteOne:two:three:) withObject:@"a" withObject:@"b" withObject:@"c" waitUntilDone:YES];
	XCTAssertEqualObjects(received, (@[@[@"a", @"b", @"c"]]));
}

- (void)testWaitedMainPerformWithFourArgumentsDeliversAllInOrder
{
	[self mainPerformSelector:@selector(noteOne:two:three:four:) withObject:@"a" withObject:@"b" withObject:@"c" withObject:@"d" waitUntilDone:YES];
	XCTAssertEqualObjects(received, (@[@[@"a", @"b", @"c", @"d"]]));
}

- (void)testNilArgumentsArriveAsNil
{
	[self mainPerformSelector:@selector(noteOne:two:) withObject:nil withObject:@"b" waitUntilDone:YES];
	XCTAssertEqualObjects(received, (@[@[[NSNull null], @"b"]]));
}

- (void)testArgumentsAreDeliveredByIdentityNotCopied
{
	NSMutableString *argument = [NSMutableString stringWithString:@"a"];
	[self mainPerformSelector:@selector(noteOne:) withObject:argument waitUntilDone:YES];
	XCTAssertTrue([[received firstObject] firstObject] == argument);
}

#pragma mark Return values

/* Constant strings only. The method writes the invocation's return value into a strong variable
 * without retaining it (AIObjectAdditions.m:47, :87, :119, :164), so anything with a finite lifetime
 * is released once too often, which kills the process rather than failing a test. A constant string
 * ignores the extra release, so these pin the value that comes back and nothing else. */
- (void)testReturnValueWithoutArgumentsIsHandedBack
{
	XCTAssertEqualObjects([self mainPerformSelector:@selector(constantName) returnValue:YES], @"constant");
}

- (void)testReturnValueWithOneArgumentIsHandedBack
{
	XCTAssertEqualObjects([self mainPerformSelector:@selector(constantNameFor:) withObject:@"a" returnValue:YES], @"constant-one");
}

- (void)testReturnValueWithTwoArgumentsIsHandedBack
{
	XCTAssertEqualObjects([self mainPerformSelector:@selector(constantNameFor:and:) withObject:@"a" withObject:@"b" returnValue:YES], @"constant-two");
}

#pragma mark Current thread

- (void)testPerformWithThreeArgumentsRunsBeforeReturning
{
	[self performSelector:@selector(noteOne:two:three:) withObject:@"a" withObject:@"b" withObject:@"c"];
	XCTAssertEqualObjects(received, (@[@[@"a", @"b", @"c"]]));
}

- (void)testHandleInvocationInvokesItOnTheReceiver
{
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(noteOne:)]];
	[invocation setSelector:@selector(noteOne:)];
	id argument = @"from-invocation";
	[invocation setArgument:&argument atIndex:2];
	[self handleInvocation:invocation];
	XCTAssertEqualObjects(received, @[@[@"from-invocation"]]);
}

@end
