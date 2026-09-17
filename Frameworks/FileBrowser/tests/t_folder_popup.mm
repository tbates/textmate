#import <FileBrowser/FileBrowserViewController.h>
#import <FileBrowser/OFB/OFBHeaderView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

// The folder popup in the header shows the current folder’s icon. The icon
// comes from a shared TMFileReference at 16 pt, so the popup needs a scaled
// copy, at creation and after a change.
void test_folder_popup_icon_is_scaled ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	FileBrowserViewController* controller = [[FileBrowserViewController alloc] init];
	[controller goToURL:[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]];
	NSPopUpButton* popUp = ((OFBHeaderView*)controller.headerView).folderPopUpButton;
	OAK_ASSERT(popUp.selectedItem.image != nil);
	OAK_ASSERT_EQ(popUp.selectedItem.image.size.width, 16.0);

	OakSetUIFontScaleFactor(2);
	OAK_ASSERT_EQ(popUp.selectedItem.image.size.width, 32.0);
	OAK_ASSERT_EQ(popUp.menu.font.pointSize, [NSFont menuFontOfSize:0].pointSize * 2);
	OakSetUIFontScaleFactor(1);
	OAK_ASSERT_EQ(popUp.selectedItem.image.size.width, 16.0);

	inject(@2);
	FileBrowserViewController* scaled = [[FileBrowserViewController alloc] init];
	[scaled goToURL:[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]];
	OAK_ASSERT_EQ(((OFBHeaderView*)scaled.headerView).folderPopUpButton.selectedItem.image.size.width, 32.0);
	inject(nil);
}
