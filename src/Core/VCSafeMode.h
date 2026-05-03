/**
 * VCSafeMode -- 安全模式
 * Crash 检测 + 自动禁用 patches + 连续 crash 保护 (3次)
 */

#import <Foundation/Foundation.h>

@interface VCSafeMode : NSObject

// 启动时调用
+ (BOOL)shouldEnterSafeMode;
+ (void)markLaunchStart;
+ (void)markLaunchSuccess;

// 安全模式操作
+ (void)disableAllPatches;
+ (void)resetCrashCounter;

// 状态
+ (BOOL)isInSafeMode;
+ (NSUInteger)consecutiveCrashCount;

@end
