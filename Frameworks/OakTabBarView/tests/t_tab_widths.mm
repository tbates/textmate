#import <OakTabBarView/OakTabBarView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import "TabWidthsDataSource.h" // the test runner puts test bodies in a namespace, where an Objective-C class cannot be declared

static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

static NSArray<NSNumber*>* tabWidths (OakTabBarView* tabBarView)
{
	NSMutableArray* res = [NSMutableArray array];
	for(NSView* view in tabBarView.subviews)
	{
		if([view isKindOfClass:NSClassFromString(@"OakTabView")] && NSMaxX(view.frame) < NSWidth(tabBarView.bounds)) // the background right of the tabs is a tab view too, reaching past the edge
			[res addObject:@(NSWidth(view.frame))];
	}
	return res;
}

// The tab width limits (tabItemMinWidth/tabItemMaxWidth, 120/250) are in
// points of the stock scale. Titles scale with the interface, so the limits
// must too, or titles truncate sooner and fewer tabs fit at a larger scale.
void test_tab_widths_follow_scale ()
{
	inject(nil);
	TabWidthsDataSource* dataSource = [TabWidthsDataSource new];
	dataSource.count = 1;
	OakTabBarView* tabBarView = [[OakTabBarView alloc] initWithFrame:NSMakeRect(0, 0, 800, 33)];
	tabBarView.dataSource = dataSource;
	[tabBarView reloadData];
	OAK_ASSERT_EQ(tabWidths(tabBarView).count, 1);
	OAK_ASSERT_EQ(tabWidths(tabBarView).firstObject.doubleValue, 250.0); // the maximum

	inject(@2);
	[tabBarView reloadData];
	OAK_ASSERT_EQ(tabWidths(tabBarView).firstObject.doubleValue, 500.0);
	inject(nil);
}

void test_visible_tab_count_follows_scale ()
{
	inject(nil);
	TabWidthsDataSource* dataSource = [TabWidthsDataSource new];
	dataSource.count = 10;
	OakTabBarView* tabBarView = [[OakTabBarView alloc] initWithFrame:NSMakeRect(0, 0, 626, 33)]; // 600 beside the 26 pt “+” button
	tabBarView.dataSource = dataSource;
	[tabBarView reloadData];
	OAK_ASSERT_EQ(tabWidths(tabBarView).count, 5); // 600 / 120

	inject(@2);
	[tabBarView reloadData];
	OAK_ASSERT_EQ(tabWidths(tabBarView).count, 2); // (626 - 52) / 240
	inject(nil);
}
