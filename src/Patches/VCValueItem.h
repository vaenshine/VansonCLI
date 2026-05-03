/**
 * VCValueItem -- 内存值修改模型
 * Slide-12: Patches Engine
 */

#import <Foundation/Foundation.h>
#import "VCPatchItem.h"  // VCItemSource

@interface VCValueItem : NSObject <NSCoding>

@property (nonatomic, strong) NSString *valueID;
@property (nonatomic, strong) NSString *targetDesc;      // e.g. "AuthManager._userToken"
@property (nonatomic, assign) uintptr_t address;
@property (nonatomic, assign) ptrdiff_t offset;
@property (nonatomic, strong) NSString *dataType;        // "int" / "float" / "NSString" / "BOOL" / "double" / "long"
@property (nonatomic, strong) NSString *originalValue;
@property (nonatomic, strong) NSString *modifiedValue;
@property (nonatomic, assign) BOOL locked;
@property (nonatomic, strong) NSString *remark;
@property (nonatomic, assign) VCItemSource source;
@property (nonatomic, strong) NSString *sourceToolID;
@property (nonatomic, assign) BOOL isDisabledBySafeMode;
@property (nonatomic, strong) NSDate *createdAt;

@end
