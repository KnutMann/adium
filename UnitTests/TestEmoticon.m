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

#import <Adium/AIEmoticon.h>
#import <Adium/AIEmoticonPack.h>
#import <Adium/AITextAttachmentExtension.h>

@interface TestEmoticon : XCTestCase
@end

@implementation TestEmoticon

- (NSString *)owlImagePath
{
	return [[[NSBundle bundleForClass:[self class]] resourcePath]
			stringByAppendingPathComponent:@"Fixtures/Birds.AdiumEmoticonset/owl.png"];
}

- (AIEmoticon *)owl
{
	return [AIEmoticon emoticonWithIconPath:[self owlImagePath]
								equivalents:[NSArray arrayWithObjects:@":))", @"(owl)", nil]
									   name:@"Owl"
									   pack:nil];
}

- (AITextAttachmentExtension *)attachmentOf:(NSAttributedString *)string
{
	return [string attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL];
}

#pragma mark What an emoticon is made of

- (void)testImageEmoticonCarriesPathNameAndEquivalents
{
	AIEmoticon *owl = [self owl];

	XCTAssertEqualObjects([owl path], [self owlImagePath]);
	XCTAssertEqualObjects([owl name], @"Owl");
	XCTAssertEqualObjects([owl textEquivalents], ([NSArray arrayWithObjects:@":))", @"(owl)", nil]));
	XCTAssertNil([owl character], @"An image emoticon is not a character emoticon");
}

- (void)testImageEmoticonIsDisplayableAndLoadsItsImage
{
	AIEmoticon *owl = [self owl];

	XCTAssertTrue([owl isDisplayable]);
	XCTAssertTrue(NSEqualSizes([[owl image] size], NSMakeSize(16, 16)), @"The fixture image is 16 by 16");
}

- (void)testEmoticonWithoutImageFileIsNotDisplayable
{
	AIEmoticon *ghost = [AIEmoticon emoticonWithIconPath:nil
											 equivalents:[NSArray arrayWithObject:@"(ghost)"]
													name:@"Ghost"
													pack:nil];

	XCTAssertFalse([ghost isDisplayable]);
	XCTAssertNil([ghost image]);
}

- (void)testCharacterEmoticonIsDisplayableWithoutAnImageFile
{
	AIEmoticon *hoot = [AIEmoticon emoticonWithCharacter:@"\U0001F989"
											 equivalents:[NSArray arrayWithObject:@"(hoot)"]
													name:@"Hoot"
													pack:nil];

	XCTAssertEqualObjects([hoot character], @"\U0001F989");
	XCTAssertNil([hoot path]);
	XCTAssertTrue([hoot isDisplayable]);
	XCTAssertNotNil([hoot image], @"Previews draw the character into an image");
}

- (void)testEmptyCharacterIsNothingToDisplay
{
	AIEmoticon *blank = [AIEmoticon emoticonWithCharacter:@""
											  equivalents:[NSArray arrayWithObject:@"(blank)"]
													 name:@"Blank"
													 pack:nil];

	XCTAssertFalse([blank isDisplayable]);
}

- (void)testEnabledStateFollowsTheSetter
{
	AIEmoticon *owl = [self owl];

	[owl setEnabled:YES];
	XCTAssertTrue([owl isEnabled]);
	[owl setEnabled:NO];
	XCTAssertFalse([owl isEnabled]);
}

- (void)testEmoticonOutsideAnyPackSuitsEveryServiceClass
{
	AIEmoticon *owl = [self owl];

	XCTAssertTrue([owl isAppropriateForServiceClass:@"Jabber"]);
	XCTAssertTrue([owl isAppropriateForServiceClass:nil]);
}

#pragma mark The attributed string an emoticon becomes

- (void)testAttributedStringOfImageEmoticonIsOneAttachmentNamingTheEquivalent
{
	NSAttributedString *string = [[self owl] attributedStringWithTextEquivalent:@":))" attachImages:NO];
	AITextAttachmentExtension *attachment = [self attachmentOf:string];

	XCTAssertEqual([string length], (NSUInteger)1);
	XCTAssertTrue([attachment isKindOfClass:[AITextAttachmentExtension class]]);
	XCTAssertEqualObjects([attachment string], @":))");
	XCTAssertEqualObjects([attachment path], [self owlImagePath]);
	XCTAssertEqualObjects([attachment imageClass], @"emoticon");
	XCTAssertTrue([attachment hasAlternate], @"The text equivalent stands in for the image wherever images cannot go");
	XCTAssertTrue([attachment shouldAlwaysSendAsText], @"Emoticons are never sent as images");
}

- (void)testAttributedStringsForDifferentEquivalentsDoNotShareTheirText
{
	AIEmoticon *owl = [self owl];
	NSAttributedString *first = [owl attributedStringWithTextEquivalent:@":))" attachImages:NO];
	NSAttributedString *second = [owl attributedStringWithTextEquivalent:@"(owl)" attachImages:NO];

	XCTAssertEqualObjects([[self attachmentOf:second] string], @"(owl)");
	XCTAssertEqualObjects([[self attachmentOf:first] string], @":))", @"Asking again must not rewrite what was handed out before");
}

- (void)testAttachingImagesGivesTheAttachmentACellShowingTheImage
{
	NSAttributedString *string = [[self owl] attributedStringWithTextEquivalent:@":))" attachImages:YES];
	NSTextAttachmentCell *cell = (NSTextAttachmentCell *)[[self attachmentOf:string] attachmentCell];

	XCTAssertTrue([cell isKindOfClass:[NSTextAttachmentCell class]]);
	XCTAssertNotNil([cell image]);
}

- (void)testCharacterEmoticonBecomesPlainText
{
	AIEmoticon *hoot = [AIEmoticon emoticonWithCharacter:@"\U0001F989"
											 equivalents:[NSArray arrayWithObject:@"(hoot)"]
													name:@"Hoot"
													pack:nil];
	NSAttributedString *string = [hoot attributedStringWithTextEquivalent:@"(hoot)" attachImages:YES];

	XCTAssertEqualObjects([string string], @"\U0001F989");
	XCTAssertNil([self attachmentOf:string], @"A character is text in every context, never an attachment");
}

@end
