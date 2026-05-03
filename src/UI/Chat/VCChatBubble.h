/**
 * VCChatBubble -- Message bubble cell
 * User: right-aligned, AI: left-aligned full-width
 */

#import <UIKit/UIKit.h>

@class VCMessage;
@class VCToolCall;

@interface VCChatBubble : UITableViewCell

- (void)configureWithMessage:(VCMessage *)message;
- (void)configureWithRole:(NSString *)role content:(NSString *)content references:(NSArray<NSDictionary *> *)references toolCalls:(NSArray<VCToolCall *> *)toolCalls;

@end
