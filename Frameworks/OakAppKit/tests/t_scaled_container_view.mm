#import <OakAppKit/OakScaledContainerView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

// A content view whose autolayout fitting size is 100 × 50.
static NSView* content ()
{
	NSView* res = [[NSView alloc] initWithFrame:NSZeroRect];
	NSView* inner = [[NSView alloc] initWithFrame:NSZeroRect];
	inner.translatesAutoresizingMaskIntoConstraints = NO;
	[res addSubview:inner];
	[NSLayoutConstraint activateConstraints:@[
		[inner.widthAnchor constraintEqualToConstant:100],
		[inner.heightAnchor constraintEqualToConstant:50],
		[inner.leadingAnchor constraintEqualToAnchor:res.leadingAnchor],
		[inner.trailingAnchor constraintEqualToAnchor:res.trailingAnchor],
		[inner.topAnchor constraintEqualToAnchor:res.topAnchor],
		[inner.bottomAnchor constraintEqualToAnchor:res.bottomAnchor],
	]];
	return res;
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
