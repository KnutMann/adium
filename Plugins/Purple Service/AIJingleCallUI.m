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
#import "AIJingleCallDiagnostics.h"

#import <Adium/AIChat.h>
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIContentControllerProtocol.h>
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
	NSMutableDictionary<NSString *, AIListContact *> *contactsBySid;	//for the note in the chat
	NSMutableArray<AIJingleCallWindowController *> *lingeringWindows;	//finished calls still on screen
	NSString *upcomingDisplayName;		//set right before the manager reports callBegan
	NSTimer *ringTimer;
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
		contactsBySid = [NSMutableDictionary dictionary];
		lingeringWindows = [NSMutableArray array];
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

	NSMenuItem *selfTestItem = [[NSMenuItem alloc] initWithTitle:
		AILocalizedString(@"Check Call Readiness…", "Menu item running the call self test")
												 action:@selector(runSelfTest:)
										  keyEquivalent:@""];
	[selfTestItem setTarget:self];
	[adium.menuController addMenuItem:selfTestItem toLocation:LOC_Adium_Other];

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

//The self test ----------------------------------------------------------------------------------
#pragma mark The self test

- (void)runSelfTest:(id)sender
{
	[AIJingleCallDiagnostics runWithCompletion:^(NSArray<AIJingleCallFinding *> *findings) {
		[self showFindings:findings asFailureOfCall:nil];
	}];
}

- (void)showFindings:(NSArray<AIJingleCallFinding *> *)findings asFailureOfCall:(NSString *)peerName
{
	NSMutableString *text = [NSMutableString string];
	NSString *settingsURL = nil;

	for (AIJingleCallFinding *finding in findings) {
		[text appendFormat:@"%@ %@: %@\n\n", (finding.good ? @"✓" : @"✗"), finding.title, finding.detail];
		if (!finding.good && !settingsURL)
			settingsURL = finding.settingsURL;
	}

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:([peerName length] ?
		[NSString stringWithFormat:AILocalizedString(@"The call with %@ could not connect",
													 "Title after a call failed; %@ is the contact"), peerName] :
		AILocalizedString(@"Call readiness", "Title of the call self test result"))];
	[alert setInformativeText:[text stringByTrimmingCharactersInSet:
							   [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	[alert addButtonWithTitle:AILocalizedString(@"OK", nil)];

	if (settingsURL)
		[alert addButtonWithTitle:AILocalizedString(@"Open Privacy Settings",
												   "Button leading to the system's privacy settings")];

	if ([alert runModal] == NSAlertSecondButtonReturn && settingsURL)
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:settingsURL]];
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
	if ([menuItem action] == @selector(runSelfTest:))
		return YES;

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

	/* The bare JID: the proposal rings every device of the contact, and the one that
	 * answers becomes the peer; the manager falls back to the best resource by itself
	 * when nobody speaks the ringing language. */
	upcomingDisplayName = contact.displayName;
	[[AIJingleCallManager sharedManager] startCallToJid:contact.UID
											  onAccount:(CBPurpleAccount *)contact.account
											  withVideo:withVideo];
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
		//Nothing held this off the button beside it, and in German it sat on top of it
		[constraints addObject:[acceptWithCamera.leadingAnchor constraintGreaterThanOrEqualToAnchor:decline.trailingAnchor constant:12.0]];
	} else {
		[constraints addObject:[accept.leadingAnchor constraintGreaterThanOrEqualToAnchor:decline.trailingAnchor constant:12.0]];
	}
	[constraints addObject:[label.bottomAnchor constraintLessThanOrEqualToAnchor:accept.topAnchor constant:-MARGIN]];
	[NSLayoutConstraint activateConstraints:constraints];

	/* A window wide enough for whichever language is speaking. The words for
	 * declining and answering differ in length from one to the next, and a panel
	 * built to fit the English ones has them overlapping in German. */
	NSSize wanted = [content fittingSize];
	[panel setContentSize:NSMakeSize(MAX(wanted.width, RING_WIDTH), MAX(wanted.height, RING_HEIGHT))];

	ringPanelsBySid[sid] = panel;
	[panel center];
	[panel makeKeyAndOrderFront:nil];
	[NSApp requestUserAttention:NSCriticalRequest];
	[self startRinging];
}

/*! @brief An audible ring while any prompt is up; a system sound stands in for a ringtone */
- (void)startRinging
{
	if (ringTimer)
		return;

	[[NSSound soundNamed:@"Glass"] play];
	ringTimer = [NSTimer scheduledTimerWithTimeInterval:2.5
												 target:self
											   selector:@selector(ringOnce)
											   userInfo:nil
												repeats:YES];
}

- (void)ringOnce
{
	if (![ringPanelsBySid count]) {
		[ringTimer invalidate];
		ringTimer = nil;
		return;
	}
	[[NSSound soundNamed:@"Glass"] play];
}

- (void)closeRingPanelForSid:(NSString *)sid
{
	NSPanel *panel = ringPanelsBySid[sid];
	[ringPanelsBySid removeObjectForKey:sid];
	[panel orderOut:nil];

	if (![ringPanelsBySid count]) {
		[ringTimer invalidate];
		ringTimer = nil;
	}
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
	  onAccount:(CBPurpleAccount *)account
{
	NSString *sid = controller.machine.sid;
	NSString *name = upcomingDisplayName;
	upcomingDisplayName = nil;

	//A call without an id has nowhere to be filed, and a nil key is an exception
	if (![sid length]) {
		AILogWithSignature(@"call began without a session id; not shown");
		return;
	}

	NSRange slash = [controller.peerFullJid rangeOfString:@"/"];
	NSString *bareJid = (slash.location == NSNotFound ? controller.peerFullJid :
						 [controller.peerFullJid substringToIndex:slash.location]);

	if (![name length])
		name = ([displayNamesBySid[sid] length] ? displayNamesBySid[sid] : bareJid);
	displayNamesBySid[sid] = name;		//kept for as long as the call lasts, for its messages

	windowsBySid[sid] = [[AIJingleCallWindowController alloc] initWithCallController:controller
																		 displayName:name];

	//A note where the conversation lives, when it is open anywhere
	AIListContact *contact = [account contactWithUID:bareJid];
	if (contact) {
		contactsBySid[sid] = contact;
		[self displayCallNote:AILocalizedString(@"Call started", "Chat line noting a call began")
				   forContact:contact];
	}
}

- (void)displayCallNote:(NSString *)note forContact:(AIListContact *)contact
{
	AIChat *chat = [adium.chatController existingChatWithContact:contact];
	if (chat)
		[adium.contentController displayEvent:note ofType:@"jingle-call" inChat:chat];
}

- (void)manager:(AIJingleCallManager *)manager callIsRinging:(AIJingleCallController *)controller
{
	[windowsBySid[controller.machine.sid] noteRinging];
}

- (void)manager:(AIJingleCallManager *)manager callWasAnswered:(AIJingleCallController *)controller
{
	[windowsBySid[controller.machine.sid] noteAnswered];
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
	AIJingleCallWindowController *window = (sid ? windowsBySid[sid] : nil);
	if (sid)
		[windowsBySid removeObjectForKey:sid];

	/* A window that stays readable after the call must stay held, or its own
	 * buttons stop working when the last reference to it goes. */
	if (window) {
		[lingeringWindows addObject:window];
		__weak AIJingleCallUI *weakSelf = self;
		__weak AIJingleCallWindowController *weakWindow = window;
		window.whenClosed = ^{
			AIJingleCallUI *ui = weakSelf;
			AIJingleCallWindowController *finished = weakWindow;
			if (ui && finished)
				[ui->lingeringWindows removeObject:finished];
		};
	}

	//The window knows whether this ending closes it or stays readable
	[window noteEndedWithReason:reason locally:locally];

	/* A call that could not connect is usually a permission nobody was asked for
	 * or that was withdrawn later; ask the machine rather than leaving the person
	 * to guess. */
	if ([reason isEqualToString:@"connectivity-error"]) {
		NSString *peerName = [displayNamesBySid[sid] length] ? displayNamesBySid[sid] : nil;
		[AIJingleCallDiagnostics runWithCompletion:^(NSArray<AIJingleCallFinding *> *findings) {
			NSString *summary = [AIJingleCallDiagnostics summaryOfFindings:findings];
			AILogWithSignature(@"call readiness after a failed call: %@", summary ?: @"nothing amiss");
			if (summary)
				[self showFindings:findings asFailureOfCall:peerName];
		}];
	}

	AIListContact *contact = contactsBySid[sid];
	[contactsBySid removeObjectForKey:sid];
	[displayNamesBySid removeObjectForKey:sid];
	if (contact) {
		NSString *note = ([reason isEqualToString:@"success"] ?
			AILocalizedString(@"Call ended", "State of a finished call") :
			[NSString stringWithFormat:AILocalizedString(@"Call ended (%@)", "Chat line noting a call ended; %@ names the reason"), reason]);
		[self displayCallNote:note forContact:contact];
	}
}

@end
