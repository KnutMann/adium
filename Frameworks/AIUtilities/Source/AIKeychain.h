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

#import <Security/Security.h>

#pragma mark AIKeychain errors

/*!	@defgroup AIKeychainErrors AIKeychain errors
 *
 *	@par
 *	All \c AIKeychain methods return by reference an \c NSError object when the
 *	Security framework function that backs that method returns an \c OSStatus
 *	other than \c errSecSuccess.
 *
 *	The domain of the error is \c AIKEYCHAIN_ERROR_DOMAIN, and the error code is the \c OSStatus returned by the Security framework.
 *
 *	You may pass \c NULL for the \a error argument, in which case the error will be
 *	silently dropped.
 */

/*@{*/

/*!	@def AIKEYCHAIN_ERROR_DOMAIN
 *	@brief The domain of all \c AIKeychain errors.
 *	Whenever you receive an \c NSError from an \c AIKeychain method, its domain will be \c AIKEYCHAIN_ERROR_DOMAIN.
 */
#define AIKEYCHAIN_ERROR_DOMAIN @"AIKeychainError"

/*!	@def AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION
 *	@brief The Security framework function that returned the error.
 *	This value is stored as an \c NSValue. Call \c -pointerValue to retrieve the function pointer.
 */
#define AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTION @"SecurityFrameworkFunction"

//!	@brief The name of the Security framework function that returned the error.
#define AIKEYCHAIN_ERROR_USERINFO_SECURITYFUNCTIONNAME @"SecurityFrameworkFunctionName"

//!	@brief Description of the error (from SecErrorMessages.strings).
#define AIKEYCHAIN_ERROR_USERINFO_ERRORDESCRIPTION @"SecurityFrameworkErrorDescription"

//!	@brief The \c AIKeychain instance that was involved.
#define AIKEYCHAIN_ERROR_USERINFO_KEYCHAIN @"Keychain"

/*!	@def AIKEYCHAIN_ERROR_USERINFO_SERVICE
 *	@brief The service name involved in the failed operation.
 */
#define AIKEYCHAIN_ERROR_USERINFO_SERVICE            @"GenericPasswordService"

/*!	@def AIKEYCHAIN_ERROR_USERINFO_SERVER
 *	@brief The server name involved in the failed operation.
 */
#define AIKEYCHAIN_ERROR_USERINFO_SERVER             @"InternetPasswordServer"

/*!	@def AIKEYCHAIN_ERROR_USERINFO_DOMAIN
 *	@brief The security domain involved in the failed operation.
 */
#define AIKEYCHAIN_ERROR_USERINFO_DOMAIN             @"InternetPasswordSecurityDomain"

/*!	@def AIKEYCHAIN_ERROR_USERINFO_ACCOUNT
 *	@brief The account name involved in the failed operation.
 */
#define AIKEYCHAIN_ERROR_USERINFO_ACCOUNT            @"PasswordAccount"

/*!	@def AIKEYCHAIN_ERROR_USERINFO_PROTOCOL
 *	@brief The protocol involved in the failed operation.
 */
#define AIKEYCHAIN_ERROR_USERINFO_PROTOCOL           @"PasswordProtocol"

/*!	@def AIKEYCHAIN_ERROR_USERINFO_AUTHENTICATIONTYPE
 *	@brief The authentication type involved in the failed operation.
 */
#define AIKEYCHAIN_ERROR_USERINFO_AUTHENTICATIONTYPE @"PasswordAuthenticationType"

/*@}*/

/*!	class AIKeychain
 *	@brief Cocoa wrapper around the SecItem API for the login keychain.
 *
 *	@par
 *	Historically this class wrapped a Keychain Services \c SecKeychainRef and the
 *	(long-deprecated) SecKeychain* function family. All remaining functionality is
 *	backed by the SecItem API, which always operates on the user's default keychain
 *	search list, so the class no longer wraps a specific keychain object. The
 *	SecKeychain*-based keychain-management methods (lock/unlock, settings, creating
 *	and deleting keychain files, generic passwords) had no remaining callers and
 *	were removed in the deprecated-API sweep.
 */
@interface AIKeychain: NSObject {
}

/*!	@brief Returns the shared \c AIKeychain instance for the user's default keychain.
 *
 *	@par
 *	With the SecItem backend there is no per-keychain state, so this always returns
 *	the same shared instance and never fails; \a outError is always set to \c nil
 *	when provided. The historical name is kept for the existing call sites.
 *
 *	@return The shared \c AIKeychain instance.
 */
+ (AIKeychain *)defaultKeychain_error:(out NSError **)outError;

#pragma mark -

/*!	@brief Adds an Internet password to the default keychain via \c SecItemAdd.
 */
- (BOOL)addInternetPassword:(NSString *)password
				  forServer:(NSString *)server
			 securityDomain:(NSString *)domain //can pass nil
					account:(NSString *)account
					   path:(NSString *)path
					   port:(u_int16_t)port //can pass 0
				   protocol:(SecProtocolType)protocol
		 authenticationType:(SecAuthenticationType)authType
			   keychainItem:(out SecKeychainItemRef *)outKeychainItem
					  error:(out NSError **)outError;

- (BOOL)addInternetPassword:(NSString *)password
				  forServer:(NSString *)server
					account:(NSString *)account
				   protocol:(SecProtocolType)protocol
					  error:(out NSError **)outError;

#pragma mark -

/*!	@brief Finds an Internet password in the default keychain via \c SecItemCopyMatching.
 */
- (NSString *)findInternetPasswordForServer:(NSString *)server
							 securityDomain:(NSString *)domain //can pass nil
									account:(NSString *)account
									   path:(NSString *)path
									   port:(u_int16_t)port //can pass 0
								   protocol:(SecProtocolType)protocol
						 authenticationType:(SecAuthenticationType)authType
							   keychainItem:(out SecKeychainItemRef *)outKeychainItem
									  error:(out NSError **)outError;

- (NSString *)internetPasswordForServer:(NSString *)server
								account:(NSString *)account
							   protocol:(SecProtocolType)protocol
								  error:(out NSError **)outError;

/*!	@brief Finds the first Internet password for \a server, returning both account and password.
 *
 *	@return A dictionary with keys \c Username and \c Password, or \c nil if no item matched.
 */
- (NSDictionary *)dictionaryFromKeychainForServer:(NSString *)server
										 protocol:(SecProtocolType)protocol
											error:(out NSError **)outError;

#pragma mark -

/*!	@brief Sets (updates or adds) an Internet password via \c SecItemUpdate / \c SecItemAdd.
 *	Passing \c nil for \a password removes the item.
 */
- (BOOL)setInternetPassword:(NSString *)password
				  forServer:(NSString *)server
			 securityDomain:(NSString *)domain //can pass nil
					account:(NSString *)account
					   path:(NSString *)path
					   port:(u_int16_t)port //can pass 0
				   protocol:(SecProtocolType)protocol
		 authenticationType:(SecAuthenticationType)authType
			   keychainItem:(out SecKeychainItemRef *)outKeychainItem
					  error:(out NSError **)outError;

- (BOOL)setInternetPassword:(NSString *)password
				  forServer:(NSString *)server
					account:(NSString *)account
				   protocol:(SecProtocolType)protocol
					  error:(out NSError **)outError;

#pragma mark -

/*!	@brief Deletes an Internet password via \c SecItemDelete.
 */
- (BOOL)deleteInternetPasswordForServer:(NSString *)server
						 securityDomain:(NSString *)domain //can pass nil
								account:(NSString *)account
								   path:(NSString *)path
								   port:(u_int16_t)port //can pass 0
							   protocol:(SecProtocolType)protocol
					 authenticationType:(SecAuthenticationType)authType
						   keychainItem:(out SecKeychainItemRef *)outKeychainItem
								  error:(out NSError **)outError;

- (BOOL)deleteInternetPasswordForServer:(NSString *)server
								account:(NSString *)account
							   protocol:(SecProtocolType)protocol
								  error:(out NSError **)outError;

@end
