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

#import "AIPurpleCertificateViewer.h"
#import <SecurityInterface/SFCertificatePanel.h>
#import <Adium/AIAccountControllerProtocol.h>

@interface AIPurpleCertificateViewer () {
	SFCertificatePanel *certificatePanel;
}

- (id)initWithCertificateChain:(CFArrayRef)cc forAccount:(AIAccount*)_account;
- (IBAction)showWindow:(id)sender;
- (void)certificateSheetDidEnd:(SFCertificatePanel*)panel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;

@end

/* The ownership home of a viewer whose sheet is up. The creator's reference ends when
 * +displayCertificateChain:forAccount: returns; from the sheet's beginning to its end the viewer
 * is held by its place in this set, which -certificateSheetDidEnd:... leaves. Under manual
 * counting that was the [self retain] in init, which nothing ever gave back. The same design as
 * AMPurpleRequestFieldsController. */
static NSMutableSet *openCertificateViewers = nil;

@implementation AIPurpleCertificateViewer

+ (void)displayCertificateChain:(CFArrayRef)cc forAccount:(AIAccount*)account {
	//This local holds the viewer through -showWindow:; only a sheet outlives this call, see above
	AIPurpleCertificateViewer *viewer = [[self alloc] initWithCertificateChain:cc forAccount:account];
	[viewer showWindow:nil];
}

- (id)initWithCertificateChain:(CFArrayRef)cc forAccount:(AIAccount*)_account {
	if((self = [super init])) {
		certificatechain = cc;
		CFRetain(certificatechain);
		account = _account;
	}
	return self;
}

- (void)dealloc {
	CFRelease(certificatechain);
}

- (IBAction)showWindow:(id)sender {
	[adium.accountController editAccount:account];
}

/* Reached only through the old account editor's notifying target, which went with that editor:
 * -editAccount: posts a notification and calls nothing back. Kept as it was, and self-contained
 * whoever begins the sheet: the set holds the viewer from here to the sheet's end. */
- (void)editAccountWindow:(NSWindow*)window didOpenForAccount:(AIAccount *)inAccount {
	if (!openCertificateViewers) openCertificateViewers = [[NSMutableSet alloc] init];
	[openCertificateViewers addObject:self];

	//Held until the sheet ends, where the manual code released it
	certificatePanel = [[SFCertificatePanel alloc] init];

	/* The context is an identity, not a reference: the window is the sheet's parent and on
	 * screen until the sheet ends, and -certificateSheetDidEnd:... closes it only after that. */
	[certificatePanel beginSheetForWindow:window modalDelegate:self didEndSelector:@selector(certificateSheetDidEnd:returnCode:contextInfo:) contextInfo:(__bridge void *)window certificates:(__bridge NSArray*)certificatechain showGroup:YES];
}

- (void)certificateSheetDidEnd:(SFCertificatePanel*)panel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
	NSWindow *win = (__bridge NSWindow*)contextInfo;

	//The reference -editAccountWindow:didOpenForAccount: took, given back where the manual code released it
	certificatePanel = nil;

	[win performSelector:@selector(performClose:) withObject:nil afterDelay:0.0];

	/* Out of the set: the sheet is over. Not before this turn of the run loop ends; the panel's
	 * sheet machinery is still on the stack below us. */
	CFAutorelease(CFBridgingRetain(self));
	[openCertificateViewers removeObject:self];
}

@end
