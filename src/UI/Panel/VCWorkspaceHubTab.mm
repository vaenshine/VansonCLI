/**
 * VCWorkspaceHubTab -- secondary workspace launcher for low-frequency tools
 */

#import "VCWorkspaceHubTab.h"
#import "../Artifacts/VCArtifactsTab.h"
#import "../../Core/VCConfig.h"
#import "../../Patches/VCPatchManager.h"
#import "../../../VansonCLI.h"

NSNotificationName const VCWorkspaceHubRequestOpenSectionNotification = @"VCWorkspaceHubRequestOpenSectionNotification";
NSString *const VCWorkspaceHubSectionKey = @"section";

static NSString *VCWorkspaceHubSectionIcon(NSString *section) {
    if ([section isEqualToString:@"chat"]) return @"sparkles";
    if ([section isEqualToString:@"inspect"]) return @"waveform.path.ecg.rectangle";
    if ([section isEqualToString:@"network"]) return @"network";
    if ([section isEqualToString:@"console"]) return @"terminal";
    if ([section isEqualToString:@"diagnostics"]) return @"waveform.path.ecg";
    if ([section isEqualToString:@"artifacts"]) return @"archivebox";
    if ([section isEqualToString:@"patches"]) return @"wrench.and.screwdriver";
    if ([section isEqualToString:@"settings"]) return @"cpu";
    return @"square.grid.2x2";
}

static NSString *VCWorkspaceHubSectionTitle(NSString *section) {
    if ([section isEqualToString:@"chat"]) return VCTextLiteral(@"AI Chat");
    if ([section isEqualToString:@"inspect"]) return VCTextLiteral(@"Inspect");
    if ([section isEqualToString:@"network"]) return VCTextLiteral(@"Network");
    if ([section isEqualToString:@"console"]) return VCTextLiteral(@"Console");
    if ([section isEqualToString:@"diagnostics"]) return VCTextLiteral(@"Chat Diagnostics");
    if ([section isEqualToString:@"artifacts"]) return VCTextLiteral(@"Artifacts");
    if ([section isEqualToString:@"patches"]) return VCTextLiteral(@"Patches");
    if ([section isEqualToString:@"settings"]) return VCTextLiteral(@"OpenAI Setup");
    return VCTextLiteral(@"Workspace");
}

static NSString *VCWorkspaceHubSectionSummary(NSString *section) {
    if ([section isEqualToString:@"chat"]) return VCTextLiteral(@"Runtime agent with context chips and tool calls.");
    if ([section isEqualToString:@"inspect"]) return VCTextLiteral(@"Members, UI picks, strings, instances, and process data.");
    if ([section isEqualToString:@"network"]) return VCTextLiteral(@"Capture traffic, replay requests, and manage rules.");
    if ([section isEqualToString:@"console"]) return VCTextLiteral(@"Command history and quick aliases.");
    if ([section isEqualToString:@"diagnostics"]) return VCTextLiteral(@"Chat request timeline and latency rollups.");
    if ([section isEqualToString:@"artifacts"]) return VCTextLiteral(@"Traces, diagrams, snapshots, and captures.");
    if ([section isEqualToString:@"patches"]) return VCTextLiteral(@"Value locks, hooks, rules, and patch drafts.");
    if ([section isEqualToString:@"settings"]) return VCTextLiteral(@"OpenAI key, endpoint, model, language, and about.");
    return VCTextLiteral(@"Secondary tools");
}

static NSString *VCWorkspaceHubSectionCTA(NSString *section) {
    return @"›";
}

static UILabel *VCWorkspaceHubPill(NSString *text, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = color ?: kVCTextPrimary;
    label.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
    label.backgroundColor = [(color ?: kVCAccent) colorWithAlphaComponent:0.12];
    label.layer.cornerRadius = 10.0;
    label.layer.borderWidth = 1.0;
    label.layer.borderColor = [(color ?: kVCAccent) colorWithAlphaComponent:0.24].CGColor;
    label.clipsToBounds = YES;
    VCPrepareSingleLineLabel(label, NSLineBreakByTruncatingTail);
    [label.heightAnchor constraintEqualToConstant:22.0].active = YES;
    return label;
}

static UIView *VCWorkspaceHubInfoCard(NSString *title, NSArray<NSString *> *rows) {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    VCApplyPanelSurface(card, 12.0);

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 7.0;
    [card addSubview:stack];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    titleLabel.textColor = kVCTextPrimary;
    VCPrepareSingleLineLabel(titleLabel, NSLineBreakByTruncatingTail);
    [stack addArrangedSubview:titleLabel];

    for (NSString *row in rows ?: @[]) {
        UILabel *rowLabel = [[UILabel alloc] init];
        rowLabel.text = row;
        rowLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
        rowLabel.textColor = kVCTextSecondary;
        VCPrepareSingleLineLabel(rowLabel, NSLineBreakByTruncatingTail);
        [stack addArrangedSubview:rowLabel];
    }

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:12.0],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12.0],
    ]];
    return card;
}

@interface VCWorkspaceHubCardButton : UIButton
@property (nonatomic, copy) NSString *section;
@property (nonatomic, strong) UILabel *titleLabelView;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UILabel *ctaLabel;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) NSLayoutConstraint *minHeightConstraint;
- (void)configureWithSection:(NSString *)section;
@end

@implementation VCWorkspaceHubCardButton

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        VCApplyPanelSurface(self, 12.0);
        self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
        self.clipsToBounds = YES;

        UIImageView *iconView = [[UIImageView alloc] init];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.tintColor = kVCAccent;
        [self addSubview:iconView];
        self.iconView = iconView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        titleLabel.textColor = kVCTextPrimary;
        titleLabel.numberOfLines = 1;
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:titleLabel];
        self.titleLabelView = titleLabel;

        UILabel *summaryLabel = [[UILabel alloc] init];
        summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        summaryLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
        summaryLabel.textColor = kVCTextMuted;
        summaryLabel.numberOfLines = 2;
        summaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:summaryLabel];
        self.summaryLabel = summaryLabel;

        UILabel *ctaLabel = [[UILabel alloc] init];
        ctaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        ctaLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
        ctaLabel.textColor = kVCAccentHover;
        ctaLabel.numberOfLines = 1;
        ctaLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:ctaLabel];
        self.ctaLabel = ctaLabel;

        [NSLayoutConstraint activateConstraints:@[
            [iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14.0],
            [iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:14.0],
            [iconView.widthAnchor constraintEqualToConstant:24.0],
            [iconView.heightAnchor constraintEqualToConstant:24.0],

            [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:14.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10.0],
            [titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14.0],

            [summaryLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6.0],
            [summaryLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
            [summaryLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14.0],
            [summaryLabel.bottomAnchor constraintLessThanOrEqualToAnchor:ctaLabel.topAnchor constant:-8.0],

            [ctaLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
            [ctaLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14.0],
            [ctaLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-14.0],
        ]];

        self.minHeightConstraint = [self.heightAnchor constraintGreaterThanOrEqualToConstant:92.0];
        self.minHeightConstraint.active = YES;
    }
    return self;
}

- (void)configureWithSection:(NSString *)section {
    self.section = section ?: @"";
    self.iconView.image = [UIImage systemImageNamed:VCWorkspaceHubSectionIcon(self.section)];
    self.titleLabelView.text = VCWorkspaceHubSectionTitle(self.section);
    self.summaryLabel.text = VCWorkspaceHubSectionSummary(self.section);
    self.ctaLabel.text = VCWorkspaceHubSectionCTA(self.section);
}

@end

@interface VCWorkspaceHubTab ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIStackView *cardGrid;
@property (nonatomic, strong) NSArray<VCWorkspaceHubCardButton *> *cards;
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) UIView *activityCard;
@property (nonatomic, strong) UIView *contextCard;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@property (nonatomic, assign) BOOL compactLandscape;
@property (nonatomic, assign) NSUInteger gridColumnCount;
@property (nonatomic, assign) CGFloat lastGridWidth;
@end

@implementation VCWorkspaceHubTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;
    self.currentLayoutMode = VCPanelLayoutModePortrait;

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;

    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 12.0;
    [scrollView addSubview:contentStack];
    self.contentStack = contentStack;

    UIView *heroCard = [[UIView alloc] init];
    heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    VCApplyPanelSurface(heroCard, 12.0);
    [contentStack addArrangedSubview:heroCard];
    self.heroCard = heroCard;

    UILabel *eyebrowLabel = [[UILabel alloc] init];
    eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
    eyebrowLabel.textColor = kVCTextSecondary;
    eyebrowLabel.text = VCTextLiteral(@"WORKSPACE");
    [heroCard addSubview:eyebrowLabel];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    titleLabel.textColor = kVCTextPrimary;
    titleLabel.numberOfLines = 1;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    NSString *targetName = [VCConfig shared].targetDisplayName.length ? [VCConfig shared].targetDisplayName : [VCConfig shared].targetBundleID;
    titleLabel.text = targetName.length > 0 ? [NSString stringWithFormat:@"%@ %@", targetName, VCTextLiteral(@"Attached")] : VCTextLiteral(@"Workspace");
    [heroCard addSubview:titleLabel];

    UILabel *summaryLabel = [[UILabel alloc] init];
    summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    summaryLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    summaryLabel.textColor = kVCTextMuted;
    summaryLabel.numberOfLines = 2;
    summaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    NSString *bundleID = [VCConfig shared].targetBundleID.length ? [VCConfig shared].targetBundleID : [[NSBundle mainBundle] bundleIdentifier];
    summaryLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Process %@ · PID %@ · %@"),
                         bundleID.length > 0 ? bundleID : @"--",
                         @([[NSProcessInfo processInfo] processIdentifier]),
                         [VCConfig shared].targetVersion.length ? [NSString stringWithFormat:@"v%@", [VCConfig shared].targetVersion] : VCTextLiteral(@"runtime")];
    [heroCard addSubview:summaryLabel];

    VCPatchManager *patchManager = [VCPatchManager shared];
    UIStackView *metricStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        VCWorkspaceHubPill(VCTextLiteral(@"GPT-5.5"), kVCAccent),
        VCWorkspaceHubPill([NSString stringWithFormat:VCTextLiteral(@"%lu Rules"), (unsigned long)[patchManager allRules].count], kVCGreen),
        VCWorkspaceHubPill([NSString stringWithFormat:VCTextLiteral(@"%lu Patches"), (unsigned long)[patchManager allPatches].count], kVCYellow),
        VCWorkspaceHubPill([NSString stringWithFormat:VCTextLiteral(@"%lu Watches"), (unsigned long)[patchManager allValues].count], [UIColor colorWithRed:0.72 green:0.42 blue:1.0 alpha:1.0])
    ]];
    metricStack.translatesAutoresizingMaskIntoConstraints = NO;
    metricStack.axis = UILayoutConstraintAxisHorizontal;
    metricStack.distribution = UIStackViewDistributionFillEqually;
    metricStack.spacing = 8.0;
    [heroCard addSubview:metricStack];

    [NSLayoutConstraint activateConstraints:@[
        [eyebrowLabel.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:12.0],
        [eyebrowLabel.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:14.0],
        [eyebrowLabel.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-14.0],

        [titleLabel.topAnchor constraintEqualToAnchor:eyebrowLabel.bottomAnchor constant:5.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:eyebrowLabel.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-14.0],

        [summaryLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6.0],
        [summaryLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [summaryLabel.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-14.0],
        [metricStack.topAnchor constraintEqualToAnchor:summaryLabel.bottomAnchor constant:10.0],
        [metricStack.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [metricStack.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-14.0],
        [metricStack.bottomAnchor constraintEqualToAnchor:heroCard.bottomAnchor constant:-12.0],
    ]];

    UIStackView *cardGrid = [[UIStackView alloc] init];
    cardGrid.translatesAutoresizingMaskIntoConstraints = NO;
    cardGrid.axis = UILayoutConstraintAxisVertical;
    cardGrid.spacing = 12.0;
    [contentStack addArrangedSubview:cardGrid];
    self.cardGrid = cardGrid;

    NSMutableArray<VCWorkspaceHubCardButton *> *cards = [NSMutableArray new];
    for (NSString *section in @[ @"settings", @"artifacts", @"patches", @"console", @"diagnostics" ]) {
        VCWorkspaceHubCardButton *button = [[VCWorkspaceHubCardButton alloc] initWithFrame:CGRectZero];
        [button configureWithSection:section];
        [button addTarget:self action:@selector(_openSection:) forControlEvents:UIControlEventTouchUpInside];
        [cards addObject:button];
    }
    self.cards = [cards copy];

    self.activityCard = VCWorkspaceHubInfoCard(VCTextLiteral(@"Recent Activity"), @[
        VCTextLiteral(@"Picked UI view • AWEFeedVideoButton"),
        VCTextLiteral(@"Installed hook • layoutSubviews"),
        VCTextLiteral(@"Captured request • /aweme/v1/feed")
    ]);
    [contentStack addArrangedSubview:self.activityCard];
    self.contextCard = VCWorkspaceHubInfoCard(VCTextLiteral(@"Pinned Context"), @[
        VCTextLiteral(@"UI · AWEFeedVideoButton"),
        VCTextLiteral(@"Class · AWEFeedVideoButton"),
        VCTextLiteral(@"Network · POST /feed")
    ]);
    [contentStack addArrangedSubview:self.contextCard];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [contentStack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:10.0],
        [contentStack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor constant:12.0],
        [contentStack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor constant:-12.0],
        [contentStack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-10.0],
        [contentStack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor constant:-24.0],
    ]];

    [self _rebuildCardGrid];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    NSUInteger columns = [self _desiredColumnCountForWidth:width];
    if (columns != self.gridColumnCount || fabs(width - self.lastGridWidth) > 8.0) {
        self.gridColumnCount = columns;
        self.lastGridWidth = width;
        [self _rebuildCardGrid];
    }
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    self.compactLandscape = mode == VCPanelLayoutModeLandscape && CGRectGetHeight(bounds) < 320.0;
    self.gridColumnCount = 0;
    [self _rebuildCardGrid];
}

- (NSUInteger)_desiredColumnCountForWidth:(CGFloat)width {
    if (self.compactLandscape) {
        if (width >= 520.0) return 4;
        if (width >= 360.0) return 3;
        if (width >= 240.0) return 2;
        return 1;
    }
    if (width >= 680.0) return 4;
    if (width >= 520.0) return 3;
    if (width >= 300.0) return 2;
    return 1;
}

- (void)_rebuildCardGrid {
    for (UIView *view in [self.cardGrid.arrangedSubviews copy]) {
        [self.cardGrid removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    CGFloat width = CGRectGetWidth(self.view.bounds);
    NSUInteger columns = self.gridColumnCount > 0 ? self.gridColumnCount : [self _desiredColumnCountForWidth:width];
    BOOL dense = columns >= 4;
    BOOL landscape = self.currentLayoutMode == VCPanelLayoutModeLandscape;
    self.contentStack.spacing = self.compactLandscape ? 8.0 : 12.0;
    self.contentStack.distribution = landscape ? UIStackViewDistributionEqualSpacing : UIStackViewDistributionFill;
    self.cardGrid.spacing = self.compactLandscape ? 8.0 : 12.0;
    self.cardGrid.distribution = UIStackViewDistributionFill;
    self.heroCard.hidden = self.compactLandscape;
    self.activityCard.hidden = self.compactLandscape;
    self.contextCard.hidden = self.compactLandscape;
    CGFloat rowHeight = self.compactLandscape
        ? (dense ? 88.0 : 96.0)
        : (landscape ? (dense ? 154.0 : 166.0) : (dense ? 132.0 : 124.0));
    if (columns <= 1) {
        for (VCWorkspaceHubCardButton *button in self.cards) {
            [self.cardGrid addArrangedSubview:button];
        }
    } else {
        for (NSUInteger idx = 0; idx < self.cards.count; idx += columns) {
            UIStackView *row = [[UIStackView alloc] init];
            row.translatesAutoresizingMaskIntoConstraints = NO;
            row.axis = UILayoutConstraintAxisHorizontal;
            row.distribution = UIStackViewDistributionFillEqually;
            row.spacing = columns >= 4 ? 8.0 : 10.0;
            [self.cardGrid addArrangedSubview:row];
            [row.heightAnchor constraintEqualToConstant:rowHeight].active = YES;

            NSUInteger rowEnd = MIN(idx + columns, self.cards.count);
            for (NSUInteger cardIndex = idx; cardIndex < rowEnd; cardIndex++) {
                [row addArrangedSubview:self.cards[cardIndex]];
            }
            for (NSUInteger filler = rowEnd - idx; filler < columns; filler++) {
                UIView *spacer = [[UIView alloc] init];
                spacer.translatesAutoresizingMaskIntoConstraints = NO;
                [row addArrangedSubview:spacer];
            }
        }
    }

    for (VCWorkspaceHubCardButton *button in self.cards) {
        if (self.compactLandscape) {
            button.minHeightConstraint.constant = dense ? 86.0 : 92.0;
            button.titleLabelView.font = [UIFont systemFontOfSize:(dense ? 10.8 : 11.6) weight:UIFontWeightBold];
            button.summaryLabel.font = [UIFont systemFontOfSize:9.2 weight:UIFontWeightMedium];
            button.summaryLabel.numberOfLines = 1;
            button.ctaLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
        } else if (landscape) {
            button.minHeightConstraint.constant = rowHeight;
            button.titleLabelView.font = [UIFont systemFontOfSize:(dense ? 13.0 : 13.5) weight:UIFontWeightBold];
            button.summaryLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
            button.summaryLabel.numberOfLines = 2;
            button.ctaLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
        } else {
            button.minHeightConstraint.constant = dense ? 132.0 : 124.0;
            button.titleLabelView.font = [UIFont systemFontOfSize:(dense ? 12.0 : 13.5) weight:UIFontWeightBold];
            button.summaryLabel.font = [UIFont systemFontOfSize:(dense ? 10.0 : 11.0) weight:UIFontWeightMedium];
            button.summaryLabel.numberOfLines = 2;
            button.ctaLabel.font = [UIFont systemFontOfSize:(dense ? 18.0 : 17.0) weight:UIFontWeightBold];
        }
    }
}

- (void)_openSection:(VCWorkspaceHubCardButton *)sender {
    NSString *section = sender.section ?: @"";
    if ([section isEqualToString:@"diagnostics"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:VCArtifactsRequestOpenModeNotification
                                                            object:self
                                                          userInfo:@{
            VCArtifactsOpenModeKey: VCArtifactsOpenModeDiagnosticsValue
        }];
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:VCWorkspaceHubRequestOpenSectionNotification
                                                        object:self
                                                      userInfo:@{
        VCWorkspaceHubSectionKey: section
    }];
}

@end
