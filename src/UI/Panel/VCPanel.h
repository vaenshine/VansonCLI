/**
 * VCPanel -- Floating window panel
 * Centered floating bgView, S/M/L transform scaling,
 * drag to move, focus/unfocus with alpha transition
 */

#import <UIKit/UIKit.h>

@class VCTabBar;

typedef NS_ENUM(NSInteger, VCPanelLayoutMode) {
    VCPanelLayoutModePortrait = 0,
    VCPanelLayoutModeLandscape,
};

typedef NS_ENUM(NSInteger, VCPanelShellLayoutTier) {
    VCPanelShellLayoutTierPortrait = 0,
    VCPanelShellLayoutTierCompactLandscape,
    VCPanelShellLayoutTierLandscape,
};

@protocol VCPanelLayoutUpdatable <NSObject>
@optional
- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets;
@end

@interface VCPanel : UIView

@property (nonatomic, strong, readonly) VCTabBar *tabBar;
@property (nonatomic, strong, readonly) UIView *bodyContainer;
@property (nonatomic, assign, readonly) VCPanelLayoutMode layoutMode;
@property (nonatomic, assign, readonly) VCPanelShellLayoutTier shellLayoutTier;

- (void)showAnimated;
- (void)hideAnimated;
- (BOOL)isVisible;

@end
