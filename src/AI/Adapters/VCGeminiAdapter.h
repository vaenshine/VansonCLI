/**
 * VCGeminiAdapter -- Google Gemini API 适配器
 * NDJSON streaming (not standard SSE)
 */

#import <Foundation/Foundation.h>
#import "VCAIAdapter.h"

@interface VCGeminiAdapter : NSObject <VCAIAdapter, NSURLSessionDataDelegate>

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
