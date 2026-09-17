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

#import <Adium/AIPlugin.h>
#import <Adium/AIContentControllerProtocol.h>

/*!
 * @class AIMessageStylingPlugin
 * @brief Reads the markup people type, in every conversation
 *
 * XEP-0393 wrote down what had been typed at each other for years, and WhatsApp reads the
 * same characters, so this is not tied to one service: whoever sends *this* means it to be
 * read as emphasis, and until now Adium showed the asterisks and nothing else.
 *
 * Only how a message looks changes. The text is never touched, the directives stay where
 * they were written, and nothing is sent differently.
 */
@interface AIMessageStylingPlugin : AIPlugin <AIContentFilter> {
}

@end
