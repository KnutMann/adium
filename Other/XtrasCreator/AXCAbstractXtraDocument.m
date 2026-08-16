//
//  AXCAbstractXtraDocument.m
//  XtrasCreator
//
//  Created by David Smith on 10/27/05.
//  Copyright 2005 Adium Team. All rights reserved.
//

#import "AXCAbstractXtraDocument.h"

#import "AXCFileCell.h"
#import "NSMutableArrayAdditions.h"

#define THUMBNAIL_SIZE 16.0
#define RESOURCE_SIZE_COLUMN_NAME @"dimensions"

@interface AXCFileListDataSource : NSObject {
	AXCAbstractXtraDocument *document;
	id originalDataSource;
}

- (id)initWithDocument:(AXCAbstractXtraDocument *)newDocument dataSource:(id)newDataSource;
- (NSArray *)resourcesAtRows:(NSIndexSet *)rows;

@end

@implementation AXCFileListDataSource

- (id)initWithDocument:(AXCAbstractXtraDocument *)newDocument dataSource:(id)newDataSource
{
	if ((self = [super init])) {
		document = newDocument; //The document owns the file list and this proxy.
		originalDataSource = [newDataSource retain];
	}
	return self;
}

- (void)dealloc
{
	[originalDataSource release];
	[super dealloc];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [[originalDataSource arrangedObjects] count];
}

- (NSArray *)resourcesAtRows:(NSIndexSet *)rows
{
	NSArray *arrangedResources = [originalDataSource arrangedObjects];
	NSMutableArray *selectedResources = [NSMutableArray arrayWithCapacity:[rows count]];
	NSUInteger row = [rows firstIndex];
	while (row != NSNotFound) {
		if (row < [arrangedResources count])
			[selectedResources addObject:[arrangedResources objectAtIndex:row]];
		row = [rows indexGreaterThanIndex:row];
	}

	return selectedResources;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSArray *resources = [originalDataSource arrangedObjects];
	if (row < 0 || row >= [resources count])
		return @"";

	NSString *resourcePath = [resources objectAtIndex:(NSUInteger)row];
	if ([[tableColumn identifier] isEqualToString:RESOURCE_SIZE_COLUMN_NAME]) {
		NSString *size = [document imageSizeStringForResource:resourcePath];
		return size ? size : @"";
	}

	return resourcePath;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	return [originalDataSource tableView:tableView validateDrop:info proposedRow:row proposedDropOperation:operation];
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	return [originalDataSource tableView:tableView acceptDrop:info row:row dropOperation:operation];
}

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pasteboard
{
	return [originalDataSource tableView:tableView writeRowsWithIndexes:rowIndexes toPasteboard:pasteboard];
}

@end

static NSString *AXCLegacyBundleIdentifier(void)
{
	return [NSString stringWithFormat:@"com.adiumx.xtra.%@", [[NSUUID UUID] UUIDString]];
}

@implementation AXCAbstractXtraDocument

- (id)init
{
	if ((self = [super init])) {
		resources = [[NSMutableArray alloc] init];
		resourcesSet = [[NSMutableSet alloc] init];
		readmeIsRichText = YES;
	}
	return self;
}

- (void)dealloc
{
	[name release];
	[author release];
	[version release];
	[bundleID release];
	[bundle release];
	[icon release];
	[readme release];
	
	[resources release];
	[resourcesSet release];
	[imagePreviews release];
	[displayNames release];
	[imageSizeStrings release];
	if (resourceRemovalEventMonitor) {
		[NSEvent removeMonitor:resourceRemovalEventMonitor];
		[resourceRemovalEventMonitor release];
	}
	[fileViewDataSource release];

	[super dealloc];
}

#pragma mark -

- (NSString *) absolutePathForFile:(NSString *)path
{
	if ([path isAbsolutePath])
		return path;
	else
		return [[bundle resourcePath] stringByAppendingPathComponent:path];
}

- (NSImage *) previewForFile:(NSString *)path
{
	NSImage *image = [imagePreviews objectForKey:path];
	if (!image) {
		image = [[[NSImage alloc] initWithContentsOfFile:[self absolutePathForFile:path]] autorelease];
		NSSize size = [image size]; //note: only used if image != nil
		if (image) {
			if (!imagePreviews)
				imagePreviews = [[NSMutableDictionary alloc] init];
			
			NSSize previewSize = size;
			float maxDimension = MAX(size.width, size.height);
			if (maxDimension > THUMBNAIL_SIZE) {
				//scale proportionally to Wx16 or 16xH.
				float scale = maxDimension / THUMBNAIL_SIZE;
				previewSize.width  /= scale;
				previewSize.height /= scale;
				[image setScalesWhenResized:YES];
				[image setSize:previewSize];
			}
			[image setFlipped:YES];
			[image setName:[@"Preview of " stringByAppendingString:path]];
			
			[imagePreviews setObject:image forKey:path];
		}
	}	
	return image;
}

- (NSString *)imageSizeStringForResource:(NSString *)path
{
	if (!path)
		return nil;

	NSString *sizeString = [imageSizeStrings objectForKey:path];
	if (sizeString)
		return sizeString;

	NSImage *image = [[NSImage alloc] initWithContentsOfFile:[self absolutePathForFile:path]];
	if (!image)
		return nil;

	NSImageRep *largestRepresentation = nil;
	NSInteger largestArea = 0;
	for (NSImageRep *representation in [image representations]) {
		NSInteger width = [representation pixelsWide];
		NSInteger height = [representation pixelsHigh];
		NSInteger area = width * height;
		if (area > largestArea) {
			largestRepresentation = representation;
			largestArea = area;
		}
	}

	NSInteger width = [largestRepresentation pixelsWide];
	NSInteger height = [largestRepresentation pixelsHigh];
	if (width > 0 && height > 0)
		sizeString = [NSString stringWithFormat:@"%ldx%ld", (long)width, (long)height];

	[image release];
	if (sizeString) {
		if (!imageSizeStrings)
			imageSizeStrings = [[NSMutableDictionary alloc] init];
		[imageSizeStrings setObject:sizeString forKey:path];
	}

	return sizeString;
}

#pragma mark -

- (void) addResource:(NSString *)path
{
	[self willChangeValueForKey:@"resources"];

	[resources    addObject:path];
	[resourcesSet addObject:path];

	if ([imagePreviews objectForKey:path])
		[imagePreviews removeObjectForKey:path];
	[imageSizeStrings removeObjectForKey:path];
	if (!displayNames)
		displayNames = [[NSMutableDictionary alloc] init];
	[displayNames setObject:[[NSFileManager defaultManager] displayNameAtPath:[self absolutePathForFile:path]] forKey:path];

	[self didChangeValueForKey:@"resources"];
}
- (void) addResources:(NSArray *)paths
{
	NSIndexSet *newIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange([resources count], [paths count])];
	[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:newIndexes forKey:@"resources"];

	[resources    addObjectsFromArray:paths];
	[resourcesSet addObjectsFromArray:paths];
	
	//Add the files to the image previews and display names dictionaries.
	NSEnumerator *pathsEnum = [paths objectEnumerator];
	NSString *path;
	while ((path = [pathsEnum nextObject])) {
		//First the image preview.
		[self previewForFile:path];
		[imageSizeStrings removeObjectForKey:path];

		/*Now store the display name as well.*/ {
			if (!displayNames)
				displayNames = [[NSMutableDictionary alloc] init];

			NSString *displayName = [[NSFileManager defaultManager] displayNameAtPath:[self absolutePathForFile:path]];
			[displayNames setObject:displayName forKey:path];
		}
	}
	
	[self didChangeValueForKey:@"resources"];
}

- (void) removeResource:(NSString *)path
{
	NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:[resources indexOfObject:path]];
	[self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexSet forKey:@"resources"];

	[resources    removeObject:path];
	[resourcesSet removeObject:path];

	if ([imagePreviews objectForKey:path])
		[imagePreviews removeObjectForKey:path];
	[displayNames removeObjectForKey:path];
	[imageSizeStrings removeObjectForKey:path];

	[self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexSet forKey:@"resources"];
}
- (void) removeResources:(NSArray *)paths
{
	//XXX should look at using NSKeyValueChangeRemoval here
	[self willChangeValueForKey:@"resources"];
	[resources removeObjectsInArray:paths];

	NSSet *temp = [[NSSet alloc] initWithArray:paths];
	[resourcesSet minusSet:temp];
	[temp release];

	[imagePreviews removeObjectsForKeys:paths];
	[displayNames  removeObjectsForKeys:paths];
	[imageSizeStrings removeObjectsForKeys:paths];

	[self didChangeValueForKey:@"resources"];
}

- (void) setResources:(NSArray *)newResources
{
	NSSet *temp = [[NSSet alloc] initWithArray:newResources];
	
	NSMutableSet *resourcesBeingAdded = [temp mutableCopy];
	[resourcesBeingAdded minusSet:resourcesSet];
	NSMutableSet *resourcesBeingRemoved = [resourcesSet mutableCopy];
	[resourcesBeingRemoved minusSet:temp];
	
	[temp release];
	
	[self removeResources:[resourcesBeingRemoved allObjects]];
	[self    addResources:[resourcesBeingAdded   allObjects]];
}

#pragma mark -

- (NSString *)windowNibName
{
	// Override returning the nib file name of the document
	// If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
	return @"MyDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)controller
{
    [super windowControllerDidLoadNib:controller];

	/*set up cell in table view*/ {
		AXCFileCell *cell = [[AXCFileCell alloc] initTextCell:@""];
		[[[fileView tableColumns] objectAtIndex:0U] setDataCell:cell];
		[cell release];

		fileViewDataSource = [[AXCFileListDataSource alloc] initWithDocument:self dataSource:[fileView dataSource]];
		[fileView setDataSource:fileViewDataSource];

		NSTableColumn *fileSizeColumn = [[NSTableColumn alloc] initWithIdentifier:RESOURCE_SIZE_COLUMN_NAME];
		[fileSizeColumn setWidth:64.0];
		[fileSizeColumn setMinWidth:64.0];
		[fileSizeColumn setMaxWidth:64.0];
		[fileSizeColumn setResizingMask:NSTableColumnNoResizing];
		[fileSizeColumn setEditable:NO];
		[[fileSizeColumn headerCell] setStringValue:@"Size"];
		[[fileSizeColumn dataCell] setAlignment:NSTextAlignmentRight];

		[fileView addTableColumn:fileSizeColumn];
		[fileView setColumnAutoresizingStyle:NSTableViewFirstColumnOnlyAutoresizingStyle];
		[fileSizeColumn release];
	}

	resourceRemovalEventMonitor = [[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
		handler:^NSEvent *(NSEvent *event) {
			unsigned short keyCode = [event keyCode];
			if ((keyCode == 51 || keyCode == 117)
				&& [event window] == [fileView window]
				&& [[event window] firstResponder] == fileView
				&& [fileView selectedRow] != -1) {
				[self removeSelectedResources:nil];
				return nil;
			}
			return event;
		}] retain];

	/*set up table view the drag types*/ {
		[fileView registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
	}

	/*fill in tab view*/ {
		NSEnumerator * tabViewItemsEnum = [[self tabViewItems] objectEnumerator];
		NSTabViewItem * item;
		while((item = [tabViewItemsEnum nextObject]))
			[tabs addTabViewItem:item];
	}
}

- (IBAction)removeSelectedResources:(id)sender
{
	NSIndexSet *selectedRows = [fileView selectedRowIndexes];
	if (![selectedRows count])
		return;

	NSArray *selectedResources = [fileViewDataSource resourcesAtRows:selectedRows];
	[self removeResources:selectedResources];
	[fileView deselectAll:nil];
}

- (BOOL)writeToFile:(NSString *)fileName ofType:(NSString *)docType
{
	NSString * bundlePath = fileName;
	NSFileManager * manager = [NSFileManager defaultManager];
	if ([manager fileExistsAtPath:bundlePath])
		return NO;

	NSString *contentsPath = [bundlePath stringByAppendingPathComponent:@"Contents"];
	NSString *resourcesPath = [contentsPath stringByAppendingPathComponent:@"Resources"];
	NSError *writeError = nil;
	if (![manager createDirectoryAtPath:resourcesPath
							 withIntermediateDirectories:YES
													attributes:nil
														 error:&writeError]) {
		NSLog(@"Unable to create Xtra at %@: %@", bundlePath, writeError);
		return NO;
	}

	NSDictionary *infoPlist = [self infoPlistDictionary];
	NSString *infoPlistPath = [contentsPath stringByAppendingPathComponent:@"Info.plist"];
	if (![infoPlist writeToFile:infoPlistPath atomically:YES]) {
		NSLog(@"Unable to write Xtra metadata at %@", infoPlistPath);
		return NO;
	}

	NSEnumerator *resourceEnu = [resources objectEnumerator];
	NSString *resourcePath;
	while ((resourcePath = [resourceEnu nextObject])) {
		NSString *resourceSrcPath = nil;
		if ([manager fileExistsAtPath:resourcePath])
			resourceSrcPath = resourcePath;
		else {
			NSString *resourceFilename = [resourcePath lastPathComponent];
			resourceSrcPath = [bundle pathForResource:[resourceFilename stringByDeletingPathExtension]
																 ofType:[resourceFilename pathExtension]];
		}
		if (!resourceSrcPath || ![manager fileExistsAtPath:resourceSrcPath]) {
			NSLog(@"Unable to find Xtra resource %@ while writing %@", resourcePath, bundlePath);
			return NO;
		}

		resourceSrcPath = [resourceSrcPath stringByStandardizingPath];
		NSString *resourceDestPath = [resourcesPath stringByAppendingPathComponent:[resourcePath lastPathComponent]];
		if (![resourceSrcPath isEqualToString:resourceDestPath]
			&& ![manager copyItemAtPath:resourceSrcPath toPath:resourceDestPath error:&writeError]) {
			NSLog(@"Unable to copy Xtra resource %@: %@", resourceSrcPath, writeError);
			return NO;
		}
	}

	if (icon && ![[NSWorkspace sharedWorkspace] setIcon:icon
													 forFile:bundlePath
													 options:NSExcludeQuickDrawElementsIconCreationOption]) {
		NSLog(@"Unable to set custom icon for Xtra at %@", bundlePath);
		return NO;
	}

	NSAttributedString *readmeText = readmeView ? [readmeView textStorage] : readme;
	BOOL shouldWriteRichText = readmeView ? [readmeView isRichText] : readmeIsRichText;
	if ([readmeText length] > 0) {
		NSRange readmeRange = NSMakeRange(0, [readmeText length]);
		NSData *readmeData = shouldWriteRichText
			? [readmeText dataFromRange:readmeRange
						 documentAttributes:[NSDictionary dictionaryWithObject:NSRTFTextDocumentType
																	 forKey:NSDocumentTypeDocumentAttribute]
																			 error:&writeError]
			: [[readmeText string] dataUsingEncoding:NSUTF8StringEncoding];
		NSString *readmeFilename = shouldWriteRichText ? @"ReadMe.rtf" : @"ReadMe.txt";
		if (!readmeData || ![readmeData writeToFile:[resourcesPath stringByAppendingPathComponent:readmeFilename] atomically:YES]) {
			NSLog(@"Unable to write Xtra ReadMe at %@: %@", bundlePath, writeError);
			return NO;
		}
	}

	NSURL *bundleURL = [NSURL fileURLWithPath:bundlePath isDirectory:YES];
	NSError *packageError = nil;
	if (![bundleURL setResourceValue:[NSNumber numberWithBool:YES]
													 forKey:NSURLIsPackageKey
													  error:&packageError]) {
		NSLog(@"Unable to mark Xtra at %@ as a package: %@", bundlePath, packageError);
		return NO;
	}

	return YES;
}
- (BOOL)writeToURL:(NSURL *)URL ofType:(NSString *)typeName error:(NSError **)outError
{
	NSString * path = [URL path];
	BOOL didWrite = [self writeToFile:path ofType:typeName];
	if (!didWrite && outError) {
		*outError = [NSError errorWithDomain:NSCocoaErrorDomain
											 code:NSFileWriteUnknownError
										 userInfo:[NSDictionary dictionaryWithObject:path forKey:NSFilePathErrorKey]];
	}
	return didWrite;
}

- (BOOL) readFromFile:(NSString *)path ofType:(NSString *)type
{
	NSBundle *bundleAtPath = [NSBundle bundleWithPath:path];
	if (!bundleAtPath)
		return NO;

	NSDictionary *infoPlist = [bundleAtPath infoDictionary];
	BOOL isCurrentBundle = ([[infoPlist objectForKey:@"XtraBundleVersion"] intValue] == 1);
	NSDictionary *legacyIconsPlist = [NSDictionary dictionaryWithContentsOfFile:[[bundleAtPath resourcePath] stringByAppendingPathComponent:@"Icons.plist"]];
	BOOL isLegacyIconPack = (!isCurrentBundle
		&& ([[legacyIconsPlist objectForKey:@"AdiumSetVersion"] intValue] == 1));
	if (!isCurrentBundle && !isLegacyIconPack)
		return NO;

	[bundle release];
	bundle = [bundleAtPath retain];

	NSString *fallbackName = [[path lastPathComponent] stringByDeletingPathExtension];
	[self setName:isCurrentBundle ? [infoPlist objectForKey:(NSString *)kCFBundleNameKey] : fallbackName];
	if (!name)
		[self setName:fallbackName];
	[self setAuthor:isCurrentBundle ? [infoPlist objectForKey:@"XtraAuthors"] : @""];
	if (!author)
		[self setAuthor:@""];
	[self setVersion:isCurrentBundle ? [infoPlist objectForKey:@"XtraVersion"] : @"1.0"];
	if (!version)
		[self setVersion:@"1.0"];
	[self setBundleID:isCurrentBundle ? [infoPlist objectForKey:(NSString *)kCFBundleIdentifierKey] : AXCLegacyBundleIdentifier()];
	if (!bundleID)
		[self setBundleID:AXCLegacyBundleIdentifier()];

	NSMutableArray *resourceNames = [[[NSFileManager defaultManager] directoryContentsAtPath:[bundle resourcePath]] mutableCopy];
	if (!resourceNames)
		return NO;
	[resourceNames removeObject:@".DS_Store"];
	[self setResources:resourceNames];
	[resourceNames release];

	NSString *readmePath = nil;
	BOOL isRichText = NO;
	NSArray *preferredReadmeExtensions = [NSArray arrayWithObjects:@"rtf", @"rtfd", @"txt", nil];
	NSEnumerator *extensionEnumerator = [preferredReadmeExtensions objectEnumerator];
	NSString *preferredExtension;
	while (!readmePath && (preferredExtension = [extensionEnumerator nextObject])) {
		NSEnumerator *resourceEnumerator = [resources objectEnumerator];
		NSString *resourceName;
		while ((resourceName = [resourceEnumerator nextObject])) {
			if ([[resourceName stringByDeletingPathExtension] caseInsensitiveCompare:@"ReadMe"] == NSOrderedSame
				&& [[resourceName pathExtension] caseInsensitiveCompare:preferredExtension] == NSOrderedSame) {
				readmePath = [[bundle resourcePath] stringByAppendingPathComponent:resourceName];
				isRichText = ![preferredExtension isEqualToString:@"txt"];
				break;
			}
		}
	}
	if (readmePath) {
		NSAttributedString *readmeTemp;
		if (isRichText) {
			readmeTemp = [[NSAttributedString alloc] initWithPath:readmePath documentAttributes:nil];
		} else {
			NSData *plainTextData = [[NSData alloc] initWithContentsOfFile:readmePath];
			NSString *plainText = [[NSString alloc] initWithData:plainTextData encoding:NSUTF8StringEncoding];
			readmeTemp = [[NSAttributedString alloc] initWithString:plainText];
			[plainText release];
			[plainTextData release];
		}
		if (readmeTemp) {
			[self setReadme:readmeTemp];
			readmeIsRichText = isRichText;
			[readmeTemp release];
			[self removeResource:[readmePath lastPathComponent]];
		}
	}

	return YES;
}

- (void) printShowingPrintPanel:(BOOL)flag
{
	//XXX TEMP - should make a new view that grabs all the information from this document, and displays it linearly
	NSPrintOperation *op = [NSPrintOperation printOperationWithView:fileView];
	[op setShowsPrintPanel:flag];
	[op runOperation];
}

- (IBAction) runAddFilesPanel:(id)sender
{
	NSOpenPanel * p = [NSOpenPanel openPanel];
	[p setAllowsMultipleSelection:YES];
	[p beginSheetForDirectory:nil
						 file:nil
						types:[self validResourceTypes]
			   modalForWindow:[self windowForSheet]
				modalDelegate:self
			   didEndSelector:@selector(didEndAddFilesPanel:returnCode:contextInfo:)
				  contextInfo:NULL];
}

- (void) didEndAddFilesPanel:(NSOpenPanel *)p returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode != NSOKButton)
		return;

	NSArray *newFiles = [p filenames];
	NSMutableSet *newFilesSet = [NSMutableSet setWithArray:newFiles];
	//remove from newFilesSet all the files that we already have added.
	NSMutableSet *temp = [resourcesSet mutableCopy];
	[temp intersectSet:newFilesSet];
	[newFilesSet minusSet:temp];
	[temp release];

	if ([newFilesSet count]) {
		newFiles = [newFilesSet allObjects];

		[self addResources:newFiles];
	}
}

- (IBAction) runChooseIconPanel:(id)sender
{
	NSOpenPanel * p = [NSOpenPanel openPanel];
	[p setAllowsMultipleSelection:YES];
	[p beginSheetForDirectory:nil
						 file:nil
						types:[NSImage imageFileTypes]
			   modalForWindow:[self windowForSheet]
				modalDelegate:self
			   didEndSelector:@selector(didEndChooseIconPanel:returnCode:contextInfo:)
				  contextInfo:NULL];
}

- (void) didEndChooseIconPanel:(NSOpenPanel *)p returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode != NSOKButton)
		return;

	[self setIcon:[[[NSImage alloc] initByReferencingFile:[[p filenames] objectAtIndex:0]]autorelease]];
}

#pragma mark -

- (void) setName:(NSString *)newName
{
	[name release];
	name = [newName copy];
}
- (NSString *) name
{
	return name;
}

- (void) setAuthor:(NSString *)newAuthor
{
	[author release];
	author = [newAuthor copy];
}
- (NSString *) author
{
	return author;
}

- (void) setVersion:(NSString *)newVersion
{
	[version release];
	version = [newVersion copy];
}
- (NSString *) version
{
	return version;
}

- (void) setBundleID:(NSString *)newBundleID
{
	[bundleID release];
	bundleID = [newBundleID copy];
}
- (NSString *) bundleID
{
	return bundleID;
}

- (void) setReadme:(NSAttributedString *)newReadme
{
	[readme release];
	readme = [newReadme copy];
}
- (NSAttributedString *) readme
{
	return readme;
}

- (void) setIcon:(NSImage *)inImage
{
	[icon autorelease];
	icon = [inImage retain];
}

- (NSImage *) icon
{
	return icon;
}

#pragma mark -

- (NSString *) OSType
{
	return @"AdIM";
}
- (NSString *) pathExtension
{
	return nil;
}
- (NSString *) uniformTypeIdentifier
{
	return @"com.adiumx.xtra";
}

- (NSArray *) validResourceTypes
{
	return nil;
}

- (NSDictionary *) infoPlistDictionary
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		@"English", kCFBundleDevelopmentRegionKey,
		name ? name : @"Untitled Xtra", kCFBundleNameKey,
		[self OSType], @"CFBundlePackageType",
		bundleID ? bundleID : AXCLegacyBundleIdentifier(), kCFBundleIdentifierKey,
		[NSNumber numberWithInt:1], @"XtraBundleVersion",
		@"1.0", kCFBundleInfoDictionaryVersionKey,
		version ? version : @"1.0", @"XtraVersion",
		author ? author : @"", @"XtraAuthors",
		nil];
}

//added to the tab view.
- (NSArray *) tabViewItems
{
	return [NSArray array];
}

#pragma mark -
#pragma mark Table-view drag validation (for resources)

- (NSDragOperation) validateDragWithInfo:(id <NSDraggingInfo>)info operation:(NSTableViewDropOperation)operation
{
	NSArray *filenames = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
	if (filenames) {
		NSSet *validTypes = [NSSet setWithArray:[self validResourceTypes]];
		if (validTypes) {
			//iterate on the array until we find an invalid type. if we do, this drag fails.
			NSEnumerator *filenamesEnum = [filenames objectEnumerator];
			NSString *path;
			while ((path = [filenamesEnum nextObject])) {
				if (![validTypes containsObject:[path pathExtension]])
					goto fail;
				//XXX OSTypes
			}

			//no failure: all the files are valid to be dropped.
			return NSDragOperationCopy;
		}
	}

fail:
	return NSDragOperationNone;
}

- (NSDragOperation) tableView:(NSTableView *)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	int thisDrag = [info draggingSequenceNumber];
	if (lastDrag != thisDrag) {
		//this is a new drag. validate it.
		lastDragOperation = [self validateDragWithInfo:info operation:operation];
		lastDrag = thisDrag;
	}

	if ((lastDragOperation != NSDragOperationNone) && (operation == NSTableViewDropOn)) {
		NSArray *filenames = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
		if ([filenames count] == 1)
			row = [resources indexForInsortingObject:[filenames objectAtIndex:0U] usingSelector:@selector(caseInsensitiveCompare:)];
		else {
			//retarget to either above or below.
			NSPoint location = [info draggingLocation];
			NSRect rowRect = [tableView rectOfRow:row];
			
			//make this relative to the row rect. (we don't care about x.)
			location.y -= rowRect.origin.y;
			//compare the y-coord to the height of the row. if below the middle, drop below the row; else, drop above it.
			if (location.y > (rowRect.size.height / 2.0))
				++row;
		}	
		
		[tableView setDropRow:row dropOperation:NSTableViewDropAbove];
	}
	
	return lastDragOperation;
}

- (BOOL) tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)operation
{
	NSArray *filenames = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];

	//XXX insort
	[self addResources:filenames];

	return YES;
}

@end
