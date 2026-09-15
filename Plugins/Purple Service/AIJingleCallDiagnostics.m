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

#import "AIJingleCallDiagnostics.h"

#import <AVFoundation/AVFoundation.h>
#import <Adium/ESDebugAILog.h>
#import <AIUtilities/AIStringUtilities.h>
#import <Network/Network.h>
#import <WebRTC/WebRTC.h>

#define SETTINGS_MICROPHONE	@"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
#define SETTINGS_CAMERA		@"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
#define SETTINGS_NETWORK	@"x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"

#define STUN_SECONDS		6.0
#define BONJOUR_SECONDS		4.0

@implementation AIJingleCallFinding
@end

@interface AIJingleCallDiagnostics () <RTCPeerConnectionDelegate>
@end

@implementation AIJingleCallDiagnostics {
	RTCPeerConnection *probeConnection;
	void (^whenGathered)(BOOL sawPublicAddress);
	BOOL sawPublicAddress;
	BOOL gatheringAnswered;
}

+ (void)runWithCompletion:(void (^)(NSArray<AIJingleCallFinding *> *))completion
{
	AIJingleCallDiagnostics *run = [[AIJingleCallDiagnostics alloc] init];
	NSMutableArray<AIJingleCallFinding *> *findings = [NSMutableArray array];

	[findings addObject:[self findingForMedia:AVMediaTypeAudio
										title:AILocalizedString(@"Microphone", "Call self test: the microphone permission")
								   settingsURL:SETTINGS_MICROPHONE
										 fatal:YES]];
	[findings addObject:[self findingForMedia:AVMediaTypeVideo
										title:AILocalizedString(@"Camera", "Call self test: the camera permission")
								   settingsURL:SETTINGS_CAMERA
										 fatal:NO]];

	//The two network questions answer themselves by really talking
	[run browseTheNeighbourhood:^(BOOL sawNeighbours) {
		AIJingleCallFinding *local = [[AIJingleCallFinding alloc] init];
		local.title = AILocalizedString(@"Local network", "Call self test: reaching devices in the same network");
		local.good = sawNeighbours;
		local.fatal = NO;
		local.settingsURL = SETTINGS_NETWORK;
		local.detail = (sawNeighbours ?
			AILocalizedString(@"Devices in this network answer.",
							  "Call self test: the local network is reachable") :
			AILocalizedString(@"Nothing in this network answered. Calls to somebody on the same network need this; check Adium under Local Network in the privacy settings.",
							  "Call self test: the local network appears blocked"));
		[findings addObject:local];

		[run askTheWorldForOurAddress:^(BOOL sawAddress) {
			AIJingleCallFinding *public = [[AIJingleCallFinding alloc] init];
			public.title = AILocalizedString(@"Public address", "Call self test: learning the address the world sees");
			public.good = sawAddress;
			public.fatal = YES;
			public.settingsURL = SETTINGS_NETWORK;
			public.detail = (sawAddress ?
				AILocalizedString(@"A STUN server answered with the address the world sees.",
								  "Call self test: STUN worked") :
				AILocalizedString(@"No STUN server answered. Without the address the world sees, nobody outside this network can be called at all. Something is keeping Adium's calls off the network.",
								  "Call self test: STUN got no answer"));
			[findings addObject:public];

			dispatch_async(dispatch_get_main_queue(), ^{
				completion(findings);
			});
		}];
	}];
}

+ (AIJingleCallFinding *)findingForMedia:(AVMediaType)media
								   title:(NSString *)title
							 settingsURL:(NSString *)settingsURL
								   fatal:(BOOL)fatal
{
	AIJingleCallFinding *finding = [[AIJingleCallFinding alloc] init];
	finding.title = title;
	finding.settingsURL = settingsURL;
	finding.fatal = fatal;

	switch ([AVCaptureDevice authorizationStatusForMediaType:media]) {
		case AVAuthorizationStatusAuthorized:
			finding.good = YES;
			finding.detail = AILocalizedString(@"Allowed.", "Call self test: a permission is granted");
			break;
		case AVAuthorizationStatusNotDetermined:
			finding.good = YES;
			finding.detail = AILocalizedString(@"Not asked for yet; macOS will ask at the first call.",
											   "Call self test: a permission nobody has been asked for");
			break;
		case AVAuthorizationStatusDenied:
			finding.detail = AILocalizedString(@"Refused. Calls stay silent until this is allowed.",
											   "Call self test: a permission was refused");
			break;
		case AVAuthorizationStatusRestricted:
			finding.detail = AILocalizedString(@"Not available on this machine.",
											   "Call self test: a permission is administratively unavailable");
			break;
	}

	return finding;
}

//Talking to the neighbours ----------------------------------------------------------------------
#pragma mark Talking to the neighbours

/*!
 * @brief Does anything in this network answer?
 *
 * Bonjour is the one conversation every household has: printers, speakers,
 * televisions and other computers all answer it. An application that macOS
 * keeps off the local network hears nothing at all, and asking is also what
 * makes macOS put its question, so a permission nobody was ever asked for
 * gets asked for here.
 */
- (void)browseTheNeighbourhood:(void (^)(BOOL sawNeighbours))answer
{
	nw_browse_descriptor_t descriptor = nw_browse_descriptor_create_bonjour_service("_services._dns-sd._udp", "local");
	nw_parameters_t parameters = nw_parameters_create_secure_udp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
	nw_browser_t browser = nw_browser_create(descriptor, parameters);

	__block BOOL answered = NO;
	__block BOOL sawSomething = NO;
	void (^finish)(void) = ^{
		if (answered)
			return;
		answered = YES;
		nw_browser_cancel(browser);
		answer(sawSomething);
	};

	nw_browser_set_queue(browser, dispatch_get_main_queue());
	nw_browser_set_browse_results_changed_handler(browser, ^(nw_browse_result_t old, nw_browse_result_t new, bool complete) {
		if (new)
			sawSomething = YES;
	});
	nw_browser_start(browser);

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BONJOUR_SECONDS * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), finish);
}

//Asking the world -------------------------------------------------------------------------------
#pragma mark Asking the world

/*!
 * @brief Does a STUN server answer with the address the world sees?
 *
 * The same question every call asks before it can be reached from outside, and
 * the same machinery: a connection that gathers candidates. An address of type
 * srflx among them means the question was heard and answered.
 */
- (void)askTheWorldForOurAddress:(void (^)(BOOL sawAddress))answer
{
	whenGathered = [answer copy];

	RTCPeerConnectionFactory *factory = [[RTCPeerConnectionFactory alloc] init];
	RTCConfiguration *configuration = [[RTCConfiguration alloc] init];
	configuration.sdpSemantics = RTCSdpSemanticsUnifiedPlan;

	NSArray *servers = [[NSUserDefaults standardUserDefaults] arrayForKey:@"AIJingleSTUNServers"];
	if (![servers count])
		servers = @[@"stun:stun.conversations.im:3478", @"stun:stun.l.google.com:19302"];

	NSMutableArray<RTCIceServer *> *iceServers = [NSMutableArray array];
	for (NSString *url in servers)
		[iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:@[url]]];
	configuration.iceServers = iceServers;

	RTCMediaConstraints *none = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@{}
																	  optionalConstraints:@{}];
	probeConnection = [factory peerConnectionWithConfiguration:configuration constraints:none delegate:self];

	/* A connection with nothing to send gathers nothing; a data channel is the
	 * cheapest thing to have, and needs no microphone. */
	[probeConnection dataChannelForLabel:@"probe" configuration:[[RTCDataChannelConfiguration alloc] init]];
	[probeConnection offerForConstraints:none completionHandler:^(RTCSessionDescription *offer, NSError *error) {
		if (offer)
			[self->probeConnection setLocalDescription:offer completionHandler:^(NSError *e) {}];
	}];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(STUN_SECONDS * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[self finishGathering];
	});
}

- (void)finishGathering
{
	if (gatheringAnswered)
		return;
	gatheringAnswered = YES;

	[probeConnection close];
	probeConnection = nil;

	void (^answer)(BOOL) = whenGathered;
	whenGathered = nil;
	if (answer)
		answer(sawPublicAddress);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
	if ([candidate.sdp containsString:@" typ srflx"]) {
		sawPublicAddress = YES;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self finishGathering];		//one answer is all the question needed
		});
	}
}

//Required by the protocol, nothing to do
- (void)peerConnection:(RTCPeerConnection *)pc didChangeSignalingState:(RTCSignalingState)stateChanged {}
- (void)peerConnection:(RTCPeerConnection *)pc didAddStream:(RTCMediaStream *)stream {}
- (void)peerConnection:(RTCPeerConnection *)pc didRemoveStream:(RTCMediaStream *)stream {}
- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)pc {}
- (void)peerConnection:(RTCPeerConnection *)pc didChangeIceConnectionState:(RTCIceConnectionState)newState {}
- (void)peerConnection:(RTCPeerConnection *)pc didChangeIceGatheringState:(RTCIceGatheringState)newState {}
- (void)peerConnection:(RTCPeerConnection *)pc didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates {}
- (void)peerConnection:(RTCPeerConnection *)pc didOpenDataChannel:(RTCDataChannel *)dataChannel {}

//Saying it ---------------------------------------------------------------------------------------
#pragma mark Saying it

+ (NSString *)summaryOfFindings:(NSArray<AIJingleCallFinding *> *)findings
{
	NSMutableArray *broken = [NSMutableArray array];

	for (AIJingleCallFinding *finding in findings)
		if (!finding.good)
			[broken addObject:finding.title];

	if (![broken count])
		return nil;

	return [NSString stringWithFormat:AILocalizedString(@"Calls are being kept from: %@",
														"Summary of a failed call self test; %@ lists what is refused"),
			[broken componentsJoinedByString:@", "]];
}

@end
