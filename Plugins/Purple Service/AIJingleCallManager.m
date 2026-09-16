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

#import "AIJingleCallManager.h"

#import "ESPurpleJabberAccount.h"

#import <Adium/AIListContact.h>
#import <libpurple/jabber.h>

/*! @brief A ringing call nobody answered yet: everything needed to take it or turn it away */
@interface AIJinglePendingCall : NSObject
@property (nonatomic, copy) NSString *jingleXML;
@property (nonatomic, copy) NSString *fromJid;
@property (nonatomic, strong) CBPurpleAccount *account;
@property (nonatomic) BOOL offersVideo;
@end
@implementation AIJinglePendingCall
@end

/*! @brief A call of ours that is still ringing over there (XEP-0353), before any session exists */
@interface AIJingleOutgoingProposal : NSObject
@property (nonatomic, copy) NSString *bareJid;
@property (nonatomic) BOOL video;
@property (nonatomic, strong) NSTimer *fallbackTimer;
@end
@implementation AIJingleOutgoingProposal
@end

@implementation AIJingleCallManager {
	NSMutableDictionary<NSString *, AIJingleCallController *> *controllersBySid;
	NSMutableDictionary<NSString *, CBPurpleAccount *> *accountsBySid;
	NSMutableDictionary<NSString *, AIJinglePendingCall *> *pendingBySid;
	NSMutableDictionary<NSString *, AIJingleOutgoingProposal *> *proposalsOutBySid;
	NSMutableDictionary<NSString *, AIJinglePendingCall *> *proposalsInBySid;
	NSMutableDictionary<NSString *, NSNumber *> *awaitingInitiateBySid;	//accepted rings: the camera choice
}

+ (AIJingleCallManager *)sharedManager
{
	static AIJingleCallManager *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [[AIJingleCallManager alloc] init];
	});
	return shared;
}

+ (void)install
{
	adiumPurpleJingleSetHandler([self sharedManager]);
}

- (id)init
{
	if ((self = [super init])) {
		controllersBySid = [NSMutableDictionary dictionary];
		accountsBySid = [NSMutableDictionary dictionary];
		pendingBySid = [NSMutableDictionary dictionary];
		proposalsOutBySid = [NSMutableDictionary dictionary];
		proposalsInBySid = [NSMutableDictionary dictionary];
		awaitingInitiateBySid = [NSMutableDictionary dictionary];
	}
	return self;
}

/*!
 * @brief The sid a jingle element names, and whether it offers video
 *
 * Read as XML, never searched as text: a stanza off the wire spells its
 * attributes with single quotes, and a search for sid=" found nothing in
 * everything a peer ever sent, which left libpurple's own blind jingle code
 * to answer every incoming call with unsupported-applications.
 */
static NSXMLElement *jingleElement(NSString *jingleXML)
{
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:jingleXML options:0 error:NULL];
	NSXMLElement *root = [document rootElement];

	return ([[root name] isEqualToString:@"jingle"] ? root : nil);
}

static NSString *sidOfElement(NSString *jingleXML)
{
	return [[jingleElement(jingleXML) attributeForName:@"sid"] stringValue];
}

static BOOL elementOffersVideo(NSString *jingleXML)
{
	for (NSXMLElement *content in [jingleElement(jingleXML) elementsForName:@"content"]) {
		for (NSXMLElement *description in [content elementsForName:@"description"]) {
			if ([[[description attributeForName:@"media"] stringValue] isEqualToString:@"video"])
				return YES;
		}
	}
	return NO;
}

- (NSString *)localJidForAccount:(CBPurpleAccount *)account
{
	PurpleAccount *purpleAccount = accountLookupFromAdiumAccount(account);
	const char *username = (purpleAccount ? purple_account_get_username(purpleAccount) : NULL);
	return (username ? [NSString stringWithUTF8String:username] : @"");
}

//The stream's questions -------------------------------------------------------------------------
#pragma mark The stream's questions

- (BOOL)handleJingleElement:(NSString *)jingleXML
					   from:(NSString *)fromJid
					 action:(NSString *)action
				  onAccount:(CBPurpleAccount *)account
{
	NSString *sid = sidOfElement(jingleXML);
	if (![sid length])
		return NO;

	AIJingleCallController *controller = controllersBySid[sid];
	if (controller) {
		[controller handleRemoteJingleElement:jingleXML];
		return YES;
	}

	//A caller may withdraw while we are still ringing
	AIJinglePendingCall *pending = pendingBySid[sid];
	if (pending) {
		if ([action isEqualToString:@"session-terminate"]) {
			[pendingBySid removeObjectForKey:sid];
			[self.uiDelegate manager:self incomingCallWithdrawn:sid];
		}
		return YES;
	}

	//A ring that was answered: the initiate we told the caller to send
	NSNumber *cameraChoice = awaitingInitiateBySid[sid];
	if (cameraChoice && [action isEqualToString:@"session-initiate"]) {
		[awaitingInitiateBySid removeObjectForKey:sid];
		[self beginIncomingCallWithSid:sid jingleXML:jingleXML from:fromJid
							 onAccount:account withVideo:[cameraChoice boolValue]];
		return YES;
	}

	if ([action isEqualToString:@"session-initiate"]) {
		/* The debug switch takes the call at once; otherwise the interface rings.
		 * With neither around, the stanza stays untouched and the protocol answers
		 * service-unavailable, exactly as before any of this was built. */
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"AIJingleAutoAcceptCalls"]) {
			AILog(@"Jingle: auto-accepting incoming call %@ from %@", sid, fromJid);
			[self beginIncomingCallWithSid:sid jingleXML:jingleXML from:fromJid
								 onAccount:account withVideo:NO];
			return YES;
		}

		if (self.uiDelegate) {
			AIJinglePendingCall *ringing = [[AIJinglePendingCall alloc] init];
			ringing.jingleXML = jingleXML;
			ringing.fromJid = fromJid;
			ringing.account = account;
			pendingBySid[sid] = ringing;

			[self.uiDelegate manager:self
	   promptForIncomingCallWithSid:sid
								from:fromJid
						   onAccount:account
						 offersVideo:elementOffersVideo(jingleXML)];
			return YES;
		}
	}

	return NO;
}

//The ringing language ---------------------------------------------------------------------------
#pragma mark The ringing language

- (BOOL)handleJingleMessageOfKind:(NSString *)kind
							  sid:(NSString *)sid
							 from:(NSString *)fromJid
					  offersVideo:(BOOL)offersVideo
						onAccount:(CBPurpleAccount *)account
{
	//Answers to our own ring
	AIJingleOutgoingProposal *proposal = proposalsOutBySid[sid];
	if (proposal) {
		AIJingleCallController *controller = controllersBySid[sid];

		if ([kind isEqualToString:@"ringing"]) {
			/* It really rings over there, so the peer speaks this language: the direct
			 * fallback would only interrupt somebody reaching for their phone. */
			[proposal.fallbackTimer invalidate];
			proposal.fallbackTimer = nil;
			[self.uiDelegate manager:self callIsRinging:controller];
			return YES;
		}
		if ([kind isEqualToString:@"proceed"] && controller) {
			//Whoever answered is whom the session now belongs to
			[proposal.fallbackTimer invalidate];
			[proposalsOutBySid removeObjectForKey:sid];
			controller.peerFullJid = fromJid;
			[self.uiDelegate manager:self callWasAnswered:controller];
			[controller start];
			return YES;
		}
		if ([kind isEqualToString:@"reject"]) {
			[proposal.fallbackTimer invalidate];
			[proposalsOutBySid removeObjectForKey:sid];
			[controller.machine abandonWithReason:@"decline" locally:NO];
			return YES;
		}
		return NO;
	}

	//A ring for us
	if ([kind isEqualToString:@"propose"] &&
		!proposalsInBySid[sid] && !controllersBySid[sid] && !pendingBySid[sid]) {
		AIJinglePendingCall *ringing = [[AIJinglePendingCall alloc] init];
		ringing.fromJid = fromJid;
		ringing.account = account;
		ringing.offersVideo = offersVideo;
		proposalsInBySid[sid] = ringing;

		if (!self.uiDelegate && [[NSUserDefaults standardUserDefaults] boolForKey:@"AIJingleAutoAcceptCalls"]) {
			[self acceptIncomingCallWithSid:sid withVideo:NO];
			return YES;
		}

		[self.uiDelegate manager:self
   promptForIncomingCallWithSid:sid
							from:fromJid
					   onAccount:account
					 offersVideo:offersVideo];

		//Tell the caller it really rings here, so their window can say so
		adiumPurpleJingleSendMessage(account, fromJid, @"ringing", sid, NO, NO);
		return YES;
	}

	//A ring that stopped: the caller gave up, or one of our other devices took or refused it
	if (proposalsInBySid[sid] &&
		([kind isEqualToString:@"retract"] || [kind isEqualToString:@"accept"] ||
		 [kind isEqualToString:@"reject"] || [kind isEqualToString:@"proceed"])) {
		[proposalsInBySid removeObjectForKey:sid];
		[self.uiDelegate manager:self incomingCallWithdrawn:sid];
		return YES;
	}

	return NO;
}

- (AIJingleCallController *)beginIncomingCallWithSid:(NSString *)sid
										   jingleXML:(NSString *)jingleXML
												from:(NSString *)fromJid
										   onAccount:(CBPurpleAccount *)account
										   withVideo:(BOOL)withVideo
{
	AIJingleCallController *incoming =
		[[AIJingleCallController alloc] initAsResponderFrom:[self localJidForAccount:account]
														 to:fromJid
														sid:sid];
	incoming.peerFullJid = fromJid;
	incoming.wantsVideo = withVideo;
	incoming.delegate = self;

	if ([account isKindOfClass:[ESPurpleJabberAccount class]])
		incoming.iceServerDictionaries = [(ESPurpleJabberAccount *)account jingleIceServers];

	controllersBySid[sid] = incoming;
	accountsBySid[sid] = account;

	[self.uiDelegate manager:self callBegan:incoming onAccount:account];
	[incoming handleRemoteJingleElement:jingleXML];
	return incoming;
}

- (AIJingleCallController *)acceptIncomingCallWithSid:(NSString *)sid withVideo:(BOOL)withVideo
{
	/* A ring that arrived as a proposal has no session yet: the answer is a proceed,
	 * and the session-initiate follows from the caller within moments. */
	AIJinglePendingCall *ringing = proposalsInBySid[sid];
	if (ringing) {
		[proposalsInBySid removeObjectForKey:sid];
		awaitingInitiateBySid[sid] = @(withVideo);
		adiumPurpleJingleSendMessage(ringing.account, ringing.fromJid, @"proceed", sid, NO, NO);
		return nil;
	}

	AIJinglePendingCall *pending = pendingBySid[sid];
	if (!pending)
		return nil;

	[pendingBySid removeObjectForKey:sid];
	return [self beginIncomingCallWithSid:sid jingleXML:pending.jingleXML from:pending.fromJid
								onAccount:pending.account withVideo:withVideo];
}

- (void)declineIncomingCallWithSid:(NSString *)sid
{
	AIJinglePendingCall *ringing = proposalsInBySid[sid];
	if (ringing) {
		[proposalsInBySid removeObjectForKey:sid];
		adiumPurpleJingleSendMessage(ringing.account, ringing.fromJid, @"reject", sid, NO, NO);
		return;
	}

	AIJinglePendingCall *pending = pendingBySid[sid];
	if (!pending)
		return;

	[pendingBySid removeObjectForKey:sid];

	//The initiate was ACKed already; the refusal is a session-terminate of its own
	NSMutableString *safeSid = [sid mutableCopy];
	[safeSid replaceOccurrencesOfString:@"&" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange(0, [safeSid length])];
	[safeSid replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange(0, [safeSid length])];
	[safeSid replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:NSLiteralSearch range:NSMakeRange(0, [safeSid length])];
	NSString *terminate = [NSString stringWithFormat:
		@"<jingle xmlns=\"urn:xmpp:jingle:1\" action=\"session-terminate\" sid=\"%@\">"
		@"<reason><decline/></reason></jingle>", safeSid];

	adiumPurpleJingleSendElement(pending.account, pending.fromJid, terminate);
}

//Starting ---------------------------------------------------------------------------------------
#pragma mark Starting

- (AIJingleCallController *)startCallToJid:(NSString *)peerJid
								 onAccount:(CBPurpleAccount *)account
								 withVideo:(BOOL)withVideo
{
	AIJingleCallController *controller =
		[[AIJingleCallController alloc] initAsInitiatorFrom:[self localJidForAccount:account]
														 to:peerJid];
	controller.peerFullJid = peerJid;
	controller.wantsVideo = withVideo;
	controller.delegate = self;

	if ([account isKindOfClass:[ESPurpleJabberAccount class]])
		controller.iceServerDictionaries = [(ESPurpleJabberAccount *)account jingleIceServers];

	NSString *sid = controller.machine.sid;
	controllersBySid[sid] = controller;
	accountsBySid[sid] = account;

	[self.uiDelegate manager:self callBegan:controller onAccount:account];

	/* Start looking for addresses now, not when they pick up. Everything a call
	 * needs from the network, the public address and the sign-in at a relay, takes
	 * a few hundred milliseconds that may as well be spent while it rings. */
	[controller prepare];

	/* Ring first (XEP-0353): the proposal goes to every device behind the bare JID,
	 * and whoever answers with a proceed is whom the session then belongs to. A peer
	 * that never says anything gets the session offered directly after a while, for
	 * the clients that never learned the ringing language.
	 *
	 * Unless it has already told us it never learned it. Then the wait is ten
	 * seconds of nothing for a question we know the answer to, and the session goes
	 * out straight away instead. And where nobody has told us anything, the wait is
	 * shorter rather than long: a client that speaks this language answers with a
	 * ringing at once, ours within a tenth of a second.
	 *
	 * Five seconds and not two, because the two mistakes cost very different
	 * things. Waiting too long is invisible, our own window says it is calling
	 * anyway. Giving up too early withdraws a ring that was already sounding on
	 * somebody's phone and rings again on one device instead of all of them, and a
	 * phone whose radio was asleep can easily take a second or two to answer. Note
	 * also that not knowing can be permanent: a resource whose abilities could not
	 * be fetched stays unknown for as long as it is signed in, so this is not a
	 * rare case to be optimised for. */
	NSRange slash = [peerJid rangeOfString:@"/"];
	NSString *bareJid = (slash.location == NSNotFound ? peerJid : [peerJid substringToIndex:slash.location]);
	AIListContact *contact = [account contactWithUID:bareJid];

	if (contact && [self contact:contact isKnownUnableTo:NS_JINGLE_MESSAGE]) {
		AILog(@"Jingle: %@ cannot be rung the modern way, offering the session directly", bareJid);
		NSString *fullJid = [self fullJidForContact:contact] ?: peerJid;
		controller.peerFullJid = fullJid;
		[controller start];
		return controller;
	}

	AIJingleOutgoingProposal *proposal = [[AIJingleOutgoingProposal alloc] init];
	proposal.bareJid = bareJid;
	proposal.video = withVideo;

	BOOL knownToRing = (contact && ![self contact:contact isKnownUnableTo:NS_JINGLE_MESSAGE] &&
						[self resourceOfContact:contact ableTo:NS_JINGLE_MESSAGE] != NULL);
	proposal.fallbackTimer = [NSTimer scheduledTimerWithTimeInterval:(knownToRing ? 10.0 : 5.0)
															  target:self
															selector:@selector(proposalWentUnanswered:)
															userInfo:sid
															 repeats:NO];
	proposalsOutBySid[sid] = proposal;

	adiumPurpleJingleSendMessage(account, proposal.bareJid, @"propose", sid, YES, withVideo);
	return controller;
}

/*!
 * @brief Nobody spoke the ringing language; offer the session directly
 *
 * The proposal is withdrawn first, so a device that did ring quietly stops, and
 * the session-initiate then goes to the contact's best resource the old way.
 */
- (void)proposalWentUnanswered:(NSTimer *)timer
{
	NSString *sid = [timer userInfo];
	AIJingleOutgoingProposal *proposal = proposalsOutBySid[sid];
	AIJingleCallController *controller = controllersBySid[sid];
	CBPurpleAccount *account = accountsBySid[sid];

	if (!proposal || !controller || !account)
		return;

	[proposalsOutBySid removeObjectForKey:sid];
	adiumPurpleJingleSendMessage(account, proposal.bareJid, @"retract", sid, NO, NO);

	AIListContact *contact = [account contactWithUID:proposal.bareJid];
	NSString *fullJid = (contact ? [self jidToCallForContact:contact withVideo:proposal.video] : nil);

	if (![fullJid length]) {
		[controller.machine abandonWithReason:@"connectivity-error" locally:YES];
		return;
	}

	controller.peerFullJid = fullJid;
	[controller start];
}

/*!
 * @brief The full JID of a contact's best resource
 *
 * A Jingle session lives between two full JIDs. The protocol keeps every resource
 * it has seen presence from; the one it would deliver a message to, its first, is
 * the one worth calling. Nil while nobody is signed in there.
 */
- (NSString *)fullJidForContact:(AIListContact *)contact
{
	JabberBuddyResource *jbr = [self resourceOfContact:contact ableTo:NULL];

	if (!jbr || !jbr->name || !*jbr->name)
		return nil;

	return [NSString stringWithFormat:@"%@/%s", contact.UID, jbr->name];
}

/*!
 * @brief Which of a contact's devices to ring directly
 *
 * The one a message would go to, unless this is a call with pictures and that one
 * has said it has no use for them while another device has. A phone held high in
 * the priority list wins every message and would otherwise also win the video
 * call that the desktop next to it could actually take.
 */
- (NSString *)jidToCallForContact:(AIListContact *)contact withVideo:(BOOL)withVideo
{
	JabberBuddyResource *jbr = NULL;

	if (withVideo) {
		jbr = [self resourceOfContact:contact ableTo:NS_JINGLE_VIDEO];
		if (jbr)
			AILog(@"Jingle: calling %@/%s, the device that says it can do pictures",
				  contact.UID, jbr->name);
	}
	if (!jbr)
		jbr = [self resourceOfContact:contact ableTo:NULL];

	if (!jbr || !jbr->name || !*jbr->name)
		return nil;

	return [NSString stringWithFormat:@"%@/%s", contact.UID, jbr->name];
}

//What the other side can ------------------------------------------------------------------------
#pragma mark What the other side can

/*!
 * @brief The best resource of a contact, optionally one that can a given thing
 *
 * The resource list is already sorted by how good a target each one is, so the
 * first that fits is the best that fits. A contact whose phone answers messages
 * first but whose desktop is the one with a camera would otherwise lose the video
 * call it could perfectly well have.
 *
 * Asking for nothing (NULL) gives the head of the list, which is where a message
 * would go.
 */
- (JabberBuddyResource *)resourceOfContact:(AIListContact *)contact ableTo:(const char *)capability
{
	CBPurpleAccount *adiumAccount = (CBPurpleAccount *)contact.account;
	PurpleAccount *account = accountLookupFromAdiumAccount(adiumAccount);
	PurpleConnection *gc = (account ? purple_account_get_connection(account) : NULL);

	if (!gc || !PURPLE_CONNECTION_IS_CONNECTED(gc))
		return NULL;

	JabberStream *js = gc->proto_data;
	JabberBuddy *jb = (js ? jabber_buddy_find(js, [contact.UID UTF8String], FALSE) : NULL);
	if (!jb)
		return NULL;

	if (!capability)
		return jabber_buddy_find_resource(jb, NULL);

	for (GList *each = jb->resources; each; each = each->next) {
		JabberBuddyResource *jbr = each->data;
		if (jbr && jbr->caps.info && jabber_resource_has_capability(jbr, capability))
			return jbr;
	}
	return NULL;
}

/*!
 * @brief Do we KNOW that this contact cannot do something?
 *
 * Three answers live in a question with two, and telling them apart is the whole
 * point. libpurple's own answer is FALSE both for "cannot" and for "nobody has
 * told us yet", and the second happens exactly in the seconds after a contact
 * appears in the list, which is when somebody clicks. So knowing nothing is never
 * a refusal here: only a resource that has told us its abilities, and does not
 * name this one, counts as a no. Every other case is tried, blind and generous,
 * the way it has always been.
 *
 * This is libpurple's house rule, written the same way four times over in
 * message.c and buddy.c for XHTML, receipts, chat markers and entity time.
 */
- (BOOL)contact:(AIListContact *)contact isKnownUnableTo:(const char *)capability
{
	CBPurpleAccount *adiumAccount = (CBPurpleAccount *)contact.account;
	PurpleAccount *account = accountLookupFromAdiumAccount(adiumAccount);
	PurpleConnection *gc = (account ? purple_account_get_connection(account) : NULL);

	if (!gc || !PURPLE_CONNECTION_IS_CONNECTED(gc))
		return NO;

	JabberStream *js = gc->proto_data;
	JabberBuddy *jb = (js ? jabber_buddy_find(js, [contact.UID UTF8String], FALSE) : NULL);
	if (!jb)
		return NO;

	BOOL anybodySaid = NO;
	for (GList *each = jb->resources; each; each = each->next) {
		JabberBuddyResource *jbr = each->data;
		if (!jbr || !jbr->caps.info)
			continue;			//this one has not told us anything yet
		anybodySaid = YES;
		if (jabber_resource_has_capability(jbr, capability))
			return NO;			//one that can is enough
	}

	return anybodySaid;			//somebody told us, and none of them can
}

//What a call reports ----------------------------------------------------------------------------
#pragma mark What a call reports

- (void)callController:(AIJingleCallController *)controller sendJingleElement:(NSString *)jingleXML
{
	NSString *sid = controller.machine.sid;
	CBPurpleAccount *account = accountsBySid[sid];

	/* Hanging up while it still rings over there: no session exists to terminate,
	 * the ringing is withdrawn in its own language instead. */
	AIJingleOutgoingProposal *proposal = proposalsOutBySid[sid];
	if (proposal && [jingleXML containsString:@"session-terminate"]) {
		[proposal.fallbackTimer invalidate];
		[proposalsOutBySid removeObjectForKey:sid];
		if (account)
			adiumPurpleJingleSendMessage(account, proposal.bareJid, @"retract", sid, NO, NO);
		return;
	}

	if (account && [controller.peerFullJid length])
		adiumPurpleJingleSendElement(account, controller.peerFullJid, jingleXML);
}

- (void)callControllerWasAnswered:(AIJingleCallController *)controller
{
	[self.uiDelegate manager:self callWasAnswered:controller];
}

- (void)callControllerPeerChangedWhatItSends:(AIJingleCallController *)controller
{
	[self.uiDelegate manager:self callPeerChangedWhatItSends:controller];
}

- (void)callControllerConnected:(AIJingleCallController *)controller
{
	AILog(@"Jingle: call %@ with %@ connected", controller.machine.sid, controller.peerFullJid);
	[self.uiDelegate manager:self callConnected:controller];
}

- (void)callController:(AIJingleCallController *)controller hasRemoteVideoTrack:(RTCVideoTrack *)track
{
	[self.uiDelegate manager:self call:controller hasRemoteVideoTrack:track];
}

- (void)callController:(AIJingleCallController *)controller endedWithReason:(NSString *)reason locally:(BOOL)locally
{
	AILog(@"Jingle: call %@ with %@ ended (%@, %@)", controller.machine.sid, controller.peerFullJid,
		  reason, locally ? @"locally" : @"by the peer");

	NSString *sid = controller.machine.sid;
	if (sid) {
		[[proposalsOutBySid[sid] fallbackTimer] invalidate];
		[proposalsOutBySid removeObjectForKey:sid];
		[controllersBySid removeObjectForKey:sid];
		[accountsBySid removeObjectForKey:sid];
	}
	[self.uiDelegate manager:self call:controller endedWithReason:reason locally:locally];
}

@end
