/**
 * VCChatReferenceCardView -- Structured reference / artifact card
 */

#import "VCChatReferenceCardView.h"
#import "../../../VansonCLI.h"

static NSString *VCChatReferenceSafeString(id value) {
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return @"";
}

static NSString *VCChatReferenceIconName(NSString *kind, NSString *type) {
    NSString *lowerKind = [VCChatReferenceSafeString(kind) lowercaseString];
    NSString *lowerType = [VCChatReferenceSafeString(type) lowercaseString];
    if ([lowerKind isEqualToString:@"ui"] || [lowerType isEqualToString:@"selected_view"]) return @"square.on.square";
    if ([lowerKind isEqualToString:@"network"]) return @"network";
    if ([lowerKind isEqualToString:@"inspect"] || [lowerType isEqualToString:@"class"]) return @"cpu";
    if ([lowerType isEqualToString:@"trace"]) return @"point.3.connected.trianglepath.dotted";
    if ([lowerType containsString:@"snapshot"] || [lowerType containsString:@"memory"]) return @"memorychip";
    if ([lowerType isEqualToString:@"file"]) return @"doc.text";
    return @"paperclip";
}

static NSArray<NSDictionary *> *VCChatReferenceRows(NSDictionary *payload) {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray new];
    NSDictionary<NSString *, NSString *> *map = @{
        @"className": @"Class",
        @"address": @"Address",
        @"frame": @"Frame",
        @"method": @"Method",
        @"url": @"URL",
        @"statusCode": @"Status",
        @"mimeType": @"MIME",
        @"moduleName": @"Module",
        @"path": @"Path",
        @"diagramType": @"Diagram"
    };
    NSArray<NSString *> *order = @[@"className", @"address", @"frame", @"method", @"url", @"statusCode", @"mimeType", @"moduleName", @"path", @"diagramType"];
    for (NSString *key in order) {
        NSString *value = VCChatReferenceSafeString(payload[key]);
        if (value.length == 0) continue;
        [rows addObject:@{@"label": map[key] ?: key, @"value": value}];
        if (rows.count >= 3) break;
    }
    return [rows copy];
}

static NSString *VCChatReferenceSummary(NSDictionary *payload) {
    NSString *summary = VCChatReferenceSafeString(payload[@"summary"]);
    if (summary.length > 0) return summary;

    NSString *type = [VCChatReferenceSafeString(payload[@"type"]) lowercaseString];
    if ([type isEqualToString:@"selected_view"]) {
        NSString *className = VCChatReferenceSafeString(payload[@"className"]);
        NSString *frame = VCChatReferenceSafeString(payload[@"frame"]);
        if (className.length || frame.length) {
            return [NSString stringWithFormat:@"%@ %@", className ?: @"UIView", frame ?: @""];
        }
    }
    if ([type isEqualToString:@"class"]) {
        NSString *moduleName = VCChatReferenceSafeString(payload[@"moduleName"]);
        NSString *superClassName = VCChatReferenceSafeString(payload[@"superClassName"]);
        NSMutableArray<NSString *> *parts = [NSMutableArray new];
        if (moduleName.length) [parts addObject:moduleName];
        if (superClassName.length) [parts addObject:[NSString stringWithFormat:@"inherits %@", superClassName]];
        if (parts.count > 0) return [parts componentsJoinedByString:@" • "];
    }
    if (payload[@"matchedRules"]) {
        NSArray *rules = [payload[@"matchedRules"] isKindOfClass:[NSArray class]] ? payload[@"matchedRules"] : @[];
        if (rules.count > 0) return [NSString stringWithFormat:@"%lu matched rule%@", (unsigned long)rules.count, rules.count == 1 ? @"" : @"s"];
    }
    return @"";
}

@interface VCChatReferenceCardView ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *kindLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIStackView *rowStack;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIView *detailContainer;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) NSLayoutConstraint *collapsedBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *expandedBottomConstraint;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, copy) NSString *detailText;
@property (nonatomic, strong) UIColor *baseSurfaceColor;
@property (nonatomic, strong) UIColor *baseBorderColor;
@end

@implementation VCChatReferenceCardView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.layer.cornerRadius = 12.0;
        self.layer.borderWidth = 1.0;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];

        _kindLabel = [[UILabel alloc] init];
        _kindLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
        _kindLabel.numberOfLines = 1;
        _kindLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _kindLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_kindLabel];

        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        _chevronView.tintColor = [kVCTextMuted colorWithAlphaComponent:0.9];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_chevronView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
        _titleLabel.textColor = kVCTextPrimary;
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _summaryLabel = [[UILabel alloc] init];
        _summaryLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
        _summaryLabel.textColor = kVCTextMuted;
        _summaryLabel.numberOfLines = 2;
        _summaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_summaryLabel];

        _rowStack = [[UIStackView alloc] init];
        _rowStack.axis = UILayoutConstraintAxisVertical;
        _rowStack.spacing = 4.0;
        _rowStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_rowStack];

        _hintLabel = [[UILabel alloc] init];
        _hintLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
        _hintLabel.textColor = kVCTextMuted;
        _hintLabel.numberOfLines = 1;
        _hintLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_hintLabel];

        _detailContainer = [[UIView alloc] init];
        VCApplyInputSurface(_detailContainer, 10.0);
        _detailContainer.backgroundColor = [kVCBgInput colorWithAlphaComponent:0.74];
        _detailContainer.hidden = YES;
        _detailContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_detailContainer];

        _detailLabel = [[UILabel alloc] init];
        _detailLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightMedium];
        _detailLabel.textColor = kVCTextSecondary;
        _detailLabel.numberOfLines = 0;
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_detailContainer addSubview:_detailLabel];

        _collapsedBottomConstraint = [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8];
        _expandedBottomConstraint = [_detailContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [_iconView.widthAnchor constraintEqualToConstant:15],
            [_iconView.heightAnchor constraintEqualToConstant:15],

            [_kindLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:7],
            [_kindLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:7],
            [_kindLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-8],

            [_chevronView.centerYAnchor constraintEqualToAnchor:_kindLabel.centerYAnchor],
            [_chevronView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_chevronView.widthAnchor constraintEqualToConstant:10],
            [_chevronView.heightAnchor constraintEqualToConstant:10],

            [_titleLabel.topAnchor constraintEqualToAnchor:_kindLabel.bottomAnchor constant:3],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_kindLabel.leadingAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],

            [_summaryLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:5],
            [_summaryLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_summaryLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],

            [_rowStack.topAnchor constraintEqualToAnchor:_summaryLabel.bottomAnchor constant:7],
            [_rowStack.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_rowStack.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_hintLabel.topAnchor constraintEqualToAnchor:_rowStack.bottomAnchor constant:7],
            [_hintLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_hintLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_detailContainer.topAnchor constraintEqualToAnchor:_hintLabel.bottomAnchor constant:7],
            [_detailContainer.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_detailContainer.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_detailLabel.topAnchor constraintEqualToAnchor:_detailContainer.topAnchor constant:8],
            [_detailLabel.leadingAnchor constraintEqualToAnchor:_detailContainer.leadingAnchor constant:9],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:_detailContainer.trailingAnchor constant:-9],
            [_detailLabel.bottomAnchor constraintEqualToAnchor:_detailContainer.bottomAnchor constant:-8],
            _collapsedBottomConstraint,
        ]];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_toggleExpanded)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (UIView *)_metricPillWithText:(NSString *)text role:(NSString *)role {
    BOOL isUser = [role isEqualToString:@"user"];
    UIView *pill = [[UIView alloc] init];
    pill.backgroundColor = isUser ? [UIColor colorWithWhite:1.0 alpha:0.08] : [kVCBgSurface colorWithAlphaComponent:0.64];
    pill.layer.cornerRadius = 9.0;
    pill.layer.borderWidth = 1.0;
    pill.layer.borderColor = (isUser ? [UIColor colorWithWhite:1.0 alpha:0.12] : [kVCBorder colorWithAlphaComponent:0.78]).CGColor;
    pill.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 1;
    label.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightMedium];
    label.textColor = isUser ? [kVCTextPrimary colorWithAlphaComponent:0.84] : kVCTextSecondary;
    label.text = text;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.78;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [pill addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:pill.topAnchor constant:6],
        [label.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:8],
        [label.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-8],
        [label.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-6],
    ]];
    return pill;
}

- (void)_animateTapFeedback {
    [UIView animateWithDuration:0.08
                     animations:^{
        self.transform = CGAffineTransformMakeScale(0.988, 0.988);
        self.layer.borderColor = [self.baseBorderColor colorWithAlphaComponent:1.0].CGColor;
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.16
                         animations:^{
            self.transform = CGAffineTransformIdentity;
            self.layer.borderColor = self.baseBorderColor.CGColor;
        }];
    }];
}

- (void)_toggleExpanded {
    if (self.detailText.length == 0) return;
    [self _animateTapFeedback];
    self.expanded = !self.expanded;
    [self _applyExpandedStateAnimated:YES];
    self.hintLabel.text = self.expanded ? VCTextLiteral(@"Tap to collapse details") : VCTextLiteral(@"Tap to expand details");
}

- (void)_applyExpandedStateAnimated:(BOOL)animated {
    self.collapsedBottomConstraint.active = !self.expanded;
    self.expandedBottomConstraint.active = self.expanded;
    self.summaryLabel.hidden = !self.expanded || self.summaryLabel.text.length == 0;
    self.rowStack.hidden = !self.expanded || self.rowStack.arrangedSubviews.count == 0;
    self.hintLabel.hidden = !self.expanded || self.detailText.length == 0;
    if (!self.expanded) self.detailContainer.hidden = YES;

    void (^changes)(void) = ^{
        self.chevronView.transform = self.expanded ? CGAffineTransformMakeRotation((CGFloat)M_PI_2) : CGAffineTransformIdentity;
        self.summaryLabel.textColor = self.expanded ? kVCTextSecondary : kVCTextMuted;
        self.backgroundColor = self.expanded ? [self.baseSurfaceColor colorWithAlphaComponent:1.0] : self.baseSurfaceColor;
        if (self.expanded) self.detailContainer.hidden = NO;
        [self.superview layoutIfNeeded];
    };
    if (!animated) {
        changes();
    } else {
    [UIView animateWithDuration:0.18 animations:^{
        changes();
    }];
    }

    UITableView *tableView = (UITableView *)self.superview;
    while (tableView && ![tableView isKindOfClass:[UITableView class]]) tableView = (UITableView *)tableView.superview;
    [tableView beginUpdates];
    [tableView endUpdates];
}

- (void)configureWithKind:(NSString *)kind
                    title:(NSString *)title
                  payload:(NSDictionary *)payload
                     role:(NSString *)role {
    NSString *type = VCChatReferenceSafeString(payload[@"type"]);
    BOOL isUser = [role isEqualToString:@"user"];
    UIColor *surface = isUser ? [kVCBgInput colorWithAlphaComponent:0.58] : [kVCBgHover colorWithAlphaComponent:0.72];
    UIColor *border = isUser ? [kVCAccent colorWithAlphaComponent:0.26] : [kVCBorderStrong colorWithAlphaComponent:0.84];
    UIColor *accent = isUser ? kVCAccentHover : kVCAccentHover;

    self.baseSurfaceColor = surface;
    self.baseBorderColor = border;
    self.backgroundColor = surface;
    self.layer.borderColor = border.CGColor;
    self.iconView.image = [UIImage systemImageNamed:VCChatReferenceIconName(kind, type)];
    self.iconView.tintColor = accent;
    self.kindLabel.text = [[VCChatReferenceSafeString(kind) uppercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.kindLabel.textColor = accent;
    self.titleLabel.text = VCChatReferenceSafeString(title);
    self.titleLabel.textColor = isUser ? [kVCTextPrimary colorWithAlphaComponent:0.95] : kVCTextPrimary;
    self.summaryLabel.text = VCChatReferenceSummary(payload);

    for (UIView *view in [self.rowStack.arrangedSubviews copy]) {
        [self.rowStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    for (NSDictionary *row in VCChatReferenceRows(payload)) {
        NSString *text = [NSString stringWithFormat:@"%@: %@", VCChatReferenceSafeString(row[@"label"]), VCChatReferenceSafeString(row[@"value"])];
        [self.rowStack addArrangedSubview:[self _metricPillWithText:text role:role]];
    }

    self.rowStack.hidden = (self.rowStack.arrangedSubviews.count == 0);
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:(payload ?: @{}) options:NSJSONWritingPrettyPrinted error:nil];
    NSString *detail = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : payload.description;
    if (detail.length > 1800) {
        detail = [[detail substringToIndex:1800] stringByAppendingString:@"\n…"];
    }
    self.detailText = detail ?: @"";
    self.detailLabel.text = self.detailText;
    self.expanded = NO;
    self.chevronView.hidden = (self.detailText.length == 0);
    self.hintLabel.text = self.detailText.length > 0 ? VCTextLiteral(@"Tap to expand details") : @"";
    [self _applyExpandedStateAnimated:NO];
}

@end
