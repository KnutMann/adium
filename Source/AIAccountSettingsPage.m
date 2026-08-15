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
- (void)watchControlsIn:(NSView *)hosted;
- (void)hostedControlActed:(id)sender;
- (void)editingEnded:(NSNotification *)notification;
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

		/* A fresh one per drill down: -configureForAccount: is written to run once, and the window
		 * this replaces made a new controller each time it opened too. */
		accountViewController = [[[account service] accountViewController] retain];
		[accountViewController configureForAccount:account];

		hostedTargets = [[NSMutableDictionary alloc] init];
		hostedActions = [[NSMutableDictionary alloc] init];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(editingEnded:)
													 name:NSControlTextDidEndEditingNotification
												   object:nil];
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

//Saving ---------------------------------------------------------------------------------------------------------------
#pragma mark Saving

- (void)commit
{
	/* Re-entrant by nature: saving an account tells its observers, and one of them redraws the row
	 * behind this page, which ends editing somewhere and asks to save again. */
	if (committing || !account || !accountViewController)
		return;

	committing = YES;

	/* Written every time, because it is idempotent and cheap: it puts the state of the controls back
	 * where it came from. */
	[accountViewController saveConfiguration];

	/* Telling the account is not cheap: it reconfigures a live connection and can bounce it. So it
	 * happens only when something was actually typed or switched, not merely because the page was
	 * opened and left again. Once per burst, so a page full of fields does not do it per field. */
	if (edited) {
		edited = NO;
		[NSObject cancelPreviousPerformRequestsWithTarget:account selector:@selector(accountEdited) object:nil];
		[account performSelector:@selector(accountEdited) withObject:nil afterDelay:0.0];
	}

	committing = NO;
}

/*!
 * @brief A field somewhere on the page was left
 */
- (void)editingEnded:(NSNotification *)notification
{
	[self commit];
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

	//Ends editing in whatever field had it, so its value is on the control before it is read
	[[[self view] window] makeFirstResponder:nil];
	[self commit];
}

/*!
 * @brief Take over every control in a hosted view, then hand the click on
 *
 * The service views come from nibs whose controls point at their own controller, and there are nine
 * of those. Rather than change all nine, each control's target and action are remembered and
 * replaced with this: it forwards to where the click was going and then saves. A control bound
 * through the controller rather than targeted has nothing to intercept, which is why leaving a field
 * and leaving the page save as well.
 */
- (void)watchControlsIn:(NSView *)hosted
{
	for (NSView *subview in [hosted subviews]) {
		if ([subview isKindOfClass:[NSControl class]]) {
			NSControl *control = (NSControl *)subview;

			//Text fields report through the editing notification; taking their action would break them
			if (![control isKindOfClass:[NSTextField class]] && [control action]) {
				[hostedTargets setObject:[NSValue valueWithPointer:[control target]]
								  forKey:[NSValue valueWithNonretainedObject:control]];
				[hostedActions setObject:NSStringFromSelector([control action])
								  forKey:[NSValue valueWithNonretainedObject:control]];
				[control setTarget:self];
				[control setAction:@selector(hostedControlActed:)];
			}
		}

		[self watchControlsIn:subview];
	}
}

- (void)hostedControlActed:(id)sender
{
	NSValue *senderKey = [NSValue valueWithNonretainedObject:sender];
	id originalTarget = [[hostedTargets objectForKey:senderKey] pointerValue];
	NSString *originalAction = [hostedActions objectForKey:senderKey];

	edited = YES;

	if (originalTarget && originalAction) {
		SEL action = NSSelectorFromString(originalAction);
		if ([originalTarget respondsToSelector:action])
			[originalTarget performSelector:action withObject:sender];
	}

	[self commit];
}

- (void)tearDown
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[hostedTargets release]; hostedTargets = nil;
	[hostedActions release]; hostedActions = nil;

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

	/* A service using the shared account views has exactly the fields everyone knows about, and those
	 * become ordinary rows. One with a nib of its own has fields nobody here knows, so its view is
	 * shown whole rather than picked apart. */
	BOOL shared = [accountViewController usesSharedAccountViews];

	if (shared) {
		[form addSectionHeader:AILocalizedString(@"Account", "Section header above an account's name and password")];
		[accountViewController addAccountRowsToForm:form];

		[form addSectionHeader:AILocalizedString(@"Personal", "Section header above an account's personal details")];
		[accountViewController addProfileRowsToForm:form];
	} else {
		[self addHostedView:[accountViewController setupView]
				underHeader:AILocalizedString(@"Account", "Section header above an account's name and password")];
		[self addHostedView:[accountViewController profileView]
				underHeader:AILocalizedString(@"Personal", "Section header above an account's personal details")];
	}
	/* Options as ordinary rows when the protocol can describe them, which for a libpurple protocol
	 * means always: it declares each option's name, type, default and, for a choice, the choices.
	 * Only when nothing can be had that way is the service's own view hosted instead, which is what
	 * every service used to do and why no two of them looked alike. */
	if ([accountViewController respondsToSelector:@selector(addOptionRowsToForm:)]) {
		/* Every libpurple protocol describes its own options, so every one of them gets ordinary rows
		 * and none of them needs a nib for it. A protocol with nothing to configure gets no heading
		 * over an empty card. */
		if ([(id)accountViewController hasProtocolOptions]) {
			[form addSectionHeader:AILocalizedString(@"Options", "Section header above an account's options")];
			[(id)accountViewController addOptionRowsToForm:form];
		}
	} else {
		[self addHostedView:[accountViewController optionsView]
				underHeader:AILocalizedString(@"Options", "Section header above an account's options")];
	}
	if (shared) {
		[form addSectionHeader:AILocalizedString(@"Privacy", "Section header above an account's privacy settings")];
		[accountViewController addPrivacyRowsToForm:form];
	} else {
		[self addHostedView:[accountViewController privacyView]
				underHeader:AILocalizedString(@"Privacy", "Section header above an account's privacy settings")];
	}

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
	[self watchControlsIn:hosted];
}

@end
