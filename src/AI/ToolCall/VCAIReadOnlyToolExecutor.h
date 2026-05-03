/**
 * VCAIReadOnlyToolExecutor -- safe auto-executed analysis tools for AI
 */

#import <Foundation/Foundation.h>

@class VCToolCall;

@interface VCAIReadOnlyToolExecutor : NSObject

+ (BOOL)isReadOnlyToolCall:(VCToolCall *)toolCall;
+ (NSArray<VCToolCall *> *)readOnlyToolCallsFromArray:(NSArray<VCToolCall *> *)toolCalls;
+ (NSArray<VCToolCall *> *)manualToolCallsFromArray:(NSArray<VCToolCall *> *)toolCalls;
+ (NSArray<NSDictionary *> *)executeToolCalls:(NSArray<VCToolCall *> *)toolCalls;
+ (NSString *)systemMessageForToolResults:(NSArray<NSDictionary *> *)results;
+ (NSArray<NSDictionary *> *)artifactReferencesFromToolResults:(NSArray<NSDictionary *> *)results;

@end
