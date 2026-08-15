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

@class AIAccount;

/*!
 * @brief Where a field's value lives
 *
 * The one thing a settings interface has to get right and the one thing the old one spread over three
 * places: a control in a nib, an outlet read in -configureForAccount:, a write in -saveConfiguration.
 * A field says it once here, and the same statement is used for reading and for writing.
 */
typedef enum {
	AIAccountFieldStoreNone = 0,	//An action: there is nothing to read or write
	AIAccountFieldStorePreference,	//An Adium preference, named by preferenceKey in preferenceGroup
	AIAccountFieldStoreAccountName,	//The account's own name, which renaming it goes through
	AIAccountFieldStorePassword		//The keychain
} AIAccountFieldStore;

/*!
 * @brief What a field looks like
 */
typedef enum {
	AIAccountFieldText = 0,
	AIAccountFieldMultiline,		//Several lines of text, a list of commands for instance
	AIAccountFieldNumber,
	AIAccountFieldSwitch,
	AIAccountFieldChoice,
	AIAccountFieldEncryption,		//Adium's own encryption menu, which every account shares
	AIAccountFieldAction			//A button, not a value
} AIAccountFieldKind;

//The cards a plan may put a field into, in the order they are shown
extern NSString *AIAccountCardAccount;
extern NSString *AIAccountCardPersonal;
extern NSString *AIAccountCardOptions;
extern NSString *AIAccountCardMore;
extern NSString *AIAccountCardPrivacy;

/*!
 * @class AIAccountPlanField
 * @brief One row of an account's settings, described rather than built
 *
 * A field carries no control and knows nothing about views. It says what it is, what it is called and
 * where its value lives; the form builder turns that into a row, and the plan reads and writes it.
 */
@interface AIAccountPlanField : NSObject {
	NSString			*name;
	NSString			*label;
	NSString			*detail;
	NSString			*placeholder;
	NSString			*preferenceKey;
	NSString			*preferenceGroup;
	NSString			*legacyKey;
	NSArray				*choiceTitles;
	NSArray				*choiceValues;
	id					 defaultValue;
	SEL					 action;
	AIAccountFieldKind	 kind;
	AIAccountFieldStore	 store;
	BOOL				 inverted;
	BOOL				 secure;
	BOOL				 attributed;
	BOOL				 disabledWhileOnline;
	CGFloat				 width;
}

+ (AIAccountPlanField *)fieldNamed:(NSString *)inName kind:(AIAccountFieldKind)inKind;

//What it is called and what it is
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *label;
@property (nonatomic, retain) NSString *detail;
@property (nonatomic, retain) NSString *placeholder;
@property (nonatomic) AIAccountFieldKind kind;

//Where the value lives
@property (nonatomic) AIAccountFieldStore store;
@property (nonatomic, retain) NSString *preferenceKey;
@property (nonatomic, retain) NSString *preferenceGroup;

/*!
 * @brief What this value used to be stored under
 *
 * Read once when nothing is stored under the current key, then written where the field lives now. The
 * old key is left alone, so going back a version loses nothing.
 */
@property (nonatomic, retain) NSString *legacyKey;

//What a choice offers: what a person reads, and what is stored for it
@property (nonatomic, retain) NSArray *choiceTitles;
@property (nonatomic, retain) NSArray *choiceValues;

/*!
 * @brief What the field shows when nothing is stored
 *
 * A protocol's own default, usually. Never written by itself: a default that is stored becomes a fixed
 * value, and the next version of the protocol can no longer change it.
 */
@property (nonatomic, retain) id defaultValue;

//For AIAccountFieldAction: what the plan is asked to do
@property (nonatomic) SEL action;

/*!
 * @brief The preference is the opposite of what the row shows
 *
 * Two of Adium's own settings are stored as what they switch off, "Disable Typing Notifications" for
 * instance, while the row says what it allows.
 */
@property (nonatomic) BOOL inverted;

//A field whose text is not shown while it is typed
@property (nonatomic) BOOL secure;

//The preference holds an attributed string rather than a plain one
@property (nonatomic) BOOL attributed;

//Renaming an account that is connected would rename it out from under its connection
@property (nonatomic) BOOL disabledWhileOnline;

//Points wide, or 0 to take whatever the row leaves
@property (nonatomic) CGFloat width;

@end

/*!
 * @class AIAccountPlanCard
 * @brief The fields of one card, in the order they are shown
 */
@interface AIAccountPlanCard : NSObject {
	NSString		*identifier;
	NSMutableArray	*fields;
}

@property (nonatomic, retain) NSString *identifier;
@property (nonatomic, readonly) NSArray *fields;

- (void)addField:(AIAccountPlanField *)field;

@end

/*!
 * @class AIAccountPlan
 * @brief What one account offers to configure, and where each of those values lives
 *
 * The plan describes; it never builds. AIAccountPlanFormBuilder turns a plan into rows, and there is
 * exactly one of those, so no two services can end up looking different from one another.
 *
 * This base class describes what every account has: its name, its password, the name it shows to
 * others, and what it tells the other side about typing and reading. A subclass adds what its own
 * world brings, which for a libpurple account is everything the protocol declares about itself.
 *
 * A subclass may also carry behaviour, and that is the only reason for one to exist: a computed
 * default, a migration a key mapping cannot express, or an action a button performs. It still never
 * sees a view.
 */
@interface AIAccountPlan : NSObject {
	AIAccount		*account;
	NSMutableArray	*cards;
	BOOL			 passwordWasShown;
}

- (id)initWithAccount:(AIAccount *)inAccount;

@property (nonatomic, readonly) AIAccount *account;

/*!
 * @brief The cards, built on first use
 */
- (NSArray *)cards;

#pragma mark Values

/*!
 * @brief What is stored for this field, or its default when nothing is
 *
 * Reads the old key once when the field names one and nothing is stored under the current one.
 */
- (id)valueForField:(AIAccountPlanField *)field;

/*!
 * @brief Write a field, as it is changed
 *
 * A settings pane has no OK to wait for, so every change is written where it belongs immediately.
 */
- (void)setValue:(id)value forField:(AIAccountPlanField *)field;

/*!
 * @brief Whether the row may be used at all right now
 */
- (BOOL)fieldIsEnabled:(AIAccountPlanField *)field;

/*!
 * @brief Perform a field's action
 */
- (void)performActionForField:(AIAccountPlanField *)field;

#pragma mark Describing, for subclasses

/*!
 * @brief Say what this account offers
 *
 * Override and call super first, so the shared fields keep their place at the top of each card.
 */
- (void)describe;

- (void)addField:(AIAccountPlanField *)field toCard:(NSString *)cardIdentifier;

/*!
 * @brief Whether this account is asked for a password at all
 *
 * A protocol that authenticates by its own means says no, and then there is no password row.
 */
- (BOOL)offersPassword;

/*!
 * @brief Whether this account can tell the other side that a message was read
 */
- (BOOL)offersReadReceipts;

@end
