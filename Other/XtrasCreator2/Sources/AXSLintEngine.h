/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Foundation/Foundation.h>

@class AXSXtraDocument;

typedef NS_ENUM(NSInteger, AXSLintLevel) {
	AXSLintLevelInfo = 0,
	AXSLintLevelWarning,
	AXSLintLevelError,
};

/*!
 * @brief One finding about an open xtra
 */
@interface AXSLintIssue : NSObject
@property (readonly, nonatomic) AXSLintLevel level;
@property (readonly, nonatomic) NSString *message;
+ (instancetype)issueWithLevel:(AXSLintLevel)level message:(NSString *)message;
@end

/*!
 * @brief Holds an xtra against what Adium's loaders demand
 *
 * The rules are the loader contracts read off the Adium sources: required
 * icons whose absence trips the invalid-pack alert, names the installer
 * refuses, references to files that are not in the pack. Errors mean Adium
 * will refuse or reset the pack; warnings mean something will silently not
 * work; info marks what is unusual but fine.
 */
@interface AXSLintEngine : NSObject

+ (NSArray<AXSLintIssue *> *)lintDocument:(AXSXtraDocument *)document;

@end
