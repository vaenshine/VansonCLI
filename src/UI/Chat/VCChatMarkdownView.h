/**
 * VCChatMarkdownView -- Lightweight markdown/code renderer for chat bubbles
 */

#import <UIKit/UIKit.h>

@interface VCChatMarkdownView : UIView

- (void)configureWithMarkdown:(NSString *)markdown role:(NSString *)role;

@end
