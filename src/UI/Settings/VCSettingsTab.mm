/**
 * VCSettingsTab -- Settings Tab
 * Refined settings surface for models and language.
 */

#import "VCSettingsTab.h"
#import "../../../VansonCLI.h"
#import "../../AI/Models/VCProviderManager.h"
#import "../../AI/Models/VCProviderConfig.h"
#import "../../AI/Adapters/VCAIAdapter.h"
#import "../../Core/VCConfig.h"
#import "../About/VCAboutTab.h"
#import "../Base/VCOverlayWindow.h"
#import "../Base/VCOverlayRootViewController.h"
#import "../Panel/VCPanel.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSNotificationName const VCSettingsRequestOpenAIChatNotification = @"VCSettingsRequestOpenAIChatNotification";

// ═══════════════════════════════════════════════════════════════
// Settings menu item model
// ═══════════════════════════════════════════════════════════════

typedef NS_ENUM(NSInteger, VCSettingsItem) {
    VCSettingsItemModel = 0,
    VCSettingsItemLanguage,
    VCSettingsItemAbout,
    VCSettingsItemCount,
};

static NSString *VCSettingsProtocolDisplayName(VCAPIProtocol protocol) {
    switch (protocol) {
        case VCAPIProtocolOpenAI: return @"OpenAI · Chat";
        case VCAPIProtocolOpenAIResponses: return @"OpenAI · Responses";
        case VCAPIProtocolAnthropic:
        case VCAPIProtocolGemini:
            return @"OpenAI · Responses";
    }
    return @"OpenAI";
}

static NSString *VCSettingsSafeString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value copy];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] copy];
    }
    return @"";
}

static BOOL VCSettingsProviderIsOpenAIOnly(VCProviderConfig *provider) {
    if (!provider) return NO;
    if (provider.protocol != VCAPIProtocolOpenAI && provider.protocol != VCAPIProtocolOpenAIResponses) return NO;
    NSString *name = VCSettingsSafeString(provider.name).lowercaseString;
    NSString *endpoint = VCSettingsSafeString(provider.endpoint).lowercaseString;
    return [name containsString:@"openai"] || [endpoint containsString:@"api.openai.com"];
}

static NSInteger VCSettingsProviderFamilyIndexForProtocol(VCAPIProtocol protocol) {
    (void)protocol;
    return 0;
}

static NSInteger VCSettingsWireModeIndexForProtocol(VCAPIProtocol protocol) {
    return (protocol == VCAPIProtocolOpenAIResponses) ? 1 : 0;
}

static VCAPIProtocol VCSettingsProtocolFromEditorSelection(NSInteger providerIndex, NSInteger wireModeIndex) {
    (void)providerIndex;
    return (wireModeIndex == 1) ? VCAPIProtocolOpenAIResponses : VCAPIProtocolOpenAI;
}

@interface VCLanguageDrawer : UIView
@property (nonatomic, strong) UIControl *backdropControl;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) UIView *handleView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIScrollView *optionsScrollView;
@property (nonatomic, strong) UIStackView *optionsStack;
@property (nonatomic, copy) NSArray<UIButton *> *optionButtons;
@property (nonatomic, copy) NSString *selectedOption;
@property (nonatomic, strong) UIStackView *actionStack;
@property (nonatomic, copy) void(^onSelect)(NSString *option);
@property (nonatomic, copy) void(^onDismiss)(void);
@end

@implementation VCLanguageDrawer

- (instancetype)initWithCurrentOption:(NSString *)currentOption {
    if (self = [super initWithFrame:CGRectZero]) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self _build:currentOption ?: [VCLanguage preferredLanguageOption]];
    }
    return self;
}

- (void)_build:(NSString *)currentOption {
    self.backdropControl = [[UIControl alloc] init];
    self.backdropControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backdropControl addTarget:self action:@selector(_dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.backdropControl];

    self.sheetView = [[UIView alloc] init];
    self.sheetView.translatesAutoresizingMaskIntoConstraints = NO;
    VCApplyPanelSurface(self.sheetView, 12.0);
    self.sheetView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    self.sheetView.clipsToBounds = YES;
    [self addSubview:self.sheetView];

    self.handleView = [[UIView alloc] init];
    self.handleView.translatesAutoresizingMaskIntoConstraints = NO;
    self.handleView.backgroundColor = kVCTextMuted;
    self.handleView.layer.cornerRadius = 2.0;
    [self.sheetView addSubview:self.handleView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = VCTextLiteral(@"Language");
    self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.titleLabel.textColor = kVCTextPrimary;
    [self.sheetView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = [NSString stringWithFormat:@"%@: %@", VCTextLiteral(@"Active"), [VCLanguage languageSummaryText]];
    self.subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.subtitleLabel.textColor = kVCTextSecondary;
    self.subtitleLabel.numberOfLines = 2;
    [self.sheetView addSubview:self.subtitleLabel];

    NSArray<NSString *> *options = [VCLanguage availableLanguageOptions];
    self.selectedOption = [options containsObject:currentOption] ? currentOption : [VCLanguage preferredLanguageOption];

    self.optionsScrollView = [[UIScrollView alloc] init];
    self.optionsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.optionsScrollView.showsVerticalScrollIndicator = YES;
    self.optionsScrollView.alwaysBounceVertical = YES;
    [self.sheetView addSubview:self.optionsScrollView];

    self.optionsStack = [[UIStackView alloc] init];
    self.optionsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.optionsStack.axis = UILayoutConstraintAxisVertical;
    self.optionsStack.spacing = 8.0;
    [self.optionsScrollView addSubview:self.optionsStack];

    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithCapacity:options.count];
    for (NSUInteger idx = 0; idx < options.count; idx++) {
        NSString *option = options[idx];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tag = (NSInteger)idx;
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 14.0, 0.0, 14.0);
        button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        button.layer.cornerRadius = 8.0;
        button.layer.borderWidth = 1.0;
        button.accessibilityIdentifier = [NSString stringWithFormat:@"vc.language.option.%@", option];
        [button setTitle:[VCLanguage displayNameForOption:option] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(_optionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.optionsStack addArrangedSubview:button];
        [button.heightAnchor constraintEqualToConstant:38.0].active = YES;
        [buttons addObject:button];
    }
    self.optionButtons = buttons;
    [self _refreshOptionButtons];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [cancel setTitle:VCTextLiteral(@"Cancel") forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(cancel);
    [cancel addTarget:self action:@selector(_dismiss) forControlEvents:UIControlEventTouchUpInside];

    UIButton *apply = [UIButton buttonWithType:UIButtonTypeSystem];
    apply.translatesAutoresizingMaskIntoConstraints = NO;
    [apply setTitle:VCTextLiteral(@"Save") forState:UIControlStateNormal];
    VCApplyCompactPrimaryButtonStyle(apply);
    [apply addTarget:self action:@selector(_apply) forControlEvents:UIControlEventTouchUpInside];

    self.actionStack = [[UIStackView alloc] initWithArrangedSubviews:@[cancel, apply]];
    self.actionStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionStack.axis = UILayoutConstraintAxisHorizontal;
    self.actionStack.spacing = 10.0;
    self.actionStack.distribution = UIStackViewDistributionFillEqually;
    [self.sheetView addSubview:self.actionStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.backdropControl.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.backdropControl.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.backdropControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.backdropControl.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [self.sheetView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.sheetView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.sheetView.topAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:12.0],
        [self.sheetView.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor],

        [self.handleView.topAnchor constraintEqualToAnchor:self.sheetView.topAnchor constant:8.0],
        [self.handleView.centerXAnchor constraintEqualToAnchor:self.sheetView.centerXAnchor],
        [self.handleView.widthAnchor constraintEqualToConstant:36.0],
        [self.handleView.heightAnchor constraintEqualToConstant:4.0],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.handleView.bottomAnchor constant:8.0],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.sheetView.leadingAnchor constant:16.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.sheetView.trailingAnchor constant:-16.0],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4.0],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],

        [self.optionsScrollView.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:12.0],
        [self.optionsScrollView.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.optionsScrollView.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.optionsScrollView.heightAnchor constraintEqualToConstant:260.0],

        [self.optionsStack.topAnchor constraintEqualToAnchor:self.optionsScrollView.contentLayoutGuide.topAnchor],
        [self.optionsStack.leadingAnchor constraintEqualToAnchor:self.optionsScrollView.contentLayoutGuide.leadingAnchor],
        [self.optionsStack.trailingAnchor constraintEqualToAnchor:self.optionsScrollView.contentLayoutGuide.trailingAnchor],
        [self.optionsStack.bottomAnchor constraintEqualToAnchor:self.optionsScrollView.contentLayoutGuide.bottomAnchor],
        [self.optionsStack.widthAnchor constraintEqualToAnchor:self.optionsScrollView.frameLayoutGuide.widthAnchor],

        [self.actionStack.topAnchor constraintEqualToAnchor:self.optionsScrollView.bottomAnchor constant:14.0],
        [self.actionStack.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.actionStack.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.actionStack.bottomAnchor constraintEqualToAnchor:self.sheetView.bottomAnchor constant:-16.0],
    ]];
}

- (void)showAnimated {
    [self layoutIfNeeded];
    self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, CGRectGetHeight(self.sheetView.bounds) + self.safeAreaInsets.bottom + 20.0);
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.24];
        self.sheetView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)_optionTapped:(UIButton *)sender {
    NSArray<NSString *> *options = [VCLanguage availableLanguageOptions];
    NSInteger index = MAX(0, MIN((NSInteger)options.count - 1, sender.tag));
    self.selectedOption = options[index];
    [self _refreshOptionButtons];
}

- (void)_refreshOptionButtons {
    NSArray<NSString *> *options = [VCLanguage availableLanguageOptions];
    for (NSUInteger idx = 0; idx < self.optionButtons.count; idx++) {
        UIButton *button = self.optionButtons[idx];
        NSString *option = idx < options.count ? options[idx] : @"auto";
        BOOL selected = [option isEqualToString:self.selectedOption];
        button.backgroundColor = selected ? kVCAccentDim : [kVCBgSecondary colorWithAlphaComponent:0.72];
        button.layer.borderColor = (selected ? kVCBorderAccent : kVCBorder).CGColor;
        [button setTitleColor:(selected ? kVCAccent : kVCTextPrimary) forState:UIControlStateNormal];
        NSString *title = [VCLanguage displayNameForOption:option];
        [button setTitle:(selected ? [NSString stringWithFormat:@"✓ %@", title] : [NSString stringWithFormat:@"  %@", title])
                forState:UIControlStateNormal];
    }
}

- (void)_apply {
    NSString *option = self.selectedOption.length > 0 ? self.selectedOption : [VCLanguage preferredLanguageOption];
    if (self.onSelect) self.onSelect(option);
    [self _dismiss];
}

- (void)_dismiss {
    [self layoutIfNeeded];
    [UIView animateWithDuration:0.22 animations:^{
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
        self.sheetView.transform = CGAffineTransformMakeTranslation(0.0, CGRectGetHeight(self.sheetView.bounds) + self.safeAreaInsets.bottom + 20.0);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (self.onDismiss) self.onDismiss();
    }];
}

@end


// ═══════════════════════════════════════════════════════════════
// Provider list cell
// ═══════════════════════════════════════════════════════════════

@interface VCProviderListCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *endpointLabel;
@property (nonatomic, strong) UILabel *modelLabel;
@property (nonatomic, strong) UILabel *protocolBadge;
@property (nonatomic, strong) UILabel *statusBadge;
@property (nonatomic, strong) UILabel *typeBadge;
- (void)configureWithProvider:(VCProviderConfig *)provider active:(BOOL)isActive;
@end

@implementation VCProviderListCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleDefault;

        _cardView = [[UIView alloc] initWithFrame:CGRectZero];
        _cardView.backgroundColor = [kVCBgHover colorWithAlphaComponent:0.78];
        _cardView.layer.cornerRadius = 16.0;
        _cardView.layer.borderWidth = 1.0;
        _cardView.layer.borderColor = kVCBorder.CGColor;
        [self.contentView addSubview:_cardView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.textColor = kVCTextPrimary;
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        [_cardView addSubview:_titleLabel];

        _endpointLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _endpointLabel.textColor = kVCTextSecondary;
        _endpointLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _endpointLabel.numberOfLines = 1;
        _endpointLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_cardView addSubview:_endpointLabel];

        _modelLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _modelLabel.textColor = kVCTextSecondary;
        _modelLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _modelLabel.numberOfLines = 2;
        [_cardView addSubview:_modelLabel];

        _protocolBadge = [self _badgeLabel];
        [_cardView addSubview:_protocolBadge];

        _statusBadge = [self _badgeLabel];
        [_cardView addSubview:_statusBadge];

        _typeBadge = [self _badgeLabel];
        [_cardView addSubview:_typeBadge];

        UIView *selectedView = [[UIView alloc] init];
        selectedView.backgroundColor = [kVCAccent colorWithAlphaComponent:0.14];
        selectedView.layer.cornerRadius = 16.0;
        selectedView.layer.borderWidth = 1.0;
        selectedView.layer.borderColor = kVCBorderAccent.CGColor;
        self.selectedBackgroundView = selectedView;
    }
    return self;
}

- (UILabel *)_badgeLabel {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    label.layer.cornerRadius = 10.0;
    label.layer.borderWidth = 1.0;
    label.clipsToBounds = YES;
    return label;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.typeBadge.hidden = NO;
}

- (void)configureWithProvider:(VCProviderConfig *)provider active:(BOOL)isActive {
    if (!provider) {
        self.titleLabel.text = @"";
        self.endpointLabel.text = @"";
        self.modelLabel.text = @"";
        self.protocolBadge.text = @"";
        self.statusBadge.text = @"";
        self.typeBadge.text = @"";
        self.typeBadge.hidden = YES;
        return;
    }

    NSString *providerName = VCSettingsSafeString(provider.name);
    NSString *providerEndpoint = VCSettingsSafeString(provider.endpoint);
    NSString *providerAPIKey = VCSettingsSafeString(provider.apiKey);
    NSString *selectedModel = [[VCProviderManager shared] effectiveSelectedModelForProvider:provider];
    NSString *modelText = selectedModel.length ? selectedModel : VCTextLiteral(@"Default");
    NSString *keyText = providerAPIKey.length > 0 ? VCTextLiteral(@"API key ready") : VCTextLiteral(@"API key missing");

    self.titleLabel.text = providerName.length > 0 ? providerName : VCTextLiteral(@"Provider");
    self.titleLabel.textColor = isActive ? kVCAccent : kVCTextPrimary;
    self.endpointLabel.text = providerEndpoint.length ? providerEndpoint : VCTextLiteral(@"Endpoint not configured");
    self.modelLabel.text = [NSString stringWithFormat:@"%@: %@  ·  %@", VCTextLiteral(@"Model"), modelText, keyText];

    [self _configureBadge:self.protocolBadge
                     text:VCSettingsProtocolDisplayName(provider.protocol)
                textColor:kVCTextPrimary
          backgroundColor:kVCAccentDim
              borderColor:kVCBorderAccent];

    [self _configureBadge:self.statusBadge
                     text:(isActive ? VCTextLiteral(@"Active") : VCTextLiteral(@"Available"))
                textColor:(isActive ? kVCGreen : kVCTextSecondary)
          backgroundColor:(isActive ? kVCGreenDim : [kVCBgInput colorWithAlphaComponent:0.72])
              borderColor:(isActive ? [kVCGreen colorWithAlphaComponent:0.30] : kVCBorder)];

    if (provider.isBuiltin) {
        [self _configureBadge:self.typeBadge
                         text:VCTextLiteral(@"Built-in")
                    textColor:kVCTextSecondary
              backgroundColor:[kVCBgInput colorWithAlphaComponent:0.72]
                  borderColor:kVCBorder];
        self.typeBadge.hidden = NO;
    } else {
        self.typeBadge.hidden = YES;
    }

    [self setNeedsLayout];
}

- (void)_configureBadge:(UILabel *)badge
                   text:(NSString *)text
              textColor:(UIColor *)textColor
        backgroundColor:(UIColor *)backgroundColor
            borderColor:(UIColor *)borderColor {
    badge.text = text ?: @"";
    badge.textColor = textColor ?: kVCTextPrimary;
    badge.backgroundColor = backgroundColor ?: [UIColor clearColor];
    badge.layer.borderColor = (borderColor ?: UIColor.clearColor).CGColor;
}

- (CGFloat)_badgeWidthForText:(NSString *)text {
    NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold]};
    CGFloat width = ceil([text sizeWithAttributes:attrs].width) + 18.0;
    return MIN(MAX(width, 56.0), 120.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.cardView.frame = CGRectInset(self.contentView.bounds, 10.0, 4.0);
    self.selectedBackgroundView.frame = self.cardView.frame;

    CGFloat inset = 14.0;
    CGFloat width = CGRectGetWidth(self.cardView.bounds);
    CGFloat rightX = width - inset;

    CGFloat statusWidth = [self _badgeWidthForText:self.statusBadge.text];
    self.statusBadge.frame = CGRectMake(rightX - statusWidth, 14.0, statusWidth, 20.0);
    rightX = CGRectGetMinX(self.statusBadge.frame) - 6.0;

    if (!self.typeBadge.hidden) {
        CGFloat typeWidth = [self _badgeWidthForText:self.typeBadge.text];
        self.typeBadge.frame = CGRectMake(rightX - typeWidth, 14.0, typeWidth, 20.0);
        rightX = CGRectGetMinX(self.typeBadge.frame) - 6.0;
    } else {
        self.typeBadge.frame = CGRectZero;
    }

    CGFloat protocolWidth = [self _badgeWidthForText:self.protocolBadge.text];
    self.protocolBadge.frame = CGRectMake(inset, 14.0, protocolWidth, 20.0);

    CGFloat titleX = CGRectGetMaxX(self.protocolBadge.frame) + 8.0;
    CGFloat titleWidth = MAX(80.0, rightX - titleX);
    self.titleLabel.frame = CGRectMake(titleX, 12.0, titleWidth, 22.0);
    self.endpointLabel.frame = CGRectMake(inset, 40.0, width - (inset * 2.0), 16.0);
    self.modelLabel.frame = CGRectMake(inset, 58.0, width - (inset * 2.0), 28.0);
}

@end


// ═══════════════════════════════════════════════════════════════
// Model settings sub-view (provider list + editor)
// ═══════════════════════════════════════════════════════════════

@interface VCModelSettingsView : UIView <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UIButton *createButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyStateLabel;
@property (nonatomic, strong) NSArray<VCProviderConfig *> *providers;
@property (nonatomic, copy) void(^onBack)(void);
@property (nonatomic, strong) UIView *editorOverlay;
@property (nonatomic, strong) UIView *editorCard;
@property (nonatomic, strong) UIScrollView *editorCardScrollView;
@property (nonatomic, strong) UIView *editorActionBar;
@property (nonatomic, strong) UIView *editorActionBarDivider;
@property (nonatomic, strong) UIView *editorHandle;
@property (nonatomic, strong) NSLayoutConstraint *editorCardBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *editorCardHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *simpleEditorCardLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *simpleEditorCardTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *simpleEditorCardWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *simpleEditorCardHeightConstraint;
@property (nonatomic, strong) UILabel *editorTitleLabel;
@property (nonatomic, strong) UILabel *editorHintLabel;
@property (nonatomic, strong) UILabel *editorStatusLabel;
@property (nonatomic, strong) UIButton *editorCloseButton;
@property (nonatomic, strong) UIButton *editorCancelButton;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *endpointField;
@property (nonatomic, strong) UITextField *apiVersionField;
@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UITextField *modelInputField;
@property (nonatomic, strong) UITextField *maxTokensField;
@property (nonatomic, strong) UITextView *rolePresetTextView;
@property (nonatomic, strong) UITextView *callLogTextView;
@property (nonatomic, strong) UILabel *debugEndpointLabel;
@property (nonatomic, strong) UILabel *providerLabel;
@property (nonatomic, strong) UILabel *connectionSectionLabel;
@property (nonatomic, strong) UILabel *connectionSectionHintLabel;
@property (nonatomic, strong) UILabel *wireModeLabel;
@property (nonatomic, strong) UILabel *rolePresetLabel;
@property (nonatomic, strong) UILabel *modelsSectionLabel;
@property (nonatomic, strong) UILabel *modelsSectionHintLabel;
@property (nonatomic, strong) UILabel *advancedSectionLabel;
@property (nonatomic, strong) UILabel *advancedSectionHintLabel;
@property (nonatomic, strong) UILabel *reasoningLabel;
@property (nonatomic, strong) UILabel *callLogLabel;
@property (nonatomic, strong) UIScrollView *modelsScrollView;
@property (nonatomic, strong) UIView *modelsScrollContentView;
@property (nonatomic, strong) UIStackView *modelsListStack;
@property (nonatomic, strong) UIButton *addModelButton;
@property (nonatomic, strong) UIButton *syncModelsButton;
@property (nonatomic, strong) UIButton *testProviderButton;
@property (nonatomic, strong) UISegmentedControl *protocolControl;
@property (nonatomic, strong) UISegmentedControl *wireModeControl;
@property (nonatomic, strong) UISegmentedControl *reasoningControl;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *activateButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIView *chatPromptBar;
@property (nonatomic, strong) UILabel *chatPromptLabel;
@property (nonatomic, strong) UIButton *chatPromptButton;
@property (nonatomic, strong) VCProviderConfig *editingProvider;
@property (nonatomic, strong) NSMutableArray<NSString *> *editorModels;
@property (nonatomic, copy) NSString *editorSelectedModel;
@property (nonatomic, weak) UIView *draggingModelRow;
@property (nonatomic, assign) NSInteger draggingModelIndex;
@property (nonatomic, assign) CGPoint draggingStartPoint;
@property (nonatomic, assign) BOOL editorCreatesProvider;
@property (nonatomic, assign) BOOL editorSyncingModels;
@property (nonatomic, assign) BOOL editorOverlaySetupFailed;
@property (nonatomic, assign) BOOL editorUsesSimpleSheet;
@property (nonatomic, assign) BOOL externalSystemModalSuspendedOverlay;
@property (nonatomic, assign) BOOL panelHiddenForExternalDocument;
- (void)reload;
- (void)presentNewProviderEditor;
@end

@implementation VCModelSettingsView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = kVCBgTertiary;
        _providers = @[];
        [self _build];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_providerStoreDidChange)
                                                     name:VCProviderManagerDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_build {
    _headerCard = [[UIView alloc] initWithFrame:CGRectZero];
    _headerCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.96];
    _headerCard.layer.cornerRadius = 18.0;
    _headerCard.layer.borderWidth = 1.0;
    _headerCard.layer.borderColor = kVCBorderStrong.CGColor;
    [self addSubview:_headerCard];

    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_backButton setTitle:VCTextLiteral(@"Back") forState:UIControlStateNormal];
    [_backButton setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(_backButton);
    _backButton.tintColor = kVCAccentHover;
    [_backButton addTarget:self action:@selector(_goBack) forControlEvents:UIControlEventTouchUpInside];
    [_headerCard addSubview:_backButton];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = VCTextLiteral(@"OpenAI Model");
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    _titleLabel.textColor = kVCTextPrimary;
    [_headerCard addSubview:_titleLabel];

    _summaryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _summaryLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _summaryLabel.textColor = kVCTextSecondary;
    _summaryLabel.numberOfLines = 1;
    _summaryLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_headerCard addSubview:_summaryLabel];

    _importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_importButton setTitle:nil forState:UIControlStateNormal];
    [_importButton setImage:[UIImage systemImageNamed:@"square.and.arrow.down"] forState:UIControlStateNormal];
    _importButton.accessibilityLabel = VCTextLiteral(@"Import");
    VCApplyCompactSecondaryButtonStyle(_importButton);
    _importButton.contentEdgeInsets = UIEdgeInsetsZero;
    _importButton.backgroundColor = [kVCBgHover colorWithAlphaComponent:0.86];
    _importButton.layer.borderColor = kVCBorder.CGColor;
    _importButton.tintColor = kVCAccentHover;
    [_importButton addTarget:self action:@selector(_importProviderConfig) forControlEvents:UIControlEventTouchUpInside];
    [_headerCard addSubview:_importButton];

    _createButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_createButton setTitle:nil forState:UIControlStateNormal];
    [_createButton setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    _createButton.accessibilityLabel = VCTextLiteral(@"Create");
    VCApplyCompactSecondaryButtonStyle(_createButton);
    _createButton.contentEdgeInsets = UIEdgeInsetsZero;
    _createButton.backgroundColor = [kVCBgHover colorWithAlphaComponent:0.86];
    _createButton.layer.borderColor = kVCBorder.CGColor;
    _createButton.tintColor = kVCAccentHover;
    [_createButton addTarget:self action:@selector(_addProvider) forControlEvents:UIControlEventTouchUpInside];
    [_headerCard addSubview:_createButton];

    // Table
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.9];
    _tableView.layer.cornerRadius = 16.0;
    _tableView.layer.borderWidth = 1.0;
    _tableView.layer.borderColor = kVCBorder.CGColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = 94;
    _tableView.contentInset = UIEdgeInsetsMake(6, 0, 8, 0);
    [_tableView registerClass:[VCProviderListCell class] forCellReuseIdentifier:@"ProvCell"];
    [self addSubview:_tableView];

    _emptyStateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyStateLabel.text = VCTextLiteral(@"No providers yet. Create one to start configuring models.");
    _emptyStateLabel.textColor = kVCTextMuted;
    _emptyStateLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _emptyStateLabel.numberOfLines = 0;
    _emptyStateLabel.textAlignment = NSTextAlignmentCenter;
    _emptyStateLabel.hidden = YES;
    _tableView.backgroundView = _emptyStateLabel;

    _chatPromptBar = [[UIView alloc] initWithFrame:CGRectZero];
    _chatPromptBar.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    _chatPromptBar.layer.cornerRadius = 14.0;
    _chatPromptBar.layer.borderWidth = 1.0;
    _chatPromptBar.layer.borderColor = kVCBorderAccent.CGColor;
    _chatPromptBar.alpha = 0.0;
    _chatPromptBar.hidden = YES;
    [self addSubview:_chatPromptBar];

    _chatPromptLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _chatPromptLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _chatPromptLabel.textColor = kVCTextPrimary;
    _chatPromptLabel.numberOfLines = 2;
    [_chatPromptBar addSubview:_chatPromptLabel];

    _chatPromptButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_chatPromptButton setTitle:VCTextLiteral(@"Open AI Chat") forState:UIControlStateNormal];
    VCApplyCompactPrimaryButtonStyle(_chatPromptButton);
    [_chatPromptButton addTarget:self action:@selector(_openAIChatFromPrompt) forControlEvents:UIControlEventTouchUpInside];
    [_chatPromptBar addSubview:_chatPromptButton];

}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    BOOL landscape = (width > height);
    CGFloat inset = 10.0;
    BOOL stacksPromptBar = width < 430.0;
    CGFloat headerHeight = landscape ? 64.0 : 72.0;
    CGFloat barHeight = stacksPromptBar ? 88.0 : (landscape ? 52.0 : 58.0);
    CGFloat promptInset = self.chatPromptBar.hidden ? 0.0 : (barHeight + 12.0);

    self.headerCard.frame = CGRectMake(inset, 10.0, width - (inset * 2.0), headerHeight);
    CGFloat headerWidth = CGRectGetWidth(self.headerCard.bounds);
    CGFloat actionSize = landscape ? 30.0 : 32.0;
    CGFloat topY = landscape ? 10.0 : 12.0;
    self.backButton.frame = CGRectMake(10.0, topY, 72.0, actionSize);
    self.createButton.frame = CGRectMake(headerWidth - actionSize - 10.0, topY, actionSize, actionSize);
    self.importButton.frame = CGRectMake(CGRectGetMinX(self.createButton.frame) - actionSize - 8.0, topY, actionSize, actionSize);

    CGFloat textX = CGRectGetMaxX(self.backButton.frame) + 10.0;
    CGFloat textRight = CGRectGetMinX(self.importButton.frame) - 10.0;
    self.titleLabel.frame = CGRectMake(textX, topY - 1.0, MAX(textRight - textX, 80.0), 21.0);
    self.summaryLabel.frame = CGRectMake(textX,
                                         CGRectGetMaxY(self.titleLabel.frame) + 2.0,
                                         MAX(textRight - textX, 80.0),
                                         18.0);

    CGFloat tableY = CGRectGetMaxY(self.headerCard.frame) + 10.0;
    CGFloat tableHeight = MAX(120.0, height - tableY - promptInset - 12.0);
    self.tableView.frame = CGRectMake(inset, tableY, width - (inset * 2.0), tableHeight);
    self.emptyStateLabel.frame = CGRectInset(self.tableView.bounds, 18.0, 18.0);

    self.chatPromptBar.frame = CGRectMake(10, height - barHeight - 12.0, width - 20.0, barHeight);
    if (stacksPromptBar) {
        self.chatPromptLabel.frame = CGRectMake(12.0, 10.0, CGRectGetWidth(self.chatPromptBar.bounds) - 24.0, 30.0);
        self.chatPromptButton.frame = CGRectMake(12.0, CGRectGetMaxY(self.chatPromptLabel.frame) + 8.0, CGRectGetWidth(self.chatPromptBar.bounds) - 24.0, 36.0);
    } else {
        self.chatPromptButton.frame = CGRectMake(CGRectGetWidth(self.chatPromptBar.bounds) - 112.0, 11.0, 98.0, 36.0);
        self.chatPromptLabel.frame = CGRectMake(12.0, 10.0, CGRectGetMinX(self.chatPromptButton.frame) - 18.0, 38.0);
    }

    [self _layoutSimpleEditorOverlay];
}

- (void)reload {
    NSMutableArray<VCProviderConfig *> *openAIProviders = [NSMutableArray array];
    for (VCProviderConfig *provider in ([[VCProviderManager shared] allProviders] ?: @[])) {
        if (VCSettingsProviderIsOpenAIOnly(provider)) {
            [openAIProviders addObject:provider];
        }
    }
    _providers = [openAIProviders copy];
    VCProviderConfig *activeProvider = [[VCProviderManager shared] activeProvider];
    if (activeProvider && !VCSettingsProviderIsOpenAIOnly(activeProvider)) {
        activeProvider = self.providers.firstObject;
        if (activeProvider) {
            [[VCProviderManager shared] setActiveProviderID:activeProvider.providerID];
        }
    }
    NSString *activeModel = [[VCProviderManager shared] effectiveSelectedModelForProvider:activeProvider];
    if (activeProvider) {
        NSString *modeText = activeProvider.protocol == VCAPIProtocolOpenAIResponses ? VCTextLiteral(@"Responses") : VCTextLiteral(@"Chat");
        self.summaryLabel.text = [NSString stringWithFormat:VCTextLiteral(@"%@ · %@"),
                                  activeModel.length ? activeModel : VCTextLiteral(@"Default"),
                                  modeText];
    } else {
        self.summaryLabel.text = VCTextLiteral(@"Add OpenAI provider to start AI Chat.");
    }
    self.emptyStateLabel.hidden = (self.providers.count > 0);
    if (activeProvider) {
        [self _showChatPromptIfNeededForProvider:activeProvider];
    } else {
        [self _hideChatPrompt];
    }
    [_tableView reloadData];
}

- (void)_providerStoreDidChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reload];
    });
}

- (void)_goBack {
    if (self.onBack) self.onBack();
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

- (UIViewController *)_preferredExternalPresenterViewController {
    UIViewController *hostVisible = [VCOverlayRootViewController currentVisibleHostViewController];
    if (hostVisible) {
        return hostVisible;
    }
    return [self _hostViewController];
}

- (void)_suspendOverlayInteractionForExternalModalIfNeeded {
    if (self.externalSystemModalSuspendedOverlay) return;
    VCOverlayWindow *overlay = [VCOverlayWindow shared];
    if (self.window == overlay || self.editorOverlay.window == overlay) {
        [overlay endInteractiveSession];
        self.externalSystemModalSuspendedOverlay = YES;
    }
}

- (void)_resumeOverlayInteractionAfterExternalModalIfNeeded {
    if (!self.externalSystemModalSuspendedOverlay) return;
    self.externalSystemModalSuspendedOverlay = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[VCOverlayWindow shared] beginInteractiveSession];
    });
}

- (VCPanel *)_owningPanel {
    UIView *view = self;
    while (view) {
        if ([view isKindOfClass:[VCPanel class]]) return (VCPanel *)view;
        view = view.superview;
    }
    return nil;
}

- (void)_hidePanelForExternalDocumentIfNeeded {
    VCPanel *panel = [self _owningPanel];
    if (!panel || !panel.isVisible) return;
    self.panelHiddenForExternalDocument = YES;
    [panel hideAnimated];
}

- (void)_restorePanelAfterExternalDocumentIfNeeded {
    if (!self.panelHiddenForExternalDocument) return;
    self.panelHiddenForExternalDocument = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        VCPanel *panel = [self _owningPanel];
        [panel showAnimated];
    });
}

- (void)_presentProviderAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIViewController *host = [self _preferredExternalPresenterViewController];
    if (!host) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @""
                                                                   message:message ?: @""
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak __typeof__(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:VCTextLiteral(@"OK")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        __strong __typeof__(weakSelf) self2 = weakSelf;
        [self2 _restorePanelAfterExternalDocumentIfNeeded];
    }]];
    [host presentViewController:alert animated:YES completion:nil];
}

- (NSString *)_sanitizedProviderFilenameComponent:(NSString *)name {
    NSMutableString *result = [NSMutableString new];
    NSString *source = VCSettingsSafeString(name).length > 0 ? VCSettingsSafeString(name) : @"provider";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"];
    for (NSUInteger idx = 0; idx < source.length; idx++) {
        unichar ch = [source characterAtIndex:idx];
        if ([allowed characterIsMember:ch]) {
            [result appendFormat:@"%C", ch];
        } else if (result.length == 0 || ![result hasSuffix:@"-"]) {
            [result appendString:@"-"];
        }
    }
    NSString *trimmed = [result stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-"]];
    return trimmed.length > 0 ? trimmed : @"provider";
}

- (NSURL *)_temporaryExportURLForProvider:(VCProviderConfig *)provider {
    NSString *directoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"VansonCLIProviderExports"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *filename = [NSString stringWithFormat:@"%@.%@", [self _sanitizedProviderFilenameComponent:provider.name], [VCProviderConfig portableFileExtension]];
    return [NSURL fileURLWithPath:[directoryPath stringByAppendingPathComponent:filename]];
}

- (void)_exportProviderConfig:(VCProviderConfig *)provider sourceView:(UIView *)sourceView {
    if (!provider) return;

    NSDictionary *payload = [provider portableExportDictionary];
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:&error];
    if (!jsonData || error) {
        [self _presentProviderAlertWithTitle:VCTextLiteral(@"Export Failed")
                                     message:VCTextLiteral(@"VansonCLI could not create the provider config file.")];
        return;
    }

    NSURL *fileURL = [self _temporaryExportURLForProvider:provider];
    if (![jsonData writeToURL:fileURL options:NSDataWritingAtomic error:&error] || error) {
        [self _presentProviderAlertWithTitle:VCTextLiteral(@"Export Failed")
                                     message:VCTextLiteral(@"VansonCLI could not write the provider config file.")];
        return;
    }

    UIViewController *host = [self _preferredExternalPresenterViewController];
    if (!host) return;

    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    __weak __typeof__(self) weakSelf = self;
    activity.completionWithItemsHandler = ^(__unused UIActivityType activityType,
                                            __unused BOOL completed,
                                            __unused NSArray *returnedItems,
                                            __unused NSError *activityError) {
        __strong __typeof__(weakSelf) self2 = weakSelf;
        if (!self2) return;
        [self2 _resumeOverlayInteractionAfterExternalModalIfNeeded];
        [self2 _restorePanelAfterExternalDocumentIfNeeded];
    };
    if (activity.popoverPresentationController) {
        UIView *anchorView = host.view ?: sourceView ?: self.createButton;
        activity.popoverPresentationController.sourceView = anchorView;
        activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(anchorView.bounds),
                                                                       CGRectGetMidY(anchorView.bounds),
                                                                       1.0,
                                                                       1.0);
    }

    BOOL shouldDelayPresentation = NO;
    VCPanel *panel = [self _owningPanel];
    if (panel && panel.isVisible) {
        [self _hidePanelForExternalDocumentIfNeeded];
        shouldDelayPresentation = YES;
    }

    void (^presentActivity)(void) = ^{
        __strong __typeof__(weakSelf) self2 = weakSelf;
        if (!self2) return;
        [self2 _suspendOverlayInteractionForExternalModalIfNeeded];
        [host presentViewController:activity animated:YES completion:nil];
    };

    if (shouldDelayPresentation) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.24 * NSEC_PER_SEC)), dispatch_get_main_queue(), presentActivity);
    } else {
        presentActivity();
    }
}

- (VCProviderConfig *)_providerMatchingImportedProvider:(VCProviderConfig *)provider {
    if (!provider) return nil;

    VCProviderManager *manager = [VCProviderManager shared];
    NSString *providerID = [VCSettingsSafeString(provider.providerID) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (providerID.length > 0) {
        VCProviderConfig *exact = [manager providerForID:providerID];
        if (exact) return exact;
    }

    NSString *importedName = [VCSettingsSafeString(provider.name) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    for (VCProviderConfig *candidate in [manager allProviders]) {
        NSString *candidateName = [VCSettingsSafeString(candidate.name) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
        if (VCSettingsProviderIsOpenAIOnly(candidate) && importedName.length > 0 && [candidateName isEqualToString:importedName]) {
            return candidate;
        }
    }
    return nil;
}

- (void)_applyImportedProvider:(VCProviderConfig *)provider {
    if (!provider || provider.name.length == 0 || provider.endpoint.length == 0) {
        [self _presentProviderAlertWithTitle:VCTextLiteral(@"Import Failed")
                                     message:VCTextLiteral(@"That file does not contain a valid provider config.")];
        return;
    }

    VCProviderManager *manager = [VCProviderManager shared];
    VCProviderConfig *existing = [self _providerMatchingImportedProvider:provider];
    VCProviderConfig *resolved = nil;

    if (existing) {
        resolved = [existing copy];
        resolved.name = provider.name;
        resolved.endpoint = provider.endpoint;
        resolved.apiVersion = provider.apiVersion;
        resolved.apiKey = provider.apiKey;
        resolved.protocol = (provider.protocol == VCAPIProtocolOpenAI) ? VCAPIProtocolOpenAI : VCAPIProtocolOpenAIResponses;
        resolved.rolePreset = provider.rolePreset;
        resolved.models = provider.models.count > 0 ? provider.models : existing.models;
        resolved.selectedModel = provider.selectedModel.length > 0 ? provider.selectedModel : existing.selectedModel;
        resolved.maxTokens = provider.maxTokens;
        resolved.reasoningEffort = provider.reasoningEffort;
        resolved.sortOrder = existing.sortOrder;
        resolved.isBuiltin = existing.isBuiltin;
        [manager updateProvider:resolved];
    } else {
        resolved = [provider copy];
        resolved.providerID = resolved.providerID.length > 0 ? resolved.providerID : [[NSUUID UUID] UUIDString];
        resolved.protocol = (resolved.protocol == VCAPIProtocolOpenAI) ? VCAPIProtocolOpenAI : VCAPIProtocolOpenAIResponses;
        resolved.sortOrder = manager.allProviders.count;
        resolved.isBuiltin = NO;
        [manager addProvider:resolved];
    }

    [manager setActiveProviderID:resolved.providerID];
    [self reload];
    [self _restorePanelAfterExternalDocumentIfNeeded];
    [self _showChatPromptIfNeededForProvider:resolved];
}

- (void)_importProviderConfigFromURL:(NSURL *)url {
    if (![url isKindOfClass:[NSURL class]]) return;

    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (accessed) {
        [url stopAccessingSecurityScopedResource];
    }
    if (!data || error) {
        [self _presentProviderAlertWithTitle:VCTextLiteral(@"Import Failed")
                                     message:VCTextLiteral(@"VansonCLI could not read that config file.")];
        return;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![json isKindOfClass:[NSDictionary class]] || error) {
        [self _presentProviderAlertWithTitle:VCTextLiteral(@"Import Failed")
                                     message:VCTextLiteral(@"That file is not a valid VansonCLI model config.")];
        return;
    }

    VCProviderConfig *provider = [VCProviderConfig fromPortableImportDictionary:(NSDictionary *)json];
    [self _applyImportedProvider:provider];
}

- (void)_importProviderConfig {
    UIViewController *host = [self _preferredExternalPresenterViewController];
    if (!host) return;

    NSMutableArray<UTType *> *types = [NSMutableArray new];
    UTType *portableType = [UTType typeWithFilenameExtension:[VCProviderConfig portableFileExtension]];
    if (portableType) [types addObject:portableType];
    [types addObject:UTTypeJSON];
    [types addObject:UTTypeData];

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    BOOL shouldDelayPresentation = NO;
    VCPanel *panel = [self _owningPanel];
    if (panel.isVisible) {
        [self _hidePanelForExternalDocumentIfNeeded];
        shouldDelayPresentation = YES;
    }

    __weak __typeof__(self) weakSelf = self;
    void (^presentPicker)(void) = ^{
        __strong __typeof__(weakSelf) self2 = weakSelf;
        if (!self2) return;
        [self2 _suspendOverlayInteractionForExternalModalIfNeeded];
        [host presentViewController:picker animated:YES completion:nil];
    };

    if (shouldDelayPresentation) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.24 * NSEC_PER_SEC)), dispatch_get_main_queue(), presentPicker);
    } else {
        presentPicker();
    }
}

- (NSArray<NSString *> *)_sanitizedModelNamesFromArray:(NSArray<NSString *> *)models {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id candidate in models ?: @[]) {
        if (![candidate isKindOfClass:[NSString class]]) continue;
        NSString *trimmed = [candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        NSString *lookupKey = trimmed.lowercaseString;
        if ([seen containsObject:lookupKey]) continue;
        [seen addObject:lookupKey];
        [result addObject:trimmed];
    }
    return result;
}

- (void)_setEditorStatusText:(NSString *)text color:(UIColor *)color {
    self.editorStatusLabel.text = text ?: @"";
    self.editorStatusLabel.textColor = color ?: kVCTextSecondary;
}

- (id<VCAIAdapter>)_adapterForEditorProtocol:(VCAPIProtocol)protocol {
    NSString *className = nil;
    switch (protocol) {
        case VCAPIProtocolOpenAI:
        case VCAPIProtocolOpenAIResponses:
            className = @"VCOpenAIAdapter";
            break;
        case VCAPIProtocolAnthropic:
            className = @"VCAnthropicAdapter";
            break;
        case VCAPIProtocolGemini:
            className = @"VCGeminiAdapter";
            break;
    }
    Class adapterClass = className.length ? NSClassFromString(className) : Nil;
    if (!adapterClass) return nil;
    return [(id)adapterClass new];
}

- (VCAPIProtocol)_editorSelectedProtocol {
    NSInteger providerIndex = MAX(0, MIN((NSInteger)self.protocolControl.numberOfSegments - 1, self.protocolControl.selectedSegmentIndex));
    NSInteger wireModeIndex = MAX(0, MIN((NSInteger)self.wireModeControl.numberOfSegments - 1, self.wireModeControl.selectedSegmentIndex));
    return VCSettingsProtocolFromEditorSelection(providerIndex, wireModeIndex);
}

- (void)_applyProtocolToEditorControls:(VCAPIProtocol)protocol {
    self.protocolControl.selectedSegmentIndex = VCSettingsProviderFamilyIndexForProtocol(protocol);
    self.wireModeControl.selectedSegmentIndex = VCSettingsWireModeIndexForProtocol(protocol);
    [self _updateWireModeVisibility];
    [self _refreshEndpointFieldGuidance];
}

- (void)_updateWireModeVisibility {
    self.protocolControl.hidden = YES;
    self.wireModeLabel.hidden = NO;
    self.wireModeControl.hidden = NO;
    [self setNeedsLayout];
}

- (void)_providerFamilyChanged {
    [self _updateWireModeVisibility];
    [self _refreshEndpointFieldGuidance];
}

- (NSString *)_normalizedEndpointString:(NSString *)endpoint forProtocol:(VCAPIProtocol)protocol {
    NSString *trimmed = [VCSettingsSafeString(endpoint) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return @"";

    while ([trimmed hasSuffix:@"/"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
    if (components.scheme.length == 0 || components.host.length == 0) {
        return trimmed;
    }

    NSString *path = components.path ?: @"";
    NSString *lowerPath = path.lowercaseString ?: @"";
    NSArray<NSString *> *knownSuffixes = nil;
    switch (protocol) {
        case VCAPIProtocolOpenAI:
        case VCAPIProtocolOpenAIResponses:
            knownSuffixes = @[@"/v1/chat/completions", @"/v1/responses", @"/v1/models"];
            break;
        case VCAPIProtocolAnthropic:
            knownSuffixes = @[@"/v1/messages", @"/messages"];
            break;
        case VCAPIProtocolGemini:
            knownSuffixes = @[@"/v1beta/models", @"/v1/models"];
            break;
    }

    for (NSString *suffix in knownSuffixes ?: @[]) {
        if ([lowerPath hasSuffix:suffix]) {
            path = [path substringToIndex:path.length - suffix.length];
            lowerPath = path.lowercaseString ?: @"";
            break;
        }
    }

    while (path.length > 1 && [path hasSuffix:@"/"]) {
        path = [path substringToIndex:path.length - 1];
    }
    components.path = path;
    components.query = nil;
    components.fragment = nil;
    return components.string ?: trimmed;
}

- (void)_refreshEndpointFieldGuidance {
    if (!self.endpointField) return;

    VCAPIProtocol protocol = [self _editorSelectedProtocol];
    NSString *placeholder = VCTextLiteral(@"Endpoint URL");
    NSString *hint = VCTextLiteral(@"Fill the OpenAI endpoint and API key, choose Chat or Responses, then sync or type a model.");

    switch (protocol) {
        case VCAPIProtocolOpenAI:
            placeholder = @"Base URL (e.g. https://api.openai.com)";
            hint = @"Use only the base URL. The app adds /v1/chat/completions and /v1/models.";
            break;
        case VCAPIProtocolOpenAIResponses:
            placeholder = @"Base URL (e.g. https://api.openai.com)";
            hint = @"Use only the base URL. The app adds /v1/responses and /v1/models.";
            break;
        case VCAPIProtocolAnthropic:
        case VCAPIProtocolGemini:
            placeholder = @"Base URL (e.g. https://api.openai.com)";
            hint = @"Use only the OpenAI base URL. The app adds the request path.";
            break;
    }

    VCApplyReadablePlaceholder(self.endpointField, placeholder);
    VCApplyReadablePlaceholder(self.apiVersionField, @"/v1");
    self.editorHintLabel.text = hint;

    NSString *normalized = [self _normalizedEndpointString:self.endpointField.text forProtocol:protocol];
    if (normalized.length > 0 && ![normalized isEqualToString:self.endpointField.text]) {
        self.endpointField.text = normalized;
    }
    [self _refreshDebugEndpointLabel];
}

- (void)_updateEditorActionState {
    NSString *providerID = VCSettingsSafeString(self.editingProvider.providerID);
    NSString *activeProviderID = VCSettingsSafeString([[VCProviderManager shared] activeProvider].providerID);
    BOOL hasProviderIdentity = providerID.length > 0;
    BOOL isActive = hasProviderIdentity && [providerID isEqualToString:activeProviderID];
    BOOL isBuiltin = self.editingProvider.isBuiltin;

    self.deleteButton.hidden = self.editorCreatesProvider || !hasProviderIdentity || isBuiltin;
    self.activateButton.hidden = NO;
    [self.activateButton setTitle:(isActive ? VCTextLiteral(@"Active") : VCTextLiteral(@"Activate")) forState:UIControlStateNormal];
    self.activateButton.backgroundColor = isActive ? kVCGreenDim : UIColorFromHex(0x133b2f);
    self.activateButton.layer.borderColor = (isActive ? [kVCGreen colorWithAlphaComponent:0.32] : kVCBorderAccent).CGColor;
    self.activateButton.enabled = !isActive;
    self.activateButton.alpha = isActive ? 0.86 : 1.0;

    NSString *scopeText = self.editorCreatesProvider ? VCTextLiteral(@"Draft provider") : (isBuiltin ? VCTextLiteral(@"Built-in provider") : VCTextLiteral(@"Custom provider"));
    NSString *activeText = isActive ? VCTextLiteral(@"Active in AI Chat") : VCTextLiteral(@"Not active yet");
    [self _setEditorStatusText:[NSString stringWithFormat:@"%@ · %@", scopeText, activeText]
                         color:(isActive ? kVCGreen : kVCTextSecondary)];
}

- (UITextField *)_editorField:(NSString *)placeholder secure:(BOOL)secure {
    UITextField *field = [[UITextField alloc] init];
    VCApplyReadablePlaceholder(field, placeholder);
    field.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    field.textColor = kVCTextPrimary;
    field.backgroundColor = kVCBgInput;
    field.secureTextEntry = secure;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    if (@available(iOS 11.0, *)) {
        field.smartQuotesType = UITextSmartQuotesTypeNo;
        field.smartDashesType = UITextSmartDashesTypeNo;
        field.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
    }
    if (@available(iOS 12.0, *)) {
        field.textContentType = secure ? UITextContentTypePassword : @"";
    }
    field.layer.cornerRadius = 12.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = kVCBorder.CGColor;
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    field.leftViewMode = UITextFieldViewModeAlways;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.heightAnchor constraintEqualToConstant:38].active = YES;
    return field;
}

- (UITextView *)_editorTextViewWithPlaceholder:(NSString *)placeholder {
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectZero];
    textView.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    textView.textColor = kVCTextPrimary;
    textView.backgroundColor = kVCBgInput;
    textView.autocorrectionType = UITextAutocorrectionTypeNo;
    textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textView.spellCheckingType = UITextSpellCheckingTypeNo;
    textView.layer.cornerRadius = 12.0;
    textView.layer.borderWidth = 1.0;
    textView.layer.borderColor = kVCBorder.CGColor;
    textView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    textView.accessibilityLabel = placeholder;
    return textView;
}

- (NSString *)_apiVersionFromEditor {
    NSString *version = [self.apiVersionField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (version.length == 0) return @"/v1";
    if (![version hasPrefix:@"/"]) version = [@"/" stringByAppendingString:version];
    while (version.length > 1 && [version hasSuffix:@"/"]) {
        version = [version substringToIndex:version.length - 1];
    }
    return version;
}

- (NSString *)_terminalPathForProtocol:(VCAPIProtocol)protocol {
    return protocol == VCAPIProtocolOpenAIResponses ? @"/responses" : @"/chat/completions";
}

- (NSString *)_debugEndpointForEndpoint:(NSString *)endpoint apiVersion:(NSString *)apiVersion protocol:(VCAPIProtocol)protocol {
    NSString *base = [self _normalizedEndpointString:endpoint forProtocol:protocol];
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    NSString *version = apiVersion.length > 0 ? apiVersion : @"/v1";
    NSString *terminal = [self _terminalPathForProtocol:protocol];
    if (base.length == 0) return [version stringByAppendingString:terminal];
    NSString *lowerBase = base.lowercaseString ?: @"";
    NSString *lowerVersion = version.lowercaseString ?: @"";
    if (lowerVersion.length > 0 && [lowerBase hasSuffix:lowerVersion]) {
        return [base stringByAppendingString:terminal];
    }
    return [[base stringByAppendingString:version] stringByAppendingString:terminal];
}

- (void)_refreshDebugEndpointLabel {
    VCAPIProtocol protocol = [self _editorSelectedProtocol];
    NSString *debugEndpoint = [self _debugEndpointForEndpoint:self.endpointField.text
                                                   apiVersion:[self _apiVersionFromEditor]
                                                     protocol:protocol];
    self.debugEndpointLabel.text = debugEndpoint.length > 0 ? debugEndpoint : VCTextLiteral(@"Debug endpoint will appear here.");
}

- (NSString *)_reasoningEffortFromEditor {
    switch (self.reasoningControl.selectedSegmentIndex) {
        case 1: return @"low";
        case 2: return @"medium";
        case 3: return @"high";
        default: return @"off";
    }
}

- (void)_applyReasoningEffortToEditor:(NSString *)effort {
    NSString *value = VCSettingsSafeString(effort).lowercaseString;
    if ([value isEqualToString:@"low"]) self.reasoningControl.selectedSegmentIndex = 1;
    else if ([value isEqualToString:@"medium"]) self.reasoningControl.selectedSegmentIndex = 2;
    else if ([value isEqualToString:@"high"]) self.reasoningControl.selectedSegmentIndex = 3;
    else self.reasoningControl.selectedSegmentIndex = 0;
}

- (void)_appendEditorCallLogLine:(NSString *)line {
    NSString *text = VCSettingsSafeString(line);
    if (text.length == 0 || !self.callLogTextView) return;
    NSString *existing = self.callLogTextView.text ?: @"";
    self.callLogTextView.text = existing.length > 0 ? [existing stringByAppendingFormat:@"\n%@", text] : text;
}

- (NSArray<NSString *> *)_sanitizedModelNamesFromText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        return @[];
    }
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",\n\r"];
    return [self _sanitizedModelNamesFromArray:[text componentsSeparatedByCharactersInSet:separators]];
}

- (void)_setupSimpleEditorOverlay {
    if (self.editorOverlay) return;

    self.editorUsesSimpleSheet = YES;

    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.hidden = YES;
    overlay.alpha = 0.0;
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    [self addSubview:overlay];
    self.editorOverlay = overlay;

    UIControl *backdrop = [[UIControl alloc] init];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addTarget:self action:@selector(_hideProviderEditor) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:backdrop];

    self.editorCard = [[UIView alloc] init];
    self.editorCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.editorCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    self.editorCard.layer.cornerRadius = 20.0;
    self.editorCard.layer.borderWidth = 1.0;
    self.editorCard.layer.borderColor = kVCBorderStrong.CGColor;
    self.editorCard.layer.shadowColor = [UIColor blackColor].CGColor;
    self.editorCard.layer.shadowOpacity = 0.24;
    self.editorCard.layer.shadowRadius = 18.0;
    self.editorCard.layer.shadowOffset = CGSizeMake(0, -6.0);
    [overlay addSubview:self.editorCard];

    self.simpleEditorCardLeadingConstraint = [self.editorCard.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:10.0];
    self.simpleEditorCardTopConstraint = [self.editorCard.topAnchor constraintEqualToAnchor:overlay.topAnchor constant:10.0];
    self.simpleEditorCardWidthConstraint = [self.editorCard.widthAnchor constraintEqualToConstant:320.0];
    self.simpleEditorCardHeightConstraint = [self.editorCard.heightAnchor constraintEqualToConstant:420.0];

    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [backdrop.topAnchor constraintEqualToAnchor:overlay.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],

        self.simpleEditorCardLeadingConstraint,
        self.simpleEditorCardTopConstraint,
        self.simpleEditorCardWidthConstraint,
        self.simpleEditorCardHeightConstraint,
    ]];

    self.editorCardScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.editorCardScrollView.alwaysBounceVertical = YES;
    self.editorCardScrollView.showsVerticalScrollIndicator = YES;
    self.editorCardScrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.editorCardScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.editorCard addSubview:self.editorCardScrollView];

    self.editorActionBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.editorActionBar.backgroundColor = [kVCBgSecondary colorWithAlphaComponent:0.94];
    self.editorActionBar.layer.cornerRadius = 18.0;
    self.editorActionBar.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    [self.editorCard addSubview:self.editorActionBar];

    self.editorActionBarDivider = [[UIView alloc] initWithFrame:CGRectZero];
    self.editorActionBarDivider.backgroundColor = kVCBorderStrong;
    [self.editorActionBar addSubview:self.editorActionBarDivider];

    self.editorHandle = [[UIView alloc] initWithFrame:CGRectZero];
    self.editorHandle.backgroundColor = kVCTextMuted;
    self.editorHandle.layer.cornerRadius = 2.0;
    [self.editorCardScrollView addSubview:self.editorHandle];

    self.editorTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.editorTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.editorTitleLabel.textColor = kVCTextPrimary;
    [self.editorCardScrollView addSubview:self.editorTitleLabel];

    self.editorCloseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.editorCloseButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(self.editorCloseButton);
    self.editorCloseButton.tintColor = kVCTextMuted;
    [self.editorCloseButton addTarget:self action:@selector(_hideProviderEditor) forControlEvents:UIControlEventTouchUpInside];
    [self.editorCardScrollView addSubview:self.editorCloseButton];

    self.editorHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.editorHintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.editorHintLabel.textColor = kVCTextSecondary;
    self.editorHintLabel.numberOfLines = 2;
    [self.editorCardScrollView addSubview:self.editorHintLabel];

    self.editorStatusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.editorStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.editorStatusLabel.textColor = kVCTextSecondary;
    self.editorStatusLabel.numberOfLines = 2;
    [self.editorCardScrollView addSubview:self.editorStatusLabel];

    UILabel *(^makeSectionLabel)(NSString *) = ^UILabel *(NSString *text) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = text;
        label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        label.textColor = kVCTextSecondary;
        return label;
    };

    self.providerLabel = makeSectionLabel(VCTextLiteral(@"Provider"));
    [self.editorCardScrollView addSubview:self.providerLabel];

    self.connectionSectionLabel = makeSectionLabel(VCTextLiteral(@"API Connection"));
    [self.editorCardScrollView addSubview:self.connectionSectionLabel];

    self.connectionSectionHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.connectionSectionHintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.connectionSectionHintLabel.textColor = kVCTextSecondary;
    self.connectionSectionHintLabel.numberOfLines = 2;
    self.connectionSectionHintLabel.text = VCTextLiteral(@"Base URL, API version, endpoint mode, and credentials.");
    [self.editorCardScrollView addSubview:self.connectionSectionHintLabel];

    self.protocolControl = [[UISegmentedControl alloc] initWithItems:@[@"OpenAI"]];
    self.protocolControl.selectedSegmentTintColor = kVCAccent;
    [self.protocolControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [self.protocolControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    [self.protocolControl addTarget:self action:@selector(_providerFamilyChanged) forControlEvents:UIControlEventValueChanged];
    [self.editorCardScrollView addSubview:self.protocolControl];

    self.wireModeLabel = makeSectionLabel(VCTextLiteral(@"Endpoint Mode"));
    [self.editorCardScrollView addSubview:self.wireModeLabel];

    self.wireModeControl = [[UISegmentedControl alloc] initWithItems:@[@"Chat", @"Responses"]];
    self.wireModeControl.selectedSegmentTintColor = kVCAccent;
    [self.wireModeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [self.wireModeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    [self.wireModeControl addTarget:self action:@selector(_providerFamilyChanged) forControlEvents:UIControlEventValueChanged];
    [self.editorCardScrollView addSubview:self.wireModeControl];

    self.nameField = [self _editorField:VCTextLiteral(@"Provider name") secure:NO];
    self.nameField.translatesAutoresizingMaskIntoConstraints = YES;
    [self.editorCardScrollView addSubview:self.nameField];

    self.endpointField = [self _editorField:VCTextLiteral(@"Endpoint URL") secure:NO];
    self.endpointField.keyboardType = UIKeyboardTypeURL;
    self.endpointField.translatesAutoresizingMaskIntoConstraints = YES;
    [self.endpointField addTarget:self action:@selector(_providerFamilyChanged) forControlEvents:UIControlEventEditingChanged];
    [self.editorCardScrollView addSubview:self.endpointField];

    self.apiVersionField = [self _editorField:VCTextLiteral(@"API Version") secure:NO];
    self.apiVersionField.translatesAutoresizingMaskIntoConstraints = YES;
    [self.apiVersionField addTarget:self action:@selector(_providerFamilyChanged) forControlEvents:UIControlEventEditingChanged];
    [self.editorCardScrollView addSubview:self.apiVersionField];

    self.apiKeyField = [self _editorField:VCTextLiteral(@"API key") secure:YES];
    self.apiKeyField.translatesAutoresizingMaskIntoConstraints = YES;
    [self.editorCardScrollView addSubview:self.apiKeyField];

    self.debugEndpointLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.debugEndpointLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
    self.debugEndpointLabel.textColor = kVCTextSecondary;
    self.debugEndpointLabel.numberOfLines = 2;
    self.debugEndpointLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.debugEndpointLabel.backgroundColor = [kVCBgInput colorWithAlphaComponent:0.72];
    self.debugEndpointLabel.layer.cornerRadius = 10.0;
    self.debugEndpointLabel.layer.borderWidth = 1.0;
    self.debugEndpointLabel.layer.borderColor = kVCBorder.CGColor;
    self.debugEndpointLabel.clipsToBounds = YES;
    [self.editorCardScrollView addSubview:self.debugEndpointLabel];

    self.rolePresetLabel = makeSectionLabel(VCTextLiteral(@"AI Role Preset"));
    [self.editorCardScrollView addSubview:self.rolePresetLabel];

    self.rolePresetTextView = [self _editorTextViewWithPlaceholder:VCTextLiteral(@"Optional system role preset")];
    [self.editorCardScrollView addSubview:self.rolePresetTextView];

    self.modelsSectionLabel = makeSectionLabel(VCTextLiteral(@"Models"));
    [self.editorCardScrollView addSubview:self.modelsSectionLabel];

    self.modelsSectionHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.modelsSectionHintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.modelsSectionHintLabel.textColor = kVCTextSecondary;
    self.modelsSectionHintLabel.numberOfLines = 2;
    self.modelsSectionHintLabel.text = VCTextLiteral(@"Keep one default model selected and add fallbacks only when you really use them.");
    [self.editorCardScrollView addSubview:self.modelsSectionHintLabel];

    self.advancedSectionLabel = makeSectionLabel(VCTextLiteral(@"Advanced"));
    [self.editorCardScrollView addSubview:self.advancedSectionLabel];

    self.advancedSectionHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.advancedSectionHintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.advancedSectionHintLabel.textColor = kVCTextSecondary;
    self.advancedSectionHintLabel.numberOfLines = 2;
    self.advancedSectionHintLabel.text = VCTextLiteral(@"Token limits, GPT reasoning depth, fetch models, and test calls.");
    [self.editorCardScrollView addSubview:self.advancedSectionHintLabel];

    self.maxTokensField = [self _editorField:VCTextLiteral(@"Token Limit") secure:NO];
    self.maxTokensField.keyboardType = UIKeyboardTypeNumberPad;
    self.maxTokensField.translatesAutoresizingMaskIntoConstraints = YES;
    [self.editorCardScrollView addSubview:self.maxTokensField];

    self.reasoningLabel = makeSectionLabel(VCTextLiteral(@"Reasoning Depth (GPT)"));
    [self.editorCardScrollView addSubview:self.reasoningLabel];

    self.reasoningControl = [[UISegmentedControl alloc] initWithItems:@[VCTextLiteral(@"Off"), @"low", @"medium", @"high"]];
    self.reasoningControl.selectedSegmentTintColor = kVCAccent;
    [self.reasoningControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary, NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]} forState:UIControlStateNormal];
    [self.reasoningControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    [self.editorCardScrollView addSubview:self.reasoningControl];

    self.testProviderButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.testProviderButton setTitle:VCTextLiteral(@"Test Call") forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(self.testProviderButton);
    self.testProviderButton.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    VCApplyCompactIconTitleButtonLayout(self.testProviderButton, @"bolt.horizontal", 11.0);
    [self.testProviderButton addTarget:self action:@selector(_testProviderFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [self.editorCardScrollView addSubview:self.testProviderButton];

    self.callLogLabel = makeSectionLabel(VCTextLiteral(@"Call Log"));
    [self.editorCardScrollView addSubview:self.callLogLabel];

    self.callLogTextView = [self _editorTextViewWithPlaceholder:VCTextLiteral(@"Call logs")];
    self.callLogTextView.editable = NO;
    self.callLogTextView.textColor = kVCTextSecondary;
    [self.editorCardScrollView addSubview:self.callLogTextView];

    self.modelInputField = [self _editorField:VCTextLiteral(@"Add model") secure:NO];
    self.modelInputField.returnKeyType = UIReturnKeyDone;
    self.modelInputField.delegate = self;
    self.modelInputField.translatesAutoresizingMaskIntoConstraints = YES;
    [self.editorCardScrollView addSubview:self.modelInputField];

    self.addModelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.addModelButton setTitle:VCTextLiteral(@"Add") forState:UIControlStateNormal];
    VCApplyCompactPrimaryButtonStyle(self.addModelButton);
    [self.addModelButton addTarget:self action:@selector(_addModelFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [self.editorCardScrollView addSubview:self.addModelButton];

    self.syncModelsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.syncModelsButton setTitle:VCTextLiteral(@"Sync") forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(self.syncModelsButton);
    self.syncModelsButton.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    VCApplyCompactIconTitleButtonLayout(self.syncModelsButton, @"arrow.clockwise", 11.0);
    [self.syncModelsButton addTarget:self action:@selector(_syncModelsFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [self.editorCardScrollView addSubview:self.syncModelsButton];

    self.modelsScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.modelsScrollView.backgroundColor = [kVCBgInput colorWithAlphaComponent:0.68];
    self.modelsScrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.modelsScrollView.layer.cornerRadius = 12.0;
    self.modelsScrollView.layer.borderWidth = 1.0;
    self.modelsScrollView.layer.borderColor = kVCBorder.CGColor;
    self.modelsScrollView.translatesAutoresizingMaskIntoConstraints = YES;
    [self.editorCardScrollView addSubview:self.modelsScrollView];

    self.modelsScrollContentView = [[UIView alloc] initWithFrame:CGRectZero];
    self.modelsScrollContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modelsScrollView addSubview:self.modelsScrollContentView];

    self.modelsListStack = [[UIStackView alloc] init];
    self.modelsListStack.axis = UILayoutConstraintAxisVertical;
    self.modelsListStack.spacing = 8.0;
    self.modelsListStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modelsScrollContentView addSubview:self.modelsListStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.modelsScrollContentView.topAnchor constraintEqualToAnchor:self.modelsScrollView.contentLayoutGuide.topAnchor],
        [self.modelsScrollContentView.leadingAnchor constraintEqualToAnchor:self.modelsScrollView.contentLayoutGuide.leadingAnchor],
        [self.modelsScrollContentView.trailingAnchor constraintEqualToAnchor:self.modelsScrollView.contentLayoutGuide.trailingAnchor],
        [self.modelsScrollContentView.bottomAnchor constraintEqualToAnchor:self.modelsScrollView.contentLayoutGuide.bottomAnchor],
        [self.modelsScrollContentView.widthAnchor constraintEqualToAnchor:self.modelsScrollView.frameLayoutGuide.widthAnchor],
        [self.modelsScrollContentView.heightAnchor constraintGreaterThanOrEqualToAnchor:self.modelsScrollView.frameLayoutGuide.heightAnchor],

        [self.modelsListStack.topAnchor constraintEqualToAnchor:self.modelsScrollContentView.topAnchor constant:10],
        [self.modelsListStack.leadingAnchor constraintEqualToAnchor:self.modelsScrollContentView.leadingAnchor constant:10],
        [self.modelsListStack.trailingAnchor constraintEqualToAnchor:self.modelsScrollContentView.trailingAnchor constant:-10],
        [self.modelsListStack.bottomAnchor constraintEqualToAnchor:self.modelsScrollContentView.bottomAnchor constant:-10],
    ]];

    self.editorCancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.editorCancelButton setTitle:VCTextLiteral(@"Cancel") forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(self.editorCancelButton);
    [self.editorCancelButton addTarget:self action:@selector(_hideProviderEditor) forControlEvents:UIControlEventTouchUpInside];
    [self.editorActionBar addSubview:self.editorCancelButton];

    self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.deleteButton setTitle:VCTextLiteral(@"Delete") forState:UIControlStateNormal];
    VCApplyDangerButtonStyle(self.deleteButton);
    [self.deleteButton addTarget:self action:@selector(_deleteProviderFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [self.editorActionBar addSubview:self.deleteButton];

    self.activateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.activateButton setTitle:VCTextLiteral(@"Activate") forState:UIControlStateNormal];
    VCApplyPositiveButtonStyle(self.activateButton);
    [self.activateButton addTarget:self action:@selector(_activateProviderFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [self.editorActionBar addSubview:self.activateButton];

    self.primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.primaryButton setTitle:VCTextLiteral(@"Save") forState:UIControlStateNormal];
    VCApplyPrimaryButtonStyle(self.primaryButton);
    [self.primaryButton addTarget:self action:@selector(_saveProviderFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [self.editorActionBar addSubview:self.primaryButton];

    self.protocolControl.selectedSegmentIndex = 0;
    self.wireModeControl.selectedSegmentIndex = 0;
    [self _updateWireModeVisibility];
    VCInstallKeyboardDismissAccessory(self.editorOverlay);
}

- (NSArray<UIButton *> *)_visibleSimpleEditorActionButtons {
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (UIButton *button in @[self.editorCancelButton, self.deleteButton, self.activateButton, self.primaryButton]) {
        if ([button isKindOfClass:[UIButton class]] && !button.hidden) {
            [buttons addObject:button];
        }
    }
    return [buttons copy];
}

- (void)_layoutSimpleEditorOverlay {
    if (!self.editorUsesSimpleSheet || !self.editorOverlay || !self.editorCard) return;

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    BOOL landscape = (width > height);
    self.editorOverlay.frame = self.bounds;

    CGFloat cardWidth = landscape ? MIN(MAX(width * 0.54, 440.0), 620.0) : (width - 20.0);
    CGFloat cardHeight = landscape
        ? MAX(320.0, height - 20.0)
        : MIN(MAX(height * 0.82, 470.0), MAX(420.0, height - 24.0));
    CGFloat cardX = landscape
        ? (self.editorOverlay.hidden ? width + 20.0 : width - cardWidth - 10.0)
        : 10.0;
    CGFloat cardY = landscape
        ? 10.0
        : (self.editorOverlay.hidden ? (height + 20.0) : (height - cardHeight - 10.0));
    self.simpleEditorCardLeadingConstraint.constant = cardX;
    self.simpleEditorCardTopConstraint.constant = cardY;
    self.simpleEditorCardWidthConstraint.constant = cardWidth;
    self.simpleEditorCardHeightConstraint.constant = cardHeight;
    [self.editorOverlay layoutIfNeeded];

    CGFloat inset = 14.0;
    CGFloat contentWidth = CGRectGetWidth(self.editorCard.bounds) - inset * 2.0;
    NSArray<UIButton *> *visibleButtons = [self _visibleSimpleEditorActionButtons];
    BOOL canFitActionsHorizontally = visibleButtons.count <= 4 && contentWidth >= (landscape ? 360.0 : 440.0);
    BOOL stacksVertically = !canFitActionsHorizontally;
    CGFloat buttonHeight = landscape ? 36.0 : 40.0;
    CGFloat buttonGap = 8.0;
    CGFloat actionBarHeight = stacksVertically
        ? MAX(64.0, 18.0 + (visibleButtons.count * buttonHeight) + (MAX((NSInteger)visibleButtons.count - 1, 0) * buttonGap))
        : (landscape ? 54.0 : 64.0);
    CGFloat scrollHeight = MAX(220.0, CGRectGetHeight(self.editorCard.bounds) - actionBarHeight);
    self.editorCardScrollView.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(self.editorCard.bounds), scrollHeight);
    self.editorActionBar.frame = CGRectMake(0.0, CGRectGetMaxY(self.editorCardScrollView.frame), CGRectGetWidth(self.editorCard.bounds), actionBarHeight);
    self.editorActionBarDivider.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(self.editorActionBar.bounds), 1.0);

    CGFloat y = 20.0;
    self.editorHandle.hidden = landscape;
    self.editorHandle.frame = CGRectMake((CGRectGetWidth(self.editorCard.bounds) - 36.0) * 0.5, 8.0, 36.0, 4.0);
    self.editorCloseButton.frame = CGRectMake(CGRectGetWidth(self.editorCard.bounds) - inset - 24.0, y + 2.0, 24.0, 24.0);
    self.editorTitleLabel.frame = CGRectMake(inset, y, contentWidth - 34.0, 22.0);
    y += 26.0;
    self.editorHintLabel.frame = CGRectMake(inset, y, contentWidth, 30.0);
    y += 30.0;
    self.editorStatusLabel.frame = CGRectMake(inset, y, contentWidth, 32.0);
    y += 38.0;

    self.providerLabel.frame = CGRectMake(inset, y, contentWidth, 16.0);
    self.providerLabel.text = VCTextLiteral(@"Basic Info");
    y += 20.0;
    self.nameField.frame = CGRectMake(inset, y, contentWidth, 38.0);
    y += 50.0;

    self.connectionSectionLabel.frame = CGRectMake(inset, y, contentWidth, 16.0);
    y += 18.0;
    self.connectionSectionHintLabel.frame = CGRectMake(inset, y, contentWidth, 30.0);
    y += 36.0;
    self.protocolControl.frame = CGRectZero;

    self.endpointField.frame = CGRectMake(inset, y, contentWidth, 38.0);
    y += 48.0;
    self.apiVersionField.frame = CGRectMake(inset, y, contentWidth, 38.0);
    y += 48.0;

    BOOL showWireMode = !self.wireModeControl.hidden;
    if (showWireMode) {
        self.wireModeLabel.frame = CGRectMake(inset, y, contentWidth, 16.0);
        y += 20.0;
        self.wireModeControl.frame = CGRectMake(inset, y, contentWidth, 32.0);
        y += 42.0;
    } else {
        self.wireModeLabel.frame = CGRectZero;
        self.wireModeControl.frame = CGRectZero;
    }

    self.apiKeyField.frame = CGRectMake(inset, y, contentWidth, 38.0);
    y += 48.0;
    self.debugEndpointLabel.frame = CGRectMake(inset, y, contentWidth, 42.0);
    y += 52.0;

    self.rolePresetLabel.frame = CGRectMake(inset, y, contentWidth, 16.0);
    y += 20.0;
    self.rolePresetTextView.frame = CGRectMake(inset, y, contentWidth, 82.0);
    y += 94.0;

    self.modelsSectionLabel.frame = CGRectMake(inset, y, contentWidth, 16.0);
    y += 18.0;
    self.modelsSectionHintLabel.frame = CGRectMake(inset, y, contentWidth, 30.0);
    y += 36.0;

    CGFloat addButtonWidth = 72.0;
    BOOL stacksModelInputRow = contentWidth < 360.0;
    if (stacksModelInputRow) {
        self.modelInputField.frame = CGRectMake(inset, y, contentWidth, 38.0);
        y += 46.0;
        self.addModelButton.frame = CGRectMake(inset, y, contentWidth, 38.0);
        y += 48.0;
    } else {
        self.modelInputField.frame = CGRectMake(inset, y, contentWidth - addButtonWidth - 8.0, 38.0);
        self.addModelButton.frame = CGRectMake(CGRectGetMaxX(self.modelInputField.frame) + 8.0, y, addButtonWidth, 38.0);
        y += 48.0;
    }

    self.modelsScrollView.frame = CGRectMake(inset, y, contentWidth, 126.0);
    y += 138.0;

    self.advancedSectionLabel.frame = CGRectMake(inset, y, contentWidth, 16.0);
    y += 18.0;
    self.advancedSectionHintLabel.frame = CGRectMake(inset, y, contentWidth, 30.0);
    y += 38.0;

    BOOL stacksAdvancedInputs = contentWidth < 390.0;
    if (stacksAdvancedInputs) {
        self.maxTokensField.frame = CGRectMake(inset, y, contentWidth, 38.0);
        y += 48.0;
        self.reasoningLabel.frame = CGRectMake(inset, y, contentWidth, 16.0);
        y += 20.0;
        self.reasoningControl.frame = CGRectMake(inset, y, contentWidth, 32.0);
        y += 42.0;
    } else {
        CGFloat maxWidth = floor((contentWidth - 10.0) * 0.34);
        self.maxTokensField.frame = CGRectMake(inset, y + 18.0, maxWidth, 38.0);
        self.reasoningLabel.frame = CGRectMake(CGRectGetMaxX(self.maxTokensField.frame) + 10.0, y, contentWidth - maxWidth - 10.0, 16.0);
        self.reasoningControl.frame = CGRectMake(CGRectGetMaxX(self.maxTokensField.frame) + 10.0, y + 18.0, contentWidth - maxWidth - 10.0, 38.0);
        y += 66.0;
    }

    BOOL stacksActionRow = contentWidth < 360.0;
    if (stacksActionRow) {
        self.syncModelsButton.frame = CGRectMake(inset, y, contentWidth, 34.0);
        y += 42.0;
        self.testProviderButton.frame = CGRectMake(inset, y, contentWidth, 34.0);
        y += 44.0;
    } else {
        CGFloat actionWidth = floor((contentWidth - 8.0) * 0.5);
        self.syncModelsButton.frame = CGRectMake(inset, y, actionWidth, 34.0);
        self.testProviderButton.frame = CGRectMake(CGRectGetMaxX(self.syncModelsButton.frame) + 8.0, y, contentWidth - actionWidth - 8.0, 34.0);
        y += 44.0;
    }

    self.callLogLabel.frame = CGRectMake(inset, y, contentWidth, 16.0);
    y += 20.0;
    self.callLogTextView.frame = CGRectMake(inset, y, contentWidth, 86.0);

    CGFloat actionGap = 8.0;
    if (stacksVertically) {
        CGFloat buttonY = 10.0;
        for (UIButton *button in visibleButtons) {
            button.titleLabel.adjustsFontSizeToFitWidth = YES;
            button.titleLabel.minimumScaleFactor = 0.78;
            button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            button.frame = CGRectMake(inset, buttonY, contentWidth, buttonHeight);
            buttonY += buttonHeight + actionGap;
        }
    } else {
        CGFloat actionWidth = floor((contentWidth - actionGap * MAX((NSInteger)visibleButtons.count - 1, 0)) / MAX((NSInteger)visibleButtons.count, 1));
        CGFloat buttonY = floor((CGRectGetHeight(self.editorActionBar.bounds) - buttonHeight) * 0.5);
        CGFloat buttonX = inset;
        for (UIButton *button in visibleButtons) {
            button.titleLabel.adjustsFontSizeToFitWidth = YES;
            button.titleLabel.minimumScaleFactor = 0.74;
            button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            button.frame = CGRectMake(buttonX, buttonY, actionWidth, buttonHeight);
            buttonX += actionWidth + actionGap;
        }
    }

    CGFloat contentBottom = CGRectGetMaxY(self.callLogTextView.frame) + 16.0;
    self.editorCardScrollView.contentSize = CGSizeMake(CGRectGetWidth(self.editorCard.bounds), MAX(contentBottom, CGRectGetHeight(self.editorCardScrollView.bounds) + 1.0));
}

- (void)_setupEditorOverlay {
    if (_editorOverlay) return;

    _editorOverlay = [[UIView alloc] init];
    _editorOverlay.alpha = 0.0;
    _editorOverlay.hidden = YES;
    _editorOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    _editorOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_editorOverlay];

    UIControl *backdrop = [[UIControl alloc] init];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addTarget:self action:@selector(_hideProviderEditor) forControlEvents:UIControlEventTouchUpInside];
    [_editorOverlay addSubview:backdrop];

    _editorCard = [[UIView alloc] init];
    _editorCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    _editorCard.layer.cornerRadius = 18.0;
    _editorCard.layer.borderWidth = 1.0;
    _editorCard.layer.borderColor = kVCBorder.CGColor;
    _editorCard.layer.shadowColor = [UIColor blackColor].CGColor;
    _editorCard.layer.shadowOpacity = 0.22;
    _editorCard.layer.shadowRadius = 18.0;
    _editorCard.layer.shadowOffset = CGSizeMake(0, -6.0);
    _editorCard.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorOverlay addSubview:_editorCard];

    _editorHandle = [[UIView alloc] init];
    _editorHandle.backgroundColor = kVCTextMuted;
    _editorHandle.layer.cornerRadius = 2.0;
    _editorHandle.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorCard addSubview:_editorHandle];

    _editorTitleLabel = [[UILabel alloc] init];
    _editorTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    _editorTitleLabel.textColor = kVCTextPrimary;
    _editorTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorCard addSubview:_editorTitleLabel];

    _editorCloseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_editorCloseButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(_editorCloseButton);
    _editorCloseButton.tintColor = kVCTextMuted;
    _editorCloseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorCloseButton addTarget:self action:@selector(_hideProviderEditor) forControlEvents:UIControlEventTouchUpInside];
    [_editorCard addSubview:_editorCloseButton];

    _editorHintLabel = [[UILabel alloc] init];
    _editorHintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _editorHintLabel.textColor = kVCTextSecondary;
    _editorHintLabel.numberOfLines = 2;
    _editorHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorCard addSubview:_editorHintLabel];

    _editorStatusLabel = [[UILabel alloc] init];
    _editorStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _editorStatusLabel.numberOfLines = 2;
    _editorStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorCard addSubview:_editorStatusLabel];

    _nameField = [self _editorField:VCTextLiteral(@"Provider name") secure:NO];
    _endpointField = [self _editorField:VCTextLiteral(@"Endpoint URL") secure:NO];
    _endpointField.keyboardType = UIKeyboardTypeURL;
    _apiKeyField = [self _editorField:VCTextLiteral(@"API key") secure:YES];

    UILabel *modelsLabel = [[UILabel alloc] init];
    modelsLabel.text = VCTextLiteral(@"Models");
    modelsLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    modelsLabel.textColor = kVCTextSecondary;
    modelsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorCard addSubview:modelsLabel];

    _syncModelsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_syncModelsButton setTitle:VCTextLiteral(@"Sync") forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(_syncModelsButton);
    _syncModelsButton.tintColor = kVCAccent;
    _syncModelsButton.contentEdgeInsets = UIEdgeInsetsMake(5, 10, 5, 10);
    VCApplyCompactIconTitleButtonLayout(_syncModelsButton, @"arrow.clockwise", 11.0);
    _syncModelsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_syncModelsButton addTarget:self action:@selector(_syncModelsFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [_editorCard addSubview:_syncModelsButton];

    _modelInputField = [self _editorField:VCTextLiteral(@"Add model one by one") secure:NO];
    _modelInputField.returnKeyType = UIReturnKeyDone;
    _modelInputField.delegate = self;

    _addModelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_addModelButton setTitle:VCTextLiteral(@"Add") forState:UIControlStateNormal];
    VCApplyCompactPrimaryButtonStyle(_addModelButton);
    _addModelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_addModelButton addTarget:self action:@selector(_addModelFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [_editorCard addSubview:_addModelButton];

    _modelsScrollView = [[UIScrollView alloc] init];
    _modelsScrollView.backgroundColor = [kVCBgInput colorWithAlphaComponent:0.68];
    _modelsScrollView.layer.cornerRadius = 12.0;
    _modelsScrollView.layer.borderWidth = 1.0;
    _modelsScrollView.layer.borderColor = kVCBorder.CGColor;
    _modelsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorCard addSubview:_modelsScrollView];

    _modelsScrollContentView = [[UIView alloc] init];
    _modelsScrollContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [_modelsScrollView addSubview:_modelsScrollContentView];

    _modelsListStack = [[UIStackView alloc] init];
    _modelsListStack.axis = UILayoutConstraintAxisVertical;
    _modelsListStack.spacing = 8.0;
    _modelsListStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_modelsScrollContentView addSubview:_modelsListStack];

    _protocolControl = [[UISegmentedControl alloc] initWithItems:@[@"OpenAI"]];
    _protocolControl.selectedSegmentTintColor = kVCAccent;
    [_protocolControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary} forState:UIControlStateNormal];
    [_protocolControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    _protocolControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorCard addSubview:_protocolControl];

    UIStackView *fieldStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameField, _endpointField, _apiKeyField]];
    fieldStack.axis = UILayoutConstraintAxisVertical;
    fieldStack.spacing = 10;
    fieldStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorCard addSubview:fieldStack];

    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancelButton setTitle:VCTextLiteral(@"Cancel") forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(cancelButton);
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton addTarget:self action:@selector(_hideProviderEditor) forControlEvents:UIControlEventTouchUpInside];
    [_editorCard addSubview:cancelButton];

    _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_deleteButton setTitle:VCTextLiteral(@"Delete") forState:UIControlStateNormal];
    VCApplyDangerButtonStyle(_deleteButton);
    _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_deleteButton addTarget:self action:@selector(_deleteProviderFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [_editorCard addSubview:_deleteButton];

    _activateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_activateButton setTitle:VCTextLiteral(@"Activate") forState:UIControlStateNormal];
    VCApplyPositiveButtonStyle(_activateButton);
    _activateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_activateButton addTarget:self action:@selector(_activateProviderFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [_editorCard addSubview:_activateButton];

    _primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_primaryButton setTitle:VCTextLiteral(@"Save") forState:UIControlStateNormal];
    VCApplyPrimaryButtonStyle(_primaryButton);
    _primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_primaryButton addTarget:self action:@selector(_saveProviderFromEditor) forControlEvents:UIControlEventTouchUpInside];
    [_editorCard addSubview:_primaryButton];

    CGFloat initialDrawerHeight = MIN(MAX(CGRectGetHeight(self.bounds) * 0.72, 430.0), MAX(360.0, CGRectGetHeight(self.bounds) - 34.0));
    self.editorCardBottomConstraint = [_editorCard.bottomAnchor constraintEqualToAnchor:_editorOverlay.bottomAnchor constant:initialDrawerHeight + 28.0];
    self.editorCardHeightConstraint = [_editorCard.heightAnchor constraintEqualToConstant:initialDrawerHeight];

    [NSLayoutConstraint activateConstraints:@[
        [_editorOverlay.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_editorOverlay.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_editorOverlay.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_editorOverlay.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [backdrop.topAnchor constraintEqualToAnchor:_editorOverlay.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:_editorOverlay.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:_editorOverlay.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:_editorOverlay.bottomAnchor],

        [_editorCard.leadingAnchor constraintEqualToAnchor:_editorOverlay.leadingAnchor constant:10],
        [_editorCard.trailingAnchor constraintEqualToAnchor:_editorOverlay.trailingAnchor constant:-10],
        self.editorCardBottomConstraint,
        self.editorCardHeightConstraint,

        [_editorHandle.topAnchor constraintEqualToAnchor:_editorCard.topAnchor constant:8],
        [_editorHandle.centerXAnchor constraintEqualToAnchor:_editorCard.centerXAnchor],
        [_editorHandle.widthAnchor constraintEqualToConstant:36],
        [_editorHandle.heightAnchor constraintEqualToConstant:4],

        [_editorTitleLabel.topAnchor constraintEqualToAnchor:_editorHandle.bottomAnchor constant:10],
        [_editorTitleLabel.leadingAnchor constraintEqualToAnchor:_editorCard.leadingAnchor constant:14],
        [_editorTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_editorCloseButton.leadingAnchor constant:-10],

        [_editorCloseButton.trailingAnchor constraintEqualToAnchor:_editorCard.trailingAnchor constant:-14],
        [_editorCloseButton.centerYAnchor constraintEqualToAnchor:_editorTitleLabel.centerYAnchor],
        [_editorCloseButton.widthAnchor constraintEqualToConstant:24],
        [_editorCloseButton.heightAnchor constraintEqualToConstant:24],

        [_editorHintLabel.topAnchor constraintEqualToAnchor:_editorTitleLabel.bottomAnchor constant:4],
        [_editorHintLabel.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [_editorHintLabel.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],

        [_editorStatusLabel.topAnchor constraintEqualToAnchor:_editorHintLabel.bottomAnchor constant:6],
        [_editorStatusLabel.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [_editorStatusLabel.trailingAnchor constraintEqualToAnchor:_editorCard.trailingAnchor constant:-14],

        [_protocolControl.topAnchor constraintEqualToAnchor:_editorStatusLabel.bottomAnchor constant:12],
        [_protocolControl.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [_protocolControl.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],
        [_protocolControl.heightAnchor constraintEqualToConstant:32],

        [fieldStack.topAnchor constraintEqualToAnchor:_protocolControl.bottomAnchor constant:12],
        [fieldStack.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [fieldStack.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],

        [modelsLabel.topAnchor constraintEqualToAnchor:fieldStack.bottomAnchor constant:12],
        [modelsLabel.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [modelsLabel.centerYAnchor constraintEqualToAnchor:_syncModelsButton.centerYAnchor],

        [_syncModelsButton.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],
        [_syncModelsButton.widthAnchor constraintGreaterThanOrEqualToConstant:78],
        [_syncModelsButton.heightAnchor constraintEqualToConstant:28],

        [modelsLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_syncModelsButton.leadingAnchor constant:-8],

        [_modelInputField.topAnchor constraintEqualToAnchor:modelsLabel.bottomAnchor constant:10],
        [_modelInputField.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [_modelInputField.trailingAnchor constraintEqualToAnchor:_addModelButton.leadingAnchor constant:-8],

        [_addModelButton.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],
        [_addModelButton.centerYAnchor constraintEqualToAnchor:_modelInputField.centerYAnchor],
        [_addModelButton.widthAnchor constraintGreaterThanOrEqualToConstant:72],
        [_addModelButton.heightAnchor constraintEqualToConstant:38],

        [_modelsScrollView.topAnchor constraintEqualToAnchor:_modelInputField.bottomAnchor constant:10],
        [_modelsScrollView.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [_modelsScrollView.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],
        [_modelsScrollView.heightAnchor constraintEqualToConstant:138],

        [_modelsScrollContentView.topAnchor constraintEqualToAnchor:_modelsScrollView.topAnchor],
        [_modelsScrollContentView.leadingAnchor constraintEqualToAnchor:_modelsScrollView.leadingAnchor],
        [_modelsScrollContentView.trailingAnchor constraintEqualToAnchor:_modelsScrollView.trailingAnchor],
        [_modelsScrollContentView.bottomAnchor constraintEqualToAnchor:_modelsScrollView.bottomAnchor],
        [_modelsScrollContentView.widthAnchor constraintEqualToAnchor:_modelsScrollView.widthAnchor],
        [_modelsScrollContentView.heightAnchor constraintGreaterThanOrEqualToAnchor:_modelsScrollView.heightAnchor],

        [_modelsListStack.topAnchor constraintEqualToAnchor:_modelsScrollContentView.topAnchor constant:10],
        [_modelsListStack.leadingAnchor constraintEqualToAnchor:_modelsScrollContentView.leadingAnchor constant:10],
        [_modelsListStack.trailingAnchor constraintEqualToAnchor:_modelsScrollContentView.trailingAnchor constant:-10],
        [_modelsListStack.bottomAnchor constraintEqualToAnchor:_modelsScrollContentView.bottomAnchor constant:-10],

        [cancelButton.topAnchor constraintEqualToAnchor:_modelsScrollView.bottomAnchor constant:14],
        [cancelButton.leadingAnchor constraintEqualToAnchor:_editorTitleLabel.leadingAnchor],
        [cancelButton.heightAnchor constraintEqualToConstant:40],
        [cancelButton.bottomAnchor constraintEqualToAnchor:_editorCard.bottomAnchor constant:-14],

        [_deleteButton.leadingAnchor constraintEqualToAnchor:cancelButton.trailingAnchor constant:8],
        [_deleteButton.widthAnchor constraintGreaterThanOrEqualToConstant:82],
        [_deleteButton.centerYAnchor constraintEqualToAnchor:cancelButton.centerYAnchor],
        [_deleteButton.heightAnchor constraintEqualToAnchor:cancelButton.heightAnchor],

        [_activateButton.leadingAnchor constraintEqualToAnchor:_deleteButton.trailingAnchor constant:8],
        [_activateButton.widthAnchor constraintGreaterThanOrEqualToConstant:90],
        [_activateButton.centerYAnchor constraintEqualToAnchor:cancelButton.centerYAnchor],
        [_activateButton.heightAnchor constraintEqualToAnchor:cancelButton.heightAnchor],

        [_primaryButton.leadingAnchor constraintEqualToAnchor:_activateButton.trailingAnchor constant:8],
        [_primaryButton.trailingAnchor constraintEqualToAnchor:_editorTitleLabel.trailingAnchor],
        [_primaryButton.centerYAnchor constraintEqualToAnchor:cancelButton.centerYAnchor],
        [_primaryButton.heightAnchor constraintEqualToAnchor:cancelButton.heightAnchor],
    ]];
    VCInstallKeyboardDismissAccessory(_editorOverlay);
}

- (void)_ensureEditorOverlay {
    if (self.editorOverlay || self.editorOverlaySetupFailed) {
        return;
    }

    @try {
        [self _setupSimpleEditorOverlay];
    } @catch (NSException *exception) {
        self.editorOverlaySetupFailed = YES;
        [self.editorOverlay removeFromSuperview];
        self.editorOverlay = nil;
        self.editorCard = nil;
        self.editorCardScrollView = nil;
        self.editorActionBar = nil;
        self.editorActionBarDivider = nil;
        self.editorHandle = nil;
        self.editorTitleLabel = nil;
        self.editorHintLabel = nil;
        self.editorStatusLabel = nil;
        self.editorCloseButton = nil;
        self.editorCancelButton = nil;
        self.providerLabel = nil;
        self.wireModeLabel = nil;
        self.modelsSectionLabel = nil;
        self.nameField = nil;
        self.endpointField = nil;
        self.apiKeyField = nil;
        self.modelInputField = nil;
        self.modelsScrollView = nil;
        self.modelsScrollContentView = nil;
        self.modelsListStack = nil;
        self.addModelButton = nil;
        self.syncModelsButton = nil;
        self.protocolControl = nil;
        self.wireModeControl = nil;
        self.primaryButton = nil;
        self.activateButton = nil;
        self.deleteButton = nil;
        self.editorUsesSimpleSheet = NO;
        VCLog(@"Settings Model editor setup exception: %@\n%@", exception.reason ?: exception.name, exception.callStackSymbols);
    }
}

- (void)_showProviderEditor:(VCProviderConfig *)provider createsProvider:(BOOL)createsProvider {
    [self _ensureEditorOverlay];
    if (!self.editorOverlay) {
        self.summaryLabel.text = VCTextLiteral(@"Model editor failed to load. The provider list is still available.");
        return;
    }

    self.editingProvider = provider;
    self.editorCreatesProvider = createsProvider;
    self.editorSyncingModels = NO;
    self.editorModels = [[self _sanitizedModelNamesFromArray:provider.models ?: @[]] mutableCopy];
    self.editorSelectedModel = [[VCProviderManager shared] effectiveSelectedModelForProvider:provider];
    if (self.editorSelectedModel.length > 0 && ![self.editorModels containsObject:self.editorSelectedModel]) {
        self.editorSelectedModel = @"";
    }
    if (self.editorSelectedModel.length == 0) {
        self.editorSelectedModel = self.editorModels.firstObject ?: @"";
    }
    self.editorTitleLabel.text = createsProvider ? VCTextLiteral(@"Add OpenAI") : VCTextLiteral(@"Edit OpenAI");
    self.editorHintLabel.text = VCTextLiteral(@"Fill the OpenAI endpoint and API key, choose Chat or Responses, then sync or type a model.");
    [self.primaryButton setTitle:(createsProvider ? VCTextLiteral(@"Create") : VCTextLiteral(@"Save")) forState:UIControlStateNormal];
    [self.syncModelsButton setTitle:VCTextLiteral(@"Sync") forState:UIControlStateNormal];
    self.syncModelsButton.enabled = YES;
    self.syncModelsButton.alpha = 1.0;

    self.nameField.text = VCSettingsSafeString(provider.name);
    self.endpointField.text = VCSettingsSafeString(provider.endpoint);
    self.apiVersionField.text = VCSettingsSafeString(provider.apiVersion).length > 0 ? VCSettingsSafeString(provider.apiVersion) : @"/v1";
    self.apiKeyField.text = VCSettingsSafeString(provider.apiKey);
    self.rolePresetTextView.text = VCSettingsSafeString(provider.rolePreset);
    self.maxTokensField.text = provider.maxTokens > 0 ? [NSString stringWithFormat:@"%ld", (long)provider.maxTokens] : @"";
    [self _applyReasoningEffortToEditor:provider.reasoningEffort];
    self.callLogTextView.text = VCTextLiteral(@"Ready.");
    self.modelInputField.text = @"";
    VCAPIProtocol protocol = provider ? provider.protocol : VCAPIProtocolOpenAI;
    if (protocol != VCAPIProtocolOpenAI && protocol != VCAPIProtocolOpenAIResponses) {
        protocol = VCAPIProtocolOpenAI;
    }
    [self _applyProtocolToEditorControls:protocol];
    [self _refreshEndpointFieldGuidance];
    [self _refreshDebugEndpointLabel];
    [self _reloadEditorModelList];
    [self _updateEditorActionState];
    [self.editorCardScrollView setContentOffset:CGPointZero animated:NO];

    self.editorOverlay.hidden = NO;
    [self bringSubviewToFront:self.editorOverlay];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    self.editorOverlay.alpha = 0.0;
    self.editorOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    BOOL landscape = CGRectGetWidth(self.bounds) > CGRectGetHeight(self.bounds);
    self.editorCard.transform = landscape
        ? CGAffineTransformMakeTranslation(CGRectGetWidth(self.editorCard.bounds) + 28.0, 0)
        : CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.editorCard.bounds) + 24.0);
    [UIView animateWithDuration:0.2 animations:^{
        self.editorOverlay.alpha = 1.0;
        self.editorOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.32];
        self.editorCard.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [self endEditing:YES];
    }];
}

- (void)_hideProviderEditor {
    if (!self.editorOverlay) return;
    [self endEditing:YES];
    BOOL landscape = CGRectGetWidth(self.bounds) > CGRectGetHeight(self.bounds);
    [UIView animateWithDuration:0.18 animations:^{
        self.editorOverlay.alpha = 0.0;
        self.editorOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
        self.editorCard.transform = landscape
            ? CGAffineTransformMakeTranslation(CGRectGetWidth(self.editorCard.bounds) + 28.0, 0)
            : CGAffineTransformMakeTranslation(0, CGRectGetHeight(self.editorCard.bounds) + 24.0);
    } completion:^(BOOL finished) {
        self.editorOverlay.hidden = YES;
        self.editorCard.transform = CGAffineTransformIdentity;
    }];
}

- (VCProviderConfig *)_providerFromEditor {
    VCProviderConfig *provider = self.editingProvider;
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) return nil;

    NSMutableArray<NSString *> *models = [[self _sanitizedModelNamesFromArray:self.editorModels ?: @[]] mutableCopy];
    NSString *pendingModel = [self.modelInputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (pendingModel.length > 0) {
        BOOL alreadyPresent = NO;
        for (NSString *existingModel in models) {
            if ([existingModel.lowercaseString isEqualToString:pendingModel.lowercaseString]) {
                alreadyPresent = YES;
                pendingModel = existingModel;
                break;
            }
        }
        if (!alreadyPresent) {
            [models addObject:pendingModel];
        }
    }
    self.editorModels = models;
    if (!provider) {
        NSString *normalizedEndpoint = [self _normalizedEndpointString:self.endpointField.text
                                                           forProtocol:[self _editorSelectedProtocol]];
        provider = [VCProviderConfig configWithName:name
                                           endpoint:normalizedEndpoint ?: @""
                                           protocol:[self _editorSelectedProtocol]
                                             models:self.editorModels];
    }

    provider.name = name;
    provider.endpoint = [self _normalizedEndpointString:self.endpointField.text forProtocol:[self _editorSelectedProtocol]];
    provider.apiVersion = [self _apiVersionFromEditor];
    NSString *normalizedAPIKey = [VCProviderConfig normalizedAPIKeyString:self.apiKeyField.text];
    if (normalizedAPIKey.length > 0 && ![normalizedAPIKey isEqualToString:self.apiKeyField.text]) {
        self.apiKeyField.text = normalizedAPIKey;
    }
    provider.apiKey = normalizedAPIKey ?: @"";
    provider.protocol = [self _editorSelectedProtocol];
    provider.rolePreset = [self.rolePresetTextView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    provider.models = self.editorModels;
    provider.selectedModel = [self.editorSelectedModel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    provider.maxTokens = [self.maxTokensField.text integerValue];
    provider.reasoningEffort = [self _reasoningEffortFromEditor];
    if (provider.selectedModel.length > 0 && ![self.editorModels containsObject:provider.selectedModel]) {
        provider.selectedModel = @"";
    }
    if (provider.selectedModel.length == 0 && pendingModel.length > 0) {
        provider.selectedModel = pendingModel;
    }
    if (provider.selectedModel.length == 0 && self.editorModels.count > 0) {
        provider.selectedModel = self.editorModels.firstObject;
    }
    return provider;
}

- (void)_saveProviderFromEditor {
    VCProviderConfig *provider = [self _providerFromEditor];
    if (!provider) return;
    if (self.editorCreatesProvider) {
        [[VCProviderManager shared] addProvider:provider];
    } else {
        [[VCProviderManager shared] updateProvider:provider];
    }
    self.editingProvider = provider;
    [self reload];
    [self _hideProviderEditor];
    [self _showChatPromptIfNeededForProvider:provider];
}

- (void)_activateProviderFromEditor {
    VCProviderConfig *provider = [self _providerFromEditor];
    if (!provider) return;
    if (self.editorCreatesProvider) {
        [[VCProviderManager shared] addProvider:provider];
        self.editorCreatesProvider = NO;
    } else {
        [[VCProviderManager shared] updateProvider:provider];
    }
    [[VCProviderManager shared] setActiveProviderID:provider.providerID];
    self.editingProvider = provider;
    [self reload];
    [self _hideProviderEditor];
    [self _showChatPromptIfNeededForProvider:provider];
}

- (void)_deleteProviderFromEditor {
    NSString *providerID = VCSettingsSafeString(self.editingProvider.providerID);
    if (providerID.length == 0) {
        [self _hideProviderEditor];
        return;
    }
    [[VCProviderManager shared] removeProvider:providerID];
    self.editingProvider = nil;
    [self reload];
    [self _hideProviderEditor];
}

- (void)_syncModelsFromEditor {
    if (self.editorSyncingModels) return;

    VCProviderConfig *draftProvider = [self _providerFromEditor];
    if (!draftProvider) {
        [self _setEditorStatusText:VCTextLiteral(@"Enter a provider name before syncing models.")
                             color:kVCYellow];
        return;
    }
    if (draftProvider.endpoint.length == 0) {
        [self _setEditorStatusText:VCTextLiteral(@"Add an endpoint before syncing models.")
                             color:kVCYellow];
        return;
    }
    if (draftProvider.apiKey.length == 0) {
        [self _setEditorStatusText:VCTextLiteral(@"Add an API key before syncing models.")
                             color:kVCYellow];
        return;
    }

    id<VCAIAdapter> adapter = [self _adapterForEditorProtocol:draftProvider.protocol];
    if (!adapter || ![adapter respondsToSelector:@selector(fetchModelsWithConfig:completion:)]) {
        [self _setEditorStatusText:VCTextLiteral(@"This provider type does not support model sync yet.")
                             color:kVCYellow];
        return;
    }

    self.editorSyncingModels = YES;
    self.syncModelsButton.enabled = NO;
    self.syncModelsButton.alpha = 0.72;
    [self.syncModelsButton setTitle:VCTextLiteral(@"Syncing") forState:UIControlStateNormal];
    [self _setEditorStatusText:VCTextLiteral(@"Fetching available models from the provider...")
                         color:kVCTextSecondary];

    __weak __typeof__(self) weakSelf = self;
    [adapter fetchModelsWithConfig:draftProvider completion:^(NSArray<NSString *> *models, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof__(weakSelf) self2 = weakSelf;
            if (!self2) return;
            self2.editorSyncingModels = NO;
            self2.syncModelsButton.enabled = YES;
            self2.syncModelsButton.alpha = 1.0;
            [self2.syncModelsButton setTitle:VCTextLiteral(@"Sync") forState:UIControlStateNormal];

            if (error) {
                NSString *message = error.localizedDescription ?: VCTextLiteral(@"Failed to sync models.");
                NSString *lowerMessage = message.lowercaseString ?: @"";
                if ((error.code == 401 || error.code == 403 || [lowerMessage containsString:@"api key"]) &&
                    self2.apiKeyField.text.length > 0) {
                    message = [message stringByAppendingFormat:@" %@", VCTextLiteral(@"Use only the raw key value here. Pasted JSON, Bearer prefixes, and extra quotes are stripped automatically on save.")];
                }
                [self2 _setEditorStatusText:message
                                      color:kVCRed];
                return;
            }

            NSArray<NSString *> *sanitizedModels = [self2 _sanitizedModelNamesFromArray:models];
            if (sanitizedModels.count == 0) {
                [self2 _setEditorStatusText:VCTextLiteral(@"No models were returned by the provider.")
                                      color:kVCYellow];
                return;
            }

            NSString *currentSelection = self2.editorSelectedModel;
            self2.editorModels = [sanitizedModels mutableCopy];
            if (![self2.editorModels containsObject:currentSelection]) {
                currentSelection = self2.editorModels.firstObject ?: @"";
            }
            self2.editorSelectedModel = currentSelection;
            [self2 _reloadEditorModelList];
            [self2 _setEditorStatusText:[NSString stringWithFormat:VCTextLiteral(@"Synced %lu models successfully."), (unsigned long)self2.editorModels.count]
                                  color:kVCGreen];
        });
    }];
}

- (void)_testProviderFromEditor {
    VCProviderConfig *draftProvider = [self _providerFromEditor];
    if (!draftProvider) {
        [self _setEditorStatusText:VCTextLiteral(@"Enter a provider name before testing.")
                             color:kVCYellow];
        return;
    }
    if (draftProvider.endpoint.length == 0 || draftProvider.apiKey.length == 0 || draftProvider.selectedModel.length == 0) {
        [self _setEditorStatusText:VCTextLiteral(@"Endpoint, API key, and model are required before testing.")
                             color:kVCYellow];
        return;
    }

    id<VCAIAdapter> adapter = [self _adapterForEditorProtocol:draftProvider.protocol];
    if (!adapter) {
        [self _setEditorStatusText:VCTextLiteral(@"This provider type cannot be tested here.")
                             color:kVCYellow];
        return;
    }

    self.testProviderButton.enabled = NO;
    self.testProviderButton.alpha = 0.72;
    [self.testProviderButton setTitle:VCTextLiteral(@"Testing") forState:UIControlStateNormal];
    [self _setEditorStatusText:VCTextLiteral(@"Sending a minimal test request...")
                         color:kVCTextSecondary];
    [self _appendEditorCallLogLine:[NSString stringWithFormat:@"%@ %@", VCTextLiteral(@"Test endpoint"), [self _debugEndpointForEndpoint:draftProvider.endpoint apiVersion:draftProvider.apiVersion protocol:draftProvider.protocol]]];

    NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
    if (draftProvider.rolePreset.length > 0) {
        [messages addObject:@{@"role": @"system", @"content": draftProvider.rolePreset}];
    }
    [messages addObject:@{@"role": @"user", @"content": @"Reply with OK."}];

    __weak __typeof__(self) weakSelf = self;
    [adapter sendMessages:messages
               withConfig:draftProvider
                streaming:NO
                  onChunk:nil
               onToolCall:nil
                  onUsage:^(NSUInteger inputTokens, NSUInteger outputTokens) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof__(weakSelf) self2 = weakSelf;
            [self2 _appendEditorCallLogLine:[NSString stringWithFormat:@"tokens in=%lu out=%lu", (unsigned long)inputTokens, (unsigned long)outputTokens]];
        });
    }
               completion:^(NSDictionary *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof__(weakSelf) self2 = weakSelf;
            if (!self2) return;
            self2.testProviderButton.enabled = YES;
            self2.testProviderButton.alpha = 1.0;
            [self2.testProviderButton setTitle:VCTextLiteral(@"Test Call") forState:UIControlStateNormal];
            if (error) {
                NSString *message = error.localizedDescription ?: VCTextLiteral(@"Test call failed.");
                [self2 _setEditorStatusText:message color:kVCRed];
                [self2 _appendEditorCallLogLine:[NSString stringWithFormat:@"failed: %@", message]];
                return;
            }
            NSString *content = [response[@"content"] isKindOfClass:[NSString class]] ? response[@"content"] : @"";
            NSString *line = content.length > 0 ? content : VCTextLiteral(@"Provider returned a valid response.");
            [self2 _setEditorStatusText:VCTextLiteral(@"Test call succeeded.")
                                  color:kVCGreen];
            [self2 _appendEditorCallLogLine:[NSString stringWithFormat:@"ok: %@", line]];
        });
    }];
}

- (void)presentNewProviderEditor {
    [self _showProviderEditor:nil createsProvider:YES];
}

- (void)_addModelFromEditor {
    NSString *model = [self.modelInputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (model.length == 0) return;
    if (!self.editorModels) {
        self.editorModels = [NSMutableArray array];
    }
    NSString *canonicalModel = nil;
    for (NSString *existingModel in self.editorModels) {
        if ([existingModel.lowercaseString isEqualToString:model.lowercaseString]) {
            canonicalModel = existingModel;
            break;
        }
    }
    if (!canonicalModel) {
        [self.editorModels addObject:model];
        canonicalModel = model;
    }
    self.editorModels = [[self _sanitizedModelNamesFromArray:self.editorModels] mutableCopy];
    self.editorSelectedModel = canonicalModel;
    self.modelInputField.text = @"";
    [self _reloadEditorModelList];
    [self _setEditorStatusText:[NSString stringWithFormat:VCTextLiteral(@"Current model set to %@."), canonicalModel]
                         color:kVCTextSecondary];
}

- (void)_selectEditorModel:(UIButton *)sender {
    NSString *model = sender.accessibilityIdentifier ?: @"";
    if (model.length == 0) return;
    self.editorSelectedModel = model;
    [self _reloadEditorModelList];
    [self _setEditorStatusText:[NSString stringWithFormat:VCTextLiteral(@"Current model set to %@."), model]
                         color:kVCTextSecondary];
}

- (void)_removeEditorModel:(UIButton *)sender {
    NSString *model = sender.accessibilityIdentifier ?: @"";
    if (model.length == 0) return;
    [self.editorModels removeObject:model];
    if ([self.editorSelectedModel isEqualToString:model]) {
        self.editorSelectedModel = self.editorModels.firstObject ?: @"";
    }
    [self _reloadEditorModelList];
    [self _setEditorStatusText:(self.editorSelectedModel.length > 0 ? [NSString stringWithFormat:VCTextLiteral(@"Removed model. %@ is now the default."), self.editorSelectedModel] : VCTextLiteral(@"Removed model from this provider."))
                         color:kVCTextSecondary];
}

- (void)_reloadEditorModelList {
    if (!self.modelsListStack) return;
    for (UIView *view in [self.modelsListStack.arrangedSubviews copy]) {
        [self.modelsListStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    if (self.editorModels.count == 0) {
        UILabel *emptyLabel = [[UILabel alloc] init];
        emptyLabel.text = VCTextLiteral(@"No models yet. Add one manually or use Sync.");
        emptyLabel.textColor = kVCTextMuted;
        emptyLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        emptyLabel.numberOfLines = 2;
        [self.modelsListStack addArrangedSubview:emptyLabel];
        return;
    }

    for (NSString *model in self.editorModels) {
        BOOL selected = [model isEqualToString:self.editorSelectedModel];
        NSInteger rowIndex = [self.editorModels indexOfObject:model];

        UIView *row = [[UIView alloc] init];
        row.backgroundColor = selected ? [kVCAccent colorWithAlphaComponent:0.14] : [kVCBgHover colorWithAlphaComponent:0.78];
        row.layer.cornerRadius = 12.0;
        row.layer.borderWidth = 1.0;
        row.layer.borderColor = (selected ? kVCBorderAccent : kVCBorder).CGColor;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.tag = rowIndex;
        row.accessibilityIdentifier = model;

        UILongPressGestureRecognizer *reorderGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_handleModelRowReorder:)];
        reorderGesture.minimumPressDuration = 0.18;
        [row addGestureRecognizer:reorderGesture];

        UIButton *selectButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [selectButton setTitle:model forState:UIControlStateNormal];
        [selectButton setTitleColor:selected ? kVCAccentHover : kVCTextPrimary forState:UIControlStateNormal];
        [selectButton setImage:[UIImage systemImageNamed:selected ? @"checkmark.circle.fill" : @"circle"] forState:UIControlStateNormal];
        selectButton.tintColor = selected ? kVCAccent : kVCTextMuted;
        selectButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:selected ? UIFontWeightBold : UIFontWeightSemibold];
        selectButton.titleLabel.numberOfLines = 1;
        selectButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        selectButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        selectButton.contentEdgeInsets = UIEdgeInsetsMake(8, 10, 8, 10);
        selectButton.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, -8);
        selectButton.accessibilityIdentifier = model;
        selectButton.translatesAutoresizingMaskIntoConstraints = NO;
        selectButton.clipsToBounds = YES;
        [selectButton setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [selectButton setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [selectButton addTarget:self action:@selector(_selectEditorModel:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:selectButton];

        UILabel *badge = [[UILabel alloc] init];
        badge.text = selected ? VCTextLiteral(@"Current") : @"";
        badge.textColor = selected ? kVCAccentHover : kVCTextMuted;
        badge.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        [badge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [badge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [row addSubview:badge];

        UIImageView *dragIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
        dragIcon.tintColor = kVCTextMuted;
        dragIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [dragIcon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [dragIcon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [row addSubview:dragIcon];

        UIButton *removeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [removeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        removeButton.tintColor = selected ? kVCRed : kVCTextMuted;
        removeButton.accessibilityIdentifier = model;
        removeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [removeButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [removeButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [removeButton addTarget:self action:@selector(_removeEditorModel:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:removeButton];

        [NSLayoutConstraint activateConstraints:@[
            [row.heightAnchor constraintEqualToConstant:42],
            [selectButton.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [selectButton.topAnchor constraintEqualToAnchor:row.topAnchor],
            [selectButton.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
            [selectButton.trailingAnchor constraintLessThanOrEqualToAnchor:badge.leadingAnchor constant:-8],

            [badge.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [badge.trailingAnchor constraintEqualToAnchor:dragIcon.leadingAnchor constant:-8],

            [dragIcon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [dragIcon.trailingAnchor constraintEqualToAnchor:removeButton.leadingAnchor constant:-10],
            [dragIcon.widthAnchor constraintEqualToConstant:14],
            [dragIcon.heightAnchor constraintEqualToConstant:14],

            [removeButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8],
            [removeButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [removeButton.widthAnchor constraintEqualToConstant:24],
            [removeButton.heightAnchor constraintEqualToConstant:24],
        ]];
        [self.modelsListStack addArrangedSubview:row];
    }
}

- (void)_handleModelRowReorder:(UILongPressGestureRecognizer *)gesture {
    UIView *row = gesture.view;
    if (!row || self.editorModels.count <= 1) return;

    CGPoint location = [gesture locationInView:self.modelsListStack];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            self.draggingModelRow = row;
            self.draggingModelIndex = row.tag;
            self.draggingStartPoint = location;
            row.layer.zPosition = 10.0;
            [UIView animateWithDuration:0.16 animations:^{
                row.transform = CGAffineTransformMakeScale(1.02, 1.02);
                row.alpha = 0.92;
                row.backgroundColor = [kVCAccent colorWithAlphaComponent:0.2];
            }];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (self.draggingModelRow != row) break;
            CGFloat translationY = location.y - self.draggingStartPoint.y;
            row.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(1.02, 1.02),
                                                    CGAffineTransformMakeTranslation(0, translationY));

            NSInteger targetIndex = [self _targetIndexForModelRowAtLocation:location];
            if (targetIndex == NSNotFound || targetIndex == self.draggingModelIndex) break;

            [self _moveEditorModelFromIndex:self.draggingModelIndex toIndex:targetIndex];
            [self.modelsListStack removeArrangedSubview:row];
            [self.modelsListStack insertArrangedSubview:row atIndex:targetIndex];
            self.draggingModelIndex = targetIndex;
            [self _refreshModelRowTags];
            [UIView animateWithDuration:0.14 animations:^{
                [self.modelsListStack layoutIfNeeded];
            }];
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateEnded:
        default: {
            if (self.draggingModelRow != row) break;
            [UIView animateWithDuration:0.18 animations:^{
                row.transform = CGAffineTransformIdentity;
                row.alpha = 1.0;
            } completion:^(BOOL finished) {
                row.layer.zPosition = 0.0;
                [self _reloadEditorModelList];
            }];
            self.draggingModelRow = nil;
            self.draggingModelIndex = NSNotFound;
            break;
        }
    }
}

- (NSInteger)_targetIndexForModelRowAtLocation:(CGPoint)location {
    NSArray<UIView *> *rows = self.modelsListStack.arrangedSubviews;
    for (NSUInteger idx = 0; idx < rows.count; idx++) {
        UIView *candidate = rows[idx];
        CGFloat midY = CGRectGetMidY(candidate.frame);
        if (location.y < midY) {
            return (NSInteger)idx;
        }
    }
    return rows.count > 0 ? (NSInteger)rows.count - 1 : NSNotFound;
}

- (void)_moveEditorModelFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex {
    if (fromIndex == toIndex || fromIndex < 0 || toIndex < 0) return;
    if (fromIndex >= (NSInteger)self.editorModels.count || toIndex >= (NSInteger)self.editorModels.count) return;
    NSString *model = self.editorModels[fromIndex];
    [self.editorModels removeObjectAtIndex:fromIndex];
    [self.editorModels insertObject:model atIndex:toIndex];
}

- (void)_refreshModelRowTags {
    NSArray<UIView *> *rows = self.modelsListStack.arrangedSubviews;
    for (NSUInteger idx = 0; idx < rows.count; idx++) {
        rows[idx].tag = (NSInteger)idx;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.modelInputField) {
        [self _addModelFromEditor];
        return NO;
    }
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.providers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    VCProviderListCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ProvCell" forIndexPath:indexPath];

    if (indexPath.row >= (NSInteger)self.providers.count) {
        [cell configureWithProvider:nil active:NO];
        return cell;
    }

    VCProviderConfig *p = self.providers[indexPath.row];
    BOOL isActive = [p.providerID isEqualToString:[[VCProviderManager shared] activeProvider].providerID];
    [cell configureWithProvider:p active:isActive];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.frame = UIEdgeInsetsInsetRect(cell.frame, UIEdgeInsetsMake(4, 0, 4, 0));
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.providers.count) return;
    VCProviderConfig *p = self.providers[indexPath.row];
    [self _showProviderEditor:[p copy] createsProvider:NO];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
               trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.providers.count) return nil;
    VCProviderConfig *p = self.providers[indexPath.row];

    UIContextualAction *edit = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:VCTextLiteral(@"Edit") handler:^(UIContextualAction *a, UIView *sv, void (^done)(BOOL)) {
        [self _showProviderEditor:[p copy] createsProvider:NO];
        done(YES);
    }];
    edit.backgroundColor = UIColorFromHex(0x2563eb);

    UIContextualAction *activate = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:VCTextLiteral(@"Activate") handler:^(UIContextualAction *a, UIView *sv, void (^done)(BOOL)) {
        [[VCProviderManager shared] setActiveProviderID:p.providerID];
        [self reload];
        done(YES);
    }];
    activate.backgroundColor = kVCAccent;

    UIContextualAction *exportAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:VCTextLiteral(@"Export") handler:^(UIContextualAction *a, UIView *sv, void (^done)(BOOL)) {
        [self _exportProviderConfig:p sourceView:sv];
        done(YES);
    }];
    exportAction.backgroundColor = kVCGreen;

    NSMutableArray<UIContextualAction *> *actions = [NSMutableArray arrayWithObjects:exportAction, activate, edit, nil];
    if (!p.isBuiltin) {
        UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
            title:VCTextLiteral(@"Delete") handler:^(UIContextualAction *a, UIView *sv, void (^done)(BOOL)) {
            [[VCProviderManager shared] removeProvider:p.providerID];
            [self reload];
            done(YES);
        }];
        [actions insertObject:del atIndex:0];
    }

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:actions];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    [self _resumeOverlayInteractionAfterExternalModalIfNeeded];
    if (!url) {
        [self _restorePanelAfterExternalDocumentIfNeeded];
        return;
    }
    [self _importProviderConfigFromURL:url];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self _resumeOverlayInteractionAfterExternalModalIfNeeded];
    [self _restorePanelAfterExternalDocumentIfNeeded];
}

- (void)_addProvider {
    [self presentNewProviderEditor];
}

- (void)_showChatPromptIfNeededForProvider:(VCProviderConfig *)provider {
    VCProviderConfig *active = [[VCProviderManager shared] activeProvider];
    NSString *effectiveModel = [[VCProviderManager shared] effectiveSelectedModelForProvider:provider];
    NSString *providerID = VCSettingsSafeString(provider.providerID);
    NSString *activeProviderID = VCSettingsSafeString(active.providerID);
    NSString *providerAPIKey = VCSettingsSafeString(provider.apiKey);
    NSString *providerName = VCSettingsSafeString(provider.name);
    BOOL providerIsActive = providerID.length > 0 && [providerID isEqualToString:activeProviderID];
    if (!providerIsActive || providerAPIKey.length == 0 || effectiveModel.length == 0) {
        [self _hideChatPrompt];
        return;
    }

    self.chatPromptLabel.text = [NSString stringWithFormat:VCTextLiteral(@"%@ is ready in AI Chat with %@."), providerName.length > 0 ? providerName : VCTextLiteral(@"Provider"), effectiveModel];
    self.chatPromptBar.hidden = NO;
    [self bringSubviewToFront:self.chatPromptBar];
    [UIView animateWithDuration:0.2 animations:^{
        self.chatPromptBar.alpha = 1.0;
    }];
}

- (void)_hideChatPrompt {
    if (self.chatPromptBar.hidden) return;
    [UIView animateWithDuration:0.18 animations:^{
        self.chatPromptBar.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.chatPromptBar.hidden = YES;
    }];
}

- (void)_openAIChatFromPrompt {
    [[NSNotificationCenter defaultCenter] postNotificationName:VCSettingsRequestOpenAIChatNotification object:self];
    [self _hideChatPrompt];
}

@end


// ═══════════════════════════════════════════════════════════════
// VCSettingsTab -- Main settings menu
// ═══════════════════════════════════════════════════════════════

@interface VCSettingsEntryCard : UIControl
@property (nonatomic, strong) UIView *iconBadge;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *chevronView;
- (instancetype)initWithTitle:(NSString *)title icon:(NSString *)iconName accentColor:(UIColor *)accentColor;
- (void)updateTitle:(NSString *)title;
- (void)updateSubtitle:(NSString *)subtitle;
@end

@implementation VCSettingsEntryCard

- (instancetype)initWithTitle:(NSString *)title icon:(NSString *)iconName accentColor:(UIColor *)accentColor {
    if (self = [super initWithFrame:CGRectZero]) {
        VCApplyPanelSurface(self, 12.0);
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }

        _iconBadge = [[UIView alloc] initWithFrame:CGRectZero];
        _iconBadge.backgroundColor = [accentColor colorWithAlphaComponent:0.18];
        _iconBadge.layer.cornerRadius = 14.0;
        _iconBadge.layer.borderWidth = 1.0;
        _iconBadge.layer.borderColor = [accentColor colorWithAlphaComponent:0.30].CGColor;
        [self addSubview:_iconBadge];

        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
        _iconView.tintColor = accentColor;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconBadge addSubview:_iconView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.text = title ?: @"";
        _titleLabel.textColor = kVCTextPrimary;
        _titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
        VCPrepareSingleLineLabel(_titleLabel, NSLineBreakByTruncatingTail);
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.textColor = kVCTextSecondary;
        _subtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_subtitleLabel];

        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        _chevronView.tintColor = kVCTextMuted;
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_chevronView];
    }
    return self;
}

- (void)updateSubtitle:(NSString *)subtitle {
    self.subtitleLabel.text = subtitle ?: @"";
    [self setNeedsLayout];
}

- (void)updateTitle:(NSString *)title {
    self.titleLabel.text = title ?: @"";
    [self setNeedsLayout];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.84 : 1.0;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat inset = 12.0;
    CGFloat iconSize = 36.0;
    CGFloat iconY = floor((CGRectGetHeight(self.bounds) - iconSize) * 0.5);
    self.iconBadge.frame = CGRectMake(inset, iconY, iconSize, iconSize);
    self.iconBadge.layer.cornerRadius = 12.0;
    self.iconView.frame = CGRectMake(9.0, 9.0, 18.0, 18.0);
    self.chevronView.frame = CGRectMake(CGRectGetWidth(self.bounds) - inset - 10.0, (CGRectGetHeight(self.bounds) - 16.0) * 0.5, 10.0, 16.0);

    CGFloat textX = CGRectGetMaxX(self.iconBadge.frame) + 10.0;
    CGFloat textWidth = MAX(80.0, CGRectGetMinX(self.chevronView.frame) - textX - 10.0);
    self.titleLabel.frame = CGRectMake(textX, 11.0, textWidth, 18.0);
    self.subtitleLabel.frame = CGRectMake(textX, CGRectGetMaxY(self.titleLabel.frame) + 4.0, textWidth, 30.0);
}

@end

@interface VCSettingsTab () <VCPanelLayoutUpdatable>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *contentDividerView;
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerSummaryLabel;
@property (nonatomic, strong) UIStackView *heroMetaStack;
@property (nonatomic, strong) UILabel *providerMetaBadge;
@property (nonatomic, strong) UILabel *modelMetaBadge;
@property (nonatomic, strong) UILabel *protocolMetaBadge;
@property (nonatomic, strong) VCSettingsEntryCard *runtimeSummaryCard;
@property (nonatomic, strong) VCSettingsEntryCard *quickActionsCard;
@property (nonatomic, strong) VCSettingsEntryCard *modelCard;
@property (nonatomic, strong) VCSettingsEntryCard *languageCard;
@property (nonatomic, strong) VCSettingsEntryCard *aboutCard;
@property (nonatomic, strong) VCSettingsEntryCard *safetyCard;
@property (nonatomic, strong) VCSettingsEntryCard *overlayCard;
@property (nonatomic, strong) VCSettingsEntryCard *exportCard;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) VCModelSettingsView *modelView;
@property (nonatomic, strong) VCLanguageDrawer *languageDrawer;
@property (nonatomic, strong) UIView *aboutOverlayView;
@property (nonatomic, strong) UILabel *aboutOverlayTitleLabel;
@property (nonatomic, strong) VCAboutTab *aboutViewController;
@property (nonatomic, strong) NSLayoutConstraint *heroPortraitLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *heroPortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *heroLandscapeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *heroLandscapeWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *heroLandscapeHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *runtimePortraitTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *runtimeLandscapeTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *runtimePortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *runtimeLandscapeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *quickPortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *quickLandscapeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *modelPortraitTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *modelLandscapeTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *modelPortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *modelLandscapeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *languagePortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *languageLandscapeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *aboutPortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *aboutLandscapeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *safetyPortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *safetyLandscapeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *overlayPortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *overlayLandscapeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *exportPortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *exportLandscapeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *versionPortraitTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *versionLandscapeTrailingConstraint;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@property (nonatomic, assign) CGRect availableLayoutBounds;
@end

@implementation VCSettingsTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;
    self.currentLayoutMode = VCPanelLayoutModePortrait;
    self.availableLayoutBounds = CGRectZero;

    [self _setupLayout];
    VCInstallKeyboardDismissAccessory(self.view);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_languageDidChange) name:VCLanguageDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_providerDidChange) name:VCProviderManagerDidChangeNotification object:nil];
    [self _refreshLocalizedText];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_setupLayout {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];

    self.heroCard = [[UIView alloc] init];
    VCApplyPanelSurface(self.heroCard, 12.0);
    self.heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.heroCard];

    self.contentDividerView = [[UIView alloc] init];
    self.contentDividerView.backgroundColor = [kVCBorderStrong colorWithAlphaComponent:0.34];
    self.contentDividerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentDividerView.hidden = YES;
    self.contentDividerView.alpha = 0.0;
    [self.contentView addSubview:self.contentDividerView];

    UILabel *eyebrow = [[UILabel alloc] init];
    eyebrow.text = VCTextLiteral(@"OPENAI");
    eyebrow.textColor = kVCAccent;
    eyebrow.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heroCard addSubview:eyebrow];

    self.headerTitleLabel = [[UILabel alloc] init];
    self.headerTitleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.headerTitleLabel.textColor = kVCTextPrimary;
    self.headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heroCard addSubview:self.headerTitleLabel];

    self.headerSummaryLabel = [[UILabel alloc] init];
    self.headerSummaryLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.headerSummaryLabel.textColor = kVCTextSecondary;
    self.headerSummaryLabel.numberOfLines = 0;
    self.headerSummaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heroCard addSubview:self.headerSummaryLabel];

    self.heroMetaStack = [[UIStackView alloc] init];
    self.heroMetaStack.axis = UILayoutConstraintAxisHorizontal;
    self.heroMetaStack.distribution = UIStackViewDistributionFillEqually;
    self.heroMetaStack.spacing = 6.0;
    self.heroMetaStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heroCard addSubview:self.heroMetaStack];

    self.providerMetaBadge = [self _makeHeroMetaBadge];
    self.modelMetaBadge = [self _makeHeroMetaBadge];
    self.protocolMetaBadge = [self _makeHeroMetaBadge];
    [self.heroMetaStack addArrangedSubview:self.providerMetaBadge];
    [self.heroMetaStack addArrangedSubview:self.modelMetaBadge];
    [self.heroMetaStack addArrangedSubview:self.protocolMetaBadge];

    self.runtimeSummaryCard = [[VCSettingsEntryCard alloc] initWithTitle:VCTextLiteral(@"Current Setup")
                                                                   icon:@"checkmark.seal"
                                                            accentColor:kVCGreen];
    self.runtimeSummaryCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.runtimeSummaryCard addTarget:self action:@selector(_showModelSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.runtimeSummaryCard];

    self.quickActionsCard = [[VCSettingsEntryCard alloc] initWithTitle:VCTextLiteral(@"OpenAI Model")
                                                                  icon:@"bolt"
                                                           accentColor:kVCYellow];
    self.quickActionsCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.quickActionsCard addTarget:self action:@selector(_addProvider) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.quickActionsCard];
    self.quickActionsCard.hidden = YES;
    [self.quickActionsCard removeFromSuperview];

    self.modelCard = [[VCSettingsEntryCard alloc] initWithTitle:VCTextLiteral(@"OpenAI Model")
                                                            icon:@"cpu"
                                                     accentColor:kVCAccent];
    self.modelCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modelCard addTarget:self action:@selector(_showModelSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.modelCard];

    self.languageCard = [[VCSettingsEntryCard alloc] initWithTitle:VCTextLiteral(@"Language")
                                                               icon:@"globe"
                                                        accentColor:kVCGreen];
    self.languageCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.languageCard addTarget:self action:@selector(_showLanguageDrawer) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.languageCard];

    self.aboutCard = [[VCSettingsEntryCard alloc] initWithTitle:VCTextLiteral(@"About")
                                                            icon:@"info.circle"
                                                     accentColor:kVCYellow];
    self.aboutCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.aboutCard addTarget:self action:@selector(_showAboutView) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.aboutCard];

    self.safetyCard = [[VCSettingsEntryCard alloc] initWithTitle:VCTextLiteral(@"Safety Capabilities")
                                                            icon:@"shield.lefthalf.filled"
                                                     accentColor:kVCGreen];
    self.safetyCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.safetyCard addTarget:self action:@selector(_showModelSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.safetyCard];

    self.overlayCard = [[VCSettingsEntryCard alloc] initWithTitle:VCTextLiteral(@"Overlay Behavior")
                                                            icon:@"rectangle.on.rectangle"
                                                     accentColor:kVCAccent];
    self.overlayCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.overlayCard addTarget:self action:@selector(_showModelSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.overlayCard];

    self.exportCard = [[VCSettingsEntryCard alloc] initWithTitle:VCTextLiteral(@"Export & Diagnostics")
                                                           icon:@"shippingbox"
                                                    accentColor:kVCYellow];
    self.exportCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.exportCard addTarget:self action:@selector(_showAboutView) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.exportCard];

    _versionLabel = [[UILabel alloc] init];
    _versionLabel.font = [UIFont systemFontOfSize:11];
    _versionLabel.textColor = kVCTextMuted;
    _versionLabel.textAlignment = NSTextAlignmentCenter;
    _versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_versionLabel];

    [self.safetyCard removeFromSuperview];
    [self.overlayCard removeFromSuperview];
    [self.exportCard removeFromSuperview];

    self.heroPortraitLeadingConstraint = [self.heroCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
    self.heroPortraitTrailingConstraint = [self.heroCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
    self.heroLandscapeTrailingConstraint = [self.heroCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
    self.heroLandscapeWidthConstraint = [self.heroCard.widthAnchor constraintEqualToConstant:300.0];
    self.heroLandscapeHeightConstraint = [self.heroCard.heightAnchor constraintEqualToConstant:188.0];
    self.runtimePortraitTopConstraint = [self.runtimeSummaryCard.topAnchor constraintEqualToAnchor:self.heroCard.bottomAnchor constant:12];
    self.runtimeLandscapeTopConstraint = [self.runtimeSummaryCard.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12];
    self.runtimePortraitTrailingConstraint = [self.runtimeSummaryCard.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor];
    self.runtimeLandscapeTrailingConstraint = [self.runtimeSummaryCard.trailingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:-12];
    self.quickPortraitTrailingConstraint = [self.quickActionsCard.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor];
    self.quickLandscapeTrailingConstraint = [self.quickActionsCard.trailingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:-12];
    self.modelPortraitTopConstraint = [self.modelCard.topAnchor constraintEqualToAnchor:self.runtimeSummaryCard.bottomAnchor constant:12];
    self.modelLandscapeTopConstraint = [self.modelCard.topAnchor constraintEqualToAnchor:self.runtimeSummaryCard.bottomAnchor constant:12];
    self.modelPortraitTrailingConstraint = [self.modelCard.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor];
    self.modelLandscapeTrailingConstraint = [self.modelCard.trailingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:-12];
    self.languagePortraitTrailingConstraint = [self.languageCard.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor];
    self.languageLandscapeTrailingConstraint = [self.languageCard.trailingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:-12];
    self.aboutPortraitTrailingConstraint = [self.aboutCard.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor];
    self.aboutLandscapeTrailingConstraint = [self.aboutCard.trailingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:-12];
    self.safetyPortraitTrailingConstraint = [self.safetyCard.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor];
    self.safetyLandscapeTrailingConstraint = [self.safetyCard.trailingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:-12];
    self.overlayPortraitTrailingConstraint = [self.overlayCard.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor];
    self.overlayLandscapeTrailingConstraint = [self.overlayCard.trailingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:-12];
    self.exportPortraitTrailingConstraint = [self.exportCard.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor];
    self.exportLandscapeTrailingConstraint = [self.exportCard.trailingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:-12];
    self.versionPortraitTrailingConstraint = [self.versionLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16];
    self.versionLandscapeTrailingConstraint = [self.versionLabel.trailingAnchor constraintEqualToAnchor:self.modelCard.trailingAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [self.heroCard.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
        self.heroPortraitLeadingConstraint,
        self.heroPortraitTrailingConstraint,

        [eyebrow.topAnchor constraintEqualToAnchor:self.heroCard.topAnchor constant:14],
        [eyebrow.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:14],
        [eyebrow.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-14],

        [self.headerTitleLabel.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:6],
        [self.headerTitleLabel.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [self.headerTitleLabel.trailingAnchor constraintEqualToAnchor:eyebrow.trailingAnchor],

        [self.headerSummaryLabel.topAnchor constraintEqualToAnchor:self.headerTitleLabel.bottomAnchor constant:6],
        [self.headerSummaryLabel.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [self.headerSummaryLabel.trailingAnchor constraintEqualToAnchor:eyebrow.trailingAnchor],
        [self.heroMetaStack.topAnchor constraintEqualToAnchor:self.headerSummaryLabel.bottomAnchor constant:10],
        [self.heroMetaStack.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [self.heroMetaStack.trailingAnchor constraintEqualToAnchor:eyebrow.trailingAnchor],
        [self.heroMetaStack.bottomAnchor constraintEqualToAnchor:self.heroCard.bottomAnchor constant:-14],

        self.runtimePortraitTopConstraint,
        [self.runtimeSummaryCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        self.runtimePortraitTrailingConstraint,
        [self.runtimeSummaryCard.heightAnchor constraintEqualToConstant:66],

        self.modelPortraitTopConstraint,
        [self.modelCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        self.modelPortraitTrailingConstraint,
        [self.modelCard.heightAnchor constraintEqualToAnchor:self.runtimeSummaryCard.heightAnchor],

        [self.languageCard.topAnchor constraintEqualToAnchor:self.modelCard.bottomAnchor constant:12],
        [self.languageCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        self.languagePortraitTrailingConstraint,
        [self.languageCard.heightAnchor constraintEqualToAnchor:self.modelCard.heightAnchor],

        [self.aboutCard.topAnchor constraintEqualToAnchor:self.languageCard.bottomAnchor constant:12],
        [self.aboutCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        self.aboutPortraitTrailingConstraint,
        [self.aboutCard.heightAnchor constraintEqualToAnchor:self.modelCard.heightAnchor],

        [self.versionLabel.topAnchor constraintEqualToAnchor:self.aboutCard.bottomAnchor constant:16],
        [self.versionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        self.versionPortraitTrailingConstraint,
        [self.versionLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16],
        [self.contentDividerView.leadingAnchor constraintEqualToAnchor:self.modelCard.trailingAnchor constant:5.5],
        [self.contentDividerView.trailingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:-5.5],
        [self.contentDividerView.widthAnchor constraintEqualToConstant:1.0],
        [self.contentDividerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16.0],
        [self.contentDividerView.bottomAnchor constraintEqualToAnchor:self.aboutCard.bottomAnchor constant:-4.0],
    ]];
}

- (UILabel *)_makeHeroMetaBadge {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    label.textColor = kVCTextPrimary;
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [kVCBgInput colorWithAlphaComponent:0.78];
    label.layer.cornerRadius = 10.0;
    label.layer.borderWidth = 1.0;
    label.layer.borderColor = kVCBorder.CGColor;
    label.clipsToBounds = YES;
    VCPrepareSingleLineLabel(label, NSLineBreakByTruncatingMiddle);
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.heightAnchor constraintGreaterThanOrEqualToConstant:22.0].active = YES;
    return label;
}

- (NSString *)_paddedBadgeText:(NSString *)text {
    NSString *safe = VCSettingsSafeString(text);
    return safe.length > 0 ? [NSString stringWithFormat:@"  %@  ", safe] : @"";
}

- (void)_refreshHeroMetaBadges {
    VCProviderConfig *activeProvider = [[VCProviderManager shared] activeProvider];
    NSString *providerName = VCSettingsSafeString(activeProvider.name);
    NSString *effectiveModel = [[VCProviderManager shared] effectiveSelectedModelForProvider:activeProvider];
    NSString *protocolText = activeProvider ? VCSettingsProtocolDisplayName(activeProvider.protocol) : VCTextLiteral(@"No protocol");
    NSString *providerText = activeProvider
        ? (providerName.length > 0 ? providerName : VCTextLiteral(@"Provider"))
        : VCTextLiteral(@"Setup");
    NSString *modelText = activeProvider
        ? (effectiveModel.length > 0 ? effectiveModel : VCTextLiteral(@"Default"))
        : VCTextLiteral(@"Model");
    self.providerMetaBadge.text = [self _paddedBadgeText:providerText];
    self.modelMetaBadge.text = [self _paddedBadgeText:modelText];
    self.protocolMetaBadge.text = [self _paddedBadgeText:[protocolText stringByReplacingOccurrencesOfString:@"OpenAI · " withString:@""]];
    self.protocolMetaBadge.textColor = (activeProvider && VCSettingsSafeString(activeProvider.apiKey).length > 0) ? kVCGreen : kVCYellow;
}

- (void)_refreshLocalizedText {
    self.headerTitleLabel.text = VCTextLiteral(@"OpenAI Setup");
    self.headerSummaryLabel.text = VCTextLiteral(@"OpenAI provider, model, and language in one place.");
    [self.runtimeSummaryCard updateTitle:VCTextLiteral(@"Current Setup")];
    [self.runtimeSummaryCard updateSubtitle:VCTextLiteral(@"OpenAI model, mode, and API key readiness.")];
    [self.modelCard updateTitle:VCTextLiteral(@"OpenAI Model")];
    [self.modelCard updateSubtitle:[self _subtitleForItem:VCSettingsItemModel]];
    [self.languageCard updateTitle:VCTextLiteral(@"Language")];
    [self.languageCard updateSubtitle:[self _subtitleForItem:VCSettingsItemLanguage]];
    [self.aboutCard updateTitle:VCTextLiteral(@"About")];
    [self.aboutCard updateSubtitle:[self _subtitleForItem:VCSettingsItemAbout]];
    [self _refreshHeroMetaBadges];
    self.versionLabel.text = [NSString stringWithFormat:@"VansonCLI v%@", [[VCConfig shared] vcVersion]];
    self.aboutOverlayTitleLabel.text = VCTextLiteral(@"About");
    [self.view setNeedsLayout];
}

- (void)_languageDidChange {
    [self _refreshLocalizedText];
    [self.modelView reload];
    if (self.aboutOverlayView.superview) {
        [self _hideAboutView];
        [self _showAboutView];
    }
}

- (void)_providerDidChange {
    [self _refreshLocalizedText];
    [self.modelView reload];
}

- (NSString *)_subtitleForItem:(VCSettingsItem)item {
    switch (item) {
        case VCSettingsItemModel: {
            VCProviderConfig *active = [[VCProviderManager shared] activeProvider];
            NSString *effectiveModel = [[VCProviderManager shared] effectiveSelectedModelForProvider:active];
            NSString *providerName = VCSettingsSafeString(active.name);
            return active ? [NSString stringWithFormat:@"%@ · %@ · %@", providerName.length > 0 ? providerName : @"OpenAI", effectiveModel.length ? effectiveModel : @"--", VCSettingsProtocolDisplayName(active.protocol)] : VCTextLiteral(@"OpenAI endpoint, API key, mode, and active model.");
        }
        case VCSettingsItemLanguage:
            return [VCLanguage languageSummaryText];
        case VCSettingsItemAbout: {
            NSString *version = [[VCConfig shared] vcVersion] ?: @"--";
            return [NSString stringWithFormat:@"VansonCLI v%@ · runtime, AI, network, and changelog.", version];
        }
        default: return @"";
    }
}

- (void)_showLanguageDrawer {
    if (self.languageDrawer.superview) return;
    VCLanguageDrawer *drawer = [[VCLanguageDrawer alloc] initWithCurrentOption:[VCLanguage preferredLanguageOption]];
    vc_weakify(self);
    drawer.onSelect = ^(NSString *option) {
        vc_strongify(self);
        [VCLanguage setPreferredLanguageOption:option];
        [self _refreshLocalizedText];
    };
    drawer.onDismiss = ^{
        vc_strongify(self);
        self.languageDrawer = nil;
    };
    self.languageDrawer = drawer;
    [self.view addSubview:drawer];
    [NSLayoutConstraint activateConstraints:@[
        [drawer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [drawer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [drawer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [drawer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [drawer showAnimated];
}

- (void)_showAboutView {
    if (self.aboutOverlayView.superview) return;

    UIView *overlay = [[UIView alloc] initWithFrame:CGRectZero];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = kVCBgTertiary;
    overlay.alpha = 0.0;

    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    VCApplyPanelSurface(header, 12.0);
    header.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    [overlay addSubview:header];

    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [backButton setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [backButton setTitle:VCTextLiteral(@"Back") forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(backButton);
    VCPrepareButtonTitle(backButton, NSLineBreakByTruncatingTail, 0.82);
    backButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    backButton.contentEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 0);
    [backButton addTarget:self action:@selector(_hideAboutView) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:backButton];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = VCTextLiteral(@"About");
    titleLabel.textColor = kVCTextPrimary;
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 1;
    [header addSubview:titleLabel];

    VCAboutTab *aboutVC = [[VCAboutTab alloc] init];
    [self addChildViewController:aboutVC];
    UIView *aboutView = aboutVC.view;
    aboutView.translatesAutoresizingMaskIntoConstraints = NO;
    [overlay addSubview:aboutView];
    [aboutVC didMoveToParentViewController:self];

    self.aboutOverlayView = overlay;
    self.aboutOverlayTitleLabel = titleLabel;
    self.aboutViewController = aboutVC;
    [self.view addSubview:overlay];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [header.topAnchor constraintEqualToAnchor:overlay.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],

        [backButton.topAnchor constraintEqualToAnchor:safeArea.topAnchor constant:8.0],
        [backButton.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:10.0],
        [backButton.widthAnchor constraintGreaterThanOrEqualToConstant:74.0],
        [backButton.heightAnchor constraintEqualToConstant:34.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:backButton.trailingAnchor constant:8.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-18.0],
        [titleLabel.centerYAnchor constraintEqualToAnchor:backButton.centerYAnchor],

        [header.bottomAnchor constraintEqualToAnchor:backButton.bottomAnchor constant:8.0],

        [aboutView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [aboutView.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [aboutView.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [aboutView.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],
    ]];

    [UIView animateWithDuration:0.2 animations:^{
        overlay.alpha = 1.0;
    }];
}

- (void)_hideAboutView {
    if (!self.aboutOverlayView.superview) return;
    UIView *overlay = self.aboutOverlayView;
    VCAboutTab *aboutVC = self.aboutViewController;
    [aboutVC willMoveToParentViewController:nil];
    [UIView animateWithDuration:0.2 animations:^{
        overlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        [overlay removeFromSuperview];
        [aboutVC removeFromParentViewController];
    }];
    self.aboutOverlayView = nil;
    self.aboutOverlayTitleLabel = nil;
    self.aboutViewController = nil;
}

#pragma mark - Model Settings Sub-page

- (void)_showModelSettings {
    if (_modelView) return;

    _modelView = [[VCModelSettingsView alloc] initWithFrame:CGRectZero];
    _modelView.translatesAutoresizingMaskIntoConstraints = NO;
    _modelView.alpha = 0;
    [_modelView reload];

    vc_weakify(self);
    _modelView.onBack = ^{
        vc_strongify(self);
        [self _hideModelSettings];
    };

    [self.view addSubview:_modelView];
    [NSLayoutConstraint activateConstraints:@[
        [_modelView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_modelView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_modelView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_modelView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [UIView animateWithDuration:0.2 animations:^{
        self->_modelView.alpha = 1;
    }];
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    self.availableLayoutBounds = bounds;
    [self.view setNeedsLayout];
    [self.modelView setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat viewWidth = CGRectGetWidth(self.view.bounds);
    CGFloat viewHeight = CGRectGetHeight(self.view.bounds);
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape || viewWidth > viewHeight) && viewWidth >= 680.0 && viewWidth > viewHeight;
    CGFloat boundsWidth = CGRectIsEmpty(self.availableLayoutBounds) ? CGRectGetWidth(self.view.bounds) : CGRectGetWidth(self.availableLayoutBounds);
    self.heroPortraitLeadingConstraint.active = !landscape;
    self.heroPortraitTrailingConstraint.active = !landscape;
    self.runtimePortraitTopConstraint.active = !landscape;
    self.runtimePortraitTrailingConstraint.active = !landscape;
    self.modelPortraitTopConstraint.active = !landscape;
    self.modelPortraitTrailingConstraint.active = !landscape;
    self.languagePortraitTrailingConstraint.active = !landscape;
    self.aboutPortraitTrailingConstraint.active = !landscape;
    self.versionPortraitTrailingConstraint.active = !landscape;

    self.heroLandscapeTrailingConstraint.active = landscape;
    self.heroLandscapeWidthConstraint.active = landscape;
    self.heroLandscapeHeightConstraint.active = landscape;
    self.runtimeLandscapeTopConstraint.active = landscape;
    self.runtimeLandscapeTrailingConstraint.active = landscape;
    self.modelLandscapeTopConstraint.active = landscape;
    self.modelLandscapeTrailingConstraint.active = landscape;
    self.languageLandscapeTrailingConstraint.active = landscape;
    self.aboutLandscapeTrailingConstraint.active = landscape;
    self.versionLandscapeTrailingConstraint.active = landscape;

    BOOL shallowLandscape = landscape && viewHeight < 340.0;
    self.heroLandscapeWidthConstraint.constant = shallowLandscape
        ? MAX(190.0, MIN(260.0, floor(boundsWidth * 0.34)))
        : MAX(268.0, MIN(348.0, floor(boundsWidth * 0.32)));
    self.heroLandscapeHeightConstraint.constant = shallowLandscape ? 118.0 : 216.0;
    self.contentDividerView.hidden = !landscape;
    self.contentDividerView.alpha = landscape ? 1.0 : 0.0;
    self.headerSummaryLabel.numberOfLines = shallowLandscape ? 1 : (landscape ? 3 : 2);
    self.headerTitleLabel.font = [UIFont systemFontOfSize:(shallowLandscape ? 15.0 : (landscape ? 19.0 : 21.0)) weight:UIFontWeightBold];
    self.headerSummaryLabel.font = [UIFont systemFontOfSize:(shallowLandscape ? 10.0 : (landscape ? 11.5 : 12.5)) weight:UIFontWeightMedium];
    self.heroMetaStack.spacing = landscape ? 4.0 : 8.0;
    self.providerMetaBadge.font = [UIFont systemFontOfSize:(shallowLandscape ? 8.5 : 10.5) weight:UIFontWeightSemibold];
    self.modelMetaBadge.font = self.providerMetaBadge.font;
    self.protocolMetaBadge.font = self.providerMetaBadge.font;
    self.versionLabel.textAlignment = landscape ? NSTextAlignmentLeft : NSTextAlignmentCenter;
}

- (void)_hideModelSettings {
    [UIView animateWithDuration:0.2 animations:^{
        self->_modelView.alpha = 0;
    } completion:^(BOOL finished) {
        [self->_modelView removeFromSuperview];
        self->_modelView = nil;
        [self _refreshLocalizedText];
    }];
}

#pragma mark - Add Provider

- (void)_addProvider {
    [self _showModelSettings];
    [self->_modelView presentNewProviderEditor];
}

@end
