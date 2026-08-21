/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSXtraFormat.h"
#import "AXSIconPlistCodec.h"
#import "AXSMenuBarIconsEditorViewController.h"

@interface AXSXtraFormat ()
@property (readwrite, nonatomic) NSString *typeName;
@property (readwrite, nonatomic) NSString *extension;
@property (readwrite, nonatomic) NSString *osType;
@property (readwrite, nonatomic) NSString *displayName;
@property (readwrite, nonatomic) BOOL supportsFlatForm;
@property (readwrite, nonatomic) BOOL flatFormIsBarePlist;
@property (readwrite, nonatomic) BOOL payloadLivesInInfoPlist;
@property (readwrite, nonatomic) BOOL requiresBundleIdentifier;
@property (readwrite, nonatomic) NSString *payloadFileName;
@property (readwrite, nonatomic) NSArray<NSString *> *categoryNames;
@property (readwrite, nonatomic) NSDictionary<NSString *, NSArray<NSString *> *> *catalog;
@property (readwrite, nonatomic) id<AXSPayloadCodec> codec;
@property (readwrite, nonatomic) Class editorClass;
@end

@implementation AXSXtraFormat

/*!
 * @brief The registry: one entry per xtra type the application can author
 *
 * Grows a type per phase; the starting points window and the document
 * machinery read whatever stands here.
 */
+ (NSArray<AXSXtraFormat *> *)allFormats
{
	static NSArray<AXSXtraFormat *> *formats;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		NSMutableArray *building = [NSMutableArray array];

		{	//Menu bar icons: two images named by an Icons dict in the bundle's own Info.plist
			AXSXtraFormat *f = [[AXSXtraFormat alloc] init];
			f.typeName = @"com.adiumx.menubaricons";
			f.extension = @"AdiumMenuBarIcons";
			f.osType = @"AdMB";
			f.displayName = @"Menu Bar Icons";
			f.supportsFlatForm = NO;
			f.payloadLivesInInfoPlist = YES;
			f.categoryNames = @[@"Icons"];
			/* The status menu item asks for all six; only Online and Offline
			 * are required, the rest fall back to Online (measured against
			 * CBStatusMenuItemController and AIMenuBarIcons). */
			f.catalog = @{ @"Icons": @[@"Online", @"Offline", @"Away", @"Idle", @"Invisible", @"Content"] };
			f.codec = [[AXSIconPlistCodec alloc] init];
			f.editorClass = [AXSMenuBarIconsEditorViewController class];
			[building addObject:f];
		}

		formats = [building copy];
	});

	return formats;
}

+ (AXSXtraFormat *)formatForTypeName:(NSString *)typeName
{
	for (AXSXtraFormat *format in [self allFormats]) {
		if ([format.typeName isEqualToString:typeName])
			return format;
	}
	return nil;
}

+ (AXSXtraFormat *)formatForExtension:(NSString *)extension
{
	for (AXSXtraFormat *format in [self allFormats]) {
		if ([format.extension caseInsensitiveCompare:extension] == NSOrderedSame)
			return format;
	}
	return nil;
}

@end
