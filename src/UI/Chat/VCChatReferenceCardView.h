/**
 * VCChatReferenceCardView -- Structured reference / artifact card
 */

#import <UIKit/UIKit.h>

@interface VCChatReferenceCardView : UIView

- (void)configureWithKind:(NSString *)kind
                    title:(NSString *)title
                  payload:(NSDictionary *)payload
                     role:(NSString *)role;

@end
