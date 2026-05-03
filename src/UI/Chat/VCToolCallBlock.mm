/**
 * VCToolCallBlock -- Collapsible tool call action card
 * Type badges: [M]odify [P]atch [H]ook [N]et [S]wizzle [V]iew
 */

#import "VCToolCallBlock.h"
#import "../../../VansonCLI.h"
#import "../../AI/Chat/VCChatSession.h"
#import "../../AI/ToolCall/VCToolCallParser.h"
#import "../../AI/Verification/VCVerificationGate.h"
#import "../../Core/VCCapabilityManager.h"
#import "../../Patches/VCPatchManager.h"
#import "../../Patches/VCPatchItem.h"
#import "../../Patches/VCValueItem.h"
#import "../../Patches/VCHookItem.h"
#import "../../Patches/VCNetRule.h"
#import "../../Hook/VCHookManager.h"
#import "../Base/VCOverlayCanvasManager.h"
#import "../Base/VCOverlayTrackingManager.h"
#import "../../UIInspector/VCUIInspector.h"
#import "../../Memory/VCMemoryScanEngine.h"
#import "../../Vendor/MemoryBackend/Engine/VCMemEngine.h"
#import <objc/runtime.h>

static NSString *VCToolCallNormalizedHexString(NSString *value) {
    NSMutableString *normalized = [NSMutableString new];
    NSString *source = [value isKindOfClass:[NSString class]] ? value : @"";
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger idx = 0; idx < source.length; idx++) {
        unichar ch = [source characterAtIndex:idx];
        if ([hexSet characterIsMember:ch]) {
            [normalized appendFormat:@"%c", (char)tolower((int)ch)];
        }
    }
    return [normalized copy];
}

static NSData *VCToolCallHexDataFromString(NSString *value) {
    NSString *normalized = VCToolCallNormalizedHexString(value);
    if (normalized.length == 0 || (normalized.length % 2) != 0) return nil;

    NSMutableData *data = [NSMutableData dataWithCapacity:(normalized.length / 2)];
    for (NSUInteger idx = 0; idx < normalized.length; idx += 2) {
        NSString *byteString = [normalized substringWithRange:NSMakeRange(idx, 2)];
        unsigned int byteValue = 0;
        NSScanner *scanner = [NSScanner scannerWithString:byteString];
        if (![scanner scanHexInt:&byteValue]) return nil;
        uint8_t byte = (uint8_t)byteValue;
        [data appendBytes:&byte length:1];
    }
    return [data copy];
}

static UIColor *VCToolCallColorFromString(NSString *value, UIColor *fallback) {
    NSString *trimmed = [value isKindOfClass:[NSString class]]
        ? [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString]
        : @"";
    if (trimmed.length == 0) return fallback;

    NSDictionary<NSString *, UIColor *> *named = @{
        @"red": kVCRed,
        @"green": kVCGreen,
        @"blue": kVCAccent,
        @"cyan": kVCAccent,
        @"yellow": kVCYellow,
        @"orange": kVCOrange,
        @"white": kVCTextPrimary,
        @"black": kVCBgPrimary,
        @"clear": [UIColor clearColor]
    };
    UIColor *namedColor = named[trimmed];
    if (namedColor) return namedColor;

    NSString *hex = [trimmed stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (hex.length == 6 || hex.length == 8) {
        unsigned long long raw = strtoull(hex.UTF8String, NULL, 16);
        CGFloat red = ((raw >> (hex.length == 8 ? 24 : 16)) & 0xFF) / 255.0;
        CGFloat green = ((raw >> (hex.length == 8 ? 16 : 8)) & 0xFF) / 255.0;
        CGFloat blue = ((raw >> (hex.length == 8 ? 8 : 0)) & 0xFF) / 255.0;
        CGFloat alpha = hex.length == 8 ? (raw & 0xFF) / 255.0 : 1.0;
        return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
    }
    return fallback;
}

static void VCToolCallPrepareButtonTitle(UIButton *button, CGFloat minimumScale) {
    button.titleLabel.numberOfLines = 1;
    button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = minimumScale;
    [button setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
}

@interface VCToolCallBlock ()
@property (nonatomic, strong) VCToolCall *toolCall;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIView *headerRow;
@property (nonatomic, strong) UIImageView *statusIconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIView *detailContainer;
@property (nonatomic, strong) UIButton *executeButton;
@property (nonatomic, strong) UIView *confirmContainer;
@property (nonatomic, strong) UILabel *confirmLabel;
@property (nonatomic, strong) UIButton *confirmRunButton;
@property (nonatomic, strong) UIButton *confirmCancelButton;
@property (nonatomic, strong) NSLayoutConstraint *confirmHeightConstraint;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) BOOL awaitingConfirmation;
@property (nonatomic, strong) UIColor *baseBorderColor;
- (BOOL)_applyExecutionWithMessage:(NSString **)message;
- (BOOL)_executeOverlayTrackWithMessage:(NSString **)message;
@end

@implementation VCToolCallBlock

+ (BOOL)executeToolCall:(VCToolCall *)toolCall resultMessage:(NSString * _Nullable * _Nullable)message {
    if (![toolCall isKindOfClass:[VCToolCall class]]) {
        if (message) *message = @"Invalid tool call.";
        return NO;
    }

    [VCToolCallParser normalizeToolCall:toolCall];

    __block BOOL success = NO;
    __block NSString *result = nil;
    void (^work)(void) = ^{
        VCToolCallBlock *executor = [[VCToolCallBlock alloc] initWithToolCall:toolCall];
        success = [executor _applyExecutionWithMessage:&result];
    };

    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_sync(dispatch_get_main_queue(), work);
    }

    if (message) *message = result;
    return success;
}

- (BOOL)_isReadOnlyToolCallType:(VCToolCallType)type {
    switch (type) {
        case VCToolCallQueryRuntime:
        case VCToolCallQueryProcess:
        case VCToolCallQueryNetwork:
        case VCToolCallQueryUI:
        case VCToolCallQueryMemory:
        case VCToolCallMemoryBrowser:
        case VCToolCallMemoryScan:
        case VCToolCallPointerChain:
        case VCToolCallSignatureScan:
        case VCToolCallAddressResolve:
        case VCToolCallExportMermaid:
        case VCToolCallTraceStart:
        case VCToolCallTraceCheckpoint:
        case VCToolCallTraceStop:
        case VCToolCallTraceEvents:
        case VCToolCallTraceExportMermaid:
        case VCToolCallQueryArtifacts:
        case VCToolCallUnityRuntime:
        case VCToolCallProject3D:
            return YES;
        default:
            return NO;
    }
}

- (instancetype)initWithToolCall:(VCToolCall *)toolCall {
    if (self = [super initWithFrame:CGRectZero]) {
        _toolCall = toolCall;
        [VCToolCallParser normalizeToolCall:_toolCall];
        _expanded = NO;
        _awaitingConfirmation = NO;
        [self _buildUI];
    }
    return self;
}

- (void)_buildUI {
    VCApplyPanelSurface(self, 9.0);
    self.backgroundColor = [kVCBgSecondary colorWithAlphaComponent:0.94];
    self.baseBorderColor = [kVCBorderStrong colorWithAlphaComponent:0.82];
    self.layer.borderColor = self.baseBorderColor.CGColor;
    self.clipsToBounds = YES;

    _contentStack = [[UIStackView alloc] init];
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = 3.0;
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_contentStack];

    _headerRow = [[UIView alloc] init];
    _headerRow.backgroundColor = [UIColor clearColor];
    _headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:_headerRow];
    [_headerRow.heightAnchor constraintGreaterThanOrEqualToConstant:21.0].active = YES;

    _statusIconView = [[UIImageView alloc] init];
    _statusIconView.contentMode = UIViewContentModeScaleAspectFit;
    _statusIconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerRow addSubview:_statusIconView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = _toolCall.title ?: @"Tool Call";
    _titleLabel.font = [UIFont systemFontOfSize:9.8 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [self _titleColorForToolCall];
    _titleLabel.numberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerRow addSubview:_titleLabel];

    _badgeLabel = [[UILabel alloc] init];
    _badgeLabel.font = [UIFont monospacedSystemFontOfSize:8.4 weight:UIFontWeightMedium];
    _badgeLabel.textColor = kVCTextSecondary;
    _badgeLabel.backgroundColor = [kVCBgHover colorWithAlphaComponent:0.92];
    _badgeLabel.layer.cornerRadius = 7.0;
    _badgeLabel.layer.borderWidth = 1.0;
    _badgeLabel.layer.borderColor = [kVCBorder colorWithAlphaComponent:0.9].CGColor;
    _badgeLabel.clipsToBounds = YES;
    _badgeLabel.textAlignment = NSTextAlignmentCenter;
    _badgeLabel.numberOfLines = 1;
    _badgeLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _badgeLabel.adjustsFontSizeToFitWidth = YES;
    _badgeLabel.minimumScaleFactor = 0.78;
    [_badgeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerRow addSubview:_badgeLabel];

    _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    _chevronView.tintColor = [kVCTextMuted colorWithAlphaComponent:0.9];
    _chevronView.contentMode = UIViewContentModeScaleAspectFit;
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerRow addSubview:_chevronView];

    _previewLabel = [[UILabel alloc] init];
    _previewLabel.font = [UIFont systemFontOfSize:8.8 weight:UIFontWeightMedium];
    _previewLabel.textColor = kVCTextMuted;
    _previewLabel.numberOfLines = 1;
    _previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _previewLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:_previewLabel];

    _confirmContainer = [[UIView alloc] init];
    VCApplyPanelSurface(_confirmContainer, 8.0);
    _confirmContainer.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.84];
    _confirmContainer.hidden = YES;
    _confirmContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:_confirmContainer];

    _confirmLabel = [[UILabel alloc] init];
    _confirmLabel.text = VCTextLiteral(@"This tool call runs immediately when executed.");
    _confirmLabel.textColor = kVCTextSecondary;
    _confirmLabel.font = [UIFont systemFontOfSize:8.8 weight:UIFontWeightSemibold];
    _confirmLabel.numberOfLines = 1;
    _confirmLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _confirmLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_confirmContainer addSubview:_confirmLabel];

    _confirmRunButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_confirmRunButton setTitle:VCTextLiteral(@"Run") forState:UIControlStateNormal];
    VCApplyCompactIconTitleButtonLayout(_confirmRunButton, @"play.fill", 9.5);
    [_confirmRunButton setTitleColor:kVCBgPrimary forState:UIControlStateNormal];
    _confirmRunButton.titleLabel.font = [UIFont systemFontOfSize:8.8 weight:UIFontWeightBold];
    VCToolCallPrepareButtonTitle(_confirmRunButton, 0.84);
    _confirmRunButton.backgroundColor = kVCAccent;
    _confirmRunButton.layer.cornerRadius = 7.0;
    _confirmRunButton.contentEdgeInsets = UIEdgeInsetsMake(3, 8, 3, 8);
    [_confirmRunButton addTarget:self action:@selector(_confirmExecution) forControlEvents:UIControlEventTouchUpInside];
    _confirmRunButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_confirmContainer addSubview:_confirmRunButton];

    _confirmCancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_confirmCancelButton setTitle:VCTextLiteral(@"Dismiss") forState:UIControlStateNormal];
    VCApplyCompactIconTitleButtonLayout(_confirmCancelButton, @"xmark", 9.5);
    [_confirmCancelButton setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    _confirmCancelButton.titleLabel.font = [UIFont systemFontOfSize:8.8 weight:UIFontWeightSemibold];
    VCToolCallPrepareButtonTitle(_confirmCancelButton, 0.80);
    _confirmCancelButton.backgroundColor = kVCAccentDim;
    _confirmCancelButton.layer.cornerRadius = 7.0;
    _confirmCancelButton.layer.borderWidth = 1.0;
    _confirmCancelButton.layer.borderColor = kVCBorder.CGColor;
    _confirmCancelButton.contentEdgeInsets = UIEdgeInsetsMake(3, 8, 3, 8);
    [_confirmCancelButton addTarget:self action:@selector(_cancelExecution) forControlEvents:UIControlEventTouchUpInside];
    _confirmCancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_confirmContainer addSubview:_confirmCancelButton];

    _executeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_executeButton setTitle:[self _buttonTitleForToolCall] forState:UIControlStateNormal];
    VCApplyCompactIconTitleButtonLayout(_executeButton, [self _buttonIconNameForToolCall], 10.5);
    [_executeButton setTitleColor:[self _buttonTitleColorForToolCall] forState:UIControlStateNormal];
    _executeButton.titleLabel.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightBold];
    VCToolCallPrepareButtonTitle(_executeButton, 0.82);
    _executeButton.enabled = [self _buttonEnabledForToolCall];
    _executeButton.backgroundColor = [self _buttonBackgroundColorForToolCall];
    _executeButton.layer.cornerRadius = 7.0;
    _executeButton.layer.borderWidth = 1.0;
    _executeButton.layer.borderColor = [self _buttonBorderColorForToolCall].CGColor;
    _executeButton.contentEdgeInsets = UIEdgeInsetsMake(4, 8, 4, 8);
    [_executeButton addTarget:self action:@selector(_executeTapped) forControlEvents:UIControlEventTouchUpInside];
    _executeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerRow addSubview:_executeButton];

    _detailContainer = [[UIView alloc] init];
    VCApplyInputSurface(_detailContainer, 8.0);
    _detailContainer.backgroundColor = [kVCBgInput colorWithAlphaComponent:0.84];
    _detailContainer.hidden = YES;
    _detailContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:_detailContainer];

    _detailLabel = [[UILabel alloc] init];
    _detailLabel.font = [UIFont monospacedSystemFontOfSize:8.8 weight:UIFontWeightRegular];
    _detailLabel.textColor = [kVCTextSecondary colorWithAlphaComponent:0.92];
    _detailLabel.numberOfLines = 0;
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailLabel.text = [self _detailText];
    [_detailContainer addSubview:_detailLabel];

    _confirmHeightConstraint = [_confirmContainer.heightAnchor constraintEqualToConstant:0.0];

    [NSLayoutConstraint activateConstraints:@[
        [_contentStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [_contentStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:5],
        [_contentStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-5],
        [_contentStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],

        [_statusIconView.leadingAnchor constraintEqualToAnchor:_headerRow.leadingAnchor],
        [_statusIconView.centerYAnchor constraintEqualToAnchor:_executeButton.centerYAnchor],
        [_statusIconView.widthAnchor constraintEqualToConstant:12.0],
        [_statusIconView.heightAnchor constraintEqualToConstant:12.0],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_statusIconView.trailingAnchor constant:5],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_executeButton.centerYAnchor],
        [_badgeLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor constant:5],
        [_badgeLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_badgeLabel.heightAnchor constraintEqualToConstant:14.0],
        [_badgeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-6],

        [_chevronView.centerYAnchor constraintEqualToAnchor:_executeButton.centerYAnchor],
        [_chevronView.trailingAnchor constraintEqualToAnchor:_executeButton.leadingAnchor constant:-6],
        [_chevronView.widthAnchor constraintEqualToConstant:9.0],
        [_chevronView.heightAnchor constraintEqualToConstant:9.0],

        [_executeButton.trailingAnchor constraintEqualToAnchor:_headerRow.trailingAnchor],
        [_executeButton.topAnchor constraintEqualToAnchor:_headerRow.topAnchor],
        [_executeButton.bottomAnchor constraintEqualToAnchor:_headerRow.bottomAnchor],
        [_executeButton.widthAnchor constraintLessThanOrEqualToConstant:68.0],

        _confirmHeightConstraint,
        [_confirmLabel.leadingAnchor constraintEqualToAnchor:_confirmContainer.leadingAnchor constant:10],
        [_confirmLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_confirmRunButton.leadingAnchor constant:-8],
        [_confirmRunButton.trailingAnchor constraintEqualToAnchor:_confirmContainer.trailingAnchor constant:-8],
        [_confirmRunButton.centerYAnchor constraintEqualToAnchor:_confirmContainer.centerYAnchor],
        [_confirmRunButton.heightAnchor constraintEqualToConstant:21],
        [_confirmRunButton.widthAnchor constraintLessThanOrEqualToConstant:62],
        [_confirmCancelButton.trailingAnchor constraintEqualToAnchor:_confirmRunButton.leadingAnchor constant:-6],
        [_confirmCancelButton.centerYAnchor constraintEqualToAnchor:_confirmRunButton.centerYAnchor],
        [_confirmCancelButton.heightAnchor constraintEqualToAnchor:_confirmRunButton.heightAnchor],
        [_confirmCancelButton.widthAnchor constraintLessThanOrEqualToConstant:70],
        [_confirmLabel.centerYAnchor constraintEqualToAnchor:_confirmRunButton.centerYAnchor],
        [_detailLabel.topAnchor constraintEqualToAnchor:_detailContainer.topAnchor constant:4],
        [_detailLabel.leadingAnchor constraintEqualToAnchor:_detailContainer.leadingAnchor constant:5],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:_detailContainer.trailingAnchor constant:-5],
        [_detailLabel.bottomAnchor constraintEqualToAnchor:_detailContainer.bottomAnchor constant:-4],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:22],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_toggleExpand)];
    [self addGestureRecognizer:tap];
    [self _refreshExecutionState];
}

- (void)_animateTapFeedback {
    [UIView animateWithDuration:0.08
                     animations:^{
        self.transform = CGAffineTransformMakeScale(0.989, 0.989);
        self.layer.borderColor = [self.baseBorderColor colorWithAlphaComponent:1.0].CGColor;
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.16
                         animations:^{
            self.transform = CGAffineTransformIdentity;
            self.layer.borderColor = self.baseBorderColor.CGColor;
        }];
    }];
}

- (void)_toggleExpand {
    [self _animateTapFeedback];
    _expanded = !_expanded;
    _detailContainer.hidden = !_expanded;
    _previewLabel.numberOfLines = _expanded ? 0 : 2;
    [UIView animateWithDuration:0.18 animations:^{
        self.chevronView.transform = self->_expanded ? CGAffineTransformMakeRotation((CGFloat)M_PI_2) : CGAffineTransformIdentity;
    }];
    [self invalidateIntrinsicContentSize];
    // Notify tableView to recalculate height
    UITableView *tv = (UITableView *)self.superview;
    while (tv && ![tv isKindOfClass:[UITableView class]]) tv = (UITableView *)tv.superview;
    [tv beginUpdates];
    [tv endUpdates];
}

- (void)_executeTapped {
    if (![self _buttonEnabledForToolCall]) return;
    [self _animateTapFeedback];
    _expanded = YES;
    _detailContainer.hidden = NO;
    _previewLabel.numberOfLines = 0;
    _chevronView.transform = CGAffineTransformMakeRotation((CGFloat)M_PI_2);
    [self _applyExecutionWithMessage:nil];
    [self _refreshExecutionState];
    [self _recalculateHeight];
}

- (void)_confirmExecution {
    [self _applyExecutionWithMessage:nil];
    [self _refreshExecutionState];
    [self invalidateIntrinsicContentSize];
}

- (BOOL)_applyExecutionWithMessage:(NSString **)message {
    NSString *result = nil;
    BOOL success = [self _executeToolCallWithMessage:&result];
    self->_toolCall.lastExecutedAt = [[NSDate date] timeIntervalSince1970];
    self->_toolCall.executed = success;
    self->_toolCall.success = success;
    self->_toolCall.resultMessage = result ?: (success ? @"Executed" : @"Execution failed");
    self->_toolCall.verificationStatus = VCToolCallVerificationNone;
    self->_toolCall.verificationMessage = nil;
    if (success) {
        [VCVerificationGate applyVerificationToToolCall:self->_toolCall];
    }
    [[VCChatSession shared] saveAll];
    [self _cancelExecution];
    if (message) *message = self->_toolCall.resultMessage;
    return success;
}

- (void)_cancelExecution {
    _awaitingConfirmation = NO;
    _confirmContainer.hidden = YES;
    _confirmHeightConstraint.constant = 0.0;
    [self _recalculateHeight];
}

- (void)_recalculateHeight {
    [self invalidateIntrinsicContentSize];
    UITableView *tv = (UITableView *)self.superview;
    while (tv && ![tv isKindOfClass:[UITableView class]]) tv = (UITableView *)tv.superview;
    [tv beginUpdates];
    [tv endUpdates];
}

- (void)_refreshExecutionState {
    [_executeButton setTitle:[self _buttonTitleForToolCall] forState:UIControlStateNormal];
    VCApplyCompactIconTitleButtonLayout(_executeButton, [self _buttonIconNameForToolCall], 10.5);
    [_executeButton setTitleColor:[self _buttonTitleColorForToolCall] forState:UIControlStateNormal];
    _executeButton.enabled = [self _buttonEnabledForToolCall];
    _executeButton.backgroundColor = [self _buttonBackgroundColorForToolCall];
    _executeButton.layer.borderColor = [self _buttonBorderColorForToolCall].CGColor;
    _titleLabel.textColor = [self _titleColorForToolCall];
    _titleLabel.text = _toolCall.title ?: @"Tool Call";
    _badgeLabel.text = [self _headerBadgeText];
    _badgeLabel.hidden = (_badgeLabel.text.length == 0);
    _previewLabel.text = [self _previewText];
    _previewLabel.hidden = (_previewLabel.text.length == 0);
    _detailLabel.text = [self _detailText];
    _detailContainer.hidden = !_expanded;
    _confirmContainer.hidden = YES;
    _confirmHeightConstraint.constant = 0.0;
    _confirmRunButton.backgroundColor = _toolCall.verificationStatus == VCToolCallVerificationFailed ? kVCOrange : kVCAccent;
    NSString *reviewText = _toolCall.resultMessage.length ? _toolCall.resultMessage : @"This tool call runs immediately when triggered.";
    if (_toolCall.verificationStatus == VCToolCallVerificationFailed && _toolCall.verificationMessage.length) {
        reviewText = [NSString stringWithFormat:@"%@ • %@", reviewText, _toolCall.verificationMessage];
    }
    _confirmLabel.text = reviewText;
    _statusIconView.image = [UIImage systemImageNamed:[self _statusIconName]];
    _statusIconView.tintColor = [self _statusIconColor];
    self.alpha = [self _isReadOnlyToolCallType:_toolCall.type] ? 0.82 : 1.0;
    self.baseBorderColor = [self _buttonBorderColorForToolCall];
    self.layer.borderColor = self.baseBorderColor.CGColor;
}

- (BOOL)_executeToolCallWithMessage:(NSString **)message {
    if ([self _isReadOnlyToolCallType:_toolCall.type]) {
        if (message) *message = @"Read-only analysis tools auto-run during the AI reply.";
        return NO;
    }

    NSString *validationMessage = nil;
    if (![self _validateExecutionWithMessage:&validationMessage]) {
        if (message) *message = validationMessage ?: @"Execution blocked";
        return NO;
    }

    switch (_toolCall.type) {
        case VCToolCallModifyValue:
            return [self _executeModifyValueWithMessage:message];
        case VCToolCallWriteMemoryBytes:
            return [self _executeWriteMemoryBytesWithMessage:message];
        case VCToolCallPatchMethod:
            return [self _executePatchMethodWithMessage:message];
        case VCToolCallHookMethod:
            return [self _executeHookMethodWithMessage:message];
        case VCToolCallModifyHeader:
            return [self _executeNetworkRuleWithMessage:message];
        case VCToolCallSwizzleMethod:
            return [self _executeSwizzleMethodWithMessage:message];
        case VCToolCallModifyView:
            return [self _executeModifyViewWithMessage:message];
        case VCToolCallInsertSubview:
            return [self _executeInsertSubviewWithMessage:message];
        case VCToolCallInvokeSelector:
            return [self _executeInvokeSelectorWithMessage:message];
        case VCToolCallOverlayCanvas:
            return [self _executeOverlayCanvasWithMessage:message];
        case VCToolCallOverlayTrack:
            return [self _executeOverlayTrackWithMessage:message];
        default:
            if (message) *message = @"Unsupported tool call type.";
            return NO;
    }
}

- (BOOL)_validateExecutionWithMessage:(NSString **)message {
    VCCapabilityManager *capabilityManager = [VCCapabilityManager shared];

    if ([self _isReadOnlyToolCallType:_toolCall.type]) {
        if (message) *message = @"Read-only analysis tools auto-run in the conversation loop.";
        return NO;
    }

    switch (_toolCall.type) {
        case VCToolCallModifyValue: {
            NSString *reason = nil;
            if (![capabilityManager canUseMemoryWritesWithReason:&reason]) {
                if (message) *message = reason;
                return NO;
            }
            NSString *normalizedType = [self _normalizedValueType:[self _stringParamForKeys:@[@"dataType", @"data_type", @"type"]] allowUnsupported:YES];
            if (normalizedType.length == 0) normalizedType = @"int";
            NSSet<NSString *> *supportedTypes = [NSSet setWithArray:@[
                @"BOOL", @"char", @"uchar", @"short", @"ushort",
                @"int", @"uint", @"float", @"double", @"long",
                @"ulong", @"longlong", @"ulonglong"
            ]];
            if (![supportedTypes containsObject:normalizedType]) {
                if (message) *message = [NSString stringWithFormat:@"Direct memory writes do not support %@ yet.", normalizedType];
                return NO;
            }
            return YES;
        }
        case VCToolCallWriteMemoryBytes: {
            NSString *reason = nil;
            if (![capabilityManager canUseMemoryWritesWithReason:&reason]) {
                if (message) *message = reason;
                return NO;
            }
            uintptr_t address = [self _addressParamForKeys:@[@"address", @"addr"]];
            if (address == 0) {
                if (message) *message = @"Missing address for write_memory_bytes";
                return NO;
            }
            NSString *hexData = [self _stringParamForKeys:@[@"hexData", @"hex_data", @"bytes", @"data"]];
            NSData *data = VCToolCallHexDataFromString(hexData);
            if (!data || data.length == 0) {
                if (message) *message = @"write_memory_bytes requires a valid hexData byte string.";
                return NO;
            }
            return YES;
        }
        case VCToolCallPatchMethod:
        case VCToolCallSwizzleMethod: {
            NSString *reason = nil;
            if (![capabilityManager canUseRuntimePatchingWithReason:&reason]) {
                if (message) *message = reason;
                return NO;
            }
            if (_toolCall.type == VCToolCallPatchMethod) {
                NSString *patchType = [self _stringParamForKeys:@[@"patchType", @"patch_type", @"type"]];
                if ([patchType.lowercaseString isEqualToString:@"custom"]) {
                    if (message) *message = @"Custom patch execution is not implemented safely yet.";
                    return NO;
                }
                NSString *className = [self _stringParamForKeys:@[@"className", @"class", @"class_name"]];
                NSString *selector = [self _stringParamForKeys:@[@"selector", @"sel", @"method"]];
                Method method = class_getInstanceMethod(NSClassFromString(className), NSSelectorFromString(selector));
                if (method && [patchType.lowercaseString isEqualToString:@"return_yes"]) {
                    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
                    const char *returnType = signature ? signature.methodReturnType : NULL;
                    char normalized = returnType ? returnType[0] : '\0';
                    while (normalized == 'r' || normalized == 'n' || normalized == 'N' || normalized == 'o' ||
                           normalized == 'O' || normalized == 'R' || normalized == 'V') {
                        returnType++;
                        normalized = returnType ? returnType[0] : '\0';
                    }
                    if (normalized == '@' || normalized == ':' || normalized == '*' || normalized == '^' ||
                        normalized == '{' || normalized == '[' || normalized == '(') {
                        if (message) *message = @"return_yes is blocked for object/pointer/aggregate return types. Use a safer hook or custom code path.";
                        return NO;
                    }
                }
            }
            return YES;
        }
        case VCToolCallHookMethod: {
            NSString *reason = nil;
            if (![capabilityManager canUseHookingWithReason:&reason]) {
                if (message) *message = reason;
                return NO;
            }
            return YES;
        }
        case VCToolCallModifyHeader: {
            NSString *action = [[self _stringParamForKeys:@[@"action"]] lowercaseString];
            if (action.length == 0) action = @"modify_header";
            if (![@[@"modify_header", @"modify_body"] containsObject:action]) {
                if (message) *message = @"Network Tool Calls currently support modify_header and modify_body only.";
                return NO;
            }
            return YES;
        }
        case VCToolCallOverlayCanvas: {
            NSString *action = [[self _stringParamForKeys:@[@"action"]] lowercaseString];
            if (action.length == 0) {
                if (message) *message = @"overlay_canvas requires an action.";
                return NO;
            }
            if (![@[@"line", @"box", @"circle", @"text", @"polyline", @"corner_box", @"health_bar", @"offscreen_arrow", @"skeleton", @"clear", @"show", @"hide"] containsObject:action]) {
                if (message) *message = [NSString stringWithFormat:@"Unsupported overlay_canvas action %@", action];
                return NO;
            }
            if ([action isEqualToString:@"line"]) {
                if (![self _paramForKeys:@[@"x1"]] || ![self _paramForKeys:@[@"y1"]] || ![self _paramForKeys:@[@"x2"]] || ![self _paramForKeys:@[@"y2"]]) {
                    if (message) *message = @"overlay_canvas line requires x1, y1, x2, and y2.";
                    return NO;
                }
            } else if ([action isEqualToString:@"box"]) {
                if (![self _paramForKeys:@[@"x"]] || ![self _paramForKeys:@[@"y"]] || ![self _paramForKeys:@[@"width"]] || ![self _paramForKeys:@[@"height"]]) {
                    if (message) *message = @"overlay_canvas box requires x, y, width, and height.";
                    return NO;
                }
            } else if ([action isEqualToString:@"circle"]) {
                if (![self _paramForKeys:@[@"x"]] || ![self _paramForKeys:@[@"y"]] || ![self _paramForKeys:@[@"radius"]]) {
                    if (message) *message = @"overlay_canvas circle requires x, y, and radius.";
                    return NO;
                }
            } else if ([action isEqualToString:@"text"]) {
                if (![self _paramForKeys:@[@"x"]] || ![self _paramForKeys:@[@"y"]] || [self _stringParamForKeys:@[@"text", @"label", @"content"]].length == 0) {
                    if (message) *message = @"overlay_canvas text requires x, y, and text.";
                    return NO;
                }
            } else if ([action isEqualToString:@"polyline"]) {
                if ([self _pointArrayParamForKeys:@[@"points"]].count < 2) {
                    if (message) *message = @"overlay_canvas polyline requires at least two points.";
                    return NO;
                }
            } else if ([action isEqualToString:@"corner_box"]) {
                if (![self _paramForKeys:@[@"x"]] || ![self _paramForKeys:@[@"y"]] || ![self _paramForKeys:@[@"width"]] || ![self _paramForKeys:@[@"height"]]) {
                    if (message) *message = @"overlay_canvas corner_box requires x, y, width, and height.";
                    return NO;
                }
            } else if ([action isEqualToString:@"health_bar"]) {
                if (![self _paramForKeys:@[@"x"]] || ![self _paramForKeys:@[@"y"]] || ![self _paramForKeys:@[@"width"]] || ![self _paramForKeys:@[@"height"]] || ![self _paramForKeys:@[@"value"]] || ![self _paramForKeys:@[@"maxValue", @"max_value"]]) {
                    if (message) *message = @"overlay_canvas health_bar requires x, y, width, height, value, and maxValue.";
                    return NO;
                }
            } else if ([action isEqualToString:@"offscreen_arrow"]) {
                if (![self _paramForKeys:@[@"x"]] || ![self _paramForKeys:@[@"y"]] || ![self _paramForKeys:@[@"angle"]]) {
                    if (message) *message = @"overlay_canvas offscreen_arrow requires x, y, and angle.";
                    return NO;
                }
            } else if ([action isEqualToString:@"skeleton"]) {
                if ([self _pointArrayParamForKeys:@[@"points"]].count < 2 || [self _indexPairsParamForKeys:@[@"bones", @"segments"]].count == 0) {
                    if (message) *message = @"overlay_canvas skeleton requires points and bones.";
                    return NO;
                }
            }
            return YES;
        }
        case VCToolCallOverlayTrack: {
            NSString *action = [[self _stringParamForKeys:@[@"action"]] lowercaseString];
            if (action.length == 0) {
                if (message) *message = @"overlay_track requires an action.";
                return NO;
            }
            if (![@[@"start", @"stop", @"clear", @"status", @"save", @"restore", @"list"] containsObject:action]) {
                if (message) *message = [NSString stringWithFormat:@"Unsupported overlay_track action %@", action];
                return NO;
            }
            if ([action isEqualToString:@"restore"]) {
                if ([self _stringParamForKeys:@[@"trackerID", @"tracker_id", @"id"]].length == 0 &&
                    [self _stringParamForKeys:@[@"trackerPath", @"tracker_path", @"path"]].length == 0) {
                    if (message) *message = @"overlay_track restore requires trackerID or trackerPath.";
                    return NO;
                }
                return YES;
            }
            if (![action isEqualToString:@"start"]) {
                return YES;
            }

            NSString *mode = [[[self _stringParamForKeys:@[@"trackMode", @"track_mode", @"mode", @"type"]] lowercaseString] copy];
            if (mode.length == 0) {
                if (message) *message = @"overlay_track start requires trackMode.";
                return NO;
            }
            BOOL isScreenPoint = [@[@"screen_point", @"point2d", @"screenpoint"] containsObject:mode];
            BOOL isScreenRect = [@[@"screen_rect", @"rect2d", @"screenrect"] containsObject:mode];
            BOOL isProjectPoint = [@[@"point", @"project_point", @"projection_point", @"project"] containsObject:mode];
            BOOL isProjectBounds = [@[@"bounds", @"project_bounds", @"projection_bounds"] containsObject:mode];
            BOOL isUnityTransform = [@[@"unity_transform", @"unity_point", @"transform", @"component", @"gameobject", @"game_object"] containsObject:mode];
            BOOL isUnityRenderer = [@[@"unity_renderer", @"renderer", @"renderer_bounds", @"unity_bounds"] containsObject:mode];
            if (!(isScreenPoint || isScreenRect || isProjectPoint || isProjectBounds || isUnityTransform || isUnityRenderer)) {
                if (message) *message = [NSString stringWithFormat:@"Unsupported overlay_track mode %@", mode];
                return NO;
            }

            if (isScreenPoint) {
                if ([self _addressParamForKeys:@[@"pointAddress", @"point_address", @"address"]] == 0 ||
                    [self _stringParamForKeys:@[@"pointType", @"point_type", @"structType", @"struct_type", @"type"]].length == 0) {
                    if (message) *message = @"overlay_track screen_point requires pointAddress plus pointType.";
                    return NO;
                }
            } else if (isScreenRect) {
                if ([self _addressParamForKeys:@[@"rectAddress", @"rect_address", @"address"]] == 0 ||
                    [self _stringParamForKeys:@[@"rectType", @"rect_type", @"structType", @"struct_type", @"type"]].length == 0) {
                    if (message) *message = @"overlay_track screen_rect requires rectAddress plus rectType.";
                    return NO;
                }
            } else if (isProjectPoint || isProjectBounds) {
                BOOL hasWorldAddress = [self _addressParamForKeys:@[@"worldAddress", @"world_address", @"address"]] != 0 &&
                    [self _stringParamForKeys:@[@"worldType", @"world_type", @"vectorType", @"vector_type"]].length > 0;
                BOOL hasWorldCoords = [self _paramForKeys:@[@"worldX", @"x"]] &&
                    [self _paramForKeys:@[@"worldY", @"y"]] &&
                    [self _paramForKeys:@[@"worldZ", @"z"]];
                if (!hasWorldAddress && !hasWorldCoords) {
                    if (message) *message = @"overlay_track project modes require world coordinates or worldAddress plus worldType.";
                    return NO;
                }

                BOOL hasMatrixAddress = [self _addressParamForKeys:@[@"matrixAddress", @"matrix_address"]] != 0;
                BOOL hasMatrixElements = [[self _paramForKeys:@[@"matrixElements", @"matrix"]] isKindOfClass:[NSArray class]];
                if (!hasMatrixAddress && !hasMatrixElements) {
                    if (message) *message = @"overlay_track project modes require matrixAddress or matrixElements.";
                    return NO;
                }

                if (isProjectBounds) {
                    BOOL hasExtentsAddress = [self _addressParamForKeys:@[@"extentAddress", @"extent_address"]] != 0 &&
                        [self _stringParamForKeys:@[@"extentType", @"extent_type"]].length > 0;
                    BOOL hasExtents = [self _paramForKeys:@[@"extentX", @"ex"]] &&
                        [self _paramForKeys:@[@"extentY", @"ey"]] &&
                        [self _paramForKeys:@[@"extentZ", @"ez"]];
                    if (!hasExtents && !hasExtentsAddress) {
                        if (message) *message = @"overlay_track project_bounds requires extents or extentAddress plus extentType.";
                        return NO;
                    }
                }
            } else if (isUnityTransform) {
                if ([self _addressParamForKeys:@[@"transformAddress", @"transform_address"]] == 0 &&
                    [self _addressParamForKeys:@[@"componentAddress", @"component_address"]] == 0 &&
                    [self _addressParamForKeys:@[@"gameObjectAddress", @"game_object_address"]] == 0 &&
                    [self _addressParamForKeys:@[@"address"]] == 0) {
                    if (message) *message = @"overlay_track unity_transform requires transformAddress, componentAddress, gameObjectAddress, or address.";
                    return NO;
                }
            } else if (isUnityRenderer) {
                if ([self _addressParamForKeys:@[@"rendererAddress", @"renderer_address", @"address"]] == 0) {
                    if (message) *message = @"overlay_track unity_renderer requires rendererAddress or address.";
                    return NO;
                }
            }
            return YES;
        }
        default:
            return YES;
    }
}

- (BOOL)_executeModifyValueWithMessage:(NSString **)message {
    uintptr_t address = [self _addressParamForKeys:@[@"address", @"addr"]];
    NSString *target = [self _stringParamForKeys:@[@"target", @"targetDesc", @"target_desc", @"name"]];
    NSString *modifiedValue = [self _stringParamForKeys:@[@"modifiedValue", @"modified_value", @"value", @"new_value"]];
    NSString *dataType = [self _normalizedValueType:[self _stringParamForKeys:@[@"dataType", @"data_type", @"type"]] allowUnsupported:YES];
    NSString *mode = [[self _stringParamForKeys:@[@"mode", @"writeMode", @"write_mode"]] lowercaseString];
    if (dataType.length == 0) dataType = @"int";
    if (mode.length == 0) mode = @"lock";

    if (modifiedValue.length == 0) {
        if (message) *message = @"Missing modified value";
        return NO;
    }
    if (address == 0) {
        NSString *source = [[self _stringParamForKeys:@[@"source", @"from", @"targetSource", @"target_source"]] lowercaseString];
        NSString *matchValue = [self _stringParamForKeys:@[@"matchValue", @"match_value", @"currentValue", @"current_value", @"originalValue", @"original_value"]];
        BOOL useActiveScan = [source rangeOfString:@"scan"].location != NSNotFound ||
            [self _boolParamForKeys:@[@"useActiveScanResults", @"use_active_scan_results", @"allScanCandidates"]];
        if (useActiveScan || matchValue.length > 0) {
            return [self _executeModifyActiveScanResultsWithValue:modifiedValue
                                                        matchValue:matchValue
                                                         valueType:dataType
                                                              mode:mode
                                                           message:message];
        }
        if (message) *message = @"Missing address for modify_value";
        return NO;
    }

    if ([mode isEqualToString:@"write_once"] || [mode isEqualToString:@"writeonce"] || [mode isEqualToString:@"write"]) {
        BOOL wrote = [[VCHookManager shared] writeValue:modifiedValue toAddress:address dataType:dataType];
        if (!wrote) {
            if (message) *message = [NSString stringWithFormat:@"Direct write failed for 0x%llx", (unsigned long long)address];
            return NO;
        }
        if (message) *message = [NSString stringWithFormat:@"Wrote %@ %@ to 0x%llx", dataType, modifiedValue, (unsigned long long)address];
        return YES;
    }

    VCValueItem *item = [[VCValueItem alloc] init];
    item.targetDesc = target ?: [NSString stringWithFormat:@"0x%llx", (unsigned long long)address];
    item.address = address;
    item.dataType = dataType;
    item.originalValue = [self _stringParamForKeys:@[@"originalValue", @"original_value"]];
    item.modifiedValue = modifiedValue;
    item.remark = _toolCall.remark ?: [self _stringParamForKeys:@[@"remark"]];
    item.source = VCItemSourceAI;
    item.sourceToolID = _toolCall.toolID;
    item.locked = YES;

    if (![[VCHookManager shared] startLocking:item]) {
        if (message) *message = [NSString stringWithFormat:@"Value lock failed for 0x%llx", (unsigned long long)item.address];
        return NO;
    }
    [[VCPatchManager shared] addValue:item];

    if (message) *message = [NSString stringWithFormat:@"Locked %@ at 0x%llx", item.dataType, (unsigned long long)item.address];
    return YES;
}

- (BOOL)_executeModifyActiveScanResultsWithValue:(NSString *)modifiedValue
                                      matchValue:(NSString *)matchValue
                                       valueType:(NSString *)fallbackType
                                            mode:(NSString *)mode
                                         message:(NSString **)message {
    if (![[VCMemoryScanEngine shared] hasActiveSession]) {
        if (message) *message = @"No active memory scan session for modify_value";
        return NO;
    }
    if (modifiedValue.length == 0) {
        if (message) *message = @"Missing modified value";
        return NO;
    }
    if (matchValue.length == 0) {
        if (message) *message = @"Missing matchValue for active scan modify_value";
        return NO;
    }

    NSUInteger maxWrites = 50;
    id maxWritesValue = [self _paramForKeys:@[@"maxWrites", @"max_writes", @"limit"]];
    if ([maxWritesValue respondsToSelector:@selector(unsignedIntegerValue)]) {
        maxWrites = MAX(1, MIN([maxWritesValue unsignedIntegerValue], 200));
    }

    NSString *errorMessage = nil;
    NSDictionary *results = [[VCMemoryScanEngine shared] resultsWithOffset:0
                                                                     limit:maxWrites
                                                             refreshValues:YES
                                                              errorMessage:&errorMessage];
    NSArray *candidates = [results[@"candidates"] isKindOfClass:[NSArray class]] ? results[@"candidates"] : @[];
    if (candidates.count == 0) {
        if (message) *message = errorMessage.length > 0 ? errorMessage : @"No active memory scan candidates";
        return NO;
    }

    NSUInteger attempted = 0;
    NSUInteger wroteCount = 0;
    NSMutableArray<NSString *> *failedAddresses = [NSMutableArray new];
    for (NSDictionary *candidate in candidates) {
        if (![candidate isKindOfClass:[NSDictionary class]]) continue;
        NSString *currentValue = [candidate[@"currentValue"] isKindOfClass:[NSString class]] ? candidate[@"currentValue"] : @"";
        NSString *storedValue = [candidate[@"storedValue"] isKindOfClass:[NSString class]] ? candidate[@"storedValue"] : @"";
        NSString *observedValue = currentValue.length > 0 ? currentValue : storedValue;
        if (![observedValue isEqualToString:matchValue]) continue;

        uintptr_t candidateAddress = 0;
        NSString *addressString = [candidate[@"address"] isKindOfClass:[NSString class]] ? candidate[@"address"] : @"";
        if (addressString.length > 0) {
            candidateAddress = (uintptr_t)strtoull(addressString.UTF8String, NULL, 0);
        }
        if (candidateAddress == 0) continue;

        NSString *candidateType = [candidate[@"dataType"] isKindOfClass:[NSString class]] ? candidate[@"dataType"] : fallbackType;
        candidateType = [self _normalizedValueType:candidateType allowUnsupported:YES];
        if ([candidateType isEqualToString:@"int32"]) candidateType = @"int";
        else if ([candidateType isEqualToString:@"uint32"]) candidateType = @"uint";
        else if ([candidateType isEqualToString:@"int64"]) candidateType = @"longlong";
        else if ([candidateType isEqualToString:@"uint64"]) candidateType = @"ulonglong";
        if (candidateType.length == 0) candidateType = fallbackType.length > 0 ? fallbackType : @"int";

        attempted += 1;
        BOOL wrote = [[VCHookManager shared] writeValue:modifiedValue toAddress:candidateAddress dataType:candidateType];
        if (wrote) {
            wroteCount += 1;
        } else {
            [failedAddresses addObject:[NSString stringWithFormat:@"0x%llx", (unsigned long long)candidateAddress]];
        }
    }

    if (attempted == 0) {
        if (message) *message = [NSString stringWithFormat:@"No active scan candidates currently match %@", matchValue];
        return NO;
    }

    if ([mode isEqualToString:@"lock"]) {
        // Batch scan writes are one-shot; stable locking still uses address-specific modify_value calls.
    }

    if (message) {
        NSString *failedText = failedAddresses.count > 0
            ? [NSString stringWithFormat:@"; failed %@", [failedAddresses componentsJoinedByString:@", "]]
            : @"";
        *message = [NSString stringWithFormat:@"Wrote %@ to %lu/%lu active scan candidates%@",
                    modifiedValue,
                    (unsigned long)wroteCount,
                    (unsigned long)attempted,
                    failedText];
    }
    return wroteCount > 0;
}

- (BOOL)_executeWriteMemoryBytesWithMessage:(NSString **)message {
    uintptr_t address = [self _addressParamForKeys:@[@"address", @"addr"]];
    NSString *hexData = [self _stringParamForKeys:@[@"hexData", @"hex_data", @"bytes", @"data"]];
    NSData *data = VCToolCallHexDataFromString(hexData);

    if (address == 0) {
        if (message) *message = @"Missing address for write_memory_bytes";
        return NO;
    }
    if (!data || data.length == 0) {
        if (message) *message = @"Missing or invalid hexData for write_memory_bytes";
        return NO;
    }

    [[VCMemEngine shared] initialize];
    BOOL wrote = [[VCMemEngine shared] writeMemory:(uint64_t)address data:data];
    if (!wrote) {
        if (message) *message = [NSString stringWithFormat:@"Raw byte write failed for 0x%llx", (unsigned long long)address];
        return NO;
    }

    if (message) *message = [NSString stringWithFormat:@"Wrote %lu raw bytes to 0x%llx",
                             (unsigned long)data.length,
                             (unsigned long long)address];
    return YES;
}

- (BOOL)_executePatchMethodWithMessage:(NSString **)message {
    NSString *className = [self _stringParamForKeys:@[@"className", @"class", @"class_name"]];
    NSString *selector = [self _stringParamForKeys:@[@"selector", @"sel", @"method"]];
    NSString *patchType = [self _stringParamForKeys:@[@"patchType", @"patch_type", @"type"]];
    if (patchType.length == 0) patchType = @"nop";

    if (className.length == 0 || selector.length == 0) {
        if (message) *message = @"Missing class or selector for patch_method";
        return NO;
    }

    VCPatchItem *item = [[VCPatchItem alloc] init];
    item.className = className;
    item.selector = selector;
    item.patchType = patchType;
    item.customCode = [self _stringParamForKeys:@[@"customCode", @"custom_code", @"code"]];
    item.remark = _toolCall.remark ?: [self _stringParamForKeys:@[@"remark"]];
    item.source = VCItemSourceAI;
    item.sourceToolID = _toolCall.toolID;
    item.enabled = YES;

    BOOL applied = [[VCHookManager shared] applyPatch:item];
    if (!applied) {
        if (message) *message = [NSString stringWithFormat:@"Patch failed for -[%@ %@]", className, selector];
        return NO;
    }

    [[VCPatchManager shared] addPatch:item];
    if (message) *message = [NSString stringWithFormat:@"Patched -[%@ %@] with %@", className, selector, patchType];
    return YES;
}

- (BOOL)_executeOverlayTrackWithMessage:(NSString **)message {
    NSString *action = [[self _stringParamForKeys:@[@"action"]] lowercaseString];
    NSDictionary *payload = nil;
    if ([action isEqualToString:@"start"]) {
        payload = [[VCOverlayTrackingManager shared] startTrackerWithConfiguration:self.toolCall.params ?: @{}];
    } else if ([action isEqualToString:@"stop"]) {
        payload = [[VCOverlayTrackingManager shared] stopTrackerWithItemIdentifier:[self _stringParamForKeys:@[@"itemID", @"item", @"item_id", @"id"]]
                                                                  canvasIdentifier:[self _stringParamForKeys:@[@"canvasID", @"canvas", @"canvas_id"]]];
    } else if ([action isEqualToString:@"clear"]) {
        payload = [[VCOverlayTrackingManager shared] clearTrackersForCanvasIdentifier:[self _stringParamForKeys:@[@"canvasID", @"canvas", @"canvas_id"]]];
    } else if ([action isEqualToString:@"status"]) {
        payload = [[VCOverlayTrackingManager shared] statusForItemIdentifier:[self _stringParamForKeys:@[@"itemID", @"item", @"item_id", @"id"]]
                                                             canvasIdentifier:[self _stringParamForKeys:@[@"canvasID", @"canvas", @"canvas_id"]]];
    } else if ([action isEqualToString:@"save"]) {
        payload = [[VCOverlayTrackingManager shared] saveTrackerWithItemIdentifier:[self _stringParamForKeys:@[@"itemID", @"item", @"item_id", @"id"]]
                                                                  canvasIdentifier:[self _stringParamForKeys:@[@"canvasID", @"canvas", @"canvas_id"]]
                                                                             title:[self _stringParamForKeys:@[@"title"]]
                                                                          subtitle:[self _stringParamForKeys:@[@"subtitle"]]];
    } else if ([action isEqualToString:@"restore"]) {
        payload = [[VCOverlayTrackingManager shared] restoreTrackerFromPath:[self _stringParamForKeys:@[@"trackerPath", @"tracker_path", @"path"]]
                                                                  trackerID:[self _stringParamForKeys:@[@"trackerID", @"tracker_id", @"id"]]];
    } else if ([action isEqualToString:@"list"]) {
        NSUInteger limit = 20;
        id limitValue = [self _paramForKeys:@[@"limit"]];
        if ([limitValue respondsToSelector:@selector(integerValue)]) {
            limit = (NSUInteger)MAX(1, MIN([limitValue integerValue], 100));
        }
        payload = @{
            @"success": @YES,
            @"summary": @"Loaded saved overlay tracker presets.",
            @"trackers": [[VCOverlayTrackingManager shared] savedTrackerSummariesWithLimit:limit] ?: @[]
        };
    } else {
        if (message) *message = @"Unsupported overlay_track action.";
        return NO;
    }

    BOOL success = [payload[@"success"] boolValue];
    NSString *summary = [payload[@"summary"] isKindOfClass:[NSString class]] ? payload[@"summary"] : @"overlay_track updated.";
    if (message) *message = summary;
    return success;
}

- (BOOL)_executeHookMethodWithMessage:(NSString **)message {
    NSString *className = [self _stringParamForKeys:@[@"className", @"class", @"class_name"]];
    NSString *selector = [self _stringParamForKeys:@[@"selector", @"sel", @"method"]];
    NSString *hookType = [self _stringParamForKeys:@[@"hookType", @"hook_type", @"type"]];
    if (hookType.length == 0) hookType = @"log";

    if (className.length == 0 || selector.length == 0) {
        if (message) *message = @"Missing class or selector for hook_method";
        return NO;
    }

    VCHookItem *item = [[VCHookItem alloc] init];
    item.className = className;
    item.selector = selector;
    item.hookType = hookType;
    item.isClassMethod = [self _boolParamForKeys:@[@"isClassMethod", @"is_class_method", @"classMethod"]];
    item.remark = _toolCall.remark ?: [self _stringParamForKeys:@[@"remark"]];
    item.source = VCItemSourceAI;
    item.sourceToolID = _toolCall.toolID;
    item.enabled = YES;

    BOOL installed = [[VCHookManager shared] installHook:item];
    if (!installed) {
        if (message) *message = [NSString stringWithFormat:@"Hook failed for %c[%@ %@]", item.isClassMethod ? '+' : '-', className, selector];
        return NO;
    }

    [[VCPatchManager shared] addHook:item];
    if (message) *message = [NSString stringWithFormat:@"Hooked %c[%@ %@] with %@", item.isClassMethod ? '+' : '-', className, selector, hookType];
    return YES;
}

- (BOOL)_executeNetworkRuleWithMessage:(NSString **)message {
    NSString *urlPattern = [self _stringParamForKeys:@[@"urlPattern", @"url_pattern", @"pattern", @"url"]];
    NSString *action = [self _stringParamForKeys:@[@"action"]];
    if (action.length == 0) action = @"modify_header";

    NSDictionary *mods = [self _dictionaryParamForKeys:@[@"modifications", @"mods"]];
    NSMutableDictionary *mutableMods = mods ? [mods mutableCopy] : [NSMutableDictionary new];
    NSDictionary *headers = [self _dictionaryParamForKeys:@[@"headers", @"request_headers"]];
    if (headers.count) {
        mutableMods[@"headers"] = headers;
    } else {
        NSString *headerKey = [self _stringParamForKeys:@[@"header", @"header_name", @"key"]];
        NSString *headerValue = [self _stringParamForKeys:@[@"headerValue", @"header_value", @"value"]];
        if (headerKey.length && headerValue.length) {
            mutableMods[@"headers"] = @{ headerKey: headerValue };
        }
    }
    NSString *body = [self _stringParamForKeys:@[@"body", @"body_text"]];
    if (body.length) mutableMods[@"body"] = body;

    if (urlPattern.length == 0) {
        if (message) *message = @"Missing URL pattern for network rule";
        return NO;
    }
    if ([action isEqualToString:@"modify_header"] && ![mutableMods[@"headers"] isKindOfClass:[NSDictionary class]]) {
        if (message) *message = @"Missing header modifications";
        return NO;
    }

    VCNetRule *item = [[VCNetRule alloc] init];
    item.urlPattern = urlPattern;
    item.action = action;
    item.modifications = [mutableMods copy];
    item.remark = _toolCall.remark ?: [self _stringParamForKeys:@[@"remark"]];
    item.source = VCItemSourceAI;
    item.sourceToolID = _toolCall.toolID;
    item.enabled = YES;

    [[VCPatchManager shared] addRule:item];
    if (message) *message = [NSString stringWithFormat:@"Added network rule for %@", urlPattern];
    return YES;
}

- (BOOL)_executeModifyViewWithMessage:(NSString **)message {
    VCUIInspector *inspector = [VCUIInspector shared];
    uintptr_t address = [self _addressParamForKeys:@[@"address", @"viewAddress", @"view_address"]];
    UIView *targetView = address ? [inspector viewForAddress:address] : inspector.currentSelectedView;
    if (!targetView) {
        if (message) *message = @"No target view selected for modify_view";
        return NO;
    }

    NSString *property = [self _stringParamForKeys:@[@"property", @"key", @"attribute", @"attr"]];
    if (property.length == 0) {
        if (message) *message = @"Missing property for modify_view";
        return NO;
    }

    id rawValue = [self _paramForKeys:@[@"value", @"newValue", @"new_value"]];
    if (!rawValue) {
        if (message) *message = @"Missing value for modify_view";
        return NO;
    }

    id convertedValue = [self _convertedViewValue:rawValue forProperty:property];
    if (!convertedValue) {
        if (message) *message = [NSString stringWithFormat:@"Unsupported value for property %@", property];
        return NO;
    }

    [inspector rememberSelectedView:targetView];
    [inspector modifyView:targetView property:property value:convertedValue];
    [inspector highlightView:targetView];

    if (message) {
        *message = [NSString stringWithFormat:@"Updated %@ on <%@: %p>",
                    property, NSStringFromClass([targetView class]), targetView];
    }
    return YES;
}

- (BOOL)_executeInsertSubviewWithMessage:(NSString **)message {
    VCUIInspector *inspector = [VCUIInspector shared];
    uintptr_t address = [self _addressParamForKeys:@[@"address", @"parentAddress", @"parent_address", @"viewAddress", @"view_address"]];
    UIView *parentView = address ? [inspector viewForAddress:address] : inspector.currentSelectedView;
    if (!parentView) {
        UIWindow *keyWindow = nil;
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (window.isKeyWindow && !window.hidden && window.alpha > 0.01) {
                keyWindow = window;
                break;
            }
        }
        if (!keyWindow) {
            for (UIWindow *window in UIApplication.sharedApplication.windows) {
                if (!window.hidden && window.alpha > 0.01) {
                    keyWindow = window;
                    break;
                }
            }
        }
        parentView = keyWindow;
    }
    if (!parentView) {
        if (message) *message = @"No parent view selected for insert_subview";
        return NO;
    }

    NSString *className = [self _stringParamForKeys:@[@"className", @"class", @"viewClass", @"type"]];
    if (className.length == 0) className = @"UILabel";

    id frameValue = [self _paramForKeys:@[@"frame", @"rect"]];
    NSDictionary *frameDict = [self _dictionaryParamForKeys:@[@"frame", @"rect"]];
    if (!frameValue && !frameDict) {
        CGFloat width = MAX(80.0, CGRectGetWidth(parentView.bounds) - 16.0);
        frameValue = @{
            @"x": @8,
            @"y": @(MAX(8.0, CGRectGetHeight(parentView.bounds) - 30.0)),
            @"width": @(width),
            @"height": @24
        };
    }

    NSMutableDictionary *spec = [NSMutableDictionary dictionary];
    spec[@"className"] = className;
    if (frameDict) spec[@"frame"] = frameDict;
    else if (frameValue) spec[@"frame"] = frameValue;

    NSArray<NSString *> *copyStringKeys = @[@"text", @"title", @"backgroundColor", @"background", @"textColor", @"placeholder", @"accessibilityIdentifier"];
    for (NSString *key in copyStringKeys) {
        NSString *value = [self _stringParamForKeys:@[key]];
        if (value.length > 0) spec[key] = value;
    }
    id alpha = [self _paramForKeys:@[@"alpha"]];
    if (alpha) spec[@"alpha"] = alpha;
    id hidden = [self _paramForKeys:@[@"hidden"]];
    if (hidden) spec[@"hidden"] = @([self _boolFromValue:hidden]);
    id userInteraction = [self _paramForKeys:@[@"userInteractionEnabled", @"user_interaction_enabled"]];
    if (userInteraction) spec[@"userInteractionEnabled"] = @([self _boolFromValue:userInteraction]);
    id clips = [self _paramForKeys:@[@"clipsToBounds", @"clips"]];
    if (clips) spec[@"clipsToBounds"] = @([self _boolFromValue:clips]);
    id tag = [self _paramForKeys:@[@"tag"]];
    if (tag) spec[@"tag"] = @((NSInteger)[self _doubleFromValue:tag]);
    id fontSize = [self _paramForKeys:@[@"fontSize", @"font_size"]];
    if (fontSize) spec[@"fontSize"] = @([self _doubleFromValue:fontSize]);

    UIView *created = [inspector insertSubviewIntoView:parentView spec:spec];
    if (!created) {
        if (message) *message = @"Failed to insert native subview";
        return NO;
    }

    NSMutableDictionary *updatedParams = [self.toolCall.params mutableCopy] ?: [NSMutableDictionary new];
    updatedParams[@"insertedAddress"] = [NSString stringWithFormat:@"0x%llx", (unsigned long long)(uintptr_t)(__bridge void *)created];
    updatedParams[@"insertedClass"] = NSStringFromClass([created class]) ?: className;
    self.toolCall.params = [updatedParams copy];

    if (message) {
        *message = [NSString stringWithFormat:@"Inserted %@ into <%@: %p>",
                    NSStringFromClass([created class]) ?: className,
                    NSStringFromClass([parentView class]),
                    parentView];
    }
    return YES;
}

- (BOOL)_executeInvokeSelectorWithMessage:(NSString **)message {
    VCUIInspector *inspector = [VCUIInspector shared];
    uintptr_t address = [self _addressParamForKeys:@[@"address", @"targetAddress", @"target_address", @"viewAddress", @"view_address"]];
    id target = address ? [inspector viewForAddress:address] : inspector.currentSelectedView;
    if (!target) {
        if (message) *message = @"No target selected for invoke_selector";
        return NO;
    }

    NSString *selectorName = [self _stringParamForKeys:@[@"selector", @"method", @"selectorName", @"selector_name"]];
    if (selectorName.length == 0) {
        if (message) *message = @"Missing selector for invoke_selector";
        return NO;
    }

    id argument = [self _paramForKeys:@[@"argument", @"arg", @"value", @"param"]];
    NSString *result = nil;
    BOOL invoked = [inspector invokeSelector:selectorName onTarget:target argument:argument result:&result];
    if (message) *message = result ?: (invoked ? @"Invoked selector" : @"Failed to invoke selector");
    return invoked;
}

- (BOOL)_executeOverlayCanvasWithMessage:(NSString **)message {
    NSString *action = [[self _stringParamForKeys:@[@"action"]] lowercaseString];
    if (action.length == 0) action = @"text";

    NSString *canvasID = [self _stringParamForKeys:@[@"canvasID", @"canvas", @"canvas_id"]];
    if (canvasID.length == 0) canvasID = @"unity";
    NSString *itemID = [self _stringParamForKeys:@[@"itemID", @"item", @"item_id"]];

    VCOverlayCanvasManager *manager = [VCOverlayCanvasManager shared];

    if ([action isEqualToString:@"clear"]) {
        [manager clearCanvasWithIdentifier:canvasID itemIdentifier:itemID];
        if (itemID.length > 0) [manager clearCanvasWithIdentifier:canvasID itemIdentifierPrefix:itemID];
        if (message) *message = itemID.length > 0
            ? [NSString stringWithFormat:@"Cleared overlay canvas %@ item %@", canvasID, itemID]
            : [NSString stringWithFormat:@"Cleared overlay canvas %@", canvasID];
        return YES;
    }
    if ([action isEqualToString:@"show"]) {
        [manager setCanvasHidden:NO identifier:canvasID];
        if (message) *message = [NSString stringWithFormat:@"Showed overlay canvas %@", canvasID];
        return YES;
    }
    if ([action isEqualToString:@"hide"]) {
        [manager setCanvasHidden:YES identifier:canvasID];
        if (message) *message = [NSString stringWithFormat:@"Hid overlay canvas %@", canvasID];
        return YES;
    }

    if (itemID.length == 0) itemID = self.toolCall.toolID ?: [[NSUUID UUID] UUIDString];

    UIColor *color = VCToolCallColorFromString([self _stringParamForKeys:@[@"color", @"strokeColor", @"stroke_color"]], kVCAccent);
    UIColor *fillColor = VCToolCallColorFromString([self _stringParamForKeys:@[@"fillColor", @"fill_color"]], nil);
    UIColor *backgroundColor = VCToolCallColorFromString([self _stringParamForKeys:@[@"backgroundColor", @"background_color"]], [kVCBgSurface colorWithAlphaComponent:0.84]);
    CGFloat rawLineWidth = [self _doubleFromValue:[self _paramForKeys:@[@"lineWidth", @"line_width"]]];
    CGFloat rawFontSize = [self _doubleFromValue:[self _paramForKeys:@[@"fontSize", @"font_size"]]];
    CGFloat rawCornerRadius = [self _doubleFromValue:[self _paramForKeys:@[@"cornerRadius", @"corner_radius"]]];
    CGFloat lineWidth = MAX(rawLineWidth, 0.0);
    CGFloat fontSize = MAX(rawFontSize, 0.0);
    CGFloat cornerRadius = MAX(rawCornerRadius, 0.0);
    NSArray<NSValue *> *points = [self _pointArrayParamForKeys:@[@"points"]];

    if ([action isEqualToString:@"line"]) {
        CGPoint start = CGPointMake([self _doubleFromValue:[self _paramForKeys:@[@"x1"]]],
                                    [self _doubleFromValue:[self _paramForKeys:@[@"y1"]]]);
        CGPoint end = CGPointMake([self _doubleFromValue:[self _paramForKeys:@[@"x2"]]],
                                  [self _doubleFromValue:[self _paramForKeys:@[@"y2"]]]);
        BOOL success = [manager drawLineFrom:start
                                          to:end
                                       color:color
                                   lineWidth:(lineWidth > 0.0 ? lineWidth : 2.0)
                            canvasIdentifier:canvasID
                              itemIdentifier:itemID];
        if (message) *message = success
            ? [NSString stringWithFormat:@"Drew line on overlay canvas %@ (%@)", canvasID, itemID]
            : @"Failed to draw line on overlay canvas";
        return success;
    }

    if ([action isEqualToString:@"box"]) {
        CGRect rect = CGRectMake([self _doubleFromValue:[self _paramForKeys:@[@"x"]]],
                                 [self _doubleFromValue:[self _paramForKeys:@[@"y"]]],
                                 [self _doubleFromValue:[self _paramForKeys:@[@"width"]]],
                                 [self _doubleFromValue:[self _paramForKeys:@[@"height"]]]);
        BOOL success = [manager drawBox:rect
                            strokeColor:color
                              lineWidth:(lineWidth > 0.0 ? lineWidth : 2.0)
                              fillColor:fillColor
                        canvasIdentifier:canvasID
                          itemIdentifier:itemID
                           cornerRadius:(cornerRadius > 0.0 ? cornerRadius : 8.0)];
        if (message) *message = success
            ? [NSString stringWithFormat:@"Drew box on overlay canvas %@ (%@)", canvasID, itemID]
            : @"Failed to draw box on overlay canvas";
        return success;
    }

    if ([action isEqualToString:@"circle"]) {
        CGPoint center = CGPointMake([self _doubleFromValue:[self _paramForKeys:@[@"x"]]],
                                     [self _doubleFromValue:[self _paramForKeys:@[@"y"]]]);
        CGFloat radius = [self _doubleFromValue:[self _paramForKeys:@[@"radius"]]];
        BOOL success = [manager drawCircleAtPoint:center
                                           radius:radius
                                      strokeColor:color
                                        lineWidth:(lineWidth > 0.0 ? lineWidth : 2.0)
                                        fillColor:fillColor
                                 canvasIdentifier:canvasID
                                   itemIdentifier:itemID];
        if (message) *message = success
            ? [NSString stringWithFormat:@"Drew circle on overlay canvas %@ (%@)", canvasID, itemID]
            : @"Failed to draw circle on overlay canvas";
        return success;
    }

    if ([action isEqualToString:@"polyline"]) {
        BOOL closed = [self _boolParamForKeys:@[@"closed"]];
        BOOL success = [manager drawPolylineWithPoints:points
                                           strokeColor:color
                                             lineWidth:(lineWidth > 0.0 ? lineWidth : 2.0)
                                             fillColor:fillColor
                                                closed:closed
                                      canvasIdentifier:canvasID
                                        itemIdentifier:itemID];
        if (message) *message = success
            ? [NSString stringWithFormat:@"Drew polyline on overlay canvas %@ (%@)", canvasID, itemID]
            : @"Failed to draw polyline on overlay canvas";
        return success;
    }

    if ([action isEqualToString:@"corner_box"]) {
        CGFloat x = [self _doubleFromValue:[self _paramForKeys:@[@"x"]]];
        CGFloat y = [self _doubleFromValue:[self _paramForKeys:@[@"y"]]];
        CGFloat width = [self _doubleFromValue:[self _paramForKeys:@[@"width"]]];
        CGFloat height = [self _doubleFromValue:[self _paramForKeys:@[@"height"]]];
        CGFloat segment = MIN(width, height) * 0.24;
        segment = MAX(segment, 8.0);
        [manager clearCanvasWithIdentifier:canvasID itemIdentifierPrefix:itemID];
        NSArray<NSArray<NSValue *> *> *segments = @[
            @[[NSValue valueWithCGPoint:CGPointMake(x, y + segment)], [NSValue valueWithCGPoint:CGPointMake(x, y)], [NSValue valueWithCGPoint:CGPointMake(x + segment, y)]],
            @[[NSValue valueWithCGPoint:CGPointMake(x + width - segment, y)], [NSValue valueWithCGPoint:CGPointMake(x + width, y)], [NSValue valueWithCGPoint:CGPointMake(x + width, y + segment)]],
            @[[NSValue valueWithCGPoint:CGPointMake(x, y + height - segment)], [NSValue valueWithCGPoint:CGPointMake(x, y + height)], [NSValue valueWithCGPoint:CGPointMake(x + segment, y + height)]],
            @[[NSValue valueWithCGPoint:CGPointMake(x + width - segment, y + height)], [NSValue valueWithCGPoint:CGPointMake(x + width, y + height)], [NSValue valueWithCGPoint:CGPointMake(x + width, y + height - segment)]]
        ];
        BOOL success = YES;
        NSUInteger idx = 0;
        for (NSArray<NSValue *> *segmentPoints in segments) {
            NSString *segmentID = [NSString stringWithFormat:@"%@.corner%lu", itemID, (unsigned long)idx++];
            success = [manager drawPolylineWithPoints:segmentPoints
                                          strokeColor:color
                                            lineWidth:(lineWidth > 0.0 ? lineWidth : 2.0)
                                            fillColor:nil
                                               closed:NO
                                     canvasIdentifier:canvasID
                                       itemIdentifier:segmentID] && success;
        }
        if (message) *message = success
            ? [NSString stringWithFormat:@"Drew corner box on overlay canvas %@ (%@)", canvasID, itemID]
            : @"Failed to draw corner box on overlay canvas";
        return success;
    }

    if ([action isEqualToString:@"health_bar"]) {
        CGFloat x = [self _doubleFromValue:[self _paramForKeys:@[@"x"]]];
        CGFloat y = [self _doubleFromValue:[self _paramForKeys:@[@"y"]]];
        CGFloat width = [self _doubleFromValue:[self _paramForKeys:@[@"width"]]];
        CGFloat height = [self _doubleFromValue:[self _paramForKeys:@[@"height"]]];
        double value = [self _doubleFromValue:[self _paramForKeys:@[@"value"]]];
        double maxValue = [self _doubleFromValue:[self _paramForKeys:@[@"maxValue", @"max_value"]]];
        double ratio = maxValue > 0.0 ? MIN(MAX(value / maxValue, 0.0), 1.0) : 0.0;
        [manager clearCanvasWithIdentifier:canvasID itemIdentifierPrefix:itemID];
        BOOL success = [manager drawBox:CGRectMake(x, y, width, height)
                            strokeColor:color
                              lineWidth:(lineWidth > 0.0 ? lineWidth : 1.5)
                              fillColor:[UIColor clearColor]
                        canvasIdentifier:canvasID
                          itemIdentifier:[NSString stringWithFormat:@"%@.health.border", itemID]
                           cornerRadius:(cornerRadius > 0.0 ? cornerRadius : 5.0)];
        UIColor *resolvedFill = fillColor ?: kVCGreen;
        success = [manager drawBox:CGRectMake(x + 1.0, y + 1.0, MAX((width - 2.0) * ratio, 0.0), MAX(height - 2.0, 1.0))
                        strokeColor:[UIColor clearColor]
                          lineWidth:0.0
                          fillColor:resolvedFill
                    canvasIdentifier:canvasID
                      itemIdentifier:[NSString stringWithFormat:@"%@.health.fill", itemID]
                       cornerRadius:MAX((cornerRadius > 0.0 ? cornerRadius : 5.0) - 1.0, 0.0)] && success;
        if ([self _boolParamForKeys:@[@"showLabel"]] || [self _stringParamForKeys:@[@"text", @"label"]].length > 0) {
            NSString *barText = [self _stringParamForKeys:@[@"text", @"label"]];
            if (barText.length == 0) {
                barText = [NSString stringWithFormat:@"%.0f / %.0f", value, maxValue];
            }
            success = [manager drawText:barText
                                 atPoint:CGPointMake(x + width + 6.0, y - 2.0)
                                   color:color
                                fontSize:(fontSize > 0.0 ? fontSize : 12.0)
                         backgroundColor:backgroundColor
                        canvasIdentifier:canvasID
                          itemIdentifier:[NSString stringWithFormat:@"%@.health.label", itemID]] && success;
        }
        if (message) *message = success
            ? [NSString stringWithFormat:@"Drew health bar on overlay canvas %@ (%@)", canvasID, itemID]
            : @"Failed to draw health bar on overlay canvas";
        return success;
    }

    if ([action isEqualToString:@"offscreen_arrow"]) {
        CGFloat x = [self _doubleFromValue:[self _paramForKeys:@[@"x"]]];
        CGFloat y = [self _doubleFromValue:[self _paramForKeys:@[@"y"]]];
        CGFloat requestedSize = [self _doubleFromValue:[self _paramForKeys:@[@"size", @"radius"]]];
        CGFloat size = MAX(requestedSize, 12.0);
        CGFloat angleDegrees = [self _doubleFromValue:[self _paramForKeys:@[@"angle"]]];
        CGFloat angle = (CGFloat)(angleDegrees * M_PI / 180.0);
        CGPoint tip = CGPointMake(x + cos(angle) * size, y + sin(angle) * size);
        CGPoint left = CGPointMake(x + cos(angle + (CGFloat)(M_PI * 0.72)) * size * 0.72,
                                   y + sin(angle + (CGFloat)(M_PI * 0.72)) * size * 0.72);
        CGPoint right = CGPointMake(x + cos(angle - (CGFloat)(M_PI * 0.72)) * size * 0.72,
                                    y + sin(angle - (CGFloat)(M_PI * 0.72)) * size * 0.72);
        BOOL success = [manager drawPolylineWithPoints:@[
            [NSValue valueWithCGPoint:tip],
            [NSValue valueWithCGPoint:left],
            [NSValue valueWithCGPoint:right]
        ]
                                           strokeColor:color
                                             lineWidth:(lineWidth > 0.0 ? lineWidth : 2.0)
                                             fillColor:(fillColor ?: [color colorWithAlphaComponent:0.28])
                                                closed:YES
                                      canvasIdentifier:canvasID
                                        itemIdentifier:itemID];
        if (message) *message = success
            ? [NSString stringWithFormat:@"Drew offscreen arrow on overlay canvas %@ (%@)", canvasID, itemID]
            : @"Failed to draw offscreen arrow on overlay canvas";
        return success;
    }

    if ([action isEqualToString:@"skeleton"]) {
        NSArray<NSArray<NSNumber *> *> *bones = [self _indexPairsParamForKeys:@[@"bones", @"segments"]];
        BOOL success = YES;
        [manager clearCanvasWithIdentifier:canvasID itemIdentifierPrefix:itemID];
        NSUInteger idx = 0;
        for (NSArray<NSNumber *> *pair in bones) {
            NSInteger firstIndex = pair.firstObject.integerValue;
            NSInteger secondIndex = pair.lastObject.integerValue;
            if (firstIndex < 0 || secondIndex < 0 || firstIndex >= (NSInteger)points.count || secondIndex >= (NSInteger)points.count) continue;
            NSString *segmentID = [NSString stringWithFormat:@"%@.bone%lu", itemID, (unsigned long)idx++];
            success = [manager drawLineFrom:points[firstIndex].CGPointValue
                                         to:points[secondIndex].CGPointValue
                                      color:color
                                  lineWidth:(lineWidth > 0.0 ? lineWidth : 2.0)
                           canvasIdentifier:canvasID
                             itemIdentifier:segmentID] && success;
        }
        if ([self _boolParamForKeys:@[@"showLabel"]]) {
            idx = 0;
            for (NSValue *pointValue in points) {
                CGPoint point = pointValue.CGPointValue;
                NSString *jointID = [NSString stringWithFormat:@"%@.joint%lu", itemID, (unsigned long)idx++];
                success = [manager drawCircleAtPoint:point
                                              radius:3.5
                                         strokeColor:color
                                           lineWidth:1.0
                                           fillColor:(fillColor ?: [color colorWithAlphaComponent:0.28])
                                    canvasIdentifier:canvasID
                                      itemIdentifier:jointID] && success;
            }
        }
        if (message) *message = success
            ? [NSString stringWithFormat:@"Drew skeleton on overlay canvas %@ (%@)", canvasID, itemID]
            : @"Failed to draw skeleton on overlay canvas";
        return success;
    }

    NSString *text = [self _stringParamForKeys:@[@"text", @"label", @"content"]];
    CGPoint point = CGPointMake([self _doubleFromValue:[self _paramForKeys:@[@"x"]]],
                                [self _doubleFromValue:[self _paramForKeys:@[@"y"]]]);
    BOOL success = [manager drawText:text
                             atPoint:point
                               color:color
                            fontSize:(fontSize > 0.0 ? fontSize : 13.0)
                     backgroundColor:backgroundColor
                    canvasIdentifier:canvasID
                      itemIdentifier:itemID];
    if (message) *message = success
        ? [NSString stringWithFormat:@"Drew text on overlay canvas %@ (%@)", canvasID, itemID]
        : @"Failed to draw text on overlay canvas";
    return success;
}

- (BOOL)_executeSwizzleMethodWithMessage:(NSString **)message {
    NSString *className = [self _stringParamForKeys:@[@"className", @"class", @"class_name"]];
    NSString *selector = [self _stringParamForKeys:@[@"selector", @"sel", @"method"]];
    NSString *otherClassName = [self _stringParamForKeys:@[@"otherClassName", @"other_class", @"swizzleClass", @"targetClass", @"class2"]];
    NSString *otherSelector = [self _stringParamForKeys:@[@"otherSelector", @"other_selector", @"swizzleSelector", @"targetSelector", @"selector2"]];

    if (className.length == 0 || selector.length == 0 || otherClassName.length == 0 || otherSelector.length == 0) {
        if (message) *message = @"Missing source or target method for swizzle_method";
        return NO;
    }

    NSDictionary *metadata = @{
        @"otherClassName": otherClassName,
        @"otherSelector": otherSelector,
        @"isClassMethod": @([self _boolParamForKeys:@[@"isClassMethod", @"class_method", @"is_class_method"]]),
        @"otherIsClassMethod": @([self _boolParamForKeys:@[@"otherIsClassMethod", @"other_class_method", @"targetClassMethod"]]),
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:metadata options:0 error:nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    VCPatchItem *item = [[VCPatchItem alloc] init];
    item.className = className;
    item.selector = selector;
    item.patchType = @"swizzle";
    item.customCode = jsonString;
    item.remark = _toolCall.remark ?: [self _stringParamForKeys:@[@"remark"]];
    item.source = VCItemSourceAI;
    item.sourceToolID = _toolCall.toolID;
    item.enabled = YES;

    BOOL applied = [[VCHookManager shared] applyPatch:item];
    if (!applied) {
        if (message) *message = [NSString stringWithFormat:@"Swizzle failed for %@ / %@", selector, otherSelector];
        return NO;
    }

    [[VCPatchManager shared] addPatch:item];
    if (message) {
        *message = [NSString stringWithFormat:@"Swizzled -[%@ %@] <-> -[%@ %@]",
                    className, selector, otherClassName, otherSelector];
    }
    return YES;
}

- (NSString *)_stringParamForKeys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        id value = _toolCall.params[key];
        if ([value isKindOfClass:[NSString class]] && [((NSString *)value) length] > 0) return value;
        if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    }
    return nil;
}

- (id)_paramForKeys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        id value = _toolCall.params[key];
        if (value && value != [NSNull null]) return value;
    }
    return nil;
}

- (BOOL)_boolParamForKeys:(NSArray<NSString *> *)keys {
    id value = [self _paramForKeys:keys];
    if (!value) return NO;
    return [self _boolFromValue:value];
}

- (NSDictionary *)_dictionaryParamForKeys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        id value = _toolCall.params[key];
        if ([value isKindOfClass:[NSDictionary class]]) return value;
    }
    return nil;
}

- (NSArray *)_arrayParamForKeys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        id value = _toolCall.params[key];
        if ([value isKindOfClass:[NSArray class]]) return value;
    }
    return nil;
}

- (NSArray<NSValue *> *)_pointArrayParamForKeys:(NSArray<NSString *> *)keys {
    NSArray *rawPoints = [self _arrayParamForKeys:keys];
    if (![rawPoints isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray<NSValue *> *points = [NSMutableArray new];
    for (id rawPoint in rawPoints) {
        CGPoint point = CGPointZero;
        BOOL valid = NO;
        if ([rawPoint isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)rawPoint;
            id x = dict[@"x"];
            id y = dict[@"y"];
            if ([x respondsToSelector:@selector(doubleValue)] && [y respondsToSelector:@selector(doubleValue)]) {
                point = CGPointMake([x doubleValue], [y doubleValue]);
                valid = YES;
            }
        } else if ([rawPoint isKindOfClass:[NSArray class]]) {
            NSArray *pair = (NSArray *)rawPoint;
            if (pair.count >= 2 &&
                [pair[0] respondsToSelector:@selector(doubleValue)] &&
                [pair[1] respondsToSelector:@selector(doubleValue)]) {
                point = CGPointMake([pair[0] doubleValue], [pair[1] doubleValue]);
                valid = YES;
            }
        }
        if (valid) [points addObject:[NSValue valueWithCGPoint:point]];
    }
    return [points copy];
}

- (NSArray<NSArray<NSNumber *> *> *)_indexPairsParamForKeys:(NSArray<NSString *> *)keys {
    NSArray *rawPairs = [self _arrayParamForKeys:keys];
    if (![rawPairs isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray<NSArray<NSNumber *> *> *pairs = [NSMutableArray new];
    for (id rawPair in rawPairs) {
        if (![rawPair isKindOfClass:[NSArray class]]) continue;
        NSArray *pair = (NSArray *)rawPair;
        if (pair.count < 2) continue;
        id first = pair[0];
        id second = pair[1];
        if (![first respondsToSelector:@selector(integerValue)] ||
            ![second respondsToSelector:@selector(integerValue)]) {
            continue;
        }
        [pairs addObject:@[@([first integerValue]), @([second integerValue])]];
    }
    return [pairs copy];
}

- (uintptr_t)_addressParamForKeys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        id value = _toolCall.params[key];
        if ([value isKindOfClass:[NSNumber class]]) return (uintptr_t)[(NSNumber *)value unsignedLongLongValue];
        if ([value isKindOfClass:[NSString class]]) {
            NSString *string = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!string.length) continue;
            unsigned long long addr = 0;
            NSScanner *scanner = [NSScanner scannerWithString:string];
            BOOL scanned = [scanner scanHexLongLong:&addr];
            if (!scanned) addr = strtoull(string.UTF8String, NULL, 0);
            if (addr != 0) return (uintptr_t)addr;
        }
    }
    return 0;
}

- (id)_convertedViewValue:(id)rawValue forProperty:(NSString *)property {
    NSString *lower = property.lowercaseString;
    if ([lower isEqualToString:@"hidden"] ||
        [lower isEqualToString:@"clipstobounds"] ||
        [lower isEqualToString:@"userinteractionenabled"]) {
        return @([self _boolFromValue:rawValue]);
    }

    if ([lower isEqualToString:@"alpha"]) {
        return @([self _doubleFromValue:rawValue]);
    }

    if ([lower isEqualToString:@"tag"]) {
        return @((NSInteger)[self _doubleFromValue:rawValue]);
    }

    if ([lower isEqualToString:@"frame"]) {
        if ([rawValue isKindOfClass:[NSString class]]) return rawValue;
        if ([rawValue isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = rawValue;
            CGFloat x = [dict[@"x"] doubleValue];
            CGFloat y = [dict[@"y"] doubleValue];
            CGFloat width = [dict[@"width"] doubleValue];
            CGFloat height = [dict[@"height"] doubleValue];
            return NSStringFromCGRect(CGRectMake(x, y, width, height));
        }
        return nil;
    }

    if ([lower isEqualToString:@"backgroundcolor"] || [lower isEqualToString:@"textcolor"]) {
        if ([rawValue isKindOfClass:[NSString class]]) {
            NSString *string = [(NSString *)rawValue stringByReplacingOccurrencesOfString:@"#" withString:@""];
            return string;
        }
        return nil;
    }

    if ([rawValue isKindOfClass:[NSNumber class]]) return [(NSNumber *)rawValue stringValue];
    if ([rawValue isKindOfClass:[NSString class]]) return rawValue;
    return [rawValue description];
}

- (BOOL)_boolFromValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value boolValue];
    if ([value isKindOfClass:[NSString class]]) {
        NSString *lower = [(NSString *)value lowercaseString];
        return [@[@"1", @"true", @"yes", @"on"] containsObject:lower];
    }
    return NO;
}

- (double)_doubleFromValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value doubleValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value doubleValue];
    return 0;
}

- (NSString *)_normalizedValueType:(NSString *)type allowUnsupported:(BOOL)allowUnsupported {
    NSString *lower = type.lowercaseString ?: @"";
    if (lower.length == 0) return @"";
    if ([lower isEqualToString:@"bool"] || [lower isEqualToString:@"boolean"]) return @"BOOL";
    if ([lower isEqualToString:@"char"]) return @"char";
    if ([lower isEqualToString:@"uchar"] || [lower isEqualToString:@"unsignedchar"]) return @"uchar";
    if ([lower isEqualToString:@"short"]) return @"short";
    if ([lower isEqualToString:@"ushort"] || [lower isEqualToString:@"unsignedshort"]) return @"ushort";
    if ([lower isEqualToString:@"int"]) return @"int";
    if ([lower isEqualToString:@"uint"] || [lower isEqualToString:@"unsignedint"]) return @"uint";
    if ([lower isEqualToString:@"float"]) return @"float";
    if ([lower isEqualToString:@"double"]) return @"double";
    if ([lower isEqualToString:@"long"]) return @"long";
    if ([lower isEqualToString:@"ulong"] || [lower isEqualToString:@"unsignedlong"]) return @"ulong";
    if ([lower isEqualToString:@"longlong"] || [lower isEqualToString:@"long_long"] || [lower isEqualToString:@"ll"]) return @"longlong";
    if ([lower isEqualToString:@"ulonglong"] || [lower isEqualToString:@"unsignedlonglong"] || [lower isEqualToString:@"ull"]) return @"ulonglong";
    if ([lower isEqualToString:@"nsstring"] || [lower isEqualToString:@"string"]) return allowUnsupported ? @"NSString" : @"";
    return allowUnsupported ? type : @"";
}

- (NSString *)_detailText {
    NSMutableString *detail = [NSMutableString new];
    NSArray *sortedKeys = [[_toolCall.params allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        id val = _toolCall.params[key];
        [detail appendFormat:@"%@: %@\n", key, val];
    }
    if (_toolCall.resultMessage.length) {
        [detail appendFormat:@"Result: %@\n", _toolCall.resultMessage];
    }
    if (_toolCall.executed) {
        [detail appendFormat:@"Execution: %@\n", _toolCall.success ? @"Applied" : @"Failed"];
    }
    if (_toolCall.lastExecutedAt > 0) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *timeText = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:_toolCall.lastExecutedAt]];
        [detail appendFormat:@"Last Run: %@\n", timeText];
    }
    if (_toolCall.verificationStatus != VCToolCallVerificationNone) {
        NSString *status = @"Claimed";
        if (_toolCall.verificationStatus == VCToolCallVerificationVerified) status = @"Verified";
        else if (_toolCall.verificationStatus == VCToolCallVerificationFailed) status = @"Failed";
        [detail appendFormat:@"Verification: %@\n", status];
        if (_toolCall.verificationMessage.length) {
            [detail appendFormat:@"Verification Detail: %@\n", _toolCall.verificationMessage];
        }
    }
    return [[detail stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
}

- (NSString *)_headerBadgeText {
    switch (_toolCall.type) {
        case VCToolCallModifyValue: {
            NSString *target = [self _stringParamForKeys:@[@"target", @"targetDesc", @"target_desc", @"name"]];
            if (target.length > 0) return [NSString stringWithFormat:@" %@ ", target];
            uintptr_t address = [self _addressParamForKeys:@[@"address", @"addr"]];
            return address ? [NSString stringWithFormat:@" 0x%llx ", (unsigned long long)address] : @"";
        }
        case VCToolCallWriteMemoryBytes: {
            NSString *target = [self _stringParamForKeys:@[@"target", @"targetDesc", @"target_desc", @"name"]];
            if (target.length > 0) return [NSString stringWithFormat:@" %@ ", target];
            uintptr_t address = [self _addressParamForKeys:@[@"address", @"addr"]];
            return address ? [NSString stringWithFormat:@" 0x%llx ", (unsigned long long)address] : @"";
        }
        case VCToolCallPatchMethod:
        case VCToolCallHookMethod:
        case VCToolCallSwizzleMethod: {
            NSString *className = [self _stringParamForKeys:@[@"className", @"class", @"class_name"]];
            NSString *selector = [self _stringParamForKeys:@[@"selector", @"sel", @"method"]];
            if (className.length == 0 && selector.length == 0) return @"";
            return [NSString stringWithFormat:@" %@ %@ ", className ?: @"", selector ?: @""];
        }
        case VCToolCallModifyHeader: {
            NSString *pattern = [self _stringParamForKeys:@[@"urlPattern", @"url_pattern", @"pattern", @"url"]];
            return pattern.length ? [NSString stringWithFormat:@" %@ ", pattern] : @"";
        }
        case VCToolCallModifyView:
        case VCToolCallInsertSubview:
        case VCToolCallInvokeSelector: {
            NSString *property = [self _stringParamForKeys:@[@"property", @"selector", @"className", @"class", @"type"]];
            return property.length ? [NSString stringWithFormat:@" %@ ", property] : @"";
        }
        case VCToolCallOverlayCanvas: {
            NSString *action = [self _stringParamForKeys:@[@"action"]];
            NSString *canvasID = [self _stringParamForKeys:@[@"canvasID", @"canvas", @"canvas_id"]];
            if (action.length == 0 && canvasID.length == 0) return @"";
            return [NSString stringWithFormat:@" %@ %@ ", action ?: @"canvas", canvasID.length > 0 ? canvasID : @"unity"];
        }
        case VCToolCallOverlayTrack: {
            NSString *action = [self _stringParamForKeys:@[@"action"]];
            NSString *mode = [self _stringParamForKeys:@[@"trackMode", @"track_mode", @"mode", @"type"]];
            NSString *canvasID = [self _stringParamForKeys:@[@"canvasID", @"canvas", @"canvas_id"]];
            NSMutableArray<NSString *> *parts = [NSMutableArray new];
            if (action.length > 0) [parts addObject:action];
            if (mode.length > 0) [parts addObject:mode];
            if (canvasID.length > 0) [parts addObject:canvasID];
            if (parts.count == 0) return @"";
            return [NSString stringWithFormat:@" %@ ", [parts componentsJoinedByString:@" • "]];
        }
        default:
            return @"";
    }
}

- (NSString *)_previewText {
    if (_toolCall.resultMessage.length > 0) {
        return _toolCall.resultMessage;
    }
    if ([self _isReadOnlyToolCallType:_toolCall.type]) {
        return @"Read-only analysis tool. It runs automatically while VansonCLI is replying.";
    }
    if (_toolCall.remark.length > 0) {
        return _toolCall.remark;
    }
    if (_toolCall.executed && _toolCall.success) {
        return @"Runtime action applied automatically.";
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    NSArray<NSString *> *keys = [[_toolCall.params allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        id value = _toolCall.params[key];
        NSString *valueText = nil;
        if ([value isKindOfClass:[NSString class]]) valueText = value;
        else if ([value isKindOfClass:[NSNumber class]]) valueText = [(NSNumber *)value stringValue];
        if (valueText.length == 0) continue;
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key, valueText]];
        if (parts.count >= 2) break;
    }
    return parts.count > 0 ? [parts componentsJoinedByString:@" • "] : @"Runtime action ready to run immediately.";
}

- (NSString *)_buttonTitleForToolCall {
    if ([self _isReadOnlyToolCallType:_toolCall.type]) return @"Auto";
    if (!_toolCall.executed) return _toolCall.resultMessage.length ? @"Retry" : @"Run";
    if (_toolCall.verificationStatus == VCToolCallVerificationVerified) return @"Verified";
    if (_toolCall.verificationStatus == VCToolCallVerificationFailed) return @"Retry";
    return @"Applied";
}

- (NSString *)_buttonIconNameForToolCall {
    if ([self _isReadOnlyToolCallType:_toolCall.type]) return @"eye";
    if (!_toolCall.executed && _toolCall.resultMessage.length) return @"arrow.clockwise";
    if (!_toolCall.executed) return @"play.fill";
    if (_toolCall.verificationStatus == VCToolCallVerificationVerified) return @"checkmark";
    if (_toolCall.verificationStatus == VCToolCallVerificationFailed) return @"arrow.clockwise";
    return @"checkmark.circle";
}

- (UIColor *)_buttonTitleColorForToolCall {
    if (!_toolCall.executed) return kVCAccent;
    if (_toolCall.verificationStatus == VCToolCallVerificationVerified) return kVCGreen;
    if (_toolCall.verificationStatus == VCToolCallVerificationFailed) return kVCRed;
    return kVCYellow;
}

- (UIColor *)_buttonBackgroundColorForToolCall {
    if (!_toolCall.executed) return kVCAccentDim;
    if (_toolCall.verificationStatus == VCToolCallVerificationVerified) return kVCGreenDim;
    if (_toolCall.verificationStatus == VCToolCallVerificationFailed) return [kVCRed colorWithAlphaComponent:0.12];
    return [kVCYellow colorWithAlphaComponent:0.14];
}

- (UIColor *)_buttonBorderColorForToolCall {
    if (!_toolCall.executed) return [kVCAccent colorWithAlphaComponent:0.22];
    if (_toolCall.verificationStatus == VCToolCallVerificationVerified) return [kVCGreen colorWithAlphaComponent:0.24];
    if (_toolCall.verificationStatus == VCToolCallVerificationFailed) return [kVCRed colorWithAlphaComponent:0.24];
    return [kVCYellow colorWithAlphaComponent:0.26];
}

- (BOOL)_buttonEnabledForToolCall {
    if ([self _isReadOnlyToolCallType:_toolCall.type]) return NO;
    return !_toolCall.executed || _toolCall.verificationStatus == VCToolCallVerificationFailed;
}

- (UIColor *)_titleColorForToolCall {
    if ([self _isReadOnlyToolCallType:_toolCall.type]) return kVCAccent;
    if (!_toolCall.executed && _toolCall.resultMessage.length) return kVCRed;
    if (!_toolCall.executed) return kVCYellow;
    if (!_toolCall.success) return kVCRed;
    if (_toolCall.verificationStatus == VCToolCallVerificationVerified) return kVCGreen;
    if (_toolCall.verificationStatus == VCToolCallVerificationFailed) return kVCRed;
    return kVCYellow;
}

- (NSString *)_statusIconName {
    if ([self _isReadOnlyToolCallType:_toolCall.type]) return @"eye";
    if (!_toolCall.executed && _toolCall.resultMessage.length > 0) return @"exclamationmark.triangle.fill";
    if (!_toolCall.executed) return @"play.circle.fill";
    if (!_toolCall.success) return @"xmark.circle.fill";
    if (_toolCall.verificationStatus == VCToolCallVerificationVerified) return @"checkmark.circle.fill";
    if (_toolCall.verificationStatus == VCToolCallVerificationFailed) return @"exclamationmark.triangle.fill";
    return @"clock.arrow.circlepath";
}

- (UIColor *)_statusIconColor {
    if ([self _isReadOnlyToolCallType:_toolCall.type]) return kVCAccent;
    if (!_toolCall.executed && _toolCall.resultMessage.length > 0) return kVCRed;
    if (!_toolCall.executed) return kVCYellow;
    if (!_toolCall.success) return kVCRed;
    if (_toolCall.verificationStatus == VCToolCallVerificationVerified) return kVCGreen;
    if (_toolCall.verificationStatus == VCToolCallVerificationFailed) return kVCRed;
    return kVCYellow;
}

@end
