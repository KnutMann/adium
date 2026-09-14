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

#import "AIJingleCallUI.h"
#import "AIJingleCallWindowController.h"

#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIMenuControllerProtocol.h>
#import <Adium/AIListContact.h>
#import <Adium/AIService.h>
#import <AIUtilities/AIStringUtilities.h>

#define RING_WIDTH	340.0
#define RING_HEIGHT	110.0
#define MARGIN		16.0

@implementation AIJingleCallUI {
	NSMenuItem *callMenuItem, *videoCallMenuItem;
	NSMenuItem *callContextItem, *videoCallContextItem;

	NSMutableDictionary<NSString *, NSPanel *> *ringPanelsBySid;
	NSMutableDictionary<NSString *, NSString *> *displayNamesBySid;
	NSMutableDictionary<NSString *, AIJingleCallWindowController *> *windowsBySid;
	NSString *upcomingDisplayName;		//set right before the manager reports callBegan
}

+ (AIJingleCallUI *)sharedUI
{
	static AIJingleCallUI *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [[AIJingleCallUI alloc] init];
	});
	return shared;
}

+ (void)install
{
	AIJingleCallUI *ui = [self sharedUI];
	[AIJingleCallManager sharedManager].uiDelegate = ui;
	[ui installMenuItems];
}

- (id)init
{
	if ((self = [super init])) {
		ringPanelsBySid = [NSMutableDictionary dictionary];
		displayNamesBySid = [NSMutableDictionary dictionary];
		windowsBySid = [NSMutableDictionary dictionary];
	}
	return self;
}

//The menu ---------------------------------------------------------------------------------------
#pragma mark The menu

- (void)installMenuItems
{
	callMenuItem = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Call", "Menu item starting an audio call with the selected contact")
											  action:@selector(startAudioCall:)
									   keyEquivalent:@""];
	[callMenuItem setTarget:self];
	[adium.menuController addMenuItem:callMenuItem toLocation:LOC_Contact_Action];

	videoCallMenuItem = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Video Call", "Menu item starting a video call with the selected contact")
												   action:@selector(startVideoCall:)
											keyEquivalent:@""];
	[videoCallMenuItem setTarget:self];
	[adium.menuController addMenuItem:videoCallMenuItem toLocation:LOC_Contact_Action];

	callContextItem = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Call", "Menu item starting an audio call with the selected contact")
												 action:@selector(startAudioCall:)
										  keyEquivalent:@""];
	[callContextItem setTarget:self];
	[adium.menuController addContextualMenuItem:callContextItem toLocation:Context_Contact_Action];

	videoCallContextItem = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Video Call", "Menu item starting a video call with the selected contact")
													  action:@selector(startVideoCall:)
											   keyEquivalent:@""];
	[videoCallContextItem setTarget:self];
	[adium.menuController addContextualMenuItem:videoCallContextItem toLocation:Context_Contact_Action];
}

- (AIListContact *)contactForMenuItem:(NSMenuItem *)menuItem
{
	AIListObject *object;

	if (menuItem == callContextItem || menuItem == videoCallContextItem)
		object = adium.menuController.currentContextMenuObject;
	else
		object = adium.interfaceController.selectedListObject;

	if (![object isKindOfClass:[AIListContact class]])
		return nil;

	AIListContact *contact = (AIListContact *)object;
	if (![contact.service.serviceClass isEqualToString:@"Jabber"])
		return nil;

	return contact;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	AIListContact *contact = [self contactForMenuItem:menuItem];
	return (contact && contact.online && contact.account.online);
}

- (void)startAudioCall:(NSMenuItem *)sender	{ [self startCallFromMenuItem:sender withVideo:NO]; }
- (void)startVideoCall:(NSMenuItem *)sender	{ [self startCallFromMenuItem:sender withVideo:YES]; }

- (void)startCallFromMenuItem:(NSMenuItem *)sender withVideo:(BOOL)withVideo
{
	AIListContact *contact = [self contactForMenuItem:sender];
	if (!contact)
		return;

	AIJingleCallManager *manager = [AIJingleCallManager sharedManager];
	NSString *fullJid = [manager fullJidForContact:contact];
	if (![fullJid length]) {
		NSBeep();
		return;
	}

	upcomingDisplayName = contact.displayName;
	[manager startCallToJid:fullJid onAccount:(CBPurpleAccount *)contact.account withVideo:withVideo];
}

//Ringing ----------------------------------------------------------------------------------------
#pragma mark Ringing

- (NSString *)displayNameForJid:(NSString *)fullJid onAccount:(CBPurpleAccount *)account
{
	NSRange slash = [fullJid rangeOfString:@"/"];
	NSString *bareJid = (slash.location == NSNotFound ? fullJid : [fullJid substringToIndex:slash.location]);
	AIListContact *contact = [account contactWithUID:bareJid];

	return ([contact.displayName length] ? contact.displayName : bareJid);
}

- (void)manager:(AIJingleCallManager *)manager promptForIncomingCallWithSid:(NSString *)sid
		   from:(NSString *)fromJid onAccount:(CBPurpleAccount *)account offersVideo:(BOOL)offersVideo
{
	NSString *name = [self displayNameForJid:fromJid onAccount:account];
	displayNamesBySid[sid] = name;

	NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, RING_WIDTH, RING_HEIGHT)
												styleMask:NSWindowStyleMaskTitled
												  backing:NSBackingStoreBuffered
													defer:NO];
	[panel setTitle:AILocalizedString(@"Incoming Call", "Title of the window announcing a call")];
	[panel setLevel:NSFloatingWindowLevel];
	[panel setReleasedWhenClosed:NO];

	NSView *content = [panel contentView];

	NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]];
	[label setStringValue:(offersVideo ?
		[NSString stringWithFormat:AILocalizedString(@"%@ is calling (with video)", "Ringing text; %@ is the caller"), name] :
		[NSString stringWithFormat:AILocalizedString(@"%@ is calling", "Ringing text; %@ is the caller"), name])];
	[label setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:label];

	NSButton *decline = [NSButton buttonWithTitle:AILocalizedString(@"Decline", "Button turning a call away")
										   target:self
										   action:@selector(declineRingingCall:)];
	[decline setBezelStyle:NSBezelStyleRounded];
	[decline setKeyEquivalent:@"\e"];
	[decline setIdentifier:sid];
	[decline setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:decline];

	NSButton *accept = [NSButton buttonWithTitle:AILocalizedString(@"Answer", "Button taking a call")
										  target:self
										  action:@selector(acceptRingingCall:)];
	[accept setBezelStyle:NSBezelStyleRounded];
	[accept setKeyEquivalent:@"\r"];
	[accept setIdentifier:sid];
	[accept setTranslatesAutoresizingMaskIntoConstraints:NO];
	[content addSubview:accept];

	NSButton *acceptWithCamera = nil;
	if (offersVideo) {
		acceptWithCamera = [NSButton buttonWithTitle:AILocalizedString(@"Accept with Camera", "Button taking a call and sending the own camera too")
											  target:self
											  action:@selector(acceptRingingCallWithCamera:)];
		[acceptWithCamera setBezelStyle:NSBezelStyleRounded];
		[acceptWithCamera setIdentifier:sid];
		[acceptWithCamera setTranslatesAutoresizingMaskIntoConstraints:NO];
		[content addSubview:acceptWithCamera];
	}

	NSMutableArray *constraints = [NSMutableArray arrayWithObjects:
		[label.topAnchor constraintEqualToAnchor:content.topAnchor constant:MARGIN],
		[label.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:MARGIN],
		[label.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-MARGIN],
		[accept.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-MARGIN],
		[accept.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-MARGIN],
		[decline.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:MARGIN],
		[decline.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-MARGIN],
		nil];
	if (acceptWithCamera) {
		[constraints addObject:[acceptWithCamera.trailingAnchor constraintEqualToAnchor:accept.leadingAnchor constant:-8.0]];
		[constraints addObject:[acceptWithCamera.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-MARGIN]];
	}
	[NSLayoutConstraint activateConstraints:constraints];

	ringPanelsBySid[sid] = panel;
	[panel center];
	[panel makeKeyAndOrderFront:nil];
	[NSApp requestUserAttention:NSCriticalRequest];
}

- (void)closeRingPanelForSid:(NSString *)sid
{
	NSPanel *panel = ringPanelsBySid[sid];
	[ringPanelsBySid removeObjectForKey:sid];
	[panel orderOut:nil];
}

- (void)acceptRingingCall:(NSButton *)sender
{
	NSString *sid = [sender identifier];
	[self closeRingPanelForSid:sid];
	upcomingDisplayName = displayNamesBySid[sid];
	[[AIJingleCallManager sharedManager] acceptIncomingCallWithSid:sid withVideo:NO];
}

- (void)acceptRingingCallWithCamera:(NSButton *)sender
{
	NSString *sid = [sender identifier];
	[self closeRingPanelForSid:sid];
	upcomingDisplayName = displayNamesBySid[sid];
	[[AIJingleCallManager sharedManager] acceptIncomingCallWithSid:sid withVideo:YES];
}

- (void)declineRingingCall:(NSButton *)sender
{
	NSString *sid = [sender identifier];
	[self closeRingPanelForSid:sid];
	[displayNamesBySid removeObjectForKey:sid];
	[[AIJingleCallManager sharedManager] declineIncomingCallWithSid:sid];
}

- (void)manager:(AIJingleCallManager *)manager incomingCallWithdrawn:(NSString *)sid
{
	[self closeRingPanelForSid:sid];
	[displayNamesBySid removeObjectForKey:sid];
}

//The windows ------------------------------------------------------------------------------------
#pragma mark The windows

- (void)manager:(AIJingleCallManager *)manager callBegan:(AIJingleCallController *)controller
{
	NSString *sid = controller.machine.sid;
	NSString *name = upcomingDisplayName;
	upcomingDisplayName = nil;

	if (![name length]) {
		NSRange slash = [controller.peerFullJid rangeOfString:@"/"];
		name = (slash.location == NSNotFound ? controller.peerFullJid :
				[controller.peerFullJid substringToIndex:slash.location]);
	}
	[displayNamesBySid removeObjectForKey:sid];

	windowsBySid[sid] = [[AIJingleCallWindowController alloc] initWithCallController:controller
																		 displayName:name];
}

- (void)manager:(AIJingleCallManager *)manager callConnected:(AIJingleCallController *)controller
{
	[windowsBySid[controller.machine.sid] noteConnected];
}

- (void)manager:(AIJingleCallManager *)manager call:(AIJingleCallController *)controller
	hasRemoteVideoTrack:(RTCVideoTrack *)track
{
	[windowsBySid[controller.machine.sid] attachRemoteVideoTrack:track];
}

- (void)manager:(AIJingleCallManager *)manager call:(AIJingleCallController *)controller
	endedWithReason:(NSString *)reason locally:(BOOL)locally
{
	NSString *sid = controller.machine.sid;
	AIJingleCallWindowController *window = windowsBySid[sid];
	[windowsBySid removeObjectForKey:sid];

	//The window knows whether this ending closes it or stays readable
	[window noteEndedWithReason:reason locally:locally];
}

@end
