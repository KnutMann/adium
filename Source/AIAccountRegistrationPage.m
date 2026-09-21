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

#import "AIAccountRegistrationPage.h"

#import <Adium/AIAccount.h>
#import <Adium/AIService.h>
#import <Adium/AISettingsFormView.h>
#import <Adium/AISettingsNavigationController.h>
#import <AIUtilities/AIStringUtilities.h>
#import <AIUtilities/AITableViewAdditions.h>

/* The XMPP Providers project's list, in the shape a client is meant to read: providers-B are
 * the ones anyone can sign up with. The old feed on xmpp.org that the previous dialog read has
 * been gone for years. */
#define PROVIDERS_URL		@"https://data.xmpp.net/providers/v2/providers-B.json"

#define FORM_WIDTH			600.0f
#define LIST_ROW_HEIGHT		24.0f
#define LIST_ROWS_SHOWN		8			//More than this, and the list scrolls
#define LIST_PADDING		10.0f		//Above the first and below the last row, inside the card

#define COLUMN_SERVER		@"jid"
#define COLUMN_LOCATION		@"location"

@interface AIAccountRegistrationPage ()
- (void)makeControls;
- (void)makeList;
- (void)buildForm;
- (void)sizeList;
- (void)noteHeightChanged;
- (void)fetchServers;
- (void)fetchedServers:(NSArray *)inServers;
+ (NSArray *)serversFromProviderList:(id)list;
- (void)requestAccount:(id)sender;
- (void)visitHomepage:(id)sender;
- (void)registered:(NSNotification *)notification;
- (void)registrationFailed:(NSNotification *)notification;
@end

@implementation AIAccountRegistrationPage

- (id)initWithAccount:(AIAccount *)inAccount
{
	if ((self = [super initWithNibName:nil bundle:nil])) {
		account = inAccount;

		/* Only XMPP has public servers to choose from; any other service that registers does so
		 * wherever the account already points. */
		offersServerList = [[[account service] serviceClass] isEqualToString:@"Jabber"];

		//A request may be out already, if this page was left and opened again while it ran
		registering = [account boolValueForProperty:@"isRegistering"];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(registered:)
													 name:AIAccountUsernameAndPasswordRegisteredNotification
												   object:account];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(registrationFailed:)
													 name:AIAccountRegistrationFailedNotification
												   object:account];
	}

	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[fetchTask cancel];
	[tableView setDelegate:nil];
	[tableView setDataSource:nil];
}

/*!
 * @brief The picture over the explanation: a person being added
 */
- (NSImage *)image
{
	NSImage *image = nil;

	if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)])
		image = [NSImage imageWithSystemSymbolName:@"person.crop.circle.badge.plus" accessibilityDescription:nil];

	if (!image)
		return nil;

	NSImageSymbolConfiguration *configuration =
		[NSImageSymbolConfiguration configurationWithPointSize:30.0
													  weight:NSFontWeightRegular
													   scale:NSImageSymbolScaleLarge];

	return [image imageWithSymbolConfiguration:configuration];
}

- (void)loadView
{
	form = [[AISettingsFormView alloc] initWithWidth:FORM_WIDTH];
	[form setSharesLabelColumn:YES];

	[self makeControls];

	if (offersServerList) {
		[self makeList];
		[self fetchServers];
	}

	[self buildForm];
	[self setView:form];
}

//The controls -------------------------------------------------------------------------------------------------------
#pragma mark The controls

/*!
 * @brief Make every control once; the form is rebuilt around them as the state changes
 *
 * Whatever was typed survives a rebuild that way: the list arriving, or a request failing, does not
 * empty the fields.
 */
- (void)makeControls
{
	serverField = [AISettingsFormView textFieldWithTarget:nil action:NULL];
	usernameField = [AISettingsFormView textFieldWithTarget:nil action:NULL];

	/* The same shape as the password field on the account's own page, so the two line up when the
	 * pages slide over each other. */
	passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 160.0, 22.0)];

	//Start from what the account is called, when it is called anything yet
	NSString	*uid = [account UID];
	NSRange		at = [uid rangeOfString:@"@"];

	if (at.location != NSNotFound) {
		[usernameField setStringValue:[uid substringToIndex:at.location]];
		[serverField setStringValue:[uid substringFromIndex:(at.location + 1)]];
	} else if ([uid length]) {
		[usernameField setStringValue:uid];
	}

	requestButton = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Request New Account", nil)
													 target:self
													 action:@selector(requestAccount:)];
	homepageButton = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Visit Server Homepage", nil)
													  target:self
													  action:@selector(visitHomepage:)];
	[homepageButton setEnabled:NO];

	spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0, 0.0, 16.0, 16.0)];
	[spinner setStyle:NSProgressIndicatorStyleSpinning];
	[spinner setControlSize:NSControlSizeSmall];
	[spinner setDisplayedWhenStopped:NO];
	[spinner sizeToFit];

	statusLabel = [NSTextField labelWithString:AILocalizedString(@"Registering…", nil)];
	[statusLabel setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[statusLabel setTextColor:[NSColor secondaryLabelColor]];
	[statusLabel sizeToFit];
}

/*!
 * @brief The list of public servers: a table hosted edge to edge in its card
 *
 * The card around it is the form's, which also rounds the corners, so nothing here draws a border
 * or a background of its own. Two columns and no header: the server, and where it stands.
 */
- (void)makeList
{
	scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, FORM_WIDTH, LIST_ROW_HEIGHT + 2.0f * LIST_PADDING)];
	tableView = [[NSTableView alloc] initWithFrame:[scrollView bounds]];

	[tableView setDataSource:self];
	[tableView setDelegate:self];
	[tableView setHeaderView:nil];
	[tableView setCornerView:nil];
	[tableView setRowHeight:LIST_ROW_HEIGHT];
	[tableView setIntercellSpacing:NSZeroSize];
	[tableView setGridStyleMask:NSTableViewGridNone];
	[tableView setUsesAlternatingRowBackgroundColors:YES];
	[tableView setBackgroundColor:[NSColor clearColor]];
	[tableView setAllowsMultipleSelection:NO];
	[tableView setAllowsEmptySelection:YES];
	[tableView setAllowsColumnReordering:NO];
	[tableView setAllowsColumnResizing:NO];
	[tableView setFocusRingType:NSFocusRingTypeNone];
	[tableView setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[tableView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	if (@available(macOS 11.0, *)) {
		[tableView setStyle:NSTableViewStyleInset];
	}

	NSTableColumn *serverColumn = [[NSTableColumn alloc] initWithIdentifier:COLUMN_SERVER];
	[serverColumn setResizingMask:NSTableColumnAutoresizingMask];
	[serverColumn setEditable:NO];
	[serverColumn setMinWidth:120.0f];
	[serverColumn setWidth:360.0f];
	[tableView addTableColumn:serverColumn];

	NSTableColumn *locationColumn = [[NSTableColumn alloc] initWithIdentifier:COLUMN_LOCATION];
	[locationColumn setResizingMask:NSTableColumnAutoresizingMask];
	[locationColumn setEditable:NO];
	[locationColumn setMinWidth:80.0f];
	[locationColumn setWidth:200.0f];
	[tableView addTableColumn:locationColumn];

	[scrollView setDocumentView:tableView];
	[scrollView setBorderType:NSNoBorder];
	[scrollView setDrawsBackground:NO];
	[scrollView setHasHorizontalScroller:NO];
	[scrollView setHorizontalScrollElasticity:NSScrollElasticityNone];
	[scrollView setAutomaticallyAdjustsContentInsets:NO];
	[scrollView setContentInsets:NSEdgeInsetsMake(LIST_PADDING, 0.0, LIST_PADDING, 0.0)];
	[scrollView setAutoresizingMask:NSViewWidthSizable];
}

/*!
 * @brief As tall as its rows, up to a point; past that it scrolls
 */
- (void)sizeList
{
	NSUInteger	shown = MIN([servers count], (NSUInteger)LIST_ROWS_SHOWN);
	BOOL		scrolls = ([servers count] > LIST_ROWS_SHOWN);

	[scrollView setHasVerticalScroller:scrolls];
	[scrollView setVerticalScrollElasticity:(scrolls ? NSScrollElasticityAutomatic : NSScrollElasticityNone)];
	[scrollView setFrameSize:NSMakeSize(NSWidth([scrollView frame]), shown * LIST_ROW_HEIGHT + 2.0f * LIST_PADDING)];
}

//The form -----------------------------------------------------------------------------------------------------------
#pragma mark The form

/*!
 * @brief Lay the page out for the state it is in
 *
 * Cheap enough to do whole every time something changes: the list arriving, a request going out,
 * an answer coming back. The controls are the same objects throughout.
 */
- (void)buildForm
{
	/* Connecting is what the account says of itself while it registers too, since a registration
	 * is a connection; that one is not a sign in and must not read as one, or a failed request
	 * would leave the page telling the user to disconnect an account that never was connected. */
	BOOL online = (([account online] || [account boolValueForProperty:@"isConnecting"]) &&
				   ![account boolValueForProperty:@"isRegistering"]);
	BOOL busy = (registering || online);

	[form removeAllSections];

	if (offersServerList) {
		[form addInfoRow:AILocalizedString(@"Pick a server from the list or enter one, choose a name and a password, and the server creates the account. The list holds public servers that let anyone register from within Adium; the XMPP Providers project keeps it.",
										   "Explains the page on which a new XMPP account is registered at a public server")
			   withImage:[self image]
				   title:AILocalizedString(@"An account on a public server",
										   "Title of the block above the fields for registering a new account")
				 control:nil];
	} else {
		[form addInfoRow:AILocalizedString(@"The service creates the account under the name it already has. All it needs is a password.",
										   "Explains the registration page for a service without a list of public servers")
			   withImage:[self image]
				   title:AILocalizedString(@"A new account",
										   "Title of the block above the password field when registering with a service that has no server list")
				 control:nil];
	}

	if (offersServerList) {
		[form addSectionHeader:AILocalizedString(@"Public Servers", "Section title above the list of public XMPP servers that register new accounts")];

		if ([servers count]) {
			[self sizeList];
			[form addEdgeToEdgeRow:scrollView];
			[form addTrailingAccessoryView:homepageButton];
		} else if (loading) {
			[form addEmptyStateRow:AILocalizedString(@"Loading the list of public servers…",
													 "Shown in place of the server list while it is being fetched")];
		} else {
			[form addEmptyStateRow:AILocalizedString(@"The list of public servers could not be loaded. A server can still be entered below.",
													 "Shown in place of the server list when fetching it failed")];
		}
	}

	[form addSectionHeader:AILocalizedString(@"New Account", "Section title above the fields for the account to register")];

	if (offersServerList) {
		[form addRowWithLabel:AILocalizedString(@"Server", nil) stretchingControl:serverField];
		[form addRowWithLabel:AILocalizedString(@"Username", "Label of the field for the name part of a new XMPP address, the part before the @")
			stretchingControl:usernameField];
	}
	[form addRowWithLabel:AILocalizedString(@"Password", nil) control:passwordField];

	[serverField setEnabled:!busy];
	[usernameField setEnabled:!busy];
	[passwordField setEnabled:!busy];
	[requestButton setEnabled:!busy];

	if (registering)
		[spinner startAnimation:nil];
	else
		[spinner stopAnimation:nil];

	//The button hangs under the card's trailing corner; while a request is out, what it is doing stands beside it
	NSArray *bar = (registering ? @[spinner, statusLabel, requestButton] : @[requestButton]);
	[form addTrailingAccessoryView:[AISettingsFormView rowOfViews:bar]];

	if (online) {
		[form addFootnote:AILocalizedString(@"Disconnect the account first: a registration needs its connection.",
											"Under the registration fields while the account is online")];
	} else if (problem) {
		[form addFootnote:problem];
	}

	[form layoutForWidth:FORM_WIDTH];
	[self noteHeightChanged];
}

- (void)noteHeightChanged
{
	/* Not while the view is still being made: the container is already this page's parent by then,
	 * and asked for the showing page's height it asks this page for its view, which is exactly what
	 * is being made. That is loadView calling loadView until the stack runs out, and until it does,
	 * a beachball. The first height reaches the container with the push itself. */
	if (![self isViewLoaded])
		return;

	id parent = [self parentViewController];

	if ([parent isKindOfClass:[AISettingsNavigationController class]])
		[(AISettingsNavigationController *)parent noteContentHeightChanged];
}

//The public servers -------------------------------------------------------------------------------------------------
#pragma mark The public servers

- (void)fetchServers
{
	__weak AIAccountRegistrationPage *weakSelf = self;

	loading = YES;

	fetchTask = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:PROVIDERS_URL]
										   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		id		 list = (data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil);
		NSArray	*found = [AIAccountRegistrationPage serversFromProviderList:list];

		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf fetchedServers:found];
		});
	}];
	[fetchTask resume];
}

- (void)fetchedServers:(NSArray *)inServers
{
	loading = NO;
	fetchTask = nil;
	servers = inServers;

	[tableView reloadData];
	[self buildForm];
}

/*!
 * @brief The servers worth listing, from what the project publishes
 *
 * Only those that register anyone from within a client and ask for nothing but a name and a
 * password: a captcha is a picture the form here cannot show, and an e-mail address is a question
 * it does not ask. Countries become names in the user's language.
 */
+ (NSArray *)serversFromProviderList:(id)list
{
	if (![list isKindOfClass:[NSArray class]])
		return nil;

	NSMutableArray	*found = [NSMutableArray array];
	NSLocale		*locale = [NSLocale currentLocale];

	for (id entry in list) {
		if (![entry isKindOfClass:[NSDictionary class]])
			continue;

		NSString *jid = [entry objectForKey:@"jid"];

		if (![jid isKindOfClass:[NSString class]] || ![jid length])
			continue;
		if (![[entry objectForKey:@"inBandRegistration"] boolValue] ||
			[[entry objectForKey:@"inBandRegistrationCaptchaRequired"] boolValue] ||
			[[entry objectForKey:@"inBandRegistrationEmailAddressRequired"] boolValue])
			continue;

		NSMutableArray	*places = [NSMutableArray array];
		id				 locations = [entry objectForKey:@"serverLocations"];

		if ([locations isKindOfClass:[NSArray class]]) {
			for (id code in locations) {
				if (![code isKindOfClass:[NSString class]])
					continue;

				NSString *name = [locale localizedStringForCountryCode:[code uppercaseString]];
				[places addObject:(name ?: code)];
			}
		}

		NSMutableDictionary *server = [NSMutableDictionary dictionaryWithObjectsAndKeys:
									   jid, COLUMN_SERVER,
									   [places componentsJoinedByString:@", "], COLUMN_LOCATION,
									   nil];

		//The website comes by language; English is the one every entry has
		id			 website = [entry objectForKey:@"website"];
		NSString	*address = nil;

		if ([website isKindOfClass:[NSDictionary class]])
			address = ([website objectForKey:@"en"] ?: [[website allValues] firstObject]);
		else if ([website isKindOfClass:[NSString class]])
			address = website;

		NSURL *url = ([address isKindOfClass:[NSString class]] ? [NSURL URLWithString:address] : nil);

		if (url)
			[server setObject:url forKey:@"website"];

		[found addObject:server];
	}

	[found sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:COLUMN_SERVER
																ascending:YES
																 selector:@selector(localizedCaseInsensitiveCompare:)]]];

	return found;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [servers count];
}

- (NSView *)tableView:(NSTableView *)aTableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[servers count])
		return nil;

	NSDictionary	*server = [servers objectAtIndex:row];
	NSTableCellView	*view = [aTableView ai_labelCellViewForColumn:tableColumn
															value:[server objectForKey:[tableColumn identifier]]];

	//Where a server stands is the aside, the server is the point
	if ([[tableColumn identifier] isEqualToString:COLUMN_LOCATION])
		[[view textField] setTextColor:[NSColor secondaryLabelColor]];

	return view;
}

/*!
 * @brief A picked server goes into the field; the field is what counts when the request goes out
 */
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger		row = [tableView selectedRow];
	NSDictionary	*server = ((row >= 0 && row < (NSInteger)[servers count]) ? [servers objectAtIndex:row] : nil);

	if (server)
		[serverField setStringValue:[server objectForKey:COLUMN_SERVER]];

	[homepageButton setEnabled:([server objectForKey:@"website"] != nil)];
}

- (void)visitHomepage:(id)sender
{
	NSInteger row = [tableView selectedRow];

	if (row < 0 || row >= (NSInteger)[servers count])
		return;

	NSURL *url = [[servers objectAtIndex:row] objectForKey:@"website"];

	if (url)
		[[NSWorkspace sharedWorkspace] openURL:url];
}

//Registering --------------------------------------------------------------------------------------------------------
#pragma mark Registering

- (void)requestAccount:(id)sender
{
	//Take what is in the fields, including the one still being typed in
	[[[self view] window] makeFirstResponder:nil];

	NSCharacterSet	*blank = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSString		*server = [[serverField stringValue] stringByTrimmingCharactersInSet:blank];
	NSString		*username = [[usernameField stringValue] stringByTrimmingCharactersInSet:blank];
	NSString		*password = [passwordField stringValue];
	NSString		*uid = [account UID];

	if (offersServerList) {
		//A whole address in the name field names the server as well, if the server field does not
		NSRange at = [username rangeOfString:@"@"];

		if (at.location != NSNotFound) {
			if (![server length])
				server = [username substringFromIndex:(at.location + 1)];
			username = [username substringToIndex:at.location];
		}

		NSTextField *missing = (![server length] ? serverField : (![username length] ? usernameField : nil));

		if (missing) {
			NSBeep();
			[[missing window] makeFirstResponder:missing];
			return;
		}

		uid = [NSString stringWithFormat:@"%@@%@", username, server];
	}

	if (![password length]) {
		NSBeep();
		[[passwordField window] makeFirstResponder:passwordField];
		return;
	}

	problem = nil;
	registering = YES;
	[self buildForm];

	[account registerNewAccountWithUID:uid password:password];
}

/*!
 * @brief The account behind this page has its new name and password; back to it
 */
- (void)registered:(NSNotification *)notification
{
	id parent = [self parentViewController];

	registering = NO;

	if ([parent isKindOfClass:[AISettingsNavigationController class]] &&
		[(AISettingsNavigationController *)parent topViewController] == self)
		[(AISettingsNavigationController *)parent popViewControllerAnimated:YES];
	else
		[self buildForm];
}

/*!
 * @brief Nothing was registered; the account has its old name back
 *
 * The protocol has usually put the reason in front of the user already, in a message of its own.
 * What the notification carries is the reason when it has not: a server that could not be reached.
 */
- (void)registrationFailed:(NSNotification *)notification
{
	NSString *error = [[notification userInfo] objectForKey:@"error"];

	registering = NO;
	problem = ([error length] ?
			   [NSString stringWithFormat:AILocalizedString(@"Registration failed: %@", "Under the registration fields; %@ is the reason the connection gave"), error] :
			   AILocalizedString(@"The server declined the registration.", "Under the registration fields when the server said no"));

	[self buildForm];
}

@end
