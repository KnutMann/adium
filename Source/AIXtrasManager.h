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

@class AIXtraInfo, AIXtrasPreferences;

#define AIXtraTypeDockIcon			@"adiumicon"
#define AIXtraTypeStatusIcons		@"adiumstatusicons"
#define AIXtraTypeEmoticons			@"adiumemoticonset"
#define AIXtraTypeScript			@"adiumscripts"
#define AIXtraTypeMessageStyle		@"adiummessagestyle"
#define AIXtraTypeListTheme			@"listtheme"
#define AIXtraTypeListLayout		@"listlayout"
#define AIXtraTypeServiceIcons		@"adiumserviceicons"
#define AIXtraTypeMenuBarIcons		@"adiummenubaricons"

/*!
 * @class AIXtrasManager
 * @brief Knows what an Xtra category is and what is installed in each of them
 *
 * The model behind the "Xtras" preference pane, and nothing else: the categories, what is installed
 * in them, and how to make an empty Xtra bundle. The user interface lives in AIXtrasPreferences,
 * which this plugin installs and which asks the questions below.
 *
 * The list of a category is read from disk once and then cached; @c -loadXtras throws every cache
 * away, so it is also how the pane picks up an Xtra which was installed or deleted since.
 */
@interface AIXtrasManager : AIPlugin {
	NSMutableArray			*categories;
	AIXtrasPreferences		*xtrasPreferences;
}

+ (AIXtrasManager *)sharedManager;

/*!
 * @brief Build the list of categories, discarding what is cached about each of them
 */
- (void)loadXtras;

/*!
 * @brief How many categories there are
 */
- (NSUInteger)numberOfCategories;

/*!
 * @brief The localized name of a category, for the card it heads
 */
- (NSString *)nameOfCategoryAtIndex:(NSInteger)inIndex;

/*!
 * @brief The AISearchPathForDirectories() constant a category is read from
 *
 * Lets a caller tell one category from another without knowing the order they are sorted in - the
 * pane uses it to hang the "restart Adium" footnote under the plug-ins card.
 */
- (NSUInteger)directoryOfCategoryAtIndex:(NSInteger)inIndex;

/*!
 * @brief The AIXtraInfos installed in a category, switched off ones included
 */
- (NSArray *)xtrasForCategoryAtIndex:(NSInteger)inIndex;

/*!
 * @brief Every Xtra below @a paths, plus every Xtra in the "(Disabled)" folder beside each of them
 */
- (NSArray *)arrayOfXtrasAtPaths:(NSArray *)paths;

/*!
 * @brief Create an empty Xtra bundle at @a path, or check that the one there is usable
 */
+ (BOOL)createXtraBundleAtPath:(NSString *)path;

@end
