/**
 * VCSafeMode.mm -- 安全模式实现
 *
 * 逻辑:
 * 1. markLaunchStart 写入 crash flag + 时间戳
 * 2. 如果 N 秒内再次启动 (flag 未清除) -> crash count++
 * 3. crash count >= 3 -> 进入安全模式, 禁用所有 patches
 * 4. markLaunchSuccess 在初始化完成后调用, 清除 crash flag
 */

#import "VCSafeMode.h"
#import "VCConfig.h"
#import "../../VansonCLI.h"

static NSString *const kCrashFlagKey   = @"com.vanson.cli.crashFlag";
static NSString *const kCrashCountKey  = @"com.vanson.cli.crashCount";
static NSString *const kLaunchTimeKey  = @"com.vanson.cli.launchTime";
static NSString *const kSafeModeKey    = @"com.vanson.cli.safeMode";

static const NSTimeInterval kCrashWindow = 10.0; // 10 秒内重启视为 crash
static const NSUInteger kMaxCrashes = 3;

static BOOL _safeMode = NO;

@implementation VCSafeMode

+ (BOOL)shouldEnterSafeMode {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL hadCrashFlag = [ud boolForKey:kCrashFlagKey];
    NSUInteger crashCount = [ud integerForKey:kCrashCountKey];

    if (hadCrashFlag) {
        NSTimeInterval lastLaunch = [ud doubleForKey:kLaunchTimeKey];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

        if ((now - lastLaunch) < kCrashWindow) {
            crashCount++;
            [ud setInteger:crashCount forKey:kCrashCountKey];
            VCLog(@"SafeMode: crash detected (%lu/%lu)", (unsigned long)crashCount, (unsigned long)kMaxCrashes);
        }
    }

    if (crashCount >= kMaxCrashes) {
        _safeMode = YES;
        [ud setBool:YES forKey:kSafeModeKey];
        VCLog(@"SafeMode: ACTIVATED -- %lu consecutive crashes", (unsigned long)crashCount);
        return YES;
    }

    _safeMode = [ud boolForKey:kSafeModeKey];
    return _safeMode;
}

+ (void)markLaunchStart {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:YES forKey:kCrashFlagKey];
    [ud setDouble:[[NSDate date] timeIntervalSince1970] forKey:kLaunchTimeKey];
    [ud synchronize];
}

+ (void)markLaunchSuccess {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:NO forKey:kCrashFlagKey];
    [ud setInteger:0 forKey:kCrashCountKey];
    [ud synchronize];
    VCLog(@"SafeMode: launch success, crash counter reset");
}

+ (void)disableAllPatches {
    // Slide-12 (VCPatchManager) 集成时实现
    // 此处预留: 通知 PatchManager 禁用所有项
    VCLog(@"SafeMode: disableAllPatches called (pending Slide-12 integration)");
    [[NSNotificationCenter defaultCenter] postNotificationName:@"VCSafeModeDisablePatches" object:nil];
}

+ (void)resetCrashCounter {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:NO forKey:kCrashFlagKey];
    [ud setInteger:0 forKey:kCrashCountKey];
    [ud setBool:NO forKey:kSafeModeKey];
    [ud synchronize];
    _safeMode = NO;
    VCLog(@"SafeMode: manually reset");
}

+ (BOOL)isInSafeMode {
    return _safeMode;
}

+ (NSUInteger)consecutiveCrashCount {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kCrashCountKey];
}

@end
