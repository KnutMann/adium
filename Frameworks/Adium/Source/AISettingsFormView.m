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

#import "AISettingsFormView.h"

//Card geometry, matching the System Settings metrics
static const CGFloat AISettingsOuterMargin		= 20.0;	//Left/right margin of a card
static const CGFloat AISettingsCardCornerRadius	= 10.0;
static const CGFloat AISettingsCardInsetH		= 16.0;	//Label/control inset inside a card
static const CGFloat AISettingsRowMinHeight		= 44.0;
static const CGFloat AISettingsRowInsetV		= 10.0;
static const CGFloat AISettingsLabelControlGap	= 12.0;
static const CGFloat AISettingsMinLabelWidth	= 120.0;
static const CGFloat AISettingsDetailGap		= 2.0;	//Between label and its detail line
static const CGFloat AISettingsHeaderGap		= 8.0;	//Between a section header and its card
static const CGFloat AISettingsSectionGap		= 22.0;	//Above a section header
static const CGFloat AISettingsCardGap			= 12.0;	//Between two cards with no header
static const CGFloat AISettingsRadioTopGap		= 8.0;	//Between a radio group label and its buttons
static const CGFloat AISettingsRadioSpacing		= 6.0;
static const CGFloat AISettingsLabelFontSize	= 13.0;
static const CGFloat AISettingsDetailFontSize	= 11.0;
static const CGFloat AISettingsHeaderFontSize	= 13.0;
static const CGFloat AISettingsFallbackWidth	= 480.0;	//Used when a host gives us no usable width

typedef enum {
	AISettingsRowTypeControl = 0,
	AISettingsRowTypeRadioGroup,
	AISettingsRowTypeFullWidth
} AISettingsRowType;

#pragma mark -

/*!
 * @brief A label styled for use inside the form. Caller owns the returned field.
 */
static NSTextField *AISettingsMakeLabel(NSString *text, NSFont *font, NSColor *color)
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];

	[field setStringValue:(text ?: @"")];
	[field setFont:font];
	[field setTextColor:color];
	[field setEditable:NO];
	[field setSelectable:NO];
	[field setBordered:NO];
	[field setBezeled:NO];
	[field setDrawsBackground:NO];
	[field setAlignment:NSTextAlignmentLeft];
	[field setLineBreakMode:NSLineBreakByWordWrapping];
	[[field cell] setWraps:YES];
	[[field cell] setScrollable:NO];

	return field;
}

/*!
 * @brief Height a wrapping label needs when constrained to @a width.
 */
static CGFloat AISettingsFieldHeight(NSTextField *field, CGFloat width)
{
	if (!field || width < 1.0) return 0.0;

	NSSize size = [[field cell] cellSizeForBounds:NSMakeRect(0.0, 0.0, width, 10000.0)];
	return ceil(size.height);
}

/*!
 * @brief The size a control should be laid out at: its own frame if it has one,
 *        otherwise its fitting size.
 *
 * Only ever called while a control still has its natural size — the result is
 * remembered per row, because layout narrows the frame it would read back.
 */
static NSSize AISettingsControlSize(NSView *control)
{
	NSSize size = (control ? [control frame].size : NSZeroSize);

	if (control && (size.width < 1.0 || size.height < 1.0)) {
		NSSize fitting = [control fittingSize];
		if (size.width < 1.0) size.width = ceil(fitting.width);
		if (size.height < 1.0) size.height = ceil(fitting.height);
	}

	return size;
}

/*!
 * @brief The control a row's label belongs to: the trailing-most one.
 *
 * A row is label-left/control-right, so the trailing control is the one the
 * label names — for a container holding a button and a switch, the switch.
 * Returns nil if @a view holds no control at all.
 */
static NSControl *AISettingsPrimaryControl(NSView *view)
{
	if (!view) return nil;
	if ([view isKindOfClass:[NSControl class]]) return (NSControl *)view;

	NSControl *primary = nil;
	for (NSView *subview in [view subviews]) {
		NSControl *candidate = AISettingsPrimaryControl(subview);
		if (candidate) primary = candidate;
	}

	return primary;
}

/*!
 * @brief Give every unlabelled control below @a view the row's label.
 *
 * NSSwitch, NSStepper, NSPopUpButton and bare text fields carry no visible
 * title, so without this VoiceOver announces a column of anonymous "switch,
 * off" rows. Buttons that show their own title keep it.
 */
static void AISettingsApplyAccessibility(NSView *view, NSString *label, NSString *help)
{
	if (!view) return;

	if ([view isKindOfClass:[NSControl class]]) {
		BOOL hasVisibleTitle = ([view isKindOfClass:[NSButton class]] &&
								[[(NSButton *)view title] length] &&
								[(NSButton *)view imagePosition] != NSImageOnly &&
								![view isKindOfClass:[NSPopUpButton class]]);

		if (label.length && !hasVisibleTitle && ![[view accessibilityLabel] length]) {
			[view setAccessibilityLabel:label];
		}
		if (help.length && ![[view accessibilityHelp] length]) {
			[view setAccessibilityHelp:help];
		}
		return;
	}

	for (NSView *subview in [view subviews]) AISettingsApplyAccessibility(subview, label, help);
}

#pragma mark -

/*!
 * @brief A plain flipped container, so nested content shares the form's y axis.
 */
@interface AISettingsFlippedView : NSView
@end

@implementation AISettingsFlippedView
- (BOOL)isFlipped
{
	return YES;
}
@end

#pragma mark -

/*!
 * @brief The rounded card: background plus the hairlines between its rows.
 */
@interface AISettingsCardView : NSView {
	NSArray		*separatorPositions;	//NSNumbers, y in this view's (flipped) space
}
- (void)setSeparatorPositions:(NSArray *)positions;
@end

@implementation AISettingsCardView

- (void)dealloc
{
	[separatorPositions release];
	[super dealloc];
}

- (BOOL)isFlipped
{
	return YES;
}

- (void)setSeparatorPositions:(NSArray *)positions
{
	if (positions != separatorPositions) {
		[separatorPositions release];
		separatorPositions = [positions retain];
		[self setNeedsDisplay:YES];
	}
}

- (void)viewDidChangeEffectiveAppearance
{
	[super viewDidChangeEffectiveAppearance];
	[self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect
{
	NSRect bounds = [self bounds];

	//A hairline, not a point line, on retina displays
	CGFloat scale = [self convertSizeToBacking:NSMakeSize(1.0, 1.0)].width;
	CGFloat thickness = (scale > 0.0 ? 1.0 / scale : 1.0);

	/* Half a point in, so the outline lands inside the card instead of straddling
	 * its edge. */
	NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, thickness / 2.0, thickness / 2.0)
														xRadius:AISettingsCardCornerRadius
														yRadius:AISettingsCardCornerRadius];

	[[NSColor controlBackgroundColor] setFill];
	[card fill];

	/* controlBackgroundColor and windowBackgroundColor are the *same* colour on
	 * current macOS (white in Aqua, 0.118 grey in Dark Aqua), so the fill above
	 * on its own leaves the card invisible against the window. A translucent
	 * system fill lifts it off the background in either appearance, and the
	 * outline keeps it readable should the two colours ever diverge again. */
	[[NSColor quaternarySystemFillColor] setFill];
	[card fill];

	[[NSColor separatorColor] setStroke];
	[card setLineWidth:thickness];
	[card stroke];

	[[NSColor separatorColor] setFill];
	for (NSNumber *position in separatorPositions) {
		//Indented to the label on the left, flush to the card edge on the right
		NSRect line = NSMakeRect(AISettingsCardInsetH,
								 floor([position doubleValue]),
								 NSWidth(bounds) - AISettingsCardInsetH,
								 thickness);
		/* separatorColor is only ~10% opaque: NSRectFill() would composite with
		 * Copy and punch a transparent slit through the card instead of drawing
		 * a hairline on top of it. */
		if (NSIntersectsRect(line, rect)) NSRectFillUsingOperation(line, NSCompositingOperationSourceOver);
	}
}

@end

#pragma mark -

/*!
 * @brief One row of a card, holding its views and its computed height.
 */
@interface AISettingsFormRow : NSObject {
@public
	AISettingsRowType	 type;
	NSTextField			*labelField;
	NSTextField			*detailField;
	NSView				*control;
	NSArray				*radioButtons;
	NSView				*radioContainer;
	NSView				*fullWidthView;
	BOOL				 stretchesFullWidthView;
	NSSize				 naturalControlSize;	//Before layout ever narrowed the frame
	NSControl			*enabledSource;			//Not retained; lives inside control/radioContainer
}
- (void)trackEnabledStateOf:(NSControl *)source;
- (void)updateLabelColor;
@end

@implementation AISettingsFormRow

/*!
 * @brief Dim this row's label along with its control.
 *
 * In the nib the label was the checkbox's own title, so AppKit greyed it out
 * together with the control. Our labels are separate fields, so we follow the
 * control's enabled state by hand.
 */
- (void)trackEnabledStateOf:(NSControl *)source
{
	if (source == enabledSource) return;

	[enabledSource removeObserver:self forKeyPath:@"enabled"];
	enabledSource = source;
	[enabledSource addObserver:self forKeyPath:@"enabled" options:0 context:NULL];

	[self updateLabelColor];
}

- (void)updateLabelColor
{
	BOOL enabled = (enabledSource ? [enabledSource isEnabled] : YES);

	[labelField setTextColor:(enabled ? [NSColor labelColor] : [NSColor disabledControlTextColor])];
	[detailField setTextColor:(enabled ? [NSColor secondaryLabelColor] : [NSColor disabledControlTextColor])];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == enabledSource && [keyPath isEqualToString:@"enabled"]) {
		[self updateLabelColor];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)dealloc
{
	[enabledSource removeObserver:self forKeyPath:@"enabled"];
	enabledSource = nil;

	[labelField release];
	[detailField release];
	[control release];
	[radioButtons release];
	[radioContainer release];
	[fullWidthView release];
	[super dealloc];
}
@end

#pragma mark -

/*!
 * @brief A section: an optional header plus the card holding its rows.
 */
@interface AISettingsFormSection : NSObject {
@public
	NSTextField			*headerField;	//nil for a header-less card
	AISettingsCardView	*cardView;
	NSMutableArray		*rows;
}
@end

@implementation AISettingsFormSection
- (id)init
{
	if ((self = [super init])) {
		rows = [[NSMutableArray alloc] init];
		cardView = [[AISettingsCardView alloc] initWithFrame:NSZeroRect];
	}
	return self;
}
- (void)dealloc
{
	[headerField release];
	[cardView release];
	[rows release];
	[super dealloc];
}
@end

#pragma mark -

@interface AISettingsFormView ()
- (AISettingsFormSection *)currentSection;
- (void)appendRow:(AISettingsFormRow *)row;
- (CGFloat)layoutRow:(AISettingsFormRow *)row atY:(CGFloat)rowY inCardOfWidth:(CGFloat)cardWidth;
- (void)updateEnclosingDocumentViewHeight;
@end

@implementation AISettingsFormView

- (instancetype)initWithWidth:(CGFloat)width
{
	return [self initWithFrame:NSMakeRect(0.0, 0.0, width, 0.0)];
}

- (id)initWithFrame:(NSRect)frame
{
	/* A form with no width can never lay itself out and would report height 0
	 * forever, so fall back to a usable width until a host gives us a real one.
	 */
	if (NSWidth(frame) < 1.0) frame.size.width = AISettingsFallbackWidth;

	if ((self = [super initWithFrame:frame])) {
		sections = [[NSMutableArray alloc] init];
		contentHeight = 0.0;
		needsFormLayout = YES;
	}
	return self;
}

- (void)dealloc
{
	[sections release];
	[super dealloc];
}

- (BOOL)isFlipped
{
	return YES;
}

#pragma mark Building

- (AISettingsFormSection *)currentSection
{
	AISettingsFormSection *section = [sections lastObject];

	if (!section) {
		section = [[[AISettingsFormSection alloc] init] autorelease];
		[sections addObject:section];
		[self addSubview:section->cardView];
	}

	return section;
}

- (void)addSectionHeader:(NSString *)title
{
	//A card that never received a row would just add a gap
	AISettingsFormSection *previous = [sections lastObject];
	if (previous && ![previous->rows count] && !previous->headerField) {
		[previous->cardView removeFromSuperview];
		[sections removeLastObject];
	}

	AISettingsFormSection *section = [[[AISettingsFormSection alloc] init] autorelease];

	if (title.length) {
		section->headerField = AISettingsMakeLabel(title,
												   [NSFont systemFontOfSize:AISettingsHeaderFontSize weight:NSFontWeightBold],
												   [NSColor labelColor]);
		[self addSubview:section->headerField];
	}

	[sections addObject:section];
	[self addSubview:section->cardView];

	[self layoutForWidth:NSWidth([self frame])];
}

- (void)endCard
{
	//An empty trailing section would just add a gap; a new row creates a fresh one.
	AISettingsFormSection *section = [sections lastObject];
	if (section && ![section->rows count] && !section->headerField) {
		[section->cardView removeFromSuperview];
		[sections removeLastObject];
	} else if (section) {
		AISettingsFormSection *next = [[[AISettingsFormSection alloc] init] autorelease];
		[sections addObject:next];
		[self addSubview:next->cardView];
	}
}

- (void)appendRow:(AISettingsFormRow *)row
{
	AISettingsFormSection *section = [self currentSection];

	[section->rows addObject:row];

	if (row->labelField) [section->cardView addSubview:row->labelField];
	if (row->detailField) [section->cardView addSubview:row->detailField];
	if (row->control) [section->cardView addSubview:row->control];
	/* Radio buttons live in their own container: AppKit makes one exclusive
	 * group out of every radio button sharing a superview and an action, so two
	 * groups in the same card would silently clear each other. */
	if (row->radioContainer) [section->cardView addSubview:row->radioContainer];
	if (row->fullWidthView) [section->cardView addSubview:row->fullWidthView];

	//Read the natural sizes now; layout narrows the frames it would read back
	row->naturalControlSize = AISettingsControlSize(row->control ?: row->fullWidthView);

	[row trackEnabledStateOf:AISettingsPrimaryControl(row->control ?: row->radioContainer)];

	[self layoutForWidth:NSWidth([self frame])];
}

- (void)addRowWithLabel:(NSString *)label control:(NSView *)control
{
	[self addRowWithLabel:label control:control detail:nil];
}

- (void)addRowWithLabel:(NSString *)label control:(NSView *)control detail:(NSString *)detail
{
	AISettingsFormRow *row = [[[AISettingsFormRow alloc] init] autorelease];

	row->type = AISettingsRowTypeControl;
	if (label.length) {
		row->labelField = AISettingsMakeLabel(label,
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor labelColor]);
	}
	if (detail.length) {
		row->detailField = AISettingsMakeLabel(detail,
											   [NSFont systemFontOfSize:AISettingsDetailFontSize],
											   [NSColor secondaryLabelColor]);
	}
	row->control = [control retain];

	AISettingsApplyAccessibility(control, label, detail);

	[self appendRow:row];
}

- (void)addRadioGroupWithLabel:(NSString *)label buttons:(NSArray *)radioButtons
{
	AISettingsFormRow *row = [[[AISettingsFormRow alloc] init] autorelease];

	row->type = AISettingsRowTypeRadioGroup;
	if (label.length) {
		row->labelField = AISettingsMakeLabel(label,
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor labelColor]);
	}
	row->radioButtons = [radioButtons copy];
	row->radioContainer = [[AISettingsFlippedView alloc] initWithFrame:NSZeroRect];
	if (label.length) [row->radioContainer setAccessibilityLabel:label];

	for (NSButton *button in row->radioButtons) {
		if (NSWidth([button frame]) < 1.0 || NSHeight([button frame]) < 1.0) [button sizeToFit];
		[row->radioContainer addSubview:button];
	}

	[self appendRow:row];
}

- (void)addFullWidthRow:(NSView *)view
{
	[self addFullWidthRow:view stretch:YES];
}

- (void)addFullWidthRow:(NSView *)view stretch:(BOOL)stretch
{
	AISettingsFormRow *row = [[[AISettingsFormRow alloc] init] autorelease];

	row->type = AISettingsRowTypeFullWidth;
	row->fullWidthView = [view retain];
	row->stretchesFullWidthView = stretch;

	[self appendRow:row];
}

- (void)removeAllSections
{
	for (AISettingsFormSection *section in sections) {
		[section->headerField removeFromSuperview];
		[section->cardView removeFromSuperview];
	}
	[sections removeAllObjects];

	[self layoutForWidth:NSWidth([self frame])];
}

#pragma mark Layout

- (CGFloat)totalHeight
{
	if (needsFormLayout) [self layoutForWidth:NSWidth([self frame])];
	return contentHeight;
}

- (void)layoutForWidth:(CGFloat)width
{
	if (width < 1.0) {
		//Nothing sensible to compute yet; try again once we have a width.
		needsFormLayout = YES;
		return;
	}

	needsFormLayout = NO;

	CGFloat cardWidth = MAX(width - 2.0 * AISettingsOuterMargin, 2.0 * AISettingsCardInsetH + 40.0);
	CGFloat y = 0.0;
	BOOL isFirstSection = YES;

	for (AISettingsFormSection *section in sections) {
		if (![section->rows count] && !section->headerField) continue;

		if (!isFirstSection) y += (section->headerField ? AISettingsSectionGap : AISettingsCardGap);
		isFirstSection = NO;

		if (section->headerField) {
			CGFloat headerHeight = AISettingsFieldHeight(section->headerField, cardWidth);
			[section->headerField setFrame:NSMakeRect(AISettingsOuterMargin, y, cardWidth, headerHeight)];
			y += headerHeight + AISettingsHeaderGap;
		}

		//Rows are laid out in the card's own (flipped) coordinates
		NSMutableArray *separators = [NSMutableArray array];
		CGFloat rowY = 0.0;

		for (AISettingsFormRow *row in section->rows) {
			if (rowY > 0.0) [separators addObject:[NSNumber numberWithDouble:rowY]];
			rowY += [self layoutRow:row atY:rowY inCardOfWidth:cardWidth];
		}

		[section->cardView setFrame:NSMakeRect(AISettingsOuterMargin, y, cardWidth, rowY)];
		[section->cardView setSeparatorPositions:separators];
		[section->cardView setNeedsDisplay:YES];

		y += rowY;
	}

	contentHeight = ceil(y);

	if (fabs(NSWidth([self frame]) - width) > 0.5 || fabs(NSHeight([self frame]) - contentHeight) > 0.5) {
		//Bypasses our own -setFrameSize: so this cannot recurse
		[super setFrameSize:NSMakeSize(width, contentHeight)];
	}

	[self updateEnclosingDocumentViewHeight];
	[self setNeedsDisplay:YES];
}

/*!
 * @brief Place one row's views and return the height it occupies.
 */
- (CGFloat)layoutRow:(AISettingsFormRow *)row atY:(CGFloat)rowY inCardOfWidth:(CGFloat)cardWidth
{
	CGFloat innerWidth = cardWidth - 2.0 * AISettingsCardInsetH;

	/* Layout only ever narrows a control, so a frame wider than the size we
	 * remembered can only come from the caller (a -sizeToFit after filling a
	 * pop up menu, say): adopt it as the new natural size. Reading the frame
	 * back unconditionally would ratchet every control down to the narrowest
	 * width it was ever laid out at.
	 */
	NSView *sizedView = (row->control ?: row->fullWidthView);
	if (sizedView) {
		NSSize current = [sizedView frame].size;
		if (current.width > row->naturalControlSize.width + 0.5) row->naturalControlSize.width = current.width;
		if (fabs(current.height - row->naturalControlSize.height) > 0.5) row->naturalControlSize.height = current.height;
	}

	switch (row->type) {
		case AISettingsRowTypeFullWidth: {
			NSSize size = row->naturalControlSize;
			CGFloat width = (row->stretchesFullWidthView ? innerWidth : MIN(size.width, innerWidth));

			[row->fullWidthView setFrame:NSMakeRect(AISettingsCardInsetH,
													rowY + AISettingsRowInsetV,
													MAX(width, 1.0),
													size.height)];
			return MAX(size.height + 2.0 * AISettingsRowInsetV, AISettingsRowMinHeight);
		}

		case AISettingsRowTypeRadioGroup: {
			CGFloat offset = AISettingsRowInsetV + 2.0;
			CGFloat buttonY = 0.0;

			if (row->labelField) {
				CGFloat labelHeight = AISettingsFieldHeight(row->labelField, innerWidth);
				[row->labelField setFrame:NSMakeRect(AISettingsCardInsetH, rowY + offset, innerWidth, labelHeight)];
				offset += labelHeight + AISettingsRadioTopGap;
			}

			//Positions are relative to the group's own (flipped) container
			for (NSButton *button in row->radioButtons) {
				NSSize size = AISettingsControlSize(button);
				[button setFrame:NSMakeRect(0.0, buttonY, MIN(size.width, innerWidth), size.height)];
				buttonY += size.height + AISettingsRadioSpacing;
			}
			if ([row->radioButtons count]) buttonY -= AISettingsRadioSpacing;

			[row->radioContainer setFrame:NSMakeRect(AISettingsCardInsetH, rowY + offset, innerWidth, MAX(buttonY, 0.0))];
			offset += MAX(buttonY, 0.0);

			return MAX(offset + AISettingsRowInsetV + 2.0, AISettingsRowMinHeight);
		}

		case AISettingsRowTypeControl:
		default: {
			NSSize controlSize = row->naturalControlSize;
			CGFloat maxControlWidth = MAX(MIN(innerWidth - AISettingsMinLabelWidth - AISettingsLabelControlGap,
											  innerWidth - 1.0),
										  MIN(60.0, innerWidth - 1.0));
			CGFloat controlWidth = MIN(controlSize.width, maxControlWidth);
			CGFloat labelWidth = MAX(innerWidth - (row->control ? controlWidth + AISettingsLabelControlGap : 0.0), 1.0);

			CGFloat labelHeight = (row->labelField ? AISettingsFieldHeight(row->labelField, labelWidth) : 0.0);
			CGFloat detailHeight = (row->detailField ? AISettingsFieldHeight(row->detailField, labelWidth) : 0.0);
			CGFloat textHeight = labelHeight + (detailHeight > 0.0 ? AISettingsDetailGap + detailHeight : 0.0);

			CGFloat rowHeight = MAX(AISettingsRowMinHeight,
									MAX(textHeight, controlSize.height) + 2.0 * AISettingsRowInsetV);

			CGFloat textY = rowY + floor((rowHeight - textHeight) / 2.0);
			if (row->labelField) {
				[row->labelField setFrame:NSMakeRect(AISettingsCardInsetH, textY, labelWidth, labelHeight)];
			}
			if (row->detailField) {
				[row->detailField setFrame:NSMakeRect(AISettingsCardInsetH,
													  textY + labelHeight + AISettingsDetailGap,
													  labelWidth,
													  detailHeight)];
			}
			if (row->control) {
				[row->control setFrame:NSMakeRect(cardWidth - AISettingsCardInsetH - controlWidth,
												  rowY + floor((rowHeight - controlSize.height) / 2.0),
												  controlWidth,
												  controlSize.height)];
			}

			return rowHeight;
		}
	}
}

/*!
 * @brief Keep a hosting scrolling column as tall as the form.
 *
 * The preferences window sizes its document view from the pane's height before
 * handing us a new width, so growing or shrinking on a resize would otherwise
 * only take effect one resize later. Only applies when we are the direct
 * subview of a flipped document view; a no-op anywhere else.
 */
- (void)updateEnclosingDocumentViewHeight
{
	NSScrollView *scrollView = [self enclosingScrollView];
	NSView *documentView = [scrollView documentView];

	if (!scrollView || !documentView || documentView != [self superview] || ![documentView isFlipped]) return;

	CGFloat padding = MAX(NSMinY([self frame]), 0.0);
	CGFloat needed = MAX(NSHeight([self frame]) + 2.0 * padding, [scrollView contentSize].height);

	if (fabs(needed - NSHeight([documentView frame])) > 0.5) {
		[documentView setFrameSize:NSMakeSize(NSWidth([documentView frame]), needed)];
	}
}

- (void)setFrameSize:(NSSize)newSize
{
	BOOL widthChanged = (fabs(newSize.width - NSWidth([self frame])) > 0.5);

	[super setFrameSize:newSize];

	if (widthChanged || needsFormLayout) [self layoutForWidth:newSize.width];
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	if (needsFormLayout) [self layoutForWidth:NSWidth([self frame])];
}

#pragma mark Control factories

+ (NSSwitch *)switchWithTarget:(id)target action:(SEL)action
{
	NSSwitch *control = [[[NSSwitch alloc] initWithFrame:NSZeroRect] autorelease];

	[control setTarget:target];
	[control setAction:action];
	[control setFrameSize:[control fittingSize]];

	return control;
}

+ (NSPopUpButton *)popUpButtonWithTitles:(NSArray *)titles target:(id)target action:(SEL)action
{
	NSPopUpButton *popUp = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];

	for (NSString *title in titles) [popUp addItemWithTitle:title];
	[popUp setTarget:target];
	[popUp setAction:action];
	[popUp sizeToFit];

	return popUp;
}

+ (NSButton *)radioButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action
{
	NSButton *button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];

	[button setButtonType:NSButtonTypeRadio];
	[button setTitle:(title ?: @"")];
	[button setFont:[NSFont systemFontOfSize:AISettingsLabelFontSize]];
	[button setTarget:target];
	[button setAction:action];
	[button sizeToFit];

	return button;
}

+ (NSButton *)pushButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action
{
	NSButton *button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];

	[button setBezelStyle:NSBezelStyleRounded];
	[button setButtonType:NSButtonTypeMomentaryPushIn];
	[button setTitle:(title ?: @"")];
	[button setFont:[NSFont systemFontOfSize:AISettingsLabelFontSize]];
	[button setTarget:target];
	[button setAction:action];
	[button sizeToFit];

	return button;
}

+ (NSTextField *)valueFieldWithWidth:(CGFloat)width target:(id)target action:(SEL)action
{
	NSTextField *field = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];

	[field setFont:[NSFont systemFontOfSize:AISettingsLabelFontSize]];
	[field setAlignment:NSTextAlignmentRight];
	[field setTarget:target];
	[field setAction:action];
	[field sizeToFit];
	[field setFrameSize:NSMakeSize(width, NSHeight([field frame]))];

	return field;
}

+ (NSView *)rowOfViews:(NSArray *)views spacing:(CGFloat)spacing
{
	CGFloat width = 0.0, height = 0.0;

	for (NSView *view in views) {
		NSSize size = AISettingsControlSize(view);
		[view setFrameSize:size];
		width += size.width;
		height = MAX(height, size.height);
	}
	if ([views count] > 1) width += spacing * ([views count] - 1);

	NSView *container = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, height)] autorelease];
	CGFloat x = 0.0;

	for (NSView *view in views) {
		NSSize size = [view frame].size;
		[view setFrameOrigin:NSMakePoint(x, floor((height - size.height) / 2.0))];
		[container addSubview:view];
		x += size.width + spacing;
	}

	return container;
}

@end
