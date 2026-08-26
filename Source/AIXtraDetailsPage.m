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

#import "AIXtraDetailsPage.h"
#import "AIXtraInfo.h"
#import <Adium/AISettingsFormView.h>
#import "AIJSXtrasManager.h"
#import "AIJSXtraBundle.h"

//Width the form starts out at; the preferences window resizes it to its column
#define XTRA_PAGE_INITIAL_WIDTH		540.0f

@interface AIXtraDetailsPage ()
@property (nonatomic) NSArray *settingDeclarations;
- (void)buildForm;
- (void)addSettingsCard;
- (BOOL)addValueRowWithLabel:(NSString *)label value:(NSString *)value;
- (NSString *)manifestStringForKey:(NSString *)key;
@end

/*!
 * @brief A row's value: right aligned, secondary, not editable but worth copying
 *
 * The shape System Settings gives a fact rather than a setting. Selectable on purpose: a bundle
 * identifier or a version is exactly the sort of thing somebody wants to paste into a bug report.
 */
static NSTextField *AIXtraDetailValue(NSString *value)
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];

	[field setEditable:NO];
	[field setSelectable:YES];
	[field setBezeled:NO];
	[field setBordered:NO];
	[field setDrawsBackground:NO];
	[field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[field setTextColor:[NSColor secondaryLabelColor]];
	[field setAlignment:NSTextAlignmentRight];
	[[field cell] setLineBreakMode:NSLineBreakByTruncatingTail];
	[field setStringValue:(value ?: @"")];

	/* A fitting size of its own, so the form pins the row to the width this text really needs and
	 * narrows it again only when the card cannot spare that much. */
	[field sizeToFit];

	return field;
}

@implementation AIXtraDetailsPage

- (id)initWithXtra:(AIXtraInfo *)inXtraInfo
	  categoryName:(NSString *)inCategoryName
		  delegate:(id<AIXtraDetailsPageDelegate>)inDelegate
{
	if ((self = [super init])) {
		xtraInfo = inXtraInfo;
		categoryName = [inCategoryName copy];
		pageDelegate = inDelegate;
	}

	return self;
}

- (AIXtraInfo *)xtra
{
	return xtraInfo;
}

- (void)tearDown
{
	pageDelegate = nil;
	xtraInfo = nil;
}

- (void)loadView
{
	form = [[AISettingsFormView alloc] initWithWidth:XTRA_PAGE_INITIAL_WIDTH];

	/* Every card here is about the same Xtra, so one label column throughout: otherwise a value
	 * under a short label sits further out than the one under a long label two cards down. */
	[form setSharesLabelColumn:YES];

	[self buildForm];
	[self setView:form];
}

//The cards ------------------------------------------------------------------------------------------------------------
#pragma mark The cards

- (void)buildForm
{
	NSBundle	*bundle = [xtraInfo bundle];
	BOOL		 isJavaScript = [[bundle objectForInfoDictionaryKey:@"AIJavaScriptPlugin"] boolValue];

	/* Who this is: the picture the Xtra ships - or, where it ships none, the document icon its kind
	 * of bundle gets - with the name beside it and whatever the manifest says it is underneath.
	 * A card of its own, because it is a block rather than a setting. */
	[form addInfoRow:[xtraInfo xtraDescription]
		   withImage:[xtraInfo icon]
			   title:[xtraInfo name]
			 control:nil];

	/* What the extension itself offers to change. Before the manifest facts rather than after them:
	 * it is the only thing on this page anybody came here to do, and reference material has no
	 * business sitting above a control. It also lands directly under the description, so the
	 * sentence naming the setting and the menu which is the setting are two rows apart. */
	if (isJavaScript) [self addSettingsCard];

	//Everything the manifest actually says. A field it does not carry is left out, not shown empty.
	[form endCard];

	/* Counted, because a card which stayed empty is one the form throws away again: the button
	 * below would then land in the card above it rather than in one of its own. Every Xtra fills in
	 * at least one of these today, so this is insurance rather than a case anybody will meet. */
	NSUInteger	fieldRows = 0;

	fieldRows += [self addValueRowWithLabel:AILocalizedString(@"Category", "Row on an Xtra's page naming the kind of Xtra it is")
									  value:categoryName];
	fieldRows += [self addValueRowWithLabel:AILocalizedString(@"Version", nil)
									  value:[xtraInfo version]];
	fieldRows += [self addValueRowWithLabel:AILocalizedString(@"Author", "Row on an Xtra's page naming who made it")
									  value:[xtraInfo author]];
	fieldRows += [self addValueRowWithLabel:AILocalizedString(@"Identifier", "Row on an Xtra's page carrying its bundle identifier")
									  value:[bundle bundleIdentifier]];

	NSString	*minimumVersion = [self manifestStringForKey:@"AIMinimumAdiumVersionRequirement"];

	if ([minimumVersion length]) {
		fieldRows += [self addValueRowWithLabel:AILocalizedString(@"Requires", "Row on an Xtra's page naming the oldest Adium it works with")
										  value:[NSString stringWithFormat:
												 AILocalizedString(@"Adium %@ or newer",
																   "Value of the 'Requires' row on an Xtra's page. %@ is a version number."),
												 minimumVersion]];
	}

	if (isJavaScript) {
		/* Which version of the extension API the plugin was written against. It says something only
		 * about a JavaScript extension, and for one of those it is the field which decides whether
		 * Adium will run it at all. */
		fieldRows += [self addValueRowWithLabel:AILocalizedString(@"Extension API", "Row on a JavaScript extension's page naming the API version it was written for")
										  value:[self manifestStringForKey:@"AIJavaScriptPluginAPIVersion"]];
	}

	//Where the file is, and a way to go and look at it
	if ([[xtraInfo path] length]) {
		[form addRowWithLabel:AILocalizedString(@"Location", "Row on an Xtra's page naming the folder it is installed in")
					  control:[AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Show in Finder", nil)
															   target:self
															   action:@selector(revealXtra:)]
					   detail:[[[xtraInfo path] stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath]];
		fieldRows++;
	}

	/* The one thing on this page which cannot be taken back. It stands alone at the bottom, away
	 * from everything that only reads, which is where System Settings puts a "Remove…" as well - and
	 * it is why the list's rows lost theirs: a target beside the switch is easy to hit by accident,
	 * and this one is not. The pane still asks before anything moves. */
	if ([pageDelegate respondsToSelector:@selector(xtraDetailsPage:canDeleteXtra:)] &&
		[pageDelegate xtraDetailsPage:self canDeleteXtra:xtraInfo]) {
		NSButton	*deleteButton = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Move to Trash", "Button on an Xtra's page which deletes it")
																	 target:self
																	 action:@selector(deleteXtra:)];

		[deleteButton setHasDestructiveAction:YES];

		if (fieldRows) [form endCard];

		[form addFullWidthRow:deleteButton stretch:NO];
	}
}

/*!
 * @brief The card of settings a JavaScript extension declares, or nothing at all
 *
 * Nothing for an extension declaring none - three of the five Adium ships declare none - and
 * nothing for one whose manifest the plugin manager refused, which is also not running. Both are
 * this page's established habit of leaving something out rather than showing it empty, and a card
 * with a header and no rows would be drawn as a bold heading above nothing.
 *
 * Shown whether the extension is switched on or off. Somebody who has just turned something off is
 * exactly the person who wants to look at why, and a value chosen while it is off takes hold when
 * it comes back on.
 *
 * A card of its own, under a header Adium wrote, and that is a security decision rather than a
 * taste one: a manifest-supplied title sits in the same visual grammar as Adium's own row labels,
 * so mixed into the facts card an author could write a row reading "Identifier" or "Requires" and
 * have it read as something Adium said.
 */
- (void)addSettingsCard
{
	NSString	*identifier = [[xtraInfo bundle] bundleIdentifier];

	[self setSettingDeclarations:[[AIJSXtrasManager sharedManager] settingsForPluginWithIdentifier:identifier]];

	if (![[self settingDeclarations] count]) return;

	[form addSectionHeader:AILocalizedString(@"Settings", "Header of the card on a JavaScript extension's page holding the settings its manifest declares")];

	NSUInteger	index = 0;

	for (AIJSXtraSetting *setting in [self settingDeclarations]) {
		NSPopUpButton	*popUp = [AISettingsFormView popUpButtonWithTitles:[setting optionTitles]
																	target:self
																	action:@selector(changedSetting:)];

		/* A menu built from titles is only as long as the titles are distinct: -[NSPopUpButton
		 * addItemWithTitle:] REMOVES an item already carrying that title. The validator refuses a
		 * manifest whose options read alike, so this cannot happen; if it ever does, the row is
		 * left out rather than drawn over options it no longer lines up with. */
		if ([[popUp itemArray] count] != [[setting optionValues] count]) {
			NSLog(@"JSXtra: the menu for %@ does not match its options; leaving the row out", [setting key]);
			index++;
			continue;
		}

		/* What each item stands for, so that reading the choice back never depends on where the
		 * item sits. The tag says which setting the menu belongs to. */
		NSUInteger	option = 0;

		for (NSMenuItem *item in [popUp itemArray]) {
			[item setRepresentedObject:[[setting optionValues] objectAtIndex:option]];
			option++;
		}

		[popUp setTag:(NSInteger)index];

		NSUInteger	selected = [[setting optionValues] indexOfObject:
								[[AIJSXtrasManager sharedManager] valueForSettingKey:[setting key]
															   pluginWithIdentifier:identifier]];

		//Never NSNotFound: the manager coerces a stored value back into the declared list on read
		if (selected != NSNotFound) [popUp selectItemAtIndex:(NSInteger)selected];

		/* addRowWithLabel:control:detail: rather than addRowWithLabel:popUpButton:accessoryButton:,
		 * which re-measures its menu at every layout for menus rebuilt on the fly and offers no
		 * detail line: this menu is built once from a manifest that cannot change while the page is
		 * open. */
		[form addRowWithLabel:[setting title] control:popUp detail:[setting detail]];

		index++;
	}

	/* Two sentences, and the first is the honest one: these are the only rows in Adium's settings
	 * whose labels a stranger wrote. The second says what the list behind this page already says
	 * about JavaScript extensions, in the same voice, and it is a real warning, because a change
	 * reloads and replays every open transcript. */
	[form addFootnote:AILocalizedString(@"What can be changed here is whatever the extension offers; the wording is its author's, not Adium's. A change takes effect immediately in every open conversation.",
										"Footnote below the settings card on a JavaScript extension's page")];

	[form endCard];
}

/*!
 * @brief Add a row reading "@a label … @a value", or nothing at all where there is no value
 *
 * @return YES if a row was added
 */
- (BOOL)addValueRowWithLabel:(NSString *)label value:(NSString *)value
{
	if (![value length]) return NO;

	[form addRowWithLabel:label control:AIXtraDetailValue(value)];

	return YES;
}

/*!
 * @brief A manifest key as a string, whatever the plist wrote it as
 *
 * The API version is a number in every manifest Adium ships and a string in about half the ones in
 * the wild; -objectForInfoDictionaryKey: hands back whichever was written, and a row which showed
 * nothing because the plist said 1 rather than "1" would be a poor reason to leave a field blank.
 */
- (NSString *)manifestStringForKey:(NSString *)key
{
	id	value = [[xtraInfo bundle] objectForInfoDictionaryKey:key];

	if ([value isKindOfClass:[NSString class]]) return value;
	if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];

	return nil;
}

#pragma mark Actions

- (IBAction)revealXtra:(id)sender
{
	[pageDelegate xtraDetailsPage:self revealXtra:xtraInfo];
}

- (IBAction)deleteXtra:(id)sender
{
	[pageDelegate xtraDetailsPage:self deleteXtra:xtraInfo];
}

/*!
 * @brief A menu on the settings card was used
 *
 * Writes a preference of Adium's. Nothing here touches the bundle, which is why this is the one
 * thing the page does without asking the pane: the delegate exists for the two actions that move
 * files, and this moves none.
 *
 * The chosen value comes off the menu item rather than from its position, so a menu which is not
 * the shape the declarations expect can write nothing rather than write the wrong thing.
 */
- (IBAction)changedSetting:(id)sender
{
	NSUInteger	index = (NSUInteger)[sender tag];

	if (index >= [[self settingDeclarations] count]) return;

	AIJSXtraSetting	*setting = [[self settingDeclarations] objectAtIndex:index];
	NSString		*value = [[sender selectedItem] representedObject];

	if (![value isKindOfClass:[NSString class]]) return;

	[[AIJSXtrasManager sharedManager] setValue:value
								 forSettingKey:[setting key]
						  pluginWithIdentifier:[[xtraInfo bundle] bundleIdentifier]];
}

@end
