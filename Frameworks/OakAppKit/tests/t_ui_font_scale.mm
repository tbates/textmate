#import <OakAppKit/OakUIConstructionFunctions.h>

// The scale is read from NSUserDefaults. The argument domain is volatile
// and takes precedence over every other domain, so tests can inject a
// value without touching the process's persistent defaults.
static void inject (id value)
{
	NSDictionary* domain = value ? @{ kUserDefaultsUIFontScaleFactorKey: value } : @{ };
	[NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}

void test_default_scale_is_one ()
{
	inject(nil);
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), 1.0);
	OAK_ASSERT_EQ(OakStatusBarFont().pointSize, 12.0);
	OAK_ASSERT_EQ(OakScaledUIMetric(23), 23.0);
}

void test_scale_from_defaults ()
{
	inject(@1.5);
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), 1.5);
	OAK_ASSERT_EQ(OakStatusBarFont().pointSize, 18.0);
	OAK_ASSERT_EQ(OakScaledUIMetric(23), 35.0); // round(34.5)
	OAK_ASSERT_EQ(OakScaledUIFont([NSFont systemFontOfSize:10]).pointSize, 15.0);
	inject(nil);
}

void test_scaled_font_keeps_face ()
{
	inject(@2);
	NSFont* base   = [NSFont fontWithName:@"Menlo-Bold" size:11];
	NSFont* scaled = OakScaledUIFont(base);
	OAK_ASSERT([scaled.fontName isEqualToString:base.fontName]);
	OAK_ASSERT_EQ(scaled.pointSize, 22.0);
	inject(nil);
}

void test_invalid_defaults_fall_back_to_one ()
{
	inject(@0);
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), 1.0);
	inject(@-2);
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), 1.0);
	inject(@"large");
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), 1.0);
	inject(nil);
}

void test_scale_is_clamped ()
{
	inject(@100);
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), kOakUIFontScaleFactorMax);
	inject(@0.01);
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), kOakUIFontScaleFactorMin);
	inject(nil);
}

void test_scaled_image_is_a_scaled_copy ()
{
	inject(@2);
	NSImage* base = [NSImage imageWithSize:NSMakeSize(14, 10) flipped:NO drawingHandler:^BOOL(NSRect){ return YES; }];
	[base setTemplate:YES];
	base.accessibilityDescription = @"Go Back";
	NSImage* scaled = OakScaledUIImage(base);
	OAK_ASSERT(scaled != base);
	OAK_ASSERT_EQ(scaled.size.width, 28.0);
	OAK_ASSERT_EQ(scaled.size.height, 20.0);
	OAK_ASSERT_EQ(base.size.width, 14.0); // untouched
	OAK_ASSERT(scaled.isTemplate);
	OAK_ASSERT([scaled.accessibilityDescription isEqualToString:@"Go Back"]);
	OAK_ASSERT(OakScaledUIImage(nil) == nil);
	inject(nil);
}

void test_setter_persists_and_notifies ()
{
	inject(nil);
	NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
	[defaults removeObjectForKey:kUserDefaultsUIFontScaleFactorKey];

	__block NSUInteger notifications = 0;
	id token = [NSNotificationCenter.defaultCenter addObserverForName:OakUIFontScaleFactorDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification*){ ++notifications; }];

	OakSetUIFontScaleFactor(1.2);
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), 1.2);
	OAK_ASSERT_EQ([defaults doubleForKey:kUserDefaultsUIFontScaleFactorKey], 1.2);
	OAK_ASSERT_EQ(notifications, 1);

	OakSetUIFontScaleFactor(1.2); // unchanged: no notification
	OAK_ASSERT_EQ(notifications, 1);

	OakSetUIFontScaleFactor(0.001); // clamped
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), kOakUIFontScaleFactorMin);
	OAK_ASSERT_EQ(notifications, 2);

	OakSetUIFontScaleFactor(1); // back to default removes the key
	OAK_ASSERT([defaults objectForKey:kUserDefaultsUIFontScaleFactorKey] == nil);
	OAK_ASSERT_EQ(notifications, 3);

	[NSNotificationCenter.defaultCenter removeObserver:token];
}

// The tab bar title label is created without an explicit font and takes
// whatever OakCreateLabel gives it. Scaling needs a known base font, so pin
// down that the two agree; if AppKit ever changes the label default, this
// is where it shows up.
void test_label_default_font_is_system_font ()
{
	NSFont* labelFont  = OakCreateLabel().font;
	NSFont* systemFont = [NSFont systemFontOfSize:0];
	OAK_ASSERT_EQ(labelFont.pointSize, systemFont.pointSize);
	OAK_ASSERT([labelFont.familyName isEqualToString:systemFont.familyName]);
}

// The system template images (NSImageNameRefreshTemplate and friends) are
// SF Symbols. A control draws a symbol at its symbol configuration — 13 pt
// medium for a regular-size control — not at the image’s nominal size: the
// refresh arrow reports 18×21 but a plain button fits it in 14×16. So the
// scaled image must stay a symbol, configured at 13 × scale pt, or the
// glyph comes out about 30 % too big at every scale.
void test_scaled_symbol_image_keeps_the_control_point_size ()
{
	NSImage* base = [NSImage imageNamed:NSImageNameRefreshTemplate];
	NSSize (^symbolSize)(CGFloat) = ^(CGFloat pointSize){
		return [base imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:NSFontWeightRegular scale:NSImageSymbolScaleMedium]].size;
	};

	inject(nil);
	OAK_ASSERT(!NSEqualSizes(symbolSize(13), base.size)); // the nominal box is not what a control draws
	OAK_ASSERT(NSEqualSizes(OakScaledUIImage(base).size, symbolSize(13)));

	inject(@2);
	NSImage* scaled = OakScaledUIImage(base);
	OAK_ASSERT(NSEqualSizes(scaled.size, symbolSize(26)));
	OAK_ASSERT(scaled.isTemplate);
	OAK_ASSERT(NSEqualSizes(base.size, [NSImage imageNamed:NSImageNameRefreshTemplate].size)); // shared named image untouched
	inject(nil);
}

// A view inside an OakScaledContainerView is zoomed as a whole, so it needs
// the status bar font at its base size or the text is scaled twice.
void test_status_bar_base_font_is_unscaled ()
{
	inject(@2);
	OAK_ASSERT_EQ(OakStatusBarBaseFont().pointSize, 12.0);
	OAK_ASSERT_EQ(OakStatusBarFont().pointSize, 24.0);
	OAK_ASSERT([OakStatusBarFont().familyName isEqualToString:OakStatusBarBaseFont().familyName]);
	inject(nil);
}

// `defaults write com.macromates.TextMate uiFontScaleFactor 1.5` stores the
// string "1.5" (so does a -uiFontScaleFactor 1.5 launch argument), which must
// count like the number.
void test_scale_from_a_string_value ()
{
	inject(@"1.5");
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), 1.5);
	inject(@"abc");
	OAK_ASSERT_EQ(OakUIFontScaleFactor(), 1.0);
	inject(nil);
}
