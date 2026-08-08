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

#import "AIPurpleImageRequestController.h"

#define PANEL_WIDTH		380.0f
#define IMAGE_SIDE		280.0f
#define MARGIN			20.0f

@interface AIPurpleImageRequestController ()
- (void)buildPanelWithTitle:(NSString *)title primary:(NSString *)primary secondary:(NSString *)secondary
					 okText:(NSString *)okText cancelText:(NSString *)cancelText;
- (void)invokeCallback:(GCallback)cb;
@end

@implementation AIPurpleImageRequestController

+ (instancetype)showImageRequestWithTitle:(NSString *)title
								  primary:(NSString *)primary
								secondary:(NSString *)secondary
									fields:(PurpleRequestFields *)inFields
								   okText:(NSString *)okText
									 okCb:(GCallback)inOkCb
							   cancelText:(NSString *)cancelText
								 cancelCb:(GCallback)inCancelCb
								 userData:(void *)inUserData
{
	AIPurpleImageRequestController *controller = [[self alloc] init];

	controller->fields = inFields;
	controller->okCb = inOkCb;
	controller->cancelCb = inCancelCb;
	controller->userData = inUserData;

	[controller buildPanelWithTitle:title primary:primary secondary:secondary
							 okText:okText cancelText:cancelText];

	//Retained until the panel closes
	return controller;
}

- (void)buildPanelWithTitle:(NSString *)title primary:(NSString *)primary secondary:(NSString *)secondary
					 okText:(NSString *)okText cancelText:(NSString *)cancelText
{
	//Collect the string values (e.g. a pairing code) and the image from the fields
	NSMutableString	*infoText = [NSMutableString string];
	NSImage			*image = nil;

	if (primary) [infoText appendString:primary];

	for (GList *groupIter = purple_request_fields_get_groups(fields); groupIter; groupIter = groupIter->next) {
		PurpleRequestFieldGroup *group = groupIter->data;
		for (GList *fieldIter = purple_request_field_group_get_fields(group); fieldIter; fieldIter = fieldIter->next) {
			PurpleRequestField *field = fieldIter->data;
			switch (purple_request_field_get_type(field)) {
				case PURPLE_REQUEST_FIELD_STRING: {
					const char *label = purple_request_field_get_label(field);
					const char *value = purple_request_field_string_get_default_value(field);
					if (value && *value) {
						[infoText appendFormat:@"\n\n%s:\n%s", (label ? label : ""), value];
					}
					break;
				}
				case PURPLE_REQUEST_FIELD_IMAGE: {
					if (!image) {
						const char *buffer = purple_request_field_image_get_buffer(field);
						gsize size = purple_request_field_image_get_size(field);
						if (buffer && size > 0) {
							NSData *data = [NSData dataWithBytes:buffer length:size];
							image = [[[NSImage alloc] initWithData:data] autorelease];
						}
					}
					break;
				}
				default:
					break;
			}
		}
	}

	//Layout, bottom-up: buttons, image, text
	CGFloat y = MARGIN;

	NSButton *cancelButton = [[[NSButton alloc] initWithFrame:NSMakeRect(MARGIN, y, 120, 32)] autorelease];
	[cancelButton setBezelStyle:NSBezelStyleRounded];
	[cancelButton setTitle:(cancelText ? cancelText : @"Cancel")];
	[cancelButton setTarget:self];
	[cancelButton setAction:@selector(cancelPressed:)];

	NSButton *okButton = [[[NSButton alloc] initWithFrame:NSMakeRect(PANEL_WIDTH - MARGIN - 120, y, 120, 32)] autorelease];
	[okButton setBezelStyle:NSBezelStyleRounded];
	[okButton setTitle:(okText ? okText : @"OK")];
	[okButton setTarget:self];
	[okButton setAction:@selector(okPressed:)];
	[okButton setKeyEquivalent:@"\r"];

	y += 32 + MARGIN;

	NSImageView *imageView = nil;
	if (image) {
		imageView = [[[NSImageView alloc] initWithFrame:NSMakeRect((PANEL_WIDTH - IMAGE_SIDE) / 2.0f, y, IMAGE_SIDE, IMAGE_SIDE)] autorelease];
		[imageView setImage:image];
		[imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
		y += IMAGE_SIDE + MARGIN;
	}

	NSTextField *textField = [[[NSTextField alloc] initWithFrame:NSMakeRect(MARGIN, y, PANEL_WIDTH - 2 * MARGIN, 10)] autorelease];
	[textField setStringValue:infoText];
	[textField setEditable:NO];
	[textField setSelectable:YES];	//So a pairing code can be copied
	[textField setBezeled:NO];
	[textField setDrawsBackground:NO];
	[[textField cell] setWraps:YES];
	NSSize textSize = [[textField cell] cellSizeForBounds:NSMakeRect(0, 0, PANEL_WIDTH - 2 * MARGIN, 400)];
	[textField setFrameSize:NSMakeSize(PANEL_WIDTH - 2 * MARGIN, textSize.height)];
	y += textSize.height + MARGIN;

	panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, PANEL_WIDTH, y)
									   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
										 backing:NSBackingStoreBuffered
										   defer:NO];
	[panel setTitle:(title ? title : @"")];
	[panel setReleasedWhenClosed:NO];
	[panel setLevel:NSFloatingWindowLevel];
	[panel setDelegate:(id)self];

	[[panel contentView] addSubview:textField];
	if (imageView) [[panel contentView] addSubview:imageView];
	[[panel contentView] addSubview:okButton];
	[[panel contentView] addSubview:cancelButton];

	[panel center];
	[panel makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)invokeCallback:(GCallback)cb
{
	if (callbackInvoked) return;
	callbackInvoked = YES;

	if (cb) {
		((PurpleRequestFieldsCb)cb)(userData, fields);
	}

	//Tell libpurple this request is finished; it will call back to close us
	purple_request_close(PURPLE_REQUEST_FIELDS, self);
}

- (void)okPressed:(id)sender
{
	[self invokeCallback:okCb];
}

- (void)cancelPressed:(id)sender
{
	[self invokeCallback:cancelCb];
}

//User closed the window via the close button: treat as cancel
- (BOOL)windowShouldClose:(id)window
{
	[self invokeCallback:cancelCb];
	return NO;	//purple_request_close triggers purpleRequestClose, which closes us
}

//Called (via adiumPurpleRequestClose) when libpurple closes this request
- (void)purpleRequestClose
{
	callbackInvoked = YES;	//No callbacks once purple has torn the request down
	[panel setDelegate:nil];
	[panel orderOut:nil];
	[panel release]; panel = nil;
	[self autorelease];
}

@end
