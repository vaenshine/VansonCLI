/**
 * VCPanel -- Floating control panel
 * Portrait: header + top tab bar
 * Landscape: workstation header + left rail navigation
 * Compact landscape: reduced header density + compact left rail navigation
 */

#import "VCPanel.h"
#import "VCTabBar.h"
#import "VCWorkspaceHubTab.h"
#import "../../../VansonCLI.h"
#import "../Patches/VCPatchesTab.h"
#import "../Inspect/VCInspectTab.h"
#import "../Network/VCNetworkTab.h"
#import "../Chat/VCChatTab.h"
#import "../Code/VCCodeTab.h"
#import "../Memory/VCMemoryBrowserTab.h"
#import "../Artifacts/VCArtifactsTab.h"
#import "../Console/VCConsoleTab.h"
#import "../Settings/VCSettingsTab.h"
#import "../Base/VCBrandIcon.h"
#import "../Base/VCOverlayWindow.h"
#import "../../Core/VCConfig.h"

static const CGFloat kPortraitHeaderHeight = 52.0;
static const CGFloat kLandscapeHeaderHeight = 44.0;
static const CGFloat kCompactLandscapeHeaderHeight = 30.0;
static const CGFloat kPortraitTabBarHeight = 44.0;
static const CGFloat kLandscapeTabBarHeight = 38.0;
static const CGFloat kCompactLandscapeTabBarWidthMin = 96.0;
static const CGFloat kCompactLandscapeTabBarWidthMax = 116.0;
static const CGFloat kLandscapeTabBarWidthMin = 112.0;
static const CGFloat kLandscapeTabBarWidthMax = 138.0;
static const CGFloat kCompactLandscapeMaxWidth = 860.0;
static const CGFloat kCompactLandscapeMaxHeight = 430.0;

typedef struct {
    CGFloat headerHeight;
    CGFloat tabBarHeight;
    CGFloat tabBarWidthMin;
    CGFloat tabBarWidthMax;
    CGFloat panelWidthInset;
    CGFloat panelWidthMax;
    CGFloat panelWidthFloorInset;
    CGFloat panelWidthFloorMin;
    CGFloat panelHeightInset;
    CGFloat panelHeightMax;
    CGFloat panelHeightFloorInset;
    CGFloat panelHeightFloorMin;
    CGFloat glowHeightCap;
    CGFloat glowHeightFactor;
    CGFloat bottomTintHeightCap;
    CGFloat bottomTintHeightFactor;
} VCPanelShellMetrics;

static VCPanelShellLayoutTier VCPanelResolveShellLayoutTier(CGRect safeBounds) {
    CGFloat width = CGRectGetWidth(safeBounds);
    CGFloat height = CGRectGetHeight(safeBounds);
    if (width <= height) {
        return VCPanelShellLayoutTierPortrait;
    }
    if (width <= kCompactLandscapeMaxWidth || height <= kCompactLandscapeMaxHeight) {
        return VCPanelShellLayoutTierCompactLandscape;
    }
    return VCPanelShellLayoutTierLandscape;
}

static VCPanelShellMetrics VCPanelShellMetricsForTier(VCPanelShellLayoutTier tier) {
    switch (tier) {
        case VCPanelShellLayoutTierCompactLandscape:
            return (VCPanelShellMetrics){
                .headerHeight = kCompactLandscapeHeaderHeight,
                .tabBarHeight = kLandscapeTabBarHeight,
                .tabBarWidthMin = kCompactLandscapeTabBarWidthMin,
                .tabBarWidthMax = kCompactLandscapeTabBarWidthMax,
                .panelWidthInset = 8.0,
                .panelWidthMax = 980.0,
                .panelWidthFloorInset = 10.0,
                .panelWidthFloorMin = 640.0,
                .panelHeightInset = 6.0,
                .panelHeightMax = 680.0,
                .panelHeightFloorInset = 8.0,
                .panelHeightFloorMin = 360.0,
                .glowHeightCap = 76.0,
                .glowHeightFactor = 0.14,
                .bottomTintHeightCap = 88.0,
                .bottomTintHeightFactor = 0.17,
            };
        case VCPanelShellLayoutTierLandscape:
            return (VCPanelShellMetrics){
                .headerHeight = kLandscapeHeaderHeight,
                .tabBarHeight = kLandscapeTabBarHeight,
                .tabBarWidthMin = kLandscapeTabBarWidthMin,
                .tabBarWidthMax = kLandscapeTabBarWidthMax,
                .panelWidthInset = 8.0,
                .panelWidthMax = 1220.0,
                .panelWidthFloorInset = 10.0,
                .panelWidthFloorMin = 680.0,
                .panelHeightInset = 6.0,
                .panelHeightMax = 780.0,
                .panelHeightFloorInset = 8.0,
                .panelHeightFloorMin = 430.0,
                .glowHeightCap = 84.0,
                .glowHeightFactor = 0.16,
                .bottomTintHeightCap = 96.0,
                .bottomTintHeightFactor = 0.18,
            };
        case VCPanelShellLayoutTierPortrait:
        default:
            return (VCPanelShellMetrics){
                .headerHeight = kPortraitHeaderHeight,
                .tabBarHeight = kPortraitTabBarHeight,
                .tabBarWidthMin = 0.0,
                .tabBarWidthMax = 0.0,
                .panelWidthInset = 12.0,
                .panelWidthMax = 560.0,
                .panelWidthFloorInset = 12.0,
                .panelWidthFloorMin = 320.0,
                .panelHeightInset = 10.0,
                .panelHeightMax = CGFLOAT_MAX,
                .panelHeightFloorInset = 10.0,
                .panelHeightFloorMin = 360.0,
                .glowHeightCap = 118.0,
                .glowHeightFactor = 0.22,
                .bottomTintHeightCap = 140.0,
                .bottomTintHeightFactor = 0.26,
            };
    }
}

static VCTabBarLayoutStyle VCPanelTabBarLayoutStyleForTier(VCPanelShellLayoutTier tier) {
    switch (tier) {
        case VCPanelShellLayoutTierCompactLandscape:
            return VCTabBarLayoutStyleCompactVertical;
        case VCPanelShellLayoutTierLandscape:
            return VCTabBarLayoutStyleVertical;
        case VCPanelShellLayoutTierPortrait:
        default:
            return VCTabBarLayoutStyleHorizontal;
    }
}

typedef NS_ENUM(NSInteger, VCPanelSizeMode) {
    VCPanelSizeS = 0,
    VCPanelSizeM,
    VCPanelSizeL,
};

typedef NS_ENUM(NSInteger, VCPanelContentTabIndex) {
    VCPanelContentTabIndexChat = 0,
    VCPanelContentTabIndexInspect,
    VCPanelContentTabIndexUI,
    VCPanelContentTabIndexNetwork,
    VCPanelContentTabIndexConsole,
    VCPanelContentTabIndexCode,
    VCPanelContentTabIndexMemory,
    VCPanelContentTabIndexArtifacts,
    VCPanelContentTabIndexPatches,
    VCPanelContentTabIndexSettings,
    VCPanelContentTabIndexWorkspaceHub,
};

static NSArray<NSString *> *VCPanelPrimaryNavigationTitles(void) {
    static NSArray<NSString *> *titles = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        titles = @[ @"AI Chat", @"Inspect", @"Network", @"Artifacts", @"Patches", @"Console", @"Settings" ];
    });
    return titles;
}

static NSArray<NSNumber *> *VCPanelPrimaryNavigationTargets(void) {
    static NSArray<NSNumber *> *targets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        targets = @[
            @(VCPanelContentTabIndexChat),
            @(VCPanelContentTabIndexInspect),
            @(VCPanelContentTabIndexNetwork),
            @(VCPanelContentTabIndexArtifacts),
            @(VCPanelContentTabIndexPatches),
            @(VCPanelContentTabIndexConsole),
            @(VCPanelContentTabIndexSettings),
        ];
    });
    return targets;
}

static NSInteger VCPanelPrimaryNavigationIndexForContentIndex(NSInteger contentIndex) {
    if (contentIndex == VCPanelContentTabIndexCode ||
        contentIndex == VCPanelContentTabIndexMemory ||
        contentIndex == VCPanelContentTabIndexWorkspaceHub) {
        return 6;
    }

    if (contentIndex == VCPanelContentTabIndexUI) {
        return 1;
    }

    NSArray<NSNumber *> *targets = VCPanelPrimaryNavigationTargets();
    for (NSUInteger idx = 0; idx < targets.count; idx++) {
        if ([targets[idx] integerValue] == contentIndex) {
            return (NSInteger)idx;
        }
    }
    return 0;
}

static NSInteger VCPanelContentIndexForWorkspaceSection(NSString *section) {
    if ([section isEqualToString:@"chat"]) return VCPanelContentTabIndexChat;
    if ([section isEqualToString:@"inspect"]) return VCPanelContentTabIndexInspect;
    if ([section isEqualToString:@"network"]) return VCPanelContentTabIndexNetwork;
    if ([section isEqualToString:@"code"]) return VCPanelContentTabIndexWorkspaceHub;
    if ([section isEqualToString:@"memory"]) return VCPanelContentTabIndexWorkspaceHub;
    if ([section isEqualToString:@"console"]) return VCPanelContentTabIndexConsole;
    if ([section isEqualToString:@"artifacts"]) return VCPanelContentTabIndexArtifacts;
    if ([section isEqualToString:@"patches"]) return VCPanelContentTabIndexPatches;
    if ([section isEqualToString:@"settings"]) return VCPanelContentTabIndexSettings;
    return VCPanelContentTabIndexWorkspaceHub;
}

static UILabel *VCPanelMakeBadge(NSString *text, UIColor *textColor, UIColor *fillColor, UIColor *borderColor) {
    UILabel *badge = [[UILabel alloc] init];
    badge.text = text;
    badge.textColor = textColor;
    badge.backgroundColor = fillColor;
    badge.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 10.0;
    badge.layer.borderWidth = 1.0;
    badge.layer.borderColor = borderColor.CGColor;
    badge.clipsToBounds = YES;
    return badge;
}

static CGFloat VCPanelBadgeWidth(NSString *text) {
    NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold] };
    CGFloat width = ceil([text sizeWithAttributes:attrs].width) + 18.0;
    return MIN(MAX(width, 52.0), 140.0);
}

@interface VCPanel () <VCTabBarDelegate>
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIView *bgView;
@property (nonatomic, strong) UIView *contentClipView;
@property (nonatomic, strong) UIView *panelOverlay;
@property (nonatomic, strong) UIView *topGlowView;
@property (nonatomic, strong) UIView *bottomTintView;
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UIView *dragHandleView;
@property (nonatomic, strong) UIView *headerSeparator;
@property (nonatomic, strong) UIView *tabSeparator;
@property (nonatomic, strong) UIImageView *logoIconView;
@property (nonatomic, strong) UILabel *logoLabel;
@property (nonatomic, strong) UILabel *headerSubtitleLabel;
@property (nonatomic, strong) UILabel *hostBadge;
@property (nonatomic, strong) UILabel *statusBadge;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) NSArray<UIButton *> *sizeButtons;
@property (nonatomic, assign) VCPanelSizeMode sizeMode;
@property (nonatomic, assign) BOOL isFocused;
@property (nonatomic, assign) BOOL visible;
@property (nonatomic, assign) CGPoint dragStart;
@property (nonatomic, assign) CGPoint bgStartCenter;
@property (nonatomic, strong, readwrite) VCTabBar *tabBar;
@property (nonatomic, strong, readwrite) UIView *bodyContainer;
@property (nonatomic, assign, readwrite) VCPanelLayoutMode layoutMode;
@property (nonatomic, assign, readwrite) VCPanelShellLayoutTier shellLayoutTier;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *tabVCs;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *tabViews;
@property (nonatomic, assign) NSInteger currentTabIndex;
@property (nonatomic, assign) NSInteger totalTabCount;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) CGRect lastLaidOutBounds;
@end

@implementation VCPanel

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _sizeMode = VCPanelSizeL;
        _isFocused = NO;
        _visible = NO;
        _layoutMode = VCPanelLayoutModePortrait;
        _shellLayoutTier = VCPanelShellLayoutTierPortrait;
        _currentTabIndex = -1;
        _tabVCs = [NSMutableDictionary new];
        _tabViews = [NSMutableDictionary new];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleOpenPatchesEditorRequest:)
                                                     name:VCPatchesRequestOpenEditorNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleOpenMemoryAddressRequest:)
                                                     name:VCMemoryBrowserRequestOpenAddressNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleLanguageDidChange)
                                                     name:VCLanguageDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleOpenAIChatRequest)
                                                     name:VCSettingsRequestOpenAIChatNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleOpenCodeFileRequest:)
                                                     name:VCCodeTabRequestOpenFileNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleOpenArtifactsRequest:)
                                                     name:VCArtifactsRequestOpenModeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleWorkspaceHubOpenSectionRequest:)
                                                     name:VCWorkspaceHubRequestOpenSectionNotification
                                                   object:nil];
        [self _buildPanel];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (CGRectEqualToRect(self.lastLaidOutBounds, self.bounds)) return;
    self.lastLaidOutBounds = self.bounds;
    self.dimView.frame = self.bounds;
    [self _relayoutForGeometryChangeAnimated:NO];
}

#pragma mark - Build

- (void)_buildPanel {
    self.dimView = [[UIView alloc] initWithFrame:CGRectZero];
    self.dimView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.54];
    self.dimView.alpha = 0;
    [self addSubview:self.dimView];
    [NSLayoutConstraint activateConstraints:@[
        [self.dimView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.dimView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.dimView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.dimView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    UITapGestureRecognizer *dimTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_onDimTap)];
    [self.dimView addGestureRecognizer:dimTap];

    self.bgView = [[UIView alloc] initWithFrame:CGRectZero];
    self.bgView.backgroundColor = kVCBgPrimary;
    self.bgView.layer.cornerRadius = 20.0;
    self.bgView.layer.borderColor = kVCBorderStrong.CGColor;
    self.bgView.layer.borderWidth = 1.0;
    self.bgView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.bgView.layer.shadowOpacity = 0.35;
    self.bgView.layer.shadowRadius = 28.0;
    self.bgView.layer.shadowOffset = CGSizeMake(0, 18.0);
    self.bgView.clipsToBounds = NO;
    [self addSubview:self.bgView];

    self.contentClipView = [[UIView alloc] initWithFrame:CGRectZero];
    self.contentClipView.backgroundColor = kVCBgPrimary;
    self.contentClipView.layer.cornerRadius = self.bgView.layer.cornerRadius;
    self.contentClipView.layer.borderWidth = 0.0;
    self.contentClipView.layer.borderColor = UIColor.clearColor.CGColor;
    self.contentClipView.clipsToBounds = YES;
    self.contentClipView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bgView addSubview:self.contentClipView];
    [NSLayoutConstraint activateConstraints:@[
        [self.contentClipView.topAnchor constraintEqualToAnchor:self.bgView.topAnchor],
        [self.contentClipView.leadingAnchor constraintEqualToAnchor:self.bgView.leadingAnchor],
        [self.contentClipView.trailingAnchor constraintEqualToAnchor:self.bgView.trailingAnchor],
        [self.contentClipView.bottomAnchor constraintEqualToAnchor:self.bgView.bottomAnchor],
    ]];

    self.panelOverlay = [[UIView alloc] initWithFrame:CGRectZero];
    self.panelOverlay.backgroundColor = [UIColor clearColor];
    self.panelOverlay.userInteractionEnabled = NO;
    self.panelOverlay.clipsToBounds = YES;
    self.panelOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentClipView addSubview:self.panelOverlay];
    [NSLayoutConstraint activateConstraints:@[
        [self.panelOverlay.topAnchor constraintEqualToAnchor:self.contentClipView.topAnchor],
        [self.panelOverlay.leadingAnchor constraintEqualToAnchor:self.contentClipView.leadingAnchor],
        [self.panelOverlay.trailingAnchor constraintEqualToAnchor:self.contentClipView.trailingAnchor],
        [self.panelOverlay.bottomAnchor constraintEqualToAnchor:self.contentClipView.bottomAnchor],
    ]];

    self.topGlowView = [[UIView alloc] initWithFrame:CGRectZero];
    self.topGlowView.backgroundColor = [kVCAccent colorWithAlphaComponent:0.08];
    self.topGlowView.userInteractionEnabled = NO;
    [self.panelOverlay addSubview:self.topGlowView];

    self.bottomTintView = [[UIView alloc] initWithFrame:CGRectZero];
    self.bottomTintView.backgroundColor = [kVCGreen colorWithAlphaComponent:0.03];
    self.bottomTintView.userInteractionEnabled = NO;
    [self.panelOverlay addSubview:self.bottomTintView];

    self.navBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.navBar.backgroundColor = [kVCBgSecondary colorWithAlphaComponent:0.42];
    [self.contentClipView addSubview:self.navBar];

    self.dragHandleView = [[UIView alloc] initWithFrame:CGRectZero];
    self.dragHandleView.backgroundColor = [kVCTextMuted colorWithAlphaComponent:0.75];
    self.dragHandleView.layer.cornerRadius = 2.0;
    [self.navBar addSubview:self.dragHandleView];

    self.headerSeparator = [[UIView alloc] initWithFrame:CGRectZero];
    self.headerSeparator.backgroundColor = [kVCBorderStrong colorWithAlphaComponent:0.38];
    [self.contentClipView addSubview:self.headerSeparator];

    self.tabSeparator = [[UIView alloc] initWithFrame:CGRectZero];
    self.tabSeparator.backgroundColor = [kVCBorderStrong colorWithAlphaComponent:0.34];
    [self.contentClipView addSubview:self.tabSeparator];

    self.logoIconView = [[UIImageView alloc] initWithImage:VCBrandIconImage()];
    self.logoIconView.contentMode = UIViewContentModeScaleAspectFill;
    self.logoIconView.clipsToBounds = YES;
    self.logoIconView.layer.borderWidth = 0.0;
    self.logoIconView.layer.borderColor = UIColor.clearColor.CGColor;
    [self.navBar addSubview:self.logoIconView];

    self.logoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.logoLabel.text = @"VansonCLI";
    self.logoLabel.textColor = kVCAccent;
    self.logoLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [self.navBar addSubview:self.logoLabel];

    self.headerSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.headerSubtitleLabel.textColor = kVCTextMuted;
    self.headerSubtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.headerSubtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.navBar addSubview:self.headerSubtitleLabel];

    self.hostBadge = VCPanelMakeBadge(VCTextLiteral(@"Host"),
                                      kVCTextPrimary,
                                      [kVCBgSurface colorWithAlphaComponent:0.9],
                                      kVCBorder);
    self.hostBadge.hidden = YES;
    [self.navBar addSubview:self.hostBadge];

    self.statusBadge = VCPanelMakeBadge(VCTextLiteral(@"Attached"),
                                        kVCGreen,
                                        kVCGreenDim,
                                        [kVCGreen colorWithAlphaComponent:0.34]);
    [self.navBar addSubview:self.statusBadge];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(self.closeButton);
    [self.closeButton addTarget:self action:@selector(hideAnimated) forControlEvents:UIControlEventTouchUpInside];
    [self.navBar addSubview:self.closeButton];

    NSArray *titles = VCPanelPrimaryNavigationTitles();
    self.totalTabCount = (NSInteger)titles.count;
    self.tabBar = [[VCTabBar alloc] initWithTitles:titles];
    self.tabBar.delegate = self;
    [self.contentClipView addSubview:self.tabBar];

    NSMutableArray<UIButton *> *buttons = [NSMutableArray new];
    NSArray *sizeTitles = @[@"S", @"M", @"L"];
    for (NSInteger idx = 0; idx < (NSInteger)sizeTitles.count; idx++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:sizeTitles[idx] forState:UIControlStateNormal];
        VCApplyCompactSecondaryButtonStyle(button);
        button.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        button.tag = idx;
        [button addTarget:self action:@selector(_onSizeTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.navBar addSubview:button];
        [buttons addObject:button];
    }
    self.sizeButtons = buttons;
    [self _updateSizeHighlight];

    self.bodyContainer = [[UIView alloc] initWithFrame:CGRectZero];
    self.bodyContainer.backgroundColor = [UIColor clearColor];
    self.bodyContainer.clipsToBounds = YES;
    [self.contentClipView addSubview:self.bodyContainer];

    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(_onSwipeLeft)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.bodyContainer addGestureRecognizer:swipeLeft];

    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(_onSwipeRight)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [self.bodyContainer addGestureRecognizer:swipeRight];

    [self _updateHeaderBadges];
    [self _relayoutForGeometryChangeAnimated:NO];
}

#pragma mark - Layout

- (CGFloat)_currentScale {
    switch (self.sizeMode) {
        case VCPanelSizeS: return 0.6;
        case VCPanelSizeM: return 0.8;
        case VCPanelSizeL: return 1.0;
    }
}

- (CGRect)_safeContainerBounds {
    CGRect bounds = self.bounds;
    UIEdgeInsets insets = self.safeAreaInsets;
    return UIEdgeInsetsInsetRect(bounds, insets);
}

- (void)_relayoutForGeometryChangeAnimated:(BOOL)animated {
    if (CGRectIsEmpty(self.bounds)) return;

    CGRect safeBounds = [self _safeContainerBounds];
    if (CGRectIsEmpty(safeBounds)) safeBounds = self.bounds;

    VCPanelShellLayoutTier tier = VCPanelResolveShellLayoutTier(safeBounds);
    VCPanelShellMetrics metrics = VCPanelShellMetricsForTier(tier);
    VCPanelLayoutMode mode = tier == VCPanelShellLayoutTierPortrait
        ? VCPanelLayoutModePortrait
        : VCPanelLayoutModeLandscape;
    self.layoutMode = mode;
    self.shellLayoutTier = tier;
    self.tabBar.layoutStyle = VCPanelTabBarLayoutStyleForTier(tier);

    CGFloat availableWidth = CGRectGetWidth(safeBounds);
    CGFloat availableHeight = CGRectGetHeight(safeBounds);
    CGFloat panelWidth = 0.0;
    CGFloat panelHeight = 0.0;
    if (mode == VCPanelLayoutModeLandscape) {
        panelWidth = MIN(availableWidth - metrics.panelWidthInset, metrics.panelWidthMax);
        panelWidth = MAX(panelWidth, MIN(availableWidth - metrics.panelWidthFloorInset, metrics.panelWidthFloorMin));
        panelHeight = MIN(availableHeight - metrics.panelHeightInset, metrics.panelHeightMax);
        panelHeight = MAX(panelHeight, MIN(availableHeight - metrics.panelHeightFloorInset, metrics.panelHeightFloorMin));
    } else {
        panelWidth = MIN(availableWidth * 0.94, 560.0);
        panelWidth = MAX(panelWidth, MIN(availableWidth - 12.0, 320.0));
        panelHeight = MIN(availableHeight * 0.86, availableHeight - 10.0);
        panelHeight = MAX(panelHeight, MIN(availableHeight - 10.0, 360.0));
    }

    CGFloat headerHeight = metrics.headerHeight;
    CGFloat tabBarHeight = metrics.tabBarHeight;

    CGFloat scale = self.visible ? [self _currentScale] : 1.0;
    self.bgView.transform = CGAffineTransformIdentity;
    self.bgView.frame = CGRectMake(CGRectGetMidX(safeBounds) - (panelWidth * 0.5),
                                   CGRectGetMidY(safeBounds) - (panelHeight * 0.5),
                                   panelWidth,
                                   panelHeight);
    self.bgView.transform = CGAffineTransformMakeScale(scale, scale);

    self.contentClipView.layer.cornerRadius = self.bgView.layer.cornerRadius;
    self.contentClipView.layer.borderWidth = 0.0;
    self.contentClipView.layer.borderColor = UIColor.clearColor.CGColor;

    self.panelOverlay.layer.cornerRadius = self.contentClipView.layer.cornerRadius;
    CGFloat glowHeight = MIN(metrics.glowHeightCap, panelHeight * metrics.glowHeightFactor);
    CGFloat bottomTintHeight = MIN(metrics.bottomTintHeightCap, panelHeight * metrics.bottomTintHeightFactor);
    self.topGlowView.frame = CGRectMake(0, 0, panelWidth, glowHeight);
    self.bottomTintView.frame = CGRectMake(0, panelHeight - bottomTintHeight, panelWidth, bottomTintHeight);

    if (mode == VCPanelLayoutModeLandscape) {
        CGFloat tabBarWidth = floor(panelWidth * 0.135);
        tabBarWidth = MAX(metrics.tabBarWidthMin, MIN(metrics.tabBarWidthMax, tabBarWidth));
        self.topGlowView.frame = CGRectMake(tabBarWidth, 0, MAX(panelWidth - tabBarWidth, 0.0), glowHeight);
        self.bottomTintView.frame = CGRectMake(tabBarWidth,
                                               panelHeight - bottomTintHeight,
                                               MAX(panelWidth - tabBarWidth, 0.0),
                                               bottomTintHeight);
        CGFloat tabBarHeight = MAX(panelHeight - headerHeight, 0.0);
        CGFloat bodyWidth = MAX(panelWidth - tabBarWidth, 0.0);
        CGFloat bodyHeight = MAX(panelHeight - headerHeight, 0.0);
        self.navBar.frame = CGRectMake(0, 0, panelWidth, headerHeight);
        self.navBar.layer.cornerRadius = self.contentClipView.layer.cornerRadius;
        self.headerSeparator.frame = CGRectMake(0, CGRectGetMaxY(self.navBar.frame) - 0.5, panelWidth, 0.5);
        self.tabBar.frame = CGRectMake(0, CGRectGetMaxY(self.navBar.frame), tabBarWidth, tabBarHeight);
        self.tabSeparator.frame = CGRectMake(CGRectGetMaxX(self.tabBar.frame) - 0.5, CGRectGetMinY(self.tabBar.frame), 0.5, CGRectGetHeight(self.tabBar.frame));
        self.bodyContainer.frame = CGRectMake(CGRectGetMaxX(self.tabBar.frame),
                                              CGRectGetMaxY(self.navBar.frame),
                                              bodyWidth,
                                              bodyHeight);
    } else {
        CGFloat bodyHeight = MAX(panelHeight - headerHeight - tabBarHeight, 0.0);
        self.navBar.frame = CGRectMake(0, 0, panelWidth, headerHeight);
        self.navBar.layer.cornerRadius = self.contentClipView.layer.cornerRadius;
        self.headerSeparator.frame = CGRectMake(0, CGRectGetMaxY(self.navBar.frame) - 0.5, panelWidth, 0.5);
        self.tabBar.frame = CGRectMake(0, CGRectGetMaxY(self.navBar.frame), panelWidth, tabBarHeight);
        self.tabSeparator.frame = CGRectMake(0, CGRectGetMaxY(self.tabBar.frame) - 0.5, panelWidth, 0.5);
        self.bodyContainer.frame = CGRectMake(0, CGRectGetMaxY(self.tabBar.frame), panelWidth, bodyHeight);
    }

    [self _layoutHeaderSubviewsForMode:mode shellTier:tier];

    for (UIView *page in self.tabViews.allValues) {
        page.frame = self.bodyContainer.bounds;
    }
    [self _dispatchLayoutUpdateToLoadedTabs];

    if (animated) {
        [UIView animateWithDuration:0.18 animations:^{
            [self.bgView layoutIfNeeded];
        }];
    }
}

- (void)_layoutHeaderSubviewsForMode:(VCPanelLayoutMode)mode shellTier:(VCPanelShellLayoutTier)tier {
    CGFloat width = CGRectGetWidth(self.navBar.bounds);
    BOOL landscape = (mode == VCPanelLayoutModeLandscape);
    BOOL compactLandscape = (tier == VCPanelShellLayoutTierCompactLandscape);

    self.dragHandleView.hidden = landscape;
    self.dragHandleView.frame = CGRectMake((width - 46.0) * 0.5, 6.0, 46.0, 4.0);

    CGFloat edgeInset = compactLandscape ? 8.0 : 10.0;
    CGFloat controlsRight = width - edgeInset;
    CGFloat closeSize = compactLandscape ? 20.0 : (landscape ? 26.0 : 28.0);
    CGFloat closeTop = compactLandscape ? 5.0 : (landscape ? 7.0 : 12.0);
    self.closeButton.frame = CGRectMake(controlsRight - closeSize, closeTop, closeSize, closeSize);
    self.closeButton.backgroundColor = landscape ? [UIColor clearColor] : [kVCBgSecondary colorWithAlphaComponent:0.9];
    self.closeButton.layer.borderWidth = landscape ? 0.0 : 1.0;
    self.closeButton.layer.borderColor = landscape ? UIColor.clearColor.CGColor : kVCBorder.CGColor;
    self.closeButton.layer.cornerRadius = landscape ? 0.0 : closeSize * 0.5;
    self.closeButton.tintColor = landscape ? kVCTextMuted : kVCAccentHover;
    controlsRight = CGRectGetMinX(self.closeButton.frame) - 10.0;

    for (NSInteger idx = (NSInteger)self.sizeButtons.count - 1; idx >= 0; idx--) {
        UIButton *button = self.sizeButtons[idx];
        CGFloat buttonSize = compactLandscape ? 16.0 : (landscape ? 22.0 : 24.0);
        controlsRight -= buttonSize;
        button.frame = CGRectMake(controlsRight,
                                  compactLandscape ? 7.0 : (landscape ? 9.0 : 14.0),
                                  buttonSize,
                                  buttonSize);
        controlsRight -= compactLandscape ? 3.0 : 4.0;
    }

    [self _updateHeaderBadges];

    CGFloat statusWidth = VCPanelBadgeWidth(self.statusBadge.text);
    self.statusBadge.frame = CGRectMake(MAX(controlsRight - statusWidth - 2.0, 14.0),
                                        compactLandscape ? 5.0 : (landscape ? 11.0 : 15.0),
                                        statusWidth,
                                        20.0);

    CGFloat subtitleMaxX = CGRectGetMinX(self.statusBadge.frame) - 12.0;
    BOOL showLogoIcon = (self.logoIconView.image != nil);
    CGFloat logoX = compactLandscape ? 10.0 : 14.0;
    CGFloat logoY = compactLandscape ? 6.0 : (landscape ? 12.0 : 13.0);
    CGFloat titleHeight = 18.0;
    CGFloat subtitleHeight = landscape ? 16.0 : 14.0;
    CGFloat logoIconSize = compactLandscape ? 16.0 : (landscape ? 18.0 : titleHeight + subtitleHeight);
    if (showLogoIcon) {
        self.logoIconView.hidden = NO;
        self.logoIconView.frame = CGRectMake(logoX,
                                             logoY,
                                             logoIconSize,
                                             logoIconSize);
        self.logoIconView.layer.cornerRadius = logoIconSize * 0.3;
    } else {
        self.logoIconView.hidden = YES;
        self.logoIconView.frame = CGRectZero;
    }

    CGFloat logoTextX = showLogoIcon ? CGRectGetMaxX(self.logoIconView.frame) + (compactLandscape ? 5.0 : 7.0) : 14.0;
    CGFloat logoTextWidth = compactLandscape ? 86.0 : (landscape ? 92.0 : 96.0);
    self.logoLabel.frame = CGRectMake(logoTextX,
                                      logoY,
                                      logoTextWidth,
                                      titleHeight);
    self.headerSubtitleLabel.font = [UIFont systemFontOfSize:(compactLandscape ? 9.0 : (landscape ? 10.0 : 11.0))
                                                     weight:UIFontWeightMedium];
    self.headerSubtitleLabel.numberOfLines = 1;
    self.headerSubtitleLabel.hidden = NO;
    if (landscape) {
        CGFloat subtitleX = CGRectGetMaxX(self.logoLabel.frame) + 10.0;
        CGFloat availableSubtitleWidth = subtitleMaxX - subtitleX;
        if (availableSubtitleWidth < (compactLandscape ? 56.0 : 72.0)) {
            self.headerSubtitleLabel.hidden = YES;
            self.headerSubtitleLabel.frame = CGRectZero;
        } else {
            self.headerSubtitleLabel.frame = CGRectMake(subtitleX,
                                                        compactLandscape ? 7.0 : 13.0,
                                                        availableSubtitleWidth,
                                                        16.0);
        }
    } else {
        CGFloat portraitSubtitleX = showLogoIcon ? logoTextX : 14.0;
        CGFloat availableSubtitleWidth = subtitleMaxX - portraitSubtitleX;
        if (availableSubtitleWidth < 96.0) {
            self.headerSubtitleLabel.hidden = YES;
            self.headerSubtitleLabel.frame = CGRectZero;
        } else {
            self.headerSubtitleLabel.frame = CGRectMake(portraitSubtitleX,
                                                        31.0,
                                                        availableSubtitleWidth,
                                                        14.0);
        }
    }
    self.hostBadge.hidden = YES;
}

- (void)_dispatchLayoutUpdateToLoadedTabs {
    CGRect bodyBounds = self.bodyContainer.bounds;
    UIEdgeInsets safeInsets = self.bodyContainer.safeAreaInsets;
    for (UIViewController *controller in self.tabVCs.allValues) {
        if ([controller conformsToProtocol:@protocol(VCPanelLayoutUpdatable)] &&
            [controller respondsToSelector:@selector(vc_applyPanelLayoutMode:availableBounds:safeAreaInsets:)]) {
            [(id<VCPanelLayoutUpdatable>)controller vc_applyPanelLayoutMode:self.layoutMode
                                                            availableBounds:bodyBounds
                                                             safeAreaInsets:safeInsets];
        }
    }
}

#pragma mark - Size

- (void)_onSizeTap:(UIButton *)btn {
    self.sizeMode = (VCPanelSizeMode)btn.tag;
    [self _updateSizeHighlight];
    [self _applySize];
}

- (void)_updateSizeHighlight {
    for (UIButton *btn in self.sizeButtons) {
        BOOL active = (btn.tag == self.sizeMode);
        btn.layer.borderColor = active ? kVCBorderAccent.CGColor : kVCBorder.CGColor;
        [btn setTitleColor:active ? kVCTextPrimary : kVCTextMuted forState:UIControlStateNormal];
        btn.backgroundColor = active ? kVCAccentDim : [kVCBgSurface colorWithAlphaComponent:0.58];
    }
}

- (void)_applySize {
    CGFloat scale = [self _currentScale];
    [UIView animateWithDuration:0.25
                          delay:0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0.5
                        options:0
                     animations:^{
        self.bgView.transform = CGAffineTransformMakeScale(scale, scale);
    } completion:nil];
}

#pragma mark - Focus

- (void)_onDimTap {
    if (self.isFocused) [self _setFocused:NO animated:YES];
}

- (void)_setFocused:(BOOL)focused animated:(BOOL)animated {
    if (self.isFocused == focused) return;
    self.isFocused = focused;
    [self _updateHeaderBadges];

    void (^block)(void) = ^{
        self.dimView.alpha = focused ? 1.0 : 0.0;
        self.bgView.alpha = focused ? 1.0 : 0.3;
    };
    if (animated) {
        [UIView animateWithDuration:0.25 animations:block];
    } else {
        block();
    }
}

#pragma mark - Hit Test + Drag

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01) return nil;

    if (CGRectContainsPoint(self.bgView.frame, point)) {
        if (self.isFocused) {
            CGPoint bgPoint = [self convertPoint:point toView:self.bgView];
            return [self.bgView hitTest:bgPoint withEvent:event];
        }
        return self;
    }

    if (self.isFocused) return self;
    return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:self];
    if (CGRectContainsPoint(self.bgView.frame, point)) {
        CGPoint bgPoint = [self convertPoint:point toView:self.bgView];
        self.dragStart = point;
        self.bgStartCenter = self.bgView.center;
        self.isDragging = (bgPoint.y <= CGRectGetHeight(self.navBar.frame));
        if (!self.isFocused) [self _setFocused:YES animated:YES];
        return;
    }
    if (self.isFocused) [self _setFocused:NO animated:YES];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.isFocused || !self.isDragging) return;
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:self];
    CGFloat dx = point.x - self.dragStart.x;
    CGFloat dy = point.y - self.dragStart.y;
    CGPoint nextCenter = CGPointMake(self.bgStartCenter.x + dx, self.bgStartCenter.y + dy);

    CGFloat halfWidth = CGRectGetWidth(self.bgView.frame) * 0.5;
    CGFloat halfHeight = CGRectGetHeight(self.bgView.frame) * 0.5;
    nextCenter.x = MAX(halfWidth - 50.0, MIN(CGRectGetWidth(self.bounds) - halfWidth + 50.0, nextCenter.x));
    nextCenter.y = MAX(halfHeight - 30.0, MIN(CGRectGetHeight(self.bounds) - halfHeight + 30.0, nextCenter.y));
    self.bgView.center = nextCenter;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.isDragging = NO;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.isDragging = NO;
}

#pragma mark - Lazy Tabs

- (UIViewController *)_createVCForTabIndex:(NSInteger)index {
    switch (index) {
        case VCPanelContentTabIndexChat: return [[VCChatTab alloc] init];
        case VCPanelContentTabIndexInspect: return [[VCInspectTab alloc] init];
        case VCPanelContentTabIndexUI: return [[VCInspectTab alloc] init];
        case VCPanelContentTabIndexNetwork: return [[VCNetworkTab alloc] init];
        case VCPanelContentTabIndexConsole: return [[VCConsoleTab alloc] init];
        case VCPanelContentTabIndexCode: return [[VCWorkspaceHubTab alloc] init];
        case VCPanelContentTabIndexMemory: return [[VCWorkspaceHubTab alloc] init];
        case VCPanelContentTabIndexArtifacts: return [[VCArtifactsTab alloc] init];
        case VCPanelContentTabIndexPatches: return [[VCPatchesTab alloc] init];
        case VCPanelContentTabIndexSettings: return [[VCSettingsTab alloc] init];
        case VCPanelContentTabIndexWorkspaceHub: return [[VCWorkspaceHubTab alloc] init];
        default: return nil;
    }
}

- (void)_switchToTab:(NSInteger)index {
    if (index == self.currentTabIndex) {
        [self _dispatchLayoutUpdateToLoadedTabs];
        return;
    }

    if (self.currentTabIndex >= 0) {
        UIView *oldView = self.tabViews[@(self.currentTabIndex)];
        oldView.hidden = YES;
    }

    self.currentTabIndex = index;
    self.tabBar.selectedIndex = (NSUInteger)VCPanelPrimaryNavigationIndexForContentIndex(index);

    if (!self.tabVCs[@(index)]) {
        UIViewController *controller = [self _createVCForTabIndex:index];
        if (!controller) return;
        self.tabVCs[@(index)] = controller;
        UIView *page = controller.view;
        page.translatesAutoresizingMaskIntoConstraints = NO;
        [self.bodyContainer addSubview:page];
        [NSLayoutConstraint activateConstraints:@[
            [page.topAnchor constraintEqualToAnchor:self.bodyContainer.topAnchor],
            [page.leadingAnchor constraintEqualToAnchor:self.bodyContainer.leadingAnchor],
            [page.trailingAnchor constraintEqualToAnchor:self.bodyContainer.trailingAnchor],
            [page.bottomAnchor constraintEqualToAnchor:self.bodyContainer.bottomAnchor],
        ]];
        self.tabViews[@(index)] = page;
    }

    UIView *view = self.tabViews[@(index)];
    view.hidden = NO;
    [self _dispatchLayoutUpdateToLoadedTabs];
}

#pragma mark - Swipe Navigation

- (void)_onSwipeLeft {
    NSInteger next = (NSInteger)self.tabBar.selectedIndex + 1;
    if (next >= self.totalTabCount) return;
    NSInteger targetContentIndex = [VCPanelPrimaryNavigationTargets()[next] integerValue];
    [self _switchToTab:targetContentIndex];
}

- (void)_onSwipeRight {
    NSInteger previous = (NSInteger)self.tabBar.selectedIndex - 1;
    if (previous < 0) return;
    NSInteger targetContentIndex = [VCPanelPrimaryNavigationTargets()[previous] integerValue];
    [self _switchToTab:targetContentIndex];
}

#pragma mark - VCTabBarDelegate

- (void)tabBar:(id)tabBar didSelectIndex:(NSUInteger)index {
    NSArray<NSNumber *> *targets = VCPanelPrimaryNavigationTargets();
    if (index >= targets.count) return;
    [self _switchToTab:[targets[index] integerValue]];
}

#pragma mark - Notifications

- (void)_handleOpenPatchesEditorRequest:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo ?: @{};
    NSInteger segment = [userInfo[VCPatchesOpenEditorSegmentKey] integerValue];
    BOOL createsItem = [userInfo[VCPatchesOpenEditorCreatesKey] boolValue];
    id item = userInfo[VCPatchesOpenEditorItemKey];

    [self _switchToTab:VCPanelContentTabIndexPatches];

    UIViewController *controller = self.tabVCs[@(VCPanelContentTabIndexPatches)];
    if ([controller isKindOfClass:[VCPatchesTab class]]) {
        [(VCPatchesTab *)controller openEditorForDraftItem:item segmentIndex:segment createsItem:createsItem];
    }
}

- (void)_handleLanguageDidChange {
    [self _updateHeaderBadges];
    NSInteger activeTab = self.currentTabIndex;
    for (UIView *view in self.tabViews.allValues) {
        [view removeFromSuperview];
    }
    [self.tabViews removeAllObjects];
    [self.tabVCs removeAllObjects];
    self.currentTabIndex = -1;
    if (activeTab >= 0) {
        [self _switchToTab:activeTab];
    }
}

- (void)_handleOpenAIChatRequest {
    [self _switchToTab:VCPanelContentTabIndexChat];
}

- (void)_handleOpenMemoryAddressRequest:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo ?: @{};
    NSString *address = [userInfo[VCMemoryBrowserOpenAddressKey] isKindOfClass:[NSString class]] ? userInfo[VCMemoryBrowserOpenAddressKey] : @"";
    if (address.length == 0) return;

    [self _switchToTab:VCPanelContentTabIndexWorkspaceHub];
}

- (void)_handleOpenCodeFileRequest:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo ?: @{};
    NSString *path = [userInfo[VCCodeTabOpenFilePathKey] isKindOfClass:[NSString class]] ? userInfo[VCCodeTabOpenFilePathKey] : @"";
    if (path.length == 0) return;

    [self _switchToTab:VCPanelContentTabIndexWorkspaceHub];
}

- (void)_handleOpenArtifactsRequest:(NSNotification *)notification {
    NSDictionary *userInfo = [notification.userInfo isKindOfClass:[NSDictionary class]] ? notification.userInfo : @{};
    NSString *modeName = [userInfo[VCArtifactsOpenModeKey] isKindOfClass:[NSString class]] ? userInfo[VCArtifactsOpenModeKey] : @"";
    [self _switchToTab:VCPanelContentTabIndexArtifacts];

    UIViewController *controller = self.tabVCs[@(VCPanelContentTabIndexArtifacts)];
    if ([controller isKindOfClass:[VCArtifactsTab class]]) {
        [(VCArtifactsTab *)controller openArtifactsModeNamed:modeName];
    }
}

- (void)_handleWorkspaceHubOpenSectionRequest:(NSNotification *)notification {
    NSDictionary *userInfo = [notification.userInfo isKindOfClass:[NSDictionary class]] ? notification.userInfo : @{};
    NSString *section = [userInfo[VCWorkspaceHubSectionKey] isKindOfClass:[NSString class]] ? userInfo[VCWorkspaceHubSectionKey] : @"";
    [self _switchToTab:VCPanelContentIndexForWorkspaceSection(section)];
}

#pragma mark - Show / Hide

- (void)showAnimated {
    if (self.visible) {
        if (!self.isFocused) [self _setFocused:YES animated:YES];
        return;
    }

    [[VCOverlayWindow shared] beginInteractiveSession];
    self.visible = YES;
    self.hidden = NO;
    [self _relayoutForGeometryChangeAnimated:NO];

    self.bgView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    self.bgView.alpha = 0.0;
    self.dimView.alpha = 0.0;
    self.isFocused = YES;

    if (self.currentTabIndex < 0) {
        [self _switchToTab:VCPanelContentTabIndexChat];
    } else {
        [self _dispatchLayoutUpdateToLoadedTabs];
    }

    [self _updateHeaderBadges];

    CGFloat scale = [self _currentScale];
    [UIView animateWithDuration:0.3
                          delay:0
         usingSpringWithDamping:0.8
          initialSpringVelocity:0.5
                        options:0
                     animations:^{
        self.bgView.transform = CGAffineTransformMakeScale(scale, scale);
        self.bgView.alpha = 1.0;
        self.dimView.alpha = 1.0;
    } completion:nil];
}

- (void)hideAnimated {
    if (!self.visible) return;
    self.visible = NO;

    [UIView animateWithDuration:0.2 animations:^{
        self.bgView.alpha = 0.0;
        self.dimView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.hidden = YES;
        self.isFocused = NO;
        [self _updateHeaderBadges];
        [[VCOverlayWindow shared] endInteractiveSession];
    }];
}

- (BOOL)isVisible {
    return self.visible;
}

- (void)_updateHeaderBadges {
    NSString *hostText = [VCConfig shared].targetDisplayName.length ? [VCConfig shared].targetDisplayName : [VCConfig shared].targetBundleID;
    NSString *versionText = [VCConfig shared].targetVersion.length ? [NSString stringWithFormat:@"v%@", [VCConfig shared].targetVersion] : @"";
    NSString *subtitleText = hostText.length ? hostText : VCTextLiteral(@"Injected process cockpit");
    if (versionText.length > 0) {
        subtitleText = [NSString stringWithFormat:@"%@ • %@", subtitleText, versionText];
    }
    self.headerSubtitleLabel.text = subtitleText;
    self.hostBadge.hidden = YES;

    NSString *statusText = self.isFocused ? VCTextLiteral(@"Focused") : VCTextLiteral(@"Attached");
    self.statusBadge.text = statusText;
    self.statusBadge.textColor = self.isFocused ? kVCGreen : kVCYellow;
    self.statusBadge.backgroundColor = self.isFocused ? kVCGreenDim : [kVCYellow colorWithAlphaComponent:0.14];
    self.statusBadge.layer.borderColor = (self.isFocused
        ? [kVCGreen colorWithAlphaComponent:0.34]
        : [kVCYellow colorWithAlphaComponent:0.24]).CGColor;
}

@end
