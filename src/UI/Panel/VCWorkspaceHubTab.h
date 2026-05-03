/**
 * VCWorkspaceHubTab -- secondary workspace launcher for low-frequency tools
 */

#import <UIKit/UIKit.h>
#import "VCPanel.h"

extern NSNotificationName const VCWorkspaceHubRequestOpenSectionNotification;
extern NSString *const VCWorkspaceHubSectionKey;

@interface VCWorkspaceHubTab : UIViewController <VCPanelLayoutUpdatable>

@end
