/**
 * VCTouchOverlay.mm -- Touch-to-select overlay implementation
 * Slide-4: UI Inspector Engine
 */

#import "VCTouchOverlay.h"
#import "VCUIInspector.h"
#import "../UI/Base/VCOverlayRootViewController.h"
#import "../../VansonCLI.h"

// ═══════════════════════════════════════════════════════════════
// VCPickerView -- Transparent full-screen touch receiver
// ═══════════════════════════════════════════════════════════════

@interface VCTouchOverlay (PickerInternals)
- (void)_finishPickingWithView:(UIView *)view cancelled:(BOOL)cancelled;
@end

@interface VCPickerView : UIView
@property (nonatomic, weak) VCTouchOverlay *overlay;
@end

@implementation VCPickerView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Always capture touches when picking
    return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint screenPoint = [touch locationInView:nil];

    UIView *deepest = [self _findDeepestViewAtPoint:screenPoint];
    if (deepest && self.overlay) {
        [self.overlay _finishPickingWithView:deepest cancelled:NO];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.overlay _finishPickingWithView:nil cancelled:YES];
}

- (UIView *)_findDeepestViewAtPoint:(CGPoint)screenPoint {
    UIView *result = nil;
    UIWindow *hostWindow = [VCOverlayRootViewController currentHostWindow];
    NSArray<UIWindow *> *windows = hostWindow.windowScene.windows ?: @[];

    for (UIWindow *win in [windows reverseObjectEnumerator]) {
        if (win.isHidden || win.alpha < 0.01) continue;
        if ([win.rootViewController isKindOfClass:[VCOverlayRootViewController class]]) continue;

        CGPoint winPoint = [win convertPoint:screenPoint fromWindow:nil];
        UIView *hit = [win hitTest:winPoint withEvent:nil];
        if (hit && hit != win) {
            result = hit;
            break;
        }
    }
    return result;
}

@end

// ═══════════════════════════════════════════════════════════════
// VCPickerWindow
// ═══════════════════════════════════════════════════════════════

@interface VCPickerWindow : UIWindow
@end

@implementation VCPickerWindow
@end

// ═══════════════════════════════════════════════════════════════
// VCTouchOverlay
// ═══════════════════════════════════════════════════════════════

@interface VCTouchOverlay ()
@property (nonatomic, strong) VCPickerWindow *overlayWindow;
@property (nonatomic, strong) VCPickerView *pickerView;
@property (nonatomic, assign) BOOL isPicking;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@property (nonatomic, strong) UIButton *cancelButton;
- (void)_finishPickingWithView:(UIView *)view cancelled:(BOOL)cancelled;
- (UIWindow *)_currentKeyWindow;
@end

@implementation VCTouchOverlay

+ (instancetype)shared {
    static VCTouchOverlay *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[VCTouchOverlay alloc] init]; });
    return inst;
}

- (void)startPicking {
    if (_isPicking) return;
    _isPicking = YES;

    vc_dispatch_main(^{
        self.previousKeyWindow = [VCOverlayRootViewController currentHostWindow];
        CGRect screenBounds = [VCOverlayRootViewController currentHostBounds];

        self.overlayWindow = [[VCPickerWindow alloc] initWithFrame:screenBounds];
        self.overlayWindow.windowLevel = CGFLOAT_MAX - 1;
        self.overlayWindow.backgroundColor = [UIColor clearColor];
        if (@available(iOS 13.0, *)) {
            UIWindow *hostWindow = [VCOverlayRootViewController currentHostWindow];
            if (hostWindow.windowScene) {
                self.overlayWindow.windowScene = hostWindow.windowScene;
            }
        }
        self.overlayWindow.rootViewController = [VCOverlayRootViewController new];
        self.overlayWindow.rootViewController.view.backgroundColor = [UIColor clearColor];

        self.pickerView = [[VCPickerView alloc] initWithFrame:screenBounds];
        self.pickerView.backgroundColor = UIColorFromHexA(0x000000, 0.15);
        self.pickerView.overlay = self;
        self.pickerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.overlayWindow.rootViewController.view addSubview:self.pickerView];

        self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.cancelButton setTitle:@"Cancel Pick" forState:UIControlStateNormal];
        [self.cancelButton setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
        self.cancelButton.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.94];
        self.cancelButton.layer.cornerRadius = 12.0;
        self.cancelButton.layer.borderWidth = 1.0;
        self.cancelButton.layer.borderColor = kVCBorderStrong.CGColor;
        self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        self.cancelButton.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
        [self.cancelButton addTarget:self action:@selector(stopPicking) forControlEvents:UIControlEventTouchUpInside];
        self.cancelButton.frame = CGRectMake(screenBounds.size.width - 116.0, 48.0, 104.0, 32.0);
        self.cancelButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
        [self.overlayWindow.rootViewController.view addSubview:self.cancelButton];

        self.overlayWindow.hidden = NO;
        [self.overlayWindow makeKeyAndVisible];

        VCLog(@"Touch picker started");
    });
}

- (void)stopPicking {
    [self _finishPickingWithView:nil cancelled:YES];
}

- (void)_finishPickingWithView:(UIView *)view cancelled:(BOOL)cancelled {
    if (!_isPicking) return;
    _isPicking = NO;

    vc_dispatch_main(^{
        [self.pickerView removeFromSuperview];
        self.pickerView = nil;
        [self.cancelButton removeFromSuperview];
        self.cancelButton = nil;

        self.overlayWindow.hidden = YES;
        self.overlayWindow = nil;

        if (self.previousKeyWindow) {
            [self.previousKeyWindow makeKeyAndVisible];
        }
        self.previousKeyWindow = nil;

        VCLog(@"Touch picker stopped");

        if (cancelled) {
            [[VCUIInspector shared] clearHighlights];
            if ([self.delegate respondsToSelector:@selector(touchOverlayDidCancel:)]) {
                [self.delegate touchOverlayDidCancel:self];
            }
            return;
        }

        if (view && [self.delegate respondsToSelector:@selector(touchOverlay:didSelectView:)]) {
            [self.delegate touchOverlay:self didSelectView:view];
        }
    });
}

- (UIWindow *)_currentKeyWindow {
    for (UIWindow *window in [[UIApplication sharedApplication].windows reverseObjectEnumerator]) {
        if (window.isKeyWindow) return window;
    }
    return nil;
}

@end
