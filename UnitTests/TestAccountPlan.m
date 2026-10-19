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
#import <Adium/AIAccountPlan.h>
#import <Adium/AIAccount.h>
#import <Adium/AIChat.h>

/* What a protocol's plan does: call super, then add its own rows, to a shared card and to one of
 * its own, and answer a button. */
@interface TAPExtendedPlan : AIAccountPlan
@property (nonatomic, readonly) AIAccountPlanField *rungField;
@end

@implementation TAPExtendedPlan

- (void)describe
{
	[super describe];
	[self addField:[AIAccountPlanField fieldNamed:@"server" kind:AIAccountFieldText] toCard:AIAccountCardAccount];
	[self addField:[AIAccountPlanField fieldNamed:@"colour" kind:AIAccountFieldChoice] toCard:@"appearance"];
}

- (void)ring:(AIAccountPlanField *)field
{
	_rungField = field;
}

@end

@interface TAPNoReceiptsPlan : AIAccountPlan
@end

@implementation TAPNoReceiptsPlan
- (BOOL)offersReadReceipts { return NO; }
@end

static AIAccountPlanCard *TAPCard(AIAccountPlan *plan, NSString *identifier)
{
	for (AIAccountPlanCard *card in plan.cards) {
		if ([card.identifier isEqualToString:identifier])
			return card;
	}
	return nil;
}

static AIAccountPlanField *TAPField(AIAccountPlan *plan, NSString *cardIdentifier, NSString *name)
{
	for (AIAccountPlanField *field in TAPCard(plan, cardIdentifier).fields) {
		if ([field.name isEqualToString:name])
			return field;
	}
	return nil;
}

@interface TestAccountPlan : XCTestCase
@end

@implementation TestAccountPlan

#pragma mark Fields and cards

- (void)testFieldFactorySetsNameAndKind
{
	AIAccountPlanField *field = [AIAccountPlanField fieldNamed:@"server" kind:AIAccountFieldNumber];
	XCTAssertEqualObjects(field.name, @"server");
	XCTAssertEqual(field.kind, AIAccountFieldNumber);
}

- (void)testFieldDefaultsToNoStoreInTheAccountStatusGroup
{
	AIAccountPlanField *field = [AIAccountPlanField fieldNamed:@"server" kind:AIAccountFieldText];
	XCTAssertEqual(field.store, AIAccountFieldStoreNone);
	XCTAssertEqualObjects(field.preferenceGroup, GROUP_ACCOUNT_STATUS);
	XCTAssertNil(field.preferenceKey);
	XCTAssertNil(field.legacyKey);
	XCTAssertNil(field.defaultValue);
	XCTAssertFalse(field.inverted);
	XCTAssertFalse(field.secure);
	XCTAssertFalse(field.attributed);
	XCTAssertFalse(field.disabledWhileOnline);
	XCTAssertEqual(field.width, (CGFloat)0);
}

- (void)testCardKeepsFieldsInOrderAndIgnoresNil
{
	AIAccountPlanCard *card = [[AIAccountPlanCard alloc] init];
	AIAccountPlanField *first = [AIAccountPlanField fieldNamed:@"first" kind:AIAccountFieldText];
	AIAccountPlanField *second = [AIAccountPlanField fieldNamed:@"second" kind:AIAccountFieldText];
	[card addField:first];
	[card addField:nil];
	[card addField:second];
	XCTAssertEqualObjects(card.fields, (@[first, second]));
}

#pragma mark The shared plan

- (void)testPlanOpensTheFiveCardsInDisplayOrder
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	NSArray *expected = @[AIAccountCardAccount, AIAccountCardPersonal, AIAccountCardOptions, AIAccountCardMore, AIAccountCardPrivacy];
	XCTAssertEqualObjects([plan.cards valueForKey:@"identifier"], expected);
}

- (void)testCardsAreBuiltOnce
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	NSArray *cards = plan.cards;
	XCTAssertTrue(plan.cards == cards);
	XCTAssertEqual(plan.cards.count, (NSUInteger)5);
}

- (void)testAccountCardStartsWithTheAccountName
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	AIAccountPlanField *name = TAPCard(plan, AIAccountCardAccount).fields.firstObject;
	XCTAssertEqualObjects(name.name, @"name");
	XCTAssertEqual(name.kind, AIAccountFieldText);
	XCTAssertEqual(name.store, AIAccountFieldStoreAccountName);
	XCTAssertTrue(name.disabledWhileOnline, @"renaming a connected account would rename it out from under its connection");
}

- (void)testNoPasswordRowWhenTheServiceOffersNone
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	XCTAssertFalse(plan.offersPassword);
	XCTAssertNil(TAPField(plan, AIAccountCardAccount, @"password"));
}

- (void)testPersonalCardCarriesTheDisplayName
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	AIAccountPlanField *displayName = TAPField(plan, AIAccountCardPersonal, @"displayName");
	XCTAssertNotNil(displayName);
	XCTAssertEqual(displayName.kind, AIAccountFieldText);
	XCTAssertEqual(displayName.store, AIAccountFieldStorePreference);
	XCTAssertEqualObjects(displayName.preferenceKey, KEY_ACCOUNT_DISPLAY_NAME);
	XCTAssertEqualObjects(displayName.preferenceGroup, GROUP_ACCOUNT_STATUS);
	XCTAssertTrue(displayName.attributed);
}

- (void)testPrivacyCardCarriesTypingReceiptsAndEncryption
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	XCTAssertEqualObjects([TAPCard(plan, AIAccountCardPrivacy).fields valueForKey:@"name"], (@[@"typing", @"readReceipts", @"encryption"]));

	AIAccountPlanField *typing = TAPField(plan, AIAccountCardPrivacy, @"typing");
	XCTAssertEqual(typing.kind, AIAccountFieldSwitch);
	XCTAssertEqual(typing.store, AIAccountFieldStorePreference);
	/* The key is what every existing account already has stored under; it is spelled out here
	 * because renaming it would silently drop everybody's setting. */
	XCTAssertEqualObjects(typing.preferenceKey, @"Disable Typing Notifications");
	XCTAssertTrue(typing.inverted);
	XCTAssertEqualObjects(typing.defaultValue, @NO);

	AIAccountPlanField *receipts = TAPField(plan, AIAccountCardPrivacy, @"readReceipts");
	XCTAssertEqual(receipts.kind, AIAccountFieldSwitch);
	XCTAssertEqual(receipts.store, AIAccountFieldStorePreference);
	XCTAssertEqualObjects(receipts.preferenceKey, KEY_DISABLE_READ_RECEIPTS);
	XCTAssertTrue(receipts.inverted);
	XCTAssertEqualObjects(receipts.defaultValue, @NO);

	AIAccountPlanField *encryption = TAPField(plan, AIAccountCardPrivacy, @"encryption");
	XCTAssertEqual(encryption.kind, AIAccountFieldEncryption);
	XCTAssertEqual(encryption.store, AIAccountFieldStorePreference);
	XCTAssertEqualObjects(encryption.preferenceKey, KEY_ENCRYPTED_CHAT_PREFERENCE);
	XCTAssertEqualObjects(encryption.preferenceGroup, GROUP_ENCRYPTION);
	XCTAssertFalse(encryption.inverted);
}

- (void)testOptionsAndMoreCardsStartEmpty
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	XCTAssertEqualObjects(TAPCard(plan, AIAccountCardOptions).fields, @[]);
	XCTAssertEqualObjects(TAPCard(plan, AIAccountCardMore).fields, @[]);
}

- (void)testAPlanMayDeclineReadReceipts
{
	AIAccountPlan *plan = [[TAPNoReceiptsPlan alloc] initWithAccount:nil];
	XCTAssertEqualObjects([TAPCard(plan, AIAccountCardPrivacy).fields valueForKey:@"name"], (@[@"typing", @"encryption"]));
}

#pragma mark A protocol's plan

- (void)testASubclassAddsBehindTheSharedFields
{
	AIAccountPlan *plan = [[TAPExtendedPlan alloc] initWithAccount:nil];
	XCTAssertEqualObjects([TAPCard(plan, AIAccountCardAccount).fields valueForKey:@"name"], (@[@"name", @"server"]));
}

- (void)testACardOfItsOwnIsOpenedBehindTheSharedOnes
{
	AIAccountPlan *plan = [[TAPExtendedPlan alloc] initWithAccount:nil];
	NSArray *expected = @[AIAccountCardAccount, AIAccountCardPersonal, AIAccountCardOptions, AIAccountCardMore, AIAccountCardPrivacy, @"appearance"];
	XCTAssertEqualObjects([plan.cards valueForKey:@"identifier"], expected);
	XCTAssertEqualObjects([TAPCard(plan, @"appearance").fields valueForKey:@"name"], @[@"colour"]);
}

#pragma mark Values

- (void)testValueForAPreferenceFieldIsItsDefaultWhenNothingIsStored
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	AIAccountPlanField *field = [AIAccountPlanField fieldNamed:@"server" kind:AIAccountFieldText];
	field.store = AIAccountFieldStorePreference;
	field.preferenceKey = @"Server";
	XCTAssertNil([plan valueForField:field]);

	field.defaultValue = @"talk.example.org";
	XCTAssertEqualObjects([plan valueForField:field], @"talk.example.org");
}

- (void)testAnInvertedSwitchShowsTheOppositeOfItsStoredDefault
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	AIAccountPlanField *field = [AIAccountPlanField fieldNamed:@"typing" kind:AIAccountFieldSwitch];
	field.store = AIAccountFieldStorePreference;
	field.preferenceKey = @"Disable Something";
	field.inverted = YES;
	field.defaultValue = @NO;
	XCTAssertEqualObjects([plan valueForField:field], @YES);

	field.defaultValue = @YES;
	XCTAssertEqualObjects([plan valueForField:field], @NO);
}

- (void)testValueForAnActionFieldIsNil
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	AIAccountPlanField *field = [AIAccountPlanField fieldNamed:@"ring" kind:AIAccountFieldAction];
	field.defaultValue = @"ignored";
	XCTAssertNil([plan valueForField:field]);
}

- (void)testFieldsAreEnabledWhileTheAccountIsOffline
{
	AIAccountPlan *plan = [[AIAccountPlan alloc] initWithAccount:nil];
	AIAccountPlanField *field = [AIAccountPlanField fieldNamed:@"name" kind:AIAccountFieldText];
	XCTAssertTrue([plan fieldIsEnabled:field]);
	field.disabledWhileOnline = YES;
	XCTAssertTrue([plan fieldIsEnabled:field]);
}

- (void)testPerformActionCallsTheFieldsActionOnThePlan
{
	TAPExtendedPlan *plan = [[TAPExtendedPlan alloc] initWithAccount:nil];
	AIAccountPlanField *field = [AIAccountPlanField fieldNamed:@"ring" kind:AIAccountFieldAction];
	field.action = @selector(ring:);
	[plan performActionForField:field];
	XCTAssertTrue(plan.rungField == field);
}

- (void)testPerformActionWithoutAnActionDoesNothing
{
	TAPExtendedPlan *plan = [[TAPExtendedPlan alloc] initWithAccount:nil];
	AIAccountPlanField *silent = [AIAccountPlanField fieldNamed:@"silent" kind:AIAccountFieldAction];
	[plan performActionForField:silent];

	AIAccountPlanField *unknown = [AIAccountPlanField fieldNamed:@"unknown" kind:AIAccountFieldAction];
	unknown.action = @selector(thisSelectorIsNotImplemented:);
	[plan performActionForField:unknown];

	XCTAssertNil(plan.rungField);
}

@end
