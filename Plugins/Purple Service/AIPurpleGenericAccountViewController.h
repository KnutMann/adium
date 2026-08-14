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

#import "PurpleAccountViewController.h"

/*!
 * @class AIPurpleGenericAccountViewController
 * @brief The account editor for a protocol described by a descriptor
 *
 * Shows the fields the protocol has a use for and hides the rest. A protocol that authenticates by
 * its own means says so, and then there is no password field; one that connects wherever it likes
 * declares no server or port option, and then there are no server and port fields.
 *
 * Both of those were hand written per protocol until now, and both said the same thing three times.
 */
@interface AIPurpleGenericAccountViewController : PurpleAccountViewController

@end
