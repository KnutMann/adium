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
#import <WebKit/WebKit.h>

#define PREF_GROUP_JSXTRAS				@"JSXtras"
#define KEY_JSXTRAS_MASTER_ENABLED		@"Master Enabled"
#define KEY_JSXTRAS_ENABLED_PLUGINS		@"Enabled Plugins"

//Posted when the set of plugins, or their enablement, changes
#define AIJSXtrasDidChangeNotification	@"AIJSXtrasDidChange"

@class AIJSXtraBundle;

/*!
 * @brief Discovers JavaScript plugins and injects them into message views
 *
 * Finds the bundled and user-installed JavaScript plugins, keeps the validated,
 * enabled set, and installs each one's script into a content world of its own
 * inside a message view's configuration. The content world isolates a plugin's
 * JavaScript from the page, the message style, and every other plugin; the
 * message view's own hardening keeps a plugin off the network and off the local
 * filesystem.
 */
@interface AIJSXtrasManager : NSObject

+ (instancetype)sharedManager;

//Re-scan the plugin folders (bundled + user); posts AIJSXtrasDidChangeNotification on change
- (void)rescan;

//The validated, enabled plugins, in a stable order
@property (readonly, nonatomic) NSArray<AIJSXtraBundle *> *enabledBundles;

//Every validated plugin, enabled or not, for the settings UI
@property (readonly, nonatomic) NSArray<AIJSXtraBundle *> *allBundles;

- (BOOL)masterEnabled;
- (void)setMasterEnabled:(BOOL)enabled;

- (BOOL)isBundleEnabled:(AIJSXtraBundle *)bundle;
- (void)setBundle:(AIJSXtraBundle *)bundle enabled:(BOOL)enabled;

//The same enablement, keyed by a plugin's CFBundleIdentifier, for the Xtras pane which holds an
//AIXtraInfo rather than one of our validated bundles
- (BOOL)isPluginEnabledWithIdentifier:(NSString *)identifier;
- (void)setPluginWithIdentifier:(NSString *)identifier enabled:(BOOL)enabled;

/*!
 * @brief Add each enabled plugin's script to a message view's configuration
 *
 * Called while the message view builds its configuration. Does nothing when the
 * feature is off; otherwise adds one user script per enabled plugin, each in its
 * own content world.
 */
- (void)installIntoUserContentController:(WKUserContentController *)userContentController;

@end
