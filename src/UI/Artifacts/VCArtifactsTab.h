/**
 * VCArtifactsTab -- Browse saved traces, Mermaid diagrams, and memory snapshots
 */

#import <UIKit/UIKit.h>

extern NSNotificationName const VCArtifactsRequestOpenModeNotification;
extern NSString *const VCArtifactsOpenModeKey;
extern NSString *const VCArtifactsOpenModeDiagnosticsValue;

@interface VCArtifactsTab : UIViewController

- (void)openArtifactsModeNamed:(NSString *)modeName;

@end
