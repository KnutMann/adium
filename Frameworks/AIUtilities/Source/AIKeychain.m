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
 *
 * Backed entirely by the SecItem API. The deprecated SecKeychain* function family
 * (and the many keychain-management methods that wrapped it — lock/unlock, settings,
 * creating/deleting keychain files, generic passwords) was removed in the
 * deprecated-API sweep; none of those methods had remaining callers.
 */

#import "AIKeychain.h"
#import "AIStringAdditions.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>

#define AI_LOCALIZED_SECURITY_ERROR_DESCRIPTION(err) \
	NSLocalizedStringFromTableInBundle([[NSNumber numberWithLong:(err)] stringValue], @"SecErrorMessages", [NSBundle bundleWithIdentifier:@"com.apple.security"], /* comment */ nil)

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
	return [[NSString alloc] initWithBytes:code length:4 encoding:NSMacOSRomanStringEncoding];
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

@implementation AIKeychain

/* The SecItem API always operates on the user's default keychain search list, so
 * there is no per-keychain state any more; a single shared instance suffices. The
 * historical method name (and the error out-parameter, which is now always nil'd)
 * are kept for the existing call sites.
 */
+ (AIKeychain *)defaultKeychain_error:(out NSError **)outError
{
	static AIKeychain *defaultKeychain = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		defaultKeychain = [[self alloc] init];
	});

	if (outError) *outError = nil;

	return defaultKeychain;
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
			/* Borrowed, not taken over. SecItemCopyMatching hands back something owned and it is
			 * given up at the end of this method, so the cast must convey no ownership: a transfer
			 * here would have the same result released twice.
			 */
			// With both kSecReturnData and kSecReturnRef set, the result is a dictionary
			NSDictionary *resultDict = (__bridge NSDictionary *)result;
			passwordData = [resultDict objectForKey:(NSString *)kSecValueData];
			SecKeychainItemRef item = (__bridge SecKeychainItemRef)[resultDict objectForKey:(NSString *)kSecValueRef];
			*outKeychainItem = item ? (SecKeychainItemRef)CFRetain(item) : NULL;
		} else {
			passwordData = (__bridge NSData *)result;   // borrowed, as above
		}
		passwordString = [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding];
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

/* Returns the account name and password of the first internet-password item matching
 * server (and protocol). Formerly implemented with the deprecated SecKeychainSearch*
 * functions; now a single SecItemCopyMatching call returning attributes and data.
 */
- (NSDictionary *)dictionaryFromKeychainForServer:(NSString *)server protocol:(SecProtocolType)protocol error:(out NSError **)outError
{
	NSDictionary *result = nil;

	NSMutableDictionary *query = AIKeychainInternetPasswordQuery(server, nil, nil, nil, 0, protocol);
	[query setObject:(NSString *)kSecMatchLimitOne forKey:(NSString *)kSecMatchLimit];
	[query setObject:(id)kCFBooleanTrue forKey:(NSString *)kSecReturnAttributes];
	[query setObject:(id)kCFBooleanTrue forKey:(NSString *)kSecReturnData];

	CFTypeRef cfResult = NULL;
	OSStatus err = SecItemCopyMatching((CFDictionaryRef)query, &cfResult);

	if (err == errSecItemNotFound && protocol) {
		// Entries written by other tools may lack the protocol attribute; retry without it
		[query removeObjectForKey:(NSString *)kSecAttrProtocol];
		err = SecItemCopyMatching((CFDictionaryRef)query, &cfResult);
	}

	if (err == errSecSuccess && cfResult) {
		/* Borrowed again: cfResult is given up below, so this cast takes nothing. */
		NSDictionary *item = (__bridge NSDictionary *)cfResult;
		NSString *username = [item objectForKey:(NSString *)kSecAttrAccount];
		NSData *passwordData = [item objectForKey:(NSString *)kSecValueData];
		NSString *password = (passwordData ? [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding] : nil);

		if (username && password) {
			result = [NSDictionary dictionaryWithObjectsAndKeys:
				username, @"Username",
				password, @"Password",
				nil];
		}
	}
	if (cfResult) CFRelease(cfResult);

	if (outError) *outError = AIKeychainErrorForStatus(err, @"SecItemCopyMatching", server, nil);

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

- (NSString *)description
{
	return [NSString stringWithFormat:@"<AIKeychain %p>", self];
}

@end
