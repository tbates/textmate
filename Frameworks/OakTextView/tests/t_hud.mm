#import <OakTextView/OTVHUD.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

static NSTextField* hudField (NSWindow* window)
{
	for(NSView* view in window.contentView.subviews)
	{
		if([view isKindOfClass:[NSTextField class]])
			return (NSTextField*)view;
	}
	return nil;
}

// The HUD that shows the editor’s zoom percentage is a fresh window each
// time, sized for its 20 pt text: both follow the interface scale.
void test_hud_is_scaled ()
{
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMinX(visible) + 50, NSMinY(visible) + 50, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
	[window.contentView addSubview:view];

	inject(nil);
	OTVHUD* hud = [OTVHUD showHudForView:view withText:@"100%"];
	OAK_ASSERT_EQ(hudField(hud.window).font.pointSize, 20.0);
	OAK_ASSERT_EQ(NSWidth(hud.window.frame), 100.0);
	OAK_ASSERT_EQ(NSHeight(hud.window.frame), 30.0);
	[hud.window close];

	inject(@2);
	hud = [OTVHUD showHudForView:view withText:@"200%"];
	OAK_ASSERT_EQ(hudField(hud.window).font.pointSize, 40.0);
	OAK_ASSERT_EQ(NSWidth(hud.window.frame), 200.0);
	OAK_ASSERT_EQ(NSHeight(hud.window.frame), 60.0);
	[hud.window close];
	[window close];
	inject(nil);
}
