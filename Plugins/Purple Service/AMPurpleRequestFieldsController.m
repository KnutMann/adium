/*
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 *
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import "AMPurpleRequestFieldsController.h"
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIStringAdditions.h>

#define REQUEST_WINDOW_WIDTH	480.0
#define REQUEST_MARGIN			20.0
#define REQUEST_FORM_MAX_HEIGHT	420.0

/*!
 * @brief One request field: knows its row in the form and how to write the answer back.
 *
 * The value is written in -submit, not as the user types: libpurple only reads the
 * fields when the ok callback fires, and writing early would leave half-typed answers
 * behind a cancel.
 */
@interface AMPurpleRequestField : NSObject {
	PurpleRequestField *field;
}

- (id)initWithRequestField:(PurpleRequestField *)inField;
- (void)addToForm:(AISettingsFormView *)form;
- (void)submit;
- (NSString *)rowLabel;

@end

@implementation AMPurpleRequestField

- (id)initWithRequestField:(PurpleRequestField *)inField
{
	if ((self = [super init])) {
		field = inField;
	}
	return self;
}

- (void)addToForm:(AISettingsFormView *)form
{
}

- (void)submit
{
}

/*!
 * @brief The field's label, shaped for a form row.
 *
 * Protocols punctuate ("Nickname:", "Reason?"); the form's label column does not, so a
 * single trailing punctuation mark comes off — the same trimming the 1.6 branch applied.
 */
- (NSString *)rowLabel
{
	const char *labelstr = purple_request_field_get_label(field);
	if (!labelstr) return @"";

	NSString *label = [NSString stringWithUTF8String:labelstr];
	unichar last = [label lastCharacter];

	if (last == ':' || last == ';' || last == ',' || last == '.' || last == '?')
		label = [label substringToIndex:[label length] - 1];

	return label;
}

@end

#pragma mark -

@interface AMPurpleRequestFieldString : AMPurpleRequestField {
	NSTextField *textField;		//NSSecureTextField when the protocol asked for masking
}
@end

@implementation AMPurpleRequestFieldString

- (void)dealloc
{
	[textField release];
	[super dealloc];
}

- (void)addToForm:(AISettingsFormView *)form
{
	//An invisible field is not shown, and -submit answers it with its default
	if (!purple_request_field_is_visible(field)) return;

	const char *defaultvalue = purple_request_field_string_get_default_value(field);

	textField = purple_request_field_string_is_masked(field) ?
		[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 220.0, 24.0)] :
		[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 220.0, 24.0)];

	[textField setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[textField setStringValue:(defaultvalue ? [NSString stringWithUTF8String:defaultvalue] : @"")];
	[textField setEditable:(purple_request_field_string_is_editable(field) ? YES : NO)];
	[textField sizeToFit];
	[textField setFrameSize:NSMakeSize(220.0, NSHeight([textField frame]))];

	[form addRowWithLabel:[self rowLabel] stretchingControl:textField];
}

- (void)submit
{
	if (textField) {
		purple_request_field_string_set_value(field, [[textField stringValue] UTF8String]);
	} else {
		//Never shown: the default is the answer
		purple_request_field_string_set_value(field, purple_request_field_string_get_default_value(field));
	}
}

@end

#pragma mark -

@interface AMPurpleRequestFieldMultilineString : AMPurpleRequestField {
	NSTextView *textView;
}
@end

@implementation AMPurpleRequestFieldMultilineString

- (void)dealloc
{
	[textView release];
	[super dealloc];
}

- (void)addToForm:(AISettingsFormView *)form
{
	if (!purple_request_field_is_visible(field)) return;

	const char *defaultvalue = purple_request_field_string_get_default_value(field);
	NSRect frame = NSMakeRect(0, 0, 220.0, 72.0);

	NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:frame] autorelease];
	[scrollView setBorderType:NSBezelBorder];
	[scrollView setHasVerticalScroller:YES];
	[scrollView setAutohidesScrollers:YES];

	textView = [[NSTextView alloc] initWithFrame:frame];
	[textView setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[textView setRichText:NO];
	[textView setEditable:(purple_request_field_string_is_editable(field) ? YES : NO)];
	[textView setString:(defaultvalue ? [NSString stringWithUTF8String:defaultvalue] : @"")];
	//Track the row's width: the scroll view resizes with the window column, the text follows
	[textView setAutoresizingMask:NSViewWidthSizable];
	[[textView textContainer] setWidthTracksTextView:YES];

	[scrollView setDocumentView:textView];

	[form addRowWithLabel:[self rowLabel] stretchingControl:scrollView labelTopAligned:YES];
}

- (void)submit
{
	if (textView) {
		purple_request_field_string_set_value(field, [[textView string] UTF8String]);
	} else {
		purple_request_field_string_set_value(field, purple_request_field_string_get_default_value(field));
	}
}

@end

#pragma mark -

@interface AMPurpleRequestFieldInteger : AMPurpleRequestField {
	NSTextField *textField;
}
@end

@implementation AMPurpleRequestFieldInteger

- (void)dealloc
{
	[textField release];
	[super dealloc];
}

- (void)addToForm:(AISettingsFormView *)form
{
	textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100.0, 24.0)];
	[textField setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];

	/* The formatter is what the old HTML form never had: it refuses non-digits at the
	 * source instead of silently reading them as zero on submit. */
	NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
	[formatter setNumberStyle:NSNumberFormatterNoStyle];
	[formatter setAllowsFloats:NO];
	[textField setFormatter:formatter];

	[textField setIntegerValue:purple_request_field_int_get_default_value(field)];
	[textField sizeToFit];
	[textField setFrameSize:NSMakeSize(100.0, NSHeight([textField frame]))];

	[form addRowWithLabel:[self rowLabel] control:textField];
}

- (void)submit
{
	purple_request_field_int_set_value(field, [textField intValue]);
}

@end

#pragma mark -

@interface AMPurpleRequestFieldBoolean : AMPurpleRequestField {
	NSSwitch *toggle;
}
@end

@implementation AMPurpleRequestFieldBoolean

- (void)dealloc
{
	[toggle release];
	[super dealloc];
}

- (void)addToForm:(AISettingsFormView *)form
{
	toggle = [[AISettingsFormView switchWithTarget:nil action:NULL] retain];
	[toggle setState:(purple_request_field_bool_get_default_value(field) ? NSControlStateValueOn : NSControlStateValueOff)];

	[form addRowWithLabel:[self rowLabel] control:toggle];
}

- (void)submit
{
	purple_request_field_bool_set_value(field, ([toggle state] == NSControlStateValueOn) ? TRUE : FALSE);
}

@end

#pragma mark -

@interface AMPurpleRequestFieldChoice : AMPurpleRequestField {
	NSPopUpButton *popUp;
}
@end

@implementation AMPurpleRequestFieldChoice

- (void)dealloc
{
	[popUp release];
	[super dealloc];
}

- (void)addToForm:(AISettingsFormView *)form
{
	NSMutableArray *titles = [NSMutableArray array];

	for (GList *label = purple_request_field_choice_get_labels(field); label; label = g_list_next(label)) {
		if (label->data) [titles addObject:[NSString stringWithUTF8String:label->data]];
	}
	if (![titles count]) return;

	popUp = [[AISettingsFormView popUpButtonWithTitles:titles target:nil action:NULL] retain];

	NSInteger defaultvalue = purple_request_field_choice_get_default_value(field);
	if (defaultvalue >= 0 && defaultvalue < [popUp numberOfItems])
		[popUp selectItemAtIndex:defaultvalue];

	[form addRowWithLabel:[self rowLabel] popUpButton:popUp accessoryButton:nil];
}

- (void)submit
{
	//A choice's value is its index; that is the contract on the libpurple side
	if ([popUp indexOfSelectedItem] >= 0)
		purple_request_field_choice_set_value(field, (int)[popUp indexOfSelectedItem]);
}

@end

#pragma mark -

@interface AMPurpleRequestFieldList : AMPurpleRequestField {
	NSPopUpButton *popUp;
}
@end

@implementation AMPurpleRequestFieldList

- (void)dealloc
{
	[popUp release];
	[super dealloc];
}

- (void)addToForm:(AISettingsFormView *)form
{
	NSMutableArray	*titles = [NSMutableArray array];
	NSInteger		 selectedIndex = -1;

	for (const GList *item = purple_request_field_list_get_items(field); item; item = g_list_next(item)) {
		if (!item->data) continue;
		if (purple_request_field_list_is_selected(field, item->data)) selectedIndex = (NSInteger)[titles count];
		[titles addObject:[NSString stringWithUTF8String:item->data]];
	}
	if (![titles count]) return;

	popUp = [[AISettingsFormView popUpButtonWithTitles:titles target:nil action:NULL] retain];
	if (selectedIndex >= 0) [popUp selectItemAtIndex:selectedIndex];

	[form addRowWithLabel:[self rowLabel] popUpButton:popUp accessoryButton:nil];
}

- (void)submit
{
	if (!popUp) return;

	purple_request_field_list_clear_selected(field);
	if ([popUp selectedItem])
		purple_request_field_list_add_selected(field, [[[popUp selectedItem] title] UTF8String]);
}

@end

#pragma mark -

/*!
 * @brief A multi-select list as a column of check boxes.
 *
 * The 1.6 branch put these behind a pull down menu whose items toggled check marks —
 * compact, but it hides the choices and the menu closes after every click. A column
 * shows everything at once, and the window's scroll view absorbs a long one.
 */
@interface AMPurpleRequestFieldMultiList : AMPurpleRequestField {
	NSMutableArray *checkBoxes;
}
@end

@implementation AMPurpleRequestFieldMultiList

- (void)dealloc
{
	[checkBoxes release];
	[super dealloc];
}

- (void)addToForm:(AISettingsFormView *)form
{
	checkBoxes = [[NSMutableArray alloc] init];

	for (const GList *item = purple_request_field_list_get_items(field); item; item = g_list_next(item)) {
		if (!item->data) continue;

		NSButton *checkBox = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
		[checkBox setButtonType:NSButtonTypeSwitch];
		[checkBox setTitle:[NSString stringWithUTF8String:item->data]];
		[checkBox setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
		[checkBox setState:(purple_request_field_list_is_selected(field, item->data) ? NSControlStateValueOn : NSControlStateValueOff)];
		[checkBox sizeToFit];

		[checkBoxes addObject:checkBox];
	}
	if (![checkBoxes count]) return;

	//Stack the boxes top-down in one container; the container is the row's control
	CGFloat spacing = 4.0;
	CGFloat rowHeight = NSHeight([[checkBoxes objectAtIndex:0] frame]);
	CGFloat totalHeight = ([checkBoxes count] * rowHeight) + (([checkBoxes count] - 1) * spacing);

	NSView *column = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220.0, totalHeight)] autorelease];
	CGFloat y = totalHeight;

	for (NSButton *checkBox in checkBoxes) {
		y -= rowHeight;
		[checkBox setFrameOrigin:NSMakePoint(0, y)];
		[column addSubview:checkBox];
		y -= spacing;
	}

	[form addRowWithLabel:[self rowLabel] stretchingControl:column labelTopAligned:YES];
}

- (void)submit
{
	if (![checkBoxes count]) return;

	purple_request_field_list_clear_selected(field);
	for (NSButton *checkBox in checkBoxes) {
		if ([checkBox state] == NSControlStateValueOn)
			purple_request_field_list_add_selected(field, [[checkBox title] UTF8String]);
	}
}

@end

#pragma mark -

@interface AMPurpleRequestFieldLabel : AMPurpleRequestField
@end

@implementation AMPurpleRequestFieldLabel

- (void)addToForm:(AISettingsFormView *)form
{
	//The full text, punctuation and all: this is prose, not a row label
	const char *labelstr = purple_request_field_get_label(field);
	if (labelstr) [form addDetailRow:[NSString stringWithUTF8String:labelstr]];
}

@end

#pragma mark -

@implementation AMPurpleRequestFieldsController

- (id)initWithTitle:(NSString*)title
        primaryText:(NSString*)primary
      secondaryText:(NSString*)secondary
      requestFields:(PurpleRequestFields*)_fields
             okText:(NSString*)okText
           callback:(GCallback)_okcb
         cancelText:(NSString*)cancelText
           callback:(GCallback)_cancelcb
            account:(CBPurpleAccount*)account
                who:(NSString*)who
       conversation:(PurpleConversation*)conv
           userData:(void*)_userData
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, REQUEST_WINDOW_WIDTH, 200.0)
												   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
													 backing:NSBackingStoreBuffered
													   defer:NO];
	[window setReleasedWhenClosed:NO];

	if ((self = [super initWithWindow:window])) {
		fields = _fields;
		okcb = _okcb;
		cancelcb = _cancelcb;
		userData = _userData;
		fieldobjects = [[NSMutableArray alloc] init];

		//A nib would have wired this; without one the close box only reaches us as delegate
		[window setDelegate:self];
		[window setTitle:(title ?: AILocalizedString(@"Form", "Generic fields request window title"))];

		NSView		*content = [window contentView];
		CGFloat		 contentWidth = REQUEST_WINDOW_WIDTH - 2.0 * REQUEST_MARGIN;

		//The form: one row per field, one card per group
		AISettingsFormView *form = [[[AISettingsFormView alloc] initWithWidth:REQUEST_WINDOW_WIDTH] autorelease];

		GList	*groups = purple_request_fields_get_groups(fields);
		BOOL	 severalGroups = (g_list_length(groups) > 1);

		for (GList *gl = groups; gl; gl = gl->next) {
			PurpleRequestFieldGroup *group = gl->data;
			const char *grouptitle = purple_request_field_group_get_title(group);

			if (severalGroups || grouptitle)
				[form addSectionHeader:(grouptitle ? [NSString stringWithUTF8String:grouptitle] : @"")];

			for (GList *fl = purple_request_field_group_get_fields(group); fl; fl = fl->next) {
				PurpleRequestField	*field = fl->data;
				Class				 fieldClass = Nil;

				switch (purple_request_field_get_type(field)) {
					case PURPLE_REQUEST_FIELD_STRING:
						fieldClass = (purple_request_field_string_is_multiline(field) ?
									  [AMPurpleRequestFieldMultilineString class] :
									  [AMPurpleRequestFieldString class]);
						break;
					case PURPLE_REQUEST_FIELD_INTEGER:
						fieldClass = [AMPurpleRequestFieldInteger class];
						break;
					case PURPLE_REQUEST_FIELD_BOOLEAN:
						fieldClass = [AMPurpleRequestFieldBoolean class];
						break;
					case PURPLE_REQUEST_FIELD_CHOICE:
						fieldClass = [AMPurpleRequestFieldChoice class];
						break;
					case PURPLE_REQUEST_FIELD_LIST:
						fieldClass = (purple_request_field_list_get_multi_select(field) ?
									  [AMPurpleRequestFieldMultiList class] :
									  [AMPurpleRequestFieldList class]);
						break;
					case PURPLE_REQUEST_FIELD_LABEL:
						fieldClass = [AMPurpleRequestFieldLabel class];
						break;
					default:
						/* PURPLE_REQUEST_FIELD_IMAGE never gets here — the dispatcher
						 * routes it to AIPurpleImageRequestController — and _ACCOUNT is
						 * unused by libpurple, exactly as the two predecessors noted. */
						break;
				}

				if (fieldClass) {
					AMPurpleRequestField *fieldobject = [[fieldClass alloc] initWithRequestField:field];
					[fieldobjects addObject:fieldobject];
					[fieldobject addToForm:form];
					[fieldobject release];
				}
			}
		}

		[form layoutForWidth:REQUEST_WINDOW_WIDTH];

		/* Assembled bottom up, every origin known the moment its view is placed.
		 * Buttons, then the form in a scroll view, then the two text lines. */
		CGFloat y = REQUEST_MARGIN;

		NSButton *okButton = [AISettingsFormView pushButtonWithTitle:(okText ?: AILocalizedString(@"OK", nil))
															  target:self
															  action:@selector(submit:)];
		NSButton *cancelButton = [AISettingsFormView pushButtonWithTitle:(cancelText ?: AILocalizedString(@"Cancel", nil))
																  target:self
																  action:@selector(cancel:)];
		[okButton setKeyEquivalent:@"\r"];
		[cancelButton setKeyEquivalent:@"\033"];
		if (!_okcb) [okButton setHidden:YES];
		if (!_cancelcb) [cancelButton setHidden:YES];

		[okButton setFrameOrigin:NSMakePoint(REQUEST_WINDOW_WIDTH - REQUEST_MARGIN - NSWidth([okButton frame]), y)];
		[cancelButton setFrameOrigin:NSMakePoint(NSMinX([okButton frame]) - 8.0 - NSWidth([cancelButton frame]), y)];
		[content addSubview:okButton];
		[content addSubview:cancelButton];
		y += NSHeight([okButton frame]) + 16.0;

		/* The form goes into a scroll view so a protocol handing over thirty fields gets a
		 * scrollbar rather than a window taller than the screen. */
		CGFloat formHeight = [form totalHeight];
		CGFloat formDisplayHeight = MIN(formHeight, REQUEST_FORM_MAX_HEIGHT);

		NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, y, REQUEST_WINDOW_WIDTH, formDisplayHeight)] autorelease];
		[scrollView setBorderType:NSNoBorder];
		[scrollView setDrawsBackground:NO];
		[scrollView setHasVerticalScroller:YES];
		[scrollView setAutohidesScrollers:YES];
		[form setFrame:NSMakeRect(0, 0, REQUEST_WINDOW_WIDTH, formHeight)];
		[scrollView setDocumentView:form];
		//A flipped-coordinate dance is not worth it; just start at the top
		[[scrollView documentView] scrollPoint:NSMakePoint(0, formHeight)];
		[content addSubview:scrollView];
		y += formDisplayHeight + 12.0;

		//Secondary under primary, both wrapping at the content width
		if (secondary && [secondary length] && ![secondary isEqualToString:primary]) {
			NSTextField *secondaryField = [self wrappedLabelWithString:secondary
																  font:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]
																 width:contentWidth];
			[secondaryField setTextColor:[NSColor secondaryLabelColor]];
			[secondaryField setFrameOrigin:NSMakePoint(REQUEST_MARGIN, y)];
			[content addSubview:secondaryField];
			y += NSHeight([secondaryField frame]) + 6.0;
		}

		if (primary && [primary length]) {
			NSTextField *primaryField = [self wrappedLabelWithString:primary
																font:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]
															   width:contentWidth];
			[primaryField setFrameOrigin:NSMakePoint(REQUEST_MARGIN, y)];
			[content addSubview:primaryField];
			y += NSHeight([primaryField frame]);
		}

		y += REQUEST_MARGIN;

		[window setContentSize:NSMakeSize(REQUEST_WINDOW_WIDTH, y)];
		[window center];

		[self showWindow:nil];
		[[self window] makeKeyAndOrderFront:nil];
	}

	[window release];

	return [self retain]; //Kept alive as long as the form is open; see -windowWillClose:
}

- (void)dealloc
{
	[fieldobjects release];

	[super dealloc];
}

/*!
 * @brief A non-editable wrapping text line, already sized for @a width.
 */
- (NSTextField *)wrappedLabelWithString:(NSString *)string font:(NSFont *)font width:(CGFloat)width
{
	NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, width, 17.0)] autorelease];

	[label setStringValue:string];
	[label setFont:font];
	[label setEditable:NO];
	[label setSelectable:YES];
	[label setBordered:NO];
	[label setDrawsBackground:NO];
	[[label cell] setWraps:YES];

	NSSize size = [[label cell] cellSizeForBounds:NSMakeRect(0, 0, width, CGFLOAT_MAX)];
	[label setFrameSize:NSMakeSize(width, ceil(size.height))];

	return label;
}

- (IBAction)submit:(id)sender
{
	for (AMPurpleRequestField *fieldobject in fieldobjects) {
		[fieldobject submit];
	}

	if (okcb) ((PurpleRequestFieldsCb)okcb)(userData, fields);
	okcb = NULL;
	cancelcb = NULL;

	[self closeWindow:nil];
}

- (IBAction)cancel:(id)sender
{
	if (cancelcb) ((PurpleRequestFieldsCb)cancelcb)(userData, fields);
	okcb = NULL;
	cancelcb = NULL;

	[self closeWindow:nil];
}

/*!
 * @brief The window is closing by any road: buttons, close box, or libpurple.
 *
 * Only the close box still finds a live cancel callback here — the buttons fire and null
 * theirs first, and -purpleRequestClose nulls both before it closes anything.
 */
- (void)doWindowWillClose
{
	if (cancelcb) ((PurpleRequestFieldsCb)cancelcb)(userData, fields);
	okcb = NULL;
	cancelcb = NULL;
}

- (void)windowWillClose:(id)sender
{
	[super windowWillClose:sender];

	//Balances the retain in init, on every close path; super has already told libpurple
	[self autorelease];
}

/*!
 * @brief libpurple has been made aware we closed or has informed us we should close
 *
 * If we haven't triggered a callback yet, we shouldn't now; the data in question is likely invalid
 * and will crash if used since purple is closing our request at the source
 */
- (void)purpleRequestClose
{
	okcb = NULL;
	cancelcb = NULL;

	[super purpleRequestClose];
}

@end
