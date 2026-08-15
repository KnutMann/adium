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

#import "AIAccountSettingsPage.h"

#import <Adium/AIAccount.h>
#import <Adium/AIAccountViewController.h>
#import <Adium/AIService.h>
#import <Adium/AIServiceIcons.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIStringUtilities.h>

@interface AIAccountSettingsPage ()
- (void)buildForm;
- (void)addHostedView:(NSView *)hosted underHeader:(NSString *)header;
@end

@implementation AIAccountSettingsPage

- (id)initWithAccount:(AIAccount *)inAccount backTarget:(id)inTarget action:(SEL)inAction
{
	if ((self = [super initWithNibName:nil bundle:nil])) {
		account = [inAccount retain];
		backTarget = inTarget;
		backAction = inAction;

		/* A fresh one per drill down: -configureForAccount: is written to run once, and the window
		 * this replaces made a new controller each time it opened too. */
		accountViewController = [[[account service] accountViewController] retain];
		[accountViewController configureForAccount:account];
	}

	return self;
}

- (void)dealloc
{
	[self tearDown];
	[super dealloc];
}

- (void)tearDown
{
	[accountViewController release]; accountViewController = nil;
	[form release]; form = nil;
	[account release]; account = nil;
	backTarget = nil;
}

- (AIAccount *)account
{
	return account;
}

- (void)loadView
{
	form = [[AISettingsFormView alloc] initWithWidth:600.0f];
	[self buildForm];
	[self setView:form];
}

//The cards ------------------------------------------------------------------------------------------------------------
#pragma mark The cards

- (void)buildForm
{
	//Which account this is, and whether it is on
	NSImage *serviceIcon = [AIServiceIcons serviceIconForObject:account
														  type:AIServiceIconLarge
													 direction:AIIconNormal];
	[form addInfoRow:[[account service] longDescription]
		   withImage:serviceIcon
			   title:[account formattedUID]
			 control:nil];

	[self addHostedView:[accountViewController setupView]
			underHeader:AILocalizedString(@"Account", "Section header above an account's name and password")];
	[self addHostedView:[accountViewController profileView]
			underHeader:AILocalizedString(@"Personal", "Section header above an account's personal details")];
	/* Options as ordinary rows when the protocol can describe them, which for a libpurple protocol
	 * means always: it declares each option's name, type, default and, for a choice, the choices.
	 * Only when nothing can be had that way is the service's own view hosted instead, which is what
	 * every service used to do and why no two of them looked alike. */
	if ([accountViewController respondsToSelector:@selector(addOptionRowsToForm:)] &&
		[(id)accountViewController hasProtocolOptions]) {
		[form addSectionHeader:AILocalizedString(@"Options", "Section header above an account's options")];
		[(id)accountViewController addOptionRowsToForm:form];
	} else if (![accountViewController respondsToSelector:@selector(addOptionRowsToForm:)]) {
		[self addHostedView:[accountViewController optionsView]
				underHeader:AILocalizedString(@"Options", "Section header above an account's options")];
	}
	[self addHostedView:[accountViewController privacyView]
			underHeader:AILocalizedString(@"Privacy", "Section header above an account's privacy settings")];

	[form layoutForWidth:600.0f];
}

/*!
 * @brief Put one of the service's own views into a card of its own
 *
 * A view the service does not supply becomes no card at all, rather than the empty tab the window
 * this replaces would have shown.
 */
- (void)addHostedView:(NSView *)hosted underHeader:(NSString *)header
{
	if (!hosted)
		return;

	[form addSectionHeader:header];
	[form addFullWidthRow:hosted stretch:YES];
}

@end
