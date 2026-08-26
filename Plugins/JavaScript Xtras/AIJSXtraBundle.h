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
 * @brief One validated setting a JavaScript plugin declares
 *
 * A choice among a handful of strings the manifest itself wrote down, and nothing else; the type
 * list in AIJSXtraBundle.m says why there is only one kind. Every string here has been through the
 * validator: the key and the option values are plain ASCII tokens, the titles carry no control
 * character and no direction override, and no two options read alike. Immutable, so the settings
 * UI can be handed the array without anybody having to think about who owns it.
 */
@interface AIJSXtraSetting : NSObject

//The JavaScript property name, and the key the chosen value is stored under
@property (readonly, nonatomic) NSString *key;

//The row label and the smaller line under it; detail may be nil
@property (readonly, nonatomic) NSString *title;
@property (readonly, nonatomic) NSString *detail;

//Always one of optionValues
@property (readonly, nonatomic) NSString *defaultValue;

//What reaches JavaScript, and what the menu reads; the same length, in the author's order
@property (readonly, nonatomic) NSArray<NSString *> *optionValues;
@property (readonly, nonatomic) NSArray<NSString *> *optionTitles;

/*!
 * @brief @a value if this setting still offers it, otherwise the manifest default
 *
 * The only way a stored value is ever read. What was valid when it was written is re-checked every
 * time: the preference file is one the user can edit, and a plugin update can drop an option from
 * under a value the version before it stored.
 */
- (NSString *)coercedValue:(id)value;

@end

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
 * that is missing or too large or not valid UTF-8, declares an API version
 * this build does not speak, or declares settings that are not exactly what the
 * schema allows.
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

//The settings the manifest declares, validated; empty for a plugin that declares none
@property (readonly, nonatomic) NSArray<AIJSXtraSetting *> *settings;

@end
