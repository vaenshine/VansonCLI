/**
 * VCToolCallBlock -- Tool Call action card (collapsible)
 */

#import <UIKit/UIKit.h>

@class VCToolCall;

NS_ASSUME_NONNULL_BEGIN

@interface VCToolCallBlock : UIView

- (instancetype)initWithToolCall:(VCToolCall * _Nonnull)toolCall;
+ (BOOL)executeToolCall:(VCToolCall *)toolCall resultMessage:(NSString * _Nullable * _Nullable)message;

@end

NS_ASSUME_NONNULL_END
