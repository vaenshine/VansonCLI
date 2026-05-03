/**
 * VCPatchManager -- 统一管理器
 * Slide-12: Patches Engine
 * 管理 Patches / Values / Hooks / Rules 的 CRUD + 持久化
 */

#import <Foundation/Foundation.h>

@class VCPatchItem;
@class VCValueItem;
@class VCHookItem;
@class VCNetRule;

extern NSNotificationName const VCPatchManagerDidUpdateNotification;

@interface VCPatchManager : NSObject

+ (instancetype)shared;

// CRUD
- (void)addPatch:(VCPatchItem *)item;
- (void)addValue:(VCValueItem *)item;
- (void)addHook:(VCHookItem *)item;
- (void)addRule:(VCNetRule *)item;
- (void)removeItemByID:(NSString *)itemID;
- (void)updateItem:(id)item;

// 查询
- (NSArray<VCPatchItem *> *)allPatches;
- (NSArray<VCValueItem *> *)allValues;
- (NSArray<VCHookItem *> *)allHooks;
- (NSArray<VCNetRule *> *)allRules;

// 执行控制
- (void)enableItem:(NSString *)itemID;
- (void)disableItem:(NSString *)itemID;
- (void)toggleItem:(NSString *)itemID;

// 安全模式
- (void)disableAllForSafeMode;
- (void)clearSafeModeFlags;

// 持久化
- (void)save;
- (void)load;

// 统计
- (NSUInteger)enabledCount;
- (NSUInteger)totalCount;
- (NSUInteger)aiCreatedCount;

@end
