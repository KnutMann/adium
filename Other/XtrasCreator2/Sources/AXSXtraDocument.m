/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSXtraDocument.h"
#import "AXSDocumentWindowController.h"

/* The Info.plist keys this application manages; everything else is preserved
 * verbatim. CFBundlePackageType is deliberately not among them: nothing reads
 * it, Adium's own theme writer stamps AdIM where this tool would stamp AILT,
 * and rewriting it buys nothing - an existing value stays, only a missing one
 * is filled with the type's own OSType. */
static NSArray *AXSManagedInfoKeys(void)
{
	return @[@"CFBundleDevelopmentRegion", @"CFBundleName",
			 @"CFBundleIdentifier", @"XtraBundleVersion", @"CFBundleInfoDictionaryVersion",
			 @"XtraVersion", @"XtraAuthors", @"OriginalAuthor", @"CFBundleVersion"];
}

@interface AXSXtraDocument ()
@property (readwrite, nonatomic) AXSXtraFormat *format;
@property (readwrite, nonatomic) AXSXtraModel *model;
@property (readwrite, nonatomic) BOOL isFlatForm;
@end

@implementation AXSXtraDocument {
	NSFileWrapper	*rootWrapper;			//The pack as loaded; mutated in place, returned on save
	NSData			*originalReadMeData;	//To leave an unedited readme file untouched
	NSString		*originalReadMeName;	//ReadMe.rtf or ReadMe.txt, as found
}

#pragma mark New documents

- (instancetype)initWithType:(NSString *)typeName error:(NSError **)outError
{
	if ((self = [super initWithType:typeName error:outError])) {
		_format = [AXSXtraFormat formatForTypeName:typeName];
		if (!_format) {
			if (outError) *outError = [NSError errorWithDomain:NSCocoaErrorDomain
														  code:NSFileReadUnknownError
													  userInfo:@{NSLocalizedDescriptionKey:
																 [NSString stringWithFormat:@"Unknown xtra type %@", typeName]}];
			return nil;
		}

		_model = [[AXSXtraModel alloc] init];
		_model.payload = [_format.codec emptyPayloadForFormat:_format];

		if (_format.flatFormIsBarePlist) {
			//Born flat, the form Adium itself writes for these
			_isFlatForm = YES;
		} else {
			//Born as a bundle, with the skeleton in place so editors can add files right away
			_isFlatForm = NO;
			[self buildEmptyBundleSkeleton];
		}
	}
	return self;
}

- (void)buildEmptyBundleSkeleton
{
	NSFileWrapper *resources = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
	[resources setPreferredFilename:@"Resources"];

	NSFileWrapper *contents = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"Resources": resources}];
	[contents setPreferredFilename:@"Contents"];

	rootWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"Contents": contents}];
}

#pragma mark Structure

- (NSFileWrapper *)contentsWrapper
{
	NSFileWrapper *contents = [rootWrapper fileWrappers][@"Contents"];
	return (contents.directory ? contents : nil);
}

- (NSFileWrapper *)resourcesWrapper
{
	if (self.isFlatForm)
		return rootWrapper;

	NSFileWrapper *contents = [self contentsWrapper];
	NSFileWrapper *resources = [contents fileWrappers][@"Resources"];

	if (!resources.directory && contents) {
		resources = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
		[resources setPreferredFilename:@"Resources"];
		[contents addFileWrapper:resources];
	}

	return resources;
}

/*!
 * @brief Replace a child file only when its bytes actually changed
 */
static void AXSReplaceFile(NSFileWrapper *directory, NSString *name, NSData *data)
{
	NSFileWrapper *existing = [directory fileWrappers][name];

	if (existing && existing.regularFile && [[existing regularFileContents] isEqualToData:data])
		return;

	if (existing) [directory removeFileWrapper:existing];
	[directory addRegularFileWithContents:data preferredFilename:name];
}

#pragma mark Reading

- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper ofType:(NSString *)typeName error:(NSError **)outError
{
	self.format = [AXSXtraFormat formatForTypeName:typeName];
	if (!self.format) {
		if (outError) *outError = [NSError errorWithDomain:NSCocoaErrorDomain
													  code:NSFileReadUnknownError
												  userInfo:@{NSLocalizedDescriptionKey:
															 [NSString stringWithFormat:@"Unknown xtra type %@", typeName]}];
		return NO;
	}

	rootWrapper = fileWrapper;

	//The bare form: the xtra is one plist file, nothing around it
	if (fileWrapper.regularFile && self.format.flatFormIsBarePlist) {
		self.isFlatForm = YES;

		id plist = [NSPropertyListSerialization propertyListWithData:[fileWrapper regularFileContents]
															 options:NSPropertyListImmutable
															  format:NULL
															   error:outError];

		AXSXtraModel *model = [[AXSXtraModel alloc] init];
		model.bundleName = [[self.fileURL lastPathComponent] stringByDeletingPathExtension] ?: @"";
		model.payload = ([plist isKindOfClass:[NSDictionary class]] ? [plist mutableCopy]
																	: [self.format.codec emptyPayloadForFormat:self.format]);
		self.model = model;

		return YES;
	}

	//A Contents/Info.plist makes it a bundle; anything else is the flat form
	NSFileWrapper *contents = [fileWrapper fileWrappers][@"Contents"];
	NSFileWrapper *infoPlist = (contents.directory ? [contents fileWrappers][@"Info.plist"] : nil);
	self.isFlatForm = (infoPlist == nil);

	NSDictionary *infoDict = @{};
	if (infoPlist.regularFile) {
		infoDict = [NSPropertyListSerialization propertyListWithData:[infoPlist regularFileContents]
															 options:NSPropertyListImmutable
															  format:NULL
															   error:NULL] ?: @{};
		if (![infoDict isKindOfClass:[NSDictionary class]]) infoDict = @{};
	}

	AXSXtraModel *model = [[AXSXtraModel alloc] init];
	model.bundleName = [infoDict[@"CFBundleName"] description] ?: [[self.fileURL lastPathComponent] stringByDeletingPathExtension] ?: @"";
	model.version = [infoDict[@"XtraVersion"] description] ?: [infoDict[@"CFBundleVersion"] description] ?: @"1.0";
	model.authors = [infoDict[@"XtraAuthors"] description] ?: [infoDict[@"OriginalAuthor"] description] ?: @"";
	model.bundleIdentifier = [infoDict[@"CFBundleIdentifier"] description] ?: @"";

	//Everything not ours to manage is preserved verbatim
	NSMutableDictionary *unmanaged = [infoDict mutableCopy] ?: [NSMutableDictionary dictionary];
	[unmanaged removeObjectsForKeys:AXSManagedInfoKeys()];
	if (self.format.payloadLivesInInfoPlist)
		[unmanaged removeObjectsForKeys:self.format.categoryNames];
	model.unmanagedInfoKeys = unmanaged;

	model.payload = [self.format.codec readPayloadFromInfoDictionary:infoDict
														resourcesDir:[self resourcesWrapperForReading]
															  format:self.format
															   error:outError];
	if (!model.payload)
		model.payload = [self.format.codec emptyPayloadForFormat:self.format];

	[self readReadMeIntoModel:model];

	self.model = model;

	return YES;
}

//During reading, resourcesWrapper must not create directories in a flat pack
- (NSFileWrapper *)resourcesWrapperForReading
{
	if (self.isFlatForm)
		return rootWrapper;

	NSFileWrapper *contents = [rootWrapper fileWrappers][@"Contents"];
	NSFileWrapper *resources = [contents fileWrappers][@"Resources"];

	return (resources.directory ? resources : rootWrapper);
}

- (void)readReadMeIntoModel:(AXSXtraModel *)model
{
	NSFileWrapper *resources = [self resourcesWrapperForReading];

	for (NSString *name in @[@"ReadMe.rtf", @"ReadMe.txt"]) {
		NSFileWrapper *readme = [resources fileWrappers][name];
		if (!readme.regularFile) continue;

		NSData *data = [readme regularFileContents];
		NSAttributedString *text;

		if ([name hasSuffix:@"rtf"]) {
			text = [[NSAttributedString alloc] initWithRTF:data documentAttributes:NULL];
		} else {
			NSString *plain = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			text = (plain ? [[NSAttributedString alloc] initWithString:plain] : nil);
		}

		if (text) {
			model.readMe = text;
			originalReadMeData = data;
			originalReadMeName = name;
			return;
		}
	}

	originalReadMeData = nil;
	originalReadMeName = nil;
}

#pragma mark Writing

- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError **)outError
{
	//The bare form writes itself: the payload is the file
	if (self.isFlatForm && self.format.flatFormIsBarePlist) {
		NSData *data = [NSPropertyListSerialization dataWithPropertyList:self.model.payload
																  format:NSPropertyListXMLFormat_v1_0
																 options:0
																   error:outError];
		if (!data) return nil;

		return [[NSFileWrapper alloc] initRegularFileWithContents:data];
	}

	if (!rootWrapper)
		[self buildEmptyBundleSkeleton];

	//The Info.plist: unmanaged keys first, then the payload's, then ours on top
	NSMutableDictionary *infoDict = [self.model.unmanagedInfoKeys mutableCopy] ?: [NSMutableDictionary dictionary];

	if (![self.format.codec writePayload:self.model.payload
					  intoInfoDictionary:infoDict
							resourcesDir:[self resourcesWrapper]
								  format:self.format
								   error:outError])
		return nil;

	infoDict[@"CFBundleDevelopmentRegion"] = @"English";
	infoDict[@"CFBundleName"] = self.model.bundleName ?: @"";
	if (!infoDict[@"CFBundlePackageType"])
		infoDict[@"CFBundlePackageType"] = self.format.osType;
	infoDict[@"CFBundleIdentifier"] = [self effectiveBundleIdentifier];
	infoDict[@"XtraBundleVersion"] = @1;
	infoDict[@"CFBundleInfoDictionaryVersion"] = @"1.0";
	infoDict[@"XtraVersion"] = self.model.version ?: @"1.0";
	infoDict[@"XtraAuthors"] = self.model.authors ?: @"";
	/* The other spelling of the same two facts: released Adium versions read
	 * only OriginalAuthor and CFBundleVersion, so both pairs are written. */
	infoDict[@"OriginalAuthor"] = self.model.authors ?: @"";
	infoDict[@"CFBundleVersion"] = self.model.version ?: @"1.0";

	if (!self.isFlatForm) {
		NSData *infoData = [NSPropertyListSerialization dataWithPropertyList:infoDict
																	  format:NSPropertyListXMLFormat_v1_0
																	 options:0
																	   error:outError];
		if (!infoData) return nil;

		AXSReplaceFile([self contentsWrapper], @"Info.plist", infoData);
	}

	[self writeReadMe];

	return rootWrapper;
}

- (NSString *)effectiveBundleIdentifier
{
	if ([self.model.bundleIdentifier length])
		return self.model.bundleIdentifier;

	/* A stable identifier is minted once and kept in the model, so saving
	 * twice does not mint twice. */
	NSString *minted = [NSString stringWithFormat:@"com.adiumx.xtra.%@", [[NSUUID UUID] UUIDString]];
	self.model.bundleIdentifier = minted;
	return minted;
}

- (void)writeReadMe
{
	NSAttributedString *readMe = self.model.readMe;
	NSFileWrapper *resources = [self resourcesWrapper];

	if (![readMe length]) {
		//An emptied readme takes the file with it; a pack that never had one stays without
		if (originalReadMeName) {
			NSFileWrapper *old = [resources fileWrappers][originalReadMeName];
			if (old) [resources removeFileWrapper:old];
			originalReadMeName = nil;
			originalReadMeData = nil;
		}
		return;
	}

	NSData *rtf = [readMe RTFFromRange:NSMakeRange(0, [readMe length]) documentAttributes:@{
					   NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType}];
	if (!rtf) return;

	//An unedited readme keeps its bytes, and with them its file, whatever its dialect was
	if (originalReadMeData && [rtf isEqualToData:originalReadMeData])
		return;

	if (originalReadMeName && ![originalReadMeName isEqualToString:@"ReadMe.rtf"]) {
		NSFileWrapper *old = [resources fileWrappers][originalReadMeName];
		if (old) [resources removeFileWrapper:old];
	}

	AXSReplaceFile(resources, @"ReadMe.rtf", rtf);
	originalReadMeName = @"ReadMe.rtf";
	originalReadMeData = rtf;
}

#pragma mark Document plumbing

- (void)makeWindowControllers
{
	[self addWindowController:[[AXSDocumentWindowController alloc] initWithDocument:self]];
}

+ (BOOL)autosavesInPlace
{
	return NO;
}

- (void)noteEdited
{
	[self updateChangeCount:NSChangeDone];
}

@end
