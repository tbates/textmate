#import <OakTabBarView/OakTabBarView.h>

// A data source with a fixed number of tabs, for the tab width tests.
@interface TabWidthsDataSource : NSObject <OakTabBarViewDataSource>
@property (nonatomic) NSUInteger count;
@end

@implementation TabWidthsDataSource
- (NSUInteger)numberOfRowsInTabBarView:(OakTabBarView*)aTabBarView             { return _count; }
- (NSString*)tabBarView:(OakTabBarView*)aTabBarView titleForIndex:(NSUInteger)i { return [NSString stringWithFormat:@"Tab %lu", i]; }
- (NSString*)tabBarView:(OakTabBarView*)aTabBarView pathForIndex:(NSUInteger)i  { return nil; }
- (NSUUID*)tabBarView:(OakTabBarView*)aTabBarView UUIDForIndex:(NSUInteger)i    { return [[NSUUID alloc] initWithUUIDString:[NSString stringWithFormat:@"00000000-0000-0000-0000-%012lu", i]]; }
- (BOOL)tabBarView:(OakTabBarView*)aTabBarView isEditedAtIndex:(NSUInteger)i   { return NO; }
@end
