#import <FileBrowser/FileItemTableCellView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

// A cell created while a scale is in effect (a new window, or rows scrolled
// into view later) must come out scaled, not only cells that were alive
// when the scale changed.
void test_cell_created_at_scale_is_scaled ()
{
	inject(@2);
	FileItemTableCellView* cell = [[FileItemTableCellView alloc] init];
	OAK_ASSERT_EQ(cell.textField.font.pointSize, NSFont.systemFontSize * 2);
	OAK_ASSERT_EQ(cell.openButton.fittingSize.width, 32.0);
	inject(nil);
}

void test_cell_follows_scale_change ()
{
	inject(nil);
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];
	FileItemTableCellView* cell = [[FileItemTableCellView alloc] init];
	OAK_ASSERT_EQ(cell.textField.font.pointSize, NSFont.systemFontSize); // the stock look: the cell’s default font, 13 pt
	OAK_ASSERT([cell.textField.font.familyName isEqualToString:[NSFont systemFontOfSize:0].familyName]);
	OakSetUIFontScaleFactor(2);
	OAK_ASSERT_EQ(cell.textField.font.pointSize, NSFont.systemFontSize * 2);
	OakSetUIFontScaleFactor(1);
}
