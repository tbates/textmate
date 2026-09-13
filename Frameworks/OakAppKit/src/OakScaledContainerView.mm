#import "OakScaledContainerView.h"
#import "OakUIConstructionFunctions.h"

@implementation OakScaledContainerView
{
	CGFloat _appliedScale; // the scale the window was last sized for
}

- (instancetype)initWithContentView:(NSView*)contentView
{
	if(self = [super initWithFrame:NSZeroRect])
	{
		_contentView = contentView;
		_contentView.translatesAutoresizingMaskIntoConstraints = YES;
		_contentView.autoresizingMask = NSViewNotSizable;
		_contentView.frame = (NSRect){ NSZeroPoint, _contentView.fittingSize };
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
	if(NSString* key = self.savedScaleKey)
		[NSUserDefaults.standardUserDefaults setDouble:_appliedScale forKey:key];
}

// Resizes the window content by newScale/oldScale about its top-left corner,
// kept within the screen’s visible frame.
- (void)resizeWindowFromScale:(CGFloat)oldScale toScale:(CGFloat)newScale
{
	NSWindow* window = self.window;
	if(!window || oldScale == newScale || oldScale <= 0)
		return;

	NSRect frame   = window.frame;
	NSRect content = [window contentRectForFrameRect:frame];
	NSSize chrome  = NSMakeSize(NSWidth(frame) - NSWidth(content), NSHeight(frame) - NSHeight(content));
	content.size   = NSMakeSize(round(NSWidth(content) * newScale / oldScale), round(NSHeight(content) * newScale / oldScale));
	if(NSScreen* screen = window.screen ?: NSScreen.mainScreen)
	{
		content.size.width  = std::min(NSWidth(content),  NSWidth(screen.visibleFrame)  - chrome.width);
		content.size.height = std::min(NSHeight(content), NSHeight(screen.visibleFrame) - chrome.height);
	}
	NSRect newFrame = [window frameRectForContentRect:content];
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

- (CGFloat)effectiveScale
{
	CGFloat scale = OakUIFontScaleFactor();
	if(NSScreen* screen = self.window.screen ?: NSScreen.mainScreen)
	{
		// Room for the content: the screen’s visible area less the window chrome around us.
		NSSize available = screen.visibleFrame.size;
		if(self.window)
		{
			available.width  -= NSWidth(self.window.frame)  - NSWidth(self.frame);
			available.height -= NSHeight(self.window.frame) - NSHeight(self.frame);
		}
		scale = OakUIScaleThatFits(_contentView.fittingSize, available, scale);
	}
	return scale;
}

- (NSSize)intrinsicContentSize
{
	NSSize fitting = _contentView.fittingSize;
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
	NSSize fitting = _contentView.fittingSize;
	NSSize size    = NSMakeSize(std::max(NSWidth(self.bounds), fitting.width), std::max(NSHeight(self.bounds), fitting.height));
	_contentView.frame = NSMakeRect(0, 0, size.width, size.height);
}

- (void)applyScale
{
	CGFloat scale = self.effectiveScale;
	_appliedScale = scale;
	[self saveAppliedScale];
	if(NSWidth(self.frame) > 0 && NSHeight(self.frame) > 0)
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
	if(NSString* key = self.savedScaleKey)
	{
		CGFloat savedScale = [NSUserDefaults.standardUserDefaults doubleForKey:key];
		if(savedScale > 0)
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

	[self resizeWindowFromScale:(_appliedScale ?: 1) toScale:self.effectiveScale];
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
}
