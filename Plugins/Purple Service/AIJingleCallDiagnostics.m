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

#import "ESPurpleJabberAccount.h"

#import <Adium/AIAccount.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <AVFoundation/AVFoundation.h>
#import <Adium/ESDebugAILog.h>
#import <AIUtilities/AIStringUtilities.h>
#import <Network/Network.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <WebRTC/WebRTC.h>

#define SETTINGS_MICROPHONE	@"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
#define SETTINGS_CAMERA		@"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
#define SETTINGS_NETWORK	@"x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"

#define STUN_SECONDS		6.0
#define BONJOUR_SECONDS		4.0
#define NEIGHBOURS_SECONDS	3.0

@implementation AIJingleCallFinding
@end

@interface AIJingleCallDiagnostics () <RTCPeerConnectionDelegate>
@end

static BOOL hostAndPortOfIceURL(NSString *url, NSString **host, NSString **port);

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
	  [run askTheNeighboursThroughAPlainSocket:^(BOOL weWereAnswered, NSString *neighbourDetail) {
		AIJingleCallFinding *local = [[AIJingleCallFinding alloc] init];
		local.title = AILocalizedString(@"Local network", "Call self test: reaching devices in the same network");
		local.good = weWereAnswered;
		local.fatal = NO;
		local.settingsURL = SETTINGS_NETWORK;

		/* Two answers to one question, and the pair says more than either alone.
		 * The system service found the neighbours while our own socket heard
		 * nothing: they are there, we are the ones not allowed to speak to them.
		 * Silence on both sides is only silence, and saying more than that once
		 * sent somebody into their settings for nothing. */
		if (weWereAnswered) {
			local.detail = AILocalizedString(@"Devices in this network answer Adium directly.",
											 "Call self test: the local network is reachable");
		} else if (sawNeighbours) {
			local.detail = AILocalizedString(@"There are devices in this network, but they do not answer Adium itself. Calls to somebody in the same network then take the long way round or fail; check Adium under Local Network in the privacy settings.",
											 "Call self test: the system sees the network but the application is kept off it");
		} else {
			local.detail = AILocalizedString(@"Nothing in this network answered, which means either that nothing is there to answer or that Adium is being kept off it. Check Adium under Local Network in the privacy settings.",
											 "Call self test: nothing answered at all");
		}
		[findings addObject:local];
		AILogWithSignature(@"local network: browse saw %@, own socket: %@",
						   (sawNeighbours ? @"neighbours" : @"nothing"), neighbourDetail);

		[run askTheWorldThroughAPlainSocket:^(BOOL heard, NSString *detail) {
			AIJingleCallFinding *plain = [[AIJingleCallFinding alloc] init];
			plain.title = AILocalizedString(@"Network for this application",
											"Call self test: whether the application may talk to the network at all");
			plain.good = heard;
			plain.fatal = YES;
			plain.settingsURL = SETTINGS_NETWORK;
			plain.detail = (heard ?
				AILocalizedString(@"Adium reaches the world through a plain connection.",
								  "Call self test: raw UDP works") :
				AILocalizedString(@"Adium cannot reach the world even through a plain connection. The machine is keeping this application off the network.",
								  "Call self test: raw UDP blocked"));
			[findings addObject:plain];
			AILogWithSignature(@"plain socket probe: %@", detail);

		[run askWhatTheAccountsWereTold:^(NSInteger named, NSInteger answering, NSString *hostNames, BOOL sawLivingRelay) {
			if (named) {
				AIJingleCallFinding *announced = [[AIJingleCallFinding alloc] init];
				announced.title = AILocalizedString(@"Helpers named by your server",
													"Call self test: the STUN and TURN servers the XMPP host announces");
				announced.good = (answering > 0);
				announced.fatal = NO;
				announced.detail = (answering > 0 ?
					[NSString stringWithFormat:AILocalizedString(@"%ld of %ld answer.",
																 "Call self test: how many announced helpers answer"),
					 (long)answering, (long)named] :
					[NSString stringWithFormat:AILocalizedString(@"%@ announces %ld, and none of them answers. Adium asks public servers as well, so calls still work, but the operator should hear about it.",
																 "Call self test: the announced helpers are all dead"),
					 hostNames, (long)named]);
				[findings addObject:announced];
			}

			/* A relay of our own, which is the difference between a call that
			 * connects at once and one that waits for the other side to offer a
			 * way in. Worth saying even when everything else is green, because
			 * nothing else on this list goes wrong when it is missing. */
			AIJingleCallFinding *relay = [[AIJingleCallFinding alloc] init];
			relay.title = AILocalizedString(@"Relay for difficult networks",
											"Call self test: whether a TURN server is available to carry the call");
			relay.good = (sawLivingRelay || [run aRelayWasWrittenDownByHand]);
			relay.fatal = NO;
			relay.detail = (relay.good ?
				AILocalizedString(@"A relay is available to carry a call when the direct ways fail.",
								  "Call self test: a working TURN server is known") :
				AILocalizedString(@"None available. When the direct ways between you and the other person carry nothing, this call has to wait for the other side to offer a way in, which costs several seconds and sometimes the whole call. Your server would have to name one that works, or one can be written into AIJingleTURNServers.",
								  "Call self test: no working TURN server anywhere"));
			[findings addObject:relay];

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
		}];
	  }];
	}];
}

static BOOL hostAndPortOfIceURL(NSString *url, NSString **host, NSString **port)
{
	NSRange scheme = [url rangeOfString:@":"];
	if (scheme.location == NSNotFound)
		return NO;

	NSString *rest = [url substringFromIndex:(scheme.location + 1)];
	NSRange query = [rest rangeOfString:@"?"];
	if (query.location != NSNotFound)
		rest = [rest substringToIndex:query.location];

	NSRange colon = [rest rangeOfString:@":" options:NSBackwardsSearch];
	*host = (colon.location == NSNotFound ? rest : [rest substringToIndex:colon.location]);
	*port = (colon.location == NSNotFound ? @"3478" : [rest substringFromIndex:(colon.location + 1)]);

	return [*host length] > 0;
}

/*!
 * @brief The helpers the account's own host announces, and whether they answer
 *
 * A host may name a STUN or TURN server that answers nothing at all, which is
 * exactly what one measured here did, and a call that trusts it alone goes out
 * blind while looking perfectly configured.
 *
 * The two kinds are not worth the same. A STUN server that is dead costs little,
 * because Adium asks public ones as well and any of them will say what address
 * the world sees. A relay that is dead cannot be replaced, because carrying
 * somebody else's call costs money and nobody does it for strangers, and without
 * one this side offers no address that works when the short ways fail. Measured
 * against a phone in the same flat: the direct way carried nothing, this side had
 * no relay because the host announces one that answers nothing, and the call sat
 * silent for nine seconds until the other side's relay was tried. So the relay is
 * named separately, and it is the sentence that matters.
 *
 * A relay only counts as one when it answers AND came with a name and a password,
 * because a relay address without keys is one WebRTC refuses outright.
 */
- (void)askWhatTheAccountsWereTold:(void (^)(NSInteger named, NSInteger answering,
											 NSString *hostNames, BOOL sawLivingRelay))answer
{
	NSMutableArray<NSDictionary *> *announced = [NSMutableArray array];
	NSMutableArray<NSString *> *hosts = [NSMutableArray array];

	for (AIAccount *account in adium.accountController.accounts) {
		if (![account isKindOfClass:[ESPurpleJabberAccount class]] || !account.online)
			continue;

		NSArray *servers = [(ESPurpleJabberAccount *)account jingleIceServers];
		for (NSDictionary *entry in servers)
			if ([entry[@"urls"] length])
				[announced addObject:entry];

		if ([servers count])
			[hosts addObject:account.explicitFormattedUID ?: account.UID];
	}

	if (![announced count]) {
		answer(0, 0, nil, NO);
		return;
	}

	NSInteger named = (NSInteger)[announced count];
	NSString *names = [hosts componentsJoinedByString:@", "];
	__block NSInteger answering = 0;
	__block NSInteger asked = 0;
	__block BOOL sawLivingRelay = NO;

	for (NSDictionary *entry in announced) {
		NSString *url = entry[@"urls"];
		BOOL couldCarry = ([url hasPrefix:@"turn"] &&
						   [entry[@"username"] length] && [entry[@"credential"] length]);

		NSString *host = nil, *port = nil;
		if (!hostAndPortOfIceURL(url, &host, &port)) {
			if (++asked == named)
				answer(named, answering, names, sawLivingRelay);
			continue;
		}

		[AIJingleCallDiagnostics probeStunHost:host port:port detailedCompletion:^(BOOL heard, NSString *detail) {
			if (heard)
				answering++;
			if (heard && couldCarry)
				sawLivingRelay = YES;
			AILogWithSignature(@"server-named helper %@: %@", url, detail);

			if (++asked == named)
				answer(named, answering, names, sawLivingRelay);
		}];
	}
}

/*! @brief Is there a relay somebody wrote down by hand, keys and all? */
- (BOOL)aRelayWasWrittenDownByHand
{
	for (NSDictionary *entry in [[NSUserDefaults standardUserDefaults] arrayForKey:@"AIJingleTURNServers"])
		if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"urls"] length] &&
			[entry[@"username"] length] && [entry[@"credential"] length])
			return YES;

	return NO;
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
	/* Named services, never the meta query: asking for the list of service types
	 * (_services._dns-sd._udp) answers nothing at all through this API, measured,
	 * and would call every household empty. These four are what a home answers. */
	NSArray<NSString *> *types = @[@"_companion-link._tcp", @"_airplay._tcp",
								   @"_raop._tcp", @"_ipp._tcp"];
	NSMutableArray<nw_browser_t> *browsers = [NSMutableArray array];
	__block BOOL answered = NO;
	__block NSInteger seen = 0;

	void (^finish)(void) = ^{
		if (answered)
			return;
		answered = YES;
		for (nw_browser_t browser in browsers)
			nw_browser_cancel(browser);
		answer(seen > 0);
	};

	for (NSString *type in types) {
		nw_browse_descriptor_t descriptor =
			nw_browse_descriptor_create_bonjour_service([type UTF8String], "local");
		nw_parameters_t parameters = nw_parameters_create_secure_udp(NW_PARAMETERS_DISABLE_PROTOCOL,
																	 NW_PARAMETERS_DEFAULT_CONFIGURATION);
		nw_browser_t browser = nw_browser_create(descriptor, parameters);

		nw_browser_set_queue(browser, dispatch_get_main_queue());
		nw_browser_set_browse_results_changed_handler(browser, ^(nw_browse_result_t old, nw_browse_result_t new, bool complete) {
			if (new)
				seen++;
		});
		nw_browser_start(browser);
		[browsers addObject:browser];
	}

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BONJOUR_SECONDS * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), finish);
}

/*!
 * @brief Do the neighbours answer this application's own packets?
 *
 * The browse above is carried out by a system service, which holds a permission
 * of its own and answers happily while ours is refused. That gap is exactly
 * where a call loses the short way home: two people in one flat, one router
 * between them, and every picture travelling through a relay somewhere in the
 * country. So the question is asked a second time through a socket of our own,
 * as the multicast query every household answers. Replies from this machine are
 * thrown away; a packet that never left the building proves nothing.
 */
- (void)askTheNeighboursThroughAPlainSocket:(void (^)(BOOL answered, NSString *detail))answer
{
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		//Which addresses are ours, so that our own answer does not count as a neighbour
		NSMutableSet<NSString *> *ourOwn = [NSMutableSet set];
		struct ifaddrs *interfaces = NULL;
		if (getifaddrs(&interfaces) == 0) {
			for (struct ifaddrs *each = interfaces; each; each = each->ifa_next) {
				if (each->ifa_addr && each->ifa_addr->sa_family == AF_INET) {
					char text[INET_ADDRSTRLEN] = {0};
					inet_ntop(AF_INET, &((struct sockaddr_in *)each->ifa_addr)->sin_addr,
							  text, sizeof(text));
					[ourOwn addObject:[NSString stringWithUTF8String:text]];
				}
			}
			freeifaddrs(interfaces);
		}

		//Which services are there? The question mDNS was made for
		static const uint8_t question[] = {
			0x00, 0x00,				//no id; this is not a conversation
			0x00, 0x00,				//a plain question
			0x00, 0x01,				//one of them
			0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
			9, '_','s','e','r','v','i','c','e','s',
			7, '_','d','n','s','-','s','d',
			4, '_','u','d','p',
			5, 'l','o','c','a','l',
			0,
			0x00, 0x0C,				//PTR
			0x80, 0x01				//and answer straight back to this socket
		};

		int socketDescriptor = socket(AF_INET, SOCK_DGRAM, 0);
		uint8_t hops = 255;			//what mDNS asks for
		setsockopt(socketDescriptor, IPPROTO_IP, IP_MULTICAST_TTL, &hops, sizeof(hops));
		struct timeval patience = { .tv_usec = 500000 };
		setsockopt(socketDescriptor, SOL_SOCKET, SO_RCVTIMEO, &patience, sizeof(patience));

		struct sockaddr_in everyone = { .sin_family = AF_INET, .sin_port = htons(5353) };
		inet_pton(AF_INET, "224.0.0.251", &everyone.sin_addr);

		BOOL heard = NO;
		NSString *detail = nil;

		if (sendto(socketDescriptor, question, sizeof(question), 0,
				   (struct sockaddr *)&everyone, sizeof(everyone)) != (ssize_t)sizeof(question)) {
			detail = [NSString stringWithFormat:@"sending failed (%s)", strerror(errno)];
		} else {
			NSDate *until = [NSDate dateWithTimeIntervalSinceNow:NEIGHBOURS_SECONDS];
			NSString *who = nil;

			while (!heard && [until timeIntervalSinceNow] > 0) {
				uint8_t reply[2048];
				struct sockaddr_in from = {0};
				socklen_t fromLength = sizeof(from);
				ssize_t received = recvfrom(socketDescriptor, reply, sizeof(reply), 0,
											(struct sockaddr *)&from, &fromLength);
				if (received <= 0)
					continue;

				char text[INET_ADDRSTRLEN] = {0};
				inet_ntop(AF_INET, &from.sin_addr, text, sizeof(text));
				NSString *sender = [NSString stringWithUTF8String:text];
				if ([ourOwn containsObject:sender])
					continue;			//ourselves, talking back

				heard = YES;
				who = sender;
			}
			detail = (heard ?
					  [NSString stringWithFormat:@"%@ answered our own socket", who] :
					  @"nobody answered our own socket");
		}

		close(socketDescriptor);
		dispatch_async(dispatch_get_main_queue(), ^{
			answer(heard, detail);
		});
	});
}

/*!
 * @brief Can this application talk UDP to the world at all, WebRTC aside?
 *
 * A STUN binding request written by hand and sent through a plain socket. It
 * answers the one question that decides where to look next: an application that
 * cannot do this is being kept off the network by the machine, while one that
 * can, and still has calls that reach nobody, is failing somewhere in its own
 * media stack.
 */
- (void)askTheWorldThroughAPlainSocket:(void (^)(BOOL answered, NSString *detail))answer
{
	[AIJingleCallDiagnostics probeStunHost:@"stun.l.google.com" port:@"19302" detailedCompletion:answer];
}

/*!
 * @brief Send one STUN question by hand and see whether anything answers
 *
 * The smallest question a call asks, asked without WebRTC in the way, so a
 * server that is named but dead can be told from one that was never named.
 */
+ (void)probeStunHost:(NSString *)host port:(NSString *)port completion:(void (^)(BOOL answered))completion
{
	[self probeStunHost:host port:port detailedCompletion:^(BOOL answered, NSString *detail) {
		completion(answered);
	}];
}

+ (BOOL)host:(NSString **)host port:(NSString **)port ofIceURL:(NSString *)url
{
	return hostAndPortOfIceURL(url, host, port);
}

+ (void)probeStunHost:(NSString *)host port:(NSString *)port detailedCompletion:(void (^)(BOOL answered, NSString *detail))answer
{
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		struct addrinfo hints = { .ai_family = AF_INET, .ai_socktype = SOCK_DGRAM };
		struct addrinfo *found = NULL;

		if (getaddrinfo([host UTF8String], [port UTF8String], &hints, &found) != 0 || !found) {
			dispatch_async(dispatch_get_main_queue(), ^{
				answer(NO, @"name could not be looked up");
			});
			return;
		}

		int socketDescriptor = socket(AF_INET, SOCK_DGRAM, 0);
		struct timeval timeout = { .tv_sec = 4 };
		setsockopt(socketDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

		//A binding request: type 0x0001, no attributes, the magic cookie and a transaction id
		uint8_t binding[20] = { 0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42 };

		/* And the question a relay answers even when it answers nothing else.
		 *
		 * TRAP, and it cost a relay: a server built to carry calls and nothing
		 * else may ignore a binding request altogether, because binding is the
		 * STUN half of its job and it was told not to do that half. Ask it to
		 * carry something instead and it says no, loudly, with a realm attached,
		 * and a refusal is proof of life. Silence on both questions is death.
		 * An allocate request: type 0x0003, with the one attribute it insists on,
		 * REQUESTED-TRANSPORT 0x0019 naming UDP, which is protocol number 17. */
		uint8_t allocate[28] = { 0x00, 0x03, 0x00, 0x08, 0x21, 0x12, 0xA4, 0x42 };
		memcpy(allocate + 20, (uint8_t[]){ 0x00, 0x19, 0x00, 0x04, 17, 0x00, 0x00, 0x00 }, 8);

		for (int index = 8; index < 20; index++)
			binding[index] = allocate[index] = (uint8_t)arc4random_uniform(256);
		allocate[19] ^= 0xFF;			//two questions, two conversations

		ssize_t sent = sendto(socketDescriptor, binding, sizeof(binding), 0,
							  found->ai_addr, found->ai_addrlen);
		if (sent == (ssize_t)sizeof(binding))
			sendto(socketDescriptor, allocate, sizeof(allocate), 0, found->ai_addr, found->ai_addrlen);

		NSString *detail = nil;
		BOOL heard = NO;

		if (sent != (ssize_t)sizeof(binding)) {
			detail = [NSString stringWithFormat:@"sending failed (%s)", strerror(errno)];
		} else {
			uint8_t reply[512];
			ssize_t received = recv(socketDescriptor, reply, sizeof(reply), 0);

			//Anything wearing the magic cookie came from a server that is there
			BOOL isStun = (received >= 20 &&
						   reply[4] == 0x21 && reply[5] == 0x12 && reply[6] == 0xA4 && reply[7] == 0x42);

			if (isStun && reply[0] == 0x01 && reply[1] == 0x01) {
				heard = YES;
				detail = @"it answers with an address";
			} else if (isStun) {
				heard = YES;
				detail = [NSString stringWithFormat:@"it refuses, so it is there (0x%02x%02x)",
						  reply[0], reply[1]];
			} else if (received < 0) {
				detail = [NSString stringWithFormat:@"nothing came back (%s)", strerror(errno)];
			} else {
				detail = @"something came back, but nothing a call would recognise";
			}
		}

		close(socketDescriptor);
		freeaddrinfo(found);

		dispatch_async(dispatch_get_main_queue(), ^{
			answer(heard, detail);
		});
	});
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
