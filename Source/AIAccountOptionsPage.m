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

#import "AIAccountOptionsPage.h"

#import <Adium/AIAccountPlanFormBuilder.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIStringUtilities.h>

@implementation AIAccountOptionsPage

- (id)initWithBuilder:(AIAccountPlanFormBuilder *)inBuilder card:(NSString *)inCardIdentifier
{
	if ((self = [super initWithNibName:nil bundle:nil])) {
		builder = [inBuilder retain];
		cardIdentifier = [inCardIdentifier copy];
	}

	return self;
}

- (void)dealloc
{
	[builder release];
	[form release];
	[cardIdentifier release];

	[super dealloc];
}

/*!
 * @brief The picture over the explanation
 *
 * A protocol plugin is what these settings come from, and a plugin is what the symbol says. Drawn
 * from the system rather than shipped, so it follows the appearance the way every other symbol in
 * this window does.
 */
- (NSImage *)pluginImage
{
	NSImage *image = nil;

	if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)])
		image = [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension.fill" accessibilityDescription:nil];

	if (!image)
		return nil;

	NSImageSymbolConfiguration *configuration =
		[NSImageSymbolConfiguration configurationWithPointSize:30.0
													  weight:NSFontWeightRegular
													   scale:NSImageSymbolScaleLarge];

	return [image imageWithSymbolConfiguration:configuration];
}

- (void)loadView
{
	form = [[AISettingsFormView alloc] initWithWidth:600.0f];
	[form setSharesLabelColumn:YES];

	[form addInfoRow:AILocalizedString(@"These come from the protocol itself rather than from Adium, and they are shown exactly as it declares them: its own names, its own wording, its own defaults. Nothing here has been chosen or arranged, which is why most accounts never need any of it. What is worth reaching for is on the page you came from.",
									   "Explains the card holding the options a protocol offers beyond the ones Adium puts in front of a person")
		   withImage:[self pluginImage]
			   title:AILocalizedString(@"Straight from the protocol",
									   "Title of the block above a protocol's remaining options")
			 control:nil];

	[builder buildCard:cardIdentifier inForm:form];

	[form layoutForWidth:600.0f];
	[self setView:form];
}

@end
