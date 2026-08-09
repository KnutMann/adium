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
 * @brief Cocoa wrapper for accessing the system keychain
 */

#import "AIKeychain.h"
#import "AIStringAdditions.h"
#import <CoreServices/CoreServices.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>

static AIKeychain *lastKnownDefaultKeychain = nil;

#define AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err) \
	NSLocalizedStringFromTableInBundle([[NSNumber numberWithLong:(err)] stringValue], @"SecErrorMessages", [NSBundle bundleWithIdentifier:@"com.apple.security"], /* comment */ nil)

@implementation AIKeychain

+ (BOOL)lockAllKeychains_error:(out NSError **)outError
{
	OSStatus err = SecKeychainLockAll();
	
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainLockAll], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainLockAll", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}
		
		*outError = error;
	}
	
	return (err == noErr);
}

+ (BOOL)lockDefaultKeychain_error:(out NSError **)outError
{
	OSStatus err = SecKeychainLock(/* keychain */ NULL);
	
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainLock], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainLock", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}
		
		*outError = error;
	}
	
	return (err == noErr);
}

+ (BOOL)unlockDefaultKeychain_error:(out NSError **)outError
{
	OSStatus err = SecKeychainUnlock(/* keychain */ NULL, /* passwordLength */ 0, /* password */ NULL, /* usePassword */ false);
	
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainUnlock], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainUnlock", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}
		
		*outError = error;
	}
	
	return (err == noErr);
}

+ (BOOL)unlockDefaultKeychainWithPassword:(NSString *)password error:(out NSError **)outError
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding];
	NSAssert( UINT_MAX >= [data length], @"Attempting to send more data than Keychain can handle.  Abort." );
	OSStatus err = SecKeychainUnlock(/* keychain */ NULL, (UInt32)[data length], [data bytes], /* usePassword */ true);

	[pool release];

	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainUnlock], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainUnlock", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}
		
		*outError = error;
	}

	return (err == noErr);
}

+ (BOOL)allowsUserInteraction_error:(out NSError **)outError
{
	Boolean state = false;

	OSStatus err = SecKeychainGetUserInteractionAllowed(&state);

	if (outError) {
		NSError *error = nil;

		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainGetUserInteractionAllowed], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainGetUserInteractionAllowed", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}
		
		*outError = error;
	}

	return state;
}

+ (BOOL)setAllowsUserInteraction:(BOOL)flag error:(out NSError **)outError
{
	OSStatus err = SecKeychainSetUserInteractionAllowed(flag);
	
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainSetUserInteractionAllowed], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainSetUserInteractionAllowed", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				[NSNumber numberWithBool:flag], AIKEYCHAIN_ERROR_USERINFO_USERINTERACTIONALLOWEDSTATE,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}
		
		*outError = error;
	}
	
	return (err == noErr);
}

+ (u_int32_t)keychainServicesVersion_error:(out NSError **)outError
{
	UInt32 version;
	// Will this function EVER return an error? well, it can, so we should be prepared for it. --boredzo
	OSStatus err = SecKeychainGetVersion(&version);
	
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainGetVersion], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainGetVersion", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}

		*outError = error;
	}

	return version;
}

#pragma mark -

+ (SecKeychainRef)copyDefaultSecKeychainRef_error:(out NSError **)outError
{
	SecKeychainRef aKeychainRef = NULL;

	OSStatus err = SecKeychainCopyDefault(&aKeychainRef);

	if (err != noErr) {
		if (err == errSecNoDefaultKeychain) {
			/* XXX - SecKeychainCreate() to an appropriate path here, followed by SecKeychainSetDefault(), would
			 * be very nice.  However, it really should not be necessary in general, since a default keychain is created
			 * at login. The only way we can get here is if the user deleted his default keychain during this OS X session
			 * and didn't create a new one.  He may not deserve password storage, anyways.
			 */
		}
		
		if (err != errSecNoDefaultKeychain) {
			if (outError) {
				NSError *error = nil;

				if (err != noErr) {
					NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
						[NSValue valueWithPointer:SecKeychainCopyDefault], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
						@"SecKeychainCopyDefault", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
						AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
						nil];
					error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
				}
				
				*outError = error;
			}
		}
		
		if (aKeychainRef) {
			CFRelease(aKeychainRef);
		}

		return nil;
	}
	
	return aKeychainRef;
}

+ (AIKeychain *)defaultKeychain_error:(out NSError **)outError
{
	// Ensure there is a default keychain which can be accessed
	SecKeychainRef aKeychainRef = [self copyDefaultSecKeychainRef_error:outError];

	if (aKeychainRef) {
		if (!lastKnownDefaultKeychain ||
			([lastKnownDefaultKeychain keychainRef] && (aKeychainRef != [lastKnownDefaultKeychain keychainRef]))) {
			[lastKnownDefaultKeychain release];
			lastKnownDefaultKeychain = [[self alloc] init];
		}

		CFRelease(aKeychainRef);

		return [[lastKnownDefaultKeychain retain] autorelease];

	} else {
		NSLog(@"No default keychain!");
		return nil;
	}
}

+ (BOOL)setDefaultKeychain:(AIKeychain *)newDefaultKeychain error:(out NSError **)outError
{
	NSParameterAssert(newDefaultKeychain != nil);

	OSStatus err = ([newDefaultKeychain keychainRef] ? SecKeychainSetDefault([newDefaultKeychain keychainRef]) : noErr);
	
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainSetDefault], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainSetDefault", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}
		
		*outError = error;
	}
	
	if (err == noErr) {
		[lastKnownDefaultKeychain release];
		lastKnownDefaultKeychain = [newDefaultKeychain retain];
	}
	
	return (err == noErr);
}

+ (AIKeychain *)keychainWithContentsOfFile:(NSString *)path error:(out NSError **)outError
{
	return [[[self alloc] initWithContentsOfFile:path error:outError] autorelease];
}

- (id)initWithContentsOfFile:(NSString *)path error:(out NSError **)outError
{
	if ((self = [super init])) {
		OSStatus err = SecKeychainOpen([path fileSystemRepresentation], &keychainRef);
		
		if (outError) {
			NSError *error = nil;

			if (err != noErr) {
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
					[NSValue valueWithPointer:SecKeychainOpen], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
					@"SecKeychainOpen", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
					AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
					nil];
				error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
			}

			*outError = error;
		}
		
		if (err != noErr) {
			[self release]; self = nil;
		}
	}

	return self;
}

// SecKeychainCreate

+ (AIKeychain *)keychainWithPath:(NSString *)path password:(NSString *)password promptUser:(BOOL)prompt initialAccess:(SecAccessRef)initialAccess error:(out NSError **)outError
{
	return [[[self alloc] initWithPath:path password:password promptUser:prompt initialAccess:initialAccess error:outError] autorelease];
}

- (id)initWithPath:(NSString *)path password:(NSString *)password promptUser:(BOOL)prompt initialAccess:(SecAccessRef)initialAccess error:(out NSError **)outError
{
	if ((self = [super init])) {
		/* We create our own copy of the string (if any) using NSString to ensure that the NSData that we create is an NSData.
		 * We create our own pool to ensure that both objects are released ASAP.
		 */
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

		void     *passwordBytes  = NULL;
		u_int32_t passwordLength = 0;

		if (password) {
			NSData  *data = [password dataUsingEncoding:NSUTF8StringEncoding];
			passwordBytes      = (void *)[data bytes];
			NSAssert( UINT_MAX >= [data length], @"Attempting to send more data than Keychain can handle.  Abort." );
			passwordLength     = (UInt32)[data length];
		}

		OSStatus err = SecKeychainCreate([path fileSystemRepresentation], passwordLength, passwordBytes, prompt, initialAccess, &keychainRef);

		[pool release];

		if (outError) {
			NSError *error = nil;
			if (err != noErr) {
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
					[NSValue valueWithPointer:SecKeychainCreate], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
					@"SecKeychainCreate", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
					AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
					nil];
				error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
			}

			*outError = error;
		}

		if (err != noErr) {
			[self release];
			self = nil;
		}

	}

	return self;
}

+ (AIKeychain *)keychainWithKeychainRef:(SecKeychainRef)newKeychainRef
{
	return [[[self alloc] initWithKeychainRef:newKeychainRef] autorelease];
}

- (id)initWithKeychainRef:(SecKeychainRef)newKeychainRef
{
	if ((self = [super init])) {
		keychainRef = (newKeychainRef ? (SecKeychainRef)CFRetain(newKeychainRef) : NULL);
	}

	return self;
}

#pragma mark -

- (BOOL)getSettings:(out struct SecKeychainSettings *)outSettings error:(out NSError **)outError
{
	NSParameterAssert(outSettings != NULL);
	SecKeychainRef targetKeychainRef = (keychainRef ? (SecKeychainRef)CFRetain(keychainRef) : NULL);

	if (!targetKeychainRef) {
		targetKeychainRef = [[self class] copyDefaultSecKeychainRef_error:outError];
	}

	if (targetKeychainRef) {
		OSStatus err = SecKeychainCopySettings(targetKeychainRef, outSettings);
		
		if (outError) {
			NSError *error = nil;
			
			if (err != noErr) {
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
					[NSValue valueWithPointer:outSettings], AIKEYCHAIN_ERROR_USERINFO_SETTINGSPOINTER,
					[NSValue valueWithPointer:SecKeychainCopySettings], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
					@"SecKeychainCopySettings", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
					AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
					nil];
				error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
			}

			*outError = error;
		}
		
		CFRelease(targetKeychainRef);
		
		return (err == noErr);
	}
	
	return NO;
}

- (BOOL)setSettings:(in struct SecKeychainSettings *)newSettings error:(out NSError **)outError
{
	NSParameterAssert(newSettings != NULL);
	// If keychainRef is NULL, we'll get the default keychain's settings
	OSStatus err = SecKeychainSetSettings(keychainRef, newSettings);
	
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:newSettings], AIKEYCHAIN_ERROR_USERINFO_SETTINGSPOINTER,
				[NSValue valueWithPointer:SecKeychainSetSettings], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainSetSettings", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}

		*outError = error;
	}
	
	return (err == noErr);
}

- (SecKeychainStatus)status_error:(out NSError **)outError
{
	SecKeychainStatus status;
	// If keychainRef is NULL, we'll get the default keychain's status
	OSStatus err = SecKeychainGetStatus(keychainRef, &status);
	
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainGetStatus], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainGetStatus", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}

		*outError = error;
	}

	return status;
}

- (char *)getPathFileSystemRepresentation:(out char *)outBuf length:(inout u_int32_t *)outLength error:(out NSError **)outError
{
	NSParameterAssert(outBuf != NULL);
	NSParameterAssert((outLength != NULL) && (*outLength > 0));

	SecKeychainRef targetKeychainRef = (keychainRef ? (SecKeychainRef)CFRetain(keychainRef) : NULL);
	
	if (!targetKeychainRef) {
		targetKeychainRef = [[self class] copyDefaultSecKeychainRef_error:outError];
	}

	if (targetKeychainRef) {		
		OSStatus err = SecKeychainGetPath(targetKeychainRef, (UInt32 *)outLength, outBuf);
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainGetPath], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainGetPath", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				[NSValue valueWithPointer:targetKeychainRef], AIKEYCHAIN_ERROR_USERINFO_KEYCHAIN,
				nil];
			
			if (outError) {
				error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
			}

			outBuf = NULL;
		}
		
		if (outError) {
			*outError = error;
		}

		CFRelease(targetKeychainRef);

	} else {
		outBuf = NULL;	
	}

	return outBuf;
}

- (NSString *)path
{
	NSMutableData *data = [NSMutableData dataWithLength:PATH_MAX];
	u_int32_t size = PATH_MAX;
	[self getPathFileSystemRepresentation:[data mutableBytes]
								   length:&size
									error:NULL];
	[data setLength:size];

	return [NSString stringWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark -

- (BOOL)lockKeychain_error:(out NSError **)outError
{
	// If keychainRef is NULL, the default keychain will locked
	OSStatus err = SecKeychainLock(keychainRef);
	
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainLock], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainLock", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				[NSValue valueWithPointer:keychainRef], AIKEYCHAIN_ERROR_USERINFO_KEYCHAIN,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}

		*outError = error;
	}
	
	return (err == noErr);
}

- (BOOL)unlockKeychain_error:(out NSError **)outError
{
	// If keychainRef is NULL, the default keychain will unlocked
	OSStatus err = SecKeychainUnlock(keychainRef, /* passwordLength */ 0, /* password */ NULL, /* usePassword */ false);
	
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainUnlock], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainUnlock", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				[NSValue valueWithPointer:keychainRef], AIKEYCHAIN_ERROR_USERINFO_KEYCHAIN,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}

		*outError = error;
	}

	return (err == noErr);
}

- (BOOL)unlockKeychainWithPassword:(NSString *)password error:(out NSError **)outError
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding];
	
	// If keychainRef is NULL, the default keychain will unlocked
	NSAssert( UINT_MAX >= [data length], @"Attempting to send more data than Keychain can handle.  Abort." );
	OSStatus err = SecKeychainUnlock(keychainRef, (UInt32)[data length], [data bytes], /* usePassword */ true);

	[pool release];

	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainUnlock], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainUnlock", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				[NSValue valueWithPointer:keychainRef], AIKEYCHAIN_ERROR_USERINFO_KEYCHAIN,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}

		*outError = error;
	}

	return (err == noErr);
}

#pragma mark -

- (BOOL)deleteKeychain_error:(out NSError **)outError
{
	SecKeychainRef targetKeychainRef = (keychainRef ? (SecKeychainRef)CFRetain(keychainRef) : NULL);
	
	if (!targetKeychainRef) {
		targetKeychainRef = [[self class] copyDefaultSecKeychainRef_error:outError];
	}
	
	if (targetKeychainRef) {				
		/* In 10.2, passing NULL to SecKeychainDelete deletes the default keychain
		 * In 10.3+, passing NULL returns errSecInvalidKeychain
		 */
		OSStatus err = SecKeychainDelete(targetKeychainRef);

		if (outError) {
			NSError *error = nil;
			if (err != noErr) {
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
					[NSValue valueWithPointer:SecKeychainDelete], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
					@"SecKeychainDelete", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
					AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
					[NSValue valueWithPointer:targetKeychainRef], AIKEYCHAIN_ERROR_USERINFO_KEYCHAIN,
					nil];
				error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
			}

			*outError = error;
		}

		CFRelease(targetKeychainRef);
		
		return (err == noErr);
	}
	
	return NO;
}

#pragma mark -
#pragma mark SecItem backend

/* SecItem-based backend for the internet-password methods. The legacy SecKeychain*
 * functions are deprecated; SecItem* operates on the same login keychain items.
 * kSecAttrProtocol values are the four-character protocol codes as strings, which
 * matches what the legacy API stored (e.g. 'AdIM' -> "AdIM"). */
static NSString *AIKeychainProtocolString(SecProtocolType protocol)
{
	if (!protocol) return nil;
	char code[4] = {
		(char)((protocol >> 24) & 0xFF),
		(char)((protocol >> 16) & 0xFF),
		(char)((protocol >> 8) & 0xFF),
		(char)(protocol & 0xFF)
	};
	return [[[NSString alloc] initWithBytes:code length:4 encoding:NSMacOSRomanStringEncoding] autorelease];
}

static NSMutableDictionary *AIKeychainInternetPasswordQuery(NSString *server, NSString *domain, NSString *account, NSString *path, u_int16_t port, SecProtocolType protocol)
{
	NSMutableDictionary *query = [NSMutableDictionary dictionaryWithObject:(NSString *)kSecClassInternetPassword
																	forKey:(NSString *)kSecClass];
	if (server)  [query setObject:server forKey:(NSString *)kSecAttrServer];
	if (domain)  [query setObject:domain forKey:(NSString *)kSecAttrSecurityDomain];
	if (account) [query setObject:account forKey:(NSString *)kSecAttrAccount];
	if (path && [path length]) [query setObject:path forKey:(NSString *)kSecAttrPath];
	if (port)    [query setObject:[NSNumber numberWithUnsignedShort:port] forKey:(NSString *)kSecAttrPort];
	NSString *protocolString = AIKeychainProtocolString(protocol);
	if (protocolString) [query setObject:protocolString forKey:(NSString *)kSecAttrProtocol];
	return query;
}

static NSError *AIKeychainErrorForStatus(OSStatus err, NSString *functionName, NSString *server, NSString *account)
{
	if (err == errSecSuccess) return nil;
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
		functionName, AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
		AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
		(server ? server : @""),  AIKEYCHAIN_ERROR_USERINFO_SERVER,
		(account ? account : @""), AIKEYCHAIN_ERROR_USERINFO_ACCOUNT,
		nil];
	return [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
}

#pragma mark -

- (BOOL)addInternetPassword:(NSString *)password
				  forServer:(NSString *)server
			 securityDomain:(NSString *)domain	// Can pass nil
					account:(NSString *)account
					   path:(NSString *)path
					   port:(u_int16_t)port		// Can pass 0
				   protocol:(SecProtocolType)protocol
		 authenticationType:(SecAuthenticationType)authType
			   keychainItem:(out SecKeychainItemRef *)outKeychainItem
					  error:(out NSError **)outError
{
	NSParameterAssert(password != nil);
	NSParameterAssert(server != nil);

	NSMutableDictionary *attributes = AIKeychainInternetPasswordQuery(server, domain, account, path, port, protocol);
	[attributes setObject:[password dataUsingEncoding:NSUTF8StringEncoding] forKey:(NSString *)kSecValueData];

	OSStatus err;
	if (outKeychainItem) {
		[attributes setObject:(id)kCFBooleanTrue forKey:(NSString *)kSecReturnRef];
		CFTypeRef itemRef = NULL;
		err = SecItemAdd((CFDictionaryRef)attributes, &itemRef);
		*outKeychainItem = (SecKeychainItemRef)itemRef;
	} else {
		err = SecItemAdd((CFDictionaryRef)attributes, NULL);
	}

	if (outError) *outError = AIKeychainErrorForStatus(err, @"SecItemAdd", server, account);

	return (err == errSecSuccess);
}

- (BOOL)addInternetPassword:(NSString *)password forServer:(NSString *)server account:(NSString *)account protocol:(SecProtocolType)protocol error:(out NSError **)outError
{
	return [self addInternetPassword:password
						   forServer:server
					  securityDomain:nil
							 account:account
								path:nil
								port:0
							protocol:protocol
				  authenticationType:kSecAuthenticationTypeDefault
						keychainItem:NULL
							   error:outError];
}

#pragma mark -

- (NSString *)findInternetPasswordForServer:(NSString *)server
							 securityDomain:(NSString *)domain	// Can pass nil
									account:(NSString *)account
									   path:(NSString *)path
									   port:(u_int16_t)port		// Can pass 0
								   protocol:(SecProtocolType)protocol
						 authenticationType:(SecAuthenticationType)authType
							   keychainItem:(out SecKeychainItemRef *)outKeychainItem
									  error:(out NSError **)outError
{
	NSMutableDictionary *query = AIKeychainInternetPasswordQuery(server, domain, account, path, port, protocol);
	[query setObject:(NSString *)kSecMatchLimitOne forKey:(NSString *)kSecMatchLimit];
	[query setObject:(id)kCFBooleanTrue forKey:(NSString *)kSecReturnData];
	if (outKeychainItem) [query setObject:(id)kCFBooleanTrue forKey:(NSString *)kSecReturnRef];

	CFTypeRef result = NULL;
	OSStatus err = SecItemCopyMatching((CFDictionaryRef)query, &result);

	if (err == errSecItemNotFound && protocol) {
		// Entries written by other tools may lack the protocol attribute; retry without it
		[query removeObjectForKey:(NSString *)kSecAttrProtocol];
		err = SecItemCopyMatching((CFDictionaryRef)query, &result);
	}

	NSString *passwordString = nil;
	if (err == errSecSuccess && result) {
		NSData *passwordData = nil;
		if (outKeychainItem) {
			// With both kSecReturnData and kSecReturnRef set, the result is a dictionary
			NSDictionary *resultDict = (NSDictionary *)result;
			passwordData = [resultDict objectForKey:(NSString *)kSecValueData];
			SecKeychainItemRef item = (SecKeychainItemRef)[resultDict objectForKey:(NSString *)kSecValueRef];
			*outKeychainItem = item ? (SecKeychainItemRef)CFRetain(item) : NULL;
		} else {
			passwordData = (NSData *)result;
		}
		passwordString = [[[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding] autorelease];
	} else if (outKeychainItem) {
		*outKeychainItem = NULL;
	}
	if (result) CFRelease(result);

	if (outError) *outError = AIKeychainErrorForStatus(err, @"SecItemCopyMatching", server, account);

	return passwordString;
}

- (NSString *)internetPasswordForServer:(NSString *)server account:(NSString *)account protocol:(SecProtocolType)protocol error:(out NSError **)outError
{
	NSString *password = [self findInternetPasswordForServer:server
											  securityDomain:nil
													 account:account
														path:nil
														port:0
													protocol:protocol
										  authenticationType:kSecAuthenticationTypeDefault
												keychainItem:NULL
													   error:outError];

	return password;
}

- (NSDictionary *)dictionaryFromKeychainForServer:(NSString *)server protocol:(SecProtocolType)protocol error:(out NSError **)outError
{
	NSAssert( UINT_MAX >= [server length], @"Attempting to send more data than Keychain can handle.  Abort." );
	NSDictionary *result = nil;

	// Search for keychain items whose server is our key
	SecKeychainSearchRef search = NULL;

	struct SecKeychainAttribute searchAttrs[] = {
		{
			.tag    = kSecServerItemAttr,
			.length = (UInt32)[server length],
			.data   = (void *)[server UTF8String],
		},
		{
			.tag    = kSecProtocolItemAttr,
			.length = sizeof(SecProtocolType),
			.data   = &protocol,
		}
	};

	struct SecKeychainAttributeList searchAttrList = {
		.count = 2,
		.attr  = searchAttrs,
	};

	// If keychainRef is NULL, the users's default keychain search list will be used
	OSStatus err = SecKeychainSearchCreateFromAttributes(keychainRef, kSecInternetPasswordItemClass, &searchAttrList, &search);
	
	if (err == noErr) {
		SecKeychainItemRef item = NULL;
			
		err = SecKeychainSearchCopyNext(search, &item);

		if (err == errSecItemNotFound) {
			// No matching server found
		} else if (err == noErr) {
			// Output storage.
			struct SecKeychainAttributeList *attrList = NULL;
			UInt32 passwordLength = 0U;
			void  *passwordBytes = NULL;

			// First, grab the username.
			UInt32    tags[] = { kSecAccountItemAttr };
			UInt32 formats[] = { CSSM_DB_ATTRIBUTE_FORMAT_STRING };
			struct SecKeychainAttributeInfo info = {
				.count  = 1,
				.tag    = tags,
				.format = formats,
			};
			
			err = SecKeychainItemCopyAttributesAndData(item,
													   &info,
													   /* itemClass */ NULL,
													   &attrList,
													   &passwordLength,
													   &passwordBytes);
			if (err == noErr) {
				NSString *username = [NSString stringWithBytes:attrList->attr[0].data length:attrList->attr[0].length encoding:NSUTF8StringEncoding];
				NSString *password = [NSString stringWithBytes:passwordBytes length:passwordLength encoding:NSUTF8StringEncoding];
				result = [NSDictionary dictionaryWithObjectsAndKeys:
					username, @"Username",
					password, @"Password",
					nil];
				
				SecKeychainItemFreeAttributesAndData(attrList, passwordBytes);
			} else {
				NSLog(@"Error extracting infomation from keychain item");
			}

			if (item) {
				CFRelease(item);
			}
		} else {
			NSLog(@"%@: Error in SecKeychainSearchCopyNext(); err is %ld", self, (long)err);	
		}

		if (search)	{
			CFRelease(search);
		}
	} else {
		NSLog(@"%@: Could not create search; err is %ld", self, (long)err);
	}

	return result;
}

#pragma mark -

- (BOOL)setInternetPassword:(NSString *)password
				  forServer:(NSString *)server
			 securityDomain:(NSString *)domain	// Can pass nil
					account:(NSString *)account
					   path:(NSString *)path
					   port:(u_int16_t)port		// Can pass 0
				   protocol:(SecProtocolType)protocol
		 authenticationType:(SecAuthenticationType)authType
			   keychainItem:(out SecKeychainItemRef *)outKeychainItem
					  error:(out NSError **)outError
{
	if (!password) {
		// Remove the password
		return [self deleteInternetPasswordForServer:server
									  securityDomain:domain
											 account:account
												path:path
												port:port
											protocol:protocol
								  authenticationType:authType
										keychainItem:outKeychainItem
											   error:outError];
	}

	NSMutableDictionary *query = AIKeychainInternetPasswordQuery(server, domain, account, path, port, protocol);
	NSDictionary *changes = [NSDictionary dictionaryWithObject:[password dataUsingEncoding:NSUTF8StringEncoding]
														forKey:(NSString *)kSecValueData];
	OSStatus err = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)changes);

	if (err == errSecItemNotFound) {
		return [self addInternetPassword:password
							   forServer:server
						  securityDomain:domain
								 account:account
									path:path
									port:port
								protocol:protocol
					  authenticationType:authType
							keychainItem:outKeychainItem
								   error:outError];
	}

	if (outKeychainItem) *outKeychainItem = NULL;
	if (outError) *outError = AIKeychainErrorForStatus(err, @"SecItemUpdate", server, account);

	return (err == errSecSuccess);
}

- (BOOL)setInternetPassword:(NSString *)password
				  forServer:(NSString *)server
					account:(NSString *)account
				   protocol:(SecProtocolType)protocol
					  error:(out NSError **)outError
{
	return [self setInternetPassword:password
						   forServer:server
					  securityDomain:nil
							 account:account
								path:nil
								port:0
							protocol:protocol
				  authenticationType:kSecAuthenticationTypeDefault
						keychainItem:NULL
							   error:outError];
}

#pragma mark -

- (BOOL)deleteInternetPasswordForServer:(NSString *)server
						 securityDomain:(NSString *)domain	// Can pass nil
								account:(NSString *)account
								   path:(NSString *)path
								   port:(u_int16_t)port		// Can pass 0
							   protocol:(SecProtocolType)protocol
					 authenticationType:(SecAuthenticationType)authType
						   keychainItem:(out SecKeychainItemRef *)outKeychainItem
								  error:(out NSError **)outError
{
	NSMutableDictionary *query = AIKeychainInternetPasswordQuery(server, domain, account, path, port, protocol);
	OSStatus err = SecItemDelete((CFDictionaryRef)query);

	if (err == errSecItemNotFound && protocol) {
		// Entries written by other tools may lack the protocol attribute; retry without it
		[query removeObjectForKey:(NSString *)kSecAttrProtocol];
		err = SecItemDelete((CFDictionaryRef)query);
	}

	if (outKeychainItem) *outKeychainItem = NULL;
	if (outError) *outError = AIKeychainErrorForStatus(err, @"SecItemDelete", server, account);

	return (err == errSecSuccess);
}

- (BOOL)deleteInternetPasswordForServer:(NSString *)server account:(NSString *)account protocol:(SecProtocolType)protocol error:(out NSError **)outError
{
	return [self deleteInternetPasswordForServer:server
								  securityDomain:nil
										 account:account
											path:nil
											port:0
										protocol:protocol
							  authenticationType:kSecAuthenticationTypeDefault
									keychainItem:NULL
										   error:outError];
}

#pragma mark -

- (BOOL)addGenericPassword:(NSString *)password
				forService:(NSString *)service
				   account:(NSString *)account
			  keychainItem:(out SecKeychainItemRef *)outKeychainItem
					 error:(out NSError **)outError
{
	NSParameterAssert(password != nil);
	NSParameterAssert(service != nil);
	NSParameterAssert(account != nil);

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
	NSData *serviceData = [service dataUsingEncoding:NSUTF8StringEncoding];
	NSData *accountData = [account dataUsingEncoding:NSUTF8StringEncoding];
	
	NSAssert( (UINT_MAX >= [passwordData length]) &&
					  (UINT_MAX >= [serviceData length]) &&
					  (UINT_MAX >= [accountData length]),
					  @"Attempting to send more data than Keychain can handle.  Abort." );
	// If keychainRef is NULL, the default keychain will be used
	OSStatus err = SecKeychainAddGenericPassword(keychainRef,
												  (UInt32)[serviceData length],  [serviceData bytes],
												  (UInt32)[accountData length],  [accountData bytes],
												 (UInt32)[passwordData length], [passwordData bytes],
												 outKeychainItem);

	[pool release];

	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainAddGenericPassword], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainAddGenericPassword", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				service, AIKEYCHAIN_ERROR_USERINFO_SERVICE,
				account, AIKEYCHAIN_ERROR_USERINFO_ACCOUNT,
				[NSValue valueWithPointer:keychainRef], AIKEYCHAIN_ERROR_USERINFO_KEYCHAIN,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}

		*outError = error;
	}
	
	return (err == noErr);
}

- (NSString *)findGenericPasswordForService:(NSString *)service
									account:(NSString *)account
							   keychainItem:(out SecKeychainItemRef *)outKeychainItem
									  error:(out NSError **)outError
{
	void  *passwordData   = NULL;
	UInt32 passwordLength = 0;

	NSData *serviceData = [service dataUsingEncoding:NSUTF8StringEncoding];
	NSData *accountData = [account dataUsingEncoding:NSUTF8StringEncoding];
	NSString *passwordString = nil;

	NSAssert( (UINT_MAX >= [serviceData length]) &&
					  (UINT_MAX >= [accountData length]),
					  @"Attempting to send more data than Keychain can handle.  Abort." );
	// If keychainRef is NULL, the users's default keychain search list will be used
	OSStatus err = SecKeychainFindGenericPassword(keychainRef,
												  (UInt32)[serviceData length],  [serviceData bytes],
												  (UInt32)[accountData length],  [accountData bytes],
												  &passwordLength,
												  &passwordData,
												  outKeychainItem);
	if (outError) {
		NSError *error = nil;
		
		if (err != noErr) {
			NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
				[NSValue valueWithPointer:SecKeychainFindGenericPassword], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
				@"SecKeychainFindGenericPassword", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
				AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
				service, AIKEYCHAIN_ERROR_USERINFO_SERVICE,
				account, AIKEYCHAIN_ERROR_USERINFO_ACCOUNT,
				[NSValue valueWithPointer:keychainRef], AIKEYCHAIN_ERROR_USERINFO_KEYCHAIN,
				nil];
			error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
		}

		*outError = error;
	}

	passwordString = [NSString stringWithBytes:passwordData length:passwordLength encoding:NSUTF8StringEncoding];

	if (err == noErr) {
		SecKeychainItemFreeContent(NULL, passwordData);
	}

	return passwordString;	
}

- (BOOL)deleteGenericPasswordForService:(NSString *)service
								account:(NSString *)account
								  error:(out NSError **)outError
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	SecKeychainItemRef keychainItem = NULL;
	NSError *error = nil;

	[self findGenericPasswordForService:service
								account:account
						   keychainItem:&keychainItem
								  error:&error];
	
	BOOL success = NO;
	
	if (keychainItem) {
		OSStatus err = SecKeychainItemDelete(keychainItem);

		if (outError) {
			if (err == noErr) {
				error = nil;
			} else if (!error) {
				NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
										  [NSValue valueWithPointer:SecKeychainFindGenericPassword], AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION,
										  @"SecKeychainFindGenerictPassword", AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME,
										  AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err), AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION,
										  service,  AIKEYCHAIN_ERROR_USERINFO_SERVICE,
										  account, AIKEYCHAIN_ERROR_USERINFO_ACCOUNT,
										  NSFileTypeForHFSTypeCode(kSecAuthenticationTypeDefault), AIKEYCHAIN_ERROR_USERINFO_AUTHENTICATIONTYPE,
										  [NSValue valueWithPointer:keychainRef], AIKEYCHAIN_ERROR_USERINFO_KEYCHAIN,
										  nil];
				error = [NSError errorWithDomain:AIKEYCHAIN_ERROR_DOMAIN code:err userInfo:userInfo];
			}

			*outError = error;
		}
		
		success = (err == noErr);
	}
	
	if (keychainItem) {
		CFRelease(keychainItem);
	}

	[pool release];
	
	return success;
}

#pragma mark -

// Returns the Keychain Services object that backs this object.
- (SecKeychainRef)keychainRef
{
	return keychainRef;
}

#pragma mark -

- (NSString *)description
{
	return [NSString stringWithFormat:@"<AIKeychain %p (%@)>", self, keychainRef];
}

@end
