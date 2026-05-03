/**
 * VCChatStatusBannerView -- Compact status banner for chat messages
 */

#import <UIKit/UIKit.h>

@interface VCChatStatusBannerView : UIView

- (void)configureWithTitle:(NSString *)title
                   content:(NSString *)content
                      tone:(NSString *)tone;

@end
