/**
 * VCNetworkTab -- Network Tab
 * Request list + detail expand + filter + cURL export + resend
 */

#import "VCNetworkTab.h"
#import "../../../VansonCLI.h"
#import "../../Network/VCNetMonitor.h"
#import "../../Network/VCNetRecord.h"
#import "../../Patches/VCPatchManager.h"
#import "../../Patches/VCNetRule.h"
#import "../../Core/VCConfig.h"
#import "../../AI/Chat/VCChatSession.h"
#import "../Panel/VCPanel.h"

static NSString *const kCellID = @"NetCell";
static NSString *const kExpandedCellID = @"NetExpandedCell";

typedef NS_ENUM(NSInteger, VCNetFilter) {
    VCNetFilterAll = 0,
    VCNetFilterGET,
    VCNetFilterPOST,
    VCNetFilterWS,
};

typedef NS_ENUM(NSInteger, VCNetQuickScope) {
    VCNetQuickScopeAny = 0,
    VCNetQuickScopeErrors,
    VCNetQuickScopeSlow,
    VCNetQuickScopeModified,
};

typedef NS_ENUM(NSInteger, VCNetStatusScope) {
    VCNetStatusScopeAll = 0,
    VCNetStatusScope2xx,
    VCNetStatusScope4xx,
    VCNetStatusScope5xx,
};

typedef NS_ENUM(NSInteger, VCNetContentScope) {
    VCNetContentScopeAny = 0,
    VCNetContentScopeImage,
    VCNetContentScopeXHR,
    VCNetContentScopeJSON,
};

typedef NS_ENUM(NSInteger, VCNetExpandableFilterSection) {
    VCNetExpandableFilterSectionNone = -1,
    VCNetExpandableFilterSectionQuick = 0,
    VCNetExpandableFilterSectionStatus,
    VCNetExpandableFilterSectionContent,
};

typedef NS_ENUM(NSInteger, VCReplayBodyMode) {
    VCReplayBodyModeRaw = 0,
    VCReplayBodyModeJSON,
    VCReplayBodyModeForm,
};

typedef NS_ENUM(NSInteger, VCNetworkModalTab) {
    VCNetworkModalTabInfo = 0,
    VCNetworkModalTabParams,
    VCNetworkModalTabReplay,
};

@interface VCReplayDraft : NSObject
@property (nonatomic, copy) NSString *favoriteID;
@property (nonatomic, copy) NSString *favoriteName;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSArray<NSDictionary *> *queryItems;
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, assign) VCReplayBodyMode bodyMode;
@property (nonatomic, copy) NSString *hostKey;
@property (nonatomic, copy) NSString *statusBucket;
@property (nonatomic, copy) NSDictionary *exportSnapshot;
@property (nonatomic, strong) NSDate *createdAt;
+ (instancetype)draftFromRecord:(VCNetRecord *)record;
+ (instancetype)draftFromDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;
- (NSString *)displayName;
@end

@interface VCNetworkExpandedCell : UITableViewCell
@property (nonatomic, strong) UILabel *recordLabel;
@property (nonatomic, strong) UITextView *paramsTextView;
@property (nonatomic, strong) UITextView *bodyTextView;
@property (nonatomic, strong) UIButton *inlineReplayButton;
@property (nonatomic, strong) UIButton *workbenchButton;
@property (nonatomic, copy) void (^inlineReplayHandler)(NSString *paramsText, NSString *bodyText);
@property (nonatomic, copy) void (^workbenchHandler)(void);
- (void)configureWithDetail:(NSAttributedString *)detail
                 paramsText:(NSString *)paramsText
                   bodyText:(NSString *)bodyText
                  bodyTitle:(NSString *)bodyTitle
        inlineReplayHandler:(void(^)(NSString *paramsText, NSString *bodyText))inlineReplayHandler
           workbenchHandler:(void(^)(void))workbenchHandler;
@end

@interface VCNetworkTab () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, VCNetMonitorDelegate, VCPanelLayoutUpdatable>
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *captureBadgeLabel;
@property (nonatomic, strong) UISegmentedControl *filterCtrl;
@property (nonatomic, strong) UISegmentedControl *scopeCtrl;
@property (nonatomic, strong) UISegmentedControl *statusScopeCtrl;
@property (nonatomic, strong) UISegmentedControl *contentScopeCtrl;
@property (nonatomic, strong) UIStackView *filterSummaryStackView;
@property (nonatomic, strong) UIButton *scopeSummaryButton;
@property (nonatomic, strong) UIButton *statusSummaryButton;
@property (nonatomic, strong) UIButton *contentSummaryButton;
@property (nonatomic, strong) UIView *filterDetailContainer;
@property (nonatomic, strong) NSLayoutConstraint *filterDetailHeightConstraint;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIScrollView *hostScrollView;
@property (nonatomic, strong) UIStackView *hostStackView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *favoritesButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UIButton *harButton;
@property (nonatomic, strong) UIButton *regexButton;
@property (nonatomic, strong) UIView *contentDividerView;
@property (nonatomic, strong) NSLayoutConstraint *headerLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerBottomPortraitConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerBottomLandscapeConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerWidthLandscapeConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tableTopPortraitConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tableTopLandscapeConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tableLeadingPortraitConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tableLeadingLandscapeConstraint;
@property (nonatomic, strong) NSLayoutConstraint *statusLeadingPortraitConstraint;
@property (nonatomic, strong) NSLayoutConstraint *statusLeadingLandscapeConstraint;
@property (nonatomic, assign) CGRect availableLayoutBounds;
@property (nonatomic, strong) UIView *editorOverlay;
@property (nonatomic, strong) UIView *editorCard;
@property (nonatomic, strong) UIView *editorDock;
@property (nonatomic, strong) UIView *editorDockHandle;
@property (nonatomic, strong) UIButton *editorDockButton;
@property (nonatomic, strong) NSLayoutConstraint *editorDockWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *editorDockHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *editorDockLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *editorDockTopConstraint;
@property (nonatomic, strong) UIScrollView *editorScrollView;
@property (nonatomic, strong) UITextField *editorFavoriteNameField;
@property (nonatomic, strong) UITextField *editorMethodField;
@property (nonatomic, strong) UITextField *editorURLField;
@property (nonatomic, strong) UITextView *editorParamsView;
@property (nonatomic, strong) UITextView *editorHeadersView;
@property (nonatomic, strong) UITextView *editorBodyView;
@property (nonatomic, strong) UISegmentedControl *editorBodyModeControl;
@property (nonatomic, strong) UISegmentedControl *editorTabControl;
@property (nonatomic, strong) UIScrollView *editorInfoScrollView;
@property (nonatomic, strong) UIScrollView *editorParamsScrollView;
@property (nonatomic, strong) UITextView *editorOverviewView;
@property (nonatomic, strong) UITextView *editorInfoRequestHeadersView;
@property (nonatomic, strong) UITextView *editorInfoResponseHeadersView;
@property (nonatomic, strong) UITextView *editorInfoRequestBodyView;
@property (nonatomic, strong) UITextView *editorInfoResponseBodyView;
@property (nonatomic, strong) UITextView *editorInfoCurlView;
@property (nonatomic, strong) UITextView *editorInfoRulesView;
@property (nonatomic, strong) UITextView *editorParamsQueryView;
@property (nonatomic, strong) UITextView *editorParamsHeadersMirrorView;
@property (nonatomic, strong) UITextView *editorParamsBodyMirrorView;
@property (nonatomic, strong) UILabel *editorHintLabel;
@property (nonatomic, strong) UIButton *editorFavoriteButton;
@property (nonatomic, strong) UIButton *editorReplayButton;
@property (nonatomic, strong) UIButton *editorCancelButton;
@property (nonatomic, strong) UIView *regexOverlay;
@property (nonatomic, strong) UIView *regexCard;
@property (nonatomic, strong) UITextField *regexPatternField;
@property (nonatomic, strong) UITextView *regexSampleView;
@property (nonatomic, strong) UILabel *regexResultLabel;
@property (nonatomic, strong) NSArray<VCNetRecord *> *records;
@property (nonatomic, strong) NSArray<VCNetRecord *> *filteredRecords;
@property (nonatomic, strong) NSMutableArray<VCReplayDraft *> *favoriteRequests;
@property (nonatomic, strong) VCReplayDraft *editingDraft;
@property (nonatomic, strong) VCNetRecord *editingRecord;
@property (nonatomic, assign) NSInteger expandedRow;
@property (nonatomic, assign) BOOL showingFavorites;
@property (nonatomic, copy) NSString *selectedHostFilter;
@property (nonatomic, assign) VCNetExpandableFilterSection expandedFilterSection;
@property (nonatomic, strong) UIStackView *headerUtilityStack;
@property (nonatomic, strong) NSLayoutConstraint *filterControlHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *searchBarHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *filterSummaryHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *hostScrollHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *statusBarHeightConstraint;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@property (nonatomic, assign) BOOL compactLandscapeLayout;
@end

static NSString *VCNetStatusBucketForCode(NSInteger statusCode) {
    if (statusCode >= 500) return @"5xx";
    if (statusCode >= 400) return @"4xx";
    if (statusCode >= 200) return @"2xx";
    return @"other";
}

static NSString *VCNetCompactLine(NSString *text) {
    NSString *source = [text isKindOfClass:[NSString class]] ? text : @"";
    NSArray<NSString *> *parts = [source componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSString *> *tokens = [NSMutableArray new];
    for (NSString *part in parts) {
        if (part.length > 0) [tokens addObject:part];
    }
    return [tokens componentsJoinedByString:@" "];
}

static NSString *VCNetTruncatedText(NSString *text, NSUInteger limit) {
    NSString *source = [text isKindOfClass:[NSString class]] ? text : @"";
    if (source.length <= limit) return source;
    return [NSString stringWithFormat:@"%@\n... %@ chars", [source substringToIndex:limit], @(source.length)];
}

static NSString *VCNetPathSummary(NSString *urlString) {
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString ?: @""];
    if (!components) return urlString ?: @"";
    NSString *path = components.path.length ? components.path : @"/";
    if (components.query.length > 0) {
        return [NSString stringWithFormat:@"%@?%@", path, components.query];
    }
    return path;
}

static NSString *VCNetCompactPath(NSString *urlString, NSUInteger limit) {
    NSString *path = VCNetPathSummary(urlString);
    if (path.length <= limit) return path;
    NSUInteger headLength = MAX((NSUInteger)12, limit / 2);
    NSUInteger tailLength = MAX((NSUInteger)12, limit - headLength - 3);
    if (path.length <= headLength + tailLength + 3) return path;
    NSString *head = [path substringToIndex:headLength];
    NSString *tail = [path substringFromIndex:path.length - tailLength];
    return [NSString stringWithFormat:@"%@...%@", head, tail];
}

static NSString *VCNetBodySizeText(NSData *data) {
    NSUInteger bytes = [data isKindOfClass:[NSData class]] ? data.length : 0;
    if (bytes >= 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    if (bytes >= 1024) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%@ B", @(bytes)];
}

@implementation VCReplayDraft

+ (NSArray<NSDictionary *> *)_queryItemsFromURLString:(NSString *)urlString {
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString ?: @""];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        [items addObject:@{
            @"name": item.name ?: @"",
            @"value": item.value ?: @""
        }];
    }
    return items;
}

+ (NSDictionary *)_snapshotForRecord:(VCNetRecord *)record {
    if (!record) return @{};
    return @{
        @"request": @{
            @"method": record.method ?: @"GET",
            @"url": record.url ?: @"",
            @"headers": record.requestHeaders ?: @{},
            @"body": [record requestBodyAsString] ?: @""
        },
        @"response": @{
            @"status": @(record.statusCode),
            @"headers": record.responseHeaders ?: @{},
            @"body": [record responseBodyAsString] ?: @""
        }
    };
}

+ (instancetype)draftFromRecord:(VCNetRecord *)record {
    VCReplayDraft *draft = [[VCReplayDraft alloc] init];
    NSURL *url = [NSURL URLWithString:record.url ?: @""];
    draft.favoriteID = record.favoriteID ?: [[NSUUID UUID] UUIDString];
    draft.favoriteName = record.favoriteName ?: [NSString stringWithFormat:@"%@ %@", record.method ?: @"REQ", url.host ?: @"request"];
    draft.method = record.method ?: @"GET";
    draft.url = record.url ?: @"";
    draft.queryItems = [self _queryItemsFromURLString:record.url];
    draft.headers = record.requestHeaders ?: @{};
    NSString *bodyText = [record requestBodyAsString];
    draft.body = [bodyText isEqualToString:@"(empty)"] ? @"" : (bodyText ?: @"");
    draft.bodyMode = VCReplayBodyModeRaw;
    draft.hostKey = record.hostKey ?: (url.host ?: @"");
    draft.statusBucket = record.statusBucket ?: VCNetStatusBucketForCode(record.statusCode);
    draft.exportSnapshot = record.exportSnapshot ?: [self _snapshotForRecord:record];
    draft.createdAt = [NSDate date];
    return draft;
}

+ (instancetype)draftFromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    VCReplayDraft *draft = [[VCReplayDraft alloc] init];
    draft.favoriteID = [dictionary[@"favoriteId"] isKindOfClass:[NSString class]] ? dictionary[@"favoriteId"] : [[NSUUID UUID] UUIDString];
    draft.favoriteName = [dictionary[@"favoriteName"] isKindOfClass:[NSString class]] ? dictionary[@"favoriteName"] : @"Favorite";
    draft.method = [dictionary[@"method"] isKindOfClass:[NSString class]] ? dictionary[@"method"] : @"GET";
    draft.url = [dictionary[@"url"] isKindOfClass:[NSString class]] ? dictionary[@"url"] : @"";
    draft.queryItems = [dictionary[@"queryItems"] isKindOfClass:[NSArray class]] ? dictionary[@"queryItems"] : @[];
    draft.headers = [dictionary[@"headers"] isKindOfClass:[NSDictionary class]] ? dictionary[@"headers"] : @{};
    draft.body = [dictionary[@"body"] isKindOfClass:[NSString class]] ? dictionary[@"body"] : @"";
    NSInteger bodyMode = [dictionary[@"bodyMode"] respondsToSelector:@selector(integerValue)] ? [dictionary[@"bodyMode"] integerValue] : VCReplayBodyModeRaw;
    draft.bodyMode = (VCReplayBodyMode)MAX((NSInteger)VCReplayBodyModeRaw, MIN((NSInteger)VCReplayBodyModeForm, bodyMode));
    draft.hostKey = [dictionary[@"hostKey"] isKindOfClass:[NSString class]] ? dictionary[@"hostKey"] : ([NSURL URLWithString:draft.url].host ?: @"");
    draft.statusBucket = [dictionary[@"statusBucket"] isKindOfClass:[NSString class]] ? dictionary[@"statusBucket"] : @"other";
    draft.exportSnapshot = [dictionary[@"exportSnapshot"] isKindOfClass:[NSDictionary class]] ? dictionary[@"exportSnapshot"] : @{};
    NSNumber *timestamp = [dictionary[@"createdAt"] respondsToSelector:@selector(doubleValue)] ? dictionary[@"createdAt"] : nil;
    draft.createdAt = timestamp ? [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue] : [NSDate date];
    return draft;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"favoriteId": self.favoriteID ?: [[NSUUID UUID] UUIDString],
        @"favoriteName": self.favoriteName ?: [self displayName],
        @"method": self.method ?: @"GET",
        @"url": self.url ?: @"",
        @"queryItems": self.queryItems ?: @[],
        @"headers": self.headers ?: @{},
        @"body": self.body ?: @"",
        @"bodyMode": @(self.bodyMode),
        @"hostKey": self.hostKey ?: @"",
        @"statusBucket": self.statusBucket ?: @"other",
        @"exportSnapshot": self.exportSnapshot ?: @{},
        @"createdAt": @((self.createdAt ?: [NSDate date]).timeIntervalSince1970),
    };
}

- (NSString *)displayName {
    if (self.favoriteName.length > 0) return self.favoriteName;
    NSURL *url = [NSURL URLWithString:self.url ?: @""];
    return [NSString stringWithFormat:@"%@ %@", self.method ?: @"REQ", url.host ?: @"request"];
}

@end

@implementation VCNetworkExpandedCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.92];
        self.contentView.layer.cornerRadius = 10.0;
        self.contentView.layer.borderWidth = 1.0;
        self.contentView.layer.borderColor = kVCBorder.CGColor;

        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 8.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];

        _recordLabel = [[UILabel alloc] init];
        _recordLabel.numberOfLines = 0;
        _recordLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [stack addArrangedSubview:_recordLabel];

        UILabel *(^makeLabel)(NSString *) = ^UILabel *(NSString *title) {
            UILabel *label = [[UILabel alloc] init];
            label.text = title;
            label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
            label.textColor = kVCTextSecondary;
            return label;
        };

        UITextView *(^makeTextView)(CGFloat) = ^UITextView *(CGFloat height) {
            UITextView *textView = [[UITextView alloc] init];
            textView.font = kVCFontMonoSm;
            textView.textColor = kVCTextPrimary;
            textView.backgroundColor = kVCBgInput;
            textView.layer.cornerRadius = 9.0;
            textView.layer.borderWidth = 1.0;
            textView.layer.borderColor = kVCBorder.CGColor;
            textView.scrollEnabled = YES;
            textView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
            [textView.heightAnchor constraintGreaterThanOrEqualToConstant:height].active = YES;
            return textView;
        };

        [stack addArrangedSubview:makeLabel(VCTextLiteral(@"Inline Query Params"))];
        _paramsTextView = makeTextView(68.0);
        [stack addArrangedSubview:_paramsTextView];

        UILabel *bodyLabel = makeLabel(VCTextLiteral(@"Inline Body Params / Body"));
        bodyLabel.tag = 9011;
        [stack addArrangedSubview:bodyLabel];
        _bodyTextView = makeTextView(88.0);
        [stack addArrangedSubview:_bodyTextView];

        UIStackView *buttonRow = [[UIStackView alloc] init];
        buttonRow.axis = UILayoutConstraintAxisHorizontal;
        buttonRow.spacing = 8.0;
        buttonRow.distribution = UIStackViewDistributionFillEqually;
        [stack addArrangedSubview:buttonRow];

        _inlineReplayButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_inlineReplayButton setTitle:VCTextLiteral(@"Replay Inline") forState:UIControlStateNormal];
        VCApplyCompactAccentButtonStyle(_inlineReplayButton);
        [_inlineReplayButton addTarget:self action:@selector(_inlineReplayTapped) forControlEvents:UIControlEventTouchUpInside];
        [buttonRow addArrangedSubview:_inlineReplayButton];

        _workbenchButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_workbenchButton setTitle:VCTextLiteral(@"Workbench") forState:UIControlStateNormal];
        VCApplyCompactPrimaryButtonStyle(_workbenchButton);
        [_workbenchButton addTarget:self action:@selector(_workbenchTapped) forControlEvents:UIControlEventTouchUpInside];
        [buttonRow addArrangedSubview:_workbenchButton];

        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
            [_inlineReplayButton.heightAnchor constraintEqualToConstant:34.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.inlineReplayHandler = nil;
    self.workbenchHandler = nil;
}

- (void)configureWithDetail:(NSAttributedString *)detail
                 paramsText:(NSString *)paramsText
                   bodyText:(NSString *)bodyText
                  bodyTitle:(NSString *)bodyTitle
        inlineReplayHandler:(void(^)(NSString *paramsText, NSString *bodyText))inlineReplayHandler
           workbenchHandler:(void(^)(void))workbenchHandler {
    self.recordLabel.attributedText = detail;
    self.paramsTextView.text = paramsText ?: @"";
    self.bodyTextView.text = bodyText ?: @"";
    self.inlineReplayHandler = inlineReplayHandler;
    self.workbenchHandler = workbenchHandler;
    for (UIView *view in self.recordLabel.superview.subviews) {
        if ([view isKindOfClass:[UILabel class]] && view.tag == 9011) {
            ((UILabel *)view).text = bodyTitle.length > 0 ? bodyTitle : VCTextLiteral(@"Inline Body Params / Body");
            break;
        }
    }
}

- (void)_inlineReplayTapped {
    if (self.inlineReplayHandler) {
        self.inlineReplayHandler(self.paramsTextView.text ?: @"", self.bodyTextView.text ?: @"");
    }
}

- (void)_workbenchTapped {
    if (self.workbenchHandler) self.workbenchHandler();
}

@end

@implementation VCNetworkTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;
    _expandedRow = -1;
    _expandedFilterSection = VCNetExpandableFilterSectionNone;
    _records = @[];
    _filteredRecords = @[];
    _favoriteRequests = [NSMutableArray new];
    _currentLayoutMode = VCPanelLayoutModePortrait;
    _availableLayoutBounds = CGRectZero;

    [self _setupHeader];
    [self _setupFilterBar];
    [self _setupSearchBar];
    [self _setupTableView];
    [self _setupStatusBar];
    [self _setupEditorDockIfNeeded];
    [self _applyCurrentLayoutMode];
    VCInstallKeyboardDismissAccessory(self.view);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_languageDidChange) name:VCLanguageDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_patchManagerDidUpdate) name:VCPatchManagerDidUpdateNotification object:nil];

    [VCNetMonitor shared].delegate = self;
    [self _loadFavorites];
    [self _refreshLocalizedText];
    [self _refresh];
}

- (VCNetRecord *)_expandedRecord {
    if (self.expandedRow < 0 || self.expandedRow >= (NSInteger)self.filteredRecords.count) return nil;
    return self.filteredRecords[self.expandedRow];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_setupHeader {
    _headerCard = [[UIView alloc] init];
    VCApplyPanelSurface(_headerCard, 12.0);
    _headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerCard];

    _headerTitleLabel = [[UILabel alloc] init];
    _headerTitleLabel.textColor = kVCTextSecondary;
    _headerTitleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    _headerTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_headerTitleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    _headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_headerTitleLabel];

    _captureBadgeLabel = [[UILabel alloc] init];
    _captureBadgeLabel.textColor = kVCGreen;
    _captureBadgeLabel.backgroundColor = kVCGreenDim;
    _captureBadgeLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    _captureBadgeLabel.textAlignment = NSTextAlignmentCenter;
    _captureBadgeLabel.layer.cornerRadius = 14.0;
    _captureBadgeLabel.layer.borderWidth = 1.0;
    _captureBadgeLabel.layer.borderColor = [kVCGreen colorWithAlphaComponent:0.34].CGColor;
    _captureBadgeLabel.clipsToBounds = YES;
    _captureBadgeLabel.numberOfLines = 1;
    _captureBadgeLabel.minimumScaleFactor = 0.72;
    _captureBadgeLabel.adjustsFontSizeToFitWidth = YES;
    _captureBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_captureBadgeLabel];

    UIButton *(^makeUtilityButton)(NSString *, UIColor *, SEL) = ^UIButton *(NSString *title, UIColor *backgroundColor, SEL action) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:title forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        VCApplyButtonChrome(button,
                            kVCTextPrimary,
                            kVCTextPrimary,
                            backgroundColor,
                            kVCBorder,
                            10.0,
                            [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]);
        VCPrepareButtonTitle(button, NSLineBreakByTruncatingTail, 0.78);
        button.contentEdgeInsets = UIEdgeInsetsMake(4, 8, 4, 8);
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        [button.heightAnchor constraintEqualToConstant:28.0].active = YES;
        return button;
    };

    _harButton = makeUtilityButton(VCTextLiteral(@"HAR"), [kVCBgSecondary colorWithAlphaComponent:0.92], @selector(_exportHAR));
    VCSetButtonSymbol(_harButton, @"doc.text");
    _harButton.accessibilityLabel = VCTextLiteral(@"HAR");
    [_headerCard addSubview:_harButton];

    _regexButton = makeUtilityButton(VCTextLiteral(@"Regex"), [kVCBgSecondary colorWithAlphaComponent:0.92], @selector(_showRegexOverlay));
    VCSetButtonSymbol(_regexButton, @"text.magnifyingglass");
    _regexButton.accessibilityLabel = VCTextLiteral(@"Regex");
    [_headerCard addSubview:_regexButton];

    _favoritesButton = makeUtilityButton(VCTextLiteral(@"Fav"), kVCAccentDim, @selector(_toggleFavoritesMode));
    VCSetButtonSymbol(_favoritesButton, @"star");
    _favoritesButton.accessibilityLabel = VCTextLiteral(@"Favorites");
    [_headerCard addSubview:_favoritesButton];

    _clearButton = makeUtilityButton(VCTextLiteral(@"Clear"), [kVCBgSecondary colorWithAlphaComponent:0.92], @selector(_clearCurrentMode));
    VCSetButtonSymbol(_clearButton, @"trash");
    _clearButton.accessibilityLabel = VCTextLiteral(@"Clear");
    [_headerCard addSubview:_clearButton];

    self.headerUtilityStack = [[UIStackView alloc] initWithArrangedSubviews:@[_clearButton, _favoritesButton, _regexButton, _harButton]];
    self.headerUtilityStack.axis = UILayoutConstraintAxisHorizontal;
    self.headerUtilityStack.alignment = UIStackViewAlignmentFill;
    self.headerUtilityStack.distribution = UIStackViewDistributionFillEqually;
    self.headerUtilityStack.spacing = 6.0;
    self.headerUtilityStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:self.headerUtilityStack];

    [NSLayoutConstraint activateConstraints:@[
        [_headerCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [_headerTitleLabel.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:10],
        [_headerTitleLabel.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_headerTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_captureBadgeLabel.leadingAnchor constant:-8],
        [_captureBadgeLabel.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_captureBadgeLabel.centerYAnchor constraintEqualToAnchor:_headerTitleLabel.centerYAnchor],
        [self.headerUtilityStack.topAnchor constraintEqualToAnchor:_headerTitleLabel.bottomAnchor constant:7],
        [self.headerUtilityStack.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [self.headerUtilityStack.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_captureBadgeLabel.heightAnchor constraintEqualToConstant:22],
        [_captureBadgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:50],
    ]];
    self.headerLeadingConstraint = [_headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10];
    self.headerLeadingConstraint.active = YES;
    self.headerTrailingConstraint = [_headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10];
    self.headerTrailingConstraint.active = YES;
}

- (void)_setupFilterBar {
    _filterCtrl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"GET", @"POST", @"WS"]];
    _filterCtrl.selectedSegmentIndex = 0;
    _filterCtrl.selectedSegmentTintColor = kVCAccent;
    [_filterCtrl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
    [_filterCtrl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    [_filterCtrl addTarget:self action:@selector(_filterChanged) forControlEvents:UIControlEventValueChanged];
    _filterCtrl.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_filterCtrl];

    [NSLayoutConstraint activateConstraints:@[
        [_filterCtrl.topAnchor constraintEqualToAnchor:self.headerUtilityStack.bottomAnchor constant:8],
        [_filterCtrl.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_filterCtrl.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
    ]];
    self.filterControlHeightConstraint = [_filterCtrl.heightAnchor constraintEqualToConstant:30];
    self.filterControlHeightConstraint.active = YES;
}

- (void)_setupSearchBar {
    _searchBar = [[UISearchBar alloc] init];
    VCApplyReadableSearchPlaceholder(_searchBar, VCTextLiteral(@"Filter URL, host, status"));
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.delegate = self;
    _searchBar.clipsToBounds = NO;
    UITextField *tf = [_searchBar valueForKey:@"searchField"];
    if (tf) {
        VCApplyInputSurface(tf, 11.0);
        tf.textColor = kVCTextPrimary;
        tf.font = [UIFont systemFontOfSize:13];
        tf.layer.masksToBounds = YES;
    }
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_searchBar];

    UIButton *(^makeSummaryButton)(NSInteger) = ^UIButton *(NSInteger tag) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        button.titleLabel.numberOfLines = 2;
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        VCApplyButtonChrome(button,
                            kVCTextPrimary,
                            kVCTextPrimary,
                            kVCBgInput,
                            kVCBorder,
                            10.0,
                            [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]);
        button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        button.titleLabel.minimumScaleFactor = 0.78;
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.contentEdgeInsets = UIEdgeInsetsMake(6, 8, 6, 8);
        button.tag = tag;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button addTarget:self action:@selector(_toggleExpandedFilterSection:) forControlEvents:UIControlEventTouchUpInside];
        return button;
    };

    _scopeSummaryButton = makeSummaryButton(VCNetExpandableFilterSectionQuick);
    _statusSummaryButton = makeSummaryButton(VCNetExpandableFilterSectionStatus);
    _contentSummaryButton = makeSummaryButton(VCNetExpandableFilterSectionContent);

    _filterSummaryStackView = [[UIStackView alloc] initWithArrangedSubviews:@[_scopeSummaryButton, _statusSummaryButton, _contentSummaryButton]];
    _filterSummaryStackView.axis = UILayoutConstraintAxisHorizontal;
    _filterSummaryStackView.alignment = UIStackViewAlignmentFill;
    _filterSummaryStackView.distribution = UIStackViewDistributionFillEqually;
    _filterSummaryStackView.spacing = 6.0;
    _filterSummaryStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_filterSummaryStackView];

    _scopeCtrl = [[UISegmentedControl alloc] initWithItems:@[@"Any", @"Err", @"Slow", @"Mod"]];
    _scopeCtrl.selectedSegmentIndex = 0;
    _scopeCtrl.selectedSegmentTintColor = UIColorFromHex(0x0f766e);
    [_scopeCtrl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [_scopeCtrl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    [_scopeCtrl addTarget:self action:@selector(_filterChanged) forControlEvents:UIControlEventValueChanged];
    _scopeCtrl.translatesAutoresizingMaskIntoConstraints = NO;

    _statusScopeCtrl = [[UISegmentedControl alloc] initWithItems:@[@"Any", @"2xx", @"4xx", @"5xx"]];
    _statusScopeCtrl.selectedSegmentIndex = 0;
    _statusScopeCtrl.selectedSegmentTintColor = UIColorFromHex(0x4338ca);
    [_statusScopeCtrl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [_statusScopeCtrl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    [_statusScopeCtrl addTarget:self action:@selector(_filterChanged) forControlEvents:UIControlEventValueChanged];
    _statusScopeCtrl.translatesAutoresizingMaskIntoConstraints = NO;

    _contentScopeCtrl = [[UISegmentedControl alloc] initWithItems:@[@"Any", @"Img", @"XHR", @"JSON"]];
    _contentScopeCtrl.selectedSegmentIndex = 0;
    _contentScopeCtrl.selectedSegmentTintColor = UIColorFromHex(0x1d4ed8);
    [_contentScopeCtrl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [_contentScopeCtrl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    [_contentScopeCtrl addTarget:self action:@selector(_filterChanged) forControlEvents:UIControlEventValueChanged];
    _contentScopeCtrl.translatesAutoresizingMaskIntoConstraints = NO;

    _filterDetailContainer = [[UIView alloc] init];
    _filterDetailContainer.clipsToBounds = YES;
    _filterDetailContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_filterDetailContainer];
    [_filterDetailContainer addSubview:_scopeCtrl];
    [_filterDetailContainer addSubview:_statusScopeCtrl];
    [_filterDetailContainer addSubview:_contentScopeCtrl];

    _hostScrollView = [[UIScrollView alloc] init];
    _hostScrollView.showsHorizontalScrollIndicator = NO;
    _hostScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_hostScrollView];

    _hostStackView = [[UIStackView alloc] init];
    _hostStackView.axis = UILayoutConstraintAxisHorizontal;
    _hostStackView.spacing = 6.0;
    _hostStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [_hostScrollView addSubview:_hostStackView];

    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:_filterCtrl.bottomAnchor constant:8],
        [_searchBar.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:6],
        [_searchBar.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-6],
        [_filterSummaryStackView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:8],
        [_filterSummaryStackView.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_filterSummaryStackView.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_filterDetailContainer.topAnchor constraintEqualToAnchor:_filterSummaryStackView.bottomAnchor],
        [_filterDetailContainer.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_filterDetailContainer.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_scopeCtrl.heightAnchor constraintEqualToConstant:28],
        [_scopeCtrl.topAnchor constraintEqualToAnchor:_filterDetailContainer.topAnchor constant:4],
        [_scopeCtrl.leadingAnchor constraintEqualToAnchor:_filterDetailContainer.leadingAnchor],
        [_scopeCtrl.trailingAnchor constraintEqualToAnchor:_filterDetailContainer.trailingAnchor],
        [_statusScopeCtrl.heightAnchor constraintEqualToConstant:28],
        [_statusScopeCtrl.topAnchor constraintEqualToAnchor:_filterDetailContainer.topAnchor constant:4],
        [_statusScopeCtrl.leadingAnchor constraintEqualToAnchor:_filterDetailContainer.leadingAnchor],
        [_statusScopeCtrl.trailingAnchor constraintEqualToAnchor:_filterDetailContainer.trailingAnchor],
        [_contentScopeCtrl.heightAnchor constraintEqualToConstant:28],
        [_contentScopeCtrl.topAnchor constraintEqualToAnchor:_filterDetailContainer.topAnchor constant:4],
        [_contentScopeCtrl.leadingAnchor constraintEqualToAnchor:_filterDetailContainer.leadingAnchor],
        [_contentScopeCtrl.trailingAnchor constraintEqualToAnchor:_filterDetailContainer.trailingAnchor],
        [_hostScrollView.topAnchor constraintEqualToAnchor:_filterDetailContainer.bottomAnchor constant:8],
        [_hostScrollView.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_hostScrollView.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_hostStackView.topAnchor constraintEqualToAnchor:_hostScrollView.contentLayoutGuide.topAnchor],
        [_hostStackView.leadingAnchor constraintEqualToAnchor:_hostScrollView.contentLayoutGuide.leadingAnchor],
        [_hostStackView.trailingAnchor constraintEqualToAnchor:_hostScrollView.contentLayoutGuide.trailingAnchor],
        [_hostStackView.bottomAnchor constraintEqualToAnchor:_hostScrollView.contentLayoutGuide.bottomAnchor],
        [_hostStackView.heightAnchor constraintEqualToAnchor:_hostScrollView.frameLayoutGuide.heightAnchor],
    ]];
    self.searchBarHeightConstraint = [_searchBar.heightAnchor constraintEqualToConstant:36];
    self.searchBarHeightConstraint.active = YES;
    self.filterSummaryHeightConstraint = [_filterSummaryStackView.heightAnchor constraintEqualToConstant:44];
    self.filterSummaryHeightConstraint.active = YES;
    self.hostScrollHeightConstraint = [_hostScrollView.heightAnchor constraintEqualToConstant:28];
    self.hostScrollHeightConstraint.active = YES;

    self.filterDetailHeightConstraint = [_filterDetailContainer.heightAnchor constraintEqualToConstant:0];
    self.filterDetailHeightConstraint.active = YES;
    self.scopeCtrl.hidden = YES;
    self.statusScopeCtrl.hidden = YES;
    self.contentScopeCtrl.hidden = YES;
    [self _updateFilterSummaryButtons];

    self.contentDividerView = [[UIView alloc] init];
    self.contentDividerView.backgroundColor = [kVCBorderStrong colorWithAlphaComponent:0.34];
    self.contentDividerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentDividerView.hidden = YES;
    self.contentDividerView.alpha = 0.0;
    [self.view addSubview:self.contentDividerView];
}

- (void)_setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _tableView.contentInset = UIEdgeInsetsMake(6, 0, 12, 0);
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellID];
    [_tableView registerClass:[VCNetworkExpandedCell class] forCellReuseIdentifier:kExpandedCellID];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    self.tableTopPortraitConstraint = [_tableView.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:8];
    self.tableTopPortraitConstraint.active = YES;
    self.tableTopLandscapeConstraint = [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10];
    self.tableLeadingPortraitConstraint = [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor];
    self.tableLeadingPortraitConstraint.active = YES;
    self.tableLeadingLandscapeConstraint = [_tableView.leadingAnchor constraintEqualToAnchor:self.contentDividerView.trailingAnchor constant:5.5];
}

- (void)_setupStatusBar {
    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _statusLabel.textColor = kVCTextPrimary;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    VCApplyPanelSurface(_statusLabel, 10.0);
    _statusLabel.clipsToBounds = YES;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_statusLabel.topAnchor constraintEqualToAnchor:_tableView.bottomAnchor],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10],
    ]];
    self.statusBarHeightConstraint = [_statusLabel.heightAnchor constraintEqualToConstant:28];
    self.statusBarHeightConstraint.active = YES;
    self.statusLeadingPortraitConstraint = [_statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10];
    self.statusLeadingPortraitConstraint.active = YES;
    self.statusLeadingLandscapeConstraint = [_statusLabel.leadingAnchor constraintEqualToAnchor:self.contentDividerView.trailingAnchor constant:10];
    self.headerBottomPortraitConstraint = [_headerCard.bottomAnchor constraintEqualToAnchor:_hostScrollView.bottomAnchor constant:8];
    self.headerBottomPortraitConstraint.active = YES;
    self.headerBottomLandscapeConstraint = [_headerCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10];
    self.headerWidthLandscapeConstraint = [_headerCard.widthAnchor constraintEqualToConstant:300];
    [NSLayoutConstraint activateConstraints:@[
        [self.contentDividerView.widthAnchor constraintEqualToConstant:1.0],
        [self.contentDividerView.leadingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:5.5],
        [self.contentDividerView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:14.0],
        [self.contentDividerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-14.0],
    ]];
}

- (void)_applyCurrentLayoutMode {
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape);
    CGFloat boundsWidth = CGRectIsEmpty(self.availableLayoutBounds) ? CGRectGetWidth(self.view.bounds) : CGRectGetWidth(self.availableLayoutBounds);
    CGFloat boundsHeight = CGRectIsEmpty(self.availableLayoutBounds) ? CGRectGetHeight(self.view.bounds) : CGRectGetHeight(self.availableLayoutBounds);
    BOOL compactLandscape = landscape && boundsHeight > 0.0 && boundsHeight < 280.0;
    self.compactLandscapeLayout = compactLandscape;
    self.headerTitleLabel.font = [UIFont systemFontOfSize:(landscape ? 9.0 : 10.0) weight:UIFontWeightBold];
    self.captureBadgeLabel.font = [UIFont systemFontOfSize:(landscape ? 9.0 : 10.0) weight:UIFontWeightSemibold];
    self.headerUtilityStack.spacing = landscape ? 5.0 : 6.0;
    self.filterControlHeightConstraint.constant = landscape ? 28.0 : 30.0;
    self.searchBarHeightConstraint.constant = compactLandscape ? 34.0 : (landscape ? 36.0 : 38.0);
    self.filterSummaryHeightConstraint.constant = compactLandscape ? 30.0 : (landscape ? 38.0 : 44.0);
    self.hostScrollHeightConstraint.constant = compactLandscape ? 22.0 : (landscape ? 24.0 : 28.0);
    self.statusBarHeightConstraint.constant = landscape ? 24.0 : 28.0;
    self.statusLabel.font = [UIFont systemFontOfSize:(landscape ? 10.0 : 11.0) weight:UIFontWeightSemibold];
    self.statusLabel.numberOfLines = 1;
    [self.favoritesButton setTitle:(compactLandscape ? @"" : (self.showingFavorites ? [NSString stringWithFormat:@"Fav %lu", (unsigned long)self.favoriteRequests.count] : VCTextLiteral(@"Fav"))) forState:UIControlStateNormal];
    [self.regexButton setTitle:(compactLandscape ? @"" : VCTextLiteral(@"Regex")) forState:UIControlStateNormal];
    [self.harButton setTitle:(compactLandscape ? @"" : VCTextLiteral(@"HAR")) forState:UIControlStateNormal];
    [self.clearButton setTitle:(compactLandscape ? @"" : VCTextLiteral(@"Clear")) forState:UIControlStateNormal];
    for (UIButton *button in @[self.clearButton, self.favoritesButton, self.regexButton, self.harButton]) {
        button.titleLabel.font = [UIFont systemFontOfSize:(landscape ? 9.0 : 10.0) weight:UIFontWeightSemibold];
        button.contentEdgeInsets = compactLandscape ? UIEdgeInsetsMake(3, 3, 3, 3) : (landscape ? UIEdgeInsetsMake(3, 5, 3, 5) : UIEdgeInsetsMake(4, 6, 4, 6));
        button.imageEdgeInsets = UIEdgeInsetsZero;
        button.titleEdgeInsets = UIEdgeInsetsZero;
    }
    for (UIButton *button in @[self.scopeSummaryButton, self.statusSummaryButton, self.contentSummaryButton]) {
        button.titleLabel.numberOfLines = compactLandscape ? 1 : 2;
        button.contentEdgeInsets = compactLandscape ? UIEdgeInsetsMake(4, 5, 4, 5) : UIEdgeInsetsMake(6, 8, 6, 8);
    }
    self.headerTrailingConstraint.active = !landscape;
    self.headerBottomPortraitConstraint.active = !landscape;
    self.headerBottomLandscapeConstraint.active = landscape;
    self.headerWidthLandscapeConstraint.active = landscape;
    self.tableTopPortraitConstraint.active = !landscape;
    self.tableTopLandscapeConstraint.active = landscape;
    self.tableLeadingPortraitConstraint.active = !landscape;
    self.tableLeadingLandscapeConstraint.active = landscape;
    self.statusLeadingPortraitConstraint.active = !landscape;
    self.statusLeadingLandscapeConstraint.active = landscape;
    self.contentDividerView.hidden = !landscape;
    self.contentDividerView.alpha = landscape ? 1.0 : 0.0;
    if (landscape) {
        self.headerWidthLandscapeConstraint.constant = compactLandscape
            ? MIN(MAX(floor(boundsWidth * 0.34), 252.0), 312.0)
            : MIN(MAX(floor(boundsWidth * 0.32), 268.0), 344.0);
    }
    UITextField *tf = [self.searchBar valueForKey:@"searchField"];
    if (tf) {
        tf.font = [UIFont systemFontOfSize:(landscape ? 12.0 : 13.0)];
        tf.layer.cornerRadius = landscape ? 10.0 : 11.0;
    }
    self.tableView.contentInset = landscape ? UIEdgeInsetsMake(4, 0, 8, 0) : UIEdgeInsetsMake(6, 0, 12, 0);
    [self _updateFilterSummaryButtons];
    [self _layoutEditorDock];
    [self _refreshEditorDock];
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    self.availableLayoutBounds = bounds;
    [self _applyCurrentLayoutMode];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self _layoutEditorDock];
}

- (UIColor *)_filterAccentColorForSection:(VCNetExpandableFilterSection)section {
    switch (section) {
        case VCNetExpandableFilterSectionQuick: return UIColorFromHex(0x0f766e);
        case VCNetExpandableFilterSectionStatus: return UIColorFromHex(0x4338ca);
        case VCNetExpandableFilterSectionContent: return UIColorFromHex(0x1d4ed8);
        default: return kVCBorderStrong;
    }
}

- (NSString *)_summaryValueForQuickScope {
    switch ((VCNetQuickScope)self.scopeCtrl.selectedSegmentIndex) {
        case VCNetQuickScopeErrors: return VCTextLiteral(@"Err");
        case VCNetQuickScopeSlow: return VCTextLiteral(@"Slow");
        case VCNetQuickScopeModified: return VCTextLiteral(@"Mod");
        default: return VCTextLiteral(@"Any");
    }
}

- (NSString *)_summaryValueForStatusScope {
    switch ((VCNetStatusScope)self.statusScopeCtrl.selectedSegmentIndex) {
        case VCNetStatusScope2xx: return @"2xx";
        case VCNetStatusScope4xx: return @"4xx";
        case VCNetStatusScope5xx: return @"5xx";
        default: return VCTextLiteral(@"Any");
    }
}

- (NSString *)_summaryValueForContentScope {
    switch ((VCNetContentScope)self.contentScopeCtrl.selectedSegmentIndex) {
        case VCNetContentScopeImage: return VCTextLiteral(@"Img");
        case VCNetContentScopeXHR: return VCTextLiteral(@"XHR");
        case VCNetContentScopeJSON: return VCTextLiteral(@"JSON");
        default: return VCTextLiteral(@"Any");
    }
}

- (UIButton *)_summaryButtonForSection:(VCNetExpandableFilterSection)section {
    switch (section) {
        case VCNetExpandableFilterSectionQuick: return self.scopeSummaryButton;
        case VCNetExpandableFilterSectionStatus: return self.statusSummaryButton;
        case VCNetExpandableFilterSectionContent: return self.contentSummaryButton;
        default: return nil;
    }
}

- (void)_updateFilterSummaryButtons {
    NSArray<NSDictionary *> *buttonConfigs = @[
        @{@"section": @(VCNetExpandableFilterSectionQuick), @"title": VCTextLiteral(@"Scope"), @"value": [self _summaryValueForQuickScope], @"selected": @((NSInteger)self.scopeCtrl.selectedSegmentIndex > 0)},
        @{@"section": @(VCNetExpandableFilterSectionStatus), @"title": VCTextLiteral(@"Status"), @"value": [self _summaryValueForStatusScope], @"selected": @((NSInteger)self.statusScopeCtrl.selectedSegmentIndex > 0)},
        @{@"section": @(VCNetExpandableFilterSectionContent), @"title": VCTextLiteral(@"Content"), @"value": [self _summaryValueForContentScope], @"selected": @((NSInteger)self.contentScopeCtrl.selectedSegmentIndex > 0)},
    ];

    for (NSDictionary *config in buttonConfigs) {
        VCNetExpandableFilterSection section = (VCNetExpandableFilterSection)[config[@"section"] integerValue];
        UIButton *button = [self _summaryButtonForSection:section];
        if (!button) continue;
        BOOL isExpanded = self.expandedFilterSection == section;
        BOOL hasSelection = [config[@"selected"] boolValue];
        UIColor *accent = [self _filterAccentColorForSection:section];
        NSString *title = self.compactLandscapeLayout
            ? [NSString stringWithFormat:@"%@ %@", config[@"title"], config[@"value"]]
            : [NSString stringWithFormat:@"%@\n%@", config[@"title"], config[@"value"]];
        [button setTitle:title forState:UIControlStateNormal];
        [button setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
        button.backgroundColor = isExpanded ? [accent colorWithAlphaComponent:0.22] : (hasSelection ? [accent colorWithAlphaComponent:0.14] : kVCBgInput);
        button.layer.borderColor = (isExpanded || hasSelection ? [accent colorWithAlphaComponent:0.72].CGColor : kVCBorder.CGColor);
        button.alpha = (isExpanded || hasSelection) ? 1.0 : 0.94;
        button.titleLabel.minimumScaleFactor = 0.75;
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
    }
}

- (void)_setExpandedFilterSection:(VCNetExpandableFilterSection)section animated:(BOOL)animated {
    _expandedFilterSection = section;
    self.scopeCtrl.hidden = section != VCNetExpandableFilterSectionQuick;
    self.statusScopeCtrl.hidden = section != VCNetExpandableFilterSectionStatus;
    self.contentScopeCtrl.hidden = section != VCNetExpandableFilterSectionContent;
    self.filterDetailHeightConstraint.constant = (section == VCNetExpandableFilterSectionNone) ? 0 : 36;

    void (^changes)(void) = ^{
        [self _updateFilterSummaryButtons];
        [self.view layoutIfNeeded];
    };
    if (animated) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:changes completion:nil];
    } else {
        changes();
    }
}

- (void)_toggleExpandedFilterSection:(UIButton *)sender {
    VCNetExpandableFilterSection section = (VCNetExpandableFilterSection)sender.tag;
    VCNetExpandableFilterSection nextSection = (self.expandedFilterSection == section) ? VCNetExpandableFilterSectionNone : section;
    [self _setExpandedFilterSection:nextSection animated:YES];
}

- (void)_refreshLocalizedText {
    self.headerTitleLabel.text = VCTextLiteral(@"NETWORK");
    [self _updateCaptureBadge];
    [self.harButton setTitle:VCTextLiteral(@"HAR") forState:UIControlStateNormal];
    [self.regexButton setTitle:VCTextLiteral(@"Regex") forState:UIControlStateNormal];
    VCApplyReadableSearchPlaceholder(self.searchBar, VCTextLiteral(@"Filter URL, host, status"));

    NSArray<NSString *> *filterTitles = @[@"All", @"GET", @"POST", @"WS"];
    for (NSUInteger idx = 0; idx < filterTitles.count; idx++) {
        [self.filterCtrl setTitle:VCTextLiteral(filterTitles[idx]) forSegmentAtIndex:idx];
    }
    NSArray<NSString *> *quickTitles = @[@"Any", @"Err", @"Slow", @"Mod"];
    for (NSUInteger idx = 0; idx < quickTitles.count; idx++) {
        [self.scopeCtrl setTitle:VCTextLiteral(quickTitles[idx]) forSegmentAtIndex:idx];
    }
    NSArray<NSString *> *statusTitles = @[@"Any", @"2xx", @"4xx", @"5xx"];
    for (NSUInteger idx = 0; idx < statusTitles.count; idx++) {
        [self.statusScopeCtrl setTitle:VCTextLiteral(statusTitles[idx]) forSegmentAtIndex:idx];
    }
    NSArray<NSString *> *contentTitles = @[@"Any", @"Img", @"XHR", @"JSON"];
    for (NSUInteger idx = 0; idx < contentTitles.count; idx++) {
        [self.contentScopeCtrl setTitle:VCTextLiteral(contentTitles[idx]) forSegmentAtIndex:idx];
    }
    [self _updateFilterSummaryButtons];
    [self _updateFavoritesButton];
}

- (void)_languageDidChange {
    [self _refreshLocalizedText];
    [self _applyFilter];
}

- (NSUInteger)_activeRuleCount {
    NSUInteger count = 0;
    for (VCNetRule *rule in [[VCPatchManager shared] allRules] ?: @[]) {
        if (rule.enabled && !rule.isDisabledBySafeMode) count++;
    }
    return count;
}

- (void)_updateCaptureBadge {
    NSUInteger count = [self _activeRuleCount];
    self.captureBadgeLabel.text = [NSString stringWithFormat:VCTextLiteral(@"%lu rules"), (unsigned long)count];
    BOOL hasRules = count > 0;
    UIColor *accent = hasRules ? kVCAccent : kVCGreen;
    self.captureBadgeLabel.textColor = accent;
    self.captureBadgeLabel.backgroundColor = [accent colorWithAlphaComponent:0.13];
    self.captureBadgeLabel.layer.borderColor = [accent colorWithAlphaComponent:0.42].CGColor;
}

- (void)_patchManagerDidUpdate {
    [self _updateCaptureBadge];
    [self _applyFilter];
}

- (void)_setupEditorOverlayIfNeeded {
    if (self.editorOverlay) return;

    UIView *overlay = [[UIView alloc] init];
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.56];
    overlay.hidden = YES;
    overlay.alpha = 0;
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:overlay];
    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    self.editorOverlay = overlay;

    self.editorCard = [[UIView alloc] init];
    self.editorCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    self.editorCard.layer.cornerRadius = 16.0;
    self.editorCard.layer.borderWidth = 1.0;
    self.editorCard.layer.borderColor = kVCBorderStrong.CGColor;
    self.editorCard.translatesAutoresizingMaskIntoConstraints = NO;
    [overlay addSubview:self.editorCard];

    UILabel *title = [[UILabel alloc] init];
    title.text = VCTextLiteral(@"Replay Workbench");
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    title.textColor = kVCTextPrimary;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorCard addSubview:title];

    self.editorHintLabel = [[UILabel alloc] init];
    self.editorHintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.editorHintLabel.textColor = kVCTextSecondary;
    self.editorHintLabel.numberOfLines = 3;
    self.editorHintLabel.text = VCTextLiteral(@"Replay with edited request fields.");
    self.editorHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorCard addSubview:self.editorHintLabel];

    self.editorTabControl = [[UISegmentedControl alloc] initWithItems:@[VCTextLiteral(@"Info"), VCTextLiteral(@"Params"), VCTextLiteral(@"Replay")]];
    self.editorTabControl.selectedSegmentIndex = VCNetworkModalTabInfo;
    self.editorTabControl.selectedSegmentTintColor = kVCAccent;
    [self.editorTabControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [self.editorTabControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    self.editorTabControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorTabControl addTarget:self action:@selector(_editorTabChanged:) forControlEvents:UIControlEventValueChanged];
    [self.editorCard addSubview:self.editorTabControl];

    UITextField *(^makeField)(NSString *, NSString *) = ^UITextField *(NSString *title, NSString *placeholder) {
        UITextField *field = [[UITextField alloc] init];
        VCApplyReadablePlaceholder(field, placeholder);
        field.font = [UIFont systemFontOfSize:13];
        field.textColor = kVCTextPrimary;
        field.backgroundColor = kVCBgInput;
        field.layer.cornerRadius = 11.0;
        field.layer.borderWidth = 1.0;
        field.layer.borderColor = kVCBorder.CGColor;
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 94, 34)];
        label.text = title;
        label.textColor = kVCTextSecondary;
        label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.76;
        UIView *leftWrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 102, 34)];
        [leftWrap addSubview:label];
        field.leftView = leftWrap;
        field.leftViewMode = UITextFieldViewModeAlways;
        field.translatesAutoresizingMaskIntoConstraints = NO;
        return field;
    };

    UITextView *(^makeTextView)(CGFloat) = ^UITextView *(CGFloat minHeight) {
        UITextView *tv = [[UITextView alloc] init];
        tv.font = kVCFontMonoSm;
        tv.textColor = kVCTextPrimary;
        tv.backgroundColor = kVCBgInput;
        tv.layer.cornerRadius = 12.0;
        tv.layer.borderWidth = 1.0;
        tv.layer.borderColor = kVCBorder.CGColor;
        tv.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
        tv.translatesAutoresizingMaskIntoConstraints = NO;
        [tv.heightAnchor constraintGreaterThanOrEqualToConstant:minHeight].active = YES;
        return tv;
    };

    UILabel *(^makeSectionLabel)(NSString *) = ^UILabel *(NSString *text) {
        UILabel *label = [[UILabel alloc] init];
        label.text = text ?: @"";
        label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        label.textColor = kVCTextSecondary;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        return label;
    };

    UIScrollView *(^makeModalScrollView)(void) = ^UIScrollView *{
        UIScrollView *scrollView = [[UIScrollView alloc] init];
        scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
        scrollView.hidden = YES;
        scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.editorCard addSubview:scrollView];
        return scrollView;
    };

    UIStackView *(^makeModalStack)(UIScrollView *) = ^UIStackView *(UIScrollView *scrollView) {
        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [scrollView addSubview:contentView];

        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 8.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
            [contentView.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],
            [stack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        ]];
        return stack;
    };

    self.editorScrollView = [[UIScrollView alloc] init];
    self.editorScrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.editorScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorCard addSubview:self.editorScrollView];

    self.editorInfoScrollView = makeModalScrollView();
    UIStackView *infoStack = makeModalStack(self.editorInfoScrollView);
    self.editorOverviewView = makeTextView(76);
    self.editorOverviewView.editable = NO;
    self.editorInfoRequestHeadersView = makeTextView(92);
    self.editorInfoRequestHeadersView.editable = NO;
    self.editorInfoResponseHeadersView = makeTextView(92);
    self.editorInfoResponseHeadersView.editable = NO;
    self.editorInfoRequestBodyView = makeTextView(110);
    self.editorInfoRequestBodyView.editable = NO;
    self.editorInfoResponseBodyView = makeTextView(132);
    self.editorInfoResponseBodyView.editable = NO;
    self.editorInfoCurlView = makeTextView(86);
    self.editorInfoCurlView.editable = NO;
    self.editorInfoRulesView = makeTextView(62);
    self.editorInfoRulesView.editable = NO;
    [infoStack addArrangedSubview:makeSectionLabel(VCTextLiteral(@"Overview"))];
    [infoStack addArrangedSubview:self.editorOverviewView];
    [infoStack addArrangedSubview:makeSectionLabel(VCTextLiteral(@"Request Headers"))];
    [infoStack addArrangedSubview:self.editorInfoRequestHeadersView];
    [infoStack addArrangedSubview:makeSectionLabel(VCTextLiteral(@"Response Headers"))];
    [infoStack addArrangedSubview:self.editorInfoResponseHeadersView];
    [infoStack addArrangedSubview:makeSectionLabel(VCTextLiteral(@"Request Body"))];
    [infoStack addArrangedSubview:self.editorInfoRequestBodyView];
    [infoStack addArrangedSubview:makeSectionLabel(VCTextLiteral(@"Response Body"))];
    [infoStack addArrangedSubview:self.editorInfoResponseBodyView];
    [infoStack addArrangedSubview:makeSectionLabel(@"cURL")];
    [infoStack addArrangedSubview:self.editorInfoCurlView];
    [infoStack addArrangedSubview:makeSectionLabel(VCTextLiteral(@"Rules"))];
    [infoStack addArrangedSubview:self.editorInfoRulesView];

    self.editorParamsScrollView = makeModalScrollView();
    UIStackView *paramsStack = makeModalStack(self.editorParamsScrollView);
    self.editorParamsQueryView = makeTextView(92);
    self.editorParamsHeadersMirrorView = makeTextView(118);
    self.editorParamsBodyMirrorView = makeTextView(150);
    [paramsStack addArrangedSubview:makeSectionLabel(VCTextLiteral(@"Query Params"))];
    [paramsStack addArrangedSubview:self.editorParamsQueryView];
    [paramsStack addArrangedSubview:makeSectionLabel(VCTextLiteral(@"Headers"))];
    [paramsStack addArrangedSubview:self.editorParamsHeadersMirrorView];
    [paramsStack addArrangedSubview:makeSectionLabel(VCTextLiteral(@"Body"))];
    [paramsStack addArrangedSubview:self.editorParamsBodyMirrorView];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorScrollView addSubview:contentView];

    self.editorFavoriteNameField = makeField(VCTextLiteral(@"Favorite Name"), VCTextLiteral(@"Optional"));
    [contentView addSubview:self.editorFavoriteNameField];

    self.editorMethodField = makeField(VCTextLiteral(@"Method"), @"GET / POST / PUT");
    self.editorMethodField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    [contentView addSubview:self.editorMethodField];

    self.editorURLField = makeField(VCTextLiteral(@"URL"), @"https://example.com/path");
    self.editorURLField.keyboardType = UIKeyboardTypeURL;
    [contentView addSubview:self.editorURLField];

    UILabel *paramsLabel = [[UILabel alloc] init];
    paramsLabel.text = VCTextLiteral(@"Query Params");
    paramsLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    paramsLabel.textColor = kVCTextSecondary;
    paramsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:paramsLabel];

    self.editorParamsView = makeTextView(88);
    [contentView addSubview:self.editorParamsView];

    UILabel *headersLabel = [[UILabel alloc] init];
    headersLabel.text = VCTextLiteral(@"Headers");
    headersLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    headersLabel.textColor = kVCTextSecondary;
    headersLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:headersLabel];

    UIButton *formatHeadersButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [formatHeadersButton setTitle:VCTextLiteral(@"Normalize") forState:UIControlStateNormal];
    [formatHeadersButton setTitleColor:kVCAccent forState:UIControlStateNormal];
    formatHeadersButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    formatHeadersButton.translatesAutoresizingMaskIntoConstraints = NO;
    [formatHeadersButton addTarget:self action:@selector(_formatHeadersJSON) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:formatHeadersButton];

    self.editorHeadersView = makeTextView(124);
    [contentView addSubview:self.editorHeadersView];

    UILabel *bodyLabel = [[UILabel alloc] init];
    bodyLabel.text = VCTextLiteral(@"Body");
    bodyLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    bodyLabel.textColor = kVCTextSecondary;
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:bodyLabel];

    self.editorBodyModeControl = [[UISegmentedControl alloc] initWithItems:@[@"Raw", @"JSON", @"Form"]];
    self.editorBodyModeControl.selectedSegmentIndex = VCReplayBodyModeRaw;
    self.editorBodyModeControl.selectedSegmentTintColor = kVCAccent;
    [self.editorBodyModeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [self.editorBodyModeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    self.editorBodyModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.editorBodyModeControl];

    UIButton *formatBodyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [formatBodyButton setTitle:VCTextLiteral(@"Format JSON") forState:UIControlStateNormal];
    [formatBodyButton setTitleColor:kVCAccent forState:UIControlStateNormal];
    formatBodyButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    formatBodyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [formatBodyButton addTarget:self action:@selector(_formatBodyJSON) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:formatBodyButton];

    self.editorBodyView = makeTextView(150);
    [contentView addSubview:self.editorBodyView];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:VCTextLiteral(@"Cancel") forState:UIControlStateNormal];
    [cancel setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    cancel.titleLabel.adjustsFontSizeToFitWidth = YES;
    cancel.titleLabel.minimumScaleFactor = 0.76;
    cancel.backgroundColor = [kVCBgSecondary colorWithAlphaComponent:0.92];
    cancel.layer.cornerRadius = 12.0;
    cancel.layer.borderWidth = 1.0;
    cancel.layer.borderColor = kVCBorder.CGColor;
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [cancel addTarget:self action:@selector(_hideEditorOverlay) forControlEvents:UIControlEventTouchUpInside];
    [self.editorCard addSubview:cancel];
    self.editorCancelButton = cancel;

    UIButton *favorite = [UIButton buttonWithType:UIButtonTypeSystem];
    [favorite setTitle:VCTextLiteral(@"Save Favorite") forState:UIControlStateNormal];
    [favorite setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    favorite.titleLabel.adjustsFontSizeToFitWidth = YES;
    favorite.titleLabel.minimumScaleFactor = 0.72;
    favorite.backgroundColor = [kVCBgSecondary colorWithAlphaComponent:0.92];
    favorite.layer.cornerRadius = 12.0;
    favorite.layer.borderWidth = 1.0;
    favorite.layer.borderColor = kVCBorder.CGColor;
    favorite.translatesAutoresizingMaskIntoConstraints = NO;
    [favorite addTarget:self action:@selector(_saveEditedFavorite) forControlEvents:UIControlEventTouchUpInside];
    [self.editorCard addSubview:favorite];
    self.editorFavoriteButton = favorite;

    UIButton *resend = [UIButton buttonWithType:UIButtonTypeSystem];
    [resend setTitle:VCTextLiteral(@"Replay") forState:UIControlStateNormal];
    [resend setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    resend.titleLabel.adjustsFontSizeToFitWidth = YES;
    resend.titleLabel.minimumScaleFactor = 0.76;
    resend.backgroundColor = kVCAccentDim;
    resend.layer.cornerRadius = 12.0;
    resend.layer.borderWidth = 1.0;
    resend.layer.borderColor = kVCBorderAccent.CGColor;
    resend.translatesAutoresizingMaskIntoConstraints = NO;
    [resend addTarget:self action:@selector(_performEditedResend) forControlEvents:UIControlEventTouchUpInside];
    [self.editorCard addSubview:resend];
    self.editorReplayButton = resend;

    [NSLayoutConstraint activateConstraints:@[
        [self.editorCard.topAnchor constraintEqualToAnchor:overlay.topAnchor constant:18],
        [self.editorCard.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:14],
        [self.editorCard.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-14],
        [self.editorCard.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor constant:-14],
        [title.topAnchor constraintEqualToAnchor:self.editorCard.topAnchor constant:14],
        [title.leadingAnchor constraintEqualToAnchor:self.editorCard.leadingAnchor constant:14],
        [self.editorHintLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [self.editorHintLabel.leadingAnchor constraintEqualToAnchor:self.editorCard.leadingAnchor constant:14],
        [self.editorHintLabel.trailingAnchor constraintEqualToAnchor:self.editorCard.trailingAnchor constant:-14],

        [self.editorTabControl.topAnchor constraintEqualToAnchor:self.editorHintLabel.bottomAnchor constant:10],
        [self.editorTabControl.leadingAnchor constraintEqualToAnchor:self.editorCard.leadingAnchor constant:14],
        [self.editorTabControl.trailingAnchor constraintEqualToAnchor:self.editorCard.trailingAnchor constant:-14],
        [self.editorTabControl.heightAnchor constraintEqualToConstant:30],

        [self.editorScrollView.topAnchor constraintEqualToAnchor:self.editorTabControl.bottomAnchor constant:12],
        [self.editorScrollView.leadingAnchor constraintEqualToAnchor:self.editorCard.leadingAnchor constant:14],
        [self.editorScrollView.trailingAnchor constraintEqualToAnchor:self.editorCard.trailingAnchor constant:-14],

        [self.editorInfoScrollView.topAnchor constraintEqualToAnchor:self.editorScrollView.topAnchor],
        [self.editorInfoScrollView.leadingAnchor constraintEqualToAnchor:self.editorScrollView.leadingAnchor],
        [self.editorInfoScrollView.trailingAnchor constraintEqualToAnchor:self.editorScrollView.trailingAnchor],
        [self.editorInfoScrollView.bottomAnchor constraintEqualToAnchor:self.editorScrollView.bottomAnchor],

        [self.editorParamsScrollView.topAnchor constraintEqualToAnchor:self.editorScrollView.topAnchor],
        [self.editorParamsScrollView.leadingAnchor constraintEqualToAnchor:self.editorScrollView.leadingAnchor],
        [self.editorParamsScrollView.trailingAnchor constraintEqualToAnchor:self.editorScrollView.trailingAnchor],
        [self.editorParamsScrollView.bottomAnchor constraintEqualToAnchor:self.editorScrollView.bottomAnchor],

        [contentView.topAnchor constraintEqualToAnchor:self.editorScrollView.contentLayoutGuide.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.editorScrollView.contentLayoutGuide.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.editorScrollView.contentLayoutGuide.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.editorScrollView.contentLayoutGuide.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.editorScrollView.frameLayoutGuide.widthAnchor],

        [self.editorFavoriteNameField.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [self.editorFavoriteNameField.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.editorFavoriteNameField.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.editorFavoriteNameField.heightAnchor constraintEqualToConstant:36],

        [self.editorMethodField.topAnchor constraintEqualToAnchor:self.editorFavoriteNameField.bottomAnchor constant:10],
        [self.editorMethodField.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.editorMethodField.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.editorMethodField.heightAnchor constraintEqualToConstant:36],

        [self.editorURLField.topAnchor constraintEqualToAnchor:self.editorMethodField.bottomAnchor constant:10],
        [self.editorURLField.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.editorURLField.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.editorURLField.heightAnchor constraintEqualToConstant:36],

        [paramsLabel.topAnchor constraintEqualToAnchor:self.editorURLField.bottomAnchor constant:10],
        [paramsLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.editorParamsView.topAnchor constraintEqualToAnchor:paramsLabel.bottomAnchor constant:6],
        [self.editorParamsView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.editorParamsView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],

        [headersLabel.topAnchor constraintEqualToAnchor:self.editorParamsView.bottomAnchor constant:10],
        [headersLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [formatHeadersButton.centerYAnchor constraintEqualToAnchor:headersLabel.centerYAnchor],
        [formatHeadersButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.editorHeadersView.topAnchor constraintEqualToAnchor:headersLabel.bottomAnchor constant:6],
        [self.editorHeadersView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.editorHeadersView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],

        [bodyLabel.topAnchor constraintEqualToAnchor:self.editorHeadersView.bottomAnchor constant:10],
        [bodyLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.editorBodyModeControl.centerYAnchor constraintEqualToAnchor:bodyLabel.centerYAnchor],
        [self.editorBodyModeControl.leadingAnchor constraintEqualToAnchor:bodyLabel.trailingAnchor constant:8],
        [formatBodyButton.centerYAnchor constraintEqualToAnchor:bodyLabel.centerYAnchor],
        [formatBodyButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.editorBodyView.topAnchor constraintEqualToAnchor:bodyLabel.bottomAnchor constant:6],
        [self.editorBodyView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.editorBodyView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.editorBodyView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

        [cancel.topAnchor constraintEqualToAnchor:self.editorScrollView.bottomAnchor constant:12],
        [cancel.leadingAnchor constraintEqualToAnchor:self.editorCard.leadingAnchor constant:14],
        [self.editorScrollView.bottomAnchor constraintEqualToAnchor:cancel.topAnchor constant:-12],
        [cancel.bottomAnchor constraintEqualToAnchor:self.editorCard.bottomAnchor constant:-14],
        [cancel.heightAnchor constraintEqualToConstant:36],
        [favorite.leadingAnchor constraintEqualToAnchor:cancel.trailingAnchor constant:10],
        [favorite.topAnchor constraintEqualToAnchor:cancel.topAnchor],
        [favorite.bottomAnchor constraintEqualToAnchor:cancel.bottomAnchor],
        [favorite.widthAnchor constraintEqualToAnchor:cancel.widthAnchor],
        [resend.topAnchor constraintEqualToAnchor:cancel.topAnchor],
        [resend.trailingAnchor constraintEqualToAnchor:self.editorCard.trailingAnchor constant:-14],
        [resend.bottomAnchor constraintEqualToAnchor:cancel.bottomAnchor],
        [resend.widthAnchor constraintEqualToAnchor:cancel.widthAnchor],
        [favorite.trailingAnchor constraintEqualToAnchor:resend.leadingAnchor constant:-10],
    ]];
    VCInstallKeyboardDismissAccessory(self.editorOverlay);
}

- (void)_setupEditorDockIfNeeded {
    if (self.editorDock) return;

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
    self.editorDock = dock;

    UIView *handle = [[UIView alloc] init];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.backgroundColor = [UIColor clearColor];
    handle.layer.cornerRadius = 2.0;
    [dock addSubview:handle];
    self.editorDockHandle = handle;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:VCTextLiteral(@"Modify") forState:UIControlStateNormal];
    [button setImage:nil forState:UIControlStateNormal];
    VCApplyCompactAccentButtonStyle(button);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 14, 10, 14);
    button.titleEdgeInsets = UIEdgeInsetsZero;
    [button addTarget:self action:@selector(_showEditorForExpandedRecord) forControlEvents:UIControlEventTouchUpInside];
    [dock addSubview:button];
    self.editorDockButton = button;

    self.editorDockWidthConstraint = [self.editorDock.widthAnchor constraintEqualToConstant:160.0];
    self.editorDockHeightConstraint = [self.editorDock.heightAnchor constraintEqualToConstant:56.0];
    self.editorDockLeadingConstraint = [self.editorDock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:0.0];
    self.editorDockTopConstraint = [self.editorDock.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:0.0];

    [NSLayoutConstraint activateConstraints:@[
        self.editorDockWidthConstraint,
        self.editorDockHeightConstraint,
        self.editorDockLeadingConstraint,
        self.editorDockTopConstraint,

        [self.editorDockHandle.topAnchor constraintEqualToAnchor:self.editorDock.topAnchor],
        [self.editorDockHandle.centerXAnchor constraintEqualToAnchor:self.editorDock.centerXAnchor],
        [self.editorDockHandle.widthAnchor constraintEqualToConstant:36.0],
        [self.editorDockHandle.heightAnchor constraintEqualToConstant:0.0],

        [self.editorDockButton.topAnchor constraintEqualToAnchor:self.editorDock.topAnchor],
        [self.editorDockButton.leadingAnchor constraintEqualToAnchor:self.editorDock.leadingAnchor],
        [self.editorDockButton.trailingAnchor constraintEqualToAnchor:self.editorDock.trailingAnchor],
        [self.editorDockButton.bottomAnchor constraintEqualToAnchor:self.editorDock.bottomAnchor],
    ]];

    [self _layoutEditorDock];
}

- (void)_layoutEditorDock {
    if (!self.editorDock) return;

    UIEdgeInsets safeInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeInsets = self.view.safeAreaInsets;
    }

    CGFloat dockWidth = MIN(MAX(CGRectGetWidth(self.view.bounds) * 0.36, 136.0), 188.0);
    CGFloat dockHeight = 48.0;
    CGFloat dockX = floor((CGRectGetWidth(self.view.bounds) - dockWidth) * 0.5);
    CGFloat dockY = CGRectGetHeight(self.view.bounds) - safeInsets.bottom - dockHeight - 14.0;
    self.editorDockWidthConstraint.constant = dockWidth;
    self.editorDockHeightConstraint.constant = dockHeight;
    self.editorDockLeadingConstraint.constant = dockX;
    self.editorDockTopConstraint.constant = dockY;
    [self.view layoutIfNeeded];
}

- (void)_refreshEditorDock {
    if (!self.editorDock) return;

    BOOL editorVisible = self.editorOverlay && !self.editorOverlay.hidden;
    BOOL shouldShowDock = ([self _expandedRecord] != nil) && !editorVisible;
    [self _layoutEditorDock];

    if (shouldShowDock) {
        self.editorDockButton.enabled = YES;
        self.editorDockButton.alpha = 1.0;
        [self.editorDockButton setTitle:VCTextLiteral(@"Modify") forState:UIControlStateNormal];
        [self.editorDockButton setImage:nil forState:UIControlStateNormal];
        self.editorDockButton.titleEdgeInsets = UIEdgeInsetsZero;
        if (self.editorDock.hidden) {
            self.editorDock.hidden = NO;
            self.editorDock.alpha = 0.0;
            self.editorDock.transform = CGAffineTransformMakeTranslation(0, 16.0);
        }
        [self.view bringSubviewToFront:self.editorDock];
        [UIView animateWithDuration:0.18 animations:^{
            self.editorDock.alpha = 1.0;
            self.editorDock.transform = CGAffineTransformIdentity;
        }];
        return;
    }

    if (!self.editorDock.hidden || self.editorDock.alpha > 0.0) {
        [UIView animateWithDuration:0.16 animations:^{
            self.editorDock.alpha = 0.0;
            self.editorDock.transform = CGAffineTransformMakeTranslation(0, 16.0);
        } completion:^(__unused BOOL finished) {
            self.editorDock.hidden = YES;
            self.editorDock.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)_showEditorForExpandedRecord {
    VCNetRecord *record = [self _expandedRecord];
    if (!record) return;
    [self _showEditorForRecord:record];
}

- (void)_setupRegexOverlayIfNeeded {
    if (self.regexOverlay) return;

    UIView *overlay = [[UIView alloc] init];
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.56];
    overlay.hidden = YES;
    overlay.alpha = 0.0;
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:overlay];
    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    self.regexOverlay = overlay;

    UIControl *backdrop = [[UIControl alloc] init];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addTarget:self action:@selector(_hideRegexOverlay) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:backdrop];

    self.regexCard = [[UIView alloc] init];
    self.regexCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    self.regexCard.layer.cornerRadius = 16.0;
    self.regexCard.layer.borderWidth = 1.0;
    self.regexCard.layer.borderColor = kVCBorderStrong.CGColor;
    self.regexCard.translatesAutoresizingMaskIntoConstraints = NO;
    [overlay addSubview:self.regexCard];

    UILabel *title = [[UILabel alloc] init];
    title.text = VCTextLiteral(@"Regex Tester");
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    title.textColor = kVCTextPrimary;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.regexCard addSubview:title];

    self.regexPatternField = [[UITextField alloc] init];
    VCApplyReadablePlaceholder(self.regexPatternField, @"re:<pattern> or plain regex");
    self.regexPatternField.textColor = kVCTextPrimary;
    self.regexPatternField.font = [UIFont systemFontOfSize:13];
    self.regexPatternField.backgroundColor = kVCBgInput;
    self.regexPatternField.layer.cornerRadius = 11.0;
    self.regexPatternField.layer.borderWidth = 1.0;
    self.regexPatternField.layer.borderColor = kVCBorder.CGColor;
    self.regexPatternField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
    self.regexPatternField.leftViewMode = UITextFieldViewModeAlways;
    self.regexPatternField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.regexCard addSubview:self.regexPatternField];

    self.regexSampleView = [[UITextView alloc] init];
    self.regexSampleView.font = kVCFontMonoSm;
    self.regexSampleView.textColor = kVCTextPrimary;
    self.regexSampleView.backgroundColor = kVCBgInput;
    self.regexSampleView.layer.cornerRadius = 12.0;
    self.regexSampleView.layer.borderWidth = 1.0;
    self.regexSampleView.layer.borderColor = kVCBorder.CGColor;
    self.regexSampleView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    self.regexSampleView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.regexCard addSubview:self.regexSampleView];

    self.regexResultLabel = [[UILabel alloc] init];
    self.regexResultLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.regexResultLabel.textColor = kVCTextSecondary;
    self.regexResultLabel.numberOfLines = 0;
    self.regexResultLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.regexCard addSubview:self.regexResultLabel];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:VCTextLiteral(@"Done") forState:UIControlStateNormal];
    [closeButton setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    closeButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    closeButton.titleLabel.minimumScaleFactor = 0.76;
    closeButton.backgroundColor = [kVCBgSecondary colorWithAlphaComponent:0.92];
    closeButton.layer.cornerRadius = 12.0;
    closeButton.layer.borderWidth = 1.0;
    closeButton.layer.borderColor = kVCBorder.CGColor;
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton addTarget:self action:@selector(_hideRegexOverlay) forControlEvents:UIControlEventTouchUpInside];
    [self.regexCard addSubview:closeButton];

    UIButton *testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [testButton setTitle:VCTextLiteral(@"Test Regex") forState:UIControlStateNormal];
    [testButton setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    testButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    testButton.titleLabel.minimumScaleFactor = 0.72;
    testButton.backgroundColor = kVCAccentDim;
    testButton.layer.cornerRadius = 12.0;
    testButton.layer.borderWidth = 1.0;
    testButton.layer.borderColor = kVCBorderAccent.CGColor;
    testButton.translatesAutoresizingMaskIntoConstraints = NO;
    [testButton addTarget:self action:@selector(_runRegexTester) forControlEvents:UIControlEventTouchUpInside];
    [self.regexCard addSubview:testButton];

    [NSLayoutConstraint activateConstraints:@[
        [backdrop.topAnchor constraintEqualToAnchor:overlay.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],
        [self.regexCard.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:14],
        [self.regexCard.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-14],
        [self.regexCard.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [title.topAnchor constraintEqualToAnchor:self.regexCard.topAnchor constant:14],
        [title.leadingAnchor constraintEqualToAnchor:self.regexCard.leadingAnchor constant:14],
        [title.trailingAnchor constraintEqualToAnchor:self.regexCard.trailingAnchor constant:-14],
        [self.regexPatternField.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [self.regexPatternField.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.regexPatternField.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.regexPatternField.heightAnchor constraintEqualToConstant:36],
        [self.regexSampleView.topAnchor constraintEqualToAnchor:self.regexPatternField.bottomAnchor constant:10],
        [self.regexSampleView.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.regexSampleView.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.regexSampleView.heightAnchor constraintGreaterThanOrEqualToConstant:150],
        [self.regexResultLabel.topAnchor constraintEqualToAnchor:self.regexSampleView.bottomAnchor constant:10],
        [self.regexResultLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.regexResultLabel.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [closeButton.topAnchor constraintEqualToAnchor:self.regexResultLabel.bottomAnchor constant:14],
        [closeButton.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [closeButton.bottomAnchor constraintEqualToAnchor:self.regexCard.bottomAnchor constant:-14],
        [closeButton.heightAnchor constraintEqualToConstant:36],
        [testButton.topAnchor constraintEqualToAnchor:closeButton.topAnchor],
        [testButton.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [testButton.leadingAnchor constraintEqualToAnchor:closeButton.trailingAnchor constant:10],
        [testButton.widthAnchor constraintEqualToAnchor:closeButton.widthAnchor],
        [testButton.bottomAnchor constraintEqualToAnchor:closeButton.bottomAnchor],
    ]];
    VCInstallKeyboardDismissAccessory(self.regexOverlay);
}

- (void)_showRegexOverlay {
    [self _setupRegexOverlayIfNeeded];
    NSString *search = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.regexPatternField.text = [search hasPrefix:@"re:"] ? search : @"";
    VCNetRecord *sampleRecord = (self.expandedRow >= 0 && self.expandedRow < (NSInteger)self.filteredRecords.count) ? self.filteredRecords[self.expandedRow] : self.filteredRecords.firstObject;
    self.regexSampleView.text = sampleRecord ? [self _searchBlobForRecord:sampleRecord] : VCTextLiteral(@"Paste sample URL / headers / body here to test matching.");
    self.regexResultLabel.text = VCTextLiteral(@"Use the same regex syntax as the search bar and rule matcher.");
    self.regexResultLabel.textColor = kVCTextSecondary;
    self.regexOverlay.hidden = NO;
    [UIView animateWithDuration:0.18 animations:^{ self.regexOverlay.alpha = 1.0; }];
}

- (void)_hideRegexOverlay {
    [UIView animateWithDuration:0.18 animations:^{ self.regexOverlay.alpha = 0.0; } completion:^(BOOL finished) {
        self.regexOverlay.hidden = YES;
    }];
}

- (void)_runRegexTester {
    NSString *pattern = [self.regexPatternField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([pattern hasPrefix:@"re:"]) pattern = [pattern substringFromIndex:3];
    NSString *sample = self.regexSampleView.text ?: @"";
    if (pattern.length == 0 || sample.length == 0) {
        self.regexResultLabel.text = VCTextLiteral(@"Enter both a regex pattern and sample text.");
        self.regexResultLabel.textColor = kVCRed;
        return;
    }
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    if (!regex || error) {
        self.regexResultLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Regex error: %@"), error.localizedDescription ?: VCTextLiteral(@"invalid pattern")];
        self.regexResultLabel.textColor = kVCRed;
        return;
    }
    NSUInteger matches = [regex numberOfMatchesInString:sample options:0 range:NSMakeRange(0, sample.length)];
    self.regexResultLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Pattern matched %lu time%@."), (unsigned long)matches, matches == 1 ? @"" : @"s"];
    self.regexResultLabel.textColor = matches > 0 ? kVCGreen : kVCYellow;
}

- (NSDictionary *)_harEntryForRecord:(VCNetRecord *)record {
    NSString *requestBodyText = [record requestBodyAsString];
    NSString *responseBodyText = [record responseBodyAsString];
    NSString *requestMimeType = [self _headerValueInDictionary:record.requestHeaders forName:@"Content-Type"];
    if (requestMimeType.length == 0) requestMimeType = @"text/plain";
    NSMutableDictionary *postData = [@{
        @"mimeType": requestMimeType,
        @"text": [requestBodyText isEqualToString:@"(empty)"] ? @"" : (requestBodyText ?: @"")
    } mutableCopy];
    if ([self _bodyModeForText:requestBodyText headers:record.requestHeaders] == VCReplayBodyModeForm) {
        postData[@"params"] = [self _queryItemDictionariesFromEditorText:[self _formEditorTextFromBodyText:requestBodyText]];
    }
    return @{
        @"startedDateTime": @(((record.startTime > 0 ? record.startTime : [NSProcessInfo processInfo].systemUptime))),
        @"time": @(MAX(record.duration * 1000.0, 0)),
        @"request": @{
            @"method": record.method ?: @"GET",
            @"url": record.url ?: @"",
            @"headers": [self _harHeaderArrayFromDictionary:record.requestHeaders],
            @"queryString": [self _queryItemDictionariesFromURLString:record.url],
            @"postData": postData
        },
        @"response": @{
            @"status": @(record.statusCode),
            @"statusText": @"",
            @"headers": [self _harHeaderArrayFromDictionary:record.responseHeaders],
            @"content": @{
                @"mimeType": record.mimeType ?: @"text/plain",
                @"text": [responseBodyText isEqualToString:@"(empty)"] ? @"" : (responseBodyText ?: @"")
            }
        },
        @"comment": record.wasModifiedByRule ? [NSString stringWithFormat:@"matched: %@", [record.matchedRules componentsJoinedByString:@", "]] : @""
    };
}

- (void)_exportHAR {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray new];
    for (VCNetRecord *record in self.filteredRecords ?: @[]) {
        [entries addObject:[self _harEntryForRecord:record]];
    }
    NSDictionary *har = @{
        @"log": @{
            @"version": @"1.2",
            @"creator": @{@"name": @"VansonCLI", @"version": @"1.0"},
            @"entries": entries
        }
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:har options:NSJSONWritingPrettyPrinted error:nil];
    if (!data) {
        self.statusLabel.text = VCTextLiteral(@"Failed to build HAR export.");
        return;
    }
    NSString *fileName = [NSString stringWithFormat:@"VansonCLI-Network-%@.har", @((NSInteger)[NSDate date].timeIntervalSince1970)];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    BOOL wrote = [data writeToFile:path atomically:YES];
    self.statusLabel.text = wrote ? [NSString stringWithFormat:VCTextLiteral(@"HAR exported: %@"), fileName] : VCTextLiteral(@"Failed to write HAR export.");
    if (wrote) {
        [UIPasteboard generalPasteboard].string = path;
    }
}

#pragma mark - Data

- (void)_refresh {
    _records = [[VCNetMonitor shared] allRecords];
    for (VCNetRecord *record in _records) {
        [self _decorateRecordMetadata:record];
    }
    [self _updateCaptureBadge];
    [self _applyFilter];
}

- (void)_filterChanged { [self _applyFilter]; }

- (void)_decorateRecordMetadata:(VCNetRecord *)record {
    if (!record) return;
    NSURL *url = [NSURL URLWithString:record.url ?: @""];
    if (record.hostKey.length == 0) {
        record.hostKey = url.host ?: @"";
    }
    if (record.statusBucket.length == 0) {
        record.statusBucket = VCNetStatusBucketForCode(record.statusCode);
    }
    if (!record.exportSnapshot) {
        record.exportSnapshot = @{
            @"request": @{
                @"method": record.method ?: @"GET",
                @"url": record.url ?: @"",
                @"headers": record.requestHeaders ?: @{},
                @"body": [record requestBodyAsString] ?: @""
            },
            @"response": @{
                @"status": @(record.statusCode),
                @"headers": record.responseHeaders ?: @{},
                @"body": [record responseBodyAsString] ?: @""
            }
        };
    }
}

- (NSString *)_favoritesArchivePath {
    NSString *dir = [VCConfig shared].configPath;
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [dir stringByAppendingPathComponent:@"network-favorites.plist"];
}

- (void)_loadFavorites {
    NSArray *saved = [NSArray arrayWithContentsOfFile:[self _favoritesArchivePath]];
    [self.favoriteRequests removeAllObjects];
    for (id item in saved) {
        VCReplayDraft *draft = [VCReplayDraft draftFromDictionary:item];
        if (draft) {
            [self.favoriteRequests addObject:draft];
        }
    }
    [self _updateFavoritesButton];
}

- (void)_saveFavorites {
    NSMutableArray<NSDictionary *> *payload = [NSMutableArray new];
    for (VCReplayDraft *draft in self.favoriteRequests) {
        [payload addObject:[draft dictionaryRepresentation]];
    }
    [payload writeToFile:[self _favoritesArchivePath] atomically:YES];
    [self _updateFavoritesButton];
}

- (void)_updateFavoritesButton {
    NSString *title = self.showingFavorites ? [NSString stringWithFormat:@"Fav %lu", (unsigned long)self.favoriteRequests.count] : VCTextLiteral(@"Fav");
    [self.favoritesButton setTitle:title forState:UIControlStateNormal];
    self.favoritesButton.backgroundColor = self.showingFavorites ? UIColorFromHex(0x1d4ed8) : kVCAccentDim;
    self.favoritesButton.layer.borderColor = (self.showingFavorites ? UIColorFromHex(0x93c5fd) : kVCBorder).CGColor;
    [self.clearButton setTitle:VCTextLiteral(@"Clear") forState:UIControlStateNormal];
}

- (UIButton *)_hostFilterChipWithTitle:(NSString *)title host:(NSString *)host {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    VCPrepareButtonTitle(button, NSLineBreakByTruncatingMiddle, 0.78);
    button.backgroundColor = [host isEqualToString:self.selectedHostFilter ?: @""] ? kVCAccentDim : [kVCBgSecondary colorWithAlphaComponent:0.92];
    button.layer.cornerRadius = 10.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = ([host isEqualToString:self.selectedHostFilter ?: @""] ? kVCBorderAccent : kVCBorder).CGColor;
    button.contentEdgeInsets = UIEdgeInsetsMake(4, 8, 4, 8);
    button.accessibilityIdentifier = host ?: @"";
    CGFloat maxWidth = host.length > 0 ? 118.0 : 82.0;
    [button.widthAnchor constraintLessThanOrEqualToConstant:maxWidth].active = YES;
    [button.heightAnchor constraintEqualToConstant:24.0].active = YES;
    [button addTarget:self action:@selector(_hostChipTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)_hostChipTapped:(UIButton *)sender {
    NSString *host = sender.accessibilityIdentifier ?: @"";
    self.selectedHostFilter = host.length > 0 ? host : nil;
    [self _applyFilter];
}

- (void)_updateHostFilterChips {
    for (UIView *view in self.hostStackView.arrangedSubviews) {
        [self.hostStackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray<VCNetRecord *> *source = [self _displayRecords];
    NSMutableOrderedSet<NSString *> *hosts = [NSMutableOrderedSet orderedSet];
    for (VCNetRecord *record in source) {
        NSString *host = record.hostKey ?: [NSURL URLWithString:record.url ?: @""].host;
        if (host.length > 0) [hosts addObject:host];
    }
    [self.hostStackView addArrangedSubview:[self _hostFilterChipWithTitle:VCTextLiteral(@"All Hosts") host:@""]];
    for (NSString *host in hosts.array) {
        [self.hostStackView addArrangedSubview:[self _hostFilterChipWithTitle:host host:host]];
    }
}

- (VCNetRecord *)_recordFromDraft:(VCReplayDraft *)draft {
    VCNetRecord *record = [[VCNetRecord alloc] init];
    record.favoriteID = draft.favoriteID;
    record.favoriteName = draft.favoriteName;
    record.method = draft.method ?: @"GET";
    record.url = draft.url ?: @"";
    record.requestHeaders = draft.headers ?: @{};
    record.requestBody = [draft.body dataUsingEncoding:NSUTF8StringEncoding];
    record.hostKey = draft.hostKey ?: ([NSURL URLWithString:draft.url ?: @""].host ?: @"");
    record.statusBucket = draft.statusBucket ?: @"other";
    record.exportSnapshot = draft.exportSnapshot ?: @{};
    return record;
}

- (NSArray<VCNetRecord *> *)_displayRecords {
    if (!self.showingFavorites) return self.records ?: @[];
    NSMutableArray<VCNetRecord *> *favorites = [NSMutableArray new];
    for (VCReplayDraft *favorite in self.favoriteRequests) {
        [favorites addObject:[self _recordFromDraft:favorite]];
    }
    return favorites;
}

- (NSString *)_prettyJSONStringFromObject:(id)object fallback:(NSString *)fallback {
    if (!object) return fallback ?: @"";
    if (![NSJSONSerialization isValidJSONObject:object]) return fallback ?: [object description];
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: (fallback ?: @"");
}

- (NSString *)_headerValueInDictionary:(NSDictionary *)headers forName:(NSString *)name {
    if (![headers isKindOfClass:[NSDictionary class]] || name.length == 0) return @"";
    for (id key in headers) {
        if ([[key description] caseInsensitiveCompare:name] == NSOrderedSame) {
            id value = headers[key];
            return [value respondsToSelector:@selector(description)] ? [value description] : @"";
        }
    }
    return @"";
}

- (NSArray<NSDictionary *> *)_queryItemDictionariesFromURLString:(NSString *)urlString {
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString ?: @""];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        [items addObject:@{
            @"name": item.name ?: @"",
            @"value": item.value ?: @""
        }];
    }
    return [items copy];
}

- (NSArray<NSDictionary *> *)_harHeaderArrayFromDictionary:(NSDictionary *)headers {
    if (![headers isKindOfClass:[NSDictionary class]] || headers.count == 0) return @[];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    NSArray *keys = [[headers allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (id key in keys) {
        id value = headers[key];
        [items addObject:@{
            @"name": [key description] ?: @"",
            @"value": [value description] ?: @""
        }];
    }
    return [items copy];
}

- (NSArray<NSString *> *)_parameterRowsFromEditorText:(NSString *)text {
    NSString *source = [text isKindOfClass:[NSString class]] ? text : @"";
    NSMutableArray<NSString *> *rows = [NSMutableArray new];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@"\n&"];
    for (NSString *part in [source componentsSeparatedByCharactersInSet:separators]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [rows addObject:trimmed];
    }
    return [rows copy];
}

- (NSDictionary *)_headersFromJSONString:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return @{};
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (NSString *)_headerEditorTextFromDictionary:(NSDictionary *)headers {
    if (![headers isKindOfClass:[NSDictionary class]] || headers.count == 0) return @"";
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    NSArray<NSString *> *keys = [[headers allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *key in keys) {
        id value = headers[key];
        [lines addObject:[NSString stringWithFormat:@"%@: %@", key ?: @"", [value description] ?: @""]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (BOOL)_tryParseHeadersEditorText:(NSString *)text result:(NSDictionary **)result {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (result) *result = @{};
        return YES;
    }
    if ([trimmed hasPrefix:@"{"]) {
        return [self _tryParseHeadersJSON:trimmed result:result];
    }

    NSMutableDictionary *headers = [NSMutableDictionary new];
    NSArray<NSString *> *lines = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *row = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (row.length == 0) continue;
        NSRange separator = [row rangeOfString:@":"];
        if (separator.location == NSNotFound) return NO;
        NSString *key = [[row substringToIndex:separator.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *value = [[row substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (key.length == 0) return NO;
        headers[key] = value ?: @"";
    }
    if (result) *result = headers;
    return YES;
}

- (BOOL)_tryParseHeadersJSON:(NSString *)text result:(NSDictionary **)result {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (result) *result = @{};
        return YES;
    }
    NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return NO;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return NO;
    if (result) *result = json;
    return YES;
}

- (NSString *)_baseURLStringFromURLString:(NSString *)urlString {
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString ?: @""];
    if (!components) return urlString ?: @"";
    components.query = nil;
    components.fragment = nil;
    return components.string ?: (urlString ?: @"");
}

- (NSString *)_queryEditorTextFromURLString:(NSString *)urlString {
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString ?: @""];
    if (components.queryItems.count == 0) return @"";
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSURLQueryItem *item in components.queryItems) {
        [lines addObject:[NSString stringWithFormat:@"%@=%@", item.name ?: @"", item.value ?: @""]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)_queryEditorTextFromItems:(NSArray<NSDictionary *> *)items fallbackURL:(NSString *)urlString {
    if ([items isKindOfClass:[NSArray class]] && items.count > 0) {
        NSMutableArray<NSString *> *lines = [NSMutableArray new];
        for (NSDictionary *item in items) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSString *name = [item[@"name"] isKindOfClass:[NSString class]] ? item[@"name"] : @"";
            NSString *value = [item[@"value"] isKindOfClass:[NSString class]] ? item[@"value"] : @"";
            if (name.length > 0) [lines addObject:[NSString stringWithFormat:@"%@=%@", name, value ?: @""]];
        }
        if (lines.count > 0) return [lines componentsJoinedByString:@"\n"];
    }
    return [self _queryEditorTextFromURLString:urlString ?: @""];
}

- (NSArray<NSURLQueryItem *> *)_queryItemsFromEditorText:(NSString *)text {
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray new];
    for (NSString *line in [self _parameterRowsFromEditorText:text]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        NSRange separator = [trimmed rangeOfString:@"="];
        NSString *name = separator.location == NSNotFound ? trimmed : [trimmed substringToIndex:separator.location];
        NSString *value = separator.location == NSNotFound ? @"" : [trimmed substringFromIndex:separator.location + 1];
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        name = [name stringByRemovingPercentEncoding] ?: name;
        value = [value stringByRemovingPercentEncoding] ?: value;
        if (name.length == 0) continue;
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }
    return items;
}

- (NSArray<NSDictionary *> *)_queryItemDictionariesFromEditorText:(NSString *)text {
    NSMutableArray<NSDictionary *> *serialized = [NSMutableArray new];
    for (NSURLQueryItem *item in [self _queryItemsFromEditorText:text]) {
        [serialized addObject:@{
            @"name": item.name ?: @"",
            @"value": item.value ?: @""
        }];
    }
    return serialized;
}

- (NSString *)_composedReplayURLString {
    return [self _composedURLStringWithBaseURLString:self.editorURLField.text paramsText:self.editorParamsView.text ?: @""];
}

- (NSString *)_composedURLStringWithBaseURLString:(NSString *)baseURLString paramsText:(NSString *)paramsText {
    NSString *baseURL = [baseURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURLComponents *components = [NSURLComponents componentsWithString:baseURL];
    if (!components) return nil;
    NSArray<NSURLQueryItem *> *items = [self _queryItemsFromEditorText:paramsText ?: @""];
    components.queryItems = items.count > 0 ? items : nil;
    return components.string;
}

- (void)_formatJSONTextView:(UITextView *)textView emptyFallback:(NSString *)fallback {
    NSString *raw = [textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) {
        textView.text = fallback ?: @"";
        self.editorHintLabel.text = VCTextLiteral(@"Inserted an empty JSON scaffold.");
        self.editorHintLabel.textColor = kVCTextSecondary;
        return;
    }
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (!json) {
        self.editorHintLabel.text = VCTextLiteral(@"This section is not valid JSON yet.");
        self.editorHintLabel.textColor = kVCRed;
        return;
    }
    NSData *prettyData = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
    textView.text = prettyData ? ([[NSString alloc] initWithData:prettyData encoding:NSUTF8StringEncoding] ?: raw) : raw;
    self.editorHintLabel.text = VCTextLiteral(@"JSON formatted.");
    self.editorHintLabel.textColor = kVCTextSecondary;
}

- (void)_formatHeadersJSON {
    NSDictionary *headers = nil;
    if (![self _tryParseHeadersEditorText:self.editorHeadersView.text ?: @"" result:&headers]) {
        self.editorHintLabel.text = VCTextLiteral(@"Headers must be JSON or lines like Authorization: Bearer token.");
        self.editorHintLabel.textColor = kVCRed;
        return;
    }
    self.editorHeadersView.text = [self _headerEditorTextFromDictionary:headers];
    self.editorHintLabel.text = VCTextLiteral(@"Headers normalized.");
    self.editorHintLabel.textColor = kVCTextSecondary;
}

- (void)_formatBodyJSON {
    [self _formatJSONTextView:self.editorBodyView emptyFallback:@"{}"];
}

- (NSString *)_querySummaryForRecord:(VCNetRecord *)record {
    NSURLComponents *components = [NSURLComponents componentsWithString:record.url];
    if (components.queryItems.count == 0) return VCTextLiteral(@"no params");
    NSMutableArray<NSString *> *items = [NSMutableArray new];
    for (NSURLQueryItem *item in components.queryItems) {
        [items addObject:[NSString stringWithFormat:@"%@=%@", item.name ?: @"", item.value ?: @""]];
    }
    return [items componentsJoinedByString:@" & "];
}

- (NSString *)_inlineParamsEditorTextForRecord:(VCNetRecord *)record {
    return [self _queryEditorTextFromURLString:record.url ?: @""];
}

- (NSString *)_bodyParamsSummaryForRecord:(VCNetRecord *)record {
    NSString *bodyText = [record requestBodyAsString];
    if ([bodyText isEqualToString:@"(empty)"]) return @"";
    VCReplayBodyMode mode = [self _bodyModeForText:bodyText headers:record.requestHeaders];
    if (mode == VCReplayBodyModeForm) {
        return [self _formEditorTextFromBodyText:bodyText];
    }
    if (mode == VCReplayBodyModeJSON) {
        return [self _bodyParamEditorTextFromJSONBody:bodyText];
    }
    return @"";
}

- (NSString *)_paramsSummaryForRecord:(VCNetRecord *)record {
    NSString *query = [self _inlineParamsEditorTextForRecord:record];
    NSString *body = [self _bodyParamsSummaryForRecord:record];
    NSMutableArray<NSString *> *sections = [NSMutableArray new];
    if (query.length > 0) [sections addObject:[NSString stringWithFormat:@"Query\n%@", query]];
    if (body.length > 0) [sections addObject:[NSString stringWithFormat:@"Body\n%@", body]];
    return sections.count > 0 ? [sections componentsJoinedByString:@"\n\n"] : VCTextLiteral(@"no params");
}

- (NSString *)_hostPathPatternForRecord:(VCNetRecord *)record {
    NSURLComponents *components = [NSURLComponents componentsWithString:record.url ?: @""];
    if (!components.host.length) return record.url ?: @"*";
    NSString *scheme = components.scheme.length > 0 ? components.scheme : @"https";
    NSString *path = components.path.length > 0 ? components.path : @"/";
    return [NSString stringWithFormat:@"%@://%@%@*", scheme, components.host, path];
}

- (NSString *)_searchBlobForRecord:(VCNetRecord *)record {
    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    if (record.method.length) [parts addObject:record.method];
    if (record.url.length) [parts addObject:record.url];
    NSString *query = [self _querySummaryForRecord:record];
    if (query.length) [parts addObject:query];
    if (record.requestHeaders.count) [parts addObject:record.requestHeaders.description];
    if (record.responseHeaders.count) [parts addObject:record.responseHeaders.description];
    NSString *requestBody = [record requestBodyAsString];
    if (requestBody.length) [parts addObject:requestBody];
    NSString *responseBody = [record responseBodyAsString];
    if (responseBody.length) [parts addObject:responseBody];
    return [[parts componentsJoinedByString:@"\n"] lowercaseString];
}

- (BOOL)_record:(VCNetRecord *)record matchesSearch:(NSString *)search {
    NSString *trimmed = [search stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return YES;
    NSString *blob = [self _searchBlobForRecord:record];
    if ([trimmed hasPrefix:@"re:"]) {
        NSString *pattern = [trimmed substringFromIndex:3];
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
        if (error || !regex) {
            self.statusLabel.text = VCTextLiteral(@"Invalid regex. Use plain text or re:<pattern>.");
            return NO;
        }
        return [regex firstMatchInString:blob options:0 range:NSMakeRange(0, blob.length)] != nil;
    }
    return [blob containsString:trimmed.lowercaseString];
}

- (void)_toggleFavoritesMode {
    self.showingFavorites = !self.showingFavorites;
    self.expandedRow = -1;
    [self _updateFavoritesButton];
    [self _applyFilter];
}

- (void)_clearCurrentMode {
    self.expandedRow = -1;
    if (self.showingFavorites) {
        [self.favoriteRequests removeAllObjects];
        [self _saveFavorites];
        self.statusLabel.text = VCTextLiteral(@"Cleared all favorites");
        [self _applyFilter];
        return;
    }

    [[VCNetMonitor shared] clearRecords];
    self.records = @[];
    self.filteredRecords = @[];
    self.tableView.backgroundView = nil;
    [self _applyFilter];
    self.statusLabel.text = VCTextLiteral(@"Cleared captured requests");
}

- (void)_saveRecordToFavorites:(VCNetRecord *)record {
    if (!record) return;
    VCReplayDraft *favorite = [VCReplayDraft draftFromRecord:record];
    NSString *favoriteKey = [NSString stringWithFormat:@"%@|%@", favorite.method ?: @"GET", favorite.url ?: @""];
    NSIndexSet *indexes = [self.favoriteRequests indexesOfObjectsPassingTest:^BOOL(VCReplayDraft *obj, NSUInteger idx, BOOL *stop) {
        NSString *key = [NSString stringWithFormat:@"%@|%@", obj.method ?: @"GET", obj.url ?: @""];
        return [key isEqualToString:favoriteKey];
    }];
    if (indexes.count > 0) {
        [self.favoriteRequests removeObjectsAtIndexes:indexes];
    }
    [self.favoriteRequests insertObject:favorite atIndex:0];
    [self _saveFavorites];
    self.statusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Saved favorite %@"), favorite.displayName];
}

- (void)_removeFavoriteAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.filteredRecords.count || !self.showingFavorites) return;
    VCNetRecord *record = self.filteredRecords[index];
    NSIndexSet *indexes = [self.favoriteRequests indexesOfObjectsPassingTest:^BOOL(VCReplayDraft *obj, NSUInteger idx, BOOL *stop) {
        if (record.favoriteID.length > 0) {
            return [obj.favoriteID isEqualToString:record.favoriteID];
        }
        NSString *key = [NSString stringWithFormat:@"%@|%@", obj.method ?: @"GET", obj.url ?: @""];
        NSString *recordKey = [NSString stringWithFormat:@"%@|%@", record.method ?: @"GET", record.url ?: @""];
        return [key isEqualToString:recordKey];
    }];
    if (indexes.count > 0) {
        [self.favoriteRequests removeObjectsAtIndexes:indexes];
        [self _saveFavorites];
    }
    [self _applyFilter];
}

- (void)_favoriteRecordAsRule:(VCNetRecord *)record {
    if (!record) return;
    VCNetRule *rule = [[VCNetRule alloc] init];
    rule.enabled = NO;
    rule.urlPattern = [self _hostPathPatternForRecord:record];
    rule.action = record.requestBody.length > 0 ? @"modify_body" : @"modify_header";
    NSMutableDictionary *mods = [NSMutableDictionary new];
    if (record.requestHeaders.count > 0) mods[@"headers"] = record.requestHeaders;
    NSString *bodyText = [record requestBodyAsString];
    if (bodyText.length > 0) mods[@"body"] = bodyText;
    rule.modifications = mods.count > 0 ? mods : nil;
    rule.remark = [NSString stringWithFormat:VCTextLiteral(@"Favorite %@ %@"), record.method ?: @"REQ", [NSURL URLWithString:record.url].host ?: VCTextLiteral(@"request")];
    [[VCPatchManager shared] addRule:rule];
    self.statusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Saved disabled rule for %@"), rule.urlPattern ?: VCTextLiteral(@"request")];
}

- (VCReplayBodyMode)_bodyModeForText:(NSString *)text headers:(NSDictionary *)headers {
    NSString *contentType = [[self _headerValueInDictionary:headers forName:@"Content-Type"] lowercaseString];
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([contentType containsString:@"application/x-www-form-urlencoded"]) return VCReplayBodyModeForm;
    if ([contentType containsString:@"application/json"]) return VCReplayBodyModeJSON;
    if ([trimmed hasPrefix:@"{"] || [trimmed hasPrefix:@"["]) return VCReplayBodyModeJSON;
    return VCReplayBodyModeRaw;
}

- (void)_showEditorForRecord:(VCNetRecord *)record {
    [self _showNetworkModalForRecord:record initialTab:VCNetworkModalTabReplay];
}

- (void)_showEditorForDraft:(VCReplayDraft *)draft {
    [self _showEditorForDraft:draft record:nil initialTab:VCNetworkModalTabReplay];
}

- (void)_showEditorForDraft:(VCReplayDraft *)draft record:(VCNetRecord *)record initialTab:(VCNetworkModalTab)initialTab {
    [self _setupEditorOverlayIfNeeded];
    self.editingDraft = draft;
    self.editingRecord = record ?: [self _recordFromDraft:draft];
    self.editorFavoriteNameField.text = draft.favoriteName ?: @"";
    self.editorMethodField.text = draft.method ?: @"GET";
    self.editorURLField.text = [self _baseURLStringFromURLString:draft.url ?: @""];
    self.editorParamsView.text = [self _queryEditorTextFromItems:draft.queryItems fallbackURL:draft.url ?: @""];
    self.editorHeadersView.text = [self _headerEditorTextFromDictionary:draft.headers];
    self.editorBodyView.text = (draft.bodyMode == VCReplayBodyModeForm) ? [self _formEditorTextFromBodyText:draft.body ?: @""] : (draft.body ?: @"");
    self.editorBodyModeControl.selectedSegmentIndex = draft.bodyMode;
    [self _populateNetworkModalTextAreasForRecord:self.editingRecord];
    NSString *favoriteTitle = self.showingFavorites ? VCTextLiteral(@"Save Favorite") : VCTextLiteral(@"Save Draft");
    [self.editorFavoriteButton setTitle:favoriteTitle forState:UIControlStateNormal];
    [self _setEditorTab:initialTab];
    self.editorOverlay.hidden = NO;
    [self _refreshEditorDock];
    [UIView animateWithDuration:0.18 animations:^{ self.editorOverlay.alpha = 1.0; }];
}

- (void)_hideEditorOverlay {
    [UIView animateWithDuration:0.18 animations:^{ self.editorOverlay.alpha = 0; } completion:^(BOOL finished) {
        self.editorOverlay.hidden = YES;
        self.editingDraft = nil;
        self.editingRecord = nil;
        [self _refreshEditorDock];
    }];
}

- (NSDictionary *)_formDictionaryFromBodyText:(NSString *)text {
    NSMutableDictionary *dictionary = [NSMutableDictionary new];
    for (NSString *line in [self _parameterRowsFromEditorText:text]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        NSRange separator = [trimmed rangeOfString:@"="];
        if (separator.location == NSNotFound) return nil;
        NSString *key = [[trimmed substringToIndex:separator.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *value = [[trimmed substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        key = [key stringByRemovingPercentEncoding] ?: key;
        value = [value stringByRemovingPercentEncoding] ?: value;
        if (key.length == 0) return nil;
        dictionary[key] = value ?: @"";
    }
    return dictionary;
}

- (NSString *)_formEditorTextFromBodyText:(NSString *)text {
    NSDictionary *form = [self _formDictionaryFromBodyText:text ?: @""];
    if (![form isKindOfClass:[NSDictionary class]] || form.count == 0) return @"";
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    NSArray *keys = [[form allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (id key in keys) {
        id value = form[key];
        [lines addObject:[NSString stringWithFormat:@"%@=%@", [key description] ?: @"", [value description] ?: @""]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)_bodyParamEditorTextFromJSONBody:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return @"";
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return @"";
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    NSArray *keys = [[(NSDictionary *)json allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (id key in keys) {
        id value = [(NSDictionary *)json objectForKey:key];
        NSString *valueText = nil;
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
            valueText = [value description];
        } else if (value) {
            valueText = [self _prettyJSONStringFromObject:value fallback:[value description]];
            valueText = VCNetCompactLine(valueText);
        }
        [lines addObject:[NSString stringWithFormat:@"%@=%@", [key description] ?: @"", valueText ?: @""]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)_inlineBodyEditorTextForRecord:(VCNetRecord *)record {
    NSString *bodyText = [record requestBodyAsString];
    if ([bodyText isEqualToString:@"(empty)"]) return @"";
    VCReplayBodyMode mode = [self _bodyModeForText:bodyText headers:record.requestHeaders];
    if (mode == VCReplayBodyModeForm) {
        NSString *formText = [self _formEditorTextFromBodyText:bodyText];
        return formText.length > 0 ? formText : (bodyText ?: @"");
    }
    return bodyText ?: @"";
}

- (NSString *)_inlineBodyTitleForRecord:(VCNetRecord *)record {
    NSString *bodyText = [record requestBodyAsString];
    VCReplayBodyMode mode = [self _bodyModeForText:bodyText headers:record.requestHeaders];
    if (mode == VCReplayBodyModeForm) return VCTextLiteral(@"Inline Form Body");
    if (mode == VCReplayBodyModeJSON) return VCTextLiteral(@"Inline JSON Body");
    return VCTextLiteral(@"Inline Body");
}

- (NSString *)_networkModalInfoTextForRecord:(VCNetRecord *)record {
    if (!record) return @"";
    NSString *host = record.hostKey ?: ([NSURL URLWithString:record.url ?: @""].host ?: @"--");
    NSString *path = VCNetPathSummary(record.url);
    NSString *requestHeadersText = [self _headerEditorTextFromDictionary:record.requestHeaders];
    NSString *responseHeadersText = [self _headerEditorTextFromDictionary:record.responseHeaders];
    NSString *requestBody = [record requestBodyAsString];
    NSString *responseBody = [record responseBodyAsString];
    NSString *requestBodyPreview = [VCNetCompactLine(requestBody) isEqualToString:@"(empty)"] ? @"(empty)" : VCNetTruncatedText(requestBody, 1200);
    NSString *responseBodyPreview = [VCNetCompactLine(responseBody) isEqualToString:@"(empty)"] ? @"(empty)" : VCNetTruncatedText(responseBody, 1400);
    NSString *curl = [[VCNetMonitor shared] curlCommandForRecord:record] ?: @"";
    NSString *rules = record.wasModifiedByRule
        ? [NSString stringWithFormat:@"Modified by %@ rule(s)\n%@", @((NSInteger)record.matchedRules.count), [record.matchedRules componentsJoinedByString:@"\n"]]
        : @"Clean pass";
    return [NSString stringWithFormat:
            @"Overview\n"
             "Method     %@\n"
             "Status     %ld\n"
             "Host       %@\n"
             "Path       %@\n"
             "Timing     %.0fms\n"
             "MIME       %@\n"
             "Payload    %@ request / %@ response\n\n"
             "Request Headers\n%@\n\n"
             "Response Headers\n%@\n\n"
             "Request Body\n%@\n\n"
             "Response Body\n%@\n\n"
             "cURL\n%@\n\n"
             "Rules\n%@",
             record.method ?: @"GET",
             (long)record.statusCode,
             host,
             path,
             record.duration * 1000.0,
             record.mimeType ?: @"--",
             VCNetBodySizeText(record.requestBody),
             VCNetBodySizeText(record.responseBody),
             requestHeadersText.length > 0 ? requestHeadersText : @"(none)",
             responseHeadersText.length > 0 ? responseHeadersText : @"(none)",
             requestBodyPreview.length > 0 ? requestBodyPreview : @"(empty)",
             responseBodyPreview.length > 0 ? responseBodyPreview : @"(empty)",
             curl.length > 0 ? curl : @"(unavailable)",
             rules];
}

- (NSString *)_networkModalParamsTextForRecord:(VCNetRecord *)record {
    if (!record) return @"";
    NSString *query = [self _inlineParamsEditorTextForRecord:record];
    NSString *bodyParams = [self _bodyParamsSummaryForRecord:record];
    NSString *bodyText = [self _inlineBodyEditorTextForRecord:record];
    NSString *headers = [self _headerEditorTextFromDictionary:record.requestHeaders];
    return [NSString stringWithFormat:
            @"Query Params\n%@\n\n"
             "Body Params\n%@\n\n"
             "Replay Body\n%@\n\n"
             "Request Headers\n%@",
             query.length > 0 ? query : @"(no query params captured)",
             bodyParams.length > 0 ? bodyParams : @"(no structured body params captured)",
             bodyText.length > 0 ? bodyText : @"(empty request body)",
             headers.length > 0 ? headers : @"(no request headers captured)"];
}

- (void)_syncReplayEditorsIntoParamsTab {
    self.editorParamsQueryView.text = self.editorParamsView.text ?: @"";
    self.editorParamsHeadersMirrorView.text = self.editorHeadersView.text ?: @"";
    self.editorParamsBodyMirrorView.text = self.editorBodyView.text ?: @"";
}

- (void)_syncParamsTabIntoReplayEditors {
    self.editorParamsView.text = self.editorParamsQueryView.text ?: @"";
    self.editorHeadersView.text = self.editorParamsHeadersMirrorView.text ?: @"";
    self.editorBodyView.text = self.editorParamsBodyMirrorView.text ?: @"";
}

- (void)_populateNetworkModalTextAreasForRecord:(VCNetRecord *)record {
    if (!record) return;
    NSString *host = record.hostKey ?: ([NSURL URLWithString:record.url ?: @""].host ?: @"--");
    NSString *path = VCNetPathSummary(record.url);
    NSString *requestHeadersText = [self _headerEditorTextFromDictionary:record.requestHeaders];
    NSString *responseHeadersText = [self _headerEditorTextFromDictionary:record.responseHeaders];
    NSString *requestBody = [record requestBodyAsString];
    NSString *responseBody = [record responseBodyAsString];
    NSString *requestBodyPreview = [VCNetCompactLine(requestBody) isEqualToString:@"(empty)"] ? @"(empty)" : VCNetTruncatedText(requestBody, 1200);
    NSString *responseBodyPreview = [VCNetCompactLine(responseBody) isEqualToString:@"(empty)"] ? @"(empty)" : VCNetTruncatedText(responseBody, 1400);
    NSString *curl = [[VCNetMonitor shared] curlCommandForRecord:record] ?: @"";
    NSString *rules = record.wasModifiedByRule
        ? [NSString stringWithFormat:@"Modified by %@ rule(s)\n%@", @((NSInteger)record.matchedRules.count), [record.matchedRules componentsJoinedByString:@"\n"]]
        : @"Clean pass";

    self.editorOverviewView.text = [NSString stringWithFormat:
                                    @"Method     %@\n"
                                     "Status     %ld\n"
                                     "Host       %@\n"
                                     "Path       %@\n"
                                     "Timing     %.0fms\n"
                                     "MIME       %@\n"
                                     "Payload    %@ request / %@ response",
                                     record.method ?: @"GET",
                                     (long)record.statusCode,
                                     host,
                                     path,
                                     record.duration * 1000.0,
                                     record.mimeType ?: @"--",
                                     VCNetBodySizeText(record.requestBody),
                                     VCNetBodySizeText(record.responseBody)];
    self.editorInfoRequestHeadersView.text = requestHeadersText.length > 0 ? requestHeadersText : @"(none)";
    self.editorInfoResponseHeadersView.text = responseHeadersText.length > 0 ? responseHeadersText : @"(none)";
    self.editorInfoRequestBodyView.text = requestBodyPreview.length > 0 ? requestBodyPreview : @"(empty)";
    self.editorInfoResponseBodyView.text = responseBodyPreview.length > 0 ? responseBodyPreview : @"(empty)";
    self.editorInfoCurlView.text = curl.length > 0 ? curl : @"(unavailable)";
    self.editorInfoRulesView.text = rules;
    [self _syncReplayEditorsIntoParamsTab];
}

- (void)_setEditorTab:(VCNetworkModalTab)tab {
    NSInteger previousTab = self.editorTabControl.selectedSegmentIndex;
    if (previousTab == VCNetworkModalTabParams && tab != VCNetworkModalTabParams) {
        [self _syncParamsTabIntoReplayEditors];
    } else if (previousTab == VCNetworkModalTabReplay && tab == VCNetworkModalTabParams) {
        [self _syncReplayEditorsIntoParamsTab];
    }

    self.editorTabControl.selectedSegmentIndex = tab;
    BOOL showingInfo = tab == VCNetworkModalTabInfo;
    BOOL showingParams = tab == VCNetworkModalTabParams;
    BOOL showingReplay = tab == VCNetworkModalTabReplay;
    self.editorInfoScrollView.hidden = !showingInfo;
    self.editorParamsScrollView.hidden = !showingParams;
    self.editorScrollView.hidden = !showingReplay;
    BOOL actionVisible = showingParams || showingReplay;
    self.editorFavoriteButton.hidden = !actionVisible;
    self.editorReplayButton.hidden = !actionVisible;
    self.editorFavoriteButton.enabled = actionVisible;
    self.editorReplayButton.enabled = actionVisible;
    [self.editorCancelButton setTitle:(actionVisible ? VCTextLiteral(@"Cancel") : VCTextLiteral(@"Done")) forState:UIControlStateNormal];

    if (showingInfo) {
        self.editorHintLabel.text = VCTextLiteral(@"Captured request and response details in copyable text areas.");
    } else if (showingParams) {
        BOOL hasParams = (self.editorParamsQueryView.text ?: @"").length > 0;
        BOOL hasBody = (self.editorParamsBodyMirrorView.text ?: @"").length > 0;
        NSMutableArray<NSString *> *parts = [NSMutableArray new];
        [parts addObject:hasParams ? VCTextLiteral(@"Query params loaded.") : VCTextLiteral(@"Query params empty; add key=value lines when needed.")];
        [parts addObject:hasBody ? VCTextLiteral(@"Body loaded.") : VCTextLiteral(@"Body empty for this request.")];
        self.editorHintLabel.text = [parts componentsJoinedByString:@" "];
    } else {
        BOOL hasParams = (self.editorParamsView.text ?: @"").length > 0;
        BOOL hasBody = (self.editorBodyView.text ?: @"").length > 0;
        NSMutableArray<NSString *> *parts = [NSMutableArray new];
        [parts addObject:hasParams ? VCTextLiteral(@"Query params loaded.") : VCTextLiteral(@"Query params empty; add key=value lines when needed.")];
        [parts addObject:hasBody ? VCTextLiteral(@"Body loaded.") : VCTextLiteral(@"Body empty for this request.")];
        self.editorHintLabel.text = [parts componentsJoinedByString:@" "];
    }
    self.editorHintLabel.textColor = kVCTextSecondary;
}

- (void)_editorTabChanged:(UISegmentedControl *)sender {
    [self _setEditorTab:(VCNetworkModalTab)sender.selectedSegmentIndex];
}

- (void)_showNetworkModalForRecord:(VCNetRecord *)record initialTab:(VCNetworkModalTab)initialTab {
    if (!record) return;
    VCReplayDraft *draft = [VCReplayDraft draftFromRecord:record];
    draft.bodyMode = [self _bodyModeForText:draft.body headers:draft.headers];
    [self _showEditorForDraft:draft record:record initialTab:initialTab];
}

- (VCReplayDraft *)_draftFromEditorWithError:(NSString **)errorMessage {
    if (self.editorTabControl.selectedSegmentIndex == VCNetworkModalTabParams) {
        [self _syncParamsTabIntoReplayEditors];
    }
    NSString *rawMethod = self.editorMethodField.text ?: @"GET";
    NSString *method = [[rawMethod stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if (method.length == 0) method = @"GET";
    NSString *fullURLString = [self _composedReplayURLString];
    NSURL *url = [NSURL URLWithString:fullURLString ?: @""];
    if (!url || fullURLString.length == 0) {
            if (errorMessage) *errorMessage = VCTextLiteral(@"Invalid base URL or query params. Fix them before replaying.");
        return nil;
    }
    NSDictionary *headers = nil;
    if (![self _tryParseHeadersEditorText:self.editorHeadersView.text ?: @"" result:&headers]) {
            if (errorMessage) *errorMessage = VCTextLiteral(@"Headers must be JSON or lines like Content-Type: application/json.");
        return nil;
    }
    NSString *body = self.editorBodyView.text ?: @"";
    VCReplayBodyMode bodyMode = (VCReplayBodyMode)self.editorBodyModeControl.selectedSegmentIndex;
    if (bodyMode == VCReplayBodyModeJSON) {
        NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : @{};
        if (!json && body.length > 0) {
            if (errorMessage) *errorMessage = VCTextLiteral(@"Body mode is JSON, but the body is not valid JSON.");
            return nil;
        }
        if ([self _headerValueInDictionary:headers forName:@"Content-Type"].length == 0) {
            NSMutableDictionary *mutableHeaders = [headers mutableCopy];
            mutableHeaders[@"Content-Type"] = @"application/json";
            headers = mutableHeaders;
        }
    } else if (bodyMode == VCReplayBodyModeForm) {
        NSDictionary *form = [self _formDictionaryFromBodyText:body];
        if (!form && body.length > 0) {
            if (errorMessage) *errorMessage = VCTextLiteral(@"Form body expects lines like key=value.");
            return nil;
        }
        NSMutableArray<NSString *> *pairs = [NSMutableArray new];
        [form enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
            NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: key;
            NSString *encodedValue = [obj stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: obj;
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
        }];
        body = [pairs componentsJoinedByString:@"&"];
        NSMutableDictionary *mutableHeaders = [headers mutableCopy];
        if ([self _headerValueInDictionary:mutableHeaders forName:@"Content-Type"].length == 0) {
            mutableHeaders[@"Content-Type"] = @"application/x-www-form-urlencoded";
        }
        headers = mutableHeaders;
    }

    VCReplayDraft *draft = [[VCReplayDraft alloc] init];
    draft.favoriteID = self.editingDraft.favoriteID.length > 0 ? self.editingDraft.favoriteID : [[NSUUID UUID] UUIDString];
    draft.favoriteName = [[self.editorFavoriteNameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    draft.method = method;
    draft.url = url.absoluteString ?: self.editingDraft.url ?: @"";
    draft.queryItems = [self _queryItemDictionariesFromEditorText:self.editorParamsView.text ?: @""];
    draft.headers = headers ?: @{};
    draft.body = body ?: @"";
    draft.bodyMode = bodyMode;
    draft.hostKey = url.host ?: @"";
    draft.statusBucket = self.editingDraft.statusBucket ?: @"other";
    draft.exportSnapshot = self.editingDraft.exportSnapshot ?: @{};
    draft.createdAt = self.editingDraft.createdAt ?: [NSDate date];
    return draft;
}

- (void)_saveEditedFavorite {
    NSString *errorMessage = nil;
    VCReplayDraft *draft = [self _draftFromEditorWithError:&errorMessage];
    if (!draft) {
        self.editorHintLabel.text = errorMessage ?: @"Unable to save this draft.";
        self.editorHintLabel.textColor = kVCRed;
        return;
    }
    NSIndexSet *indexes = [self.favoriteRequests indexesOfObjectsPassingTest:^BOOL(VCReplayDraft *obj, NSUInteger idx, BOOL *stop) {
        return [obj.favoriteID isEqualToString:draft.favoriteID];
    }];
    if (indexes.count > 0) {
        [self.favoriteRequests removeObjectsAtIndexes:indexes];
    }
    if (draft.favoriteName.length == 0) {
        draft.favoriteName = draft.displayName;
    }
    [self.favoriteRequests insertObject:draft atIndex:0];
    [self _saveFavorites];
    self.editorHintLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Saved favorite draft %@."), draft.displayName];
    self.editorHintLabel.textColor = kVCGreen;
    self.statusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Saved favorite %@"), draft.displayName];
    if (self.showingFavorites) {
        [self _applyFilter];
    }
}

- (void)_performEditedResend {
    if (!self.editingDraft) return;
    NSString *errorMessage = nil;
    VCReplayDraft *draft = [self _draftFromEditorWithError:&errorMessage];
    if (!draft) {
        self.editorHintLabel.text = errorMessage ?: @"Unable to replay this draft.";
        self.editorHintLabel.textColor = kVCRed;
        return;
    }
    VCNetRecord *record = [self _recordFromDraft:draft];
    NSDictionary *mods = @{
        @"method": draft.method ?: @"GET",
        @"url": draft.url ?: @"",
        @"headers": draft.headers ?: @{},
        @"body": draft.body ?: @"",
    };
    [[VCNetMonitor shared] resendRecord:record withModifications:mods];
    self.statusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Replayed %@ %@"), draft.method ?: @"GET", [NSURL URLWithString:draft.url ?: @""].host ?: VCTextLiteral(@"request")];
    self.editorHintLabel.text = VCTextLiteral(@"Replay request prepared.");
    self.editorHintLabel.textColor = kVCTextSecondary;
    [self _hideEditorOverlay];
}

- (void)_performInlineReplayForRecord:(VCNetRecord *)record paramsText:(NSString *)paramsText bodyText:(NSString *)bodyText {
    if (!record) return;
    NSString *baseURL = [self _baseURLStringFromURLString:record.url ?: @""];
    NSString *fullURL = [self _composedURLStringWithBaseURLString:baseURL paramsText:paramsText ?: @""];
    NSURL *url = [NSURL URLWithString:fullURL ?: @""];
    if (!url) {
        self.statusLabel.text = VCTextLiteral(@"Inline replay needs a valid URL.");
        return;
    }

    NSDictionary *headers = record.requestHeaders ?: @{};
    NSString *body = bodyText ?: @"";
    VCReplayBodyMode bodyMode = [self _bodyModeForText:[record requestBodyAsString] headers:headers];
    if (bodyMode == VCReplayBodyModeJSON && body.length > 0) {
        NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (!json) {
            self.statusLabel.text = VCTextLiteral(@"Inline JSON body needs valid JSON.");
            return;
        }
    } else if (bodyMode == VCReplayBodyModeForm) {
        NSDictionary *form = [self _formDictionaryFromBodyText:body];
        if (!form && body.length > 0) {
            self.statusLabel.text = VCTextLiteral(@"Inline form body expects key=value pairs.");
            return;
        }
        NSMutableArray<NSString *> *pairs = [NSMutableArray new];
        [form enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
            NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: key;
            NSString *encodedValue = [obj stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: obj;
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
        }];
        body = [pairs componentsJoinedByString:@"&"];
    }

    VCNetRecord *replayRecord = [[VCNetRecord alloc] init];
    replayRecord.method = record.method ?: @"GET";
    replayRecord.url = fullURL ?: record.url ?: @"";
    replayRecord.requestHeaders = headers;
    replayRecord.requestBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    replayRecord.hostKey = url.host ?: record.hostKey ?: @"";

    [[VCNetMonitor shared] resendRecord:replayRecord withModifications:@{
        @"method": replayRecord.method ?: @"GET",
        @"url": replayRecord.url ?: @"",
        @"headers": headers ?: @{},
        @"body": body ?: @"",
    }];
    self.statusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Inline replay sent %@ %@"), replayRecord.method ?: @"GET", url.host ?: VCTextLiteral(@"request")];
}

- (void)_applyFilter {
    NSMutableArray *result = [NSMutableArray new];
    NSString *search = _searchBar.text ?: @"";
    VCNetFilter f = (VCNetFilter)_filterCtrl.selectedSegmentIndex;
    VCNetQuickScope scope = (VCNetQuickScope)_scopeCtrl.selectedSegmentIndex;
    VCNetStatusScope statusScope = (VCNetStatusScope)_statusScopeCtrl.selectedSegmentIndex;
    VCNetContentScope contentScope = (VCNetContentScope)_contentScopeCtrl.selectedSegmentIndex;
    NSRegularExpression *regex = nil;
    NSString *trimmedSearch = [search stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<VCNetRecord *> *displayRecords = [self _displayRecords];
    [self _updateFilterSummaryButtons];
    [self _updateHostFilterChips];
    if ([trimmedSearch hasPrefix:@"re:"]) {
        NSError *error = nil;
        regex = [NSRegularExpression regularExpressionWithPattern:[trimmedSearch substringFromIndex:3] options:NSRegularExpressionCaseInsensitive error:&error];
        if (error || !regex) {
            _filteredRecords = @[];
            self.tableView.backgroundView = nil;
            _statusLabel.text = VCTextLiteral(@"Invalid regex. Use plain text or re:<pattern>.");
            [_tableView reloadData];
            return;
        }
    }

    for (VCNetRecord *r in displayRecords) {
        if (f == VCNetFilterGET && ![r.method isEqualToString:@"GET"]) continue;
        if (f == VCNetFilterPOST && ![r.method isEqualToString:@"POST"]) continue;
        if (f == VCNetFilterWS && !r.isWebSocket) continue;
        if (scope == VCNetQuickScopeErrors && r.statusCode < 400) continue;
        if (scope == VCNetQuickScopeSlow && r.duration < 1.0) continue;
        if (scope == VCNetQuickScopeModified && !r.wasModifiedByRule) continue;
        if (statusScope == VCNetStatusScope2xx && !(r.statusCode >= 200 && r.statusCode < 300)) continue;
        if (statusScope == VCNetStatusScope4xx && !(r.statusCode >= 400 && r.statusCode < 500)) continue;
        if (statusScope == VCNetStatusScope5xx && !(r.statusCode >= 500 && r.statusCode < 600)) continue;
        if (![self _record:r matchesContentScope:contentScope]) continue;
        if (self.selectedHostFilter.length > 0 && ![r.hostKey isEqualToString:self.selectedHostFilter]) continue;
        if (trimmedSearch.length > 0) {
            if (regex) {
                NSString *blob = [self _searchBlobForRecord:r];
                if ([regex firstMatchInString:blob options:0 range:NSMakeRange(0, blob.length)] == nil) continue;
            } else if (![self _record:r matchesSearch:trimmedSearch]) {
                continue;
            }
        }
        [result addObject:r];
    }
    _filteredRecords = result;
    NSUInteger errorCount = 0;
    NSUInteger slowCount = 0;
    NSUInteger modifiedCount = 0;
    for (VCNetRecord *record in displayRecords) {
        if (record.statusCode >= 400) errorCount++;
        if (record.duration >= 1.0) slowCount++;
        if (record.wasModifiedByRule) modifiedCount++;
    }
    NSString *searchScopeText = trimmedSearch.length > 0 ? [NSString stringWithFormat:@" • %@: %@", VCTextLiteral(@"Search"), trimmedSearch] : @"";
    NSString *scopeLabel = @"";
    switch ((VCNetQuickScope)_scopeCtrl.selectedSegmentIndex) {
        case VCNetQuickScopeErrors: scopeLabel = [NSString stringWithFormat:@" • %@", VCTextLiteral(@"Errors")]; break;
        case VCNetQuickScopeSlow: scopeLabel = [NSString stringWithFormat:@" • %@", VCTextLiteral(@"Slow")]; break;
        case VCNetQuickScopeModified: scopeLabel = [NSString stringWithFormat:@" • %@", VCTextLiteral(@"Modified")]; break;
        default: break;
    }
    NSString *statusScopeLabel = @"";
    switch (statusScope) {
        case VCNetStatusScope2xx: statusScopeLabel = @" • 2xx"; break;
        case VCNetStatusScope4xx: statusScopeLabel = @" • 4xx"; break;
        case VCNetStatusScope5xx: statusScopeLabel = @" • 5xx"; break;
        default: break;
    }
    NSString *contentScopeLabel = @"";
    switch (contentScope) {
        case VCNetContentScopeImage: contentScopeLabel = [NSString stringWithFormat:@" • %@", VCTextLiteral(@"Img")]; break;
        case VCNetContentScopeXHR: contentScopeLabel = [NSString stringWithFormat:@" • %@", VCTextLiteral(@"XHR")]; break;
        case VCNetContentScopeJSON: contentScopeLabel = [NSString stringWithFormat:@" • %@", VCTextLiteral(@"JSON")]; break;
        default: break;
    }
    NSString *hostLabel = self.selectedHostFilter.length > 0 ? [NSString stringWithFormat:@" • host:%@", self.selectedHostFilter] : @"";
    NSString *mode = self.showingFavorites ? VCTextLiteral(@"Fav") : VCTextLiteral(@"Req");
    _statusLabel.text = [NSString stringWithFormat:@"%lu/%lu %@ · %lu err · %lu slow · %lu mod%@%@%@",
                         (unsigned long)_filteredRecords.count,
                         (unsigned long)displayRecords.count,
                         mode,
                         (unsigned long)errorCount,
                         (unsigned long)slowCount,
                         (unsigned long)modifiedCount,
                         scopeLabel,
                         statusScopeLabel,
                         [NSString stringWithFormat:@"%@%@%@", contentScopeLabel, hostLabel, searchScopeText]];
    if (_filteredRecords.count == 0) {
        UILabel *emptyLabel = [[UILabel alloc] init];
        if (trimmedSearch.length > 0) {
            emptyLabel.text = VCTextLiteral(@"No matching requests.\nTry broader text or use re:<pattern>.");
        } else if (self.showingFavorites) {
            emptyLabel.text = VCTextLiteral(@"No favorites yet.\nSwipe a request and tap Fav to save one.");
        } else {
            emptyLabel.text = VCTextLiteral(@"No captured requests yet.");
        }
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        emptyLabel.numberOfLines = 0;
        emptyLabel.textColor = kVCTextMuted;
        emptyLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        self.tableView.backgroundView = emptyLabel;
    } else {
        self.tableView.backgroundView = nil;
    }
    if (self.expandedRow >= (NSInteger)self.filteredRecords.count) {
        self.expandedRow = -1;
    }
    [_tableView reloadData];
    [self _refreshEditorDock];
}

#pragma mark - VCNetMonitorDelegate

- (void)netMonitor:(VCNetMonitor *)monitor didCaptureRecord:(VCNetRecord *)record {
    vc_dispatch_main(^{ [self _refresh]; });
}

- (void)netMonitor:(VCNetMonitor *)monitor didCaptureWSFrame:(VCWebSocketFrame *)frame {
    // WS frames shown inline with records
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { [self _applyFilter]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_filteredRecords.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL isExpanded = (indexPath.row == _expandedRow);
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:(isExpanded ? kExpandedCellID : kCellID) forIndexPath:indexPath];
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.92];
    cell.contentView.layer.cornerRadius = 10.0;
    cell.contentView.layer.borderWidth = 1.0;
    cell.contentView.layer.borderColor = kVCBorder.CGColor;
    if (!isExpanded) {
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = kVCFontMonoSm;
        cell.textLabel.textColor = kVCTextPrimary;
    }

    UIView *selectedBg = [[UIView alloc] init];
    selectedBg.backgroundColor = kVCAccentDim;
    selectedBg.layer.cornerRadius = 12.0;
    cell.selectedBackgroundView = selectedBg;

    VCNetRecord *r = _filteredRecords[indexPath.row];
    UIColor *statusColor = (r.statusCode >= 200 && r.statusCode < 300) ? kVCGreen :
                           (r.statusCode >= 400) ? kVCRed : kVCYellow;

    if (isExpanded) {
        NSMutableAttributedString *detail = [[NSMutableAttributedString alloc] init];
        NSMutableParagraphStyle *bodyStyle = [[NSMutableParagraphStyle alloc] init];
        bodyStyle.lineSpacing = 3.0;
        bodyStyle.paragraphSpacing = 4.0;
        NSDictionary *headingAttrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: kVCAccent,
            NSParagraphStyleAttributeName: bodyStyle
        };
        NSDictionary *tabAttrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: kVCAccentHover,
            NSBackgroundColorAttributeName: kVCAccentDim,
            NSParagraphStyleAttributeName: bodyStyle
        };
        NSDictionary *bodyAttrs = @{
            NSFontAttributeName: kVCFontMonoSm,
            NSForegroundColorAttributeName: kVCTextPrimary,
            NSParagraphStyleAttributeName: bodyStyle
        };
        NSDictionary *mutedAttrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: kVCTextSecondary,
            NSParagraphStyleAttributeName: bodyStyle
        };
        NSDictionary *statusAttrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: statusColor,
            NSParagraphStyleAttributeName: bodyStyle
        };
        void (^appendSection)(NSString *, NSString *) = ^(NSString *title, NSString *text) {
            [detail appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@\n", title ?: @""]
                                                                           attributes:headingAttrs]];
            [detail appendAttributedString:[[NSAttributedString alloc] initWithString:(text.length > 0 ? text : @"(empty)")
                                                                           attributes:bodyAttrs]];
        };
        [detail appendAttributedString:[self _typeBadgeAttributedStringForRecord:r]];
        NSString *host = r.hostKey ?: ([NSURL URLWithString:r.url ?: @""].host ?: @"--");
        NSString *path = VCNetPathSummary(r.url);
        NSString *direction = [VCNetCompactLine([r requestBodyAsString]) isEqualToString:@"(empty)"] ? @"↓" : @"↑";
        [detail appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@  ", r.method ?: @"GET"] attributes:bodyAttrs]];
        [detail appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%ld", (long)r.statusCode] attributes:statusAttrs]];
        [detail appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"  %@\n", host] attributes:bodyAttrs]];
        NSString *overview = [NSString stringWithFormat:@"Host       %@\nPath       %@\nStatus     %ld\nTiming     %.0fms\nPayload    %@ request • %@ response %@\nMIME       %@\nParams     %@",
                              host,
                              path,
                              (long)r.statusCode,
                              r.duration * 1000.0,
                              VCNetBodySizeText(r.requestBody),
                              VCNetBodySizeText(r.responseBody),
                              direction,
                              r.mimeType ?: @"--",
                              VCNetCompactLine([self _paramsSummaryForRecord:r])];
        appendSection(VCTextLiteral(@"Overview"), overview);
        appendSection(VCTextLiteral(@"Params"), [self _paramsSummaryForRecord:r]);

        [detail appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n Headers " attributes:tabAttrs]];
        [detail appendAttributedString:[[NSAttributedString alloc] initWithString:@"  Body " attributes:tabAttrs]];
        [detail appendAttributedString:[[NSAttributedString alloc] initWithString:@"  Timing " attributes:tabAttrs]];
        [detail appendAttributedString:[[NSAttributedString alloc] initWithString:@"  Rules " attributes:tabAttrs]];

        NSString *requestHeadersText = VCNetTruncatedText([self _headerEditorTextFromDictionary:r.requestHeaders], 720);
        NSString *responseHeadersText = VCNetTruncatedText([self _headerEditorTextFromDictionary:r.responseHeaders], 720);
        appendSection(VCTextLiteral(@"Headers"), [NSString stringWithFormat:@"Request\n%@\n\nResponse\n%@",
                                   requestHeadersText.length > 0 ? requestHeadersText : @"(none)",
                                   responseHeadersText.length > 0 ? responseHeadersText : @"(none)"]);

        NSString *reqBody = [r requestBodyAsString];
        NSString *resBody = [r responseBodyAsString];
        NSString *requestBodyPreview = [VCNetCompactLine(reqBody) isEqualToString:@"(empty)"] ? @"(empty)" : VCNetTruncatedText(reqBody, 900);
        NSString *responseBodyPreview = [VCNetCompactLine(resBody) isEqualToString:@"(empty)"] ? @"(empty)" : VCNetTruncatedText(resBody, 1100);
        appendSection(VCTextLiteral(@"Body"), [NSString stringWithFormat:@"Request\n%@\n\nResponse\n%@",
                                requestBodyPreview.length > 0 ? requestBodyPreview : @"(empty)",
                                responseBodyPreview.length > 0 ? responseBodyPreview : @"(empty)"]);
        NSTextAttachment *imageAttachment = [self _imagePreviewAttachmentForRecord:r maximumWidth:MIN(CGRectGetWidth(tableView.bounds) - 64.0, 240.0)];
        if (imageAttachment) {
            [detail appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\nIMAGE PREVIEW\n" attributes:headingAttrs]];
            [detail appendAttributedString:[NSAttributedString attributedStringWithAttachment:imageAttachment]];
        }

        appendSection(@"Timing", [NSString stringWithFormat:@"Duration   %.0fms\nStarted    %.3f\nBucket     %@",
                                  r.duration * 1000.0,
                                  r.startTime,
                                  r.statusBucket ?: VCNetStatusBucketForCode(r.statusCode)]);
        NSString *ruleSummary = r.wasModifiedByRule
            ? [NSString stringWithFormat:@"Modified by %@ rule(s)\n%@", @((NSInteger)r.matchedRules.count), [r.matchedRules componentsJoinedByString:@"\n"]]
            : @"Clean pass";
        appendSection(VCTextLiteral(@"Rules"), ruleSummary);
        [detail appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n\n%@\n", VCTextLiteral(@"Actions")] attributes:headingAttrs]];
        [detail appendAttributedString:[[NSAttributedString alloc] initWithString:VCTextLiteral(@"Edit params/body below, replay inline, or open the full workbench.") attributes:mutedAttrs]];
        VCNetworkExpandedCell *expandedCell = [cell isKindOfClass:[VCNetworkExpandedCell class]] ? (VCNetworkExpandedCell *)cell : nil;
        __weak __typeof__(self) weakSelf = self;
        [expandedCell configureWithDetail:detail
                               paramsText:[self _inlineParamsEditorTextForRecord:r]
                                 bodyText:[self _inlineBodyEditorTextForRecord:r]
                                bodyTitle:[self _inlineBodyTitleForRecord:r]
                      inlineReplayHandler:^(NSString *paramsText, NSString *bodyText) {
            __strong __typeof__(weakSelf) self2 = weakSelf;
            [self2 _performInlineReplayForRecord:r paramsText:paramsText bodyText:bodyText];
        } workbenchHandler:^{
            __strong __typeof__(weakSelf) self2 = weakSelf;
            [self2 _showEditorForRecord:r];
        }];
    } else {
        cell.textLabel.numberOfLines = 4;
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        NSURL *url = [NSURL URLWithString:r.url ?: @""];
        NSString *host = r.hostKey.length > 0 ? r.hostKey : (url.host ?: @"--");
        NSString *path = VCNetCompactPath(r.url, 54);
        NSString *sizeText = VCNetBodySizeText(r.responseBody);
        NSString *direction = [VCNetCompactLine([r requestBodyAsString]) isEqualToString:@"(empty)"] ? @"↓" : @"↑";
        NSString *primary = [NSString stringWithFormat:@"%@  %ld  %@", r.method ?: @"GET", (long)r.statusCode, host];
        NSString *favoriteMark = self.showingFavorites ? @" ★" : @"";
        NSString *ruleMark = r.wasModifiedByRule ? @"  Rewrite" : @"";
        NSString *slowMark = r.duration >= 1.0 ? @"  Slow" : @"";
        NSString *secondary = [NSString stringWithFormat:@"%@\n%.0fms · %@ · %@%@%@%@",
                               path,
                               r.duration * 1000,
                               sizeText,
                               direction,
                               favoriteMark,
                               ruleMark,
                               slowMark];
        NSString *fullText = [NSString stringWithFormat:@"%@\n%@", primary, secondary];
        NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];
        [attr appendAttributedString:[self _typeBadgeAttributedStringForRecord:r]];
        NSUInteger primaryStart = attr.length;
        [attr appendAttributedString:[[NSAttributedString alloc] initWithString:fullText]];
        [attr addAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: kVCTextPrimary
        } range:NSMakeRange(primaryStart, primary.length)];
        NSRange statusRange = [primary rangeOfString:[NSString stringWithFormat:@"%ld", (long)r.statusCode]];
        if (statusRange.location != NSNotFound) {
            [attr addAttributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightBold],
                NSForegroundColorAttributeName: statusColor
            } range:NSMakeRange(primaryStart + statusRange.location, statusRange.length)];
        }
        NSRange secondaryRange = [attr.string rangeOfString:secondary options:0 range:NSMakeRange(primaryStart, attr.length - primaryStart)];
        [attr addAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: kVCTextSecondary
        } range:secondaryRange];
        if (r.wasModifiedByRule) {
            NSRange ruleRange = [fullText rangeOfString:@"Rewrite"];
            if (ruleRange.location != NSNotFound) {
                [attr addAttributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightBold],
                    NSForegroundColorAttributeName: kVCAccent
                } range:NSMakeRange(primaryStart + ruleRange.location, ruleRange.length)];
            }
        }
        if (r.duration >= 1.0) {
            NSRange slowRange = [fullText rangeOfString:@"Slow"];
            if (slowRange.location != NSNotFound) {
                [attr addAttributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightBold],
                    NSForegroundColorAttributeName: kVCOrange
                } range:NSMakeRange(primaryStart + slowRange.location, slowRange.length)];
            }
        }
        cell.textLabel.text = nil;
        cell.textLabel.attributedText = attr;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.frame = UIEdgeInsetsInsetRect(cell.frame, UIEdgeInsetsMake(4, 10, 4, 10));
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.filteredRecords.count) return;
    _expandedRow = -1;
    [self _showNetworkModalForRecord:self.filteredRecords[indexPath.row] initialTab:VCNetworkModalTabInfo];
    [self _refreshEditorDock];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
              leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    VCNetRecord *record = self.filteredRecords[indexPath.row];
    UIContextualAction *copyAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                             title:VCTextLiteral(@"Copy")
                                                                           handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [UIPasteboard generalPasteboard].string = record.url ?: @"";
        self.statusLabel.text = VCTextLiteral(@"Copied request URL");
        completionHandler(YES);
    }];
    copyAction.backgroundColor = UIColorFromHex(0x0f766e);
    copyAction.image = [UIImage systemImageNamed:@"link"];
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[copyAction]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
               trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    VCNetRecord *r = _filteredRecords[indexPath.row];
    UIContextualAction *chatAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:VCTextLiteral(@"Chat") handler:^(UIContextualAction *action, UIView *sv, void (^done)(BOOL)) {
        [self _queueNetworkReferenceForRecord:r];
        done(YES);
    }];
    chatAction.backgroundColor = UIColorFromHex(0x2563eb);
    chatAction.image = [UIImage systemImageNamed:@"sparkles"];

    UIContextualAction *resendAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:VCTextLiteral(@"Replay") handler:^(UIContextualAction *action, UIView *sv, void (^done)(BOOL)) {
        [self _showNetworkModalForRecord:r initialTab:VCNetworkModalTabReplay];
        done(YES);
    }];
    resendAction.backgroundColor = kVCOrange;
    resendAction.image = [UIImage systemImageNamed:@"slider.horizontal.3"];

    UIContextualAction *favoriteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:(self.showingFavorites ? VCTextLiteral(@"Remove") : VCTextLiteral(@"Fav")) handler:^(UIContextualAction *action, UIView *sv, void (^done)(BOOL)) {
        if (self.showingFavorites) {
            [self _removeFavoriteAtIndex:indexPath.row];
        } else {
            [self _saveRecordToFavorites:r];
        }
        done(YES);
    }];
    favoriteAction.backgroundColor = self.showingFavorites ? kVCRed : UIColorFromHex(0x2563eb);
    favoriteAction.image = [UIImage systemImageNamed:self.showingFavorites ? @"star.slash" : @"star"];

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[chatAction, resendAction, favoriteAction]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (BOOL)_recordIsImage:(VCNetRecord *)record {
    NSString *mime = [[record.mimeType ?: record.responseHeaders[@"Content-Type"] ?: @"" description] lowercaseString];
    return [mime hasPrefix:@"image/"];
}

- (BOOL)_recordIsJSON:(VCNetRecord *)record {
    NSString *mime = [[record.mimeType ?: record.responseHeaders[@"Content-Type"] ?: @"" description] lowercaseString];
    if ([mime containsString:@"application/json"] || [mime containsString:@"+json"]) return YES;
    NSString *body = [[record responseBodyAsString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [body hasPrefix:@"{"] || [body hasPrefix:@"["];
}

- (BOOL)_recordIsXHRLike:(VCNetRecord *)record {
    if (record.isWebSocket || [self _recordIsImage:record] || [self _recordIsJSON:record]) return NO;
    NSString *accept = [[record.requestHeaders[@"Accept"] description] lowercaseString];
    NSString *requestedWith = [[record.requestHeaders[@"X-Requested-With"] description] lowercaseString];
    NSString *fetchMode = [[record.requestHeaders[@"Sec-Fetch-Mode"] description] lowercaseString];
    NSString *mime = [[record.mimeType ?: record.responseHeaders[@"Content-Type"] ?: @"" description] lowercaseString];
    if ([requestedWith containsString:@"xmlhttprequest"]) return YES;
    if ([fetchMode containsString:@"cors"] || [fetchMode containsString:@"same-origin"]) return YES;
    if ([accept containsString:@"json"] || [accept containsString:@"javascript"] || [accept containsString:@"xml"]) return YES;
    if (![record.method isEqualToString:@"GET"]) return YES;
    return [mime containsString:@"xml"] || [mime containsString:@"javascript"] || [mime containsString:@"text/plain"];
}

- (NSString *)_recordMimeString:(VCNetRecord *)record {
    return [[record.mimeType ?: record.responseHeaders[@"Content-Type"] ?: @"" description] lowercaseString];
}

- (NSString *)_recordPathExtension:(VCNetRecord *)record {
    NSURL *url = [NSURL URLWithString:record.url ?: @""];
    return url.pathExtension.lowercaseString ?: @"";
}

- (NSString *)_recordTypeBadgeText:(VCNetRecord *)record {
    if (record.isWebSocket) return @"WS";

    NSString *mime = [self _recordMimeString:record];
    NSString *ext = [self _recordPathExtension:record];
    NSSet<NSString *> *jsExtensions = [NSSet setWithArray:@[@"js", @"mjs", @"cjs"]];
    NSSet<NSString *> *fontExtensions = [NSSet setWithArray:@[@"woff", @"woff2", @"ttf", @"otf", @"eot"]];
    NSSet<NSString *> *mediaExtensions = [NSSet setWithArray:@[@"mp4", @"webm", @"mp3", @"wav", @"m4a", @"mov"]];

    if ([self _recordIsImage:record]) return @"IMG";
    if ([mime containsString:@"javascript"] || [jsExtensions containsObject:ext]) return @"JS";
    if ([mime containsString:@"text/css"] || [ext isEqualToString:@"css"]) return @"CSS";
    if ([self _recordIsJSON:record]) return @"JSON";
    if ([mime containsString:@"text/html"] || [mime containsString:@"application/xhtml"] || [ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) return @"HTML";
    if ([mime containsString:@"font"] || [fontExtensions containsObject:ext]) return @"FONT";
    if ([mime hasPrefix:@"audio/"] || [mime hasPrefix:@"video/"] || [mediaExtensions containsObject:ext]) return @"MEDIA";
    if ([mime containsString:@"xml"] || [ext isEqualToString:@"xml"]) return @"XML";
    if ([self _recordIsXHRLike:record]) return @"XHR";
    if (ext.length > 0 && ext.length <= 5) return ext.uppercaseString;
    return @"REQ";
}

- (UIColor *)_recordTypeBadgeColor:(VCNetRecord *)record {
    NSString *badge = [self _recordTypeBadgeText:record];
    if ([badge isEqualToString:@"WS"]) return UIColorFromHex(0x0891b2);
    if ([badge isEqualToString:@"IMG"]) return UIColorFromHex(0x2563eb);
    if ([badge isEqualToString:@"JS"]) return UIColorFromHex(0xd97706);
    if ([badge isEqualToString:@"CSS"]) return UIColorFromHex(0x1d4ed8);
    if ([badge isEqualToString:@"JSON"]) return UIColorFromHex(0x0f766e);
    if ([badge isEqualToString:@"HTML"]) return UIColorFromHex(0x15803d);
    if ([badge isEqualToString:@"FONT"]) return UIColorFromHex(0x475569);
    if ([badge isEqualToString:@"MEDIA"]) return UIColorFromHex(0xea580c);
    if ([badge isEqualToString:@"XML"]) return UIColorFromHex(0x7c3aed);
    if ([badge isEqualToString:@"XHR"]) return kVCAccent;
    return kVCTextMuted;
}

- (UIColor *)_textColorForBadgeFillColor:(UIColor *)fillColor {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    if ([fillColor getRed:&red green:&green blue:&blue alpha:&alpha]) {
        CGFloat luminance = 0.299 * red + 0.587 * green + 0.114 * blue;
        return luminance > 0.62 ? kVCBgPrimary : UIColor.whiteColor;
    }
    return UIColor.whiteColor;
}

- (UIImage *)_badgeImageWithText:(NSString *)text fillColor:(UIColor *)fillColor {
    NSString *badgeText = text.length > 0 ? text : @"REQ";
    UIFont *font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [self _textColorForBadgeFillColor:fillColor ?: kVCAccent]
    };
    CGSize textSize = [badgeText sizeWithAttributes:attributes];
    CGFloat width = MAX(30.0, ceil(textSize.width) + 14.0);
    CGFloat height = 17.0;
    CGRect rect = CGRectMake(0, 0, width, height);

    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0.0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:8.5];
    UIColor *baseColor = fillColor ?: kVCAccent;
    [[baseColor colorWithAlphaComponent:0.92] setFill];
    [path fill];

    UIBezierPath *border = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, 0.5, 0.5) cornerRadius:8.0];
    [[baseColor colorWithAlphaComponent:1.0] setStroke];
    border.lineWidth = 1.0;
    [border stroke];

    CGRect textRect = CGRectMake((width - textSize.width) * 0.5, floor((height - textSize.height) * 0.5) - 0.5, textSize.width, textSize.height);
    [badgeText drawInRect:textRect withAttributes:attributes];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (NSAttributedString *)_typeBadgeAttributedStringForRecord:(VCNetRecord *)record {
    UIImage *badgeImage = [self _badgeImageWithText:[self _recordTypeBadgeText:record]
                                          fillColor:[self _recordTypeBadgeColor:record]];
    if (!badgeImage) return [[NSAttributedString alloc] initWithString:@""];
    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
    attachment.image = badgeImage;
    attachment.bounds = CGRectMake(0, -2.0, badgeImage.size.width, badgeImage.size.height);
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
    return result;
}

- (BOOL)_record:(VCNetRecord *)record matchesContentScope:(VCNetContentScope)scope {
    switch (scope) {
        case VCNetContentScopeImage: return [self _recordIsImage:record];
        case VCNetContentScopeXHR: return [self _recordIsXHRLike:record];
        case VCNetContentScopeJSON: return [self _recordIsJSON:record];
        default: return YES;
    }
}

- (NSTextAttachment *)_imagePreviewAttachmentForRecord:(VCNetRecord *)record maximumWidth:(CGFloat)maximumWidth {
    if (![self _recordIsImage:record] || record.responseBody.length == 0) return nil;
    UIImage *image = [UIImage imageWithData:record.responseBody];
    if (!image) return nil;
    CGFloat width = MIN(MAX(maximumWidth, 120.0), image.size.width);
    CGFloat ratio = image.size.height / MAX(image.size.width, 1.0);
    CGFloat height = MIN(MAX(width * ratio, 60.0), 180.0);
    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
    attachment.image = image;
    attachment.bounds = CGRectMake(0, 8, width, height);
    return attachment;
}

- (void)_queueNetworkReferenceForRecord:(VCNetRecord *)record {
    if (!record) return;
    NSString *requestBody = [record requestBodyAsString] ?: @"";
    NSString *responseBody = [record responseBodyAsString] ?: @"";
    NSDictionary *reference = @{
        @"referenceID": [[NSUUID UUID] UUIDString],
        @"kind": @"Network",
        @"title": [NSString stringWithFormat:@"%@ %@", record.method ?: @"REQ", [NSURL URLWithString:record.url ?: @""].host ?: @"request"],
        @"payload": @{
            @"method": record.method ?: @"GET",
            @"url": record.url ?: @"",
            @"statusCode": @(record.statusCode),
            @"mimeType": record.mimeType ?: @"",
            @"requestHeaders": record.requestHeaders ?: @{},
            @"responseHeaders": record.responseHeaders ?: @{},
            @"requestBody": requestBody.length > 1200 ? [requestBody substringToIndex:1200] : requestBody,
            @"responseBody": responseBody.length > 1600 ? [responseBody substringToIndex:1600] : responseBody,
            @"matchedRules": record.matchedRules ?: @[],
            @"wasModifiedByRule": @(record.wasModifiedByRule)
        }
    };
    [[VCChatSession shared] enqueuePendingReference:reference];
    self.statusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Queued %@ for Chat"), reference[@"title"] ?: VCTextLiteral(@"Request")];
}

@end
