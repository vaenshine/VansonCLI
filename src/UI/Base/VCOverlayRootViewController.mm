/**
 * VCOverlayRootViewController -- scene/orientation bridge for overlay windows
 */

#import "VCOverlayRootViewController.h"

static UIViewController *VCTopVisibleController(UIViewController *controller) {
    UIViewController *current = controller;
    while (current) {
        if (current.presentedViewController &&
            !current.presentedViewController.isBeingDismissed) {
            current = current.presentedViewController;
            continue;
        }
        if ([current isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)current;
            current = nav.visibleViewController ?: nav.topViewController ?: current;
            if (current == nav) break;
            continue;
        }
        if ([current isKindOfClass:[UITabBarController class]]) {
            UITabBarController *tab = (UITabBarController *)current;
            current = tab.selectedViewController ?: current;
            if (current == tab) break;
            continue;
        }
        break;
    }
    return current ?: controller;
}

static BOOL VCOverlayIsForegroundScene(UIScene *scene) {
    return scene.activationState == UISceneActivationStateForegroundActive ||
           scene.activationState == UISceneActivationStateForegroundInactive;
}

static BOOL VCOverlayIsHostWindow(UIWindow *window) {
    if (![window isKindOfClass:[UIWindow class]]) return NO;
    if (window.hidden || window.alpha < 0.01) return NO;
    UIViewController *root = window.rootViewController;
    return ![root isKindOfClass:[VCOverlayRootViewController class]];
}

static UIInterfaceOrientationMask VCOverlayMaskForInterfaceOrientation(UIInterfaceOrientation orientation) {
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            return UIInterfaceOrientationMaskPortrait;
        case UIInterfaceOrientationPortraitUpsideDown:
            return UIInterfaceOrientationMaskPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft:
            return UIInterfaceOrientationMaskLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:
            return UIInterfaceOrientationMaskLandscapeRight;
        case UIInterfaceOrientationUnknown:
        default:
            return UIInterfaceOrientationMaskAllButUpsideDown;
    }
}

@implementation VCOverlayRootViewController

+ (NSArray<UIWindowScene *> *)_candidateScenes {
    NSMutableArray<UIWindowScene *> *scenes = [NSMutableArray new];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (VCOverlayIsForegroundScene(scene)) {
                [scenes addObject:(UIWindowScene *)scene];
            }
        }
        if (scenes.count == 0) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    [scenes addObject:(UIWindowScene *)scene];
                }
            }
        }
    }
    return scenes;
}

+ (UIWindow *)currentHostWindow {
    UIWindow *fallbackWindow = nil;

    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [self _candidateScenes]) {
            for (UIWindow *window in [scene.windows reverseObjectEnumerator]) {
                if (!VCOverlayIsHostWindow(window)) continue;
                if (!fallbackWindow) fallbackWindow = window;
                if (window.isKeyWindow) return window;
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in [UIApplication sharedApplication].windows.reverseObjectEnumerator) {
        if (!VCOverlayIsHostWindow(window)) continue;
        if (!fallbackWindow) fallbackWindow = window;
        if (window.isKeyWindow) return window;
    }
#pragma clang diagnostic pop

    return fallbackWindow;
}

+ (UIViewController *)currentVisibleHostViewController {
    UIWindow *window = [self currentHostWindow];
    UIViewController *root = window.rootViewController;
    return VCTopVisibleController(root);
}

+ (CGRect)currentHostBounds {
    UIWindow *window = [self currentHostWindow];
    if (window) return window.bounds;

    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = [self _candidateScenes].firstObject;
        if (scene) return scene.coordinateSpace.bounds;
    }
    return [UIScreen mainScreen].bounds;
}

+ (UIInterfaceOrientation)currentHostInterfaceOrientation {
    UIWindow *window = [self currentHostWindow];
    if (@available(iOS 13.0, *)) {
        UIInterfaceOrientation sceneOrientation = window.windowScene.interfaceOrientation;
        if (sceneOrientation != UIInterfaceOrientationUnknown) return sceneOrientation;

        for (UIWindowScene *scene in [self _candidateScenes]) {
            if (scene.interfaceOrientation != UIInterfaceOrientationUnknown) {
                return scene.interfaceOrientation;
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIInterfaceOrientation statusOrientation = UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
    if (statusOrientation != UIInterfaceOrientationUnknown) return statusOrientation;

    CGRect bounds = [self currentHostBounds];
    if (CGRectGetWidth(bounds) > CGRectGetHeight(bounds)) {
        return UIInterfaceOrientationLandscapeRight;
    }
    return UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIInterfaceOrientation orientation = [VCOverlayRootViewController currentHostInterfaceOrientation];
    return VCOverlayMaskForInterfaceOrientation(orientation);
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [VCOverlayRootViewController currentHostInterfaceOrientation];
}

@end
