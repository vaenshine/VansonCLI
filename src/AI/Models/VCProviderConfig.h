/**
 * VCProviderConfig -- Provider 配置模型
 * API Provider 的配置信息, 支持 NSCoding 持久化
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, VCAPIProtocol) {
    VCAPIProtocolOpenAI = 0,        // /v1/chat/completions
    VCAPIProtocolOpenAIResponses,   // /v1/responses
    VCAPIProtocolAnthropic,         // /v1/messages
    VCAPIProtocolGemini,            // /v1beta/models/{model}:streamGenerateContent
};

@interface VCProviderConfig : NSObject <NSCoding, NSCopying>

@property (nonatomic, copy) NSString *providerID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *endpoint;
@property (nonatomic, copy) NSString *apiVersion;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, assign) VCAPIProtocol protocol;
@property (nonatomic, copy) NSString *rolePreset;
@property (nonatomic, copy) NSArray<NSString *> *models;
@property (nonatomic, copy) NSString *selectedModel;
@property (nonatomic, assign) NSInteger maxTokens;
@property (nonatomic, copy) NSString *reasoningEffort;
@property (nonatomic, assign) NSInteger sortOrder;
@property (nonatomic, assign) BOOL isBuiltin;

+ (NSString *)normalizedAPIKeyString:(id)value;
+ (NSString *)portableFileExtension;
+ (instancetype)configWithName:(NSString *)name
                      endpoint:(NSString *)endpoint
                      protocol:(VCAPIProtocol)protocol
                        models:(NSArray<NSString *> *)models;

- (NSDictionary *)toDictionary;
- (NSDictionary *)portableExportDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
+ (instancetype)fromPortableImportDictionary:(NSDictionary *)dict;

@end
