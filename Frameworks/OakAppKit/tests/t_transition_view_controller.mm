#import <OakAppKit/OakTransitionViewController.h>
#import <OakAppKit/OakScaledContainerView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import "TransitionToolbarDelegate.h"

static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

// A pane with a fixed autolayout fitting size, as the code-built preference panes have.
static NSView* paneOfSize (CGFloat width, CGFloat height)
{
	NSView* res = [[NSView alloc] initWithFrame:NSZeroRect];
	NSView* inner = [[NSView alloc] initWithFrame:NSZeroRect];
	inner.translatesAutoresizingMaskIntoConstraints = NO;
	[res addSubview:inner];
	[NSLayoutConstraint activateConstraints:@[
		[inner.widthAnchor constraintEqualToConstant:width],
		[inner.heightAnchor constraintEqualToConstant:height],
		[inner.leadingAnchor constraintEqualToAnchor:res.leadingAnchor],
		[inner.trailingAnchor constraintEqualToAnchor:res.trailingAnchor],
		[inner.topAnchor constraintEqualToAnchor:res.topAnchor],
		[inner.bottomAnchor constraintEqualToAnchor:res.bottomAnchor],
	]];
	return res;
}

// A pane laid out with autoresizing masks and no constraints, as a xib pane
// (Terminal) has: its frame is its only size.
static NSView* xibPaneOfSize (CGFloat width, CGFloat height)
{
	NSView* res = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	NSButton* button = [[NSButton alloc] initWithFrame:NSMakeRect(width - 110, 12, 100, 32)];
	button.autoresizingMask = NSViewMinXMargin;
	[res addSubview:button];
	return res;
}

static NSWindow* windowOfSize (CGFloat width, CGFloat height)
{
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	return [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(visible) + 100, NSMinY(visible) + 350, width, height) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
}

// The window is resized by the difference between the old and the new pane.
void test_window_follows_pane_size ()
{
	inject(nil);
	NSWindow* window = windowOfSize(300, 150);
	OakTransitionViewController* controller = [[OakTransitionViewController alloc] init];
	window.contentView = controller.view;

	controller.subview = paneOfSize(200, 100);
	[window layoutIfNeeded];
	NSRect content = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(content), 200.0);
	OAK_ASSERT_EQ(NSHeight(content), 100.0);

	controller.subview = paneOfSize(100, 50);
	[window layoutIfNeeded];
	content = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(content), 100.0);
	OAK_ASSERT_EQ(NSHeight(content), 50.0);
	[window close];
}

// Inside a scaled container the panes lay out in their own points but the
// window is scale times larger, so the difference between the panes must be
// taken in window points, or the window ends up sized for scale 1.
void test_window_follows_pane_size_through_scaled_container ()
{
	inject(@2);
	NSWindow* window = windowOfSize(300, 150);
	OakTransitionViewController* controller = [[OakTransitionViewController alloc] init];
	OakSetScaledWindowContentView(window, controller.view);
	[window layoutIfNeeded];

	controller.subview = paneOfSize(200, 100);
	[window layoutIfNeeded];
	NSRect content = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(content), 400.0);
	OAK_ASSERT_EQ(NSHeight(content), 200.0);
	OAK_ASSERT_EQ(NSWidth(controller.view.frame), 200.0); // the pane keeps its own points
	OAK_ASSERT_EQ(NSHeight(controller.view.frame), 100.0);

	controller.subview = paneOfSize(100, 50);
	[window layoutIfNeeded];
	content = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(content), 200.0);
	OAK_ASSERT_EQ(NSHeight(content), 100.0);
	OAK_ASSERT_EQ(NSWidth(controller.view.frame), 100.0);
	OAK_ASSERT_EQ(NSHeight(controller.view.frame), 50.0);
	[window close];
	inject(nil);
}

// Preferences builds its window with windowWithContentViewController: and
// then puts the container in; a xib pane has no constraints, so the container
// must not hold the content at whatever size it had when installed.
void test_xib_panes_in_window_from_content_view_controller ()
{
	inject(@2);
	OakTransitionViewController* controller = [[OakTransitionViewController alloc] init];
	NSWindow* window = [NSPanel windowWithContentViewController:controller];
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	[window setFrameTopLeftPoint:NSMakePoint(NSMinX(visible) + 100, NSMinY(visible) + 550)];
	OakSetScaledWindowContentView(window, controller.view);
	[window layoutIfNeeded];

	NSView* wide = xibPaneOfSize(400, 200);
	controller.subview = wide;
	[window layoutIfNeeded];
	NSRect content = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(content), 800.0);
	OAK_ASSERT_EQ(NSHeight(content), 400.0);
	OAK_ASSERT_EQ(NSWidth(wide.frame), 400.0);
	OAK_ASSERT_EQ(NSHeight(wide.frame), 200.0);

	NSView* narrow = xibPaneOfSize(200, 100);
	controller.subview = narrow;
	[window layoutIfNeeded];
	content = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(content), 400.0);
	OAK_ASSERT_EQ(NSHeight(content), 200.0);
	OAK_ASSERT_EQ(NSWidth(controller.view.frame), 200.0); // not held at the wide pane’s size
	OAK_ASSERT_EQ(NSHeight(controller.view.frame), 100.0);
	OAK_ASSERT_EQ(NSWidth(narrow.frame), 200.0);
	OAK_ASSERT_EQ(NSHeight(narrow.frame), 100.0);
	[window close];
	inject(nil);
}

// While a toolbar is added, AppKit gives the window content a transient
// height. A container places its content by frame, which becomes required
// constraints, and the empty transition view is pinned to zero height by a
// constraint of its own: if that one is required as well, the layout is
// unsatisfiable and AppKit raises (Preferences at init). The transient does
// not happen in a window that is never shown, so the priority is checked.
void test_empty_view_survives_toolbar_in_scaled_container ()
{
	inject(@2);
	OakTransitionViewController* controller = [[OakTransitionViewController alloc] init];
	NSLayoutConstraint* emptyHeight = nil;
	for(NSLayoutConstraint* constraint in controller.view.constraints)
	{
		if(constraint.firstAttribute == NSLayoutAttributeHeight && constraint.constant == 0)
			emptyHeight = constraint;
	}
	OAK_ASSERT(emptyHeight != nil);
	OAK_ASSERT(emptyHeight.priority < NSLayoutPriorityRequired);

	NSWindow* window = [NSPanel windowWithContentViewController:controller];
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	[window setFrameTopLeftPoint:NSMakePoint(NSMinX(visible) + 100, NSMinY(visible) + 550)];
	OakSetScaledWindowContentView(window, controller.view);

	TransitionToolbarDelegate* delegate = [[TransitionToolbarDelegate alloc] init];
	NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"t_transition_view_controller"];
	toolbar.delegate = delegate;
	toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
	window.toolbar = toolbar;
	window.toolbarStyle = NSWindowToolbarStylePreference;
	[window layoutIfNeeded];

	controller.subview = paneOfSize(200, 100);
	[window layoutIfNeeded];
	NSRect content = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(content), 400.0);
	OAK_ASSERT_EQ(NSHeight(content), 200.0);
	[window close];
	inject(nil);
}

// A pane whose constraints fix its size, as a grid with explicit column
// widths does (Files, Projects): it can only ever be width × height.
static NSView* rigidPaneOfSize (CGFloat width, CGFloat height)
{
	NSView* res = paneOfSize(width, height);
	NSView* inner = res.subviews.firstObject;
	for(NSLayoutConstraint* constraint in inner.constraints)
		constraint.priority = NSLayoutPriorityRequired;
	return res;
}

// The view can be larger than its subview: the window was resized by the
// user, or a fractional interface scale (1.4) rounded the window up by a
// fraction of a point. A subview whose size is fixed by required constraints
// must then keep its size at the top-left rather than make the layout
// unsatisfiable, which AppKit raises on. The view is sized by the container
// here, as in Preferences; as a content view it would be sized by its own
// constraints and never be larger.
void test_rigid_subview_in_larger_view_keeps_its_size ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	NSWindow* window = windowOfSize(300, 150);
	OakTransitionViewController* controller = [[OakTransitionViewController alloc] init];
	OakSetScaledWindowContentView(window, controller.view);
	[window layoutIfNeeded];

	NSView* pane = rigidPaneOfSize(200, 100);
	controller.subview = pane;
	[window layoutIfNeeded];
	OAK_ASSERT_EQ(NSWidth(controller.view.frame), 200.0);

	BOOL raised = NO;
	@try {
		[window setContentSize:NSMakeSize(300, 150)];
		[window layoutIfNeeded];
	}
	@catch(NSException* e) {
		raised = YES;
	}
	OAK_ASSERT(!raised);
	OAK_ASSERT_EQ(NSWidth(controller.view.frame), 300.0);
	OAK_ASSERT_EQ(NSHeight(controller.view.frame), 150.0);
	OAK_ASSERT_EQ(NSWidth(pane.frame), 200.0);
	OAK_ASSERT_EQ(NSHeight(pane.frame), 100.0);
	OAK_ASSERT_EQ(NSMinX(pane.frame), 0.0);
	OAK_ASSERT_EQ(NSMaxY(pane.frame), 150.0); // stays at the top

	// While switching, the outgoing view is held at its frame size. A frame
	// that does not match the view’s required size (at scale 1.4 the Files
	// grid was 622.143 wide for 622 of required columns) must not be
	// unsatisfiable either.
	pane.frame = NSMakeRect(0, 0, 300, 150);
	raised = NO;
	@try {
		controller.subview = rigidPaneOfSize(100, 50);
		[window layoutIfNeeded];
	}
	@catch(NSException* e) {
		raised = YES;
	}
	OAK_ASSERT(!raised);
	OAK_ASSERT_EQ(NSWidth(pane.frame), 200.0); // its own size, whatever the frame said
	[window close];
}
