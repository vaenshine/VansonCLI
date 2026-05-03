/**
 * VCFloatingButton -- 悬浮按钮
 * 圆形 48pt, 可拖拽, 记忆位置, 点击展开/收起面板
 */

#import "VCFloatingButton.h"
#import "VCBrandIcon.h"
#import "VCOverlayWindow.h"
#import "VCOverlayRootViewController.h"
#import "../Panel/VCPanel.h"
#import "../../../VansonCLI.h"

static const CGFloat kButtonSize = 54.0;
static NSString *const kPositionXKey = @"com.vanson.cli.btn.x";
static NSString *const kPositionYKey = @"com.vanson.cli.btn.y";
static NSString *const kPositionSideKey = @"com.vanson.cli.btn.anchor.side";
static NSString *const kPositionVerticalRatioKey = @"com.vanson.cli.btn.anchor.ratio";

@interface VCFloatingButton ()
@property (nonatomic, strong) VCPanel *panel;
@property (nonatomic, assign) CGPoint dragStart;
@property (nonatomic, assign) CGPoint originCenter;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, strong) UIControl *quickMenuBackdrop;
@property (nonatomic, strong) UIView *quickMenuCard;
@end

@implementation VCFloatingButton

+ (instancetype)shared {
    static VCFloatingButton *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[VCFloatingButton alloc] initWithFrame:CGRectMake(0, 0, kButtonSize, kButtonSize)];
    });
    return inst;
}

+ (void)show {
    VCOverlayWindow *overlay = [VCOverlayWindow shared];
    [overlay showOverlay];

    VCFloatingButton *btn = [self shared];
    if (!btn.superview) {
        [overlay.rootViewController.view addSubview:btn];
    }
    btn.hidden = NO;
    [btn _applyStoredAnchorToCurrentSuperviewAnimated:NO persistIfNeeded:YES];

    VCLog(@"[UI] Floating button shown");
}

+ (void)hide {
    VCFloatingButton *button = [self shared];
    [button _hideQuickMenu];
    button.hidden = YES;
    if (!button.panel.isVisible) {
        [[VCOverlayWindow shared] hideOverlay];
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self _setup];
    }
    return self;
}

- (void)_setup {
    self.backgroundColor = [UIColor clearColor];
    self.layer.cornerRadius = kButtonSize / 2;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeZero;
    self.layer.shadowRadius = 12;
    self.layer.shadowOpacity = 0.35;

    UIImage *brandIcon = VCBrandIconImage();
    self.layer.borderWidth = brandIcon ? 1.5 : 0.0;
    self.layer.borderColor = brandIcon ? [UIColor colorWithRed:0.0 green:0.86 blue:1.0 alpha:0.92].CGColor : UIColor.clearColor.CGColor;

    UIView *outerRing = [[UIView alloc] initWithFrame:CGRectZero];
    outerRing.translatesAutoresizingMaskIntoConstraints = NO;
    outerRing.backgroundColor = brandIcon ? [UIColor clearColor] : [kVCBgSecondary colorWithAlphaComponent:0.96];
    outerRing.layer.cornerRadius = kButtonSize / 2;
    outerRing.layer.borderWidth = brandIcon ? 0.0 : 1.0;
    outerRing.layer.borderColor = brandIcon ? UIColor.clearColor.CGColor : kVCBorderStrong.CGColor;
    outerRing.userInteractionEnabled = NO;
    [self addSubview:outerRing];

    UIView *innerOrb = [[UIView alloc] initWithFrame:CGRectZero];
    innerOrb.translatesAutoresizingMaskIntoConstraints = NO;
    innerOrb.backgroundColor = brandIcon ? [UIColor clearColor] : kVCAccentDim;
    innerOrb.layer.cornerRadius = (kButtonSize - 12.0) * 0.5;
    innerOrb.layer.borderWidth = brandIcon ? 0.0 : 1.0;
    innerOrb.layer.borderColor = brandIcon ? UIColor.clearColor.CGColor : kVCBorderAccent.CGColor;
    innerOrb.userInteractionEnabled = NO;
    [self addSubview:innerOrb];

    UIView *highlight = [[UIView alloc] initWithFrame:CGRectMake(10, 8, kButtonSize - 20, 14)];
    highlight.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    highlight.layer.cornerRadius = 7.0;
    highlight.hidden = brandIcon;
    highlight.userInteractionEnabled = NO;
    [innerOrb addSubview:highlight];

    UIView *logoView = nil;
    if (brandIcon) {
        UIImageView *iconView = [[UIImageView alloc] initWithImage:brandIcon];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        iconView.contentMode = UIViewContentModeScaleAspectFill;
        iconView.clipsToBounds = YES;
        iconView.layer.cornerRadius = kButtonSize * 0.5;
        logoView = iconView;
        [self addSubview:logoView];
    } else {
        UILabel *fallbackLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = NO;
        fallbackLabel.text = @"VC";
        fallbackLabel.textColor = kVCTextPrimary;
        fallbackLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightBold];
        fallbackLabel.textAlignment = NSTextAlignmentCenter;
        logoView = fallbackLabel;
        [self addSubview:logoView];
    }

    UIView *statusDot = [[UIView alloc] initWithFrame:CGRectMake(kButtonSize - 16, 8, 8, 8)];
    statusDot.backgroundColor = kVCGreen;
    statusDot.layer.cornerRadius = 4;
    statusDot.layer.borderColor = kVCBgSecondary.CGColor;
    statusDot.layer.borderWidth = 1.0;
    statusDot.userInteractionEnabled = NO;
    [self addSubview:statusDot];

    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [outerRing.topAnchor constraintEqualToAnchor:self.topAnchor],
        [outerRing.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [outerRing.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [outerRing.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [innerOrb.topAnchor constraintEqualToAnchor:self.topAnchor constant:6.0],
        [innerOrb.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0],
        [innerOrb.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6.0],
        [innerOrb.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6.0],
    ]];
    if (brandIcon) {
        [constraints addObjectsFromArray:@[
            [logoView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [logoView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [logoView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [logoView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    } else {
        [constraints addObjectsFromArray:@[
            [logoView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [logoView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [logoView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [logoView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    [NSLayoutConstraint activateConstraints:constraints];

    self.center = CGPointMake(kButtonSize, kButtonSize);

    // Gestures
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePan:)];
    [self addGestureRecognizer:pan];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTap)];
    [self addGestureRecognizer:tap];

    // Long press -> quick menu
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [self addGestureRecognizer:longPress];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleOverlayGeometryChange:)
                                                 name:VCOverlayWindowGeometryDidChangeNotification
                                               object:nil];
}

#pragma mark - Tap -> Toggle Panel

- (void)_handleTap {
    if (_dragging) return;

    if (!_panel) {
        UIView *container = [VCOverlayWindow shared].rootViewController.view;
        _panel = [[VCPanel alloc] initWithFrame:CGRectZero];
        _panel.translatesAutoresizingMaskIntoConstraints = NO;
        _panel.hidden = YES;
        [container insertSubview:_panel belowSubview:self];
        [NSLayoutConstraint activateConstraints:@[
            [_panel.topAnchor constraintEqualToAnchor:container.topAnchor],
            [_panel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [_panel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [_panel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        ]];
    }

    if (_panel.isVisible) {
        [_panel hideAnimated];
    } else {
        [_panel showAnimated];
    }
}

#pragma mark - Drag

- (void)_handlePan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;

    CGPoint translation = [pan translationInView:superview];

    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            _dragStart = self.center;
            _dragging = YES;
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat newX = _dragStart.x + translation.x;
            CGFloat newY = _dragStart.y + translation.y;
            CGRect bounds = superview.bounds;
            UIEdgeInsets safeInsets = superview.safeAreaInsets;
            CGFloat half = kButtonSize / 2.0;
            CGFloat minX = half;
            CGFloat maxX = MAX(minX, CGRectGetWidth(bounds) - half);
            CGFloat minY = [self _verticalMinForBounds:bounds safeInsets:safeInsets] - 4.0;
            CGFloat maxY = [self _verticalMaxForBounds:bounds safeInsets:safeInsets] + 4.0;
            newX = MAX(minX, MIN(maxX, newX));
            newY = MAX(minY, MIN(maxY, newY));
            self.center = CGPointMake(newX, newY);
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            // Snap to nearest edge
            [self _snapToEdge];
            _dragging = NO;
            break;
        }
        default: break;
    }
}

- (void)_snapToEdge {
    CGRect bounds = self.superview.bounds;
    if (CGRectIsEmpty(bounds)) return;

    NSString *side = self.center.x < CGRectGetMidX(bounds) ? @"left" : @"right";
    UIEdgeInsets safeInsets = self.superview.safeAreaInsets;
    CGFloat topLimit = [self _verticalMinForBounds:bounds safeInsets:safeInsets];
    CGFloat bottomLimit = [self _verticalMaxForBounds:bounds safeInsets:safeInsets];
    CGFloat ratio = 0.42;
    if (bottomLimit > topLimit) {
        ratio = (self.center.y - topLimit) / (bottomLimit - topLimit);
    }
    ratio = MIN(MAX(ratio, 0.0), 1.0);

    CGPoint target = [self _anchoredCenterForSide:side ratio:ratio bounds:bounds safeInsets:safeInsets];
    [UIView animateWithDuration:0.25
                          delay:0
         usingSpringWithDamping:0.8
          initialSpringVelocity:0
                        options:0
                     animations:^{
        self.center = target;
    } completion:^(BOOL finished) {
        [self _persistAnchorSide:side ratio:ratio center:target];
    }];
}

#pragma mark - Long Press -> Quick Menu

- (void)_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    if (self.quickMenuBackdrop) {
        [self _hideQuickMenu];
        return;
    }
    [self _showQuickMenu];
}

- (UIButton *)_quickMenuButtonWithTitle:(NSString *)title tint:(UIColor *)tint action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    if (tint == kVCRed) {
        VCApplyCompactDangerButtonStyle(button);
    } else if (tint == kVCAccent) {
        VCApplyCompactAccentButtonStyle(button);
    } else {
        VCApplyCompactSecondaryButtonStyle(button);
    }
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)_showQuickMenu {
    UIView *container = [VCOverlayWindow shared].rootViewController.view;
    if (!container) return;

    self.quickMenuBackdrop = [[UIControl alloc] init];
    self.quickMenuBackdrop.translatesAutoresizingMaskIntoConstraints = NO;
    self.quickMenuBackdrop.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    [self.quickMenuBackdrop addTarget:self action:@selector(_hideQuickMenu) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.quickMenuBackdrop];

    self.quickMenuCard = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 184, 154)];
    self.quickMenuCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    self.quickMenuCard.layer.cornerRadius = 18.0;
    self.quickMenuCard.layer.borderWidth = 1.0;
    self.quickMenuCard.layer.borderColor = kVCBorderStrong.CGColor;
    self.quickMenuCard.clipsToBounds = YES;
    [container addSubview:self.quickMenuCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.quickMenuBackdrop.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.quickMenuBackdrop.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.quickMenuBackdrop.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.quickMenuBackdrop.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = VCTextLiteral(@"Quick Actions");
    titleLabel.textColor = kVCTextSecondary;
    titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [self.quickMenuCard addSubview:titleLabel];

    UIButton *hideButton = [self _quickMenuButtonWithTitle:VCTextLiteral(@"Hide Button") tint:kVCTextPrimary action:@selector(_quickHideButton)];
    UIButton *safeModeButton = [self _quickMenuButtonWithTitle:VCTextLiteral(@"Safe Mode") tint:kVCRed action:@selector(_quickTriggerSafeMode)];
    UIButton *resetButton = [self _quickMenuButtonWithTitle:VCTextLiteral(@"Reset Position") tint:kVCAccent action:@selector(_quickResetPosition)];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[hideButton, safeModeButton, resetButton]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6.0;
    stack.distribution = UIStackViewDistributionFillEqually;
    [self.quickMenuCard addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.quickMenuCard.topAnchor constant:12.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.quickMenuCard.leadingAnchor constant:14.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.quickMenuCard.trailingAnchor constant:-14.0],

        [stack.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [stack.leadingAnchor constraintEqualToAnchor:self.quickMenuCard.leadingAnchor constant:10.0],
        [stack.trailingAnchor constraintEqualToAnchor:self.quickMenuCard.trailingAnchor constant:-10.0],
        [stack.bottomAnchor constraintEqualToAnchor:self.quickMenuCard.bottomAnchor constant:-14.0],
        [stack.heightAnchor constraintEqualToConstant:102.0],
    ]];
    [self _layoutQuickMenuAnimated:NO];
    CGRect targetFrame = self.quickMenuCard.frame;
    self.quickMenuCard.frame = CGRectOffset(targetFrame, 0, 8.0);
    self.quickMenuCard.alpha = 0.0;
    self.quickMenuCard.transform = CGAffineTransformMakeScale(0.98, 0.98);

    [UIView animateWithDuration:0.18 animations:^{
        self.quickMenuBackdrop.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
        self.quickMenuCard.alpha = 1.0;
        self.quickMenuCard.transform = CGAffineTransformIdentity;
        self.quickMenuCard.frame = targetFrame;
    }];
}

- (void)_hideQuickMenu {
    if (!self.quickMenuBackdrop || !self.quickMenuCard) return;
    UIControl *backdrop = self.quickMenuBackdrop;
    UIView *card = self.quickMenuCard;
    self.quickMenuBackdrop = nil;
    self.quickMenuCard = nil;

    [UIView animateWithDuration:0.16 animations:^{
        backdrop.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
        card.alpha = 0.0;
        card.transform = CGAffineTransformMakeScale(0.98, 0.98);
    } completion:^(BOOL finished) {
        [backdrop removeFromSuperview];
        [card removeFromSuperview];
    }];
}

- (void)_quickHideButton {
    [self _hideQuickMenu];
    [VCFloatingButton hide];
}

- (void)_quickTriggerSafeMode {
    [self _hideQuickMenu];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"VCSafeModeDisablePatches" object:nil];
    VCLog(@"[UI] Safe mode triggered from floating button");
}

- (void)_quickResetPosition {
    [self _hideQuickMenu];
    CGRect bounds = self.superview.bounds;
    UIEdgeInsets safeInsets = self.superview.safeAreaInsets;
    CGPoint target = [self _anchoredCenterForSide:@"right" ratio:0.42 bounds:bounds safeInsets:safeInsets];
    self.center = target;
    [self _persistAnchorSide:@"right" ratio:0.42 center:target];
}

- (void)_handleOverlayGeometryChange:(NSNotification *)notification {
    if (!self.superview || self.hidden || self.dragging) return;
    [self _applyStoredAnchorToCurrentSuperviewAnimated:NO persistIfNeeded:NO];
    if (self.quickMenuCard) {
        [self _layoutQuickMenuAnimated:NO];
    }
}

- (CGFloat)_verticalMinForBounds:(CGRect)bounds safeInsets:(UIEdgeInsets)safeInsets {
    CGFloat half = kButtonSize / 2.0 + 4.0;
    return MAX(half + 12.0, safeInsets.top + half + 8.0);
}

- (CGFloat)_verticalMaxForBounds:(CGRect)bounds safeInsets:(UIEdgeInsets)safeInsets {
    CGFloat half = kButtonSize / 2.0 + 4.0;
    return MAX([self _verticalMinForBounds:bounds safeInsets:safeInsets],
               CGRectGetHeight(bounds) - MAX(half + 12.0, safeInsets.bottom + half + 8.0));
}

- (CGPoint)_anchoredCenterForSide:(NSString *)side
                            ratio:(CGFloat)ratio
                           bounds:(CGRect)bounds
                        safeInsets:(UIEdgeInsets)safeInsets {
    CGFloat half = kButtonSize / 2.0 + 4.0;
    CGFloat x = [[side lowercaseString] isEqualToString:@"left"] ? half : CGRectGetWidth(bounds) - half;
    CGFloat minY = [self _verticalMinForBounds:bounds safeInsets:safeInsets];
    CGFloat maxY = [self _verticalMaxForBounds:bounds safeInsets:safeInsets];
    CGFloat clampedRatio = MIN(MAX(ratio, 0.0), 1.0);
    CGFloat y = minY;
    if (maxY > minY) {
        y = minY + ((maxY - minY) * clampedRatio);
    }
    return CGPointMake(x, y);
}

- (void)_persistAnchorSide:(NSString *)side ratio:(CGFloat)ratio center:(CGPoint)center {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *resolvedSide = [[side lowercaseString] isEqualToString:@"left"] ? @"left" : @"right";
    [defaults setObject:resolvedSide forKey:kPositionSideKey];
    [defaults setFloat:MIN(MAX(ratio, 0.0), 1.0) forKey:kPositionVerticalRatioKey];
    [defaults setFloat:center.x forKey:kPositionXKey];
    [defaults setFloat:center.y forKey:kPositionYKey];
}

- (void)_migrateLegacyAnchorIfNeededForBounds:(CGRect)bounds {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults stringForKey:kPositionSideKey].length > 0) return;

    CGFloat savedX = [defaults floatForKey:kPositionXKey];
    CGFloat savedY = [defaults floatForKey:kPositionYKey];
    NSString *side = savedX > 0 && savedX < CGRectGetMidX(bounds) ? @"left" : @"right";
    UIEdgeInsets safeInsets = self.superview ? self.superview.safeAreaInsets : UIEdgeInsetsZero;
    CGFloat minY = [self _verticalMinForBounds:bounds safeInsets:safeInsets];
    CGFloat maxY = [self _verticalMaxForBounds:bounds safeInsets:safeInsets];
    CGFloat ratio = 0.42;
    if (savedY > 0 && maxY > minY) {
        ratio = (savedY - minY) / (maxY - minY);
    }
    ratio = MIN(MAX(ratio, 0.0), 1.0);
    CGPoint migratedCenter = [self _anchoredCenterForSide:side ratio:ratio bounds:bounds safeInsets:safeInsets];
    [self _persistAnchorSide:side ratio:ratio center:migratedCenter];
}

- (void)_applyStoredAnchorToCurrentSuperviewAnimated:(BOOL)animated persistIfNeeded:(BOOL)persistIfNeeded {
    CGRect bounds = self.superview ? self.superview.bounds : [VCOverlayRootViewController currentHostBounds];
    if (CGRectIsEmpty(bounds)) return;

    [self _migrateLegacyAnchorIfNeededForBounds:bounds];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *side = [defaults stringForKey:kPositionSideKey];
    if (side.length == 0) side = @"right";
    CGFloat ratio = [defaults floatForKey:kPositionVerticalRatioKey];
    if (ratio <= 0.0f && [defaults objectForKey:kPositionVerticalRatioKey] == nil) ratio = 0.42f;
    UIEdgeInsets safeInsets = self.superview ? self.superview.safeAreaInsets : UIEdgeInsetsZero;
    CGPoint target = [self _anchoredCenterForSide:side ratio:ratio bounds:bounds safeInsets:safeInsets];

    void (^applyBlock)(void) = ^{
        self.center = target;
    };
    if (animated) {
        [UIView animateWithDuration:0.2 animations:applyBlock];
    } else {
        applyBlock();
    }
    if (persistIfNeeded) {
        [self _persistAnchorSide:side ratio:ratio center:target];
    }
}

- (void)_layoutQuickMenuAnimated:(BOOL)animated {
    UIView *container = [VCOverlayWindow shared].rootViewController.view;
    if (!container || !self.quickMenuCard || !self.superview) return;

    CGRect anchorFrame = [self.superview convertRect:self.frame toView:container];
    CGFloat preferredX = CGRectGetMidX(anchorFrame) < CGRectGetMidX(container.bounds)
        ? CGRectGetMinX(anchorFrame)
        : CGRectGetMaxX(anchorFrame) - CGRectGetWidth(self.quickMenuCard.frame);
    CGFloat preferredY = CGRectGetMinY(anchorFrame) - CGRectGetHeight(self.quickMenuCard.frame) - 10.0;
    CGFloat x = MAX(10.0, MIN(CGRectGetWidth(container.bounds) - CGRectGetWidth(self.quickMenuCard.frame) - 10.0, preferredX));
    CGFloat y = preferredY < (container.safeAreaInsets.top + 14.0) ? CGRectGetMaxY(anchorFrame) + 10.0 : preferredY;
    CGRect targetFrame = CGRectMake(x, y, CGRectGetWidth(self.quickMenuCard.frame), CGRectGetHeight(self.quickMenuCard.frame));
    if (animated) {
        [UIView animateWithDuration:0.16 animations:^{
            self.quickMenuCard.frame = targetFrame;
        }];
    } else {
        self.quickMenuCard.frame = targetFrame;
    }
}

@end
