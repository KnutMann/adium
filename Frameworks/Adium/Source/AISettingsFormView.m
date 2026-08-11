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
static const CGFloat AISettingsInlineButtonSize	= 22.0;		//Edge length of a row's trailing symbol button
static const CGFloat AISettingsInlineSymbolSize	= 16.0;		//Point size of the symbol drawn in it
static const CGFloat AISettingsInfoImageSize	= 40.0;		//Longest edge of the picture in an info row

/* Our own KVO context: a row must be able to tell its own notification from one
 * meant for a superclass. AISettingsFormRow inherits from NSObject, whose
 * -observeValueForKeyPath:… raises, so forwarding a foreign notification would
 * end the process. */
static void *AISettingsRowEnabledContext = &AISettingsRowEnabledContext;

typedef enum {
	AISettingsRowTypeControl = 0,
	AISettingsRowTypePopUp,
	AISettingsRowTypeSlider,
	AISettingsRowTypeStretch,		//Label plus a control filling the row; laid out as a slider row
	AISettingsRowTypeRadioGroup,
	AISettingsRowTypeFullWidth,
	AISettingsRowTypeEdgeToEdge,
	AISettingsRowTypeDetail,		//Explanatory text, no control at all
	AISettingsRowTypeEmptyState,	//"Nothing here yet", centred in an otherwise empty card
	AISettingsRowTypeInfo			//A picture plus the paragraph it illustrates
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
 * @brief The explanatory label both detail shapes are built from.
 *
 * -addDetailRow: and -addFootnote: differ only in where they put their field,
 * not in what it looks like: same font, same colour, same wrapping as the
 * detail line under a row's label. Building both here keeps that true.
 *
 * Selectable, unlike every other label of the form: an explanation is text a
 * user may well want to copy, and System Settings lets its footnotes be
 * selected. Caller owns the returned field.
 */
static NSTextField *AISettingsMakeDetailLabel(NSString *text)
{
	NSTextField *field = AISettingsMakeLabel(text,
											 [NSFont systemFontOfSize:AISettingsDetailFontSize],
											 [NSColor secondaryLabelColor]);

	[field setSelectable:YES];

	return field;
}

/*!
 * @brief The picture of an info row, scaled into the standard square.
 *
 * Scales a <em>copy</em>, never the image it was handed: a caller may hand us a
 * picture the whole process shares — anything out of +[NSImage imageNamed:] or
 * of a cache of its own — and -setSize: on that instance would quietly shrink it
 * in every toolbar and list drawing it too. Proportional, so a
 * portrait picture keeps its shape, and never enlarging: a picture already
 * smaller than the square is left at its own size rather than blown up into a
 * blur. Returns nil for an image with no size at all. Caller owns the result.
 */
static NSImage *AISettingsMakeInfoImage(NSImage *image)
{
	NSSize	 size = (image ? [image size] : NSZeroSize);
	CGFloat	 scale;
	NSImage	*scaled;

	if (size.width < 1.0 || size.height < 1.0) return nil;

	scale = MIN(AISettingsInfoImageSize / size.width, AISettingsInfoImageSize / size.height);
	scaled = [image copy];

	if (scale < 1.0) {
		//Rounded rather than truncated on both axes, so the shape survives the scaling
		[scaled setSize:NSMakeSize(MAX(round(size.width * scale), 1.0),
								   MAX(round(size.height * scale), 1.0))];
	}

	return scaled;
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

/*!
 * @brief The translucent fill that lifts the card off the window background
 *
 * quaternarySystemFillColor is what System Settings itself uses, but it only
 * exists from macOS 14 on and we deploy back to 11. Five percent of labelColor
 * stands in below that: labelColor is near-black in Aqua and near-white in
 * Dark Aqua, so the tint follows the appearance the same way the system fill
 * does, instead of baking in one colour that would vanish in the other.
 */
- (NSColor *)cardFillTint
{
	if (@available(macOS 14.0, *))
		return [NSColor quaternarySystemFillColor];

	return [[NSColor labelColor] colorWithAlphaComponent:0.05];
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
	[[self cardFillTint] setFill];
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
	NSImageView			*imageView;				//Leading picture of an info row
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
	[imageView release];
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
	NSTextField			*footnoteField;	//Below the card and below the accessory; nil for most sections
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
	[footnoteField release];
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
	if (previous && ![previous->rows count] && !previous->headerField && !previous->accessoryView && !previous->footnoteField) {
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
	if (section && ![section->rows count] && !section->headerField && !section->accessoryView && !section->footnoteField) {
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
	/* Before its text, in the order the row is read - drawing order only, since an info
	 * row keeps its picture out of the accessibility tree altogether. */
	if (row->imageView) [section->cardView addSubview:row->imageView];
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

- (void)addRowWithLabel:(NSString *)label stretchingControl:(NSView *)control
{
	AISettingsFormRow *row = [[[AISettingsFormRow alloc] init] autorelease];

	AISettingsAdoptView(control);

	/* Filled exactly like a slider row, and laid out by the slider row's case
	 * below: the two are the same shape — a label as wide as its text, a control
	 * taking everything left — and a stretching row is one without a readout.
	 */
	row->type = AISettingsRowTypeStretch;
	if (label.length) {
		row->labelField = AISettingsMakeLabel(label,
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor labelColor]);
	}
	row->control = [control retain];

	AISettingsApplyAccessibility(control, label, nil);

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

- (void)addDetailRow:(NSString *)text
{
	/* An empty field is not nothing: it still measures one blank line, so a row
	 * without text would open a gap in the card. */
	if (!text.length) return;

	AISettingsFormRow *row = [[[AISettingsFormRow alloc] init] autorelease];

	row->type = AISettingsRowTypeDetail;
	row->detailField = AISettingsMakeDetailLabel(text);

	/* Deliberately neither control nor fullWidthView: -layoutRow:atY:inCardOfWidth:
	 * adopts the frame of either as the row's natural size, which would freeze the
	 * height measured for a wide card and stop the text from ever folding again.
	 * The same nil also means -appendRow: finds no control to follow, so the field
	 * never dims and keeps the colour AISettingsMakeDetailLabel() gave it — right
	 * for a sentence which explains a whole card rather than one setting. */
	[self appendRow:row];
}

- (void)addEmptyStateRow:(NSString *)text
{
	/* As for a detail row: an empty field still measures one blank line, so a
	 * row without text would open a hole in the card rather than fill it. */
	if (!text.length) return;

	AISettingsFormRow *row = [[[AISettingsFormRow alloc] init] autorelease];

	row->type = AISettingsRowTypeEmptyState;
	row->detailField = AISettingsMakeDetailLabel(text);
	[row->detailField setAlignment:NSTextAlignmentCenter];
	/* Not selectable, unlike the sentence a detail row carries: this is the state
	 * of a list, not a text about it, and a selection highlight in the middle of
	 * an empty card reads as if something were there after all. */
	[row->detailField setSelectable:NO];

	//Neither control nor fullWidthView, for the reason -addDetailRow: spells out
	[self appendRow:row];
}

- (void)addInfoRow:(NSString *)text withImage:(NSImage *)image
{
	NSImage *symbol = [AISettingsMakeInfoImage(image) autorelease];

	//Neither a picture nor a sentence: an empty field still measures a blank line
	if (!text.length && !symbol) return;

	AISettingsFormRow *row = [[[AISettingsFormRow alloc] init] autorelease];

	row->type = AISettingsRowTypeInfo;
	if (text.length) row->detailField = AISettingsMakeDetailLabel(text);

	if (symbol) {
		NSSize symbolSize = [symbol size];

		row->imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0, 0.0, symbolSize.width, symbolSize.height)];
		[row->imageView setImage:symbol];
		/* The picture was scaled to exactly this frame, so there is nothing left to
		 * scale — but saying so means a picture whose frame is ever off by a point
		 * shrinks in proportion instead of being stretched or cropped. */
		[row->imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
		[row->imageView setImageAlignment:NSImageAlignCenter];
		/* Out of the accessibility tree, as a slider's readout is: the picture
		 * illustrates the sentence next to it and has nothing of its own to say, so
		 * announcing it would only put an "image" between the user and the text. */
		[row->imageView setAccessibilityElement:NO];
	}

	/* The picture goes in an ivar of its own rather than into control or
	 * fullWidthView, for the reason -addDetailRow: spells out: those two are where
	 * -layoutRow:atY:inCardOfWidth: takes a row's natural size from, and a row
	 * measured from a hosted view keeps the height it was first given and never
	 * folds its text again. Here the height still comes from measuring the text at
	 * the width the picture leaves it, every layout — the image view only ever
	 * receives a frame, it never decides one. */
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

		/* A footnote is drawn below the accessory bar, and VoiceOver reads a
		 * container in subview order: a footnote added before the bar has to move
		 * behind it again, or it is announced above what it stands under. */
		if (view && section->footnoteField) {
			[section->footnoteField removeFromSuperview];
			[self addSubview:section->footnoteField];
		}
	}

	section->accessoryTrailing = trailing;

	[self layoutForWidth:NSWidth([self frame])];
}

- (void)addFootnote:(NSString *)text
{
	AISettingsFormSection *section = [self currentSection];

	[section->footnoteField removeFromSuperview];
	[section->footnoteField release];
	//An empty field would still measure one blank line below the card
	section->footnoteField = (text.length ? AISettingsMakeDetailLabel(text) : nil);

	//Below the card, so a subview of the form itself rather than of the card
	if (section->footnoteField) [self addSubview:section->footnoteField];

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
		[section->footnoteField removeFromSuperview];
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
		if (![section->rows count] && !section->headerField && !section->accessoryView && !section->footnoteField) continue;

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
		 * of them would shift its slider while the user works two rows above.
		 * Stretching rows are laid out as slider rows and share the columns with
		 * them, so a card mixing both still has one label column. */
		CGFloat sliderInnerWidth = cardWidth - 2.0 * AISettingsCardInsetH;
		CGFloat sliderLabelColumn = 0.0;
		CGFloat sliderValueColumn = 0.0;

		for (AISettingsFormRow *row in section->rows) {
			if (row->type != AISettingsRowTypeSlider && row->type != AISettingsRowTypeStretch) continue;

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
			 * so the card must not draw one against it. A detail row explains what
			 * stands above it and has to end up on the near side of the line: it
			 * gets no divider of its own, while the row after it draws one as
			 * usual. */
			if (rowY > 0.0 && !edgeToEdge && !previousWasEdgeToEdge && row->type != AISettingsRowTypeDetail) {
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

		if (section->footnoteField) {
			/* Aligned with the card's edge rather than with the labels inside it,
			 * so a card carrying both a button bar and a footnote does not put two
			 * different left edges underneath itself. Measured at exactly the width
			 * it is given, so it refolds with the window instead of being clipped. */
			CGFloat footnoteHeight = AISettingsFieldHeight(section->footnoteField, cardWidth);

			y += AISettingsAccessoryGap;
			[section->footnoteField setFrame:NSMakeRect(AISettingsOuterMargin, y, cardWidth, footnoteHeight)];
			y += footnoteHeight;
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

		case AISettingsRowTypeDetail: {
			/* A block of explanation, not a control row: no minimum height — a
			 * 44 point row around one 15 point line would be a hole in the card —
			 * and measured at exactly the width the frame is about to get, so a
			 * word cannot fold into a line no height was reserved for. */
			CGFloat textHeight = AISettingsFieldHeight(row->detailField, innerWidth);

			/* A detail row explains the row above it, so it clings to it the way a
			 * label's own detail line does; opening a card it needs the card's
			 * padding instead. rowY is 0 for the first row of a card — the same
			 * test -layoutForWidth: uses for the dividers. */
			CGFloat topInset = (rowY > 0.0 ? AISettingsDetailGap : AISettingsRowInsetV);

			[row->detailField setFrame:NSMakeRect(AISettingsCardInsetH,
												  rowY + topInset,
												  innerWidth,
												  textHeight)];

			return topInset + textHeight + AISettingsRowInsetV;
		}

		case AISettingsRowTypeEmptyState: {
			/* A whole row's worth of height, unlike a detail row: this stands for
			 * the rows which are not there, so the card has to look like a list
			 * with nothing in it rather than like a single line of prose. The text
			 * is centred in both directions and re-measured every time, so it
			 * refolds with the window. */
			CGFloat textHeight = AISettingsFieldHeight(row->detailField, innerWidth);
			CGFloat rowHeight = MAX(AISettingsRowMinHeight, textHeight + 2.0 * AISettingsRowInsetV);

			[row->detailField setFrame:NSMakeRect(AISettingsCardInsetH,
												  rowY + floor((rowHeight - textHeight) / 2.0),
												  innerWidth,
												  textHeight)];

			return rowHeight;
		}

		case AISettingsRowTypeInfo: {
			/* A picture at the leading edge and the paragraph it illustrates beside
			 * it, both centred against whichever of the two is taller.
			 *
			 * Measured exactly the way a detail row is: the text height is asked for
			 * afresh at every layout, at the width that is actually left next to the
			 * picture, so the sentence refolds as the window narrows. Nothing here
			 * reads a frame back — the image view is given the size its (already
			 * scaled) picture has and never reports one — so no measurement of a
			 * wide card can survive into a narrow one. */
			NSImage	*symbol = [row->imageView image];
			NSSize	 symbolSize = (symbol ? [symbol size] : NSZeroSize);
			/* The text begins at the far side of the whole square, not at the far side of
			 * this particular picture: only one of the two edges of a scaled picture ends up
			 * on the square, so a portrait one is 36 points wide and a landscape one 40, and
			 * two info rows in a card would start their paragraphs at two different x - the
			 * same misalignment the shared slider label column above exists to prevent. The
			 * picture is centred in that column, so a narrow one does not hang off its
			 * leading edge. */
			CGFloat	 leading = (symbolSize.width > 0.0 ? AISettingsInfoImageSize + AISettingsLabelControlGap : 0.0);
			CGFloat	 textWidth = MAX(innerWidth - leading, 1.0);
			CGFloat	 textHeight = AISettingsFieldHeight(row->detailField, textWidth);
			CGFloat	 rowHeight = MAX(AISettingsRowMinHeight,
									 MAX(textHeight, symbolSize.height) + 2.0 * AISettingsRowInsetV);

			if (row->imageView) {
				[row->imageView setFrame:NSMakeRect(AISettingsCardInsetH + floor((AISettingsInfoImageSize - symbolSize.width) / 2.0),
													rowY + floor((rowHeight - symbolSize.height) / 2.0),
													symbolSize.width,
													symbolSize.height)];
			}
			if (row->detailField) {
				[row->detailField setFrame:NSMakeRect(AISettingsCardInsetH + leading,
													  rowY + floor((rowHeight - textHeight) / 2.0),
													  textWidth,
													  textHeight)];
			}

			return rowHeight;
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

		case AISettingsRowTypeSlider:
		case AISettingsRowTypeStretch: {
			/* Label, slider and readout share one line: the label and the readout
			 * keep the width of their text, the slider takes what is left. A
			 * stretching row is the same thing without a readout — valueField is
			 * nil, so the trailing column collapses to nothing and the control
			 * runs to the card's inset. */
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

+ (NSButton *)inlineSymbolButtonWithSymbolName:(NSString *)symbolName
							 fallbackImageName:(NSString *)imageName
										target:(id)target
										action:(SEL)action
{
	NSImage *image = nil;

	if (@available(macOS 11.0, *)) {
		image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
		/* A symbol drawn at its own point size rather than scaled to the button:
		 * that is what makes a column of these line up whatever glyph they show. */
		image = [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:AISettingsInlineSymbolSize
																									weight:NSFontWeightRegular]];
	}
	if (!image && imageName.length) image = [NSImage imageNamed:imageName];

	NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0,
																   AISettingsInlineButtonSize,
																   AISettingsInlineButtonSize)] autorelease];

	[button setButtonType:NSButtonTypeMomentaryChange];
	[button setBordered:NO];
	[button setTitle:@""];
	[button setImage:image];
	[button setImagePosition:NSImageOnly];
	//Recedes behind the row's own text, the way System Settings tints its inline controls
	[button setContentTintColor:[NSColor secondaryLabelColor]];
	[button setTarget:target];
	[button setAction:action];
	//A fixed size, not a fitted one: the frame is the column every row shares
	[button setFrameSize:NSMakeSize(AISettingsInlineButtonSize, AISettingsInlineButtonSize)];

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

+ (NSTextField *)textFieldWithTarget:(id)target action:(SEL)action
{
	NSTextField *field = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];

	[field setFont:[NSFont systemFontOfSize:AISettingsLabelFontSize]];
	[field setAlignment:NSTextAlignmentLeft];
	[field setTarget:target];
	[field setAction:action];
	/* Return alone is not enough: a user who types and then clicks somewhere else
	 * expects what they typed to have been taken. */
	[[field cell] setSendsActionOnEndEditing:YES];
	[field sizeToFit];

	//The row decides the width; only the height comes from the field itself
	[field setFrameSize:NSMakeSize(AISettingsSliderMinWidth, ceil(NSHeight([field frame])))];

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
