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

#import "ESStatusPreferences.h"
#import "AIStatusController.h"
#import "ESEditStatusGroupWindowController.h"
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIAccount.h>
#import <Adium/AIEditStateWindowController.h>
#import <Adium/AIStatusMenu.h>
#import <Adium/AIStatusGroup.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIImageTextCell.h>
#import <AIUtilities/AIVerticallyCenteredTextCell.h>
#import <AIUtilities/AIOutlineViewAdditions.h>
#import <AIUtilities/AIAlternatingRowOutlineView.h>
#import <AIUtilities/AIImageDrawingAdditions.h>

#define STATE_DRAG_TYPE	@"AIState"

/* Width of the three minute fields. Wide enough for more digits than the stepper can produce: a
 * setting made before this pane had a stepper at all may be any number of minutes, and the field
 * shows what is stored rather than what the stepper could reach. */
#define MINUTES_FIELD_WIDTH			52.0
/* The range of the steppers, not of the settings. Zero minutes is not a setting, and a stepper has
 * to stop somewhere; a stored value outside this range is shown and kept as it is. */
#define MINUTES_MINIMUM				1
#define MINUTES_MAXIMUM				999

/* Fallback only: the room the outline view keeps above its first and below its last row is
 * measured off the view itself as soon as it has any (see -heightOfStateList). */
#define STATE_LIST_END_PADDING		4.0f
//An empty card must not collapse into a line
#define STATE_LIST_MINIMUM_ROWS		3

@interface ESStatusPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (AISettingsFormView *)settingsForm;
- (void)tearDown;

- (void)configureStateListButtons;
- (NSView *)minutesRowWithField:(NSTextField *)field
						stepper:(NSStepper *)stepper
					  unitLabel:(NSTextField *)unitLabel;

- (CGFloat)heightOfStateList;
- (void)updateStateListHeight;
- (void)setStateListHeightNeedsUpdate;
- (void)stateListHeightUpdateFired;
- (void)synchronizeStateColumnWidth;
- (void)stateListFrameChanged:(NSNotification *)notification;
- (void)autoscrollPaneForDrag:(id <NSDraggingInfo>)info;

- (void)configureOtherControls;
- (void)refreshDisplayedValues;
- (void)showMinutes:(double)minutes inField:(NSTextField *)field stepper:(NSStepper *)stepper;
- (void)configureAutoAwayStatusStatePopUp;
- (void)prependDoNotChangeItemToMenu:(NSMenu *)menu action:(SEL)action;
- (NSNumber *)statusIDForSelectedMenuItem:(id)sender;
- (void)commitMinutesFromField:(NSTextField *)field
					   stepper:(NSStepper *)stepper
						sender:(id)sender
						forKey:(NSString *)key;
- (void)_selectStatusWithUniqueID:(NSNumber *)uniqueID inPopUpButton:(NSPopUpButton *)inPopUpButton;

- (void)reselectDraggedItems:(NSArray *)theDraggedItems;
- (void)changedAutoAwayStatus:(id)sender;
- (void)changedFastUserSwitchingStatus:(id)sender;
- (void)changedScreenSaverStatus:(id)sender;

- (BOOL)addItemIfNeeded:(NSMenuItem *)menuItem toPopUpButton:(NSPopUpButton *)popUpButton alreadyShowingAnItem:(BOOL)alreadyShowing;


- (void)newState;
- (void)deleteState;
@end

@implementation ESStatusPreferences

- (NSString *)paneIdentifier
{
	return @"Status";
}
- (NSString *)paneName
{
    return AILocalizedString(@"Status",nil);
}
- (NSImage *)paneIcon
{
	return [NSImage imageNamed:@"pref-status" forClass:[self class]];
}

/*!
 * @brief Nib name
 */
- (NSString *)nibName{
    return @"StatusPreferences";
}

#pragma mark View

/*!
 * @brief Our view: the nib's controls, arranged by the settings form
 *
 * The nib still supplies the outline view — with its data source, its delegate, its drag
 * registration and its column — plus the three list buttons, the minute fields, their steppers
 * and the three status menus, but no longer their arrangement. Mirrors -[AIModularPane view] so
 * the subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		[NSBundle loadNibNamed:[self nibName] owner:self];

		/* The nib set the inherited 'view' outlet to its own top level view, retaining it. We take
		 * that reference over rather than retaining it again; it keeps the nib alive while we use
		 * its controls, and -tearDown releases it. */
		[nibView release];
		nibView = view;
		view = [[self buildSettingsForm] retain];

		[self viewDidLoad];
		[self localizePane];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];

	} else {
		/* The preferences window asks a pane for its view every time that pane is selected, and it
		 * leaves a pane it switches away from by taking its view out of the window - not by closing
		 * it. Nothing on that way out ends editing, so a field left holding a half typed number, or
		 * nothing at all, would come back on screen still holding it while the setting says
		 * something else. This is where that is put right: the counterpart of
		 * -controlTextDidEndEditing: for the exit which never ends editing. */
		[self refreshDisplayedValues];
	}

	return view;
}

/*!
 * @brief The settings form we live in, or nil before -view built it
 */
- (AISettingsFormView *)settingsForm
{
	return ([view isKindOfClass:[AISettingsFormView class]] ? (AISettingsFormView *)view : nil);
}

/*!
 * @brief Stack the nib's controls into cards
 *
 * Three of them: the saved statuses with their button bar, everything about being idle and away,
 * and the two status changes Adium makes on its own. The checkbox titles of the old layout became
 * row labels, and the sentences they used to continue ("Set idle after [10] minutes of
 * inactivity") became a row of their own — a dependent row, dimmed with the switch above it,
 * rather than an indented one.
 */
- (AISettingsFormView *)buildSettingsForm
{
	/* No width of our own: the form falls back to a usable one and the preferences window hands it
	 * its column width right afterwards. */
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:0.0f] autorelease];

	/* The form lays everything out by frame, and a view out of a nib saved without Auto Layout
	 * arrives with translatesAutoresizingMaskIntoConstraints turned off - the layout engine owns it
	 * and resolves it as ambiguous, which collapses it to nothing. Every way into the form adopts
	 * the views handed to it for frame based layout, except the pop up row, so these three have to
	 * say it for themselves; the other nib views reach the form through -addEdgeToEdgeRow: and
	 * +rowOfViews:, which do it for them. */
	for (NSPopUpButton *popUp in [NSArray arrayWithObjects:
								  popUp_autoAwayStatusState, popUp_fastUserSwitchingStatusState,
								  popUp_screenSaverStatusState, nil]) {
		[popUp setTranslatesAutoresizingMaskIntoConstraints:YES];
	}

	/* Card 1: the list of saved statuses.
	 *
	 * The column follows the width the form gives the scroll view, so the outline view has to
	 * resize with it from the very first layout - the nib leaves it non-resizable. */
	[outlineView_stateList setAutoresizingMask:NSViewWidthSizable];

	[form addSectionHeader:AILocalizedString(@"Statuses", nil)];

	/* The list is the card: it fills it edge to edge and its height decides how tall the card is.
	 * Adding a view which still has a superview moves it, so the nib's arrangement comes apart on
	 * its own - no view is ever left without an owner in between. */
	[form addEdgeToEdgeRow:scrollView_stateList];

	//...and all three of its buttons hang under the card in one bar, the way System Settings does
	[self configureStateListButtons];
	[form addAccessoryView:[AISettingsFormView rowOfViews:[NSArray arrayWithObjects:
														   button_addOrRemoveState,
														   button_addGroup,
														   button_editState,
														   nil]]];

	//Card 2: idle and away
	[form addSectionHeader:AILocalizedString(@"Idle and Away","Section title above the idle and away status settings")];

	checkBox_idle = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Report me as idle","Switch for telling contacts when the user is inactive")
				  control:checkBox_idle];

	[form addRowWithLabel:AILocalizedString(@"Report idle after","Label of the field holding how many minutes of inactivity make the user idle")
				  control:[self minutesRowWithField:textField_idleMinutes
											stepper:stepper_idleMinutes
										  unitLabel:label_idleMinutes]];

	/* A pop up row rather than a plain control row: the menu is rebuilt whenever the saved
	 * statuses change, and the button then has to be free to grow and to shrink again. */
	[form addRowWithLabel:AILocalizedString(@"Change my status to","Label of the menu holding the status set after a while of inactivity")
			  popUpButton:popUp_autoAwayStatusState
		  accessoryButton:nil];

	/* Says out loud what the merged setting does: the same duration carries both halves. Without
	 * it nothing on screen would tell the user when the status above is going to be set. */
	[form addDetailRow:AILocalizedString(@"Adium changes to this status after the same time.","Explanation under the menu holding the status set after a while of inactivity")];

	checkBox_awayReminder = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Remind me while away","Switch for being reminded now and then that one's status is still away")
				  control:checkBox_awayReminder];

	[form addRowWithLabel:AILocalizedString(@"Remind me every","Label of the field holding how many minutes lie between two away reminders")
				  control:[self minutesRowWithField:textField_awayReminderMinutes
											stepper:stepper_awayReminderMinutes
										  unitLabel:label_awayReminderMinutes]];

	//Card 3: the status changes Adium makes on its own
	[form addSectionHeader:AILocalizedString(@"Automatic Status Changes","Section title above the fast user switching and screen saver status settings")];

	[form addRowWithLabel:AILocalizedString(@"Status after switching users","Label of the menu holding the status set when another user logs in")
			  popUpButton:popUp_fastUserSwitchingStatusState
		  accessoryButton:nil];

	[form addRowWithLabel:AILocalizedString(@"Status while the screen saver runs","Label of the menu holding the status set while the screen saver runs")
			  popUpButton:popUp_screenSaverStatusState
		  accessoryButton:nil];

	return form;
}

/*!
 * @brief Configure the preference view
 */
- (void)viewDidLoad
{
	//Configure the controls
	[self configureStateList];

	[outlineView_stateList accessibilitySetOverrideValue:AILocalizedString(@"Statuses", nil)
											forAttribute:NSAccessibilityTitleAttribute];

	/* Register as an observer of state array changes so we can refresh our list
	 * in response to changes. */
	[[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(stateArrayChanged:)
									   name:AIStatusStateArrayChangedNotification
									 object:nil];
	[self stateArrayChanged:nil];

	[self configureOtherControls];
}

/*!
 * @brief Preference view is closing
 *
 * Nothing is saved here any more: every control writes the moment it is touched, which it has to,
 * since the preferences window only closes a pane when the window itself closes.
 */
- (void)viewWillClose
{
	[self tearDown];
}

/*!
 * @brief Undo everything -viewDidLoad and -buildSettingsForm set up
 *
 * Idempotent, so that it is safe to run it from both -viewWillClose and -dealloc. Running it from
 * -dealloc matters, because -viewWillClose is only reached when the preference window closes.
 */
- (void)tearDown
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	stateListHeightUpdateScheduled = NO;

	/* One of the performs just cancelled may have been -reselectDraggedItems:, which is the only
	 * thing that gives back the rebuilding delay a drop takes. The status controller counts those
	 * delays and rebuilds no status menu anywhere in Adium until the count is back at zero, so a
	 * delay left behind here would be one for the rest of the session. */
	if (delayedStatusMenuRebuilding) {
		delayedStatusMenuRebuilding = NO;
		[adium.statusController setDelayStatusMenuRebuilding:NO];
	}

	/* The list no longer lives in the nib's view but in the form's card, and those two are released
	 * on different paths (-tearDown here, -[AIModularPane closeView] there). Cut the outline view
	 * loose from us here, so a view which outlives us for a moment can never ask a freed pane for
	 * its rows - its delegate, data source and target are all non-retaining references to us. */
	[outlineView_stateList setDelegate:nil];
	[outlineView_stateList setDataSource:nil];
	[outlineView_stateList setTarget:nil];
	[outlineView_stateList setDoubleAction:NULL];

	//Same for everything else we handed a target or a delegate to
	for (NSControl *control in [NSArray arrayWithObjects:
								button_addOrRemoveState, button_addGroup, button_editState,
								checkBox_idle, checkBox_awayReminder,
								stepper_idleMinutes, stepper_awayReminderMinutes,
								nil]) {
		[control setTarget:nil];
	}
	for (NSTextField *field in [NSArray arrayWithObjects:
								textField_idleMinutes, textField_awayReminderMinutes,
								nil]) {
		[field setTarget:nil];
		[field setDelegate:nil];
	}
	/* Every item of these menus carries our address as its target (AIStatusMenu sets it per item),
	 * so the menus go rather than outlive us on a button the form has not released yet. */
	for (NSPopUpButton *popUp in [NSArray arrayWithObjects:
								  popUp_autoAwayStatusState, popUp_fastUserSwitchingStatusState,
								  popUp_screenSaverStatusState, nil]) {
		[popUp setMenu:[[[NSMenu alloc] initWithTitle:@""] autorelease]];
	}

	[scrollView_stateList removeFromSuperview];

	/* All of these outlets are non-retaining and the views behind them go away with the form,
	 * which may be released after us; forget them so a second -tearDown cannot message freed
	 * memory. */
	outlineView_stateList = nil;
	scrollView_stateList = nil;
	button_addOrRemoveState = nil;
	button_addGroup = nil;
	button_editState = nil;
	checkBox_idle = nil;
	checkBox_awayReminder = nil;
	textField_idleMinutes = nil;
	textField_awayReminderMinutes = nil;
	stepper_idleMinutes = nil;
	stepper_awayReminderMinutes = nil;
	label_idleMinutes = nil;
	label_awayReminderMinutes = nil;
	popUp_autoAwayStatusState = nil;
	popUp_fastUserSwitchingStatusState = nil;
	popUp_screenSaverStatusState = nil;

	showingSubmenuItemInAutoAway = NO;
	showingSubmenuItemInFastUserSwitching = NO;
	showingSubmenuItemInScreenSaver = NO;

	//A drag which never reached -outlineView:acceptDrop:item:childIndex: still holds its items
	[draggingItems release]; draggingItems = nil;

	[nibView release]; nibView = nil;
}

/*!
 * @brief Deallocate
 */
- (void)dealloc
{
	[self tearDown];
	[super dealloc];
}

#pragma mark Status state list and controls
/*!
* @brief Configure the state list
 *
 * Configure the state list table view, setting up the custom table cells, padding, scroll view settings and other
 * state list interface related setup.
 */
- (void)configureStateList
{
    AIVerticallyCenteredTextCell *cell;

	//Configure the table view
	[outlineView_stateList setTarget:self];
	[outlineView_stateList setDoubleAction:@selector(editState:)];
	[outlineView_stateList setIntercellSpacing:NSMakeSize(4,4)];

	/* The card behind the list is drawn by the form - controlBackgroundColor plus a translucent
	 * tint - so the list has to let it through, the way the account list does.
	 *
	 * Two things are needed for that, not one. -[AIAlternatingRowOutlineView setDrawsBackground:]
	 * writes its own flag and never reaches NSTableView, so it only switches off that class's own
	 * alternating rows and grid; NSTableView goes on filling the whole card with the nib's
	 * controlBackgroundColor, which is the card's fill without its tint and square where the card
	 * is round. Clearing the background colour is what actually stops that. The system's own
	 * alternating rows are off with them: they are opaque as well, and neither the account list nor
	 * a System Settings list has stripes. */
	[outlineView_stateList setDrawsBackground:NO];
	[outlineView_stateList setUsesAlternatingRowBackgroundColors:NO];
	[(NSTableView *)outlineView_stateList setBackgroundColor:[NSColor clearColor]];

	/* The single column has to follow the width of the card. A table does not reliably re-tile it
	 * on its own (measured on macOS 26 for the account list, which needs the same treatment), so it
	 * is set from the width the list really has whenever that changes. */
	stateColumnMargin = 0.0f;
	[outlineView_stateList setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(stateListFrameChanged:)
												 name:NSViewFrameDidChangeNotification
											   object:outlineView_stateList];

	/* The list does not scroll: it is as tall as its rows and the preferences column scrolls
	 * instead. The scroll view stays - an outline view outside of one loses its tiling and its
	 * enclosing clip view, and dragging states about is the whole point of this list - but it never
	 * scrolls anything: no scrollers, no elasticity. The nib gives it AIPassthroughScrollView on top
	 * of that, so the wheel reaches the pane behind it; a drag which reaches the edge of the window
	 * is followed by -autoscrollPaneForDrag:, since a clip view with nothing to scroll has nothing
	 * to offer AppKit's own drag autoscrolling either.
	 *
	 * It draws no background of its own; the form draws the card and rounds our corners to its
	 * radius. */
	[scrollView_stateList setBorderType:NSNoBorder];
	[scrollView_stateList setDrawsBackground:NO];
	[scrollView_stateList setHasVerticalScroller:NO];
	[scrollView_stateList setHasHorizontalScroller:NO];
	[scrollView_stateList setVerticalScrollElasticity:NSScrollElasticityNone];
	[scrollView_stateList setHorizontalScrollElasticity:NSScrollElasticityNone];
	[scrollView_stateList setAutomaticallyAdjustsContentInsets:NO];
	[scrollView_stateList setContentInsets:NSEdgeInsetsZero];
	[scrollView_stateList setAutoresizingMask:NSViewNotSizable];

	//Enable dragging of states
	[outlineView_stateList registerForDraggedTypes:[NSArray arrayWithObject:STATE_DRAG_TYPE]];

    //Custom vertically-centered text cell for status state names
    cell = [[AIVerticallyCenteredTextCell alloc] init];
    [cell setFont:[NSFont systemFontOfSize:13]];
    [[outlineView_stateList tableColumnWithIdentifier:@"name"] setDataCell:cell];
	[cell release];
}

/*!
 * @brief Give the three list buttons their titles and the look of a bar under a card
 *
 * The nib drew them in the small square style which belonged under a bezelled list; under a card
 * System Settings uses the ordinary rounded push button and, for a +/- pair, the rounded segmented
 * group. Each is then sized to its content, because the accessory bar arranges them by their
 * natural size and never resizes them.
 */
- (void)configureStateListButtons
{
	[button_addOrRemoveState setSegmentStyle:NSSegmentStyleRounded];
	[button_addOrRemoveState setTrackingMode:NSSegmentSwitchTrackingMomentary];
	[button_addOrRemoveState sizeToFit];

	[button_addGroup setTitle:AILocalizedString(@"Add Group",nil)];
	[button_editState setTitle:AILocalizedString(@"Edit",nil)];

	for (NSButton *button in [NSArray arrayWithObjects:button_addGroup, button_editState, nil]) {
		[button setBezelStyle:NSBezelStyleRounded];
		[button setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
		[button sizeToFit];
	}
}

/*!
 * @brief One minute setting: a field, its stepper and the unit behind them
 *
 * Both halves send their action here rather than to each other, which is the whole of the old
 * pane's trouble: the nib had the steppers hand their value to their text field, so a click on one
 * never reached this class and the value was written by -saveTimeValues at window close, if at
 * all. Now the stepper writes on every click and the field on every keystroke.
 *
 * The unit label is part of the bundle rather than part of the row label, so the row reads
 * "Report idle after [10] minutes". It is also the trailing-most control of the row, which is the
 * one the form watches to dim the row's label - see -configureControlDimming.
 */
- (NSView *)minutesRowWithField:(NSTextField *)field
						stepper:(NSStepper *)stepper
					  unitLabel:(NSTextField *)unitLabel
{
	NSNumberFormatter	*formatter = [[[NSNumberFormatter alloc] init] autorelease];

	/* Plain digits, and deliberately no minimum and no maximum. A formatter which rejects what
	 * stands in the field refuses to let editing end, and with no
	 * -control:didFailToFormatString:errorDescription: that is an alert and a focus which cannot
	 * leave the field - for a blank field, for a zero, and for every setting outside the stepper's
	 * range. Anything the user may pass through on the way to a number is a matter for
	 * -commitMinutesFromField:… (which writes nothing below a minute) and for
	 * -controlTextDidEndEditing: (which puts the setting back on screen), not for the formatter. */
	[formatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
	[formatter setPositiveFormat:@"0"];

	[field setFormatter:formatter];
	[field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[field setAlignment:NSTextAlignmentRight];
	[field setTarget:self];
	[field setAction:@selector(changedTimeValue:)];
	[[field cell] setSendsActionOnEndEditing:YES];
	[field setDelegate:(id<NSTextFieldDelegate>)self];
	[field sizeToFit];
	[field setFrameSize:NSMakeSize(MINUTES_FIELD_WIDTH, ceil(NSHeight([field frame])))];

	/* Zero minutes is not a setting, and with the nib's valueWraps a single click on "down" at
	 * zero used to land on 999 - which, now that every click writes, would be 999 minutes in the
	 * preferences before the user could let go of the mouse. */
	[stepper setMinValue:MINUTES_MINIMUM];
	[stepper setMaxValue:MINUTES_MAXIMUM];
	[stepper setIncrement:1.0];
	[stepper setValueWraps:NO];
	[stepper setAutorepeat:YES];
	[stepper setContinuous:YES];
	[stepper setTarget:self];
	[stepper setAction:@selector(changedTimeValue:)];
	[stepper sizeToFit];

	[field setNextKeyView:stepper];

	[unitLabel setStringValue:AILocalizedString(@"minutes",nil)];
	[unitLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[unitLabel sizeToFit];

	//Field and stepper are one control and sit closer together than the standard gap
	NSView	*valueBundle = [AISettingsFormView rowOfViews:[NSArray arrayWithObjects:field, stepper, nil]
												  spacing:2.0];

	return [AISettingsFormView rowOfViews:[NSArray arrayWithObjects:valueBundle, unitLabel, nil]];
}

/*!
 * @brief The height the state list needs to show every visible row without scrolling
 *
 * Unlike the account list this one has a fixed row height, so nothing here depends on the width -
 * and unlike a flat table, only -numberOfRows knows how many rows there are: a collapsed group is
 * one row, an expanded one is itself plus its children. Row rects are where the outline view says
 * how it really laid itself out, so the last row's rect plus the room the view keeps below it is
 * the whole answer. An empty list still gets a few rows' worth of height, so its card does not
 * collapse into a line.
 */
- (CGFloat)heightOfStateList
{
	NSInteger	visibleRows = [outlineView_stateList numberOfRows];
	CGFloat		rowStep = [outlineView_stateList rowHeight] + [outlineView_stateList intercellSpacing].height;
	CGFloat		endPadding = STATE_LIST_END_PADDING;
	CGFloat		height;

	/* The room the view keeps at each end. Only the outline view can say what it is, and only once
	 * it has rows; until then the fallback is the best guess we have. */
	if (visibleRows > 0) {
		CGFloat		topInset = NSMinY([outlineView_stateList rectOfRow:0]);

		if (topInset >= 0.0f) endPadding = topInset;

		height = NSMaxY([outlineView_stateList rectOfRow:(visibleRows - 1)]) + endPadding;
	} else {
		height = rowStep + (2.0f * endPadding);
	}

	CGFloat		minimumHeight = (STATE_LIST_MINIMUM_ROWS * rowStep) + (2.0f * endPadding);

	return ceil(height < minimumHeight ? minimumHeight : height);
}

/*!
 * @brief Grow or shrink the card around the list to fit its rows
 *
 * The list is the edge to edge row of a card, so its height is the card's height. Handing the new
 * height to the form makes the form resize its card and itself, and the preferences window - which
 * watches the pane's frame - resizes its scrolling column in turn. That is the whole chain: the
 * card grows with the number of statuses and the window scrolls, not the list.
 *
 * The half point guard is not decoration: -noteContentSizeChanged runs a full layout pass, which
 * causes frame changes of its own, and without it that can circle.
 */
- (void)updateStateListHeight
{
	CGFloat		height;

	if (!scrollView_stateList) return;

	//Whatever changed the list may have changed how wide its rows have to be laid out
	[self synchronizeStateColumnWidth];

	height = [self heightOfStateList];

	if (fabs(NSHeight([scrollView_stateList frame]) - height) < 0.5f) return;

	[scrollView_stateList setFrameSize:NSMakeSize(NSWidth([scrollView_stateList frame]), height)];
	[[self settingsForm] noteContentSizeChanged];
}

/*!
 * @brief Ask for the card to be refitted once the outline view is done laying itself out
 *
 * Expanding and collapsing a group changes the number of rows without the model moving at all, and
 * we hear about it from inside the outline view's own work; resizing it from there would be
 * resizing a view in the middle of its layout. The common run loop modes rather than the default
 * one, so a group opened while a menu or a sheet is up is followed straight away too. An update
 * which is already scheduled is left alone: it reads the row count when it runs, so it is up to
 * date whatever happened in between.
 */
- (void)setStateListHeightNeedsUpdate
{
	if (stateListHeightUpdateScheduled) return;

	stateListHeightUpdateScheduled = YES;
	[self performSelector:@selector(stateListHeightUpdateFired)
			   withObject:nil
			   afterDelay:0.0
				  inModes:[NSArray arrayWithObject:(NSString *)NSRunLoopCommonModes]];
}

- (void)stateListHeightUpdateFired
{
	stateListHeightUpdateScheduled = NO;
	[self updateStateListHeight];
}

/*!
 * @brief Keep the single column as wide as the room the list has
 *
 * A table does not reliably re-tile its columns when it is widened - measured on macOS 26 for the
 * account list, which is hosted in a card exactly like this one: a table grown from 505pt to 640pt
 * left its only column at the 473pt it had before, while narrowing it and widening it again did
 * re-tile. A column left behind like that lays every status name out in a strip well short of the
 * card's edge, and a click beside it hits no row at all.
 *
 * So the column is set from the width of the clip view rather than left to the table. Whatever the
 * table keeps beside its column while it is tiled to that clip view is measured off the table
 * itself instead of assumed, the same way the account list does it.
 */
- (void)synchronizeStateColumnWidth
{
	NSTableColumn	*column = [outlineView_stateList tableColumnWithIdentifier:@"name"];
	CGFloat			 clipWidth = NSWidth([[scrollView_stateList contentView] bounds]);

	if (!column || clipWidth <= 0.0f) return;

	CGFloat			 tableWidth = NSWidth([outlineView_stateList bounds]);
	CGFloat			 observedMargin = tableWidth - [column width];

	if ((fabs(tableWidth - clipWidth) < 0.5f) && (observedMargin >= 0.0f) && (observedMargin <= 32.0f)) {
		stateColumnMargin = observedMargin;
	}

	CGFloat			 targetWidth = clipWidth - stateColumnMargin;

	if (targetWidth < [column minWidth]) targetWidth = [column minWidth];
	if (targetWidth > [column maxWidth]) targetWidth = [column maxWidth];

	if (fabs([column width] - targetWidth) > 0.5f) [column setWidth:targetWidth];
}

/*!
 * @brief The list was resized: its column has to follow
 *
 * The form hands the scroll view the width of the card at every layout, and the outline view
 * follows it by its autoresizing mask; the column is the one thing which does not follow on its own.
 */
- (void)stateListFrameChanged:(NSNotification *)notification
{
	[self synchronizeStateColumnWidth];
}

/*!
 * @brief Update table control availability
 *
 * Updates table control availability based on the current state selection.  If no states are selected this method dims the
 * edit and delete buttons since they require a selection to function.  The edit and delete buttons are also
 * dimmed if the selected state is a built-in state.
 */
- (void)updateTableControlAvailability
{
//	NSArray *selectedItems = [outlineView_stateList arrayOfSelectedItems];
	NSIndexSet *selectedIndexes = [outlineView_stateList selectedRowIndexes];
	NSInteger			count = [selectedIndexes count];

	[button_editState setEnabled:(count && 
								  ([[outlineView_stateList itemAtRow:[selectedIndexes firstIndex]] mutabilityType] == AIEditableStatusState))];
	[button_addOrRemoveState setEnabled:count forSegment:1];
}

/*!
 * @brief Invoked when the state array changes
 *
 * This method is invoked when the state array changes.  In response, we hold onto the new array and refresh our state
 * list.
 */
- (void)stateArrayChanged:(NSNotification *)notification
{
	[outlineView_stateList reloadData];
	[self updateTableControlAvailability];

	/* Menus first, height second. A pop up row measures its button at every layout pass, and
	 * -updateStateListHeight is what triggers one - so filling the menus afterwards left the
	 * three buttons measured empty, which is a width of nothing and a row that looks like it has
	 * no control at all. It only ever corrected itself one notification late, when the next
	 * layout found the menus the previous round had built. */
	[self configureAutoAwayStatusStatePopUp];

	//The card is as tall as the list; a status more or less changes it
	[self updateStateListHeight];
}

//State Editing --------------------------------------------------------------------------------------------------------
#pragma mark State Editing
/*!
* @brief Edit the selected state
 *
 * Opens an edit state sheet for the selected state.  If the sheet is closed with success our
 * customStatusState:changedTo: method will be invoked and we can save the changes
 */
- (IBAction)editState:(id)sender
{
	NSInteger				selectedRow = [outlineView_stateList selectedRow];
	AIStatusItem	*statusState = [outlineView_stateList itemAtRow:selectedRow];
	
	if (statusState) {
		if ([statusState isKindOfClass:[AIStatus class]]) {
			[AIEditStateWindowController editCustomState:(AIStatus *)statusState
												 forType:statusState.statusType
											  andAccount:nil
										  withSaveOption:NO
												onWindow:[[self view] window]
										 notifyingTarget:self];
			
		} else if ([statusState isKindOfClass:[AIStatusGroup class]]) {
			ESEditStatusGroupWindowController *editStatusGroupWindowController = [[ESEditStatusGroupWindowController alloc] initWithStatusGroup:(AIStatusGroup *)statusState
																																notifyingTarget:self];
			[editStatusGroupWindowController showOnWindow:[[self view] window]];
		}
	}
}

/*!
* @brief State edited callback
 *
 * Invoked when the user successfully edits a state.  This method adds the new or updated state to Adium's state array.
 */
- (void)customStatusState:(AIStatus *)originalState changedTo:(AIStatus *)newState forAccount:(AIAccount *)account
{
	if (originalState) {
		/* As far the user was concerned, this was an edit.  The unique status ID should remain the same so that anything
		 * depending upon this status will update to using it.  Furthermore, since this may be a copy of originalState
		 * rather than the exact same object, we should update all accounts which are using this state to use the new copy
		 */
		[newState setUniqueStatusID:[originalState uniqueStatusID]];
		
		for (AIAccount *loopAccount in adium.accountController.accounts) {
			if (loopAccount.statusState == originalState) {
				[loopAccount setStatusStateAndRemainOffline:newState];
				
				[loopAccount notifyOfChangedPropertiesSilently:YES];
			}
		}

		[[originalState containingStatusGroup] replaceExistingStatusState:originalState withStatusState:newState];

		[originalState setUniqueStatusID:nil];

	} else {
		[adium.statusController addStatusState:newState];
	}
	
	[outlineView_stateList selectItemsInArray:[NSArray arrayWithObject:newState]];
	[outlineView_stateList scrollRowToVisible:[outlineView_stateList rowForItem:newState]];
}

- (void)finishedStatusGroupEdit:(AIStatusGroup *)inStatusGroup
{
	if (![inStatusGroup containingStatusGroup]) {
		//Add it if it's not already in a group
		[[adium.statusController rootStateGroup] addStatusItem:inStatusGroup atIndex:-1];

	} else {
		//Otherwise just save
		[adium.statusController savedStatusesChanged];
	}

	[outlineView_stateList selectItemsInArray:[NSArray arrayWithObject:inStatusGroup]];
	[outlineView_stateList scrollRowToVisible:[outlineView_stateList rowForItem:inStatusGroup]];
}

/*!
 * @brief Delete the selected state
 *
 * Deletes the selected state from Adium's state array.
 */
- (void)deleteState
{
	NSArray		 *selectedItems = [outlineView_stateList arrayOfSelectedItems];
	
	if ([selectedItems count]) {
		//Confirm deletion of a status group with contents
		NSUInteger			 numberOfItems = 0;

		for (AIStatusItem *statusItem in selectedItems) {
			if ([statusItem isKindOfClass:[AIStatusGroup class]] &&
				[[(AIStatusGroup *)statusItem flatStatusSet] count]) {
				numberOfItems += [[(AIStatusGroup *)statusItem flatStatusSet] count];
			} else {
				numberOfItems++;
			}
		}

		NSString *message = [NSString stringWithFormat:AILocalizedString(@"Are you sure you want to delete %lu saved status items?",nil),
							 numberOfItems];
		
		//Warn if deleting a group containing status items
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:AILocalizedString(@"Status Deletion Confirmation",nil)];
		[alert setInformativeText:message];
		[alert addButtonWithTitle:AILocalizedString(@"Delete", nil)];	//NSAlertFirstButtonReturn, was the default button
		[alert addButtonWithTitle:AILocalizedString(@"Cancel", nil)];	//NSAlertSecondButtonReturn, was the alternate button
		/* The former didEndSelector's contextInfo is now captured by the completion block,
		 * which retains selectedItems for us (blocks retain captured objects). */
		[alert beginSheetModalForWindow:[[self view] window] completionHandler:^(NSModalResponse returnCode) {
			if (returnCode == NSAlertFirstButtonReturn) {
				for (AIStatusItem *statusItem in selectedItems) {
					[[statusItem containingStatusGroup] removeStatusItem:statusItem];
				}
			}
		}];
	}
}

/*!
* @brief Add a new state
 *
 * Creates a new state.  This is done by invoking an edit window without passing it a base state.  When the edit window
 * returns successfully, it will invoke our customStatusState:changedTo: which adds the new state to Adium's state
 * array.
 */
- (void)newState
{
	[AIEditStateWindowController editCustomState:nil
										 forType:AIAwayStatusType
									  andAccount:nil
								  withSaveOption:NO
										onWindow:[[self view] window]
								 notifyingTarget:self];
}

- (IBAction)addGroup:(id)sender
{
	ESEditStatusGroupWindowController *editStatusGroupWindowController = [[ESEditStatusGroupWindowController alloc] initWithStatusGroup:nil
																														notifyingTarget:self];
	[editStatusGroupWindowController showOnWindow:[[self view] window]];
}

- (IBAction)addOrRemoveState:(id)sender
{
	NSInteger selectedSegment = [sender selectedSegment];
	
	switch (selectedSegment) {
		case 0:
			[self newState];
			break;
		case 1:
			[self deleteState];
			break;
	}
}

//State List OutlinView Delegate --------------------------------------------------------------------------------------------
#pragma mark State List (OutlineView Delegate)
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)idx ofItem:(id)item
{
	AIStatusGroup *statusGroup = (item ? item : [adium.statusController rootStateGroup]);
	
	return [[statusGroup containedStatusItems] objectAtIndex:idx];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	AIStatusGroup *statusGroup = (item ? item : [adium.statusController rootStateGroup]);
	
	return [[statusGroup containedStatusItems] count];	
}

- (NSString *)outlineView:(NSOutlineView *)outlineView typeSelectStringForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	if([[tableColumn identifier] isEqualToString:@"name"])
		return [item title] ? [item title] : @"";
	return @"";
}
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{

}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	NSString 		*identifier = [tableColumn identifier];
	
	if ([identifier isEqualToString:@"icon"]) {
		return ([item respondsToSelector:@selector(icon)] ? [item icon] : nil);
		
	} else if ([identifier isEqualToString:@"name"]) {
		NSImage *icon = ([item respondsToSelector:@selector(icon)] ? [item icon] : nil);
		
		if (icon) {
			NSMutableAttributedString *name;

			NSTextAttachment		*attachment;
			NSTextAttachmentCell	*cell;
			
			NSSize					iconSize = [icon size];
			
			if ((iconSize.width > 13) || (iconSize.height > 13)) {
				icon = [icon imageByScalingToSize:NSMakeSize(13, 13)];
			}

			cell = [[[NSTextAttachmentCell alloc] init] autorelease];
			[cell setImage:icon];
			
			attachment = [[[NSTextAttachment alloc] init] autorelease];
			[attachment setAttachmentCell:cell];
			
			name = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
			[name appendAttributedString:[[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" %@",([item title] ? [item title] : @"")]
																		  attributes:nil] autorelease]];
			return [name autorelease];
		} else {
			return [item title]; 
		}
	}
	
	return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [item isKindOfClass:[AIStatusGroup class]];
}

/*!
 * @brief A group was opened or closed
 *
 * The number of visible rows changed without the saved statuses moving, so nothing else will tell
 * the card to grow. Without this the opened group would scroll inside a card which is still as
 * tall as the closed one.
 */
- (void)outlineViewItemDidExpand:(NSNotification *)notification
{
	[self setStateListHeightNeedsUpdate];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
	[self setStateListHeightNeedsUpdate];
}

/*!
* @brief Delete the selected row
 */
- (void)outlineViewDeleteSelectedRows:(NSTableView *)tableView
{
    [self deleteState];
}

/*!
* @brief Selection change
 */
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	[self updateTableControlAvailability];
}

/*!
* @brief Drag start
 */
- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray*)items toPasteboard:(NSPasteboard*)pboard
{
	/* Release first: only a drag which ends in a drop clears this, so a drag let go of anywhere else
	 * leaves its items here until the next one takes their place. */
	[draggingItems release];
	draggingItems = [items retain];

    [pboard declareTypes:[NSArray arrayWithObject:STATE_DRAG_TYPE] owner:self];
    [pboard setString:@"State" forType:STATE_DRAG_TYPE]; //Arbitrary state

    return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)idx
{
	[self autoscrollPaneForDrag:info];

    if (idx == NSOutlineViewDropOnItemIndex && ![item isKindOfClass:[AIStatusGroup class]]) {
		AIStatusGroup *dropItem = [item containingStatusGroup];
		if (dropItem == [adium.statusController rootStateGroup])
			dropItem = nil;

		[outlineView setDropItem:dropItem
				  dropChildIndex:[[[item containingStatusGroup] containedStatusItems] indexOfObjectIdenticalTo:item]];
	}
     
	return NSDragOperationPrivate;
}

/*!
 * @brief Follow a drag which has reached the edge of the window
 *
 * AppKit's own drag autoscrolling asks the clip view the list sits in, and that one has nothing to
 * scroll: the list is as tall as its rows. It does not walk any further out either, so with a card
 * taller than the window a drop position below the fold could not be reached at all - and moving
 * statuses about is what this list is for. The scrolling therefore happens one scroll view further
 * out, the one the preferences window scrolls its column with.
 *
 * Best effort by its nature: it moves whenever the outline view asks us to validate a drop, so a
 * pointer held perfectly still at the edge may need a nudge. Which end of the visible area the
 * pointer is at decides the direction, so it reads the same whether that view is flipped or not.
 */
- (void)autoscrollPaneForDrag:(id <NSDraggingInfo>)info
{
	NSView		*ancestor = [scrollView_stateList superview];

	while (ancestor && ![ancestor isKindOfClass:[NSScrollView class]])
		ancestor = [ancestor superview];

	if (!ancestor) return;

	NSScrollView	*paneScrollView = (NSScrollView *)ancestor;
	NSClipView		*clipView = [paneScrollView contentView];
	NSRect			 visible = [clipView bounds];
	NSPoint			 point = [clipView convertPoint:[info draggingLocation] fromView:nil];
	//One row at a time, and the same distance from the edge at which the scrolling starts
	CGFloat			 step = [outlineView_stateList rowHeight] + [outlineView_stateList intercellSpacing].height;
	CGFloat			 delta = 0.0f;

	if (NSHeight(visible) <= (3.0f * step)) return;

	if (point.y < (NSMinY(visible) + step)) delta = -step;
	else if (point.y > (NSMaxY(visible) - step)) delta = step;

	if (delta == 0.0f) return;

	NSRect			 target = visible;

	target.origin.y += delta;

	[clipView scrollToPoint:[clipView constrainBoundsRect:target].origin];
	[paneScrollView reflectScrolledClipView:clipView];
}

/*!
* @brief Drag complete
 */
- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)idx
{
    NSString	*avaliableType = [[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:STATE_DRAG_TYPE]];
    if ([avaliableType isEqualToString:STATE_DRAG_TYPE]) {
		[adium.statusController setDelayStatusMenuRebuilding:YES];
		delayedStatusMenuRebuilding = YES;

		if (!item) item = [adium.statusController rootStateGroup];

		AIStatusItem *statusItem;
		

		for (statusItem in draggingItems) {
			if ([statusItem containingStatusGroup] == item) {
				BOOL shouldIncrement = NO;
				if ([[[statusItem containingStatusGroup] containedStatusItems] indexOfObject:statusItem] > idx) {
					shouldIncrement = YES;
				}
				
				//Move the state and select it in the new location
				[item moveStatusItem:statusItem toIndex:idx];
				
				if (shouldIncrement) idx++;
			} else {
				//Don't let an object be moved into itself...
				if (item != statusItem) {
					[statusItem retain];
					[[statusItem containingStatusGroup] removeStatusItem:statusItem];
					[item addStatusItem:statusItem atIndex:idx];
					[statusItem release];
					
					idx++;
				}
			}
		}

		//Notify and reselect outside of the NSOutlineView callback
		[self performSelector:@selector(reselectDraggedItems:)
				   withObject:draggingItems
				   afterDelay:0];

		[draggingItems release]; draggingItems = nil;

        return YES;
    } else {
        return NO;
    }
}

- (void)reselectDraggedItems:(NSArray *)theDraggedItems
{
	delayedStatusMenuRebuilding = NO;
	[adium.statusController setDelayStatusMenuRebuilding:NO];

	[outlineView_stateList selectItemsInArray:theDraggedItems];
	[outlineView_stateList scrollRowToVisible:[outlineView_stateList rowForItem:[theDraggedItems objectAtIndex:0]]];

	/* A state dragged into a collapsed group leaves fewer visible rows behind than there were, so
	 * the card has to be refitted even though nothing was added or removed. */
	[self updateStateListHeight];
}

#pragma mark Other status-related controls

/*!
 * @brief Configure initial values for idle, auto-away, etc., preferences.
 */

- (void)configureOtherControls
{
	NSDictionary	*prefDict = [adium.preferenceController preferencesForGroup:PREF_GROUP_STATUS_PREFERENCES];

	[checkBox_idle setState:([[prefDict objectForKey:KEY_STATUS_REPORT_IDLE] boolValue] ?
							 NSControlStateValueOn : NSControlStateValueOff)];
	[self showMinutes:([[prefDict objectForKey:KEY_STATUS_REPORT_IDLE_INTERVAL] doubleValue] / 60.0)
			  inField:textField_idleMinutes
			  stepper:stepper_idleMinutes];

	[checkBox_awayReminder setState:([[prefDict objectForKey:KEY_STATUS_AWAY_REMINDER] boolValue] ?
									 NSControlStateValueOn : NSControlStateValueOff)];
	[self showMinutes:([[prefDict objectForKey:KEY_STATUS_AWAY_REMINDER_INTERVAL] doubleValue] / 60.0)
			  inField:textField_awayReminderMinutes
			  stepper:stepper_awayReminderMinutes];

	[self configureControlDimming];
}

/*!
 * @brief Show the stored values again, unless the user is in the middle of typing one
 *
 * Called when the pane is handed out for display a second time. A field which is being edited right
 * now belongs to the user, not to us: -view is also asked for the pane's window when a sheet is
 * opened from one of the list's buttons, and taking a half typed number off the screen at that
 * moment would be worse than the stale number this exists to clear away.
 */
- (void)refreshDisplayedValues
{
	for (NSTextField *field in [NSArray arrayWithObjects:
								textField_idleMinutes, textField_awayReminderMinutes, nil]) {
		if ([field currentEditor]) return;
	}

	[self configureOtherControls];
}

/*!
 * @brief Put a stored interval on screen, in both halves of its row
 *
 * Rounded to whole minutes, because that is what the field and the stepper can express, but
 * otherwise shown exactly as it is stored: the number in the field is the setting, always. A value
 * from before this pane had a stepper may well lie outside the stepper's range - an interval of a
 * whole day, say - and clamping the field to that range would put a number on screen which is not
 * the setting and which one click of the stepper would then make true. The stepper alone takes what
 * it can of such a value.
 */
- (void)showMinutes:(double)minutes inField:(NSTextField *)field stepper:(NSStepper *)stepper
{
	NSInteger	rounded = (NSInteger)round(minutes);

	[field setIntegerValue:rounded];
	//Out of range in either direction, the stepper stops at its own end; it never writes on its own
	[stepper setIntegerValue:rounded];
}

/*!
 * @brief Configure the pop up of states for autoAway.
 *
 * Should be called by stateArrayChanged: both for initial set up and for updating when the states change.
 */
- (void)configureAutoAwayStatusStatePopUp
{
	NSMenu		*statusStatesMenu;
	NSNumber	*targetUniqueStatusIDNumber;

	/* The three menus are about to be thrown away and built again, so whatever separator plus
	 * imitation item -addItemIfNeeded:… had appended to them goes with them. Forgetting to say so
	 * is a trap: the next -changed*Status: would take "already showing" at its word and remove the
	 * last two items of the fresh menu, which are real statuses. */
	showingSubmenuItemInAutoAway = NO;
	showingSubmenuItemInFastUserSwitching = NO;
	showingSubmenuItemInScreenSaver = NO;

	statusStatesMenu = [AIStatusMenu staticStatusStatesMenuNotifyingTarget:self selector:@selector(changedAutoAwayStatus:)];
	[self prependDoNotChangeItemToMenu:statusStatesMenu action:@selector(changedAutoAwayStatus:)];
	[popUp_autoAwayStatusState setMenu:statusStatesMenu];

	statusStatesMenu = [AIStatusMenu staticStatusStatesMenuNotifyingTarget:self selector:@selector(changedFastUserSwitchingStatus:)];
	[self prependDoNotChangeItemToMenu:statusStatesMenu action:@selector(changedFastUserSwitchingStatus:)];
	[popUp_fastUserSwitchingStatusState setMenu:[[statusStatesMenu copy] autorelease]];

	statusStatesMenu = [AIStatusMenu staticStatusStatesMenuNotifyingTarget:self selector:@selector(changedScreenSaverStatus:)];
	[self prependDoNotChangeItemToMenu:statusStatesMenu action:@selector(changedScreenSaverStatus:)];
	[popUp_screenSaverStatusState setMenu:[[statusStatesMenu copy] autorelease]];

	//Now select the proper state, or deselect all items if there is no chosen state or the chosen state doesn't exist
	targetUniqueStatusIDNumber = [adium.preferenceController preferenceForKey:KEY_STATUS_AUTO_AWAY_STATUS_STATE_ID
																		  group:PREF_GROUP_STATUS_PREFERENCES];
	[self _selectStatusWithUniqueID:targetUniqueStatusIDNumber inPopUpButton:popUp_autoAwayStatusState];
	
	targetUniqueStatusIDNumber = [adium.preferenceController preferenceForKey:KEY_STATUS_FUS_STATUS_STATE_ID
																		  group:PREF_GROUP_STATUS_PREFERENCES];
	[self _selectStatusWithUniqueID:targetUniqueStatusIDNumber inPopUpButton:popUp_fastUserSwitchingStatusState];	
	
	targetUniqueStatusIDNumber = [adium.preferenceController preferenceForKey:KEY_STATUS_SS_STATUS_STATE_ID
																		  group:PREF_GROUP_STATUS_PREFERENCES];
	[self _selectStatusWithUniqueID:targetUniqueStatusIDNumber inPopUpButton:popUp_screenSaverStatusState];

	/* A pop up row is measured afresh at every layout, so a menu which just gained or lost a
	 * status only needs to be told that a layout is due. */
	[[self settingsForm] noteContentSizeChanged];
}

/*!
 * @brief Put "Do not change" plus a separator at the top of a status menu
 *
 * This entry <em>is</em> the off switch of an automatic status change; the three checkboxes which
 * used to do that job are gone, and a checkbox whose meaning lives in a menu below it said the same
 * thing twice. Its represented object is deliberately nil, so -changed…Status: recognises it by
 * finding no status behind it and writes STATUS_STATE_ID_NONE.
 */
- (void)prependDoNotChangeItemToMenu:(NSMenu *)menu action:(SEL)action
{
	NSMenuItem	*doNotChange = [[[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Do not change","First entry of the menus choosing a status Adium sets on its own; it means: leave the status alone")
														  action:action
												   keyEquivalent:@""] autorelease];

	[doNotChange setTarget:self];

	[menu insertItem:[NSMenuItem separatorItem] atIndex:0];
	[menu insertItem:doNotChange atIndex:0];
}

/*!
 * @brief Add all items in inMenu to an array, returning the resulting array
 *
 * This method adds items deeply; that is, submenus and their contents are recursively included
 *
 * @param inMenu The menu to start from
 * @param recursiveArray The array thus far; if nil an array will be created
 *
 * @result All the menu items in inMenu
 */
- (NSMutableArray *)addItemsFromMenu:(NSMenu *)inMenu toArray:(NSMutableArray *)recursiveArray
{
	NSArray			*itemArray = [inMenu itemArray];
	NSMenuItem		*menuItem;

	if (!recursiveArray) recursiveArray = [NSMutableArray array];

	for (menuItem in itemArray) {
		[recursiveArray addObject:menuItem];

		if ([menuItem submenu]) {
			[self addItemsFromMenu:[menuItem submenu] toArray:recursiveArray];
		}
	}

	return recursiveArray;
}

/*!
 * @brief Select a status with uniqueID in inPopUpButton
 *
 * An ID no status answers to — STATUS_STATE_ID_NONE, or one whose status has since been deleted —
 * selects the first entry, "Do not change". It has to select something now: the menus are the only
 * place left where an automatic status change is switched off, and a button showing nothing at all
 * would not say which of its entries is in force.
 */
- (void)_selectStatusWithUniqueID:(NSNumber *)uniqueID inPopUpButton:(NSPopUpButton *)inPopUpButton
{
	NSMenuItem	*menuItem = nil;
	
	if (uniqueID) {
		NSInteger			 targetUniqueStatusID= [uniqueID integerValue];

		for (NSMenuItem *candidate in [self addItemsFromMenu:[inPopUpButton menu] toArray:nil]) {
			AIStatusItem	*statusState;

			statusState = [[candidate representedObject] objectForKey:@"AIStatus"];

			/* Found the right status by matching its status ID to our preferred one. Only an item
			 * with a real status behind it may match: separators and our own "Do not change" carry
			 * no represented object, and [nil preexistingUniqueStatusID] is 0 - which would answer
			 * to a stored ID of 0 and select a separator. */
			if (statusState && ([statusState preexistingUniqueStatusID] == targetUniqueStatusID)) {
				menuItem = candidate;
				break;
			}
		}
	}

	if (!menuItem) {
		//Nothing to select: fall back on "Do not change", which we put at the top ourselves
		if ([[inPopUpButton menu] numberOfItems]) [inPopUpButton selectItemAtIndex:0];

	} else {
		[inPopUpButton selectItem:menuItem];

		//Add it if we weren't able to select it initially
		if (![inPopUpButton selectedItem]) {
			[self addItemIfNeeded:menuItem toPopUpButton:inPopUpButton alreadyShowingAnItem:NO];
			
			if (inPopUpButton == popUp_autoAwayStatusState) {
				showingSubmenuItemInAutoAway = YES;
				
			} else if (inPopUpButton == popUp_fastUserSwitchingStatusState) {
				showingSubmenuItemInFastUserSwitching = YES;
				
			} else if (inPopUpButton == popUp_screenSaverStatusState) {
				showingSubmenuItemInScreenSaver = YES;
				
			}
		}
	}
}

/*!
 * @brief Configure control dimming for idle, auto-away, etc., preferences.
 *
 * Every dependent control still follows the switch above it. The two unit labels are here because a
 * row of the form has a label of its own which follows the enabled state of the trailing-most
 * control of the row — that is the unit label, so without these lines the labels on the left would
 * never grey out with their row.
 *
 * Two of the three status menus are never dimmed: the ones for the fast user switch and for the
 * screen saver carry their own off switch in their first entry, and nothing above them could take
 * them away. The third is not like them. It hangs on the switch for being reported as idle, because
 * AIAutomaticStatus only ever sets the idle bit inside "reporting is on and the duration has run
 * out" — with the switch off, a status chosen here would never be set. Left black and usable it
 * would be exactly the thing this pane was rebuilt to be rid of, only the other way round: not a
 * setting which works while being invisible, but one which is visible while doing nothing.
 */
- (void)configureControlDimming
{
	BOOL	idleControlsEnabled, awayReminderControlsEnabled;

	idleControlsEnabled = ([checkBox_idle state] == NSControlStateValueOn);
	[textField_idleMinutes setEnabled:idleControlsEnabled];
	[stepper_idleMinutes setEnabled:idleControlsEnabled];
	[label_idleMinutes setEnabled:idleControlsEnabled];
	[popUp_autoAwayStatusState setEnabled:idleControlsEnabled];

	awayReminderControlsEnabled = ([checkBox_awayReminder state] == NSControlStateValueOn);
	[textField_awayReminderMinutes setEnabled:awayReminderControlsEnabled];
	[stepper_awayReminderMinutes setEnabled:awayReminderControlsEnabled];
	[label_awayReminderMinutes setEnabled:awayReminderControlsEnabled];
}

/*!
 * @brief Change preference
 *
 * Sent when one of the two switches is clicked. Each of them writes there and then: the
 * preferences window only calls -closeView when it closes — switching to another pane takes the
 * view out with -removeFromSuperview — so there is no later point at which anything could be
 * saved.
 */
- (IBAction)changePreference:(id)sender
{
	/* Read the state through the ivar rather than through sender: -state is declared on NSSwitch
	 * and on NSButton alike, and asking an untyped id for it leaves the compiler to pick one. */
	if (sender == checkBox_idle) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_idle state] == NSControlStateValueOn)]
											 forKey:KEY_STATUS_REPORT_IDLE
											  group:PREF_GROUP_STATUS_PREFERENCES];

	} else if (sender == checkBox_awayReminder) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_awayReminder state] == NSControlStateValueOn)]
											 forKey:KEY_STATUS_AWAY_REMINDER
											  group:PREF_GROUP_STATUS_PREFERENCES];

	}

	[self configureControlDimming];
}

/*!
 * @brief If menuItem is not selectable in popUpButton, add it and select it
 *
 * Menu items located within submenus can't be directly selected. This method will add a spearator item and then the item itself
 * to the bottom of popUpButton if needed.  alreadyShowing should be YES if a similarly set separate + item exists; it will be removed
 * first.
 *
 * @result YES if the item was added to popUpButton.
 */
- (BOOL)addItemIfNeeded:(NSMenuItem *)menuItem toPopUpButton:(NSPopUpButton *)popUpButton alreadyShowingAnItem:(BOOL)alreadyShowing
{
	BOOL	nowShowing = NO;
	NSMenu	*menu = [popUpButton menu];

	[menuItem retain];
	if (alreadyShowing) {
		NSInteger count = [menu numberOfItems];
		[menu removeItemAtIndex:--count];
		[menu removeItemAtIndex:--count];			
	}
	
	if ([popUpButton selectedItem] != menuItem) {
		NSMenuItem  *imitationMenuItem = [menuItem copy];
		
		[menu addItem:[NSMenuItem separatorItem]];
		[menu addItem:imitationMenuItem];
		
		[popUpButton selectItem:imitationMenuItem];
		[imitationMenuItem release];
		
		nowShowing = YES;
	}	
	[menuItem release];
	
	return nowShowing;
}
/*!
 * @brief The status ID a menu item stands for, or "do not change" for the first entry
 *
 * The "Do not change" item carries no represented object, and STATUS_STATE_ID_NONE is what has to
 * be written for it — not nil, which would let the default take over again.
 */
- (NSNumber *)statusIDForSelectedMenuItem:(id)sender
{
	AIStatus	*statusState = [[sender representedObject] objectForKey:@"AIStatus"];

	return (statusState ?
			[statusState uniqueStatusID] :
			[NSNumber numberWithInteger:STATUS_STATE_ID_NONE]);
}

- (void)changedAutoAwayStatus:(id)sender
{
	[adium.preferenceController setPreference:[self statusIDForSelectedMenuItem:sender]
										 forKey:KEY_STATUS_AUTO_AWAY_STATUS_STATE_ID
										  group:PREF_GROUP_STATUS_PREFERENCES];

	showingSubmenuItemInAutoAway = [self addItemIfNeeded:sender
										   toPopUpButton:popUp_autoAwayStatusState
									alreadyShowingAnItem:showingSubmenuItemInAutoAway];
}

- (void)changedFastUserSwitchingStatus:(id)sender
{
	[adium.preferenceController setPreference:[self statusIDForSelectedMenuItem:sender]
										 forKey:KEY_STATUS_FUS_STATUS_STATE_ID
										  group:PREF_GROUP_STATUS_PREFERENCES];

	showingSubmenuItemInFastUserSwitching = [self addItemIfNeeded:sender
													toPopUpButton:popUp_fastUserSwitchingStatusState
											 alreadyShowingAnItem:showingSubmenuItemInFastUserSwitching];
}

- (void)changedScreenSaverStatus:(id)sender
{
	[adium.preferenceController setPreference:[self statusIDForSelectedMenuItem:sender]
										 forKey:KEY_STATUS_SS_STATUS_STATE_ID
										  group:PREF_GROUP_STATUS_PREFERENCES];

	showingSubmenuItemInScreenSaver = [self addItemIfNeeded:sender
													toPopUpButton:popUp_screenSaverStatusState
											 alreadyShowingAnItem:showingSubmenuItemInScreenSaver];
}

/*!
 * @brief A minutes field or its stepper changed; write that interval now
 *
 * The one place both time settings are written. Every click of a stepper and every keystroke
 * in a field lands here, and the value goes straight into the preferences: the preferences window
 * only calls -closeView when the window itself closes, so leaving this pane through the sidebar is
 * not a point at which anything could still be saved. The old pane wrote the idle and auto away
 * intervals from -viewWillClose alone, which is exactly why a value set with a stepper used to
 * survive closing the window but not switching to another pane.
 */
- (IBAction)changedTimeValue:(id)sender
{
	if (sender == stepper_idleMinutes || sender == textField_idleMinutes) {
		[self commitMinutesFromField:textField_idleMinutes
							 stepper:stepper_idleMinutes
							  sender:sender
							  forKey:KEY_STATUS_REPORT_IDLE_INTERVAL];

	} else if (sender == stepper_awayReminderMinutes || sender == textField_awayReminderMinutes) {
		[self commitMinutesFromField:textField_awayReminderMinutes
							 stepper:stepper_awayReminderMinutes
							  sender:sender
							  forKey:KEY_STATUS_AWAY_REMINDER_INTERVAL];
	}
}

/*!
 * @brief Keep a field and its stepper in step and store what they now say, in seconds
 *
 * Whichever half the user touched is the one that is believed; the other is brought up to it. A
 * field is read through its field editor while it is being edited, because -stringValue is still
 * the last committed text until then.
 *
 * A blank field, a zero and a half typed number are what the user passes through on the way to a
 * real value, not settings: they leave both the stepper and the preference alone. The stepper
 * cannot produce them at all — it starts at one minute and no longer wraps round.
 *
 * A typed value above the stepper's range is written as typed. The stepper stops at its own end,
 * but the setting is the user's to make: the pane used to take any number of minutes and there is
 * no reason for the range of a stepper to become the range of a preference.
 */
- (void)commitMinutesFromField:(NSTextField *)field
					   stepper:(NSStepper *)stepper
						sender:(id)sender
						forKey:(NSString *)key
{
	NSInteger	minutes;

	if (sender == stepper) {
		minutes = [stepper integerValue];
		[field setIntegerValue:minutes];

	} else {
		NSText		*editor = [field currentEditor];

		minutes = (editor ? [[editor string] integerValue] : [field integerValue]);

		if (minutes < MINUTES_MINIMUM) return;

		[stepper setIntegerValue:minutes];
	}

	[adium.preferenceController setPreference:[NSNumber numberWithDouble:(minutes * 60.0)]
									   forKey:key
										group:PREF_GROUP_STATUS_PREFERENCES];
}

/*!
 * @brief Control text did end editing
 *
 * The value itself is already in the preferences twice over by now — once per keystroke through
 * -controlTextDidChange:, and once more through the field's own action, which it sends on Return,
 * on Tab and when the focus moves away. What is left to do here is the other half: if the field
 * was left holding something which was never written — blank, or below a minute — put the stored
 * setting back on screen, so that the number standing there is always the setting.
 *
 * This only covers the ways out which end editing. Leaving the pane through the sidebar is not one
 * of them; -view puts the values back when the pane is shown again.
 */
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	NSTextField		*field = [notification object];

	if ([field integerValue] < MINUTES_MINIMUM) [self configureOtherControls];
}

/*!
 * @brief Something which is not a number was left in a field
 *
 * Saying yes here means: end the editing anyway. The alternative is AppKit's own answer, which is
 * to put up an alert and keep the focus in the field until a number is typed — and the field a user
 * has just emptied to type a new value into holds exactly such a string. Nothing is accepted by
 * saying yes: the field keeps its old value, -controlTextDidEndEditing: then puts the setting back
 * on screen, and the preference was never touched.
 */
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error
{
	return YES;
}

/*!
 * @brief Control text did change
 *
 * Every keystroke is written, not only the committed value. Taking a preference pane off screen
 * does not end editing — the preferences window simply removes the view — so a number which had
 * only reached the field editor would otherwise be lost on the way to another pane. Half typed
 * numbers cost nothing here: -commitMinutesFromField:… drops anything below a minute, and the
 * user is on their way to a real value in the same second — and what such a field is left showing
 * is put right the next time the pane is shown (see -view).
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	[self changedTimeValue:[notification object]];
}

@end
