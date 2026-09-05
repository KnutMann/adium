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

@class ESPurpleJabberAccount, ESFileTransfer;

/*!
 * @class AMPurpleJabberHTTPFileUpload
 * @brief Sends a picture the way modern XMPP clients do: upload it, message its address
 *
 * XEP-0363. The server's upload service is found through service discovery when the
 * account connects; a picture handed to the classic file transfer is then taken over
 * instead: a slot is requested by IQ, the file goes up by HTTPS PUT, and the address
 * the server hands back is sent as the message, which every modern client, this one
 * included, shows as the picture itself. Anything that goes wrong on the way falls
 * back to the classic transfer, and files that are not pictures never come here.
 */
@interface AMPurpleJabberHTTPFileUpload : NSObject {
	ESPurpleJabberAccount	*account;			//not retained; owns us
	NSString				*serviceJid;
	NSString				*serviceNamespace;	//urn:xmpp:http:upload:0, or the older unversioned form
	unsigned long long		 maxSize;			//0 = the service named no limit
	NSMutableSet			*queriedJids;		//whose discovery answers are ours to believe
	NSMutableDictionary		*pendingSlots;		//iq id -> completion block
	NSUInteger				 sequence;
	NSURLSession			*urlSession;
}

- (id)initWithAccount:(ESPurpleJabberAccount *)inAccount;

/*!
 * @brief Take a picture off the classic transfer path, if this account's server can
 *
 * Returns NO at once when it cannot (no upload service, not a picture, too big);
 * the caller then begins the classic transfer. Returns YES when the upload is on
 * its way; failures later fall back through -[ESPurpleJabberAccount
 * httpUploadFellBackForFileTransfer:].
 */
- (BOOL)takeOverFileTransfer:(ESFileTransfer *)fileTransfer;

@end
