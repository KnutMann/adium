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

#import <AIUtilities/AIToolbarUtilities.h>

@interface TestToolbarUtilities : XCTestCase
@end

//A view that cannot be copied but wants to know which item it ends up in
@interface AIPlainToolbarView : NSView
@property (nonatomic, weak) NSToolbarItem *toolbarItemToldOf;
@end

@implementation AIPlainToolbarView

- (void)setToolbarItem:(NSToolbarItem *)item
{
	self.toolbarItemToldOf = item;
}

@end

@interface AICopyableToolbarView : AIPlainToolbarView <NSCopying>
@end

@implementation AICopyableToolbarView

- (id)copyWithZone:(NSZone *)zone
{
	return [[[self class] alloc] initWithFrame:[self frame]];
}

@end

@implementation TestToolbarUtilities

- (NSToolbarItem *)itemWithTarget:(id)target action:(SEL)action selector:(SEL)settingSelector content:(id)content menu:(NSMenu *)menu
{
	return [AIToolbarUtilities toolbarItemWithIdentifier:@"AITestItem"
												   label:@"Label"
											paletteLabel:@"Palette label"
												 toolTip:@"Tool tip"
												  target:target
										 settingSelector:settingSelector
											 itemContent:content
												  action:action
													menu:menu];
}

- (void)testToolbarItemCarriesIdentifierLabelsAndToolTip
{
	NSToolbarItem *item = [self itemWithTarget:nil action:NULL selector:NULL content:nil menu:nil];

	XCTAssertEqualObjects([item itemIdentifier], @"AITestItem");
	XCTAssertEqualObjects([item label], @"Label");
	XCTAssertEqualObjects([item paletteLabel], @"Palette label");
	XCTAssertEqualObjects([item toolTip], @"Tool tip");
}

- (void)testToolbarItemSetsTargetAndAction
{
	NSToolbarItem *item = [self itemWithTarget:self action:@selector(description) selector:NULL content:nil menu:nil];

	XCTAssertTrue([item target] == self);
	XCTAssertTrue([item action] == @selector(description));
}

- (void)testToolbarItemWithoutTargetOrActionLeavesThemUnset
{
	NSToolbarItem *item = [self itemWithTarget:nil action:NULL selector:NULL content:nil menu:nil];

	XCTAssertNil([item target]);
	XCTAssertTrue([item action] == NULL);
}

- (void)testToolbarItemSettingSelectorInstallsTheContent
{
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];

	NSToolbarItem *item = [self itemWithTarget:nil action:NULL selector:@selector(setImage:) content:image menu:nil];
	XCTAssertTrue([item image] == image);
}

- (void)testToolbarItemWithAViewInstallsIt
{
	AIPlainToolbarView *view = [[AIPlainToolbarView alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];

	NSToolbarItem *item = [self itemWithTarget:nil action:NULL selector:@selector(setView:) content:view menu:nil];
	XCTAssertTrue([item view] == view);
}

- (void)testToolbarItemWithASelectorButNoContentSetsNothing
{
	NSToolbarItem *item = [self itemWithTarget:nil action:NULL selector:@selector(setView:) content:nil menu:nil];

	XCTAssertNil([item view]);
}

- (void)testToolbarItemWrapsTheMenuInAMenuItemNamedAfterIt
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Choices"];

	NSToolbarItem *item = [self itemWithTarget:nil action:NULL selector:NULL content:nil menu:menu];
	NSMenuItem *form = [item menuFormRepresentation];
	XCTAssertNotNil(form);
	XCTAssertTrue([form submenu] == menu);
	XCTAssertEqualObjects([form title], @"Choices");
}

- (void)testAddToolbarItemToDictionaryStoresTheItemUnderItsIdentifier
{
	NSMutableDictionary *items = [NSMutableDictionary dictionary];

	[AIToolbarUtilities addToolbarItemToDictionary:items
									withIdentifier:@"AIStored"
											 label:@"Stored"
									  paletteLabel:@"Stored"
										   toolTip:nil
											target:self
								   settingSelector:NULL
									   itemContent:nil
											action:@selector(description)
											  menu:nil];
	NSToolbarItem *item = items[@"AIStored"];
	XCTAssertTrue([item isKindOfClass:[NSToolbarItem class]]);
	XCTAssertEqualObjects([item itemIdentifier], @"AIStored");
	XCTAssertEqualObjects([item label], @"Stored");
	XCTAssertTrue([item target] == self);
}

- (void)testToolbarItemFromDictionaryIsAFreshItemWithTheSameIdentity
{
	NSMutableDictionary *items = [NSMutableDictionary dictionary];
	[AIToolbarUtilities addToolbarItemToDictionary:items withIdentifier:@"AIStored" label:@"Stored" paletteLabel:@"On the palette" toolTip:@"Tip" target:nil settingSelector:NULL itemContent:nil action:NULL menu:nil];
	NSToolbarItem *stored = items[@"AIStored"];

	NSToolbarItem *fresh = [AIToolbarUtilities toolbarItemFromDictionary:items withIdentifier:@"AIStored"];
	XCTAssertNotNil(fresh);
	XCTAssertFalse(fresh == stored);
	XCTAssertEqualObjects([fresh itemIdentifier], @"AIStored");
	XCTAssertEqualObjects([fresh label], @"Stored");
	XCTAssertEqualObjects([fresh paletteLabel], @"On the palette");
	XCTAssertEqualObjects([fresh toolTip], @"Tip");
	XCTAssertTrue(items[@"AIStored"] == stored, @"the dictionary keeps the original");
}

- (void)testToolbarItemFromDictionarySharesAViewThatCannotBeCopiedAndTellsItTheNewItem
{
	AIPlainToolbarView *view = [[AIPlainToolbarView alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
	NSMutableDictionary *items = [NSMutableDictionary dictionary];
	[AIToolbarUtilities addToolbarItemToDictionary:items withIdentifier:@"AIViewItem" label:@"V" paletteLabel:@"V" toolTip:nil target:nil settingSelector:@selector(setView:) itemContent:view action:NULL menu:nil];

	NSToolbarItem *fresh = [AIToolbarUtilities toolbarItemFromDictionary:items withIdentifier:@"AIViewItem"];
	XCTAssertTrue([fresh view] == view);
	XCTAssertTrue(view.toolbarItemToldOf == fresh);
}

- (void)testToolbarItemFromDictionaryCopiesAViewThatCanBeCopied
{
	AICopyableToolbarView *view = [[AICopyableToolbarView alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
	NSMutableDictionary *items = [NSMutableDictionary dictionary];
	[AIToolbarUtilities addToolbarItemToDictionary:items withIdentifier:@"AIViewItem" label:@"V" paletteLabel:@"V" toolTip:nil target:nil settingSelector:@selector(setView:) itemContent:view action:NULL menu:nil];

	NSToolbarItem *fresh = [AIToolbarUtilities toolbarItemFromDictionary:items withIdentifier:@"AIViewItem"];
	NSView *freshView = [fresh view];
	XCTAssertNotNil(freshView);
	XCTAssertFalse(freshView == view);
	XCTAssertTrue([freshView isKindOfClass:[AICopyableToolbarView class]]);
	XCTAssertTrue([(AICopyableToolbarView *)freshView toolbarItemToldOf] == fresh);
	XCTAssertTrue([items[@"AIViewItem"] view] == view, @"the stored item keeps its own view");
}

@end
