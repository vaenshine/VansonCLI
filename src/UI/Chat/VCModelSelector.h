/**
 * VCModelSelector -- Inline provider/model drawer
 */

#import <UIKit/UIKit.h>

typedef void(^VCModelSelectorCompletion)(NSString *providerID, NSString *model);

@interface VCModelSelector : NSObject

+ (void)showFromViewController:(UIViewController *)vc completion:(VCModelSelectorCompletion)completion;

@end
