/**
 * VCHookItem -- 动态 Hook 模型
 * Slide-12: Patches Engine
 */

#import <Foundation/Foundation.h>
#import "VCPatchItem.h"  // VCItemSource

@interface VCHookItem : NSObject <NSCoding>

@property (nonatomic, strong) NSString *hookID;
@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong) NSString *selector;
@property (nonatomic, strong) NSString *hookType;        // "log" / "modify_args" / "modify_return" / "custom"
@property (nonatomic, strong) NSString *remark;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL isClassMethod;
@property (nonatomic, assign) NSUInteger hitCount;
@property (nonatomic, assign) VCItemSource source;
@property (nonatomic, strong) NSString *sourceToolID;
@property (nonatomic, assign) BOOL isDisabledBySafeMode;
@property (nonatomic, strong) NSDate *createdAt;

@end
