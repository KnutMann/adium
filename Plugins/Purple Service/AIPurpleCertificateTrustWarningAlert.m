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

#import "AIPurpleCertificateTrustWarningAlert.h"
#import <SecurityInterface/SFCertificateTrustPanel.h>
#import <Security/SecPolicy.h>
#import <Security/SecTrust.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import "ESPurpleJabberAccount.h"

#define PREF_GROUP_SSL_EXCEPTIONS	@"SSL Certificate Exceptions"

//#define ALWAYS_SHOW_TRUST_WARNING

@interface AIPurpleCertificateTrustWarningAlert () {
	SFCertificateTrustPanel *trustPanel;
}
- (id)initWithAccount:(AIAccount*)account
			 hostname:(NSString*)hostname
		 certificates:(CFArrayRef)certs
	   resultCallback:(void (*)(gboolean trusted, void *userdata))_query_cert_cb
			 userData:(void*)ud;
- (IBAction)showWindow:(id)sender;
- (void)runTrustPanelOnWindow:(NSWindow *)window;
- (void)certificateTrustSheetDidEnd:(SFCertificateTrustPanel *)endedPanel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
@end

/* The ownership home of every alert whose sheet is up. The creator's reference ends when
 * +displayTrustWarningAlertWithAccount:... returns; what keeps an alert alive from there to the
 * end of its sheet is its place in this set, which -certificateTrustSheetDidEnd:... leaves. Under
 * manual counting that was the [self retain] in init and the [self release] at the end of the
 * sheet. The same design as AMPurpleRequestFieldsController. */
static NSMutableSet *openTrustWarningAlerts = nil;

@implementation AIPurpleCertificateTrustWarningAlert

+ (void)displayTrustWarningAlertWithAccount:(AIAccount *)account
								   hostname:(NSString *)hostname
							   certificates:(CFArrayRef)certs
							 resultCallback:(void (*)(gboolean trusted, void *userdata))_query_cert_cb
								   userData:(void*)ud
{
	if (account &&
		[hostname caseInsensitiveCompare:@"talk.google.com"] == NSOrderedSame &&
		![[account preferenceForKey:KEY_JABBER_FORCE_OLD_SSL group:GROUP_ACCOUNT_STATUS] boolValue]) {
		NSString *UID = account.UID;
		NSRange startOfDomain = [UID rangeOfString:@"@"];

		if (startOfDomain.location == NSNotFound ||
			([[UID substringFromIndex:NSMaxRange(startOfDomain)] caseInsensitiveCompare:@"gmail.com"] == NSOrderedSame)) {
			/* Google Talk accounts end up with a cert signed using gmail.com as the server.
			 * However, Google For Domains accounts are signed using talk.google.com
			 */
			hostname = @"gmail.com";
		} else if ([[UID substringFromIndex:NSMaxRange(startOfDomain)] caseInsensitiveCompare:@"googlemail.com"] == NSOrderedSame) {
			/* There are three certificates, as far as I (am) know. Maybe we should ask Sean for confirmation. */
			hostname = @"googlemail.com";
		}
	}

	/* This local holds the alert through -showWindow:. Every synchronous exit in there has
	 * answered libpurple before it returns and needs nothing more; only the sheet path outlives
	 * this call, and that path puts the alert into the set above in -runTrustPanelOnWindow:. */
	AIPurpleCertificateTrustWarningAlert *alert = [[self alloc] initWithAccount:account hostname:hostname certificates:certs resultCallback:_query_cert_cb userData:ud];
	[alert showWindow:nil];
}

- (id)initWithAccount:(AIAccount*)_account
			 hostname:(NSString*)_hostname
		 certificates:(CFArrayRef)certs
	   resultCallback:(void (*)(gboolean trusted, void *userdata))_query_cert_cb
			 userData:(void*)ud
{
	if((self = [super init])) {
		query_cert_cb = _query_cert_cb;
		
		certificates = certs;
		CFRetain(certificates);
		
		account = _account;
		hostname = [_hostname copy];
		
		userdata = ud;
	}
	return self;
}

- (void)dealloc {
	CFRelease(certificates);
	//The early error paths let self go before a trust ref exists, and CFRelease(NULL) aborts
	if (trustRef) CFRelease(trustRef);
}

- (IBAction)showWindow:(id)sender {
	OSStatus err;

	/* An SSL evaluation policy for this hostname. This took a CSSM policy-database search and a
	 * hand-packed options struct before; the one-call form has existed since 10.6 and is also
	 * what the trust panel below is given. */
	SecPolicyRef policyRef = SecPolicyCreateSSL(true, (__bridge CFStringRef)hostname);
	if (!policyRef) {
		/* The old code beeped and returned without ever answering libpurple, leaving the
		 * connection waiting forever. An unanswerable question is answered with no. */
		query_cert_cb(false, userdata);
		return;
	}

	err = SecTrustCreateWithCertificates(certificates, policyRef, &trustRef);

	/* A chain the user already accepted for this host: the stored exception makes the
	 * evaluation below succeed, and no question is asked twice. A changed certificate
	 * is not covered by the old exception, so it asks again, as it should. */
	if (err == noErr) {
		NSData *storedException = [adium.preferenceController preferenceForKey:hostname
																		 group:PREF_GROUP_SSL_EXCEPTIONS];
		if (storedException)
			SecTrustSetExceptions(trustRef, (__bridge CFDataRef)storedException);
	}

	if(err != noErr) {
		CFRelease(policyRef);
		query_cert_cb(false, userdata);
		return;
	}

	/* Whether the chain stands on its own. The boolean answer is not enough here: the result
	 * type distinguishes a chain the user could choose to trust from one that is beyond asking
	 * about, so it is read back after the evaluation. */
	SecTrustResultType result = kSecTrustResultOtherError;
	(void)SecTrustEvaluateWithError(trustRef, NULL);
	err = SecTrustGetTrustResult(trustRef, &result);
	if(err == noErr) {
		switch(result) {
			case kSecTrustResultProceed: // trust ok, go right ahead
			case kSecTrustResultUnspecified: // trust ok, user has no particular opinion about this
#ifndef ALWAYS_SHOW_TRUST_WARNING
				query_cert_cb(true, userdata);
				break;
#endif
			case kSecTrustResultDeny: // trust ok, but user previously said not to trust it anyway
			case kSecTrustResultRecoverableTrustFailure: // trust broken, perhaps argue with the user
			case kSecTrustResultOtherError: // failure other than trust evaluation; We'll let the user decide where to go from here.
			{
				
				/* The trust panel only knows how to be a sheet, and a sheet needs a window
				 * to hang from. There is no natural one during a connect, so it gets an
				 * anchor - but an invisible one: the sliver of title bar the old visible
				 * anchor showed under a far larger sheet read as a glitch. With the anchor
				 * at zero alpha only the certificate card itself is on screen, which is how
				 * the system presents free-standing dialogs anyway. Titled, because a
				 * borderless window could not become key for the sheet's sake. */
#define TRUST_PANEL_WIDTH 535
				NSWindow *anchorWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, TRUST_PANEL_WIDTH, 1)
																	  styleMask:NSWindowStyleMaskTitled
																		backing:NSBackingStoreBuffered
																		  defer:NO];
				[anchorWindow setReleasedWhenClosed:NO];
				[anchorWindow setAlphaValue:0.0];
				[anchorWindow setExcludedFromWindowsMenu:YES];
				[anchorWindow center];

				[self runTrustPanelOnWindow:anchorWindow];
				[anchorWindow makeKeyAndOrderFront:nil];
				break;
			}
			default:
				/*
				 * kSecTrustResultFatalTrustFailure -> trust broken, user can't fix it
				 * kSecTrustResultInvalid -> logic error; fix your program (SecTrust was used incorrectly)
				 */
				query_cert_cb(false, userdata);
				break;
		}
	} else {
		query_cert_cb(false, userdata);
	}

	CFRelease(policyRef);
}

- (void)runTrustPanelOnWindow:(NSWindow *)window
{
	//Alive as long as the sheet is up; see -certificateTrustSheetDidEnd:returnCode:contextInfo:
	if (!openTrustWarningAlerts) openTrustWarningAlerts = [[NSMutableSet alloc] init];
	[openTrustWarningAlerts addObject:self];

	//Held until the sheet ends, where the manual code released it
	trustPanel = [[SFCertificateTrustPanel alloc] init];
	
	// this could probably be used for a more detailed message:
	//	CFArrayRef certChain;
	//	CSSM_TP_APPLE_EVIDENCE_INFO *statusChain;
	//	err = SecTrustGetResult(trustRef, &result, &certChain, &statusChain);
	
	/* Both lines travel through the panel's public message: parameter. The informative text used
	 * to be set through a private selector found via class-dump; the panel renders the combined
	 * message a little less prettily and owes nobody an apology for existing. */
	NSString *title = [NSString stringWithFormat:@"%@\n\n%@",
					   [NSString stringWithFormat:AILocalizedString(@"Adium can't verify the identity of \"%@\".", nil), hostname],
					   [NSString stringWithFormat:AILocalizedString(@"The certificate of the server %@ is not trusted, which means that the server's identity cannot be automatically verified. Do you want to continue connecting?\n\nFor more information, click \"Show Certificate\".",nil), hostname]];

	[trustPanel setAlternateButtonTitle:AILocalizedString(@"Cancel",nil)];
	[trustPanel setShowsHelp:YES];

	SecPolicyRef sslPolicy = SecPolicyCreateSSL(TRUE, (__bridge CFStringRef)hostname);
	if (sslPolicy) {
		[trustPanel setPolicies:(__bridge id)sslPolicy];
		CFRelease(sslPolicy);
	}

	/* The context is an identity, not a reference: the window is the sheet's parent and on
	 * screen until the sheet ends, and -certificateTrustSheetDidEnd:... closes it only then. */
	[trustPanel beginSheetForWindow:window
					  modalDelegate:self
					 didEndSelector:@selector(certificateTrustSheetDidEnd:returnCode:contextInfo:)
						contextInfo:(__bridge void *)window
							  trust:trustRef
							message:title];
}


- (void)editAccountWindow:(NSWindow *)window didOpenForAccount:(AIAccount *)inAccount
{
	[self runTrustPanelOnWindow:window];	
}

- (void)certificateTrustSheetDidEnd:(SFCertificateTrustPanel *)endedPanel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
	BOOL didTrustCerficate = (returnCode == NSModalResponseOK);
	NSWindow *parentWindow = (__bridge NSWindow *)contextInfo;

	/* Proceeding used to hold for one connection only, and the question returned at
	 * every launch. The failures the user just waved through become a stored
	 * exception for this host, applied before the next evaluation. */
	if (didTrustCerficate) {
		CFDataRef exceptions = SecTrustCopyExceptions(trustRef);
		if (exceptions) {
			[adium.preferenceController setPreference:(__bridge NSData *)exceptions
											   forKey:hostname
												group:PREF_GROUP_SSL_EXCEPTIONS];
			CFRelease(exceptions);
		}
	}

	query_cert_cb(didTrustCerficate, userdata);

	//The reference -runTrustPanelOnWindow: took, given back where the manual code released it
	trustPanel = nil;

	/* -close, not -performClose:: the anchor has no close button, and -performClose:
	 * refuses to close what the user could not have closed, so the invisible anchor
	 * lived on. Closing does not release the anchor (see above); being on screen is what
	 * held it, and the local above holds it to the end of this method. */
	[parentWindow close];

	/* Out of the set: the sheet is over and libpurple has its answer. Not before this turn
	 * of the run loop ends; the panel's sheet machinery is still on the stack below us. */
	CFAutorelease(CFBridgingRetain(self));
	[openTrustWarningAlerts removeObject:self];
}

@end
