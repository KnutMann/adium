//
//  AIProgressDataUploader.m
//  Adium
//
//  Created by Zachary West on 2009-05-27.
//  
//  Thoroughly modified from the source of OFPOSTRequest at
//  http://objectiveflickr.googlecode.com/svn/trunk/Source/OFPOSTRequest.m
//
// Copyright (c) 2004-2006 Lukhnos D. Liu (lukhnos {at} gmail.com)
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Neither the name of ObjectiveFlickr nor the names of its contributors
//    may be used to endorse or promote products derived from this software
//    without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#import "AIProgressDataUploader.h"

#define TIMEOUT_INTERVAL 30.0

@interface AIProgressDataUploader() <NSURLSessionDataDelegate>
- (id)initWithData:(NSData *)inUploadData
			   URL:(NSURL *)inUrl
		   headers:(NSDictionary *)inHeaders
		  delegate:(id <AIProgressDataUploaderDelegate>)inDelegate
		   context:(id)inContext;

// Timers
- (void)timeoutDidOccur;
@end

@implementation AIProgressDataUploader
/*!
 * @brief Create a data uploader.
 *
 * @param delegate The delegate
 * @param context The context for this upload
 *
 * Uploading does not begin until -upload is called.
 */
+ (id)dataUploaderWithData:(NSData *)uploadData
					   URL:(NSURL *)url
				   headers:(NSDictionary *)headers
				  delegate:(id <AIProgressDataUploaderDelegate>)delegate
				   context:(id)context
{
	return [[self alloc] initWithData:uploadData URL:url headers:headers delegate:delegate context:context];
}

- (id)initWithData:(NSData *)inUploadData
			   URL:(NSURL *)inURL
		   headers:(NSDictionary *)inHeaders
		  delegate:(id <AIProgressDataUploaderDelegate>)inDelegate
		   context:(id)inContext
{
	if ((self = [super init])) {
		uploadData = inUploadData;
		delegate = inDelegate;
		context = inContext;
		url = inURL;
		headers = inHeaders;
	}
	
	return self;
}

- (void)dealloc
{
	url = nil;
	headers = nil;
	uploadData = nil;
	returnedData = nil;
}

/*!
 * @brief Begin the upload.
 *
 * Immediately begins the upload.
 */
- (void)upload
{
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setHTTPMethod:@"POST"];
	
	for (NSString *headerKey in headers) {
		[request setValue:[headers objectForKey:headerKey] forHTTPHeaderField:headerKey];
	}
	
	totalSize = [uploadData length];
	returnedData = [[NSMutableData alloc] init];
	
	/* The main queue as the delegate queue keeps the callbacks on the main thread, which is where
	 * the run-loop-scheduled stream this replaces delivered them. The ephemeral configuration keeps
	 * shared cookies and caches out of the request, as the bare stream did. The session holds on to
	 * its delegate (us) until it is invalidated, which every path out of the upload does. */
	session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
											delegate:self
									   delegateQueue:[NSOperationQueue mainQueue]];
	
	uploadTask = [session uploadTaskWithRequest:request fromData:uploadData];
	[uploadTask resume];
	
	timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:TIMEOUT_INTERVAL
													target:self
											  selector:@selector(timeoutDidOccur)
											  userInfo:nil
												   repeats:NO];
}

/*!
 * @brief Cancel the upload.
 *
 * Cancels the upload and returns no further status messages to the delegate.
 */
- (void)cancel
{
	if (!uploadTask) {
		return;
	}
	
	/* Forget the task before cancelling it: the completion callback still arrives, carrying
	 * NSURLErrorCancelled, and no longer matching uploadTask is what keeps any further status
	 * messages away from the delegate. */
	NSURLSessionUploadTask *task = uploadTask;
	uploadTask = nil;
	[task cancel];
	
	[session invalidateAndCancel]; session = nil;

	[timeoutTimer invalidate]; timeoutTimer = nil;
}

/*!
 * @brief A timeout occured
 *
 * We weren't able to upload any more data after a specified duration of time.
 * Fail cleanly and let our delegate know.
 */
- (void)timeoutDidOccur
{
	[self cancel];
	[delegate uploadFailed:context];
}

#pragma mark NSURLSession delegate

/*!
 * @brief Body bytes went out
 *
 * Updates our delegate with our current upload progress and pushes the timeout back,
 * as often as the connection reports progress.
 */
- (void)URLSession:(NSURLSession *)inSession
			  task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)inBytesSent
	totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
	if (task != uploadTask) {
		return;
	}
	
	if (totalBytesSent > bytesSent) {
		bytesSent = (NSInteger)totalBytesSent;

		[delegate updateUploadProgress:bytesSent
								 total:totalSize
							  context:context];
		
		[timeoutTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:TIMEOUT_INTERVAL]];
	}
}

/*!
 * @brief The server redirected us
 *
 * The stream this replaces never followed redirects; keep that, and let the body of the
 * redirect response itself flow to the delegate like any other result.
 */
- (void)URLSession:(NSURLSession *)inSession
			  task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
		newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler
{
	completionHandler(nil);
}

/*!
 * @brief Bytes are available
 *
 * Collect the response body as it arrives.
 */
- (void)URLSession:(NSURLSession *)inSession
		  dataTask:(NSURLSessionDataTask *)dataTask
	didReceiveData:(NSData *)data
{
	if (dataTask != uploadTask) {
		return;
	}
	
	[returnedData appendData:data];
}

/*!
 * @brief The upload finished
 *
 * Let our delegate know how it went, unless the upload was cancelled, in which case the
 * delegate hears nothing further.
 */
- (void)URLSession:(NSURLSession *)inSession
			  task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
	if (task != uploadTask) {
		return;
	}
	
	uploadTask = nil;
	
	[timeoutTimer invalidate]; timeoutTimer = nil;
	
	[session finishTasksAndInvalidate]; session = nil;
	
	if (error) {
		[delegate uploadFailed:context];
	} else {
		[delegate uploadCompleted:context result:returnedData];
	}
}

@end
