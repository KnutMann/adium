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

#import <Adium/AIAdvancedPreferencePane.h>

@interface ESStatusAdvancedPreferences : AIAdvancedPreferencePane <NSTokenFieldDelegate> {
	IBOutlet	NSTextField					*label_statusWindow;
	IBOutlet	NSButton					*checkBox_statusWindowHideInBackground;
	IBOutlet	NSButton					*checkBox_statusWindowAlwaysOnTop;

	IBOutlet	NSBox						*box_itunesElements;

	IBOutlet	NSTextField					*label_itunesStatusFormat;
	IBOutlet	NSTextField					*label_instructions;
	IBOutlet	NSTextField					*label_album;
	IBOutlet	NSTextField					*label_artist;
	IBOutlet	NSTextField					*label_composer;
	IBOutlet	NSTextField					*label_genre;
	IBOutlet	NSTextField					*label_status;
	IBOutlet	NSTextField					*label_title;
	IBOutlet	NSTextField					*label_year;

	IBOutlet	NSTokenField				*tokenField_format;
	IBOutlet	NSTokenField				*tokenField_album;
	IBOutlet	NSTokenField				*tokenField_artist;
	IBOutlet	NSTokenField				*tokenField_composer;
	IBOutlet	NSTokenField				*tokenField_genre;
	IBOutlet	NSTokenField				*tokenField_status;
	IBOutlet	NSTokenField				*tokenField_title;
	IBOutlet	NSTokenField				*tokenField_year;
}

@end
