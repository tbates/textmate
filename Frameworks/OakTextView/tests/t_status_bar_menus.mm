#import <OakTextView/OTVStatusBar.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

// The status bar’s popup buttons show their titles in the scaled status
// bar font, but the menus they drop down use the menu font, which must be
// scaled separately, at creation and on change.
void test_status_bar_popup_menus_follow_scale ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	OTVStatusBar* statusBar = [[OTVStatusBar alloc] initWithFrame:NSZeroRect];
	CGFloat menuFontSize = [NSFont menuFontOfSize:0].pointSize;
	for(NSString* key in @[ @"grammarPopUp", @"tabSizePopUp", @"bundleItemsPopUp", @"symbolPopUp" ])
		OAK_ASSERT_EQ([[statusBar valueForKey:key] menu].font.pointSize, menuFontSize);

	OakSetUIFontScaleFactor(2);
	for(NSString* key in @[ @"grammarPopUp", @"tabSizePopUp", @"bundleItemsPopUp", @"symbolPopUp" ])
		OAK_ASSERT_EQ([[statusBar valueForKey:key] menu].font.pointSize, menuFontSize * 2);
	OakSetUIFontScaleFactor(1);

	inject(@2);
	OTVStatusBar* scaled = [[OTVStatusBar alloc] initWithFrame:NSZeroRect];
	OAK_ASSERT_EQ([[scaled valueForKey:@"grammarPopUp"] menu].font.pointSize, menuFontSize * 2);
	inject(nil);
}
