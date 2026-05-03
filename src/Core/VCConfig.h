/**
 * VCConfig -- 全局配置管理单例
 * bundleID / sandbox paths / feature flags
 */

#import <Foundation/Foundation.h>

typedef void (^VCUpdateCheckCompletion)(NSDictionary *info, NSError *error);

@interface VCConfig : NSObject

+ (instancetype)shared;

// 目标进程信息
@property (nonatomic, readonly) NSString *targetBundleID;
@property (nonatomic, readonly) NSString *targetDisplayName;
@property (nonatomic, readonly) NSString *targetVersion;

// 路径
@property (nonatomic, readonly) NSString *sandboxPath;       // Documents/VansonCLI/
@property (nonatomic, readonly) NSString *patchesPath;       // sandboxPath/patches/
@property (nonatomic, readonly) NSString *sessionsPath;      // sandboxPath/sessions/
@property (nonatomic, readonly) NSString *configPath;        // sandboxPath/config/

// Feature Flags
- (BOOL)isFeatureEnabled:(NSString *)featureID;
- (void)setFeature:(NSString *)featureID enabled:(BOOL)enabled;

// 版本
@property (nonatomic, readonly) NSString *vcVersion;
- (void)checkForUpdatesWithCompletion:(VCUpdateCheckCompletion)completion;

@end
