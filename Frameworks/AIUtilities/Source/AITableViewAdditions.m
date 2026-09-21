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

#import "AITableViewAdditions.h"
#import "AIApplicationAdditions.h"
#import <objc/objc-class.h>

@implementation NSTableView (AITableViewAdditions)

//Return an array of items which are currently selected. SourceArray should be an array from which to pull the items;
//its count must be the same as the number of rows
- (NSArray *)selectedItemsFromArray:(NSArray *)sourceArray
{
	NSParameterAssert([sourceArray count] >= [self numberOfRows]);

	NSMutableArray 	*itemArray = [NSMutableArray array];
	id 				item;

	//Apple wants us to do some pretty crazy stuff for selections in 10.3
	NSIndexSet *indices = [self selectedRowIndexes];
	NSUInteger bufSize = [indices count];
	NSUInteger *buf = malloc(bufSize * sizeof(NSUInteger));
	NSUInteger i;

	NSRange range = NSMakeRange([indices firstIndex], ([indices lastIndex]-[indices firstIndex]) + 1);
	[indices getIndexes:buf maxCount:bufSize inIndexRange:&range];
		
	for (i = 0; i != bufSize; i++) {
		if ((item = [sourceArray objectAtIndex:buf[i]])) {
			[itemArray addObject:item];
		}
	}

	free(buf);

	return itemArray;
}

- (void)selectItemsInArray:(NSArray *)selectedItems usingSourceArray:(NSArray *)sourceArray
{
	if ([sourceArray count] != [self numberOfRows]) {
		NSLog(@"SourceArray is %lu; rows is %ld",(unsigned long)[sourceArray count], (long)[self numberOfRows]);
	}

	NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
	
	NSEnumerator *enumerator = [selectedItems objectEnumerator];
	id	item;
	while ((item = [enumerator nextObject])) {
		NSUInteger i = [sourceArray indexOfObject:item];
		if (i != NSNotFound) {
			[indexes addIndex:i];
		}
	}
	
	[self selectRowIndexes:indexes byExtendingSelection:NO];
}

- (NSTableCellView *)ai_labelCellViewForColumn:(NSTableColumn *)tableColumn value:(id)value
{
	NSString		*identifier = [tableColumn identifier];
	NSTableCellView	*view = [self makeViewWithIdentifier:identifier owner:nil];

	if (!view) {
		view = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
		[view setIdentifier:identifier];

		NSTextField *label = [NSTextField labelWithString:@""];
		[label setLineBreakMode:NSLineBreakByTruncatingTail];
		[label setTranslatesAutoresizingMaskIntoConstraints:NO];
		[view addSubview:label];
		[view setTextField:label];

		[NSLayoutConstraint activateConstraints:@[
			[[label leadingAnchor] constraintEqualToAnchor:[view leadingAnchor] constant:2.0],
			[[label trailingAnchor] constraintEqualToAnchor:[view trailingAnchor] constant:-2.0],
			[[label centerYAnchor] constraintEqualToAnchor:[view centerYAnchor]],
		]];
	}

	NSString *text = ([value isKindOfClass:[NSString class]] ? value :
					  ((value && value != [NSNull null]) ? [value description] : @""));
	[[view textField] setStringValue:text];

	return view;
}

- (NSTableCellView *)ai_imageCellViewForColumn:(NSTableColumn *)tableColumn image:(NSImage *)image
{
	NSString		*identifier = [tableColumn identifier];
	NSTableCellView	*view = [self makeViewWithIdentifier:identifier owner:nil];

	if (!view) {
		view = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
		[view setIdentifier:identifier];

		NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		[imageView setImageScaling:NSImageScaleProportionallyDown];
		[imageView setImageAlignment:NSImageAlignCenter];
		[imageView setTranslatesAutoresizingMaskIntoConstraints:NO];
		[view addSubview:imageView];
		[view setImageView:imageView];

		[NSLayoutConstraint activateConstraints:@[
			[[imageView leadingAnchor] constraintEqualToAnchor:[view leadingAnchor] constant:2.0],
			[[imageView trailingAnchor] constraintEqualToAnchor:[view trailingAnchor] constant:-2.0],
			[[imageView topAnchor] constraintEqualToAnchor:[view topAnchor] constant:2.0],
			[[imageView bottomAnchor] constraintEqualToAnchor:[view bottomAnchor] constant:-2.0],
		]];
	}

	[[view imageView] setImage:image];

	return view;
}

- (AISidebarCellView *)ai_iconLabelCellViewForColumn:(NSTableColumn *)tableColumn image:(NSImage *)image value:(id)value
{
	NSString			*identifier = [tableColumn identifier];
	AISidebarCellView	*view = [self makeViewWithIdentifier:identifier owner:nil];

	if (!view) {
		view = [[AISidebarCellView alloc] initWithFrame:NSZeroRect];
		[view setIdentifier:identifier];

		NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		[imageView setImageScaling:NSImageScaleProportionallyDown];
		[imageView setImageAlignment:NSImageAlignCenter];
		[imageView setTranslatesAutoresizingMaskIntoConstraints:NO];
		[view addSubview:imageView];
		[view setSidebarIcon:imageView];

		NSTextField *label = [NSTextField labelWithString:@""];
		[label setLineBreakMode:NSLineBreakByTruncatingTail];
		[label setTranslatesAutoresizingMaskIntoConstraints:NO];
		[view addSubview:label];
		[view setSidebarLabel:label];

		[NSLayoutConstraint activateConstraints:@[
			[[imageView leadingAnchor] constraintEqualToAnchor:[view leadingAnchor] constant:2.0],
			[[imageView widthAnchor] constraintEqualToConstant:16.0],
			[[imageView heightAnchor] constraintEqualToConstant:16.0],
			[[imageView centerYAnchor] constraintEqualToAnchor:[view centerYAnchor]],
			[[label leadingAnchor] constraintEqualToAnchor:[imageView trailingAnchor] constant:4.0],
			[[label trailingAnchor] constraintEqualToAnchor:[view trailingAnchor] constant:-2.0],
			[[label centerYAnchor] constraintEqualToAnchor:[view centerYAnchor]],
		]];
	}

	NSString *text = ([value isKindOfClass:[NSString class]] ? value :
					  ((value && value != [NSNull null]) ? [value description] : @""));
	[[view sidebarIcon] setImage:image];
	[[view sidebarLabel] setStringValue:text];
	[view updateTextColors];

	return view;
}

- (AICheckboxTableCellView *)ai_checkboxCellViewForColumn:(NSTableColumn *)tableColumn
														on:(BOOL)on
												   enabled:(BOOL)enabled
													target:(id)target
													action:(SEL)action
{
	NSString				*identifier = [tableColumn identifier];
	AICheckboxTableCellView	*view = [self makeViewWithIdentifier:identifier owner:nil];

	if (!view) {
		view = [[AICheckboxTableCellView alloc] initWithFrame:NSZeroRect];
		[view setIdentifier:identifier];

		NSButton *checkbox = [[NSButton alloc] initWithFrame:NSZeroRect];
		[checkbox setButtonType:NSButtonTypeSwitch];
		[checkbox setTitle:@""];
		[checkbox setImagePosition:NSImageOnly];
		[checkbox setTranslatesAutoresizingMaskIntoConstraints:NO];
		[view addSubview:checkbox];
		[view setCheckbox:checkbox];

		[NSLayoutConstraint activateConstraints:@[
			[[checkbox centerXAnchor] constraintEqualToAnchor:[view centerXAnchor]],
			[[checkbox centerYAnchor] constraintEqualToAnchor:[view centerYAnchor]],
		]];
	}

	NSButton *checkbox = [view checkbox];
	[checkbox setState:(on ? NSControlStateValueOn : NSControlStateValueOff)];
	[checkbox setEnabled:enabled];
	[checkbox setTarget:target];
	[checkbox setAction:action];

	return view;
}

@end

@implementation AICheckboxTableCellView
@end

@implementation AISidebarCellView

@synthesize isGroupRow, sidebarLabel, sidebarIcon;

- (void)setBackgroundStyle:(NSBackgroundStyle)style
{
	[super setBackgroundStyle:style];
	[self updateTextColors];
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	[self updateTextColors];
}

/*!
 * @brief AppKit re-tints the label right before drawing; have the last word
 *
 * Without this, an unemphasised source list selection keeps the accent colour AppKit applies
 * after setBackgroundStyle: has run.
 */
- (void)viewWillDraw
{
	[self updateTextColors];
	[super viewWillDraw];
}

- (void)updateTextColors
{
	/* Only the focused window keeps full-strength labels: System Settings dims its sidebar as
	 * soon as the window is no longer key, whether the app went inactive or another window of
	 * the same app took focus. */
	BOOL	windowActive = [[self window] isKeyWindow];
	NSColor	*color;

	if (isGroupRow) {
		color = (windowActive ? [NSColor secondaryLabelColor] : [NSColor tertiaryLabelColor]);
	} else if (!windowActive) {
		//Inactive window: everything dims, the selected row included
		color = [NSColor secondaryLabelColor];
	} else if ([self backgroundStyle] == NSBackgroundStyleEmphasized) {
		color = [NSColor alternateSelectedControlTextColor];
	} else {
		color = [NSColor labelColor];
	}

	[sidebarLabel setTextColor:color];
}

@end

@implementation AISidebarRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
	if (![self isSelected])
		return;

	BOOL	windowActive = [[self window] isKeyWindow];
	NSColor	*fill;

	if ([self isEmphasized] && windowActive) {
		fill = [NSColor selectedContentBackgroundColor];
	} else {
		//Noticeably deeper than unemphasizedSelectedContentBackgroundColor
		fill = [[NSColor labelColor] colorWithAlphaComponent:0.14];
	}

	NSRect			pill = NSInsetRect([self bounds], 5.0, 1.0);
	NSBezierPath	*path = [NSBezierPath bezierPathWithRoundedRect:pill xRadius:6.0 yRadius:6.0];

	[fill set];
	[path fill];
}

@end

@interface AITableView : NSTableView {}
@end

@implementation AITableView


/* 
 * @brief Load
 *
 * Install ourself to intercept keyDown: calls so we can stick our delete handling in, and menuForEvent: calls so we can ask our delegate
 */
+ (void)load
{
	//Anything you can do, I can do better...
	method_exchangeImplementations(class_getInstanceMethod([NSTableView class], @selector(keyDown:)), class_getInstanceMethod(self, @selector(keyDown:)));
	
	method_exchangeImplementations(class_getInstanceMethod([NSTableView class], @selector(menuForEvent:)), class_getInstanceMethod(self, @selector(menuForEvent:)));
}

//Filter keydowns looking for the delete key (to delete the current selection)
- (void)keyDown:(NSEvent *)theEvent
{
	NSString	*charString = [theEvent charactersIgnoringModifiers];
	unichar		pressedChar = 0;

	//Get the pressed character
	if ([charString length] == 1) pressedChar = [charString characterAtIndex:0];

	//Check if 'delete' was pressed
	if (pressedChar == NSDeleteFunctionKey || pressedChar == NSBackspaceCharacter || pressedChar == NSDeleteCharacter) { //Delete
		if ([[self delegate] respondsToSelector:@selector(tableViewDeleteSelectedRows:)])
			[(id <AITableViewDelegate>)[self delegate] tableViewDeleteSelectedRows:self]; //Delete the selection
	} else {
		//Pass the key event on to the unswizzled impl
        static void (*_key_down_method_invoke)(id, Method, NSEvent *) = (void (*)(id, Method, NSEvent *)) method_invoke;
		_key_down_method_invoke(self, class_getInstanceMethod([AITableView class], @selector(keyDown:)), theEvent);
	}
}

//Allow our delegate to specify context menus
- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
	if ([[self delegate] respondsToSelector:@selector(tableView:menuForEvent:)])
		return [(id<AITableViewDelegate>)[self delegate] tableView:self menuForEvent:theEvent];
    
    static NSMenu * (*_menu_for_event_method_invoke)(id, Method, NSEvent *) = (NSMenu * (*)(id, Method, NSEvent *)) method_invoke;
	return _menu_for_event_method_invoke(self, class_getInstanceMethod([AITableView class], @selector(menuForEvent:)), theEvent);
}

@end
