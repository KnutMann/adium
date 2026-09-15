/* Sitzt im Anruffenster alles da, wo es hingehoert?
 *
 * Geometrie laesst sich nicht durch Hinsehen pruefen, jedenfalls nicht in jeder
 * Sprache und nicht in jeder Fenstergroesse. Dieser Test baut das ECHTE Fenster,
 * einmal ohne Bild und einmal mit, und misst die Rahmen: nichts ueberlappt, nichts
 * steht ausserhalb, kein versteckter Knopf haelt eine Luecke frei, und die Leiste
 * bleibt frei, auch wenn das Bild das Fenster ausfuellt.
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

/*! Alle Knoepfe und Beschriftungen der unteren Leiste, egal wie tief verschachtelt */
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

/*! Der Rahmen einer Ansicht in den Koordinaten des Fensterinhalts */
static NSRect frameInContent(NSView *view, NSView *content)
{
	return [content convertRect:[view bounds] fromView:view];
}

/*! Das erste sichtbare Bildschild auf der Buehne, falls eines da ist */
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
 * @brief Steht die Knopfreihe geschlossen am rechten Rand?
 *
 * Ein Knopf, der nur unsichtbar ist, behaelt jede Bedingung und damit seine
 * Breite; zwischen zwei sichtbaren Knoepfen klaffte dann ein Loch von seiner
 * Groesse, und die Reihe sass nicht mehr da, wo sie hingehoert.
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

	check([NSString stringWithFormat:@"Kein versteckter Knopf haelt eine Luecke frei (%@)", which],
		  widestGap <= 16.0, [NSString stringWithFormat:@"groesste Luecke=%.0f", widestGap]);

	CGFloat toTheEdge = ([buttons count] ?
						 NSMaxX([content bounds]) - NSMaxX([[buttons lastObject] rectValue]) : -1);
	check([NSString stringWithFormat:@"Die Reihe schliesst rechts am Rand ab (%@)", which],
		  [buttons count] && toTheEdge <= 14.0,
		  [NSString stringWithFormat:@"Abstand=%.0f", toTheEdge]);
}

int main(void) { @autoreleasepool {
	[NSApplication sharedApplication];

	//Ein Anruf ohne Bild ------------------------------------------------------------------------
	AIJingleCallController *plain = [[AIJingleCallController alloc] initAsInitiatorFrom:@"a@localhost/a"
																					 to:@"b@localhost/b"];
	AIJingleCallWindowController *audio =
		[[AIJingleCallWindowController alloc] initWithCallController:plain displayName:@"Jemand"];
	NSWindow *window = [audio window];
	NSView *content = [window contentView];
	settle(window);

	check(@"Ohne Bild ist die Hoehe festgenagelt",
		  [window contentMaxSize].height == BAR_HEIGHT,
		  [NSString stringWithFormat:@"max=%.0f", [window contentMaxSize].height]);
	check(@"und die Breite darf trotzdem wachsen",
		  [window contentMaxSize].width > [window contentMinSize].width * 2, nil);

	NSArray<NSView *> *pieces = barPieces(content);
	check(@"Ohne Kamera zeigt die Leiste nur, was es gibt",
		  [pieces count] == 3,		//Status, Mikrofon, Auflegen
		  [NSString stringWithFormat:@"sichtbar=%lu", (unsigned long)[pieces count]]);

	for (NSView *piece in pieces) {
		NSRect frame = frameInContent(piece, content);
		if (!NSContainsRect([content bounds], frame))
			check(@"Alles in der Leiste steht im Fenster", NO,
				  [NSString stringWithFormat:@"%@ bei %@", [piece className], NSStringFromRect(frame)]);
	}
	check(@"Alles in der Leiste steht im Fenster", YES, nil);

	for (NSUInteger one = 0; one < [pieces count]; one++)
		for (NSUInteger two = one + 1; two < [pieces count]; two++) {
			NSRect left = frameInContent(pieces[one], content), right = frameInContent(pieces[two], content);
			if (NSIntersectsRect(NSInsetRect(left, 1, 1), NSInsetRect(right, 1, 1)))
				check(@"Nichts in der Leiste ueberlappt", NO,
					  [NSString stringWithFormat:@"%@ und %@", NSStringFromRect(left), NSStringFromRect(right)]);
		}
	check(@"Nichts in der Leiste ueberlappt", YES, nil);

	checkTheRow(content, @"ohne Bild");

	//Ein Anruf mit Bild -------------------------------------------------------------------------
	AIJingleCallController *withPicture = [[AIJingleCallController alloc] initAsInitiatorFrom:@"a@localhost/a"
																						   to:@"b@localhost/b"];
	/* Wie im echten Anruf: der Wunsch nach Video steht fest, BEVOR das Fenster
	 * gebaut wird, die Spuren entstehen erst danach. Genau daran hing der
	 * Kameraknopf frueher und war deshalb in jedem Anruf unsichtbar. */
	withPicture.wantsVideo = YES;
	AIJingleCallWindowController *video =
		[[AIJingleCallWindowController alloc] initWithCallController:withPicture displayName:@"Jemand"];
	NSWindow *bigger = [video window];
	NSView *stageContent = [bigger contentView];

	RTCPeerConnectionFactory *factory = [[RTCPeerConnectionFactory alloc] init];
	RTCVideoSource *source = [factory videoSource];
	RTCVideoTrack *track = [factory videoTrackWithSource:source trackId:@"pruefung"];
	[video attachRemoteVideoTrack:track];
	settle(bigger);

	check(@"Ein Videoanruf hat einen Knopf fuer die eigene Kamera",
		  [barPieces(stageContent) count] == 5,		//Status, Mikrofon, Kamera, Fuellen, Auflegen
		  [NSString stringWithFormat:@"sichtbar=%lu", (unsigned long)[barPieces(stageContent) count]]);

	//Und er wirkt, auch bevor ueberhaupt eine Verbindung steht
	withPicture.cameraOff = YES;
	check(@"Die eigene Kamera laesst sich abschalten", withPicture.cameraOff, nil);
	withPicture.cameraOff = NO;

	check(@"Mit Bild darf das Fenster wieder hoeher werden",
		  [bigger contentMaxSize].height > 1000.0, nil);

	AIJingleVideoView *picture = findVideoView(stageContent);
	check(@"Es gibt eine Bildflaeche", picture != nil, nil);

	if (picture) {
		check(@"Die Bildflaeche beschneidet, was ueber ihren Rand hinausgeht",
			  [[picture layer] masksToBounds], nil);

		NSRect frame = frameInContent(picture, stageContent);
		check(@"Die Bildflaeche laesst die Leiste frei",
			  NSMinY(frame) >= BAR_HEIGHT - 0.5,
			  [NSString stringWithFormat:@"unterer Rand bei %.1f, Leiste bis %.0f", NSMinY(frame), BAR_HEIGHT]);

		//Und auch beim Ausfuellen, denn genau da hat sie es frueher ueberzeichnet
		picture.fillsTheFrame = YES;
		settle(bigger);
		check(@"Auch beim Ausfuellen bleibt die Leiste frei",
			  NSMinY(frameInContent(picture, stageContent)) >= BAR_HEIGHT - 0.5 &&
			  [[picture layer] masksToBounds], nil);
	}

	/* Und das Schild, wenn die Gegenseite ihre Kamera ausmacht. Gefuettert wird es
	 * ueber den echten Weg, also eine session-info, wie sie vom Draht kaeme. */
	[video noteConnected];
	check(@"Solange die Gegenseite sendet, steht kein Schild im Bild",
		  visibleSign(stageContent) == nil, nil);

	[withPicture handleRemoteJingleElement:
		@"<jingle xmlns='urn:xmpp:jingle:1' action='session-info' sid='testsid'>"
		@"<mute xmlns='urn:xmpp:jingle:apps:rtp:info:1' creator='initiator' name='video'/></jingle>"];
	[video showWhatThePeerSends];
	settle(bigger);

	check(@"Die abgeschaltete Kamera der Gegenseite wird gemeldet", withPicture.peerCameraOff, nil);

	NSImageView *sign = visibleSign(stageContent);
	check(@"und als Schild mitten ins schwarze Bild gestellt", sign != nil, nil);
	if (sign) {
		NSRect where = frameInContent(sign, stageContent);
		NSRect picture = frameInContent(findVideoView(stageContent), stageContent);
		check(@"Das Schild steht in der Mitte des Bildes",
			  fabs(NSMidX(where) - NSMidX(picture)) < 2.0 && fabs(NSMidY(where) - NSMidY(picture)) < 2.0,
			  [NSString stringWithFormat:@"Schild %@ im Bild %@",
			   NSStringFromRect(where), NSStringFromRect(picture)]);
	}

	[withPicture handleRemoteJingleElement:
		@"<jingle xmlns='urn:xmpp:jingle:1' action='session-info' sid='testsid'>"
		@"<unmute xmlns='urn:xmpp:jingle:apps:rtp:info:1' creator='initiator' name='video'/></jingle>"];
	[video showWhatThePeerSends];
	settle(bigger);
	check(@"Schaltet sie wieder ein, verschwindet das Schild",
		  !withPicture.peerCameraOff && visibleSign(stageContent) == nil, nil);

	/* Und nach dem Ende duerfen die Schalter nicht mehr so aussehen, als taeten sie
	 * noch etwas. Beendet die Gegenseite, bleibt das Fenster ja lesbar stehen. */
	[video noteEndedWithReason:@"success" locally:NO];
	settle(bigger);

	/* Die Schalter tragen ein Symbol, der Auflegenknopf einen Text: der heisst jetzt
	 * Schliessen und muss weiter wirken. */
	BOOL anyStillLive = NO;
	for (NSView *piece in barPieces(stageContent))
		if ([piece isKindOfClass:[NSButton class]] &&
			[(NSButton *)piece image] && [(NSButton *)piece isEnabled])
			anyStillLive = YES;

	check(@"Nach dem Ende wirkt kein Schalter mehr", !anyStillLive, nil);

	checkTheRow(stageContent, @"mit Bild");

	NSArray<NSView *> *withStage = barPieces(stageContent);
	for (NSView *piece in withStage) {
		NSRect frame = frameInContent(piece, stageContent);
		if (NSMaxY(frame) > BAR_HEIGHT + 0.5 && ![piece isKindOfClass:[AIJingleVideoView class]])
			check(@"Die Leiste bleibt unten und wandert nicht ins Bild", NO,
				  [NSString stringWithFormat:@"%@ bis %.1f", [piece className], NSMaxY(frame)]);
	}
	check(@"Die Leiste bleibt unten und wandert nicht ins Bild", YES, nil);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
