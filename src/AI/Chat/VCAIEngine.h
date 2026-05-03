/**
 * VCAIEngine -- AI 对话引擎 (统一入口)
 * 整合 Provider/Adapter/Session/Token/ToolCall/Prompt
 */

#import <Foundation/Foundation.h>

@class VCMessage;
@class VCToolCall;

@interface VCAIEngine : NSObject

+ (instancetype)shared;

// Core API
- (void)sendMessage:(NSString *)text
        withContext:(NSDictionary *)context
          streaming:(BOOL)streaming
            onChunk:(void(^)(NSString *text))onChunk
         onToolCall:(void(^)(VCToolCall *toolCall))onToolCall
         completion:(void(^)(VCMessage *message, NSError *error))completion;

// Provider/Model switching
- (void)switchProvider:(NSString *)providerID model:(NSString *)model;

// Message operations
- (void)editAndResend:(NSString *)messageID newText:(NSString *)text;
- (void)deleteMessage:(NSString *)messageID;
- (void)resendMessage:(NSString *)messageID;

// Stop generation
- (void)stopGeneration;

// State
@property (nonatomic, readonly) BOOL isGenerating;

@end
