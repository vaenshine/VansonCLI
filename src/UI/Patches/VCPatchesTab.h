/**
 * VCPatchesTab -- Patches Tab 主容器
 * Slide-12: Patches Engine UI
 */

#import <UIKit/UIKit.h>

extern NSNotificationName const VCPatchesRequestOpenEditorNotification;
extern NSString *const VCPatchesOpenEditorSegmentKey;
extern NSString *const VCPatchesOpenEditorItemKey;
extern NSString *const VCPatchesOpenEditorCreatesKey;

@interface VCPatchesTab : UIViewController

- (void)openEditorForDraftItem:(id)item segmentIndex:(NSInteger)segment createsItem:(BOOL)createsItem;

@end
