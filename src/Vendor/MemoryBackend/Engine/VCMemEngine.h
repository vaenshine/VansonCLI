/**
 * VansonCLI Memory Backend - Memory Engine (ObjC Bridge)
 * 内存搜索引擎 ObjC 接口
 * 简化版：仅保留内存搜索功能
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 数据类型枚举
typedef NS_ENUM(NSUInteger, VCMemDataType) {
    VCMemDataTypeI8 = 0,
    VCMemDataTypeI16 = 1,
    VCMemDataTypeI32 = 2,
    VCMemDataTypeI64 = 3,
    VCMemDataTypeU8 = 4,
    VCMemDataTypeU16 = 5,
    VCMemDataTypeU32 = 6,
    VCMemDataTypeU64 = 7,
    VCMemDataTypeF32 = 8,
    VCMemDataTypeF64 = 9,
    VCMemDataTypeString = 10,
    VCMemDataTypeIntAuto = 11,
    VCMemDataTypeUIntAuto = 12,
    VCMemDataTypeFloatAuto = 13
};

// 搜索模式
typedef NS_ENUM(NSUInteger, VCMemSearchMode) {
    VCMemSearchModeExact = 0,
    VCMemSearchModeFuzzy = 1,
    VCMemSearchModeGroup = 2,
    VCMemSearchModeBetween = 3
};

// 筛选模式
typedef NS_ENUM(NSUInteger, VCMemFilterMode) {
    VCMemFilterModeLess = 0,
    VCMemFilterModeGreater = 1,
    VCMemFilterModeBetween = 2,
    VCMemFilterModeIncreased = 3,
    VCMemFilterModeDecreased = 4,
    VCMemFilterModeChanged = 5,
    VCMemFilterModeUnchanged = 6
};

// 搜索结果项
@interface VCMemResultItem : NSObject
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) VCMemDataType type;
@property (nonatomic, copy, nullable) NSString *valueStr;
@property (nonatomic, strong, nullable) NSNumber *prevValue;
@end

// 内存引擎
@interface VCMemEngine : NSObject

+ (instancetype)shared;

#pragma mark - 初始化

- (void)initialize;

@property (nonatomic, readonly) BOOL isReady;

#pragma mark - 配置

@property (nonatomic, assign) double floatTolerance;
@property (nonatomic, assign) uint64_t groupSearchRange;
@property (nonatomic, assign) BOOL groupAnchorMode;
@property (nonatomic, assign) NSUInteger resultLimit;

#pragma mark - 内存搜索

- (void)scanWithMode:(VCMemSearchMode)mode
              value:(NSString *)valueStr
               type:(VCMemDataType)type
         completion:(void (^)(NSUInteger count, NSString *msg))completion;

- (void)nextScanWithValue:(NSString *)valueStr
                     type:(VCMemDataType)type
               filterMode:(VCMemFilterMode)mode
               completion:(void (^)(NSUInteger count, NSString *msg))completion;

- (void)scanNearbyWithValue:(NSString *)valueStr
                       type:(VCMemDataType)type
                      range:(uint64_t)range
                 completion:(void (^)(NSUInteger count, NSString *msg))completion;

- (void)filterResultsWithMode:(VCMemFilterMode)mode
                        val1:(NSString *)v1
                        val2:(NSString *)v2
                        type:(VCMemDataType)type
                  completion:(void (^)(NSUInteger count, NSString *msg))completion;

#pragma mark - 结果管理

@property (nonatomic, readonly) NSUInteger resultCount;

- (nullable VCMemResultItem *)getResultAtIndex:(NSUInteger)index type:(VCMemDataType)type;
- (void)removeResultAtIndex:(NSUInteger)index;
- (void)clearResults;

- (void)batchModifyWithValue:(NSString *)value
                       limit:(NSInteger)limit
                        type:(VCMemDataType)type
                        mode:(int)mode;

#pragma mark - 内存读写

- (nullable NSString *)readAddress:(uint64_t)address type:(VCMemDataType)type;
- (BOOL)writeAddress:(uint64_t)address value:(NSString *)value type:(VCMemDataType)type;
- (nullable NSData *)readMemory:(uint64_t)address length:(size_t)length;
- (BOOL)writeMemory:(uint64_t)address data:(NSData *)data;

#pragma mark - 特征码搜索

- (void)scanSignature:(NSString *)signature
           rangeStart:(uint64_t)start
             rangeEnd:(uint64_t)end
           completion:(void (^)(NSArray<VCMemResultItem *> *results))completion;

#pragma mark - 快速模糊搜索

- (void)fastFuzzyInitWithCompletion:(void (^)(BOOL success, NSString *msg, NSUInteger addressCount))completion;
- (BOOL)hasFastFuzzySnapshot;
- (void)fastFuzzyFilterWithMode:(VCMemFilterMode)mode
                           type:(VCMemDataType)type
                     completion:(void (^)(NSUInteger count, NSString *msg))completion;
- (void)clearFastFuzzySnapshot;

#pragma mark - 快照

- (void)takeSnapshot;
- (void)clearSnapshot;
- (void)saveBaselineSnapshot;
- (void)clearBaselineSnapshot;
- (BOOL)hasBaselineSnapshot;

@end

NS_ASSUME_NONNULL_END
