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

#import "AIEventsInspectorPane.h"
#import <Adium/AIListObject.h>
#import <Adium/AIListContact.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/ESContactAlertsViewController.h>
#import <AIUtilities/AIBundleAdditions.h>

#define EVENTS_NIB_NAME (@"AIEventsInspectorPane")

@implementation AIEventsInspectorPane

- (id) init
{
	self = [super init];
	if (self != nil) {
		[NSBundle ai_loadNibNamed:[self nibName] owner:self];
		/* The loader hands every top level object one reference that belongs to nobody
		 * (see AIBundleAdditions.h); the strong ivars hold their own, so the stray ones
		 * are given up here, once. */
		if (inspectorContentView) CFRelease((__bridge CFTypeRef)inspectorContentView);
		if (alertsController) CFRelease((__bridge CFTypeRef)alertsController);
		//Other init goes here.
	}
	return self;
}

-(NSString *)nibName
{
	return EVENTS_NIB_NAME;
}

-(NSView *)inspectorContentView
{
	return inspectorContentView;
}

-(void)updateForListObject:(AIListObject *)inObject
{
	[alertsController configureForListObject:inObject];
}

@end
