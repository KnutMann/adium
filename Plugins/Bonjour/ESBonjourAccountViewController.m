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

#import "ESBonjourAccountViewController.h"

//Use the default profile view, but override optionsView to be nil so it isn't displayed
@implementation ESBonjourAccountViewController

//Account specific views -----------------------------------------------------------------------------------------------
#pragma mark Account specific views
//Options view
- (NSView *)optionsView
{
    return nil;
}

#pragma mark Localization
//The xib is monolingual (English) and uses plain controls; set all visible strings from code
- (void)localizeStrings
{
	[super localizeStrings];

	NSBundle *adiumFrameworkBundle = [NSBundle bundleForClass:[AIAccountViewController class]];
	[label_typing setStringValue:AILocalizedStringFromTableInBundle(@"Typing:", nil, adiumFrameworkBundle, "Label beside the 'let others know when you are typing' checkbox in the account preferences")];
	[checkBox_sendTyping setTitle:AILocalizedStringFromTableInBundle(@"Let others know when you are typing", nil, adiumFrameworkBundle, "Text of the typing preference checkbox in the account preferences")];
}

@end
