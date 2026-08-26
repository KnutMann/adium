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

#import <Adium/AIControllerProtocol.h>

@protocol AIPlugin;

@interface AICorePluginLoader : NSObject <AIController> {
    NSMutableArray		*pluginArray;
}

+ (void)loadPluginAtPath:(NSString *)pluginName confirmLoading:(BOOL)confirmLoading pluginArray:(NSMutableArray *)pluginArray;
- (id <AIPlugin>)pluginWithClassName:(NSString *)className;

/*!
 * @brief Run the external-plugin gates for a plugin something other than the loader activates
 *
 * The version gate and the confirm-with-the-user gate, exactly as loadPluginAtPath: runs
 * them for a native plugin. JavaScript plugins are activated by AIJSXtrasManager's scan,
 * not by this loader, so the scan asks here before taking an external bundle in; a plugin
 * the user has already confirmed passes silently, and one the user disables is moved away
 * by the gate itself, so a NO needs no further cleanup by the caller.
 */
+ (BOOL)externalPluginPassesGatesAtPath:(NSString *)pluginPath;

@end
