#import <Preferences/Preferences.h>
#import <settings/settings.h>
#import <test/jail.h>
#import <objc/message.h>

// Selects a pane the way a toolbar item or the Show Tab menu does.
static void selectPane (Preferences* preferences, NSString* identifier)
{
	NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:identifier action:NULL keyEquivalent:@""];
	item.representedObject = identifier;
	((void(*)(id, SEL, id))objc_msgSend)(preferences, NSSelectorFromString(@"takeSelectedViewControllerIdentifierFrom:"), item);
}

// The window used to take its size limits from the pane’s own constraints:
// fixed for the grid panes, growable for the panes with a list. With the
// panes inside a scaled container those limits no longer reach the window,
// so the panes say whether they can grow, and the window is resizable only
// then, with the pane’s scaled fitting size as its minimum.
void test_window_is_resizable_only_for_panes_that_can_grow ()
{
	test::jail_t jail; // the Files pane binds to settings, which assert their paths are set
	settings_t::set_default_settings_path(jail.path("default"));
	settings_t::set_global_settings_path(jail.path("global"));

	Preferences* preferences = Preferences.sharedInstance;
	NSWindow* window = preferences.window;

	selectPane(preferences, @"Files");
	OAK_ASSERT((window.styleMask & NSWindowStyleMaskResizable) == 0);

	selectPane(preferences, @"Bundles");
	OAK_ASSERT((window.styleMask & NSWindowStyleMaskResizable) != 0);
	OAK_ASSERT_GT(window.contentMinSize.width, 100.0);
	OAK_ASSERT_GT(window.contentMinSize.height, 100.0);

	selectPane(preferences, @"Projects");
	OAK_ASSERT((window.styleMask & NSWindowStyleMaskResizable) == 0);

	selectPane(preferences, @"Variables");
	OAK_ASSERT((window.styleMask & NSWindowStyleMaskResizable) != 0);

	// A pane the user made larger (or zoomed to the screen) keeps that frame
	// and comes back at it, but its minimum is still what its constraints say,
	// or the window could never be shrunk again.
	// On screen the switch animates and finishes later; the transition
	// controller holds each pane at its frame with size constraints until then,
	// which a fitting size taken in between would report. The run loop may not
	// get to the completion at all here (it did not on CI), as with fast
	// switching in the app.
	NSSize minimum = window.contentMinSize;
	[window orderFront:nil];
	[window setContentSize:NSMakeSize(1400, 1200)];
	selectPane(preferences, @"Bundles");
	[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
	selectPane(preferences, @"Variables");
	[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
	NSSize afterwards = window.contentMinSize;
	[window orderOut:nil];
	OAK_ASSERT_EQ(afterwards.width, minimum.width);
	OAK_ASSERT_EQ(afterwards.height, minimum.height);
}
