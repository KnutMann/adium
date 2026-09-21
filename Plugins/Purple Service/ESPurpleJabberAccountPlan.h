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

#import "AIPurpleAccountPlan.h"

/*!
 * @class ESPurpleJabberAccountPlan
 * @brief What XMPP brings beyond its own options
 *
 * Two of Adium's old switches say together what the protocol says with one choice, and that cannot
 * be written down as a key mapping. And the settings Adium keeps for an XMPP account itself, rather
 * than handing them to the protocol: the resource, the priorities, the certificate check, what to
 * do when somebody asks to see the status, and whether the song playing is told. Everything the
 * protocol declares is in prpl-jabber.json.
 */
@interface ESPurpleJabberAccountPlan : AIPurpleAccountPlan

@end
