/* Turns an SDP file into the jingle element a peer would send, so other tools
 * can speak a real session at Adium without carrying WebRTC themselves. */
#import <Foundation/Foundation.h>
#import "AIJingleEngine.h"

int main(int argc, char **argv) { @autoreleasepool {
	if (argc < 2) { fprintf(stderr, "usage: sdp-to-jingle <sdp file> [action] [sid]\n"); return 2; }
	NSString *sdp = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]
											 encoding:NSUTF8StringEncoding error:NULL];
	if (![sdp length]) { fprintf(stderr, "cannot read sdp\n"); return 1; }

	AIJingleSession *session = [AIJingleSession sessionFromSDP:sdp];
	session.sid = (argc > 3) ? [NSString stringWithUTF8String:argv[3]] : @"SIDPLACEHOLDER";
	NSString *action = (argc > 2) ? [NSString stringWithUTF8String:argv[2]] : @"session-initiate";

	printf("%s\n", [[session jingleElementForAction:action
										  initiator:@"peer@localhost/fakepeer"
										  responder:nil
										asInitiator:YES] UTF8String]);
	return 0;
} }
