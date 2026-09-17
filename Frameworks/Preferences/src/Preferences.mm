#import "Preferences.h"
#import "FilesPreferences.h"
#import "ProjectsPreferences.h"
#import "BundlesPreferences.h"
#import "VariablesPreferences.h"
#import "SoftwareUpdatePreferences.h"
#import "TerminalPreferences.h"
#import "Keys.h"
#import <OakAppKit/OakTransitionViewController.h>
#import <OakAppKit/OakScaledContainerView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

static NSString* const kMASPreferencesFrameTopLeftKey = @"MASPreferences Frame Top Left";
static NSString* const kMASPreferencesSelectedViewKey = @"MASPreferences Selected Identifier View";

// =============================
// = PreferencesViewController =
// =============================

@interface PreferencesViewController : OakTransitionViewController
@property (nonatomic) NSString* selectedViewIdentifier;
@property (nonatomic) NSMutableDictionary<NSString*, NSValue*>* minimumSizes; // each pane’s fitting size, read before it has ever been in a switch
@end

@implementation PreferencesViewController
- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil
{
	if(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])
	{
		_minimumSizes = [NSMutableDictionary dictionary];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(uiFontScaleFactorDidChange:) name:OakUIFontScaleFactorDidChangeNotification object:nil];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

// A pane’s fitting size is what its own constraints allow at least, but only
// while the pane is not in a switch: OakTransitionViewController holds each
// pane at its frame with size constraints of its own until the switch’s
// animation completes, and a pane zoomed to the screen would report that.
// So it is read once, before the pane’s first switch.
- (NSSize)minimumSizeForViewController:(NSViewController*)viewController
{
	NSValue* cached = _minimumSizes[viewController.identifier];
	if(!cached)
		_minimumSizes[viewController.identifier] = cached = [NSValue valueWithSize:viewController.view.fittingSize];
	return cached.sizeValue;
}

// The panes are inside a scaled container, so their constraints no longer
// reach the window: the window is resizable only for a pane that says it can
// grow, and never below the pane’s scaled minimum.
- (void)updateWindowSizingForViewController:(NSViewController <PreferencesPaneProtocol>*)viewController
{
	NSWindow* window = self.view.window;
	if(!window || !viewController)
		return;
	NSSize fitting = [self minimumSizeForViewController:viewController];

	BOOL resizable = [viewController respondsToSelector:@selector(isResizable)] && viewController.isResizable;
	window.styleMask = resizable ? (window.styleMask | NSWindowStyleMaskResizable) : (window.styleMask & ~NSWindowStyleMaskResizable);

	CGFloat scale = OakScaledContainerScaleForView(self.view);
	window.contentMinSize = NSMakeSize(ceil(fitting.width * scale), ceil(fitting.height * scale));
}

- (void)uiFontScaleFactorDidChange:(NSNotification*)aNotification
{
	[self updateWindowSizingForViewController:[self viewControllerForIdentifier:_selectedViewIdentifier]];
}

- (void)viewWillAppear
{
	NSString* viewIdentifier = [NSUserDefaults.standardUserDefaults stringForKey:kMASPreferencesSelectedViewKey];
	self.selectedViewIdentifier = viewIdentifier ?: self.childViewControllers.firstObject.identifier;
}

- (void)setSelectedViewIdentifier:(NSString*)viewIdentifier
{
	if(_selectedViewIdentifier == viewIdentifier || [_selectedViewIdentifier isEqual:viewIdentifier])
		return;

	NSViewController* oldViewController = [self viewControllerForIdentifier:_selectedViewIdentifier];
	if(oldViewController && ![oldViewController commitEditing])
	{
		self.view.window.toolbar.selectedItemIdentifier = oldViewController.identifier;
		return;
	}

	_selectedViewIdentifier = viewIdentifier;
	self.view.window.toolbar.selectedItemIdentifier = viewIdentifier;
	[NSUserDefaults.standardUserDefaults setObject:_selectedViewIdentifier forKey:kMASPreferencesSelectedViewKey];

	NSViewController <PreferencesPaneProtocol>* newViewController = [self viewControllerForIdentifier:viewIdentifier];
	self.title = newViewController.title ?: @"Preferences";

	[self minimumSizeForViewController:newViewController]; // before its first switch
	self.view.window.contentMinSize = NSZeroSize; // the new pane may be smaller than the old minimum
	self.subview = newViewController.view;
	[self updateWindowSizingForViewController:newViewController];

	BOOL setNewFirstResponder = self.view.window.firstResponder == self.view.window;
	[self.view.window recalculateKeyViewLoop];
	NSView* newKeyView = newViewController.view.nextValidKeyView;
	if(setNewFirstResponder && newKeyView && [newKeyView isDescendantOf:newViewController.view])
		[self.view.window makeFirstResponder:newKeyView];
}

- (NSViewController <PreferencesPaneProtocol>*)viewControllerForIdentifier:(NSString*)viewIdentifier
{
	for(NSViewController <PreferencesPaneProtocol>* viewController in self.childViewControllers)
	{
		if([viewController.identifier isEqual:viewIdentifier])
			return viewController;
	}
	return nil;
}
@end

// ===============================
// = PreferencesWindowController =
// ===============================

@interface Preferences () <NSToolbarDelegate, NSWindowDelegate>
@property (nonatomic) PreferencesViewController* preferencesViewController;
@end

@implementation Preferences
+ (instancetype)sharedInstance
{
	static Preferences* sharedInstance = [self new];
	return sharedInstance;
}

- (instancetype)init
{
	PreferencesViewController* contentViewController = [[PreferencesViewController alloc] init];

	NSWindow* window = [NSPanel windowWithContentViewController:contentViewController];
	if(NSString* topLeft = [NSUserDefaults.standardUserDefaults stringForKey:kMASPreferencesFrameTopLeftKey])
		[window setFrameTopLeftPoint:NSPointFromString(topLeft)];
	OakSetScaledWindowContentView(window, contentViewController.view); // the panes zoom with the interface scale; the toolbar is AppKit’s and does not
	[window bind:NSTitleBinding toObject:contentViewController withKeyPath:@"title" options:nil]; // replacing the content view cleared the content view controller, and with it the title binding windowWithContentViewController: made

	if((self = [super initWithWindow:window]))
	{
		_preferencesViewController = contentViewController;

		NSArray<NSViewController <PreferencesPaneProtocol>*>* viewControllers = @[
			[[FilesPreferences alloc] init],
			[[ProjectsPreferences alloc] init],
			[[BundlesPreferences alloc] init],
			[[VariablesPreferences alloc] init],
			[[SoftwareUpdatePreferences alloc] init],
			[[TerminalPreferences alloc] init]
		];

		for(NSViewController* viewController in viewControllers)
			[contentViewController addChildViewController:viewController];

		NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"Preferneces"];
		toolbar.allowsUserCustomization = NO;
		toolbar.delegate                = self;

		BOOL hasToolbarImages = NO;
		for(NSViewController* viewController in viewControllers)
			hasToolbarImages = hasToolbarImages || [viewController respondsToSelector:@selector(toolbarItemImage)];
		toolbar.displayMode = hasToolbarImages ? NSToolbarDisplayModeIconAndLabel : NSToolbarDisplayModeLabelOnly;

		window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace|NSWindowCollectionBehaviorFullScreenAuxiliary;
		window.delegate           = self;
		window.hidesOnDeactivate  = NO;
		window.toolbar            = toolbar;
		if(@available(macos 11.0, *))
		{
			window.toolbarStyle = NSWindowToolbarStylePreference;
		}
	}
	return self;
}

- (void)windowDidMove:(NSNotification*)aNotification
{
   [NSUserDefaults.standardUserDefaults setObject:NSStringFromPoint(NSMakePoint(NSMinX(self.window.frame), NSMaxY(self.window.frame))) forKey:kMASPreferencesFrameTopLeftKey];
}

- (void)selectViewAtRelativeOffset:(NSInteger)offset
{
	NSArray* identifiers = [self toolbarSelectableItemIdentifiers:self.window.toolbar];
	NSUInteger index = [identifiers indexOfObject:_preferencesViewController.selectedViewIdentifier];
	if(index != NSNotFound)
			_preferencesViewController.selectedViewIdentifier = identifiers[(index + identifiers.count + offset) % identifiers.count];
	else	_preferencesViewController.selectedViewIdentifier = offset < 0 ? identifiers.lastObject : identifiers.firstObject;
}

- (void)selectNextTab:(id)sender     { [self selectViewAtRelativeOffset:+1]; }
- (void)selectPreviousTab:(id)sender { [self selectViewAtRelativeOffset:-1]; }

- (void)updateShowTabMenu:(NSMenu*)aMenu
{
	if(!self.isWindowLoaded || !self.window.isKeyWindow)
		return;

	NSString* const selectedIdentifier = _preferencesViewController.selectedViewIdentifier;

	int i = 0;
	for(NSViewController* viewController in _preferencesViewController.childViewControllers)
	{
		NSMenuItem* item = [aMenu addItemWithTitle:viewController.title action:@selector(takeSelectedViewControllerIdentifierFrom:) keyEquivalent:i < 9 ? [NSString stringWithFormat:@"%c", '1' + i] : @""];
		item.representedObject = viewController.identifier;
		item.target = self;
		if([viewController.identifier isEqual:selectedIdentifier])
			item.state = NSControlStateValueOn;
		++i;
	}
}

- (void)takeSelectedViewControllerIdentifierFrom:(id)sender
{
	if([sender respondsToSelector:@selector(itemIdentifier)])
		_preferencesViewController.selectedViewIdentifier = [sender itemIdentifier];
	else if([sender respondsToSelector:@selector(representedObject)])
		_preferencesViewController.selectedViewIdentifier = [sender representedObject];
}

// ====================
// = Toolbar Delegate =
// ====================

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem* res = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
	res.action = @selector(takeSelectedViewControllerIdentifierFrom:);
	res.target = self;

	if(NSViewController <PreferencesPaneProtocol>* viewController = [_preferencesViewController viewControllerForIdentifier:itemIdentifier])
	{
		res.label = viewController.title;
		if([viewController respondsToSelector:@selector(toolbarItemImage)])
		{
			NSImage* image = viewController.toolbarItemImage;
			// SF Symbol panes render a larger glyph via scale (keeps the box compact); PNG
			// fallbacks return nil here and are left as-is.
			if(@available(macos 11.0, *))
			{
				if(NSImage* symbol = [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithScale:NSImageSymbolScaleLarge]])
				{
					// The preference toolbar positions the label off the bottom of the icon's
					// box, so pad the box below the glyph to widen the icon→label gap without
					// changing the glyph size. Kept as a template image so it still tints.
					CGFloat const kLabelGapPadding = 6;
					NSSize const glyphSize = symbol.size;
					NSImage* padded = [NSImage imageWithSize:NSMakeSize(glyphSize.width, glyphSize.height + kLabelGapPadding) flipped:NO drawingHandler:^BOOL(NSRect){
						[symbol drawInRect:NSMakeRect(0, kLabelGapPadding, glyphSize.width, glyphSize.height)];
						return YES;
					}];
					[padded setTemplate:YES];
					image = padded;
				}
			}
			res.image = image;
		}
	}

	return res;
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
	NSMutableArray* res = [NSMutableArray array];
	for(NSViewController* viewController in _preferencesViewController.childViewControllers)
	{
		if(viewController.identifier)
			[res addObject:viewController.identifier];
	}
	return res;
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
	return [self toolbarAllowedItemIdentifiers:toolbar];
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarSelectableItemIdentifiers:(NSToolbar*)toolbar
{
	return [self toolbarAllowedItemIdentifiers:toolbar];
}
@end
