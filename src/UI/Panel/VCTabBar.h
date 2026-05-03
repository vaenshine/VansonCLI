/**
 * VCTabBar -- Tab 栏
 * 水平滚动, 选中指示线
 */

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, VCTabBarLayoutStyle) {
    VCTabBarLayoutStyleHorizontal = 0,
    VCTabBarLayoutStyleVertical,
    VCTabBarLayoutStyleCompactVertical,
};

@protocol VCTabBarDelegate <NSObject>
- (void)tabBar:(id)tabBar didSelectIndex:(NSUInteger)index;
@end

@interface VCTabBar : UIView

@property (nonatomic, weak) id<VCTabBarDelegate> delegate;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, assign) VCTabBarLayoutStyle layoutStyle;

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles;

@end
