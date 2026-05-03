/**
 * VCMemoryBrowserTab -- native memory browser workspace
 */

#import <UIKit/UIKit.h>
#import "../Panel/VCPanel.h"

extern NSNotificationName const VCMemoryBrowserRequestOpenAddressNotification;
extern NSString *const VCMemoryBrowserOpenAddressKey;

@interface VCMemoryBrowserTab : UIViewController <VCPanelLayoutUpdatable>

- (void)openAddressString:(NSString *)addressString;

@end
