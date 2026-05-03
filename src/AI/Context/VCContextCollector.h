/**
 * VCContextCollector -- 上下文收集
 * 从各模块收集当前调试上下文, Tab 切换时自动调用
 */

#import <Foundation/Foundation.h>

@interface VCContextCollector : NSObject

+ (instancetype)shared;

/**
 * 收集指定 Tab 的上下文
 * @param tabName "inspect" / "network" / "ui" / "patches" / "console"
 * @return 包含该 Tab 当前可见关键数据摘要的 dict
 */
- (NSDictionary *)collectContextForTab:(NSString *)tabName;

@end
