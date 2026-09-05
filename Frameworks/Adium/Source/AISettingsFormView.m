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

/* Auto Layout inside, a frame contract outside.
 *
 * Towards its host this view is what it always was: a frame based NSView whose
 * size the preferences window controller sets with -setFrame:, and which
 * answers with the truthful height of its content. Nothing above it — the
 * window controller, the panes — knows or cares how that height comes about.
 *
 * Inside, the height is no longer added up by hand. The form holds exactly one
 * vertical NSStackView, pinned to its top and leading edge and given its width
 * by -layoutForWidth: through a single constraint. Sections drop their header,
 * card, accessory strip and footnote into that stack; each card holds a second
 * vertical stack with one row view per row; and each row view describes its
 * shape — label left, control right, everything centred, at least 44 points
 * tall — as constraints. A layout pass resolves the whole tree, the form reads
 * the stack's height back, and that is the content height. The old machine
 * computed every one of those numbers itself, which bred a whole class of
 * bugs: imposed heights, autoresizing springs re-moving what had just been
 * placed, two writers disagreeing about the document height.
 *
 * Views handed in by the panes are the reason this is a hybrid and not a
 * conversion: they come out of nibs and code that positions by frame, resize
 * themselves with -setFrameSize: and report it with -noteContentSizeChanged.
 * Rather than teaching each of them constraints, every guest keeps its frame
 * semantics inside a small host view (AISettingsGuestHostView below) which
 * translates between the two worlds: the constraint engine sizes the host, the
 * host sizes the guest by frame, and the guest's own height is read back as
 * the host's intrinsic size. The guests never meet a constraint.
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
static const CGFloat AISettingsAccessoryGap	= 8.0;	//Between a card and the button bar below it
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
/* One point above a detail line. An info row carries a paragraph a user is meant to read
 * rather than a remark under a setting, and at 11 pt beside a 40 pt picture it reads as
 * small print. Its own constant, so raising it here cannot shrink or grow the detail
 * lines the other panes are built from. */
static const CGFloat AISettingsInfoFontSize	= 12.0;
static const CGFloat AISettingsHeaderFontSize	= 13.0;
static const CGFloat AISettingsFallbackWidth	= 480.0;	//Used when a host gives us no usable width
static const CGFloat AISettingsInlineButtonSize	= 22.0;		//Edge length of a row's trailing symbol button
static const CGFloat AISettingsInlineSymbolSize	= 16.0;		//Point size of the symbol drawn in it
static const CGFloat AISettingsDisclosureSymbolSize = 11.0;	//Point size of a row's chevron
static const CGFloat AISettingsInfoImageSize	= 40.0;		//Longest edge of the picture in an info row
/* A profile header breathes more than a row does: it opens a page instead of
 * carrying a setting, and the picture needs air around it to read as a portrait
 * rather than as a control which happens to be round. */
static const CGFloat AISettingsProfileTopInset	= 20.0;		//Above the picture of a profile header, and below its button
static const CGFloat AISettingsProfileNameGap	= 12.0;		//Between that picture and the name under it
static const CGFloat AISettingsProfileButtonGap	= 8.0;		//Between that name and the button under it
static const CGFloat AISettingsProfileNameSize	= 19.0;		//Point size of that name

/* The pecking order of the constraints. Where the old machine wrote its rules
 * as arithmetic — "the control keeps its natural width, but never more than
 * the card minus the label's minimum; a squeezed slider shortens its label
 * first" — the new one writes them as priorities, and the order below is that
 * arithmetic, spelt out once. Higher numbers give way later:
 *
 *   ShrinkRow < LabelFill < NaturalWidth < SliderLabelColumn < SliderMinWidth
 *   < LabelReserve < ControlFloor < NaturalCap < ValueColumn < CardWidth.
 *
 * So a row is pulled down onto its content (ShrinkRow) unless something taller
 * stands in it; a label stretches into leftover width (LabelFill) but never
 * pushes a control off its natural size (NaturalWidth); a narrow card takes
 * width from the control before it takes the label below its minimum
 * (LabelReserve beats NaturalWidth), yet cannot squeeze a control below its
 * floor (ControlFloor) or stretch it beyond its natural size (NaturalCap). */
static const NSLayoutPriority AISettingsPriorityShrinkRow			= 200.0;
static const NSLayoutPriority AISettingsPriorityLabelFill			= 400.0;
static const NSLayoutPriority AISettingsPriorityNaturalWidth		= 500.0;
static const NSLayoutPriority AISettingsPrioritySliderLabelColumn	= 600.0;
static const NSLayoutPriority AISettingsPrioritySliderMinWidth		= 650.0;
static const NSLayoutPriority AISettingsPriorityLabelReserve		= 700.0;
static const NSLayoutPriority AISettingsPriorityControlFloor		= 710.0;
static const NSLayoutPriority AISettingsPriorityNaturalCap			= 720.0;
static const NSLayoutPriority AISettingsPriorityValueColumn		= 730.0;
static const NSLayoutPriority AISettingsPrioritySliderCap			= 760.0;	//A capped slider holds its width until the card cannot spare it
static const NSLayoutPriority AISettingsPriorityKeepFrame			= 900.0;	//An accessory is never resized at all
static const NSLayoutPriority AISettingsPriorityCardWidth			= 900.0;	//Card tracks the form's width...
static const NSLayoutPriority AISettingsPriorityCardWidthFloor		= 995.0;	//...but never collapses entirely

/* Our own KVO context: a row must be able to tell its own notification from one
 * meant for a superclass. AISettingsFormRow inherits from NSObject, whose
 * -observeValueForKeyPath:… raises, so forwarding a foreign notification would
 * end the process. */
static void *AISettingsRowEnabledContext = &AISettingsRowEnabledContext;

typedef enum {
	AISettingsRowTypeControl = 0,
	AISettingsRowTypePopUp,
	AISettingsRowTypeSlider,
	AISettingsRowTypeStretch,		//Label plus a control filling the row; built as a slider row
	AISettingsRowTypeRadioGroup,
	AISettingsRowTypeFullWidth,
	AISettingsRowTypeEdgeToEdge,
	AISettingsRowTypeDetail,		//Explanatory text, no control at all
	AISettingsRowTypeEmptyState,	//"Nothing here yet", centred in an otherwise empty card
	AISettingsRowTypeInfo,			//A picture plus the paragraph it illustrates
	AISettingsRowTypeProfileHeader	//Round picture, name and a button under it, all centred
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
 * @brief Hand one of the form's own fields to the constraint engine.
 *
 * Only the fields the form itself creates live in Auto Layout; everything a
 * pane hands in stays frame based inside a host view. The low horizontal
 * priorities make a field the most compliant thing in its row: it stretches
 * into whatever width the row leaves it and never pushes a control off its
 * natural size — the frame based machine gave labels no say either.
 */
static void AISettingsPrepareField(NSTextField *field)
{
	if (!field) return;

	[field setTranslatesAutoresizingMaskIntoConstraints:NO];
	[field setContentHuggingPriority:100.0 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[field setContentCompressionResistancePriority:100.0 forOrientation:NSLayoutConstraintOrientationHorizontal];
}

/*!
 * @brief Sugar: give @a constraint a priority and hand it back.
 */
static NSLayoutConstraint *AISettingsPrioritized(NSLayoutConstraint *constraint, NSLayoutPriority priority)
{
	[constraint setPriority:priority];
	return constraint;
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
 * @brief The size a hosted view should be laid out at: its own frame if it has
 *        one, otherwise its fitting size.
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
 * @brief Take a view over for frame based hosting.
 *
 * Guests live by their frames inside their host view. A view whose
 * translatesAutoresizingMaskIntoConstraints is NO — anything coming out of a
 * XIB which was saved with Auto Layout, for instance — expects constraints
 * that nobody here is going to write, and the engine would resolve it as
 * ambiguous and collapse it. Say explicitly that its frame is the truth; its
 * own subviews keep whatever layout they came with.
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
	/* A scroller is never a row's setting: it is furniture inside a scroll view, and an
	 * autohiding one with nothing to scroll reports itself disabled - which, taken for the
	 * row's control, greyed the label of a text-editor row for no reason. */
	if ([view isKindOfClass:[NSScroller class]]) return nil;
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
 * @brief How a host treats the frame based guest it carries.
 */
typedef enum {
	/*! The guest is resized to the host: as wide as the engine made the host,
	 *  as tall as its remembered natural size. For controls which keep their
	 *  natural width but may be narrowed by a narrow card — and must grow back
	 *  when there is room again, which is why the natural size is remembered
	 *  here instead of being read from the (possibly narrowed) frame. */
	AISettingsGuestSizingNatural = 0,
	/*! The guest is stretched to the host's width but keeps whatever height its
	 *  own frame has, and that height <em>is</em> the host's intrinsic height —
	 *  read afresh every time, so a guest which resizes itself (a hosted list,
	 *  a WebView preview) resizes its row with it. */
	AISettingsGuestSizingStretch,
	/*! The guest is never touched at all; the host simply reports the guest's
	 *  frame as its own intrinsic size. For accessory bars, which keep the size
	 *  their builder gave them. */
	AISettingsGuestSizingKeepFrame
} AISettingsGuestSizing;

/*!
 * @brief The bridge between the constraint engine and a frame based guest.
 *
 * The engine sizes the host; the host sizes the guest by plain -setFrame:, the
 * way the old layout machine did — so guests out of nibs and panes never need
 * constraints, springs keep meaning what they meant, and a guest resizing
 * itself keeps working: its new frame becomes the host's intrinsic size at the
 * next -noteContentSizeChanged. Flipped, so the guest hangs from the top edge.
 */
@interface AISettingsGuestHostView : NSView {
@public
	NSView					*guestView;		//Retained; also our subview
	AISettingsGuestSizing	 sizing;
	NSSize					 naturalSize;	//Natural sizing only: the size the guest wants
}
+ (AISettingsGuestHostView *)hostForGuest:(NSView *)guest sizing:(AISettingsGuestSizing)guestSizing;
- (void)refreshGuestMetrics;
- (void)resetNaturalSize;
@end

@implementation AISettingsGuestHostView

+ (AISettingsGuestHostView *)hostForGuest:(NSView *)guest sizing:(AISettingsGuestSizing)guestSizing
{
	AISettingsGuestHostView *host = [[self alloc] initWithFrame:NSZeroRect];

	[host setTranslatesAutoresizingMaskIntoConstraints:NO];
	host->sizing = guestSizing;
	host->guestView = guest;
	host->naturalSize = AISettingsControlSize(guest);

	//A guest without a frame yet starts at its natural size, as it always did
	NSRect guestFrame = [guest frame];
	if (NSWidth(guestFrame) < 1.0 || NSHeight(guestFrame) < 1.0) [guest setFrameSize:host->naturalSize];
	[guest setFrameOrigin:NSZeroPoint];

	[host addSubview:guest];

	return host;
}

- (BOOL)isFlipped
{
	return YES;
}

- (NSSize)intrinsicContentSize
{
	switch (sizing) {
		case AISettingsGuestSizingNatural:
			return naturalSize;
		case AISettingsGuestSizingStretch:
			//Width is the row's business; the guest only ever decides its height
			return NSMakeSize(NSViewNoIntrinsicMetric, NSHeight([guestView frame]));
		case AISettingsGuestSizingKeepFrame:
		default:
			return [guestView frame].size;
	}
}

- (void)layout
{
	[super layout];

	NSRect	target = [guestView frame];

	switch (sizing) {
		case AISettingsGuestSizingNatural:
			target = NSMakeRect(0.0, 0.0, NSWidth([self bounds]), naturalSize.height);
			break;
		case AISettingsGuestSizingStretch:
			target = NSMakeRect(0.0, 0.0, NSWidth([self bounds]), NSHeight(target));
			break;
		case AISettingsGuestSizingKeepFrame:
			target.origin = NSZeroPoint;
			break;
	}

	/* Only when something moved: guests may watch their own frame, and a no-op
	 * -setFrame: still costs them a notification. */
	if (!NSEqualRects(target, [guestView frame])) [guestView setFrame:target];
}

/*!
 * @brief Re-read what the guest wants to be; called once per form layout.
 *
 * For a natural sized guest the width only ever ratchets up: our own layout is
 * what narrows the frame, so reading it back unconditionally would ratchet
 * every control down to the narrowest width it was ever laid out at. A frame
 * wider than what we remember can only come from the caller — a -sizeToFit
 * after filling a menu, say — and is adopted as the new natural width. Heights
 * are the guest's own and are adopted in both directions.
 */
- (void)refreshGuestMetrics
{
	if (sizing == AISettingsGuestSizingNatural) {
		NSSize current = [guestView frame].size;
		if (current.width > naturalSize.width + 0.5) naturalSize.width = current.width;
		if (fabs(current.height - naturalSize.height) > 0.5) naturalSize.height = current.height;
	}
	[self invalidateIntrinsicContentSize];
}

/*!
 * @brief Take the guest's current frame as the natural size, wider or narrower.
 *
 * For pop up buttons, which are re-measured from scratch at every layout: a
 * rebuilt menu may want less room than the old one, not just more.
 */
- (void)resetNaturalSize
{
	naturalSize = AISettingsControlSize(guestView);
	[self invalidateIntrinsicContentSize];
}

@end

#pragma mark -

/*!
 * @brief One row of a card: a plain constraint container.
 *
 * Its only behaviour of its own is the wrapping bookkeeping: a wrapping
 * NSTextField only reports a useful intrinsic height once it knows the width
 * it will actually get, so after every engine pass the row feeds each wrapping
 * field its resolved width back as preferredMaxLayoutWidth. A changed width
 * invalidates the field's intrinsic size, and the following pass gets the
 * refolded height — which is why -layoutForWidth: always runs two passes.
 */
@interface AISettingsRowView : NSView {
	NSMutableArray	*wrappingFields;
}
- (void)followWidthOfField:(NSTextField *)field;
@end

@implementation AISettingsRowView

- (void)followWidthOfField:(NSTextField *)field
{
	if (!field) return;
	if (!wrappingFields) wrappingFields = [[NSMutableArray alloc] init];
	[wrappingFields addObject:field];
}

- (void)layout
{
	[super layout];

	for (NSTextField *field in wrappingFields) {
		CGFloat width = NSWidth([field frame]);
		if (width >= 1.0 && fabs([field preferredMaxLayoutWidth] - width) > 0.5) {
			[field setPreferredMaxLayoutWidth:width];
		}
	}
}

@end

#pragma mark -

/*!
 * @brief A whole row that acts as one button, the way a System Settings row that opens a page does.
 *
 * A chevron at the trailing edge is a signpost rather than a target: what is pressed is the row, all
 * of it, and it darkens under the finger while it is held. A button placed in an ordinary row would
 * only answer to the few points the glyph covers, and would give no sign that it had been hit.
 *
 * Hosted edge to edge, so the highlight runs the full width of the card and is clipped to its
 * corners. The label keeps the same inset every other row's label has, so a card mixing both kinds
 * lines up.
 */
@interface AISettingsNavigationRowView : NSView {
	NSTextField	*labelField;
	NSImageView	*chevron;
	__unsafe_unretained id	 target;	//Not retained, as a control's target is not
	SEL			 action;
	BOOL		 pressed;
}
- (id)initWithLabel:(NSString *)label target:(id)inTarget action:(SEL)inAction;
@end

@implementation AISettingsNavigationRowView

- (id)initWithLabel:(NSString *)label target:(id)inTarget action:(SEL)inAction
{
	if ((self = [super initWithFrame:NSMakeRect(0.0, 0.0, 100.0, AISettingsRowMinHeight)])) {
		target = inTarget;
		action = inAction;

		labelField = AISettingsMakeLabel(label,
										 [NSFont systemFontOfSize:AISettingsLabelFontSize],
										 [NSColor labelColor]);
		[labelField sizeToFit];

		chevron = [NSImageView imageViewWithImage:[AISettingsFormView disclosureIndicatorImage]];
		[chevron setContentTintColor:[NSColor tertiaryLabelColor]];
		[chevron setFrameSize:[[chevron image] size]];

		/* Frames rather than constraints: the form hosts this view the way it hosts anything a pane
		 * hands it, by setting its frame, and a view laid out both ways at once fights itself. */
		[self addSubview:labelField];
		[self addSubview:chevron];

		[self setAccessibilityRole:NSAccessibilityButtonRole];
		[self setAccessibilityLabel:label];
	}

	return self;
}

- (BOOL)isFlipped
{
	return YES;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
	NSRect bounds = [self bounds];
	NSSize chevronSize = [chevron frame].size;
	CGFloat chevronX = NSMaxX(bounds) - AISettingsCardInsetH - chevronSize.width;

	[chevron setFrame:NSMakeRect(chevronX,
								 round((NSHeight(bounds) - chevronSize.height) / 2.0),
								 chevronSize.width,
								 chevronSize.height)];

	CGFloat labelWidth = chevronX - 8.0 - AISettingsCardInsetH;
	NSSize labelSize = [labelField frame].size;

	[labelField setFrame:NSMakeRect(AISettingsCardInsetH,
									round((NSHeight(bounds) - labelSize.height) / 2.0),
									MAX(labelWidth, 0.0),
									labelSize.height)];
}

- (void)drawRect:(NSRect)dirtyRect
{
	if (!pressed) return;

	/* A foreground colour at low alpha rather than a fixed grey: it darkens on a light card and
	 * lightens on a dark one, which is what the system does, and it needs no second colour. */
	[[NSColor quaternaryLabelColor] set];
	NSRectFillUsingOperation([self bounds], NSCompositingOperationSourceOver);
}

- (void)setPressed:(BOOL)inPressed
{
	if (pressed == inPressed) return;

	pressed = inPressed;
	[self setNeedsDisplay:YES];
}

/*!
 * @brief Track the press ourselves
 *
 * A row is not a control, and wrapping one in an NSButton would put the button's own drawing under
 * the label. Tracking is a few lines and gives exactly the behaviour of a list row: held down it
 * darkens, dragged off it goes back, released outside it does nothing.
 */
- (void)mouseDown:(NSEvent *)event
{
	BOOL inside = YES;

	[self setPressed:YES];

	while (YES) {
		NSEvent *next = [[self window] nextEventMatchingMask:(NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged)];
		inside = NSPointInRect([self convertPoint:[next locationInWindow] fromView:nil], [self bounds]);

		if ([next type] == NSEventTypeLeftMouseUp)
			break;

		[self setPressed:inside];
	}

	[self setPressed:NO];

	if (inside && target && action)
		[NSApp sendAction:action to:target from:self];
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

- (BOOL)isFlipped
{
	return YES;
}

- (void)setSeparatorPositions:(NSArray *)positions
{
	if (positions != separatorPositions && ![positions isEqualToArray:separatorPositions]) {
		separatorPositions = positions;
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
 * In Aqua quaternarySystemFillColor is what System Settings itself uses (it
 * only exists from macOS 14 on and we deploy back to 11; five percent of
 * labelColor stands in below that). In Dark Aqua the quaternary fill turned
 * out to be no lift at all: measured over this window it raises the card from
 * 0.118 to 0.142, which reads as the same black on most panels, and the cards
 * disappeared. Eight percent of white takes the card to 0.188, about where
 * System Settings' own dark cards sit above their window.
 */
- (NSColor *)cardFillTint
{
	NSString *match = [[self effectiveAppearance] bestMatchFromAppearancesWithNames:
					   [NSArray arrayWithObjects:NSAppearanceNameAqua, NSAppearanceNameDarkAqua, nil]];

	if ([match isEqualToString:NSAppearanceNameDarkAqua])
		return [NSColor colorWithWhite:1.0 alpha:0.08];

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
 * @brief One row of a card, holding its views, its row container and the
 *        constraints the form retunes at layout time.
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
	BOOL				 trailingAlignsFullWidthView;	//Unstretched only: the view sits at the trailing edge
	/* Edge to edge rows draw no hairline against their neighbours, because a hosted list brings its
	 * own. A row that is edge to edge only so that its highlight covers the card still wants one. */
	BOOL				 wantsSeparators;
	BOOL				 labelTopAligned;		//Stretch rows: pin the label to the control's top, not its centre
	__unsafe_unretained NSControl	*enabledSource;	//Not retained; lives inside control/radioContainer

	AISettingsRowView		*rowView;			//The row's container in the card stack
	//Hosts are subviews of rowView and owned by it; plain pointers are enough
	__unsafe_unretained AISettingsGuestHostView	*controlHost;
	__unsafe_unretained AISettingsGuestHostView	*accessoryHost;
	__unsafe_unretained AISettingsGuestHostView	*valueHost;
	__unsafe_unretained AISettingsGuestHostView	*radioHost;
	__unsafe_unretained AISettingsGuestHostView	*fullWidthHost;
	/* Slider/stretch rows only: the shared label and readout columns of the
	 * card, as constraints whose constants -layoutForWidth: retunes so every
	 * slider of a card starts and ends on the same two lines. */
	NSLayoutConstraint		*labelColumnConstraint;
	NSLayoutConstraint		*valueColumnConstraint;
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
	NSStackView			*cardStack;		//Inside the card; one arranged subview per row
	NSMutableArray		*rows;
	NSView				*accessoryView;	//Sits below the card, outside of it; nil for most sections
	BOOL				 accessoryTrailing;	//NO: aligned with the card's leading edge, the default
	NSView				*accessoryWrapper;	//Card-wide strip the accessory hangs in, for the alignment
	__unsafe_unretained AISettingsGuestHostView	*accessoryHost;	//Subview of the wrapper; plain pointer
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
		[cardView setTranslatesAutoresizingMaskIntoConstraints:NO];

		/* The rows stack inside the card and give it its height: the stack is
		 * pinned to all four card edges, so the card is exactly as tall as its
		 * rows and no code ever adds row heights up again. */
		cardStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
		[cardStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
		[cardStack setAlignment:NSLayoutAttributeCenterX];
		[cardStack setDistribution:NSStackViewDistributionFill];
		[cardStack setSpacing:0.0];
		[cardStack setTranslatesAutoresizingMaskIntoConstraints:NO];
		[cardView addSubview:cardStack];
		[NSLayoutConstraint activateConstraints:
		 @[[cardStack.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor],
		   [cardStack.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor],
		   [cardStack.topAnchor constraintEqualToAnchor:cardView.topAnchor],
		   [cardStack.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor]]];
	}
	return self;
}
@end

#pragma mark -

@interface AISettingsFormView ()
- (void)addAccessoryView:(NSView *)view trailing:(BOOL)trailing;
- (AISettingsFormSection *)currentSection;
- (void)attachSection:(AISettingsFormSection *)section;
- (void)pinCardWidthElement:(NSView *)view;
- (void)appendRow:(AISettingsFormRow *)row;
- (void)buildViewForRow:(AISettingsFormRow *)row isFirstRowInCard:(BOOL)isFirstRowInCard;
- (void)constrainHeightFloorOfRow:(AISettingsRowView *)rowView;
- (NSLayoutGuide *)textBlockWithTop:(NSTextField *)topField bottom:(NSTextField *)bottomField inRow:(AISettingsRowView *)rowView;
- (void)refreshGuestMetricsForCardWidth:(CGFloat)cardWidth;
- (void)updateStackSpacing;
- (void)updateCardSeparators;
- (void)updateEnclosingDocumentViewHeight;
@end

@implementation AISettingsFormView

@synthesize maximumSliderWidth = maximumSliderWidth;
@synthesize sharesLabelColumn = sharesLabelColumn;

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

		/* The one stack everything hangs off. Pinned to top and leading only:
		 * the bottom stays free because the stack's height is the answer we
		 * read back, not something the form's frame may dictate — the frame
		 * height follows the stack, never the other way round. The width comes
		 * through a constraint of its own, so -layoutForWidth: can lay out for
		 * a width the frame does not have yet. */
		formStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
		[formStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
		[formStack setAlignment:NSLayoutAttributeCenterX];
		[formStack setDistribution:NSStackViewDistributionFill];
		[formStack setSpacing:0.0];
		[formStack setTranslatesAutoresizingMaskIntoConstraints:NO];
		[self addSubview:formStack];
		[NSLayoutConstraint activateConstraints:
		 @[[formStack.topAnchor constraintEqualToAnchor:self.topAnchor],
		   [formStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor]]];

		formWidthConstraint = [formStack.widthAnchor constraintEqualToConstant:NSWidth(frame)];
		[formWidthConstraint setActive:YES];
	}
	return self;
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
		section = [[AISettingsFormSection alloc] init];
		[sections addObject:section];
		[self attachSection:section];
	}

	return section;
}

/*!
 * @brief Put a section's header and card into the form stack.
 */
- (void)attachSection:(AISettingsFormSection *)section
{
	if (section->headerField) {
		AISettingsPrepareField(section->headerField);
		[formStack addArrangedSubview:section->headerField];
		[self pinCardWidthElement:section->headerField];
	}
	[formStack addArrangedSubview:section->cardView];
	[self pinCardWidthElement:section->cardView];
}

/*!
 * @brief Make @a view as wide as a card: the form's width minus both margins.
 *
 * Below required, so a floor keeps the card usable when a host hands over an
 * absurdly narrow width — the same MAX() the old machine applied.
 */
- (void)pinCardWidthElement:(NSView *)view
{
	[NSLayoutConstraint activateConstraints:
	 @[AISettingsPrioritized([view.widthAnchor constraintEqualToAnchor:formStack.widthAnchor
															  constant:-2.0 * AISettingsOuterMargin],
							 AISettingsPriorityCardWidth),
	   AISettingsPrioritized([view.widthAnchor constraintGreaterThanOrEqualToConstant:2.0 * AISettingsCardInsetH + 40.0],
							 AISettingsPriorityCardWidthFloor)]];
}

- (void)addSectionHeader:(NSString *)title
{
	//A card that never received a row would just add a gap
	AISettingsFormSection *previous = [sections lastObject];
	if (previous && ![previous->rows count] && !previous->headerField && !previous->accessoryView && !previous->footnoteField) {
		[previous->cardView removeFromSuperview];
		[sections removeLastObject];
	}

	AISettingsFormSection *section = [[AISettingsFormSection alloc] init];

	if (title.length) {
		section->headerField = AISettingsMakeLabel(title,
												   [NSFont systemFontOfSize:AISettingsHeaderFontSize weight:NSFontWeightBold],
												   [NSColor labelColor]);
	}

	[sections addObject:section];
	[self attachSection:section];

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
		AISettingsFormSection *next = [[AISettingsFormSection alloc] init];
		[sections addObject:next];
		[self attachSection:next];
	}
}

- (void)appendRow:(AISettingsFormRow *)row
{
	AISettingsFormSection *section = [self currentSection];
	BOOL isFirstRowInCard = ([section->rows count] == 0);

	[section->rows addObject:row];

	/* Every guest is hosted frame based, and its host is the only thing that
	 * may ever write its frame — so it must translate its mask (a nib view may
	 * arrive constraint based) and must carry no springs of its own: the status
	 * pane's pop up menus once came with NSViewMinXMargin and were shifted a
	 * second time on top of the position they had just been given. */
	AISettingsAdoptView(row->control);
	AISettingsAdoptView(row->accessoryControl);
	AISettingsAdoptView(row->valueField);
	AISettingsAdoptView(row->fullWidthView);
	[row->control setAutoresizingMask:NSViewNotSizable];
	[row->accessoryControl setAutoresizingMask:NSViewNotSizable];
	[row->valueField setAutoresizingMask:NSViewNotSizable];
	[row->radioContainer setAutoresizingMask:NSViewNotSizable];
	[row->fullWidthView setAutoresizingMask:NSViewNotSizable];

	[self buildViewForRow:row isFirstRowInCard:isFirstRowInCard];

	[section->cardStack addArrangedSubview:row->rowView];
	//Every row spans the card; the shapes inside the row do the aligning
	[[row->rowView.widthAnchor constraintEqualToAnchor:section->cardStack.widthAnchor] setActive:YES];

	[row trackEnabledStateOf:AISettingsPrimaryControl(row->control ?: row->radioContainer)];

	[self layoutForWidth:NSWidth([self frame])];
}

- (void)addRowWithLabel:(NSString *)label control:(NSView *)control
{
	[self addRowWithLabel:label control:control detail:nil];
}

- (void)addRowWithLabel:(NSString *)label control:(NSView *)control detail:(NSString *)detail
{
	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

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
	row->control = control;

	AISettingsApplyAccessibility(control, label, detail);

	[self appendRow:row];
}

- (void)addRowWithLabel:(NSString *)label popUpButton:(NSPopUpButton *)popUpButton accessoryButton:(NSButton *)button
{
	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

	row->type = AISettingsRowTypePopUp;
	if (label.length) {
		row->labelField = AISettingsMakeLabel(label,
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor labelColor]);
	}
	row->control = popUpButton;
	row->accessoryControl = button;

	AISettingsApplyAccessibility(popUpButton, label, nil);
	/* The accessory keeps its own title as its accessibility label — it shows one
	 * — but three buttons reading "Customize…" in a row say nothing about what
	 * they customize, so the row's label becomes their help text. */
	AISettingsApplyAccessibility(button, nil, label);

	[self appendRow:row];
}

- (void)addRowWithLabel:(NSString *)label slider:(NSSlider *)slider valueLabel:(NSTextField *)valueLabel
{
	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

	row->type = AISettingsRowTypeSlider;
	if (label.length) {
		row->labelField = AISettingsMakeLabel(label,
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor labelColor]);
	}
	row->control = slider;
	row->valueField = valueLabel;

	AISettingsApplyAccessibility(slider, label, nil);
	/* The readout only repeats the slider's own value, which VoiceOver already
	 * announces; leaving it in the tree makes every slider read out twice. */
	[valueLabel setAccessibilityElement:NO];

	[self appendRow:row];
}

- (void)addRowWithLabel:(NSString *)label stretchingControl:(NSView *)control
{
	[self addRowWithLabel:label stretchingControl:control labelTopAligned:NO];
}

- (void)addRowWithLabel:(NSString *)label stretchingControl:(NSView *)control labelTopAligned:(BOOL)labelTopAligned
{
	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

	/* Built exactly like a slider row: the two are the same shape — a label as
	 * wide as its text, a control taking everything left — and a stretching row
	 * is one without a readout. */
	row->type = AISettingsRowTypeStretch;
	if (label.length) {
		row->labelField = AISettingsMakeLabel(label,
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor labelColor]);
	}
	row->control = control;
	//A tall control - a text editor - reads better with its label beside its first line, not its middle
	row->labelTopAligned = labelTopAligned;

	AISettingsApplyAccessibility(control, label, nil);

	[self appendRow:row];
}

- (void)addRadioGroupWithLabel:(NSString *)label buttons:(NSArray *)radioButtons
{
	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

	row->type = AISettingsRowTypeRadioGroup;
	if (label.length) {
		row->labelField = AISettingsMakeLabel(label,
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor labelColor]);
	}
	row->radioButtons = [radioButtons copy];
	/* Radio buttons live in their own container: AppKit makes one exclusive
	 * group out of every radio button sharing a superview and an action, so two
	 * groups in the same card would silently clear each other. The buttons
	 * never change size, so the column is laid out once, right here; the
	 * container's height is what the row reads back. */
	row->radioContainer = [[AISettingsFlippedView alloc] initWithFrame:NSZeroRect];
	if (label.length) [row->radioContainer setAccessibilityLabel:label];

	CGFloat buttonY = 0.0;
	CGFloat widestButton = 0.0;
	for (NSButton *button in row->radioButtons) {
		AISettingsAdoptView(button);
		[button setAutoresizingMask:NSViewNotSizable];
		if (NSWidth([button frame]) < 1.0 || NSHeight([button frame]) < 1.0) [button sizeToFit];

		NSSize size = [button frame].size;
		[button setFrameOrigin:NSMakePoint(0.0, buttonY)];
		[row->radioContainer addSubview:button];
		buttonY += size.height + AISettingsRadioSpacing;
		widestButton = MAX(widestButton, size.width);
	}
	if ([row->radioButtons count]) buttonY -= AISettingsRadioSpacing;

	[row->radioContainer setFrame:NSMakeRect(0.0, 0.0, MAX(widestButton, 1.0), MAX(buttonY, 0.0))];

	[self appendRow:row];
}

- (void)addFullWidthRow:(NSView *)view
{
	[self addFullWidthRow:view stretch:YES];
}

- (void)addFullWidthRow:(NSView *)view stretch:(BOOL)stretch
{
	[self addFullWidthRow:view stretch:stretch trailingAligned:NO];
}

- (void)addFullWidthRow:(NSView *)view stretch:(BOOL)stretch trailingAligned:(BOOL)trailingAligned
{
	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

	row->type = AISettingsRowTypeFullWidth;
	row->fullWidthView = view;
	row->stretchesFullWidthView = stretch;
	row->trailingAlignsFullWidthView = trailingAligned;

	[self appendRow:row];
}

- (void)addEdgeToEdgeRow:(NSView *)view
{
	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

	/* The view <em>is</em> the card, so it has to be clipped to the card's
	 * rounded corners - a selected first or last row of a hosted list would
	 * otherwise paint over them. Doing it here keeps the radius in one place:
	 * no host ever repeats it. */
	[view setWantsLayer:YES];
	[[view layer] setCornerRadius:AISettingsCardCornerRadius];
	[[view layer] setMasksToBounds:YES];

	row->type = AISettingsRowTypeEdgeToEdge;
	row->fullWidthView = view;
	row->stretchesFullWidthView = YES;

	[self appendRow:row];
}

/*!
 * @brief Append a row that opens a page of its own.
 */
- (void)addNavigationRowWithLabel:(NSString *)label target:(id)target action:(SEL)action
{
	AISettingsNavigationRowView *row = [[AISettingsNavigationRowView alloc] initWithLabel:label
																				   target:target
																				   action:action];

	/* Edge to edge, so the highlight covers the card rather than stopping at the inset. Unlike a
	 * hosted list, which draws its own lines, this is one row among others and takes the card's. */
	[self addEdgeToEdgeRow:row];

	AISettingsFormSection *section = [sections lastObject];
	[[section->rows lastObject] setValue:[NSNumber numberWithBool:YES] forKey:@"wantsSeparators"];
}

- (void)addDetailRow:(NSString *)text
{
	/* An empty field is not nothing: it still measures one blank line, so a row
	 * without text would open a gap in the card. */
	if (!text.length) return;

	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

	row->type = AISettingsRowTypeDetail;
	row->detailField = AISettingsMakeDetailLabel(text);

	/* Deliberately not the control of the row: the same nil means -appendRow:
	 * finds no control to follow, so the field never dims and keeps the colour
	 * AISettingsMakeDetailLabel() gave it — right for a sentence which explains
	 * a whole card rather than one setting. */
	[self appendRow:row];
}

- (void)addEmptyStateRow:(NSString *)text
{
	/* As for a detail row: an empty field still measures one blank line, so a
	 * row without text would open a hole in the card rather than fill it. */
	if (!text.length) return;

	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

	row->type = AISettingsRowTypeEmptyState;
	row->detailField = AISettingsMakeDetailLabel(text);
	[row->detailField setAlignment:NSTextAlignmentCenter];
	/* Not selectable, unlike the sentence a detail row carries: this is the state
	 * of a list, not a text about it, and a selection highlight in the middle of
	 * an empty card reads as if something were there after all. */
	[row->detailField setSelectable:NO];

	[self appendRow:row];
}

- (void)addInfoRow:(NSString *)text withImage:(NSImage *)image
{
	[self addInfoRow:text withImage:image title:nil control:nil];
}

- (void)addInfoRow:(NSString *)text withImage:(NSImage *)image title:(NSString *)title control:(NSView *)control
{
	NSImage *symbol = AISettingsMakeInfoImage(image);

	//Nothing to show at all: an empty field still measures a blank line
	if (!text.length && !title.length && !symbol && !control) return;

	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

	row->type = AISettingsRowTypeInfo;
	/* The heading takes the row label's font rather than a section header's bold:
	 * this row usually shares its card with plain label/control rows, and a
	 * heavier heading inside the card would read as a heading for those rows
	 * instead of as the name of this one. */
	if (title.length) {
		row->labelField = AISettingsMakeLabel(title,
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor labelColor]);
	}
	if (text.length) {
		row->detailField = AISettingsMakeLabel(text,
											   [NSFont systemFontOfSize:AISettingsInfoFontSize],
											   [NSColor secondaryLabelColor]);
		//Selectable for the same reason a detail line is: an explanation is text worth copying
		[row->detailField setSelectable:YES];
	}
	row->control = control;

	/* A control showing a title of its own keeps it as its accessibility label and
	 * only takes the heading as its help text, the way a pop up row's accessory
	 * button does: a button announcing nothing but "Open" says nothing about what
	 * it opens. One without a title — a switch — is named by the heading instead. */
	AISettingsApplyAccessibility(control, title, title);

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

	[self appendRow:row];
}

- (void)addProfileHeaderWithImageView:(NSView *)imageView nameView:(NSView *)nameView button:(NSView *)button
{
	if (!imageView && !nameView && !button) return;

	AISettingsFormRow *row = [[AISettingsFormRow alloc] init];

	/* The three guests travel in the ivars the other shapes use for the same kind
	 * of thing: the picture is the row's control, the name the view which spans the
	 * row, the button its accessory. Adoption, the refresh of the guest metrics at
	 * every layout and -dealloc then all reach them without a line of their own. */
	row->type = AISettingsRowTypeProfileHeader;
	row->control = imageView;
	row->fullWidthView = nameView;
	row->accessoryControl = button;

	if (imageView) {
		/* Round, and rounded here rather than by the caller for the reason a card's
		 * corners are: the radius is the form's, so no pane picks a number half a
		 * point off the one the disc behind the picture is drawn with. Taken from the
		 * frame the picture arrives with, which is also the frame it keeps, so the
		 * circle cannot drift away from the picture afterwards. */
		NSSize	size = AISettingsControlSize(imageView);

		[imageView setFrameSize:size];
		[imageView setWantsLayer:YES];
		[[imageView layer] setCornerRadius:(MIN(size.width, size.height) / 2.0)];
		[[imageView layer] setMasksToBounds:YES];
	}

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
	[view setAutoresizingMask:NSViewNotSizable];

	/* One accessory per card, so the old strip goes wholesale; rebuilding it is
	 * also what makes switching between leading and trailing alignment work
	 * without bookkeeping which constraint is currently installed. */
	[section->accessoryWrapper removeFromSuperview];
	section->accessoryWrapper = nil;
	section->accessoryHost = nil;
	section->accessoryView = view;
	section->accessoryTrailing = trailing;

	if (view) {
		/* A card-wide strip with the accessory hanging in one corner of it: the
		 * strip takes the card's width, so leading and trailing alignment are a
		 * single constraint each, and the stack below never needs to know. */
		NSView *wrapper = [[NSView alloc] initWithFrame:NSZeroRect];
		[wrapper setTranslatesAutoresizingMaskIntoConstraints:NO];

		AISettingsGuestHostView *host = [AISettingsGuestHostView hostForGuest:view
																	   sizing:AISettingsGuestSizingKeepFrame];
		/* Aligned with one edge of the card and never resized: it keeps the size
		 * its builder gave it, so reading the frame back cannot ratchet it down. */
		[host setContentHuggingPriority:AISettingsPriorityKeepFrame forOrientation:NSLayoutConstraintOrientationHorizontal];
		[host setContentCompressionResistancePriority:AISettingsPriorityKeepFrame forOrientation:NSLayoutConstraintOrientationHorizontal];
		[wrapper addSubview:host];
		[NSLayoutConstraint activateConstraints:
		 @[[host.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
		   [host.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor],
		   (trailing ?
			[host.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor] :
			[host.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor])]];

		section->accessoryWrapper = wrapper;
		section->accessoryHost = host;

		/* Into the stack ahead of the footnote: a footnote is drawn below the
		 * accessory bar, and VoiceOver reads a container in subview order, so a
		 * footnote added first must stay behind the bar or it is announced
		 * above what it stands under. The section is always the last one —
		 * -currentSection says so — hence the end of the stack otherwise. */
		NSArray *arranged = [formStack arrangedSubviews];
		NSUInteger index = [arranged count];
		if (section->footnoteField && [arranged containsObject:section->footnoteField]) {
			index = [arranged indexOfObject:section->footnoteField];
		}
		[formStack insertArrangedSubview:wrapper atIndex:index];
		[self pinCardWidthElement:wrapper];
	}

	[self layoutForWidth:NSWidth([self frame])];
}

- (void)addFootnote:(NSString *)text
{
	AISettingsFormSection *section = [self currentSection];

	[section->footnoteField removeFromSuperview];
	//An empty field would still measure one blank line below the card
	section->footnoteField = (text.length ? AISettingsMakeDetailLabel(text) : nil);

	if (section->footnoteField) {
		/* Aligned with the card's edge rather than with the labels inside it,
		 * so a card carrying both a button bar and a footnote does not put two
		 * different left edges underneath itself. The section is the last one,
		 * so the end of the stack is the footnote's place: below the card and
		 * below the accessory bar. */
		AISettingsPrepareField(section->footnoteField);
		[formStack addArrangedSubview:section->footnoteField];
		[self pinCardWidthElement:section->footnoteField];
	}

	[self layoutForWidth:NSWidth([self frame])];
}

- (void)setLabel:(NSString *)label forRowWithControl:(NSView *)control
{
	if (!control) return;

	for (AISettingsFormSection *section in sections) {
		for (AISettingsFormRow *row in section->rows) {
			NSView *rowHostedView = (row->control ?: row->fullWidthView);

			if (!rowHostedView || !(rowHostedView == control || [control isDescendantOf:rowHostedView])) continue;

			//A row added without a label has no field to put one in
			if (!row->labelField) return;

			/* Callers retitle a row from a preference observer, which fires for
			 * every key of its group: the text is usually the one already there,
			 * and a needless layout would re-measure every pop up menu of the
			 * form and resize the pane inside its window. */
			if ([[row->labelField stringValue] isEqualToString:(label ?: @"")]) return;

			[row->labelField setStringValue:(label ?: @"")];
			if (label.length) [AISettingsPrimaryControl(rowHostedView) setAccessibilityLabel:label];

			//The new text may need more or fewer points than the old one
			[self layoutForWidth:NSWidth([self frame])];
			return;
		}
	}
}

- (void)setToolTip:(NSString *)toolTip forRowWithControl:(NSView *)control
{
	if (!control) return;

	for (AISettingsFormSection *section in sections) {
		for (AISettingsFormRow *row in section->rows) {
			NSView *rowHostedView = (row->control ?: row->fullWidthView);

			if (!rowHostedView || !(rowHostedView == control || [control isDescendantOf:rowHostedView])) continue;

			/* Everything the row draws, so the hot area is the whole line as it was
			 * in a nib, where the label was the control's own title. No layout is
			 * needed: a tool tip changes nothing that is measured. */
			[rowHostedView setToolTip:toolTip];
			[row->labelField setToolTip:toolTip];
			[row->detailField setToolTip:toolTip];
			[row->valueField setToolTip:toolTip];
			[row->accessoryControl setToolTip:toolTip];
			return;
		}
	}
}

- (void)removeAllSections
{
	for (AISettingsFormSection *section in sections) {
		//The accessory itself hangs inside its wrapper and leaves with it
		[section->headerField removeFromSuperview];
		[section->cardView removeFromSuperview];
		[section->accessoryWrapper removeFromSuperview];
		[section->footnoteField removeFromSuperview];
	}
	[sections removeAllObjects];

	[self layoutForWidth:NSWidth([self frame])];
}

#pragma mark Row shapes

/*!
 * @brief Build the constraint container for @a row.
 *
 * Everything the old -layoutRow:atY:inCardOfWidth: computed per pass is
 * declared here once, as constraints; from then on the engine keeps it true at
 * every width. The row types map onto a handful of shapes.
 */
- (void)buildViewForRow:(AISettingsFormRow *)row isFirstRowInCard:(BOOL)isFirstRowInCard
{
	AISettingsRowView *rowView = [[AISettingsRowView alloc] initWithFrame:NSZeroRect];
	[rowView setTranslatesAutoresizingMaskIntoConstraints:NO];
	row->rowView = rowView;

	switch (row->type) {
		case AISettingsRowTypeControl:		[self buildControlRow:row];		break;
		case AISettingsRowTypePopUp:		[self buildPopUpRow:row];		break;
		case AISettingsRowTypeSlider:
		case AISettingsRowTypeStretch:		[self buildSliderRow:row];		break;
		case AISettingsRowTypeRadioGroup:	[self buildRadioRow:row];		break;
		case AISettingsRowTypeFullWidth:	[self buildFullWidthRow:row];	break;
		case AISettingsRowTypeEdgeToEdge:	[self buildEdgeToEdgeRow:row];	break;
		case AISettingsRowTypeDetail:		[self buildDetailRow:row isFirstRowInCard:isFirstRowInCard]; break;
		case AISettingsRowTypeEmptyState:	[self buildEmptyStateRow:row];	break;
		case AISettingsRowTypeInfo:			[self buildInfoRow:row];		break;
		case AISettingsRowTypeProfileHeader:[self buildProfileHeaderRow:row]; break;
	}
}

/*!
 * @brief A row's minimum height, and the pull that keeps it honest.
 *
 * Every constraint above the shrinker only ever says "at least this tall"; the
 * low priority equality is what pulls the row down onto the tallest of those
 * floors, so a row is exactly 44 points or exactly its content plus padding —
 * never something in between left over from an earlier pass.
 */
- (void)constrainHeightFloorOfRow:(AISettingsRowView *)rowView
{
	[NSLayoutConstraint activateConstraints:
	 @[[rowView.heightAnchor constraintGreaterThanOrEqualToConstant:AISettingsRowMinHeight],
	   AISettingsPrioritized([rowView.heightAnchor constraintEqualToConstant:0.0], AISettingsPriorityShrinkRow)]];
}

/*!
 * @brief Label over detail line, as one block the caller centres in the row.
 *
 * A layout guide rather than a container view, so the fields stay direct
 * subviews of the row — which is what lets the row feed them their wrap width
 * back after every pass.
 */
- (NSLayoutGuide *)textBlockWithTop:(NSTextField *)topField bottom:(NSTextField *)bottomField inRow:(AISettingsRowView *)rowView
{
	NSLayoutGuide *block = [[NSLayoutGuide alloc] init];
	[rowView addLayoutGuide:block];

	AISettingsPrepareField(topField);
	[rowView addSubview:topField];
	[rowView followWidthOfField:topField];

	NSMutableArray *constraints = [NSMutableArray arrayWithObjects:
								   [topField.topAnchor constraintEqualToAnchor:block.topAnchor],
								   [topField.leadingAnchor constraintEqualToAnchor:block.leadingAnchor],
								   [topField.trailingAnchor constraintEqualToAnchor:block.trailingAnchor],
								   nil];

	if (bottomField) {
		AISettingsPrepareField(bottomField);
		[rowView addSubview:bottomField];
		[rowView followWidthOfField:bottomField];
		[constraints addObjectsFromArray:
		 @[[bottomField.topAnchor constraintEqualToAnchor:topField.bottomAnchor constant:AISettingsDetailGap],
		   [bottomField.leadingAnchor constraintEqualToAnchor:block.leadingAnchor],
		   [bottomField.trailingAnchor constraintEqualToAnchor:block.trailingAnchor],
		   [bottomField.bottomAnchor constraintEqualToAnchor:block.bottomAnchor]]];
	} else {
		[constraints addObject:[topField.bottomAnchor constraintEqualToAnchor:block.bottomAnchor]];
	}

	[NSLayoutConstraint activateConstraints:constraints];

	return block;
}

/*!
 * @brief Label on the left, the control right aligned at its natural width.
 */
- (void)buildControlRow:(AISettingsFormRow *)row
{
	AISettingsRowView	*rowView = row->rowView;
	NSMutableArray		*constraints = [NSMutableArray array];
	//Subview order is reading order: the label goes in first, as it always did
	NSLayoutGuide		*block = nil;

	if (row->labelField || row->detailField) {
		NSTextField *topField = (row->labelField ?: row->detailField);
		NSTextField *bottomField = ((row->labelField && row->detailField) ? row->detailField : nil);

		block = [self textBlockWithTop:topField bottom:bottomField inRow:rowView];
	}

	if (row->control) {
		AISettingsGuestHostView *host = [AISettingsGuestHostView hostForGuest:row->control
																	   sizing:AISettingsGuestSizingNatural];
		row->controlHost = host;
		/* The natural width as a pair of priorities: hugging keeps the control
		 * from ever growing past it, compression lets a narrow card take width
		 * away — and since the natural size is remembered in the host, the
		 * control grows back the moment there is room again. */
		[host setContentHuggingPriority:AISettingsPriorityNaturalCap forOrientation:NSLayoutConstraintOrientationHorizontal];
		[host setContentCompressionResistancePriority:AISettingsPriorityNaturalWidth forOrientation:NSLayoutConstraintOrientationHorizontal];
		[rowView addSubview:host];

		[constraints addObjectsFromArray:
		 @[[host.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH],
		   [host.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
		   [host.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV],
		   //Whatever the priorities below decide, the card's inner width is a hard wall
		   [host.leadingAnchor constraintGreaterThanOrEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH],
		   //A wide control gives way before the label column falls below its minimum...
		   AISettingsPrioritized([host.widthAnchor constraintLessThanOrEqualToAnchor:rowView.widthAnchor
																			constant:-(2.0 * AISettingsCardInsetH + AISettingsLabelControlGap + AISettingsMinLabelWidth)],
								 AISettingsPriorityLabelReserve),
		   //...but never below a usable floor, which a naturally narrow control ignores (its hugging outranks this)
		   AISettingsPrioritized([host.widthAnchor constraintGreaterThanOrEqualToConstant:60.0],
								 AISettingsPriorityControlFloor)]];
	}

	if (block) {
		[constraints addObjectsFromArray:
		 @[[block.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH],
		   [block.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
		   [block.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV]]];

		if (row->controlHost) {
			/* The label column is as wide as the row leaves it — that width is
			 * also the tool tip's hot area — but stretching it must never be a
			 * reason to squeeze the control, hence below NaturalWidth. */
			[constraints addObjectsFromArray:
			 @[[block.trailingAnchor constraintLessThanOrEqualToAnchor:row->controlHost.leadingAnchor
															  constant:-AISettingsLabelControlGap],
			   AISettingsPrioritized([block.trailingAnchor constraintEqualToAnchor:row->controlHost.leadingAnchor
																		  constant:-AISettingsLabelControlGap],
									 AISettingsPriorityLabelFill)]];
		} else {
			[constraints addObject:[block.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor
																		constant:-AISettingsCardInsetH]];
		}
	}

	[NSLayoutConstraint activateConstraints:constraints];
	[self constrainHeightFloorOfRow:rowView];
}

/*!
 * @brief Label, pop up button and optional accessory button at the trailing edge.
 */
- (void)buildPopUpRow:(AISettingsFormRow *)row
{
	AISettingsRowView	*rowView = row->rowView;
	NSMutableArray		*constraints = [NSMutableArray array];

	//Subview order is reading order: label, accessory, menu — as it always was
	if (row->labelField) {
		AISettingsPrepareField(row->labelField);
		[rowView addSubview:row->labelField];
		[rowView followWidthOfField:row->labelField];
	}

	if (row->accessoryControl) {
		AISettingsGuestHostView *accessory = [AISettingsGuestHostView hostForGuest:row->accessoryControl
																			sizing:AISettingsGuestSizingKeepFrame];
		row->accessoryHost = accessory;
		//The accessory is never resized; in a card too narrow for both, the menu gives way
		[accessory setContentHuggingPriority:AISettingsPriorityKeepFrame forOrientation:NSLayoutConstraintOrientationHorizontal];
		[accessory setContentCompressionResistancePriority:AISettingsPriorityKeepFrame forOrientation:NSLayoutConstraintOrientationHorizontal];
		[rowView addSubview:accessory];

		[constraints addObjectsFromArray:
		 @[[accessory.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH],
		   [accessory.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
		   [accessory.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV]]];
	}

	AISettingsGuestHostView *popUp = [AISettingsGuestHostView hostForGuest:row->control
																	sizing:AISettingsGuestSizingNatural];
	row->controlHost = popUp;
	/* Natural width as priorities, exactly as in a control row — but the
	 * natural size itself is re-measured from the menu at every layout, in
	 * -refreshGuestMetricsForCardWidth:. */
	[popUp setContentHuggingPriority:AISettingsPriorityNaturalCap forOrientation:NSLayoutConstraintOrientationHorizontal];
	[popUp setContentCompressionResistancePriority:AISettingsPriorityNaturalWidth forOrientation:NSLayoutConstraintOrientationHorizontal];
	[rowView addSubview:popUp];

	[constraints addObjectsFromArray:
	 @[(row->accessoryHost ?
		[popUp.trailingAnchor constraintEqualToAnchor:row->accessoryHost.leadingAnchor constant:-AISettingsControlGap] :
		[popUp.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH]),
	   [popUp.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
	   [popUp.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV],
	   [popUp.leadingAnchor constraintGreaterThanOrEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH],
	   //A minimum for the menu, not a licence to overrun the card: the required pins above win
	   AISettingsPrioritized([popUp.widthAnchor constraintGreaterThanOrEqualToConstant:40.0],
							 AISettingsPriorityControlFloor)]];

	if (row->labelField) {
		[constraints addObjectsFromArray:
		 @[[row->labelField.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH],
		   [row->labelField.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
		   [row->labelField.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV],
		   [row->labelField.trailingAnchor constraintLessThanOrEqualToAnchor:popUp.leadingAnchor
																	constant:-AISettingsLabelControlGap],
		   AISettingsPrioritized([row->labelField.trailingAnchor constraintEqualToAnchor:popUp.leadingAnchor
																				constant:-AISettingsLabelControlGap],
								 AISettingsPriorityLabelFill),
		   //A wide menu gives way before the label column falls below its minimum
		   AISettingsPrioritized([row->labelField.widthAnchor constraintGreaterThanOrEqualToConstant:AISettingsMinLabelWidth],
								 AISettingsPriorityLabelReserve)]];
	}

	[NSLayoutConstraint activateConstraints:constraints];
	[self constrainHeightFloorOfRow:rowView];
}

/*!
 * @brief Label column, stretching control, optional readout column.
 *
 * Serves sliders and stretching rows alike: the two are the same shape, and a
 * stretching row is one without a readout, so its control runs to the card's
 * inset. The label and readout widths are the card-wide shared columns whose
 * constants -refreshGuestMetricsForCardWidth: keeps up to date.
 */
- (void)buildSliderRow:(AISettingsFormRow *)row
{
	AISettingsRowView	*rowView = row->rowView;
	NSMutableArray		*constraints = [NSMutableArray array];

	if (row->labelField) {
		AISettingsPrepareField(row->labelField);
		/* A label pressed below the width its text needs is truncated, not
		 * wrapped: wrapping would turn a long label into a column of single
		 * syllables and blow the row up to ten lines. Within the column it
		 * always fits on one line, so nothing is lost by never wrapping. */
		[[row->labelField cell] setWraps:NO];
		[row->labelField setLineBreakMode:NSLineBreakByTruncatingTail];
		[rowView addSubview:row->labelField];

		row->labelColumnConstraint = [row->labelField.widthAnchor constraintEqualToConstant:0.0];
		[row->labelColumnConstraint setPriority:AISettingsPrioritySliderLabelColumn];

		/* Beside the control's top line for a tall control, beside its middle otherwise: a
		 * label centred against a text editor floats halfway down an empty box. Both keep the
		 * same top floor, so a one-line control looks identical either way. */
		NSLayoutConstraint *labelVertical = (row->labelTopAligned ?
			[row->labelField.topAnchor constraintEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV] :
			[row->labelField.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor]);

		[constraints addObjectsFromArray:
		 @[[row->labelField.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH],
		   labelVertical,
		   [row->labelField.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV],
		   row->labelColumnConstraint]];
	}

	if (row->valueField) {
		AISettingsGuestHostView *value = [AISettingsGuestHostView hostForGuest:row->valueField
																		sizing:AISettingsGuestSizingStretch];
		row->valueHost = value;
		[rowView addSubview:value];

		/* The readout is stretched to the shared column; its text is right
		 * aligned, so a wider column still ends at the card's inset. */
		row->valueColumnConstraint = [value.widthAnchor constraintEqualToConstant:0.0];
		[row->valueColumnConstraint setPriority:AISettingsPriorityValueColumn];

		[constraints addObjectsFromArray:
		 @[[value.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH],
		   [value.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
		   [value.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV],
		   row->valueColumnConstraint]];
	}

	AISettingsGuestHostView *host = [AISettingsGuestHostView hostForGuest:row->control
																   sizing:AISettingsGuestSizingStretch];
	row->controlHost = host;
	[rowView addSubview:host];

	/* Uncapped, the slider fills the span between the label and the readout by pinning to both.
	 * Capped, it takes a fixed width against the readout and lets the gap open on the label side,
	 * so it sits at a moderate length on the right rather than running the whole card - the shape
	 * a short control has. The leading pin loosens to >= so there is somewhere for that gap to go. */
	BOOL capped = (maximumSliderWidth > 0.0);

	[constraints addObjectsFromArray:
	 @[(row->labelField ?
		(capped ?
		 [host.leadingAnchor constraintGreaterThanOrEqualToAnchor:row->labelField.trailingAnchor constant:AISettingsLabelControlGap] :
		 [host.leadingAnchor constraintEqualToAnchor:row->labelField.trailingAnchor constant:AISettingsLabelControlGap]) :
		(capped ?
		 [host.leadingAnchor constraintGreaterThanOrEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH] :
		 [host.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH])),
	   (row->valueHost ?
		[host.trailingAnchor constraintEqualToAnchor:row->valueHost.leadingAnchor constant:-AISettingsLabelControlGap] :
		[host.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH]),
	   [host.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
	   [host.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV],
	   /* A narrow card shortens the label rather than the slider: this outranks
		* the label column, so the column's equality is what breaks first. */
	   AISettingsPrioritized([host.widthAnchor constraintGreaterThanOrEqualToConstant:AISettingsSliderMinWidth],
							 AISettingsPrioritySliderMinWidth)]];

	if (capped) {
		//At the cap when there is room, giving way only if the card cannot even spare that much
		[constraints addObject:AISettingsPrioritized([host.widthAnchor constraintEqualToConstant:maximumSliderWidth],
													  AISettingsPrioritySliderCap)];
	}

	[NSLayoutConstraint activateConstraints:constraints];
	[self constrainHeightFloorOfRow:rowView];
}

/*!
 * @brief Label on top, the radio button column below it.
 */
- (void)buildRadioRow:(AISettingsFormRow *)row
{
	AISettingsRowView	*rowView = row->rowView;
	NSMutableArray		*constraints = [NSMutableArray array];
	//The 2 point nudge keeps the group clear of the hairline, as it always did
	CGFloat				 insetV = AISettingsRowInsetV + 2.0;

	if (row->labelField) {
		AISettingsPrepareField(row->labelField);
		[rowView addSubview:row->labelField];
		[rowView followWidthOfField:row->labelField];

		[constraints addObjectsFromArray:
		 @[[row->labelField.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH],
		   [row->labelField.topAnchor constraintEqualToAnchor:rowView.topAnchor constant:insetV],
		   [row->labelField.trailingAnchor constraintLessThanOrEqualToAnchor:rowView.trailingAnchor
																	constant:-AISettingsCardInsetH],
		   AISettingsPrioritized([row->labelField.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor
																				constant:-AISettingsCardInsetH],
								 AISettingsPriorityLabelFill)]];
	}

	AISettingsGuestHostView *host = [AISettingsGuestHostView hostForGuest:row->radioContainer
																   sizing:AISettingsGuestSizingStretch];
	row->radioHost = host;
	[rowView addSubview:host];

	[constraints addObjectsFromArray:
	 @[[host.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH],
	   [host.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH],
	   (row->labelField ?
		[host.topAnchor constraintEqualToAnchor:row->labelField.bottomAnchor constant:AISettingsRadioTopGap] :
		[host.topAnchor constraintEqualToAnchor:rowView.topAnchor constant:insetV]),
	   [host.bottomAnchor constraintLessThanOrEqualToAnchor:rowView.bottomAnchor constant:-insetV]]];

	[NSLayoutConstraint activateConstraints:constraints];
	[self constrainHeightFloorOfRow:rowView];
}

/*!
 * @brief A view spanning the card's inner width — or keeping its own.
 *
 * Top aligned rather than centred, as the frame based machine had it: a short
 * bar in a minimum height row sits at the standard top inset.
 */
- (void)buildFullWidthRow:(AISettingsFormRow *)row
{
	AISettingsRowView		*rowView = row->rowView;
	AISettingsGuestHostView	*host = [AISettingsGuestHostView hostForGuest:row->fullWidthView
																   sizing:(row->stretchesFullWidthView ?
																		   AISettingsGuestSizingStretch :
																		   AISettingsGuestSizingNatural)];
	row->fullWidthHost = host;
	[rowView addSubview:host];

	NSMutableArray *constraints = [NSMutableArray arrayWithObjects:
								   [host.topAnchor constraintEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV],
								   [host.bottomAnchor constraintLessThanOrEqualToAnchor:rowView.bottomAnchor constant:-AISettingsRowInsetV],
								   nil];

	if (row->stretchesFullWidthView) {
		[constraints addObject:[host.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH]];
		[constraints addObject:[host.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH]];
	} else {
		//Its own width, capped at the card: a push button is not stretched across a card
		[host setContentHuggingPriority:AISettingsPriorityNaturalCap forOrientation:NSLayoutConstraintOrientationHorizontal];
		[host setContentCompressionResistancePriority:AISettingsPriorityNaturalWidth forOrientation:NSLayoutConstraintOrientationHorizontal];

		//Anchored to one edge, held inside the card at the other
		if (row->trailingAlignsFullWidthView) {
			[constraints addObject:[host.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH]];
			[constraints addObject:[host.leadingAnchor constraintGreaterThanOrEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH]];
		} else {
			[constraints addObject:[host.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH]];
			[constraints addObject:[host.trailingAnchor constraintLessThanOrEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH]];
		}
	}

	[NSLayoutConstraint activateConstraints:constraints];
	[self constrainHeightFloorOfRow:rowView];
}

/*!
 * @brief The view is the card: all four edges, no padding, no minimum height.
 */
- (void)buildEdgeToEdgeRow:(AISettingsFormRow *)row
{
	AISettingsRowView		*rowView = row->rowView;
	AISettingsGuestHostView	*host = [AISettingsGuestHostView hostForGuest:row->fullWidthView
																   sizing:AISettingsGuestSizingStretch];
	row->fullWidthHost = host;
	[rowView addSubview:host];

	//The hosted view's own height is the row height; it decides how tall the card is
	[NSLayoutConstraint activateConstraints:
	 @[[host.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor],
	   [host.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor],
	   [host.topAnchor constraintEqualToAnchor:rowView.topAnchor],
	   [host.bottomAnchor constraintEqualToAnchor:rowView.bottomAnchor]]];
}

/*!
 * @brief A block of explanation, hugging the row above it.
 *
 * No minimum height — a 44 point row around one 15 point line would be a hole
 * in the card — and no shrinker either: both edges are pinned, so the row is
 * exactly its text plus the padding. Opening a card it takes the card's own
 * top padding instead of clinging to a row that is not there.
 */
- (void)buildDetailRow:(AISettingsFormRow *)row isFirstRowInCard:(BOOL)isFirstRowInCard
{
	AISettingsRowView	*rowView = row->rowView;

	AISettingsPrepareField(row->detailField);
	[rowView addSubview:row->detailField];
	[rowView followWidthOfField:row->detailField];

	[NSLayoutConstraint activateConstraints:
	 @[[row->detailField.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH],
	   [row->detailField.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH],
	   [row->detailField.topAnchor constraintEqualToAnchor:rowView.topAnchor
												  constant:(isFirstRowInCard ? AISettingsRowInsetV : AISettingsDetailGap)],
	   [row->detailField.bottomAnchor constraintEqualToAnchor:rowView.bottomAnchor constant:-AISettingsRowInsetV]]];
}

/*!
 * @brief Centred text standing in for the rows a list does not have yet.
 */
- (void)buildEmptyStateRow:(AISettingsFormRow *)row
{
	AISettingsRowView	*rowView = row->rowView;

	AISettingsPrepareField(row->detailField);
	[rowView addSubview:row->detailField];
	[rowView followWidthOfField:row->detailField];

	//A whole control row's height, so the card reads as an empty list, not as prose
	[NSLayoutConstraint activateConstraints:
	 @[[row->detailField.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH],
	   [row->detailField.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH],
	   [row->detailField.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
	   [row->detailField.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV]]];
	[self constrainHeightFloorOfRow:rowView];
}

/*!
 * @brief Picture, heading over paragraph, optional control — all centred.
 */
- (void)buildInfoRow:(AISettingsFormRow *)row
{
	AISettingsRowView	*rowView = row->rowView;
	NSMutableArray		*constraints = [NSMutableArray array];
	/* The text begins at the far side of the whole 40 point square, not of this
	 * particular picture: only one edge of a scaled picture lands on the
	 * square, so a portrait one is 36 points wide and a landscape one 40, and
	 * two info rows in a card would otherwise start their paragraphs at two
	 * different x — the same misalignment the shared slider label column exists
	 * to prevent. The picture is centred in that column. */
	CGFloat				 leadingColumn = (row->imageView ? AISettingsInfoImageSize + AISettingsLabelControlGap : 0.0);
	//Subview order is reading order: the text goes in first, the picture is not read at all
	NSLayoutGuide		*block = nil;

	if (row->labelField || row->detailField) {
		NSTextField *topField = (row->labelField ?: row->detailField);
		NSTextField *bottomField = ((row->labelField && row->detailField) ? row->detailField : nil);

		block = [self textBlockWithTop:topField bottom:bottomField inRow:rowView];
	}

	if (row->imageView) {
		NSSize symbolSize = [[row->imageView image] size];

		[row->imageView setTranslatesAutoresizingMaskIntoConstraints:NO];
		[rowView addSubview:row->imageView];
		[constraints addObjectsFromArray:
		 @[[row->imageView.widthAnchor constraintEqualToConstant:symbolSize.width],
		   [row->imageView.heightAnchor constraintEqualToConstant:symbolSize.height],
		   [row->imageView.centerXAnchor constraintEqualToAnchor:rowView.leadingAnchor
														constant:AISettingsCardInsetH + AISettingsInfoImageSize / 2.0],
		   [row->imageView.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
		   [row->imageView.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV]]];
	}

	if (row->control) {
		AISettingsGuestHostView *host = [AISettingsGuestHostView hostForGuest:row->control
																	   sizing:AISettingsGuestSizingNatural];
		row->controlHost = host;
		//Natural width as priorities, exactly as in a control row
		[host setContentHuggingPriority:AISettingsPriorityNaturalCap forOrientation:NSLayoutConstraintOrientationHorizontal];
		[host setContentCompressionResistancePriority:AISettingsPriorityNaturalWidth forOrientation:NSLayoutConstraintOrientationHorizontal];
		[rowView addSubview:host];

		[constraints addObjectsFromArray:
		 @[[host.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH],
		   [host.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
		   [host.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV],
		   [host.leadingAnchor constraintGreaterThanOrEqualToAnchor:rowView.leadingAnchor
															constant:AISettingsCardInsetH + leadingColumn],
		   AISettingsPrioritized([host.widthAnchor constraintGreaterThanOrEqualToConstant:60.0],
								 AISettingsPriorityControlFloor)]];
	}

	if (block) {
		[constraints addObjectsFromArray:
		 @[[block.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor
											   constant:AISettingsCardInsetH + leadingColumn],
		   [block.centerYAnchor constraintEqualToAnchor:rowView.centerYAnchor],
		   [block.topAnchor constraintGreaterThanOrEqualToAnchor:rowView.topAnchor constant:AISettingsRowInsetV],
		   (row->controlHost ?
			[block.trailingAnchor constraintEqualToAnchor:row->controlHost.leadingAnchor constant:-AISettingsLabelControlGap] :
			[block.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH]),
		   /* A button wider than what the paragraph can spare gives way, so the
			* text is never squeezed into a column of syllables. */
		   AISettingsPrioritized([block.widthAnchor constraintGreaterThanOrEqualToConstant:AISettingsMinLabelWidth],
								 AISettingsPriorityLabelReserve)]];
	}

	[NSLayoutConstraint activateConstraints:constraints];
	[self constrainHeightFloorOfRow:rowView];
}

/*!
 * @brief A round picture, the name under it and the button which changes it.
 *
 * All three are optional and all three are centred, so the row is built from top
 * to bottom against a moving anchor rather than against three fixed ones: each
 * element hangs from whatever stood above it, and the last one gives the row its
 * height. The picture and the button keep their own size; only the name is
 * stretched, which is what makes text centred inside it sit on the middle of the
 * card instead of on the middle of the name.
 */
- (void)buildProfileHeaderRow:(AISettingsFormRow *)row
{
	AISettingsRowView	*rowView = row->rowView;
	NSMutableArray		*constraints = [NSMutableArray array];
	//What the next element hangs from, and how far below it
	NSLayoutYAxisAnchor	*previousBottom = rowView.topAnchor;
	CGFloat				 gap = AISettingsProfileTopInset;

	if (row->control) {
		NSSize					 size = [row->control frame].size;
		CGFloat					 radius = MIN(size.width, size.height) / 2.0;
		NSBox					*disc = [[NSBox alloc] initWithFrame:NSZeroRect];
		AISettingsGuestHostView	*host = [AISettingsGuestHostView hostForGuest:row->control
																	   sizing:AISettingsGuestSizingKeepFrame];

		/* What the picture is centred on. A picture which is not square fills only
		 * part of the circle it is clipped to, and a user who has set no picture at
		 * all fills none of it, so without something behind it the header would show
		 * the card through a hole shaped like the missing photograph. An NSBox rather
		 * than a layer of the form's own: a layer's colour is a CGColor, which would
		 * keep the light appearance's grey after the user switches to the dark one. */
		[disc setBoxType:NSBoxCustom];
		[disc setBorderWidth:0.0];
		[disc setTitlePosition:NSNoTitle];
		[disc setFillColor:[NSColor quaternaryLabelColor]];
		[disc setCornerRadius:radius];
		[disc setTranslatesAutoresizingMaskIntoConstraints:NO];
		//It says nothing the picture in front of it does not; that one is the control
		[disc setAccessibilityElement:NO];

		row->controlHost = host;
		//Behind the picture, which is what adding it first means
		[rowView addSubview:disc];
		[rowView addSubview:host];

		[constraints addObjectsFromArray:
		 @[[host.centerXAnchor constraintEqualToAnchor:rowView.centerXAnchor],
		   [host.topAnchor constraintEqualToAnchor:previousBottom constant:gap],
		   [disc.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
		   [disc.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
		   [disc.topAnchor constraintEqualToAnchor:host.topAnchor],
		   [disc.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]]];

		previousBottom = host.bottomAnchor;
		gap = AISettingsProfileNameGap;
	}

	if (row->fullWidthView) {
		AISettingsGuestHostView *host = [AISettingsGuestHostView hostForGuest:row->fullWidthView
																	   sizing:AISettingsGuestSizingStretch];
		row->fullWidthHost = host;
		[rowView addSubview:host];

		[constraints addObjectsFromArray:
		 @[[host.leadingAnchor constraintEqualToAnchor:rowView.leadingAnchor constant:AISettingsCardInsetH],
		   [host.trailingAnchor constraintEqualToAnchor:rowView.trailingAnchor constant:-AISettingsCardInsetH],
		   [host.topAnchor constraintEqualToAnchor:previousBottom constant:gap]]];

		previousBottom = host.bottomAnchor;
		gap = AISettingsProfileButtonGap;
	}

	if (row->accessoryControl) {
		AISettingsGuestHostView *host = [AISettingsGuestHostView hostForGuest:row->accessoryControl
																	   sizing:AISettingsGuestSizingKeepFrame];
		row->accessoryHost = host;
		/* Never resized, as an accessory bar under a card is not: it keeps the size
		 * its builder gave it, and nothing here pins it to an edge, so a card too
		 * narrow for it cannot turn into a broken layout either. */
		[host setContentHuggingPriority:AISettingsPriorityKeepFrame forOrientation:NSLayoutConstraintOrientationHorizontal];
		[host setContentCompressionResistancePriority:AISettingsPriorityKeepFrame forOrientation:NSLayoutConstraintOrientationHorizontal];
		[rowView addSubview:host];

		[constraints addObjectsFromArray:
		 @[[host.centerXAnchor constraintEqualToAnchor:rowView.centerXAnchor],
		   [host.topAnchor constraintEqualToAnchor:previousBottom constant:gap]]];

		previousBottom = host.bottomAnchor;
	}

	//A floor rather than an equality, so the shrinker pulls the row exactly onto its content
	[constraints addObject:[previousBottom constraintLessThanOrEqualToAnchor:rowView.bottomAnchor
																   constant:-AISettingsProfileTopInset]];

	[NSLayoutConstraint activateConstraints:constraints];
	[self constrainHeightFloorOfRow:rowView];
}

#pragma mark Layout

- (CGFloat)totalHeight
{
	if (needsFormLayout) [self layoutForWidth:NSWidth([self frame])];
	return contentHeight;
}

- (void)noteContentSizeChanged
{
	/* The hosts re-read every guest's frame in the next pass, so laying out
	 * again is all it takes: the grown list becomes its host's new intrinsic
	 * height, the card follows, the form follows, the document height follows. */
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

	[self updateStackSpacing];
	[self refreshGuestMetricsForCardWidth:cardWidth];

	if (fabs([formWidthConstraint constant] - width) > 0.5) [formWidthConstraint setConstant:width];

	/* Two passes: the first resolves the widths, and on its way out hands every
	 * wrapping field the width it actually got (see AISettingsRowView); the
	 * second resolves the heights of the text that refolded to those widths.
	 * Heights never feed back into widths here, so two passes settle it. */
	[self layoutSubtreeIfNeeded];
	[self layoutSubtreeIfNeeded];

	[self updateCardSeparators];

	//The whole point of the stack: the content height is read, not added up
	contentHeight = ceil(NSHeight([formStack frame]));

	if (fabs(NSWidth([self frame]) - width) > 0.5 || fabs(NSHeight([self frame]) - contentHeight) > 0.5) {
		//Bypasses our own -setFrameSize: so this cannot recurse
		[super setFrameSize:NSMakeSize(width, contentHeight)];
	}

	[self updateEnclosingDocumentViewHeight];
	[self setNeedsDisplay:YES];
}

/*!
 * @brief Everything a layout pass must re-read before the engine runs.
 *
 * The one place where guest frames meet the constraint world: pop up menus are
 * re-measured, self resized guests become their host's new intrinsic height,
 * and the shared slider columns get their constants. All of it happens before
 * -layoutSubtreeIfNeeded, so the engine sees one consistent picture.
 */
- (void)refreshGuestMetricsForCardWidth:(CGFloat)cardWidth
{
	CGFloat sliderInnerWidth = cardWidth - 2.0 * AISettingsCardInsetH;
	CGFloat sharedColumn = 0.0;

	/* One column for the whole form rather than one per card: every field that takes what its row
	 * leaves then starts at the same x and ends at the same inset, so they are all the same width. */
	if (sharesLabelColumn) {
		for (AISettingsFormSection *section in sections) {
			for (AISettingsFormRow *row in section->rows) {
				if (row->type != AISettingsRowTypeSlider && row->type != AISettingsRowTypeStretch) continue;

				if (row->labelField)
					sharedColumn = MAX(sharedColumn, ceil([[row->labelField cell] cellSize].width));
			}
		}

		//Only the cap follows the card's width; the text width itself never shrinks again
		sharedLabelNatural = MAX(sharedLabelNatural, sharedColumn);
		sharedColumn = MIN(sharedLabelNatural, floor(sliderInnerWidth * AISettingsSliderLabelMax));
	}

	for (AISettingsFormSection *section in sections) {
		//Headers and footnotes wrap at the card's width, which is known up front
		if (section->headerField) [section->headerField setPreferredMaxLayoutWidth:cardWidth];
		if (section->footnoteField) [section->footnoteField setPreferredMaxLayoutWidth:cardWidth];
		[section->accessoryHost refreshGuestMetrics];

		/* Slider rows of one card share a label and a readout column, the way
		 * System Settings lines its sliders up: otherwise "Opacity" and "Maximum
		 * Width" would start their sliders at two different x, and retitling one
		 * of them would shift its slider while the user works two rows above.
		 * Stretching rows are built as slider rows and share the columns with
		 * them, so a card mixing both still has one label column. */
		CGFloat labelColumn = 0.0;
		CGFloat valueColumn = 0.0;
		for (AISettingsFormRow *row in section->rows) {
			if (row->type != AISettingsRowTypeSlider && row->type != AISettingsRowTypeStretch) continue;

			if (row->labelField) labelColumn = MAX(labelColumn, ceil([[row->labelField cell] cellSize].width));
			if (row->valueField) valueColumn = MAX(valueColumn, AISettingsControlSize(row->valueField).width);
		}
		//Only the cap follows the card's width; the text width itself never shrinks again
		section->sliderLabelNatural = MAX(section->sliderLabelNatural, labelColumn);
		labelColumn = MIN(section->sliderLabelNatural, floor(sliderInnerWidth * AISettingsSliderLabelMax));

		if (sharesLabelColumn)
			labelColumn = sharedColumn;

		for (AISettingsFormRow *row in section->rows) {
			if (row->type == AISettingsRowTypePopUp) {
				/* The menu decides how wide the button wants to be, and it may
				 * have been rebuilt since the last pass, so ask again every time
				 * — wider or narrower, unlike the ratchet every other control
				 * rides on. */
				[(NSControl *)row->control sizeToFit];
				[row->controlHost resetNaturalSize];
			} else {
				[row->controlHost refreshGuestMetrics];
			}
			if (row->labelColumnConstraint) [row->labelColumnConstraint setConstant:labelColumn];
			if (row->valueColumnConstraint) [row->valueColumnConstraint setConstant:valueColumn];
			[row->accessoryHost refreshGuestMetrics];
			[row->valueHost refreshGuestMetrics];
			[row->radioHost refreshGuestMetrics];
			[row->fullWidthHost refreshGuestMetrics];
		}
	}
}

/*!
 * @brief Keep the stack's gaps true to the section structure.
 *
 * The gaps of the old machine, expressed as custom spacing: a header hangs
 * eight points over its card, an accessory or footnote eight points under it,
 * and a section keeps twenty-two points of air in front of a headed successor
 * but only twelve in front of a bare card. Empty sections — endCard leaves one
 * behind by design — are hidden, which detaches them from the stack entirely,
 * so they cost no gap either.
 */
- (void)updateStackSpacing
{
	NSMutableArray *visibleSections = [NSMutableArray array];

	for (AISettingsFormSection *section in sections) {
		BOOL visible = ([section->rows count] || section->headerField || section->accessoryView || section->footnoteField);
		[section->cardView setHidden:!visible];
		if (visible) [visibleSections addObject:section];
	}

	NSUInteger count = [visibleSections count];
	for (NSUInteger index = 0; index < count; index++) {
		AISettingsFormSection	*section = [visibleSections objectAtIndex:index];
		AISettingsFormSection	*next = (index + 1 < count ? [visibleSections objectAtIndex:index + 1] : nil);
		NSView					*lastView = (section->footnoteField ?
											 (NSView *)section->footnoteField :
											 (section->accessoryWrapper ?: (NSView *)section->cardView));
		//The air in front of the next section belongs to this one's last view
		CGFloat					 trailingGap = (next ? (next->headerField ? AISettingsSectionGap : AISettingsCardGap) : 0.0);

		if (section->headerField) [formStack setCustomSpacing:AISettingsHeaderGap afterView:section->headerField];
		if ((NSView *)section->cardView != lastView) {
			[formStack setCustomSpacing:AISettingsAccessoryGap afterView:section->cardView];
		}
		if (section->accessoryWrapper && section->accessoryWrapper != lastView) {
			[formStack setCustomSpacing:AISettingsAccessoryGap afterView:section->accessoryWrapper];
		}
		[formStack setCustomSpacing:trailingGap afterView:lastView];
	}
}

/*!
 * @brief Tell every card where its hairlines go.
 *
 * The dividers are read off the rows' resolved frames after a pass instead of
 * being views of their own: a separator view in the stack would add its point
 * to the card's height, while the frame based machine always drew the line
 * <em>on</em> the boundary. The rules are unchanged: a line between two rows,
 * none against an edge to edge row — a hosted list draws its own — and none
 * above a detail row, whose text belongs to the row it stands under.
 */
- (void)updateCardSeparators
{
	for (AISettingsFormSection *section in sections) {
		NSMutableArray		*positions = [NSMutableArray array];
		AISettingsFormRow	*previous = nil;

		for (AISettingsFormRow *row in section->rows) {
			if (previous &&
				(row->type != AISettingsRowTypeEdgeToEdge || row->wantsSeparators) &&
				(previous->type != AISettingsRowTypeEdgeToEdge || previous->wantsSeparators) &&
				row->type != AISettingsRowTypeDetail &&
				[row->rowView superview]) {
				NSRect rowFrame = [section->cardView convertRect:[row->rowView frame]
														fromView:[row->rowView superview]];
				[positions addObject:[NSNumber numberWithDouble:NSMinY(rowFrame)]];
			}
			previous = row;
		}

		[section->cardView setSeparatorPositions:([positions count] ? positions : nil)];
	}
}

- (void)layout
{
	[super layout];
	/* Engine passes the form did not start — an intrinsic size invalidated by
	 * AppKit itself, say — still move rows, and the hairlines have to follow. */
	[self updateCardSeparators];
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
	/* Minus the top inset, or a form that fits could still travel by exactly that inset: the
	 * inset is part of the scrollable range, and a document as tall as the clip view scrolls
	 * up under the title bar with blank space following it. Same arithmetic as
	 * -[AIModernPreferencesWindowController layoutCurrentPane]; they take turns setting this
	 * height and must agree, or every pass undoes the other's. */
	CGFloat needed = MAX(NSHeight([self frame]) + 2.0 * padding,
						 [scrollView contentSize].height - [scrollView contentInsets].top);

	if (fabs(needed - NSHeight([documentView frame])) > 0.5) {
		[documentView setFrameSize:NSMakeSize(NSWidth([documentView frame]), needed)];
	}
}

- (void)setFrameSize:(NSSize)newSize
{
	BOOL widthChanged = (fabs(newSize.width - NSWidth([self frame])) > 0.5);
	/* The height is not the caller's to choose: it is what the cards add up to, and only a
	 * layout pass may set it. Heights get imposed on us regardless - a superview resizing with
	 * no flexible vertical spring on us scales every subview proportionally, which pressed a
	 * form down to the clip height and cut everything below it off, with nothing ever putting
	 * it right because only a width change used to earn a new layout. Accepting the size and
	 * laying out again is the correction: -layoutForWidth: ends by restoring the computed
	 * height through [super setFrameSize:], which cannot come back through here. */
	BOOL heightImposed = (contentHeight > 0.5 && fabs(newSize.height - contentHeight) > 0.5);

	[super setFrameSize:newSize];

	if (widthChanged || heightImposed || needsFormLayout) [self layoutForWidth:newSize.width];
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	if (needsFormLayout) [self layoutForWidth:NSWidth([self frame])];
}

#pragma mark Control factories

+ (NSSwitch *)switchWithTarget:(id)target action:(SEL)action
{
	NSSwitch *control = [[NSSwitch alloc] initWithFrame:NSZeroRect];

	//System Settings uses the small switch, not the regular one
	[control setControlSize:NSControlSizeSmall];
	[control setTarget:target];
	[control setAction:action];
	[control setFrameSize:[control fittingSize]];

	return control;
}

+ (NSPopUpButton *)popUpButtonWithTitles:(NSArray *)titles target:(id)target action:(SEL)action
{
	NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];

	for (NSString *title in titles) [popUp addItemWithTitle:title];
	[popUp setTarget:target];
	[popUp setAction:action];
	[popUp sizeToFit];

	return popUp;
}

+ (NSButton *)radioButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action
{
	NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];

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
	NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];

	[button setBezelStyle:NSBezelStyleRounded];
	[button setButtonType:NSButtonTypeMomentaryPushIn];
	[button setTitle:(title ?: @"")];
	[button setFont:[NSFont systemFontOfSize:AISettingsLabelFontSize]];
	[button setTarget:target];
	[button setAction:action];
	[button sizeToFit];

	return button;
}

+ (NSImage *)disclosureIndicatorImage
{
	NSImage *image = nil;

	if (@available(macOS 11.0, *)) {
		image = [NSImage imageWithSystemSymbolName:@"chevron.forward"
						  accessibilityDescription:nil];
		/* Smaller than the symbols that sit in a row as controls. This one is a signpost, not
		 * something to aim at, and at the inline size it reads as heavy beside the system's own. */
		image = [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:AISettingsDisclosureSymbolSize
																								   weight:NSFontWeightSemibold]];
	}

	if (!image)
		image = [NSImage imageNamed:NSImageNameGoRightTemplate];

	[image setTemplate:YES];

	return image;
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

	NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0,
																   AISettingsInlineButtonSize,
																   AISettingsInlineButtonSize)];

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
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];

	[field setFont:[NSFont systemFontOfSize:AISettingsLabelFontSize]];
	[field setAlignment:NSTextAlignmentRight];
	[field setTarget:target];
	[field setAction:action];
	/* Return alone is not enough here either: a port typed into this field and left behind by a click
	 * elsewhere used to be dropped without a word, and the setting kept whatever it had before. */
	[[field cell] setSendsActionOnEndEditing:YES];
	[field sizeToFit];
	[field setFrameSize:NSMakeSize(width, NSHeight([field frame]))];

	return field;
}

+ (NSTextField *)textFieldWithTarget:(id)target action:(SEL)action
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];

	[field setFont:[NSFont systemFontOfSize:AISettingsLabelFontSize]];
	[field setAlignment:NSTextAlignmentLeft];
	[field setTarget:target];
	[field setAction:action];
	/* Return alone is not enough: a user who types and then clicks somewhere else
	 * expects what they typed to have been taken. */
	[[field cell] setSendsActionOnEndEditing:YES];
	/* One line whatever the value: a long one scrolls under the insertion point while it is typed
	 * and is truncated once it is not. Left to its default the cell wraps, and a value longer than
	 * the row paints itself across the rows below while the field stays one line tall. */
	[[field cell] setWraps:NO];
	[[field cell] setScrollable:YES];
	[field setLineBreakMode:NSLineBreakByTruncatingTail];
	[field sizeToFit];

	//The row decides the width; only the height comes from the field itself
	[field setFrameSize:NSMakeSize(AISettingsSliderMinWidth, ceil(NSHeight([field frame])))];

	return field;
}

+ (NSTextField *)profileNameFieldWithTarget:(id)target action:(SEL)action
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];

	[field setFont:[NSFont systemFontOfSize:AISettingsProfileNameSize weight:NSFontWeightSemibold]];
	[field setAlignment:NSTextAlignmentCenter];
	/* No box around it, and no background either: under the picture this is the
	 * name of the page, and it happens to be editable. The insertion point and the
	 * focus ring are what say so while it is being used. */
	[field setBordered:NO];
	[field setBezeled:NO];
	[field setDrawsBackground:NO];
	[field setTarget:target];
	[field setAction:action];
	//As in +textFieldWithTarget:action:: Return is not the only way out of a field
	[[field cell] setSendsActionOnEndEditing:YES];
	/* One line whatever the name: it scrolls under the insertion point while it is
	 * typed and is truncated once it is not, so a long name neither folds the
	 * header into two lines nor pushes the button under it out of the card. */
	[[field cell] setWraps:NO];
	[[field cell] setScrollable:YES];
	[field setLineBreakMode:NSLineBreakByTruncatingTail];
	[field sizeToFit];

	//The row decides the width; only the height comes from the field itself
	[field setFrameSize:NSMakeSize(AISettingsSliderMinWidth, ceil(NSHeight([field frame])))];

	return field;
}

+ (NSSlider *)sliderWithMinValue:(double)minValue maxValue:(double)maxValue target:(id)target action:(SEL)action
{
	NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(0.0, 0.0, AISettingsSliderMinWidth, AISettingsSliderHeight)];

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
	NSTextField *field = AISettingsMakeLabel((widestValue ?: @""),
											  [NSFont systemFontOfSize:AISettingsLabelFontSize],
											  [NSColor secondaryLabelColor]);

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

	NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, height)];
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
