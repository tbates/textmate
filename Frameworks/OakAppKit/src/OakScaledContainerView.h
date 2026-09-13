// Zooms a whole view tree by the UI font scale without touching its
// controls: the content view keeps laying out in its own points and the
// container draws it through a bounds transform. Standard bezelled
// controls cannot be scaled by re-fonting (a rounded push button keeps its
// 24 pt bezel whatever font it is given), so dialogs use this instead.
//
// The content view is placed manually (translatesAutoresizingMaskIntoConstraints
// stays YES) so its constraints never reach the container's superview. The
// container's intrinsic size is the content's fitting size × scale, which is
// what the window sizes itself from; when the window grows, the container's
// bounds follow frame ÷ scale and the content reflows in its own units.
//
// The scale is capped so the content fits the screen the window is on.
@interface OakScaledContainerView : NSView
- (instancetype)initWithContentView:(NSView*)contentView;
@property (nonatomic, readonly) NSView* contentView;
@property (nonatomic, readonly) CGFloat effectiveScale;
@end

// Installs contentView in a window inside an OakScaledContainerView.
void OakSetScaledWindowContentView (NSWindow* window, NSView* contentView);
