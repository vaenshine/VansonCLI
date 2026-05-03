/**
 * VCOverlayWindow -- 高层级覆盖窗口
 * 承载悬浮按钮和面板, 非交互区域穿透
 */

#import <UIKit/UIKit.h>

extern NSNotificationName const VCOverlayWindowGeometryDidChangeNotification;

@interface VCOverlayWindow : UIWindow

+ (instancetype)shared;
- (void)showOverlay;
- (void)hideOverlay;
- (void)refreshGeometryIfNeeded;
- (void)beginInteractiveSession;
- (void)endInteractiveSession;

@end
