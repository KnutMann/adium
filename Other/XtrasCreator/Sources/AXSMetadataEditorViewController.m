/*
 * XtrasCreator is part of the Adium project and shares its license; see the
 * License.txt at the repository root.
 */

#import "AXSMetadataEditorViewController.h"

@implementation AXSMetadataEditorViewController {
	NSTextField *nameField;
	NSTextField *versionField;
	NSTextField *authorsField;
	NSTextField *descriptionField;
	NSTextField *identifierField;
}

- (NSString *)tabTitle
{
	return @"Info";
}

- (void)buildForm
{
	AISettingsFormView *form = self.form;
	[form setSharesLabelColumn:YES];

	[form addSectionHeader:@"Xtra"];

	nameField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedName:)];
	[form addRowWithLabel:@"Name" stretchingControl:nameField];

	versionField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedVersion:)];
	[form addRowWithLabel:@"Version" stretchingControl:versionField];

	authorsField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedAuthors:)];
	[form addRowWithLabel:@"Author" stretchingControl:authorsField];

	descriptionField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedDescription:)];
	[form addRowWithLabel:@"Description" stretchingControl:descriptionField];
	[form addFootnote:@"A sentence or two saying what this xtra does. "
					  @"Adium shows it on the xtra's own page in its Xtras settings, "
					  @"beside the icon and under the name."];

	[form addSectionHeader:@"Bundle"];

	identifierField = [AISettingsFormView textFieldWithTarget:self action:@selector(changedIdentifier:)];
	[form addRowWithLabel:@"Identifier" stretchingControl:identifierField];
	[form addFootnote:@"A reverse-DNS name such as com.example.myxtra. "
					  @"Left empty, a stable one is minted on the first save. "
					  @"Message styles are told apart by this, so give them one of their own."];
}

- (void)reloadFromModel
{
	AXSXtraModel *model = self.document.model;

	[nameField setStringValue:model.bundleName ?: @""];
	[versionField setStringValue:model.version ?: @""];
	[authorsField setStringValue:model.authors ?: @""];
	[descriptionField setStringValue:model.xtraDescription ?: @""];
	[identifierField setStringValue:model.bundleIdentifier ?: @""];
}

#pragma mark Actions

- (IBAction)changedName:(id)sender
{
	if ([self.document.model.bundleName isEqualToString:[nameField stringValue]]) return;
	self.document.model.bundleName = [nameField stringValue];
	[self.document noteEdited];
}

- (IBAction)changedVersion:(id)sender
{
	if ([self.document.model.version isEqualToString:[versionField stringValue]]) return;
	self.document.model.version = [versionField stringValue];
	[self.document noteEdited];
}

- (IBAction)changedAuthors:(id)sender
{
	if ([self.document.model.authors isEqualToString:[authorsField stringValue]]) return;
	self.document.model.authors = [authorsField stringValue];
	[self.document noteEdited];
}

- (IBAction)changedDescription:(id)sender
{
	if ([self.document.model.xtraDescription isEqualToString:[descriptionField stringValue]]) return;
	self.document.model.xtraDescription = [descriptionField stringValue];
	[self.document noteEdited];
}

- (IBAction)changedIdentifier:(id)sender
{
	if ([self.document.model.bundleIdentifier isEqualToString:[identifierField stringValue]]) return;
	self.document.model.bundleIdentifier = [identifierField stringValue];
	[self.document noteEdited];
}

@end
