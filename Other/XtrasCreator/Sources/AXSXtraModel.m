/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSXtraModel.h"

@implementation AXSXtraModel

- (instancetype)init
{
	if ((self = [super init])) {
		_bundleName = @"";
		_version = @"1.0";
		_authors = @"";
		_xtraDescription = @"";
		_bundleIdentifier = @"";
		_unmanagedInfoKeys = [NSMutableDictionary dictionary];
	}
	return self;
}

@end
