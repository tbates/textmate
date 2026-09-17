#import <OakAppKit/OakToolTip.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

static NSTextField* toolTipField (NSWindow* window)
{
	for(NSView* view in window.contentView.subviews)
	{
		if([view isKindOfClass:[NSTextField class]])
			return (NSTextField*)view;
	}
	return nil;
}

// A tool tip is a fresh window each time it is shown, so its font is fixed
// at creation: at the tool tip font size × the interface scale.
void test_tool_tip_font_is_scaled ()
{
	inject(@2);
	NSRect visible = NSScreen.mainScreen.visibleFrame;
	OakShowToolTip(@"Scaled tool tip", NSMakePoint(NSMidX(visible), NSMidY(visible)));

	NSWindow* toolTip = nil;
	for(NSWindow* window in NSApp.windows)
	{
		if([window isKindOfClass:NSClassFromString(@"OakToolTip")])
			toolTip = window;
	}
	OAK_ASSERT(toolTip != nil);
	OAK_ASSERT_EQ(toolTipField(toolTip).font.pointSize, [NSFont toolTipsFontOfSize:0].pointSize * 2);
	OAK_ASSERT_GT(NSHeight(toolTip.frame), [NSFont toolTipsFontOfSize:0].pointSize * 2); // sized for the scaled text
	[toolTip close];
	inject(nil);
}
