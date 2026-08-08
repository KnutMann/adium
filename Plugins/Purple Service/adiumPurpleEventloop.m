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

#import "adiumPurpleEventloop.h"
#import <poll.h>
#import <unistd.h>
#import <sys/socket.h>
#import <sys/select.h>

#include <dispatch/dispatch.h>
#include <os/lock.h>
#include <stdatomic.h>

//#define PURPLE_SOCKET_DEBUG

/* Plugins such as purple-gowhatsapp and tdlib-purple call purple_timeout_add() from
 * background threads (g_timeout_add is documented as thread-safe), so tag allocation
 * and the tag→source map must be safe for concurrent access.
 */
static _Atomic guint		sourceId = 0;		//The next source key; continuously incrementing
static os_unfair_lock		sourceDictLock = OS_UNFAIR_LOCK_INIT;

static inline guint nextSourceTag(void) {
    return atomic_fetch_add(&sourceId, 1) + 1;
}

/*
 * glib, unfortunately, identifies all sources and timers via unsigned 32 bit tags. We would like to map them to dispatch_source_t objects.
 * So: we make a CFDictionary with all null callbacks (hash on the value of the integer, cast to a void*, and don't retain/release anything).
 * That gives us a guint->dispatch_source_t map, but it's a little gross, so three inline wrapper functions are provided to make things nice:
 * sourceForTag, setSourceForTag, and removeSourceForTag. The names should be self-explanatory. No retains or releases are done by them.
 */
static inline CFMutableDictionaryRef sourceInfoDict() {
    static CFMutableDictionaryRef _sourceInfoDict;
    static dispatch_once_t sourceInfoDictToken;
    dispatch_once(&sourceInfoDictToken, ^{
        static const CFDictionaryKeyCallBacks keyCallbacks = {0, NULL, NULL, NULL, NULL, NULL};
        static const CFDictionaryValueCallBacks valueCallbacks = {0, NULL, NULL, NULL, NULL};
        _sourceInfoDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &valueCallbacks);
    });
    return _sourceInfoDict;
}

static inline dispatch_source_t sourceForTag(unsigned long tag) {
    os_unfair_lock_lock(&sourceDictLock);
    dispatch_source_t source = (dispatch_source_t)CFDictionaryGetValue(sourceInfoDict(), (void *)tag);
    os_unfair_lock_unlock(&sourceDictLock);
    return source;
}
static inline void setSourceForTag(dispatch_source_t source, unsigned long tag) {
    os_unfair_lock_lock(&sourceDictLock);
    CFDictionarySetValue(sourceInfoDict(), (void *)tag, source);
    os_unfair_lock_unlock(&sourceDictLock);
}

/* Atomically look up and remove the source for a tag, so that no two callers can
 * ever cancel/release the same source. Returns NULL if the tag is unknown.
 */
static inline dispatch_source_t claimSourceForTag(unsigned long tag) {
    os_unfair_lock_lock(&sourceDictLock);
    dispatch_source_t source = (dispatch_source_t)CFDictionaryGetValue(sourceInfoDict(), (void *)tag);
    if (source) {
        CFDictionaryRemoveValue(sourceInfoDict(), (void *)tag);
    }
    os_unfair_lock_unlock(&sourceDictLock);
    return source;
}

gboolean adium_source_remove(guint tag) {
	dispatch_source_t src = claimSourceForTag(tag);

    if (!src) {
		AILogWithSignature(@"Source info for %i not found", tag);
		return FALSE;
	}

    dispatch_source_cancel(src);

	BOOL success = (dispatch_source_testcancel(src) != 0);

	dispatch_release(src);

	return success;
}

//Like g_source_remove, return TRUE if successful, FALSE if not
gboolean adium_timeout_remove(guint tag) {
    return adium_source_remove(tag);
}

/* Extra function to generalize adium_timeout_add and adium_timeout_add_seconds,
 * making the permitted leeway explicit.
 */
guint addTimer(uint64_t interval, uint64_t leeway, GSourceFunc function, gpointer data)
{
	dispatch_source_t src;
	guint tag;
	
    tag = nextSourceTag();
    
    src = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	
    dispatch_source_set_timer(src, dispatch_time(DISPATCH_TIME_NOW, interval), interval, leeway);
	
    setSourceForTag(src, tag);
	
    dispatch_source_set_event_handler(src, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

		if (sourceForTag(tag)) {
            if (!function || !function(data)) {
                adium_timeout_remove(tag);
            }
        } else {
			AILogWithSignature(@"Timer with tag %i was already canceled!", tag);
		}
  
        [pool drain];
    });
	
    dispatch_resume(src);

    return tag;
}

// Add a timer in miliseconds
guint adium_timeout_add(guint interval, GSourceFunc function, gpointer data)
{
	return addTimer(((uint64_t)interval) * NSEC_PER_MSEC, NSEC_PER_USEC, function, data);
}

// Add a timer in seconds (allowing more leeway, therefore allowing the OS to group events and save power)
guint adium_timeout_add_seconds(guint interval, GSourceFunc function, gpointer data)
{
	return addTimer(((uint64_t)interval) * NSEC_PER_SEC, NSEC_PER_SEC, function, data);
}

guint adium_input_add(gint fd, PurpleInputCondition condition,
					  PurpleInputFunction func, gpointer user_data)
{	
	if (fd < 0) {
		guint invalidTag = nextSourceTag();
		NSLog(@"INVALID: fd was %i; returning tag %i",fd,invalidTag);
		return invalidTag;
	}

	dispatch_source_t src;
	guint tag;
	dispatch_source_type_t type;
	
    tag = nextSourceTag();
	
	if (condition == PURPLE_INPUT_READ) {
		type = DISPATCH_SOURCE_TYPE_READ;
	} else {
		type = DISPATCH_SOURCE_TYPE_WRITE;
	}
	
    src = dispatch_source_create(type, fd, 0, dispatch_get_main_queue());
	
    dispatch_source_set_event_handler(src, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        if (func) func(user_data, fd, condition);
        [pool drain];
    });
		
    setSourceForTag(src, tag);

	dispatch_resume(src);
	
    return tag;
}

int adium_input_get_error(int fd, int *error)
{
	int		  ret;
	socklen_t len;
	len = sizeof(*error);
	
	ret = getsockopt(fd, SOL_SOCKET, SO_ERROR, error, &len);
	if (!ret && !(*error)) {
		/*
		 * Taken from Fire's FaimP2PConnection.m:
		 * The job of this function is to detect if the connection failed or not
		 * There has to be a better way to do this
		 *
		 * Any socket that fails to connect will select for reading and writing
		 * and all reads and writes will fail
		 * Any listening socket will select for reading, and any read will fail
		 * So, select for writing, if you can write, and the write fails, not connected
		 */
		
		{
			fd_set thisfd;
			struct timeval timeout;
			
			FD_ZERO(&thisfd);
			FD_SET(fd, &thisfd);
			timeout.tv_sec = 0;
			timeout.tv_usec = 0;
			select(fd+1, NULL, &thisfd, NULL, &timeout);
			if(FD_ISSET(fd, &thisfd)){
				ssize_t length = 0;
				char buffer[4] = {0, 0, 0, 0};
				
				length = write(fd, buffer, length);
				if(length == -1)
				{
					/* Not connected */
					ret = -1;
					*error = ENOTCONN;
					AILog(@"adium_input_get_error(%i): Socket is NOT valid", fd);
				}
			}
		}
	}

	return ret;
}

static PurpleEventLoopUiOps adiumEventLoopUiOps = {
    adium_timeout_add,
    adium_timeout_remove,
    adium_input_add,
    adium_source_remove,
	adium_input_get_error,
	adium_timeout_add_seconds,
	/* _purple_reserved2 */ NULL,
	/* _purple_reserved3 */ NULL,
	/* _purple_reserved4 */ NULL
};

PurpleEventLoopUiOps *adium_purple_eventloop_get_ui_ops(void)
{
	return &adiumEventLoopUiOps;
}
