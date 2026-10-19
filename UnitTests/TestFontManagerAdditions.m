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

#import <AIUtilities/AIFontManagerAdditions.h>

@interface TestFontManagerAdditions : XCTestCase
@end

@implementation TestFontManagerAdditions

- (void)testFamilyNameSpelledAsInstalledIsFound
{
	NSFont *font = [[NSFontManager sharedFontManager] fontWithFamilyInsensitively:@"Helvetica" traits:0 weight:5 size:12];

	XCTAssertNotNil(font);
	XCTAssertEqualObjects([font familyName], @"Helvetica");
	XCTAssertEqualWithAccuracy([font pointSize], 12, AIFloatComparisonAccuracy);
}

- (void)testFamilyNameInLowercaseIsFound
{
	NSFont *font = [[NSFontManager sharedFontManager] fontWithFamilyInsensitively:@"helvetica" traits:0 weight:5 size:12];

	XCTAssertEqualObjects([font familyName], @"Helvetica");
}

- (void)testFamilyNameInUppercaseIsFoundWithTheRequestedTrait
{
	NSFontManager *manager = [NSFontManager sharedFontManager];

	NSFont *font = [manager fontWithFamilyInsensitively:@"HELVETICA" traits:NSBoldFontMask weight:9 size:14];
	XCTAssertEqualObjects([font familyName], @"Helvetica");
	XCTAssertTrue([manager traitsOfFont:font] & NSBoldFontMask);
	XCTAssertEqualWithAccuracy([font pointSize], 14, AIFloatComparisonAccuracy);
}

- (void)testAFixedPitchFamilyKeepsItsPitch
{
	NSFont *font = [[NSFontManager sharedFontManager] fontWithFamilyInsensitively:@"menlo" traits:NSFixedPitchFontMask weight:5 size:11];

	XCTAssertEqualObjects([font familyName], @"Menlo");
	XCTAssertTrue([font isFixedPitch]);
	XCTAssertEqualWithAccuracy([font pointSize], 11, AIFloatComparisonAccuracy);
}

- (void)testUnknownFamilyGivesNil
{
	XCTAssertNil([[NSFontManager sharedFontManager] fontWithFamilyInsensitively:@"AIThereIsNoSuchFamily" traits:0 weight:5 size:12]);
}

@end
