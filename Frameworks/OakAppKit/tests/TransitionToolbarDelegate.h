// A toolbar with one labelled item, as the Preferences window has: the item
// gives the toolbar a height, and adding it reshapes the window.
@interface TransitionToolbarDelegate : NSObject <NSToolbarDelegate>
@end

@implementation TransitionToolbarDelegate
- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem* res = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
	res.label = itemIdentifier;
	res.image = [NSImage imageNamed:NSImageNamePreferencesGeneral];
	return res;
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar   { return @[ @"General" ]; }
- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar   { return @[ @"General" ]; }
- (NSArray<NSToolbarItemIdentifier>*)toolbarSelectableItemIdentifiers:(NSToolbar*)toolbar { return @[ @"General" ]; }
@end
