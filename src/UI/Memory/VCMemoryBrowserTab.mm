/**
 * VCMemoryBrowserTab -- native memory browser + scan workspace
 */

#import "VCMemoryBrowserTab.h"
#import "../../../VansonCLI.h"
#import "../../Core/VCConfig.h"
#import "../../Memory/VCMemoryBrowserEngine.h"
#import "../../Memory/VCMemoryLocatorEngine.h"
#import "../../Memory/VCMemoryScanEngine.h"
#import "../../AI/Chat/VCChatSession.h"
#import "../../AI/ToolCall/VCToolCallParser.h"
#import "../../Patches/VCValueItem.h"
#import "../Chat/VCToolCallBlock.h"
#import "../Patches/VCPatchesTab.h"
#import "../Settings/VCSettingsTab.h"
#import "../Base/VCOverlayRootViewController.h"
#import "../Base/VCOverlayTrackingManager.h"
#import "../../Vendor/MemoryBackend/Engine/VCMemEngine.h"

static NSString *VCMemoryBrowserSafeString(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return (NSString *)value;
}

static NSString *VCMemoryBrowserPrettyJSONString(id object) {
    if (!object || ![NSJSONSerialization isValidJSONObject:object]) return @"";
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    if (![data isKindOfClass:[NSData class]]) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *VCMemoryBrowserPreviewString(id value) {
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        NSString *json = VCMemoryBrowserPrettyJSONString(value);
        return json.length > 0 ? json : [value description];
    }
    return value ? [value description] : @"";
}

static NSString *VCMemoryBrowserSizeText(id value) {
    unsigned long long bytes = [value respondsToSelector:@selector(unsignedLongLongValue)] ? [value unsignedLongLongValue] : 0;
    if (bytes >= 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    if (bytes >= 1024) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%@ B", @(bytes)];
}

static NSString *VCMemoryBrowserFormattedDetail(NSDictionary *payload) {
    if (![payload isKindOfClass:[NSDictionary class]] || payload.count == 0) {
        return VCTextLiteral(@"Typed previews, region metadata, and stable navigation details will appear here once a page is loaded.");
    }
    NSString *address = VCMemoryBrowserSafeString(payload[@"address"]);
    NSString *moduleName = VCMemoryBrowserSafeString(payload[@"moduleName"]);
    NSString *rva = VCMemoryBrowserSafeString(payload[@"rva"]);
    NSDictionary *region = [payload[@"region"] isKindOfClass:[NSDictionary class]] ? payload[@"region"] : @{};
    NSDictionary *typedPreview = [payload[@"typedPreview"] isKindOfClass:[NSDictionary class]] ? payload[@"typedPreview"] : @{};
    NSString *asciiPreview = VCMemoryBrowserSafeString(payload[@"asciiPreview"]);
    NSDictionary *session = [payload[@"session"] isKindOfClass:[NSDictionary class]] ? payload[@"session"] : @{};

    NSMutableString *text = [NSMutableString new];
    [text appendFormat:@"%@\n", VCTextLiteral(@"ADDRESS")];
    [text appendFormat:@"Runtime: %@\n", address.length ? address : @"--"];
    [text appendFormat:@"Module: %@\n", moduleName.length ? moduleName : @"--"];
    [text appendFormat:@"RVA: %@\n", rva.length ? rva : @"--"];
    [text appendFormat:@"Region: %@ - %@\n", VCMemoryBrowserSafeString(region[@"start"]), VCMemoryBrowserSafeString(region[@"end"])];
    [text appendFormat:@"Size: %@  Protection: %@\n\n", VCMemoryBrowserSizeText(region[@"size"]), VCMemoryBrowserSafeString(region[@"protection"]).length ? VCMemoryBrowserSafeString(region[@"protection"]) : @"---"];

    [text appendFormat:@"%@\n", VCTextLiteral(@"TYPED VALUES")];
    NSArray<NSString *> *orderedKeys = @[ @"int8", @"uint8", @"int16", @"uint16", @"int32", @"uint32", @"int64", @"uint64", @"float", @"double" ];
    for (NSString *key in orderedKeys) {
        NSString *value = VCMemoryBrowserPreviewString(typedPreview[key]);
        if (value.length > 0) [text appendFormat:@"%@: %@\n", key, value];
    }
    NSDictionary *pointer = [typedPreview[@"pointer"] isKindOfClass:[NSDictionary class]] ? typedPreview[@"pointer"] : nil;
    if (pointer) {
        [text appendFormat:@"pointer: %@  %@ %@\n",
         VCMemoryBrowserSafeString(pointer[@"value"]),
         [pointer[@"readable"] boolValue] ? VCTextLiteral(@"readable") : VCTextLiteral(@"unreadable"),
         VCMemoryBrowserSafeString(pointer[@"protection"])];
    }

    [text appendFormat:@"\n%@\n%@\n\n", VCTextLiteral(@"ASCII"), asciiPreview.length ? asciiPreview : @"--"];
    [text appendFormat:@"%@\nPrev: %@\nNext: %@\n",
     VCTextLiteral(@"NAVIGATION"),
     VCMemoryBrowserSafeString(payload[@"prevAddress"]),
     VCMemoryBrowserSafeString(payload[@"nextAddress"])];
    if (session.count > 0) {
        [text appendFormat:@"\n%@\nSession: %@\nPage: %@\n",
         VCTextLiteral(@"SESSION"),
         VCMemoryBrowserSafeString(session[@"sessionID"]),
         VCMemoryBrowserPreviewString(session[@"pageSize"])];
    }
    return text;
}

static UILabel *VCMemoryBrowserSectionLabel(NSString *text) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = kVCTextSecondary;
    label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    return label;
}

static NSString *VCMemoryBrowserReadableScanType(NSString *type) {
    NSDictionary<NSString *, NSString *> *labels = @{
        @"int_auto": VCTextLiteral(@"Auto"),
        @"int32": VCTextLiteral(@"Int"),
        @"float": VCTextLiteral(@"Float"),
        @"double": VCTextLiteral(@"Double"),
        @"string": VCTextLiteral(@"String")
    };
    NSString *label = labels[[VCMemoryBrowserSafeString(type) lowercaseString]];
    return label ?: VCTextLiteral(@"Auto");
}

NSNotificationName const VCMemoryBrowserRequestOpenAddressNotification = @"VCMemoryBrowserRequestOpenAddressNotification";
NSString *const VCMemoryBrowserOpenAddressKey = @"address";

@interface VCMemoryBrowserTab () <UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate, VCPanelLayoutUpdatable>
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextField *addressField;
@property (nonatomic, strong) UIButton *goButton;
@property (nonatomic, strong) UISegmentedControl *pageSizeControl;
@property (nonatomic, strong) UIStackView *actionRow;
@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *clipboardButton;
@property (nonatomic, strong) UIButton *locateButton;
@property (nonatomic, strong) UIButton *writeButton;
@property (nonatomic, strong) UIButton *sendToAIButton;
@property (nonatomic, strong) UIView *writeDock;
@property (nonatomic, strong) UIView *writeDockHandle;
@property (nonatomic, strong) UIButton *writeDockButton;
@property (nonatomic, strong) NSLayoutConstraint *writeDockWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *writeDockHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *writeDockLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *writeDockTopConstraint;
@property (nonatomic, strong) UIView *writeOverlay;
@property (nonatomic, strong) UIControl *writeBackdrop;
@property (nonatomic, strong) UIView *writeDrawerCard;
@property (nonatomic, strong) UIView *writeDrawerHandle;
@property (nonatomic, strong) UILabel *writeDrawerTitleLabel;
@property (nonatomic, strong) UILabel *writeDrawerSubtitleLabel;
@property (nonatomic, strong) UIButton *writeValueActionButton;
@property (nonatomic, strong) UIButton *lockValueActionButton;
@property (nonatomic, strong) UIButton *writeBytesActionButton;
@property (nonatomic, strong) UIButton *writeDrawerCloseButton;
@property (nonatomic, strong) UIStackView *writeActionStack;
@property (nonatomic, strong) NSLayoutConstraint *writeDrawerCardWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *writeDrawerCardHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *writeDrawerCardLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *writeDrawerCardTopConstraint;

@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIView *contentDividerView;
@property (nonatomic, strong) UIView *hexCard;
@property (nonatomic, strong) UILabel *hexTitleLabel;
@property (nonatomic, strong) UILabel *hexSubtitleLabel;
@property (nonatomic, strong) UITextView *hexTextView;

@property (nonatomic, strong) UIView *detailCard;
@property (nonatomic, strong) UILabel *detailTitleLabel;
@property (nonatomic, strong) UILabel *detailSubtitleLabel;
@property (nonatomic, strong) UISegmentedControl *detailModeControl;
@property (nonatomic, strong) UITextView *detailTextView;
@property (nonatomic, strong) UIView *scanContainer;
@property (nonatomic, strong) UILabel *scanStatusLabel;
@property (nonatomic, strong) UISegmentedControl *scanModeControl;
@property (nonatomic, strong) UITextField *scanValueField;
@property (nonatomic, strong) UITextField *scanSecondaryField;
@property (nonatomic, strong) UIButton *scanTypeButton;
@property (nonatomic, strong) UIStackView *scanFieldRow;
@property (nonatomic, strong) UIStackView *scanActionRow;
@property (nonatomic, strong) UIButton *scanStartButton;
@property (nonatomic, strong) UIButton *scanRefineButton;
@property (nonatomic, strong) UIButton *scanResultsButton;
@property (nonatomic, strong) UIButton *scanResumeButton;
@property (nonatomic, strong) UIButton *scanClearButton;
@property (nonatomic, strong) UITableView *scanResultsTable;
@property (nonatomic, strong) UILabel *scanEmptyLabel;
@property (nonatomic, strong) NSLayoutConstraint *scanTypeWidthConstraint;

@property (nonatomic, strong) NSLayoutConstraint *contentTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *detailWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *pageSizeTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *pageLabelCenterYConstraint;
@property (nonatomic, strong) NSLayoutConstraint *actionRowTopConstraint;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@property (nonatomic, assign) CGRect availableLayoutBounds;
@property (nonatomic, strong) NSDictionary *currentPayload;
@property (nonatomic, strong) NSDictionary *currentLocatorPayload;
@property (nonatomic, copy) NSString *currentLocatorTitle;
@property (nonatomic, copy) NSString *currentLocatorSubtitle;
@property (nonatomic, copy) NSArray<NSDictionary *> *scanCandidates;
@property (nonatomic, copy) NSString *selectedScanType;
@end

@implementation VCMemoryBrowserTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;
    self.currentLayoutMode = VCPanelLayoutModePortrait;
    self.availableLayoutBounds = CGRectZero;
    self.selectedScanType = @"int_auto";
    self.scanCandidates = @[];

    [self _setupHeaderCard];
    [self _setupContentCards];
    [self _configureMenus];
    [self _setupWriteDockIfNeeded];
    [self _setupWriteOverlayIfNeeded];
    VCInstallKeyboardDismissAccessory(self.view);
    [self _restoreSessionIfAvailable];
    [self _restoreScanIfAvailable];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat viewWidth = CGRectGetWidth(self.view.bounds);
    CGFloat viewHeight = CGRectGetHeight(self.view.bounds);
    BOOL wideLayout = (self.currentLayoutMode == VCPanelLayoutModeLandscape || viewWidth > viewHeight) && viewWidth >= 680.0 && viewWidth > viewHeight;
    self.contentStack.axis = wideLayout ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    self.contentStack.spacing = wideLayout ? 10.0 : 8.0;
    self.detailWidthConstraint.active = wideLayout;
    self.contentDividerView.hidden = !wideLayout;
    self.contentDividerView.alpha = wideLayout ? 1.0 : 0.0;
    self.statusLabel.font = [UIFont systemFontOfSize:(wideLayout ? 10.0 : 11.0) weight:UIFontWeightSemibold];
    self.statusLabel.numberOfLines = 1;
    self.hexSubtitleLabel.numberOfLines = wideLayout ? 1 : 2;
    self.detailSubtitleLabel.numberOfLines = wideLayout ? 1 : 2;
    self.scanStatusLabel.numberOfLines = wideLayout ? 1 : 2;
    BOOL compactScanControls = !wideLayout || viewWidth < 430.0;
    self.scanFieldRow.axis = compactScanControls ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.scanFieldRow.spacing = compactScanControls ? 6.0 : 8.0;
    self.scanTypeWidthConstraint.active = !compactScanControls;
    self.scanActionRow.spacing = compactScanControls ? 6.0 : 8.0;
    if (wideLayout) {
        CGFloat boundsWidth = CGRectIsEmpty(self.availableLayoutBounds) ? viewWidth : CGRectGetWidth(self.availableLayoutBounds);
        CGFloat width = MAX(284.0, MIN(420.0, floor(boundsWidth * 0.30)));
        self.detailWidthConstraint.constant = width;
    }
    [self _layoutWriteDock];
    [self _layoutWriteOverlay];
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    self.availableLayoutBounds = bounds;
    [self.view setNeedsLayout];
}

#pragma mark - Build

- (void)_setupHeaderCard {
    self.headerCard = [[UIView alloc] init];
    VCApplyPanelSurface(self.headerCard, 12.0);
    self.headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerCard];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = VCTextLiteral(@"MEMORY WORKSPACE");
    self.titleLabel.textColor = kVCTextSecondary;
    self.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerCard addSubview:self.titleLabel];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textColor = kVCTextMuted;
    self.statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.statusLabel.textAlignment = NSTextAlignmentRight;
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.statusLabel.numberOfLines = 1;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerCard addSubview:self.statusLabel];

    UILabel *addressLabel = VCMemoryBrowserSectionLabel(VCTextLiteral(@"Address"));
    addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerCard addSubview:addressLabel];

    self.addressField = [self _inputFieldWithPlaceholder:@"0x1234abcd"];
    self.addressField.returnKeyType = UIReturnKeyGo;
    self.addressField.delegate = self;
    [self.headerCard addSubview:self.addressField];

    self.goButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Go") emphasized:YES];
    [self.goButton addTarget:self action:@selector(_goToAddress) forControlEvents:UIControlEventTouchUpInside];
    self.goButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerCard addSubview:self.goButton];

    UILabel *pageLabel = VCMemoryBrowserSectionLabel(VCTextLiteral(@"Page"));
    pageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    pageLabel.hidden = YES;
    [self.headerCard addSubview:pageLabel];

    self.pageSizeControl = [[UISegmentedControl alloc] initWithItems:@[@"128", @"256", @"512", @"1K"]];
    self.pageSizeControl.selectedSegmentIndex = 1;
    self.pageSizeControl.selectedSegmentTintColor = kVCAccent;
    [self.pageSizeControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: kVCTextPrimary,
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]
    } forState:UIControlStateNormal];
    [self.pageSizeControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: kVCBgPrimary,
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightBold]
    } forState:UIControlStateSelected];
    [self.pageSizeControl addTarget:self action:@selector(_pageSizeChanged) forControlEvents:UIControlEventValueChanged];
    self.pageSizeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerCard addSubview:self.pageSizeControl];

    self.prevButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Prev") emphasized:NO];
    VCSetButtonSymbol(self.prevButton, @"chevron.left");
    [self.prevButton addTarget:self action:@selector(_loadPrevPage) forControlEvents:UIControlEventTouchUpInside];

    self.nextButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Next") emphasized:NO];
    VCSetButtonSymbol(self.nextButton, @"chevron.right");
    [self.nextButton addTarget:self action:@selector(_loadNextPage) forControlEvents:UIControlEventTouchUpInside];

    self.clipboardButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Copy") emphasized:NO];
    VCSetButtonSymbol(self.clipboardButton, @"doc.on.doc");
    [self.clipboardButton addTarget:self action:@selector(_copyHexDump) forControlEvents:UIControlEventTouchUpInside];

    self.locateButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Locate") emphasized:NO];
    VCSetButtonSymbol(self.locateButton, @"scope");

    self.writeButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Write") emphasized:NO];
    VCSetButtonSymbol(self.writeButton, @"square.and.pencil");
    self.writeButton.hidden = YES;
    self.writeButton.alpha = 0.0;

    self.sendToAIButton = [self _utilityButtonWithTitle:VCTextLiteral(@"AI") emphasized:NO];
    VCSetButtonSymbol(self.sendToAIButton, @"sparkles");
    [self.sendToAIButton addTarget:self action:@selector(_queueCurrentPageForChat) forControlEvents:UIControlEventTouchUpInside];

    self.actionRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.prevButton, self.nextButton, self.clipboardButton, self.locateButton, self.writeButton, self.sendToAIButton
    ]];
    self.actionRow.axis = UILayoutConstraintAxisHorizontal;
    self.actionRow.spacing = 8.0;
    self.actionRow.distribution = UIStackViewDistributionFillEqually;
    self.actionRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerCard addSubview:self.actionRow];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.headerCard.topAnchor constant:10],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:12],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-12],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.statusLabel.leadingAnchor constant:-10],
        [self.statusLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.headerCard.widthAnchor multiplier:0.58],

        [addressLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:12],
        [addressLabel.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:12],
        [addressLabel.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-12],

        [self.addressField.topAnchor constraintEqualToAnchor:addressLabel.bottomAnchor constant:6],
        [self.addressField.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:12],
        [self.pageSizeControl.leadingAnchor constraintEqualToAnchor:self.addressField.trailingAnchor constant:8],
        [self.goButton.leadingAnchor constraintEqualToAnchor:self.pageSizeControl.trailingAnchor constant:8],
        [self.goButton.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-12],
        [self.goButton.centerYAnchor constraintEqualToAnchor:self.addressField.centerYAnchor],
        [self.goButton.widthAnchor constraintEqualToConstant:60],
        [self.addressField.heightAnchor constraintEqualToConstant:38],
        [self.goButton.heightAnchor constraintEqualToConstant:38],

        [self.pageSizeControl.centerYAnchor constraintEqualToAnchor:self.addressField.centerYAnchor],
        [self.pageSizeControl.widthAnchor constraintGreaterThanOrEqualToConstant:168],
        [self.actionRow.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:12],
        [self.actionRow.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-12],
        [self.actionRow.heightAnchor constraintEqualToConstant:34],
        [self.actionRow.bottomAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:-10],
    ]];
    self.pageSizeTopConstraint = [self.pageSizeControl.centerYAnchor constraintEqualToAnchor:self.addressField.centerYAnchor];
    self.pageSizeTopConstraint.active = YES;
    self.pageLabelCenterYConstraint = [pageLabel.centerYAnchor constraintEqualToAnchor:self.pageSizeControl.centerYAnchor];
    self.pageLabelCenterYConstraint.active = YES;
    self.actionRowTopConstraint = [self.actionRow.topAnchor constraintEqualToAnchor:self.addressField.bottomAnchor constant:8];
    self.actionRowTopConstraint.active = YES;
}

- (void)_setupContentCards {
    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 8.0;
    self.contentStack.alignment = UIStackViewAlignmentFill;
    self.contentStack.distribution = UIStackViewDistributionFill;
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.contentStack];

    self.contentDividerView = [[UIView alloc] init];
    self.contentDividerView.backgroundColor = [kVCBorderStrong colorWithAlphaComponent:0.34];
    self.contentDividerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentDividerView.hidden = YES;
    self.contentDividerView.alpha = 0.0;
    [self.view addSubview:self.contentDividerView];

    self.hexCard = [self _cardView];
    [self.contentStack addArrangedSubview:self.hexCard];

    self.hexTitleLabel = [[UILabel alloc] init];
    self.hexTitleLabel.text = VCTextLiteral(@"Hex View");
    self.hexTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    self.hexTitleLabel.textColor = kVCTextPrimary;
    self.hexTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.hexCard addSubview:self.hexTitleLabel];

    self.hexSubtitleLabel = [[UILabel alloc] init];
    self.hexSubtitleLabel.text = VCTextLiteral(@"Load an address to inspect raw bytes, ASCII, and common typed previews.");
    self.hexSubtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.hexSubtitleLabel.textColor = kVCTextMuted;
    self.hexSubtitleLabel.numberOfLines = 2;
    self.hexSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.hexCard addSubview:self.hexSubtitleLabel];

    self.hexTextView = [[UITextView alloc] init];
    self.hexTextView.backgroundColor = kVCBgInput;
    self.hexTextView.textColor = kVCAccent;
    self.hexTextView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.hexTextView.editable = NO;
    VCApplyInputSurface(self.hexTextView, 10.0);
    self.hexTextView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    self.hexTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.hexCard addSubview:self.hexTextView];

    self.detailCard = [self _cardView];
    [self.contentStack addArrangedSubview:self.detailCard];

    self.detailTitleLabel = [[UILabel alloc] init];
    self.detailTitleLabel.text = VCTextLiteral(@"Preview");
    self.detailTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    self.detailTitleLabel.textColor = kVCTextPrimary;
    self.detailTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailCard addSubview:self.detailTitleLabel];

    self.detailModeControl = [[UISegmentedControl alloc] initWithItems:@[VCTextLiteral(@"Preview"), VCTextLiteral(@"Scan")]];
    self.detailModeControl.selectedSegmentIndex = 0;
    self.detailModeControl.selectedSegmentTintColor = kVCAccent;
    [self.detailModeControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: kVCTextPrimary,
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]
    } forState:UIControlStateNormal];
    [self.detailModeControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: kVCBgPrimary,
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightBold]
    } forState:UIControlStateSelected];
    [self.detailModeControl addTarget:self action:@selector(_detailModeChanged) forControlEvents:UIControlEventValueChanged];
    self.detailModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailCard addSubview:self.detailModeControl];

    self.detailSubtitleLabel = [[UILabel alloc] init];
    self.detailSubtitleLabel.text = VCTextLiteral(@"Region metadata, typed values, and stable navigation details appear here.");
    self.detailSubtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.detailSubtitleLabel.textColor = kVCTextMuted;
    self.detailSubtitleLabel.numberOfLines = 2;
    self.detailSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailCard addSubview:self.detailSubtitleLabel];

    self.detailTextView = [[UITextView alloc] init];
    self.detailTextView.backgroundColor = kVCBgInput;
    self.detailTextView.textColor = kVCTextSecondary;
    self.detailTextView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.detailTextView.editable = NO;
    VCApplyInputSurface(self.detailTextView, 10.0);
    self.detailTextView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    self.detailTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailCard addSubview:self.detailTextView];

    self.scanContainer = [[UIView alloc] init];
    self.scanContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailCard addSubview:self.scanContainer];

    UIStackView *scanStack = [[UIStackView alloc] init];
    scanStack.axis = UILayoutConstraintAxisVertical;
    scanStack.spacing = 8.0;
    scanStack.alignment = UIStackViewAlignmentFill;
    scanStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scanContainer addSubview:scanStack];

    self.scanStatusLabel = [[UILabel alloc] init];
    self.scanStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.scanStatusLabel.textColor = kVCTextMuted;
    self.scanStatusLabel.numberOfLines = 2;
    [scanStack addArrangedSubview:self.scanStatusLabel];

    self.scanModeControl = [[UISegmentedControl alloc] initWithItems:@[VCTextLiteral(@"Exact"), VCTextLiteral(@"Fuzzy"), VCTextLiteral(@"Range"), VCTextLiteral(@"Group")]];
    self.scanModeControl.selectedSegmentIndex = 0;
    self.scanModeControl.selectedSegmentTintColor = kVCAccent;
    [self.scanModeControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: kVCTextPrimary,
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]
    } forState:UIControlStateNormal];
    [self.scanModeControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: kVCBgPrimary,
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightBold]
    } forState:UIControlStateSelected];
    [self.scanModeControl addTarget:self action:@selector(_scanModeChanged) forControlEvents:UIControlEventValueChanged];
    [scanStack addArrangedSubview:self.scanModeControl];

    UIStackView *fieldRow = [[UIStackView alloc] init];
    fieldRow.axis = UILayoutConstraintAxisHorizontal;
    fieldRow.spacing = 8.0;
    fieldRow.alignment = UIStackViewAlignmentFill;
    fieldRow.distribution = UIStackViewDistributionFill;
    [scanStack addArrangedSubview:fieldRow];
    self.scanFieldRow = fieldRow;

    self.scanValueField = [self _inputFieldWithLabel:VCTextLiteral(@"Scan Value") placeholder:VCTextLiteral(@"Current value")];
    self.scanValueField.delegate = self;
    self.scanValueField.returnKeyType = UIReturnKeySearch;
    [fieldRow addArrangedSubview:self.scanValueField];

    self.scanSecondaryField = [self _inputFieldWithLabel:VCTextLiteral(@"Max") placeholder:VCTextLiteral(@"Max value")];
    self.scanSecondaryField.delegate = self;
    self.scanSecondaryField.returnKeyType = UIReturnKeySearch;
    [fieldRow addArrangedSubview:self.scanSecondaryField];

    self.scanTypeButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Type • Auto") emphasized:NO];
    [fieldRow addArrangedSubview:self.scanTypeButton];
    self.scanTypeWidthConstraint = [self.scanTypeButton.widthAnchor constraintEqualToConstant:112];
    self.scanTypeWidthConstraint.active = YES;

    self.scanStartButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Start") emphasized:YES];
    [self.scanStartButton addTarget:self action:@selector(_startScan) forControlEvents:UIControlEventTouchUpInside];

    self.scanRefineButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Refine") emphasized:NO];
    self.scanResultsButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Results") emphasized:NO];
    [self.scanResultsButton addTarget:self action:@selector(_loadScanResultsButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    self.scanResumeButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Resume") emphasized:NO];
    [self.scanResumeButton addTarget:self action:@selector(_resumeSavedScan) forControlEvents:UIControlEventTouchUpInside];

    self.scanClearButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Clear") emphasized:NO];
    [self.scanClearButton addTarget:self action:@selector(_clearScan) forControlEvents:UIControlEventTouchUpInside];

    self.scanActionRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.scanStartButton, self.scanRefineButton, self.scanResultsButton, self.scanResumeButton, self.scanClearButton
    ]];
    self.scanActionRow.axis = UILayoutConstraintAxisHorizontal;
    self.scanActionRow.spacing = 8.0;
    self.scanActionRow.distribution = UIStackViewDistributionFillEqually;
    [scanStack addArrangedSubview:self.scanActionRow];

    self.scanResultsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.scanResultsTable.backgroundColor = kVCBgInput;
    self.scanResultsTable.separatorColor = kVCBorder;
    self.scanResultsTable.dataSource = self;
    self.scanResultsTable.delegate = self;
    VCApplyInputSurface(self.scanResultsTable, 10.0);
    self.scanResultsTable.rowHeight = 52.0;
    self.scanResultsTable.sectionHeaderHeight = 0.0;
    self.scanResultsTable.sectionFooterHeight = 0.0;
    self.scanResultsTable.translatesAutoresizingMaskIntoConstraints = NO;
    [scanStack addArrangedSubview:self.scanResultsTable];
    [self.scanResultsTable.heightAnchor constraintEqualToConstant:190].active = YES;

    self.scanEmptyLabel = VCBuildEmptyStateLabel(nil);
    self.scanEmptyLabel.numberOfLines = 3;
    self.scanResultsTable.backgroundView = self.scanEmptyLabel;

    [NSLayoutConstraint activateConstraints:@[
        [scanStack.topAnchor constraintEqualToAnchor:self.scanContainer.topAnchor],
        [scanStack.leadingAnchor constraintEqualToAnchor:self.scanContainer.leadingAnchor],
        [scanStack.trailingAnchor constraintEqualToAnchor:self.scanContainer.trailingAnchor],
        [scanStack.bottomAnchor constraintEqualToAnchor:self.scanContainer.bottomAnchor],
    ]];

    self.contentTopConstraint = [self.contentStack.topAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:8];
    self.detailWidthConstraint = [self.detailCard.widthAnchor constraintEqualToConstant:360];

    [NSLayoutConstraint activateConstraints:@[
        self.contentTopConstraint,
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10],
        [self.contentDividerView.leadingAnchor constraintEqualToAnchor:self.hexCard.trailingAnchor constant:5.5],
        [self.contentDividerView.trailingAnchor constraintEqualToAnchor:self.detailCard.leadingAnchor constant:-5.5],
        [self.contentDividerView.widthAnchor constraintEqualToConstant:1.0],
        [self.contentDividerView.topAnchor constraintEqualToAnchor:self.contentStack.topAnchor constant:4.0],
        [self.contentDividerView.bottomAnchor constraintEqualToAnchor:self.contentStack.bottomAnchor constant:-4.0],

        [self.hexCard.heightAnchor constraintGreaterThanOrEqualToConstant:220],
        [self.detailCard.heightAnchor constraintGreaterThanOrEqualToConstant:280],

        [self.hexTitleLabel.topAnchor constraintEqualToAnchor:self.hexCard.topAnchor constant:10],
        [self.hexTitleLabel.leadingAnchor constraintEqualToAnchor:self.hexCard.leadingAnchor constant:12],
        [self.hexSubtitleLabel.topAnchor constraintEqualToAnchor:self.hexTitleLabel.bottomAnchor constant:2],
        [self.hexSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.hexCard.leadingAnchor constant:12],
        [self.hexSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.hexCard.trailingAnchor constant:-12],
        [self.hexTextView.topAnchor constraintEqualToAnchor:self.hexSubtitleLabel.bottomAnchor constant:8],
        [self.hexTextView.leadingAnchor constraintEqualToAnchor:self.hexCard.leadingAnchor constant:12],
        [self.hexTextView.trailingAnchor constraintEqualToAnchor:self.hexCard.trailingAnchor constant:-12],
        [self.hexTextView.bottomAnchor constraintEqualToAnchor:self.hexCard.bottomAnchor constant:-12],

        [self.detailTitleLabel.topAnchor constraintEqualToAnchor:self.detailCard.topAnchor constant:10],
        [self.detailTitleLabel.leadingAnchor constraintEqualToAnchor:self.detailCard.leadingAnchor constant:12],
        [self.detailModeControl.trailingAnchor constraintEqualToAnchor:self.detailCard.trailingAnchor constant:-12],
        [self.detailModeControl.centerYAnchor constraintEqualToAnchor:self.detailTitleLabel.centerYAnchor],
        [self.detailTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.detailModeControl.leadingAnchor constant:-10],

        [self.detailSubtitleLabel.topAnchor constraintEqualToAnchor:self.detailTitleLabel.bottomAnchor constant:2],
        [self.detailSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.detailCard.leadingAnchor constant:12],
        [self.detailSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.detailCard.trailingAnchor constant:-12],

        [self.detailTextView.topAnchor constraintEqualToAnchor:self.detailSubtitleLabel.bottomAnchor constant:8],
        [self.detailTextView.leadingAnchor constraintEqualToAnchor:self.detailCard.leadingAnchor constant:12],
        [self.detailTextView.trailingAnchor constraintEqualToAnchor:self.detailCard.trailingAnchor constant:-12],
        [self.detailTextView.bottomAnchor constraintEqualToAnchor:self.detailCard.bottomAnchor constant:-12],

        [self.scanContainer.topAnchor constraintEqualToAnchor:self.detailSubtitleLabel.bottomAnchor constant:8],
        [self.scanContainer.leadingAnchor constraintEqualToAnchor:self.detailCard.leadingAnchor constant:12],
        [self.scanContainer.trailingAnchor constraintEqualToAnchor:self.detailCard.trailingAnchor constant:-12],
        [self.scanContainer.bottomAnchor constraintEqualToAnchor:self.detailCard.bottomAnchor constant:-12],
    ]];

    [self _updateDetailMode];
    [self _updateScanModeUI];
    [self _updateBrowserActionState];
    [self _refreshScanResultsPlaceholder];
}

- (UIView *)_cardView {
    UIView *view = [[UIView alloc] init];
    VCApplyPanelSurface(view, 12.0);
    view.translatesAutoresizingMaskIntoConstraints = NO;
    return view;
}

- (UITextField *)_inputFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    VCApplyReadablePlaceholder(field, placeholder);
    field.backgroundColor = kVCBgInput;
    field.textColor = kVCTextPrimary;
    field.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    VCApplyInputSurface(field, 10.0);
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.smartQuotesType = UITextSmartQuotesTypeNo;
    field.smartDashesType = UITextSmartDashesTypeNo;
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    field.leftViewMode = UITextFieldViewModeAlways;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.heightAnchor constraintEqualToConstant:38].active = YES;
    return field;
}

- (UITextField *)_inputFieldWithLabel:(NSString *)label placeholder:(NSString *)placeholder {
    UITextField *field = [self _inputFieldWithPlaceholder:placeholder];
    [self _setInputLabel:label forField:field];
    return field;
}

- (void)_setInputLabel:(NSString *)label forField:(UITextField *)field {
    NSString *safeLabel = label.length > 0 ? label : @"";
    UILabel *labelView = [[UILabel alloc] init];
    labelView.text = safeLabel;
    labelView.textColor = kVCTextMuted;
    labelView.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    labelView.textAlignment = NSTextAlignmentLeft;
    labelView.adjustsFontSizeToFitWidth = YES;
    labelView.minimumScaleFactor = 0.72;

    CGFloat labelWidth = MIN(MAX([safeLabel sizeWithAttributes:@{NSFontAttributeName: labelView.font}].width + 18.0, 48.0), 78.0);
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, labelWidth, 38.0)];
    labelView.frame = CGRectMake(10.0, 0.0, labelWidth - 12.0, 38.0);
    [container addSubview:labelView];
    field.leftView = container;
    field.leftViewMode = UITextFieldViewModeAlways;
}

- (UIButton *)_utilityButtonWithTitle:(NSString *)title emphasized:(BOOL)emphasized {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    if (emphasized) {
        VCApplyCompactPrimaryButtonStyle(button);
        button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    } else {
        VCApplyCompactSecondaryButtonStyle(button);
        button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    }
    VCPrepareButtonTitle(button, NSLineBreakByTruncatingTail, 0.78);
    return button;
}

- (void)_setupWriteDockIfNeeded {
    if (self.writeDock) return;

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
    self.writeDock = dock;

    UIView *handle = [[UIView alloc] init];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.backgroundColor = [UIColor clearColor];
    handle.layer.cornerRadius = 2.0;
    [dock addSubview:handle];
    self.writeDockHandle = handle;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:VCTextLiteral(@"Modify") forState:UIControlStateNormal];
    VCApplyCompactAccentButtonStyle(button);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 14, 10, 14);
    button.titleEdgeInsets = UIEdgeInsetsZero;
    [button addTarget:self action:@selector(_toggleWriteDrawer) forControlEvents:UIControlEventTouchUpInside];
    [dock addSubview:button];
    self.writeDockButton = button;

    self.writeDockWidthConstraint = [self.writeDock.widthAnchor constraintEqualToConstant:160.0];
    self.writeDockHeightConstraint = [self.writeDock.heightAnchor constraintEqualToConstant:56.0];
    self.writeDockLeadingConstraint = [self.writeDock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:0.0];
    self.writeDockTopConstraint = [self.writeDock.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:0.0];

    [NSLayoutConstraint activateConstraints:@[
        self.writeDockWidthConstraint,
        self.writeDockHeightConstraint,
        self.writeDockLeadingConstraint,
        self.writeDockTopConstraint,

        [self.writeDockHandle.topAnchor constraintEqualToAnchor:self.writeDock.topAnchor],
        [self.writeDockHandle.centerXAnchor constraintEqualToAnchor:self.writeDock.centerXAnchor],
        [self.writeDockHandle.widthAnchor constraintEqualToConstant:36.0],
        [self.writeDockHandle.heightAnchor constraintEqualToConstant:0.0],

        [self.writeDockButton.topAnchor constraintEqualToAnchor:self.writeDock.topAnchor],
        [self.writeDockButton.leadingAnchor constraintEqualToAnchor:self.writeDock.leadingAnchor],
        [self.writeDockButton.trailingAnchor constraintEqualToAnchor:self.writeDock.trailingAnchor],
        [self.writeDockButton.bottomAnchor constraintEqualToAnchor:self.writeDock.bottomAnchor],
    ]];

    [self _layoutWriteDock];
}

- (void)_setupWriteOverlayIfNeeded {
    if (self.writeOverlay) return;

    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.hidden = YES;
    overlay.alpha = 0.0;
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    [self.view addSubview:overlay];
    self.writeOverlay = overlay;

    UIControl *backdrop = [[UIControl alloc] init];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addTarget:self action:@selector(_hideWriteDrawer) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:backdrop];
    self.writeBackdrop = backdrop;

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
    self.writeDrawerCard = card;

    self.writeDrawerHandle = [[UIView alloc] init];
    self.writeDrawerHandle.translatesAutoresizingMaskIntoConstraints = NO;
    self.writeDrawerHandle.backgroundColor = kVCTextMuted;
    self.writeDrawerHandle.layer.cornerRadius = 2.0;
    [card addSubview:self.writeDrawerHandle];

    self.writeDrawerTitleLabel = [[UILabel alloc] init];
    self.writeDrawerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.writeDrawerTitleLabel.text = VCTextLiteral(@"Memory Modify");
    self.writeDrawerTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.writeDrawerTitleLabel.textColor = kVCTextPrimary;
    [card addSubview:self.writeDrawerTitleLabel];

    self.writeDrawerSubtitleLabel = [[UILabel alloc] init];
    self.writeDrawerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.writeDrawerSubtitleLabel.text = VCTextLiteral(@"Open a memory page to write values or raw bytes.");
    self.writeDrawerSubtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.writeDrawerSubtitleLabel.textColor = kVCTextSecondary;
    self.writeDrawerSubtitleLabel.numberOfLines = 2;
    [card addSubview:self.writeDrawerSubtitleLabel];

    self.writeDrawerCloseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.writeDrawerCloseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.writeDrawerCloseButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(self.writeDrawerCloseButton);
    [self.writeDrawerCloseButton addTarget:self action:@selector(_hideWriteDrawer) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.writeDrawerCloseButton];

    self.writeValueActionButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Write Value") emphasized:YES];
    self.writeValueActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.writeValueActionButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.writeValueActionButton.titleLabel.minimumScaleFactor = 0.72;
    [self.writeValueActionButton addTarget:self action:@selector(_triggerWriteValueAction) forControlEvents:UIControlEventTouchUpInside];

    self.lockValueActionButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Lock Value") emphasized:NO];
    self.lockValueActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.lockValueActionButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.lockValueActionButton.titleLabel.minimumScaleFactor = 0.72;
    [self.lockValueActionButton addTarget:self action:@selector(_triggerLockValueAction) forControlEvents:UIControlEventTouchUpInside];

    self.writeBytesActionButton = [self _utilityButtonWithTitle:VCTextLiteral(@"Write Bytes") emphasized:NO];
    self.writeBytesActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.writeBytesActionButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.writeBytesActionButton.titleLabel.minimumScaleFactor = 0.72;
    [self.writeBytesActionButton addTarget:self action:@selector(_triggerWriteBytesAction) forControlEvents:UIControlEventTouchUpInside];

    self.writeActionStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.writeValueActionButton,
        self.lockValueActionButton,
        self.writeBytesActionButton
    ]];
    self.writeActionStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.writeActionStack.axis = UILayoutConstraintAxisVertical;
    self.writeActionStack.spacing = 8.0;
    self.writeActionStack.distribution = UIStackViewDistributionFillEqually;
    [card addSubview:self.writeActionStack];

    self.writeDrawerCardLeadingConstraint = [self.writeDrawerCard.leadingAnchor constraintEqualToAnchor:self.writeOverlay.leadingAnchor constant:12.0];
    self.writeDrawerCardTopConstraint = [self.writeDrawerCard.topAnchor constraintEqualToAnchor:self.writeOverlay.topAnchor constant:12.0];
    self.writeDrawerCardWidthConstraint = [self.writeDrawerCard.widthAnchor constraintEqualToConstant:320.0];
    self.writeDrawerCardHeightConstraint = [self.writeDrawerCard.heightAnchor constraintEqualToConstant:232.0];

    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [backdrop.topAnchor constraintEqualToAnchor:overlay.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],

        self.writeDrawerCardLeadingConstraint,
        self.writeDrawerCardTopConstraint,
        self.writeDrawerCardWidthConstraint,
        self.writeDrawerCardHeightConstraint,

        [self.writeDrawerHandle.topAnchor constraintEqualToAnchor:self.writeDrawerCard.topAnchor constant:10.0],
        [self.writeDrawerHandle.centerXAnchor constraintEqualToAnchor:self.writeDrawerCard.centerXAnchor],
        [self.writeDrawerHandle.widthAnchor constraintEqualToConstant:36.0],
        [self.writeDrawerHandle.heightAnchor constraintEqualToConstant:4.0],

        [self.writeDrawerCloseButton.topAnchor constraintEqualToAnchor:self.writeDrawerCard.topAnchor constant:18.0],
        [self.writeDrawerCloseButton.trailingAnchor constraintEqualToAnchor:self.writeDrawerCard.trailingAnchor constant:-14.0],
        [self.writeDrawerCloseButton.widthAnchor constraintEqualToConstant:24.0],
        [self.writeDrawerCloseButton.heightAnchor constraintEqualToConstant:24.0],

        [self.writeDrawerTitleLabel.topAnchor constraintEqualToAnchor:self.writeDrawerCard.topAnchor constant:18.0],
        [self.writeDrawerTitleLabel.leadingAnchor constraintEqualToAnchor:self.writeDrawerCard.leadingAnchor constant:14.0],
        [self.writeDrawerTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.writeDrawerCloseButton.leadingAnchor constant:-10.0],

        [self.writeDrawerSubtitleLabel.topAnchor constraintEqualToAnchor:self.writeDrawerTitleLabel.bottomAnchor constant:8.0],
        [self.writeDrawerSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.writeDrawerTitleLabel.leadingAnchor],
        [self.writeDrawerSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.writeDrawerCard.trailingAnchor constant:-14.0],

        [self.writeActionStack.topAnchor constraintEqualToAnchor:self.writeDrawerSubtitleLabel.bottomAnchor constant:10.0],
        [self.writeActionStack.leadingAnchor constraintEqualToAnchor:self.writeDrawerCard.leadingAnchor constant:14.0],
        [self.writeActionStack.trailingAnchor constraintEqualToAnchor:self.writeDrawerCard.trailingAnchor constant:-14.0],
        [self.writeActionStack.bottomAnchor constraintEqualToAnchor:self.writeDrawerCard.bottomAnchor constant:-14.0],
    ]];

    [self _layoutWriteOverlay];
}

- (void)_layoutWriteDock {
    if (!self.writeDock) return;

    UIEdgeInsets safeInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeInsets = self.view.safeAreaInsets;
    }

    CGFloat dockWidth = MIN(MAX(CGRectGetWidth(self.view.bounds) * 0.36, 136.0), 188.0);
    CGFloat dockHeight = 48.0;
    CGFloat dockX = floor((CGRectGetWidth(self.view.bounds) - dockWidth) * 0.5);
    CGFloat dockY = CGRectGetHeight(self.view.bounds) - safeInsets.bottom - dockHeight - 14.0;
    self.writeDockWidthConstraint.constant = dockWidth;
    self.writeDockHeightConstraint.constant = dockHeight;
    self.writeDockLeadingConstraint.constant = dockX;
    self.writeDockTopConstraint.constant = dockY;
    [self.view layoutIfNeeded];
}

- (void)_layoutWriteOverlay {
    if (!self.writeOverlay || !self.writeDrawerCard) return;

    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape) || (width > height);
    BOOL sideSheetLandscape = landscape && width >= 780.0;
    CGFloat cardWidth = sideSheetLandscape ? MIN(MAX(width * 0.32, 308.0), 368.0) : (width - 24.0);
    CGFloat cardHeight = sideSheetLandscape ? 236.0 : 232.0;
    CGFloat cardX = sideSheetLandscape ? (width - cardWidth - 10.0) : 12.0;
    CGFloat cardY = sideSheetLandscape ? 10.0 : (height - cardHeight - 10.0);
    self.writeDrawerHandle.hidden = sideSheetLandscape;
    self.writeDrawerCardLeadingConstraint.constant = cardX;
    self.writeDrawerCardTopConstraint.constant = cardY;
    self.writeDrawerCardWidthConstraint.constant = cardWidth;
    self.writeDrawerCardHeightConstraint.constant = cardHeight;
    [self.writeOverlay layoutIfNeeded];
}

- (void)_configureMenus {
    [self _refreshScanTypeButton];
    [self _refreshRefineMenu];
    [self _refreshLocateMenu];
    [self _refreshWriteMenu];
}

- (void)_refreshScanTypeButton {
    [self.scanTypeButton setTitle:[NSString stringWithFormat:@"Type • %@", VCMemoryBrowserReadableScanType(self.selectedScanType)]
                         forState:UIControlStateNormal];
    if (@available(iOS 14.0, *)) {
        __weak __typeof__(self) weakSelf = self;
        NSArray<NSDictionary *> *types = @[
            @{@"value": @"int_auto", @"label": VCTextLiteral(@"Auto")},
            @{@"value": @"int32", @"label": VCTextLiteral(@"Int")},
            @{@"value": @"float", @"label": VCTextLiteral(@"Float")},
            @{@"value": @"double", @"label": VCTextLiteral(@"Double")},
            @{@"value": @"string", @"label": VCTextLiteral(@"String")}
        ];
        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray new];
        for (NSDictionary *entry in types) {
            NSString *value = entry[@"value"];
            UIAction *action = [UIAction actionWithTitle:entry[@"label"]
                                                   image:nil
                                              identifier:nil
                                                 handler:^(__kindof UIAction * _Nonnull action) {
                weakSelf.selectedScanType = value;
                [weakSelf _refreshScanTypeButton];
            }];
            if ([weakSelf.selectedScanType isEqualToString:value]) {
                action.state = UIMenuElementStateOn;
            }
            [actions addObject:action];
        }
        self.scanTypeButton.menu = [UIMenu menuWithTitle:@"" children:actions];
        self.scanTypeButton.showsMenuAsPrimaryAction = YES;
    }
}

- (void)_refreshRefineMenu {
    if (@available(iOS 14.0, *)) {
        __weak __typeof__(self) weakSelf = self;
        NSArray<NSDictionary *> *modes = @[
            @{@"value": @"exact", @"label": VCTextLiteral(@"Exact Value")},
            @{@"value": @"increased", @"label": VCTextLiteral(@"Increased")},
            @{@"value": @"decreased", @"label": VCTextLiteral(@"Decreased")},
            @{@"value": @"changed", @"label": VCTextLiteral(@"Changed")},
            @{@"value": @"unchanged", @"label": VCTextLiteral(@"Unchanged")},
            @{@"value": @"greater", @"label": VCTextLiteral(@"Greater Than")},
            @{@"value": @"less", @"label": VCTextLiteral(@"Less Than")},
            @{@"value": @"between", @"label": VCTextLiteral(@"Between")}
        ];
        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray new];
        for (NSDictionary *entry in modes) {
            [actions addObject:[UIAction actionWithTitle:entry[@"label"]
                                                   image:nil
                                              identifier:nil
                                                 handler:^(__kindof UIAction * _Nonnull action) {
                [weakSelf _refineScanWithMode:entry[@"value"]];
            }]];
        }
        self.scanRefineButton.menu = [UIMenu menuWithTitle:@"" children:actions];
        self.scanRefineButton.showsMenuAsPrimaryAction = YES;
    } else {
        [self.scanRefineButton addTarget:self action:@selector(_refineExactFallback) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)_refreshWriteMenu {
    if (@available(iOS 14.0, *)) {
        __weak __typeof__(self) weakSelf = self;
        self.writeButton.menu = [UIMenu menuWithTitle:@""
                                             children:@[
            [UIAction actionWithTitle:VCTextLiteral(@"Write Value")
                                image:nil
                           identifier:nil
                              handler:^(__kindof UIAction * _Nonnull action) {
                [weakSelf _presentValueMutationPromptForMode:@"write_once"];
            }],
            [UIAction actionWithTitle:VCTextLiteral(@"Lock Value")
                                image:nil
                           identifier:nil
                              handler:^(__kindof UIAction * _Nonnull action) {
                [weakSelf _presentValueMutationPromptForMode:@"lock"];
            }],
            [UIAction actionWithTitle:VCTextLiteral(@"Write Bytes")
                                image:nil
                           identifier:nil
                              handler:^(__kindof UIAction * _Nonnull action) {
                [weakSelf _presentWriteBytesPrompt];
            }],
        ]];
        self.writeButton.showsMenuAsPrimaryAction = YES;
    } else {
        [self.writeButton addTarget:self action:@selector(_writeFallback) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)_refreshLocateMenu {
    if (@available(iOS 14.0, *)) {
        __weak __typeof__(self) weakSelf = self;
        BOOL hasLocator = [self.currentLocatorPayload isKindOfClass:[NSDictionary class]] && self.currentLocatorPayload.count > 0;

        UIAction *saveAction = [UIAction actionWithTitle:VCTextLiteral(@"Save Current Locator")
                                                   image:nil
                                              identifier:nil
                                                 handler:^(__kindof UIAction * _Nonnull action) {
            [weakSelf _saveCurrentLocatorArtifact];
        }];
        if (!hasLocator) saveAction.attributes = UIMenuElementAttributesDisabled;

        UIAction *draftAction = [UIAction actionWithTitle:VCTextLiteral(@"Draft Value Lock")
                                                    image:nil
                                               identifier:nil
                                                  handler:^(__kindof UIAction * _Nonnull action) {
            [weakSelf _openValueLockDraftFromCurrentLocator];
        }];
        if (!hasLocator) draftAction.attributes = UIMenuElementAttributesDisabled;

        self.locateButton.menu = [UIMenu menuWithTitle:@""
                                              children:@[
            [UIAction actionWithTitle:VCTextLiteral(@"Resolve Module + RVA")
                                image:nil
                           identifier:nil
                              handler:^(__kindof UIAction * _Nonnull action) {
                [weakSelf _showRuntimeLocatorForCurrentAddress];
            }],
            [UIAction actionWithTitle:VCTextLiteral(@"Create Module Root")
                                image:nil
                           identifier:nil
                              handler:^(__kindof UIAction * _Nonnull action) {
                [weakSelf _showModuleRootLocatorForCurrentAddress];
            }],
            [UIAction actionWithTitle:VCTextLiteral(@"Find Pointer Refs")
                                image:nil
                           identifier:nil
                              handler:^(__kindof UIAction * _Nonnull action) {
                [weakSelf _showPointerReferencesForCurrentAddress];
            }],
            [UIAction actionWithTitle:VCTextLiteral(@"Create Signature (12B)")
                                image:nil
                           identifier:nil
                              handler:^(__kindof UIAction * _Nonnull action) {
                [weakSelf _showSignatureLocatorForCurrentAddressWithLength:12];
            }],
            [UIAction actionWithTitle:VCTextLiteral(@"Create Signature (16B)")
                                image:nil
                           identifier:nil
                              handler:^(__kindof UIAction * _Nonnull action) {
                [weakSelf _showSignatureLocatorForCurrentAddressWithLength:16];
            }],
            [UIMenu menuWithTitle:VCTextLiteral(@"Track")
                          image:nil
                     identifier:nil
                        options:UIMenuOptionsDisplayInline
                       children:@[
                [UIAction actionWithTitle:VCTextLiteral(@"Track as CGPoint")
                                    image:nil
                               identifier:nil
                                  handler:^(__kindof UIAction * _Nonnull action) {
                    [weakSelf _startScreenPointTrackForCurrentAddressWithStructType:@"cgpoint"];
                }],
                [UIAction actionWithTitle:VCTextLiteral(@"Track as CGRect")
                                    image:nil
                               identifier:nil
                                  handler:^(__kindof UIAction * _Nonnull action) {
                    [weakSelf _startScreenRectTrackForCurrentAddressWithStructType:@"cgrect"];
                }],
            ]],
            [UIMenu menuWithTitle:VCTextLiteral(@"Reuse")
                          image:nil
                     identifier:nil
                        options:UIMenuOptionsDisplayInline
                       children:@[saveAction, draftAction]],
        ]];
        self.locateButton.showsMenuAsPrimaryAction = YES;
    } else {
        [self.locateButton addTarget:self action:@selector(_showRuntimeLocatorForCurrentAddress) forControlEvents:UIControlEventTouchUpInside];
    }
}

#pragma mark - Actions

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.addressField) {
        [self _goToAddress];
    } else {
        [self _startScan];
    }
    return NO;
}

- (void)_pageSizeChanged {
    if (self.currentPayload[@"address"]) {
        [self _loadAddressString:VCMemoryBrowserSafeString(self.currentPayload[@"address"])];
    }
}

- (void)_goToAddress {
    [self.addressField resignFirstResponder];
    [self _loadAddressString:self.addressField.text];
}

- (void)_loadPrevPage {
    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryBrowserEngine shared] stepPageBy:-1
                                                              pageSize:[self _selectedPageSize]
                                                          errorMessage:&errorMessage];
    if (!payload) {
        [self _setStatus:errorMessage ?: VCTextLiteral(@"Could not load previous page.") color:kVCRed];
        return;
    }
    [self _applyPayload:payload];
}

- (void)_loadNextPage {
    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryBrowserEngine shared] stepPageBy:1
                                                              pageSize:[self _selectedPageSize]
                                                          errorMessage:&errorMessage];
    if (!payload) {
        [self _setStatus:errorMessage ?: VCTextLiteral(@"Could not load next page.") color:kVCRed];
        return;
    }
    [self _applyPayload:payload];
}

- (void)_copyHexDump {
    NSString *hexDump = VCMemoryBrowserSafeString(self.currentPayload[@"hexDump"]);
    if (hexDump.length == 0) {
        [self _setStatus:VCTextLiteral(@"Nothing loaded to copy yet.") color:kVCYellow];
        return;
    }
    [UIPasteboard generalPasteboard].string = hexDump;
    [self _setStatus:VCTextLiteral(@"Copied current memory page.") color:kVCAccent];
}

- (void)_queueCurrentPageForChat {
    if (![self.currentPayload isKindOfClass:[NSDictionary class]] || self.currentPayload.count == 0) {
        [self _setStatus:VCTextLiteral(@"Load a memory page before sending it to AI.") color:kVCYellow];
        return;
    }

    NSString *address = VCMemoryBrowserSafeString(self.currentPayload[@"address"]);
    NSDictionary *reference = @{
        @"referenceID": [[NSUUID UUID] UUIDString],
        @"kind": @"Memory",
        @"title": address.length > 0 ? [NSString stringWithFormat:@"Memory %@", address] : VCTextLiteral(@"Memory Page"),
        @"payload": @{
            @"address": address ?: @"",
            @"pageSize": self.currentPayload[@"pageSize"] ?: @0,
            @"readLength": self.currentPayload[@"readLength"] ?: @0,
            @"region": self.currentPayload[@"region"] ?: @{},
            @"moduleName": self.currentPayload[@"moduleName"] ?: @"",
            @"rva": self.currentPayload[@"rva"] ?: @"",
            @"typedPreview": self.currentPayload[@"typedPreview"] ?: @{},
            @"asciiPreview": self.currentPayload[@"asciiPreview"] ?: @"",
            @"hexDump": self.currentPayload[@"hexDump"] ?: @"",
            @"lines": self.currentPayload[@"lines"] ?: @[]
        }
    };
    [[VCChatSession shared] enqueuePendingReference:reference];
    [[NSNotificationCenter defaultCenter] postNotificationName:VCSettingsRequestOpenAIChatNotification object:self];
    [self _setStatus:[NSString stringWithFormat:VCTextLiteral(@"Queued %@ for Chat"), reference[@"title"] ?: VCTextLiteral(@"Memory")] color:kVCAccent];
}

- (void)_detailModeChanged {
    [self _updateDetailMode];
}

- (void)_scanModeChanged {
    [self _updateScanModeUI];
}

- (void)_startScan {
    [self.scanValueField resignFirstResponder];
    [self.scanSecondaryField resignFirstResponder];

    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryScanEngine shared] startScanWithMode:[self _selectedScanModeString]
                                                                      value:self.scanValueField.text
                                                                   minValue:self.scanValueField.text
                                                                   maxValue:self.scanSecondaryField.text
                                                             dataTypeString:self.selectedScanType
                                                             floatTolerance:nil
                                                                 groupRange:nil
                                                            groupAnchorMode:nil
                                                                resultLimit:@500
                                                               errorMessage:&errorMessage];
    if (!payload) {
        [self _setStatus:errorMessage ?: VCTextLiteral(@"Could not start the scan.") color:kVCRed];
        self.scanStatusLabel.text = errorMessage ?: VCTextLiteral(@"Could not start the scan.");
        self.scanStatusLabel.textColor = kVCRed;
        [self _refreshScanResultsPlaceholder];
        return;
    }

    [self _showScanWorkspace];
    [self _refreshScanStatusFromSession];
    [self _loadScanResults];
}

- (void)_refineExactFallback {
    [self _refineScanWithMode:@"exact"];
}

- (void)_loadScanResultsButtonTapped {
    [self _showScanWorkspace];
    [self _loadScanResults];
}

- (void)_clearScan {
    [[VCMemoryScanEngine shared] clearScan];
    self.scanCandidates = @[];
    [self.scanResultsTable reloadData];
    [self _refreshScanStatusFromSession];
    [self _refreshScanResultsPlaceholder];
    [self _setStatus:VCTextLiteral(@"Cleared the memory scan session.") color:kVCAccent];
}

- (void)_resumeSavedScan {
    NSDictionary *snapshot = [[VCMemoryScanEngine shared] persistedSessionSummary];
    if (![snapshot[@"hasPersistedSession"] boolValue]) {
        [self _setStatus:VCTextLiteral(@"No saved scan is available to resume.") color:kVCYellow];
        return;
    }

    [self _showScanWorkspace];
    [self _applyPersistedScanInputsFromSnapshot:snapshot];

    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryScanEngine shared] resumePersistedSessionWithErrorMessage:&errorMessage];
    if (!payload) {
        NSString *message = errorMessage.length > 0 ? errorMessage : VCTextLiteral(@"Could not resume the saved scan.");
        self.scanStatusLabel.text = message;
        self.scanStatusLabel.textColor = kVCRed;
        [self _setStatus:message color:kVCRed];
        [self _refreshScanResumeButtonState];
        return;
    }

    BOOL resumed = [payload[@"resumed"] boolValue];
    BOOL replayable = [payload[@"replayable"] boolValue];
    if (resumed && replayable) {
        [self _refreshScanStatusFromSession];
        [self _loadScanResults];
        [self _setStatus:VCTextLiteral(@"Resumed the saved scan session.") color:kVCAccent];
        return;
    }

    NSDictionary *savedSnapshot = [payload[@"snapshot"] isKindOfClass:[NSDictionary class]] ? payload[@"snapshot"] : snapshot;
    [self _restoreSavedScanCandidatesFromSnapshot:savedSnapshot];
    NSString *message = VCMemoryBrowserSafeString(payload[@"message"]);
    self.scanStatusLabel.text = message.length > 0 ? message : VCTextLiteral(@"Saved scan inputs restored.");
    self.scanStatusLabel.textColor = kVCYellow;
    [self _setStatus:self.scanStatusLabel.text color:kVCYellow];
    [self _refreshScanResumeButtonState];
}

- (void)_refineScanWithMode:(NSString *)mode {
    [self.scanValueField resignFirstResponder];
    [self.scanSecondaryField resignFirstResponder];

    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryScanEngine shared] refineScanWithMode:mode
                                                                       value:self.scanValueField.text
                                                                    minValue:self.scanValueField.text
                                                                    maxValue:self.scanSecondaryField.text
                                                              dataTypeString:self.selectedScanType
                                                                errorMessage:&errorMessage];
    if (!payload) {
        [self _setStatus:errorMessage ?: VCTextLiteral(@"Could not refine the scan.") color:kVCRed];
        self.scanStatusLabel.text = errorMessage ?: VCTextLiteral(@"Could not refine the scan.");
        self.scanStatusLabel.textColor = kVCRed;
        [self _refreshScanResultsPlaceholder];
        return;
    }

    [self _showScanWorkspace];
    [self _refreshScanStatusFromSession];
    [self _loadScanResults];
}

- (void)_presentValueMutationPromptForMode:(NSString *)mode {
    NSString *address = VCMemoryBrowserSafeString(self.currentPayload[@"address"]);
    if (address.length == 0) {
        [self _setStatus:VCTextLiteral(@"Load an address before writing memory.") color:kVCYellow];
        return;
    }

    UIViewController *presenter = [self _preferredPresenter];
    if (!presenter) return;

    NSString *title = [mode isEqualToString:@"lock"] ? VCTextLiteral(@"Lock Value") : VCTextLiteral(@"Write Value");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:address
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        VCApplyReadablePlaceholder(textField, VCTextLiteral(@"New value"));
        textField.keyboardType = UIKeyboardTypeDefault;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        VCApplyReadablePlaceholder(textField, VCTextLiteral(@"Type: int / float / double / string"));
        textField.text = [self _defaultWriteType];
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    __weak __typeof__(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:VCTextLiteral(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:title
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *type = [alert.textFields.lastObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (value.length == 0) {
            [weakSelf _setStatus:VCTextLiteral(@"Enter a value to write.") color:kVCYellow];
            return;
        }

        NSMutableDictionary *params = [@{
            @"address": address,
            @"value": value,
            @"mode": mode,
            @"target": [NSString stringWithFormat:@"Memory %@", address]
        } mutableCopy];
        if (type.length > 0) params[@"dataType"] = type;
        [weakSelf _executeMutationToolCallType:VCToolCallModifyValue
                                        title:@"modify_value"
                                       params:[params copy]
                                  successText:([mode isEqualToString:@"lock"] ? VCTextLiteral(@"Locked the current address.") : VCTextLiteral(@"Wrote the new value."))
                                       remark:[NSString stringWithFormat:@"Memory tab %@ %@", mode, address]];
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)_presentWriteBytesPrompt {
    NSString *address = VCMemoryBrowserSafeString(self.currentPayload[@"address"]);
    if (address.length == 0) {
        [self _setStatus:VCTextLiteral(@"Load an address before writing bytes.") color:kVCYellow];
        return;
    }

    UIViewController *presenter = [self _preferredPresenter];
    if (!presenter) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:VCTextLiteral(@"Write Bytes")
                                                                   message:address
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        VCApplyReadablePlaceholder(textField, @"DE AD BE EF");
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    __weak __typeof__(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:VCTextLiteral(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:VCTextLiteral(@"Write Bytes")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        NSString *hexData = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (hexData.length == 0) {
            [weakSelf _setStatus:VCTextLiteral(@"Enter a byte sequence first.") color:kVCYellow];
            return;
        }
        [weakSelf _executeMutationToolCallType:VCToolCallWriteMemoryBytes
                                        title:@"write_memory_bytes"
                                       params:@{
                                           @"address": address,
                                           @"hexData": hexData,
                                           @"target": [NSString stringWithFormat:@"Memory %@", address]
                                       }
                                  successText:VCTextLiteral(@"Wrote the requested bytes.")
                                       remark:[NSString stringWithFormat:@"Memory tab raw byte write %@", address]];
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)_writeFallback {
    [self _presentValueMutationPromptForMode:@"write_once"];
}

- (void)_toggleWriteDrawer {
    BOOL showing = self.writeOverlay && !self.writeOverlay.hidden;
    if (showing) {
        [self _hideWriteDrawer];
    } else {
        [self _showWriteDrawer];
    }
}

- (void)_showWriteDrawer {
    NSString *address = VCMemoryBrowserSafeString(self.currentPayload[@"address"]);
    if (address.length == 0) {
        [self _setStatus:VCTextLiteral(@"Load an address before opening modify tools.") color:kVCYellow];
        return;
    }

    self.writeDrawerSubtitleLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Editing %@ with native write actions."), address];
    self.writeOverlay.hidden = NO;
    [self.view bringSubviewToFront:self.writeOverlay];
    self.writeOverlay.alpha = 0.0;
    self.writeOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    [self _layoutWriteOverlay];

    BOOL sideSheetLandscape = (((self.currentLayoutMode == VCPanelLayoutModeLandscape) || (CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds))) && CGRectGetWidth(self.view.bounds) >= 780.0);
    self.writeDrawerCard.transform = sideSheetLandscape
        ? CGAffineTransformMakeTranslation(CGRectGetWidth(self.writeDrawerCard.bounds) + 20.0, 0)
        : CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.writeDrawerCard.bounds) + 20.0);

    [self _refreshWriteDock];
    [UIView animateWithDuration:0.22 animations:^{
        self.writeOverlay.alpha = 1.0;
        self.writeOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.24];
        self.writeDrawerCard.transform = CGAffineTransformIdentity;
    }];
}

- (void)_hideWriteDrawer {
    if (!self.writeOverlay || self.writeOverlay.hidden) return;

    BOOL sideSheetLandscape = (((self.currentLayoutMode == VCPanelLayoutModeLandscape) || (CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds))) && CGRectGetWidth(self.view.bounds) >= 780.0);
    [UIView animateWithDuration:0.18 animations:^{
        self.writeOverlay.alpha = 0.0;
        self.writeOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
        self.writeDrawerCard.transform = sideSheetLandscape
            ? CGAffineTransformMakeTranslation(CGRectGetWidth(self.writeDrawerCard.bounds) + 20.0, 0)
            : CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.writeDrawerCard.bounds) + 20.0);
    } completion:^(BOOL finished) {
        self.writeOverlay.hidden = YES;
        self.writeDrawerCard.transform = CGAffineTransformIdentity;
        [self _refreshWriteDock];
    }];
}

- (void)_refreshWriteDock {
    if (!self.writeDock) return;

    BOOL hasPayload = [self.currentPayload isKindOfClass:[NSDictionary class]] && self.currentPayload.count > 0;
    BOOL drawerVisible = self.writeOverlay && !self.writeOverlay.hidden;
    BOOL shouldShowDock = hasPayload && !drawerVisible;
    [self _layoutWriteDock];

    if (shouldShowDock) {
        self.writeDockButton.enabled = YES;
        self.writeDockButton.alpha = 1.0;
        [self.writeDockButton setTitle:VCTextLiteral(@"Modify") forState:UIControlStateNormal];
        [self.writeDockButton setImage:nil forState:UIControlStateNormal];
        self.writeDockButton.titleEdgeInsets = UIEdgeInsetsZero;
        if (self.writeDock.hidden) {
            self.writeDock.hidden = NO;
            self.writeDock.alpha = 0.0;
            self.writeDock.transform = CGAffineTransformMakeTranslation(0, 16.0);
        }
        [self.view bringSubviewToFront:self.writeDock];
        [UIView animateWithDuration:0.18 animations:^{
            self.writeDock.alpha = 1.0;
            self.writeDock.transform = CGAffineTransformIdentity;
        }];
        return;
    }

    if (!self.writeDock.hidden || self.writeDock.alpha > 0.0) {
        [UIView animateWithDuration:0.16 animations:^{
            self.writeDock.alpha = 0.0;
            self.writeDock.transform = CGAffineTransformMakeTranslation(0, 16.0);
        } completion:^(__unused BOOL finished) {
            self.writeDock.hidden = YES;
            self.writeDock.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)_triggerWriteValueAction {
    [self _hideWriteDrawer];
    [self _presentValueMutationPromptForMode:@"write_once"];
}

- (void)_triggerLockValueAction {
    [self _hideWriteDrawer];
    [self _presentValueMutationPromptForMode:@"lock"];
}

- (void)_triggerWriteBytesAction {
    [self _hideWriteDrawer];
    [self _presentWriteBytesPrompt];
}

#pragma mark - Loading

- (void)_restoreSessionIfAvailable {
    NSDictionary *session = [[VCMemoryBrowserEngine shared] activeSessionSummary];
    NSString *address = VCMemoryBrowserSafeString(session[@"currentAddress"]);
    if (address.length > 0) {
        [self _loadAddressString:address];
    } else {
        self.hexTextView.text = VCTextLiteral(@"No memory page loaded yet.\n\nEnter an address above, or let AI use memory_browser first and come back here.");
        self.detailTextView.text = VCMemoryBrowserFormattedDetail(nil);
        [self _setStatus:VCTextLiteral(@"Ready") color:kVCTextMuted];
    }
    [self _updateBrowserActionState];
}

- (void)_restoreScanIfAvailable {
    if ([[VCMemoryScanEngine shared] hasActiveSession]) {
        [self _applyPersistedScanInputsFromSnapshot:[[VCMemoryScanEngine shared] persistedSessionSummary]];
        [self _refreshScanStatusFromSession];
        [self _loadScanResults];
    } else {
        NSDictionary *snapshot = [[VCMemoryScanEngine shared] persistedSessionSummary];
        [self _applyPersistedScanInputsFromSnapshot:snapshot];
        [self _restoreSavedScanCandidatesFromSnapshot:snapshot];
        [self _refreshScanStatusFromSession];
    }
}

- (void)_loadAddressString:(NSString *)addressString {
    NSString *trimmed = [VCMemoryBrowserSafeString(addressString) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    uint64_t address = strtoull(trimmed.UTF8String, NULL, 0);
    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryBrowserEngine shared] browseAtAddress:address
                                                                   pageSize:[self _selectedPageSize]
                                                                     length:[self _selectedPageSize]
                                                              updateSession:YES
                                                               errorMessage:&errorMessage];
    if (!payload) {
        [self _setStatus:errorMessage ?: VCTextLiteral(@"Could not load that address.") color:kVCRed];
        return;
    }
    [self _applyPayload:payload];
}

- (void)openAddressString:(NSString *)addressString {
    [self _loadAddressString:addressString];
}

- (void)_applyPayload:(NSDictionary *)payload {
    self.currentPayload = payload ?: @{};
    self.currentLocatorPayload = nil;
    self.currentLocatorTitle = nil;
    self.currentLocatorSubtitle = nil;
    self.addressField.text = VCMemoryBrowserSafeString(payload[@"address"]);
    [self _selectPageSize:[payload[@"pageSize"] unsignedIntegerValue]];
    self.hexTextView.text = VCMemoryBrowserSafeString(payload[@"hexDump"]);

    NSString *moduleName = VCMemoryBrowserSafeString(payload[@"moduleName"]);
    NSDictionary *region = [payload[@"region"] isKindOfClass:[NSDictionary class]] ? payload[@"region"] : @{};
    NSString *protection = VCMemoryBrowserSafeString(region[@"protection"]);
    NSString *readLength = [payload[@"readLength"] respondsToSelector:@selector(stringValue)] ? [payload[@"readLength"] stringValue] : @"0";

    self.hexTitleLabel.text = [NSString stringWithFormat:@"%@ %@", VCTextLiteral(@"Hex View"), self.addressField.text ?: @""];
    self.hexSubtitleLabel.text = [NSString stringWithFormat:@"%@ bytes • %@%@%@",
                                  readLength,
                                  protection.length > 0 ? protection : @"---",
                                  moduleName.length > 0 ? @" • " : @"",
                                  moduleName];

    self.detailTextView.text = VCMemoryBrowserFormattedDetail(payload ?: @{});

    if (self.detailModeControl.selectedSegmentIndex == 0) {
        self.detailTitleLabel.text = VCTextLiteral(@"Preview");
        self.detailSubtitleLabel.text = moduleName.length > 0
            ? [NSString stringWithFormat:@"%@ • %@ %@", moduleName, VCTextLiteral(@"region"), protection.length > 0 ? protection : @"---"]
            : [NSString stringWithFormat:@"%@ %@", VCTextLiteral(@"Region"), protection.length > 0 ? protection : @"---"];
    }

    [self _setStatus:[NSString stringWithFormat:@"%@ • %@ bytes", self.addressField.text ?: @"", readLength] color:kVCAccent];
    [self _updateBrowserActionState];
    [self _refreshLocateMenu];
    [self _refreshWriteDock];
}

- (void)_loadScanResults {
    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryScanEngine shared] resultsWithOffset:0
                                                                     limit:24
                                                             refreshValues:YES
                                                              errorMessage:&errorMessage];
    if (!payload) {
        self.scanCandidates = @[];
        [self.scanResultsTable reloadData];
        [self _refreshScanStatusFromSession];
        [self _refreshScanResultsPlaceholder];
        if (errorMessage.length > 0) {
            [self _setStatus:errorMessage color:kVCRed];
        }
        return;
    }

    NSArray *candidates = [payload[@"candidates"] isKindOfClass:[NSArray class]] ? payload[@"candidates"] : @[];
    self.scanCandidates = candidates;
    [self.scanResultsTable reloadData];
    [self _refreshScanResultsPlaceholder];

    NSUInteger totalCount = [payload[@"totalCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"totalCount"] unsignedIntegerValue] : candidates.count;
    NSUInteger returnedCount = [payload[@"returnedCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"returnedCount"] unsignedIntegerValue] : candidates.count;
    self.scanStatusLabel.text = [NSString stringWithFormat:@"%@ • %@ %@",
                                 [[VCMemoryScanEngine shared] hasActiveSession] ? VCMemoryBrowserReadableScanType([VCMemoryScanEngine shared].activeSessionSummary[@"dataType"]) : @"Scan",
                                 @(totalCount),
                                 totalCount == 1 ? VCTextLiteral(@"candidate") : VCTextLiteral(@"candidates")];
    self.scanStatusLabel.textColor = totalCount > 0 ? kVCTextSecondary : kVCYellow;
    [self _setStatus:[NSString stringWithFormat:VCTextLiteral(@"Loaded %lu of %lu scan candidates"),
                      (unsigned long)returnedCount,
                      (unsigned long)totalCount]
               color:kVCAccent];
}

- (void)_refreshScanStatusFromSession {
    NSDictionary *session = [[VCMemoryScanEngine shared] activeSessionSummary];
    BOOL active = [session[@"active"] boolValue];
    if (!active) {
        NSDictionary *snapshot = [[VCMemoryScanEngine shared] persistedSessionSummary];
        if ([snapshot[@"hasPersistedSession"] boolValue]) {
            NSDictionary *savedSession = [snapshot[@"session"] isKindOfClass:[NSDictionary class]] ? snapshot[@"session"] : @{};
            NSString *scanMode = VCMemoryBrowserSafeString(savedSession[@"scanMode"]);
            NSString *dataType = VCMemoryBrowserSafeString(savedSession[@"dataType"]);
            NSUInteger resultCount = [savedSession[@"resultCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [savedSession[@"resultCount"] unsignedIntegerValue] : 0;
            BOOL replayable = [snapshot[@"replayable"] boolValue];
            self.scanStatusLabel.text = [NSString stringWithFormat:@"%@ • %@ • %@ %@ • %@",
                                         VCMemoryBrowserReadableScanType(dataType),
                                         scanMode.length > 0 ? scanMode.capitalizedString : VCTextLiteral(@"Saved"),
                                         @(resultCount),
                                         resultCount == 1 ? VCTextLiteral(@"candidate") : VCTextLiteral(@"candidates"),
                                         (replayable ? VCTextLiteral(@"tap Resume") : VCTextLiteral(@"restore inputs only"))];
            self.scanStatusLabel.textColor = replayable ? kVCTextSecondary : kVCYellow;
        } else {
            self.scanStatusLabel.text = VCTextLiteral(@"No active memory scan. Start with the visible score, change it once, then refine.");
            self.scanStatusLabel.textColor = kVCTextMuted;
        }
        [self _refreshScanResumeButtonState];
        return;
    }

    NSString *scanMode = VCMemoryBrowserSafeString(session[@"scanMode"]);
    NSString *dataType = VCMemoryBrowserSafeString(session[@"dataType"]);
    NSUInteger resultCount = [session[@"resultCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [session[@"resultCount"] unsignedIntegerValue] : 0;
    self.scanStatusLabel.text = [NSString stringWithFormat:@"%@ • %@ • %@ %@",
                                 VCMemoryBrowserReadableScanType(dataType),
                                 scanMode.length > 0 ? scanMode.capitalizedString : VCTextLiteral(@"Scan"),
                                 @(resultCount),
                                 resultCount == 1 ? VCTextLiteral(@"candidate") : VCTextLiteral(@"candidates")];
    self.scanStatusLabel.textColor = resultCount > 0 ? kVCTextSecondary : kVCYellow;
    [self _refreshScanResumeButtonState];
}

#pragma mark - Helpers

- (void)_showScanWorkspace {
    self.detailModeControl.selectedSegmentIndex = 1;
    [self _updateDetailMode];
}

- (void)_updateDetailMode {
    BOOL showingScan = self.detailModeControl.selectedSegmentIndex == 1;
    self.detailTextView.hidden = showingScan;
    self.scanContainer.hidden = !showingScan;
    self.detailTitleLabel.text = showingScan ? VCTextLiteral(@"Scan") : VCTextLiteral(@"Preview");
    self.detailSubtitleLabel.text = showingScan
        ? VCTextLiteral(@"Start, refine, then tap a candidate to jump straight into the browser.")
        : VCTextLiteral(@"Region metadata, typed values, and stable navigation details appear here.");
}

- (void)_updateScanModeUI {
    NSString *mode = [self _selectedScanModeString];
    BOOL isRange = [mode isEqualToString:@"between"];
    BOOL isFuzzy = [mode isEqualToString:@"fuzzy"];
    self.scanSecondaryField.hidden = !isRange;
    [self _setInputLabel:isRange ? VCTextLiteral(@"Min") : ([mode isEqualToString:@"group"] ? VCTextLiteral(@"Group") : VCTextLiteral(@"Scan Value"))
               forField:self.scanValueField];
    VCApplyReadablePlaceholder(self.scanValueField, isFuzzy ? VCTextLiteral(@"Value not required for fuzzy start") :
                               ([mode isEqualToString:@"group"] ? VCTextLiteral(@"Group values, e.g. 100;200;300") :
                                (isRange ? VCTextLiteral(@"Min value") : VCTextLiteral(@"Current value"))));
    if (isRange) {
        [self _setInputLabel:VCTextLiteral(@"Max") forField:self.scanSecondaryField];
        VCApplyReadablePlaceholder(self.scanSecondaryField, VCTextLiteral(@"Max value"));
    }
}

- (void)_refreshScanResumeButtonState {
    BOOL enabled = ![[VCMemoryScanEngine shared] hasActiveSession] && [[VCMemoryScanEngine shared] hasPersistedSession];
    self.scanResumeButton.enabled = enabled;
    self.scanResumeButton.alpha = enabled ? 1.0 : 0.45;
}

- (void)_updateBrowserActionState {
    BOOL hasPayload = [self.currentPayload isKindOfClass:[NSDictionary class]] && self.currentPayload.count > 0;
    self.prevButton.enabled = hasPayload;
    self.nextButton.enabled = hasPayload;
    self.clipboardButton.enabled = hasPayload;
    self.locateButton.enabled = hasPayload;
    self.writeButton.enabled = hasPayload;
    self.sendToAIButton.enabled = hasPayload;
    NSArray<UIButton *> *buttons = @[self.prevButton, self.nextButton, self.clipboardButton, self.locateButton, self.writeButton, self.sendToAIButton];
    for (UIButton *button in buttons) {
        button.alpha = button.enabled ? 1.0 : 0.45;
    }
    [self _refreshWriteDock];
}

- (NSString *)_selectedScanModeString {
    switch (self.scanModeControl.selectedSegmentIndex) {
        case 1: return @"fuzzy";
        case 2: return @"between";
        case 3: return @"group";
        default: return @"exact";
    }
}

- (void)_setScanModeFromString:(NSString *)mode {
    NSString *normalized = [VCMemoryBrowserSafeString(mode).lowercaseString copy];
    if ([normalized isEqualToString:@"fuzzy"]) self.scanModeControl.selectedSegmentIndex = 1;
    else if ([normalized isEqualToString:@"between"]) self.scanModeControl.selectedSegmentIndex = 2;
    else if ([normalized isEqualToString:@"group"] || [normalized isEqualToString:@"union"]) self.scanModeControl.selectedSegmentIndex = 3;
    else self.scanModeControl.selectedSegmentIndex = 0;
    [self _updateScanModeUI];
}

- (void)_applyPersistedScanInputsFromSnapshot:(NSDictionary *)snapshot {
    NSDictionary *start = [snapshot[@"startParameters"] isKindOfClass:[NSDictionary class]] ? snapshot[@"startParameters"] : nil;
    if (![start isKindOfClass:[NSDictionary class]] || start.count == 0) return;

    [self _setScanModeFromString:VCMemoryBrowserSafeString(start[@"scanMode"])];

    NSString *mode = [self _selectedScanModeString];
    if ([mode isEqualToString:@"between"]) {
        self.scanValueField.text = VCMemoryBrowserSafeString(start[@"minValue"]);
        self.scanSecondaryField.text = VCMemoryBrowserSafeString(start[@"maxValue"]);
    } else if ([mode isEqualToString:@"fuzzy"]) {
        self.scanValueField.text = @"";
        self.scanSecondaryField.text = @"";
    } else {
        self.scanValueField.text = VCMemoryBrowserSafeString(start[@"value"]);
        self.scanSecondaryField.text = VCMemoryBrowserSafeString(start[@"maxValue"]);
    }

    NSString *dataType = VCMemoryBrowserSafeString(start[@"dataType"]);
    self.selectedScanType = dataType.length > 0 ? dataType : @"int_auto";
    [self _refreshScanTypeButton];
}

- (void)_restoreSavedScanCandidatesFromSnapshot:(NSDictionary *)snapshot {
    NSDictionary *lastPage = [snapshot[@"lastResultsPage"] isKindOfClass:[NSDictionary class]] ? snapshot[@"lastResultsPage"] : nil;
    NSArray *candidates = [lastPage[@"candidates"] isKindOfClass:[NSArray class]] ? lastPage[@"candidates"] : nil;
    self.scanCandidates = candidates ?: @[];
    [self.scanResultsTable reloadData];
    [self _refreshScanResultsPlaceholder];
}

- (NSString *)_defaultWriteType {
    NSString *type = [self.selectedScanType lowercaseString];
    if ([type isEqualToString:@"float"]) return @"float";
    if ([type isEqualToString:@"double"]) return @"double";
    if ([type isEqualToString:@"string"]) return @"string";
    return @"int";
}

- (NSString *)_memoryArtifactsDirectoryPath {
    NSString *path = [[[VCConfig shared] sessionsPath] stringByAppendingPathComponent:@"memory"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

- (void)_saveCurrentLocatorArtifact {
    if (![self.currentLocatorPayload isKindOfClass:[NSDictionary class]] || self.currentLocatorPayload.count == 0) {
        [self _setStatus:VCTextLiteral(@"Generate a locator before saving it.") color:kVCYellow];
        return;
    }

    NSMutableDictionary *payload = [self.currentLocatorPayload mutableCopy] ?: [NSMutableDictionary new];
    NSString *locatorID = [[NSUUID UUID] UUIDString];
    payload[@"queryType"] = @"locator";
    payload[@"snapshotID"] = locatorID;
    payload[@"createdAt"] = @([[NSDate date] timeIntervalSince1970]);
    payload[@"title"] = self.currentLocatorTitle ?: VCTextLiteral(@"Locator");
    payload[@"subtitle"] = self.currentLocatorSubtitle ?: @"";
    if (![payload[@"address"] isKindOfClass:[NSString class]] || [payload[@"address"] length] == 0) {
        NSString *resolvedAddress = VCMemoryBrowserSafeString(payload[@"resolvedAddress"]);
        NSString *currentAddress = VCMemoryBrowserSafeString(self.currentPayload[@"address"]);
        payload[@"address"] = resolvedAddress.length > 0 ? resolvedAddress : currentAddress;
    }
    if (![payload[@"moduleName"] isKindOfClass:[NSString class]] || [payload[@"moduleName"] length] == 0) {
        NSString *moduleName = VCMemoryBrowserSafeString(payload[@"moduleForResolvedAddress"]);
        if (moduleName.length == 0) {
            moduleName = VCMemoryBrowserSafeString(self.currentPayload[@"moduleName"]);
        }
        payload[@"moduleName"] = moduleName ?: @"";
    }
    if (!payload[@"length"]) payload[@"length"] = @0;

    NSString *path = [[self _memoryArtifactsDirectoryPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", locatorID]];
    payload[@"path"] = path;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    if (![jsonData isKindOfClass:[NSData class]] || ![jsonData writeToFile:path atomically:YES]) {
        [self _setStatus:VCTextLiteral(@"Could not save the locator artifact.") color:kVCRed];
        return;
    }

    self.currentLocatorPayload = [payload copy];
    [self _refreshLocateMenu];
    [self _setStatus:[NSString stringWithFormat:VCTextLiteral(@"Saved locator %@"), locatorID] color:kVCAccent];
}

- (void)_openValueLockDraftFromCurrentLocator {
    NSString *addressString = VCMemoryBrowserSafeString(self.currentPayload[@"address"]);
    uintptr_t address = (uintptr_t)[self _currentLoadedAddress];
    if (address == 0) {
        [self _setStatus:VCTextLiteral(@"Load an address before drafting a value lock.") color:kVCYellow];
        return;
    }

    VCValueItem *draft = [[VCValueItem alloc] init];
    NSString *moduleName = VCMemoryBrowserSafeString(self.currentPayload[@"moduleName"]);
    NSString *rva = VCMemoryBrowserSafeString(self.currentPayload[@"rva"]);
    NSString *targetDesc = self.currentLocatorTitle.length > 0
        ? [NSString stringWithFormat:@"%@ %@", self.currentLocatorTitle, addressString]
        : [NSString stringWithFormat:@"Memory %@", addressString];
    if (moduleName.length > 0 && rva.length > 0) {
        targetDesc = [NSString stringWithFormat:@"%@ (%@ %@)", targetDesc, moduleName, rva];
    }

    draft.targetDesc = targetDesc;
    draft.address = address;
    draft.dataType = [self _defaultWriteType];
    draft.modifiedValue = @"";

    NSMutableArray<NSString *> *remarkParts = [NSMutableArray new];
    if (self.currentLocatorSubtitle.length > 0) {
        [remarkParts addObject:self.currentLocatorSubtitle];
    }
    if ([self.currentLocatorPayload isKindOfClass:[NSDictionary class]] && self.currentLocatorPayload.count > 0) {
        NSString *json = VCMemoryBrowserPrettyJSONString(self.currentLocatorPayload);
        if (json.length > 0) {
            [remarkParts addObject:[NSString stringWithFormat:@"Locator:\n%@", json]];
        }
    }
    draft.remark = [remarkParts componentsJoinedByString:@"\n\n"];

    [[NSNotificationCenter defaultCenter] postNotificationName:VCPatchesRequestOpenEditorNotification
                                                        object:self
                                                      userInfo:@{
        VCPatchesOpenEditorSegmentKey: @1,
        VCPatchesOpenEditorItemKey: draft,
        VCPatchesOpenEditorCreatesKey: @YES
    }];
    [self _setStatus:VCTextLiteral(@"Opened a value lock draft in Patches.") color:kVCAccent];
}

- (void)_startScreenPointTrackForCurrentAddressWithStructType:(NSString *)structType {
    uint64_t address = [self _currentLoadedAddress];
    if (address == 0) {
        [self _setStatus:VCTextLiteral(@"Load a concrete address before starting a point track.") color:kVCYellow];
        return;
    }
    NSString *addressString = VCMemoryBrowserSafeString(self.currentPayload[@"address"]);
    NSDictionary *result = [[VCOverlayTrackingManager shared] startTrackerWithConfiguration:@{
        @"trackMode": @"screen_point",
        @"canvasID": @"memory",
        @"pointAddress": addressString.length > 0 ? addressString : [NSString stringWithFormat:@"0x%llx", address],
        @"pointType": structType ?: @"cgpoint",
        @"label": self.currentLocatorTitle.length > 0 ? self.currentLocatorTitle : [NSString stringWithFormat:@"Point %@", addressString.length > 0 ? addressString : [NSString stringWithFormat:@"0x%llx", address]],
        @"drawStyle": @"circle_label",
        @"color": @"#00D4FF",
        @"backgroundColor": @"#10151DBB"
    }];
    [self _setStatus:VCMemoryBrowserSafeString(result[@"summary"]).length > 0 ? result[@"summary"] : VCTextLiteral(@"Started screen point tracking.") color:([result[@"success"] boolValue] ? kVCAccent : kVCRed)];
}

- (void)_startScreenRectTrackForCurrentAddressWithStructType:(NSString *)structType {
    uint64_t address = [self _currentLoadedAddress];
    if (address == 0) {
        [self _setStatus:VCTextLiteral(@"Load a concrete address before starting a rect track.") color:kVCYellow];
        return;
    }
    NSString *addressString = VCMemoryBrowserSafeString(self.currentPayload[@"address"]);
    NSDictionary *result = [[VCOverlayTrackingManager shared] startTrackerWithConfiguration:@{
        @"trackMode": @"screen_rect",
        @"canvasID": @"memory",
        @"rectAddress": addressString.length > 0 ? addressString : [NSString stringWithFormat:@"0x%llx", address],
        @"rectType": structType ?: @"cgrect",
        @"label": self.currentLocatorTitle.length > 0 ? self.currentLocatorTitle : [NSString stringWithFormat:@"Rect %@", addressString.length > 0 ? addressString : [NSString stringWithFormat:@"0x%llx", address]],
        @"drawStyle": @"box_label",
        @"color": @"#00D4FF",
        @"backgroundColor": @"#10151DBB",
        @"cornerRadius": @6
    }];
    [self _setStatus:VCMemoryBrowserSafeString(result[@"summary"]).length > 0 ? result[@"summary"] : VCTextLiteral(@"Started screen rect tracking.") color:([result[@"success"] boolValue] ? kVCAccent : kVCRed)];
}

- (uint64_t)_currentLoadedAddress {
    NSString *addressString = VCMemoryBrowserSafeString(self.currentPayload[@"address"]);
    if (addressString.length == 0) {
        addressString = [VCMemoryBrowserSafeString(self.addressField.text) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return strtoull(addressString.UTF8String, NULL, 0);
}

- (NSData *)_memoryDataAtAddress:(uint64_t)address length:(NSUInteger)length {
    if (address == 0 || length == 0) return nil;
    [[VCMemEngine shared] initialize];
    return [[VCMemEngine shared] readMemory:address length:length];
}

- (NSString *)_signaturePatternFromData:(NSData *)data {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    if (!bytes || data.length == 0) return @"";
    NSMutableArray<NSString *> *components = [NSMutableArray new];
    for (NSUInteger idx = 0; idx < data.length; idx++) {
        [components addObject:[NSString stringWithFormat:@"%02X", bytes[idx]]];
    }
    return [components componentsJoinedByString:@" "];
}

- (void)_showLocatorPayload:(NSDictionary *)payload
                      title:(NSString *)title
                   subtitle:(NSString *)subtitle
                 statusText:(NSString *)statusText
                statusColor:(UIColor *)statusColor {
    self.currentLocatorPayload = payload ?: @{};
    self.currentLocatorTitle = title ?: @"";
    self.currentLocatorSubtitle = subtitle ?: @"";
    self.detailModeControl.selectedSegmentIndex = 0;
    [self _updateDetailMode];
    self.detailTitleLabel.text = title ?: VCTextLiteral(@"Locator");
    self.detailSubtitleLabel.text = subtitle ?: VCTextLiteral(@"Stable address metadata and reusable locators.");
    self.detailTextView.text = VCMemoryBrowserPrettyJSONString(payload ?: @{});
    [self _setStatus:statusText color:statusColor ?: kVCAccent];
    [self _refreshLocateMenu];
}

- (void)_showRuntimeLocatorForCurrentAddress {
    uint64_t address = [self _currentLoadedAddress];
    if (address == 0) {
        [self _setStatus:VCTextLiteral(@"Load an address before resolving a locator.") color:kVCYellow];
        return;
    }

    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryLocatorEngine shared] resolveAddressAction:@"runtime_to_rva"
                                                                      moduleName:nil
                                                                             rva:0
                                                                         address:address
                                                                    errorMessage:&errorMessage];
    if (!payload) {
        [self _setStatus:errorMessage ?: VCTextLiteral(@"Could not resolve module + RVA.") color:kVCRed];
        return;
    }

    NSString *moduleName = VCMemoryBrowserSafeString(payload[@"moduleName"]);
    NSString *rva = VCMemoryBrowserSafeString(payload[@"rva"]);
    [self _showLocatorPayload:payload
                        title:VCTextLiteral(@"Module + RVA")
                     subtitle:(moduleName.length > 0 ? [NSString stringWithFormat:@"%@ • %@", moduleName, rva] : VCTextLiteral(@"Stable module-relative locator"))
                   statusText:[NSString stringWithFormat:VCTextLiteral(@"Resolved %@ into %@ %@"),
                               VCMemoryBrowserSafeString(payload[@"address"]),
                               moduleName.length > 0 ? moduleName : VCTextLiteral(@"module"),
                               rva]
                  statusColor:kVCAccent];
}

- (void)_showModuleRootLocatorForCurrentAddress {
    NSString *moduleName = VCMemoryBrowserSafeString(self.currentPayload[@"moduleName"]);
    NSString *rva = VCMemoryBrowserSafeString(self.currentPayload[@"rva"]);
    uint64_t baseOffset = strtoull(rva.UTF8String, NULL, 0);
    if (moduleName.length == 0 || baseOffset == 0) {
        [self _showRuntimeLocatorForCurrentAddress];
        return;
    }

    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryLocatorEngine shared] resolvePointerChainWithModuleName:moduleName
                                                                                   baseAddress:0
                                                                                    baseOffset:baseOffset
                                                                                       offsets:@[]
                                                                                  errorMessage:&errorMessage];
    if (!payload) {
        [self _setStatus:errorMessage ?: VCTextLiteral(@"Could not create the module root locator.") color:kVCRed];
        return;
    }

    NSMutableDictionary *locator = [payload mutableCopy];
    locator[@"locatorKind"] = @"module_root";
    locator[@"note"] = VCTextLiteral(@"Direct module-base + offset locator. This is stable, but it is not a deep pointer chain.");
    [self _showLocatorPayload:[locator copy]
                        title:VCTextLiteral(@"Module Root")
                     subtitle:[NSString stringWithFormat:@"%@ + %@", moduleName, rva]
                   statusText:[NSString stringWithFormat:VCTextLiteral(@"Created module root %@ + %@"), moduleName, rva]
                  statusColor:kVCAccent];
}

- (void)_showPointerReferencesForCurrentAddress {
    uint64_t address = [self _currentLoadedAddress];
    if (address == 0) {
        [self _setStatus:VCTextLiteral(@"Load an address before searching references.") color:kVCYellow];
        return;
    }

    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryLocatorEngine shared] findPointerReferencesToAddress:address
                                                                                      limit:12
                                                                           includeSecondHop:YES
                                                                               errorMessage:&errorMessage];
    if (!payload) {
        [self _setStatus:errorMessage ?: VCTextLiteral(@"Could not search pointer references.") color:kVCRed];
        return;
    }

    NSUInteger directCount = [payload[@"directReferenceCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"directReferenceCount"] unsignedIntegerValue] : 0;
    NSArray *chains = [payload[@"suggestedPointerChains"] isKindOfClass:[NSArray class]] ? payload[@"suggestedPointerChains"] : @[];
    UIColor *statusColor = directCount > 0 ? kVCAccent : kVCYellow;
    NSString *statusText = directCount > 0
        ? [NSString stringWithFormat:VCTextLiteral(@"Found %lu direct refs and %lu shallow chains"),
           (unsigned long)directCount,
           (unsigned long)chains.count]
        : VCTextLiteral(@"No pointer references found in readable non-executable memory.");
    [self _showLocatorPayload:payload
                        title:VCTextLiteral(@"Pointer Refs")
                     subtitle:VCTextLiteral(@"Reverse pointer hits and shallow chain suggestions.")
                   statusText:statusText
                  statusColor:statusColor];
}

- (void)_showSignatureLocatorForCurrentAddressWithLength:(NSUInteger)length {
    uint64_t address = [self _currentLoadedAddress];
    if (address == 0) {
        [self _setStatus:VCTextLiteral(@"Load an address before generating a signature.") color:kVCYellow];
        return;
    }

    NSData *data = [self _memoryDataAtAddress:address length:length];
    if (![data isKindOfClass:[NSData class]] || data.length == 0) {
        [self _setStatus:VCTextLiteral(@"Could not read enough bytes to generate a signature.") color:kVCRed];
        return;
    }

    NSString *signature = [self _signaturePatternFromData:data];
    NSString *moduleName = VCMemoryBrowserSafeString(self.currentPayload[@"moduleName"]);
    NSString *errorMessage = nil;
    NSDictionary *verification = [[VCMemoryLocatorEngine shared] scanSignature:signature
                                                                     moduleName:moduleName
                                                                          limit:8
                                                                   errorMessage:&errorMessage];
    if (!verification) {
        [self _setStatus:errorMessage ?: VCTextLiteral(@"Could not verify the generated signature.") color:kVCRed];
        return;
    }

    NSArray *matches = [verification[@"matches"] isKindOfClass:[NSArray class]] ? verification[@"matches"] : @[];
    NSMutableDictionary *payload = [@{
        @"locatorKind": @"signature",
        @"address": [NSString stringWithFormat:@"0x%llx", (unsigned long long)address],
        @"moduleName": moduleName ?: @"",
        @"signature": signature ?: @"",
        @"byteLength": @(data.length),
        @"returnedCount": verification[@"returnedCount"] ?: @(matches.count),
        @"matches": matches
    } mutableCopy];
    if (matches.count > 0) {
        payload[@"firstMatch"] = matches.firstObject;
    }
    payload[@"note"] = matches.count == 1
        ? VCTextLiteral(@"Unique signature candidate.")
        : VCTextLiteral(@"Signature is reusable, but review match count before patching.");

    NSString *status = matches.count == 1
        ? VCTextLiteral(@"Generated a unique signature candidate.")
        : [NSString stringWithFormat:VCTextLiteral(@"Generated a signature with %lu matches."), (unsigned long)matches.count];
    [self _showLocatorPayload:[payload copy]
                        title:VCTextLiteral(@"Signature")
                     subtitle:[NSString stringWithFormat:@"%@ bytes • %@", @(data.length), moduleName.length > 0 ? moduleName : VCTextLiteral(@"all modules")]
                   statusText:status
                  statusColor:(matches.count == 1 ? kVCAccent : kVCYellow)];
}

- (void)_refreshScanResultsPlaceholder {
    if (!self.scanEmptyLabel) return;
    self.scanEmptyLabel.hidden = self.scanCandidates.count > 0;
    self.scanEmptyLabel.text = self.scanCandidates.count > 0
        ? @""
        : ([[VCMemoryScanEngine shared] hasActiveSession]
           ? VCTextLiteral(@"No candidates on this page.\nRefine again, or refresh results\nafter the in-app value changes.")
           : VCTextLiteral(@"No candidates yet.\nStart a scan, change the in-app value,\nthen refine and tap a result."));
}

- (void)_executeMutationToolCallType:(VCToolCallType)type
                               title:(NSString *)title
                              params:(NSDictionary *)params
                         successText:(NSString *)successText
                              remark:(NSString *)remark {
    VCToolCall *toolCall = [VCToolCall new];
    toolCall.toolID = [[NSUUID UUID] UUIDString];
    toolCall.type = type;
    toolCall.title = title ?: @"tool";
    toolCall.params = params ?: @{};
    toolCall.remark = remark ?: @"";

    NSString *resultMessage = nil;
    BOOL success = [VCToolCallBlock executeToolCall:toolCall resultMessage:&resultMessage];
    if (!success) {
        [self _setStatus:resultMessage.length > 0 ? resultMessage : VCTextLiteral(@"Memory mutation failed.") color:kVCRed];
        return;
    }

    if (self.currentPayload[@"address"]) {
        [self _loadAddressString:VCMemoryBrowserSafeString(self.currentPayload[@"address"])];
    }
    [self _setStatus:successText.length > 0 ? successText : (resultMessage ?: VCTextLiteral(@"Mutation applied.")) color:kVCAccent];
}

- (UIViewController *)_hostViewController {
    UIResponder *responder = self;
    while (responder) {
        responder = responder.nextResponder;
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
    }
    return nil;
}

- (UIViewController *)_preferredPresenter {
    UIViewController *hostVisible = [VCOverlayRootViewController currentVisibleHostViewController];
    if (hostVisible) return hostVisible;
    return [self _hostViewController];
}

- (void)_setStatus:(NSString *)text color:(UIColor *)color {
    self.statusLabel.text = text ?: @"";
    self.statusLabel.textColor = color ?: kVCTextMuted;
}

- (NSUInteger)_selectedPageSize {
    switch (self.pageSizeControl.selectedSegmentIndex) {
        case 0: return 128;
        case 1: return 256;
        case 2: return 512;
        case 3: return 1024;
        default: return 256;
    }
}

- (void)_selectPageSize:(NSUInteger)pageSize {
    if (pageSize >= 1024) self.pageSizeControl.selectedSegmentIndex = 3;
    else if (pageSize >= 512) self.pageSizeControl.selectedSegmentIndex = 2;
    else if (pageSize >= 256) self.pageSizeControl.selectedSegmentIndex = 1;
    else self.pageSizeControl.selectedSegmentIndex = 0;
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.scanCandidates.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"scanCandidate";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.backgroundColor = UIColor.clearColor;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        cell.textLabel.textColor = kVCTextPrimary;
        cell.detailTextLabel.textColor = kVCTextMuted;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UIView *selected = [[UIView alloc] init];
        selected.backgroundColor = [kVCAccent colorWithAlphaComponent:0.12];
        cell.selectedBackgroundView = selected;
    }

    NSDictionary *candidate = indexPath.row < self.scanCandidates.count ? self.scanCandidates[indexPath.row] : nil;
    NSString *address = VCMemoryBrowserSafeString(candidate[@"address"]);
    NSString *dataType = VCMemoryBrowserSafeString(candidate[@"dataType"]);
    NSString *storedValue = VCMemoryBrowserSafeString(candidate[@"storedValue"]);
    NSString *currentValue = VCMemoryBrowserSafeString(candidate[@"currentValue"]);

    cell.textLabel.text = address.length > 0 ? address : VCTextLiteral(@"Unknown address");
    if (currentValue.length > 0 && ![currentValue isEqualToString:storedValue]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@ -> %@", dataType.length > 0 ? dataType : @"value", storedValue, currentValue];
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", dataType.length > 0 ? dataType : @"value", storedValue];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *candidate = indexPath.row < self.scanCandidates.count ? self.scanCandidates[indexPath.row] : nil;
    NSString *address = VCMemoryBrowserSafeString(candidate[@"address"]);
    if (address.length == 0) return;
    [self _loadAddressString:address];
    self.detailModeControl.selectedSegmentIndex = 0;
    [self _updateDetailMode];
    [self _setStatus:[NSString stringWithFormat:VCTextLiteral(@"Jumped to %@"), address] color:kVCAccent];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *candidate = indexPath.row < self.scanCandidates.count ? self.scanCandidates[indexPath.row] : nil;
    NSString *address = VCMemoryBrowserSafeString(candidate[@"address"]);
    if (address.length == 0) return nil;

    __weak __typeof__(self) weakSelf = self;
    UIContextualAction *rvaAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"RVA"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf _loadAddressString:address];
        [weakSelf _showRuntimeLocatorForCurrentAddress];
        completionHandler(YES);
    }];
    rvaAction.backgroundColor = kVCAccent;

    UIContextualAction *sigAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:@"Sig"
                                                                          handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf _loadAddressString:address];
        [weakSelf _showSignatureLocatorForCurrentAddressWithLength:12];
        completionHandler(YES);
    }];
    sigAction.backgroundColor = [kVCYellow colorWithAlphaComponent:0.9];

    UIContextualAction *refsAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                             title:@"Refs"
                                                                           handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf _loadAddressString:address];
        [weakSelf _showPointerReferencesForCurrentAddress];
        completionHandler(YES);
    }];
    refsAction.backgroundColor = [kVCAccentDim colorWithAlphaComponent:0.95];

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[rvaAction, sigAction, refsAction]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [UIView new];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 0.01;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self _refreshScanResultsPlaceholder];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self _refreshScanResultsPlaceholder];
}

@end
