/**
 * VCAutoSave.mm -- 30s 定时自动保存实现
 */

#import "VCAutoSave.h"
#import "VCChatSession.h"
#import "../../../VansonCLI.h"

static const NSTimeInterval kAutoSaveInterval = 30.0;

@implementation VCAutoSave {
    NSTimer *_timer;
}

+ (instancetype)shared {
    static VCAutoSave *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCAutoSave alloc] init];
    });
    return instance;
}

- (void)start {
    [self stop];
    _timer = [NSTimer scheduledTimerWithTimeInterval:kAutoSaveInterval
                                              target:self
                                            selector:@selector(_autoSaveTick)
                                            userInfo:nil
                                             repeats:YES];
    // Allow timer to fire even during UI tracking
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    VCLog(@"AutoSave: started (%.0fs interval)", kAutoSaveInterval);
}

- (void)stop {
    [_timer invalidate];
    _timer = nil;
}

- (void)saveNow {
    [[VCChatSession shared] saveAll];
}

- (void)_autoSaveTick {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [[VCChatSession shared] saveAll];
    });
}

- (void)dealloc {
    [self stop];
}

@end
