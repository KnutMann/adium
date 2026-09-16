/* The call controller writes to Adium's debug log. A test that compiles it on
 * its own has no Adium around it, so the two functions behind the logging
 * macros print to the terminal instead. */
#import <Foundation/Foundation.h>

BOOL AIDebugLoggingEnabled = YES;

void AILog_impl(NSString *format, ...)
{
	va_list arguments;
	va_start(arguments, format);
	NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
	va_end(arguments);
	fprintf(stderr, "    log: %s\n", [line UTF8String]);
}

void AILogWithSignature_impl(const char *signature, int line, NSString *format, ...)
{
	va_list arguments;
	va_start(arguments, format);
	NSString *text = [[NSString alloc] initWithFormat:format arguments:arguments];
	va_end(arguments);
	fprintf(stderr, "    log: %s\n", [text UTF8String]);
}
