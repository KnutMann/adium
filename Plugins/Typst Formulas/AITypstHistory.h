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

#import <Cocoa/Cocoa.h>

/*!
 * @brief Posted when the remembered formulas change, so an open editor can redraw its strip
 */
extern NSString *AITypstHistoryDidChangeNotification;

/*!
 * @class AITypstHistory
 * @brief The formulas that have been used, most recent first, each appearing once
 *
 * Deliberately a list of the source text and nothing else. A formula is a few dozen characters and
 * renders in a fraction of a second, so keeping the pictures would trade a great deal of space for
 * an imperceptible saving, and it would leave stale pictures behind on the day the template changes.
 *
 * There is one list, shared by every chat. A formula worth sending once is worth sending again in
 * another conversation, and keeping a separate list per chat would mostly mean not finding what you
 * were looking for.
 */
@interface AITypstHistory : NSObject

/*!
 * @brief Every remembered formula, most recently used first
 */
+ (NSArray *)formulas;

/*!
 * @brief Record that a formula was used
 *
 * Using one that is already known moves it to the front rather than adding it again, which is what
 * makes the list stay short and useful: the ten formulas somebody actually works with stay at the
 * top instead of being pushed off by their own repetitions.
 *
 * Blank or whitespace-only input is ignored.
 */
+ (void)rememberFormula:(NSString *)formula;

/*!
 * @brief Drop one formula from the list
 */
+ (void)forgetFormula:(NSString *)formula;

/*!
 * @brief Empty the list
 */
+ (void)forgetAllFormulas;

@end
