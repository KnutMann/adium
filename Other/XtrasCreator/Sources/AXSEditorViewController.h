/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import <Cocoa/Cocoa.h>
#import "AISettingsFormView.h"
#import "AXSXtraDocument.h"

/*!
 * @brief One page of a document window
 *
 * Every page is a scrolling settings form, built in code on the same form
 * view the Adium preferences use. Subclasses build their rows in -buildForm
 * and refresh their controls from the document in -reloadFromModel.
 */
@interface AXSEditorViewController : NSViewController

@property (weak, nonatomic, readonly) AXSXtraDocument *document;
@property (readonly, nonatomic) AISettingsFormView *form;

- (instancetype)initWithDocument:(AXSXtraDocument *)document;

//The tab this page goes by
- (NSString *)tabTitle;

//Build the form's rows; called once after the form exists
- (void)buildForm;

//Push the document's current state into the controls
- (void)reloadFromModel;

@end
