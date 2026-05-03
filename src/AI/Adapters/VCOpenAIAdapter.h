/**
 * VCOpenAIAdapter -- OpenAI Compatible + Responses API 适配器
 * 支持 /v1/chat/completions 和 /v1/responses
 */

#import <Foundation/Foundation.h>
#import "VCAIAdapter.h"

@interface VCOpenAIAdapter : NSObject <VCAIAdapter, NSURLSessionDataDelegate>

- (void)sendMessages:(NSArray<NSDictionary *> *)messages
          withConfig:(VCProviderConfig *)config
           streaming:(BOOL)streaming
             onChunk:(void(^)(NSString *text))onChunk
          onToolCall:(void(^)(NSDictionary *toolCall))onToolCall
             onUsage:(void(^)(NSUInteger inputTokens, NSUInteger outputTokens))onUsage
          completion:(void(^)(NSDictionary *fullResponse, NSError *error))completion;

- (void)fetchModelsWithConfig:(VCProviderConfig *)config
                   completion:(void(^)(NSArray<NSString *> *models, NSError *error))completion;

- (void)cancel;

@end
