/**
 * VCTokenTracker -- Token 追踪
 * 累计 input/output tokens, 根据模型名自动设置 maxTokens
 */

#import <Foundation/Foundation.h>

@interface VCTokenTracker : NSObject

+ (instancetype)shared;

@property (nonatomic, assign) NSUInteger inputTokens;
@property (nonatomic, assign) NSUInteger outputTokens;
@property (nonatomic, assign) NSUInteger contextTokens;
@property (nonatomic, assign) NSUInteger maxTokens;
@property (nonatomic, readonly) NSUInteger usagePercent;

- (void)updateForModel:(NSString *)modelName;
- (BOOL)shouldCompactWithMessageCount:(NSUInteger)messageCount;
- (void)addUsage:(NSUInteger)input output:(NSUInteger)output;
- (void)reset;

@end
