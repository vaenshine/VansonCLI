/**
 * VCOverlayWindow -- scene-aware overlay window
 * Keeps geometry/orientation aligned with the host app and only
 * becomes key while VansonCLI needs interactive focus.
 */

#import "VCOverlayWindow.h"
#import "VCOverlayRootViewController.h"
#import "../../../VansonCLI.h"

NSNotificationName const VCOverlayWindowGeometryDidChangeNotification = @"VCOverlayWindowGeometryDidChangeNotification";

@interface VCOverlayWindow ()
@property (nonatomic, weak) UIWindow *previousKeyHostWindow;
@property (nonatomic, assign) NSInteger interactionDepth;
@property (nonatomic, assign) CGRect lastPublishedBounds;
@end

@implementation VCOverlayWindow

+ (instancetype)shared {
    static VCOverlayWindow *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[VCOverlayWindow alloc] initWithFrame:[VCOverlayRootViewController currentHostBounds]];
        inst.windowLevel = UIWindowLevelAlert + 100;
        inst.backgroundColor = [UIColor clearColor];
        inst.hidden = YES;
        inst.rootViewController = [VCOverlayRootViewController new];
        inst.rootViewController.view.backgroundColor = [UIColor clearColor];
        inst.rootViewController.view.userInteractionEnabled = YES;
        [inst _installObservers];
        [inst refreshGeometryIfNeeded];
    });
    return inst;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_installObservers {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(refreshGeometryIfNeeded) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(refreshGeometryIfNeeded) name:UIDeviceOrientationDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(_editingResponderDidBegin:) name:UITextFieldTextDidBeginEditingNotification object:nil];
    [center addObserver:self selector:@selector(_editingResponderDidBegin:) name:UITextViewTextDidBeginEditingNotification object:nil];
    if (@available(iOS 13.0, *)) {
        [center addObserver:self selector:@selector(refreshGeometryIfNeeded) name:UISceneDidActivateNotification object:nil];
        [center addObserver:self selector:@selector(refreshGeometryIfNeeded) name:UISceneWillEnterForegroundNotification object:nil];
    }
}

- (void)_editingResponderDidBegin:(NSNotification *)notification {
    id object = notification.object;
    if (![object isKindOfClass:[UIView class]]) return;

    UIView *editingView = (UIView *)object;
    if (editingView.window != self) return;

    VCEnsureKeyboardDismissAccessory((UIResponder *)editingView, YES);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self _publishGeometryIfNeeded];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01 || !self.userInteractionEnabled) {
        return nil;
    }

    UIView *hitView = [super hitTest:point withEvent:event];
    if (!hitView) {
        return nil;
    }

    UIView *rootView = self.rootViewController.view;
    if (!rootView) {
        return hitView;
    }

    // Let the host app receive touches when the overlay background itself was hit.
    if (hitView == rootView) {
        return nil;
    }

    return hitView;
}

- (void)_publishGeometryIfNeeded {
    if (CGRectEqualToRect(self.lastPublishedBounds, self.bounds)) return;
    self.lastPublishedBounds = self.bounds;
    [[NSNotificationCenter defaultCenter] postNotificationName:VCOverlayWindowGeometryDidChangeNotification
                                                        object:self
                                                      userInfo:@{ @"bounds": [NSValue valueWithCGRect:self.bounds] }];
}

- (void)refreshGeometryIfNeeded {
    CGRect targetBounds = [VCOverlayRootViewController currentHostBounds];
    UIWindowScene *targetScene = nil;

    if (@available(iOS 13.0, *)) {
        UIWindow *hostWindow = [VCOverlayRootViewController currentHostWindow];
        targetScene = hostWindow.windowScene;
        if (targetScene && self.windowScene != targetScene) {
            self.windowScene = targetScene;
        }
        if (targetScene && !CGRectIsEmpty(targetScene.coordinateSpace.bounds)) {
            targetBounds = targetScene.coordinateSpace.bounds;
        }
    }

    CGRect normalizedFrame = CGRectMake(0, 0, CGRectGetWidth(targetBounds), CGRectGetHeight(targetBounds));
    if (!CGRectEqualToRect(self.frame, normalizedFrame)) {
        self.frame = normalizedFrame;
    }
    if (!CGRectEqualToRect(self.bounds, normalizedFrame)) {
        self.bounds = normalizedFrame;
    }
    self.rootViewController.view.frame = self.bounds;
    [self _publishGeometryIfNeeded];
}

- (void)showOverlay {
    [self refreshGeometryIfNeeded];
    if (!self.hidden) return;
    self.hidden = NO;
}

- (void)hideOverlay {
    self.hidden = YES;
}

- (void)beginInteractiveSession {
    [self showOverlay];
    [self refreshGeometryIfNeeded];
    if (self.interactionDepth == 0) {
        self.previousKeyHostWindow = [VCOverlayRootViewController currentHostWindow];
    }
    self.interactionDepth += 1;
    [self makeKeyAndVisible];
}

- (void)endInteractiveSession {
    if (self.interactionDepth <= 0) return;
    self.interactionDepth -= 1;
    if (self.interactionDepth > 0) return;

    UIWindow *restoreWindow = self.previousKeyHostWindow;
    self.previousKeyHostWindow = nil;
    self.hidden = NO;

    if (restoreWindow && restoreWindow != self && !restoreWindow.hidden) {
        [restoreWindow makeKeyWindow];
        return;
    }

    UIWindow *hostWindow = [VCOverlayRootViewController currentHostWindow];
    if (hostWindow && hostWindow != self) {
        [hostWindow makeKeyWindow];
    }
}

@end
