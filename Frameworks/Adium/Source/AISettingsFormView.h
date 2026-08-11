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
 * <tt>controlBackgroundColor</tt> plus a translucent system fill and a hairline
 * outline (the plain fill alone is invisible — it is the same colour as the
 * window background on current macOS), each holding one or more rows separated
 * by hairlines. A card is usually introduced by a bold section header sitting
 * above it.
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
 * Everything is positioned with explicit frames — no Auto Layout, no XIB — so
 * the form composes freely with the rest of the (frame based) codebase and is
 * safe under manual retain/release. The view is flipped: rows are appended
 * downwards in the order they are added.
 *
 * <h3>Sizing</h3>
 * The form lays itself out whenever its width changes and updates its own
 * frame height to match its content, so a host may set any height it likes and
 * read back the truthful one afterwards. @c totalHeight reports that height.
 * When the form is the direct subview of a scroll view's document view, it also
 * grows that document view so the scrolling column always covers the content.
 */
@interface AISettingsFormView : NSView {
	NSMutableArray	*sections;			//AISettingsFormSection, in display order
	CGFloat			 contentHeight;		//Height of the laid out content
	BOOL			 needsFormLayout;
}

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
 * @brief Drop every section and row, e.g. before rebuilding the form.
 */
- (void)removeAllSections;

#pragma mark Layout

/*!
 * @brief Lay the form out for @a width points and update its frame height.
 */
- (void)layoutForWidth:(CGFloat)width;

/*!
 * @brief Height the form needs at its current width.
 */
- (CGFloat)totalHeight;

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
 * @brief A text field of @a width points for value rows.
 */
+ (NSTextField *)valueFieldWithWidth:(CGFloat)width target:(id)target action:(SEL)action;

/*!
 * @brief Lay @a views out in a row, @a spacing points apart, vertically centred.
 *
 * Handy for a text field plus stepper, or a bar of buttons handed to
 * @c addFullWidthRow:.
 */
+ (NSView *)rowOfViews:(NSArray *)views spacing:(CGFloat)spacing;

@end
