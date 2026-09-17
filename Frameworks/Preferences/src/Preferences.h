@protocol PreferencesPaneProtocol <NSObject>
@optional
@property (nonatomic, readonly) NSImage* toolbarItemImage;
@property (nonatomic, readonly, getter=isResizable) BOOL resizable; // the window may be made larger than the pane (a pane with a list); otherwise it is fixed at the pane’s size
@end

@interface Preferences : NSWindowController
@property (class, readonly) Preferences* sharedInstance;
@end
