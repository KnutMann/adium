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
static const CGFloat AISettingsAccessoryGap		= 8.0;	//Between a card and the button bar below it
static const CGFloat AISettingsControlGap		= 8.0;	//Between two adjacent controls of one bar
static const CGFloat AISettingsRadioTopGap		= 8.0;	//Between a radio group label and its buttons
static const CGFloat AISettingsRadioSpacing		= 6.0;
static const CGFloat AISettingsSliderMinWidth	= 120.0;	//A slider is never squeezed below this
/* Height a slider is given. AppKit reports 16 points for a linear slider while
 * its knob measures 20, i.e. the knob is drawn outside the frame; a view which
 * clips its bounds would cut it in half. 21 is the height a slider has in a nib. */
static const CGFloat AISettingsSliderHeight		= 21.0;
static const CGFloat AISettingsSliderLabelMax	= 0.45;		//Share of a slider row its label may claim
static const CGFloat AISettingsValueLabelSlack	= 2.0;		//Keeps a readout from clipping its own text
static const CGFloat AISettingsLabelFontSize	= 13.0;
static const CGFloat AISettingsDetailFontSize	= 11.0;
static const CGFloat AISettingsHeaderFontSize	= 13.0;
static const CGFloat AISettingsFallbackWidth	= 480.0;	//Used when a host gives us no usable width

/* Our own KVO context: a row must be able to tell its own notification from one
 * meant for a superclass. AISettingsFormRow inherits from NSObject, whose
 * -observeValueForKeyPath:… raises, so forwarding a foreign notification would
 * end the process. */
static void *AISettingsRowEnabledContext = &AISettingsRowEnabledContext;

typedef enum {
	AISettingsRowTypeControl = 0,
	AISettingsRowTypePopUp,
	AISettingsRowTypeSlider,
	AISettingsRowTypeRadioGroup,
	AISettingsRowTypeFullWidth,
	AISettingsRowTypeEdgeToEdge
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
 * @brief Take a view over for frame based layout.
 *
 * The form positions everything by frame. A view whose
 * translatesAutoresizingMaskIntoConstraints is NO — anything coming out of a
 * XIB which was saved without Auto Layout, for instance — is owned by the
 * layout engine instead, which would resolve it as ambiguous and collapse it
 * the moment the constraint engine touches that part of the hierarchy. Say
 * explicitly that its frame is the truth.
 */
static void AISettingsAdoptView(NSView *view)
{
	if (view && ![view translatesAutoresizingMaskIntoConstraints]) {
		[view setTranslatesAutoresizingMaskIntoConstraints:YES];
	}
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

	/* The full bounds: with no outline to keep inside the card, insetting the fill
	 * would only leave a hairline of window background around every card — a
	 * visible ring at 1x, where half a point rounds up to a whole one. */
	NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:bounds
														xRadius:AISettingsCardCornerRadius
														yRadius:AISettingsCardCornerRadius];

	[[NSColor controlBackgroundColor] setFill];
	[card fill];

	/* controlBackgroundColor and windowBackgroundColor are the *same* colour on
	 * current macOS (white in Aqua, 0.118 grey in Dark Aqua), so the fill above
	 * on its own leaves the card invisible against the window. A translucent
	 * system fill lifts it off the background in either appearance. There is no
	 * outline: System Settings cards are a plain fill, the dividers inside are
	 * the only lines. */
	[[NSColor quaternarySystemFillColor] setFill];
	[card fill];

	[[NSColor separatorColor] setFill];
	for (NSNumber *position in separatorPositions) {
		//Indented on both sides, the way System Settings insets its dividers
		NSRect line = NSMakeRect(AISettingsCardInsetH,
								 floor([position doubleValue]),
								 NSWidth(bounds) - 2.0 * AISettingsCardInsetH,
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
	NSTextField			*valueField;			//Trailing readout of a slider row
	NSView				*accessoryControl;		//Trailing button of a pop up row
	NSView				*control;
	NSArray				*radioButtons;
	NSView				*radioContainer;
	NSView				*fullWidthView;
	BOOL				 stretchesFullWidthView;
	NSSize				 naturalControlSize;	//Before layout ever narrowed the frame
	NSControl			*enabledSource;			//Not retained; lives inside control/radioContainer
	/* Slider rows only: the label and readout columns shared by every slider row
	 * of the same card, so their sliders start and end on one line. Filled by
	 * -layoutForWidth: before the rows are placed. */
	CGFloat				 sliderLabelColumn;
	CGFloat				 sliderValueColumn;
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

	[enabledSource removeObserver:self forKeyPath:@"enabled" context:AISettingsRowEnabledContext];
	enabledSource = source;
	[enabledSource addObserver:self forKeyPath:@"enabled" options:0 context:AISettingsRowEnabledContext];

	[self updateLabelColor];
}

- (void)updateLabelColor
{
	BOOL enabled = (enabledSource ? [enabledSource isEnabled] : YES);

	[labelField setTextColor:(enabled ? [NSColor labelColor] : [NSColor disabledControlTextColor])];
	[detailField setTextColor:(enabled ? [NSColor secondaryLabelColor] : [NSColor disabledControlTextColor])];
	[valueField setTextColor:(enabled ? [NSColor secondaryLabelColor] : [NSColor disabledControlTextColor])];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == AISettingsRowEnabledContext) {
		/* Ours even when it arrives after the source was swapped out: a
		 * notification already in flight names the old object. */
		[self updateLabelColor];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)dealloc
{
	[enabledSource removeObserver:self forKeyPath:@"enabled" context:AISettingsRowEnabledContext];
	enabledSource = nil;

	[labelField release];
	[detailField release];
	[valueField release];
	[accessoryControl release];
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
	NSView				*accessoryView;	//Sits below the card, outside of it; nil for most sections
	BOOL				 accessoryTrailing;	//NO: aligned with the card's leading edge, the default
	/* Widest slider label this card has ever held, uncapped. Never shrinks, so a
	 * row renamed to something shorter leaves the column — and with it every
	 * slider of the card — exactly where it was. */
	CGFloat				 sliderLabelNatural;
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
	[accessoryView release];
	[super dealloc];
}
@end

#pragma mark -

@interface AISettingsFormView ()
- (void)addAccessoryView:(NSView *)view trailing:(BOOL)trailing;
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
	if (previous && ![previous->rows count] && !previous->headerField && !previous->accessoryView) {
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
	if (section && ![section->rows count] && !section->headerField && !section->accessoryView) {
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
	if (row->valueField) [section->cardView addSubview:row->valueField];
	if (row->accessoryControl) [section->cardView addSubview:row->accessoryControl];
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

- (void)addRowWithLabel:(NSString *)label popUpButton:(NSPopUpButton *)popUpButton accessoryButton:(NSButton *)button
{
	AISettingsFormRow *row = [[[AISettingsFormRow alloc] init] autorelease];

	row->type = AISettingsRowTypePopUp;
	if (label.length) {
		row->labelField = AISettingsMakeLabel(label,
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor labelColor]);
	}
	row->control = [popUpButton retain];
	row->accessoryControl = [button retain];

	AISettingsApplyAccessibility(popUpButton, label, nil);
	/* The accessory keeps its own title as its accessibility label — it shows one
	 * — but three buttons reading "Customize…" in a row say nothing about what
	 * they customize, so the row's label becomes their help text. */
	AISettingsApplyAccessibility(button, nil, label);

	[self appendRow:row];
}

- (void)addRowWithLabel:(NSString *)label slider:(NSSlider *)slider valueLabel:(NSTextField *)valueLabel
{
	AISettingsFormRow *row = [[[AISettingsFormRow alloc] init] autorelease];

	row->type = AISettingsRowTypeSlider;
	if (label.length) {
		row->labelField = AISettingsMakeLabel(label,
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor labelColor]);
	}
	row->control = [slider retain];
	row->valueField = [valueLabel retain];

	AISettingsApplyAccessibility(slider, label, nil);
	/* The readout only repeats the slider's own value, which VoiceOver already
	 * announces; leaving it in the tree makes every slider read out twice. */
	[valueLabel setAccessibilityElement:NO];

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

	AISettingsAdoptView(view);

	row->type = AISettingsRowTypeFullWidth;
	row->fullWidthView = [view retain];
	row->stretchesFullWidthView = stretch;

	[self appendRow:row];
}

- (void)addEdgeToEdgeRow:(NSView *)view
{
	AISettingsFormRow *row = [[[AISettingsFormRow alloc] init] autorelease];

	AISettingsAdoptView(view);

	/* The view <em>is</em> the card, so it has to be clipped to the card's
	 * rounded corners - a selected first or last row of a hosted list would
	 * otherwise paint over them. Doing it here keeps the radius in one place:
	 * no host ever repeats it. */
	[view setWantsLayer:YES];
	[[view layer] setCornerRadius:AISettingsCardCornerRadius];
	[[view layer] setMasksToBounds:YES];

	row->type = AISettingsRowTypeEdgeToEdge;
	row->fullWidthView = [view retain];
	row->stretchesFullWidthView = YES;

	[self appendRow:row];
}

- (void)addAccessoryView:(NSView *)view
{
	[self addAccessoryView:view trailing:NO];
}

- (void)addTrailingAccessoryView:(NSView *)view
{
	[self addAccessoryView:view trailing:YES];
}

- (void)addAccessoryView:(NSView *)view trailing:(BOOL)trailing
{
	AISettingsFormSection *section = [self currentSection];

	AISettingsAdoptView(view);

	if (section->accessoryView != view) {
		[section->accessoryView removeFromSuperview];
		[section->accessoryView release];
		section->accessoryView = [view retain];
		//Below the card, so a subview of the form itself rather than of the card
		if (view) [self addSubview:view];
	}

	section->accessoryTrailing = trailing;

	[self layoutForWidth:NSWidth([self frame])];
}

- (void)setLabel:(NSString *)label forRowWithControl:(NSView *)control
{
	if (!control) return;

	for (AISettingsFormSection *section in sections) {
		for (AISettingsFormRow *row in section->rows) {
			NSView *rowView = (row->control ?: row->fullWidthView);

			if (!rowView || !(rowView == control || [control isDescendantOf:rowView])) continue;

			//A row added without a label has no field to put one in
			if (!row->labelField) return;

			/* Callers retitle a row from a preference observer, which fires for
			 * every key of its group: the text is usually the one already there,
			 * and a needless layout would re-measure every pop up menu of the
			 * form and resize the pane inside its window. */
			if ([[row->labelField stringValue] isEqualToString:(label ?: @"")]) return;

			[row->labelField setStringValue:(label ?: @"")];
			if (label.length) [AISettingsPrimaryControl(rowView) setAccessibilityLabel:label];

			//The new text may need more or fewer points than the old one
			[self layoutForWidth:NSWidth([self frame])];
			return;
		}
	}
}

- (void)removeAllSections
{
	for (AISettingsFormSection *section in sections) {
		[section->headerField removeFromSuperview];
		[section->cardView removeFromSuperview];
		[section->accessoryView removeFromSuperview];
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

- (void)noteContentSizeChanged
{
	/* -layoutRow:atY:inCardOfWidth: adopts a height a hosted view changed on its
	 * own, so laying out again is all it takes. */
	[self layoutForWidth:NSWidth([self frame])];
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
		if (![section->rows count] && !section->headerField && !section->accessoryView) continue;

		if (!isFirstSection) y += (section->headerField ? AISettingsSectionGap : AISettingsCardGap);
		isFirstSection = NO;

		if (section->headerField) {
			CGFloat headerHeight = AISettingsFieldHeight(section->headerField, cardWidth);
			[section->headerField setFrame:NSMakeRect(AISettingsOuterMargin, y, cardWidth, headerHeight)];
			y += headerHeight + AISettingsHeaderGap;
		}

		/* Slider rows of one card share a label and a readout column, the way
		 * System Settings lines its sliders up: otherwise "Opacity" and "Maximum
		 * Width" would start their sliders at two different x, and retitling one
		 * of them would shift its slider while the user works two rows above. */
		CGFloat sliderInnerWidth = cardWidth - 2.0 * AISettingsCardInsetH;
		CGFloat sliderLabelColumn = 0.0;
		CGFloat sliderValueColumn = 0.0;

		for (AISettingsFormRow *row in section->rows) {
			if (row->type != AISettingsRowTypeSlider) continue;

			if (row->labelField) {
				sliderLabelColumn = MAX(sliderLabelColumn, ceil([[row->labelField cell] cellSize].width));
			}
			if (row->valueField) {
				sliderValueColumn = MAX(sliderValueColumn, AISettingsControlSize(row->valueField).width);
			}
		}
		//Only the cap follows the card's width; the text width itself never shrinks again
		section->sliderLabelNatural = MAX(section->sliderLabelNatural, sliderLabelColumn);
		sliderLabelColumn = MIN(section->sliderLabelNatural, floor(sliderInnerWidth * AISettingsSliderLabelMax));

		for (AISettingsFormRow *row in section->rows) {
			row->sliderLabelColumn = sliderLabelColumn;
			row->sliderValueColumn = sliderValueColumn;
		}

		//Rows are laid out in the card's own (flipped) coordinates
		NSMutableArray *separators = [NSMutableArray array];
		CGFloat rowY = 0.0;
		BOOL previousWasEdgeToEdge = NO;

		for (AISettingsFormRow *row in section->rows) {
			BOOL edgeToEdge = (row->type == AISettingsRowTypeEdgeToEdge);

			/* An edge to edge row fills the card and brings its own separators,
			 * so the card must not draw one against it. */
			if (rowY > 0.0 && !edgeToEdge && !previousWasEdgeToEdge) {
				[separators addObject:[NSNumber numberWithDouble:rowY]];
			}
			rowY += [self layoutRow:row atY:rowY inCardOfWidth:cardWidth];
			previousWasEdgeToEdge = edgeToEdge;
		}

		[section->cardView setFrame:NSMakeRect(AISettingsOuterMargin, y, cardWidth, rowY)];
		[section->cardView setSeparatorPositions:separators];
		[section->cardView setNeedsDisplay:YES];

		y += rowY;

		if (section->accessoryView) {
			/* Aligned with one edge of the card and never resized: it keeps the size
			 * its builder gave it, so reading the frame back cannot ratchet it down. */
			NSSize	size = AISettingsControlSize(section->accessoryView);
			CGFloat	accessoryX = (section->accessoryTrailing ?
								  AISettingsOuterMargin + MAX(cardWidth - size.width, 0.0) :
								  AISettingsOuterMargin);

			y += AISettingsAccessoryGap;
			[section->accessoryView setFrame:NSMakeRect(accessoryX, y, size.width, size.height)];
			y += size.height;
		}
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
		case AISettingsRowTypeEdgeToEdge: {
			/* The view is the card: full width, no inset, and its height is the
			 * row height, so a hosted list decides how tall the card is. */
			CGFloat height = MAX(row->naturalControlSize.height, 1.0);

			[row->fullWidthView setFrame:NSMakeRect(0.0, rowY, cardWidth, height)];

			return height;
		}

		case AISettingsRowTypeFullWidth: {
			NSSize size = row->naturalControlSize;
			CGFloat width = (row->stretchesFullWidthView ? innerWidth : MIN(size.width, innerWidth));

			[row->fullWidthView setFrame:NSMakeRect(AISettingsCardInsetH,
													rowY + AISettingsRowInsetV,
													MAX(width, 1.0),
													size.height)];
			return MAX(size.height + 2.0 * AISettingsRowInsetV, AISettingsRowMinHeight);
		}

		case AISettingsRowTypePopUp: {
			/* The menu decides how wide the button wants to be, and it may have
			 * been rebuilt since the row was added, so ask again every time. */
			[(NSControl *)row->control sizeToFit];

			NSSize	popUpSize = AISettingsControlSize(row->control);
			NSSize	accessorySize = (row->accessoryControl ? AISettingsControlSize(row->accessoryControl) : NSZeroSize);
			CGFloat	trailing = (accessorySize.width > 0.0 ? accessorySize.width + AISettingsControlGap : 0.0);
			CGFloat	maxControlWidth = MAX(MIN(innerWidth - AISettingsMinLabelWidth - AISettingsLabelControlGap,
											  innerWidth - 1.0),
										  MIN(60.0, innerWidth - 1.0));
			CGFloat	popUpWidth = MIN(popUpSize.width, MAX(maxControlWidth - trailing, 40.0));
			CGFloat	controlWidth = popUpWidth + trailing;

			/* The 40 point floor above is a minimum for the menu, not a licence to
			 * overrun the card: in a card narrow enough that the accessory button
			 * alone fills it, the menu — not the button — gives way. */
			if (controlWidth > innerWidth) {
				popUpWidth = MAX(innerWidth - trailing, 20.0);
				controlWidth = popUpWidth + trailing;
			}
			CGFloat	labelWidth = MAX(innerWidth - controlWidth - AISettingsLabelControlGap, 1.0);

			CGFloat	labelHeight = (row->labelField ? AISettingsFieldHeight(row->labelField, labelWidth) : 0.0);
			CGFloat	rowHeight = MAX(AISettingsRowMinHeight,
									MAX(MAX(labelHeight, popUpSize.height), accessorySize.height) + 2.0 * AISettingsRowInsetV);

			if (row->labelField) {
				[row->labelField setFrame:NSMakeRect(AISettingsCardInsetH,
													 rowY + floor((rowHeight - labelHeight) / 2.0),
													 labelWidth,
													 labelHeight)];
			}
			if (row->accessoryControl) {
				[row->accessoryControl setFrame:NSMakeRect(cardWidth - AISettingsCardInsetH - accessorySize.width,
														   rowY + floor((rowHeight - accessorySize.height) / 2.0),
														   accessorySize.width,
														   accessorySize.height)];
			}
			[row->control setFrame:NSMakeRect(cardWidth - AISettingsCardInsetH - controlWidth,
											  rowY + floor((rowHeight - popUpSize.height) / 2.0),
											  popUpWidth,
											  popUpSize.height)];

			return rowHeight;
		}

		case AISettingsRowTypeSlider: {
			/* Label, slider and readout share one line: the label and the readout
			 * keep the width of their text, the slider takes what is left. */
			NSSize	valueSize = (row->valueField ? AISettingsControlSize(row->valueField) : NSZeroSize);
			CGFloat	sliderHeight = MAX(row->naturalControlSize.height, 1.0);
			//Both columns are shared by every slider row of this card
			CGFloat	valueWidth = MAX(row->sliderValueColumn, valueSize.width);
			CGFloat	trailing = (valueWidth > 0.0 ? valueWidth + AISettingsLabelControlGap : 0.0);
			CGFloat	labelWidth = (row->labelField ? row->sliderLabelColumn : 0.0);

			CGFloat leading = (labelWidth > 0.0 ? labelWidth + AISettingsLabelControlGap : 0.0);
			CGFloat sliderWidth = innerWidth - leading - trailing;

			if (sliderWidth < AISettingsSliderMinWidth) {
				//A narrow card shortens the label rather than the slider
				labelWidth = MAX(labelWidth - (AISettingsSliderMinWidth - sliderWidth), 0.0);
				leading = (labelWidth > 0.0 ? labelWidth + AISettingsLabelControlGap : 0.0);
				sliderWidth = MAX(innerWidth - leading - trailing, 1.0);
			}

			/* A label pressed below the width its text needs is truncated, not
			 * wrapped: wrapping would turn a long label into a column of single
			 * syllables and blow the row up to ten lines. */
			if (row->labelField) {
				BOOL	fits = (labelWidth + 0.5 >= ceil([[row->labelField cell] cellSize].width));

				/* -setWraps: rewrites the line break mode (word wrapping when YES,
				 * clipping when NO), so the mode has to be set afterwards. */
				[[row->labelField cell] setWraps:fits];
				[row->labelField setLineBreakMode:(fits ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail)];
			}

			CGFloat labelHeight = (labelWidth > 0.0 ? AISettingsFieldHeight(row->labelField, labelWidth) : 0.0);
			CGFloat rowHeight = MAX(AISettingsRowMinHeight,
									MAX(MAX(labelHeight, sliderHeight), valueSize.height) + 2.0 * AISettingsRowInsetV);

			if (row->labelField) {
				[row->labelField setFrame:NSMakeRect(AISettingsCardInsetH,
													 rowY + floor((rowHeight - labelHeight) / 2.0),
													 MAX(labelWidth, 1.0),
													 labelHeight)];
				[row->labelField setHidden:(labelWidth < 1.0)];
			}
			[row->control setFrame:NSMakeRect(AISettingsCardInsetH + leading,
											  rowY + floor((rowHeight - sliderHeight) / 2.0),
											  sliderWidth,
											  sliderHeight)];
			if (row->valueField) {
				//Right aligned text, so a wider shared column still ends at the card's inset
				[row->valueField setFrame:NSMakeRect(cardWidth - AISettingsCardInsetH - valueWidth,
													 rowY + floor((rowHeight - valueSize.height) / 2.0),
													 valueWidth,
													 valueSize.height)];
			}

			return rowHeight;
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

	//System Settings uses the small switch, not the regular one
	[control setControlSize:NSControlSizeSmall];
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

+ (NSSlider *)sliderWithMinValue:(double)minValue maxValue:(double)maxValue target:(id)target action:(SEL)action
{
	NSSlider *slider = [[[NSSlider alloc] initWithFrame:NSMakeRect(0.0, 0.0, AISettingsSliderMinWidth, AISettingsSliderHeight)] autorelease];

	[slider setSliderType:NSSliderTypeLinear];
	[slider setMinValue:minValue];
	[slider setMaxValue:maxValue];
	[slider setTarget:target];
	[slider setAction:action];
	/* Not continuous, so the action fires when the drag ends and a preference is
	 * written once per adjustment rather than once per pixel. Note that this is
	 * *not* what Interface Builder does — a slider dropped into a nib is
	 * continuous — so a slider whose effect the user must see while dragging
	 * (and whose action is cheap, or guards its own writes) wants an explicit
	 * setContinuous:YES from its pane. */
	[slider setContinuous:NO];

	NSSize fitting = [slider fittingSize];
	[slider setFrameSize:NSMakeSize(AISettingsSliderMinWidth,
									MAX(ceil(fitting.height), AISettingsSliderHeight))];

	return slider;
}

+ (NSTextField *)valueLabelForWidestValue:(NSString *)widestValue
{
	NSTextField *field = [AISettingsMakeLabel((widestValue ?: @""),
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor secondaryLabelColor]) autorelease];

	//One line, right up against the card's trailing inset, and never re-measured
	[field setAlignment:NSTextAlignmentRight];
	[field setLineBreakMode:NSLineBreakByClipping];
	[[field cell] setWraps:NO];
	[field sizeToFit];
	[field setFrameSize:NSMakeSize(ceil(NSWidth([field frame])) + AISettingsValueLabelSlack,
								   ceil(NSHeight([field frame])))];

	return field;
}

+ (CGFloat)cardCornerRadius
{
	return AISettingsCardCornerRadius;
}

+ (CGFloat)standardControlGap
{
	return AISettingsControlGap;
}

+ (NSView *)rowOfViews:(NSArray *)views
{
	return [self rowOfViews:views spacing:AISettingsControlGap];
}

+ (NSView *)rowOfViews:(NSArray *)views spacing:(CGFloat)spacing
{
	CGFloat width = 0.0, height = 0.0;

	for (NSView *view in views) {
		NSSize size;

		AISettingsAdoptView(view);
		size = AISettingsControlSize(view);
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
