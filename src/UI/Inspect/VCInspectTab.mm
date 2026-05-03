/**
 * VCInspectTab -- Inspect Tab
 * Unified analysis workspace: All / Members / UI / Strings / Instances / Process
 */

#import "VCInspectTab.h"
#import "../../../VansonCLI.h"
#import "../../Runtime/VCRuntimeEngine.h"
#import "../../Runtime/VCRuntimeModels.h"
#import "../../Runtime/VCStringScanner.h"
#import "../../Runtime/VCInstanceScanner.h"
#import "../../Runtime/VCValueReader.h"
#import "../../Process/VCProcessInfo.h"
#import "../../Patches/VCPatchItem.h"
#import "../../Patches/VCValueItem.h"
#import "../../Patches/VCHookItem.h"
#import "../../AI/Chat/VCChatSession.h"
#import "../../UIInspector/VCUIInspector.h"
#import "../../UIInspector/VCTouchOverlay.h"
#import "../Patches/VCPatchesTab.h"
#import "../Memory/VCMemoryBrowserTab.h"
#import "../Panel/VCPanel.h"
#import "../Settings/VCSettingsTab.h"

static NSString *const kCellID = @"InspectCell";

typedef NS_ENUM(NSInteger, VCInspectSubTab) {
    VCInspectSubTabAll = 0,
    VCInspectSubTabMembers,
    VCInspectSubTabUI,
    VCInspectSubTabStrings,
    VCInspectSubTabInstances,
    VCInspectSubTabProcess,
};

@interface VCInspectTab () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, VCTouchOverlayDelegate, VCPanelLayoutUpdatable>
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISegmentedControl *segCtrl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIButton *pickButton;
@property (nonatomic, strong) UIButton *highlightToggleButton;
@property (nonatomic, strong) NSArray *dataSource;
@property (nonatomic, strong) NSDictionary *selectedDetailItem;
@property (nonatomic, assign) NSUInteger runtimeOffset;
@property (nonatomic, assign) BOOL runtimeHasMore;
@property (nonatomic, strong) VCClassInfo *selectedClass;
@property (nonatomic, strong) UIView *actionDock;
@property (nonatomic, strong) UIView *actionDockHandle;
@property (nonatomic, strong) UIButton *actionDockButton;
@property (nonatomic, strong) NSLayoutConstraint *actionDockWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *actionDockHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *actionDockLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *actionDockTopConstraint;
@property (nonatomic, strong) UIView *actionOverlay;
@property (nonatomic, strong) UIControl *actionBackdrop;
@property (nonatomic, strong) UIView *actionDrawerCard;
@property (nonatomic, strong) UIView *actionDrawerHandle;
@property (nonatomic, strong) UILabel *actionDrawerTitleLabel;
@property (nonatomic, strong) UILabel *actionDrawerSubtitleLabel;
@property (nonatomic, strong) UIButton *actionPrimaryButton;
@property (nonatomic, strong) UIButton *actionSecondaryButton;
@property (nonatomic, strong) UIButton *actionTertiaryButton;
@property (nonatomic, strong) UIButton *actionQuaternaryButton;
@property (nonatomic, strong) UIButton *actionDrawerCloseButton;
@property (nonatomic, strong) UIStackView *actionButtonStack;
@property (nonatomic, strong) NSLayoutConstraint *actionDrawerCardWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *actionDrawerCardHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *actionDrawerCardLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *actionDrawerCardTopConstraint;
@property (nonatomic, strong) UIView *uiQuickEditOverlay;
@property (nonatomic, strong) UIControl *uiQuickEditBackdrop;
@property (nonatomic, strong) UIView *uiQuickEditCard;
@property (nonatomic, strong) UILabel *uiQuickEditTitleLabel;
@property (nonatomic, strong) UILabel *uiQuickEditSubtitleLabel;
@property (nonatomic, strong) UIScrollView *uiQuickEditScrollView;
@property (nonatomic, strong) UITextField *uiQuickTextField;
@property (nonatomic, strong) UITextField *uiQuickColorField;
@property (nonatomic, strong) UITextField *uiQuickTextColorField;
@property (nonatomic, strong) UITextField *uiQuickTintColorField;
@property (nonatomic, strong) UITextField *uiQuickAlphaField;
@property (nonatomic, strong) UITextField *uiQuickFrameField;
@property (nonatomic, strong) UITextField *uiQuickTagField;
@property (nonatomic, strong) UITextField *uiQuickHiddenField;
@property (nonatomic, strong) UITextField *uiQuickInteractionField;
@property (nonatomic, strong) UITextField *uiQuickClipsField;
@property (nonatomic, strong) UIButton *uiQuickApplyButton;
@property (nonatomic, strong) UIButton *uiQuickCancelButton;
@property (nonatomic, strong) NSLayoutConstraint *uiQuickEditCardWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *uiQuickEditCardHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *uiQuickEditCardLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *uiQuickEditCardTopConstraint;
@property (nonatomic, assign) CGFloat runtimeListOffsetY;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *searchMemory;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *offsetMemory;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *collapsedUIAddresses;
@property (nonatomic, weak) UIView *selectedUIView;
@property (nonatomic, assign) BOOL panelHiddenForPicking;
@property (nonatomic, strong) NSLayoutConstraint *backButtonHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *segmentHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *searchHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *pickButtonSizeConstraint;
@property (nonatomic, strong) NSLayoutConstraint *highlightToggleButtonSizeConstraint;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@end

@implementation VCInspectTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;
    _runtimeOffset = 0;
    _runtimeHasMore = YES;
    _dataSource = @[];
    _searchMemory = [NSMutableDictionary new];
    _offsetMemory = [NSMutableDictionary new];
    _collapsedUIAddresses = [NSMutableSet new];
    _currentLayoutMode = VCPanelLayoutModePortrait;
    [VCTouchOverlay shared].delegate = self;

    [self _setupHeader];
    [self _setupSearchBar];
    [self _setupSegment];
    [self _setupTableView];
    [self _setupActionDockIfNeeded];
    [self _setupActionOverlayIfNeeded];
    [self _setupUIQuickEditOverlayIfNeeded];
    VCInstallKeyboardDismissAccessory(self.view);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_languageDidChange) name:VCLanguageDidChangeNotification object:nil];
    [self _refreshLocalizedText];
    [self _applyCurrentLayoutMode];
    [self _loadData];
}

- (void)dealloc {
    if ([VCTouchOverlay shared].delegate == self) {
        [VCTouchOverlay shared].delegate = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_setupHeader {
    _headerCard = [[UIView alloc] init];
    VCApplyPanelSurface(_headerCard, 12.0);
    _headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerCard];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = VCTextLiteral(@"RUNTIME WORKSPACE");
    _titleLabel.textColor = kVCTextSecondary;
    _titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_titleLabel];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.textColor = kVCTextMuted;
    _statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _statusLabel.textAlignment = NSTextAlignmentRight;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _statusLabel.numberOfLines = 1;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_statusLabel];

    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_backButton setTitle:VCTextLiteral(@"Back") forState:UIControlStateNormal];
    [_backButton setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(_backButton);
    VCPrepareButtonTitle(_backButton, NSLineBreakByTruncatingTail, 0.78);
    _backButton.contentEdgeInsets = UIEdgeInsetsMake(4, 8, 4, 8);
    _backButton.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
    _backButton.hidden = YES;
    [_backButton addTarget:self action:@selector(_headerActionTapped) forControlEvents:UIControlEventTouchUpInside];
    _backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_backButton];

    [NSLayoutConstraint activateConstraints:@[
        [_headerCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [_headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [_headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [_backButton.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_backButton.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
        [_titleLabel.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:10],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_backButton.trailingAnchor constant:8],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-10],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_statusLabel.widthAnchor constraintLessThanOrEqualToAnchor:_headerCard.widthAnchor multiplier:0.58],
    ]];
    self.backButtonHeightConstraint = [_backButton.heightAnchor constraintEqualToConstant:24];
    self.backButtonHeightConstraint.active = YES;
}

- (void)_setupSegment {
    _segCtrl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Members", @"UI", @"Strings", @"Instances", @"Process"]];
    _segCtrl.selectedSegmentIndex = 0;
    _segCtrl.selectedSegmentTintColor = kVCAccent;
    [_segCtrl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [_segCtrl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    [_segCtrl addTarget:self action:@selector(_segChanged) forControlEvents:UIControlEventValueChanged];
    _segCtrl.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_segCtrl];

    [NSLayoutConstraint activateConstraints:@[
        [_segCtrl.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:8],
        [_segCtrl.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_segCtrl.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_segCtrl.bottomAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:-8],
    ]];
    self.segmentHeightConstraint = [_segCtrl.heightAnchor constraintEqualToConstant:30];
    self.segmentHeightConstraint.active = YES;
}

- (void)_setupSearchBar {
    _searchBar = [[UISearchBar alloc] init];
    VCApplyReadableSearchPlaceholder(_searchBar, VCTextLiteral(@"Search classes, members, or results"));
    _searchBar.barTintColor = [UIColor clearColor];
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.delegate = self;
    [_searchBar setSearchFieldBackgroundImage:[[UIImage alloc] init] forState:UIControlStateNormal];
    UITextField *tf = [_searchBar valueForKey:@"searchField"];
    if (tf) {
        VCApplyInputSurface(tf, 11.0);
        tf.textColor = kVCTextPrimary;
        tf.font = [UIFont systemFontOfSize:13];
        tf.layer.masksToBounds = YES;
    }
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_searchBar];

    _highlightToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_highlightToggleButton setImage:[UIImage systemImageNamed:@"square"] forState:UIControlStateNormal];
    _highlightToggleButton.hidden = YES;
    _highlightToggleButton.accessibilityLabel = VCTextLiteral(@"Pick View Border");
    VCApplyCompactAccentButtonStyle(_highlightToggleButton);
    _highlightToggleButton.contentEdgeInsets = UIEdgeInsetsZero;
    VCApplyCompactIconTitleButtonLayout(_highlightToggleButton, @"square", 13.0);
    [_highlightToggleButton addTarget:self action:@selector(_toggleSelectionHighlight) forControlEvents:UIControlEventTouchUpInside];
    _highlightToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_highlightToggleButton];

    _pickButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_pickButton setImage:[UIImage systemImageNamed:@"scope"] forState:UIControlStateNormal];
    _pickButton.hidden = YES;
    _pickButton.accessibilityLabel = VCTextLiteral(@"Pick View");
    VCApplyCompactAccentButtonStyle(_pickButton);
    _pickButton.contentEdgeInsets = UIEdgeInsetsZero;
    [_pickButton addTarget:self action:@selector(_togglePick) forControlEvents:UIControlEventTouchUpInside];
    _pickButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_pickButton];

    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:30],
        [_searchBar.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:6],
        [_searchBar.trailingAnchor constraintEqualToAnchor:_highlightToggleButton.leadingAnchor constant:-6],
        [_highlightToggleButton.centerYAnchor constraintEqualToAnchor:_searchBar.centerYAnchor],
        [_highlightToggleButton.trailingAnchor constraintEqualToAnchor:_pickButton.leadingAnchor constant:-6],
        [_highlightToggleButton.heightAnchor constraintEqualToAnchor:_highlightToggleButton.widthAnchor],
        [_pickButton.centerYAnchor constraintEqualToAnchor:_searchBar.centerYAnchor],
        [_pickButton.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_pickButton.heightAnchor constraintEqualToAnchor:_pickButton.widthAnchor],
    ]];
    self.searchHeightConstraint = [_searchBar.heightAnchor constraintEqualToConstant:36];
    self.searchHeightConstraint.active = YES;
    self.highlightToggleButtonSizeConstraint = [_highlightToggleButton.widthAnchor constraintEqualToConstant:34];
    self.highlightToggleButtonSizeConstraint.active = YES;
    self.pickButtonSizeConstraint = [_pickButton.widthAnchor constraintEqualToConstant:34];
    self.pickButtonSizeConstraint.active = YES;
    [self _updateSelectionHighlightButtonState];
}

- (void)_applyCurrentLayoutMode {
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape);
    self.titleLabel.font = [UIFont systemFontOfSize:(landscape ? 9.0 : 10.0) weight:UIFontWeightBold];
    self.statusLabel.font = [UIFont systemFontOfSize:(landscape ? 10.0 : 11.0) weight:UIFontWeightSemibold];
    self.statusLabel.numberOfLines = 1;
    self.backButton.titleLabel.font = [UIFont systemFontOfSize:(landscape ? 10.0 : 11.0) weight:UIFontWeightSemibold];
    self.backButtonHeightConstraint.constant = landscape ? 22.0 : 24.0;
    self.segmentHeightConstraint.constant = landscape ? 28.0 : 30.0;
    self.searchHeightConstraint.constant = landscape ? 32.0 : 36.0;
    self.pickButtonSizeConstraint.constant = landscape ? 30.0 : 34.0;
    self.tableView.contentInset = landscape ? UIEdgeInsetsMake(4, 0, 8, 0) : UIEdgeInsetsMake(6, 0, 12, 0);
    UITextField *tf = [self.searchBar valueForKey:@"searchField"];
    if (tf) {
        tf.font = [UIFont systemFontOfSize:(landscape ? 12.0 : 13.0)];
    }
    [self _applySegmentTitlesForLayout];
    [self _layoutActionDock];
    [self _layoutActionOverlay];
    [self _layoutUIQuickEditOverlay];
    [self _updateHeaderActionButton];
    [self _refreshActionDock];
}

- (void)_applySegmentTitlesForLayout {
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape);
    NSArray<NSString *> *titles = landscape
        ? @[VCTextLiteral(@"All"), VCTextLiteral(@"Mem"), VCTextLiteral(@"UI"), VCTextLiteral(@"Str"), VCTextLiteral(@"Inst"), VCTextLiteral(@"Proc")]
        : @[VCTextLiteral(@"All"), VCTextLiteral(@"Members"), VCTextLiteral(@"UI"), VCTextLiteral(@"Strings"), VCTextLiteral(@"Instances"), VCTextLiteral(@"Process")];
    for (NSUInteger idx = 0; idx < titles.count; idx++) {
        [self.segCtrl setTitle:titles[idx] forSegmentAtIndex:idx];
    }
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    [self _applyCurrentLayoutMode];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self _layoutActionDock];
    [self _layoutActionOverlay];
    [self _layoutUIQuickEditOverlay];
}

- (void)_refreshLocalizedText {
    [self _applySegmentTitlesForLayout];
    [self _updateHeaderActionButton];
    VCApplyReadableSearchPlaceholder(self.searchBar, self.selectedClass ? VCTextLiteral(@"Search classes, members, or results") : VCTextLiteral(@"Search classes, members, or results"));
    [self _updateStatus];
    [self.tableView reloadData];
}

- (BOOL)_isUISegment {
    return self.segCtrl.selectedSegmentIndex == VCInspectSubTabUI;
}

- (void)_updateHeaderActionButton {
    BOOL picking = [VCTouchOverlay shared].isPicking;
    self.pickButton.hidden = NO;
    self.highlightToggleButton.hidden = NO;
    self.pickButtonSizeConstraint.constant = (self.currentLayoutMode == VCPanelLayoutModeLandscape) ? 30.0 : 34.0;
    self.highlightToggleButtonSizeConstraint.constant = (self.currentLayoutMode == VCPanelLayoutModeLandscape) ? 30.0 : 34.0;
    [self.pickButton setImage:[UIImage systemImageNamed:(picking ? @"xmark" : @"scope")] forState:UIControlStateNormal];
    VCApplyCompactIconTitleButtonLayout(self.pickButton, (picking ? @"xmark" : @"scope"), 13.0);
    self.pickButton.accessibilityLabel = picking ? VCTextLiteral(@"Cancel") : VCTextLiteral(@"Pick View");
    if (picking) {
        VCApplyCompactDangerButtonStyle(self.pickButton);
    } else {
        VCApplyCompactAccentButtonStyle(self.pickButton);
    }
    self.pickButton.contentEdgeInsets = UIEdgeInsetsZero;
    [self _updateSelectionHighlightButtonState];
    [self.backButton setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [self.backButton setTitle:VCTextLiteral(@"Back") forState:UIControlStateNormal];
    self.backButton.hidden = (self.selectedClass == nil);
}

- (void)_headerActionTapped {
    [self _goBackFromDetail];
}

- (void)_toggleSelectionHighlight {
    VCUIInspector *inspector = [VCUIInspector shared];
    inspector.selectionHighlightEnabled = !inspector.selectionHighlightEnabled;
    if (inspector.selectionHighlightEnabled && self.selectedUIView) {
        [inspector highlightView:self.selectedUIView];
    }
    [self _updateSelectionHighlightButtonState];
}

- (void)_updateSelectionHighlightButtonState {
    BOOL enabled = [VCUIInspector shared].selectionHighlightEnabled;
    self.highlightToggleButton.selected = enabled;
    self.highlightToggleButton.accessibilityLabel = VCTextLiteral(@"Pick View Border");
    self.highlightToggleButton.accessibilityValue = enabled ? VCTextLiteral(@"On") : VCTextLiteral(@"Off");
    if (enabled) {
        VCApplyCompactAccentButtonStyle(self.highlightToggleButton);
    } else {
        VCApplyCompactSecondaryButtonStyle(self.highlightToggleButton);
    }
    self.highlightToggleButton.contentEdgeInsets = UIEdgeInsetsZero;
    VCApplyCompactIconTitleButtonLayout(self.highlightToggleButton, @"square", 13.0);
}

- (void)_togglePick {
    VCTouchOverlay *overlay = [VCTouchOverlay shared];
    overlay.delegate = self;
    if (overlay.isPicking) {
        [overlay stopPicking];
    } else {
        [self _setPanelHiddenForPicking:YES];
        [overlay startPicking];
        self.statusLabel.text = VCTextLiteral(@"Picking active");
    }
    [self _updateHeaderActionButton];
}

- (VCPanel *)_owningPanel {
    UIView *view = self.view;
    while (view) {
        if ([view isKindOfClass:[VCPanel class]]) return (VCPanel *)view;
        view = view.superview;
    }
    return nil;
}

- (void)_setPanelHiddenForPicking:(BOOL)hidden {
    VCPanel *panel = [self _owningPanel];
    if (!panel) return;
    if (hidden) {
        if (panel.isVisible) {
            self.panelHiddenForPicking = YES;
            [panel hideAnimated];
        }
        return;
    }
    if (self.panelHiddenForPicking) {
        self.panelHiddenForPicking = NO;
        [panel showAnimated];
    }
}

- (void)_languageDidChange {
    [self _refreshLocalizedText];
    [self _loadData];
}

- (void)_setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 52;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _tableView.contentInset = UIEdgeInsetsMake(6, 0, 12, 0);
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellID];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:8],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)_setupActionDockIfNeeded {
    if (self.actionDock) return;

    UIView *dock = [[UIView alloc] init];
    dock.translatesAutoresizingMaskIntoConstraints = NO;
    dock.hidden = YES;
    dock.alpha = 0.0;
    dock.backgroundColor = [UIColor clearColor];
    dock.layer.cornerRadius = 0.0;
    dock.layer.borderWidth = 0.0;
    dock.layer.borderColor = UIColor.clearColor.CGColor;
    dock.layer.shadowColor = [UIColor blackColor].CGColor;
    dock.layer.shadowOpacity = 0.18;
    dock.layer.shadowRadius = 14.0;
    dock.layer.shadowOffset = CGSizeMake(0, 8.0);
    [self.view addSubview:dock];
    self.actionDock = dock;

    UIView *handle = [[UIView alloc] init];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.backgroundColor = [UIColor clearColor];
    handle.layer.cornerRadius = 2.0;
    [dock addSubview:handle];
    self.actionDockHandle = handle;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:VCTextLiteral(@"Modify") forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    VCApplyCompactAccentButtonStyle(button);
    VCPrepareButtonTitle(button, NSLineBreakByTruncatingTail, 0.80);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 14, 10, 14);
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 7, 0, -7);
    [button addTarget:self action:@selector(_toggleActionDrawer) forControlEvents:UIControlEventTouchUpInside];
    [dock addSubview:button];
    self.actionDockButton = button;

    self.actionDockWidthConstraint = [self.actionDock.widthAnchor constraintEqualToConstant:160.0];
    self.actionDockHeightConstraint = [self.actionDock.heightAnchor constraintEqualToConstant:56.0];
    self.actionDockLeadingConstraint = [self.actionDock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:0.0];
    self.actionDockTopConstraint = [self.actionDock.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:0.0];

    [NSLayoutConstraint activateConstraints:@[
        self.actionDockWidthConstraint,
        self.actionDockHeightConstraint,
        self.actionDockLeadingConstraint,
        self.actionDockTopConstraint,

        [self.actionDockHandle.topAnchor constraintEqualToAnchor:self.actionDock.topAnchor],
        [self.actionDockHandle.centerXAnchor constraintEqualToAnchor:self.actionDock.centerXAnchor],
        [self.actionDockHandle.widthAnchor constraintEqualToConstant:36.0],
        [self.actionDockHandle.heightAnchor constraintEqualToConstant:0.0],

        [self.actionDockButton.topAnchor constraintEqualToAnchor:self.actionDock.topAnchor],
        [self.actionDockButton.leadingAnchor constraintEqualToAnchor:self.actionDock.leadingAnchor],
        [self.actionDockButton.trailingAnchor constraintEqualToAnchor:self.actionDock.trailingAnchor],
        [self.actionDockButton.bottomAnchor constraintEqualToAnchor:self.actionDock.bottomAnchor],
    ]];

    [self _layoutActionDock];
}

- (UIButton *)_inspectDrawerActionButtonWithTitle:(NSString *)title emphasized:(BOOL)emphasized {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    if (emphasized) {
        VCApplyCompactPrimaryButtonStyle(button);
    } else {
        VCApplyCompactSecondaryButtonStyle(button);
    }
    VCPrepareButtonTitle(button, NSLineBreakByTruncatingTail, 0.78);
    return button;
}

- (void)_removeActionButtonIcon:(UIButton *)button {
    if (!button) return;
    [button setImage:nil forState:UIControlStateNormal];
    button.imageEdgeInsets = UIEdgeInsetsZero;
    button.titleEdgeInsets = UIEdgeInsetsZero;
    button.semanticContentAttribute = UISemanticContentAttributeUnspecified;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
}

- (void)_setupActionOverlayIfNeeded {
    if (self.actionOverlay) return;

    UIView *overlay = [[UIView alloc] initWithFrame:CGRectZero];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.hidden = YES;
    overlay.alpha = 0.0;
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    [self.view addSubview:overlay];
    self.actionOverlay = overlay;

    UIControl *backdrop = [[UIControl alloc] initWithFrame:CGRectZero];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addTarget:self action:@selector(_hideActionDrawer) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:backdrop];
    self.actionBackdrop = backdrop;

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    VCApplyPanelSurface(card, 12.0);
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.24;
    card.layer.shadowRadius = 18.0;
    card.layer.shadowOffset = CGSizeMake(0, -6.0);
    [overlay addSubview:card];
    self.actionDrawerCard = card;

    self.actionDrawerHandle = [[UIView alloc] init];
    self.actionDrawerHandle.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionDrawerHandle.backgroundColor = kVCTextMuted;
    self.actionDrawerHandle.layer.cornerRadius = 2.0;
    [card addSubview:self.actionDrawerHandle];

    self.actionDrawerTitleLabel = [[UILabel alloc] init];
    self.actionDrawerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionDrawerTitleLabel.text = VCTextLiteral(@"Inspect Actions");
    self.actionDrawerTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.actionDrawerTitleLabel.textColor = kVCTextPrimary;
    [card addSubview:self.actionDrawerTitleLabel];

    self.actionDrawerSubtitleLabel = [[UILabel alloc] init];
    self.actionDrawerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionDrawerSubtitleLabel.text = VCTextLiteral(@"Select a member row to open actions.");
    self.actionDrawerSubtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.actionDrawerSubtitleLabel.textColor = kVCTextSecondary;
    self.actionDrawerSubtitleLabel.numberOfLines = 2;
    [card addSubview:self.actionDrawerSubtitleLabel];

    self.actionDrawerCloseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.actionDrawerCloseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionDrawerCloseButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(self.actionDrawerCloseButton);
    [self.actionDrawerCloseButton addTarget:self action:@selector(_hideActionDrawer) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.actionDrawerCloseButton];

    self.actionPrimaryButton = [self _inspectDrawerActionButtonWithTitle:VCTextLiteral(@"Chat") emphasized:YES];
    self.actionPrimaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionPrimaryButton addTarget:self action:@selector(_performPrimaryInspectAction) forControlEvents:UIControlEventTouchUpInside];

    self.actionSecondaryButton = [self _inspectDrawerActionButtonWithTitle:VCTextLiteral(@"Hook") emphasized:NO];
    self.actionSecondaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionSecondaryButton addTarget:self action:@selector(_performSecondaryInspectAction) forControlEvents:UIControlEventTouchUpInside];

    self.actionTertiaryButton = [self _inspectDrawerActionButtonWithTitle:VCTextLiteral(@"Patch") emphasized:NO];
    self.actionTertiaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionTertiaryButton addTarget:self action:@selector(_performTertiaryInspectAction) forControlEvents:UIControlEventTouchUpInside];

    self.actionQuaternaryButton = [self _inspectDrawerActionButtonWithTitle:VCTextLiteral(@"Copy") emphasized:NO];
    self.actionQuaternaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionQuaternaryButton addTarget:self action:@selector(_performQuaternaryInspectAction) forControlEvents:UIControlEventTouchUpInside];

    self.actionButtonStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.actionPrimaryButton,
        self.actionSecondaryButton,
        self.actionTertiaryButton,
        self.actionQuaternaryButton
    ]];
    self.actionButtonStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionButtonStack.axis = UILayoutConstraintAxisVertical;
    self.actionButtonStack.spacing = 8.0;
    self.actionButtonStack.distribution = UIStackViewDistributionFillEqually;
    [card addSubview:self.actionButtonStack];

    self.actionDrawerCardLeadingConstraint = [self.actionDrawerCard.leadingAnchor constraintEqualToAnchor:self.actionOverlay.leadingAnchor constant:12.0];
    self.actionDrawerCardTopConstraint = [self.actionDrawerCard.topAnchor constraintEqualToAnchor:self.actionOverlay.topAnchor constant:12.0];
    self.actionDrawerCardWidthConstraint = [self.actionDrawerCard.widthAnchor constraintEqualToConstant:320.0];
    self.actionDrawerCardHeightConstraint = [self.actionDrawerCard.heightAnchor constraintEqualToConstant:274.0];

    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [backdrop.topAnchor constraintEqualToAnchor:overlay.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],

        self.actionDrawerCardLeadingConstraint,
        self.actionDrawerCardTopConstraint,
        self.actionDrawerCardWidthConstraint,
        self.actionDrawerCardHeightConstraint,

        [self.actionDrawerHandle.topAnchor constraintEqualToAnchor:self.actionDrawerCard.topAnchor constant:10.0],
        [self.actionDrawerHandle.centerXAnchor constraintEqualToAnchor:self.actionDrawerCard.centerXAnchor],
        [self.actionDrawerHandle.widthAnchor constraintEqualToConstant:36.0],
        [self.actionDrawerHandle.heightAnchor constraintEqualToConstant:4.0],

        [self.actionDrawerCloseButton.topAnchor constraintEqualToAnchor:self.actionDrawerCard.topAnchor constant:18.0],
        [self.actionDrawerCloseButton.trailingAnchor constraintEqualToAnchor:self.actionDrawerCard.trailingAnchor constant:-14.0],
        [self.actionDrawerCloseButton.widthAnchor constraintEqualToConstant:24.0],
        [self.actionDrawerCloseButton.heightAnchor constraintEqualToConstant:24.0],

        [self.actionDrawerTitleLabel.topAnchor constraintEqualToAnchor:self.actionDrawerCard.topAnchor constant:18.0],
        [self.actionDrawerTitleLabel.leadingAnchor constraintEqualToAnchor:self.actionDrawerCard.leadingAnchor constant:14.0],
        [self.actionDrawerTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.actionDrawerCloseButton.leadingAnchor constant:-10.0],

        [self.actionDrawerSubtitleLabel.topAnchor constraintEqualToAnchor:self.actionDrawerTitleLabel.bottomAnchor constant:8.0],
        [self.actionDrawerSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.actionDrawerTitleLabel.leadingAnchor],
        [self.actionDrawerSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.actionDrawerCard.trailingAnchor constant:-14.0],

        [self.actionButtonStack.topAnchor constraintEqualToAnchor:self.actionDrawerSubtitleLabel.bottomAnchor constant:12.0],
        [self.actionButtonStack.leadingAnchor constraintEqualToAnchor:self.actionDrawerCard.leadingAnchor constant:14.0],
        [self.actionButtonStack.trailingAnchor constraintEqualToAnchor:self.actionDrawerCard.trailingAnchor constant:-14.0],
        [self.actionButtonStack.bottomAnchor constraintEqualToAnchor:self.actionDrawerCard.bottomAnchor constant:-14.0],
    ]];

    [self _layoutActionOverlay];
}

- (UITextField *)_quickEditFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.backgroundColor = kVCBgInput;
    field.textColor = kVCTextPrimary;
    field.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    field.layer.cornerRadius = 10.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = kVCBorder.CGColor;
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    field.leftViewMode = UITextFieldViewModeAlways;
    VCApplyReadablePlaceholder(field, placeholder);
    return field;
}

- (UIView *)_quickEditRowWithTitle:(NSString *)title field:(UITextField *)field {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title;
    label.textColor = kVCTextSecondary;
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    label.numberOfLines = 2;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.78;
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    [row addSubview:label];
    [row addSubview:field];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:40.0],

        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.widthAnchor constraintEqualToConstant:92.0],

        [field.topAnchor constraintEqualToAnchor:row.topAnchor constant:2.0],
        [field.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:10.0],
        [field.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [field.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-2.0],
        [field.heightAnchor constraintEqualToConstant:36.0],
    ]];

    return row;
}

- (void)_setupUIQuickEditOverlayIfNeeded {
    if (self.uiQuickEditOverlay) return;

    UIView *overlay = [[UIView alloc] initWithFrame:CGRectZero];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.hidden = YES;
    overlay.alpha = 0.0;
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    [self.view addSubview:overlay];
    self.uiQuickEditOverlay = overlay;

    UIControl *backdrop = [[UIControl alloc] initWithFrame:CGRectZero];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addTarget:self action:@selector(_hideUIQuickEditor) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:backdrop];
    self.uiQuickEditBackdrop = backdrop;

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    card.layer.cornerRadius = 18.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = kVCBorderStrong.CGColor;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.24;
    card.layer.shadowRadius = 18.0;
    card.layer.shadowOffset = CGSizeMake(0, -6.0);
    [overlay addSubview:card];
    self.uiQuickEditCard = card;

    self.uiQuickEditTitleLabel = [[UILabel alloc] init];
    self.uiQuickEditTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.uiQuickEditTitleLabel.text = VCTextLiteral(@"Quick Edit");
    self.uiQuickEditTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.uiQuickEditTitleLabel.textColor = kVCTextPrimary;
    [card addSubview:self.uiQuickEditTitleLabel];

    self.uiQuickEditSubtitleLabel = [[UILabel alloc] init];
    self.uiQuickEditSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.uiQuickEditSubtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.uiQuickEditSubtitleLabel.textColor = kVCTextSecondary;
    self.uiQuickEditSubtitleLabel.numberOfLines = 2;
    [card addSubview:self.uiQuickEditSubtitleLabel];

    self.uiQuickEditScrollView = [[UIScrollView alloc] init];
    self.uiQuickEditScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.uiQuickEditScrollView.showsVerticalScrollIndicator = YES;
    [card addSubview:self.uiQuickEditScrollView];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.uiQuickEditScrollView addSubview:contentView];

    UIStackView *fieldStack = [[UIStackView alloc] init];
    fieldStack.translatesAutoresizingMaskIntoConstraints = NO;
    fieldStack.axis = UILayoutConstraintAxisVertical;
    fieldStack.alignment = UIStackViewAlignmentFill;
    fieldStack.distribution = UIStackViewDistributionFill;
    fieldStack.spacing = 8.0;
    [contentView addSubview:fieldStack];

    self.uiQuickTextField = [self _quickEditFieldWithPlaceholder:VCTextLiteral(@"Text / title")];
    self.uiQuickColorField = [self _quickEditFieldWithPlaceholder:@"00D4FF"];
    self.uiQuickTextColorField = [self _quickEditFieldWithPlaceholder:@"FFFFFF"];
    self.uiQuickTintColorField = [self _quickEditFieldWithPlaceholder:@"00D4FF"];
    self.uiQuickAlphaField = [self _quickEditFieldWithPlaceholder:@"0.0 - 1.0"];
    self.uiQuickAlphaField.keyboardType = UIKeyboardTypeDecimalPad;
    self.uiQuickFrameField = [self _quickEditFieldWithPlaceholder:@"{{x, y}, {w, h}}"];
    self.uiQuickTagField = [self _quickEditFieldWithPlaceholder:@"0"];
    self.uiQuickTagField.keyboardType = UIKeyboardTypeNumberPad;
    self.uiQuickHiddenField = [self _quickEditFieldWithPlaceholder:@"true / false"];
    self.uiQuickInteractionField = [self _quickEditFieldWithPlaceholder:@"true / false"];
    self.uiQuickClipsField = [self _quickEditFieldWithPlaceholder:@"true / false"];

    NSArray<UIView *> *quickRows = @[
        [self _quickEditRowWithTitle:VCTextLiteral(@"Text") field:self.uiQuickTextField],
        [self _quickEditRowWithTitle:VCTextLiteral(@"Background") field:self.uiQuickColorField],
        [self _quickEditRowWithTitle:VCTextLiteral(@"Text Color") field:self.uiQuickTextColorField],
        [self _quickEditRowWithTitle:VCTextLiteral(@"Tint Color") field:self.uiQuickTintColorField],
        [self _quickEditRowWithTitle:VCTextLiteral(@"Alpha") field:self.uiQuickAlphaField],
        [self _quickEditRowWithTitle:VCTextLiteral(@"Frame") field:self.uiQuickFrameField],
        [self _quickEditRowWithTitle:VCTextLiteral(@"Tag") field:self.uiQuickTagField],
        [self _quickEditRowWithTitle:VCTextLiteral(@"Hidden") field:self.uiQuickHiddenField],
        [self _quickEditRowWithTitle:VCTextLiteral(@"Tap Enabled") field:self.uiQuickInteractionField],
        [self _quickEditRowWithTitle:VCTextLiteral(@"Clips") field:self.uiQuickClipsField],
    ];
    for (UIView *row in quickRows) {
        [fieldStack addArrangedSubview:row];
    }

    self.uiQuickCancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.uiQuickCancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.uiQuickCancelButton setTitle:VCTextLiteral(@"Cancel") forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(self.uiQuickCancelButton);
    [self.uiQuickCancelButton addTarget:self action:@selector(_hideUIQuickEditor) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.uiQuickCancelButton];

    self.uiQuickApplyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.uiQuickApplyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.uiQuickApplyButton setTitle:VCTextLiteral(@"Apply") forState:UIControlStateNormal];
    VCApplyCompactPrimaryButtonStyle(self.uiQuickApplyButton);
    [self.uiQuickApplyButton addTarget:self action:@selector(_applyUIQuickEdit) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.uiQuickApplyButton];

    self.uiQuickEditCardLeadingConstraint = [card.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:12.0];
    self.uiQuickEditCardTopConstraint = [card.topAnchor constraintEqualToAnchor:overlay.topAnchor constant:12.0];
    self.uiQuickEditCardWidthConstraint = [card.widthAnchor constraintEqualToConstant:320.0];
    self.uiQuickEditCardHeightConstraint = [card.heightAnchor constraintEqualToConstant:420.0];

    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [backdrop.topAnchor constraintEqualToAnchor:overlay.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],

        self.uiQuickEditCardLeadingConstraint,
        self.uiQuickEditCardTopConstraint,
        self.uiQuickEditCardWidthConstraint,
        self.uiQuickEditCardHeightConstraint,

        [self.uiQuickEditTitleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [self.uiQuickEditTitleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [self.uiQuickEditTitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],

        [self.uiQuickEditSubtitleLabel.topAnchor constraintEqualToAnchor:self.uiQuickEditTitleLabel.bottomAnchor constant:6.0],
        [self.uiQuickEditSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.uiQuickEditTitleLabel.leadingAnchor],
        [self.uiQuickEditSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.uiQuickEditTitleLabel.trailingAnchor],

        [self.uiQuickEditScrollView.topAnchor constraintEqualToAnchor:self.uiQuickEditSubtitleLabel.bottomAnchor constant:10.0],
        [self.uiQuickEditScrollView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [self.uiQuickEditScrollView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [self.uiQuickEditScrollView.bottomAnchor constraintEqualToAnchor:self.uiQuickCancelButton.topAnchor constant:-12.0],
        [contentView.topAnchor constraintEqualToAnchor:self.uiQuickEditScrollView.contentLayoutGuide.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.uiQuickEditScrollView.contentLayoutGuide.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.uiQuickEditScrollView.contentLayoutGuide.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.uiQuickEditScrollView.contentLayoutGuide.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.uiQuickEditScrollView.frameLayoutGuide.widthAnchor],

        [fieldStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [fieldStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [fieldStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [fieldStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

        [self.uiQuickCancelButton.leadingAnchor constraintEqualToAnchor:self.uiQuickEditTitleLabel.leadingAnchor],
        [self.uiQuickCancelButton.trailingAnchor constraintEqualToAnchor:self.uiQuickApplyButton.leadingAnchor constant:-10.0],
        [self.uiQuickCancelButton.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0],
        [self.uiQuickCancelButton.heightAnchor constraintEqualToConstant:38.0],
        [self.uiQuickApplyButton.trailingAnchor constraintEqualToAnchor:self.uiQuickEditTitleLabel.trailingAnchor],
        [self.uiQuickApplyButton.bottomAnchor constraintEqualToAnchor:self.uiQuickCancelButton.bottomAnchor],
        [self.uiQuickApplyButton.widthAnchor constraintEqualToAnchor:self.uiQuickCancelButton.widthAnchor],
        [self.uiQuickApplyButton.heightAnchor constraintEqualToAnchor:self.uiQuickCancelButton.heightAnchor],
    ]];

    [self _layoutUIQuickEditOverlay];
}

#pragma mark - Data Loading

- (void)_segChanged {
    [self _cacheCurrentState];
    [self _hideActionDrawer];
    [self _hideUIQuickEditor];
    _runtimeOffset = 0;
    _runtimeHasMore = YES;
    _selectedClass = nil;
    self.selectedDetailItem = nil;
    if (![self _isUISegment]) {
        self.selectedUIView = nil;
    }
    NSNumber *segmentKey = @(_segCtrl.selectedSegmentIndex);
    _searchBar.text = self.searchMemory[segmentKey] ?: @"";
    _runtimeListOffsetY = [self.offsetMemory[segmentKey] doubleValue];
    [self _loadData];
}

- (void)_goBackFromDetail {
    _selectedClass = nil;
    self.selectedDetailItem = nil;
    [self _loadRuntime:_searchBar.text.length > 0 ? _searchBar.text : nil reset:YES];
}

- (void)_cacheCurrentState {
    NSNumber *segmentKey = @(_segCtrl.selectedSegmentIndex);
    self.searchMemory[segmentKey] = _searchBar.text ?: @"";
    if (_segCtrl.selectedSegmentIndex == VCInspectSubTabMembers && !_selectedClass) {
        self.offsetMemory[segmentKey] = @(_tableView.contentOffset.y);
    }
}

- (void)_loadData {
    NSString *filter = _searchBar.text.length > 0 ? _searchBar.text : nil;

    switch (_segCtrl.selectedSegmentIndex) {
        case VCInspectSubTabAll:
            [self _loadOverview:filter];
            break;
        case VCInspectSubTabMembers:
            [self _loadRuntime:filter reset:YES];
            break;
        case VCInspectSubTabUI:
            [self _loadUIHierarchy:filter];
            break;
        case VCInspectSubTabStrings:
            [self _loadStrings:filter];
            break;
        case VCInspectSubTabInstances:
            [self _loadInstances:filter];
            break;
        case VCInspectSubTabProcess:
            [self _loadProcess];
            break;
    }
    [self _updateStatus];
}

- (void)_appendUINodePreviews:(VCViewNode *)node
                       depth:(NSInteger)depth
                       query:(NSString *)query
                    maxCount:(NSUInteger)maxCount
                    intoRows:(NSMutableArray *)rows {
    if (!node || rows.count >= maxCount) return;
    NSDictionary *entry = [self _uiEntryForNode:node depth:depth];
    BOOL include = query.length == 0;
    if (!include) {
        NSString *candidate = [NSString stringWithFormat:@"%@ %@ %@ %@",
                               entry[@"title"] ?: @"",
                               entry[@"detail"] ?: @"",
                               entry[@"address"] ?: @"",
                               node.briefDescription ?: @""].lowercaseString;
        include = [candidate containsString:query];
    }
    if (include) [rows addObject:entry];
    for (VCViewNode *child in node.children) {
        if (rows.count >= maxCount) break;
        [self _appendUINodePreviews:child depth:depth + 1 query:query maxCount:maxCount intoRows:rows];
    }
}

- (void)_loadOverview:(NSString *)filter {
    NSString *query = [[filter ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSMutableArray *rows = [NSMutableArray new];
    [self _appendUINodePreviews:[[VCUIInspector shared] viewHierarchyTree] depth:0 query:query maxCount:4 intoRows:rows];

    VCProcessInfo *pi = [VCProcessInfo shared];
    NSDictionary *info = [pi basicInfo] ?: @{};
    NSString *bundleID = [info[@"bundleID"] isKindOfClass:[NSString class]] ? info[@"bundleID"] : @"Process";
    NSString *pid = [info[@"pid"] description] ?: @"--";
    [rows addObject:@{
        @"kind": @"process_overview",
        @"title": bundleID,
        @"address": pid,
        @"detail": [NSString stringWithFormat:@"PID %@ • %@", pid, info[@"architecture"] ?: @"arm64"]
    }];

    self.dataSource = rows;
    [self _updateStatus];
    [self.tableView reloadData];
    [self _refreshActionDock];

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSArray *classes = [[VCRuntimeEngine shared] allClassesFilteredBy:(filter.length > 0 ? filter : nil) module:nil offset:0 limit:3];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.segCtrl.selectedSegmentIndex != VCInspectSubTabAll) return;
            NSMutableArray *merged = [rows mutableCopy];
            [merged addObjectsFromArray:classes ?: @[]];
            self.dataSource = merged;
            [self _updateStatus];
            [self.tableView reloadData];
            [self _refreshActionDock];
        });
    });
}

- (void)_loadRuntime:(NSString *)filter reset:(BOOL)reset {
    if (reset) { _runtimeOffset = 0; _runtimeHasMore = YES; }
    self.selectedDetailItem = nil;
    if (_selectedClass) {
        // Show class detail
        [self _loadClassDetail];
        return;
    }
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSArray *classes = [[VCRuntimeEngine shared] allClassesFilteredBy:filter module:nil offset:self->_runtimeOffset limit:100];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (reset) {
                self->_dataSource = classes;
            } else {
                self->_dataSource = [self->_dataSource arrayByAddingObjectsFromArray:classes];
            }
            self->_runtimeHasMore = (classes.count >= 100);
            self->_runtimeOffset += classes.count;
            [self _updateStatus];
            [self->_tableView reloadData];
            [self _refreshActionDock];
            if (reset && self.runtimeListOffsetY > 0 && !self->_selectedClass) {
                CGFloat maxOffset = MAX(0, self->_tableView.contentSize.height - self->_tableView.bounds.size.height);
                CGPoint restoredOffset = CGPointMake(0, MIN(self.runtimeListOffsetY, maxOffset));
                [self->_tableView setContentOffset:restoredOffset animated:NO];
            }
        });
    });
}

- (void)_loadClassDetail {
    self.selectedDetailItem = nil;
    NSMutableArray *rows = [NSMutableArray new];
    VCClassInfo *ci = _selectedClass;
    NSString *filter = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *needle = filter.lowercaseString;
    BOOL hasFilter = needle.length > 0;
    [rows addObject:@{@"kind": @"meta", @"title": VCTextLiteral(@"Class"), @"value": ci.className ?: @"(unknown)"}];
    [rows addObject:@{@"kind": @"meta", @"title": VCTextLiteral(@"Superclass"), @"value": ci.superClassName ?: @"(none)"}];
    [rows addObject:@{@"kind": @"meta", @"title": VCTextLiteral(@"Module"), @"value": ci.moduleName ?: @"(unknown)"}];
    if (ci.protocols.count) {
        [rows addObject:@{@"kind": @"meta", @"title": VCTextLiteral(@"Protocols"), @"value": [ci.protocols componentsJoinedByString:@", "]}];
    }

    NSArray<VCMethodInfo *> *instanceMethods = ci.instanceMethods ?: @[];
    NSArray<VCMethodInfo *> *classMethods = ci.classMethods ?: @[];
    NSArray<VCIvarInfo *> *ivars = ci.ivars ?: @[];
    NSArray<VCPropertyInfo *> *properties = ci.properties ?: @[];
    if (hasFilter) {
        NSPredicate *methodFilter = [NSPredicate predicateWithBlock:^BOOL(VCMethodInfo *evaluated, NSDictionary<NSString *,id> * _Nullable bindings) {
            NSString *candidate = [NSString stringWithFormat:@"%@ %@ %@", evaluated.selector ?: @"", evaluated.decodedSignature ?: @"", evaluated.typeEncoding ?: @""].lowercaseString;
            return [candidate containsString:needle];
        }];
        NSPredicate *ivarFilter = [NSPredicate predicateWithBlock:^BOOL(VCIvarInfo *evaluated, NSDictionary<NSString *,id> * _Nullable bindings) {
            NSString *candidate = [NSString stringWithFormat:@"%@ %@", evaluated.name ?: @"", evaluated.decodedType ?: evaluated.typeEncoding ?: @""].lowercaseString;
            return [candidate containsString:needle];
        }];
        NSPredicate *propertyFilter = [NSPredicate predicateWithBlock:^BOOL(VCPropertyInfo *evaluated, NSDictionary<NSString *,id> * _Nullable bindings) {
            NSString *candidate = [NSString stringWithFormat:@"%@ %@ %@ %@", evaluated.name ?: @"", evaluated.type ?: @"", evaluated.getter ?: @"", evaluated.setter ?: @""].lowercaseString;
            return [candidate containsString:needle];
        }];
        instanceMethods = [instanceMethods filteredArrayUsingPredicate:methodFilter];
        classMethods = [classMethods filteredArrayUsingPredicate:methodFilter];
        ivars = [ivars filteredArrayUsingPredicate:ivarFilter];
        properties = [properties filteredArrayUsingPredicate:propertyFilter];
        [rows addObject:@{@"kind": @"meta", @"title": VCTextLiteral(@"Search"), @"value": filter ?: @""}];
    }

    NSString *summaryValue = [NSString stringWithFormat:@"%@ %@ • %@ %@ • %@ %@ • %@ %@",
                              @(instanceMethods.count), VCTextLiteral(@"Instance Methods"),
                              @(classMethods.count), VCTextLiteral(@"Class Methods"),
                              @(ivars.count), VCTextLiteral(@"Ivars"),
                              @(properties.count), VCTextLiteral(@"Properties")];
    [rows addObject:@{@"kind": @"meta", @"title": VCTextLiteral(@"Process summary"), @"value": summaryValue}];

    [rows addObject:@{@"kind": @"section", @"title": [NSString stringWithFormat:@"%@ (%lu)", VCTextLiteral(@"Instance Methods"), (unsigned long)instanceMethods.count]}];
    for (VCMethodInfo *m in instanceMethods) {
        [rows addObject:@{
            @"kind": @"method",
            @"scope": @"instance",
            @"title": [NSString stringWithFormat:@"-[%@ %@]", ci.className ?: @"Class", m.selector ?: @"selector"],
            @"selector": m.selector ?: @"",
            @"signature": m.decodedSignature ?: m.typeEncoding ?: @"",
            @"rva": [NSString stringWithFormat:@"0x%lX", (unsigned long)m.rva]
        }];
    }
    [rows addObject:@{@"kind": @"section", @"title": [NSString stringWithFormat:@"%@ (%lu)", VCTextLiteral(@"Class Methods"), (unsigned long)classMethods.count]}];
    for (VCMethodInfo *m in classMethods) {
        [rows addObject:@{
            @"kind": @"method",
            @"scope": @"class",
            @"title": [NSString stringWithFormat:@"+[%@ %@]", ci.className ?: @"Class", m.selector ?: @"selector"],
            @"selector": m.selector ?: @"",
            @"signature": m.decodedSignature ?: m.typeEncoding ?: @"",
            @"rva": [NSString stringWithFormat:@"0x%lX", (unsigned long)m.rva]
        }];
    }
    [rows addObject:@{@"kind": @"section", @"title": [NSString stringWithFormat:@"%@ (%lu)", VCTextLiteral(@"Ivars"), (unsigned long)ivars.count]}];
    for (VCIvarInfo *iv in ivars) {
        [rows addObject:@{
            @"kind": @"ivar",
            @"title": iv.name ?: @"ivar",
            @"type": iv.decodedType ?: iv.typeEncoding ?: @"id",
            @"offset": [NSString stringWithFormat:@"%ld", (long)iv.offset]
        }];
    }
    [rows addObject:@{@"kind": @"section", @"title": [NSString stringWithFormat:@"%@ (%lu)", VCTextLiteral(@"Properties"), (unsigned long)properties.count]}];
    for (VCPropertyInfo *p in properties) {
        NSString *access = p.isReadonly ? @"readonly" : @"mutable";
        NSString *setter = p.setter.length > 0 ? p.setter : @"(default setter)";
        [rows addObject:@{
            @"kind": @"property",
            @"title": p.name ?: @"property",
            @"type": p.type ?: @"id",
            @"getter": p.getter ?: @"",
            @"setter": setter,
            @"access": access
        }];
    }
    _dataSource = rows;
    [self _updateStatus];
    [_tableView reloadData];
    [self _refreshActionDock];
}

- (void)_loadProcess {
    NSMutableArray *rows = [NSMutableArray new];
    VCProcessInfo *pi = [VCProcessInfo shared];
    NSDictionary *info = [pi basicInfo];
    for (NSString *key in [info.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [rows addObject:[NSString stringWithFormat:@"%@: %@", key, info[key]]];
    }
    [rows addObject:@"--- Loaded Modules ---"];
    for (VCModuleInfo *mod in [pi loadedModules]) {
        NSString *address = [NSString stringWithFormat:@"0x%llX", mod.loadAddress];
        [rows addObject:@{
            @"kind": @"process_module",
            @"title": mod.name ?: @"Module",
            @"address": address,
            @"detail": [NSString stringWithFormat:@"%@ • %@ +0x%X", mod.category ?: @"", address, mod.size],
            @"category": mod.category ?: @"",
            @"size": @(mod.size)
        }];
    }
    [rows addObject:@"--- Memory Regions ---"];
    for (VCMemRegion *reg in [pi memoryRegions]) {
        NSString *address = [NSString stringWithFormat:@"0x%llX", reg.start];
        [rows addObject:@{
            @"kind": @"process_region",
            @"title": [NSString stringWithFormat:@"0x%llX-0x%llX", reg.start, reg.end],
            @"address": address,
            @"detail": [NSString stringWithFormat:@"%@ • %u KB", reg.protection ?: @"", reg.size / 1024],
            @"protection": reg.protection ?: @"",
            @"size": @(reg.size)
        }];
    }
    _dataSource = rows;
    [self _updateStatus];
    [_tableView reloadData];
    [self _refreshActionDock];
}

- (void)_loadStrings:(NSString *)filter {
    if (!filter.length) {
        _dataSource = @[VCTextLiteral(@"Enter a search pattern to scan strings")];
        [_tableView reloadData];
        [self _refreshActionDock];
        return;
    }
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSArray *results = [VCStringScanner scanStringsMatching:filter inModule:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray *rows = [NSMutableArray new];
            for (VCStringResult *r in results) {
                NSString *address = [NSString stringWithFormat:@"0x%lX", (unsigned long)r.address];
                NSString *rva = [NSString stringWithFormat:@"0x%lX", (unsigned long)r.rva];
                [rows addObject:@{
                    @"kind": @"string_result",
                    @"title": r.value ?: @"",
                    @"section": r.section ?: @"",
                    @"moduleName": r.moduleName ?: @"",
                    @"address": address,
                    @"rva": rva,
                    @"detail": [NSString stringWithFormat:@"%@ • %@ • %@", r.section ?: @"", address, rva]
                }];
            }
            if (!rows.count) [rows addObject:VCTextLiteral(@"No strings found")];
            self->_dataSource = rows;
            [self _updateStatus];
            [self->_tableView reloadData];
            [self _refreshActionDock];
        });
    });
}

- (void)_loadInstances:(NSString *)filter {
    if (!filter.length) {
        _dataSource = @[VCTextLiteral(@"Enter a class name to scan instances")];
        [_tableView reloadData];
        [self _refreshActionDock];
        return;
    }
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSArray *results = [VCInstanceScanner scanInstancesOfClass:filter];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray *rows = [NSMutableArray new];
            for (VCInstanceRecord *r in results) {
                NSString *address = [NSString stringWithFormat:@"0x%lX", (unsigned long)r.address];
                [rows addObject:@{
                    @"kind": @"instance_result",
                    @"title": r.className ?: @"Instance",
                    @"address": address,
                    @"detail": r.briefDescription ?: @"",
                    @"hasLiveObject": @(r.instance != nil)
                }];
            }
            if (!rows.count) [rows addObject:VCTextLiteral(@"No live instances found")];
            self->_dataSource = rows;
            [self _updateStatus];
            [self->_tableView reloadData];
            [self _refreshActionDock];
        });
    });
}

- (NSString *)_uiPreviewForNode:(VCViewNode *)node {
    NSString *preview = [node.briefDescription isKindOfClass:[NSString class]] ? node.briefDescription : @"";
    NSString *className = node.className ?: @"";
    if (className.length > 0 && [preview hasPrefix:className]) {
        preview = [preview substringFromIndex:className.length];
    }
    preview = [preview stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *sizeChars = [NSCharacterSet characterSetWithCharactersInString:@"0123456789xX. "];
    BOOL sizeOnly = preview.length == 0 || [[preview stringByTrimmingCharactersInSet:sizeChars] length] == 0;
    return sizeOnly ? @"" : preview;
}

- (NSDictionary *)_uiEntryForNode:(VCViewNode *)node depth:(NSInteger)depth {
    BOOL hasChildren = node.children.count > 0;
    NSNumber *addrKey = @(node.address);
    BOOL collapsed = [self.collapsedUIAddresses containsObject:addrKey];
    NSString *address = [NSString stringWithFormat:@"0x%lX", (unsigned long)node.address];
    NSString *preview = [self _uiPreviewForNode:node];
    NSString *size = [NSString stringWithFormat:@"%.0fx%.0f", CGRectGetWidth(node.frame), CGRectGetHeight(node.frame)];
    NSString *detail = preview.length > 0
        ? [NSString stringWithFormat:@"%@ • %@ • %@", size, address, preview]
        : [NSString stringWithFormat:@"%@ • %@", size, address];
    return @{
        @"kind": @"ui_view",
        @"node": node,
        @"title": node.className ?: @"UIView",
        @"detail": detail,
        @"address": address,
        @"depth": @(depth),
        @"hasChildren": @(hasChildren),
        @"collapsed": @(collapsed),
        @"childrenCount": @(node.children.count),
        @"preview": preview ?: @""
    };
}

- (void)_flattenUINode:(VCViewNode *)node depth:(NSInteger)depth query:(NSString *)query intoArray:(NSMutableArray *)rows {
    if (!node) return;
    NSDictionary *entry = [self _uiEntryForNode:node depth:depth];
    BOOL hasQuery = query.length > 0;
    if (hasQuery) {
        NSString *candidate = [NSString stringWithFormat:@"%@ %@ %@ %@",
                               entry[@"title"] ?: @"",
                               entry[@"detail"] ?: @"",
                               entry[@"address"] ?: @"",
                               node.briefDescription ?: @""].lowercaseString;
        if ([candidate containsString:query]) {
            [rows addObject:entry];
        }
        for (VCViewNode *child in node.children) {
            [self _flattenUINode:child depth:depth + 1 query:query intoArray:rows];
        }
        return;
    }
    [rows addObject:entry];
    if (![self.collapsedUIAddresses containsObject:@(node.address)]) {
        for (VCViewNode *child in node.children) {
            [self _flattenUINode:child depth:depth + 1 query:query intoArray:rows];
        }
    }
}

- (void)_loadUIHierarchy:(NSString *)filter {
    VCViewNode *root = [[VCUIInspector shared] viewHierarchyTree];
    NSMutableArray *rows = [NSMutableArray new];
    NSString *query = [[filter ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    [self _flattenUINode:root depth:0 query:query intoArray:rows];
    self.dataSource = rows;
    [self _updateStatus];
    [self.tableView reloadData];
    [self _refreshActionDock];
}

- (void)_updateStatus {
    NSString *mode = [_segCtrl titleForSegmentAtIndex:_segCtrl.selectedSegmentIndex] ?: @"Inspect";
    if (self.segCtrl.selectedSegmentIndex == VCInspectSubTabAll) {
        self.titleLabel.text = VCTextLiteral(@"RUNTIME WORKSPACE");
        NSString *filter = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.statusLabel.text = filter.length > 0
            ? [NSString stringWithFormat:@"%@ • %@ %lu", VCTextLiteral(@"All"), VCTextLiteral(@"Search"), (unsigned long)self.dataSource.count]
            : [NSString stringWithFormat:@"%@ • %lu", VCTextLiteral(@"All"), (unsigned long)self.dataSource.count];
    } else if ([self _isUISegment]) {
        self.titleLabel.text = VCTextLiteral(@"UI HIERARCHY");
        NSString *filter = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.statusLabel.text = filter.length > 0
            ? [NSString stringWithFormat:@"%@ • %@ %lu", VCTextLiteral(@"UI"), VCTextLiteral(@"Search"), (unsigned long)self.dataSource.count]
            : [NSString stringWithFormat:@"%@ • %lu", VCTextLiteral(@"UI"), (unsigned long)self.dataSource.count];
    } else if (_selectedClass) {
        self.titleLabel.text = VCTextLiteral(@"CLASS DETAIL");
        NSString *filter = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (filter.length > 0) {
            _statusLabel.text = [NSString stringWithFormat:@"%@ / %@ • %@ %lu", VCTextLiteral(@"Members"), _selectedClass.className ?: mode, VCTextLiteral(@"Search"), (unsigned long)self.dataSource.count];
        } else {
            _statusLabel.text = [NSString stringWithFormat:@"%@ / %@ • %lu", VCTextLiteral(@"Members"), _selectedClass.className ?: mode, (unsigned long)self.dataSource.count];
        }
    } else {
        self.titleLabel.text = VCTextLiteral(@"RUNTIME WORKSPACE");
        _statusLabel.text = [NSString stringWithFormat:@"%@ • %lu", mode, (unsigned long)_dataSource.count];
    }
    [self _updateHeaderActionButton];
    [self _refreshActionDock];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self _cacheCurrentState];
    if (_selectedClass) {
        [self _loadClassDetail];
    } else {
        self.selectedDetailItem = nil;
        [self _loadData];
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self _cacheCurrentState];
    BOOL isDetailSearch = (_segCtrl.selectedSegmentIndex == VCInspectSubTabMembers && _selectedClass != nil);
    if (isDetailSearch) {
        [self _loadClassDetail];
        return;
    }
    if (_segCtrl.selectedSegmentIndex == VCInspectSubTabAll ||
        _segCtrl.selectedSegmentIndex == VCInspectSubTabMembers ||
        _segCtrl.selectedSegmentIndex == VCInspectSubTabStrings ||
        _segCtrl.selectedSegmentIndex == VCInspectSubTabInstances ||
        _segCtrl.selectedSegmentIndex == VCInspectSubTabUI ||
        searchText.length == 0) {
        _selectedClass = nil;
        if (_segCtrl.selectedSegmentIndex != VCInspectSubTabUI) {
            self.selectedDetailItem = nil;
        }
        [self _loadData];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_dataSource.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID forIndexPath:indexPath];
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.92];
    cell.contentView.layer.cornerRadius = 10.0;
    cell.contentView.layer.borderWidth = 1.0;
    cell.contentView.layer.borderColor = kVCBorder.CGColor;
    cell.textLabel.font = kVCFontMonoSm;
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.textLabel.textColor = kVCTextPrimary;

    UIView *selectedBg = [[UIView alloc] init];
    selectedBg.backgroundColor = kVCAccentDim;
    selectedBg.layer.cornerRadius = 12.0;
    cell.selectedBackgroundView = selectedBg;

    id item = _dataSource[indexPath.row];
    if ([item isKindOfClass:[VCClassInfo class]]) {
        VCClassInfo *ci = item;
        cell.textLabel.text = [NSString stringWithFormat:@"[C] %@\n%@ • %@", ci.className ?: @"--", ci.superClassName ?: @"NSObject", ci.moduleName ?: @"runtime"];
        cell.textLabel.textColor = kVCAccent;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([item isKindOfClass:[NSDictionary class]]) {
        NSString *kind = item[@"kind"];
        NSString *title = item[@"title"] ?: @"";
        NSString *detailText = @"";
        UIColor *titleColor = kVCTextPrimary;
        if ([kind isEqualToString:@"section"]) {
            detailText = VCTextLiteral(@"Left swipe: Operation");
            titleColor = kVCYellow;
        } else if ([kind isEqualToString:@"meta"]) {
            detailText = item[@"value"] ?: @"";
            titleColor = kVCAccent;
        } else if ([kind isEqualToString:@"method"]) {
            detailText = [NSString stringWithFormat:@"%@ • RVA %@",
                          item[@"signature"] ?: @"",
                          item[@"rva"] ?: @"--"];
            titleColor = kVCGreen;
        } else if ([kind isEqualToString:@"ivar"]) {
            detailText = [NSString stringWithFormat:@"%@ • offset %@",
                          item[@"type"] ?: @"id",
                          item[@"offset"] ?: @"0"];
            titleColor = kVCTextPrimary;
        } else if ([kind isEqualToString:@"property"]) {
            detailText = [NSString stringWithFormat:@"%@ • %@ • %@",
                          item[@"type"] ?: @"id",
                          item[@"access"] ?: @"mutable",
                          item[@"setter"] ?: @"setter"];
            titleColor = kVCAccentHover;
        } else if ([kind isEqualToString:@"string_result"]) {
            detailText = [NSString stringWithFormat:@"%@ • %@", item[@"detail"] ?: @"", item[@"address"] ?: @""];
            titleColor = kVCGreen;
        } else if ([kind isEqualToString:@"instance_result"]) {
            detailText = [NSString stringWithFormat:@"%@ • %@", item[@"address"] ?: @"", item[@"detail"] ?: @""];
            titleColor = kVCAccentHover;
        } else if ([kind isEqualToString:@"process_module"]) {
            detailText = [NSString stringWithFormat:@"%@ • %@", item[@"detail"] ?: @"", item[@"address"] ?: @""];
            titleColor = kVCAccent;
        } else if ([kind isEqualToString:@"process_region"]) {
            detailText = [NSString stringWithFormat:@"%@ • %@", item[@"detail"] ?: @"", item[@"address"] ?: @""];
            titleColor = kVCYellow;
        } else if ([kind isEqualToString:@"process_overview"]) {
            detailText = item[@"detail"] ?: @"";
            titleColor = kVCGreen;
        } else if ([kind isEqualToString:@"ui_view"]) {
            NSInteger depth = [item[@"depth"] integerValue];
            BOOL hasChildren = [item[@"hasChildren"] boolValue];
            BOOL collapsed = [item[@"collapsed"] boolValue];
            NSString *prefix = hasChildren ? (collapsed ? @"▸ " : @"▾ ") : @"• ";
            NSMutableString *indent = [NSMutableString string];
            for (NSInteger idx = 0; idx < MIN(depth, 10); idx++) {
                [indent appendString:@"  "];
            }
            title = [NSString stringWithFormat:@"%@%@%@", indent, prefix, item[@"title"] ?: @"UIView"];
            NSString *children = hasChildren ? [NSString stringWithFormat:@" • %@ children", item[@"childrenCount"] ?: @0] : @"";
            detailText = [NSString stringWithFormat:@"%@%@", item[@"detail"] ?: @"", children];
            VCViewNode *node = item[@"node"];
            BOOL selected = (node.view && node.view == self.selectedUIView);
            titleColor = selected ? kVCAccent : kVCTextPrimary;
        }
        NSString *fullText = detailText.length > 0 ? [NSString stringWithFormat:@"%@\n%@", title, detailText] : title;
        NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:fullText];
        [attr addAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: titleColor
        } range:NSMakeRange(0, title.length)];
        if (detailText.length > 0) {
            [attr addAttributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium],
                NSForegroundColorAttributeName: kVCTextSecondary
            } range:NSMakeRange(title.length + 1, detailText.length)];
        }
        cell.textLabel.text = nil;
        cell.textLabel.attributedText = attr;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        cell.textLabel.text = item;
        NSString *s = item;
        if ([s hasPrefix:@"[Class]"] || [s hasPrefix:@"[Super]"] || [s hasPrefix:@"[Module]"] || [s hasPrefix:@"[Protocols]"]) {
            cell.textLabel.textColor = kVCAccent;
        } else if ([s hasPrefix:@"---"]) {
            cell.textLabel.textColor = kVCYellow;
        } else if ([s hasPrefix:@"  -["] || [s hasPrefix:@"  +["]) {
            cell.textLabel.textColor = kVCGreen;
        } else {
            cell.textLabel.textColor = kVCTextPrimary;
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.frame = UIEdgeInsetsInsetRect(cell.frame, UIEdgeInsetsMake(4, 10, 4, 10));
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    id item = _dataSource[indexPath.row];
    if ([item isKindOfClass:[VCClassInfo class]]) {
        VCClassInfo *ci = item;
        _runtimeListOffsetY = tableView.contentOffset.y;
        if (self.segCtrl.selectedSegmentIndex != VCInspectSubTabMembers) {
            self.segCtrl.selectedSegmentIndex = VCInspectSubTabMembers;
        }
        _selectedClass = [[VCRuntimeEngine shared] classInfoForName:ci.className];
        self.selectedDetailItem = nil;
        [self _loadClassDetail];
        return;
    }
    if ([item isKindOfClass:[NSDictionary class]]) {
        NSString *kind = item[@"kind"];
        if ([kind isEqualToString:@"ui_view"]) {
            VCViewNode *node = item[@"node"];
            if ([item[@"hasChildren"] boolValue] && node) {
                NSNumber *addrKey = @(node.address);
                if ([self.collapsedUIAddresses containsObject:addrKey]) {
                    [self.collapsedUIAddresses removeObject:addrKey];
                } else {
                    [self.collapsedUIAddresses addObject:addrKey];
                }
            }
            UIView *view = node.view ?: [[VCUIInspector shared] viewForAddress:node.address];
            if (view) {
                self.selectedUIView = view;
                [[VCUIInspector shared] rememberSelectedView:view];
                [[VCUIInspector shared] highlightView:view];
                self.selectedDetailItem = item;
                self.statusLabel.text = [NSString stringWithFormat:@"%@ %@", VCTextLiteral(@"Selected"), NSStringFromClass([view class])];
                [self _refreshActionDock];
            } else {
                self.selectedDetailItem = nil;
                self.statusLabel.text = VCTextLiteral(@"View is unavailable");
                [self _refreshActionDock];
            }
            if (self.segCtrl.selectedSegmentIndex == VCInspectSubTabUI) {
                [self _loadUIHierarchy:self.searchBar.text.length > 0 ? self.searchBar.text : nil];
            } else {
                [self _loadData];
            }
            return;
        }
        BOOL actionable = [kind isEqualToString:@"method"] || [kind isEqualToString:@"ivar"] || [kind isEqualToString:@"property"];
        if ([kind isEqualToString:@"string_result"] ||
            [kind isEqualToString:@"instance_result"] ||
            [kind isEqualToString:@"process_module"] ||
            [kind isEqualToString:@"process_region"]) {
            self.selectedDetailItem = item;
            self.statusLabel.text = VCTextLiteral(@"Swipe left for member actions");
            [self _refreshActionDock];
            return;
        }
        if (actionable) {
            self.selectedDetailItem = item;
            self.statusLabel.text = VCTextLiteral(@"Swipe left for member actions");
            [self _refreshActionDock];
        }
    }
}

- (void)_prepareInspectItemForAction:(id)item {
    if (![item isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *dictionary = (NSDictionary *)item;
    NSString *kind = dictionary[@"kind"] ?: @"";
    if ([kind isEqualToString:@"ui_view"]) {
        VCViewNode *node = dictionary[@"node"];
        UIView *view = node.view ?: [[VCUIInspector shared] viewForAddress:node.address];
        if (view) {
            self.selectedUIView = view;
            [[VCUIInspector shared] rememberSelectedView:view];
            [[VCUIInspector shared] highlightView:view];
        }
    }
    self.selectedDetailItem = dictionary;
    [self _refreshActionDock];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.dataSource.count) return nil;
    id item = self.dataSource[indexPath.row];

    UIContextualAction *chatAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                             title:VCTextLiteral(@"Chat")
                                                                           handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self _queueInspectReferenceForItem:item];
        completionHandler(YES);
    }];
    chatAction.backgroundColor = UIColorFromHex(0x2563eb);
    chatAction.image = nil;

    if (![item isKindOfClass:[NSDictionary class]]) {
        UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[chatAction]];
        config.performsFirstActionWithFullSwipe = NO;
        return config;
    }

    NSString *kind = item[@"kind"];
    BOOL actionable = [kind isEqualToString:@"ui_view"] ||
        [kind isEqualToString:@"method"] ||
        [kind isEqualToString:@"ivar"] ||
        [kind isEqualToString:@"property"] ||
        [kind isEqualToString:@"string_result"] ||
        [kind isEqualToString:@"instance_result"] ||
        [kind isEqualToString:@"process_module"] ||
        [kind isEqualToString:@"process_region"];
    if (actionable) {
        UIContextualAction *operationAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                      title:VCTextLiteral(@"Operation")
                                                                                    handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self _prepareInspectItemForAction:item];
            [self _showActionDrawer];
            completionHandler(YES);
        }];
        operationAction.backgroundColor = UIColorFromHex(0x0f766e);
        operationAction.image = nil;
        UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[operationAction, chatAction]];
        config.performsFirstActionWithFullSwipe = NO;
        return config;
    }

    NSMutableArray<UIContextualAction *> *actions = [NSMutableArray arrayWithObject:chatAction];
    if ([kind isEqualToString:@"ui_view"]) {
        UIContextualAction *toggleHidden = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                   title:VCTextLiteral(@"Hide")
                                                                                 handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            self.selectedDetailItem = item;
            [self _performSecondaryInspectAction];
            completionHandler(YES);
        }];
        toggleHidden.backgroundColor = UIColorFromHex(0xd97706);
        toggleHidden.image = nil;

        UIContextualAction *copyAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                 title:VCTextLiteral(@"Copy")
                                                                               handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            self.selectedDetailItem = item;
            [self _performQuaternaryInspectAction];
            completionHandler(YES);
        }];
        copyAction.backgroundColor = UIColorFromHex(0x9333ea);
        copyAction.image = nil;
        [actions addObjectsFromArray:@[toggleHidden, copyAction]];
    } else if ([kind isEqualToString:@"method"] && ![item[@"scope"] isEqualToString:@"class"]) {
        UIContextualAction *hookAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                 title:VCTextLiteral(@"Hook")
                                                                               handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self _addHookForMethodItem:item];
            completionHandler(YES);
        }];
        hookAction.backgroundColor = UIColorFromHex(0x0f766e);
        hookAction.image = nil;

        UIContextualAction *patchAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                  title:VCTextLiteral(@"Patch")
                                                                                handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self _addPatchDraftForMethodItem:item];
            completionHandler(YES);
        }];
        patchAction.backgroundColor = UIColorFromHex(0x7c3aed);
        patchAction.image = nil;
        [actions addObjectsFromArray:@[hookAction, patchAction]];
    } else if ([kind isEqualToString:@"ivar"] || [kind isEqualToString:@"property"] || [kind isEqualToString:@"method"]) {
        if ([kind isEqualToString:@"ivar"] || [kind isEqualToString:@"property"]) {
            UIContextualAction *valueAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                      title:VCTextLiteral(@"Value")
                                                                                    handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
                [self _openValueDraftForMemberItem:item];
                completionHandler(YES);
            }];
            valueAction.backgroundColor = UIColorFromHex(0xd97706);
            valueAction.image = nil;
            [actions addObject:valueAction];
        }
        UIContextualAction *copyAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                 title:VCTextLiteral(@"Copy")
                                                                               handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            NSString *copyText = item[@"title"] ?: item[@"selector"] ?: @"member";
            [UIPasteboard generalPasteboard].string = copyText;
            self.statusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Copied %@"), copyText];
            completionHandler(YES);
        }];
        copyAction.backgroundColor = UIColorFromHex(0x9333ea);
        copyAction.image = nil;
        [actions addObject:copyAction];
    }
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:actions];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (void)_queueInspectReferenceForItem:(id)item {
    NSDictionary *reference = [self _referenceDictionaryForInspectItem:item];
    if (!reference) return;
    [[VCChatSession shared] enqueuePendingReference:reference];
    self.statusLabel.text = [NSString stringWithFormat:@"Queued %@ for Chat", reference[@"kind"] ?: @"Inspect"];
    [[NSNotificationCenter defaultCenter] postNotificationName:VCSettingsRequestOpenAIChatNotification object:self];
}

- (void)_openPatchesEditorForItem:(id)item segment:(NSInteger)segment {
    if (!item) return;
    NSDictionary *userInfo = @{
        VCPatchesOpenEditorSegmentKey: @(segment),
        VCPatchesOpenEditorItemKey: item,
        VCPatchesOpenEditorCreatesKey: @YES,
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:VCPatchesRequestOpenEditorNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)_openMemoryForInspectAddress:(NSString *)address {
    if (address.length == 0) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:VCMemoryBrowserRequestOpenAddressNotification
                                                        object:self
                                                      userInfo:@{ VCMemoryBrowserOpenAddressKey: address }];
    self.statusLabel.text = [NSString stringWithFormat:@"%@ %@", VCTextLiteral(@"Open Memory"), address];
}

- (NSDictionary *)_referenceDictionaryForInspectItem:(id)item {
    NSString *referenceID = [[NSUUID UUID] UUIDString];
    if ([item isKindOfClass:[VCClassInfo class]]) {
        VCClassInfo *ci = item;
        return @{
            @"referenceID": referenceID,
            @"kind": @"Inspect",
            @"title": ci.className ?: @"Class",
            @"payload": @{
                @"type": @"class",
                @"className": ci.className ?: @"",
                @"superClassName": ci.superClassName ?: @"",
                @"moduleName": ci.moduleName ?: @""
            }
        };
    }
    if (![item isKindOfClass:[NSDictionary class]]) return nil;
    if ([item[@"kind"] isEqualToString:@"ui_view"]) {
        VCViewNode *node = item[@"node"];
        UIView *view = node.view ?: [[VCUIInspector shared] viewForAddress:node.address];
        if (!view) return nil;
        NSDictionary *props = [[VCUIInspector shared] propertiesForView:view] ?: @{};
        NSArray *chain = [[VCUIInspector shared] responderChainForView:view] ?: @[];
        NSString *className = NSStringFromClass([view class]) ?: @"UIView";
        NSString *address = [NSString stringWithFormat:@"0x%llx", (unsigned long long)(uintptr_t)(__bridge void *)view];
        return @{
            @"referenceID": referenceID,
            @"kind": @"UI",
            @"title": [NSString stringWithFormat:@"%@ • %@", className, address],
            @"payload": @{
                @"type": @"selected_view",
                @"className": className,
                @"address": address,
                @"frame": NSStringFromCGRect(view.frame),
                @"bounds": NSStringFromCGRect(view.bounds),
                @"properties": props,
                @"responderChain": chain,
                @"accessibilityLabel": view.accessibilityLabel ?: @"",
                @"accessibilityIdentifier": view.accessibilityIdentifier ?: @""
            }
        };
    }
    if ([item[@"kind"] isEqualToString:@"string_result"] ||
        [item[@"kind"] isEqualToString:@"instance_result"] ||
        [item[@"kind"] isEqualToString:@"process_module"] ||
        [item[@"kind"] isEqualToString:@"process_region"] ||
        [item[@"kind"] isEqualToString:@"process_overview"]) {
        NSMutableDictionary *payload = [item mutableCopy];
        NSString *kind = item[@"kind"] ?: @"Inspect";
        NSString *title = item[@"title"] ?: item[@"address"] ?: kind;
        return @{
            @"referenceID": referenceID,
            @"kind": @"Inspect",
            @"title": title,
            @"payload": payload
        };
    }
    NSMutableDictionary *payload = [item mutableCopy];
    payload[@"className"] = self.selectedClass.className ?: @"";
    payload[@"moduleName"] = self.selectedClass.moduleName ?: @"";
    NSString *kind = item[@"kind"] ?: @"Inspect";
    NSString *title = item[@"title"] ?: kind;
    return @{
        @"referenceID": referenceID,
        @"kind": @"Inspect",
        @"title": [NSString stringWithFormat:@"%@ • %@", self.selectedClass.className ?: @"Class", title],
        @"payload": payload
    };
}

- (void)_addHookForMethodItem:(NSDictionary *)item {
    NSString *selector = item[@"selector"];
    if (selector.length == 0 || self.selectedClass.className.length == 0) return;
    VCHookItem *hook = [[VCHookItem alloc] init];
    hook.className = self.selectedClass.className;
    hook.selector = selector;
    hook.hookType = @"log";
    hook.remark = [NSString stringWithFormat:@"Inspect quick hook for %@", selector];
    [self _openPatchesEditorForItem:hook segment:2];
    self.statusLabel.text = [NSString stringWithFormat:@"Opened hook editor for %@", selector];
}

- (void)_addPatchDraftForMethodItem:(NSDictionary *)item {
    NSString *selector = item[@"selector"];
    if (selector.length == 0 || self.selectedClass.className.length == 0) return;
    VCPatchItem *patch = [[VCPatchItem alloc] init];
    patch.className = self.selectedClass.className;
    patch.selector = selector;
    patch.patchType = @"nop";
    patch.enabled = NO;
    patch.remark = [NSString stringWithFormat:@"Inspect quick patch draft for %@", selector];
    [self _openPatchesEditorForItem:patch segment:0];
    self.statusLabel.text = [NSString stringWithFormat:@"Opened patch editor for %@", selector];
}

- (NSString *)_defaultValueTypeForInspectType:(NSString *)typeString {
    NSString *type = typeString.lowercaseString ?: @"";
    if ([type containsString:@"bool"] || [type isEqualToString:@"b"]) return @"BOOL";
    if ([type containsString:@"float"]) return @"float";
    if ([type containsString:@"double"]) return @"double";
    if ([type containsString:@"long"]) return @"long";
    if ([type containsString:@"string"] || [type containsString:@"nsstring"] || [type containsString:@"char *"]) return @"NSString";
    return @"int";
}

- (void)_openValueDraftForMemberItem:(NSDictionary *)item {
    if (![item isKindOfClass:[NSDictionary class]] || self.selectedClass.className.length == 0) return;
    NSString *memberName = item[@"title"] ?: item[@"getter"] ?: @"member";
    VCValueItem *value = [[VCValueItem alloc] init];
    value.targetDesc = [NSString stringWithFormat:@"%@.%@", self.selectedClass.className, memberName];
    value.dataType = [self _defaultValueTypeForInspectType:(item[@"type"] ?: @"")];
    value.modifiedValue = @"";
    value.remark = [NSString stringWithFormat:@"Inspect quick value draft for %@", memberName];
    if ([item[@"kind"] isEqualToString:@"ivar"]) {
        value.offset = [item[@"offset"] longLongValue];
    }
    [self _openPatchesEditorForItem:value segment:1];
    self.statusLabel.text = [NSString stringWithFormat:@"Opened value editor for %@", memberName];
}

- (void)_openValueDraftForAddressItem:(NSDictionary *)item {
    if (![item isKindOfClass:[NSDictionary class]]) return;
    NSString *address = item[@"address"] ?: @"";
    if (address.length == 0) return;
    NSString *kind = item[@"kind"] ?: @"";
    VCValueItem *value = [[VCValueItem alloc] init];
    value.targetDesc = [NSString stringWithFormat:@"%@ %@", item[@"title"] ?: kind, address];
    value.dataType = [kind isEqualToString:@"string_result"] ? @"NSString" : @"int";
    value.modifiedValue = @"";
    value.remark = [NSString stringWithFormat:@"Inspect quick value draft for %@", address];
    unsigned long long numericAddress = 0;
    NSScanner *scanner = [NSScanner scannerWithString:address];
    [scanner scanHexLongLong:&numericAddress];
    value.offset = (long long)numericAddress;
    [self _openPatchesEditorForItem:value segment:1];
    self.statusLabel.text = [NSString stringWithFormat:@"Opened value editor for %@", address];
}

- (void)_layoutActionDock {
    if (!self.actionDock) return;

    UIEdgeInsets safeInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeInsets = self.view.safeAreaInsets;
    }

    CGFloat dockWidth = MIN(MAX(CGRectGetWidth(self.view.bounds) * 0.32, 132.0), 172.0);
    CGFloat dockHeight = 44.0;
    CGFloat dockX = floor((CGRectGetWidth(self.view.bounds) - dockWidth) * 0.5);
    CGFloat dockY = CGRectGetHeight(self.view.bounds) - safeInsets.bottom - dockHeight - 14.0;
    self.actionDockWidthConstraint.constant = dockWidth;
    self.actionDockHeightConstraint.constant = dockHeight;
    self.actionDockLeadingConstraint.constant = dockX;
    self.actionDockTopConstraint.constant = dockY;
    [self.view layoutIfNeeded];
}

- (void)_layoutActionOverlay {
    if (!self.actionOverlay || !self.actionDrawerCard) return;

    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape) || (width > height);
    BOOL sideSheetLandscape = landscape && width >= 560.0;
    CGFloat cardWidth = sideSheetLandscape ? MIN(MAX(width * 0.32, 308.0), 368.0) : (width - 24.0);
    CGFloat cardHeight = sideSheetLandscape ? 278.0 : 274.0;
    CGFloat cardX = sideSheetLandscape ? (width - cardWidth - 10.0) : 12.0;
    CGFloat cardY = sideSheetLandscape ? 10.0 : (height - cardHeight - 10.0);
    self.actionDrawerHandle.hidden = sideSheetLandscape;
    self.actionDrawerCardLeadingConstraint.constant = cardX;
    self.actionDrawerCardTopConstraint.constant = cardY;
    self.actionDrawerCardWidthConstraint.constant = cardWidth;
    self.actionDrawerCardHeightConstraint.constant = cardHeight;
    [self.actionOverlay layoutIfNeeded];
}

- (void)_layoutUIQuickEditOverlay {
    if (!self.uiQuickEditOverlay || !self.uiQuickEditCard) return;
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape) || (width > height);
    BOOL sideSheetLandscape = landscape && width >= 560.0;
    CGFloat cardWidth = sideSheetLandscape ? MIN(MAX(width * 0.32, 320.0), 380.0) : (width - 24.0);
    CGFloat maxHeight = MAX(300.0, height - 20.0);
    CGFloat cardHeight = MIN(sideSheetLandscape ? 420.0 : 420.0, maxHeight);
    CGFloat cardX = sideSheetLandscape ? (width - cardWidth - 10.0) : 12.0;
    CGFloat cardY = sideSheetLandscape ? 10.0 : (height - cardHeight - 10.0);
    self.uiQuickEditCardLeadingConstraint.constant = cardX;
    self.uiQuickEditCardTopConstraint.constant = cardY;
    self.uiQuickEditCardWidthConstraint.constant = cardWidth;
    self.uiQuickEditCardHeightConstraint.constant = cardHeight;
    [self.uiQuickEditOverlay layoutIfNeeded];
}

- (void)_showUIQuickEditor {
    UIView *view = [self _viewForUIInspectItem:self.selectedDetailItem];
    if (!view) return;
    [self _hideActionDrawer];
    self.actionDock.hidden = YES;
    self.actionDock.alpha = 0.0;
    self.actionDock.transform = CGAffineTransformIdentity;

    NSDictionary *props = [[VCUIInspector shared] propertiesForView:view] ?: @{};
    NSString *text = props[@"text"] ?: props[@"currentTitle"] ?: props[@"titleLabel.text"];
    NSString *bgColor = props[@"backgroundColor"];
    NSString *textColor = props[@"textColor"];
    NSString *tintColor = props[@"tintColor"];
    self.uiQuickTextField.text = ([text isKindOfClass:[NSString class]] && ![text isEqualToString:@"nil"]) ? text : @"";
    self.uiQuickColorField.text = ([bgColor isKindOfClass:[NSString class]] && ![bgColor isEqualToString:@"nil"]) ? bgColor : @"";
    self.uiQuickTextColorField.text = ([textColor isKindOfClass:[NSString class]] && ![textColor isEqualToString:@"nil"]) ? textColor : @"";
    self.uiQuickTintColorField.text = ([tintColor isKindOfClass:[NSString class]] && ![tintColor isEqualToString:@"nil"]) ? tintColor : @"";
    self.uiQuickAlphaField.text = [NSString stringWithFormat:@"%.2f", view.alpha];
    self.uiQuickFrameField.text = NSStringFromCGRect(view.frame);
    self.uiQuickTagField.text = [NSString stringWithFormat:@"%ld", (long)view.tag];
    self.uiQuickHiddenField.text = view.hidden ? @"true" : @"false";
    self.uiQuickInteractionField.text = view.userInteractionEnabled ? @"true" : @"false";
    self.uiQuickClipsField.text = view.clipsToBounds ? @"true" : @"false";
    self.uiQuickEditSubtitleLabel.text = [NSString stringWithFormat:@"%@ • %p", NSStringFromClass([view class]), view];
    [self.uiQuickEditScrollView setContentOffset:CGPointZero animated:NO];

    self.uiQuickEditOverlay.hidden = NO;
    [self.view bringSubviewToFront:self.uiQuickEditOverlay];
    self.uiQuickEditOverlay.alpha = 0.0;
    self.uiQuickEditOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    [self _layoutUIQuickEditOverlay];
    BOOL sideSheetLandscape = (((self.currentLayoutMode == VCPanelLayoutModeLandscape) || (CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds))) && CGRectGetWidth(self.view.bounds) >= 560.0);
    self.uiQuickEditCard.transform = sideSheetLandscape
        ? CGAffineTransformMakeTranslation(CGRectGetWidth(self.uiQuickEditCard.bounds) + 20.0, 0)
        : CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.uiQuickEditCard.bounds) + 20.0);
    [UIView animateWithDuration:0.22 animations:^{
        self.uiQuickEditOverlay.alpha = 1.0;
        self.uiQuickEditOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.24];
        self.uiQuickEditCard.transform = CGAffineTransformIdentity;
    }];
}

- (void)_hideUIQuickEditor {
    if (!self.uiQuickEditOverlay || self.uiQuickEditOverlay.hidden) return;
    BOOL sideSheetLandscape = (((self.currentLayoutMode == VCPanelLayoutModeLandscape) || (CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds))) && CGRectGetWidth(self.view.bounds) >= 560.0);
    [UIView animateWithDuration:0.18 animations:^{
        self.uiQuickEditOverlay.alpha = 0.0;
        self.uiQuickEditOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
        self.uiQuickEditCard.transform = sideSheetLandscape
            ? CGAffineTransformMakeTranslation(CGRectGetWidth(self.uiQuickEditCard.bounds) + 20.0, 0)
            : CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.uiQuickEditCard.bounds) + 20.0);
    } completion:^(__unused BOOL finished) {
        self.uiQuickEditOverlay.hidden = YES;
        self.uiQuickEditCard.transform = CGAffineTransformIdentity;
        [self _refreshActionDock];
    }];
}

- (BOOL)_quickEditBoolFromText:(NSString *)text fallback:(BOOL)fallback {
    NSString *value = [[text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (value.length == 0) return fallback;
    if ([value isEqualToString:@"1"] || [value isEqualToString:@"true"] || [value isEqualToString:@"yes"] || [value isEqualToString:@"y"]) return YES;
    if ([value isEqualToString:@"0"] || [value isEqualToString:@"false"] || [value isEqualToString:@"no"] || [value isEqualToString:@"n"]) return NO;
    return fallback;
}

- (void)_applyUIQuickEdit {
    UIView *view = [self _viewForUIInspectItem:self.selectedDetailItem];
    if (!view) return;
    BOOL changed = NO;
    NSString *text = [self.uiQuickTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length > 0) {
        [[VCUIInspector shared] modifyView:view property:@"text" value:text];
        changed = YES;
    }
    NSString *color = [self.uiQuickColorField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (color.length > 0) {
        [[VCUIInspector shared] modifyView:view property:@"backgroundColor" value:color];
        changed = YES;
    }
    NSString *textColor = [self.uiQuickTextColorField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (textColor.length > 0) {
        [[VCUIInspector shared] modifyView:view property:@"textColor" value:textColor];
        changed = YES;
    }
    NSString *tintColor = [self.uiQuickTintColorField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (tintColor.length > 0) {
        [[VCUIInspector shared] modifyView:view property:@"tintColor" value:tintColor];
        changed = YES;
    }
    NSString *alphaText = [self.uiQuickAlphaField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (alphaText.length > 0) {
        [[VCUIInspector shared] modifyView:view property:@"alpha" value:@([alphaText doubleValue])];
        changed = YES;
    }
    NSString *frameText = [self.uiQuickFrameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (frameText.length > 0 && !CGRectEqualToRect(CGRectFromString(frameText), CGRectZero)) {
        [[VCUIInspector shared] modifyView:view property:@"frame" value:frameText];
        changed = YES;
    }
    NSString *tagText = [self.uiQuickTagField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (tagText.length > 0) {
        [[VCUIInspector shared] modifyView:view property:@"tag" value:@([tagText integerValue])];
        changed = YES;
    }
    NSString *hiddenText = [self.uiQuickHiddenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (hiddenText.length > 0) {
        [[VCUIInspector shared] modifyView:view property:@"hidden" value:@([self _quickEditBoolFromText:hiddenText fallback:view.hidden])];
        changed = YES;
    }
    NSString *interactionText = [self.uiQuickInteractionField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (interactionText.length > 0) {
        [[VCUIInspector shared] modifyView:view property:@"userInteractionEnabled" value:@([self _quickEditBoolFromText:interactionText fallback:view.userInteractionEnabled])];
        changed = YES;
    }
    NSString *clipsText = [self.uiQuickClipsField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clipsText.length > 0) {
        [[VCUIInspector shared] modifyView:view property:@"clipsToBounds" value:@([self _quickEditBoolFromText:clipsText fallback:view.clipsToBounds])];
        changed = YES;
    }
    [[VCUIInspector shared] highlightView:view];
    [self _loadUIHierarchy:self.searchBar.text.length > 0 ? self.searchBar.text : nil];
    self.statusLabel.text = changed ? VCTextLiteral(@"Applied view edit") : VCTextLiteral(@"View selected");
    [self _hideUIQuickEditor];
}

- (void)_refreshActionDrawerButtons {
    NSDictionary *item = self.selectedDetailItem;
    NSString *kind = item[@"kind"] ?: @"";
    NSString *title = item[@"title"] ?: VCTextLiteral(@"Member");
    if ([kind isEqualToString:@"ui_view"]) {
        VCViewNode *node = item[@"node"];
        UIView *view = node.view ?: [[VCUIInspector shared] viewForAddress:node.address];
        self.actionDrawerTitleLabel.text = VCTextLiteral(@"View Actions");
        self.actionDrawerSubtitleLabel.text = view
            ? [NSString stringWithFormat:@"%@ • %p", NSStringFromClass([view class]), view]
            : (item[@"detail"] ?: title);
        [self.actionPrimaryButton setTitle:VCTextLiteral(@"Quick Edit") forState:UIControlStateNormal];
        [self.actionSecondaryButton setTitle:(view.hidden ? VCTextLiteral(@"Show") : VCTextLiteral(@"Hide")) forState:UIControlStateNormal];
        [self.actionTertiaryButton setTitle:(view.userInteractionEnabled ? VCTextLiteral(@"Disable Tap") : VCTextLiteral(@"Enable Tap")) forState:UIControlStateNormal];
        [self.actionQuaternaryButton setTitle:VCTextLiteral(@"Copy View") forState:UIControlStateNormal];
    } else if ([kind isEqualToString:@"string_result"] ||
               [kind isEqualToString:@"instance_result"] ||
               [kind isEqualToString:@"process_module"] ||
               [kind isEqualToString:@"process_region"]) {
        if ([kind isEqualToString:@"string_result"]) {
            self.actionDrawerTitleLabel.text = VCTextLiteral(@"String Actions");
        } else if ([kind isEqualToString:@"instance_result"]) {
            self.actionDrawerTitleLabel.text = VCTextLiteral(@"Instance Actions");
        } else {
            self.actionDrawerTitleLabel.text = VCTextLiteral(@"Memory Actions");
        }
        self.actionDrawerSubtitleLabel.text = [NSString stringWithFormat:@"%@ • %@", item[@"title"] ?: kind, item[@"address"] ?: @""];
        [self.actionPrimaryButton setTitle:VCTextLiteral(@"Open Memory") forState:UIControlStateNormal];
        [self.actionSecondaryButton setTitle:VCTextLiteral(@"Edit Value") forState:UIControlStateNormal];
        [self.actionTertiaryButton setTitle:VCTextLiteral(@"Copy Address") forState:UIControlStateNormal];
        [self.actionQuaternaryButton setTitle:([kind isEqualToString:@"string_result"] ? VCTextLiteral(@"Copy Text") : VCTextLiteral(@"Copy Object")) forState:UIControlStateNormal];
    } else {
        self.actionDrawerTitleLabel.text = VCTextLiteral(@"Inspect Actions");
        self.actionDrawerSubtitleLabel.text = self.selectedClass.className.length > 0
            ? [NSString stringWithFormat:@"%@ • %@", self.selectedClass.className, title]
            : title;

        [self.actionPrimaryButton setTitle:VCTextLiteral(@"Chat") forState:UIControlStateNormal];
        [self.actionSecondaryButton setTitle:([kind isEqualToString:@"method"] ? VCTextLiteral(@"Hook") : VCTextLiteral(@"Edit Value")) forState:UIControlStateNormal];
        [self.actionTertiaryButton setTitle:([kind isEqualToString:@"method"] ? VCTextLiteral(@"Patch") : VCTextLiteral(@"Copy Type")) forState:UIControlStateNormal];
        [self.actionQuaternaryButton setTitle:VCTextLiteral(@"Copy Name") forState:UIControlStateNormal];
    }

    self.actionPrimaryButton.hidden = NO;
    self.actionSecondaryButton.hidden = NO;
    self.actionTertiaryButton.hidden = NO;
    self.actionQuaternaryButton.hidden = NO;
    [self _removeActionButtonIcon:self.actionPrimaryButton];
    [self _removeActionButtonIcon:self.actionSecondaryButton];
    [self _removeActionButtonIcon:self.actionTertiaryButton];
    [self _removeActionButtonIcon:self.actionQuaternaryButton];
}

- (void)_refreshActionDock {
    if (!self.actionDock) return;
    self.actionDock.hidden = YES;
    self.actionDock.alpha = 0.0;
    self.actionDock.transform = CGAffineTransformIdentity;
    [self _refreshActionDrawerButtons];
}

- (void)_toggleActionDrawer {
    BOOL showing = self.actionOverlay && !self.actionOverlay.hidden;
    if (showing) {
        [self _hideActionDrawer];
    } else {
        [self _showActionDrawer];
    }
}

- (void)_showActionDrawer {
    if (![self.selectedDetailItem isKindOfClass:[NSDictionary class]]) return;

    [self _refreshActionDrawerButtons];
    self.actionOverlay.hidden = NO;
    [self.view bringSubviewToFront:self.actionOverlay];
    self.actionOverlay.alpha = 0.0;
    self.actionOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    [self _layoutActionOverlay];

    BOOL sideSheetLandscape = (((self.currentLayoutMode == VCPanelLayoutModeLandscape) || (CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds))) && CGRectGetWidth(self.view.bounds) >= 560.0);
    self.actionDrawerCard.transform = sideSheetLandscape
        ? CGAffineTransformMakeTranslation(CGRectGetWidth(self.actionDrawerCard.bounds) + 20.0, 0)
        : CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.actionDrawerCard.bounds) + 20.0);

    [self _refreshActionDock];
    [UIView animateWithDuration:0.22 animations:^{
        self.actionOverlay.alpha = 1.0;
        self.actionOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.24];
        self.actionDrawerCard.transform = CGAffineTransformIdentity;
    }];
}

- (void)_hideActionDrawer {
    if (!self.actionOverlay || self.actionOverlay.hidden) return;

    BOOL sideSheetLandscape = (((self.currentLayoutMode == VCPanelLayoutModeLandscape) || (CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds))) && CGRectGetWidth(self.view.bounds) >= 560.0);
    [UIView animateWithDuration:0.18 animations:^{
        self.actionOverlay.alpha = 0.0;
        self.actionOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
        self.actionDrawerCard.transform = sideSheetLandscape
            ? CGAffineTransformMakeTranslation(CGRectGetWidth(self.actionDrawerCard.bounds) + 20.0, 0)
            : CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.actionDrawerCard.bounds) + 20.0);
    } completion:^(BOOL finished) {
        self.actionOverlay.hidden = YES;
        self.actionDrawerCard.transform = CGAffineTransformIdentity;
        [self _refreshActionDock];
    }];
}

- (void)_performPrimaryInspectAction {
    if (!self.selectedDetailItem) return;
    if ([self.selectedDetailItem[@"kind"] isEqualToString:@"ui_view"]) {
        [self _showUIQuickEditor];
        return;
    }
    if ([self.selectedDetailItem[@"kind"] isEqualToString:@"string_result"] ||
        [self.selectedDetailItem[@"kind"] isEqualToString:@"instance_result"] ||
        [self.selectedDetailItem[@"kind"] isEqualToString:@"process_module"] ||
        [self.selectedDetailItem[@"kind"] isEqualToString:@"process_region"]) {
        [self _hideActionDrawer];
        [self _openMemoryForInspectAddress:self.selectedDetailItem[@"address"] ?: @""];
        return;
    }
    [self _hideActionDrawer];
    [self _queueInspectReferenceForItem:self.selectedDetailItem];
}

- (UIView *)_viewForUIInspectItem:(NSDictionary *)item {
    if (![item[@"kind"] isEqualToString:@"ui_view"]) return nil;
    VCViewNode *node = item[@"node"];
    return node.view ?: [[VCUIInspector shared] viewForAddress:node.address];
}

- (void)_performSecondaryInspectAction {
    NSDictionary *item = self.selectedDetailItem;
    if (!item) return;
    [self _hideActionDrawer];
    NSString *kind = item[@"kind"] ?: @"";
    if ([kind isEqualToString:@"ui_view"]) {
        UIView *view = [self _viewForUIInspectItem:item];
        if (!view) return;
        BOOL nextHidden = !view.hidden;
        [[VCUIInspector shared] modifyView:view property:@"hidden" value:@(nextHidden)];
        self.statusLabel.text = nextHidden ? VCTextLiteral(@"View hidden") : VCTextLiteral(@"View shown");
        [self _loadUIHierarchy:self.searchBar.text.length > 0 ? self.searchBar.text : nil];
        return;
    }
    if ([kind isEqualToString:@"string_result"] ||
        [kind isEqualToString:@"instance_result"] ||
        [kind isEqualToString:@"process_module"] ||
        [kind isEqualToString:@"process_region"]) {
        [self _openValueDraftForAddressItem:item];
        return;
    }
    if ([kind isEqualToString:@"method"]) {
        [self _addHookForMethodItem:item];
    } else {
        [self _openValueDraftForMemberItem:item];
    }
}

- (void)_performTertiaryInspectAction {
    NSDictionary *item = self.selectedDetailItem;
    if (!item) return;
    [self _hideActionDrawer];
    NSString *kind = item[@"kind"] ?: @"";
    if ([kind isEqualToString:@"ui_view"]) {
        UIView *view = [self _viewForUIInspectItem:item];
        if (!view) return;
        BOOL nextValue = !view.userInteractionEnabled;
        [[VCUIInspector shared] modifyView:view property:@"userInteractionEnabled" value:@(nextValue)];
        self.statusLabel.text = nextValue ? VCTextLiteral(@"Tap interaction enabled") : VCTextLiteral(@"Tap interaction disabled");
        [[VCUIInspector shared] highlightView:view];
        [self _loadUIHierarchy:self.searchBar.text.length > 0 ? self.searchBar.text : nil];
        return;
    }
    if ([kind isEqualToString:@"string_result"] ||
        [kind isEqualToString:@"instance_result"] ||
        [kind isEqualToString:@"process_module"] ||
        [kind isEqualToString:@"process_region"]) {
        NSString *copyText = item[@"address"] ?: @"";
        [UIPasteboard generalPasteboard].string = copyText;
        self.statusLabel.text = [NSString stringWithFormat:@"Copied %@", copyText];
        return;
    }
    if ([kind isEqualToString:@"method"]) {
        [self _addPatchDraftForMethodItem:item];
        return;
    }
    NSString *copyText = item[@"type"] ?: item[@"title"] ?: @"member";
    [UIPasteboard generalPasteboard].string = copyText;
    self.statusLabel.text = [NSString stringWithFormat:@"Copied %@", copyText];
}

- (void)_performQuaternaryInspectAction {
    NSDictionary *item = self.selectedDetailItem;
    if (!item) return;
    [self _hideActionDrawer];
    NSString *copyText = nil;
    if ([item[@"kind"] isEqualToString:@"ui_view"]) {
        VCViewNode *node = item[@"node"];
        copyText = [NSString stringWithFormat:@"<%@: 0x%lX> %@", item[@"title"] ?: @"UIView", (unsigned long)node.address, item[@"detail"] ?: @""];
    } else if ([item[@"kind"] isEqualToString:@"string_result"]) {
        copyText = item[@"title"] ?: @"";
    } else if ([item[@"kind"] isEqualToString:@"instance_result"]) {
        copyText = [NSString stringWithFormat:@"<%@: %@> %@", item[@"title"] ?: @"Instance", item[@"address"] ?: @"", item[@"detail"] ?: @""];
    } else if ([item[@"kind"] isEqualToString:@"process_module"] || [item[@"kind"] isEqualToString:@"process_region"]) {
        copyText = [NSString stringWithFormat:@"%@ • %@ • %@", item[@"title"] ?: @"Memory", item[@"address"] ?: @"", item[@"detail"] ?: @""];
    } else {
        copyText = item[@"title"] ?: item[@"selector"] ?: @"member";
    }
    [UIPasteboard generalPasteboard].string = copyText;
    self.statusLabel.text = [NSString stringWithFormat:@"Copied %@", copyText];
}

#pragma mark - VCTouchOverlayDelegate

- (void)touchOverlay:(VCTouchOverlay *)overlay didSelectView:(UIView *)view {
    [self _setPanelHiddenForPicking:NO];
    [self _updateHeaderActionButton];
    if (self.segCtrl.selectedSegmentIndex != VCInspectSubTabUI) {
        self.segCtrl.selectedSegmentIndex = VCInspectSubTabUI;
    }
    self.selectedUIView = view;
    [[VCUIInspector shared] rememberSelectedView:view];
    [[VCUIInspector shared] highlightView:view];
    [self _loadUIHierarchy:self.searchBar.text.length > 0 ? self.searchBar.text : nil];
    uintptr_t address = (uintptr_t)(__bridge void *)view;
    for (NSDictionary *entry in self.dataSource) {
        VCViewNode *node = entry[@"node"];
        if (node.address == address) {
            self.selectedDetailItem = entry;
            NSUInteger row = [self.dataSource indexOfObject:entry];
            if (row != NSNotFound && row < (NSUInteger)[self.tableView numberOfRowsInSection:0]) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
                [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
            }
            break;
        }
    }
    self.statusLabel.text = [NSString stringWithFormat:@"%@ %@", VCTextLiteral(@"Picked"), NSStringFromClass([view class])];
    [self _refreshActionDock];
}

- (void)touchOverlayDidCancel:(VCTouchOverlay *)overlay {
    [self _setPanelHiddenForPicking:NO];
    [self _updateHeaderActionButton];
    if (self.selectedUIView) {
        [[VCUIInspector shared] highlightView:self.selectedUIView];
    } else {
        [[VCUIInspector shared] clearHighlights];
    }
    self.statusLabel.text = VCTextLiteral(@"Pick cancelled");
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([VCTouchOverlay shared].isPicking && [VCTouchOverlay shared].delegate == self) {
        [[VCTouchOverlay shared] stopPicking];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // Infinite scroll for Runtime tab
    if (_segCtrl.selectedSegmentIndex != VCInspectSubTabMembers) return;
    if (_selectedClass) return;
    if (!_runtimeHasMore) return;

    CGFloat offsetY = scrollView.contentOffset.y;
    CGFloat contentH = scrollView.contentSize.height;
    CGFloat frameH = scrollView.frame.size.height;
    self.offsetMemory[@(VCInspectSubTabMembers)] = @(scrollView.contentOffset.y);
    if (offsetY > contentH - frameH - 200) {
        [self _loadRuntime:_searchBar.text.length > 0 ? _searchBar.text : nil reset:NO];
    }
}

@end
