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

#import "adiumPurpleCertificateTrustWarning.h"
#import "AIPurpleCertificateTrustWarningAlert.h"

#import <Adium/AIAccount.h>
#import <Adium/AIAccountControllerProtocol.h>
#import "CBPurpleAccount.h"
#import "ESPurpleJabberAccount.h"

/*!
 * @brief The SSL plugin asks what to do with a peer's certificate chain
 *
 * Called for every TLS connection libpurple's cdsa plugin completes, good chains included: the
 * verdict is made here, not before. This used to look for an owner among the Jabber accounts
 * only, and whatever it could not place it accepted without any check at all, which meant an
 * IRC server presenting an expired certificate connected without a word. Now every purple
 * account is asked whether the connection is its own, an owner's stored opt-out is honoured,
 * and everything else is verified. A connection nobody claims is still verified, only without
 * an account to show; it is never waved through again.
 */
void adium_query_cert_chain(PurpleSslConnection *gsc, const char *hostname, CFArrayRef certs, void (*query_cert_cb)(gboolean trusted, void *userdata), void *userdata) {
	@autoreleasepool {
		CBPurpleAccount *account = nil;

		for (AIAccount *candidate in adium.accountController.accounts) {
			if ([candidate isKindOfClass:[CBPurpleAccount class]] &&
				[(CBPurpleAccount *)candidate secureConnection] == gsc) {
				account = (CBPurpleAccount *)candidate;
				break;
			}
		}

		//The one documented opt-out: an account whose settings say not to verify
		if (account &&
			[account respondsToSelector:@selector(shouldVerifyCertificates)] &&
			![(ESPurpleJabberAccount *)account shouldVerifyCertificates]) {
			query_cert_cb(true, userdata);
			return;
		}

		[AIPurpleCertificateTrustWarningAlert displayTrustWarningAlertWithAccount:account
																		 hostname:[NSString stringWithUTF8String:hostname]
																	 certificates:certs
																   resultCallback:query_cert_cb
																		 userData:userdata];
	}
}
