#import "OakRolloverButton.h"
typedef NS_ENUM(NSUInteger, OakBackgroundFillViewStyle) {
	OakBackgroundFillViewStyleNone = 0,
	OakBackgroundFillViewStyleHeader,
};

@interface OakBackgroundFillView : NSView
@property (nonatomic) OakBackgroundFillViewStyle style;
@property (nonatomic) NSColor* activeBackgroundColor;
@property (nonatomic) NSColor* inactiveBackgroundColor;
@property (nonatomic) NSGradient* activeBackgroundGradient;
@property (nonatomic) NSGradient* inactiveBackgroundGradient;
@property (nonatomic) BOOL active;
@end

// User-adjustable scale applied to the fonts and metrics of the window
// chrome (tab bar, status bars, file browser). Stored in user defaults;
// 1 means the stock sizes. Views that size themselves from these read them
// again when the notification fires.
extern NSString* const kUserDefaultsUIFontScaleFactorKey;
extern NSNotificationName const OakUIFontScaleFactorDidChangeNotification;
extern CGFloat const kOakUIFontScaleFactorMin;
extern CGFloat const kOakUIFontScaleFactorMax;
extern CGFloat const kOakUIFontScaleFactorStep;

CGFloat OakUIFontScaleFactor ();
void OakSetUIFontScaleFactor (CGFloat scale);
NSFont* OakScaledUIFont (NSFont* base);
CGFloat OakScaledUIMetric (CGFloat metric);
NSImage* OakScaledUIImage (NSImage* base); // a copy of base at base.size × scale, or for a system symbol a symbol at 13 × scale pt; base (often a shared named image) is left alone
CGFloat OakUIScaleThatFits (NSSize designSize, NSSize availableSize, CGFloat scale); // scale, reduced (never below 1) so designSize × result fits availableSize

NSFont* OakStatusBarFont ();     // OakStatusBarBaseFont() × the UI scale
NSFont* OakStatusBarBaseFont (); // for text inside an OakScaledContainerView, which zooms it
NSFont* OakControlFont ();

NSTextField* OakCreateLabel (NSString* label = @"", NSFont* font = nil, NSTextAlignment alignment = NSTextAlignmentLeft, NSLineBreakMode lineBreakMode = NSLineBreakByTruncatingMiddle);
NSButton* OakCreateCheckBox (NSString* label);
NSButton* OakCreateButton (NSString* label, NSBezelStyle bezel = NSBezelStyleRounded);
NSPopUpButton* OakCreatePopUpButton (BOOL pullsDown = NO, NSString* initialItemTitle = nil, NSView* labelView = nil);
NSPopUpButton* OakCreateActionPopUpButton (BOOL bordered = NO);
NSComboBox* OakCreateComboBox (NSView* labelView = nil);
OakRolloverButton* OakCreateCloseButton (NSString* accessibilityLabel = @"Close document");
NSView* OakCreateNSBoxSeparator ();

OakBackgroundFillView* OakCreateVerticalLine (OakBackgroundFillViewStyle style);
void OakSetupKeyViewLoop (NSArray<NSView*>* views);
void OakAddAutoLayoutViewsToSuperview (NSArray<NSView*>* views, NSView* superview);
