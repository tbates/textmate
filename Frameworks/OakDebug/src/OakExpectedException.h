#import <Foundation/Foundation.h>

// Exceptions the frameworks raise and catch themselves. TextMate's exception
// handler observes every exception when it is thrown, before anyone catches
// it, and aborts on all but these.
BOOL OakExceptionIsExpected (NSException* exception);
