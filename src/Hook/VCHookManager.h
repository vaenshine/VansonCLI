/**
 * VCHookManager -- 动态 Hook 执行引擎
 * Slide-12: Patches Engine
 */

#import <Foundation/Foundation.h>

@class VCPatchItem;
@class VCHookItem;
@class VCValueItem;

extern NSString *const kVCHookManagerDidCaptureInvocationNotification;

@interface VCHookManager : NSObject

+ (instancetype)shared;

// Patch 执行
- (BOOL)applyPatch:(VCPatchItem *)item;
- (BOOL)revertPatch:(VCPatchItem *)item;

// Hook 安装
- (BOOL)installHook:(VCHookItem *)item;
- (BOOL)removeHook:(VCHookItem *)item;

// 当前线程上由 traced hook 建立的调用上下文快照
- (NSDictionary *)currentTraceContextSnapshot;

// 值锁定
- (BOOL)startLocking:(VCValueItem *)item;
- (void)stopLocking:(VCValueItem *)item;
- (void)stopAllLocks;
- (BOOL)writeValue:(NSString *)value toAddress:(uintptr_t)addr dataType:(NSString *)type;

@end
