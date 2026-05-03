/**
 * VCNetRule -- 网络拦截规则模型
 * Slide-12: Patches Engine
 */

#import <Foundation/Foundation.h>
#import "VCPatchItem.h"  // VCItemSource

@interface VCNetRule : NSObject <NSCoding>

@property (nonatomic, strong) NSString *ruleID;
@property (nonatomic, strong) NSString *urlPattern;      // 正则或通配符
@property (nonatomic, strong) NSString *action;          // "modify_header" / "modify_body" / "block" / "delay"
@property (nonatomic, strong) NSDictionary *modifications;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, strong) NSString *remark;
@property (nonatomic, assign) VCItemSource source;
@property (nonatomic, strong) NSString *sourceToolID;
@property (nonatomic, assign) BOOL isDisabledBySafeMode;
@property (nonatomic, strong) NSDate *createdAt;

@end
