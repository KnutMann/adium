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

#import <Adium/AIXMLElement.h>

@interface TestXMLElement : XCTestCase
@end

@implementation TestXMLElement

/* What the element writes has to be XML, so the parser is the judge of escaping, not the bytes. */
- (NSXMLElement *)parsedRootOf:(AIXMLElement *)element
{
	NSError *error = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:[element XMLString] options:0 error:&error];
	XCTAssertNotNil(document, @"%@ did not parse: %@", [element XMLString], error);
	return [document rootElement];
}

#pragma mark Names

- (void)testElementHasTheNameItWasMadeWith
{
	AIXMLElement *element = [AIXMLElement elementWithName:@"p"];
	XCTAssertEqualObjects([element name], @"p");
	XCTAssertEqualObjects([element XMLString], @"<p></p>");
	XCTAssertEqualObjects([[[AIXMLElement alloc] initWithName:@"span"] name], @"span");
}

- (void)testNamespacePrefixesTheName
{
	XCTAssertEqualObjects([[AIXMLElement elementWithNamespaceName:@"x" elementName:@"p"] name], @"x:p");
	XCTAssertEqualObjects([[AIXMLElement elementWithNamespaceName:nil elementName:@"p"] name], @"p");
	XCTAssertEqualObjects([[[AIXMLElement alloc] initWithNamespaceName:@"x" elementName:@"p"] XMLString], @"<x:p></x:p>");
}

- (void)testInitWithoutANameIsRefused
{
	XCTAssertThrows((void)[[AIXMLElement alloc] init]);
}

#pragma mark Self-closing

- (void)testBRSelfClosesByDefaultWhateverItsCase
{
	XCTAssertTrue([[AIXMLElement elementWithName:@"br"] selfCloses]);
	XCTAssertEqualObjects([[AIXMLElement elementWithName:@"br"] XMLString], @"<br />");
	XCTAssertEqualObjects([[AIXMLElement elementWithName:@"BR"] XMLString], @"<BR />");
	XCTAssertFalse([[AIXMLElement elementWithName:@"p"] selfCloses]);
}

- (void)testSelfClosingElementWithContentsWritesBothTags
{
	AIXMLElement *br = [AIXMLElement elementWithName:@"br"];
	[br addObject:@"x"];
	XCTAssertEqualObjects([br XMLString], @"<br>x</br>");
}

- (void)testSelfClosesCanBeTurnedOnForAnyElement
{
	AIXMLElement *img = [AIXMLElement elementWithName:@"img"];
	img.selfCloses = YES;
	[img setValue:@"a.png" forAttribute:@"src"];
	XCTAssertEqualObjects([img XMLString], @"<img src=\"a.png\" />");
}

#pragma mark Attributes

- (void)testAttributesKeepTheirOrderAndAReplacedValueKeepsItsPlace
{
	AIXMLElement *element = [AIXMLElement elementWithName:@"p"];
	[element setValue:@"1" forAttribute:@"a"];
	[element setValue:@"2" forAttribute:@"b"];
	[element setValue:@"3" forAttribute:@"a"];
	XCTAssertEqual([element numberOfAttributes], (NSUInteger)2);
	XCTAssertEqualObjects([element XMLString], @"<p a=\"3\" b=\"2\"></p>");
	XCTAssertEqualObjects([element attributes], (@{ @"a": @"3", @"b": @"2" }));
	XCTAssertEqualObjects([element valueForAttribute:@"b"], @"2");
	XCTAssertNil([element valueForAttribute:@"missing"]);
}

- (void)testSetAttributeNamesValuesReplacesTheWholeSet
{
	AIXMLElement *element = [AIXMLElement elementWithName:@"p"];
	[element setValue:@"1" forAttribute:@"a"];
	[element setAttributeNames:@[ @"c", @"d" ] values:@[ @"4", @"5" ]];
	XCTAssertEqualObjects([element attributes], (@{ @"c": @"4", @"d": @"5" }));
	XCTAssertNil([element valueForAttribute:@"a"]);
}

- (void)testAttributeValuesAreEscapedAndParseBack
{
	AIXMLElement *element = [AIXMLElement elementWithName:@"p"];
	NSString *tricky = @"a \"b\" & <c> 'd'";
	[element setValue:tricky forAttribute:@"title"];
	XCTAssertFalse([[element XMLString] containsString:@"\"b\""]);
	XCTAssertEqualObjects([[[self parsedRootOf:element] attributeForName:@"title"] stringValue], tricky);
}

- (void)testNumberAndURLAttributeValuesAreWrittenAsStrings
{
	AIXMLElement *element = [AIXMLElement elementWithName:@"img"];
	[element setValue:(id)@3 forAttribute:@"width"];
	[element setValue:(id)[NSURL URLWithString:@"http://example.com/a?b=1&c=2"] forAttribute:@"src"];
	XCTAssertEqualObjects([element XMLString], @"<img width=\"3\" src=\"http://example.com/a?b=1&amp;c=2\"></img>");
}

#pragma mark Contents

- (void)testAddObjectEscapesTextForXML
{
	AIXMLElement *element = [AIXMLElement elementWithName:@"p"];
	NSString *text = @"a < b & c > \"d\" 'e'";
	[element addObject:text];
	NSString *xml = [element XMLString];
	XCTAssertTrue([xml containsString:@"&lt;"], @"%@", xml);
	XCTAssertTrue([xml containsString:@"&amp;"], @"%@", xml);
	XCTAssertTrue([xml containsString:@"&gt;"], @"%@", xml);
	XCTAssertEqualObjects([[self parsedRootOf:element] stringValue], text);
}

- (void)testAddEscapedObjectIsWrittenVerbatim
{
	AIXMLElement *escaped = [AIXMLElement elementWithName:@"p"];
	[escaped addEscapedObject:@"&amp;"];
	XCTAssertEqualObjects([escaped XMLString], @"<p>&amp;</p>");
	XCTAssertEqualObjects([escaped contentsAsXMLString], @"&amp;");

	AIXMLElement *unescaped = [AIXMLElement elementWithName:@"p"];
	[unescaped addObject:@"&amp;"];
	XCTAssertEqualObjects([unescaped XMLString], @"<p>&amp;amp;</p>");
}

- (void)testChildElementsNest
{
	AIXMLElement *p = [AIXMLElement elementWithName:@"p"];
	AIXMLElement *span = [AIXMLElement elementWithName:@"span"];
	[span addObject:@"x"];
	[p addObject:span];
	XCTAssertEqualObjects([p XMLString], @"<p><span>x</span></p>");
	XCTAssertEqual([[p contents] count], (NSUInteger)1);
	XCTAssertEqual([[p contents] firstObject], span);
	XCTAssertEqualObjects([p contentsAsXMLString], @"<span>x</span>");
}

- (void)testInsertAtIndexAndSetContents
{
	AIXMLElement *p = [AIXMLElement elementWithName:@"p"];
	[p addObject:@"b"];
	[p insertObject:@"a" atIndex:0];
	[p insertEscapedObject:@"&amp;" atIndex:1];
	XCTAssertEqualObjects([p XMLString], @"<p>a&amp;b</p>");
	[p setContents:@[ @"z" ]];
	XCTAssertEqualObjects([p XMLString], @"<p>z</p>");
}

- (void)testAddObjectsFromArrayEscapesEachString
{
	AIXMLElement *p = [AIXMLElement elementWithName:@"p"];
	[p addObjectsFromArray:@[ @"<", [AIXMLElement elementWithName:@"br"], @">" ]];
	XCTAssertEqualObjects([p XMLString], @"<p>&lt;<br />&gt;</p>");
}

- (void)testAddingNilIsANoOp
{
	AIXMLElement *p = [AIXMLElement elementWithName:@"p"];
	XCTAssertNoThrow([p addObject:nil]);
	XCTAssertNoThrow([p addEscapedObject:nil]);
	XCTAssertEqual([[p contents] count], (NSUInteger)0);
}

- (void)testWhitespaceControlCharactersSurviveARoundTrip
{
	AIXMLElement *p = [AIXMLElement elementWithName:@"p"];
	[p addObject:@"a\nb\tc"];
	XCTAssertEqualObjects([[self parsedRootOf:p] stringValue], @"a\nb\tc");
}

- (void)testACarriageReturnIsWrittenAsACharacterReference
{
	// A parser would fold a literal CR LF into LF; only a reference keeps the return.
	AIXMLElement *p = [AIXMLElement elementWithName:@"p"];
	[p addObject:@"a\r\nb"];
	XCTAssertEqualObjects([p XMLString], @"<p>a&#x0d;&#x0a;b</p>");
}

- (void)testNonASCIITextIsWrittenAsUTF8
{
	AIXMLElement *p = [AIXMLElement elementWithName:@"p"];
	NSString *text = @"caf\u00e9 \u2603 \U0001F600";
	[p addObject:text];
	XCTAssertEqualObjects([p UTF8XMLData], [[p XMLString] dataUsingEncoding:NSUTF8StringEncoding]);
	XCTAssertEqualObjects([[self parsedRootOf:p] stringValue], text);
}

- (void)testUTF8DataMatchesTheStringForAWholeTree
{
	AIXMLElement *div = [AIXMLElement elementWithName:@"div"];
	[div setValue:@"rtl" forAttribute:@"dir"];
	AIXMLElement *a = [AIXMLElement elementWithName:@"a"];
	[a setValue:@"http://example.com/?a=1&b=2" forAttribute:@"href"];
	[a addObject:@"link"];
	[div addObjectsFromArray:@[ a, @" & more", [AIXMLElement elementWithName:@"br"] ]];
	XCTAssertEqualObjects([div UTF8XMLData], [[div XMLString] dataUsingEncoding:NSUTF8StringEncoding]);

	NSMutableData *data = [NSMutableData dataWithBytes:"<!-- -->" length:8];
	[div appendUTF8XMLBytesToData:data];
	XCTAssertEqualObjects(data, [[@"<!-- -->" stringByAppendingString:[div XMLString]] dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testAppendXMLStringAppendsToWhatIsThere
{
	NSMutableString *string = [NSMutableString stringWithString:@"<?xml version=\"1.0\"?>"];
	[[AIXMLElement elementWithName:@"p"] appendXMLStringtoString:string];
	XCTAssertEqualObjects(string, @"<?xml version=\"1.0\"?><p></p>");
}

- (void)testCopyIsIndependentOfTheOriginal
{
	AIXMLElement *original = [AIXMLElement elementWithName:@"p"];
	[original setValue:@"1" forAttribute:@"a"];
	[original addObject:@"x"];
	AIXMLElement *copy = [original copy];
	XCTAssertEqualObjects([copy XMLString], [original XMLString]);

	[copy setValue:@"2" forAttribute:@"a"];
	[copy addObject:@"y"];
	copy.selfCloses = YES;
	XCTAssertEqualObjects([original XMLString], @"<p a=\"1\">x</p>");
	XCTAssertEqualObjects([copy XMLString], @"<p a=\"2\">xy</p>");
}

- (void)testABuiltTreeParsesBackWithNamesAttributesAndText
{
	AIXMLElement *div = [AIXMLElement elementWithName:@"div"];
	AIXMLElement *a = [AIXMLElement elementWithName:@"a"];
	[a setValue:@"http://example.com/?a=1&b=2" forAttribute:@"href"];
	[a addObject:@"link"];
	[div addObject:a];
	[div addObject:@" and "];
	[div addObject:[AIXMLElement elementWithName:@"br"]];

	NSXMLElement *root = [self parsedRootOf:div];
	XCTAssertEqualObjects([root name], @"div");
	XCTAssertEqual([root childCount], (NSUInteger)3);
	NSXMLElement *anchor = (NSXMLElement *)[root childAtIndex:0];
	XCTAssertEqualObjects([anchor name], @"a");
	XCTAssertEqualObjects([[anchor attributeForName:@"href"] stringValue], @"http://example.com/?a=1&b=2");
	XCTAssertEqualObjects([root stringValue], @"link and ");
	XCTAssertEqualObjects([[root childAtIndex:2] name], @"br");
}

@end
