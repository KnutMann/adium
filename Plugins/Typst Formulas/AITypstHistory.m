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

#import "AITypstHistory.h"

#import <Adium/AIPreferenceControllerProtocol.h>

NSString *AITypstHistoryDidChangeNotification = @"AITypstHistoryDidChange";

#define PREF_GROUP_TYPST_FORMULAS	@"Typst Formulas"
#define KEY_FORMULA_HISTORY			@"Formula History"

/* Enough that a week of work is still there, few enough that the strip stays something you scan
 * rather than search. */
#define HISTORY_LIMIT				40

@implementation AITypstHistory

+ (NSArray *)formulas
{
	NSArray *stored = [adium.preferenceController preferenceForKey:KEY_FORMULA_HISTORY
															 group:PREF_GROUP_TYPST_FORMULAS];

	return (stored ? stored : [NSArray array]);
}

/*!
 * @brief Write a list back
 *
 * The copy is not tidiness. preferenceForKey:group: hands out the container the preference store is
 * itself holding, so mutating that and passing it back means the store compares the new value with
 * itself, concludes nothing changed, and drops both the write and the notification. The bug that
 * follows is that the history looks right until the next launch and is then empty.
 */
+ (void)_setFormulas:(NSArray *)formulas
{
	[adium.preferenceController setPreference:[formulas copy]
									   forKey:KEY_FORMULA_HISTORY
										group:PREF_GROUP_TYPST_FORMULAS];

	[[NSNotificationCenter defaultCenter] postNotificationName:AITypstHistoryDidChangeNotification
													   object:nil];
}

+ (void)rememberFormula:(NSString *)formula
{
	NSString *trimmed = [formula stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (![trimmed length]) return;

	NSMutableArray *updated = [[self formulas] mutableCopy];

	/* Remove before inserting, so that using a known formula again promotes it instead of leaving a
	 * second copy further down the list. */
	[updated removeObject:trimmed];
	[updated insertObject:trimmed atIndex:0];

	while ([updated count] > HISTORY_LIMIT)
		[updated removeLastObject];

	[self _setFormulas:updated];
}

+ (void)forgetFormula:(NSString *)formula
{
	NSArray *current = [self formulas];
	if (![current containsObject:formula]) return;

	NSMutableArray *updated = [current mutableCopy];
	[updated removeObject:formula];

	[self _setFormulas:updated];
}

+ (void)forgetAllFormulas
{
	[self _setFormulas:[NSArray array]];
}

@end
