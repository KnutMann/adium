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

#import "AIXtrasPreferences.h"
#import "AIXtrasManager.h"
#import "AIXtraInfo.h"
#import "AIJSXtrasManager.h"
#import <Adium/AIPathUtilities.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIFileManagerAdditions.h>
#import <AIUtilities/AIImageAdditions.h>

/* xtras.adium.im still resolves and still serves the site, but its certificate is issued for
 * adiumxtras.com, so a browser opens it with a security warning. The paragraph shows the host
 * of whatever stands here, so both the sentence and the button follow this one line. */
#define ADIUM_XTRAS_PAGE		AILocalizedString(@"https://www.adiumxtras.com/","Adium xtras page. Localized only if a translated version exists.")

//Sibling folder an Xtra is parked in while it is switched off
#define DISABLED_FOLDER_SUFFIX	@" (Disabled)"

//Width the form starts out at; the preferences window resizes it to its column
#define XTRAS_PANE_INITIAL_WIDTH	540.0f

@interface AIXtrasPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (AISettingsFormView *)settingsForm;
- (void)populateForm:(AISettingsFormView *)form;
- (void)releaseListViews;
- (void)xtrasChanged:(NSNotification *)notification;
- (void)rebuildFormSoon;
- (void)rebuildForm;
- (void)trashXtra:(AIXtraInfo *)xtraInfo;
- (void)postXtrasDidChangeForType:(NSString *)type;
- (void)reportFailure:(NSString *)message forXtra:(AIXtraInfo *)xtraInfo error:(NSError *)error;
- (BOOL)xtraIsJavaScript:(AIXtraInfo *)xtraInfo;
- (BOOL)xtraIsBundled:(AIXtraInfo *)xtraInfo;
@end

@implementation AIXtrasPreferences

#pragma mark Preference pane properties

- (NSString *)paneIdentifier
{
	return @"Xtras";
}

- (NSString *)paneName
{
	/* The key the old Xtras window used for its title: every translation Adium ships already carries
	 * it, and it says what this pane is - "Xtra-Verwaltung" in German, and so on. */
	return AILocalizedString(@"Xtras Manager", "Name of the preference pane which manages installed Xtras");
}

- (NSImage *)paneIcon
{
	/* The document icon Adium gives an .AdiumPlugin bundle, which is also what the old Xtras
	 * window put beside the plug-in category. A copy per call, so the sidebar resizing this
	 * one cannot resize the copy the Finder icon or the category list is holding.
	 */
	NSImage	*icon = [[NSImage imageNamed:@"AdiumPlugin"] copy];

	if (icon) return icon;

	return [[NSImage imageNamed:@"xtras_duck" forClass:[self class]] copy];
}

#pragma mark View

/*!
 * @brief Build our view instead of loading a nib
 *
 * Mirrors -[AIModularPane view] so subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		AISettingsFormView	*form = [self buildSettingsForm];

		view = form;

		[self viewDidLoad];
		[self localizePane];

		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief The settings form we live in, or nil before -view built it
 */
- (AISettingsFormView *)settingsForm
{
	return ([view isKindOfClass:[AISettingsFormView class]] ? (AISettingsFormView *)view : nil);
}

- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[AISettingsFormView alloc] initWithWidth:XTRAS_PANE_INITIAL_WIDTH];

	[self populateForm:form];

	return form;
}

/*!
 * @brief Fill @a form with the "where Xtras come from" card, then one card per non-empty category
 *
 * Reads the set of installed Xtras afresh: -loadXtras throws away the manager's cache, so this is
 * also what makes an Xtra which appeared or disappeared while the pane was open show up correctly.
 *
 * A category with nothing in it is skipped. Drawing it would leave a bold heading standing above a
 * card of zero height, and on a normal installation eight of the ten categories are empty.
 */
- (void)populateForm:(AISettingsFormView *)form
{
	AIXtrasManager	*manager = [AIXtrasManager sharedManager];
	BOOL			 foundAny = NO;
	/* The host on its own is what the sentence names, not the whole URL - and it comes from the
	 * address the "Open" button actually opens, so a translation which points at a page of its own
	 * (ADIUM_XTRAS_PAGE is localizable) cannot end up telling the user one address while sending
	 * them to another. Whole URL if it will not parse: a hole in the sentence would be worse. */
	NSString		*website = ([[NSURL URLWithString:ADIUM_XTRAS_PAGE] host] ?: ADIUM_XTRAS_PAGE);

	if (!listViews) listViews = [[NSMutableArray alloc] init];

	[manager loadXtras];

	/* Where to get more, and where the ones you already have live - above the lists rather than
	 * below them. This is the one thing the pane can say to somebody who has installed nothing at
	 * all, and on a fresh installation that is everybody; making them scroll past the lists to
	 * find it would be backwards. No heading over this card: the two rows name themselves, and a
	 * heading on the very first card would only repeat the pane's own title.
	 *
	 * The duck is the one the old Xtras window carried in its toolbar for exactly this errand -
	 * fetching what is not there yet. */
	[form addInfoRow:[NSString stringWithFormat:
												AILocalizedString(@"More Xtras for Adium can be downloaded from the website %@. Double-click a downloaded Xtra to install it.",
																  "Paragraph at the top of the Xtras pane. %@ is the host name of the Xtras website."),
												website]
		   withImage:[NSImage imageNamed:@"xtras_duck" forClass:[self class]]
			   title:AILocalizedString(@"Xtras Website", "Heading of the paragraph pointing at xtras.adium.im")
			 control:[AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Open", nil)
													  target:self
													  action:@selector(browseXtras:)]];

	[form addRowWithLabel:AILocalizedString(@"Xtras Folder", "Row leading to the folder installed Xtras are kept in")
				  control:[AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Show in Finder", nil)
														   target:self
														   action:@selector(revealXtrasFolder:)]
				   detail:[[adium applicationSupportDirectory] stringByAbbreviatingWithTildeInPath]];

	for (NSInteger index = 0; index < (NSInteger)[manager numberOfCategories]; index++) {
		NSArray	*xtras = [manager xtrasForCategoryAtIndex:index];

		if (![xtras count]) continue;

		foundAny = YES;

		[form addSectionHeader:[manager nameOfCategoryAtIndex:index]];

		/* The list is the card: it fills it edge to edge and its height decides how tall the card
		 * is. Everything a row does - its switch, its ⊖, its context menu - comes back to us
		 * through AIXtraListViewDelegate. */
		AIXtraListView	*listView = [[AIXtraListView alloc] initWithXtras:xtras];

		[listView setListDelegate:self];
		[listViews addObject:listView];
		[form addEdgeToEdgeRow:listView];

		if ([manager categoryAtIndexIsJavaScript:index]) {
			//JavaScript plugins are injected live, so a change shows in every open message view at once
			[form addFootnote:AILocalizedString(@"JavaScript extensions take effect immediately.",
												"Footnote below the list of installed JavaScript extension Xtras")];
		} else if ([manager directoryOfCategoryAtIndex:index] == AIPluginsDirectory) {
			//Plugins are loaded once, at startup; switching one off here changes nothing until then
			[form addFootnote:AILocalizedString(@"Changes to plug-ins take effect after Adium is restarted.",
												"Footnote below the list of installed plug-in Xtras")];
		}
	}

	if (!foundAny) {
		/* Not a card per empty category, and not nothing either: a single card saying so, the shape
		 * System Settings gives a list which has nothing in it yet. It stands exactly where the
		 * categories would - under the card above, which has already said where Xtras come from. */
		[form addSectionHeader:AILocalizedString(@"Installed Xtras", "Section title above the list of installed Xtras")];
		[form addEmptyStateRow:AILocalizedString(@"No Xtras Installed", "Shown instead of the list when no Xtras are installed")];
	}
}

/*!
 * @brief Configure the view initially
 */
- (void)viewDidLoad
{
	/* An Xtra installed from the web arrives through XtrasInstaller, which posts this once it has
	 * copied the files into place - the only way this pane ever hears that the set of installed
	 * Xtras changed while it is on screen. */
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(xtrasChanged:)
												 name:AIXtrasDidChangeNotification
											   object:nil];
}

/*!
 * @brief Preference view is closing
 *
 * Note that this runs when the preferences <em>window</em> closes, not when the user picks another
 * pane: switching panes only takes our view out of the window, and the pane keeps its observer and
 * its lists. Nothing is lost by that, because nothing is ever held back - every change is written
 * to disk the moment it is made.
 */
- (void)viewWillClose
{
	/* Only our own registration: removeObserver:self would silently take any other one - a
	 * category's, a superclass's - with it. */
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:AIXtrasDidChangeNotification
												  object:nil];

	//A rebuild reaching a closed pane would ask -view for a form and so build a second one
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	rebuildScheduled = NO;

	[self releaseListViews];
}

/*!
 * @brief Undo everything -view built
 *
 * -closeView is idempotent, so running it from here as well as from the preferences window is safe;
 * it matters because a pane released without -viewWillClose would leave a notification observer
 * registered on freed memory.
 */
- (void)dealloc
{
	[self closeView];
}

/*!
 * @brief Cut every list loose from us and let go of them
 *
 * The lists live in the form's cards, which are released on a different path (-closeView, or
 * -removeAllSections on a rebuild). Their delegate and the target of every row's controls are
 * non-retaining references to us, so they are cleared before we let go.
 */
- (void)releaseListViews
{
	for (AIXtraListView *listView in listViews) {
		[listView tearDown];
	}

	[listViews removeAllObjects];
}

#pragma mark Keeping up to date

- (void)xtrasChanged:(NSNotification *)notification
{
	[self rebuildFormSoon];
}

/*!
 * @brief Rebuild the whole form once the run loop comes back around
 *
 * Coalesced on purpose: installing a single Xtra touches several files and posts more than one
 * notification, and each of those would otherwise pay for a complete rebuild. A rebuild which is
 * already scheduled is left alone rather than pushed back, so a long series of changes cannot defer
 * it indefinitely.
 */
- (void)rebuildFormSoon
{
	if (rebuildScheduled) return;

	rebuildScheduled = YES;
	[self performSelector:@selector(rebuildForm) withObject:nil afterDelay:0.0];
}

/*!
 * @brief Throw the form away and build it again from what is on disk now
 *
 * Cheaper than it sounds - three cards on a normal installation - and it is the only way a card
 * which was not there before (a category which just gained its first Xtra) can appear at all.
 */
- (void)rebuildForm
{
	rebuildScheduled = NO;

	AISettingsFormView	*form = [self settingsForm];

	if (!form) return;

	/* Where the scrolling column stands now: the form is empty for a moment while it is rebuilt,
	 * which drags the column back to the top. An Xtra arriving from the web must not make the page
	 * the user is reading jump. */
	NSClipView	*clipView = [[form enclosingScrollView] contentView];
	NSPoint		 scrollOrigin = (clipView ? [clipView bounds].origin : NSZeroPoint);

	[self releaseListViews];
	[form removeAllSections];

	[self populateForm:form];
	[form layoutForWidth:NSWidth([form frame])];

	if (clipView) {
		//Constrained, because the form may well be shorter than it was
		NSRect	proposed = NSMakeRect(scrollOrigin.x, scrollOrigin.y,
									  NSWidth([clipView bounds]), NSHeight([clipView bounds]));

		[clipView scrollToPoint:[clipView constrainBoundsRect:proposed].origin];
		[[form enclosingScrollView] reflectScrolledClipView:clipView];
	}
}

#pragma mark Actions

- (IBAction)browseXtras:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:ADIUM_XTRAS_PAGE]];
}

- (IBAction)revealXtrasFolder:(id)sender
{
	[[NSWorkspace sharedWorkspace] selectFile:nil
					 inFileViewerRootedAtPath:[adium applicationSupportDirectory]];
}

#pragma mark Xtra list delegate

- (void)xtraListViewDidChangeHeight:(AIXtraListView *)listView
{
	//The list is the edge to edge row of a card, so its height is the card's height
	[[self settingsForm] noteContentSizeChanged];
}

- (void)xtraListView:(AIXtraListView *)listView revealXtra:(AIXtraInfo *)xtraInfo
{
	[[NSWorkspace sharedWorkspace] selectFile:[xtraInfo path] inFileViewerRootedAtPath:@""];
}

/*!
 * @brief Switch an Xtra on or off by moving it in or out of a "(Disabled)" folder
 *
 * That folder is the mechanism Adium already uses: everything which looks for Xtras goes through
 * AISearchPathForDirectories(), which only ever returns "<Folder>" - so an Xtra sitting in
 * "<Folder> (Disabled)" beside it is invisible to every consumer without any of them knowing about
 * the convention. AICorePluginLoader and AISoundSet already park Xtras there themselves, and
 * -[AIXtrasManager arrayOfXtrasAtPaths:] is what reads them back out again.
 */
- (void)xtraListView:(AIXtraListView *)listView setEnabled:(BOOL)enabled forXtra:(AIXtraInfo *)xtraInfo
{
	/* A JavaScript plugin is not moved on disk to switch it - it is injected live, and the plugins
	 * that ship inside the app could not be moved anyway. Its switch is a preference the manager
	 * keeps and reads; writing it makes the manager re-scan and redraw every open message view on
	 * its own, so nothing here posts a further "the Xtras changed" of its own - that would only make
	 * the manager re-scan and every window redraw a second time, drawing the conversation twice. */
	if ([self xtraIsJavaScript:xtraInfo]) {
		NSString *identifier = [[xtraInfo bundle] bundleIdentifier];

		if ([identifier length])
			[[AIJSXtrasManager sharedManager] setPluginWithIdentifier:identifier enabled:enabled];

		[xtraInfo setEnabled:enabled];
		return;
	}

	NSFileManager	*fileManager = [NSFileManager defaultManager];
	NSString		*path = [xtraInfo path];
	NSString		*folder = [path stringByDeletingLastPathComponent];
	NSString		*folderName = [folder lastPathComponent];
	NSString		*enclosingFolder = [folder stringByDeletingLastPathComponent];
	BOOL			 isParked = [folderName hasSuffix:DISABLED_FOLDER_SUFFIX];
	NSString		*targetFolder;

	//Already where the new state wants it; nothing to move and nothing to tell anybody about
	if (enabled != isParked) return;

	if (enabled) {
		targetFolder = [enclosingFolder stringByAppendingPathComponent:
						[folderName substringToIndex:([folderName length] - [DISABLED_FOLDER_SUFFIX length])]];
	} else {
		targetFolder = [enclosingFolder stringByAppendingPathComponent:
						[folderName stringByAppendingString:DISABLED_FOLDER_SUFFIX]];
	}

	NSString		*targetPath = [targetFolder stringByAppendingPathComponent:[path lastPathComponent]];
	NSError			*error = nil;

	//Whether this worked is not worth asking: if it did not, the move right after it says why
	[fileManager createDirectoryAtPath:targetFolder withIntermediateDirectories:YES attributes:nil error:NULL];

	if (![fileManager moveItemAtPath:path toPath:targetPath error:&error]) {
		[self reportFailure:AILocalizedString(@"The Xtra could not be switched.",
											  "Title of the alert shown when enabling or disabling an Xtra failed")
					forXtra:xtraInfo
					  error:error];

		/* Nothing moved, so only the switch is wrong; reading the folders again is what puts it
		 * back where it was. */
		[self rebuildFormSoon];
		return;
	}

	[xtraInfo setEnabled:enabled];
	[self postXtrasDidChangeForType:[xtraInfo type]];
}

/*!
 * @brief Whether a row's switch is live
 *
 * A JavaScript plugin is switched by preference, so its switch works wherever the plugin lives -
 * the app's own bundle included, where nothing can be moved. Every other Xtra follows the list's
 * own rule, that only one in the user's folder may be switched off.
 */
- (BOOL)xtraListView:(AIXtraListView *)listView canToggleXtra:(AIXtraInfo *)xtraInfo whenMovable:(BOOL)movable
{
	if ([self xtraIsJavaScript:xtraInfo]) return YES;

	return movable;
}

/*!
 * @brief Whether a row keeps its ⊖
 *
 * A plugin that ships inside the app has no file of the user's to throw away; everything else can be
 * deleted, just as it always could.
 */
- (BOOL)xtraListView:(AIXtraListView *)listView canDeleteXtra:(AIXtraInfo *)xtraInfo whenMovable:(BOOL)movable
{
	return ![self xtraIsBundled:xtraInfo];
}

/*!
 * @brief Is this Xtra a JavaScript plugin?
 */
- (BOOL)xtraIsJavaScript:(AIXtraInfo *)xtraInfo
{
	return [[[xtraInfo bundle] objectForInfoDictionaryKey:@"AIJavaScriptPlugin"] boolValue];
}

/*!
 * @brief Does this Xtra ship inside the app rather than in a folder of the user's?
 */
- (BOOL)xtraIsBundled:(AIXtraInfo *)xtraInfo
{
	NSString	*path = [[xtraInfo path] stringByStandardizingPath];
	NSString	*appPath = [[[NSBundle mainBundle] bundlePath] stringByStandardizingPath];

	if (![path length] || ![appPath length]) return NO;

	return [path hasPrefix:[appPath stringByAppendingString:@"/"]];
}

/*!
 * @brief Ask before throwing an Xtra away, then throw it away
 *
 * The question is the point: an Xtra which is in use right now - the message style of every open
 * chat, the sound set of every event - is deleted just as readily as an unused one, and only the
 * user can know which is which. Adium copes afterwards (a message style which will not load falls
 * back to the default, the icon packs fall back to theirs), but the file itself is in the Trash and
 * nothing but this sheet stands between the user and that.
 */
- (void)xtraListView:(AIXtraListView *)listView deleteXtra:(AIXtraInfo *)xtraInfo
{
	NSAlert		*warning = [[NSAlert alloc] init];
	NSWindow	*sheetParent = [view window];

	[warning setMessageText:AILocalizedString(@"Delete Xtra?", nil)];
	[warning setInformativeText:[NSString stringWithFormat:
								 AILocalizedString(@"“%@” will be moved to the Trash.",
												   "Confirmation before deleting an Xtra. %@ is the name of the Xtra."),
								 ([xtraInfo name] ?: @"")]];
	[warning addButtonWithTitle:AILocalizedString(@"Delete", nil)];	//NSAlertFirstButtonReturn, the default button
	[warning addButtonWithTitle:AILocalizedString(@"Cancel", nil)];

	/* The block keeps the Xtra and us alive until the sheet is answered; the list holding it may
	 * well have been rebuilt and released by then. */
	void (^completionHandler)(NSModalResponse) = ^(NSModalResponse returnCode) {
		if (returnCode == NSAlertFirstButtonReturn) [self trashXtra:xtraInfo];
	};

	if (sheetParent) {
		[warning beginSheetModalForWindow:sheetParent completionHandler:completionHandler];
	} else {
		completionHandler([warning runModal]);
	}
}

- (void)trashXtra:(AIXtraInfo *)xtraInfo
{
	/* The old window threw the result away. It is not a formality: in /Library/Application Support
	 * or on a read-only volume the file stays exactly where it is, and a row which disappeared all
	 * the same would be back the next time the folders are read. */
	if (![[NSFileManager defaultManager] trashFileAtPath:[xtraInfo path]]) {
		[self reportFailure:AILocalizedString(@"The Xtra could not be moved to the Trash.",
											  "Title of the alert shown when deleting an Xtra failed")
					forXtra:xtraInfo
					  error:nil];
		return;
	}

	[self postXtrasDidChangeForType:[xtraInfo type]];
}

/*!
 * @brief Tell the rest of Adium that the installed Xtras changed
 *
 * The notification carries the Xtra's type, which is its filename extension: every receiver
 * compares it case-insensitively against the extension it cares about. An Xtra without one - a lone
 * .ListLayout plist, an old sound set folder - would match nobody, so it is posted with no object at
 * all, which every receiver reads as "rebuild everything".
 */
- (void)postXtrasDidChangeForType:(NSString *)type
{
	[[NSNotificationCenter defaultCenter] postNotificationName:AIXtrasDidChangeNotification
														object:([type length] ? type : nil)];
}

/*!
 * @brief Say that a file operation did not happen, and why it might not have
 *
 * The reason has to be asked for: the one failure which nobody caused is a second Xtra of the same
 * name at the destination. Adium's own installer copies into "<Folder>" without ever looking at
 * "<Folder> (Disabled)" beside it, and AICorePluginLoader and AISoundSet park Xtras there by
 * themselves, so both folders can hold the same name without anybody noticing. NSFileManager
 * refuses to overwrite, which is right - but blaming the folder's permissions for it sends the user
 * to check something which is in perfect order.
 */
- (void)reportFailure:(NSString *)message forXtra:(AIXtraInfo *)xtraInfo error:(NSError *)error
{
	NSAlert		*alert = [[NSAlert alloc] init];
	NSWindow	*sheetParent = [view window];
	NSString	*explanation;

	if ([[error domain] isEqualToString:NSCocoaErrorDomain] && [error code] == NSFileWriteFileExistsError) {
		explanation = AILocalizedString(@"An Xtra of this name is already where this one would have to go. Delete one of the two to switch the other.",
										"Explanation shown when an Xtra could not be switched because one of the same name is in the way");
	} else {
		explanation = [NSString stringWithFormat:
					   AILocalizedString(@"Adium may not be allowed to change the folder this Xtra is in:\n%@",
										 "Explanation shown when an Xtra could not be moved or deleted. %@ is a folder path."),
					   [[[xtraInfo path] stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath]];
	}

	[alert setMessageText:message];
	[alert setInformativeText:explanation];
	[alert addButtonWithTitle:AILocalizedStringFromTable(@"OK", @"Buttons", nil)];

	if (sheetParent) {
		[alert beginSheetModalForWindow:sheetParent completionHandler:nil];
	} else {
		[alert runModal];
	}
}

@end
