#import "OakTransitionViewController.h"
#import "OakScaledContainerView.h"

@interface OakTransitionViewController ()
{
	NSUInteger                    _animationCounter;
	NSArray<NSLayoutConstraint*>* _viewFrameConstraints;
	NSMutableArray<NSView*>*      _hostedSubviews;
}
@end

@implementation OakTransitionViewController
- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil
{
	if(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])
	{
		_hostedSubviews = [NSMutableArray array];
	}
	return self;
}

// Just below required: with no subview the view is empty, but its superview may
// still have to give it a frame for a moment (AppKit reshapes the window content
// while a toolbar is added), and an OakScaledContainerView places its content
// by frame, which is a required constraint. Required against required is
// unsatisfiable, which this app treats as fatal.
- (NSLayoutConstraint*)emptyHeightConstraint
{
	NSLayoutConstraint* res = [self.view.heightAnchor constraintEqualToConstant:0];
	res.priority = NSLayoutPriorityRequired - 1;
	return res;
}

- (void)loadView
{
	self.view = [[NSView alloc] initWithFrame:NSZeroRect];
	_viewFrameConstraints = @[ [self emptyHeightConstraint] ];
	[NSLayoutConstraint activateConstraints:_viewFrameConstraints];
}

- (void)setSubview:(NSView*)newView
{
	if(_subview == newView)
		return;

	NSWindow* window = self.view.window;
	if(_subview && [window.firstResponder isKindOfClass:[NSView class]] && [(NSView*)window.firstResponder isDescendantOf:_subview])
		[window makeFirstResponder:window];

	if(newView)
	{
		if(NSEqualSizes(NSZeroSize, newView.frame.size))
			newView.frame = { .size = newView.fittingSize };

		newView.translatesAutoresizingMaskIntoConstraints = NO;
		newView.wantsLayer = YES;
		newView.alphaValue = 0;

		[self.view addSubview:newView];
		[_hostedSubviews addObject:newView];
	}

	// Only update the key view loop if we are part of it
	if(self.view.nextKeyView)
	{
		std::set<NSView*> avoidLoop;

		NSView* lastOldView = self.view;
		for(NSView* view = _subview; view && [view isDescendantOf:self.view] && avoidLoop.insert(view).second; view = view.nextKeyView)
			lastOldView = view;

		NSView* lastNewView;
		for(NSView* view = newView; view && [view isDescendantOf:self.view] && avoidLoop.insert(view).second; view = view.nextKeyView)
			lastNewView = view;

		if(newView)
			lastNewView.nextKeyView = lastOldView.nextKeyView;
		self.view.nextKeyView = newView ?: lastOldView.nextKeyView;
		if(lastOldView != self.view)
			lastOldView.nextKeyView = nil;
	}

	// In window points: inside an OakScaledContainerView the views lay out in their own points, but the window is scale times larger. (Not convertSize:toView: — a side without size, this view before its first subview, has no transform.)
	CGFloat scale   = OakScaledContainerScaleForView(self.view);
	NSSize oldSize  = NSMakeSize(NSWidth(self.view.frame) * scale, NSHeight(self.view.frame) * scale);
	NSSize newSize  = newView ? NSMakeSize(NSWidth(newView.frame) * scale, NSHeight(newView.frame) * scale) : NSMakeSize(oldSize.width, 0);
	NSRect newFrame = NSOffsetRect(NSInsetRect(window.frame, (oldSize.width - newSize.width) / 2, (oldSize.height - newSize.height) / 2), (newSize.width - oldSize.width) / 2, (oldSize.height - newSize.height) / 2);

	NSRect screenFrame = (self.view.window.screen ?: NSScreen.mainScreen).visibleFrame;
	if(NSMinX(newFrame) < NSMinX(screenFrame))
		newFrame.origin.x += NSMinX(screenFrame) - NSMinX(newFrame);
	else if(NSMaxX(newFrame) > NSMaxX(screenFrame))
		newFrame.origin.x -= NSMaxX(newFrame) - NSMaxX(screenFrame);
	if(NSMinY(newFrame) < NSMinY(screenFrame))
		newFrame.origin.y += NSMinY(screenFrame) - NSMinY(newFrame);
	else if(NSMaxY(newFrame) > NSMaxY(screenFrame))
		newFrame.origin.y -= NSMaxY(newFrame) - NSMaxY(screenFrame);
	newFrame = NSIntersectionRect(newFrame, screenFrame);

	NSMutableArray* viewFrameConstraints = [NSMutableArray array];
	for(NSView* view in _hostedSubviews)
	{
		// The size is held just below required: a frame can disagree with a
		// view’s own required size (see the completion below), and the view’s own
		// size wins then.
		NSLayoutConstraint* width  = [view.widthAnchor  constraintEqualToConstant:NSWidth(view.frame) ];
		NSLayoutConstraint* height = [view.heightAnchor constraintEqualToConstant:NSHeight(view.frame)];
		width.priority  = NSLayoutPriorityRequired - 1;
		height.priority = NSLayoutPriorityRequired - 1;
		[viewFrameConstraints addObjectsFromArray:@[
			[view.leadingAnchor constraintEqualToAnchor:view.superview.leadingAnchor],
			[view.topAnchor     constraintEqualToAnchor:view.superview.topAnchor    ],
			width, height,
		]];
	}

	if(_viewFrameConstraints)
		[NSLayoutConstraint deactivateConstraints:_viewFrameConstraints];
	_viewFrameConstraints = viewFrameConstraints;
	[NSLayoutConstraint activateConstraints:_viewFrameConstraints];

	NSUInteger animationCounter = ++_animationCounter;

	auto animationBody = ^(BOOL animated){
		_subview.alphaValue = 0;
		_subview = newView;
		newView.alphaValue = 1;
		if(animated)
				[window setFrame:newFrame display:YES animate:YES];
		else	[window setFrame:newFrame display:YES];
	};

	auto animationCompletion = ^{
		if(animationCounter == _animationCounter)
		{
			[NSLayoutConstraint deactivateConstraints:_viewFrameConstraints];
			_viewFrameConstraints = nil;

			for(NSView* view in _hostedSubviews)
			{
				if(view != newView)
					[view removeFromSuperview];
			}
			[_hostedSubviews removeAllObjects];

			if(newView)
			{
				[_hostedSubviews addObject:newView];

				// The trailing and bottom edges are pinned just below required: a
				// subview whose constraints fix its size (a grid with explicit column
				// widths) keeps it at the top-left when this view is larger, e.g.
				// after a user resize or a fractional interface scale, rather than
				// making the layout unsatisfiable, which AppKit raises on.
				NSLayoutConstraint* bottom   = [newView.bottomAnchor   constraintEqualToAnchor:newView.superview.bottomAnchor  ];
				NSLayoutConstraint* trailing = [newView.trailingAnchor constraintEqualToAnchor:newView.superview.trailingAnchor];
				bottom.priority   = NSLayoutPriorityRequired - 1;
				trailing.priority = NSLayoutPriorityRequired - 1;
				_viewFrameConstraints = @[
					[newView.leadingAnchor constraintEqualToAnchor:newView.superview.leadingAnchor],
					[newView.topAnchor     constraintEqualToAnchor:newView.superview.topAnchor    ],
					bottom, trailing,
				];
				[NSLayoutConstraint activateConstraints:_viewFrameConstraints];
			}
			else
			{
				_viewFrameConstraints = @[
					[self emptyHeightConstraint]
				];
				[NSLayoutConstraint activateConstraints:_viewFrameConstraints];
			}
		}
	};

	if(@available(macos 10.15, *))
	{
		if(window && window.isVisible)
		{
			[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
				context.allowsImplicitAnimation = YES;
				context.duration                = 0.2;
				animationBody(NO);
			} completionHandler:animationCompletion];
		}
		else
		{
			animationBody(NO);
			animationCompletion();
		}
	}
	else
	{
		animationBody(YES);
		animationCompletion();
	}
}
@end
