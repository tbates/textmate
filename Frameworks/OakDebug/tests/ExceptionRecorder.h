#import <ExceptionHandling/NSExceptionHandler.h>

// Records every exception NSExceptionHandler observes, the way TextMate's own
// handler does, without acting on it.
@interface ExceptionRecorder : NSObject
@property (nonatomic) NSMutableArray<NSException*>* exceptions;
@end

@implementation ExceptionRecorder
- (BOOL)exceptionHandler:(NSExceptionHandler*)sender shouldLogException:(NSException*)exception mask:(NSUInteger)mask
{
	[(_exceptions = _exceptions ?: [NSMutableArray array]) addObject:exception];
	return NO;
}
@end
