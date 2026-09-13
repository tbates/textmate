#import "OFBActionsView.h"
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakAppKit/OakScaledImageButton.h>

static NSButton* OakCreateImageButton (NSImage* image)
{
	OakScaledImageButton* res = [OakScaledImageButton new];
	res.baseImage = image;
	return res;
}

@interface OFBActionsView ()
@property (nonatomic) NSView* topDivider;
@property (nonatomic) NSView* divider;
@property (nonatomic) NSArray<NSLayoutConstraint*>* metricConstraints;
@property (nonatomic) NSView* wrappedActionsPopUpButton;
@property (nonatomic) NSImage* actionsBaseImage;
@end

@implementation OFBActionsView
- (id)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		self.wantsLayer   = YES;
		self.material     = NSVisualEffectMaterialTitlebar;
		self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
		self.state        = NSVisualEffectStateFollowsWindowActiveState;

		self.createButton       = OakCreateImageButton([NSImage imageNamed:NSImageNameAddTemplate]);
		self.actionsPopUpButton = OakCreateActionPopUpButton();
		self.reloadButton       = OakCreateImageButton([NSImage imageNamed:NSImageNameRefreshTemplate]);
		self.searchButton       = OakCreateImageButton([NSImage imageNamed:@"SearchTemplate" inSameBundleAsClass:[self class]]);
		self.favoritesButton    = OakCreateImageButton([NSImage imageNamed:@"FavoritesTemplate" inSameBundleAsClass:[self class]]);
		self.scmButton          = OakCreateImageButton([NSImage imageNamed:@"SCMTemplate" inSameBundleAsClass:[self class]]);

		self.createButton.toolTip       = @"Create new file";
		self.reloadButton.toolTip       = @"Reload file browser";
		self.searchButton.toolTip       = @"Search current folder";
		self.favoritesButton.toolTip    = @"Show favorites";
		// A button cannot display a key equivalent, so the tool tip carries it —
		// the binding is otherwise only discoverable under the File Browser menu,
		// which is not where one looks for an SCM action. Kept in step with
		// AppController's "SCM Status" item, which owns the shortcut.
		NSString* const scmDescription  = @"Show source control management status";
		self.scmButton.toolTip          = [scmDescription stringByAppendingString:@" (⇧⌘Y)"];

		((OakScaledImageButton*)self.reloadButton).baseImage.accessibilityDescription    = self.reloadButton.toolTip;
		((OakScaledImageButton*)self.createButton).baseImage.accessibilityDescription    = self.createButton.toolTip;
		((OakScaledImageButton*)self.searchButton).baseImage.accessibilityDescription    = self.searchButton.toolTip;
		((OakScaledImageButton*)self.favoritesButton).baseImage.accessibilityDescription = self.favoritesButton.toolTip;
		((OakScaledImageButton*)self.scmButton).baseImage.accessibilityDescription       = scmDescription;

		NSView* wrappedActionsPopUpButton = _wrappedActionsPopUpButton = [NSView new];
		_actionsBaseImage = [[self.actionsPopUpButton cell] menuItem].image;
		[self updateImages];
		OakAddAutoLayoutViewsToSuperview(@[ self.actionsPopUpButton ], wrappedActionsPopUpButton);
		[wrappedActionsPopUpButton addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[popup]|" options:0 metrics:nil views:@{ @"popup": self.actionsPopUpButton }]];
		[wrappedActionsPopUpButton addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[popup]|" options:0 metrics:nil views:@{ @"popup": self.actionsPopUpButton }]];

		NSView* topDivider = _topDivider = OakCreateNSBoxSeparator();
		_divider = OakCreateNSBoxSeparator();

		NSDictionary* views = @{
			@"topDivider": topDivider,
			@"create":     self.createButton,
			@"divider":    _divider,
			@"actions":    wrappedActionsPopUpButton,
			@"reload":     self.reloadButton,
			@"search":     self.searchButton,
			@"favorites":  self.favoritesButton,
			@"scm":        self.scmButton,
		};

		OakAddAutoLayoutViewsToSuperview([views allValues], self);
		OakSetupKeyViewLoop(@[ self, _createButton, _actionsPopUpButton, _reloadButton, _searchButton, _favoritesButton, _scmButton ]);

		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[topDivider]|"                                                                                         options:0 metrics:nil views:views]];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(uiFontScaleFactorDidChange:) name:OakUIFontScaleFactorDidChangeNotification object:nil];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

// The divider sets the bar’s height: 15 pt with 4 pt above and 5 pt below
// at the stock scale, under the 1 pt top divider.
- (void)updateConstraints
{
	if(_metricConstraints)
		[self removeConstraints:_metricConstraints];
	[super updateConstraints];

	NSDictionary* metrics = @{ @"top": @(OakScaledUIMetric(4)), @"height": @(OakScaledUIMetric(15)), @"bottom": @(OakScaledUIMetric(5)), @"actions": @(OakScaledUIMetric(31)) };
	NSDictionary* views   = @{ @"topDivider": _topDivider, @"create": _createButton, @"divider": _divider, @"actions": _wrappedActionsPopUpButton, @"reload": _reloadButton, @"search": _searchButton, @"favorites": _favoritesButton, @"scm": _scmButton };
	NSMutableArray* constraints = [NSMutableArray array];
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-8-[create]-8-[divider(==1)]-8-[actions(==actions)]-(>=8)-[reload]-4-[search]-4-[favorites]-4-[scm]-(12)-|" options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[topDivider(==1)]-(top)-[divider(==height)]-(bottom)-|" options:0 metrics:metrics views:views]];
	_metricConstraints = constraints;
	[self addConstraints:_metricConstraints];
}

- (void)updateImages
{
	[[self.actionsPopUpButton cell] menuItem].image = OakScaledUIImage(_actionsBaseImage);
}

- (void)uiFontScaleFactorDidChange:(NSNotification*)aNotification
{
	[self updateImages];
	self.needsUpdateConstraints = YES;
}
@end
