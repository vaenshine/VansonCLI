/**
 * VCCodeTab -- Code Editor Tab
 * Slide-13: File tree + editor + snippets
 */

#import <UIKit/UIKit.h>

extern NSNotificationName const VCCodeTabRequestOpenFileNotification;
extern NSString *const VCCodeTabOpenFilePathKey;
extern NSString *const VCCodeTabOpenFileLineKey;

@interface VCCodeTab : UIViewController

- (void)openFileAtPath:(NSString *)path line:(NSUInteger)line;

@end
