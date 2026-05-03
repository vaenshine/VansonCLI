/**
 * VCCapabilityManager -- runtime mutation capability detection
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCCapabilityManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, copy) NSString *hookBackend;
@property (nonatomic, readonly) BOOL jailbreakEnvironmentLikely;
@property (nonatomic, readonly) BOOL canModifyRuntime;
@property (nonatomic, readonly) BOOL canInstallHooks;
@property (nonatomic, readonly) BOOL canWriteMemory;
@property (nonatomic, readonly) BOOL canWriteDataMemory;
@property (nonatomic, readonly) BOOL canPatchExecutableText;
@property (nonatomic, readonly) BOOL developerOverrideEnabled;

- (NSDictionary *)capabilitiesSnapshot;
- (BOOL)canUseRuntimePatchingWithReason:(NSString * _Nullable * _Nullable)reason;
- (BOOL)canUseHookingWithReason:(NSString * _Nullable * _Nullable)reason;
- (BOOL)canUseMemoryWritesWithReason:(NSString * _Nullable * _Nullable)reason;

@end

NS_ASSUME_NONNULL_END
