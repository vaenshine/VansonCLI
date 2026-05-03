/**
 * VCChatTab -- AI Chat Tab
 * Message list + input bar + model selector + streaming response
 */

#import "VCChatTab.h"
#import "VCChatBubble.h"
#import "VCToolCallBlock.h"
#import "VCModelSelector.h"
#import "../Panel/VCPanel.h"
#import "../Artifacts/VCArtifactsTab.h"
#import "../../../VansonCLI.h"
#import "../../AI/Chat/VCAIEngine.h"
#import "../../AI/Chat/VCChatDiagnostics.h"
#import "../../AI/Chat/VCChatSession.h"
#import "../../AI/Chat/VCMessage.h"
#import "../../AI/TokenManager/VCTokenTracker.h"
#import "../../AI/ToolCall/VCToolCallParser.h"
#import "../../AI/Models/VCProviderManager.h"
#import "../../AI/Context/VCContextCollector.h"
#import "../../Core/VCCapabilityManager.h"
#import "../../Core/VCConfig.h"

static NSString *const kBubbleCellID = @"BubbleCell";

static NSString *VCChatReferenceChipIconName(NSString *kind) {
    NSString *lower = [[kind ?: @"" lowercaseString] copy];
    if ([lower isEqualToString:@"ui"]) return @"square.on.square";
    if ([lower isEqualToString:@"network"]) return @"network";
    if ([lower isEqualToString:@"inspect"]) return @"cpu";
    if ([lower isEqualToString:@"diagram"]) return @"point.3.connected.trianglepath.dotted";
    return @"paperclip";
}

static void VCChatPrepareButtonTitle(UIButton *button, NSLineBreakMode mode, CGFloat minimumScale) {
    button.titleLabel.numberOfLines = 1;
    button.titleLabel.lineBreakMode = mode;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = minimumScale;
    [button setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
}

static void VCChatPrepareSingleLineLabel(UILabel *label, NSLineBreakMode mode) {
    label.numberOfLines = 1;
    label.lineBreakMode = mode;
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
}

@interface VCChatTab () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, VCPanelLayoutUpdatable>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *topBarView;
@property (nonatomic, strong) UIView *workspaceView;
@property (nonatomic, strong) UIView *conversationColumnView;
@property (nonatomic, strong) UIView *contextRailView;
@property (nonatomic, strong) UIView *sidebarDividerView;
@property (nonatomic, strong) UIView *contextRailDividerView;
@property (nonatomic, strong) UIView *contextSummaryCard;
@property (nonatomic, strong) UIView *referenceRailCard;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UIView *composerCard;
@property (nonatomic, strong) UITextView *inputTextView;
@property (nonatomic, strong) UILabel *inputPlaceholderLabel;
@property (nonatomic, strong) UIScrollView *referenceScrollView;
@property (nonatomic, strong) UIStackView *referenceStack;
@property (nonatomic, strong) UILabel *contextSummaryTitleLabel;
@property (nonatomic, strong) UILabel *contextSummaryBodyLabel;
@property (nonatomic, strong) UILabel *contextSummaryMetaLabel;
@property (nonatomic, strong) UIButton *contextModelButton;
@property (nonatomic, strong) UIButton *contextClearButton;
@property (nonatomic, strong) UIButton *contextDiagnosticsButton;
@property (nonatomic, strong) UILabel *referenceRailTitleLabel;
@property (nonatomic, strong) UILabel *referenceRailSubtitleLabel;
@property (nonatomic, strong) UIScrollView *referenceRailScrollView;
@property (nonatomic, strong) UIStackView *referenceRailStack;
@property (nonatomic, strong) UILabel *referenceRailEmptyLabel;
@property (nonatomic, strong) NSLayoutConstraint *referenceStripHeight;
@property (nonatomic, strong) NSLayoutConstraint *inputTextHeightConstraint;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *modelButton;
@property (nonatomic, strong) UIButton *clearChatButton;
@property (nonatomic, strong) UIButton *diagnosticsButton;
@property (nonatomic, strong) UIProgressView *tokenBar;
@property (nonatomic, strong) UILabel *tokenLabel;
@property (nonatomic, strong) UILabel *sessionStateLabel;
@property (nonatomic, strong) UILabel *statusPhaseLabel;
@property (nonatomic, strong) UILabel *statusHeadlineLabel;
@property (nonatomic, strong) UILabel *statusDetailLabel;
@property (nonatomic, strong) UILabel *composerTitleLabel;
@property (nonatomic, strong) UILabel *toolsChipLabel;
@property (nonatomic, strong) UILabel *contextChipLabel;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIStackView *quickCommandStack;
@property (nonatomic, strong) NSLayoutConstraint *topBarHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tokenBarWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *inputBarMinHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *inputBarPreferredHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sendButtonWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *referenceTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *inputSurfaceTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *workspaceTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *workspaceTopToViewConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contextRailWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contextRailSpacingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *modelButtonTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sessionStateTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *statusPhaseCenterYConstraint;
@property (nonatomic, strong) NSLayoutConstraint *statusHeadlineTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *statusDetailTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tokenLabelTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tokenBarTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *clearButtonBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tableBottomToInputConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tableBottomToConversationBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *referenceRailBottomToContextConstraint;
@property (nonatomic, strong) NSLayoutConstraint *referenceRailBottomToInputConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contextRailDividerTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contextRailDividerBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *referenceRailScrollTopToSubtitleConstraint;
@property (nonatomic, strong) NSLayoutConstraint *referenceRailScrollTopToTitleConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contextSummaryTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *referenceRailTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *inputSurfaceTopToComposerConstraint;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *inputBarConversationConstraints;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *inputBarRailConstraints;
@property (nonatomic, strong) NSArray<VCMessage *> *messages;
@property (nonatomic, strong) NSString *streamingText;
@property (nonatomic, strong) NSLayoutConstraint *inputBarBottom;
@property (nonatomic, copy) NSString *transientStatusText;
@property (nonatomic, strong) UIColor *transientStatusColor;
@property (nonatomic, strong) NSMutableSet<NSString *> *revealedMessageIDs;
@property (nonatomic, assign) BOOL hasAnimatedStreamingBubble;
@property (nonatomic, assign) BOOL streamingRefreshScheduled;
@property (nonatomic, assign) BOOL stopRequested;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@property (nonatomic, assign) CGRect availableLayoutBounds;
@property (nonatomic, strong) UIView *diagnosticsOverlayView;
@property (nonatomic, strong) UIView *diagnosticsCardView;
@property (nonatomic, strong) UILabel *diagnosticsSummaryLabel;
@property (nonatomic, strong) UITextView *diagnosticsTextView;
@property (nonatomic, assign) NSUInteger suppressedSessionNotificationCount;
@property (nonatomic, strong) NSTimer *controlInboxTimer;
@property (nonatomic, copy) NSString *lastControlCommandID;
@end

@implementation VCChatTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;
    _messages = @[];
    _streamingText = nil;
	    _revealedMessageIDs = [NSMutableSet new];
	    _hasAnimatedStreamingBubble = NO;
	    _streamingRefreshScheduled = NO;
	    _currentLayoutMode = VCPanelLayoutModePortrait;
    _availableLayoutBounds = CGRectZero;

    [self _setupTokenBar];
    [self _setupWorkspaceShell];
    [self _setupTableView];
    [self _setupContextRail];
    [self _setupInputBar];
    [self _setupEmptyStateView];
    [self _reloadMessages];
    VCInstallKeyboardDismissAccessory(self.view);
    [self _refreshProviderDisplay];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_pendingReferencesChanged)
                                                 name:VCChatPendingReferencesDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_providerChanged)
                                                 name:VCProviderManagerDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_languageChanged)
                                                 name:VCLanguageDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_diagnosticsDidUpdate:)
                                                 name:VCChatDiagnosticsDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_chatSessionDidChange:)
                                                 name:VCChatSessionDidChangeNotification object:nil];
    [self _startControlInboxPolling];
}

- (void)dealloc {
    [self.controlInboxTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self _refreshProviderDisplay];
    [self _updateSessionStateDisplay];
    [self _refreshDiagnosticsView];
}

- (UIView *)_makeRailCardView {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    VCApplyPanelSurface(card, 12.0);
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.06;
    card.layer.shadowRadius = 10.0;
    card.layer.shadowOffset = CGSizeMake(0, 4.0);
    return card;
}

- (void)_applyWorkbenchChromeToContainer:(UIView *)container enabled:(BOOL)enabled {
    if (!container) return;
    if (enabled) {
        VCApplyPanelSurface(container, 14.0);
        container.layer.shadowColor = [UIColor blackColor].CGColor;
        container.layer.shadowOpacity = 0.06;
        container.layer.shadowRadius = 10.0;
        container.layer.shadowOffset = CGSizeMake(0, 4.0);
        container.clipsToBounds = YES;
    } else {
        container.backgroundColor = [UIColor clearColor];
        container.layer.cornerRadius = 0.0;
        container.layer.borderWidth = 0.0;
        container.layer.borderColor = UIColor.clearColor.CGColor;
        container.layer.shadowOpacity = 0.0;
        container.layer.shadowRadius = 0.0;
        container.layer.shadowOffset = CGSizeZero;
        container.clipsToBounds = NO;
    }
}

- (void)_applySectionChromeToView:(UIView *)view flattened:(BOOL)flattened {
    if (!view) return;
    if (flattened) {
        view.backgroundColor = [UIColor clearColor];
        view.layer.cornerRadius = 0.0;
        view.layer.borderWidth = 0.0;
        view.layer.borderColor = UIColor.clearColor.CGColor;
        view.layer.shadowOpacity = 0.0;
        view.layer.shadowRadius = 0.0;
        view.layer.shadowOffset = CGSizeZero;
    } else {
        VCApplyPanelSurface(view, 12.0);
        view.layer.shadowColor = [UIColor blackColor].CGColor;
        view.layer.shadowOpacity = 0.06;
        view.layer.shadowRadius = 10.0;
        view.layer.shadowOffset = CGSizeMake(0, 4.0);
    }
}

- (void)_setupWorkspaceShell {
    self.workspaceView = [[UIView alloc] init];
    self.workspaceView.backgroundColor = [UIColor clearColor];
    self.workspaceView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.workspaceView];

    self.conversationColumnView = [[UIView alloc] init];
    self.conversationColumnView.backgroundColor = [UIColor clearColor];
    self.conversationColumnView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.workspaceView addSubview:self.conversationColumnView];

    self.contextRailView = [[UIView alloc] init];
    self.contextRailView.backgroundColor = [UIColor clearColor];
    self.contextRailView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.workspaceView addSubview:self.contextRailView];

    self.contextRailDividerView = [[UIView alloc] init];
    self.contextRailDividerView.backgroundColor = [kVCBorderStrong colorWithAlphaComponent:0.34];
    self.contextRailDividerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contextRailView addSubview:self.contextRailDividerView];

    self.sidebarDividerView = [[UIView alloc] init];
    self.sidebarDividerView.backgroundColor = [kVCBorderStrong colorWithAlphaComponent:0.38];
    self.sidebarDividerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.workspaceView addSubview:self.sidebarDividerView];

    self.workspaceTopConstraint = [self.workspaceView.topAnchor constraintEqualToAnchor:self.topBarView.bottomAnchor constant:8.0];
    self.workspaceTopToViewConstraint = [self.workspaceView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8.0];
    self.contextRailWidthConstraint = [self.contextRailView.widthAnchor constraintEqualToConstant:0.0];
    self.contextRailSpacingConstraint = [self.contextRailView.leadingAnchor constraintEqualToAnchor:self.conversationColumnView.trailingAnchor constant:0.0];

    [NSLayoutConstraint activateConstraints:@[
        self.workspaceTopConstraint,
        [self.workspaceView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10.0],
        [self.workspaceView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10.0],
        [self.workspaceView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-6.0],

        [self.conversationColumnView.leadingAnchor constraintEqualToAnchor:self.workspaceView.leadingAnchor],
        [self.conversationColumnView.topAnchor constraintEqualToAnchor:self.workspaceView.topAnchor],
        [self.conversationColumnView.bottomAnchor constraintEqualToAnchor:self.workspaceView.bottomAnchor],

        [self.sidebarDividerView.leadingAnchor constraintEqualToAnchor:self.conversationColumnView.trailingAnchor constant:5.0],
        [self.sidebarDividerView.trailingAnchor constraintEqualToAnchor:self.contextRailView.leadingAnchor constant:-5.0],
        [self.sidebarDividerView.widthAnchor constraintEqualToConstant:1.0],
        [self.sidebarDividerView.topAnchor constraintEqualToAnchor:self.workspaceView.topAnchor constant:4.0],
        [self.sidebarDividerView.bottomAnchor constraintEqualToAnchor:self.workspaceView.bottomAnchor constant:-4.0],

        self.contextRailSpacingConstraint,
        [self.contextRailView.trailingAnchor constraintEqualToAnchor:self.workspaceView.trailingAnchor],
        [self.contextRailView.topAnchor constraintEqualToAnchor:self.workspaceView.topAnchor],
        [self.contextRailView.bottomAnchor constraintEqualToAnchor:self.workspaceView.bottomAnchor],
        self.contextRailWidthConstraint,
    ]];
    self.workspaceTopToViewConstraint.active = NO;
    self.sidebarDividerView.hidden = YES;
    self.sidebarDividerView.alpha = 0.0;
    self.contextRailDividerView.hidden = YES;
    self.contextRailDividerView.alpha = 0.0;
}

- (void)_setupTokenBar {
    UIView *topBar = [[UIView alloc] init];
    self.topBarView = topBar;
    VCApplyPanelSurface(topBar, 12.0);
    topBar.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.96];
    topBar.layer.shadowColor = [UIColor blackColor].CGColor;
    topBar.layer.shadowOpacity = 0.07;
    topBar.layer.shadowRadius = 10.0;
    topBar.layer.shadowOffset = CGSizeMake(0, 4.0);
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:topBar];

    _modelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    VCProviderConfig *active = [[VCProviderManager shared] activeProvider];
    NSString *modelTitle = active ? (active.selectedModel ?: @"--") : VCTextLiteral(@"No Provider");
    [_modelButton setTitle:modelTitle forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(_modelButton);
    _modelButton.titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    VCChatPrepareButtonTitle(_modelButton, NSLineBreakByTruncatingMiddle, 0.82);
    _modelButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    _modelButton.contentEdgeInsets = UIEdgeInsetsMake(6, 8, 6, 8);
    [_modelButton addTarget:self action:@selector(_showModelSelector) forControlEvents:UIControlEventTouchUpInside];
    _modelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:_modelButton];

    _clearChatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_clearChatButton setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    VCApplyCompactDangerButtonStyle(_clearChatButton);
    _clearChatButton.accessibilityLabel = VCTextLiteral(@"Clear Chat");
    [_clearChatButton addTarget:self action:@selector(_confirmClearChat) forControlEvents:UIControlEventTouchUpInside];
    _clearChatButton.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:_clearChatButton];

    _diagnosticsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_diagnosticsButton setImage:[UIImage systemImageNamed:@"waveform.path.ecg"] forState:UIControlStateNormal];
    VCApplyCompactAccentButtonStyle(_diagnosticsButton);
    _diagnosticsButton.accessibilityLabel = VCTextLiteral(@"Chat Diagnostics");
    [_diagnosticsButton addTarget:self action:@selector(_showDiagnostics) forControlEvents:UIControlEventTouchUpInside];
    _diagnosticsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:_diagnosticsButton];

    _tokenBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _tokenBar.progressTintColor = kVCAccent;
    _tokenBar.trackTintColor = kVCBgSurface;
    _tokenBar.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:_tokenBar];

    _tokenLabel = [[UILabel alloc] init];
    _tokenLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _tokenLabel.textColor = kVCTextSecondary;
    _tokenLabel.textAlignment = NSTextAlignmentRight;
    _tokenLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_tokenLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_tokenLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    _tokenLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:_tokenLabel];

    _sessionStateLabel = [[UILabel alloc] init];
    _sessionStateLabel.hidden = YES;

    _statusPhaseLabel = [[UILabel alloc] init];
    _statusPhaseLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightBold];
    _statusPhaseLabel.textColor = kVCAccentHover;
    _statusPhaseLabel.backgroundColor = [kVCAccent colorWithAlphaComponent:0.14];
    _statusPhaseLabel.layer.cornerRadius = 9.0;
    _statusPhaseLabel.layer.borderWidth = 1.0;
    _statusPhaseLabel.layer.borderColor = [kVCAccent colorWithAlphaComponent:0.20].CGColor;
    _statusPhaseLabel.clipsToBounds = YES;
    _statusPhaseLabel.textAlignment = NSTextAlignmentCenter;
    VCChatPrepareSingleLineLabel(_statusPhaseLabel, NSLineBreakByTruncatingTail);
    _statusPhaseLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:_statusPhaseLabel];

    _statusHeadlineLabel = [[UILabel alloc] init];
    _statusHeadlineLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    _statusHeadlineLabel.textColor = kVCTextPrimary;
    VCChatPrepareSingleLineLabel(_statusHeadlineLabel, NSLineBreakByTruncatingTail);
    _statusHeadlineLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:_statusHeadlineLabel];

    _statusDetailLabel = [[UILabel alloc] init];
    _statusDetailLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
    _statusDetailLabel.textColor = kVCTextMuted;
    _statusDetailLabel.numberOfLines = 2;
    _statusDetailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_statusDetailLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    _statusDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:_statusDetailLabel];

    [NSLayoutConstraint activateConstraints:@[
        [topBar.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8],
        [topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [_modelButton.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor constant:10],
        [_modelButton.widthAnchor constraintGreaterThanOrEqualToConstant:74],
        [_modelButton.trailingAnchor constraintLessThanOrEqualToAnchor:_statusPhaseLabel.leadingAnchor constant:-8],
        [_clearChatButton.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-10],
        [_diagnosticsButton.trailingAnchor constraintEqualToAnchor:_clearChatButton.leadingAnchor constant:-8],
        [_diagnosticsButton.centerYAnchor constraintEqualToAnchor:_clearChatButton.centerYAnchor],
        [_diagnosticsButton.widthAnchor constraintEqualToConstant:30],
        [_diagnosticsButton.heightAnchor constraintEqualToConstant:30],
        [_clearChatButton.widthAnchor constraintEqualToConstant:30],
        [_clearChatButton.heightAnchor constraintEqualToConstant:30],
        [_tokenLabel.trailingAnchor constraintEqualToAnchor:_diagnosticsButton.leadingAnchor constant:-10],
        [_tokenBar.trailingAnchor constraintEqualToAnchor:_diagnosticsButton.leadingAnchor constant:-10],
        [_statusPhaseLabel.leadingAnchor constraintEqualToAnchor:_modelButton.trailingAnchor constant:8],
        [_statusPhaseLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_tokenLabel.leadingAnchor constant:-10],
        [_statusPhaseLabel.heightAnchor constraintEqualToConstant:18.0],
        [_statusHeadlineLabel.leadingAnchor constraintEqualToAnchor:_statusPhaseLabel.leadingAnchor],
        [_statusHeadlineLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_tokenLabel.leadingAnchor constant:-10],
        [_statusDetailLabel.leadingAnchor constraintEqualToAnchor:_statusPhaseLabel.leadingAnchor],
        [_statusDetailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_tokenLabel.leadingAnchor constant:-10],
        [_statusDetailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:topBar.bottomAnchor constant:-10],
    ]];
    self.modelButtonTopConstraint = [_modelButton.topAnchor constraintEqualToAnchor:topBar.topAnchor constant:8];
    self.modelButtonTopConstraint.active = YES;
    self.clearButtonBottomConstraint = [_clearChatButton.bottomAnchor constraintEqualToAnchor:topBar.bottomAnchor constant:-9];
    self.clearButtonBottomConstraint.active = YES;
    self.tokenLabelTopConstraint = [_tokenLabel.topAnchor constraintEqualToAnchor:topBar.topAnchor constant:9];
    self.tokenLabelTopConstraint.active = YES;
    self.tokenBarTopConstraint = [_tokenBar.topAnchor constraintEqualToAnchor:_tokenLabel.bottomAnchor constant:6];
    self.tokenBarTopConstraint.active = YES;
    self.sessionStateTopConstraint = [_statusPhaseLabel.topAnchor constraintEqualToAnchor:_modelButton.bottomAnchor constant:6];
    self.sessionStateTopConstraint.active = NO;
    self.statusPhaseCenterYConstraint = [_statusPhaseLabel.centerYAnchor constraintEqualToAnchor:_modelButton.centerYAnchor];
    self.statusPhaseCenterYConstraint.active = YES;
    self.statusHeadlineTopConstraint = [_statusHeadlineLabel.topAnchor constraintEqualToAnchor:_statusPhaseLabel.bottomAnchor constant:4.0];
    self.statusHeadlineTopConstraint.active = NO;
    self.statusDetailTopConstraint = [_statusDetailLabel.topAnchor constraintEqualToAnchor:_statusHeadlineLabel.bottomAnchor constant:2.0];
    self.statusDetailTopConstraint.active = NO;
    _statusHeadlineLabel.hidden = YES;
    _statusDetailLabel.hidden = YES;
    self.topBarHeightConstraint = [topBar.heightAnchor constraintEqualToConstant:52.0];
    self.topBarHeightConstraint.active = YES;
    self.tokenBarWidthConstraint = [_tokenBar.widthAnchor constraintEqualToConstant:88.0];
    self.tokenBarWidthConstraint.active = YES;
    [self _updateTokenDisplay];
    [self _updateSessionStateDisplay];
    [self _refreshDiagnosticsButton];
}

- (void)_setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 72;
    _tableView.alwaysBounceVertical = YES;
    _tableView.delaysContentTouches = NO;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _tableView.contentInset = UIEdgeInsetsMake(3, 0, 8, 0);
    _tableView.scrollIndicatorInsets = UIEdgeInsetsMake(3, 0, 8, 0);
    [_tableView registerClass:[VCChatBubble class] forCellReuseIdentifier:kBubbleCellID];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.conversationColumnView addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.conversationColumnView.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.conversationColumnView.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.conversationColumnView.trailingAnchor],
    ]];
}

- (void)_setupContextRail {
    self.contextSummaryCard = [self _makeRailCardView];
    [self.contextRailView addSubview:self.contextSummaryCard];

    self.contextSummaryTitleLabel = [[UILabel alloc] init];
    self.contextSummaryTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.contextSummaryTitleLabel.text = VCTextLiteral(@"Workspace");
    self.contextSummaryTitleLabel.textColor = kVCTextSecondary;
    self.contextSummaryTitleLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
    [self.contextSummaryCard addSubview:self.contextSummaryTitleLabel];

    self.contextSummaryBodyLabel = [[UILabel alloc] init];
    self.contextSummaryBodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.contextSummaryBodyLabel.textColor = kVCTextPrimary;
    self.contextSummaryBodyLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.contextSummaryBodyLabel.numberOfLines = 2;
    [self.contextSummaryCard addSubview:self.contextSummaryBodyLabel];

    self.contextSummaryMetaLabel = [[UILabel alloc] init];
    self.contextSummaryMetaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.contextSummaryMetaLabel.textColor = kVCTextMuted;
    self.contextSummaryMetaLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    self.contextSummaryMetaLabel.numberOfLines = 3;
    [self.contextSummaryCard addSubview:self.contextSummaryMetaLabel];

    self.contextModelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.contextModelButton.translatesAutoresizingMaskIntoConstraints = NO;
    VCApplyCompactSecondaryButtonStyle(self.contextModelButton);
    VCSetButtonSymbol(self.contextModelButton, @"cpu");
    self.contextModelButton.titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    VCChatPrepareButtonTitle(self.contextModelButton, NSLineBreakByTruncatingMiddle, 0.84);
    self.contextModelButton.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    [self.contextModelButton addTarget:self action:@selector(_showModelSelector) forControlEvents:UIControlEventTouchUpInside];
    [self.contextSummaryCard addSubview:self.contextModelButton];

    self.contextClearButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.contextClearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contextClearButton setTitle:VCTextLiteral(@"Clear") forState:UIControlStateNormal];
    VCSetButtonSymbol(self.contextClearButton, @"trash");
    VCApplyCompactDangerButtonStyle(self.contextClearButton);
    self.contextClearButton.titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    VCChatPrepareButtonTitle(self.contextClearButton, NSLineBreakByTruncatingTail, 0.86);
    self.contextClearButton.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    [self.contextClearButton addTarget:self action:@selector(_confirmClearChat) forControlEvents:UIControlEventTouchUpInside];
    [self.contextSummaryCard addSubview:self.contextClearButton];

    self.contextDiagnosticsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.contextDiagnosticsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contextDiagnosticsButton setTitle:VCTextLiteral(@"Diagnostics") forState:UIControlStateNormal];
    [self.contextDiagnosticsButton setImage:[UIImage systemImageNamed:@"waveform.path.ecg"] forState:UIControlStateNormal];
    VCApplyCompactAccentButtonStyle(self.contextDiagnosticsButton);
    self.contextDiagnosticsButton.titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    VCChatPrepareButtonTitle(self.contextDiagnosticsButton, NSLineBreakByTruncatingTail, 0.82);
    self.contextDiagnosticsButton.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    self.contextDiagnosticsButton.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
    self.contextDiagnosticsButton.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.contextDiagnosticsButton.accessibilityLabel = VCTextLiteral(@"Chat Diagnostics");
    [self.contextDiagnosticsButton addTarget:self action:@selector(_showDiagnostics) forControlEvents:UIControlEventTouchUpInside];
    [self.contextSummaryCard addSubview:self.contextDiagnosticsButton];

    self.referenceRailCard = [self _makeRailCardView];
    [self.contextRailView addSubview:self.referenceRailCard];

    self.referenceRailTitleLabel = [[UILabel alloc] init];
    self.referenceRailTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.referenceRailTitleLabel.text = VCTextLiteral(@"Attached Context");
    self.referenceRailTitleLabel.textColor = kVCTextPrimary;
    self.referenceRailTitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    VCChatPrepareSingleLineLabel(self.referenceRailTitleLabel, NSLineBreakByTruncatingTail);
    [self.referenceRailCard addSubview:self.referenceRailTitleLabel];

    self.referenceRailSubtitleLabel = [[UILabel alloc] init];
    self.referenceRailSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.referenceRailSubtitleLabel.text = VCTextLiteral(@"Picked UI nodes, memory pages, inspect payloads, and manual references stay here while you chat.");
    self.referenceRailSubtitleLabel.textColor = kVCTextSecondary;
    self.referenceRailSubtitleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    self.referenceRailSubtitleLabel.numberOfLines = 3;
    self.referenceRailSubtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.referenceRailCard addSubview:self.referenceRailSubtitleLabel];

    self.referenceRailScrollView = [[UIScrollView alloc] init];
    self.referenceRailScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.referenceRailScrollView.showsVerticalScrollIndicator = YES;
    [self.referenceRailCard addSubview:self.referenceRailScrollView];

    self.referenceRailStack = [[UIStackView alloc] init];
    self.referenceRailStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.referenceRailStack.axis = UILayoutConstraintAxisVertical;
    self.referenceRailStack.spacing = 8.0;
    [self.referenceRailScrollView addSubview:self.referenceRailStack];

    self.referenceRailEmptyLabel = [[UILabel alloc] init];
    self.referenceRailEmptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.referenceRailEmptyLabel.text = VCTextLiteral(@"Nothing is attached yet. Long-press UI picks, send memory pages, or add context from other tabs.");
    self.referenceRailEmptyLabel.textColor = kVCTextMuted;
    self.referenceRailEmptyLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    self.referenceRailEmptyLabel.numberOfLines = 0;
    self.referenceRailEmptyLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.referenceRailCard addSubview:self.referenceRailEmptyLabel];

    self.contextSummaryTopConstraint = [self.contextSummaryCard.topAnchor constraintEqualToAnchor:self.contextRailView.topAnchor];
    self.referenceRailTopConstraint = [self.referenceRailCard.topAnchor constraintEqualToAnchor:self.contextSummaryCard.bottomAnchor constant:10.0];

    [NSLayoutConstraint activateConstraints:@[
        self.contextSummaryTopConstraint,
        [self.contextSummaryCard.leadingAnchor constraintEqualToAnchor:self.contextRailView.leadingAnchor],
        [self.contextSummaryCard.trailingAnchor constraintEqualToAnchor:self.contextRailView.trailingAnchor],

        [self.contextSummaryTitleLabel.topAnchor constraintEqualToAnchor:self.contextSummaryCard.topAnchor constant:14.0],
        [self.contextSummaryTitleLabel.leadingAnchor constraintEqualToAnchor:self.contextSummaryCard.leadingAnchor constant:14.0],
        [self.contextSummaryTitleLabel.trailingAnchor constraintEqualToAnchor:self.contextSummaryCard.trailingAnchor constant:-14.0],
        [self.contextSummaryBodyLabel.topAnchor constraintEqualToAnchor:self.contextSummaryTitleLabel.bottomAnchor constant:6.0],
        [self.contextSummaryBodyLabel.leadingAnchor constraintEqualToAnchor:self.contextSummaryTitleLabel.leadingAnchor],
        [self.contextSummaryBodyLabel.trailingAnchor constraintEqualToAnchor:self.contextSummaryTitleLabel.trailingAnchor],
        [self.contextSummaryMetaLabel.topAnchor constraintEqualToAnchor:self.contextSummaryBodyLabel.bottomAnchor constant:8.0],
        [self.contextSummaryMetaLabel.leadingAnchor constraintEqualToAnchor:self.contextSummaryTitleLabel.leadingAnchor],
        [self.contextSummaryMetaLabel.trailingAnchor constraintEqualToAnchor:self.contextSummaryTitleLabel.trailingAnchor],
        [self.contextModelButton.topAnchor constraintEqualToAnchor:self.contextSummaryMetaLabel.bottomAnchor constant:10.0],
        [self.contextModelButton.leadingAnchor constraintEqualToAnchor:self.contextSummaryTitleLabel.leadingAnchor],
        [self.contextModelButton.trailingAnchor constraintEqualToAnchor:self.contextSummaryTitleLabel.trailingAnchor],
        [self.contextModelButton.heightAnchor constraintEqualToConstant:32.0],
        [self.contextDiagnosticsButton.topAnchor constraintEqualToAnchor:self.contextModelButton.bottomAnchor constant:8.0],
        [self.contextDiagnosticsButton.leadingAnchor constraintEqualToAnchor:self.contextSummaryTitleLabel.leadingAnchor],
        [self.contextDiagnosticsButton.heightAnchor constraintEqualToAnchor:self.contextModelButton.heightAnchor],
        [self.contextDiagnosticsButton.trailingAnchor constraintEqualToAnchor:self.contextClearButton.leadingAnchor constant:-8.0],
        [self.contextClearButton.topAnchor constraintEqualToAnchor:self.contextDiagnosticsButton.topAnchor],
        [self.contextClearButton.trailingAnchor constraintEqualToAnchor:self.contextSummaryTitleLabel.trailingAnchor],
        [self.contextClearButton.widthAnchor constraintEqualToConstant:74.0],
        [self.contextClearButton.heightAnchor constraintEqualToAnchor:self.contextModelButton.heightAnchor],
        [self.contextSummaryCard.bottomAnchor constraintEqualToAnchor:self.contextDiagnosticsButton.bottomAnchor constant:12.0],

        self.referenceRailTopConstraint,
        [self.referenceRailCard.leadingAnchor constraintEqualToAnchor:self.contextRailView.leadingAnchor],
        [self.referenceRailCard.trailingAnchor constraintEqualToAnchor:self.contextRailView.trailingAnchor],

        [self.referenceRailTitleLabel.topAnchor constraintEqualToAnchor:self.referenceRailCard.topAnchor constant:14.0],
        [self.referenceRailTitleLabel.leadingAnchor constraintEqualToAnchor:self.referenceRailCard.leadingAnchor constant:14.0],
        [self.referenceRailTitleLabel.trailingAnchor constraintEqualToAnchor:self.referenceRailCard.trailingAnchor constant:-14.0],
        [self.referenceRailSubtitleLabel.topAnchor constraintEqualToAnchor:self.referenceRailTitleLabel.bottomAnchor constant:4.0],
        [self.referenceRailSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.referenceRailTitleLabel.leadingAnchor],
        [self.referenceRailSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.referenceRailTitleLabel.trailingAnchor],
        [self.referenceRailScrollView.leadingAnchor constraintEqualToAnchor:self.referenceRailCard.leadingAnchor constant:10.0],
        [self.referenceRailScrollView.trailingAnchor constraintEqualToAnchor:self.referenceRailCard.trailingAnchor constant:-10.0],
        [self.referenceRailScrollView.bottomAnchor constraintEqualToAnchor:self.referenceRailCard.bottomAnchor constant:-10.0],
        [self.referenceRailStack.topAnchor constraintEqualToAnchor:self.referenceRailScrollView.contentLayoutGuide.topAnchor],
        [self.referenceRailStack.leadingAnchor constraintEqualToAnchor:self.referenceRailScrollView.contentLayoutGuide.leadingAnchor],
        [self.referenceRailStack.trailingAnchor constraintEqualToAnchor:self.referenceRailScrollView.contentLayoutGuide.trailingAnchor],
        [self.referenceRailStack.bottomAnchor constraintEqualToAnchor:self.referenceRailScrollView.contentLayoutGuide.bottomAnchor],
        [self.referenceRailStack.widthAnchor constraintEqualToAnchor:self.referenceRailScrollView.frameLayoutGuide.widthAnchor],
        [self.referenceRailEmptyLabel.topAnchor constraintEqualToAnchor:self.referenceRailScrollView.topAnchor constant:4.0],
        [self.referenceRailEmptyLabel.leadingAnchor constraintEqualToAnchor:self.referenceRailScrollView.leadingAnchor constant:4.0],
        [self.referenceRailEmptyLabel.trailingAnchor constraintEqualToAnchor:self.referenceRailScrollView.trailingAnchor constant:-4.0],
        [self.contextRailDividerView.leadingAnchor constraintEqualToAnchor:self.contextRailView.leadingAnchor constant:10.0],
        [self.contextRailDividerView.trailingAnchor constraintEqualToAnchor:self.contextRailView.trailingAnchor constant:-10.0],
        [self.contextRailDividerView.heightAnchor constraintEqualToConstant:1.0],
    ]];
    self.referenceRailScrollTopToSubtitleConstraint = [self.referenceRailScrollView.topAnchor constraintEqualToAnchor:self.referenceRailSubtitleLabel.bottomAnchor constant:8.0];
    self.referenceRailScrollTopToSubtitleConstraint.active = YES;
    self.referenceRailScrollTopToTitleConstraint = [self.referenceRailScrollView.topAnchor constraintEqualToAnchor:self.referenceRailTitleLabel.bottomAnchor constant:4.0];
    self.referenceRailBottomToContextConstraint = [self.referenceRailCard.bottomAnchor constraintEqualToAnchor:self.contextRailView.bottomAnchor];
    self.referenceRailBottomToContextConstraint.active = YES;

    self.contextRailView.hidden = YES;
    self.contextRailView.alpha = 0.0;
}

- (void)_setupInputBar {
    _inputBar = [[UIView alloc] init];
    _inputBar.backgroundColor = [UIColor clearColor];
    _inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.conversationColumnView addSubview:_inputBar];

    UIView *composer = [[UIView alloc] init];
    VCApplyPanelSurface(composer, 12.0);
    composer.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.96];
    composer.layer.shadowColor = [UIColor blackColor].CGColor;
    composer.layer.shadowOpacity = 0.08;
    composer.layer.shadowRadius = 10.0;
    composer.layer.shadowOffset = CGSizeMake(0, -3.0);
    composer.translatesAutoresizingMaskIntoConstraints = NO;
    [_inputBar addSubview:composer];
    self.composerCard = composer;

    self.composerTitleLabel = [[UILabel alloc] init];
    self.composerTitleLabel.text = VCTextLiteral(@"PROMPT");
    self.composerTitleLabel.textColor = kVCTextSecondary;
    self.composerTitleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    VCChatPrepareSingleLineLabel(self.composerTitleLabel, NSLineBreakByTruncatingTail);
    self.composerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [composer addSubview:self.composerTitleLabel];

    self.toolsChipLabel = [[UILabel alloc] init];
    self.toolsChipLabel.text = [NSString stringWithFormat:@" %@ ", VCTextLiteral(@"Tools On")];
    self.toolsChipLabel.textAlignment = NSTextAlignmentCenter;
    self.toolsChipLabel.textColor = kVCAccent;
    self.toolsChipLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    self.toolsChipLabel.backgroundColor = kVCAccentDim;
    self.toolsChipLabel.layer.cornerRadius = 9.0;
    self.toolsChipLabel.clipsToBounds = YES;
    VCChatPrepareSingleLineLabel(self.toolsChipLabel, NSLineBreakByTruncatingTail);
    self.toolsChipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [composer addSubview:self.toolsChipLabel];

    self.contextChipLabel = [[UILabel alloc] init];
    self.contextChipLabel.text = [NSString stringWithFormat:@" %@ ", VCTextLiteral(@"Live")];
    self.contextChipLabel.textAlignment = NSTextAlignmentCenter;
    self.contextChipLabel.textColor = kVCGreen;
    self.contextChipLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    self.contextChipLabel.backgroundColor = kVCGreenDim;
    self.contextChipLabel.layer.cornerRadius = 9.0;
    self.contextChipLabel.clipsToBounds = YES;
    VCChatPrepareSingleLineLabel(self.contextChipLabel, NSLineBreakByTruncatingTail);
    self.contextChipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [composer addSubview:self.contextChipLabel];

    self.quickCommandStack = [[UIStackView alloc] init];
    self.quickCommandStack.axis = UILayoutConstraintAxisHorizontal;
    self.quickCommandStack.alignment = UIStackViewAlignmentFill;
    self.quickCommandStack.distribution = UIStackViewDistributionFillEqually;
    self.quickCommandStack.spacing = 6.0;
    self.quickCommandStack.translatesAutoresizingMaskIntoConstraints = NO;
    [composer addSubview:self.quickCommandStack];
    NSArray<NSDictionary *> *quickPrompts = @[
        @{@"title": VCTextLiteral(@"Current UI"),
          @"prompt": VCTextLiteral(@"Analyze the current screen and point out UI hierarchy, layout, and interaction risks.")},
        @{@"title": VCTextLiteral(@"Find issue"),
          @"prompt": VCTextLiteral(@"Inspect the selected context and find the most likely bug or UI regression.")},
        @{@"title": VCTextLiteral(@"Find value"),
          @"prompt": VCTextLiteral(@"Look at the current game screen and runtime context. Identify visible numeric resources or values, then propose a safe memory or UI-backed modification path with exact tools to call before changing anything.")},
        @{@"title": VCTextLiteral(@"Patch plan"),
          @"prompt": VCTextLiteral(@"Generate a focused patch plan for this injected process and mention the safest first edit.")}
    ];
    for (NSDictionary *item in quickPrompts) {
        [self.quickCommandStack addArrangedSubview:[self _quickPromptButtonWithTitle:item[@"title"] prompt:item[@"prompt"]]];
    }

    UIView *inputSurface = [[UIView alloc] init];
    VCApplyInputSurface(inputSurface, 10.0);
    inputSurface.translatesAutoresizingMaskIntoConstraints = NO;
    [composer addSubview:inputSurface];

    _referenceScrollView = [[UIScrollView alloc] init];
    _referenceScrollView.showsHorizontalScrollIndicator = NO;
    _referenceScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [composer addSubview:_referenceScrollView];

    _referenceStack = [[UIStackView alloc] init];
    _referenceStack.axis = UILayoutConstraintAxisHorizontal;
    _referenceStack.spacing = 6.0;
    _referenceStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_referenceScrollView addSubview:_referenceStack];

    _inputTextView = [[UITextView alloc] init];
    _inputTextView.backgroundColor = [UIColor clearColor];
    _inputTextView.textColor = kVCTextPrimary;
    _inputTextView.font = [UIFont systemFontOfSize:14];
    _inputTextView.keyboardType = UIKeyboardTypeDefault;
    _inputTextView.returnKeyType = UIReturnKeySend;
    _inputTextView.enablesReturnKeyAutomatically = YES;
    _inputTextView.textContentType = nil;
    _inputTextView.autocorrectionType = UITextAutocorrectionTypeDefault;
    _inputTextView.spellCheckingType = UITextSpellCheckingTypeDefault;
    if (@available(iOS 11.0, *)) {
        _inputTextView.smartQuotesType = UITextSmartQuotesTypeDefault;
        _inputTextView.smartDashesType = UITextSmartDashesTypeDefault;
    }
    _inputTextView.scrollEnabled = NO;
    _inputTextView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    _inputTextView.textContainer.lineFragmentPadding = 0.0;
    _inputTextView.delegate = self;
    _inputTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [inputSurface addSubview:_inputTextView];

    _inputPlaceholderLabel = [[UILabel alloc] init];
    _inputPlaceholderLabel.text = VCTextLiteral(@"Ask about the current UI, network flow, crash, or patch.");
    _inputPlaceholderLabel.textColor = kVCTextMuted;
    _inputPlaceholderLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    _inputPlaceholderLabel.numberOfLines = 2;
    _inputPlaceholderLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _inputPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [inputSurface addSubview:_inputPlaceholderLabel];

    _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _sendButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    VCChatPrepareButtonTitle(_sendButton, NSLineBreakByTruncatingTail, 0.86);
    _sendButton.layer.cornerRadius = 10.0;
    _sendButton.layer.shadowRadius = 8.0;
    _sendButton.layer.shadowOpacity = 0.14;
    _sendButton.layer.shadowOffset = CGSizeMake(0, 3);
    _sendButton.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
    _sendButton.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    _sendButton.imageEdgeInsets = UIEdgeInsetsMake(0, -2, 0, 2);
    [_sendButton addTarget:self action:@selector(_sendMessage) forControlEvents:UIControlEventTouchUpInside];
    _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [inputSurface addSubview:_sendButton];

    self.inputBarMinHeightConstraint = [_inputBar.heightAnchor constraintGreaterThanOrEqualToConstant:166];
    self.inputBarPreferredHeightConstraint = [_inputBar.heightAnchor constraintEqualToConstant:166];
    self.tableBottomToInputConstraint = [_tableView.bottomAnchor constraintEqualToAnchor:_inputBar.topAnchor];
    self.tableBottomToConversationBottomConstraint = [_tableView.bottomAnchor constraintEqualToAnchor:self.conversationColumnView.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        self.inputBarMinHeightConstraint,
        [composer.topAnchor constraintEqualToAnchor:_inputBar.topAnchor constant:5],
        [composer.bottomAnchor constraintEqualToAnchor:_inputBar.bottomAnchor constant:-7],
        [composer.leadingAnchor constraintEqualToAnchor:_inputBar.leadingAnchor constant:10],
        [composer.trailingAnchor constraintEqualToAnchor:_inputBar.trailingAnchor constant:-10],
        [self.composerTitleLabel.topAnchor constraintEqualToAnchor:composer.topAnchor constant:10],
        [self.composerTitleLabel.leadingAnchor constraintEqualToAnchor:composer.leadingAnchor constant:14],
        [self.composerTitleLabel.centerYAnchor constraintEqualToAnchor:self.toolsChipLabel.centerYAnchor],
        [self.contextChipLabel.topAnchor constraintEqualToAnchor:composer.topAnchor constant:9],
        [self.contextChipLabel.trailingAnchor constraintEqualToAnchor:composer.trailingAnchor constant:-10],
        [self.toolsChipLabel.heightAnchor constraintEqualToConstant:18],
        [self.contextChipLabel.heightAnchor constraintEqualToConstant:18],
        [self.toolsChipLabel.centerYAnchor constraintEqualToAnchor:self.contextChipLabel.centerYAnchor],
        [self.toolsChipLabel.trailingAnchor constraintEqualToAnchor:self.contextChipLabel.leadingAnchor constant:-6],
        [self.composerTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.toolsChipLabel.leadingAnchor constant:-10],
        [self.quickCommandStack.topAnchor constraintEqualToAnchor:self.composerTitleLabel.bottomAnchor constant:8],
        [self.quickCommandStack.leadingAnchor constraintEqualToAnchor:composer.leadingAnchor constant:12],
        [self.quickCommandStack.trailingAnchor constraintEqualToAnchor:composer.trailingAnchor constant:-12],
        [self.quickCommandStack.heightAnchor constraintEqualToConstant:26],
        [_referenceScrollView.leadingAnchor constraintEqualToAnchor:composer.leadingAnchor constant:12],
        [_referenceScrollView.trailingAnchor constraintEqualToAnchor:composer.trailingAnchor constant:-12],
        [_referenceStack.topAnchor constraintEqualToAnchor:_referenceScrollView.contentLayoutGuide.topAnchor],
        [_referenceStack.leadingAnchor constraintEqualToAnchor:_referenceScrollView.contentLayoutGuide.leadingAnchor],
        [_referenceStack.trailingAnchor constraintEqualToAnchor:_referenceScrollView.contentLayoutGuide.trailingAnchor],
        [_referenceStack.bottomAnchor constraintEqualToAnchor:_referenceScrollView.contentLayoutGuide.bottomAnchor],
        [_referenceStack.heightAnchor constraintEqualToAnchor:_referenceScrollView.frameLayoutGuide.heightAnchor],
        [inputSurface.leadingAnchor constraintEqualToAnchor:composer.leadingAnchor constant:9],
        [inputSurface.trailingAnchor constraintEqualToAnchor:composer.trailingAnchor constant:-9],
        [inputSurface.bottomAnchor constraintEqualToAnchor:composer.bottomAnchor constant:-9],
        [_inputTextView.topAnchor constraintEqualToAnchor:inputSurface.topAnchor constant:4],
        [_inputTextView.leadingAnchor constraintEqualToAnchor:inputSurface.leadingAnchor constant:4],
        [_inputTextView.bottomAnchor constraintEqualToAnchor:inputSurface.bottomAnchor constant:-4],
        [_inputPlaceholderLabel.topAnchor constraintEqualToAnchor:_inputTextView.topAnchor constant:12],
        [_inputPlaceholderLabel.leadingAnchor constraintEqualToAnchor:_inputTextView.leadingAnchor constant:12],
        [_inputPlaceholderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_sendButton.leadingAnchor constant:-10],
        [_sendButton.trailingAnchor constraintEqualToAnchor:inputSurface.trailingAnchor constant:-6],
        [_sendButton.centerYAnchor constraintEqualToAnchor:inputSurface.centerYAnchor],
        [_sendButton.heightAnchor constraintEqualToConstant:30],
        [_inputTextView.trailingAnchor constraintEqualToAnchor:_sendButton.leadingAnchor constant:-8],
    ]];
    self.sendButtonWidthConstraint = [_sendButton.widthAnchor constraintEqualToConstant:92.0];
    self.sendButtonWidthConstraint.active = YES;
    self.inputBarConversationConstraints = @[
        [_inputBar.leadingAnchor constraintEqualToAnchor:self.conversationColumnView.leadingAnchor],
        [_inputBar.trailingAnchor constraintEqualToAnchor:self.conversationColumnView.trailingAnchor],
        [_inputBar.bottomAnchor constraintEqualToAnchor:self.conversationColumnView.bottomAnchor],
    ];
    [NSLayoutConstraint activateConstraints:self.inputBarConversationConstraints];
    self.tableBottomToInputConstraint.active = YES;
    self.tableBottomToConversationBottomConstraint.active = NO;
    self.inputBarBottom = self.inputBarConversationConstraints.lastObject;
    self.referenceTopConstraint = [_referenceScrollView.topAnchor constraintEqualToAnchor:self.quickCommandStack.bottomAnchor constant:8];
    self.referenceTopConstraint.active = YES;
    self.inputSurfaceTopConstraint = [inputSurface.topAnchor constraintEqualToAnchor:_referenceScrollView.bottomAnchor constant:8];
    self.inputSurfaceTopConstraint.active = YES;
    self.inputSurfaceTopToComposerConstraint = [inputSurface.topAnchor constraintEqualToAnchor:composer.topAnchor constant:10];
    self.inputSurfaceTopToComposerConstraint.active = NO;
    _inputTextHeightConstraint = [_inputTextView.heightAnchor constraintEqualToConstant:72];
    _inputTextHeightConstraint.active = YES;
    _referenceStripHeight = [_referenceScrollView.heightAnchor constraintEqualToConstant:0];
    _referenceStripHeight.active = YES;
    self.inputBarPreferredHeightConstraint.active = NO;
    [self _setSendButtonGenerating:NO];
    [self _updateInputTextHeight];
    [self _refreshComposerState];
    [self _reloadPendingReferences];
    [self _applyCurrentLayoutMode];
}

- (UIButton *)_quickPromptButtonWithTitle:(NSString *)title prompt:(NSString *)prompt {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title ?: @"" forState:UIControlStateNormal];
    [button setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    [button setImage:nil forState:UIControlStateNormal];
    button.tintColor = kVCAccentHover;
    button.accessibilityValue = prompt ?: @"";
    button.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    button.titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.78;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 6);
    button.titleEdgeInsets = UIEdgeInsetsZero;
    VCApplyCompactSecondaryButtonStyle(button);
    [button addTarget:self action:@selector(_quickPromptTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)_setupEmptyStateView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [UIColor clearColor];
    [self.conversationColumnView addSubview:container];
    self.emptyStateView = container;

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    VCApplyPanelSurface(card, 14.0);
    card.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.92];
    [container addSubview:card];

    UILabel *eyebrow = [[UILabel alloc] init];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrow.text = VCTextLiteral(@"AI WORKSPACE");
    eyebrow.textColor = kVCAccentHover;
    eyebrow.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
    [card addSubview:eyebrow];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = VCTextLiteral(@"Ready to inspect the live app");
    title.textColor = kVCTextPrimary;
    title.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    title.numberOfLines = 1;
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.82;
    [card addSubview:title];

    UILabel *body = [[UILabel alloc] init];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.text = VCTextLiteral(@"Pick UI nodes, attach runtime details, or ask for a patch plan. Context from Inspect and Network is available to the chat.");
    body.textColor = kVCTextSecondary;
    body.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    body.numberOfLines = 4;
    body.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:body];

    UIStackView *actions = [[UIStackView alloc] init];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.alignment = UIStackViewAlignmentFill;
    actions.distribution = UIStackViewDistributionFillEqually;
    actions.spacing = 8.0;
    [card addSubview:actions];
    [actions addArrangedSubview:[self _quickPromptButtonWithTitle:VCTextLiteral(@"Inspect UI")
                                                           prompt:VCTextLiteral(@"Use the current UI context and explain what should be inspected first.")]];
    [actions addArrangedSubview:[self _quickPromptButtonWithTitle:VCTextLiteral(@"Find Value")
                                                           prompt:VCTextLiteral(@"Look at the current game screen and runtime context. Identify visible numeric resources or values, then propose a safe memory or UI-backed modification path with exact tools to call before changing anything.")]];
    [actions addArrangedSubview:[self _quickPromptButtonWithTitle:VCTextLiteral(@"Debug Flow")
                                                           prompt:VCTextLiteral(@"Trace the current user flow and list likely failure points in order.")]];

    [NSLayoutConstraint activateConstraints:@[
        [container.topAnchor constraintEqualToAnchor:self.tableView.topAnchor],
        [container.leadingAnchor constraintEqualToAnchor:self.tableView.leadingAnchor],
        [container.trailingAnchor constraintEqualToAnchor:self.tableView.trailingAnchor],
        [container.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor],

        [card.topAnchor constraintEqualToAnchor:container.topAnchor constant:12.0],
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:10.0],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-10.0],

        [eyebrow.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [eyebrow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [eyebrow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:6.0],
        [title.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:eyebrow.trailingAnchor],
        [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8.0],
        [body.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:eyebrow.trailingAnchor],
        [actions.topAnchor constraintEqualToAnchor:body.bottomAnchor constant:12.0],
        [actions.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [actions.trailingAnchor constraintEqualToAnchor:eyebrow.trailingAnchor],
        [actions.heightAnchor constraintEqualToConstant:30.0],
        [card.bottomAnchor constraintEqualToAnchor:actions.bottomAnchor constant:14.0],
    ]];
}

- (void)_mountInputBarInConversationIfNeeded {
    if (self.inputBar.superview != self.conversationColumnView) {
        if (self.inputBar.superview) {
            [NSLayoutConstraint deactivateConstraints:self.inputBarRailConstraints ?: @[]];
            [self.inputBar removeFromSuperview];
        }
        [self.conversationColumnView addSubview:self.inputBar];
        self.inputBarConversationConstraints = @[
            [self.inputBar.leadingAnchor constraintEqualToAnchor:self.conversationColumnView.leadingAnchor],
            [self.inputBar.trailingAnchor constraintEqualToAnchor:self.conversationColumnView.trailingAnchor],
            [self.inputBar.bottomAnchor constraintEqualToAnchor:self.conversationColumnView.bottomAnchor],
        ];
    }
    [NSLayoutConstraint deactivateConstraints:self.inputBarRailConstraints ?: @[]];
    [NSLayoutConstraint activateConstraints:self.inputBarConversationConstraints];
    self.inputBarBottom = self.inputBarConversationConstraints.lastObject;
    self.tableBottomToInputConstraint.active = YES;
    self.tableBottomToConversationBottomConstraint.active = NO;
    self.referenceRailBottomToInputConstraint.active = NO;
    self.referenceRailBottomToContextConstraint.active = YES;
    self.contextRailDividerTopConstraint.active = NO;
    self.contextRailDividerBottomConstraint.active = NO;
}

- (void)_mountInputBarInRailIfNeeded {
    if (self.inputBar.superview != self.contextRailView) {
        if (self.inputBar.superview) {
            [NSLayoutConstraint deactivateConstraints:self.inputBarConversationConstraints ?: @[]];
            [self.inputBar removeFromSuperview];
        }
        [self.contextRailView addSubview:self.inputBar];
        self.inputBarRailConstraints = @[
            [self.inputBar.leadingAnchor constraintEqualToAnchor:self.contextRailView.leadingAnchor],
            [self.inputBar.trailingAnchor constraintEqualToAnchor:self.contextRailView.trailingAnchor],
            [self.inputBar.bottomAnchor constraintEqualToAnchor:self.contextRailView.bottomAnchor],
        ];
    }
    [NSLayoutConstraint deactivateConstraints:self.inputBarConversationConstraints ?: @[]];
    [NSLayoutConstraint activateConstraints:self.inputBarRailConstraints];
    self.inputBarBottom = self.inputBarRailConstraints.lastObject;
    self.tableBottomToInputConstraint.active = NO;
    self.tableBottomToConversationBottomConstraint.active = YES;
    if (!self.referenceRailBottomToInputConstraint) {
        self.referenceRailBottomToInputConstraint = [self.referenceRailCard.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor constant:-10.0];
    }
    if (!self.contextRailDividerTopConstraint) {
        self.contextRailDividerTopConstraint = [self.contextRailDividerView.topAnchor constraintEqualToAnchor:self.referenceRailCard.bottomAnchor constant:6.0];
    }
    if (!self.contextRailDividerBottomConstraint) {
        self.contextRailDividerBottomConstraint = [self.contextRailDividerView.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor constant:-6.0];
    }
    self.referenceRailBottomToContextConstraint.active = NO;
    self.referenceRailBottomToInputConstraint.active = YES;
    self.contextRailDividerTopConstraint.active = YES;
    self.contextRailDividerBottomConstraint.active = YES;
}

- (void)_syncRevealStateForMessages:(NSArray<VCMessage *> *)messages {
    NSMutableSet<NSString *> *existingMessageIDs = [NSMutableSet new];
    for (VCMessage *message in messages) {
        if ([message.messageID isKindOfClass:[NSString class]] && message.messageID.length > 0) {
            [existingMessageIDs addObject:message.messageID];
        }
    }
    [self.revealedMessageIDs intersectSet:existingMessageIDs];
    if (messages.count == 0 && self.streamingText.length == 0) {
        [self.revealedMessageIDs removeAllObjects];
        self.hasAnimatedStreamingBubble = NO;
    }
}

- (void)_refreshChatChrome {
    [self _updateTokenDisplay];
    [self _updateSessionStateDisplay];
    [self _refreshProviderDisplay];
    [self _refreshClearButtonState];
    [self _refreshContextRail];
    [self _refreshDiagnosticsButton];
    [self _refreshEmptyStateVisibility];
}

- (void)_performSuppressingSessionNotifications:(dispatch_block_t)block {
    if (!block) return;
    self.suppressedSessionNotificationCount += 1;
    block();
    if (self.suppressedSessionNotificationCount > 0) {
        self.suppressedSessionNotificationCount -= 1;
    }
}

- (NSArray<NSString *> *)_messageIdentifiersForMessages:(NSArray<VCMessage *> *)messages {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray arrayWithCapacity:messages.count];
    for (NSUInteger idx = 0; idx < messages.count; idx++) {
        VCMessage *message = messages[idx];
        NSString *messageID = [message.messageID isKindOfClass:[NSString class]] && message.messageID.length > 0
            ? message.messageID
            : [NSString stringWithFormat:@"idx-%lu-%@", (unsigned long)idx, message.content ?: @""];
        [identifiers addObject:messageID];
    }
    return [identifiers copy];
}

- (NSArray<NSIndexPath *> *)_contiguousDeletedIndexPathsFromOldMessages:(NSArray<VCMessage *> *)oldMessages
                                                             newMessages:(NSArray<VCMessage *> *)newMessages {
    if (newMessages.count >= oldMessages.count) return nil;
    NSArray<NSString *> *oldIDs = [self _messageIdentifiersForMessages:oldMessages];
    NSArray<NSString *> *newIDs = [self _messageIdentifiersForMessages:newMessages];
    NSUInteger prefix = 0;
    while (prefix < newIDs.count && [oldIDs[prefix] isEqualToString:newIDs[prefix]]) {
        prefix += 1;
    }
    NSUInteger oldSuffix = oldIDs.count;
    NSUInteger newSuffix = newIDs.count;
    while (oldSuffix > prefix && newSuffix > prefix &&
           [oldIDs[oldSuffix - 1] isEqualToString:newIDs[newSuffix - 1]]) {
        oldSuffix -= 1;
        newSuffix -= 1;
    }
    NSUInteger removedCount = oldMessages.count - newMessages.count;
    if ((oldSuffix - prefix) != removedCount || newSuffix != prefix) return nil;
    NSMutableArray<NSIndexPath *> *indexPaths = [NSMutableArray arrayWithCapacity:removedCount];
    for (NSUInteger idx = prefix; idx < oldSuffix; idx++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:(NSInteger)idx inSection:0]];
    }
    return indexPaths.count > 0 ? [indexPaths copy] : nil;
}

- (void)_syncMessagesFromSessionWithPreviousCount:(NSUInteger)previousCount
                         previousStreamingActive:(BOOL)previousStreamingActive
                                          reason:(NSString *)reason {
    NSArray<VCMessage *> *oldMessages = self.messages ?: @[];
    NSArray<VCMessage *> *newMessages = [[VCChatSession shared] currentMessages];
    [self _syncRevealStateForMessages:newMessages];

    BOOL newStreamingActive = (self.streamingText != nil);
    NSUInteger newCount = newMessages.count;
    NSUInteger previousRows = previousCount + (previousStreamingActive ? 1 : 0);
    NSUInteger newRows = newCount + (newStreamingActive ? 1 : 0);
    self.messages = newMessages;

    BOOL canUseIncrementalUpdate = (self.tableView.window != nil);
    if (canUseIncrementalUpdate &&
        !previousStreamingActive &&
        newStreamingActive &&
        newCount == previousCount + 1 &&
        previousRows == (NSUInteger)[self.tableView numberOfRowsInSection:0]) {
        NSIndexPath *userIndexPath = [NSIndexPath indexPathForRow:previousCount inSection:0];
        NSIndexPath *streamingIndexPath = [NSIndexPath indexPathForRow:(previousCount + 1) inSection:0];
        [self.tableView performBatchUpdates:^{
            [self.tableView insertRowsAtIndexPaths:@[userIndexPath, streamingIndexPath] withRowAnimation:UITableViewRowAnimationFade];
        } completion:nil];
        [self _scrollToBottom:NO];
        [self _refreshChatChrome];
        [[VCChatDiagnostics shared] recordEventWithPhase:@"ui"
                                                subphase:@"insert_user_and_streaming_rows"
                                              durationMS:0.0
                                                   extra:@{
                                                       @"previousCount": @(previousCount),
                                                       @"newCount": @(newCount),
                                                       @"reason": reason ?: @"send"
                                                   }];
        return;
    }

    if (canUseIncrementalUpdate &&
        previousStreamingActive &&
        !newStreamingActive &&
        newCount == previousCount + 1 &&
        previousRows == newRows &&
        newRows == (NSUInteger)[self.tableView numberOfRowsInSection:0]) {
        NSIndexPath *finalAssistantIndexPath = [NSIndexPath indexPathForRow:previousCount inSection:0];
        [UIView performWithoutAnimation:^{
            [self.tableView reloadRowsAtIndexPaths:@[finalAssistantIndexPath] withRowAnimation:UITableViewRowAnimationFade];
        }];
        [self _scrollToBottom:NO];
        [self _refreshChatChrome];
        [[VCChatDiagnostics shared] recordEventWithPhase:@"ui"
                                                subphase:@"replace_streaming_with_final_row"
                                              durationMS:0.0
                                                   extra:@{
                                                       @"previousCount": @(previousCount),
                                                       @"newCount": @(newCount),
                                                       @"reason": reason ?: @"complete"
                                                   }];
        return;
    }

    if (canUseIncrementalUpdate &&
        previousStreamingActive &&
        !newStreamingActive &&
        newCount == previousCount &&
        previousRows == newRows + 1 &&
        previousRows == (NSUInteger)[self.tableView numberOfRowsInSection:0]) {
        NSIndexPath *streamingIndexPath = [NSIndexPath indexPathForRow:previousCount inSection:0];
        [self.tableView performBatchUpdates:^{
            [self.tableView deleteRowsAtIndexPaths:@[streamingIndexPath] withRowAnimation:UITableViewRowAnimationFade];
        } completion:nil];
        [self _scrollToBottom:NO];
        [self _refreshChatChrome];
        [[VCChatDiagnostics shared] recordEventWithPhase:@"ui"
                                                subphase:@"remove_streaming_row"
                                              durationMS:0.0
                                                   extra:@{
                                                       @"previousCount": @(previousCount),
                                                       @"newCount": @(newCount),
                                                       @"reason": reason ?: @"stop"
                                                   }];
        return;
    }

    NSArray<NSIndexPath *> *deletedIndexPaths = nil;
    if (canUseIncrementalUpdate &&
        !previousStreamingActive &&
        !newStreamingActive &&
        previousRows == (NSUInteger)[self.tableView numberOfRowsInSection:0]) {
        deletedIndexPaths = [self _contiguousDeletedIndexPathsFromOldMessages:oldMessages newMessages:newMessages];
    }
    if (deletedIndexPaths.count > 0) {
        [self.tableView performBatchUpdates:^{
            [self.tableView deleteRowsAtIndexPaths:deletedIndexPaths withRowAnimation:UITableViewRowAnimationFade];
        } completion:nil];
        [self _scrollToBottom:NO];
        [self _refreshChatChrome];
        [[VCChatDiagnostics shared] recordEventWithPhase:@"ui"
                                                subphase:@"delete_message_rows"
                                              durationMS:0.0
                                                   extra:@{
                                                       @"deletedCount": @(deletedIndexPaths.count),
                                                       @"reason": reason ?: @"delete"
                                                   }];
        return;
    }

    [self _reloadMessages];
}

- (NSString *)_diagnosticsFormattedText {
    NSArray<NSDictionary *> *events = [[VCChatDiagnostics shared] recentEvents];
    if (events.count == 0) {
        return VCTextLiteral(@"No chat diagnostics have been recorded yet.");
    }

    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });

    NSUInteger maxLines = MIN((NSUInteger)40, events.count);
    NSUInteger startIndex = events.count > maxLines ? (events.count - maxLines) : 0;
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSUInteger idx = startIndex; idx < events.count; idx++) {
        NSDictionary *event = events[idx];
        NSTimeInterval timestamp = [event[@"timestamp"] doubleValue];
        NSString *phase = [event[@"phase"] isKindOfClass:[NSString class]] ? event[@"phase"] : @"";
        NSString *subphase = [event[@"subphase"] isKindOfClass:[NSString class]] ? event[@"subphase"] : @"";
        NSString *durationText = [event[@"durationMS"] isKindOfClass:[NSNumber class]]
            ? [NSString stringWithFormat:@"%@ms", event[@"durationMS"]]
            : @"-";
        NSString *extraText = @"";
        NSDictionary *extra = [event[@"extra"] isKindOfClass:[NSDictionary class]] ? event[@"extra"] : nil;
        if (extra.count > 0) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:extra options:0 error:nil];
            extraText = json ? ([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"") : extra.description;
        }
        NSString *timestampText = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]] ?: @"--:--:--.---";
        NSString *line = extraText.length > 0
            ? [NSString stringWithFormat:@"%@  %@/%@  %@  %@", timestampText, phase, subphase, durationText, extraText]
            : [NSString stringWithFormat:@"%@  %@/%@  %@", timestampText, phase, subphase, durationText];
        [lines addObject:line];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)_refreshDiagnosticsButton {
    BOOL active = ([VCChatDiagnostics shared].activeRequestID.length > 0);
    NSArray<UIButton *> *buttons = @[self.diagnosticsButton ?: [UIButton new], self.contextDiagnosticsButton ?: [UIButton new]];
    UIColor *tintColor = active ? kVCGreen : kVCAccentHover;
    UIColor *backgroundColor = active ? kVCGreenDim : [kVCAccent colorWithAlphaComponent:0.11];
    CGColorRef borderColor = (active ? [kVCGreen colorWithAlphaComponent:0.24] : [kVCAccent colorWithAlphaComponent:0.24]).CGColor;
    for (UIButton *button in buttons) {
        if (![button isKindOfClass:[UIButton class]] || button.superview == nil) continue;
        button.tintColor = tintColor;
        button.backgroundColor = backgroundColor;
        button.layer.borderColor = borderColor;
    }
}

- (void)_ensureDiagnosticsOverlayIfNeeded {
    if (self.diagnosticsOverlayView) return;

    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.36];
    overlay.hidden = YES;
    overlay.alpha = 0.0;
    [self.view addSubview:overlay];
    self.diagnosticsOverlayView = overlay;

    UIControl *dismissControl = [[UIControl alloc] init];
    dismissControl.translatesAutoresizingMaskIntoConstraints = NO;
    [dismissControl addTarget:self action:@selector(_hideDiagnostics) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:dismissControl];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    VCApplyPanelSurface(card, 14.0);
    card.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    [overlay addSubview:card];
    self.diagnosticsCardView = card;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = VCTextLiteral(@"Chat Diagnostics");
    titleLabel.textColor = kVCTextPrimary;
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    VCChatPrepareSingleLineLabel(titleLabel, NSLineBreakByTruncatingTail);
    [card addSubview:titleLabel];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    closeButton.tintColor = kVCTextPrimary;
    closeButton.backgroundColor = [kVCBgHover colorWithAlphaComponent:0.9];
    closeButton.layer.cornerRadius = 14.0;
    closeButton.layer.borderWidth = 1.0;
    closeButton.layer.borderColor = kVCBorder.CGColor;
    [closeButton addTarget:self action:@selector(_hideDiagnostics) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:closeButton];

    UIButton *artifactsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    artifactsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [artifactsButton setTitle:VCTextLiteral(@"Open In Artifacts") forState:UIControlStateNormal];
    VCSetButtonSymbol(artifactsButton, @"shippingbox");
    [artifactsButton setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    artifactsButton.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    VCChatPrepareButtonTitle(artifactsButton, NSLineBreakByTruncatingTail, 0.78);
    artifactsButton.backgroundColor = kVCAccentDim;
    VCApplyCompactAccentButtonStyle(artifactsButton);
    [artifactsButton addTarget:self action:@selector(_openDiagnosticsInArtifacts) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:artifactsButton];

    UILabel *summaryLabel = [[UILabel alloc] init];
    summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    summaryLabel.textColor = kVCTextSecondary;
    summaryLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    summaryLabel.numberOfLines = 2;
    [card addSubview:summaryLabel];
    self.diagnosticsSummaryLabel = summaryLabel;

    UITextView *textView = [[UITextView alloc] init];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.editable = NO;
    textView.selectable = YES;
    VCApplyInputSurface(textView, 10.0);
    textView.textColor = kVCTextPrimary;
    textView.font = [UIFont fontWithName:@"Menlo" size:11.0] ?: [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    textView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    [card addSubview:textView];
    self.diagnosticsTextView = textView;

    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [dismissControl.topAnchor constraintEqualToAnchor:overlay.topAnchor],
        [dismissControl.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [dismissControl.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [dismissControl.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],

        [card.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [card.widthAnchor constraintEqualToAnchor:overlay.widthAnchor multiplier:0.88],
        [card.heightAnchor constraintEqualToAnchor:overlay.heightAnchor multiplier:0.72],

        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:artifactsButton.leadingAnchor constant:-10.0],

        [closeButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [closeButton.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [closeButton.widthAnchor constraintEqualToConstant:28.0],
        [closeButton.heightAnchor constraintEqualToConstant:28.0],

        [artifactsButton.trailingAnchor constraintEqualToAnchor:closeButton.leadingAnchor constant:-10.0],
        [artifactsButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [artifactsButton.heightAnchor constraintEqualToConstant:28.0],
        [artifactsButton.widthAnchor constraintLessThanOrEqualToConstant:148.0],

        [summaryLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [summaryLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [summaryLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],

        [textView.topAnchor constraintEqualToAnchor:summaryLabel.bottomAnchor constant:9.0],
        [textView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12.0],
        [textView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12.0],
        [textView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12.0],
    ]];
}

- (void)_refreshDiagnosticsView {
    [self _refreshDiagnosticsButton];
    if (!self.diagnosticsOverlayView) return;
    NSString *activeRequestID = [VCChatDiagnostics shared].activeRequestID ?: @"";
    NSString *recentPath = [[VCChatDiagnostics shared] recentEventsPath].lastPathComponent ?: @"chat_diagnostics_recent.json";
    NSString *historyPath = [[VCChatDiagnostics shared] requestHistoryPath].lastPathComponent ?: @"chat_request_history.jsonl";
    self.diagnosticsSummaryLabel.text = activeRequestID.length > 0
        ? [NSString stringWithFormat:VCTextLiteral(@"Active request: %@ • recent events in %@ • request history in %@."), activeRequestID, recentPath, historyPath]
        : [NSString stringWithFormat:VCTextLiteral(@"Idle • recent events in %@ • request history in %@."), recentPath, historyPath];
    self.diagnosticsTextView.text = [self _diagnosticsFormattedText];
    if (self.diagnosticsTextView.text.length > 0) {
        NSRange bottom = NSMakeRange(MAX((NSInteger)self.diagnosticsTextView.text.length - 1, 0), 1);
        [self.diagnosticsTextView scrollRangeToVisible:bottom];
    }
}

- (void)_showDiagnostics {
    [self.view endEditing:YES];
    [self _ensureDiagnosticsOverlayIfNeeded];
    [self _refreshDiagnosticsView];
    self.diagnosticsOverlayView.hidden = NO;
    [UIView animateWithDuration:0.18 animations:^{
        self.diagnosticsOverlayView.alpha = 1.0;
    }];
}

- (void)_hideDiagnostics {
    if (!self.diagnosticsOverlayView || self.diagnosticsOverlayView.hidden) return;
    [UIView animateWithDuration:0.18 animations:^{
        self.diagnosticsOverlayView.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        self.diagnosticsOverlayView.hidden = YES;
    }];
}

- (void)_openDiagnosticsInArtifacts {
    [[NSNotificationCenter defaultCenter] postNotificationName:VCArtifactsRequestOpenModeNotification
                                                        object:self
                                                      userInfo:@{
        VCArtifactsOpenModeKey: VCArtifactsOpenModeDiagnosticsValue
    }];
    [self _hideDiagnostics];
}

- (void)_diagnosticsDidUpdate:(NSNotification *)note {
    [self _refreshDiagnosticsView];
}

- (void)_chatSessionDidChange:(NSNotification *)notification {
    if (self.suppressedSessionNotificationCount > 0) return;

    NSDictionary *userInfo = [notification.userInfo isKindOfClass:[NSDictionary class]] ? notification.userInfo : nil;
    NSString *changeKind = [userInfo[VCChatSessionChangeKindKey] isKindOfClass:[NSString class]] ? userInfo[VCChatSessionChangeKindKey] : @"session_update";
    NSString *changedSessionID = [userInfo[VCChatSessionChangedSessionIDKey] isKindOfClass:[NSString class]] ? userInfo[VCChatSessionChangedSessionIDKey] : @"";
    NSString *currentSessionID = [userInfo[VCChatSessionCurrentSessionIDKey] isKindOfClass:[NSString class]] ? userInfo[VCChatSessionCurrentSessionIDKey] : [VCChatSession shared].currentSessionID;
    BOOL messagesChanged = [userInfo[VCChatSessionMessagesChangedKey] boolValue];
    BOOL metadataChanged = [userInfo[VCChatSessionMetadataChangedKey] boolValue];
    BOOL sessionListChanged = [userInfo[VCChatSessionListChangedKey] boolValue];
    BOOL currentSessionChanged = [userInfo[VCChatSessionCurrentSessionChangedKey] boolValue];
    BOOL affectsCurrentSession = currentSessionChanged ||
        (changedSessionID.length > 0 && [changedSessionID isEqualToString:currentSessionID]) ||
        (changedSessionID.length == 0 && sessionListChanged);

    if (!affectsCurrentSession && !sessionListChanged) return;

    NSUInteger previousMessageCount = self.messages.count;
    BOOL previousStreamingActive = (self.streamingText != nil);

    if (currentSessionChanged) {
        self.streamingText = nil;
        self.hasAnimatedStreamingBubble = NO;
        self.streamingRefreshScheduled = NO;
        [self _clearTransientStatus];
        [self _reloadPendingReferences];
    }

    if (messagesChanged || currentSessionChanged) {
        [self _syncMessagesFromSessionWithPreviousCount:previousMessageCount
                               previousStreamingActive:previousStreamingActive
                                                reason:changeKind];
    } else if (metadataChanged || sessionListChanged) {
        [self _refreshChatChrome];
    }

    [self _updateSessionStateDisplay];
    [self _refreshClearButtonState];
    [[VCChatDiagnostics shared] recordEventWithPhase:@"ui"
                                            subphase:@"session_sync"
                                           sessionID:currentSessionID
                                           requestID:nil
                                          durationMS:0.0
                                               extra:@{
                                                   @"changeKind": changeKind ?: @"session_update",
                                                   @"messagesChanged": @(messagesChanged),
                                                   @"metadataChanged": @(metadataChanged),
                                                   @"sessionListChanged": @(sessionListChanged),
                                                   @"currentSessionChanged": @(currentSessionChanged)
                                               }];
}

#pragma mark - Data

- (void)_reloadMessages {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    _messages = [[VCChatSession shared] currentMessages];
    [self _syncRevealStateForMessages:_messages];
    [_tableView reloadData];
    [self _scrollToBottom:NO];
    [self _refreshChatChrome];
    double durationMS = MAX(0.0, (CFAbsoluteTimeGetCurrent() - start) * 1000.0);
    if (durationMS >= 10.0) {
        [[VCChatDiagnostics shared] recordEventWithPhase:@"ui"
                                                subphase:@"reload_messages"
                                              durationMS:durationMS
                                                   extra:@{
                                                       @"messageCount": @(_messages.count),
                                                       @"hasStreamingText": @(self.streamingText.length > 0)
                                                   }];
    }
}

- (void)_scrollToBottom:(BOOL)animated {
    NSInteger rows = [_tableView numberOfRowsInSection:0];
    if (rows > 0) {
        [_tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:rows - 1 inSection:0]
                          atScrollPosition:UITableViewScrollPositionBottom animated:animated];
    }
}

- (void)_refreshStreamingRow {
    if (self.streamingText == nil) return;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    NSIndexPath *streamingIndexPath = [NSIndexPath indexPathForRow:self.messages.count inSection:0];
    NSInteger displayedRows = [self.tableView numberOfRowsInSection:0];
    if (displayedRows <= (NSInteger)self.messages.count) {
        [self.tableView performBatchUpdates:^{
            [self.tableView insertRowsAtIndexPaths:@[streamingIndexPath] withRowAnimation:UITableViewRowAnimationFade];
        } completion:nil];
        [self _scrollToBottom:NO];
        [[VCChatDiagnostics shared] recordEventWithPhase:@"ui"
                                                subphase:@"insert_streaming_row"
                                              durationMS:MAX(0.0, (CFAbsoluteTimeGetCurrent() - start) * 1000.0)
                                                   extra:@{
                                                       @"messageCount": @(self.messages.count),
                                                       @"streamingLength": @(self.streamingText.length)
                                                   }];
        return;
    }

    VCMessage *streamingMessage = [VCMessage messageWithRole:@"assistant" content:self.streamingText];
    VCChatBubble *visibleCell = [self.tableView cellForRowAtIndexPath:streamingIndexPath];
    if ([visibleCell isKindOfClass:[VCChatBubble class]]) {
        [UIView performWithoutAnimation:^{
            [visibleCell configureWithMessage:streamingMessage];
            [visibleCell setNeedsLayout];
            [visibleCell layoutIfNeeded];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
            [CATransaction commit];
            [self.tableView layoutIfNeeded];
        }];
    } else {
        [UIView performWithoutAnimation:^{
            [self.tableView reloadRowsAtIndexPaths:@[streamingIndexPath] withRowAnimation:UITableViewRowAnimationNone];
        }];
    }
    [self _scrollToBottom:NO];
    double durationMS = MAX(0.0, (CFAbsoluteTimeGetCurrent() - start) * 1000.0);
    if (durationMS >= 8.0) {
        [[VCChatDiagnostics shared] recordEventWithPhase:@"ui"
                                                subphase:@"refresh_streaming_row"
                                              durationMS:durationMS
                                                   extra:@{
                                                       @"messageCount": @(self.messages.count),
                                                       @"streamingLength": @(self.streamingText.length)
                                                   }];
    }
}

- (void)_scheduleStreamingRefresh {
    if (self.streamingRefreshScheduled) return;
    self.streamingRefreshScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.045 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.streamingRefreshScheduled = NO;
        [self _refreshStreamingRow];
    });
}

- (void)_updateTokenDisplay {
    VCTokenTracker *tt = [VCTokenTracker shared];
    CGFloat pct = tt.usagePercent / 100.0;
    _tokenBar.progress = (float)pct;
    _tokenLabel.text = tt.usagePercent == 0
        ? VCTextLiteral(@"Context empty")
        : [NSString stringWithFormat:@"%@ %lu%%", VCTextLiteral(@"Context"), (unsigned long)tt.usagePercent];
    _tokenBar.progressTintColor = (pct > 0.9) ? kVCRed : (pct > 0.7) ? kVCYellow : kVCAccent;
    [self _refreshContextRail];
}

- (UIColor *)_chatStatusAccentColorForPhase:(NSString *)phase {
    if ([phase isEqualToString:VCTextLiteral(@"Failed")]) {
        return kVCRed;
    }
    if ([phase isEqualToString:VCTextLiteral(@"Tool Running")]) {
        return kVCYellow;
    }
    if ([phase isEqualToString:VCTextLiteral(@"Done")]) {
        return kVCGreen;
    }
    return kVCAccent;
}

- (NSDictionary *)_currentChatStatusSnapshot {
    VCProviderConfig *activeProvider = [[VCProviderManager shared] activeProvider];
    NSString *effectiveModel = [[VCProviderManager shared] effectiveSelectedModelForProvider:activeProvider];
    NSString *providerName = activeProvider.name.length ? activeProvider.name : VCTextLiteral(@"Provider");
    NSString *modelName = effectiveModel.length > 0 ? effectiveModel : VCTextLiteral(@"Not configured");
    NSString *phase = VCTextLiteral(@"Preparing");
    NSString *headline = VCTextLiteral(@"Collecting context for the next reply.");
    NSString *detail = [NSString stringWithFormat:VCTextLiteral(@"%@ / %@"), providerName, modelName];

    if (!activeProvider) {
        phase = VCTextLiteral(@"Failed");
        headline = VCTextLiteral(@"Add a provider in Settings before sending.");
        detail = VCTextLiteral(@"Chat cannot start until an active provider is selected.");
        return @{@"phase": phase, @"headline": headline, @"detail": detail};
    }
    if (activeProvider.apiKey.length == 0) {
        phase = VCTextLiteral(@"Failed");
        headline = VCTextLiteral(@"The active provider is missing an API key.");
        detail = [NSString stringWithFormat:VCTextLiteral(@"%@ needs credentials before chat can run."), providerName];
        return @{@"phase": phase, @"headline": headline, @"detail": detail};
    }
    if (effectiveModel.length == 0) {
        phase = VCTextLiteral(@"Failed");
        headline = VCTextLiteral(@"Pick a model or set a provider default before sending.");
        detail = [NSString stringWithFormat:VCTextLiteral(@"%@ is active, but no model is configured yet."), providerName];
        return @{@"phase": phase, @"headline": headline, @"detail": detail};
    }

    NSArray<NSDictionary *> *events = [[VCChatDiagnostics shared] recentEvents];
    NSDictionary *lastEvent = [events.lastObject isKindOfClass:[NSDictionary class]] ? events.lastObject : nil;
    NSString *lastPhase = [lastEvent[@"phase"] isKindOfClass:[NSString class]] ? lastEvent[@"phase"] : @"";
    NSString *lastSubphase = [lastEvent[@"subphase"] isKindOfClass:[NSString class]] ? lastEvent[@"subphase"] : @"";
    NSDictionary *lastExtra = [lastEvent[@"extra"] isKindOfClass:[NSDictionary class]] ? lastEvent[@"extra"] : @{};
    BOOL hasStreamingDraft = self.streamingText.length > 0;
    BOOL generating = [VCAIEngine shared].isGenerating;
    VCMessage *lastMessage = [self.messages.lastObject isKindOfClass:[VCMessage class]] ? self.messages.lastObject : nil;
    NSString *lastMessageContent = lastMessage.content ?: @"";
    BOOL lastMessageFailed = [lastMessageContent hasPrefix:@"[Error]"];

    if (generating) {
        if ([lastPhase isEqualToString:@"tool"]) {
            phase = VCTextLiteral(@"Tool Running");
            headline = VCTextLiteral(@"Waiting for tool results before the final answer.");
            NSNumber *count = [lastExtra[@"count"] isKindOfClass:[NSNumber class]] ? lastExtra[@"count"] : nil;
            detail = count ? [NSString stringWithFormat:VCTextLiteral(@"%lu tool action(s) are in flight."), (unsigned long)count.unsignedIntegerValue]
                           : [NSString stringWithFormat:VCTextLiteral(@"%@ / %@"), providerName, modelName];
        } else if (hasStreamingDraft || [lastPhase isEqualToString:@"stream"]) {
            phase = VCTextLiteral(@"Streaming");
            headline = VCTextLiteral(@"Reply tokens are arriving now.");
            NSNumber *visibleLength = [lastExtra[@"visibleLength"] isKindOfClass:[NSNumber class]] ? lastExtra[@"visibleLength"] : nil;
            detail = visibleLength ? [NSString stringWithFormat:VCTextLiteral(@"Current visible length: %lu characters."), (unsigned long)visibleLength.unsignedIntegerValue]
                                   : [NSString stringWithFormat:VCTextLiteral(@"%@ / %@"), providerName, modelName];
        } else {
            phase = VCTextLiteral(@"Preparing");
            headline = VCTextLiteral(@"Collecting context for the next reply.");
            detail = [NSString stringWithFormat:VCTextLiteral(@"%@ / %@"), providerName, modelName];
        }
    } else if ([lastPhase isEqualToString:@"request"] && [lastSubphase isEqualToString:@"error"]) {
        phase = VCTextLiteral(@"Failed");
        headline = [lastExtra[@"error"] isKindOfClass:[NSString class]] && [lastExtra[@"error"] length] > 0
            ? lastExtra[@"error"]
            : VCTextLiteral(@"The last request failed before finishing.");
        detail = [NSString stringWithFormat:VCTextLiteral(@"%@ / %@"), providerName, modelName];
    } else if (self.transientStatusText.length > 0) {
        phase = (self.transientStatusColor == kVCRed) ? VCTextLiteral(@"Failed") : VCTextLiteral(@"Done");
        headline = self.transientStatusText;
        detail = [NSString stringWithFormat:VCTextLiteral(@"%@ / %@"), providerName, modelName];
    } else if (lastMessageFailed) {
        phase = VCTextLiteral(@"Failed");
        headline = VCTextLiteral(@"The last reply ended with an error.");
        detail = lastMessage.content.length > 8 ? [lastMessage.content substringFromIndex:8] : (lastMessage.content ?: @"");
    } else if ([lastMessage.role isEqualToString:@"assistant"]) {
        phase = VCTextLiteral(@"Done");
        headline = VCTextLiteral(@"The last reply is ready to review.");
        detail = [NSString stringWithFormat:VCTextLiteral(@"%@ / %@"), providerName, modelName];
    } else {
        phase = VCTextLiteral(@"Done");
        headline = VCTextLiteral(@"Ready for the next prompt.");
        detail = [NSString stringWithFormat:VCTextLiteral(@"%@ / %@"), providerName, modelName];
    }

    return @{@"phase": phase ?: @"",
             @"headline": headline ?: @"",
             @"detail": detail ?: @""};
}

- (void)_applyChatStatusSnapshot:(NSDictionary *)snapshot {
    NSString *phase = [snapshot[@"phase"] isKindOfClass:[NSString class]] ? snapshot[@"phase"] : VCTextLiteral(@"Preparing");
    NSString *headline = [snapshot[@"headline"] isKindOfClass:[NSString class]] ? snapshot[@"headline"] : @"";
    NSString *detail = [snapshot[@"detail"] isKindOfClass:[NSString class]] ? snapshot[@"detail"] : @"";
    UIColor *accent = [self _chatStatusAccentColorForPhase:phase];
    self.statusPhaseLabel.text = [NSString stringWithFormat:@"  %@  ", phase];
    self.statusPhaseLabel.textColor = accent;
    self.statusPhaseLabel.backgroundColor = [accent colorWithAlphaComponent:0.12];
    self.statusPhaseLabel.layer.borderColor = [accent colorWithAlphaComponent:0.22].CGColor;
    self.statusHeadlineLabel.text = headline;
    self.statusHeadlineLabel.textColor = [phase isEqualToString:VCTextLiteral(@"Failed")] ? accent : kVCTextPrimary;
    self.statusDetailLabel.text = detail;
    self.statusDetailLabel.textColor = [phase isEqualToString:VCTextLiteral(@"Failed")] ? [accent colorWithAlphaComponent:0.92] : kVCTextMuted;
    self.sessionStateLabel.text = detail.length > 0 ? [NSString stringWithFormat:@"%@ • %@", phase, detail] : phase;
    self.sessionStateLabel.textColor = accent;
}

- (void)_updateSessionStateDisplay {
    NSDictionary *snapshot = [self _currentChatStatusSnapshot];
    [self _applyChatStatusSnapshot:snapshot];
    [self _refreshContextRail];
}

- (void)_refreshProviderDisplay {
    VCProviderConfig *active = [[VCProviderManager shared] activeProvider];
    NSString *modelTitle = VCTextLiteral(@"No Provider");
    if (active) {
        NSString *modelName = [[VCProviderManager shared] effectiveSelectedModelForProvider:active];
        if (modelName.length == 0) {
            modelName = VCTextLiteral(@"Not configured");
        }
        modelTitle = modelName;
    }
    [_modelButton setTitle:modelTitle forState:UIControlStateNormal];
    [_modelButton setImage:nil forState:UIControlStateNormal];
    NSString *compactTitle = active ? [[VCProviderManager shared] effectiveSelectedModelForProvider:active] : VCTextLiteral(@"Model");
    if (compactTitle.length == 0) compactTitle = VCTextLiteral(@"Model");
    [self.contextModelButton setTitle:compactTitle forState:UIControlStateNormal];
    VCSetButtonSymbol(self.contextModelButton, @"cpu");
    [self _refreshContextRail];
}

- (void)_setTransientStatus:(NSString *)status color:(UIColor *)color {
    self.transientStatusText = status;
    self.transientStatusColor = color;
    [self _updateSessionStateDisplay];
}

- (void)_clearTransientStatus {
    self.transientStatusText = nil;
    self.transientStatusColor = nil;
    [self _updateSessionStateDisplay];
}

#pragma mark - Control Inbox

- (NSString *)_controlInboxPath {
    NSString *directory = [[[VCConfig shared] sandboxPath] stringByAppendingPathComponent:@"control"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return [directory stringByAppendingPathComponent:@"chat_command.json"];
}

- (void)_startControlInboxPolling {
    if (self.controlInboxTimer) return;
    self.controlInboxTimer = [NSTimer scheduledTimerWithTimeInterval:0.75
                                                              target:self
                                                            selector:@selector(_pollControlInbox)
                                                            userInfo:nil
                                                             repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.controlInboxTimer forMode:NSRunLoopCommonModes];
}

- (void)_pollControlInbox {
    NSString *path = [self _controlInboxPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) return;

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *command = (NSDictionary *)object;

    NSString *commandID = [command[@"id"] isKindOfClass:[NSString class]] ? command[@"id"] : @"";
    if (commandID.length == 0) {
        commandID = [NSString stringWithFormat:@"%lu", (unsigned long)data.hash];
    }
    if ([commandID isEqualToString:self.lastControlCommandID]) return;

    NSString *text = [command[@"text"] isKindOfClass:[NSString class]] ? command[@"text"] : @"";
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return;

    self.lastControlCommandID = commandID;
    self.inputTextView.text = text;
    [self _updateInputTextHeight];
    [self _refreshComposerState];

    BOOL shouldSend = [command[@"send"] respondsToSelector:@selector(boolValue)] ? [command[@"send"] boolValue] : YES;
    if (shouldSend) {
        [self _sendMessage];
    } else {
        [self.inputTextView becomeFirstResponder];
    }
}

#pragma mark - Send

- (void)_sendMessage {
    if ([VCAIEngine shared].isGenerating) {
        NSUInteger previousMessageCount = self.messages.count;
        BOOL previousStreamingActive = (self.streamingText != nil);
        self.stopRequested = YES;
        [[VCAIEngine shared] stopGeneration];
        _streamingText = nil;
        self.hasAnimatedStreamingBubble = NO;
        self.streamingRefreshScheduled = NO;
        [[VCChatSession shared] clearStreamingDraft];
        [self _syncMessagesFromSessionWithPreviousCount:previousMessageCount
                               previousStreamingActive:previousStreamingActive
                                                reason:@"manual_stop"];
        [self _setSendButtonGenerating:NO];
        [self _setTransientStatus:VCTextLiteral(@"Generation stopped") color:kVCYellow];
        [self _refreshComposerState];
        return;
    }

    NSString *text = [_inputTextView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) return;
    [_inputTextView resignFirstResponder];
    [self.view endEditing:YES];

    VCProviderManager *providerManager = [VCProviderManager shared];
    VCProviderConfig *activeProvider = [providerManager activeProvider];
    NSString *effectiveModel = [providerManager effectiveSelectedModelForProvider:activeProvider];
    if (!activeProvider) {
        [self _appendErrorMessage:VCTextLiteral(@"Add a provider in Settings to start chatting.")];
        [self _setTransientStatus:VCTextLiteral(@"Add a provider in Settings to start chatting.") color:kVCRed];
        [self _reloadMessages];
        return;
    }
    if (!activeProvider || activeProvider.apiKey.length == 0) {
        [self _appendErrorMessage:VCTextLiteral(@"No API key configured")];
        [self _setTransientStatus:VCTextLiteral(@"The active provider is missing an API key.") color:kVCRed];
        [self _reloadMessages];
        return;
    }
    if (effectiveModel.length == 0) {
        [self _appendErrorMessage:VCTextLiteral(@"No model selected for the active provider")];
        [self _setTransientStatus:VCTextLiteral(@"Pick a model or set a provider default before sending.") color:kVCRed];
        [self _reloadMessages];
        return;
    }

    _inputTextView.text = @"";
    [self _updateInputTextHeight];
    [self _setTransientStatus:[NSString stringWithFormat:@"%@ %@ / %@", VCTextLiteral(@"Sending with"), activeProvider.name ?: VCTextLiteral(@"Provider"), effectiveModel] color:kVCAccent];

    NSUInteger previousMessageCount = self.messages.count;
    BOOL previousStreamingActive = (self.streamingText != nil);
    // Streaming placeholder
    _streamingText = @"";
    self.hasAnimatedStreamingBubble = NO;
    self.streamingRefreshScheduled = NO;
    self.stopRequested = NO;
    [self _setSendButtonGenerating:YES];
    [self _refreshComposerState];
    VCContextCollector *collector = [VCContextCollector shared];
    NSArray<NSDictionary *> *pendingReferences = [[[VCChatSession shared] pendingReferences] copy];
    CFAbsoluteTime contextStart = CFAbsoluteTimeGetCurrent();
    NSDictionary *context = @{
        @"workspace": @{
            @"inspect": [collector collectContextForTab:@"inspect"],
            @"network": [collector collectContextForTab:@"network"],
            @"ui": [collector collectContextForTab:@"ui"],
            @"patches": [collector collectContextForTab:@"patches"],
            @"console": [collector collectContextForTab:@"console"],
        },
        @"runtimeCapabilities": [[VCCapabilityManager shared] capabilitiesSnapshot],
        @"manualReferences": pendingReferences ?: @[]
    };
    NSDictionary *workspace = [context[@"workspace"] isKindOfClass:[NSDictionary class]] ? context[@"workspace"] : @{};
    NSUInteger workspaceSignalCount = 0;
    for (NSString *key in @[@"inspect", @"network", @"ui", @"patches", @"console"]) {
        id payload = workspace[key];
        BOOL hasSignal = NO;
        if ([payload isKindOfClass:[NSDictionary class]]) {
            hasSignal = [(NSDictionary *)payload count] > 0;
        } else if ([payload isKindOfClass:[NSArray class]]) {
            hasSignal = [(NSArray *)payload count] > 0;
        } else if (payload) {
            hasSignal = YES;
        }
        if (hasSignal) workspaceSignalCount += 1;
    }
    [[VCChatDiagnostics shared] recordEventWithPhase:@"ui"
                                            subphase:@"context_collect"
                                           sessionID:[VCChatSession shared].currentSessionID
                                           requestID:nil
                                          durationMS:MAX(0.0, (CFAbsoluteTimeGetCurrent() - contextStart) * 1000.0)
                                               extra:@{
                                                   @"manualReferenceCount": @(pendingReferences.count),
                                                   @"workspaceSignalCount": @(workspaceSignalCount)
                                               }];

    if (pendingReferences.count > 0) {
        [[VCChatSession shared] clearPendingReferences];
        [self _reloadPendingReferences];
    }

    __weak __typeof__(self) weakSelf = self;
    __block BOOL requestCompletedInline = NO;
    [[VCAIEngine shared] sendMessage:text withContext:context streaming:YES
        onChunk:^(NSString *chunk) {
            __strong __typeof__(weakSelf) self2 = weakSelf;
            if (!self2) return;
            self2->_streamingText = [self2->_streamingText stringByAppendingString:chunk];
            [[VCChatSession shared] updateStreamingDraft:self2->_streamingText];
            vc_dispatch_main(^{
                [self2 _scheduleStreamingRefresh];
            });
        }
        onToolCall:^(VCToolCall *toolCall) {
            VCLog(@"[Chat] Tool call: %@", toolCall.title);
        }
        completion:^(VCMessage *message, NSError *error) {
            __strong __typeof__(weakSelf) self2 = weakSelf;
            if (!self2) return;
            requestCompletedInline = YES;
            vc_dispatch_main(^{
                NSUInteger completionPreviousCount = self2.messages.count;
                BOOL completionPreviousStreamingActive = (self2.streamingText != nil);
                self2->_streamingText = nil;
                self2.hasAnimatedStreamingBubble = NO;
                self2.streamingRefreshScheduled = NO;
                [[VCChatSession shared] clearStreamingDraft];
                BOOL cancelledByStop = self2.stopRequested &&
                    ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled);
                self2.stopRequested = NO;
                if (error && !cancelledByStop) {
                    [self2 _appendErrorMessage:error.localizedDescription];
                    [self2 _setTransientStatus:error.localizedDescription color:kVCRed];
                } else if (cancelledByStop) {
                    [self2 _setTransientStatus:VCTextLiteral(@"Generation stopped") color:kVCYellow];
                } else {
                    [[VCChatSession shared] clearPendingReferences];
                    [self2 _clearTransientStatus];
                }
                [self2 _syncMessagesFromSessionWithPreviousCount:completionPreviousCount
                                       previousStreamingActive:completionPreviousStreamingActive
                                                        reason:(error ? @"completion_error" : @"completion")];
                [self2 _setSendButtonGenerating:NO];
                [self2 _refreshComposerState];
            });
        }];
    if (!requestCompletedInline) {
        [self _syncMessagesFromSessionWithPreviousCount:previousMessageCount
                               previousStreamingActive:previousStreamingActive
                                                reason:@"send"];
    }
}

- (void)_appendErrorMessage:(NSString *)errorText {
    VCMessage *errMsg = [VCMessage messageWithRole:@"assistant" content:[NSString stringWithFormat:@"[Error] %@", errorText]];
    [[VCChatSession shared] addMessage:errMsg];
    [[VCChatSession shared] saveAll];
}

#pragma mark - Model Selector

- (void)_showModelSelector {
    [self.view endEditing:YES];
    [VCModelSelector showFromViewController:self completion:^(NSString *providerID, NSString *model) {
        [[VCAIEngine shared] switchProvider:providerID model:model];
        [self _refreshProviderDisplay];
        [self _clearTransientStatus];
    }];
}

- (void)_confirmClearChat {
    BOOL hasMessages = self.messages.count > 0 || self.streamingText.length > 0;
    if (!hasMessages) return;

    [self.view endEditing:YES];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:VCTextLiteral(@"Clear current chat?")
                                                                   message:VCTextLiteral(@"This removes the current conversation history and saved draft for this chat.")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak __typeof__(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:VCTextLiteral(@"Clear")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        __strong __typeof__(weakSelf) self2 = weakSelf;
        if (!self2) return;
        NSUInteger previousMessageCount = self2.messages.count;
        BOOL previousStreamingActive = (self2.streamingText != nil);
        if ([VCAIEngine shared].isGenerating) {
            [[VCAIEngine shared] stopGeneration];
        }
        self2->_streamingText = nil;
        self2.hasAnimatedStreamingBubble = NO;
        self2.streamingRefreshScheduled = NO;
        [self2 _performSuppressingSessionNotifications:^{
            [[VCChatSession shared] clearCurrentSessionMessages];
        }];
        [self2 _clearTransientStatus];
        [self2 _syncMessagesFromSessionWithPreviousCount:previousMessageCount
                               previousStreamingActive:previousStreamingActive
                                                reason:@"clear_chat"];
        [self2 _setSendButtonGenerating:NO];
        [self2 _refreshComposerState];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:VCTextLiteral(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.clearChatButton;
        alert.popoverPresentationController.sourceRect = self.clearChatButton.bounds;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = (NSInteger)_messages.count;
    if (_streamingText) count++; // streaming placeholder row
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    VCChatBubble *cell = [tableView dequeueReusableCellWithIdentifier:kBubbleCellID forIndexPath:indexPath];

    if (_streamingText && indexPath.row == (NSInteger)_messages.count) {
        NSString *streamingDisplay = _streamingText.length > 0 ? [_streamingText stringByAppendingString:@" ▍"] : @"▍";
        VCMessage *streamingMessage = [VCMessage messageWithRole:@"assistant" content:streamingDisplay];
        [cell configureWithMessage:streamingMessage];
    } else if (indexPath.row < (NSInteger)_messages.count) {
        VCMessage *msg = _messages[indexPath.row];
        [cell configureWithMessage:msg];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (indexPath.row >= (NSInteger)_messages.count) return;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView != self.tableView) return;

    BOOL shouldAnimate = NO;
    if (self.streamingText != nil && indexPath.row == (NSInteger)self.messages.count) {
        shouldAnimate = !self.hasAnimatedStreamingBubble;
        self.hasAnimatedStreamingBubble = YES;
    } else if (indexPath.row < (NSInteger)self.messages.count) {
        VCMessage *message = self.messages[indexPath.row];
        if ([message.messageID isKindOfClass:[NSString class]] && message.messageID.length > 0 &&
            ![self.revealedMessageIDs containsObject:message.messageID]) {
            [self.revealedMessageIDs addObject:message.messageID];
            shouldAnimate = YES;
        }
    }

    if (!shouldAnimate) {
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
        return;
    }

    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeTranslation(0, 10.0);
    [UIView animateWithDuration:0.28
                          delay:0
         usingSpringWithDamping:0.92
          initialSpringVelocity:0.16
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
               contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                                   point:(CGPoint)point {
    if (indexPath.row >= (NSInteger)_messages.count) return nil;
    VCMessage *msg = _messages[indexPath.row];

    __weak __typeof__(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:msg.messageID previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        __strong __typeof__(weakSelf) self2 = weakSelf;
        if (!self2) return nil;

        UIAction *copyAction = [UIAction actionWithTitle:@"Copy"
                                                   image:[UIImage systemImageNamed:@"doc.on.doc"]
                                              identifier:nil
                                                 handler:^(__kindof UIAction * _Nonnull action) {
            [UIPasteboard generalPasteboard].string = msg.content ?: @"";
        }];

        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray arrayWithObject:copyAction];
        if ([msg.role isEqualToString:@"user"]) {
            UIAction *editAction = [UIAction actionWithTitle:@"Edit & Resend"
                                                       image:[UIImage systemImageNamed:@"square.and.pencil"]
                                                  identifier:nil
                                                     handler:^(__kindof UIAction * _Nonnull action) {
                self2->_inputTextView.text = msg.content ?: @"";
                [self2->_inputTextView becomeFirstResponder];
            }];
            [actions addObject:editAction];
        } else if ([msg.role isEqualToString:@"assistant"] && msg.content.length > 0) {
            UIAction *reuseAction = [UIAction actionWithTitle:@"Use as Prompt"
                                                        image:[UIImage systemImageNamed:@"arrow.uturn.backward.circle"]
                                                   identifier:nil
                                                      handler:^(__kindof UIAction * _Nonnull action) {
                self2->_inputTextView.text = msg.content ?: @"";
                [self2 _updateInputTextHeight];
                [self2->_inputTextView becomeFirstResponder];
            }];
            [actions addObject:reuseAction];
        }

        UIAction *deleteAction = [UIAction actionWithTitle:@"Delete"
                                                     image:[UIImage systemImageNamed:@"trash"]
                                                identifier:nil
                                                   handler:^(__kindof UIAction * _Nonnull action) {
            NSUInteger previousMessageCount = self2.messages.count;
            BOOL previousStreamingActive = (self2.streamingText != nil);
            [[VCChatSession shared] deleteMessage:msg.messageID];
            [self2 _syncMessagesFromSessionWithPreviousCount:previousMessageCount
                                   previousStreamingActive:previousStreamingActive
                                                    reason:@"delete_message"];
        }];
        deleteAction.attributes = UIMenuElementAttributesDestructive;
        [actions addObject:deleteAction];
        return [UIMenu menuWithTitle:@"" children:actions];
    }];
}

#pragma mark - Keyboard

- (void)_keyboardWillChange:(NSNotification *)note {
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect convertedEndFrame = self.view.window ? [self.view convertRect:endFrame fromView:nil] : endFrame;
    CGFloat offset = MAX(0.0, CGRectGetHeight(self.view.bounds) - CGRectGetMinY(convertedEndFrame));
    _inputBarBottom.constant = -offset;
    NSTimeInterval dur = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:dur animations:^{ [self.view layoutIfNeeded]; }];
}

- (void)_pendingReferencesChanged {
    [self _reloadPendingReferences];
}

- (void)_providerChanged {
    [self _refreshProviderDisplay];
    [self _updateSessionStateDisplay];
    [self _refreshClearButtonState];
}

- (void)_languageChanged {
    [self _refreshProviderDisplay];
    [self _clearTransientStatus];
    [self _refreshComposerState];
}

- (void)_reloadPendingReferences {
    NSArray<NSDictionary *> *references = [[VCChatSession shared] pendingReferences];
    for (UIView *view in [self.referenceStack.arrangedSubviews copy]) {
        [self.referenceStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (UIView *view in [self.referenceRailStack.arrangedSubviews copy]) {
        [self.referenceRailStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSDictionary *reference in references) {
        [self.referenceStack addArrangedSubview:[self _referenceChipForReference:reference vertical:NO]];
        [self.referenceRailStack addArrangedSubview:[self _referenceChipForReference:reference vertical:YES]];
    }
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape);
    BOOL compactLandscape = landscape && !CGRectIsEmpty(self.availableLayoutBounds) && CGRectGetHeight(self.availableLayoutBounds) < 320.0;
    BOOL showsLandscapeRail = landscape && !compactLandscape;
    CGFloat preferredHeight = showsLandscapeRail ? 0.0 : 34.0;
    self.referenceStripHeight.constant = references.count > 0 ? preferredHeight : 0.0;
    self.referenceScrollView.hidden = showsLandscapeRail || (references.count == 0);
    self.referenceRailEmptyLabel.hidden = (references.count > 0);
    self.referenceRailScrollView.hidden = (references.count == 0);
    self.referenceRailSubtitleLabel.text = references.count > 0
        ? [NSString stringWithFormat:VCTextLiteral(@"%lu item(s) are ready to be included with your next message."), (unsigned long)references.count]
        : VCTextLiteral(@"Picked UI nodes, memory pages, inspect payloads, and manual references stay here while you chat.");
    self.referenceRailSubtitleLabel.hidden = showsLandscapeRail;
    self.referenceRailScrollTopToSubtitleConstraint.active = !self.referenceRailSubtitleLabel.hidden;
    self.referenceRailScrollTopToTitleConstraint.active = self.referenceRailSubtitleLabel.hidden;
    self.referenceRailEmptyLabel.textAlignment = showsLandscapeRail ? NSTextAlignmentLeft : NSTextAlignmentNatural;
    [self.view layoutIfNeeded];
    [self _refreshContextRail];
}

- (void)_applyCurrentLayoutMode {
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape);
    CGFloat availableWidth = CGRectIsEmpty(self.availableLayoutBounds) ? CGRectGetWidth(self.view.bounds) : CGRectGetWidth(self.availableLayoutBounds);
    CGFloat availableHeight = CGRectIsEmpty(self.availableLayoutBounds) ? CGRectGetHeight(self.view.bounds) : CGRectGetHeight(self.availableLayoutBounds);
    BOOL compactLandscape = landscape && availableHeight < 320.0;
    BOOL shallowLandscape = landscape && availableHeight < 460.0;
    BOOL showsLandscapeRail = landscape && !compactLandscape;
    CGFloat contextRailWidth = 0.0;
    if (showsLandscapeRail) {
        contextRailWidth = shallowLandscape
            ? MIN(MAX(floor(availableWidth * 0.28), 220.0), 300.0)
            : MIN(MAX(floor(availableWidth * 0.32), 252.0), 344.0);
    }

    self.topBarHeightConstraint.constant = landscape ? 0.0 : 52.0;
    self.tokenBarWidthConstraint.constant = landscape ? 64.0 : 78.0;
    self.inputBarMinHeightConstraint.constant = landscape ? (shallowLandscape ? 62.0 : 74.0) : 166.0;
    self.contextSummaryTopConstraint.constant = landscape ? 8.0 : 0.0;
    self.referenceRailTopConstraint.constant = landscape ? 6.0 : 10.0;
    self.workspaceTopConstraint.constant = 8.0;
    self.workspaceTopConstraint.active = !landscape;
    self.workspaceTopToViewConstraint.active = landscape;
    self.contextRailWidthConstraint.constant = contextRailWidth;
    self.contextRailSpacingConstraint.constant = contextRailWidth > 0.0 ? 10.0 : 0.0;
    self.contextRailView.hidden = (contextRailWidth <= 0.0);
    self.contextRailView.alpha = (contextRailWidth > 0.0) ? 1.0 : 0.0;
    self.sidebarDividerView.hidden = !landscape || contextRailWidth <= 0.0;
    self.sidebarDividerView.alpha = (!self.sidebarDividerView.hidden) ? 1.0 : 0.0;
    self.contextRailDividerView.hidden = !landscape || contextRailWidth <= 0.0;
    self.contextRailDividerView.alpha = (!self.contextRailDividerView.hidden) ? 1.0 : 0.0;
    self.topBarView.hidden = landscape;
    self.topBarView.alpha = landscape ? 0.0 : 1.0;
    self.statusHeadlineLabel.hidden = YES;
    self.statusDetailLabel.hidden = YES;
    self.statusHeadlineLabel.numberOfLines = 1;
    self.statusDetailLabel.numberOfLines = 1;
    self.inputPlaceholderLabel.numberOfLines = shallowLandscape ? 1 : (landscape ? 2 : 3);
    self.contextSummaryBodyLabel.numberOfLines = shallowLandscape ? 1 : 2;
    self.contextSummaryMetaLabel.numberOfLines = landscape ? 2 : 3;
    self.referenceRailSubtitleLabel.numberOfLines = landscape ? 1 : 3;
    self.modelButtonTopConstraint.constant = 8.0;
    self.sessionStateTopConstraint.active = NO;
    self.statusPhaseCenterYConstraint.active = !landscape;
    self.statusHeadlineTopConstraint.active = NO;
    self.statusDetailTopConstraint.active = NO;
    self.tokenLabelTopConstraint.constant = 10.0;
    self.tokenBarTopConstraint.constant = 6.0;
    self.clearButtonBottomConstraint.constant = -9.0;
    self.modelButton.contentEdgeInsets = landscape ? UIEdgeInsetsMake(3, 8, 3, 8) : UIEdgeInsetsMake(6, 8, 6, 8);
    self.modelButton.titleLabel.font = [UIFont systemFontOfSize:(landscape ? 9.5 : 10.5) weight:UIFontWeightSemibold];
    self.tokenLabel.font = [UIFont systemFontOfSize:(landscape ? 10.0 : 11.0) weight:UIFontWeightSemibold];
    self.statusPhaseLabel.font = [UIFont systemFontOfSize:(landscape ? 8.5 : 9.5) weight:UIFontWeightBold];
    self.statusHeadlineLabel.font = [UIFont systemFontOfSize:(landscape ? 10.0 : 11.0) weight:UIFontWeightSemibold];
    self.statusDetailLabel.font = [UIFont systemFontOfSize:(landscape ? 9.0 : 10.0) weight:UIFontWeightMedium];
    self.composerTitleLabel.font = [UIFont systemFontOfSize:(landscape ? 10.0 : 10.0) weight:UIFontWeightBold];
    self.toolsChipLabel.font = [UIFont systemFontOfSize:(landscape ? 9.5 : 10.0) weight:UIFontWeightSemibold];
    self.contextChipLabel.font = [UIFont systemFontOfSize:(landscape ? 9.5 : 10.0) weight:UIFontWeightSemibold];
    for (UIView *view in self.quickCommandStack.arrangedSubviews) {
        if (![view isKindOfClass:[UIButton class]]) continue;
        UIButton *button = (UIButton *)view;
        button.titleLabel.font = [UIFont systemFontOfSize:(landscape ? 9.0 : 10.5) weight:UIFontWeightSemibold];
    }
    self.composerTitleLabel.hidden = landscape;
    self.toolsChipLabel.hidden = landscape;
    self.contextChipLabel.hidden = landscape;
    self.quickCommandStack.hidden = landscape;
    self.referenceTopConstraint.constant = 10.0;
    self.inputSurfaceTopConstraint.constant = 8.0;
    self.inputSurfaceTopConstraint.active = !landscape;
    self.inputSurfaceTopToComposerConstraint.constant = landscape ? 7.0 : 10.0;
    self.inputSurfaceTopToComposerConstraint.active = landscape;
    self.inputTextView.font = [UIFont systemFontOfSize:(landscape ? 11.2 : 14.0)];
    self.inputTextView.textContainerInset = landscape ? UIEdgeInsetsMake(5, 7, 5, 7) : UIEdgeInsetsMake(10, 10, 10, 10);
    self.sendButton.contentEdgeInsets = landscape ? UIEdgeInsetsMake(0, 8, 0, 8) : UIEdgeInsetsMake(0, 14, 0, 14);
    self.sendButton.titleLabel.font = [UIFont systemFontOfSize:(landscape ? 10.6 : 13.0) weight:UIFontWeightBold];
    self.sendButtonWidthConstraint.constant = landscape ? 66.0 : 92.0;
    UIEdgeInsets insets = landscape ? UIEdgeInsetsMake(2.0, 0, 6.0, 0) : UIEdgeInsetsMake(3.0, 0, 8.0, 0);
    self.tableView.contentInset = insets;
    self.tableView.scrollIndicatorInsets = insets;
    [self _applyWorkbenchChromeToContainer:self.conversationColumnView enabled:landscape];
    [self _applyWorkbenchChromeToContainer:self.contextRailView enabled:showsLandscapeRail && contextRailWidth > 0.0];
    [self _applySectionChromeToView:self.contextSummaryCard flattened:landscape];
    [self _applySectionChromeToView:self.referenceRailCard flattened:landscape];
    [self _applySectionChromeToView:self.composerCard flattened:landscape];
    self.inputBarPreferredHeightConstraint.active = showsLandscapeRail && !shallowLandscape;
    self.inputBarPreferredHeightConstraint.constant = landscape ? MIN(MAX(availableHeight * 0.16, 72.0), 104.0) : 166.0;
    self.contextSummaryCard.hidden = (contextRailWidth <= 0.0);
    self.referenceRailCard.hidden = (contextRailWidth <= 0.0);
    if (showsLandscapeRail && !shallowLandscape) {
        [self _mountInputBarInRailIfNeeded];
    } else {
        [self _mountInputBarInConversationIfNeeded];
    }
    [self _updateInputTextHeight];
    [self _refreshContextRail];
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    self.availableLayoutBounds = bounds;
    [self _applyCurrentLayoutMode];
    [self _reloadPendingReferences];
}

- (void)_removeReferenceChip:(UIButton *)sender {
    [[VCChatSession shared] removePendingReferenceByID:sender.accessibilityIdentifier ?: @""];
}

#pragma mark - Composer

- (void)_setSendButtonGenerating:(BOOL)generating {
    NSString *title = generating ? VCTextLiteral(@"Stop") : VCTextLiteral(@"Send");
    NSString *imageName = generating ? @"stop.fill" : @"arrow.up";
    UIColor *background = generating ? kVCRed : kVCAccent;
    UIColor *foreground = generating ? [UIColor whiteColor] : kVCBgPrimary;

    [self.sendButton setTitle:title forState:UIControlStateNormal];
    [self.sendButton setImage:[UIImage systemImageNamed:imageName] forState:UIControlStateNormal];
    [self.sendButton setTitleColor:foreground forState:UIControlStateNormal];
    self.sendButton.tintColor = foreground;
    self.sendButton.backgroundColor = background;
    self.sendButton.layer.borderWidth = 1.0;
    self.sendButton.layer.borderColor = [background colorWithAlphaComponent:0.30].CGColor;
    self.sendButton.layer.shadowColor = background.CGColor;
    self.sendButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.sendButton.titleLabel.minimumScaleFactor = 0.78;
    self.sendButton.titleEdgeInsets = UIEdgeInsetsMake(0, 3, 0, -3);
}

- (void)_quickPromptTapped:(UIButton *)sender {
    NSString *prompt = sender.accessibilityValue.length > 0 ? sender.accessibilityValue : (sender.currentTitle ?: @"");
    if (prompt.length == 0) return;
    self.inputTextView.text = prompt;
    [self _updateInputTextHeight];
    [self _refreshComposerState];
    [self.inputTextView becomeFirstResponder];
}

- (void)_updateInputTextHeight {
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape);
    BOOL compactLandscape = landscape && !CGRectIsEmpty(self.availableLayoutBounds) && CGRectGetHeight(self.availableLayoutBounds) < 320.0;
    CGFloat minHeight = landscape ? (compactLandscape ? 32.0 : 40.0) : 72.0;
    CGFloat maxHeight = landscape ? (compactLandscape ? 54.0 : 70.0) : 148.0;
    CGFloat targetHeight = MIN(maxHeight, MAX(minHeight, ceil(self.inputTextView.contentSize.height)));
    self.inputTextHeightConstraint.constant = targetHeight;
}

- (void)_refreshComposerState {
    BOOL hasText = [[self.inputTextView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
    BOOL generating = [VCAIEngine shared].isGenerating || (self.streamingText != nil);
    self.inputPlaceholderLabel.hidden = self.inputTextView.text.length > 0;
    self.sendButton.enabled = generating || hasText;
    self.sendButton.alpha = (generating || hasText) ? 1.0 : 0.55;
}

- (void)_refreshEmptyStateVisibility {
    BOOL showEmpty = (self.messages.count == 0 && self.streamingText.length == 0);
    self.emptyStateView.hidden = !showEmpty;
    self.emptyStateView.alpha = showEmpty ? 1.0 : 0.0;
}

- (UIButton *)_referenceChipForReference:(NSDictionary *)reference vertical:(BOOL)vertical {
    NSString *kind = [reference[@"kind"] isKindOfClass:[NSString class]] ? reference[@"kind"] : @"Ref";
    NSString *title = [reference[@"title"] isKindOfClass:[NSString class]] ? reference[@"title"] : VCTextLiteral(@"Attached");
    UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    chip.backgroundColor = [kVCBgHover colorWithAlphaComponent:0.98];
    chip.layer.cornerRadius = vertical ? 14.0 : 11.0;
    chip.layer.borderWidth = 1.0;
    chip.layer.borderColor = [kVCBorderStrong colorWithAlphaComponent:0.88].CGColor;
    chip.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    chip.tintColor = kVCAccentHover;
    chip.accessibilityIdentifier = reference[@"referenceID"];
    chip.adjustsImageWhenHighlighted = NO;
    [chip setImage:[UIImage systemImageNamed:VCChatReferenceChipIconName(kind)] forState:UIControlStateNormal];
    [chip addTarget:self action:@selector(_removeReferenceChip:) forControlEvents:UIControlEventTouchUpInside];

    if (vertical) {
        [chip setTitle:[NSString stringWithFormat:@"%@\n%@", kind, title] forState:UIControlStateNormal];
        [chip setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        chip.titleLabel.numberOfLines = 2;
        chip.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        chip.titleLabel.adjustsFontSizeToFitWidth = YES;
        chip.titleLabel.minimumScaleFactor = 0.84;
        chip.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        chip.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
        chip.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 6);
        [chip.heightAnchor constraintGreaterThanOrEqualToConstant:52.0].active = YES;
    } else {
        [chip setTitle:[NSString stringWithFormat:@"%@ • %@  ×", kind, title] forState:UIControlStateNormal];
        [chip setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        chip.titleLabel.numberOfLines = 1;
        chip.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        chip.titleLabel.adjustsFontSizeToFitWidth = YES;
        chip.titleLabel.minimumScaleFactor = 0.82;
        chip.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
        chip.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
        [chip.widthAnchor constraintLessThanOrEqualToConstant:240.0].active = YES;
    }

    return chip;
}

- (void)_refreshContextRail {
    VCProviderConfig *activeProvider = [[VCProviderManager shared] activeProvider];
    NSString *providerName = activeProvider.name.length ? activeProvider.name : VCTextLiteral(@"No Provider");
    NSString *modelName = activeProvider ? [[VCProviderManager shared] effectiveSelectedModelForProvider:activeProvider] : @"";
    if (modelName.length == 0) {
        modelName = activeProvider ? VCTextLiteral(@"Not configured") : VCTextLiteral(@"Configure one in Settings");
    }
    if (self.currentLayoutMode == VCPanelLayoutModeLandscape) {
        self.contextSummaryBodyLabel.text = [NSString stringWithFormat:@"%@\n%@", providerName, modelName];
    } else {
        self.contextSummaryBodyLabel.text = [NSString stringWithFormat:@"%@\n%@", providerName, modelName];
    }

    VCTokenTracker *tracker = [VCTokenTracker shared];
    NSArray<NSDictionary *> *references = [[VCChatSession shared] pendingReferences];
    NSString *refSummary = references.count > 0
        ? [NSString stringWithFormat:VCTextLiteral(@"%lu attached"), (unsigned long)references.count]
        : VCTextLiteral(@"No attached refs");
    NSString *statusText = self.sessionStateLabel.text.length > 0 ? self.sessionStateLabel.text : VCTextLiteral(@"Ready");
    if (self.currentLayoutMode == VCPanelLayoutModeLandscape) {
        NSString *contextText = tracker.usagePercent == 0 ? VCTextLiteral(@"Context empty") : [NSString stringWithFormat:@"%@ %lu%%", VCTextLiteral(@"Context"), (unsigned long)tracker.usagePercent];
        self.contextSummaryMetaLabel.text = [NSString stringWithFormat:@"%@\n%@ • %@", contextText, refSummary, statusText];
    } else {
        NSString *contextText = tracker.usagePercent == 0 ? VCTextLiteral(@"Context empty") : [NSString stringWithFormat:@"%@ %lu%%", VCTextLiteral(@"Context"), (unsigned long)tracker.usagePercent];
        self.contextSummaryMetaLabel.text = [NSString stringWithFormat:@"%@\n%@\n%@", contextText, refSummary, statusText];
    }
}

- (void)_refreshClearButtonState {
    BOOL hasMessages = self.messages.count > 0 || self.streamingText.length > 0;
    self.clearChatButton.enabled = hasMessages;
    self.clearChatButton.alpha = hasMessages ? 1.0 : 0.52;
    self.contextClearButton.enabled = hasMessages;
    self.contextClearButton.alpha = hasMessages ? 1.0 : 0.52;
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    if (textView != self.inputTextView) return;
    [self _updateInputTextHeight];
    [self _refreshComposerState];
    [self.view layoutIfNeeded];
}

- (BOOL)textView:(UITextView *)textView
shouldChangeTextInRange:(NSRange)range
 replacementText:(NSString *)text {
    if (textView != self.inputTextView) return YES;
    if (![text isEqualToString:@"\n"]) return YES;

    UITextRange *markedRange = textView.markedTextRange;
    UITextPosition *markedStart = markedRange.start;
    UITextPosition *markedEnd = markedRange.end;
    if (markedStart && markedEnd && [textView offsetFromPosition:markedStart toPosition:markedEnd] > 0) {
        return YES;
    }

    [self _sendMessage];
    return NO;
}

@end
