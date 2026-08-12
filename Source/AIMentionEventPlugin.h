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

#import <AIUtilities/AIStringAdditions.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import "AIMentionAdvancedPreferences.h"

@interface AIMentionEventPlugin : AIPlugin <AIContentFilter> {
	AIMentionAdvancedPreferences	*advancedPreferences;
	NSArray							*mentionPredicates;
}
@property(copy, nonatomic) NSArray *mentionPredicates;

/*!
 * @brief Is @a term written in the /…/ form, and therefore a regular expression?
 *
 * The one place which decides that question. The preference pane asks it too, and it must get the
 * same answer we act on: this is not "begins and ends with a slash" - "/a/b/" is the expression
 * form to us, a bare "/" is not - and two hand written tests of that would drift apart.
 */
+ (BOOL)termIsRegularExpression:(NSString *)term;

/*!
 * @brief The predicate @a term matches messages with, or nil if it cannot have one
 *
 * nil for an empty term (there is nothing to match yet) and for a /…/ term whose expression does
 * not compile; @a outError then holds the reason, may be NULL, and is not for showing to the user -
 * it quotes the pattern as we wrapped it, not as the user typed it.
 *
 * Everything the terms mean lives here so that asking and applying cannot come apart: the pane
 * switches a term off with the very call that would otherwise have built its predicate.
 */
+ (NSPredicate *)predicateForTerm:(NSString *)term error:(NSError **)outError;

/*!
 * @brief Can @a term be used as it stands?
 *
 * YES for anything which is not of the /…/ form - a plain word is escaped, never compiled, so it
 * cannot be wrong - and for the empty term of a row which was only just added. The check must never
 * stand in the user's way where there is nothing to be wrong about.
 */
+ (BOOL)termIsValid:(NSString *)term;

@end
