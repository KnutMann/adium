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

#import "AdiumApplescriptRunner.h"

/* We need exactly four four-character codes out of OpenScripting to build an Apple event which calls
 * a named handler. Defining them here is cheaper than dragging all of Carbon.h into every file which
 * happens to include AIUtilities; the old out-of-process runner made the same trade.
 */
enum {
	AIAppleScriptSuite		= 'ascr',	//kASAppleScriptSuite
	AISubroutineEvent		= 'psbr',	//kASSubroutineEvent
	AISubroutineNameParam	= 'snam',	//keyASSubroutineName
	AIDirectObjectParam		= '----'	//keyDirectObject
};
enum {
	AIAutoGenerateReturnID	= -1,		//kAutoGenerateReturnID
	AIAnyTransactionID		= 0			//kAnyTransactionID
};

/*!
 * @brief Build an Apple event which calls a named handler within a script
 */
static NSAppleEventDescriptor *AIEventCallingHandler(NSString *handlerName, NSArray *arguments)
{
	NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:AIAppleScriptSuite
																			eventID:AISubroutineEvent
																   targetDescriptor:[NSAppleEventDescriptor nullDescriptor]
																		   returnID:AIAutoGenerateReturnID
																	  transactionID:AIAnyTransactionID];

	/* The handler name must be lowercase: AppleScript folds identifiers to lowercase internally, so
	 * asking for "Substitute" would not find a handler named substitute.
	 */
	[event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:[handlerName lowercaseString]]
				   forKeyword:AISubroutineNameParam];

	/* Arguments travel as an Apple event list in the direct object. If there are none we must leave
	 * the parameter off entirely, otherwise the signature no longer matches a handler declared as
	 * 'on substitute()' -- which is exactly how the shipped /chuck script declares it.
	 */
	if ([arguments count]) {
		NSAppleEventDescriptor	*list = [NSAppleEventDescriptor listDescriptor];
		NSInteger				 i = 1;

		for (NSString *anArgument in arguments) {
			[list insertDescriptor:[NSAppleEventDescriptor descriptorWithString:anArgument]
						   atIndex:i++];
		}

		[event setParamDescriptor:list forKeyword:AIDirectObjectParam];
	}

	return event;
}

/*!
 * @brief Load and run a script, returning its result as a string
 *
 * Deliberately a plain C function rather than a method: the block below must not keep the runner
 * alive after -controllerWillClose has already released it.
 *
 * @param outErrorDescription If non-NULL, filled with a human-readable reason on failure.
 * @result The script's result, or nil if it produced none or failed.
 */
static NSString *AIRunAppleScript(NSString *path, NSString *function, NSArray *arguments, NSString **outErrorDescription)
{
	if (![path length]) {
		if (outErrorDescription) *outErrorDescription = @"No script path was given";
		return nil;
	}

	NSDictionary	*errorInfo = nil;
	NSAppleScript	*script = [[NSAppleScript alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]
																	error:&errorInfo];

	if (!script) {
		if (outErrorDescription) {
			*outErrorDescription = [errorInfo objectForKey:NSAppleScriptErrorBriefMessage];
			if (!*outErrorDescription) *outErrorDescription = [errorInfo description];
			if (!*outErrorDescription) *outErrorDescription = @"The script could not be loaded";
		}
		return nil;
	}

	NSAppleEventDescriptor	*result;

	if ([function length]) {
		result = [script executeAppleEvent:AIEventCallingHandler(function, arguments) error:&errorInfo];
	} else {
		//No handler name means: run the whole script. The AppleScript contact alert works this way.
		result = [script executeAndReturnError:&errorInfo];
	}

	//Hold on to the result past the release of the script which produced it
	NSString	*resultString = [[[result stringValue] retain] autorelease];

	/* Keyed off resultString rather than result, because the caller cannot tell the two apart: a run
	 * which succeeded but produced no text leaves the keyword standing exactly like a failed one.
	 * That is the case which used to be completely silent -- a 'substitute' handler which falls off
	 * its end, or returns 'missing value' -- and it is the one the script's author most needs told.
	 */
	if (!resultString && outErrorDescription) {
		if (result) {
			*outErrorDescription = [NSString stringWithFormat:@"The script ran but returned no text (descriptor type %u)",
									(unsigned)[result descriptorType]];
		} else {
			*outErrorDescription = [errorInfo objectForKey:NSAppleScriptErrorBriefMessage];
			if (!*outErrorDescription) *outErrorDescription = [errorInfo description];
			if (!*outErrorDescription) *outErrorDescription = @"The script failed for an unknown reason";
		}
	}

	[script release];

	return resultString;
}

@implementation AdiumApplescriptRunner

- (id)init
{
	if ((self = [super init])) {
		scriptQueue = [[NSOperationQueue alloc] init];
		[scriptQueue setName:@"im.adium.applescript"];

		/* A serial queue would be closest to the old behaviour (one helper process meant everything
		 * ran one after another), but a script which hangs -- say, an Apple event to a frozen
		 * application -- would then pile every later script up behind it. NSAppleScript has been
		 * thread-safe since 10.6 as long as the same instance is not used from two threads at once,
		 * and we create a fresh one per run.
		 */
		[scriptQueue setMaxConcurrentOperationCount:4];
		[scriptQueue setQualityOfService:NSQualityOfServiceUserInitiated];
	}

	return self;
}

- (void)dealloc
{
	/* No -waitUntilAllOperationsAreFinished: a script which never returns must not be able to hold
	 * up quitting.
	 */
	[scriptQueue release]; scriptQueue = nil;

	[super dealloc];
}

/*!
 * @brief Run an applescript, optionally calling a function with arguments, and notify a target/selector with its output when it is done
 */
- (void)runApplescriptAtPath:(NSString *)path function:(NSString *)function arguments:(NSArray *)arguments notifyingTarget:(id)target selector:(SEL)selector userInfo:(id)userInfo
{
	/* There is deliberately no early return anywhere in here. Every possible outcome -- including a
	 * nil path -- has to end in the callback below, because a delayed content filter which never
	 * hears back blocks the chat's send queue for good.
	 *
	 * Memory management, since this is not ARC: target and userInfo are held by hand rather than by
	 * block capture. A block retains what it captures and releases it when the block itself dies --
	 * and the operation's block dies on a worker thread, whenever the queue gets around to it. If
	 * both blocks held a reference, the last release would land on whichever thread finished last.
	 * That is a coin toss we must not take: ESSafariLinkToolbarItemPlugin passes an NSTextView as
	 * userInfo, and an AppKit object deallocated off the main thread is a crash looking for an
	 * excuse. __block object variables are NOT retained by a block under manual retain/release, so
	 * the pair below is the only claim on these objects, and it is given up on the main thread.
	 *
	 * path, function and arguments are plain strings and arrays; ordinary capture is fine for them.
	 */
	__block id	blockTarget = [target retain];
	__block id	blockUserInfo = [userInfo retain];

	[scriptQueue addOperationWithBlock:^{
		NSAutoreleasePool	*pool = [[NSAutoreleasePool alloc] init];
		NSString			*errorDescription = nil;
		NSString			*resultString = nil;

		/* Swallowed rather than rethrown, and deliberately not @finally: an exception must not be
		 * allowed to skip the callback (the promise in the header is what the send pipeline hangs
		 * on), and unwinding out of here would take the worker thread with it. Releasing the pool
		 * while an exception is in flight is its own kind of trouble, so we catch instead.
		 */
		@try {
			resultString = AIRunAppleScript(path, function, arguments, &errorDescription);
		}
		@catch (NSException *exception) {
			errorDescription = [NSString stringWithFormat:@"%@: %@", [exception name], [exception reason]];
		}

		//Make failures visible; they used to be entirely silent, which is how this went unnoticed for years
		if (errorDescription) {
			NSLog(@"AdiumApplescriptRunner: %@ (%@)", errorDescription, path);
		}

		/* Back to the main thread: the callbacks mutate attributed strings and touch views. This
		 * block is copied -- and so retains resultString -- before the pool below is drained.
		 */
		[[NSOperationQueue mainQueue] addOperationWithBlock:^{
			if (blockTarget && selector) {
				[blockTarget performSelector:selector withObject:blockUserInfo withObject:resultString];
			}

			[blockTarget release]; blockTarget = nil;
			[blockUserInfo release]; blockUserInfo = nil;
		}];

		[pool release];
	}];
}

@end
