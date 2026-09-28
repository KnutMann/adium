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
#import <AIUtilities/AIButtonWithCursor.h>

@class AIMessageEntryTextView;

//! Where a feature keeps the switch for its button when it has no preference group of its own
#define PREF_GROUP_MESSAGE_ENTRY		@"Message Entry"

/*!
 * @class AIMessageEntryAccessory
 * @brief A button a feature contributes to the right edge of the message field
 *
 * The smiley that opens the emoticon menu was the first of these, built into the entry
 * view by hand. This is that place made general: a feature describes its button once,
 * here, and every message field shows it or does not, according to one preference. The
 * message view controller reads the preference and the settings page shows a switch for
 * it, so a feature that registers an accessory has nothing more to do.
 *
 * The buttons stand side by side, left to right in the order they were registered, so
 * the last one registered is the one at the edge of the field.
 */
@interface AIMessageEntryAccessory : NSObject

@property (readonly, nonatomic, copy) NSString *identifier;
//! Names the button's switch on the settings page
@property (readonly, nonatomic, copy) NSString *label;
@property (readonly, nonatomic, copy) NSString *toolTip;
@property (readonly, nonatomic, strong) NSImage *image;
@property (readonly, nonatomic, copy) NSString *preferenceKey;
@property (readonly, nonatomic, copy) NSString *preferenceGroup;
//! Receives the action with the button as sender; see AIMessageEntryAccessoryButton
@property (readonly, nonatomic, weak) id target;
@property (readonly, nonatomic) SEL action;

//! Whether the preference says the button is shown right now
@property (readonly, nonatomic, getter=isEnabled) BOOL enabled;

+ (instancetype)accessoryWithIdentifier:(NSString *)identifier
								  label:(NSString *)label
								toolTip:(NSString *)toolTip
								  image:(NSImage *)image
						  preferenceKey:(NSString *)preferenceKey
								  group:(NSString *)preferenceGroup
								 target:(id)target
								 action:(SEL)action;

+ (void)registerAccessory:(AIMessageEntryAccessory *)accessory;
+ (void)unregisterAccessoryWithIdentifier:(NSString *)identifier;

//! Every registered accessory, in registration order
+ (NSArray *)registeredAccessories;
//! The registered accessories whose preference is on, in the same order
+ (NSArray *)enabledAccessories;
//! Every preference group a registered accessory reads, for whoever wants to observe them
+ (NSSet *)preferenceGroups;

@end

/*!
 * @protocol AIMessageEntryShelf
 * @brief A view on the shelf below the conversation names the button that opened it
 *
 * While a shelf is open, the buttons in the message field are greyed out, since the
 * shelf has taken over what they would put into the message. The one that opened the
 * shelf is the one that closes it again and stays usable; a shelf says which by
 * answering this.
 *
 * A shelf can also say that it holds something which would be lost if it were taken
 * away, a recording under way say. While it does, nothing replaces or closes it but
 * the shelf itself; whoever else asks is refused.
 */
@protocol AIMessageEntryShelf <NSObject>
@optional
- (NSString *)messageEntryAccessoryIdentifier;
- (BOOL)messageEntryShelfIsBusy;
@end

/*!
 * @class AIMessageEntryAccessoryButton
 * @brief The button in the field, which knows the field it stands in
 *
 * This is what an accessory's action receives as sender. A toolbar item has to search
 * the key window for the field it belongs to; this button was made for one field and
 * says which, so the action can act on that field whether or not it is the key one.
 */
@interface AIMessageEntryAccessoryButton : AIButtonWithCursor

@property (readonly, nonatomic, strong) AIMessageEntryAccessory *accessory;
//! Set by the field when it takes the button in, cleared when it lets it go
@property (readwrite, nonatomic, unsafe_unretained) AIMessageEntryTextView *messageEntryTextView;

- (instancetype)initWithAccessory:(AIMessageEntryAccessory *)accessory;

@end
