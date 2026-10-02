#import <OakTextView/OakTextView.h>

// The text view builds its command variables in a method it does not declare
// publicly; the tests call it directly.
@interface OakTextView (Variables)
- (std::map<std::string, std::string>)variables;
@end
