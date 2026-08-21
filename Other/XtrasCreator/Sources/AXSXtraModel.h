/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>

/*!
 * @brief What one open xtra says about itself, plus its payload
 *
 * The common metadata every xtra carries, the payload the type's codec read,
 * and the Info.plist keys nobody here manages - kept word for word so a saved
 * pack loses nothing a foreign tool put there.
 */
@interface AXSXtraModel : NSObject

@property (copy, nonatomic) NSString *bundleName;		//CFBundleName; the name the xtra goes by
@property (copy, nonatomic) NSString *version;			//written as XtraVersion AND CFBundleVersion
@property (copy, nonatomic) NSString *authors;			//written as XtraAuthors AND OriginalAuthor
@property (copy, nonatomic) NSString *bundleIdentifier;

//Info.plist keys outside our management, preserved verbatim on save
@property (strong, nonatomic) NSMutableDictionary *unmanagedInfoKeys;

//Whatever the type's codec reads and writes
@property (strong, nonatomic) id payload;

//nil when the pack has no readme of its own
@property (copy, nonatomic) NSAttributedString *readMe;

@end
