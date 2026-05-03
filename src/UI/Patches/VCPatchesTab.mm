/**
 * VCPatchesTab -- Patches Tab 主容器
 */

#import "VCPatchesTab.h"
#import "VCPatchCell.h"
#import "../../../VansonCLI.h"
#import "../../Patches/VCPatchManager.h"
#import "../../Patches/VCPatchItem.h"
#import "../../Patches/VCValueItem.h"
#import "../../Patches/VCHookItem.h"
#import "../../Patches/VCNetRule.h"
#import "../Panel/VCPanel.h"

static NSString *const kCellID = @"VCPatchCell";
NSNotificationName const VCPatchesRequestOpenEditorNotification = @"VCPatchesRequestOpenEditorNotification";
NSString *const VCPatchesOpenEditorSegmentKey = @"segment";
NSString *const VCPatchesOpenEditorItemKey = @"item";
NSString *const VCPatchesOpenEditorCreatesKey = @"creates";

@interface VCPatchesTab () <UITableViewDataSource, UITableViewDelegate, VCPatchCellDelegate, VCPanelLayoutUpdatable>
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) UIView *editorOverlay;
@property (nonatomic, strong) UIView *editorCard;
@property (nonatomic, strong) UIScrollView *editorScrollView;
@property (nonatomic, strong) UIView *editorContentView;
@property (nonatomic, strong) UILabel *editorTitleLabel;
@property (nonatomic, strong) UILabel *editorHintLabel;
@property (nonatomic, strong) UILabel *editorErrorLabel;
@property (nonatomic, strong) UILabel *editorField1Label;
@property (nonatomic, strong) UILabel *editorField2Label;
@property (nonatomic, strong) UILabel *editorField3Label;
@property (nonatomic, strong) UILabel *editorField4Label;
@property (nonatomic, strong) UILabel *editorField5Label;
@property (nonatomic, strong) UILabel *editorPayloadLabel;
@property (nonatomic, strong) UITextField *editorField1;
@property (nonatomic, strong) UITextField *editorField2;
@property (nonatomic, strong) UITextField *editorField3;
@property (nonatomic, strong) UITextField *editorField4;
@property (nonatomic, strong) UISegmentedControl *editorTypeControl;
@property (nonatomic, strong) UITextView *editorPayloadView;
@property (nonatomic, strong) UIButton *editorPrimaryButton;
@property (nonatomic, strong) UIButton *editorCancelButton;
@property (nonatomic, strong) id editingItem;
@property (nonatomic, assign) BOOL editorCreatesItem;
@property (nonatomic, strong) NSLayoutConstraint *segmentHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *addButtonWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *addButtonHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *segmentTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *editorCardLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *editorCardTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *editorCardWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *editorCardHeightConstraint;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@end

@implementation VCPatchesTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;
    self.title = @"Patches";
    self.currentLayoutMode = VCPanelLayoutModePortrait;

    [self setupHeader];
    [self setupSegment];
    [self setupTableView];
    [self setupStatusBar];
    [self setupAddButton];
    [self setupEditorOverlay];
    VCInstallKeyboardDismissAccessory(self.view);
    [self _applyCurrentLayoutMode];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleUpdate)
                                                 name:VCPatchManagerDidUpdateNotification
                                               object:nil];
    [self refreshUI];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self _layoutEditorOverlay];
}

- (void)openEditorForDraftItem:(id)item segmentIndex:(NSInteger)segment createsItem:(BOOL)createsItem {
    NSInteger clampedSegment = MAX(0, MIN(3, segment));
    self.segmentControl.selectedSegmentIndex = clampedSegment;
    [self refreshUI];
    [self showEditorForItem:item createsItem:createsItem];
}

#pragma mark - Setup

- (void)setupHeader {
    _headerCard = [[UIView alloc] init];
    _headerCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.94];
    _headerCard.layer.cornerRadius = 18.0;
    _headerCard.layer.borderWidth = 1.0;
    _headerCard.layer.borderColor = kVCBorder.CGColor;
    _headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerCard];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"PATCH RACK";
    titleLabel.textColor = kVCTextSecondary;
    titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_headerCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [_headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [_headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [titleLabel.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:10],
        [titleLabel.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
    ]];
}

- (void)setupSegment {
    _segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"Patches", @"Values", @"Hooks", @"Rules"]];
    _segmentControl.selectedSegmentIndex = 0;
    _segmentControl.selectedSegmentTintColor = kVCAccent;
    [_segmentControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary} forState:UIControlStateNormal];
    [_segmentControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    [_segmentControl addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    _segmentControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_segmentControl];

    [NSLayoutConstraint activateConstraints:@[
        [_segmentControl.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:30],
        [_segmentControl.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
    ]];
    self.segmentTrailingConstraint = [_segmentControl.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-56];
    self.segmentTrailingConstraint.active = YES;
    self.segmentHeightConstraint = [_segmentControl.heightAnchor constraintEqualToConstant:32];
    self.segmentHeightConstraint.active = YES;
}

- (void)setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 80;
    _tableView.contentInset = UIEdgeInsetsMake(6, 0, 12, 0);
    [_tableView registerClass:[VCPatchCell class] forCellReuseIdentifier:kCellID];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:8],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)setupStatusBar {
    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _statusLabel.textColor = kVCTextPrimary;
    _statusLabel.textAlignment = NSTextAlignmentLeft;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _statusLabel.numberOfLines = 1;
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_statusLabel.topAnchor constraintEqualToAnchor:_segmentControl.bottomAnchor constant:10],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:-10],
    ]];
}

- (void)setupAddButton {
    _addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_addButton setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    VCApplyCompactPrimaryButtonStyle(_addButton);
    [_addButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    _addButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_addButton];

    [NSLayoutConstraint activateConstraints:@[
        [_addButton.centerYAnchor constraintEqualToAnchor:_segmentControl.centerYAnchor],
        [_addButton.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
    ]];
    self.addButtonWidthConstraint = [_addButton.widthAnchor constraintEqualToConstant:32];
    self.addButtonWidthConstraint.active = YES;
    self.addButtonHeightConstraint = [_addButton.heightAnchor constraintEqualToConstant:32];
    self.addButtonHeightConstraint.active = YES;
}

#pragma mark - Actions

- (void)segmentChanged {
    [self hideEditorOverlay];
    [self.tableView reloadData];
    [self refreshUI];
}

- (void)handleUpdate {
    vc_dispatch_main(^{ [self refreshUI]; });
}

- (void)refreshUI {
    VCPatchManager *mgr = [VCPatchManager shared];
    BOOL compact = (self.currentLayoutMode == VCPanelLayoutModeLandscape);
    [_segmentControl setTitle:(compact ? [NSString stringWithFormat:@"P %lu", (unsigned long)mgr.allPatches.count] : [NSString stringWithFormat:@"Patches (%lu)", (unsigned long)mgr.allPatches.count]) forSegmentAtIndex:0];
    [_segmentControl setTitle:(compact ? [NSString stringWithFormat:@"V %lu", (unsigned long)mgr.allValues.count] : [NSString stringWithFormat:@"Values (%lu)", (unsigned long)mgr.allValues.count]) forSegmentAtIndex:1];
    [_segmentControl setTitle:(compact ? [NSString stringWithFormat:@"H %lu", (unsigned long)mgr.allHooks.count] : [NSString stringWithFormat:@"Hooks (%lu)", (unsigned long)mgr.allHooks.count]) forSegmentAtIndex:2];
    [_segmentControl setTitle:(compact ? [NSString stringWithFormat:@"R %lu", (unsigned long)mgr.allRules.count] : [NSString stringWithFormat:@"Rules (%lu)", (unsigned long)mgr.allRules.count]) forSegmentAtIndex:3];

    NSArray *items = [self currentItems];
    _statusLabel.text = compact
        ? [NSString stringWithFormat:@"%lu/%lu enabled · %lu AI · %@ items",
           (unsigned long)mgr.enabledCount, (unsigned long)mgr.totalCount,
           (unsigned long)mgr.aiCreatedCount, @((NSInteger)items.count)]
        : [NSString stringWithFormat:@"Enabled: %lu/%lu | From AI: %lu | %@ items • tap to edit",
           (unsigned long)mgr.enabledCount, (unsigned long)mgr.totalCount,
           (unsigned long)mgr.aiCreatedCount, @((NSInteger)items.count)];
    if (items.count == 0) {
        self.tableView.backgroundView = VCBuildEmptyStateLabel(@"No items yet.\nUse + to create one for this tab.");
    } else {
        self.tableView.backgroundView = nil;
    }
    [_tableView reloadData];
}

- (void)_applyCurrentLayoutMode {
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape);
    self.segmentHeightConstraint.constant = landscape ? 28.0 : 32.0;
    self.addButtonWidthConstraint.constant = landscape ? 28.0 : 32.0;
    self.addButtonHeightConstraint.constant = landscape ? 28.0 : 32.0;
    self.segmentTrailingConstraint.constant = landscape ? -48.0 : -56.0;
    [self.segmentControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: kVCTextPrimary,
        NSFontAttributeName: [UIFont systemFontOfSize:(landscape ? 10.0 : 11.0) weight:UIFontWeightSemibold]
    } forState:UIControlStateNormal];
    [self.segmentControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: kVCBgPrimary,
        NSFontAttributeName: [UIFont systemFontOfSize:(landscape ? 10.0 : 11.0) weight:UIFontWeightSemibold]
    } forState:UIControlStateSelected];
    self.statusLabel.font = [UIFont systemFontOfSize:(landscape ? 10.0 : 11.0) weight:UIFontWeightSemibold];
    self.statusLabel.numberOfLines = 1;
    self.tableView.contentInset = landscape ? UIEdgeInsetsMake(4, 0, 8, 0) : UIEdgeInsetsMake(6, 0, 12, 0);
    [self refreshUI];
    [self _layoutEditorOverlay];
}

- (void)_layoutEditorOverlay {
    if (!self.editorOverlay || !self.editorCard) return;
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    if (width <= 1.0 || height <= 1.0) return;
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape) || (width > height);
    BOOL sideSheet = landscape && width >= 560.0;
    CGFloat cardWidth = sideSheet ? MIN(MAX(width * 0.34, 320.0), 390.0) : MAX(260.0, width - 20.0);
    CGFloat maxHeight = MAX(260.0, height - 20.0);
    CGFloat cardHeight = sideSheet ? maxHeight : MIN(430.0, maxHeight);
    self.editorCardLeadingConstraint.constant = sideSheet ? (width - cardWidth - 10.0) : 10.0;
    self.editorCardTopConstraint.constant = sideSheet ? 10.0 : (height - cardHeight - 10.0);
    self.editorCardWidthConstraint.constant = cardWidth;
    self.editorCardHeightConstraint.constant = cardHeight;
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    [self _applyCurrentLayoutMode];
}

#pragma mark - Current Data

- (NSArray *)currentItems {
    VCPatchManager *mgr = [VCPatchManager shared];
    switch (_segmentControl.selectedSegmentIndex) {
        case 0: return mgr.allPatches;
        case 1: return mgr.allValues;
        case 2: return mgr.allHooks;
        case 3: return mgr.allRules;
        default: return @[];
    }
}

- (NSString *)itemIDForItem:(id)item {
    if ([item isKindOfClass:[VCPatchItem class]]) return [(VCPatchItem *)item patchID];
    if ([item isKindOfClass:[VCValueItem class]]) return [(VCValueItem *)item valueID];
    if ([item isKindOfClass:[VCHookItem class]]) return [(VCHookItem *)item hookID];
    if ([item isKindOfClass:[VCNetRule class]]) return [(VCNetRule *)item ruleID];
    return nil;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self currentItems].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    VCPatchCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID forIndexPath:indexPath];
    cell.delegate = self;

    NSArray *items = [self currentItems];
    if (indexPath.row >= (NSInteger)items.count) return cell;

    id item = items[indexPath.row];
    if ([item isKindOfClass:[VCPatchItem class]])  [cell configureWithPatch:item];
    else if ([item isKindOfClass:[VCValueItem class]]) [cell configureWithValue:item];
    else if ([item isKindOfClass:[VCHookItem class]])  [cell configureWithHook:item];
    else if ([item isKindOfClass:[VCNetRule class]])    [cell configureWithRule:item];

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.frame = UIEdgeInsetsInsetRect(cell.frame, UIEdgeInsetsMake(4, 10, 4, 10));
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSArray *items = [self currentItems];
    if (indexPath.row >= (NSInteger)items.count) return;
    id item = items[indexPath.row];

    [self showEditorForItem:item createsItem:NO];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
               trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:VCTextLiteral(@"Delete")
                          handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSArray *items = [self currentItems];
        if (indexPath.row < (NSInteger)items.count) {
            NSString *itemID = [self itemIDForItem:items[indexPath.row]];
            [[VCPatchManager shared] removeItemByID:itemID];
        }
        completionHandler(YES);
    }];
    deleteAction.backgroundColor = kVCRed;
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

#pragma mark - VCPatchCellDelegate

- (void)patchCell:(VCPatchCell *)cell didToggleEnabled:(BOOL)enabled {
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    if (!ip) return;

    NSArray *items = [self currentItems];
    if (ip.row >= (NSInteger)items.count) return;

    NSString *itemID = [self itemIDForItem:items[ip.row]];
    if (enabled) [[VCPatchManager shared] enableItem:itemID];
    else [[VCPatchManager shared] disableItem:itemID];
}

#pragma mark - Inline Editor

- (void)setupEditorOverlay {
    _editorOverlay = [[UIView alloc] init];
    _editorOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    _editorOverlay.alpha = 0.0;
    _editorOverlay.hidden = YES;
    _editorOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_editorOverlay];

    UIControl *backdrop = [[UIControl alloc] init];
    backdrop.backgroundColor = [UIColor clearColor];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addTarget:self action:@selector(hideEditorOverlay) forControlEvents:UIControlEventTouchUpInside];
    [_editorOverlay addSubview:backdrop];

    _editorCard = [[UIView alloc] init];
    _editorCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    _editorCard.layer.cornerRadius = 18.0;
    _editorCard.layer.borderWidth = 1.0;
    _editorCard.layer.borderColor = kVCBorder.CGColor;
    _editorCard.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorOverlay addSubview:_editorCard];

    _editorScrollView = [[UIScrollView alloc] init];
    self.editorScrollView.alwaysBounceVertical = YES;
    self.editorScrollView.showsVerticalScrollIndicator = YES;
    self.editorScrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.editorScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 11.0, *)) {
        self.editorScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [_editorCard addSubview:self.editorScrollView];

    _editorContentView = [[UIView alloc] init];
    self.editorContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorScrollView addSubview:self.editorContentView];

    _editorTitleLabel = [[UILabel alloc] init];
    _editorTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    _editorTitleLabel.textColor = kVCTextPrimary;
    _editorTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorContentView addSubview:_editorTitleLabel];

    _editorHintLabel = [[UILabel alloc] init];
    _editorHintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _editorHintLabel.textColor = kVCTextSecondary;
    _editorHintLabel.numberOfLines = 2;
    _editorHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorContentView addSubview:_editorHintLabel];

    _editorErrorLabel = [[UILabel alloc] init];
    _editorErrorLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _editorErrorLabel.textColor = kVCRed;
    _editorErrorLabel.numberOfLines = 0;
    _editorErrorLabel.hidden = YES;
    _editorErrorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorContentView addSubview:_editorErrorLabel];

    _editorField1Label = [self editorFieldLabel];
    _editorField2Label = [self editorFieldLabel];
    _editorField3Label = [self editorFieldLabel];
    _editorField4Label = [self editorFieldLabel];
    _editorField5Label = [self editorFieldLabel];
    _editorPayloadLabel = [self editorFieldLabel];

    _editorField1 = [self editorField];
    _editorField2 = [self editorField];
    _editorField3 = [self editorField];
    _editorField4 = [self editorField];
    _editorTypeControl = [[UISegmentedControl alloc] initWithItems:@[@"Type"]];
    _editorTypeControl.selectedSegmentTintColor = kVCAccent;
    [_editorTypeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [_editorTypeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    _editorTypeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorTypeControl.heightAnchor constraintEqualToConstant:32].active = YES;

    _editorPayloadView = [[UITextView alloc] init];
    _editorPayloadView.font = kVCFontMonoSm;
    _editorPayloadView.textColor = kVCTextPrimary;
    _editorPayloadView.backgroundColor = kVCBgInput;
    _editorPayloadView.layer.cornerRadius = 12.0;
    _editorPayloadView.layer.borderWidth = 1.0;
    _editorPayloadView.layer.borderColor = kVCBorder.CGColor;
    _editorPayloadView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    _editorPayloadView.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorPayloadView.heightAnchor constraintGreaterThanOrEqualToConstant:88].active = YES;

    UIStackView *fieldStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        _editorField1Label, _editorField1,
        _editorField2Label, _editorField2,
        _editorField3Label, _editorTypeControl,
        _editorField4Label, _editorField3,
        _editorField5Label, _editorField4,
        _editorPayloadLabel, _editorPayloadView
    ]];
    fieldStack.axis = UILayoutConstraintAxisVertical;
    fieldStack.spacing = 8;
    fieldStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorContentView addSubview:fieldStack];

    _editorCancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_editorCancelButton setTitle:VCTextLiteral(@"Cancel") forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(_editorCancelButton);
    _editorCancelButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _editorCancelButton.titleLabel.minimumScaleFactor = 0.76;
    _editorCancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorCancelButton addTarget:self action:@selector(hideEditorOverlay) forControlEvents:UIControlEventTouchUpInside];
    [_editorContentView addSubview:_editorCancelButton];

    _editorPrimaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_editorPrimaryButton setTitle:VCTextLiteral(@"Save") forState:UIControlStateNormal];
    VCApplyPrimaryButtonStyle(_editorPrimaryButton);
    _editorPrimaryButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _editorPrimaryButton.titleLabel.minimumScaleFactor = 0.76;
    _editorPrimaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorPrimaryButton addTarget:self action:@selector(saveEditor) forControlEvents:UIControlEventTouchUpInside];
    [_editorContentView addSubview:_editorPrimaryButton];

    self.editorCardLeadingConstraint = [_editorCard.leadingAnchor constraintEqualToAnchor:_editorOverlay.leadingAnchor constant:10.0];
    self.editorCardTopConstraint = [_editorCard.topAnchor constraintEqualToAnchor:_editorOverlay.topAnchor constant:10.0];
    self.editorCardWidthConstraint = [_editorCard.widthAnchor constraintEqualToConstant:320.0];
    self.editorCardHeightConstraint = [_editorCard.heightAnchor constraintEqualToConstant:420.0];

    [NSLayoutConstraint activateConstraints:@[
        [_editorOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_editorOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_editorOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_editorOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [backdrop.topAnchor constraintEqualToAnchor:_editorOverlay.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:_editorOverlay.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:_editorOverlay.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:_editorOverlay.bottomAnchor],

        self.editorCardLeadingConstraint,
        self.editorCardTopConstraint,
        self.editorCardWidthConstraint,
        self.editorCardHeightConstraint,

        [_editorScrollView.topAnchor constraintEqualToAnchor:_editorCard.topAnchor],
        [_editorScrollView.leadingAnchor constraintEqualToAnchor:_editorCard.leadingAnchor],
        [_editorScrollView.trailingAnchor constraintEqualToAnchor:_editorCard.trailingAnchor],
        [_editorScrollView.bottomAnchor constraintEqualToAnchor:_editorCard.bottomAnchor],

        [_editorContentView.topAnchor constraintEqualToAnchor:_editorScrollView.contentLayoutGuide.topAnchor],
        [_editorContentView.leadingAnchor constraintEqualToAnchor:_editorScrollView.contentLayoutGuide.leadingAnchor],
        [_editorContentView.trailingAnchor constraintEqualToAnchor:_editorScrollView.contentLayoutGuide.trailingAnchor],
        [_editorContentView.bottomAnchor constraintEqualToAnchor:_editorScrollView.contentLayoutGuide.bottomAnchor],
        [_editorContentView.widthAnchor constraintEqualToAnchor:_editorScrollView.frameLayoutGuide.widthAnchor],

        [_editorTitleLabel.topAnchor constraintEqualToAnchor:_editorContentView.topAnchor constant:14],
        [_editorTitleLabel.leadingAnchor constraintEqualToAnchor:_editorContentView.leadingAnchor constant:14],
        [_editorTitleLabel.trailingAnchor constraintEqualToAnchor:_editorContentView.trailingAnchor constant:-14],

        [_editorHintLabel.topAnchor constraintEqualToAnchor:_editorTitleLabel.bottomAnchor constant:4],
        [_editorHintLabel.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [_editorHintLabel.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],

        [_editorErrorLabel.topAnchor constraintEqualToAnchor:_editorHintLabel.bottomAnchor constant:6],
        [_editorErrorLabel.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [_editorErrorLabel.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],

        [fieldStack.topAnchor constraintEqualToAnchor:_editorErrorLabel.bottomAnchor constant:10],
        [fieldStack.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [fieldStack.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],

        [_editorCancelButton.topAnchor constraintEqualToAnchor:fieldStack.bottomAnchor constant:14],
        [_editorCancelButton.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [_editorCancelButton.heightAnchor constraintEqualToConstant:40],
        [_editorCancelButton.bottomAnchor constraintEqualToAnchor:_editorContentView.bottomAnchor constant:-14],

        [_editorPrimaryButton.leadingAnchor constraintEqualToAnchor:_editorCancelButton.trailingAnchor constant:10],
        [_editorPrimaryButton.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],
        [_editorPrimaryButton.widthAnchor constraintEqualToAnchor:_editorCancelButton.widthAnchor],
        [_editorPrimaryButton.centerYAnchor constraintEqualToAnchor:_editorCancelButton.centerYAnchor],
        [_editorPrimaryButton.heightAnchor constraintEqualToAnchor:_editorCancelButton.heightAnchor],
    ]];
}

- (UITextField *)editorField {
    UITextField *field = [[UITextField alloc] init];
    field.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    field.textColor = kVCTextPrimary;
    field.backgroundColor = kVCBgInput;
    field.layer.cornerRadius = 12.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = kVCBorder.CGColor;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    field.leftViewMode = UITextFieldViewModeAlways;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    VCApplyReadablePlaceholder(field, @"");
    [field.heightAnchor constraintEqualToConstant:38].active = YES;
    return field;
}

- (UILabel *)editorFieldLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    label.textColor = kVCTextSecondary;
    label.numberOfLines = 1;
    return label;
}

- (NSString *)editorHintForSegment:(NSInteger)segment {
    switch (segment) {
        case 0:
            return @"Patch form: class + selector + patch type + optional swizzle target / remark.";
        case 1:
            return @"Value form: target + address + value type + modified value. Invalid addresses are blocked before save.";
        case 2:
            return @"Hook form: class + selector + hook type + optional note.";
        case 3:
            return @"Rule form: pattern + action + note + JSON payload. Payload is required for header/body/delay rules.";
        default:
            return @"Edit in place, then tap Save.";
    }
}

- (void)setEditorError:(NSString *)message {
    self.editorErrorLabel.text = message ?: @"";
    self.editorErrorLabel.hidden = (message.length == 0);
}

- (NSArray<NSString *> *)editorTypeItemsForSegment:(NSInteger)segment {
    switch (segment) {
        case 0: return @[@"nop", @"yes", @"no", @"custom", @"swizzle"];
        case 1: return @[@"int", @"float", @"BOOL", @"double", @"NSString"];
        case 2: return @[@"log"];
        case 3: return @[@"block", @"header", @"body", @"delay"];
        default: return @[];
    }
}

- (NSString *)_rawTypeValueFromDisplay:(NSString *)display segment:(NSInteger)segment {
    if (segment == 0) {
        if ([display isEqualToString:@"yes"]) return @"return_yes";
        if ([display isEqualToString:@"no"]) return @"return_no";
    }
    if (segment == 3) {
        if ([display isEqualToString:@"header"]) return @"modify_header";
        if ([display isEqualToString:@"body"]) return @"modify_body";
    }
    return display ?: @"";
}

- (NSString *)_displayTypeValueFromRaw:(NSString *)raw segment:(NSInteger)segment {
    if (segment == 0) {
        if ([raw isEqualToString:@"return_yes"]) return @"yes";
        if ([raw isEqualToString:@"return_no"]) return @"no";
    }
    if (segment == 3) {
        if ([raw isEqualToString:@"modify_header"]) return @"header";
        if ([raw isEqualToString:@"modify_body"]) return @"body";
    }
    return raw ?: @"";
}

- (void)_configureTypeControlForSegment:(NSInteger)segment selectedRawValue:(NSString *)rawValue {
    NSArray<NSString *> *items = [self editorTypeItemsForSegment:segment];
    [self.editorTypeControl removeAllSegments];
    NSString *displayValue = [self _displayTypeValueFromRaw:rawValue segment:segment];
    NSInteger selectedIndex = 0;
    for (NSUInteger idx = 0; idx < items.count; idx++) {
        [self.editorTypeControl insertSegmentWithTitle:items[idx] atIndex:idx animated:NO];
        if ([items[idx] isEqualToString:displayValue]) {
            selectedIndex = (NSInteger)idx;
        }
    }
    self.editorTypeControl.selectedSegmentIndex = items.count > 0 ? selectedIndex : UISegmentedControlNoSegment;
}

- (NSString *)_selectedTypeValue {
    NSInteger index = self.editorTypeControl.selectedSegmentIndex;
    NSArray<NSString *> *items = [self editorTypeItemsForSegment:self.segmentControl.selectedSegmentIndex];
    if (index < 0 || index >= (NSInteger)items.count) return @"";
    return [self _rawTypeValueFromDisplay:items[index] segment:self.segmentControl.selectedSegmentIndex];
}

- (void)applyEditorStateForItem:(id)item {
    NSArray<UITextField *> *fields = @[_editorField1, _editorField2, _editorField3, _editorField4];
    NSArray<UILabel *> *labels = @[_editorField1Label, _editorField2Label, _editorField4Label, _editorField5Label];
    for (UITextField *field in fields) {
        field.hidden = NO;
        field.text = @"";
        field.keyboardType = UIKeyboardTypeDefault;
        field.secureTextEntry = NO;
    }
    for (UILabel *label in labels) {
        label.hidden = NO;
    }
    self.editorPayloadLabel.hidden = YES;
    self.editorPayloadView.hidden = YES;
    self.editorPayloadView.text = @"";
    self.editorTypeControl.hidden = NO;
    self.editorField3Label.text = VCTextLiteral(@"Type");
    self.editorHintLabel.text = [self editorHintForSegment:self.segmentControl.selectedSegmentIndex];
    [self setEditorError:nil];

    NSInteger segment = self.segmentControl.selectedSegmentIndex;
    if (segment == 0) {
        self.editorField1Label.text = VCTextLiteral(@"Target Class");
        self.editorField2Label.text = VCTextLiteral(@"Selector");
        self.editorField4Label.text = VCTextLiteral(@"Swizzle Target");
        self.editorField5Label.text = VCTextLiteral(@"Remark");
        self.editorField1.placeholder = @"UIViewController";
        self.editorField2.placeholder = @"viewDidAppear:";
        self.editorField3.placeholder = @"OtherClass otherSelector: (only for swizzle)";
        self.editorField4.placeholder = VCTextLiteral(@"Why this patch exists");
        VCApplyReadablePlaceholder(self.editorField1, self.editorField1.placeholder);
        VCApplyReadablePlaceholder(self.editorField2, self.editorField2.placeholder);
        VCApplyReadablePlaceholder(self.editorField3, self.editorField3.placeholder);
        VCApplyReadablePlaceholder(self.editorField4, self.editorField4.placeholder);
        VCPatchItem *patch = [item isKindOfClass:[VCPatchItem class]] ? item : nil;
        [self _configureTypeControlForSegment:segment selectedRawValue:(patch.patchType ?: @"nop")];
        self.editorField1.text = patch.className ?: @"";
        self.editorField2.text = patch.selector ?: @"";
        self.editorField4.text = patch.remark ?: @"";
        if (patch.customCode.length > 0) {
            NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:[patch.customCode dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if ([metadata isKindOfClass:[NSDictionary class]]) {
                NSString *otherClass = metadata[@"otherClassName"] ?: metadata[@"targetClass"] ?: @"";
                NSString *otherSelector = metadata[@"otherSelector"] ?: metadata[@"targetSelector"] ?: @"";
                if (otherClass.length > 0 && otherSelector.length > 0) {
                    self.editorField3.text = [NSString stringWithFormat:@"%@ %@", otherClass, otherSelector];
                }
            }
        }
    } else if (segment == 1) {
        self.editorField1Label.text = VCTextLiteral(@"Target");
        self.editorField2Label.text = VCTextLiteral(@"Address");
        self.editorField4Label.text = VCTextLiteral(@"Modified Value");
        self.editorField5Label.text = VCTextLiteral(@"Remark");
        self.editorField1.placeholder = @"AuthManager._token";
        self.editorField2.placeholder = @"0x1234 or decimal";
        self.editorField3.placeholder = @"42";
        self.editorField4.placeholder = VCTextLiteral(@"Optional note");
        VCApplyReadablePlaceholder(self.editorField1, self.editorField1.placeholder);
        VCApplyReadablePlaceholder(self.editorField2, self.editorField2.placeholder);
        VCApplyReadablePlaceholder(self.editorField3, self.editorField3.placeholder);
        VCApplyReadablePlaceholder(self.editorField4, self.editorField4.placeholder);
        self.editorField2.keyboardType = UIKeyboardTypeASCIICapable;
        VCValueItem *value = [item isKindOfClass:[VCValueItem class]] ? item : nil;
        [self _configureTypeControlForSegment:segment selectedRawValue:(value.dataType ?: @"int")];
        self.editorField1.text = value.targetDesc ?: @"";
        self.editorField2.text = value.address ? [NSString stringWithFormat:@"0x%llx", (unsigned long long)value.address] : @"";
        self.editorField3.text = value.modifiedValue ?: @"";
        self.editorField4.text = value.remark ?: @"";
    } else if (segment == 2) {
        self.editorField1Label.text = VCTextLiteral(@"Target Class");
        self.editorField2Label.text = VCTextLiteral(@"Selector");
        self.editorField4Label.text = VCTextLiteral(@"Remark");
        self.editorField5Label.hidden = YES;
        self.editorField4.hidden = YES;
        self.editorField1.placeholder = @"UIViewController";
        self.editorField2.placeholder = @"viewDidAppear:";
        self.editorField3.placeholder = VCTextLiteral(@"Optional note");
        VCApplyReadablePlaceholder(self.editorField1, self.editorField1.placeholder);
        VCApplyReadablePlaceholder(self.editorField2, self.editorField2.placeholder);
        VCApplyReadablePlaceholder(self.editorField3, self.editorField3.placeholder);
        VCHookItem *hook = [item isKindOfClass:[VCHookItem class]] ? item : nil;
        [self _configureTypeControlForSegment:segment selectedRawValue:(hook.hookType ?: @"log")];
        self.editorField1.text = hook.className ?: @"";
        self.editorField2.text = hook.selector ?: @"";
        self.editorField3.text = hook.remark ?: @"";
    } else {
        self.editorField1Label.text = VCTextLiteral(@"URL Pattern");
        self.editorField2Label.text = VCTextLiteral(@"Remark");
        self.editorField4Label.hidden = YES;
        self.editorField5Label.hidden = YES;
        self.editorField3.hidden = YES;
        self.editorField4.hidden = YES;
        self.editorField1.placeholder = @"https://api.example.com/path*";
        self.editorField2.placeholder = VCTextLiteral(@"Rule note / source");
        VCApplyReadablePlaceholder(self.editorField1, self.editorField1.placeholder);
        VCApplyReadablePlaceholder(self.editorField2, self.editorField2.placeholder);
        self.editorPayloadLabel.hidden = NO;
        self.editorPayloadView.hidden = NO;
        self.editorPayloadLabel.text = VCTextLiteral(@"Rule Payload (JSON object)");
        VCNetRule *rule = [item isKindOfClass:[VCNetRule class]] ? item : nil;
        [self _configureTypeControlForSegment:segment selectedRawValue:(rule.action ?: @"block")];
        self.editorField1.text = rule.urlPattern ?: @"";
        self.editorField2.text = rule.remark ?: @"";
        if (rule.modifications.count > 0) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:rule.modifications options:NSJSONWritingPrettyPrinted error:nil];
            self.editorPayloadView.text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
        }
    }
}

- (void)showEditorForItem:(id)item createsItem:(BOOL)createsItem {
    self.editingItem = item;
    self.editorCreatesItem = createsItem;
    self.editorTitleLabel.text = createsItem ? @"Create Item" : @"Edit Item";
    [self.editorPrimaryButton setTitle:(createsItem ? @"Create" : @"Save") forState:UIControlStateNormal];
    [self setEditorError:nil];
    [self applyEditorStateForItem:item];

    self.editorOverlay.hidden = NO;
    [self.view bringSubviewToFront:self.editorOverlay];
    [self _layoutEditorOverlay];
    [UIView animateWithDuration:0.2 animations:^{
        self.editorOverlay.alpha = 1.0;
        self.editorOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.22];
    }];
}

- (void)hideEditorOverlay {
    [self.view endEditing:YES];
    [UIView animateWithDuration:0.18 animations:^{
        self.editorOverlay.alpha = 0.0;
        self.editorOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    } completion:^(BOOL finished) {
        self.editorOverlay.hidden = YES;
    }];
}

- (NSDictionary *)editorModificationPayloadWithError:(NSString **)errorMessage {
    NSString *jsonString = [self.editorPayloadView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (jsonString.length == 0) return nil;
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError] : nil;
    if (!json) {
        if (errorMessage) *errorMessage = jsonError.localizedDescription ?: @"Invalid JSON payload";
        return nil;
    }
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (errorMessage) *errorMessage = @"Rule payload must be a JSON object";
        return nil;
    }
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (BOOL)parsedAddressFromString:(NSString *)stringValue outValue:(uintptr_t *)outValue error:(NSString **)errorMessage {
    NSString *raw = [stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) {
        if (outValue) *outValue = 0;
        return YES;
    }
    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:raw];
    BOOL parsed = NO;
    if ([raw hasPrefix:@"0x"] || [raw hasPrefix:@"0X"]) {
        [scanner setScanLocation:2];
        parsed = [scanner scanHexLongLong:&value];
    } else if ([scanner scanUnsignedLongLong:&value]) {
        parsed = YES;
    } else {
        NSScanner *hexScanner = [NSScanner scannerWithString:raw];
        parsed = [hexScanner scanHexLongLong:&value];
    }
    if (!parsed) {
        if (errorMessage) *errorMessage = @"Address must be hex like 0x1234 or a decimal number";
        return NO;
    }
    if (outValue) *outValue = (uintptr_t)value;
    return YES;
}

- (BOOL)isValidPatchType:(NSString *)patchType {
    NSSet *allowed = [NSSet setWithArray:@[@"nop", @"return_yes", @"return_no", @"custom", @"swizzle"]];
    return [allowed containsObject:patchType.lowercaseString];
}

- (BOOL)isValidHookType:(NSString *)hookType {
    NSSet *allowed = [NSSet setWithArray:@[@"log"]];
    return [allowed containsObject:hookType.lowercaseString];
}

- (BOOL)isValidRuleAction:(NSString *)action {
    NSSet *allowed = [NSSet setWithArray:@[@"block", @"modify_header", @"modify_body", @"delay"]];
    return [allowed containsObject:action.lowercaseString];
}

- (void)saveEditor {
    NSInteger segment = _segmentControl.selectedSegmentIndex;
    NSString *field1 = [self.editorField1.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *field2 = [self.editorField2.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *field3 = [self.editorField3.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *field4 = [self.editorField4.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *selectedType = [self _selectedTypeValue];
    VCPatchManager *manager = [VCPatchManager shared];
    [self setEditorError:nil];

    if (segment == 0) {
        VCPatchItem *item = [self.editingItem isKindOfClass:[VCPatchItem class]] ? self.editingItem : [[VCPatchItem alloc] init];
        if (field1.length == 0 || field2.length == 0) {
            [self setEditorError:@"Class name and selector are required for patches."];
            return;
        }
        NSString *patchType = selectedType.length > 0 ? selectedType : @"nop";
        if (![self isValidPatchType:patchType]) {
            [self setEditorError:@"Patch type must be nop, return_yes, return_no, custom, or swizzle."];
            return;
        }
        NSDictionary *existingMetadata = [NSJSONSerialization JSONObjectWithData:[item.customCode dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSMutableDictionary *metadata = [existingMetadata isKindOfClass:[NSDictionary class]] ? [existingMetadata mutableCopy] : [NSMutableDictionary new];
        if ([patchType isEqualToString:@"swizzle"]) {
            NSArray<NSString *> *parts = [field3 componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSPredicate *nonEmpty = [NSPredicate predicateWithBlock:^BOOL(NSString *evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
                return evaluatedObject.length > 0;
            }];
            parts = [parts filteredArrayUsingPredicate:nonEmpty];
            if (parts.count < 2) {
                [self setEditorError:@"Swizzle target must be entered as `OtherClass otherSelector:`."];
                return;
            }
            metadata[@"otherClassName"] = parts[0];
            metadata[@"otherSelector"] = parts[1];
            metadata[@"isClassMethod"] = metadata[@"isClassMethod"] ?: @NO;
            metadata[@"otherIsClassMethod"] = metadata[@"otherIsClassMethod"] ?: @NO;
        }
        item.className = field1;
        item.selector = field2;
        item.patchType = patchType;
        item.remark = field4;
        item.customCode = metadata.count > 0 ? ([[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:metadata options:0 error:nil] encoding:NSUTF8StringEncoding] ?: @"") : nil;
        item.source = VCItemSourceManual;
        if (self.editorCreatesItem) [manager addPatch:item];
        else [manager updateItem:item];
        self.statusLabel.text = [NSString stringWithFormat:@"Saved patch %@ %@", item.className, item.selector];
    } else if (segment == 1) {
        VCValueItem *item = [self.editingItem isKindOfClass:[VCValueItem class]] ? self.editingItem : [[VCValueItem alloc] init];
        if (field1.length == 0) {
            [self setEditorError:@"Target description is required for value locks."];
            return;
        }
        uintptr_t parsedAddress = 0;
        NSString *addressError = nil;
        if (![self parsedAddressFromString:field2 outValue:&parsedAddress error:&addressError]) {
            [self setEditorError:addressError];
            return;
        }
        if (field3.length == 0) {
            [self setEditorError:@"Modified value is required for value locks."];
            return;
        }
        item.targetDesc = field1;
        item.address = parsedAddress;
        item.dataType = selectedType.length > 0 ? selectedType : @"int";
        item.modifiedValue = field3;
        item.remark = field4;
        item.source = VCItemSourceManual;
        if (self.editorCreatesItem) [manager addValue:item];
        else [manager updateItem:item];
        self.statusLabel.text = [NSString stringWithFormat:@"Saved value lock %@", item.targetDesc];
    } else if (segment == 2) {
        VCHookItem *item = [self.editingItem isKindOfClass:[VCHookItem class]] ? self.editingItem : [[VCHookItem alloc] init];
        if (field1.length == 0 || field2.length == 0) {
            [self setEditorError:@"Class name and selector are required for hooks."];
            return;
        }
        NSString *hookType = selectedType.length > 0 ? selectedType : @"log";
        if (![self isValidHookType:hookType]) {
            [self setEditorError:@"Hook type must currently be log."];
            return;
        }
        item.className = field1;
        item.selector = field2;
        item.hookType = hookType;
        item.remark = field3;
        item.source = VCItemSourceManual;
        if (self.editorCreatesItem) [manager addHook:item];
        else [manager updateItem:item];
        self.statusLabel.text = [NSString stringWithFormat:@"Saved hook %@ %@", item.className, item.selector];
    } else {
        VCNetRule *item = [self.editingItem isKindOfClass:[VCNetRule class]] ? self.editingItem : [[VCNetRule alloc] init];
        if (field1.length == 0) {
            [self setEditorError:@"URL pattern is required for rules."];
            return;
        }
        NSString *action = selectedType.lowercaseString;
        if (![self isValidRuleAction:action]) {
            [self setEditorError:@"Rule action must be block, modify_header, modify_body, or delay."];
            return;
        }
        NSString *payloadError = nil;
        NSDictionary *payload = [self editorModificationPayloadWithError:&payloadError];
        if (payloadError.length > 0) {
            [self setEditorError:payloadError];
            return;
        }
        if ([action isEqualToString:@"modify_header"] || [action isEqualToString:@"modify_body"] || [action isEqualToString:@"delay"]) {
            if (self.editorPayloadView.text.length == 0) {
                [self setEditorError:@"This rule action needs a JSON payload."];
                return;
            }
        }
        item.urlPattern = field1;
        item.action = action;
        item.remark = field2;
        item.modifications = payload;
        item.source = VCItemSourceManual;
        if (self.editorCreatesItem) [manager addRule:item];
        else [manager updateItem:item];
        self.statusLabel.text = [NSString stringWithFormat:@"Saved %@ rule for %@", item.action, item.urlPattern];
    }

    [self hideEditorOverlay];
    [self refreshUI];
}

#pragma mark - Add

- (void)addTapped {
    [self showEditorForItem:nil createsItem:YES];
}

@end
