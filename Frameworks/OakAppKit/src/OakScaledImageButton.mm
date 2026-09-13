#import "OakScaledImageButton.h"
#import "OakUIConstructionFunctions.h"

@implementation OakScaledImageButton
- (instancetype)initWithFrame:(NSRect)aFrame
{
	if(self = [super initWithFrame:aFrame])
	{
		self.buttonType    = NSButtonTypeMomentaryChange;
		self.bordered      = NO;
		self.imagePosition = NSImageOnly;
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(uiFontScaleFactorDidChange:) name:OakUIFontScaleFactorDidChangeNotification object:nil];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setBaseImage:(NSImage*)anImage
{
	_baseImage = anImage;
	[self updateImage];
}

- (void)updateImage
{
	self.image = OakScaledUIImage(_baseImage);
	[self invalidateIntrinsicContentSize];
}

- (void)uiFontScaleFactorDidChange:(NSNotification*)aNotification
{
	[self updateImage];
}
@end
