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

/* NSString+AIBidi.h is not among the framework's public headers, so the one method is declared here. */
@interface NSString (AIBidi)
- (NSWritingDirection)baseWritingDirection;
@end

@interface TestStringBidi : XCTestCase
@end

@implementation TestStringBidi

static NSString *const hebrew = @"\u05e9\u05dc\u05d5\u05dd";
static NSString *const arabic = @"\u0645\u0631\u062d\u0628\u0627";

- (void)testEmptyStringHasNoDirection
{
	XCTAssertEqual([@"" baseWritingDirection], NSWritingDirectionNatural);
}

- (void)testLatinIsLeftToRight
{
	XCTAssertEqual([@"hello" baseWritingDirection], NSWritingDirectionLeftToRight);
	XCTAssertEqual([@"HELLO" baseWritingDirection], NSWritingDirectionLeftToRight);
}

- (void)testHebrewIsRightToLeft
{
	XCTAssertEqual([hebrew baseWritingDirection], NSWritingDirectionRightToLeft);
}

- (void)testArabicIsRightToLeft
{
	XCTAssertEqual([arabic baseWritingDirection], NSWritingDirectionRightToLeft);
	// Letters Persian and Urdu add to the Arabic block are right-to-left too.
	XCTAssertEqual([@"\u067e\u06cc" baseWritingDirection], NSWritingDirectionRightToLeft);
}

- (void)testDigitsPunctuationAndSpacesAloneAreNeutral
{
	XCTAssertEqual([@"123 456" baseWritingDirection], NSWritingDirectionNatural);
	XCTAssertEqual([@"!? ... (-) [+] {=} \"'" baseWritingDirection], NSWritingDirectionNatural);
	XCTAssertEqual([@"\t\n " baseWritingDirection], NSWritingDirectionNatural);
}

- (void)testNeutralPrefixDefersToTheFirstStrongCharacter
{
	XCTAssertEqual([[@"123 " stringByAppendingString:hebrew] baseWritingDirection], NSWritingDirectionRightToLeft);
	XCTAssertEqual([[@"... (" stringByAppendingString:hebrew] baseWritingDirection], NSWritingDirectionRightToLeft);
	XCTAssertEqual([@"... hello" baseWritingDirection], NSWritingDirectionLeftToRight);
	XCTAssertEqual([@"42 answers" baseWritingDirection], NSWritingDirectionLeftToRight);
}

- (void)testTheFirstStrongCharacterWinsInMixedText
{
	XCTAssertEqual([[@"hello " stringByAppendingString:hebrew] baseWritingDirection], NSWritingDirectionLeftToRight);
	XCTAssertEqual([[hebrew stringByAppendingString:@" hello"] baseWritingDirection], NSWritingDirectionRightToLeft);
	XCTAssertEqual([[[@"(" stringByAppendingString:hebrew] stringByAppendingString:@") hello"] baseWritingDirection], NSWritingDirectionRightToLeft);
	XCTAssertEqual([[[@"hello (" stringByAppendingString:arabic] stringByAppendingString:@")"] baseWritingDirection], NSWritingDirectionLeftToRight);
}

- (void)testLatinWithDiacriticsIsLeftToRight
{
	XCTAssertEqual([@"\u00e9t\u00e9" baseWritingDirection], NSWritingDirectionLeftToRight);
	XCTAssertEqual([@"\u00c4rger" baseWritingDirection], NSWritingDirectionLeftToRight);
	XCTAssertEqual([@"\u00bfQu\u00e9?" baseWritingDirection], NSWritingDirectionLeftToRight);
}

- (void)testGreekAndCyrillicAreLeftToRight
{
	XCTAssertEqual([@"\u03b1\u03b2\u03b3" baseWritingDirection], NSWritingDirectionLeftToRight);
	XCTAssertEqual([@"\u043f\u0440\u0438\u0432\u0435\u0442" baseWritingDirection], NSWritingDirectionLeftToRight);
}

- (void)testIndicAndEastAsianScriptsAreLeftToRight
{
	XCTAssertEqual([@"\u0928\u092e\u0938\u094d\u0924\u0947" baseWritingDirection], NSWritingDirectionLeftToRight);
	XCTAssertEqual([@"\u65e5\u672c\u8a9e" baseWritingDirection], NSWritingDirectionLeftToRight);
	XCTAssertEqual([@"\ud55c\uad6d\uc5b4" baseWritingDirection], NSWritingDirectionLeftToRight);
	XCTAssertEqual([@"\u3053\u3093\u306b\u3061\u306f" baseWritingDirection], NSWritingDirectionLeftToRight);
}

- (void)testHebrewAndArabicPresentationFormsAreRightToLeft
{
	XCTAssertEqual([@"\ufb2a" baseWritingDirection], NSWritingDirectionRightToLeft);
	XCTAssertEqual([@"\ufe8d\ufedf" baseWritingDirection], NSWritingDirectionRightToLeft);
}

- (void)testEmojiIsNeutralAndDoesNotHideTheTextAfterIt
{
	XCTAssertEqual([@"\U0001F600" baseWritingDirection], NSWritingDirectionNatural);
	XCTAssertEqual([@"\U0001F600 hello" baseWritingDirection], NSWritingDirectionLeftToRight);
	XCTAssertEqual([[@"\U0001F600 " stringByAppendingString:hebrew] baseWritingDirection], NSWritingDirectionRightToLeft);
}

- (void)testDirectionalMarksAreStrong
{
	XCTExpectFailure(@"U+200F and U+200E are skipped as neutral: NSString+AIBidi.m:30 and :39 list script ranges and the marks are in none of them, though Unicode gives them bidirectional class R and L and they exist only to decide direction");
	XCTAssertEqual([@"\u200f123" baseWritingDirection], NSWritingDirectionRightToLeft);
	XCTAssertEqual([[@"\u200e" stringByAppendingString:hebrew] baseWritingDirection], NSWritingDirectionLeftToRight);
}

- (void)testNeutralSymbolsInTheLatin1BlockDoNotDecide
{
	XCTExpectFailure(@"The multiplication sign is taken as left-to-right: NSString+AIBidi.m:40 counts all of U+00C0 to U+058F as strong, and that range holds neutrals such as U+00D7 and U+00F7 and the combining marks U+0300 to U+036F");
	XCTAssertEqual([[@"\u00d7 " stringByAppendingString:hebrew] baseWritingDirection], NSWritingDirectionRightToLeft);
	XCTAssertEqual([[@"\u0301" stringByAppendingString:hebrew] baseWritingDirection], NSWritingDirectionRightToLeft);
}

@end
