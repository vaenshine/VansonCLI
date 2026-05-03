/**
 * VCContextCompactor -- 上下文压缩
 * 长会话上下文压缩工具
 */

#import <Foundation/Foundation.h>

@class VCMessage;
@class VCProviderConfig;

@interface VCContextCompactor : NSObject

+ (void)compactMessages:(NSMutableArray<VCMessage *> *)messages
           withProvider:(VCProviderConfig *)provider
             completion:(void(^)(BOOL success, NSDictionary *artifact))completion;

+ (BOOL)isTokenLimitError:(NSString *)errorMessage;

+ (NSString *)messagesToSummaryText:(NSArray<VCMessage *> *)messages
                          maxLength:(NSUInteger)maxLen;

+ (NSString *)renderArtifact:(NSDictionary *)artifact;

@end
