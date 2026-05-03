/**
 * VCModelSelector -- Inline provider/model drawer
 */

#import "VCModelSelector.h"
#import "../../../VansonCLI.h"
#import "../../AI/Models/VCProviderManager.h"
#import "../../AI/Models/VCProviderConfig.h"

@interface VCModelSelectorRow : UIControl
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIView *stateBadge;
@property (nonatomic, strong) UILabel *stateLabel;
- (instancetype)initWithTitle:(NSString *)title meta:(NSString *)meta state:(NSString *)state selected:(BOOL)selected;
@end

@interface VCModelSelectorSheet : UIView
@property (nonatomic, copy) VCModelSelectorCompletion completion;
@property (nonatomic, copy) NSArray<VCProviderConfig *> *providers;
@property (nonatomic, strong) VCProviderConfig *selectedProvider;
@property (nonatomic, strong) UIControl *backdrop;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *handleView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIScrollView *providerScroll;
@property (nonatomic, strong) UIView *providerContentView;
@property (nonatomic, strong) UIStackView *providerStack;
@property (nonatomic, strong) UIScrollView *modelScroll;
@property (nonatomic, strong) UIStackView *modelStack;
@property (nonatomic, strong) UIButton *dismissButton;
@property (nonatomic, strong) NSLayoutConstraint *providerScrollHeightConstraint;
- (void)_updateModelContentLayout;
- (instancetype)initWithProviders:(NSArray<VCProviderConfig *> *)providers completion:(VCModelSelectorCompletion)completion;
- (void)presentInView:(UIView *)view;
@end

@implementation VCModelSelectorRow

- (instancetype)initWithTitle:(NSString *)title meta:(NSString *)meta state:(NSString *)state selected:(BOOL)selected {
    if (self = [super initWithFrame:CGRectZero]) {
        self.backgroundColor = [kVCBgHover colorWithAlphaComponent:0.86];
        self.layer.cornerRadius = 16.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = kVCBorder.CGColor;
        self.clipsToBounds = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        [[self.heightAnchor constraintEqualToConstant:68.0] setActive:YES];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.text = title ?: VCTextLiteral(@"Model");
        _titleLabel.textColor = kVCTextPrimary;
        _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _titleLabel.numberOfLines = 2;
        [self addSubview:_titleLabel];

        _metaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _metaLabel.text = meta ?: @"";
        _metaLabel.textColor = kVCTextSecondary;
        _metaLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _metaLabel.numberOfLines = 1;
        [self addSubview:_metaLabel];

        _stateBadge = [[UIView alloc] initWithFrame:CGRectZero];
        _stateBadge.layer.cornerRadius = 11.0;
        _stateBadge.layer.borderWidth = 1.0;
        [self addSubview:_stateBadge];

        _stateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _stateLabel.text = state ?: @"";
        _stateLabel.textAlignment = NSTextAlignmentCenter;
        _stateLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        [_stateBadge addSubview:_stateLabel];

        self.selected = selected;
        [self _applyAppearance];
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self _applyAppearance];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.86 : 1.0;
}

- (void)_applyAppearance {
    BOOL active = self.selected;
    self.backgroundColor = active ? [kVCGreen colorWithAlphaComponent:0.12] : [kVCBgHover colorWithAlphaComponent:0.86];
    self.layer.borderColor = (active ? [kVCGreen colorWithAlphaComponent:0.32].CGColor : kVCBorder.CGColor);
    self.titleLabel.textColor = active ? kVCTextPrimary : kVCTextPrimary;
    self.metaLabel.textColor = active ? kVCGreen : kVCTextSecondary;
    self.stateBadge.backgroundColor = active ? [kVCGreen colorWithAlphaComponent:0.18] : kVCAccentDim;
    self.stateBadge.layer.borderColor = (active ? [kVCGreen colorWithAlphaComponent:0.30].CGColor : kVCBorderAccent.CGColor);
    self.stateLabel.textColor = active ? kVCGreen : kVCTextPrimary;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat inset = 14.0;
    CGFloat badgeInset = 12.0;
    CGSize badgeLabelSize = [self.stateLabel sizeThatFits:CGSizeMake(120.0, 20.0)];
    CGFloat badgeWidth = MIN(MAX(badgeLabelSize.width + 20.0, 64.0), 110.0);
    CGFloat badgeHeight = 26.0;
    self.stateBadge.frame = CGRectMake(CGRectGetWidth(self.bounds) - inset - badgeWidth,
                                       (CGRectGetHeight(self.bounds) - badgeHeight) * 0.5,
                                       badgeWidth,
                                       badgeHeight);
    self.stateLabel.frame = CGRectMake(0, 0, badgeWidth, badgeHeight);

    CGFloat contentWidth = MAX(CGRectGetMinX(self.stateBadge.frame) - inset - badgeInset, 72.0);
    CGFloat titleMaxHeight = self.metaLabel.text.length > 0 ? 22.0 : 38.0;
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(contentWidth, CGFLOAT_MAX)];
    CGFloat titleHeight = MIN(MAX(titleSize.height, 18.0), titleMaxHeight);
    CGFloat totalHeight = titleHeight + (self.metaLabel.text.length > 0 ? 18.0 : 0.0);
    CGFloat originY = MAX((CGRectGetHeight(self.bounds) - totalHeight) * 0.5, 10.0);
    self.titleLabel.frame = CGRectMake(inset, originY, contentWidth, titleHeight);
    self.metaLabel.frame = CGRectMake(inset,
                                      CGRectGetMaxY(self.titleLabel.frame) + (self.metaLabel.text.length > 0 ? 2.0 : 0.0),
                                      contentWidth,
                                      self.metaLabel.text.length > 0 ? 16.0 : 0.0);
}

@end

@implementation VCModelSelectorSheet

- (instancetype)initWithProviders:(NSArray<VCProviderConfig *> *)providers completion:(VCModelSelectorCompletion)completion {
    if (self = [super initWithFrame:CGRectZero]) {
        _providers = [providers copy] ?: @[];
        _completion = [completion copy];
        _selectedProvider = [[VCProviderManager shared] activeProvider] ?: _providers.firstObject;
        self.backgroundColor = [UIColor clearColor];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self _buildUI];
        [self _reloadProviderButtons];
        [self _reloadModelButtons];
    }
    return self;
}

- (void)_buildUI {
    _backdrop = [[UIControl alloc] initWithFrame:CGRectZero];
    _backdrop.backgroundColor = [kVCBgPrimary colorWithAlphaComponent:0.58];
    _backdrop.alpha = 0.0;
    [_backdrop addTarget:self action:@selector(_dismissTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_backdrop];

    _cardView = [[UIView alloc] initWithFrame:CGRectZero];
    _cardView.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.985];
    _cardView.layer.cornerRadius = 22.0;
    _cardView.layer.borderWidth = 1.0;
    _cardView.layer.borderColor = kVCBorderStrong.CGColor;
    _cardView.layer.shadowColor = [kVCBgPrimary colorWithAlphaComponent:0.92].CGColor;
    _cardView.layer.shadowOpacity = 0.36;
    _cardView.layer.shadowRadius = 20.0;
    _cardView.layer.shadowOffset = CGSizeMake(0, 8);
    if (@available(iOS 13.0, *)) {
        _cardView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [self addSubview:_cardView];

    _handleView = [[UIView alloc] init];
    _handleView.translatesAutoresizingMaskIntoConstraints = NO;
    _handleView.backgroundColor = kVCTextMuted;
    _handleView.layer.cornerRadius = 2.0;
    [_cardView addSubview:_handleView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = VCTextLiteral(@"Model Workspace");
    _titleLabel.textColor = kVCTextPrimary;
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    _titleLabel.numberOfLines = 1;
    [_cardView addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.textColor = kVCTextSecondary;
    _subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _subtitleLabel.numberOfLines = 2;
    [_cardView addSubview:_subtitleLabel];

    _dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _dismissButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_dismissButton setTitle:VCTextLiteral(@"Done") forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(_dismissButton);
    _dismissButton.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    _dismissButton.adjustsImageWhenHighlighted = NO;
    [_dismissButton addTarget:self action:@selector(_dismissTapped) forControlEvents:UIControlEventTouchUpInside];
    [_cardView addSubview:_dismissButton];

    _providerScroll = [[UIScrollView alloc] init];
    _providerScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _providerScroll.showsHorizontalScrollIndicator = NO;
    _providerScroll.backgroundColor = [UIColor clearColor];
    [_cardView addSubview:_providerScroll];

    _providerContentView = [[UIView alloc] init];
    _providerContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [_providerScroll addSubview:_providerContentView];

    _providerStack = [[UIStackView alloc] init];
    _providerStack.translatesAutoresizingMaskIntoConstraints = NO;
    _providerStack.axis = UILayoutConstraintAxisHorizontal;
    _providerStack.spacing = 8.0;
    [_providerContentView addSubview:_providerStack];

    _modelScroll = [[UIScrollView alloc] init];
    _modelScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _modelScroll.showsVerticalScrollIndicator = YES;
    _modelScroll.backgroundColor = [UIColor clearColor];
    [_cardView addSubview:_modelScroll];

    _modelStack = [[UIStackView alloc] init];
    _modelStack.translatesAutoresizingMaskIntoConstraints = NO;
    _modelStack.axis = UILayoutConstraintAxisVertical;
    _modelStack.spacing = 10.0;
    [_modelScroll addSubview:_modelStack];

    self.providerScrollHeightConstraint = [self.providerScroll.heightAnchor constraintEqualToConstant:42.0];
    self.providerScrollHeightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.handleView.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:8.0],
        [self.handleView.centerXAnchor constraintEqualToAnchor:self.cardView.centerXAnchor],
        [self.handleView.widthAnchor constraintEqualToConstant:36.0],
        [self.handleView.heightAnchor constraintEqualToConstant:4.0],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:16.0],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:16.0],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.dismissButton.leadingAnchor constant:-10.0],

        [self.dismissButton.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16.0],
        [self.dismissButton.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.dismissButton.heightAnchor constraintEqualToConstant:30.0],
        [self.dismissButton.widthAnchor constraintGreaterThanOrEqualToConstant:64.0],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6.0],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16.0],

        [self.providerScroll.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:6.0],
        [self.providerScroll.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:16.0],
        [self.providerScroll.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16.0],

        [self.modelScroll.topAnchor constraintEqualToAnchor:self.providerScroll.bottomAnchor constant:2.0],
        [self.modelScroll.leadingAnchor constraintEqualToAnchor:self.providerScroll.leadingAnchor],
        [self.modelScroll.trailingAnchor constraintEqualToAnchor:self.providerScroll.trailingAnchor],
        [self.modelScroll.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-16.0],

        [self.providerContentView.topAnchor constraintEqualToAnchor:self.providerScroll.contentLayoutGuide.topAnchor],
        [self.providerContentView.leadingAnchor constraintEqualToAnchor:self.providerScroll.contentLayoutGuide.leadingAnchor],
        [self.providerContentView.trailingAnchor constraintEqualToAnchor:self.providerScroll.contentLayoutGuide.trailingAnchor],
        [self.providerContentView.bottomAnchor constraintEqualToAnchor:self.providerScroll.contentLayoutGuide.bottomAnchor],
        [self.providerContentView.heightAnchor constraintEqualToAnchor:self.providerScroll.frameLayoutGuide.heightAnchor],

        [self.providerStack.topAnchor constraintEqualToAnchor:self.providerContentView.topAnchor constant:4.0],
        [self.providerStack.leadingAnchor constraintEqualToAnchor:self.providerContentView.leadingAnchor],
        [self.providerStack.trailingAnchor constraintEqualToAnchor:self.providerContentView.trailingAnchor],
        [self.providerStack.bottomAnchor constraintEqualToAnchor:self.providerContentView.bottomAnchor constant:-4.0],
        [self.providerStack.heightAnchor constraintEqualToConstant:34.0],

        [self.modelStack.topAnchor constraintEqualToAnchor:self.modelScroll.contentLayoutGuide.topAnchor],
        [self.modelStack.leadingAnchor constraintEqualToAnchor:self.modelScroll.contentLayoutGuide.leadingAnchor],
        [self.modelStack.trailingAnchor constraintEqualToAnchor:self.modelScroll.contentLayoutGuide.trailingAnchor],
        [self.modelStack.bottomAnchor constraintEqualToAnchor:self.modelScroll.contentLayoutGuide.bottomAnchor],
        [self.modelStack.widthAnchor constraintEqualToAnchor:self.modelScroll.frameLayoutGuide.widthAnchor],
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.backdrop.frame = self.bounds;

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    BOOL landscape = (width > height);
    CGFloat horizontalInset = landscape ? MIN(MAX(width * 0.08, 28.0), 72.0) : MIN(MAX(width * 0.04, 14.0), 22.0);
    CGFloat cardWidth = landscape ? MIN(MAX(width * 0.72, 480.0), 760.0) : (width - (horizontalInset * 2.0));
    CGFloat cardHeight = landscape ? MIN(MAX(height * 0.72, 320.0), 520.0) : MIN(MAX(height * 0.5, 302.0), 396.0);
    CGFloat cardX = landscape ? floor((width - cardWidth) * 0.5) : horizontalInset;
    CGFloat cardY = landscape ? floor((height - cardHeight) * 0.5) : (height - cardHeight - 14.0);
    self.cardView.frame = CGRectMake(cardX, cardY, cardWidth, cardHeight);
    self.cardView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.cardView.bounds cornerRadius:self.cardView.layer.cornerRadius].CGPath;
    self.subtitleLabel.numberOfLines = landscape ? 1 : 2;
    BOOL showsProviderSwitchRow = (self.providers.count > 1);
    self.handleView.hidden = landscape;
    self.providerScroll.hidden = !showsProviderSwitchRow;
    self.providerScrollHeightConstraint.constant = showsProviderSwitchRow ? 42.0 : 0.0;
    [self.cardView layoutIfNeeded];
    [self _updateModelContentLayout];
}

- (UIButton *)_chipButtonWithTitle:(NSString *)title selected:(BOOL)selected action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:selected ? kVCBgPrimary : kVCTextPrimary forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    button.backgroundColor = selected ? kVCAccent : kVCAccentDim;
    button.layer.cornerRadius = 12.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = (selected ? kVCAccent : kVCBorderAccent).CGColor;
    button.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
    button.adjustsImageWhenHighlighted = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button sizeToFit];
    CGRect frame = button.frame;
    frame.size.width += 20;
    frame.size.height = 34;
    button.frame = frame;
    return button;
}

- (void)_reloadProviderButtons {
    for (UIView *view in [self.providerStack.arrangedSubviews copy]) {
        [self.providerStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    for (NSUInteger idx = 0; idx < self.providers.count; idx++) {
        VCProviderConfig *provider = self.providers[idx];
        BOOL isSelected = [provider.providerID isEqualToString:self.selectedProvider.providerID];
        UIButton *button = [self _chipButtonWithTitle:provider.name ?: @"Provider"
                                             selected:isSelected
                                               action:@selector(_providerTapped:)];
        button.tag = idx;
        [self.providerStack addArrangedSubview:button];
    }

    self.providerScroll.hidden = (self.providers.count <= 1);
    [self setNeedsLayout];
}

- (void)_reloadModelButtons {
    for (UIView *view in [self.modelStack.arrangedSubviews copy]) {
        [self.modelStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    VCProviderConfig *provider = self.selectedProvider;
    NSString *effectiveModel = [[VCProviderManager shared] effectiveSelectedModelForProvider:provider];
    if (!provider) {
        self.subtitleLabel.text = VCTextLiteral(@"Add a provider in Settings first, then come back here to switch models.");
        UILabel *emptyLabel = [[UILabel alloc] init];
        emptyLabel.text = VCTextLiteral(@"No providers configured");
        emptyLabel.textColor = kVCTextMuted;
        emptyLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        emptyLabel.textAlignment = NSTextAlignmentLeft;
        emptyLabel.numberOfLines = 0;
        emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.modelStack addArrangedSubview:emptyLabel];
    } else if (provider.models.count == 0) {
        self.subtitleLabel.text = [NSString stringWithFormat:VCTextLiteral(@"%@ is active. Add models in Settings to make the picker richer."), provider.name ?: VCTextLiteral(@"Provider")];
        VCModelSelectorRow *fallback = [[VCModelSelectorRow alloc] initWithTitle:(effectiveModel.length ? effectiveModel : VCTextLiteral(@"Use Current Provider Default"))
                                                                            meta:VCTextLiteral(@"Use the provider fallback and return to chat")
                                                                           state:VCTextLiteral(@"Use")
                                                                        selected:YES];
        [fallback addTarget:self action:@selector(_useProviderDefault) forControlEvents:UIControlEventTouchUpInside];
        [self.modelStack addArrangedSubview:fallback];
    } else {
        self.subtitleLabel.text = [NSString stringWithFormat:@"%@ • %lu models", provider.name ?: @"Provider", (unsigned long)provider.models.count];
        for (NSString *model in provider.models) {
            BOOL isSelected = [model isEqualToString:effectiveModel];
            VCModelSelectorRow *row = [[VCModelSelectorRow alloc] initWithTitle:model
                                                                           meta:(isSelected ? VCTextLiteral(@"Current active model") : VCTextLiteral(@"Tap to switch without leaving chat"))
                                                                          state:(isSelected ? VCTextLiteral(@"Active") : VCTextLiteral(@"Switch"))
                                                                       selected:isSelected];
            row.accessibilityIdentifier = model;
            [row addTarget:self action:@selector(_modelTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.modelStack addArrangedSubview:row];
        }
    }

    [self _updateModelContentLayout];
    [self setNeedsLayout];
}

- (UIButton *)_modelButtonWithTitle:(NSString *)title subtitle:(NSString *)subtitle selected:(BOOL)selected {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 12, 12, 12);
    button.backgroundColor = selected ? [kVCGreen colorWithAlphaComponent:0.14] : [kVCBgHover colorWithAlphaComponent:0.76];
    button.layer.cornerRadius = 14.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = (selected ? [kVCGreen colorWithAlphaComponent:0.35].CGColor : kVCBorder.CGColor);
    [button setTitleColor:kVCTextPrimary forState:UIControlStateNormal];

    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", title ?: @"Model", subtitle ?: @""]
                                                                             attributes:@{
                                                                                 NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold],
                                                                                 NSForegroundColorAttributeName: kVCTextPrimary
                                                                             }];
    if (subtitle.length > 0) {
        [text addAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: selected ? kVCGreen : kVCTextSecondary
        } range:NSMakeRange(title.length + 1, subtitle.length)];
    }
    [button setAttributedTitle:text forState:UIControlStateNormal];
    button.titleLabel.numberOfLines = 2;
    button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    button.adjustsImageWhenHighlighted = NO;
    button.frame = CGRectMake(0, 0, self.bounds.size.width - 28, 58);
    return button;
}

- (void)_updateModelContentLayout {
    [self.modelStack setNeedsLayout];
    [self.modelStack layoutIfNeeded];
    [self.modelScroll layoutIfNeeded];
}

- (void)_providerTapped:(UIButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.providers.count) return;
    self.selectedProvider = self.providers[sender.tag];
    [self _reloadProviderButtons];
    [self _reloadModelButtons];
}

- (void)_modelTapped:(UIButton *)sender {
    NSString *model = sender.accessibilityIdentifier ?: @"";
    if (!self.selectedProvider) return;
    if (self.completion) {
        self.completion(self.selectedProvider.providerID, model);
    }
    [self _dismiss];
}

- (void)_useProviderDefault {
    if (!self.selectedProvider) return;
    if (self.completion) {
        NSString *effectiveModel = [[VCProviderManager shared] effectiveSelectedModelForProvider:self.selectedProvider];
        self.completion(self.selectedProvider.providerID, effectiveModel ?: @"");
    }
    [self _dismiss];
}

- (void)presentInView:(UIView *)view {
    if (!view) return;
    self.alpha = 1.0;
    [view addSubview:self];
    [NSLayoutConstraint activateConstraints:@[
        [self.topAnchor constraintEqualToAnchor:view.topAnchor],
        [self.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [self.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
    ]];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    self.cardView.alpha = 0.0;
    self.cardView.transform = CGAffineTransformMakeTranslation(0, 26);

    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.backdrop.alpha = 1.0;
    } completion:nil];

    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.2 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.cardView.alpha = 1.0;
        self.cardView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)_dismissTapped {
    [self _dismiss];
}

- (void)_dismiss {
    [UIView animateWithDuration:0.18 animations:^{
        self.backdrop.alpha = 0.0;
        self.cardView.transform = CGAffineTransformMakeTranslation(0, 22);
        self.cardView.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

@end

@implementation VCModelSelector

+ (void)showFromViewController:(UIViewController *)vc completion:(VCModelSelectorCompletion)completion {
    NSArray<VCProviderConfig *> *providers = [[VCProviderManager shared] allProviders];
    VCModelSelectorSheet *sheet = [[VCModelSelectorSheet alloc] initWithProviders:providers completion:completion];
    UIView *hostView = vc.view ?: vc.view.window;
    [sheet presentInView:hostView];
}

@end
