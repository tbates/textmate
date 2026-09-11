#include <bundles/bundles.h>

@interface BundleEditor : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (class, readonly) BundleEditor* sharedInstance;
- (void)revealBundleItem:(bundles::item_ptr const&)anItem;
@end
