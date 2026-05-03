/**
 * VCProviderManager -- Provider CRUD + 持久化
 * API Key 用 VCCrypto 加密后存储
 */

#import <Foundation/Foundation.h>
#import "VCProviderConfig.h"

extern NSNotificationName const VCProviderManagerDidChangeNotification;

@interface VCProviderManager : NSObject

+ (instancetype)shared;

// CRUD
- (void)addProvider:(VCProviderConfig *)provider;
- (void)updateProvider:(VCProviderConfig *)provider;
- (void)removeProvider:(NSString *)providerID;
- (VCProviderConfig *)providerForID:(NSString *)providerID;

// 列表
- (NSArray<VCProviderConfig *> *)allProviders;
- (VCProviderConfig *)activeProvider;
- (NSString *)effectiveSelectedModelForProvider:(VCProviderConfig *)provider;
- (void)setActiveProviderID:(NSString *)providerID;

// 排序
- (void)moveProvider:(NSString *)providerID toIndex:(NSInteger)index;

// 模型列表
- (void)fetchModelsForProvider:(NSString *)providerID
                    completion:(void(^)(NSArray<NSString *> *models, NSError *error))completion;

// 持久化
- (void)save;
- (void)load;

@end
