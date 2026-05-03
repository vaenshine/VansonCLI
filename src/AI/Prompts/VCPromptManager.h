/**
 * VCPromptManager -- Prompt 管理
 * System prompt builder with compile-time string protection
 */

#import <Foundation/Foundation.h>

@interface VCPromptManager : NSObject

+ (instancetype)shared;

/**
 * 组装完整 system prompt
 * 顺序: identity -> capabilities -> contextStrategy -> responseStyle
 *       -> selfProtect -> rules -> systemInfo -> goal
 */
- (NSString *)buildSystemPrompt;

@end
