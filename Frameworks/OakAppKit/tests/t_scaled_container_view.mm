#import <OakAppKit/OakScaledContainerView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

// A content view with a fixed autolayout fitting size.
static NSView* contentOfSize (CGFloat width, CGFloat height)
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

// The usual 100 × 50 content.
static NSView* content ()
{
	return contentOfSize(100, 50);
}

void test_scale_that_fits ()
{
	OAK_ASSERT_EQ(OakUIScaleThatFits(NSMakeSize(500, 300), NSMakeSize(1000, 1000), 2), 2.0);
	OAK_ASSERT_EQ(OakUIScaleThatFits(NSMakeSize(500, 300), NSMakeSize(800, 1000), 2), 1.6);  // width bound
	OAK_ASSERT_EQ(OakUIScaleThatFits(NSMakeSize(500, 300), NSMakeSize(2000, 450), 2), 1.5);  // height bound
	OAK_ASSERT_EQ(OakUIScaleThatFits(NSMakeSize(500, 300), NSMakeSize(400, 200), 2), 1.0);   // never below 1
	OAK_ASSERT_EQ(OakUIScaleThatFits(NSMakeSize(500, 300), NSMakeSize(1000, 1000), 0.9), 0.9); // shrinking is untouched
	OAK_ASSERT_EQ(OakUIScaleThatFits(NSMakeSize(0, 0), NSMakeSize(1000, 1000), 2), 2.0);    // degenerate design size
}

void test_identity_at_scale_one ()
{
	inject(nil);
	OakScaledContainerView* container = [[OakScaledContainerView alloc] initWithContentView:content()];
	OAK_ASSERT_EQ(container.effectiveScale, 1.0);
	OAK_ASSERT_EQ(container.intrinsicContentSize.width, 100.0);
	OAK_ASSERT_EQ(container.intrinsicContentSize.height, 50.0);

	[container setFrameSize:NSMakeSize(300, 200)];
	[container layoutSubtreeIfNeeded];
	OAK_ASSERT_EQ(container.bounds.size.width, 300.0);
	OAK_ASSERT_EQ(container.contentView.frame.size.width, 300.0);
	OAK_ASSERT_EQ(container.contentView.frame.size.height, 200.0);
}

void test_intrinsic_size_and_bounds_follow_scale ()
{
	inject(@2);
	OakScaledContainerView* container = [[OakScaledContainerView alloc] initWithContentView:content()];
	OAK_ASSERT_EQ(container.effectiveScale, 2.0);
	OAK_ASSERT_EQ(container.intrinsicContentSize.width, 200.0);
	OAK_ASSERT_EQ(container.intrinsicContentSize.height, 100.0);

	// The window gives the container 400 × 200 points; the content lays out in 200 × 100.
	[container setFrameSize:NSMakeSize(400, 200)];
	[container layoutSubtreeIfNeeded];
	OAK_ASSERT_EQ(container.bounds.size.width, 200.0);
	OAK_ASSERT_EQ(container.bounds.size.height, 100.0);
	OAK_ASSERT_EQ(container.contentView.frame.origin.x, 0.0);
	OAK_ASSERT_EQ(container.contentView.frame.size.width, 200.0);
	OAK_ASSERT_EQ(container.contentView.frame.size.height, 100.0);
	inject(nil);
}

// The content view keeps translatesAutoresizingMaskIntoConstraints, so its
// frame becomes required constraints. A frame smaller than the fitting size
// (the container has no frame until the window lays it out) conflicts with
// the content’s own required constraints and AppKit raises.
void test_content_frame_never_below_fitting_size ()
{
	inject(@2);
	OakScaledContainerView* container = [[OakScaledContainerView alloc] initWithContentView:content()];
	OAK_ASSERT_EQ(container.contentView.frame.size.width, 100.0);
	OAK_ASSERT_EQ(container.contentView.frame.size.height, 50.0);
	[container updateConstraintsForSubtreeIfNeeded];
	[container layoutSubtreeIfNeeded];

	[container setFrameSize:NSMakeSize(100, 40)]; // smaller than fitting × scale
	[container layoutSubtreeIfNeeded];
	OAK_ASSERT_EQ(container.contentView.frame.size.width, 100.0);
	OAK_ASSERT_EQ(container.contentView.frame.size.height, 50.0);
	inject(nil);
}

void test_reacts_to_scale_change ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	OakScaledContainerView* container = [[OakScaledContainerView alloc] initWithContentView:content()];
	[container setFrameSize:NSMakeSize(300, 150)];

	OakSetUIFontScaleFactor(1.5);
	[container layoutSubtreeIfNeeded];
	OAK_ASSERT_EQ(container.effectiveScale, 1.5);
	OAK_ASSERT_EQ(container.intrinsicContentSize.width, 150.0);
	OAK_ASSERT_EQ(container.bounds.size.width, 200.0);
	OAK_ASSERT_EQ(container.contentView.frame.size.width, 200.0);

	OakSetUIFontScaleFactor(1);
	[container layoutSubtreeIfNeeded];
	OAK_ASSERT_EQ(container.bounds.size.width, 300.0);
	OAK_ASSERT([NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsUIFontScaleFactorKey] == nil);
}

// Drives a real (never shown) window: the panel should grow with the
// scale and come back to its original size, not only grow.
void test_window_follows_scale_both_ways ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	// Zooming keeps the top edge, so the window needs room below it for the
	// doubled height and must not start above the screen top. 350 pt up from
	// the bottom of the visible frame satisfies both on any display down to
	// about 550 pt tall (CI runners are small).
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(visible) + 100, NSMinY(visible) + 350, 300, 150) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	OakSetScaledWindowContentView(window, content());
	[window layoutIfNeeded];
	NSRect base = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(base), 300.0);
	OAK_ASSERT_EQ(NSHeight(base), 150.0);

	OakSetUIFontScaleFactor(2);
	[window layoutIfNeeded];
	NSRect big = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(big), 600.0);
	OAK_ASSERT_EQ(NSHeight(big), 300.0);
	OAK_ASSERT_EQ(NSMaxY(big), NSMaxY(base)); // top edge kept

	OakSetUIFontScaleFactor(1);
	[window layoutIfNeeded];
	NSRect back = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(back), 300.0);
	OAK_ASSERT_EQ(NSHeight(back), 150.0);
	[window close];
}

// A frame autosaved at scale 2 must come back at the current scale.
void test_restored_frame_is_brought_to_current_scale ()
{
	inject(nil);
	NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
	[defaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	[defaults removeObjectForKey:@"NSWindow Frame t_scaled_container_view"]; // a frame left by an earlier run would be restored and then rescaled
	[defaults setDouble:2 forKey:@"OakScaledContainerScale t_scaled_container_view"];

	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 600, 600, 300) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	window.frameAutosaveName = @"t_scaled_container_view";
	OakSetScaledWindowContentView(window, content());
	[window layoutIfNeeded];
	NSRect rect = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(rect), 300.0);
	OAK_ASSERT_EQ(NSHeight(rect), 150.0);
	OAK_ASSERT_EQ([defaults doubleForKey:@"OakScaledContainerScale t_scaled_container_view"], 1.0); // re-saved at the current scale
	[window close];
	[defaults removeObjectForKey:@"OakScaledContainerScale t_scaled_container_view"];
	[defaults removeObjectForKey:@"NSWindow Frame t_scaled_container_view"];
}

// Growing must stop at the screen: a 1000 pt panel at scale 2 is wider than
// any screen this runs on today.
void test_window_growth_is_capped_by_screen ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 600, 1000, 150) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	OakSetScaledWindowContentView(window, content());
	[window layoutIfNeeded];

	OakSetUIFontScaleFactor(2);
	[window layoutIfNeeded];
	NSRect big = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_LE(NSWidth(big), NSWidth(NSScreen.mainScreen.visibleFrame));
	OAK_ASSERT_LT(NSWidth(big), 2000.0);
	OAK_ASSERT_EQ(NSHeight(big), 300.0);
	OAK_ASSERT(NSContainsRect(NSScreen.mainScreen.visibleFrame, window.frame)); // moved back on screen, not just clamped in size

	OakSetUIFontScaleFactor(1);
	[window close];
}

// A window can hold a second container in its title bar (the choosers keep
// their search field there). That one must zoom its content and report the
// scaled size, but leave the window frame and the saved scale to the
// content container, or the window would be resized twice.
void test_container_that_does_not_resize_the_window ()
{
	inject(nil);
	NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
	[defaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	[defaults removeObjectForKey:@"OakScaledContainerScale t_scaled_container_view_titlebar"];

	NSRect visible = NSScreen.mainScreen.visibleFrame;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(visible) + 100, NSMinY(visible) + 350, 300, 150) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	window.frameAutosaveName = @"t_scaled_container_view_titlebar";
	OakScaledContainerView* container = [[OakScaledContainerView alloc] initWithContentView:content()];
	container.resizesWindow = NO;
	[window.contentView addSubview:container];
	[container setFrameSize:NSMakeSize(300, 50)];
	[window layoutIfNeeded];
	NSRect base = window.frame;

	OakSetUIFontScaleFactor(2);
	[window layoutIfNeeded];
	OAK_ASSERT_EQ(container.effectiveScale, 2.0);
	OAK_ASSERT_EQ(container.intrinsicContentSize.height, 100.0);
	OAK_ASSERT_EQ(container.frame.size.height, 100.0); // a title bar accessory is as tall as its frame, so the container sets it
	OAK_ASSERT_EQ(container.frame.size.width, 300.0);  // the width is the superview’s business
	OAK_ASSERT_EQ(container.bounds.size.width, 150.0); // content still zoomed
	OAK_ASSERT(NSEqualRects(window.frame, base));
	OAK_ASSERT([defaults objectForKey:@"OakScaledContainerScale t_scaled_container_view_titlebar"] == nil);

	OakSetUIFontScaleFactor(1);
	[window close];
	[defaults removeObjectForKey:@"NSWindow Frame t_scaled_container_view_titlebar"];
}

// The choosers build their views lazily, after the content view is
// installed. The content view keeps its autoresizing mask, so its frame is
// a required constraint: if it were left at the empty content’s 0 × 0
// fitting size, the first subview with a minimum height would make the
// layout unsatisfiable. Installing must therefore size the content to the
// window right away.
void test_content_added_after_install_fits ()
{
	inject(nil);
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 600, 300, 150) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	NSView* empty = [[NSView alloc] initWithFrame:NSZeroRect];
	OakSetScaledWindowContentView(window, empty);
	OAK_ASSERT_EQ(empty.frame.size.width, 300.0);
	OAK_ASSERT_EQ(empty.frame.size.height, 150.0);

	NSView* footer = [[NSView alloc] initWithFrame:NSZeroRect];
	footer.translatesAutoresizingMaskIntoConstraints = NO;
	[empty addSubview:footer];
	[empty addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(>=77)-[footer(==30)]|" options:0 metrics:nil views:@{ @"footer": footer }]]; // raises if the content were 0 × 0
	[window layoutIfNeeded];
	OAK_ASSERT_EQ(NSMinY(footer.frame), 0.0);
	OAK_ASSERT_EQ(NSWidth(empty.frame), 300.0);
	[window close];
}

// A frame saved before any scale existed (no OakScaledContainerScale key
// next to it) was saved at scale 1, and so was the frame a window is
// created with in code. Either must grow to the current scale.
void test_frame_without_saved_scale_is_treated_as_scale_one ()
{
	// Its own autosave name: a closed window from another test still holds the shared one, and a name in use is refused.
	inject(@2);
	NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
	[defaults removeObjectForKey:@"NSWindow Frame t_scaled_container_view_unscaled"];
	[defaults removeObjectForKey:@"OakScaledContainerScale t_scaled_container_view_unscaled"];

	NSRect visible = NSScreen.mainScreen.visibleFrame;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(visible) + 100, NSMinY(visible) + 350, 300, 150) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	window.frameAutosaveName = @"t_scaled_container_view_unscaled";
	OakSetScaledWindowContentView(window, content());
	[window layoutIfNeeded];
	NSRect rect = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(rect), 600.0);
	OAK_ASSERT_EQ(NSHeight(rect), 300.0);
	OAK_ASSERT_EQ([defaults doubleForKey:@"OakScaledContainerScale t_scaled_container_view_unscaled"], 2.0);
	[window close];
	[defaults removeObjectForKey:@"OakScaledContainerScale t_scaled_container_view_unscaled"];
	[defaults removeObjectForKey:@"NSWindow Frame t_scaled_container_view_unscaled"];
	inject(nil);
}

// A window with no autosave name has the frame it was created with in
// code, which is a scale-1 frame too.
void test_window_without_autosave_name_is_brought_to_current_scale ()
{
	inject(@2);
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(visible) + 100, NSMinY(visible) + 350, 300, 150) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	OakSetScaledWindowContentView(window, content());
	[window layoutIfNeeded];
	NSRect rect = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(rect), 600.0);
	OAK_ASSERT_EQ(NSHeight(rect), 300.0);
	[window close];
	inject(nil);
}

// With a scaled accessory in the title bar, the window’s chrome changes
// height with the scale too. The content container must budget for that,
// or each round trip leaves the accessory’s old height in the content.
void test_window_budgets_for_scaled_titlebar_accessory ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(visible) + 100, NSMinY(visible) + 350, 300, 150) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	OakSetScaledWindowContentView(window, content());

	OakScaledContainerView* accessory = [[OakScaledContainerView alloc] initWithContentView:content()];
	accessory.resizesWindow = NO;
	NSTitlebarAccessoryViewController* controller = [[NSTitlebarAccessoryViewController alloc] init];
	controller.view = accessory;
	[accessory setFrameSize:accessory.intrinsicContentSize]; // after the controller has the view, as the choosers do; the controller resets the frame when it takes the view
	[window addTitlebarAccessoryViewController:controller];
	[window layoutIfNeeded];
	OAK_ASSERT_EQ(NSHeight(accessory.frame), 50.0);
	NSRect base = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSHeight(base), 100.0); // the accessory took its 50 pt from the content, as when the choosers are built

	OakSetUIFontScaleFactor(2);
	[window layoutIfNeeded];
	OAK_ASSERT_EQ(NSHeight(accessory.frame), 100.0);
	NSRect big = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(big), 600.0);
	OAK_ASSERT_EQ(NSHeight(big), 200.0);

	OakSetUIFontScaleFactor(1);
	[window layoutIfNeeded];
	NSRect back = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSHeight(back), 100.0);
	OAK_ASSERT_EQ(NSHeight(accessory.frame), 50.0);
	[window close];
}

// A title bar container follows the scale of the container that sizes the
// window, whatever the window’s own size and even when that scale is capped
// by the screen: the window is budgeted for that scale. Judging the room by
// the screen alone would scale the accessory more than the content, and by
// the screen minus the window would leave a tall window’s accessory unscaled.
void test_titlebar_container_follows_the_window_container ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(visible), NSMinY(visible), 300, round(NSHeight(visible) / 1.5)) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
	OakSetScaledWindowContentView(window, contentOfSize(100, round(NSHeight(visible) / 1.5))); // too tall to double: the owner’s scale is capped between 1 and 2
	OakScaledContainerView* owner = (OakScaledContainerView*)window.contentView.subviews.firstObject;
	OAK_ASSERT([owner isKindOfClass:[OakScaledContainerView class]]);

	OakScaledContainerView* accessory = [[OakScaledContainerView alloc] initWithContentView:content()];
	accessory.resizesWindow = NO;
	NSTitlebarAccessoryViewController* controller = [[NSTitlebarAccessoryViewController alloc] init];
	controller.view = accessory;
	[accessory setFrameSize:accessory.intrinsicContentSize];
	[window addTitlebarAccessoryViewController:controller];
	[window layoutIfNeeded];

	OakSetUIFontScaleFactor(2);
	[window layoutIfNeeded];
	CGFloat ownerScale = owner.effectiveScale, accessoryScale = accessory.effectiveScale, accessoryHeight = NSHeight(accessory.frame);
	OakSetUIFontScaleFactor(1); // before the assertions: a failed one returns, and the next test would see the scale
	[window close];

	OAK_ASSERT_GT(ownerScale, 1.0);
	OAK_ASSERT_LT(ownerScale, 2.0);
	OAK_ASSERT_EQ(accessoryScale, ownerScale);
	OAK_ASSERT_EQ(accessoryHeight, ceil(50 * ownerScale));
}

// A borderless window has no title bar to hold accessories, and asking it
// for them raises. The pasteboard selector lives in one.
void test_container_in_borderless_window ()
{
	inject(@2);
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(visible) + 100, NSMinY(visible) + 350, 300, 150) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
	OakSetScaledWindowContentView(window, content()); // raised NSInternalInconsistencyException before the guard
	[window layoutIfNeeded];
	NSRect rect = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(rect), 600.0);
	OAK_ASSERT_EQ(NSHeight(rect), 300.0);
	[window close];
	inject(nil);
}

// A xib-built content view lays its subviews out with autoresizing masks
// and has no constraints, so its fitting size says nothing: its own frame
// is its design size. A window restored smaller than that (Jump to Line
// had a 191 × 71 saved frame for a 269 × 102 panel) must not squeeze it,
// which collapses the autoresizing subviews; the window grows instead.
void test_autoresizing_content_keeps_its_design_size ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(visible) + 100, NSMinY(visible) + 350, 191, 71) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
	NSView* xibLike = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 269, 102)];
	NSButton* button = [[NSButton alloc] initWithFrame:NSMakeRect(150, 12, 105, 32)];
	button.autoresizingMask = NSViewMinXMargin; // sticks to the right edge, as in the xib
	[xibLike addSubview:button];

	OakSetScaledWindowContentView(window, xibLike);
	[window layoutIfNeeded];
	OAK_ASSERT_EQ(NSWidth(xibLike.frame), 269.0);
	OAK_ASSERT_EQ(NSHeight(xibLike.frame), 102.0);
	OAK_ASSERT_EQ(NSMinX(button.frame), 150.0); // never squeezed, so never moved
	NSRect content = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(content), 269.0);  // the window grew to the design size
	OAK_ASSERT_EQ(NSHeight(content), 102.0);

	OakSetUIFontScaleFactor(2);
	[window layoutIfNeeded];
	content = [window contentRectForFrameRect:window.frame];
	OAK_ASSERT_EQ(NSWidth(content), 538.0);
	OAK_ASSERT_EQ(NSWidth(xibLike.frame), 269.0);
	OAK_ASSERT_EQ(NSMinX(button.frame), 150.0);
	OakSetUIFontScaleFactor(1);
	[window close];
}
