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
 * @brief One JavaScript plugin, validated
 *
 * A JavaScript plugin is an ordinary .AdiumPlugin bundle carrying no code, only
 * a script the message view injects. This reads such a bundle, validates its
 * manifest against everything that could turn a plugin into a foothold, and
 * holds the source ready. A bundle that fails validation yields nil - it is
 * never partially trusted.
 */
@interface AIJSXtraBundle : NSObject

/*!
 * @brief Read and validate the bundle at a path, or nil
 *
 * Fails (with a logged reason) when the bundle does not declare itself a
 * JavaScript plugin, names a script file that escapes Resources/, names one
 * that is missing or too large or not valid UTF-8, or declares an API version
 * this build does not speak.
 */
+ (instancetype)bundleWithPath:(NSString *)path;

@property (readonly, nonatomic) NSString *bundleIdentifier;
@property (readonly, nonatomic) NSString *displayName;
@property (readonly, nonatomic) NSString *version;
@property (readonly, nonatomic) NSString *author;

//The validated script, ready to inject
@property (readonly, nonatomic) NSString *source;

//The content world name this plugin runs in: one of its own, keyed by identifier
@property (readonly, nonatomic) NSString *contentWorldName;

@end
