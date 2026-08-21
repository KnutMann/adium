/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSEditorViewController.h"

/*!
 * @brief Flipped container so the form stacks from the top
 */
@interface AXSFlippedDocumentView : NSView
@end

@implementation AXSFlippedDocumentView
- (BOOL)isFlipped { return YES; }
@end

@interface AXSEditorViewController ()
@property (weak, nonatomic, readwrite) AXSXtraDocument *document;
@property (readwrite, nonatomic) AISettingsFormView *form;
@end

@implementation AXSEditorViewController {
	NSScrollView *scrollView;
}

- (instancetype)initWithDocument:(AXSXtraDocument *)document
{
	if ((self = [super initWithNibName:nil bundle:nil])) {
		_document = document;
	}
	return self;
}

- (void)loadView
{
	scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 720, 520)];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setAutohidesScrollers:YES];
	[scrollView setDrawsBackground:NO];

	AXSFlippedDocumentView *container = [[AXSFlippedDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 720, 520)];
	[container setAutoresizingMask:NSViewWidthSizable];

	self.form = [[AISettingsFormView alloc] initWithWidth:680.0];
	[container addSubview:self.form];

	[scrollView setDocumentView:container];

	self.view = scrollView;

	[self buildForm];
	[self reloadFromModel];
}

- (void)viewDidLayout
{
	[super viewDidLayout];
	[self.form layoutForWidth:NSWidth([scrollView contentView].bounds)];
}

- (NSString *)tabTitle
{
	return @"";
}

- (void)buildForm
{
}

- (void)reloadFromModel
{
}

@end
