/**
 * VCOverlayRootViewController -- Orientation-forwarding overlay host
 * Keeps overlay windows aligned with the current host scene/window
 * without becoming the source of interface orientation decisions.
 */

#import <UIKit/UIKit.h>

@interface VCOverlayRootViewController : UIViewController

+ (UIWindow *)currentHostWindow;
+ (UIViewController *)currentVisibleHostViewController;
+ (CGRect)currentHostBounds;
+ (UIInterfaceOrientation)currentHostInterfaceOrientation;

@end
