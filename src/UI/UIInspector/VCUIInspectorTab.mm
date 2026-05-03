/**
 * VCUIInspectorTab -- UI Inspector Tab
 * View hierarchy tree + touch-to-select + property panel
 */

#import "VCUIInspectorTab.h"
#import "../../../VansonCLI.h"
#import "../../UIInspector/VCUIInspector.h"
#import "../../UIInspector/VCTouchOverlay.h"
#import "../../AI/Chat/VCChatSession.h"
#import "../Panel/VCPanel.h"
#import "../Settings/VCSettingsTab.h"

static NSString *const kCellID = @"UICell";
static NSString *const kVCUIInspectorEmptyDetailText = @"Select a view to inspect";

static BOOL VCUIInspectorPreviewLooksLikeOnlySize(NSString *preview) {
    if (![preview isKindOfClass:[NSString class]] || preview.length == 0) return YES;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789xX. "];
    return [[preview stringByTrimmingCharactersInSet:allowed] length] == 0;
}

static NSString *VCUIInspectorInlinePreviewForNode(VCViewNode *node) {
    if (![node.briefDescription isKindOfClass:[NSString class]] || node.briefDescription.length == 0) {
        return nil;
    }

    NSString *preview = node.briefDescription;
    NSString *className = node.className ?: @"";
    if (className.length > 0 && [preview hasPrefix:className]) {
        preview = [preview substringFromIndex:className.length];
    }
    preview = [preview stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (preview.length == 0) return nil;
    if (VCUIInspectorPreviewLooksLikeOnlySize(preview)) return nil;
    return preview;
}

@interface VCUIInspectorTreeCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *disclosureBadge;
@property (nonatomic, strong) UIImageView *disclosureIconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *childrenBadge;
- (void)configureWithNode:(VCViewNode *)node
                    depth:(NSInteger)depth
              hasChildren:(BOOL)hasChildren
                collapsed:(BOOL)isCollapsed
                 selected:(BOOL)isSelected;
@end

@implementation VCUIInspectorTreeCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        _cardView.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.92];
        _cardView.layer.cornerRadius = 14.0;
        _cardView.layer.borderWidth = 1.0;
        _cardView.layer.borderColor = kVCBorder.CGColor;
        [self.contentView addSubview:_cardView];

        _disclosureBadge = [[UIView alloc] initWithFrame:CGRectZero];
        _disclosureBadge.layer.cornerRadius = 11.0;
        _disclosureBadge.layer.borderWidth = 1.0;
        [_cardView addSubview:_disclosureBadge];

        _disclosureIconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _disclosureIconView.contentMode = UIViewContentModeScaleAspectFit;
        [_disclosureBadge addSubview:_disclosureIconView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.textColor = kVCTextPrimary;
        _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_cardView addSubview:_titleLabel];

        _detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _detailLabel.textColor = kVCTextSecondary;
        _detailLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_cardView addSubview:_detailLabel];

        _childrenBadge = [[UILabel alloc] initWithFrame:CGRectZero];
        _childrenBadge.textAlignment = NSTextAlignmentCenter;
        _childrenBadge.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        _childrenBadge.layer.cornerRadius = 10.0;
        _childrenBadge.layer.borderWidth = 1.0;
        _childrenBadge.clipsToBounds = YES;
        [_cardView addSubview:_childrenBadge];
    }
    return self;
}

- (CGFloat)_badgeWidthForText:(NSString *)text {
    NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]};
    CGFloat width = ceil([text sizeWithAttributes:attrs].width) + 18.0;
    return MIN(MAX(width, 52.0), 120.0);
}

- (UIColor *)_fillColorForDepth:(NSInteger)depth expanded:(BOOL)isExpanded selected:(BOOL)isSelected {
    if (isSelected) {
        return [kVCAccent colorWithAlphaComponent:0.14];
    }
    if (isExpanded) {
        return [kVCAccent colorWithAlphaComponent:(depth % 2 == 0 ? 0.10 : 0.13)];
    }
    return (depth % 2 == 0)
        ? [kVCBgSurface colorWithAlphaComponent:0.95]
        : [kVCBgInput colorWithAlphaComponent:0.88];
}

- (CGColorRef)_borderColorForExpanded:(BOOL)isExpanded selected:(BOOL)isSelected {
    if (isSelected) {
        return [kVCAccent colorWithAlphaComponent:0.40].CGColor;
    }
    if (isExpanded) {
        return [kVCAccent colorWithAlphaComponent:0.22].CGColor;
    }
    return kVCBorder.CGColor;
}

- (void)configureWithNode:(VCViewNode *)node
                    depth:(NSInteger)depth
              hasChildren:(BOOL)hasChildren
                collapsed:(BOOL)isCollapsed
                 selected:(BOOL)isSelected {
    BOOL isExpanded = hasChildren && !isCollapsed;
    NSString *className = node.className ?: @"UIView";
    if (className.length > 32) {
        className = [NSString stringWithFormat:@"...%@", [className substringFromIndex:className.length - 29]];
    }

    self.cardView.backgroundColor = [self _fillColorForDepth:depth expanded:isExpanded selected:isSelected];
    self.cardView.layer.borderColor = [self _borderColorForExpanded:isExpanded selected:isSelected];

    self.titleLabel.text = className;
    self.titleLabel.textColor = isSelected ? kVCAccent : kVCTextPrimary;
    NSString *preview = VCUIInspectorInlinePreviewForNode(node);
    NSString *baseDetail = [NSString stringWithFormat:@"%.0fx%.0f • 0x%lX",
                            node.frame.size.width,
                            node.frame.size.height,
                            (unsigned long)node.address];
    self.detailLabel.text = preview.length > 0
        ? [NSString stringWithFormat:@"%@ • %@", baseDetail, preview]
        : baseDetail;

    if (hasChildren) {
        self.disclosureBadge.backgroundColor = isSelected
            ? [kVCAccent colorWithAlphaComponent:0.18]
            : (isExpanded ? [kVCAccent colorWithAlphaComponent:0.14] : [kVCBgSecondary colorWithAlphaComponent:0.94]);
        self.disclosureBadge.layer.borderColor = (isSelected
            ? [kVCAccent colorWithAlphaComponent:0.34]
            : (isExpanded ? [kVCAccent colorWithAlphaComponent:0.24] : kVCBorder)).CGColor;
        self.disclosureIconView.image = [UIImage systemImageNamed:(isCollapsed ? @"chevron.right" : @"chevron.down")];
        self.disclosureIconView.tintColor = isSelected ? kVCAccent : kVCTextPrimary;

        self.childrenBadge.hidden = NO;
        self.childrenBadge.text = [NSString stringWithFormat:@"%lu children", (unsigned long)node.children.count];
        self.childrenBadge.textColor = isSelected ? kVCAccent : kVCTextSecondary;
        self.childrenBadge.backgroundColor = isExpanded ? [kVCAccent colorWithAlphaComponent:0.10] : [kVCBgInput colorWithAlphaComponent:0.72];
        self.childrenBadge.layer.borderColor = [self _borderColorForExpanded:isExpanded selected:isSelected];
    } else {
        self.disclosureBadge.backgroundColor = [kVCBgInput colorWithAlphaComponent:0.78];
        self.disclosureBadge.layer.borderColor = kVCBorder.CGColor;
        self.disclosureIconView.image = [UIImage systemImageNamed:@"circle.fill"];
        self.disclosureIconView.tintColor = kVCTextMuted;

        self.childrenBadge.hidden = YES;
        self.childrenBadge.text = nil;
    }

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.cardView.frame = CGRectInset(self.contentView.bounds, 10.0, 4.0);

    CGFloat inset = 12.0;
    CGFloat badgeSize = 22.0;
    self.disclosureBadge.frame = CGRectMake(inset, 14.0, badgeSize, badgeSize);
    self.disclosureIconView.frame = CGRectMake(5.0, 5.0, 12.0, 12.0);

    CGFloat badgeMinX = CGRectGetWidth(self.cardView.bounds) - inset;
    if (!self.childrenBadge.hidden) {
        CGFloat childrenWidth = [self _badgeWidthForText:self.childrenBadge.text];
        self.childrenBadge.frame = CGRectMake(CGRectGetWidth(self.cardView.bounds) - inset - childrenWidth, 15.0, childrenWidth, 20.0);
        badgeMinX = CGRectGetMinX(self.childrenBadge.frame);
    }

    CGFloat textX = CGRectGetMaxX(self.disclosureBadge.frame) + 10.0;
    CGFloat textWidth = MAX(70.0, badgeMinX - textX - 8.0);
    self.titleLabel.frame = CGRectMake(textX, 11.0, textWidth, 22.0);
    self.detailLabel.frame = CGRectMake(textX, 35.0, CGRectGetWidth(self.cardView.bounds) - textX - inset, 16.0);
}

@end

@interface VCUIInspectorTab () <UITableViewDataSource, UITableViewDelegate, VCTouchOverlayDelegate, VCPanelLayoutUpdatable>
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UIButton *pickButton;
@property (nonatomic, strong) UIButton *highlightToggleButton;
@property (nonatomic, strong) UIButton *refreshButton;
@property (nonatomic, strong) UITextField *filterField;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *detailCard;
@property (nonatomic, strong) UITextView *detailView;
@property (nonatomic, strong) UIView *detailActionRow;
@property (nonatomic, strong) UILabel *detailActionHintLabel;
@property (nonatomic, strong) UIButton *quickEditOpenButton;
@property (nonatomic, strong) UIView *quickEditorDock;
@property (nonatomic, strong) UIView *quickEditorDockHandle;
@property (nonatomic, strong) UIButton *quickEditorDockButton;
@property (nonatomic, strong) NSLayoutConstraint *quickEditorDockWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *quickEditorDockHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *quickEditorDockLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *quickEditorDockTopConstraint;
@property (nonatomic, strong) UIView *quickEditorInlineContainer;
@property (nonatomic, strong) UIView *quickEditorOverlay;
@property (nonatomic, strong) UIControl *quickEditorBackdrop;
@property (nonatomic, strong) UIView *quickEditorCard;
@property (nonatomic, strong) NSLayoutConstraint *quickEditorCardLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *quickEditorCardTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *quickEditorCardWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *quickEditorCardHeightConstraint;
@property (nonatomic, strong) UIView *quickEditorHandle;
@property (nonatomic, strong) UILabel *quickEditorTitleLabel;
@property (nonatomic, strong) UILabel *quickEditorSubtitleLabel;
@property (nonatomic, strong) UIButton *quickEditorCloseButton;
@property (nonatomic, strong) UITextField *quickTextField;
@property (nonatomic, strong) UITextField *quickColorField;
@property (nonatomic, strong) UITextField *quickAlphaField;
@property (nonatomic, strong) UISegmentedControl *quickColorTargetControl;
@property (nonatomic, strong) UIButton *quickApplyTextButton;
@property (nonatomic, strong) UIButton *quickInsertLabelButton;
@property (nonatomic, strong) UIButton *quickApplyStyleButton;
@property (nonatomic, strong) UIButton *quickToggleHiddenButton;
@property (nonatomic, strong) UIButton *quickToggleInteractionButton;
@property (nonatomic, strong) UILabel *quickStatusLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *flatTree; // {node, depth, collapsed}
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *allFlatTree;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *collapsedAddresses; // collapsed node addresses
@property (nonatomic, weak) UIView *selectedView;
@property (nonatomic, assign) BOOL panelHiddenForPicking;
@property (nonatomic, strong) NSLayoutConstraint *detailHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *detailLandscapeBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerPortraitLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerPortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerLandscapeLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerLandscapeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tableTopToHeaderConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tableTopToViewConstraint;
@property (nonatomic, strong) NSLayoutConstraint *portraitTableBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *portraitDetailLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *portraitDetailTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *portraitDetailBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *detailActionRowBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *detailActionRowBottomToInlineConstraint;
@property (nonatomic, strong) NSLayoutConstraint *quickEditorInlineBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *quickEditorInlineHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *pickRefreshSpacingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *pickRefreshEqualWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *highlightRefreshSpacingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *highlightRefreshEqualWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *landscapeTableTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *landscapeTableBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *landscapeDetailLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *landscapeDetailTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *landscapeDetailTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *landscapeDetailBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *landscapeDetailWidthConstraint;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@property (nonatomic, assign) BOOL quickEditorInlineVisible;
@end

@implementation VCUIInspectorTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;
    _flatTree = [NSMutableArray new];
    _allFlatTree = [NSMutableArray new];
    _collapsedAddresses = [NSMutableSet new];
    _currentLayoutMode = VCPanelLayoutModePortrait;

    [self _setupHeaderCard];
    [self _setupToolbar];
    [self _setupTableView];
    [self _setupDetailLabel];
    [self _refreshQuickEditState];
    VCInstallKeyboardDismissAccessory(self.view);
    [self _installChatQueueGestures];

    [VCTouchOverlay shared].delegate = self;
    [self _refreshTree];
}

- (void)_setupHeaderCard {
    _headerCard = [[UIView alloc] init];
    _headerCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.94];
    _headerCard.layer.cornerRadius = 16.0;
    _headerCard.layer.borderWidth = 1.0;
    _headerCard.layer.borderColor = kVCBorder.CGColor;
    _headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerCard];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = VCTextLiteral(@"UI SURFACE MAP");
    titleLabel.textColor = kVCTextSecondary;
    titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:titleLabel];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.textColor = kVCTextMuted;
    _statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _statusLabel.textAlignment = NSTextAlignmentRight;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _statusLabel.numberOfLines = 1;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_headerCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [titleLabel.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:10],
        [titleLabel.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-8],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [_statusLabel.widthAnchor constraintLessThanOrEqualToAnchor:_headerCard.widthAnchor multiplier:0.58],
    ]];
    self.headerHeightConstraint = [_headerCard.heightAnchor constraintEqualToConstant:122.0];
    self.headerHeightConstraint.active = YES;
    self.headerPortraitLeadingConstraint = [_headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10];
    self.headerPortraitLeadingConstraint.active = YES;
    self.headerPortraitTrailingConstraint = [_headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10];
    self.headerPortraitTrailingConstraint.active = YES;
}

- (void)_setupToolbar {
    _pickButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_pickButton setTitle:VCTextLiteral(@"Pick View") forState:UIControlStateNormal];
    VCApplyCompactAccentButtonStyle(_pickButton);
    _pickButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _pickButton.contentEdgeInsets = UIEdgeInsetsMake(7, 10, 7, 10);
    VCApplyCompactIconTitleButtonLayout(_pickButton, @"scope", 11.0);
    _pickButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _pickButton.titleLabel.minimumScaleFactor = 0.82;
    [_pickButton addTarget:self action:@selector(_togglePick) forControlEvents:UIControlEventTouchUpInside];
    _pickButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_pickButton];

    _highlightToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_highlightToggleButton setTitle:VCTextLiteral(@"Border") forState:UIControlStateNormal];
    _highlightToggleButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _highlightToggleButton.contentEdgeInsets = UIEdgeInsetsMake(7, 10, 7, 10);
    _highlightToggleButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _highlightToggleButton.titleLabel.minimumScaleFactor = 0.82;
    [_highlightToggleButton addTarget:self action:@selector(_toggleSelectionHighlight) forControlEvents:UIControlEventTouchUpInside];
    _highlightToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_highlightToggleButton];

    _refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_refreshButton setTitle:VCTextLiteral(@"Refresh") forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(_refreshButton);
    _refreshButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _refreshButton.contentEdgeInsets = UIEdgeInsetsMake(7, 10, 7, 10);
    VCApplyCompactIconTitleButtonLayout(_refreshButton, @"arrow.clockwise", 11.0);
    _refreshButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _refreshButton.titleLabel.minimumScaleFactor = 0.82;
    [_refreshButton addTarget:self action:@selector(_refreshTree) forControlEvents:UIControlEventTouchUpInside];
    _refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_refreshButton];

    _filterField = [[UITextField alloc] init];
    VCApplyReadablePlaceholder(_filterField, VCTextLiteral(@"Filter by class, address, or text"));
    _filterField.textColor = kVCTextPrimary;
    _filterField.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _filterField.backgroundColor = kVCBgInput;
    _filterField.layer.cornerRadius = 12.0;
    _filterField.layer.borderWidth = 1.0;
    _filterField.layer.borderColor = kVCBorder.CGColor;
    _filterField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _filterField.autocorrectionType = UITextAutocorrectionTypeNo;
    _filterField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _filterField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
    _filterField.leftViewMode = UITextFieldViewModeAlways;
    [_filterField addTarget:self action:@selector(_filterChanged:) forControlEvents:UIControlEventEditingChanged];
    _filterField.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_filterField];

    [NSLayoutConstraint activateConstraints:@[
        [_pickButton.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:30],
        [_pickButton.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_pickButton.heightAnchor constraintEqualToConstant:34],
        [_highlightToggleButton.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:30],
        [_highlightToggleButton.heightAnchor constraintEqualToConstant:34],
        [_refreshButton.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:30],
        [_refreshButton.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_refreshButton.heightAnchor constraintEqualToConstant:34],
        [_filterField.topAnchor constraintEqualToAnchor:_pickButton.bottomAnchor constant:8],
        [_filterField.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_filterField.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_filterField.heightAnchor constraintEqualToConstant:36],
        [_filterField.bottomAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:-10],
    ]];
    self.pickRefreshSpacingConstraint = [_pickButton.trailingAnchor constraintEqualToAnchor:_highlightToggleButton.leadingAnchor constant:-8];
    self.pickRefreshSpacingConstraint.active = YES;
    self.highlightRefreshSpacingConstraint = [_highlightToggleButton.trailingAnchor constraintEqualToAnchor:_refreshButton.leadingAnchor constant:-8];
    self.highlightRefreshSpacingConstraint.active = YES;
    self.pickRefreshEqualWidthConstraint = [_pickButton.widthAnchor constraintEqualToAnchor:_highlightToggleButton.widthAnchor];
    self.pickRefreshEqualWidthConstraint.active = YES;
    self.highlightRefreshEqualWidthConstraint = [_highlightToggleButton.widthAnchor constraintEqualToAnchor:_refreshButton.widthAnchor];
    self.highlightRefreshEqualWidthConstraint.active = YES;
    [self _updateSelectionHighlightButtonState];
}

- (void)_setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = 64.0;
    _tableView.estimatedRowHeight = 64.0;
    _tableView.contentInset = UIEdgeInsetsMake(6, 0, 8, 0);
    [_tableView registerClass:[VCUIInspectorTreeCell class] forCellReuseIdentifier:kCellID];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    self.tableTopToHeaderConstraint = [_tableView.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:8];
    self.tableTopToHeaderConstraint.active = YES;
}

- (void)_setupDetailLabel {
    _detailCard = [[UIView alloc] init];
    _detailCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.94];
    _detailCard.layer.cornerRadius = 16.0;
    _detailCard.layer.borderWidth = 1.0;
    _detailCard.layer.borderColor = kVCBorder.CGColor;
    _detailCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_detailCard];

    _detailView = [[UITextView alloc] init];
    _detailView.font = kVCFontMonoSm;
    _detailView.textColor = kVCTextPrimary;
    _detailView.backgroundColor = [UIColor clearColor];
    _detailView.editable = NO;
    _detailView.selectable = YES;
    _detailView.scrollEnabled = YES;
    _detailView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    _detailView.text = kVCUIInspectorEmptyDetailText;
    _detailView.translatesAutoresizingMaskIntoConstraints = NO;
    [_detailCard addSubview:_detailView];

    _detailActionRow = [[UIView alloc] init];
    _detailActionRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_detailCard addSubview:_detailActionRow];

    _quickEditorInlineContainer = [[UIView alloc] init];
    _quickEditorInlineContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _quickEditorInlineContainer.hidden = YES;
    _quickEditorInlineContainer.alpha = 0.0;
    [_detailCard addSubview:_quickEditorInlineContainer];

    _detailActionHintLabel = [[UILabel alloc] init];
    _detailActionHintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _detailActionHintLabel.textColor = kVCTextSecondary;
    _detailActionHintLabel.numberOfLines = 2;
    _detailActionHintLabel.text = VCTextLiteral(@"Pick a live view to inspect it. Long press a row or the detail text area to send it to AI Chat.");
    _detailActionHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_detailActionRow addSubview:_detailActionHintLabel];

    _quickEditOpenButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_quickEditOpenButton setTitle:VCTextLiteral(@"Quick Edit") forState:UIControlStateNormal];
    [_quickEditOpenButton setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    VCApplyCompactAccentButtonStyle(_quickEditOpenButton);
    _quickEditOpenButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _quickEditOpenButton.contentEdgeInsets = UIEdgeInsetsMake(7, 10, 7, 10);
    _quickEditOpenButton.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, -6);
    [_quickEditOpenButton addTarget:self action:@selector(_toggleQuickEditor) forControlEvents:UIControlEventTouchUpInside];
    _quickEditOpenButton.translatesAutoresizingMaskIntoConstraints = NO;
    _quickEditOpenButton.hidden = YES;
    _quickEditOpenButton.alpha = 0.0;
    [_detailActionRow addSubview:_quickEditOpenButton];

    UITextField *(^makeField)(NSString *) = ^UITextField *(NSString *placeholder) {
        UITextField *field = [[UITextField alloc] init];
        VCApplyReadablePlaceholder(field, placeholder);
        field.textColor = kVCTextPrimary;
        field.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        field.backgroundColor = kVCBgInput;
        field.layer.cornerRadius = 10.0;
        field.layer.borderWidth = 1.0;
        field.layer.borderColor = kVCBorder.CGColor;
        field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 1)];
        field.leftViewMode = UITextFieldViewModeAlways;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.translatesAutoresizingMaskIntoConstraints = YES;
        return field;
    };

    UIButton *(^makeActionButton)(NSString *, UIColor *, SEL) = ^UIButton *(NSString *title, UIColor *bg, SEL action) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:title forState:UIControlStateNormal];
        [button setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        button.backgroundColor = bg;
        button.layer.cornerRadius = 10.0;
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = kVCBorder.CGColor;
        button.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        button.translatesAutoresizingMaskIntoConstraints = YES;
        return button;
    };

    _quickTextField = makeField(VCTextLiteral(@"Text / Title"));
    _quickTextField.returnKeyType = UIReturnKeyDone;

    _quickApplyTextButton = makeActionButton(VCTextLiteral(@"Apply Text"), kVCAccentDim, @selector(_applyQuickText));

    _quickInsertLabelButton = makeActionButton(VCTextLiteral(@"Add Label"), kVCGreenDim, @selector(_insertQuickLabel));

    _quickColorTargetControl = [[UISegmentedControl alloc] initWithItems:@[VCTextLiteral(@"BG"), VCTextLiteral(@"Text")]];
    _quickColorTargetControl.selectedSegmentIndex = 0;
    _quickColorTargetControl.selectedSegmentTintColor = kVCAccent;
    [_quickColorTargetControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [_quickColorTargetControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    _quickColorTargetControl.translatesAutoresizingMaskIntoConstraints = YES;

    _quickColorField = makeField(VCTextLiteral(@"Hex color"));

    _quickAlphaField = makeField(VCTextLiteral(@"Alpha 0-1"));
    _quickAlphaField.keyboardType = UIKeyboardTypeDecimalPad;

    _quickApplyStyleButton = makeActionButton(VCTextLiteral(@"Apply Style"), [kVCBgSecondary colorWithAlphaComponent:0.94], @selector(_applyQuickStyle));

    _quickToggleHiddenButton = makeActionButton(VCTextLiteral(@"Hide"), [kVCRed colorWithAlphaComponent:0.14], @selector(_toggleQuickHidden));

    _quickToggleInteractionButton = makeActionButton(VCTextLiteral(@"Disable Tap"), [kVCBgSecondary colorWithAlphaComponent:0.94], @selector(_toggleQuickInteraction));

    _quickStatusLabel = [[UILabel alloc] init];
    _quickStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _quickStatusLabel.textColor = kVCTextSecondary;
    _quickStatusLabel.numberOfLines = 2;
    _quickStatusLabel.text = VCTextLiteral(@"Pick a live view to edit it directly without Chat.");
    _quickStatusLabel.translatesAutoresizingMaskIntoConstraints = YES;

    [NSLayoutConstraint activateConstraints:@[
        [_detailView.topAnchor constraintEqualToAnchor:_detailCard.topAnchor constant:2],
        [_detailView.leadingAnchor constraintEqualToAnchor:_detailCard.leadingAnchor constant:2],
        [_detailView.trailingAnchor constraintEqualToAnchor:_detailCard.trailingAnchor constant:-2],
        [_detailView.heightAnchor constraintGreaterThanOrEqualToConstant:132],

        [_detailActionRow.topAnchor constraintEqualToAnchor:_detailView.bottomAnchor constant:8],
        [_detailActionRow.leadingAnchor constraintEqualToAnchor:_detailCard.leadingAnchor constant:14],
        [_detailActionRow.trailingAnchor constraintEqualToAnchor:_detailCard.trailingAnchor constant:-14],
        [_detailActionRow.heightAnchor constraintGreaterThanOrEqualToConstant:40],

        [_quickEditOpenButton.trailingAnchor constraintEqualToAnchor:_detailActionRow.trailingAnchor],
        [_quickEditOpenButton.centerYAnchor constraintEqualToAnchor:_detailActionRow.centerYAnchor],
        [_quickEditOpenButton.widthAnchor constraintEqualToConstant:112],
        [_quickEditOpenButton.heightAnchor constraintEqualToConstant:32],

        [_detailActionHintLabel.leadingAnchor constraintEqualToAnchor:_detailActionRow.leadingAnchor],
        [_detailActionHintLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_quickEditOpenButton.leadingAnchor constant:-10],
        [_detailActionHintLabel.centerYAnchor constraintEqualToAnchor:_detailActionRow.centerYAnchor],

        [_quickEditorInlineContainer.leadingAnchor constraintEqualToAnchor:_detailCard.leadingAnchor constant:2],
        [_quickEditorInlineContainer.trailingAnchor constraintEqualToAnchor:_detailCard.trailingAnchor constant:-2],
    ]];

    self.detailActionRowBottomConstraint = [_detailActionRow.bottomAnchor constraintEqualToAnchor:_detailCard.bottomAnchor constant:-12];
    self.detailActionRowBottomToInlineConstraint = [_detailActionRow.bottomAnchor constraintEqualToAnchor:_quickEditorInlineContainer.topAnchor constant:-10];
    self.quickEditorInlineBottomConstraint = [_quickEditorInlineContainer.bottomAnchor constraintEqualToAnchor:_detailCard.bottomAnchor constant:-2];
    self.quickEditorInlineHeightConstraint = [_quickEditorInlineContainer.heightAnchor constraintEqualToConstant:0.0];

    _detailHeightConstraint = [_detailView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.28];
    _detailLandscapeBottomConstraint = [_detailView.bottomAnchor constraintEqualToAnchor:_detailActionRow.topAnchor constant:-8];
    self.portraitTableBottomConstraint = [_tableView.bottomAnchor constraintEqualToAnchor:_detailCard.topAnchor constant:-8];
    self.portraitDetailLeadingConstraint = [_detailCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10];
    self.portraitDetailTrailingConstraint = [_detailCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10];
    self.portraitDetailBottomConstraint = [_detailCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10];
    self.landscapeTableTrailingConstraint = [_tableView.trailingAnchor constraintEqualToAnchor:_detailCard.leadingAnchor constant:-8];
    self.landscapeTableBottomConstraint = [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10];
    self.landscapeDetailLeadingConstraint = [_detailCard.leadingAnchor constraintEqualToAnchor:_tableView.trailingAnchor constant:8];
    self.landscapeDetailTrailingConstraint = [_detailCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10];
    self.landscapeDetailTopConstraint = [_detailCard.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:8];
    self.landscapeDetailBottomConstraint = [_detailCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10];
    self.landscapeDetailWidthConstraint = [_detailCard.widthAnchor constraintEqualToConstant:340.0];
    self.headerLandscapeLeadingConstraint = [_headerCard.leadingAnchor constraintEqualToAnchor:_detailCard.leadingAnchor];
    self.headerLandscapeTrailingConstraint = [_headerCard.trailingAnchor constraintEqualToAnchor:_detailCard.trailingAnchor];
    self.tableTopToViewConstraint = [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10];
    [NSLayoutConstraint activateConstraints:@[
        self.portraitTableBottomConstraint,
        self.portraitDetailLeadingConstraint,
        self.portraitDetailTrailingConstraint,
        self.portraitDetailBottomConstraint,
        self.detailActionRowBottomConstraint,
        self.quickEditorInlineBottomConstraint,
        self.quickEditorInlineHeightConstraint,
        _detailHeightConstraint,
    ]];
    [self _setupQuickEditorOverlay];
    [self _setupQuickEditorDock];
    [self _applyCurrentLayoutMode];
}

- (void)_installChatQueueGestures {
    UILongPressGestureRecognizer *treeLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTreeLongPress:)];
    treeLongPress.minimumPressDuration = 0.38;
    [self.tableView addGestureRecognizer:treeLongPress];

    UILongPressGestureRecognizer *detailLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleDetailLongPress:)];
    detailLongPress.minimumPressDuration = 0.38;
    [self.detailView addGestureRecognizer:detailLongPress];
}

- (void)_setupQuickEditorOverlay {
    if (self.quickEditorOverlay) return;

    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.hidden = YES;
    overlay.alpha = 0.0;
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    [self.view addSubview:overlay];
    self.quickEditorOverlay = overlay;

    UIControl *backdrop = [[UIControl alloc] init];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addTarget:self action:@selector(_hideQuickEditor) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:backdrop];
    self.quickEditorBackdrop = backdrop;

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
    self.quickEditorCard = card;

    self.quickEditorCardLeadingConstraint = [self.quickEditorCard.leadingAnchor constraintEqualToAnchor:self.quickEditorOverlay.leadingAnchor constant:12.0];
    self.quickEditorCardTopConstraint = [self.quickEditorCard.topAnchor constraintEqualToAnchor:self.quickEditorOverlay.topAnchor constant:12.0];
    self.quickEditorCardWidthConstraint = [self.quickEditorCard.widthAnchor constraintEqualToConstant:320.0];
    self.quickEditorCardHeightConstraint = [self.quickEditorCard.heightAnchor constraintEqualToConstant:320.0];

    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [backdrop.topAnchor constraintEqualToAnchor:overlay.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],

        self.quickEditorCardLeadingConstraint,
        self.quickEditorCardTopConstraint,
        self.quickEditorCardWidthConstraint,
        self.quickEditorCardHeightConstraint,
    ]];

    self.quickEditorHandle = [[UIView alloc] init];
    self.quickEditorHandle.backgroundColor = kVCTextMuted;
    self.quickEditorHandle.layer.cornerRadius = 2.0;
    [card addSubview:self.quickEditorHandle];

    self.quickEditorTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.quickEditorTitleLabel.text = VCTextLiteral(@"Quick Edit");
    self.quickEditorTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.quickEditorTitleLabel.textColor = kVCTextPrimary;
    [card addSubview:self.quickEditorTitleLabel];

    self.quickEditorSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.quickEditorSubtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.quickEditorSubtitleLabel.textColor = kVCTextSecondary;
    self.quickEditorSubtitleLabel.numberOfLines = 2;
    [card addSubview:self.quickEditorSubtitleLabel];

    self.quickEditorCloseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.quickEditorCloseButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(self.quickEditorCloseButton);
    [self.quickEditorCloseButton addTarget:self action:@selector(_hideQuickEditor) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.quickEditorCloseButton];

    [card addSubview:self.quickTextField];
    [card addSubview:self.quickApplyTextButton];
    [card addSubview:self.quickInsertLabelButton];
    [card addSubview:self.quickColorTargetControl];
    [card addSubview:self.quickColorField];
    [card addSubview:self.quickAlphaField];
    [card addSubview:self.quickApplyStyleButton];
    [card addSubview:self.quickToggleHiddenButton];
    [card addSubview:self.quickToggleInteractionButton];
    [card addSubview:self.quickStatusLabel];

    VCInstallKeyboardDismissAccessory(self.quickEditorOverlay);
    [self _layoutQuickEditorOverlay];
}

- (void)_setupQuickEditorDock {
    if (self.quickEditorDock) return;

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
    self.quickEditorDock = dock;

    UIView *handle = [[UIView alloc] init];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.backgroundColor = [UIColor clearColor];
    handle.layer.cornerRadius = 2.0;
    [dock addSubview:handle];
    self.quickEditorDockHandle = handle;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:VCTextLiteral(@"Modify") forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    VCApplyCompactAccentButtonStyle(button);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 14, 10, 14);
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 7, 0, -7);
    [button addTarget:self action:@selector(_toggleQuickEditor) forControlEvents:UIControlEventTouchUpInside];
    [dock addSubview:button];
    self.quickEditorDockButton = button;

    self.quickEditorDockWidthConstraint = [self.quickEditorDock.widthAnchor constraintEqualToConstant:160.0];
    self.quickEditorDockHeightConstraint = [self.quickEditorDock.heightAnchor constraintEqualToConstant:56.0];
    self.quickEditorDockLeadingConstraint = [self.quickEditorDock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:0.0];
    self.quickEditorDockTopConstraint = [self.quickEditorDock.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:0.0];

    [NSLayoutConstraint activateConstraints:@[
        self.quickEditorDockWidthConstraint,
        self.quickEditorDockHeightConstraint,
        self.quickEditorDockLeadingConstraint,
        self.quickEditorDockTopConstraint,

        [self.quickEditorDockHandle.topAnchor constraintEqualToAnchor:self.quickEditorDock.topAnchor],
        [self.quickEditorDockHandle.centerXAnchor constraintEqualToAnchor:self.quickEditorDock.centerXAnchor],
        [self.quickEditorDockHandle.widthAnchor constraintEqualToConstant:36.0],
        [self.quickEditorDockHandle.heightAnchor constraintEqualToConstant:0.0],

        [self.quickEditorDockButton.topAnchor constraintEqualToAnchor:self.quickEditorDock.topAnchor],
        [self.quickEditorDockButton.leadingAnchor constraintEqualToAnchor:self.quickEditorDock.leadingAnchor],
        [self.quickEditorDockButton.trailingAnchor constraintEqualToAnchor:self.quickEditorDock.trailingAnchor],
        [self.quickEditorDockButton.bottomAnchor constraintEqualToAnchor:self.quickEditorDock.bottomAnchor],
    ]];

    [self _layoutQuickEditorDock];
}

- (void)_layoutQuickEditorDock {
    if (!self.quickEditorDock) return;

    UIEdgeInsets safeInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeInsets = self.view.safeAreaInsets;
    }

    CGFloat dockWidth = MIN(MAX(CGRectGetWidth(self.view.bounds) * 0.36, 136.0), 188.0);
    CGFloat dockHeight = 48.0;
    CGFloat dockX = floor((CGRectGetWidth(self.view.bounds) - dockWidth) * 0.5);
    CGFloat dockY = CGRectGetHeight(self.view.bounds) - safeInsets.bottom - dockHeight - 14.0;
    self.quickEditorDockWidthConstraint.constant = dockWidth;
    self.quickEditorDockHeightConstraint.constant = dockHeight;
    self.quickEditorDockLeadingConstraint.constant = dockX;
    self.quickEditorDockTopConstraint.constant = dockY;
    [self.view layoutIfNeeded];
}

- (BOOL)_shouldUseInlineQuickEditor {
    return NO;
}

- (void)_applyQuickEditorCardChromeInline:(BOOL)inlineMode {
    if (!self.quickEditorCard) return;
    if (inlineMode) {
        self.quickEditorCard.backgroundColor = [UIColor clearColor];
        self.quickEditorCard.layer.cornerRadius = 0.0;
        self.quickEditorCard.layer.borderWidth = 0.0;
        self.quickEditorCard.layer.borderColor = UIColor.clearColor.CGColor;
        self.quickEditorCard.layer.shadowOpacity = 0.0;
        self.quickEditorCard.layer.shadowRadius = 0.0;
        self.quickEditorCard.layer.shadowOffset = CGSizeZero;
    } else {
        self.quickEditorCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
        self.quickEditorCard.layer.cornerRadius = 18.0;
        self.quickEditorCard.layer.borderWidth = 1.0;
        self.quickEditorCard.layer.borderColor = kVCBorderStrong.CGColor;
        self.quickEditorCard.layer.shadowColor = [UIColor blackColor].CGColor;
        self.quickEditorCard.layer.shadowOpacity = 0.24;
        self.quickEditorCard.layer.shadowRadius = 18.0;
        self.quickEditorCard.layer.shadowOffset = CGSizeMake(0, -6.0);
    }
}

- (void)_ensureQuickEditorCardParent {
    if (!self.quickEditorCard) return;
    UIView *targetParent = [self _shouldUseInlineQuickEditor] ? self.quickEditorInlineContainer : self.quickEditorOverlay;
    if (self.quickEditorCard.superview == targetParent) return;
    [self.quickEditorCard removeFromSuperview];
    [targetParent addSubview:self.quickEditorCard];
}

- (void)_layoutQuickEditorOverlay {
    if (!self.quickEditorOverlay || !self.quickEditorCard) return;

    BOOL inlineMode = [self _shouldUseInlineQuickEditor];
    [self _ensureQuickEditorCardParent];
    [self _applyQuickEditorCardChromeInline:inlineMode];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape) || (width > height);
    BOOL sideSheetLandscape = landscape && width >= 780.0 && !inlineMode;

    if (inlineMode) {
        self.quickEditorCard.frame = self.quickEditorInlineContainer.bounds;
    } else {
        CGFloat cardWidth = sideSheetLandscape ? MIN(MAX(width * 0.32, 308.0), 368.0) : (width - 24.0);
        CGFloat preferredCardHeight = sideSheetLandscape ? 390.0 : 360.0;
        CGFloat cardHeight = MAX(280.0, MIN(preferredCardHeight, height - 20.0));
        CGFloat cardX = sideSheetLandscape ? (width - cardWidth - 10.0) : 12.0;
        CGFloat cardY = sideSheetLandscape ? 10.0 : (height - cardHeight - 10.0);
        self.quickEditorCardLeadingConstraint.constant = cardX;
        self.quickEditorCardTopConstraint.constant = cardY;
        self.quickEditorCardWidthConstraint.constant = cardWidth;
        self.quickEditorCardHeightConstraint.constant = cardHeight;
        [self.quickEditorOverlay layoutIfNeeded];
    }

    CGFloat inset = 14.0;
    CGFloat contentWidth = CGRectGetWidth(self.quickEditorCard.bounds) - inset * 2.0;
    CGFloat y = 10.0;
    self.quickEditorHandle.hidden = sideSheetLandscape || inlineMode;
    self.quickEditorHandle.frame = CGRectMake((CGRectGetWidth(self.quickEditorCard.bounds) - 36.0) * 0.5, y, 36.0, 4.0);
    y += (sideSheetLandscape || inlineMode) ? 8.0 : 14.0;

    self.quickEditorCloseButton.frame = CGRectMake(CGRectGetWidth(self.quickEditorCard.bounds) - inset - 24.0, y, 24.0, 24.0);
    self.quickEditorTitleLabel.frame = CGRectMake(inset, y, contentWidth - 34.0, 20.0);
    y += 24.0;
    self.quickEditorSubtitleLabel.frame = CGRectMake(inset, y, contentWidth, 30.0);
    y += 38.0;

    self.quickTextField.frame = CGRectMake(inset, y, contentWidth, 34.0);
    y += 42.0;

    CGFloat halfWidth = floor((contentWidth - 8.0) * 0.5);
    self.quickApplyTextButton.frame = CGRectMake(inset, y, halfWidth, 34.0);
    self.quickInsertLabelButton.frame = CGRectMake(CGRectGetMaxX(self.quickApplyTextButton.frame) + 8.0, y, halfWidth, 34.0);
    y += 42.0;

    CGFloat colorTargetWidth = sideSheetLandscape ? 98.0 : 92.0;
    self.quickColorTargetControl.frame = CGRectMake(inset, y, colorTargetWidth, 32.0);
    self.quickColorField.frame = CGRectMake(CGRectGetMaxX(self.quickColorTargetControl.frame) + 8.0, y, contentWidth - colorTargetWidth - 8.0, 34.0);
    y += 42.0;

    CGFloat alphaWidth = sideSheetLandscape ? 92.0 : 82.0;
    self.quickAlphaField.frame = CGRectMake(inset, y, alphaWidth, 34.0);
    self.quickApplyStyleButton.frame = CGRectMake(CGRectGetMaxX(self.quickAlphaField.frame) + 8.0, y, contentWidth - alphaWidth - 8.0, 34.0);
    y += 42.0;

    self.quickToggleHiddenButton.frame = CGRectMake(inset, y, halfWidth, 34.0);
    self.quickToggleInteractionButton.frame = CGRectMake(CGRectGetMaxX(self.quickToggleHiddenButton.frame) + 8.0, y, halfWidth, 34.0);
    y += 42.0;

    self.quickStatusLabel.frame = CGRectMake(inset, y, contentWidth, MAX(40.0, CGRectGetHeight(self.quickEditorCard.bounds) - y - 14.0));
}

- (void)_toggleQuickEditor {
    BOOL showingInline = [self _shouldUseInlineQuickEditor] && self.quickEditorInlineVisible;
    if (showingInline || (!self.quickEditorOverlay.hidden && ![self _shouldUseInlineQuickEditor])) {
        [self _hideQuickEditor];
    } else {
        [self _showQuickEditor];
    }
}

- (void)_showQuickEditor {
    if (!self.selectedView) {
        [self _setQuickStatus:VCTextLiteral(@"Pick a live view before opening Quick Edit.") success:NO];
        return;
    }

    [self.view endEditing:YES];
    [self _refreshQuickEditState];
    [self _layoutQuickEditorOverlay];
    if ([self _shouldUseInlineQuickEditor]) {
        self.quickEditorInlineVisible = YES;
        self.quickEditorInlineContainer.hidden = NO;
        self.detailActionRowBottomConstraint.active = NO;
        self.detailActionRowBottomToInlineConstraint.active = YES;
        self.quickEditorInlineHeightConstraint.constant = MIN(MAX(CGRectGetHeight(self.view.bounds) * 0.36, 220.0), 286.0);
        self.quickEditorInlineContainer.alpha = 0.0;
        [self.view layoutIfNeeded];
        [UIView animateWithDuration:0.20 animations:^{
            self.quickEditorInlineContainer.alpha = 1.0;
            [self.view layoutIfNeeded];
        }];
        [self _refreshQuickEditState];
        return;
    }

    self.quickEditorOverlay.hidden = NO;
    [self.view bringSubviewToFront:self.quickEditorOverlay];
    self.quickEditorOverlay.alpha = 0.0;
    self.quickEditorOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];

    BOOL sideSheetLandscape = ((self.currentLayoutMode == VCPanelLayoutModeLandscape) || (CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds))) && CGRectGetWidth(self.view.bounds) >= 780.0;
    self.quickEditorCard.transform = sideSheetLandscape
        ? CGAffineTransformMakeTranslation(CGRectGetWidth(self.quickEditorCard.bounds) + 20.0, 0)
        : CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.quickEditorCard.bounds) + 20.0);

    [UIView animateWithDuration:0.22 animations:^{
        self.quickEditorOverlay.alpha = 1.0;
        self.quickEditorOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.24];
        self.quickEditorCard.transform = CGAffineTransformIdentity;
    }];
}

- (void)_hideQuickEditor {
    if ([self _shouldUseInlineQuickEditor] && self.quickEditorInlineVisible) {
        [self.view endEditing:YES];
        self.quickEditorInlineVisible = NO;
        self.detailActionRowBottomToInlineConstraint.active = NO;
        self.detailActionRowBottomConstraint.active = YES;
        self.quickEditorInlineHeightConstraint.constant = 0.0;
        [UIView animateWithDuration:0.18 animations:^{
            self.quickEditorInlineContainer.alpha = 0.0;
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished) {
            self.quickEditorInlineContainer.hidden = YES;
            [self _refreshQuickEditState];
        }];
        return;
    }
    if (!self.quickEditorOverlay || self.quickEditorOverlay.hidden) return;

    [self.view endEditing:YES];
    BOOL sideSheetLandscape = ((self.currentLayoutMode == VCPanelLayoutModeLandscape) || (CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds))) && CGRectGetWidth(self.view.bounds) >= 780.0;
    [UIView animateWithDuration:0.18 animations:^{
        self.quickEditorOverlay.alpha = 0.0;
        self.quickEditorOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
        self.quickEditorCard.transform = sideSheetLandscape
            ? CGAffineTransformMakeTranslation(CGRectGetWidth(self.quickEditorCard.bounds) + 20.0, 0)
            : CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.quickEditorCard.bounds) + 20.0);
    } completion:^(BOOL finished) {
        self.quickEditorOverlay.hidden = YES;
        self.quickEditorCard.transform = CGAffineTransformIdentity;
        [self _refreshQuickEditState];
    }];
}

- (void)_applyCurrentLayoutMode {
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape);
    CGFloat width = CGRectGetWidth(self.view.bounds);
    self.headerPortraitLeadingConstraint.active = !landscape;
    self.headerPortraitTrailingConstraint.active = !landscape;
    self.headerLandscapeLeadingConstraint.active = landscape;
    self.headerLandscapeTrailingConstraint.active = landscape;
    self.tableTopToHeaderConstraint.active = !landscape;
    self.tableTopToViewConstraint.active = landscape;
    self.portraitTableBottomConstraint.active = !landscape;
    self.portraitDetailLeadingConstraint.active = !landscape;
    self.portraitDetailTrailingConstraint.active = !landscape;
    self.portraitDetailBottomConstraint.active = !landscape;
    self.detailHeightConstraint.active = !landscape;

    self.landscapeTableTrailingConstraint.active = landscape;
    self.landscapeTableBottomConstraint.active = landscape;
    self.landscapeDetailLeadingConstraint.active = landscape;
    self.landscapeDetailTrailingConstraint.active = landscape;
    self.landscapeDetailTopConstraint.active = landscape;
    self.landscapeDetailBottomConstraint.active = landscape;
    self.landscapeDetailWidthConstraint.active = landscape;
    self.detailLandscapeBottomConstraint.active = landscape;
    self.headerHeightConstraint.constant = landscape ? 108.0 : 122.0;
    self.landscapeDetailWidthConstraint.constant = landscape ? MIN(MAX(width * 0.30, 284.0), 360.0) : 340.0;

    if ([self _shouldUseInlineQuickEditor]) {
        self.quickEditorOverlay.hidden = YES;
        self.quickEditorOverlay.alpha = 0.0;
        if (self.quickEditorInlineVisible) {
            self.quickEditorInlineContainer.hidden = NO;
            self.quickEditorInlineContainer.alpha = 1.0;
            self.detailActionRowBottomConstraint.active = NO;
            self.detailActionRowBottomToInlineConstraint.active = YES;
            self.quickEditorInlineHeightConstraint.constant = MIN(MAX(CGRectGetHeight(self.view.bounds) * 0.36, 220.0), 286.0);
        }
    } else {
        self.detailActionRowBottomToInlineConstraint.active = NO;
        self.detailActionRowBottomConstraint.active = YES;
        self.quickEditorInlineHeightConstraint.constant = 0.0;
        self.quickEditorInlineContainer.hidden = YES;
        self.quickEditorInlineContainer.alpha = 0.0;
        self.quickEditorInlineVisible = NO;
    }

    [self _layoutQuickEditorOverlay];
    [self _layoutQuickEditorDock];
    [self _refreshQuickEditState];
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    [self _applyCurrentLayoutMode];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self _layoutQuickEditorOverlay];
    [self _layoutQuickEditorDock];
}

#pragma mark - Actions

- (void)_toggleSelectionHighlight {
    VCUIInspector *inspector = [VCUIInspector shared];
    inspector.selectionHighlightEnabled = !inspector.selectionHighlightEnabled;
    if (inspector.selectionHighlightEnabled && self.selectedView) {
        [inspector highlightView:self.selectedView];
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
    self.highlightToggleButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.highlightToggleButton.contentEdgeInsets = UIEdgeInsetsMake(7, 10, 7, 10);
    VCApplyCompactIconTitleButtonLayout(self.highlightToggleButton, @"square", 11.0);
}

- (void)_togglePick {
    VCTouchOverlay *overlay = [VCTouchOverlay shared];
    if (overlay.isPicking) {
        [overlay stopPicking];
    } else {
        [self _setPanelHiddenForPicking:YES];
        [overlay startPicking];
        _statusLabel.text = VCTextLiteral(@"Picking active • panel hidden until you tap a view");
    }
    [self _updatePickButtonState];
}

- (void)_updatePickButtonState {
    BOOL picking = [VCTouchOverlay shared].isPicking;
    [_pickButton setTitle:(picking ? VCTextLiteral(@"Picking...") : VCTextLiteral(@"Pick View")) forState:UIControlStateNormal];
    if (picking) {
        VCApplyCompactDangerButtonStyle(_pickButton);
    } else {
        VCApplyCompactAccentButtonStyle(_pickButton);
    }
    _pickButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _pickButton.contentEdgeInsets = UIEdgeInsetsMake(7, 10, 7, 10);
    VCApplyCompactIconTitleButtonLayout(_pickButton, (picking ? @"xmark" : @"scope"), 11.0);
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
            _panelHiddenForPicking = YES;
            [panel hideAnimated];
        }
    } else if (_panelHiddenForPicking) {
        _panelHiddenForPicking = NO;
        [panel showAnimated];
    }
}

- (void)_refreshTree {
    VCViewNode *root = [[VCUIInspector shared] viewHierarchyTree];
    [_allFlatTree removeAllObjects];
    [_flatTree removeAllObjects];
    [self _flattenNode:root depth:0 intoArray:_allFlatTree];
    [self _applyFilter];
    _statusLabel.text = [NSString stringWithFormat:@"%lu nodes%@", (unsigned long)_flatTree.count, _filterField.text.length ? @" • filtered" : @""];
    [_tableView reloadData];
}

- (void)_flattenNode:(VCViewNode *)node depth:(NSInteger)depth intoArray:(NSMutableArray<NSDictionary *> *)collector {
    if (!node) return;
    BOOL hasChildren = (node.children.count > 0);
    NSNumber *addrKey = @(node.address);
    BOOL isCollapsed = [_collapsedAddresses containsObject:addrKey];
    [collector addObject:@{@"node": node, @"depth": @(depth), @"hasChildren": @(hasChildren), @"collapsed": @(isCollapsed)}];
    if (!isCollapsed) {
        for (VCViewNode *child in node.children) {
            [self _flattenNode:child depth:depth + 1 intoArray:collector];
        }
    }
}

- (void)_showDetailForView:(UIView *)view {
    if (!view) {
        _detailView.text = kVCUIInspectorEmptyDetailText;
        [self _refreshQuickEditState];
        return;
    }
    NSDictionary *props = [[VCUIInspector shared] propertiesForView:view];
    NSMutableString *s = [NSMutableString new];
    [s appendFormat:@"<%@: 0x%lX>\n", NSStringFromClass([view class]), (unsigned long)(uintptr_t)(__bridge void *)view];
    [s appendFormat:@"frame: %@\n", NSStringFromCGRect(view.frame)];
    for (NSString *key in [props.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [s appendFormat:@"%@: %@\n", key, props[key]];
    }
    NSArray *chain = [[VCUIInspector shared] responderChainForView:view];
    [s appendFormat:@"responders: %@", [chain componentsJoinedByString:@" -> "]];
    _detailView.text = s;
    [_detailView setContentOffset:CGPointZero animated:NO];
    [self _refreshQuickEditState];
}

- (NSDictionary *)_referenceDictionaryForView:(UIView *)view {
    if (!view) return nil;

    NSDictionary *props = [[VCUIInspector shared] propertiesForView:view] ?: @{};
    NSArray<NSString *> *chain = [[VCUIInspector shared] responderChainForView:view] ?: @[];
    NSString *className = NSStringFromClass([view class]) ?: @"UIView";
    NSString *address = [NSString stringWithFormat:@"0x%llx", (unsigned long long)(uintptr_t)(__bridge void *)view];
    NSString *title = [NSString stringWithFormat:@"%@ • %@", className, address];

    return @{
        @"referenceID": [[NSUUID UUID] UUIDString],
        @"kind": @"UI",
        @"title": title,
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

- (void)_queueViewForChat:(UIView *)view switchToChat:(BOOL)switchToChat {
    NSDictionary *reference = [self _referenceDictionaryForView:view];
    if (!reference) {
        self.statusLabel.text = VCTextLiteral(@"No selected view to queue for Chat");
        return;
    }

    [[VCChatSession shared] enqueuePendingReference:reference];
    self.statusLabel.text = switchToChat
        ? [NSString stringWithFormat:VCTextLiteral(@"Queued %@ for Chat • opening AI Chat"), reference[@"title"] ?: VCTextLiteral(@"UI view")]
        : [NSString stringWithFormat:VCTextLiteral(@"Queued %@ for Chat"), reference[@"title"] ?: VCTextLiteral(@"UI view")];
    [self _setQuickStatus:VCTextLiteral(@"Queued selected view for AI Chat.") success:YES];

    if (switchToChat) {
        [[NSNotificationCenter defaultCenter] postNotificationName:VCSettingsRequestOpenAIChatNotification object:self];
    }
}

- (void)_handleTreeLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath || indexPath.row >= (NSInteger)self.flatTree.count) return;

    NSDictionary *entry = self.flatTree[indexPath.row];
    VCViewNode *node = entry[@"node"];
    if (!node.view) return;

    [self _applySelectedView:node.view
                  statusText:[NSString stringWithFormat:VCTextLiteral(@"Queued %@ for Chat"), node.className ?: VCTextLiteral(@"View")]
     deselectSameViewStatus:VCTextLiteral(@"Selection cleared")
                 revealInTree:NO];
    [self _queueViewForChat:node.view switchToChat:YES];
}

- (void)_handleDetailLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self _queueViewForChat:self.selectedView switchToChat:YES];
}

- (void)_clearSelectedViewWithStatus:(NSString *)statusText {
    self.selectedView = nil;
    [[VCUIInspector shared] rememberSelectedView:nil];
    [[VCUIInspector shared] clearHighlights];
    [self _showDetailForView:nil];
    if (statusText.length > 0) {
        self.statusLabel.text = statusText;
    }
    [self.tableView reloadData];
}

- (void)_applySelectedView:(UIView *)view
                statusText:(NSString *)statusText
   deselectSameViewStatus:(NSString *)deselectStatusText
               revealInTree:(BOOL)revealInTree {
    if (!view) {
        [self _clearSelectedViewWithStatus:deselectStatusText];
        return;
    }

    if (self.selectedView == view) {
        [self _clearSelectedViewWithStatus:(deselectStatusText.length > 0 ? deselectStatusText : @"Selection cleared")];
        return;
    }

    self.selectedView = view;
    [[VCUIInspector shared] rememberSelectedView:view];
    [[VCUIInspector shared] highlightView:view];
    [self _showDetailForView:view];
    if (statusText.length > 0) {
        self.statusLabel.text = statusText;
    }
    [self.tableView reloadData];
    if (revealInTree) {
        [self _revealSelectedViewInTree];
    }
}

- (void)_setQuickStatus:(NSString *)message success:(BOOL)success {
    self.quickStatusLabel.text = message ?: @"";
    self.quickStatusLabel.textColor = success ? kVCGreen : kVCRed;
    if (message.length > 0) {
        self.detailActionHintLabel.text = message;
        self.detailActionHintLabel.textColor = success ? kVCGreen : kVCRed;
    }
}

- (void)_refreshQuickEditState {
    UIView *view = self.selectedView;
    BOOL editorVisible = ([self _shouldUseInlineQuickEditor] && self.quickEditorInlineVisible) ||
        (!self.quickEditorOverlay.hidden && ![self _shouldUseInlineQuickEditor]);
    BOOL shouldShowDock = (view != nil) && !editorVisible;
    if (!view) {
        self.quickTextField.text = @"";
        self.quickColorField.text = @"";
        self.quickAlphaField.text = @"";
        [self.quickToggleHiddenButton setTitle:VCTextLiteral(@"Hide") forState:UIControlStateNormal];
        [self.quickToggleInteractionButton setTitle:VCTextLiteral(@"Disable Tap") forState:UIControlStateNormal];
        self.quickStatusLabel.text = VCTextLiteral(@"Pick a live view to edit it.");
        self.quickStatusLabel.textColor = kVCTextSecondary;
        self.detailActionHintLabel.text = VCTextLiteral(@"Pick a live view to inspect it.");
        self.detailActionHintLabel.textColor = kVCTextSecondary;
        self.quickEditOpenButton.enabled = NO;
        self.quickEditOpenButton.alpha = 0.55;
        self.quickEditOpenButton.hidden = YES;
        self.quickEditorDockButton.enabled = NO;
        self.quickEditorDockButton.alpha = 0.55;
        [self.quickEditorDockButton setTitle:VCTextLiteral(@"Modify") forState:UIControlStateNormal];
        self.quickEditorSubtitleLabel.text = VCTextLiteral(@"Select a live view first.");
        [self.quickEditOpenButton setTitle:VCTextLiteral(@"Quick Edit") forState:UIControlStateNormal];
        if (!self.quickEditorOverlay.hidden) {
            [self _hideQuickEditor];
        }
        self.quickEditorDock.hidden = YES;
        self.quickEditorDock.alpha = 0.0;
        return;
    }

    NSDictionary *props = [[VCUIInspector shared] propertiesForView:view];
    NSString *text = props[@"text"] ?: props[@"currentTitle"] ?: props[@"titleLabel.text"];
    self.quickTextField.text = ([text isKindOfClass:[NSString class]] && ![text isEqualToString:@"nil"]) ? text : @"";
    NSString *bgColor = props[@"backgroundColor"];
    self.quickColorField.text = ([bgColor isKindOfClass:[NSString class]] && ![bgColor isEqualToString:@"nil"]) ? bgColor : @"";
    self.quickAlphaField.text = [NSString stringWithFormat:@"%.2f", view.alpha];
    [self.quickToggleHiddenButton setTitle:(view.hidden ? VCTextLiteral(@"Show") : VCTextLiteral(@"Hide")) forState:UIControlStateNormal];
    [self.quickToggleInteractionButton setTitle:(view.userInteractionEnabled ? VCTextLiteral(@"Disable Tap") : VCTextLiteral(@"Enable Tap")) forState:UIControlStateNormal];
    self.quickStatusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Editing <%@: %p>"), NSStringFromClass([view class]), view];
    self.quickStatusLabel.textColor = kVCTextSecondary;
    self.detailActionHintLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Selected %@"), NSStringFromClass([view class])];
    self.detailActionHintLabel.textColor = kVCTextSecondary;
    self.quickEditOpenButton.enabled = YES;
    self.quickEditOpenButton.alpha = 1.0;
    self.quickEditOpenButton.hidden = NO;
    self.quickEditorDockButton.enabled = YES;
    self.quickEditorDockButton.alpha = 1.0;
    [self.quickEditorDockButton setTitle:(editorVisible ? VCTextLiteral(@"Collapse") : VCTextLiteral(@"Modify")) forState:UIControlStateNormal];
    self.quickEditorSubtitleLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Editing <%@: %p>"), NSStringFromClass([view class]), view];
    [self.quickEditOpenButton setTitle:(editorVisible ? VCTextLiteral(@"Hide Editor") : VCTextLiteral(@"Quick Edit")) forState:UIControlStateNormal];

    [self _layoutQuickEditorDock];
    if (shouldShowDock) {
        if (self.quickEditorDock.hidden) {
            self.quickEditorDock.hidden = NO;
            self.quickEditorDock.alpha = 0.0;
            self.quickEditorDock.transform = CGAffineTransformMakeTranslation(0, 16.0);
        }
        [self.view bringSubviewToFront:self.quickEditorDock];
        [UIView animateWithDuration:0.18 animations:^{
            self.quickEditorDock.alpha = 1.0;
            self.quickEditorDock.transform = CGAffineTransformIdentity;
        }];
    } else if (!self.quickEditorDock.hidden || self.quickEditorDock.alpha > 0.0) {
        [UIView animateWithDuration:0.16 animations:^{
            self.quickEditorDock.alpha = 0.0;
            self.quickEditorDock.transform = CGAffineTransformMakeTranslation(0, 16.0);
        } completion:^(__unused BOOL finished) {
            self.quickEditorDock.hidden = YES;
            self.quickEditorDock.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)_applyQuickText {
    if (!self.selectedView) {
        [self _setQuickStatus:VCTextLiteral(@"No selected view to update.") success:NO];
        return;
    }
    NSString *text = [self.quickTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        [self _setQuickStatus:VCTextLiteral(@"Enter text before applying it.") success:NO];
        return;
    }
    [[VCUIInspector shared] modifyView:self.selectedView property:@"text" value:text];
    [[VCUIInspector shared] highlightView:self.selectedView];
    [self _showDetailForView:self.selectedView];
    [self _setQuickStatus:VCTextLiteral(@"Applied native text/title update.") success:YES];
}

- (void)_insertQuickLabel {
    if (!self.selectedView) {
        [self _setQuickStatus:VCTextLiteral(@"Select a parent view before adding a label.") success:NO];
        return;
    }
    NSString *text = [self.quickTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) text = VCTextLiteral(@"New Label");
    CGFloat parentWidth = MAX(CGRectGetWidth(self.selectedView.bounds), CGRectGetWidth(self.selectedView.frame));
    NSDictionary *spec = @{
        @"className": @"UILabel",
        @"text": text,
        @"frame": @{
            @"x": @8,
            @"y": @(MAX(8.0, CGRectGetHeight(self.selectedView.bounds) - 28.0)),
            @"width": @(MAX(80.0, parentWidth - 16.0)),
            @"height": @24
        },
        @"textColor": self.quickColorField.text.length > 0 ? self.quickColorField.text : @"FFFFFF"
    };
    UIView *created = [[VCUIInspector shared] insertSubviewIntoView:self.selectedView spec:spec];
    if (!created) {
        [self _setQuickStatus:VCTextLiteral(@"Unable to insert a native label into the selected view.") success:NO];
        return;
    }
    self.selectedView = created;
    [self _showDetailForView:created];
    [self _refreshTree];
    [self _revealSelectedViewInTree];
    [self _setQuickStatus:VCTextLiteral(@"Inserted a native UILabel into the selected view.") success:YES];
}

- (void)_applyQuickStyle {
    if (!self.selectedView) {
        [self _setQuickStatus:VCTextLiteral(@"No selected view to style.") success:NO];
        return;
    }
    BOOL changed = NO;
    NSString *colorText = [self.quickColorField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (colorText.length > 0) {
        NSString *property = self.quickColorTargetControl.selectedSegmentIndex == 0 ? @"backgroundColor" : @"textColor";
        [[VCUIInspector shared] modifyView:self.selectedView property:property value:colorText];
        changed = YES;
    }
    NSString *alphaText = [self.quickAlphaField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (alphaText.length > 0) {
        [[VCUIInspector shared] modifyView:self.selectedView property:@"alpha" value:@([alphaText doubleValue])];
        changed = YES;
    }
    if (!changed) {
        [self _setQuickStatus:VCTextLiteral(@"Enter a color and/or alpha value first.") success:NO];
        return;
    }
    [[VCUIInspector shared] highlightView:self.selectedView];
    [self _showDetailForView:self.selectedView];
    [self _setQuickStatus:VCTextLiteral(@"Applied native style changes.") success:YES];
}

- (void)_toggleQuickHidden {
    if (!self.selectedView) {
        [self _setQuickStatus:VCTextLiteral(@"No selected view to hide/show.") success:NO];
        return;
    }
    BOOL nextHidden = !self.selectedView.hidden;
    [[VCUIInspector shared] modifyView:self.selectedView property:@"hidden" value:@(nextHidden)];
    [self _showDetailForView:self.selectedView];
    [self _setQuickStatus:(nextHidden ? VCTextLiteral(@"View hidden.") : VCTextLiteral(@"View shown.")) success:YES];
}

- (void)_toggleQuickInteraction {
    if (!self.selectedView) {
        [self _setQuickStatus:VCTextLiteral(@"No selected view to toggle interaction.") success:NO];
        return;
    }
    BOOL nextValue = !self.selectedView.userInteractionEnabled;
    [[VCUIInspector shared] modifyView:self.selectedView property:@"userInteractionEnabled" value:@(nextValue)];
    [self _showDetailForView:self.selectedView];
    [self _setQuickStatus:(nextValue ? VCTextLiteral(@"Tap interaction enabled.") : VCTextLiteral(@"Tap interaction disabled.")) success:YES];
}

- (void)_filterChanged:(UITextField *)field {
    [self _applyFilter];
    _statusLabel.text = [NSString stringWithFormat:@"%lu nodes%@", (unsigned long)_flatTree.count, field.text.length ? @" • filtered" : @""];
    [_tableView reloadData];
}

- (void)_applyFilter {
    [_flatTree removeAllObjects];
    NSString *query = [self.filterField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        [_flatTree addObjectsFromArray:_allFlatTree];
        return;
    }

    NSString *lowerQuery = query.lowercaseString;
    for (NSDictionary *entry in _allFlatTree) {
        VCViewNode *node = entry[@"node"];
        NSString *addressString = [NSString stringWithFormat:@"0x%lX", (unsigned long)node.address].lowercaseString;
        NSString *className = node.className.lowercaseString ?: @"";
        NSString *summary = node.briefDescription.lowercaseString ?: @"";
        if ([className containsString:lowerQuery] || [addressString containsString:lowerQuery] || [summary containsString:lowerQuery]) {
            [_flatTree addObject:entry];
        }
    }
}

- (void)_revealSelectedViewInTree {
    if (!_selectedView) return;
    uintptr_t address = (uintptr_t)(__bridge void *)_selectedView;
    for (NSUInteger idx = 0; idx < _flatTree.count; idx++) {
        VCViewNode *node = _flatTree[idx][@"node"];
        if (node.address == address) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)idx inSection:0];
            if (idx < (NSUInteger)[_tableView numberOfRowsInSection:0]) {
                [_tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
            }
            return;
        }
    }
}

#pragma mark - VCTouchOverlayDelegate

- (void)touchOverlay:(VCTouchOverlay *)overlay didSelectView:(UIView *)view {
    [self _setPanelHiddenForPicking:NO];
    [self _updatePickButtonState];
    [self _refreshTree];
    [self _applySelectedView:view
                  statusText:[NSString stringWithFormat:VCTextLiteral(@"Picked %@"), NSStringFromClass([view class])]
     deselectSameViewStatus:VCTextLiteral(@"Picked same view again • highlight cleared")
                 revealInTree:YES];
}

- (void)touchOverlayDidCancel:(VCTouchOverlay *)overlay {
    [self _setPanelHiddenForPicking:NO];
    [self _updatePickButtonState];
    if (self.selectedView) {
        [[VCUIInspector shared] highlightView:self.selectedView];
    } else {
        [[VCUIInspector shared] clearHighlights];
    }
    [self _refreshTree];
    _statusLabel.text = VCTextLiteral(@"Pick cancelled");
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([VCTouchOverlay shared].isPicking) {
        [[VCTouchOverlay shared] stopPicking];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_flatTree.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    VCUIInspectorTreeCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID forIndexPath:indexPath];

    NSDictionary *entry = _flatTree[indexPath.row];
    VCViewNode *node = entry[@"node"];
    NSInteger depth = [entry[@"depth"] integerValue];
    BOOL hasChildren = [entry[@"hasChildren"] boolValue];
    BOOL isCollapsed = [entry[@"collapsed"] boolValue];
    [cell configureWithNode:node
                      depth:depth
                hasChildren:hasChildren
                  collapsed:isCollapsed
                   selected:(node.view == _selectedView)];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.frame = UIEdgeInsetsInsetRect(cell.frame, UIEdgeInsetsMake(4, 10, 4, 10));
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *entry = _flatTree[indexPath.row];
    VCViewNode *node = entry[@"node"];
    BOOL hasChildren = [entry[@"hasChildren"] boolValue];

    if (hasChildren) {
        // Toggle collapse/expand
        NSNumber *addrKey = @(node.address);
        if ([_collapsedAddresses containsObject:addrKey]) {
            [_collapsedAddresses removeObject:addrKey];
        } else {
            [_collapsedAddresses addObject:addrKey];
        }
        // Rebuild flat tree preserving collapse state
        VCViewNode *root = [[VCUIInspector shared] viewHierarchyTree];
        [_allFlatTree removeAllObjects];
        [_flatTree removeAllObjects];
        [self _flattenNode:root depth:0 intoArray:_allFlatTree];
        [self _applyFilter];
        [_tableView reloadData];
    }

    if (node.view) {
        [self _applySelectedView:node.view
                      statusText:(node.className ?: VCTextLiteral(@"View selected"))
         deselectSameViewStatus:VCTextLiteral(@"Selection cleared")
                     revealInTree:NO];
    }
}

@end
