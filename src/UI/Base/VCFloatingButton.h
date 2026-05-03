/**
 * VCFloatingButton -- 悬浮按钮
 * 圆形 48pt, 可拖拽, 记忆位置, 点击展开面板
 */

#import <UIKit/UIKit.h>

@interface VCFloatingButton : UIView

+ (void)show;
+ (void)hide;
+ (instancetype)shared;

@end
