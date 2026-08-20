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

#import "AIAddressBookPerson.h"
#import <Contacts/Contacts.h>

@implementation AIAddressBookPerson

+ (instancetype)personWithContact:(CNContact *)inContact
{
	if (!inContact) return nil;

	AIAddressBookPerson *person = [[[self alloc] init] autorelease];
	person->contact = [inContact retain];
	return person;
}

- (void)dealloc
{
	[contact release];
	[super dealloc];
}

- (CNContact *)contact
{
	return contact;
}

- (NSString *)uniqueId
{
	return contact.identifier;
}

- (NSString *)firstName          { return contact.givenName; }
- (NSString *)middleName         { return contact.middleName; }
- (NSString *)lastName           { return contact.familyName; }
- (NSString *)nickname           { return contact.nickname; }
- (NSString *)organization       { return contact.organizationName; }
- (NSString *)phoneticFirstName  { return contact.phoneticGivenName; }
- (NSString *)phoneticMiddleName { return contact.phoneticMiddleName; }
- (NSString *)phoneticLastName   { return contact.phoneticFamilyName; }

- (BOOL)isCompany
{
	return (contact.contactType == CNContactTypeOrganization);
}

- (NSArray *)emailAddresses
{
	NSMutableArray *addresses = [NSMutableArray array];
	for (CNLabeledValue *labeled in contact.emailAddresses) {
		NSString *address = (NSString *)labeled.value;
		if ([address length]) [addresses addObject:address];
	}
	return addresses;
}

- (NSArray *)phoneNumbers
{
	NSMutableArray *numbers = [NSMutableArray array];
	for (CNLabeledValue *labeled in contact.phoneNumbers) {
		NSString *number = [(CNPhoneNumber *)labeled.value stringValue];
		if ([number length]) [numbers addObject:number];
	}
	return numbers;
}

- (NSArray *)jabberNames
{
	NSMutableArray *names = [NSMutableArray array];
	for (CNLabeledValue *labeled in contact.instantMessageAddresses) {
		CNInstantMessageAddress *address = (CNInstantMessageAddress *)labeled.value;

		if ([address.service caseInsensitiveCompare:CNInstantMessageServiceJabber] == NSOrderedSame &&
			[address.username length]) {
			[names addObject:address.username];
		}
	}
	return names;
}

- (NSData *)imageData
{
	CNContact *withImage = contact;

	if (![withImage isKeyAvailable:CNContactImageDataKey]) {
		withImage = [[[[CNContactStore alloc] init] autorelease] unifiedContactWithIdentifier:contact.identifier
																				  keysToFetch:[NSArray arrayWithObject:CNContactImageDataKey]
																						error:NULL];
	}

	return withImage.imageData;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p %@>", NSStringFromClass([self class]), self, self.uniqueId];
}

@end
