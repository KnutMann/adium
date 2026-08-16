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

#import <Adium/AIDebugControllerProtocol.h>
#import <stdarg.h>
#import <stdlib.h>
#import <stdio.h>
#import <execinfo.h>
#import <pthread.h>
#import <AIUtilities/AIDateFormatterAdditions.h>

#ifdef DEBUG_BUILD
BOOL AIDebugLoggingEnabled = YES;
#else
BOOL AIDebugLoggingEnabled = NO;
#endif

NSString *const AIDebugLoggingEnabledNotification = @"AIDebugLoggingEnabledNotification";

void AIEnableDebugLogging(void)
{
	AIDebugLoggingEnabled = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:AIDebugLoggingEnabledNotification object:nil];
}

BOOL AIDebugLoggingIsEnabled(void)
{
	return AIDebugLoggingEnabled;	
}

/*!
 * @brief Adium debug log function
 *
 * Prints a message to the Adium debug window, which is only enabled in Debug builds or by a hidden preference.  
 *
 * @param format A printf-style format string
 * @param ... 0 or more arguments to the format string
 */
void AIAddDebugMessage(NSString *debugMessage)
{
	/* Session debugging aid: mirror to stderr when ADIUM_PURPLE_DEBUG is set. */
	static int mirrorToStderr = -1;
	if (mirrorToStderr == -1) mirrorToStderr = (getenv("ADIUM_PURPLE_DEBUG") != NULL);
	if (mirrorToStderr) fprintf(stderr, "[AILog] %s\n", [debugMessage UTF8String]);

	/* One of these per debug line, from whichever thread wrote it, so the formatter is made once and
	 * never touched again afterwards. */
	static NSDateFormatter *timeFormatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		timeFormatter = [[NSDateFormatter ai_fixedFormatterWithFormat:@"HH:mm:ss': '" timeZone:nil] retain];
	});

	NSString *actualMessage = [[timeFormatter stringFromDate:[NSDate date]] stringByAppendingString:debugMessage];
	
	/* Be careful; we should only modify debugLogArray and the windowController's view on the main thread. */
	if ([NSRunLoop currentRunLoop] == [NSRunLoop mainRunLoop]) {
		[adium.debugController addMessage:actualMessage];

	} else {
		[adium.debugController performSelectorOnMainThread:@selector(addMessage:)
																		   withObject:actualMessage
																		waitUntilDone:NO];		
	}
}

void AILog_impl (NSString *format, ...) {
	va_list		ap; /* Points to each unamed argument in turn */
	NSString	*debugMessage;
	
	va_start(ap, format); /* Make ap point to the first unnamed argument */
	
	debugMessage = [[NSString alloc] initWithFormat:format
										  arguments:ap];
	AIAddDebugMessage(debugMessage);
	[debugMessage release];

	va_end(ap); /* clean up when done */
}

void AILogWithSignature_impl(const char *name, int line, NSString *format, ...) {
	va_list		ap; /* Points to each unamed argument in turn */
	NSString	*debugMessage, *actualMessage;
	const char	*queue = NULL;
	
	/* Purely diagnostic queue label for the log line. dispatch_get_current_queue() is
	 * deprecated; DISPATCH_CURRENT_QUEUE_LABEL is the supported way to get the current
	 * queue's label, and pthread_main_np() approximates the old "not on the main queue"
	 * check (the main queue only ever runs on the main thread).
	 */
	if (!pthread_main_np()) {
		queue = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
	}
	
	va_start(ap, format); /* Make ap point to the first unnamed argument */
	
	debugMessage = [[NSString alloc] initWithFormat:format
										  arguments:ap];
	if (!queue)
		actualMessage = [NSString stringWithFormat:@"%s:%d: %@", name, line, debugMessage];
	else
		actualMessage = [NSString stringWithFormat:@"%s:%d: (on %s) %@", name, line, (queue ?: ""), debugMessage];
	AIAddDebugMessage(actualMessage);
	[debugMessage release];
	
	va_end(ap); /* clean up when done */
}

void AILogWithPrefix_impl (const char *prefix, NSString *format, ...) {
	va_list		ap; /* Points to each unamed argument in turn */
	NSString	*debugMessage, *actualMessage;
	
	va_start(ap, format); /* Make ap point to the first unnamed argument */
	
	debugMessage = [[NSString alloc] initWithFormat:format
										  arguments:ap];
	actualMessage = [NSString stringWithFormat:@"%s: %@", prefix, debugMessage];
	AIAddDebugMessage(actualMessage);
	[debugMessage release];

	va_end(ap); /* clean up when done */
}

void AILogBacktrace_impl(void) {
	void* callstack[128];
	int i, frames = backtrace(callstack, 128);
	char** strs = backtrace_symbols(callstack, frames);
	NSMutableString *str = [NSMutableString string];
	for (i = 0; i < frames; ++i) {
		[str appendFormat:@"%s\n", strs[i]];
	}
	free(strs);	
	AILog_impl(@"%@", str);
};

//For compatibility with plugins that expect these symbols to exist
#undef AILog
#undef AILogWithPrefix
#undef AILogWithBacktrace
void AILog(NSString *fmt, ...) {}
void AILogWithPrefix(const char *signature, NSString *fmt, ...) {}
void AILogWithBacktrace(void) {}
