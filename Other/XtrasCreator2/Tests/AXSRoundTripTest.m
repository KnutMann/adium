/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 *
 * Round-trip test runner: reads a pack, writes it untouched to a scratch
 * location, reads that back, and holds the result against the format
 * contract. Run it through run-tests.sh, which compiles it against the
 * application sources and feeds it every fixture.
 *
 *   AXSRoundTripTest <extension> <pack path> <scratch dir>
 *
 * What an untouched round trip must keep:
 *  - every file byte for byte, except the Info.plist and the payload file,
 *    which may be re-serialized
 *  - every original Info.plist key semantically, except the managed ones
 *    this tool normalizes (XtraBundleVersion becomes the integer 1)
 *  - the payload, read back equal from the written pack
 * And what it must add: the second spelling of author and version for old
 * Adium clients, wherever an Info.plist is written at all.
 */

#import <Cocoa/Cocoa.h>
#import "AXSXtraDocument.h"

static int failures;
static NSString *packName;

static void check(BOOL ok, NSString *what)
{
	if (!ok) {
		printf("FAIL %s: %s\n", [packName UTF8String], [what UTF8String]);
		failures++;
	}
}

static NSDictionary *plistAt(NSString *path)
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data) return nil;
	id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
	return ([plist isKindOfClass:[NSDictionary class]] ? plist : nil);
}

static void compareTrees(NSString *origRoot, NSString *outRoot, NSString *relative, NSArray *reserializable)
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *origDir = [origRoot stringByAppendingPathComponent:relative];

	for (NSString *name in [fm contentsOfDirectoryAtPath:origDir error:NULL]) {
		NSString *rel = ([relative length] ? [relative stringByAppendingPathComponent:name] : name);
		NSString *origPath = [origRoot stringByAppendingPathComponent:rel];
		NSString *outPath = [outRoot stringByAppendingPathComponent:rel];

		BOOL isDir = NO;
		[fm fileExistsAtPath:origPath isDirectory:&isDir];

		if (isDir) {
			compareTrees(origRoot, outRoot, rel, reserializable);
			continue;
		}

		if (![fm fileExistsAtPath:outPath]) {
			check(NO, [NSString stringWithFormat:@"%@ lost on round trip", rel]);
			continue;
		}

		if ([reserializable containsObject:rel]) {
			//May be rewritten; must stay a plist whose original keys survive semantically
			NSDictionary *orig = plistAt(origPath);
			NSDictionary *out = plistAt(outPath);
			check(out != nil, [NSString stringWithFormat:@"%@ still parses", rel]);

			for (NSString *key in orig) {
				if ([key isEqualToString:@"XtraBundleVersion"]) {
					check([out[key] isEqual:@1] || [[out[key] description] isEqualToString:@"1"],
						  @"XtraBundleVersion normalized to 1");
				} else if ([key isEqualToString:@"AdiumSetVersion"]) {
					check([[out[key] description] isEqualToString:[orig[key] description]],
						  @"AdiumSetVersion kept");
				} else {
					check([out[key] isEqual:orig[key]],
						  [NSString stringWithFormat:@"%@: key %@ survives", rel, key]);
				}
			}
		} else {
			NSData *a = [NSData dataWithContentsOfFile:origPath];
			NSData *b = [NSData dataWithContentsOfFile:outPath];
			check([a isEqualToData:b], [NSString stringWithFormat:@"%@ byte-identical", rel]);
		}
	}
}

int main(int argc, char *argv[])
{
	@autoreleasepool {
		if (argc < 4) {
			fprintf(stderr, "usage: AXSRoundTripTest <extension> <pack> <scratch dir>\n");
			return 2;
		}

		NSString *extension = [NSString stringWithUTF8String:argv[1]];
		NSString *packPath = [NSString stringWithUTF8String:argv[2]];
		NSString *scratch = [NSString stringWithUTF8String:argv[3]];
		packName = [packPath lastPathComponent];

		AXSXtraFormat *format = [AXSXtraFormat formatForExtension:extension];
		if (!format) {
			printf("SKIP %s: extension %s not registered yet\n", [packName UTF8String], [extension UTF8String]);
			return 0;
		}

		NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithURL:[NSURL fileURLWithPath:packPath]
															options:0 error:NULL];
		check(wrapper != nil, @"pack loads from disk");

		AXSXtraDocument *doc = [[AXSXtraDocument alloc] init];
		NSError *error = nil;
		check([doc readFromFileWrapper:wrapper ofType:format.typeName error:&error],
			  [NSString stringWithFormat:@"reads (%@)", error.localizedDescription]);

		NSFileWrapper *written = [doc fileWrapperOfType:format.typeName error:&error];
		check(written != nil, [NSString stringWithFormat:@"writes (%@)", error.localizedDescription]);

		NSString *outPath = [scratch stringByAppendingPathComponent:packName];
		[[NSFileManager defaultManager] removeItemAtPath:outPath error:NULL];
		[[NSFileManager defaultManager] createDirectoryAtPath:scratch withIntermediateDirectories:YES attributes:nil error:NULL];
		check([written writeToURL:[NSURL fileURLWithPath:outPath]
						  options:NSFileWrapperWritingAtomic
			  originalContentsURL:nil error:&error], @"lands on disk");

		//The files that may legitimately be re-serialized on an untouched save
		NSMutableArray *reserializable = [NSMutableArray arrayWithObject:@"Contents/Info.plist"];
		if (format.payloadFileName) {
			[reserializable addObject:[@"Contents/Resources" stringByAppendingPathComponent:format.payloadFileName]];
			[reserializable addObject:format.payloadFileName];	//flat form
		}

		compareTrees(packPath, outPath, @"", reserializable);

		//Contract keys, wherever an Info.plist was written
		NSString *infoPath = [outPath stringByAppendingPathComponent:@"Contents/Info.plist"];
		NSDictionary *info = plistAt(infoPath);
		if (info) {
			check(info[@"XtraVersion"] && info[@"CFBundleVersion"], @"both version spellings present");
			check(info[@"XtraAuthors"] && info[@"OriginalAuthor"], @"both author spellings present");
			check([info[@"XtraBundleVersion"] isEqual:@1], @"XtraBundleVersion is the integer 1");
		}

		//And the model must come back from what was written
		NSFileWrapper *rewrapped = [[NSFileWrapper alloc] initWithURL:[NSURL fileURLWithPath:outPath]
															  options:0 error:NULL];
		AXSXtraDocument *doc2 = [[AXSXtraDocument alloc] init];
		check([doc2 readFromFileWrapper:rewrapped ofType:format.typeName error:&error], @"written pack reads again");
		check((doc2.model.payload == doc.model.payload) || [doc2.model.payload isEqual:doc.model.payload],
			  @"payload round-trips");
		check([doc2.model.bundleName isEqualToString:doc.model.bundleName], @"name round-trips");

		if (!failures)
			printf("ok   %s\n", [packName UTF8String]);
	}
	return failures ? 1 : 0;
}
