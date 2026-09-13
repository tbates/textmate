// An unbordered, image-only button whose glyph follows the UI font scale.
// Set baseImage (the stock-size image); the button shows it scaled and
// re-scales itself when the scale changes.
@interface OakScaledImageButton : NSButton
@property (nonatomic) NSImage* baseImage;
@end
