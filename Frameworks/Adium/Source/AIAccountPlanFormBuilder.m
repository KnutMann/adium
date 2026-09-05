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

#import <Adium/AIAccountPlanFormBuilder.h>
#import <Adium/AIAccountPlan.h>
#import <Adium/AIAccount.h>
#import <Adium/AIService.h>
#import <Adium/AIChat.h>
#import <Adium/AISettingsFormView.h>
#import <Adium/AIContentControllerProtocol.h>
#import <AIUtilities/AIStringFormatter.h>
#import <AIUtilities/AIStringUtilities.h>

@interface AIAccountPlanFormBuilder () <NSTextViewDelegate>
- (NSString *)titleForCard:(NSString *)identifier;
- (void)addCard:(AIAccountPlanCard *)card toForm:(AISettingsFormView *)form;
- (void)addField:(AIAccountPlanField *)field toForm:(AISettingsFormView *)form;
- (NSView *)controlForField:(AIAccountPlanField *)field;
- (void)controlChanged:(id)sender;
- (void)actionPressed:(id)sender;
@end

@implementation AIAccountPlanFormBuilder

- (id)initWithPlan:(AIAccountPlan *)inPlan
{
	if ((self = [super init])) {
		plan = inPlan;
		fieldsByName = [[NSMutableDictionary alloc] init];
		controlsByName = [[NSMutableDictionary alloc] init];
	}

	return self;
}

- (void)setChangeTarget:(id)target action:(SEL)inAction
{
	changeTarget = target;
	changeAction = inAction;
}

//Building ---------------------------------------------------------------------------------------
#pragma mark Building

/*!
 * @brief What a card is called
 *
 * A plan names its cards by identifier rather than by title, so the words live here, where the
 * localisation tooling can find them, and a plan written in a plugin does not carry English.
 */
- (NSString *)titleForCard:(NSString *)identifier
{
	if ([identifier isEqualToString:AIAccountCardAccount])
		return AILocalizedString(@"Account", "Section header above an account's name and password");

	if ([identifier isEqualToString:AIAccountCardPersonal])
		return AILocalizedString(@"Personal", "Section header above an account's personal details");

	if ([identifier isEqualToString:AIAccountCardOptions])
		return AILocalizedString(@"Options", "Section header above an account's options");

	if ([identifier isEqualToString:AIAccountCardMore])
		return AILocalizedString(@"More Options", "Section header above the options a protocol offers beyond the usual ones");

	if ([identifier isEqualToString:AIAccountCardPrivacy])
		return AILocalizedString(@"Privacy", "Section header above an account's privacy settings");

	return identifier;
}

- (void)buildInForm:(AISettingsFormView *)form
{
	[self buildInForm:form skippingCard:nil];
}

- (void)buildInForm:(AISettingsFormView *)form skippingCard:(NSString *)skipped
{
	for (AIAccountPlanCard *card in [plan cards]) {
		if (skipped && [[card identifier] isEqualToString:skipped])
			continue;

		[self addCard:card toForm:form];
	}
}

- (void)buildCard:(NSString *)cardIdentifier inForm:(AISettingsFormView *)form
{
	for (AIAccountPlanCard *card in [plan cards]) {
		if ([[card identifier] isEqualToString:cardIdentifier])
			[self addCard:card toForm:form];
	}
}

- (BOOL)hasFieldsInCard:(NSString *)cardIdentifier
{
	for (AIAccountPlanCard *card in [plan cards]) {
		if ([[card identifier] isEqualToString:cardIdentifier])
			return ([[card fields] count] != 0);
	}

	return NO;
}

- (void)addNavigationRowTo:(NSString *)cardIdentifier
					inForm:(AISettingsFormView *)form
					 label:(NSString *)label
					target:(id)target
					action:(SEL)action
{
	//Nothing opened the card if it has no rows, and an unopened card is the one before it
	if (![self hasFieldsInCard:cardIdentifier])
		[form addSectionHeader:[self titleForCard:cardIdentifier]];

	[form addNavigationRowWithLabel:label target:target action:action];
}

- (void)addCard:(AIAccountPlanCard *)card toForm:(AISettingsFormView *)form
{
	if (![[card fields] count])
		return;

	[form addSectionHeader:[self titleForCard:[card identifier]]];

	for (AIAccountPlanField *field in [card fields])
		[self addField:field toForm:form];
}

- (void)addField:(AIAccountPlanField *)field toForm:(AISettingsFormView *)form
{
	NSView *control = [self controlForField:field];
	if (!control)
		return;

	[fieldsByName setObject:field forKey:[field name]];
	[controlsByName setObject:control forKey:[field name]];

	if ([field kind] == AIAccountFieldAction) {
		//At the trailing edge, the way a lone action button sits under the row it acts on
		[form addFullWidthRow:control stretch:NO trailingAligned:YES];
		return;
	}

	//A tall control reads better with its label beside its first line, not its middle
	if ([field kind] == AIAccountFieldMultiline) {
		[form addRowWithLabel:[field label] stretchingControl:control labelTopAligned:YES];

		//No room beside a box this tall, so what would have been a second line goes under it
		if ([[field detail] length])
			[form addDetailRow:[field detail]];

		return;
	}

	/* A field the row decides the width of, against a control that brought its own. A text field
	 * given its natural width would sit as a stub at the trailing edge. */
	if ([field kind] == AIAccountFieldText && [field width] <= 0.0)
		[form addRowWithLabel:[field label] stretchingControl:control];
	else
		[form addRowWithLabel:[field label] control:control detail:[field detail]];
}

- (NSView *)controlForField:(AIAccountPlanField *)field
{
	id value = [plan valueForField:field];
	BOOL enabled = [plan fieldIsEnabled:field];

	switch ([field kind]) {
		case AIAccountFieldText: {
			NSTextField *control;

			if ([field secure]) {
				/* No factory for this one: a secure field is the only control here that is not what
				 * the form vends, and it wants exactly the same wiring. */
				control = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 160.0, 22.0)];
				[control setTarget:self];
				[control setAction:@selector(controlChanged:)];
				[[control cell] setSendsActionOnEndEditing:YES];
			} else if ([field width] > 0.0) {
				control = [AISettingsFormView valueFieldWithWidth:[field width]
														  target:self
														  action:@selector(controlChanged:)];
			} else {
				control = [AISettingsFormView textFieldWithTarget:self action:@selector(controlChanged:)];
			}

			[control setStringValue:(value ? value : @"")];

			if ([field placeholder])
				[[control cell] setPlaceholderString:[field placeholder]];

			/* What a name may look like is the service's own rule, and it is the only field whose
			 * contents are not free text. */
			if ([field store] == AIAccountFieldStoreAccountName) {
				AIService *service = [[plan account] service];

				[control setFormatter:
					[AIStringFormatter stringFormatterAllowingCharacters:[service allowedCharactersForAccountName]
																 length:[service allowedLengthForAccountName]
														  caseSensitive:[service caseSensitive]
														   errorMessage:AILocalizedString(@"The characters you're entering are not valid for an account name on this service.", nil)]];
			}

			[control setEnabled:enabled];
			[control setIdentifier:[field name]];

			return control;
		}

		case AIAccountFieldMultiline: {
			NSScrollView *scroller = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 72.0)];
			NSTextView *editor = [[NSTextView alloc] initWithFrame:[[scroller contentView] bounds]];

			[editor setString:(value ? value : @"")];
			[editor setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
			[editor setRichText:NO];
			[editor setAutomaticQuoteSubstitutionEnabled:NO];
			[editor setDelegate:self];
			[editor setIdentifier:[field name]];
			[editor setEditable:enabled];
			[editor setAutoresizingMask:NSViewWidthSizable];
			[[editor textContainer] setWidthTracksTextView:YES];

			[scroller setDocumentView:editor];
			[scroller setHasVerticalScroller:YES];
			[scroller setBorderType:NSBezelBorder];
			[scroller setIdentifier:[field name]];

			//What is looked up on a change is the editor, which is what the delegate hands back
			return scroller;
		}

		case AIAccountFieldNumber: {
			NSTextField *control = [AISettingsFormView valueFieldWithWidth:([field width] > 0.0 ? [field width] : 70.0)
																   target:self
																   action:@selector(controlChanged:)];

			[control setStringValue:(value ? [value stringValue] : @"")];

			if ([field placeholder])
				[[control cell] setPlaceholderString:[field placeholder]];

			[control setEnabled:enabled];
			[control setIdentifier:[field name]];

			return control;
		}

		case AIAccountFieldSwitch: {
			NSSwitch *control = [AISettingsFormView switchWithTarget:self action:@selector(controlChanged:)];

			[control setState:([value boolValue] ? NSControlStateValueOn : NSControlStateValueOff)];
			[control setEnabled:enabled];
			[control setIdentifier:[field name]];

			return control;
		}

		case AIAccountFieldChoice: {
			if (![[field choiceTitles] count])
				return nil;

			NSPopUpButton *control = [AISettingsFormView popUpButtonWithTitles:[field choiceTitles]
																	   target:self
																	   action:@selector(controlChanged:)];

			//The menu shows what a person reads; what is stored is what the protocol wants
			for (NSUInteger i = 0; i < [[field choiceValues] count] && i < (NSUInteger)[control numberOfItems]; i++)
				[[control itemAtIndex:(NSInteger)i] setRepresentedObject:[[field choiceValues] objectAtIndex:i]];

			NSUInteger index = (value ? [[field choiceValues] indexOfObject:value] : NSNotFound);

			/* A stored value the protocol no longer offers falls back to the protocol's own default
			 * rather than to whatever happens to be first in the menu: showing the first entry would
			 * claim a setting nobody chose. */
			if (index == NSNotFound && [field defaultValue])
				index = [[field choiceValues] indexOfObject:[field defaultValue]];

			if (index != NSNotFound)
				[control selectItemAtIndex:(NSInteger)index];

			[control setEnabled:enabled];
			[control setIdentifier:[field name]];

			return control;
		}

		case AIAccountFieldEncryption: {
			NSPopUpButton *control = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 25.0)];

			[control setMenu:[adium.contentController encryptionMenuNotifyingTarget:nil withDefault:NO]];
			[[control menu] setAutoenablesItems:NO];

			/* The menu is built for a target of its own. Taking the items' actions away lets the
			 * button send its own, which is what tells us the row was used. */
			for (NSMenuItem *item in [[control menu] itemArray]) {
				[item setTarget:nil];
				[item setAction:NULL];
			}

			[control selectItemWithTag:[value integerValue]];
			[control sizeToFit];
			[control setTarget:self];
			[control setAction:@selector(controlChanged:)];
			[control setEnabled:enabled];
			[control setIdentifier:[field name]];

			return control;
		}

		case AIAccountFieldAction: {
			NSButton *control = [AISettingsFormView pushButtonWithTitle:[field label]
																 target:self
																 action:@selector(actionPressed:)];

			[control setEnabled:enabled];
			[control setIdentifier:[field name]];

			return control;
		}
	}

	return nil;
}

//Changes ----------------------------------------------------------------------------------------
#pragma mark Changes

- (void)controlChanged:(id)sender
{
	AIAccountPlanField *field = [fieldsByName objectForKey:[sender identifier]];
	if (!field)
		return;

	id value = nil;

	switch ([field kind]) {
		case AIAccountFieldText:
			value = [sender stringValue];
			break;

		case AIAccountFieldMultiline:
			value = [sender string];
			break;

		case AIAccountFieldNumber:
			//An emptied field is not a zero: it means the setting is not given, so the default applies
			value = ([[sender stringValue] length] ? [NSNumber numberWithInteger:[sender integerValue]] : nil);
			break;

		case AIAccountFieldSwitch:
			value = [NSNumber numberWithBool:([sender state] == NSControlStateValueOn)];
			break;

		case AIAccountFieldChoice:
			value = [[sender selectedItem] representedObject];
			break;

		case AIAccountFieldEncryption:
			value = [NSNumber numberWithInteger:[[sender selectedItem] tag]];
			break;

		case AIAccountFieldAction:
			return;
	}

	[plan setValue:value forField:field];

	if (changeTarget && changeAction && [changeTarget respondsToSelector:changeAction])
		/* Void callback selector; no returned object to leak. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[changeTarget performSelector:changeAction withObject:field];
#pragma clang diagnostic pop
}

/*!
 * @brief A text editor was left
 *
 * An editor sends no action, so this is where a multi line field is written. Every keystroke would be
 * a preference write, which is why it waits for the editor to be left.
 */
- (void)textDidEndEditing:(NSNotification *)notification
{
	[self controlChanged:[notification object]];
}

- (void)actionPressed:(id)sender
{
	AIAccountPlanField *field = [fieldsByName objectForKey:[sender identifier]];

	if (field)
		[plan performActionForField:field];
}

@end
