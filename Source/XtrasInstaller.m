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

#import "XtrasInstaller.h"
#import <AIUtilities/AIBundleAdditions.h>
#import <AIUtilities/AIStringAdditions.h>

//Should only be YES for testing
#define	ALLOW_UNTRUSTED_XTRAS	NO

@interface XtrasInstaller ()
- (void)closeInstaller __attribute__((ns_consumes_self));
- (void)updateInfoText;
@end

/*!
 * @class XtrasInstaller
 * @brief Class which displays a progress window and downloads an AdiumXtra, decompresses it, and installs it.
 */
@implementation XtrasInstaller

@synthesize dest, session, downloadTask, xtraName;

//XtrasInstaller does not autorelease because it will release itself when closed
+ (XtrasInstaller *)installer
{
	return [[XtrasInstaller alloc] init];
}

- (id)init
{
	if ((self = [super init])) {
		session = nil;
		downloadTask = nil;
		window = nil;
	}

	return self;
}

- (void)dealloc
{
	[session release];
	[downloadTask release];
	[xtraName release];
	[dest release];

	[super dealloc];
}

- (IBAction)cancel:(id)sender;
{
	if (self.downloadTask) [self.downloadTask cancel];
	[self closeInstaller];
}

- (void)closeInstaller
{
	if (window) [window close];
	/* The session retains its delegate (us) until it is invalidated, so this must
	 * happen before the autorelease below or the installer would never deallocate.
	 * It also guarantees we stay alive for any delegate callback still in flight:
	 * the session only drops its delegate after invalidation completes. */
	[self.session invalidateAndCancel];
	[self autorelease];	
}

- (void)installXtraAtURL:(NSURL *)url
{
	if ([[url host] isEqualToString:@"xtras.adium.im"] || [[url host] isEqualToString:@"www.adiumxtras.com"] || ALLOW_UNTRUSTED_XTRAS) {
		NSURL	*urlToDownload;

		[NSBundle ai_loadNibNamed:@"XtraProgressWindow" owner:self];
		[progressBar setUsesThreadedAnimation:YES];
		
		xtraName = nil;
		amountDownloaded = 0;
		downloadSize = 0;
		
		[progressBar setDoubleValue:0];
		[cancelButton setTitle:AILocalizedString(@"Cancel",nil)];
		[window setTitle:AILocalizedString(@"Xtra Download",nil)];

		[self updateInfoText];

		[window makeKeyAndOrderFront:self];

		/* App Transport Security refuses plain HTTP outright, so an adiumxtra:// link died with a
		 * policy error rather than a download. Both names below answer on the same address and
		 * serve the same site, but the certificate is issued for adiumxtras.com alone - asking
		 * for xtras.adium.im over TLS fails on the name, not on the connection. So ask the host
		 * the certificate is written for. */
		NSString *downloadHost = ([[url host] isEqualToString:@"xtras.adium.im"] ?
								  @"www.adiumxtras.com" :
								  [url host]);

		urlToDownload = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"%@://%@/%@%@%@", @"https", downloadHost, [url path],
													   ([url query] ? @"?" : @""),
													   ([url query] ? [url query] : @"")]];
//		dest = [NSTemporaryDirectory() stringByAppendingPathComponent:[[urlToDownload path] lastPathComponent]];
		AILogWithSignature(@"Downloading %@", urlToDownload);
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:urlToDownload];
		[request setHTTPShouldHandleCookies:NO];
		/* NSURLDownload let its delegate refuse transparent Content-Encoding decoding
		 * (shouldDecodeSourceDataOfMIMEType: returned NO); NSURLSession has no such
		 * switch, so ask the server for raw bytes instead. Otherwise a .tgz served
		 * with Content-Encoding: gzip would be gunzipped behind our back and the
		 * decompression in the finish handler would fail. */
		[request setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];

		/* Delegate callbacks arrive on the main queue: the progress UI and the
		 * synchronous unpacking in the delegate methods expect that, exactly as
		 * NSURLDownload delivered them. */
		self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
													 delegate:self
												delegateQueue:[NSOperationQueue mainQueue]];
		self.downloadTask = [self.session downloadTaskWithRequest:request];
		[self.downloadTask resume];

		[urlToDownload release];

	} else {
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:AILocalizedString(@"Nontrusted Xtra", nil)];
		[alert setInformativeText:AILocalizedString(@"This Xtra is not hosted on the Adium Xtras website. Automatic installation is not allowed.", nil)];
		[alert addButtonWithTitle:AILocalizedString(@"Cancel", nil)];
		[alert runModal];
		[self closeInstaller];
	}
}

- (void)updateInfoText
{
	NSInteger				percentComplete = (downloadSize > 0 ? (NSUInteger)(((double)amountDownloaded / (double)downloadSize) * 100.0) : 0);
	NSString		*installText = [NSString stringWithFormat:AILocalizedString(@"Downloading %@", @"Install an Xtra; %@ is the name of the Xtra."), (self.xtraName ? self.xtraName : @"")];
	
	[infoText setStringValue:[NSString stringWithFormat:@"%@ (%lu%%)", installText, percentComplete]];
}

- (void)URLSession:(NSURLSession *)inSession downloadTask:(NSURLSessionDownloadTask *)inDownloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
	/* Download tasks get no didReceiveResponse callback; the response is available on
	 * the task once data starts arriving. -valueForHTTPHeaderField: is case-insensitive,
	 * unlike the old allHeaderFields lookup, which relied on NSURLDownload's header
	 * canonicalization. */
	if (!self.xtraName) {
		NSURLResponse *response = [inDownloadTask response];
		if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
			self.xtraName = [(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"X-Xtraname"];
		}
	}

	amountDownloaded = (unsigned long long)totalBytesWritten;

	if (totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown) {
		if (downloadSize != (unsigned long long)totalBytesExpectedToWrite) {
			downloadSize = (unsigned long long)totalBytesExpectedToWrite;
			[progressBar setIndeterminate:NO];
			[progressBar setMaxValue:(double)downloadSize];
		}
		[progressBar setDoubleValue:(double)amountDownloaded];
		[self updateInfoText];
	}
	else
		[progressBar setIndeterminate:YES];
}

- (void)URLSession:(NSURLSession *)inSession task:(NSURLSessionTask *)inTask didCompleteWithError:(NSError *)error
{
	/* Success: the file was already moved, unpacked, and the installer closed in
	 * -URLSession:downloadTask:didFinishDownloadingToURL: (which also covers a failed
	 * move, showing its own alert there). */
	if (!error) return;

	/* Cancellation: the cancel button already cancelled the task and closed the
	 * installer. Closing again here would over-release self. */
	if ([[error domain] isEqualToString:NSURLErrorDomain] && [error code] == NSURLErrorCancelled) return;

	NSString	*errorMsg;

	errorMsg = [NSString stringWithFormat:AILocalizedString(@"An error occurred while downloading this Xtra: %@.",nil),[error localizedDescription]];
	
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:AILocalizedString(@"Xtra Downloading Error",nil)];
	[alert setInformativeText:errorMsg];
	[alert addButtonWithTitle:AILocalizedString(@"Cancel",nil)];
	/* The former didDismissSelector cancelled the download regardless of the button pressed;
	 * the completion handler runs after the sheet is dismissed, preserving that behavior. */
	[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
		[self cancel:nil];
	}];
}

/* Applies the quarantine properties to everything inside the directory. Replaces the
 * former FSIterator/LSSetItemAttribute implementation with the NSURL resource-value
 * API (AdiumY pattern); the deep NSDirectoryEnumerator covers the same set of items
 * the old flat-iterate-plus-recurse loop did.
 */
- (void)setQuarantineProperties:(NSDictionary *)dict forDirectory:(NSURL *)dir
{
	NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:dir
															 includingPropertiesForKeys:nil
																				options:0
																		   errorHandler:nil];
	for (NSURL *url in enumerator) {
		NSError *error = nil;
		if (![url setResourceValue:dict forKey:NSURLQuarantinePropertiesKey error:&error]) {
			AILogWithSignature(@"Error quarantining %@: %@", url, error);
		}
	}
}

- (void)URLSession:(NSURLSession *)inSession downloadTask:(NSURLSessionDownloadTask *)inDownloadTask didFinishDownloadingToURL:(NSURL *)location
{
	/* The file at 'location' is only guaranteed to exist until this method returns,
	 * so it MUST be moved out synchronously, right here, before anything else. */
	NSString *downloadDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString uuid]];
	[[NSFileManager defaultManager] createDirectoryAtPath:downloadDir withIntermediateDirectories:YES attributes:nil error:NULL];

	/* -suggestedFilename derives from Content-Disposition, then the URL, the same way
	 * NSURLDownload's decideDestinationWithSuggestedFilename: argument did; dest must
	 * keep the real archive name because the decompression below dispatches on its
	 * path extension (.tgz/.tar.gz/.zip). */
	NSString *filename = [[inDownloadTask response] suggestedFilename];
	if (![filename length]) filename = [location lastPathComponent];
	self.dest = [downloadDir stringByAppendingPathComponent:filename];
	AILogWithSignature(@"Downloading to is %@", self.dest);

	NSError *moveError = nil;
	if (![[NSFileManager defaultManager] moveItemAtURL:location
												 toURL:[NSURL fileURLWithPath:self.dest]
												 error:&moveError]) {
		AILogWithSignature(@"Could not move %@ to %@: %@", location, self.dest, moveError);
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:AILocalizedString(@"Xtra Downloading Error",nil)];
		[alert setInformativeText:[NSString stringWithFormat:AILocalizedString(@"An error occurred while downloading this Xtra: %@.",nil),[moveError localizedDescription]]];
		[alert addButtonWithTitle:AILocalizedString(@"Cancel",nil)];
		[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
			[self cancel:nil];
		}];
		return;
	}

	NSString		*lastPathComponent = [self.dest lastPathComponent];
	NSString		*pathExtension = [[lastPathComponent pathExtension] lowercaseString];
	BOOL			decompressionSuccess = YES, success = NO;
	
	if ([pathExtension isEqualToString:@"tgz"] || [lastPathComponent hasSuffix:@".tar.gz"]) {
		NSTask			*uncompress, *untar;

		uncompress = [[NSTask alloc] init];
		[uncompress setLaunchPath:@"/usr/bin/gunzip"];
		[uncompress setArguments:[NSArray arrayWithObjects:@"-df" , [self.dest lastPathComponent] ,  nil]];
		[uncompress setCurrentDirectoryPath:[self.dest stringByDeletingLastPathComponent]];
		
		@try
		{
			[uncompress launch];
			[uncompress waitUntilExit];
		}
		@catch(id exc)
		{
			decompressionSuccess = NO;	
		}
			
		[uncompress release];
		
		if (decompressionSuccess) {
			if ([pathExtension isEqualToString:@"tgz"]) {
				self.dest = [[self.dest stringByDeletingPathExtension] stringByAppendingPathExtension:@"tar"];
			} else {
				//hasSuffix .tar.gz
				self.dest = [self.dest substringToIndex:[self.dest length] - 3];//remove the .gz, leaving us with .tar
			}
			
			untar = [[NSTask alloc] init];
			[untar setLaunchPath:@"/usr/bin/tar"];
			[untar setArguments:[NSArray arrayWithObjects:@"-xvf", [self.dest lastPathComponent], nil]];
			[untar setCurrentDirectoryPath:[self.dest stringByDeletingLastPathComponent]];
			
			@try
			{
				[untar launch];
				[untar waitUntilExit];
			}
			@catch(id exc)
			{
				decompressionSuccess = NO;
			}
			[untar release];
		}
		
	} else if ([pathExtension isEqualToString:@"zip"]) {
		NSTask	*unzip;
		
		//First, perform the actual unzipping
		unzip = [[NSTask alloc] init];
		[unzip setLaunchPath:@"/usr/bin/unzip"];
		[unzip setArguments:[NSArray arrayWithObjects:
			@"-o",  /* overwrite */
			@"-q", /* quiet! */
			self.dest, /* source zip file */
			@"-d", [self.dest stringByDeletingLastPathComponent], /*destination folder*/
			nil]];

		[unzip setCurrentDirectoryPath:[self.dest stringByDeletingLastPathComponent]];

		@try
		{
			[unzip launch];
			[unzip waitUntilExit];
		}
		@catch(id exc)
		{
			decompressionSuccess = NO;			
		}
		[unzip release];

	} else {
		decompressionSuccess = NO;
	}
	
	NSFileManager	*fileManager = [NSFileManager defaultManager];
	NSEnumerator	*fileEnumerator;

	//Delete the compressed xtra, now that we've decompressed it
#ifdef DEBUG_BUILD
	if (decompressionSuccess)
		[fileManager removeItemAtPath:self.dest error:NULL];
#else
	[fileManager removeItemAtPath:self.dest error:NULL];
#endif
	
	self.dest = [self.dest stringByDeletingLastPathComponent];
	
	/* NSURLQuarantinePropertiesKey replaces LSCopyItemAttribute/LSSetItemAttribute
	 * (AdiumY pattern). Error semantics: an item that is not quarantined returns YES
	 * with a nil value (the old kLSAttributeNotFoundErr case); NO means the item could
	 * not be inspected at all.
	 */
	NSURL *destURL = [NSURL fileURLWithPath:self.dest];
	NSMutableDictionary *quarantineProperties = nil;
	NSDictionary *oldQuarantineProperties = nil;

	if ([destURL getResourceValue:&oldQuarantineProperties forKey:NSURLQuarantinePropertiesKey error:NULL]) {
		if (oldQuarantineProperties) {
			quarantineProperties = [[oldQuarantineProperties mutableCopy] autorelease];
			AILogWithSignature(@"Old quarantine data: %@", quarantineProperties);
		} else {
			quarantineProperties = [NSMutableDictionary dictionaryWithCapacity:2];
		}

		[quarantineProperties setObject:(NSString *)kLSQuarantineTypeWebDownload
								 forKey:(NSString *)kLSQuarantineTypeKey];

		[quarantineProperties setObject:[[self.downloadTask originalRequest] URL]
								 forKey:(NSString *)kLSQuarantineDataURLKey];

		[self setQuarantineProperties:quarantineProperties forDirectory:destURL];

		AILogWithSignature(@"Quarantined %@ with %@", self.dest, quarantineProperties);

	} else {
		AILogWithSignature(@"Danger! Could not find file to quarantine: %@!", self.dest);
	}
	
	//the remaining files in the directory should be the contents of the xtra
	fileEnumerator = [fileManager enumeratorAtPath:self.dest];

	if (decompressionSuccess && fileEnumerator) {
		NSSet			*supportedDocumentExtensions = [[NSBundle mainBundle] supportedDocumentExtensions];

		for (NSString *nextFile in fileEnumerator) {
			
			/* Ignore hidden files and the __MACOSX folder which some compression engines stick into the archive but
			 * /usr/bin/unzip doesn't handle properly.
			 */
			if ((![[nextFile lastPathComponent] hasPrefix:@"."]) &&
				(![[nextFile pathComponents] containsObject:@"__MACOSX"])) {
				NSString		*fileExtension = [nextFile pathExtension];
				NSEnumerator	*supportedDocumentExtensionsEnumerator;
				NSString		*extension;
				BOOL			isSupported = NO;

				//We want to do a case-insensitive path extension comparison
				supportedDocumentExtensionsEnumerator = [supportedDocumentExtensions objectEnumerator];
				while (!isSupported &&
					   (extension = [supportedDocumentExtensionsEnumerator nextObject])) {
					isSupported = ([fileExtension caseInsensitiveCompare:extension] == NSOrderedSame);
				}

				if (isSupported) {
					NSString *xtraPath = [self.dest stringByAppendingPathComponent:nextFile];

					//Open the file directly
					AILogWithSignature(@"Installing %@",xtraPath);
					success = [[NSApp delegate] application:NSApp
											   openTempFile:xtraPath];

					if (!success) {
						NSLog(@"Installation Error: %@",xtraPath);
					}
				}
			}
		}
		
	} else {
		NSLog(@"Installation Error: %@ (%@)",self.dest, (decompressionSuccess ? @"Decompressed succesfully" : @"Failed to decompress"));
	}
	
	//delete our temporary directory, and any files remaining in it
#ifdef DEBUG_BUILD
	if (success)
		[fileManager removeItemAtPath:self.dest error:NULL];
#else
	[fileManager removeItemAtPath:self.dest error:NULL];
#endif

	[self closeInstaller];
}

@end
