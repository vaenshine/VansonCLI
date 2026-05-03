/**
 * VCChatMessageBlockView -- Resolves a single chat block into a UIKit view
 */

#import <UIKit/UIKit.h>

@class VCToolCall;

@interface VCChatMessageBlockView : UIView

- (void)configureWithBlock:(NSDictionary *)block
                      role:(NSString *)role
            toolCallLookup:(NSDictionary<NSString *, VCToolCall *> *)toolCallLookup;

@end
