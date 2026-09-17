#import "OakScaledContainerView.h"
#import "OakUIConstructionFunctions.h"

@implementation OakScaledContainerView
{
	CGFloat _appliedScale; // the scale the window was last sized for
	NSSize  _initialSize;  // the content’s frame when installed: the design size of a content without constraints
}

- (instancetype)initWithContentView:(NSView*)contentView
{
	if(self = [super initWithFrame:NSZeroRect])
	{
		_contentView   = contentView;
		_resizesWindow = YES;
		_contentView.translatesAutoresizingMaskIntoConstraints = YES;
		_contentView.autoresizingMask = NSViewNotSizable;
		_initialSize = _contentView.frame.size;
		_contentView.frame = (NSRect){ NSZeroPoint, self.designSize };
		[self addSubview:_contentView];

		// The window should not shrink the content below its fitting size, but
		// may grow it. Just below required: when the screen forces a smaller
		// window than the scaled content (a tall panel at a high scale) the
		// content is clipped rather than the layout being unsatisfiable, which
		// this app treats as fatal.
		[self setContentCompressionResistancePriority:NSLayoutPriorityRequired-1 forOrientation:NSLayoutConstraintOrientationHorizontal];
		[self setContentCompressionResistancePriority:NSLayoutPriorityRequired-1 forOrientation:NSLayoutConstraintOrientationVertical];
		[self setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
		[self setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(uiFontScaleFactorDidChange:) name:OakUIFontScaleFactorDidChangeNotification object:nil];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

// The window’s autosaved frame is in screen points at whatever scale was in
// effect when it was saved. The scale is saved next to it under the same
// name so the frame can be brought to the current scale on restore.
- (NSString*)savedScaleKey
{
	NSString* name = self.window.frameAutosaveName;
	return name.length ? [@"OakScaledContainerScale " stringByAppendingString:name] : nil;
}

- (void)saveAppliedScale
{
	if(!_resizesWindow)
		return;
	if(NSString* key = self.savedScaleKey)
		[NSUserDefaults.standardUserDefaults setDouble:_appliedScale forKey:key];
}

// Resizes the window content by newScale/oldScale about its top-left corner,
// kept within the screen’s visible frame. Title bar accessories that are
// scaled containers (resizesWindow == NO) change height with the scale as
// well; they are budgeted from their unscaled content heights so that the
// result does not depend on whether they have already resized themselves.
- (void)resizeWindowFromScale:(CGFloat)oldScale toScale:(CGFloat)newScale
{
	NSWindow* window = self.window;
	if(!window || oldScale == newScale || oldScale <= 0)
		return;

	NSRect frame   = window.frame;
	NSRect content = [window contentRectForFrameRect:frame];
	NSSize chrome  = NSMakeSize(NSWidth(frame) - NSWidth(content), NSHeight(frame) - NSHeight(content));

	CGFloat accessoriesNow = 0, accessoriesOld = 0, accessoriesNew = 0;
	for(OakScaledContainerView* accessory in self.scaledAccessories)
	{
		CGFloat height  = accessory.designSize.height;
		accessoriesNow += NSHeight(accessory.frame);
		accessoriesOld += ceil(height * oldScale);
		accessoriesNew += ceil(height * newScale);
	}
	chrome.height   -= accessoriesNow;                                   // the fixed part of the chrome
	content.size.height = NSHeight(frame) - chrome.height - accessoriesOld; // the content at oldScale, whatever the accessories are at now

	content.size   = NSMakeSize(round(NSWidth(content) * newScale / oldScale), round(NSHeight(content) * newScale / oldScale));
	chrome.height += accessoriesNew;
	if(NSScreen* screen = window.screen ?: NSScreen.mainScreen)
	{
		content.size.width  = std::min(NSWidth(content),  NSWidth(screen.visibleFrame)  - chrome.width);
		content.size.height = std::min(NSHeight(content), NSHeight(screen.visibleFrame) - chrome.height);
	}
	NSRect newFrame = NSMakeRect(NSMinX(frame), 0, NSWidth(content) + chrome.width, NSHeight(content) + chrome.height);
	newFrame.origin.y = NSMaxY(frame) - NSHeight(newFrame);
	if(NSScreen* screen = window.screen ?: NSScreen.mainScreen)
	{
		// constrainFrameRect:toScreen: only keeps the title bar on screen; keep the whole window on it.
		NSRect visible = screen.visibleFrame;
		newFrame.origin.x = std::max(NSMinX(visible), std::min(NSMinX(newFrame), NSMaxX(visible) - NSWidth(newFrame)));
		newFrame.origin.y = std::max(NSMinY(visible), std::min(NSMinY(newFrame), NSMaxY(visible) - NSHeight(newFrame)));
	}
	newFrame = [window constrainFrameRect:newFrame toScreen:window.screen];
	[window setFrame:newFrame display:YES];
}

// The size the content is designed for: its fitting size when it has
// constraints, otherwise (a xib laid out with autoresizing masks) the frame
// it came with. The content is never placed smaller than this.
- (NSSize)designSize
{
	NSSize fitting = _contentView.fittingSize;
	return fitting.width > 0 && fitting.height > 0 ? fitting : _initialSize;
}

// The container that sizes a window, if any: OakSetScaledWindowContentView() puts it in a wrapper content view.
static OakScaledContainerView* OakScaledWindowContentContainer (NSWindow* window)
{
	for(NSView* view in window.contentView.subviews)
	{
		if([view isKindOfClass:[OakScaledContainerView class]] && ((OakScaledContainerView*)view).resizesWindow)
			return (OakScaledContainerView*)view;
	}
	return nil;
}

// Title bar accessories of the window that are scaled containers.
- (NSArray<OakScaledContainerView*>*)scaledAccessories
{
	NSMutableArray* res = [NSMutableArray array];
	if(!(self.window.styleMask & NSWindowStyleMaskTitled))
		return res; // a borderless window raises when asked for title bar accessories
	for(NSTitlebarAccessoryViewController* controller in self.window.titlebarAccessoryViewControllers)
	{
		if([controller.view isKindOfClass:[OakScaledContainerView class]] && !((OakScaledContainerView*)controller.view).resizesWindow)
			[res addObject:controller.view];
	}
	return res;
}

// The scale, reduced so that the content and the scaled title bar accessories
// fit the screen beside the fixed chrome. Only the fixed chrome is measured
// from the window, so the answer is the same before and after the
// accessories have been resized.
- (CGFloat)effectiveScale
{
	if(!_resizesWindow)
	{
		// Follow the container that sizes the window: it budgets our height for its scale.
		if(OakScaledContainerView* owner = OakScaledWindowContentContainer(self.window))
			return owner.effectiveScale;
	}

	CGFloat scale = OakUIFontScaleFactor();
	if(NSScreen* screen = self.window.screen ?: NSScreen.mainScreen)
	{
		NSSize available = screen.visibleFrame.size;
		NSSize design    = self.designSize;
		if(self.window && _resizesWindow)
		{
			CGFloat accessoriesNow = 0;
			for(OakScaledContainerView* accessory in self.scaledAccessories)
			{
				accessoriesNow += NSHeight(accessory.frame);
				design.height  += accessory.designSize.height;
			}
			available.width  -= NSWidth(self.window.frame)  - NSWidth(self.frame);
			available.height -= NSHeight(self.window.frame) - NSHeight(self.frame) - accessoriesNow;
		}
		scale = OakUIScaleThatFits(design, available, scale);
	}
	return scale;
}

- (NSSize)intrinsicContentSize
{
	NSSize fitting = self.designSize;
	CGFloat scale  = self.effectiveScale;
	return NSMakeSize(ceil(fitting.width * scale), ceil(fitting.height * scale));
}

- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	[self applyScale];
}

// The content’s frame turns into required constraints (it keeps its
// autoresizing mask), so it must never drop below the fitting size or those
// constraints fight the content’s own and AppKit raises.
- (void)placeContentView
{
	NSSize fitting = self.designSize;
	NSSize size    = NSMakeSize(std::max(NSWidth(self.bounds), fitting.width), std::max(NSHeight(self.bounds), fitting.height));
	_contentView.frame = NSMakeRect(0, 0, size.width, size.height);
}

- (void)applyScale
{
	CGFloat scale = self.effectiveScale;
	_appliedScale = scale;
	[self saveAppliedScale];
	// Each side that has a size is scaled: an empty content (a transition view with no subview yet) has a width but no height, and what it holds next is sized through the bounds.
	if(NSWidth(self.frame) > 0 || NSHeight(self.frame) > 0)
		[self setBoundsSize:NSMakeSize(NSWidth(self.frame) / scale, NSHeight(self.frame) / scale)];
	[self placeContentView];
}

- (void)layout
{
	[super layout];
	[self placeContentView];
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	[self invalidateIntrinsicContentSize];
	if(_resizesWindow)
	{
		// No saved scale (no autosave name, or a frame saved before there was a scale): the frame is at scale 1.
		NSString* key      = self.savedScaleKey;
		CGFloat savedScale = (key ? [NSUserDefaults.standardUserDefaults doubleForKey:key] : 0) ?: 1;
		[self resizeWindowFromScale:savedScale toScale:self.effectiveScale];
	}
	[self applyScale];
}

// Resize the window by the change in scale so the panel grows and shrinks
// with the setting rather than only growing. Kept at its top-left corner and
// on its screen.
- (void)uiFontScaleFactorDidChange:(NSNotification*)aNotification
{
	[self invalidateIntrinsicContentSize];

	if(_resizesWindow)
			[self resizeWindowFromScale:(_appliedScale ?: 1) toScale:self.effectiveScale];
	else	[self setFrameSize:NSMakeSize(NSWidth(self.frame), self.intrinsicContentSize.height)]; // a title bar accessory is as tall as its frame; its width is set by the window
	[self applyScale];
	self.needsLayout = YES;
}
@end

void OakSetScaledWindowContentView (NSWindow* window, NSView* contentView)
{
	OakScaledContainerView* container = [[OakScaledContainerView alloc] initWithContentView:contentView];
	NSView* wrapper = [[NSView alloc] initWithFrame:NSZeroRect];
	OakAddAutoLayoutViewsToSuperview(@[ container ], wrapper);
	[NSLayoutConstraint activateConstraints:@[
		[container.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
		[container.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],
		[container.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
		[container.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor],
	]];
	window.contentView = wrapper;
	[window layoutIfNeeded]; // size the content to the window now, so views added to it later fit (see the tests)

	// A frame restored smaller than the content (a panel whose design grew
	// since the frame was saved) would clip it: grow the window to fit.
	NSSize least   = container.intrinsicContentSize;
	NSRect content = [window contentRectForFrameRect:window.frame];
	if(NSWidth(content) < least.width || NSHeight(content) < least.height)
	{
		NSRect frame = [window frameRectForContentRect:NSMakeRect(NSMinX(content), NSMinY(content), std::max(NSWidth(content), least.width), std::max(NSHeight(content), least.height))];
		frame.origin.y = NSMaxY(window.frame) - NSHeight(frame); // keep the top-left corner
		[window setFrame:frame display:NO];
	}
}

CGFloat OakScaledContainerScaleForView (NSView* view)
{
	for(NSView* candidate = view; candidate; candidate = candidate.superview)
	{
		if([candidate isKindOfClass:[OakScaledContainerView class]])
			return ((OakScaledContainerView*)candidate).effectiveScale;
	}
	return 1;
}
