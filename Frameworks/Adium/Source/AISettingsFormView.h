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

#import <Cocoa/Cocoa.h>

/*!
 * @class AISettingsFormView
 * @brief A settings pane body in the macOS System Settings style.
 *
 * The form is a stack of <em>cards</em>: rounded rectangles filled with
 * <tt>controlBackgroundColor</tt> plus a translucent system fill (the plain fill
 * alone is invisible — it is the same colour as the window background on current
 * macOS), each holding one or more rows separated by hairlines. A card carries
 * no outline of its own; the dividers between its rows are the only lines. A
 * card is usually introduced by a bold section header sitting above it.
 *
 * Build a form top to bottom, then hand it to a preference pane as its view:
 *
 * <pre>
 * AISettingsFormView *form = [[AISettingsFormView alloc] initWithWidth:680.0];
 *
 * [form addSectionHeader:AILocalizedString(@"Messages", nil)];
 * [form addRowWithLabel:AILocalizedString(@"Open messages in tabs", nil)
 *               control:[AISettingsFormView switchWithTarget:self action:@selector(changedTabs:)]];
 * [form addRowWithLabel:AILocalizedString(@"Send messages on", nil)
 *               control:[AISettingsFormView popUpButtonWithTitles:titles target:self action:@selector(changedSendKey:)]
 *                detail:AILocalizedString(@"Applies to every chat window.", nil)];
 *
 * [form addSectionHeader:AILocalizedString(@"Logging", nil)];
 * [form addRadioGroupWithLabel:AILocalizedString(@"Keep a log of", nil) buttons:radioButtons];
 * [form addFullWidthRow:buttonBar];
 * </pre>
 *
 * The form is a hybrid: towards its host it keeps the frame contract of the
 * (frame based) codebase — the window controller sets its frame, the form sets
 * its own height — while on the inside a stack of Auto Layout constraints
 * derives every height, so no code here adds y coordinates up. Views handed in
 * by a pane stay frame based; the form hosts them, so they need no constraints
 * of their own and remain safe under manual retain/release. The view is
 * flipped: rows are appended downwards in the order they are added.
 *
 * <h3>Sizing</h3>
 * The form lays itself out whenever its width changes and updates its own
 * frame height to match its content, so a host may set any height it likes and
 * read back the truthful one afterwards. @c totalHeight reports that height.
 * When the form is the direct subview of a scroll view's document view, it also
 * grows that document view so the scrolling column always covers the content.
 */
@interface AISettingsFormView : NSView {
	NSMutableArray		*sections;				//AISettingsFormSection, in display order
	NSStackView			*formStack;				//The one vertical stack everything hangs off
	NSLayoutConstraint	*formWidthConstraint;	//How -layoutForWidth: hands the stack its width
	CGFloat				 contentHeight;			//Height of the laid out content
	CGFloat				 maximumSliderWidth;	//0: sliders fill their row; >0: capped to this and right aligned
	CGFloat				 sharedLabelNatural;	//Widest label of the whole form, once they share a column
	BOOL				 sharesLabelColumn;
	BOOL				 needsFormLayout;
}

/*!
 * @brief Line the label column up across every card, not only within one.
 *
 * By default each card finds its own label column, which is what System
 * Settings does: two cards about different things have no reason to agree. A
 * form whose cards are all the same kind of thing - a page of fields about one
 * account - reads better with one column throughout, because then every field
 * that takes what the row leaves is exactly as wide as the next.
 *
 * Set it before adding rows. The column never gives width back, so it settles
 * on the widest label the form ever had.
 */
@property (nonatomic) BOOL sharesLabelColumn;

/*!
 * @brief Cap the width of every slider row added after this, or 0 to fill.
 *
 * A capped slider takes a fixed width against its readout and leaves the gap on
 * the label side, rather than running the full width of the card. Set it before
 * adding the rows it should govern.
 */
@property (nonatomic) CGFloat maximumSliderWidth;

/*!
 * @brief Create a form that starts out @a width points wide.
 *
 * A width below 1 point falls back to a usable default; the host is expected to
 * hand over its real width later through @c layoutForWidth: or a frame change.
 */
- (instancetype)initWithWidth:(CGFloat)width;

#pragma mark Building

/*!
 * @brief Start a new card, introduced by a bold section header.
 *
 * Pass nil for an unlabelled card. Rows added afterwards land in this card.
 */
- (void)addSectionHeader:(NSString *)title;

/*!
 * @brief Close the current card.
 *
 * The next row added opens a fresh, header-less card. Only needed for two
 * adjacent cards without a header in between; @c addSectionHeader: closes the
 * previous card by itself.
 */
- (void)endCard;

/*!
 * @brief Append a row: @a label on the left, @a control right aligned.
 *
 * @a control keeps its own frame size if it has one, otherwise its fitting
 * size is used; that natural size is remembered, so a control narrowed for a
 * narrow card grows back when there is room again. The label wraps rather than
 * clipping, and the row grows to fit.
 *
 * The label dims with the control: the row follows the enabled state of the
 * trailing-most control below @a control, so an NSEnabledBinding greys the
 * label out the way a checkbox title used to. The label is also handed to the
 * control as its accessibility label unless the control shows a title itself.
 */
- (void)addRowWithLabel:(NSString *)label control:(NSView *)control;

/*!
 * @brief As above, with a smaller secondary line under the label.
 *
 * @a detail may be nil, in which case this is exactly @c addRowWithLabel:control:.
 */
- (void)addRowWithLabel:(NSString *)label control:(NSView *)control detail:(NSString *)detail;

/*!
 * @brief Append a row: @a label on the left, @a popUpButton and @a button on the right.
 *
 * The shape of a row offering a choice plus a way to edit it ("Color Theme ⟨…⟩
 * [Customize…]"). @a button sits at the trailing edge with the menu to its left
 * and may be nil, which leaves a plain pop up row. It keeps its own title as its
 * accessibility label and is given @a label as its help text, so a column of
 * buttons all reading "Customize…" still says which row it belongs to.
 *
 * Unlike @c addRowWithLabel:control:, the pop up is re-measured at every layout
 * instead of being pinned to the size it had when it was added, so a menu built
 * or rebuilt afterwards — Xtras appearing and disappearing, say — decides the
 * width of the button by itself. Ask for a fresh layout after such a rebuild
 * with @c noteContentSizeChanged. The menu is still narrowed to what the card
 * can spare when it asks for more.
 */
- (void)addRowWithLabel:(NSString *)label popUpButton:(NSPopUpButton *)popUpButton accessoryButton:(NSButton *)button;

/*!
 * @brief Append a row: @a label on the left, @a slider filling the row, @a valueLabel at its end.
 *
 * The shape of a System Settings slider row ("Display brightness", "Volume"):
 * the label keeps only the width its text needs, the readout keeps the width
 * its factory gave it, and the slider stretches into everything in between —
 * which is why a slider cannot be handed to @c addRowWithLabel:control:, where
 * a control keeps its natural width.
 *
 * Every slider row of one card shares one label column and one readout column,
 * both as wide as the widest of them, so the sliders of a card start and end on
 * the same two lines. The label column never gives width back either, so
 * retitling a row — see @c setLabel:forRowWithControl: — moves no slider at all,
 * neither its own nor its neighbours'. A label pressed below the width its text
 * needs is truncated rather than wrapped.
 *
 * @a valueLabel may be nil for a slider without a readout; otherwise build it
 * with @c valueLabelForWidestValue: and keep a reference, because the readout's
 * text is the caller's to update (@c setStringValue:) whenever the slider
 * moves. It is excluded from the accessibility tree: VoiceOver reads the value
 * off the slider itself, so a second announcement of the same number is noise.
 *
 * The label and the readout dim with the slider, exactly as in a control row.
 */
- (void)addRowWithLabel:(NSString *)label slider:(NSSlider *)slider valueLabel:(NSTextField *)valueLabel;

/*!
 * @brief Append a row: @a label on the left, @a control filling the rest of the row.
 *
 * The shape of a System Settings row whose control has no natural width of its
 * own — a text field the user types a name or a format into: the label keeps
 * only the width its text needs and the control takes everything left up to the
 * card's trailing inset. @c addRowWithLabel:control: cannot do this, because
 * there a control keeps the width it had when it was added and would sit as a
 * stub at the right hand edge.
 *
 * Shares the label column with the slider rows of the same card — a slider row
 * and a stretching row are the same shape — so their controls start on one line
 * and a retitled row moves none of them. A label pressed below the width its
 * text needs is truncated rather than wrapped, and the row is as tall as the
 * control it was handed.
 *
 * The label dims with the control, exactly as in a control row.
 */
- (void)addRowWithLabel:(NSString *)label stretchingControl:(NSView *)control;

/*!
 * @brief As above, but with the label beside the control's top line.
 *
 * For a tall stretching control - a text editor - where a vertically centred
 * label floats halfway down the box. A one-line control looks the same either
 * way. Pass NO and this is exactly @c addRowWithLabel:stretchingControl:.
 */
- (void)addRowWithLabel:(NSString *)label stretchingControl:(NSView *)control labelTopAligned:(BOOL)labelTopAligned;

/*!
 * @brief Append a row with @a label on top and radio buttons stacked below it.
 *
 * @a radioButtons are NSButtons (see @c radioButtonWithTitle:target:action:);
 * the caller keeps ownership of their state and target/action. Each group gets
 * its own container view, so two groups in one card stay independent even when
 * they share an action.
 */
- (void)addRadioGroupWithLabel:(NSString *)label buttons:(NSArray *)radioButtons;

/*!
 * @brief Append a row holding @a view across the full inner width of the card.
 *
 * Use for button bars, tables or anything that does not fit the label/control
 * shape. @a view keeps its height; it is resized to the card's inner width.
 */
- (void)addFullWidthRow:(NSView *)view;

/*!
 * @brief As above, but @a view keeps its natural width when @a stretch is NO.
 *
 * Pass NO for a single push button — a button stretched across the card is not
 * a shape System Settings uses.
 */
- (void)addFullWidthRow:(NSView *)view stretch:(BOOL)stretch;

/*!
 * @brief Append a row in which @a view <em>is</em> the card: no inset at all.
 *
 * Unlike @c addFullWidthRow:, @a view is laid out flush with all four edges of
 * the card and its own height becomes the row height — no minimum height, no
 * padding. That is the shape System Settings uses for a list (Bluetooth's "My
 * Devices", Network's VPN list): the card <em>is</em> the list, the list brings
 * its own rows, its own row height and its own separators.
 *
 * @a view is expected to size itself vertically; tell the form about a new
 * height with @c noteContentSizeChanged. The form never draws a separator next
 * to an edge to edge row, so a hosted list is free to draw its own.
 *
 * The form also rounds @a view to the card's corner radius (it gains a layer),
 * so a selected first or last row cannot paint over the rounded corners. Hosts
 * neither know nor repeat that radius; ask for it with @c cardCornerRadius if
 * something has to line up with it.
 */
- (void)addEdgeToEdgeRow:(NSView *)view;

/*!
 * @brief Append a row holding nothing but @a text, wrapped across the card.
 *
 * The shape System Settings uses for a line of explanation inside a group: the
 * same small secondary text a row's @c detail: line carries, but standing on
 * its own instead of under a label — for a sentence which belongs to the whole
 * card rather than to one setting ("Messages are highlighted when the following
 * terms are spoken"), or for one which explains the row above it and would not
 * fit beside its control.
 *
 * The row carries no control, so it is not stretched to the height of a control
 * row: it is exactly as tall as its text plus the standard padding. The text
 * wraps at the card's inner width and is re-measured at every layout, so it
 * refolds when the window is resized. It clings to the row above it — the form
 * draws no divider against a detail row, because the text reads as belonging to
 * what stands above it — while the next row draws its own divider as usual, so
 * the detail stays on the near side of the line. Opening a card, it takes the
 * card's own top padding instead.
 *
 * The text is selectable but never dims: a detail row follows no control.
 * A nil or empty @a text adds nothing at all.
 */
- (void)addDetailRow:(NSString *)text;

/*!
 * @brief Append a row holding nothing but @a text, centred in the card.
 *
 * The shape System Settings uses for a list which has nothing in it yet
 * (Bluetooth with no devices, Login Items with no items): the same small
 * secondary text as @c addDetailRow:, but centred horizontally and given a
 * control row's minimum height, so the card reads as an empty list rather than
 * as a sentence. Use it instead of leaving a section without rows — a card with
 * a header and no row is drawn as a bold header above nothing.
 *
 * The text wraps at the card's inner width and is re-measured at every layout.
 * A nil or empty @a text adds nothing at all.
 */
- (void)addEmptyStateRow:(NSString *)text;

/*!
 * @brief Append a row: @a image at the leading edge, @a title over @a text
 *        beside it, @a control at the trailing edge.
 *
 * The shape System Settings uses for an explanation worth a picture and a way
 * to act on it — the paragraph standing next to the Mac in Bluetooth, the
 * software update block with its "Update Now": a symbol at the leading edge, a
 * heading with the same small secondary text @c addDetailRow: carries under it,
 * and a button at the far end. Picture, text block and control are centred
 * against whichever of the three is taller.
 *
 * Use it where a sentence carries the weight of a whole card rather than of the
 * row above it; a line which only qualifies its neighbour stays an
 * @c addDetailRow:. Because it reads as a block of its own, it usually wants a
 * card of its own — open one with @c endCard or @c addSectionHeader: — unless
 * it really is about the rows it is sitting with.
 *
 * @a title is set in the font of an ordinary row label, not in a section
 * header's bold: it names this row, and a heavier heading inside a card would
 * read as a heading for every row below it.
 *
 * @a image is scaled proportionally into a square of at most 40 points, and a
 * <em>copy</em> is what gets scaled: a named image is shared with everything
 * else drawing it, and resizing the original would shrink it in a toolbar or a
 * list on the other side of the application. An image already smaller than that
 * square keeps its own size rather than being blown up, and whatever its shape
 * it is centred in that square: the text always begins at the same column, so
 * two info rows of one card line their paragraphs up. It stays out of the
 * accessibility tree, since it illustrates @a text and says nothing @a text does
 * not.
 *
 * @a control keeps its natural width — narrowed only when the card cannot spare
 * it — and is given @a title as its help text, so a button reading nothing but
 * "Open" still says what it opens. Hand over a single control; for a bar of
 * them, wrap it in @c rowOfViews:.
 *
 * Both @a title and @a text wrap at whatever width the picture and the control
 * leave them, and both are re-measured at every layout, so they refold when the
 * window is resized. Every argument may be nil; with nothing at all, nothing is
 * added.
 */
- (void)addInfoRow:(NSString *)text
		 withImage:(NSImage *)image
			 title:(NSString *)title
		   control:(NSView *)control;

/*!
 * @brief As above: a picture and the paragraph it illustrates, nothing else.
 *
 * The plain shape, for a sentence which wants no heading over it and offers
 * nothing to press. Everything else is @c addInfoRow:withImage:title:control:.
 */
- (void)addInfoRow:(NSString *)text withImage:(NSImage *)image;

/*!
 * @brief Put @a view directly below the current card, outside of any card.
 *
 * The shape of the +/− bar under a System Settings list. @a view keeps its own
 * size, is left aligned with the card and gets the form's standard gap above
 * it; the next section starts below it. Build the bar itself with
 * @c rowOfViews:spacing: so no host ever positions a button by hand.
 *
 * Only one accessory per card; a second call replaces the first.
 */
- (void)addAccessoryView:(NSView *)view;

/*!
 * @brief As @c addAccessoryView:, but aligned with the card's trailing edge.
 *
 * The shape System Settings uses for an "add" control below a list (Network's
 * VPN list, Bluetooth): the bar hangs under the right-hand corner of the card
 * instead of the left one. Everything else — sizing, the gap above it, the fact
 * that it lives outside the card — is exactly @c addAccessoryView:.
 *
 * Only one accessory per card; this and @c addAccessoryView: replace each other.
 */
- (void)addTrailingAccessoryView:(NSView *)view;

/*!
 * @brief Put @a text directly below the current card, outside of any card.
 *
 * The footnote System Settings sets under a group ("Style changes take effect
 * for new message windows."): the same small secondary text as
 * @c addDetailRow:, but on the window background rather than on the card,
 * aligned with the card's leading edge and as wide as the card. It sits below
 * the card's accessory bar when the section has one, and the next section
 * starts below it. Like a detail row it is re-measured at every layout, so it
 * refolds with the window.
 *
 * Takes a string rather than a view — as @c addSectionHeader: does and unlike
 * @c addAccessoryView: — so no pane ever builds a second, nearly identical
 * field of its own.
 *
 * Only one footnote per card; a second call replaces the first, and nil or
 * empty text removes it. For two paragraphs, hand over one string with a blank
 * line in it.
 */
- (void)addFootnote:(NSString *)text;

/*!
 * @brief Retitle the row @a control sits in.
 *
 * For the rare label which is not constant — one naming what a slider does
 * depending on another setting, say. @a control is the view handed to
 * @c addRowWithLabel:control: (or the slider of a slider row); a control nested
 * inside the row's view works as well. The row is re-laid out, so the new text
 * may be longer or shorter than the old one, and it becomes the control's
 * accessibility label too.
 *
 * Setting the text a row already carries does nothing at all, so a caller may
 * hand over the current label on every preference change without paying for a
 * layout pass. Does nothing either for a row which was added without a label: a
 * row cannot grow one afterwards, since that would change the height of a card
 * already on screen.
 */
- (void)setLabel:(NSString *)label forRowWithControl:(NSView *)control;

/*!
 * @brief Give the whole row @a control sits in a tool tip.
 *
 * In a nib a checkbox carried its title, so a tool tip set on it covered the
 * words as well as the box. Here the label is a field of its own, and a tool tip
 * set on the control alone would only show over the switch at the trailing edge.
 * This one goes on the label, the detail line, the value readout and any
 * accessory button too, so hovering anywhere along the row shows it — the label
 * column is as wide as the row leaves it, so the hot area is a little wider than
 * the title text.
 *
 * @a control is the view handed to @c addRowWithLabel:control: (or a control
 * nested inside it), as with @c setLabel:forRowWithControl:. Nothing is
 * re-measured: a tool tip changes no size. Pass nil to take one away.
 */
- (void)setToolTip:(NSString *)toolTip forRowWithControl:(NSView *)control;

/*!
 * @brief Drop every section and row, e.g. before rebuilding the form.
 */
- (void)removeAllSections;

#pragma mark Layout

/*!
 * @brief Lay the form out for @a width points and update its frame height.
 */
- (void)layoutForWidth:(CGFloat)width;

/*!
 * @brief A hosted view resized itself; take its new height into account.
 *
 * Call after growing or shrinking a view handed to @c addEdgeToEdgeRow: or
 * @c addFullWidthRow: — a list which gained a row, say. The form re-reads the
 * hosted heights, resizes the card around them and updates its own frame, which
 * is what makes the enclosing preference column follow along.
 */
- (void)noteContentSizeChanged;

/*!
 * @brief Height the form needs at its current width.
 */
- (CGFloat)totalHeight;

#pragma mark Shared metrics

/*!
 * @brief Corner radius of a card.
 *
 * Only needed by a host which has to line something up with a card's corners;
 * @c addEdgeToEdgeRow: already rounds what it is given.
 */
+ (CGFloat)cardCornerRadius;

/*!
 * @brief The standard gap between two adjacent controls of one bar.
 *
 * Use it instead of a hand-picked number so every pane keeps the same rhythm;
 * @c rowOfViews: applies it by itself.
 */
+ (CGFloat)standardControlGap;

#pragma mark Control factories

/*!
 * @brief An NSSwitch wired to @a target / @a action, sized to fit.
 */
+ (NSSwitch *)switchWithTarget:(id)target action:(SEL)action;

/*!
 * @brief A pop up button holding @a titles (NSStrings), sized to fit.
 */
+ (NSPopUpButton *)popUpButtonWithTitles:(NSArray *)titles target:(id)target action:(SEL)action;

/*!
 * @brief A radio button for use with @c addRadioGroupWithLabel:buttons:.
 */
+ (NSButton *)radioButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action;

/*!
 * @brief An ordinary push button, sized to fit.
 */
+ (NSButton *)pushButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action;

/*!
 * @brief A borderless 22 by 22 point button showing nothing but a symbol.
 *
 * The inline control System Settings puts at the trailing edge of a list row —
 * the (i) of an account, the ⊖ of an item which can be removed. It carries no
 * bezel and no title, tints itself with @c secondaryLabelColor so it recedes
 * behind the row's text, and is sized so a column of them lines up whatever
 * symbol they show.
 *
 * @a symbolName is an SF Symbol name; @a imageName names a bundled image used
 * where that symbol is not available, and may be nil. Give the button an
 * accessibility label of its own — a symbol has no title to fall back on.
 */
/*!
 * @brief The chevron a row shows when it opens a page of its own
 *
 * A host which draws its own rows, a table hosted edge to edge for instance, would otherwise pick a
 * glyph and a tint of its own and end up half a point off the ones the form draws.
 */
+ (NSImage *)disclosureIndicatorImage;

+ (NSButton *)inlineSymbolButtonWithSymbolName:(NSString *)symbolName
							 fallbackImageName:(NSString *)imageName
										target:(id)target
										action:(SEL)action;

/*!
 * @brief A text field of @a width points for value rows.
 */
+ (NSTextField *)valueFieldWithWidth:(CGFloat)width target:(id)target action:(SEL)action;

/*!
 * @brief A text field for @c addRowWithLabel:stretchingControl:, wired to @a target / @a action.
 *
 * Left aligned and without a width of its own, because the row decides that.
 * Sends its action when editing ends — on Return, on Tab and when the focus
 * moves away — so a pane which only saves in its action still saves. A pane
 * that must not lose the last keystroke should also take
 * @c controlTextDidChange:, since taking a preference pane off screen does not
 * end editing.
 */
+ (NSTextField *)textFieldWithTarget:(id)target action:(SEL)action;

/*!
 * @brief A slider for @c addRowWithLabel:slider:valueLabel:, wired to @a target / @a action.
 *
 * Deliberately <em>not</em> continuous: the action fires once the drag ends, so
 * a preference is written once per adjustment instead of once per pixel. Note
 * that Interface Builder does the opposite — a slider dropped into a nib is
 * continuous — so send @c setContinuous:YES yourself for a slider whose readout
 * and effect should follow the knob live, and have its action skip writing when
 * the value has not actually changed.
 */
+ (NSSlider *)sliderWithMinValue:(double)minValue maxValue:(double)maxValue target:(id)target action:(SEL)action;

/*!
 * @brief The trailing readout of a slider row, sized to hold @a widestValue.
 *
 * Pass the longest string the row will ever show ("100%", "640px"), so the
 * slider does not change length as the number does; the caller sets the actual
 * text with @c setStringValue: whenever the value changes. The field is not
 * editable and carries no target/action — for a number the user types into, use
 * @c valueFieldWithWidth:target:action:.
 */
+ (NSTextField *)valueLabelForWidestValue:(NSString *)widestValue;

/*!
 * @brief Lay @a views out in a row, the standard gap apart, vertically centred.
 *
 * The shape of a +/− bar plus its buttons; hand the result to
 * @c addAccessoryView: or @c addFullWidthRow:.
 */
+ (NSView *)rowOfViews:(NSArray *)views;

/*!
 * @brief As above with an explicit @a spacing between the views.
 *
 * Handy for a text field plus stepper; prefer @c rowOfViews: wherever the
 * standard gap fits, so panes keep the same rhythm.
 */
+ (NSView *)rowOfViews:(NSArray *)views spacing:(CGFloat)spacing;

@end
