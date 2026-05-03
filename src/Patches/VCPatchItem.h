/**
 * VCPatchItem -- 方法补丁模型
 * Slide-12: Patches Engine
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, VCItemSource) {
    VCItemSourceAI = 0,
    VCItemSourceConsole = 1,
    VCItemSourceManual = 2,
};

@interface VCPatchItem : NSObject <NSCoding>

@property (nonatomic, strong) NSString *patchID;
@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong) NSString *selector;
@property (nonatomic, strong) NSString *patchType;       // "return_yes" / "return_no" / "nop" / "custom" / "swizzle"
@property (nonatomic, strong) NSString *customCode;
@property (nonatomic, strong) NSString *remark;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) VCItemSource source;
@property (nonatomic, strong) NSString *sourceToolID;
@property (nonatomic, assign) BOOL isDisabledBySafeMode;
@property (nonatomic, strong) NSDate *createdAt;

@end
