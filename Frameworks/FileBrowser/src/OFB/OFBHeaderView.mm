#import "OFBHeaderView.h"
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/OakScaledImageButton.h>

static NSButton* OakCreateImageButton (NSString* imageName)
{
	OakScaledImageButton* res = [[OakScaledImageButton alloc] initWithFrame:NSZeroRect];
	res.baseImage = [NSImage imageNamed:imageName];
	return res;
}

static NSPopUpButton* OakCreateFolderPopUpButton ()
{
	NSPopUpButton* res = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
	[res setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[res setContentHuggingPriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
	[res setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
	[res setBordered:NO];
	return res;
}

@interface OFBHeaderView ()
@property (nonatomic) NSView* bottomDivider;
@property (nonatomic) NSView* divider;
@property (nonatomic) NSFont* folderPopUpBaseFont;
@property (nonatomic) NSArray<NSLayoutConstraint*>* metricConstraints;
@end

@implementation OFBHeaderView
- (id)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		self.wantsLayer   = YES;
		self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
		self.material     = NSVisualEffectMaterialTitlebar;

		self.folderPopUpButton       = OakCreateFolderPopUpButton();
		self.folderPopUpBaseFont     = self.folderPopUpButton.font;
		self.goBackButton            = OakCreateImageButton(NSImageNameGoLeftTemplate);
		self.goBackButton.toolTip    = @"Go Back";
		self.goForwardButton         = OakCreateImageButton(NSImageNameGoRightTemplate);
		self.goForwardButton.toolTip = @"Go Forward";

		self.folderPopUpButton.accessibilityLabel           = @"Current folder";
		((OakScaledImageButton*)self.goBackButton).baseImage.accessibilityDescription    = self.goBackButton.toolTip;
		((OakScaledImageButton*)self.goForwardButton).baseImage.accessibilityDescription = self.goForwardButton.toolTip;

		_bottomDivider = OakCreateNSBoxSeparator();
		_divider       = OakCreateNSBoxSeparator();

		NSDictionary* views = @{
			@"folder":        self.folderPopUpButton,
			@"divider":       _divider,
			@"back":          self.goBackButton,
			@"forward":       self.goForwardButton,
			@"bottomDivider": _bottomDivider,
		};

		OakAddAutoLayoutViewsToSuperview([views allValues], self);
		OakSetupKeyViewLoop(@[ self, _folderPopUpButton, _goBackButton, _goForwardButton ]);

		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[bottomDivider]|"                                                                     options:0 metrics:nil views:views]];
		[self updateFonts];

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(uiFontScaleFactorDidChange:) name:OakUIFontScaleFactorDidChangeNotification object:nil];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)updateFonts
{
	self.folderPopUpButton.font = OakScaledUIFont(_folderPopUpBaseFont);
}

// The divider sets the bar’s height: 15 pt with 4 pt above and below at the
// stock scale, plus the 1 pt bottom divider. Done in updateConstraints so
// that fittingSize (which FileBrowserView uses for the list’s top inset)
// reflects the current scale as soon as the constraints are marked stale.
- (void)updateConstraints
{
	if(_metricConstraints)
		[self removeConstraints:_metricConstraints];
	[super updateConstraints];

	NSDictionary* metrics = @{ @"margin": @(OakScaledUIMetric(4)), @"height": @(OakScaledUIMetric(15)), @"button": @(OakScaledUIMetric(22)) };
	NSDictionary* views   = @{ @"folder": _folderPopUpButton, @"divider": _divider, @"back": _goBackButton, @"forward": _goForwardButton, @"bottomDivider": _bottomDivider };
	NSMutableArray* constraints = [NSMutableArray array];
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(3)-[folder(>=75)]-(3)-[divider(==1)]-(2)-[back(==button)]-(2)-[forward(==back)]-(3)-|" options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(margin)-[divider(==height)]-(margin)-[bottomDivider(==1)]|" options:0 metrics:metrics views:views]];
	_metricConstraints = constraints;
	[self addConstraints:_metricConstraints];
}

- (void)uiFontScaleFactorDidChange:(NSNotification*)aNotification
{
	[self updateFonts];
	self.needsUpdateConstraints = YES;
}
@end
