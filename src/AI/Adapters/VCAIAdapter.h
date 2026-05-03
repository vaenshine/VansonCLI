/**
 * VCAIAdapter -- AI API 适配器协议
 * 统一 4 种 API 协议的调用接口
 */

#import <Foundation/Foundation.h>

@class VCProviderConfig;

@protocol VCAIAdapter <NSObject>

/**
 * 发送消息到 AI API
 * @param messages   消息数组, 每个元素 {role, content, ...}
 * @param config     Provider 配置
 * @param streaming  是否流式响应
 * @param onChunk    流式文本回调
 * @param onToolCall 工具调用回调
 * @param onUsage    Token 用量回调
 * @param completion 完成回调 (fullResponse 包含完整 API 响应, error 为错误)
 */
- (void)sendMessages:(NSArray<NSDictionary *> *)messages
          withConfig:(VCProviderConfig *)config
           streaming:(BOOL)streaming
             onChunk:(void(^)(NSString *text))onChunk
          onToolCall:(void(^)(NSDictionary *toolCall))onToolCall
             onUsage:(void(^)(NSUInteger inputTokens, NSUInteger outputTokens))onUsage
          completion:(void(^)(NSDictionary *fullResponse, NSError *error))completion;

/**
 * 从 API 拉取可用模型列表
 */
- (void)fetchModelsWithConfig:(VCProviderConfig *)config
                   completion:(void(^)(NSArray<NSString *> *models, NSError *error))completion;

/**
 * 取消当前请求
 */
- (void)cancel;

@optional

/**
 * 发送带 tools 定义的消息
 */
- (void)sendMessages:(NSArray<NSDictionary *> *)messages
          withConfig:(VCProviderConfig *)config
               tools:(NSArray<NSDictionary *> *)tools
           streaming:(BOOL)streaming
             onChunk:(void(^)(NSString *text))onChunk
          onToolCall:(void(^)(NSDictionary *toolCall))onToolCall
             onUsage:(void(^)(NSUInteger inputTokens, NSUInteger outputTokens))onUsage
          completion:(void(^)(NSDictionary *fullResponse, NSError *error))completion;

@end
