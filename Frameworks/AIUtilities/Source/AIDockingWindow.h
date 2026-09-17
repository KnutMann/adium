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

/*!
 * @class AIDockingWindow
 * @brief An NSWindow subclass which docks to screen edges
 *
 * An NSWindow subclass which docks to screen edges. It also posts AIWindowToolbarDidToggleVisibility to the default notification center
 * when its toolbar visibility is toggled with an object of the window.
 *
 * Docking is temporarily disabled if the shift key is held.
 */

#define AIWindowToolbarDidToggleVisibility @"AIWindowToolbarDidToggleVisibility"

@interface AIDockingWindow : NSWindow {
	NSRect			oldWindowFrame;
	unsigned int	resisted_XMotion;
	unsigned int	resisted_YMotion;
	BOOL 			alreadyMoving;
	
	BOOL			dockingEnabled;
}

- (void)setDockingEnabled:(BOOL)inEnabled;

@end

/*!
 * @class AIDockingPanel
 * @brief The same window that snaps to the screen edges, drawn with a small title bar
 *
 * The system draws a tall title bar on an ordinary window, taller than it used to, and
 * over a contact list that is most of the window's height it costs more than it says. A
 * utility panel gets the short bar instead, the one the inspector has, and that is the
 * only supported way to ask for it: the style mask that selects it is documented as
 * applying to NSPanel and nothing else.
 *
 * What a panel otherwise changes is put back here. It would hide itself when the
 * application is deactivated, which for a contact list is exactly wrong, and it would
 * refuse to be the main window, which is the only window Adium has when no conversation
 * is open.
 */
@interface AIDockingPanel : NSPanel {
	NSRect			oldWindowFrame;
	unsigned int	resisted_XMotion;
	unsigned int	resisted_YMotion;
	BOOL 			alreadyMoving;

	BOOL			dockingEnabled;
}

- (void)setDockingEnabled:(BOOL)inEnabled;

@end
