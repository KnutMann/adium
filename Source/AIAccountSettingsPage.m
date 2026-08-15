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
#import "AIAccountOptionsPage.h"

#import <Adium/AIAccount.h>
#import <Adium/AIAccountPlan.h>
#import <Adium/AIAccountPlanFormBuilder.h>
#import <Adium/AISettingsNavigationController.h>
#import <Adium/AIService.h>
#import <Adium/AIServiceIcons.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIStringUtilities.h>

@interface AIAccountSettingsPage ()
- (void)buildForm;
- (void)showMoreOptions:(id)sender;
- (void)fieldChanged:(AIAccountPlanField *)field;
- (void)editingChanged:(NSNotification *)notification;
- (void)windowResignedKey:(NSNotification *)notification;
@end

@implementation AIAccountSettingsPage

- (id)initWithAccount:(AIAccount *)inAccount backTarget:(id)inTarget action:(SEL)inAction
{
	if ((self = [super initWithNibName:nil bundle:nil])) {
		account = [inAccount retain];
		backTarget = inTarget;
		backAction = inAction;

		/* A fresh one per drill down: a plan reads the account's values as it is built, and the window
		 * this replaces made a new controller each time it opened too. */
		plan = [[account accountPlan] retain];
		builder = [[AIAccountPlanFormBuilder alloc] initWithPlan:plan];
		[builder setChangeTarget:self action:@selector(fieldChanged:)];

		/* Typing is what makes a page dirty, not leaving a field: tabbing through an account without
		 * touching anything ends editing in every field it passes and changes none of them. */
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(editingChanged:)
													 name:NSControlTextDidChangeNotification
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(windowResignedKey:)
													 name:NSWindowDidResignKeyNotification
												   object:nil];
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
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[builder release]; builder = nil;
	[plan release]; plan = nil;
	[form release]; form = nil;
	[account release]; account = nil;
	backTarget = nil;
}

- (AIAccount *)account
{
	return account;
}

//Saving ---------------------------------------------------------------------------------------------------------------
#pragma mark Saving

/*!
 * @brief A field was changed and has already been written
 *
 * The plan writes as it goes, because a settings pane has no OK to wait for. What is left is telling
 * the account, which is not cheap: it reconfigures a live connection and can bounce it.
 */
- (void)fieldChanged:(AIAccountPlanField *)field
{
	edited = YES;
	[self commit];
}

- (void)commit
{
	/* Re-entrant by nature: saving an account tells its observers, and one of them redraws the row
	 * behind this page, which ends editing somewhere and asks to save again. */
	if (committing || !account || !edited)
		return;

	committing = YES;
	edited = NO;

	//Once per burst, so a page full of fields does not tell the account per field
	[NSObject cancelPreviousPerformRequestsWithTarget:account selector:@selector(accountEdited) object:nil];
	[account performSelector:@selector(accountEdited) withObject:nil afterDelay:0.0];

	committing = NO;
}

- (void)editingChanged:(NSNotification *)notification
{
	if ([[notification object] isDescendantOf:[self view]])
		edited = YES;
}

/*!
 * @brief The window went away; whatever was typed goes with it
 */
- (void)windowResignedKey:(NSNotification *)notification
{
	if ([notification object] != [[self view] window])
		return;

	//Ends editing in whatever field had it, so its value is written before the window is gone
	[[[self view] window] makeFirstResponder:nil];
	[self commit];
}

- (void)loadView
{
	form = [[AISettingsFormView alloc] initWithWidth:600.0f];

	/* Every card here is about the same account, so one label column throughout: otherwise a field
	 * under a short label is wider than the one under a long label two cards down. */
	[form setSharesLabelColumn:YES];

	[self buildForm];
	[self setView:form];
}

//The cards ------------------------------------------------------------------------------------------------------------
#pragma mark The cards

- (void)buildForm
{
	//Which account this is
	NSImage *serviceIcon = [AIServiceIcons serviceIconForObject:account
														   type:AIServiceIconLarge
													  direction:AIIconNormal];
	[form addInfoRow:[[account service] longDescription]
		   withImage:serviceIcon
			   title:[account formattedUID]
			 control:nil];

	/* Everything but the options nobody curated. A dozen rows named the way the protocol names them
	 * would be the first thing met on this page, and they are the last thing most accounts need. */
	[builder buildInForm:form skippingCard:AIAccountCardMore];

	if ([builder hasFieldsInCard:AIAccountCardMore]) {
		NSButton *chevron = [AISettingsFormView inlineSymbolButtonWithSymbolName:@"chevron.forward"
															  fallbackImageName:nil
																		 target:self
																		 action:@selector(showMoreOptions:)];

		[chevron setAccessibilityLabel:AILocalizedString(@"More Options",
														 "Row that opens the options a protocol offers beyond the usual ones")];

		[form endCard];
		[form addRowWithLabel:AILocalizedString(@"More Options",
												"Row that opens the options a protocol offers beyond the usual ones")
					  control:chevron];
	}

	[form layoutForWidth:600.0f];
}

/*!
 * @brief Open the protocol's remaining options as a page of their own
 */
- (void)showMoreOptions:(id)sender
{
	AIAccountOptionsPage *page = [[[AIAccountOptionsPage alloc] initWithBuilder:builder
																		  card:AIAccountCardMore] autorelease];

	//The stack this page is in is the one it was pushed onto, so there is nothing to hand around
	id parent = [self parentViewController];

	if ([parent isKindOfClass:[AISettingsNavigationController class]])
		[(AISettingsNavigationController *)parent pushViewController:page animated:YES];
}

@end
