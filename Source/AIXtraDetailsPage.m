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

//Width the form starts out at; the preferences window resizes it to its column
#define XTRA_PAGE_INITIAL_WIDTH		540.0f

@interface AIXtraDetailsPage ()
- (void)buildForm;
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

@end
