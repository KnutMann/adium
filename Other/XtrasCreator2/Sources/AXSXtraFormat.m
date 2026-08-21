/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSXtraFormat.h"
#import "AXSIconPlistCodec.h"
#import "AXSEmoticonSetCodec.h"
#import "AXSMenuBarIconsEditorViewController.h"
#import "AXSIconPackEditorViewController.h"
#import "AXSEmoticonSetEditorViewController.h"
#import "AXSSoundSetEditorViewController.h"
#import "AXSDockIconCodec.h"
#import "AXSDockIconEditorViewController.h"
#import "AXSPlistPassthroughCodec.h"
#import "AXSPlistTableEditorViewController.h"

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
@property (readwrite, nonatomic) NSDictionary<NSString *, NSArray<NSString *> *> *requiredCatalog;
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
			f.requiredCatalog = @{ @"Icons": @[@"Online", @"Offline"] };
			f.codec = [[AXSIconPlistCodec alloc] init];
			f.editorClass = [AXSMenuBarIconsEditorViewController class];
			[building addObject:f];
		}

		{	//Status icons: Icons.plist with a List and a Tabs category over status names
			AXSXtraFormat *f = [[AXSXtraFormat alloc] init];
			f.typeName = @"com.adiumx.statusicons";
			f.extension = @"AdiumStatusIcons";
			f.osType = @"AISt";
			f.displayName = @"Status Icons";
			f.supportsFlatForm = YES;
			f.payloadFileName = @"Icons.plist";
			f.categoryNames = @[@"List", @"Tabs"];

			NSArray *statusKeys = @[@"Generic Available", @"Generic Away", @"Away", @"Idle",
									@"Busy", @"DND", @"Not Available", @"Occupied", @"Free for Chat",
									@"Invisible", @"Mobile", @"Offline", @"Unknown",
									@"content", @"typing", @"enteredtext"];
			f.catalog = @{ @"List": statusKeys, @"Tabs": statusKeys };

			/* The four names the fallback chain lands on; a pack without them
			 * trips Adium's "invalid status icon pack" alert (AIStatusIcons). */
			NSArray *requiredKeys = @[@"Generic Available", @"Generic Away", @"Invisible", @"Offline"];
			f.requiredCatalog = @{ @"List": requiredKeys, @"Tabs": requiredKeys };

			f.codec = [[AXSIconPlistCodec alloc] init];
			f.editorClass = [AXSIconPackEditorViewController class];
			[building addObject:f];
		}

		{	//Service icons: Icons.plist keyed by service IDs, in three sizes
			AXSXtraFormat *f = [[AXSXtraFormat alloc] init];
			f.typeName = @"com.adiumx.serviceicons";
			f.extension = @"AdiumServiceIcons";
			f.osType = @"AISr";
			f.displayName = @"Service Icons";
			f.supportsFlatForm = YES;
			f.payloadFileName = @"Icons.plist";
			f.categoryNames = @[@"Interface-Large", @"Interface-Small", @"List"];

			//The services this fork runs; keys of other networks are kept but shown as legacy
			NSArray *serviceKeys = @[@"Jabber", @"IRCv3", @"Gadu-Gadu", @"GroupWise", @"SIMPLE",
									 @"WhatsApp", @"Signal", @"Telegram", @"Teams", @"TeamsPersonal"];
			f.catalog = @{ @"Interface-Large": serviceKeys, @"Interface-Small": serviceKeys, @"List": serviceKeys };
			//Missing service icons fall back to Adium's defaults; nothing is required

			f.codec = [[AXSIconPlistCodec alloc] init];
			f.editorClass = [AXSIconPackEditorViewController class];
			[building addObject:f];
		}

		{	//Group chat status icons: role images and colors, both in Info.plist
			AXSXtraFormat *f = [[AXSXtraFormat alloc] init];
			f.typeName = @"com.adiumx.groupchatstatusicons";
			f.extension = @"AdiumGroupChatStatusIcons";
			f.osType = @"AIGc";
			f.displayName = @"Group Chat Status Icons";
			f.supportsFlatForm = NO;
			f.payloadLivesInInfoPlist = YES;
			f.categoryNames = @[@"Icons", @"Colors"];

			NSArray *roleKeys = @[@"Founder", @"Op", @"Half-op", @"Voice", @"None"];
			f.catalog = @{ @"Icons": roleKeys, @"Colors": roleKeys };
			//Everything falls back to None, so None is the one entry a pack needs
			f.requiredCatalog = @{ @"Icons": @[@"None"], @"Colors": @[@"None"] };

			f.codec = [[AXSIconPlistCodec alloc] init];
			f.editorClass = [AXSIconPackEditorViewController class];
			[building addObject:f];
		}

		{	//Emoticon sets: Emoticons.plist over images, or emoji entries without any
			AXSXtraFormat *f = [[AXSXtraFormat alloc] init];
			f.typeName = @"com.adiumx.emoticonset";
			f.extension = @"AdiumEmoticonset";
			f.osType = @"AIEm";
			f.displayName = @"Emoticon Set";
			f.supportsFlatForm = YES;
			f.payloadFileName = @"Emoticons.plist";
			f.codec = [[AXSEmoticonSetCodec alloc] init];
			f.editorClass = [AXSEmoticonSetEditorViewController class];
			[building addObject:f];
		}

		{	//Sound sets: Sounds.plist mapping event names to audio files
			AXSXtraFormat *f = [[AXSXtraFormat alloc] init];
			f.typeName = @"com.adiumx.soundset";
			f.extension = @"AdiumSoundset";
			f.osType = @"AISd";
			f.displayName = @"Sound Set";
			f.supportsFlatForm = YES;
			f.payloadFileName = @"Sounds.plist";
			f.categoryNames = @[@"Sounds"];

			/* The keys are the events' English display names; the loader maps
			 * them back through eventIDForEnglishDisplayName:. Harvested from
			 * every englishGlobalShortDescriptionForEventID: in the tree. */
			f.catalog = @{ @"Sounds": @[
				@"Connected", @"Disconnected", @"Error", @"New Mail Received",
				@"Contact Signed On", @"Contact Signed Off",
				@"Contact is seen", @"Contact is no longer seen",
				@"Contact Went Away", @"Contact Returned from Away",
				@"Contact Went Idle", @"Contact Returned from Idle",
				@"Contact Went Mobile", @"Contact Returns from Mobile",
				@"Message Received", @"Message Received (New)", @"Message Received (Away)",
				@"Message Received (Background Chat)", @"Message Received (Group Chat)",
				@"Message Received (Background Group Chat)", @"Message Received (Away Group Chat)",
				@"Message Sent", @"Message Sent (Group Chat)",
				@"You Are Mentioned (Group Chat)",
				@"Contact Joins", @"Contact Leaves", @"Contact Invites You to Chat",
				@"File Transfer Request", @"File Transfer Began", @"File Transfer Complete",
				@"File transfer failed", @"File Transfer Canceled Remotely",
				@"Notification received",
			] };

			f.codec = [[AXSIconPlistCodec alloc] init];
			f.editorClass = [AXSSoundSetEditorViewController class];
			[building addObject:f];
		}

		{	//Dock icons: IconPack.plist with description and still or animated states
			AXSXtraFormat *f = [[AXSXtraFormat alloc] init];
			f.typeName = @"com.adiumx.dockicon";
			f.extension = @"AdiumIcon";
			f.osType = @"AIDk";
			f.displayName = @"Dock Icon";
			f.supportsFlatForm = YES;
			f.payloadFileName = @"IconPack.plist";
			/* No categoryNames: the payload is not the flat category shape the
			 * icon codec speaks; the catalog below only names the states. */
			f.catalog = @{ @"State": @[@"Base", @"Preview", @"ApplicationIcon", @"Alert",
									   @"Away", @"Idle", @"Connecting", @"Invisible"] };
			f.requiredCatalog = @{ @"State": @[@"Base"] };
			f.codec = [[AXSDockIconCodec alloc] init];
			f.editorClass = [AXSDockIconEditorViewController class];
			[building addObject:f];
		}

		{	//Contact list themes and layouts: a preference dictionary each
			NSDictionary *plistTypes = @{
				@"com.adiumx.contactlisttheme": @[@"ListTheme", @"AILT", @"Contact List Theme"],
				@"com.adiumx.contactlistlayout": @[@"ListLayout", @"AILL", @"Contact List Layout"],
			};

			for (NSString *typeName in plistTypes) {
				NSArray *spec = plistTypes[typeName];
				AXSXtraFormat *f = [[AXSXtraFormat alloc] init];
				f.typeName = typeName;
				f.extension = spec[0];
				f.osType = spec[1];
				f.displayName = spec[2];
				f.supportsFlatForm = YES;
				f.flatFormIsBarePlist = YES;	//the flat form is the plist file itself
				f.payloadFileName = @"Data.plist";
				f.codec = [[AXSPlistPassthroughCodec alloc] init];
				f.editorClass = [AXSPlistTableEditorViewController class];
				[building addObject:f];
			}
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
