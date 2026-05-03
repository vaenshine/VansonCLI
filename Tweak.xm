/**
 * VansonCLI -- Tweak Entry Point
 * 注入目标进程后的初始化入口
 */

#import "VansonCLI.h"
#import "src/Core/VCConfig.h"
#import "src/Core/VCSafeMode.h"
#import "src/Core/VCCore.hpp"
#import "src/Network/VCNetMonitor.h"
#import "src/UI/Base/VCFloatingButton.h"

/**
 * 初始化顺序:
 * 1. SafeMode -- crash 检测, 决定是否进入安全模式
 * 2. Config   -- 全局配置, 创建目录结构
 * 3. 各引擎   -- Slide-1~6 在集成阶段注册
 * 4. UI       -- Slide-14 在集成阶段初始化
 */

static BOOL gVCInitialized = NO;

static void vcInitialize(void) {
    @autoreleasepool {
        if (gVCInitialized) return;
        gVCInitialized = YES;

        VCLog(@"=== VansonCLI v%@ initializing ===", [[VCConfig shared] vcVersion]);
        VCLog(@"Target: %@ (%@)", [[VCConfig shared] targetDisplayName], [[VCConfig shared] targetBundleID]);

        // 1. SafeMode
        [VCSafeMode markLaunchStart];

        if ([VCSafeMode shouldEnterSafeMode]) {
            VCLog(@"SafeMode: ACTIVE -- patches disabled, minimal mode");
            [VCSafeMode disableAllPatches];
            // 安全模式下初始化 Config 后跳过引擎
            [VCConfig shared];
            return;
        }

        // 2. Config
        VCConfig *config = [VCConfig shared];
        VCLog(@"Config: sandbox = %@", config.sandboxPath);

        // 3. 引擎初始化 (Slide-14 集成阶段补充)
        // [VCRuntimeEngine shared];
        // [VCProcessInfo shared];
        // [VCUIInspector shared];
        // [VCAIEngine shared];
        // [VCCommandRouter shared];

        // 网络监控 -- 自动启动
        [[VCNetMonitor shared] startMonitoring];

        // 4. UI 初始化 -- 悬浮按钮
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
            [VCFloatingButton show];
        });

        // 标记启动成功 (清除 crash flag)
        [VCSafeMode markLaunchSuccess];

        VCLog(@"=== VansonCLI initialized ===");
    }
}

%ctor {
    // 延迟到 UIApplicationDidFinishLaunching 之后初始化
    // 确保 UIKit 已完全加载
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        vcInitialize();
    }];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        if (app && (app.applicationState == UIApplicationStateActive ||
                    app.applicationState == UIApplicationStateInactive ||
                    app.applicationState == UIApplicationStateBackground)) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                vcInitialize();
            });
        }
    });
}
