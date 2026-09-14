/* Prints the offer SDP this WebRTC build really produces for an audio and a
 * video track. The Jingle mapper is developed against this output, not
 * against examples from the XEPs: what our own stack emits is what the
 * mapping has to carry. */
#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

@interface Quiet : NSObject <RTCPeerConnectionDelegate>
@end
@implementation Quiet
- (void)peerConnection:(RTCPeerConnection *)pc didChangeSignalingState:(RTCSignalingState)stateChanged {}
- (void)peerConnection:(RTCPeerConnection *)pc didAddStream:(RTCMediaStream *)stream {}
- (void)peerConnection:(RTCPeerConnection *)pc didRemoveStream:(RTCMediaStream *)stream {}
- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)pc {}
- (void)peerConnection:(RTCPeerConnection *)pc didChangeIceConnectionState:(RTCIceConnectionState)newState {}
- (void)peerConnection:(RTCPeerConnection *)pc didChangeIceGatheringState:(RTCIceGatheringState)newState {}
- (void)peerConnection:(RTCPeerConnection *)pc didGenerateIceCandidate:(RTCIceCandidate *)candidate {}
- (void)peerConnection:(RTCPeerConnection *)pc didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates {}
- (void)peerConnection:(RTCPeerConnection *)pc didOpenDataChannel:(RTCDataChannel *)dataChannel {}
@end

int main(void) { @autoreleasepool {
	RTCPeerConnectionFactory *factory = [[RTCPeerConnectionFactory alloc]
		initWithEncoderFactory:[[RTCDefaultVideoEncoderFactory alloc] init]
				decoderFactory:[[RTCDefaultVideoDecoderFactory alloc] init]];

	RTCConfiguration *config = [[RTCConfiguration alloc] init];
	config.sdpSemantics = RTCSdpSemanticsUnifiedPlan;
	RTCMediaConstraints *none = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@{}
																	  optionalConstraints:@{}];
	Quiet *quiet = [Quiet new];
	RTCPeerConnection *pc = [factory peerConnectionWithConfiguration:config constraints:none delegate:quiet];

	RTCAudioSource *audioSource = [factory audioSourceWithConstraints:none];
	[pc addTrack:[factory audioTrackWithSource:audioSource trackId:@"audio0"] streamIds:@[@"stream0"]];
	RTCVideoSource *videoSource = [factory videoSource];
	[pc addTrack:[factory videoTrackWithSource:videoSource trackId:@"video0"] streamIds:@[@"stream0"]];

	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	[pc offerForConstraints:none completionHandler:^(RTCSessionDescription *offer, NSError *error) {
		if (offer) printf("%s", offer.sdp.UTF8String);
		else fprintf(stderr, "offer failed: %s\n", error.description.UTF8String);
		dispatch_semaphore_signal(done);
	}];
	dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
	return 0;
} }
