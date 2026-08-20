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

#import <Foundation/Foundation.h>

@class CNContact;

/*!
 * @brief One address book card, as Adium reads it
 *
 * A thin, immutable face over CNContact: the fields the integration actually
 * uses, under the names the old ABPerson-based code used for them, so that the
 * rest of Adium reads a card without knowing which framework delivered it.
 */
@interface AIAddressBookPerson : NSObject {
	CNContact	*contact;
}

+ (instancetype)personWithContact:(CNContact *)inContact;

@property (readonly, nonatomic) CNContact *contact;

//The card's stable identifier: CNContact.identifier (on macOS: UUID plus ":ABPerson")
@property (readonly, nonatomic) NSString *uniqueId;

@property (readonly, nonatomic) NSString *firstName;
@property (readonly, nonatomic) NSString *middleName;
@property (readonly, nonatomic) NSString *lastName;
@property (readonly, nonatomic) NSString *nickname;
@property (readonly, nonatomic) NSString *organization;
@property (readonly, nonatomic) NSString *phoneticFirstName;
@property (readonly, nonatomic) NSString *phoneticMiddleName;
@property (readonly, nonatomic) NSString *phoneticLastName;

//YES for a card that shows as a company rather than a person
@property (readonly, nonatomic) BOOL isCompany;

//NSString values, in card order
@property (readonly, nonatomic) NSArray *emailAddresses;
@property (readonly, nonatomic) NSArray *phoneNumbers;

//The card's Jabber names, from the instant-message entries
@property (readonly, nonatomic) NSArray *jabberNames;

/*!
 * @brief The card's picture, fetched from the store when asked
 *
 * Not part of the cached fields: pictures are big and rarely needed, so they
 * are read per card, on demand.
 */
- (NSData *)imageData;

@end
