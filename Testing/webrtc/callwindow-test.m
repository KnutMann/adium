/* Does everything in the call window sit where it belongs?
 *
 * Geometry cannot be checked by looking, at least not in every language and not
 * at every window size. This test builds the REAL window, once without video and
 * once with, and measures the frames: nothing overlaps, nothing stands outside,
 * no hidden button holds a gap open, and the bar stays clear even when the
 * picture fills the window.
 */
#import <AppKit/AppKit.h>
#import <WebRTC/WebRTC.h>
#import "AIJingleCallController.h"
#import "AIJingleCallWindowController.h"
#import "AIJingleVideoView.h"

#define BAR_HEIGHT 56.0

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

static void settle(NSWindow *window)
{
	[[window contentView] layoutSubtreeIfNeeded];
	for (int i = 0; i < 6; i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
	[[window contentView] layoutSubtreeIfNeeded];
}

/*! Every button and label of the bottom bar, however deeply nested */
static NSArray<NSView *> *barPieces(NSView *content)
{
	NSMutableArray *found = [NSMutableArray array];
	NSMutableArray *todo = [[content subviews] mutableCopy];

	while ([todo count]) {
		NSView *view = [todo firstObject];
		[todo removeObjectAtIndex:0];
		if ([view isHidden])
			continue;
		if ([view isKindOfClass:[NSButton class]] || [view isKindOfClass:[NSTextField class]])
			[found addObject:view];
		else
			[todo addObjectsFromArray:[view subviews]];
	}
	return found;
}

/*! A view's frame in the coordinates of the window's content */
static NSRect frameInContent(NSView *view, NSView *content)
{
	return [content convertRect:[view bounds] fromView:view];
}

/*! The first visible sign on the stage, if there is one */
static NSImageView *visibleSign(NSView *view)
{
	if ([view isKindOfClass:[NSImageView class]] && ![view isHidden])
		return (NSImageView *)view;
	for (NSView *child in [view subviews]) {
		NSImageView *found = visibleSign(child);
		if (found)
			return found;
	}
	return nil;
}

static AIJingleVideoView *findVideoView(NSView *view)
{
	if ([view isKindOfClass:[AIJingleVideoView class]])
		return (AIJingleVideoView *)view;
	for (NSView *child in [view subviews]) {
		AIJingleVideoView *found = findVideoView(child);
		if (found)
			return found;
	}
	return nil;
}

/*!
 * @brief Does the row of buttons sit closed up against the right edge?
 *
 * A button that is merely invisible keeps every constraint and therefore its
 * width; a hole of that size then gaped between two visible buttons, and the
 * row no longer sat where it belongs.
 */
static void checkTheRow(NSView *content, NSString *which)
{
	NSMutableArray<NSValue *> *buttons = [NSMutableArray array];
	for (NSView *piece in barPieces(content))
		if ([piece isKindOfClass:[NSButton class]])
			[buttons addObject:[NSValue valueWithRect:frameInContent(piece, content)]];

	[buttons sortUsingComparator:^NSComparisonResult(NSValue *one, NSValue *two) {
		CGFloat left = NSMinX([one rectValue]), right = NSMinX([two rectValue]);
		return (left < right ? NSOrderedAscending : (left > right ? NSOrderedDescending : NSOrderedSame));
	}];

	CGFloat widestGap = 0;
	for (NSUInteger index = 1; index < [buttons count]; index++)
		widestGap = MAX(widestGap, NSMinX([buttons[index] rectValue]) - NSMaxX([buttons[index - 1] rectValue]));

	check([NSString stringWithFormat:@"No hidden button holds a gap open (%@)", which],
		  widestGap <= 16.0, [NSString stringWithFormat:@"widest gap=%.0f", widestGap]);

	CGFloat toTheEdge = ([buttons count] ?
						 NSMaxX([content bounds]) - NSMaxX([[buttons lastObject] rectValue]) : -1);
	check([NSString stringWithFormat:@"The row finishes at the right edge (%@)", which],
		  [buttons count] && toTheEdge <= 14.0,
		  [NSString stringWithFormat:@"distance=%.0f", toTheEdge]);
}

int main(void) { @autoreleasepool {
	[NSApplication sharedApplication];

	//A call without video -----------------------------------------------------------------------
	AIJingleCallController *plain = [[AIJingleCallController alloc] initAsInitiatorFrom:@"a@localhost/a"
																					 to:@"b@localhost/b"];
	AIJingleCallWindowController *audio =
		[[AIJingleCallWindowController alloc] initWithCallController:plain displayName:@"Somebody"];
	NSWindow *window = [audio window];
	NSView *content = [window contentView];
	settle(window);

	check(@"Without video the height is nailed down",
		  [window contentMaxSize].height == BAR_HEIGHT,
		  [NSString stringWithFormat:@"max=%.0f", [window contentMaxSize].height]);
	check(@"and the width may still grow",
		  [window contentMaxSize].width > [window contentMinSize].width * 2, nil);

	NSArray<NSView *> *pieces = barPieces(content);
	check(@"Without a camera the bar shows only what there is",
		  [pieces count] == 3,		//status, microphone, hang up
		  [NSString stringWithFormat:@"visible=%lu", (unsigned long)[pieces count]]);

	for (NSView *piece in pieces) {
		NSRect frame = frameInContent(piece, content);
		if (!NSContainsRect([content bounds], frame))
			check(@"Everything in the bar stands inside the window", NO,
				  [NSString stringWithFormat:@"%@ at %@", [piece className], NSStringFromRect(frame)]);
	}
	check(@"Everything in the bar stands inside the window", YES, nil);

	for (NSUInteger one = 0; one < [pieces count]; one++)
		for (NSUInteger two = one + 1; two < [pieces count]; two++) {
			NSRect left = frameInContent(pieces[one], content), right = frameInContent(pieces[two], content);
			if (NSIntersectsRect(NSInsetRect(left, 1, 1), NSInsetRect(right, 1, 1)))
				check(@"Nothing in the bar overlaps", NO,
					  [NSString stringWithFormat:@"%@ and %@", NSStringFromRect(left), NSStringFromRect(right)]);
		}
	check(@"Nothing in the bar overlaps", YES, nil);

	checkTheRow(content, @"without video");

	//A call with video --------------------------------------------------------------------------
	AIJingleCallController *withPicture = [[AIJingleCallController alloc] initAsInitiatorFrom:@"a@localhost/a"
																						   to:@"b@localhost/b"];
	/* As in a real call: the wish for video is settled BEFORE the window is
	 * built, the tracks come into being only afterwards. That is exactly what
	 * the camera button used to hang on, and why it was invisible in every call. */
	withPicture.wantsVideo = YES;
	AIJingleCallWindowController *video =
		[[AIJingleCallWindowController alloc] initWithCallController:withPicture displayName:@"Somebody"];
	NSWindow *bigger = [video window];
	NSView *stageContent = [bigger contentView];

	RTCPeerConnectionFactory *factory = [[RTCPeerConnectionFactory alloc] init];
	RTCVideoSource *source = [factory videoSource];
	RTCVideoTrack *track = [factory videoTrackWithSource:source trackId:@"check"];
	[video attachRemoteVideoTrack:track];
	settle(bigger);

	check(@"A video call has a button for our own camera",
		  [barPieces(stageContent) count] == 5,		//status, microphone, camera, fill, hang up
		  [NSString stringWithFormat:@"visible=%lu", (unsigned long)[barPieces(stageContent) count]]);

	//And it works even before a connection stands at all
	withPicture.cameraOff = YES;
	check(@"Our own camera can be switched off", withPicture.cameraOff, nil);
	withPicture.cameraOff = NO;

	check(@"With video the window may grow taller again",
		  [bigger contentMaxSize].height > 1000.0, nil);

	AIJingleVideoView *picture = findVideoView(stageContent);
	check(@"There is a picture area", picture != nil, nil);

	if (picture) {
		check(@"The picture area clips whatever goes past its edge",
			  [[picture layer] masksToBounds], nil);

		NSRect frame = frameInContent(picture, stageContent);
		check(@"The picture area leaves the bar clear",
			  NSMinY(frame) >= BAR_HEIGHT - 0.5,
			  [NSString stringWithFormat:@"bottom edge at %.1f, bar up to %.0f", NSMinY(frame), BAR_HEIGHT]);

		//And while filling too, because that is exactly where it used to draw over it
		picture.fillsTheFrame = YES;
		settle(bigger);
		check(@"Even while filling, the bar stays clear",
			  NSMinY(frameInContent(picture, stageContent)) >= BAR_HEIGHT - 0.5 &&
			  [[picture layer] masksToBounds], nil);
	}

	/* And the sign for when the other side turns its camera off. It is fed over
	 * the real path, that is a session-info the way it would come off the wire. */
	[video noteConnected];
	check(@"While the other side is sending, no sign stands in the picture",
		  visibleSign(stageContent) == nil, nil);

	[withPicture handleRemoteJingleElement:
		@"<jingle xmlns='urn:xmpp:jingle:1' action='session-info' sid='testsid'>"
		@"<mute xmlns='urn:xmpp:jingle:apps:rtp:info:1' creator='initiator' name='video'/></jingle>"];
	[video showWhatThePeerSends];
	settle(bigger);

	check(@"The other side's switched off camera is reported", withPicture.peerCameraOff, nil);

	NSImageView *sign = visibleSign(stageContent);
	check(@"and put as a sign in the middle of the black picture", sign != nil, nil);
	if (sign) {
		NSRect where = frameInContent(sign, stageContent);
		NSRect picture = frameInContent(findVideoView(stageContent), stageContent);
		check(@"The sign stands in the middle of the picture",
			  fabs(NSMidX(where) - NSMidX(picture)) < 2.0 && fabs(NSMidY(where) - NSMidY(picture)) < 2.0,
			  [NSString stringWithFormat:@"sign %@ in picture %@",
			   NSStringFromRect(where), NSStringFromRect(picture)]);
	}

	[withPicture handleRemoteJingleElement:
		@"<jingle xmlns='urn:xmpp:jingle:1' action='session-info' sid='testsid'>"
		@"<unmute xmlns='urn:xmpp:jingle:apps:rtp:info:1' creator='initiator' name='video'/></jingle>"];
	[video showWhatThePeerSends];
	settle(bigger);
	check(@"Switch it back on and the sign disappears",
		  !withPicture.peerCameraOff && visibleSign(stageContent) == nil, nil);

	/* And after the end the switches must not look as though they still did
	 * anything. If the other side ends it, the window stays there to be read. */
	[video noteEndedWithReason:@"success" locally:NO];
	settle(bigger);

	/* The switches carry a symbol, the hang up button carries text: that one now
	 * says Close and has to keep working. */
	BOOL anyStillLive = NO;
	for (NSView *piece in barPieces(stageContent))
		if ([piece isKindOfClass:[NSButton class]] &&
			[(NSButton *)piece image] && [(NSButton *)piece isEnabled])
			anyStillLive = YES;

	check(@"After the end no switch works any more", !anyStillLive, nil);

	checkTheRow(stageContent, @"with video");

	NSArray<NSView *> *withStage = barPieces(stageContent);
	for (NSView *piece in withStage) {
		NSRect frame = frameInContent(piece, stageContent);
		if (NSMaxY(frame) > BAR_HEIGHT + 0.5 && ![piece isKindOfClass:[AIJingleVideoView class]])
			check(@"The bar stays at the bottom and does not wander into the picture", NO,
				  [NSString stringWithFormat:@"%@ up to %.1f", [piece className], NSMaxY(frame)]);
	}
	check(@"The bar stays at the bottom and does not wander into the picture", YES, nil);

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
