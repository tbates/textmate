#import <FileBrowser/OFB/OFBActionsView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

// The action bar’s gear menu uses the menu font, scaled at creation and on change.
void test_actions_menu_font_follows_scale ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	OFBActionsView* actionsView = [[OFBActionsView alloc] initWithFrame:NSZeroRect];
	CGFloat menuFontSize = [NSFont menuFontOfSize:0].pointSize;
	OAK_ASSERT_EQ(actionsView.actionsPopUpButton.menu.font.pointSize, menuFontSize);
	OakSetUIFontScaleFactor(2);
	OAK_ASSERT_EQ(actionsView.actionsPopUpButton.menu.font.pointSize, menuFontSize * 2);
	OakSetUIFontScaleFactor(1);
}
