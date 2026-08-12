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


/*!
 * @class AdiumApplescriptRunner
 * @brief Runs AppleScripts on a worker queue and hands the result back on the main thread
 *
 * This used to hand the script off to a separate helper process via NSDistributedNotificationCenter,
 * launched with Carbon's LSOpenFromRefSpec. The helper no longer exists (and has not existed since
 * the sources for it were removed), which meant every script silently did nothing at all. Since
 * 10.6 NSAppleScript is thread-safe, so we simply run the script ourselves on a background queue --
 * one process less to build, sign, notarize and lose.
 */
@interface AdiumApplescriptRunner : NSObject {
	NSOperationQueue	*scriptQueue;
}

/*!
 * @brief Run an AppleScript, optionally calling a named handler with arguments
 *
 * The callback is of the form -<selector>:(id)userInfo resultString:(NSString *)resultString, and
 * we guarantee three things about it, because the outgoing message pipeline now depends on them:
 *
 * 1. It happens EXACTLY ONCE and ALWAYS -- even if the path is nil, the file cannot be loaded, the
 *    script does not compile, the handler does not exist, or the script dies at runtime. In those
 *    cases resultString is simply nil. Delayed content filters hang the chat's send queue forever
 *    if nobody ever tells them the script is done, so there is no error path which stays silent.
 * 2. It NEVER happens synchronously from within this call. The caller registers its pending
 *    operation only after we return (see AdiumContentFiltering.m, where the tracking dictionary is
 *    stored at :343 but the filter is invoked at :318) -- a synchronous completion would be looked
 *    up before it was ever recorded and swallowed without a trace.
 * 3. It happens on the main thread, because the callbacks mutate NSMutableAttributedStrings and
 *    poke NSTextViews.
 *
 * target == nil / selector == NULL are legal (the AppleScript contact alert uses them) and simply
 * mean: run the script, don't tell anyone.
 *
 * @param path Full path to the compiled script.
 * @param function Name of a handler to call; if nil or empty, the whole script is run instead.
 * @param arguments NSStrings to pass to the handler; may be nil.
 * @param target Object to notify when the script is done; may be nil.
 * @param selector Selector to call on target; may be NULL.
 * @param userInfo Passed back as the first argument of the callback; may be nil.
 */
- (void)runApplescriptAtPath:(NSString *)path
					function:(NSString *)function
				   arguments:(NSArray *)arguments
			 notifyingTarget:(id)target
					selector:(SEL)selector
					userInfo:(id)userInfo;
@end
