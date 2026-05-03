/**
 * VCPatchCell -- Patches 列表 Cell
 */

#import "VCPatchCell.h"
#import "../../../VansonCLI.h"
#import "../../Patches/VCPatchItem.h"
#import "../../Patches/VCValueItem.h"
#import "../../Patches/VCHookItem.h"
#import "../../Patches/VCNetRule.h"

@interface VCPatchCell ()
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *typeLabel;
@property (nonatomic, strong) UILabel *remarkLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@end

@implementation VCPatchCell

static NSDictionary *VCParsePatchCellMetadata(NSString *customCode) {
    if (![customCode isKindOfClass:[NSString class]] || customCode.length == 0) return nil;
    NSData *data = [customCode dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

static BOOL VCInvalidPatchItem(VCPatchItem *item) {
    return item.className.length == 0 || item.selector.length == 0 || item.patchType.length == 0;
}

static BOOL VCInvalidValueItem(VCValueItem *item) {
    return item.targetDesc.length == 0 || item.modifiedValue.length == 0 || item.dataType.length == 0;
}

static BOOL VCInvalidHookItem(VCHookItem *item) {
    return item.className.length == 0 || item.selector.length == 0 || item.hookType.length == 0;
}

static BOOL VCInvalidRuleItem(VCNetRule *item) {
    return item.urlPattern.length == 0 || item.action.length == 0;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    UIView *selBg = [[UIView alloc] init];
    selBg.backgroundColor = kVCAccentDim;
    selBg.layer.cornerRadius = 14.0;
    self.selectedBackgroundView = selBg;

    _cardView = [[UIView alloc] init];
    _cardView.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.95];
    _cardView.layer.cornerRadius = 14.0;
    _cardView.layer.borderWidth = 1.0;
    _cardView.layer.borderColor = kVCBorder.CGColor;
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_cardView];

    // Toggle switch
    _toggleSwitch = [[UISwitch alloc] init];
    _toggleSwitch.onTintColor = kVCAccent;
    _toggleSwitch.transform = CGAffineTransformMakeScale(0.75, 0.75);
    [_toggleSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    _toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_toggleSwitch];

    // Title
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = kVCTextPrimary;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_titleLabel];

    // Type
    _typeLabel = [[UILabel alloc] init];
    _typeLabel.font = [UIFont systemFontOfSize:12];
    _typeLabel.textColor = kVCTextSecondary;
    _typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_typeLabel];

    // Remark
    _remarkLabel = [[UILabel alloc] init];
    _remarkLabel.font = [UIFont systemFontOfSize:12];
    _remarkLabel.textColor = kVCTextMuted;
    _remarkLabel.numberOfLines = 1;
    _remarkLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_remarkLabel];

    // Meta (source + time)
    _metaLabel = [[UILabel alloc] init];
    _metaLabel.font = [UIFont systemFontOfSize:11];
    _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_metaLabel];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

        [_toggleSwitch.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:12],
        [_toggleSwitch.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_toggleSwitch.trailingAnchor constant:10],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12],
        [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:10],

        [_typeLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_typeLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_typeLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],

        [_remarkLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_remarkLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_remarkLabel.topAnchor constraintEqualToAnchor:_typeLabel.bottomAnchor constant:2],

        [_metaLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_metaLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_metaLabel.topAnchor constraintEqualToAnchor:_remarkLabel.bottomAnchor constant:2],
        [_metaLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-10],
    ]];
}

- (void)switchChanged:(UISwitch *)sw {
    if ([self.delegate respondsToSelector:@selector(patchCell:didToggleEnabled:)]) {
        [self.delegate patchCell:self didToggleEnabled:sw.isOn];
    }
}

#pragma mark - Configure

- (void)configureWithPatch:(VCPatchItem *)item {
    NSDictionary *metadata = VCParsePatchCellMetadata(item.customCode);
    BOOL isClassMethod = [metadata[@"isClassMethod"] boolValue];
    if ([item.patchType isEqualToString:@"swizzle"] && metadata) {
        BOOL otherIsClassMethod = [metadata[@"otherIsClassMethod"] boolValue];
        NSString *otherClassName = metadata[@"otherClassName"] ?: @"?";
        NSString *otherSelector = metadata[@"otherSelector"] ?: @"?";
        self.titleLabel.text = [NSString stringWithFormat:@"%c[%@ %@] <-> %c[%@ %@]",
                                isClassMethod ? '+' : '-',
                                item.className ?: @"?", item.selector ?: @"?",
                                otherIsClassMethod ? '+' : '-',
                                otherClassName, otherSelector];
    } else {
        self.titleLabel.text = [NSString stringWithFormat:@"%c[%@ %@]",
                                isClassMethod ? '+' : '-',
                                item.className ?: @"?", item.selector ?: @"?"];
    }
    self.typeLabel.text = [self statusLineForType:item.patchType enabled:item.enabled safeMode:item.isDisabledBySafeMode invalid:VCInvalidPatchItem(item) source:item.source];
    [self setRemark:item.remark];
    [self setMeta:item.source date:item.createdAt];
    self.toggleSwitch.on = item.enabled;
    [self applySafeModeStyle:item.isDisabledBySafeMode title:self.titleLabel.text];
}

- (void)configureWithValue:(VCValueItem *)item {
    NSString *lockIcon = item.locked ? @"[L] " : @"";
    self.titleLabel.text = [NSString stringWithFormat:@"%@%@ = %@", lockIcon, item.targetDesc ?: @"?", item.modifiedValue ?: @"?"];
    self.typeLabel.text = [self statusLineForType:item.dataType enabled:item.locked safeMode:item.isDisabledBySafeMode invalid:VCInvalidValueItem(item) source:item.source];
    [self setRemark:item.remark];
    [self setMeta:item.source date:item.createdAt];
    self.toggleSwitch.on = item.locked;
    [self applySafeModeStyle:item.isDisabledBySafeMode title:self.titleLabel.text];
}

- (void)configureWithHook:(VCHookItem *)item {
    self.titleLabel.text = [NSString stringWithFormat:@"-[%@ %@] (%lu hits)",
                            item.className ?: @"?", item.selector ?: @"?", (unsigned long)item.hitCount];
    self.typeLabel.text = [self statusLineForType:item.hookType enabled:item.enabled safeMode:item.isDisabledBySafeMode invalid:VCInvalidHookItem(item) source:item.source];
    [self setRemark:item.remark];
    [self setMeta:item.source date:item.createdAt];
    self.toggleSwitch.on = item.enabled;
    [self applySafeModeStyle:item.isDisabledBySafeMode title:self.titleLabel.text];
}

- (void)configureWithRule:(VCNetRule *)item {
    self.titleLabel.text = [NSString stringWithFormat:@"%@ -> %@", item.urlPattern ?: @"*", item.action ?: @"?"];
    NSString *payloadSummary = item.modifications.count > 0 ? [NSString stringWithFormat:@"%@ keys", @((NSInteger)item.modifications.count)] : @"no payload";
    self.typeLabel.text = [self statusLineForType:[NSString stringWithFormat:@"%@ • %@", item.action ?: @"rule", payloadSummary]
                                          enabled:item.enabled
                                         safeMode:item.isDisabledBySafeMode
                                          invalid:VCInvalidRuleItem(item)
                                           source:item.source];
    [self setRemark:item.remark.length > 0 ? item.remark : [NSString stringWithFormat:@"match: %@", item.urlPattern ?: @"*"]];
    [self setMeta:item.source date:item.createdAt];
    self.toggleSwitch.on = item.enabled;
    [self applySafeModeStyle:item.isDisabledBySafeMode title:self.titleLabel.text];
}

#pragma mark - Helpers

- (void)setRemark:(NSString *)remark {
    if (remark.length > 0) {
        self.remarkLabel.text = [NSString stringWithFormat:@"remark: %@", remark];
        self.remarkLabel.hidden = NO;
    } else {
        self.remarkLabel.text = nil;
        self.remarkLabel.hidden = YES;
    }
}

- (NSString *)statusLineForType:(NSString *)type enabled:(BOOL)enabled safeMode:(BOOL)safeMode invalid:(BOOL)invalid source:(VCItemSource)source {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:(type ?: @"item")];
    if (invalid) [parts addObject:@"Invalid"];
    else if (safeMode) [parts addObject:@"Safe"];
    else if (!enabled) [parts addObject:@"Disabled"];
    else [parts addObject:@"Active"];
    if (source == VCItemSourceAI) [parts addObject:@"AI"];
    return [parts componentsJoinedByString:@" • "];
}

- (void)setMeta:(VCItemSource)source date:(NSDate *)date {
    NSString *srcText;
    UIColor *srcColor;
    switch (source) {
        case VCItemSourceAI:      srcText = @"AI";      srcColor = kVCAccent;       break;
        case VCItemSourceConsole: srcText = @"Console"; srcColor = kVCYellow;       break;
        case VCItemSourceManual:  srcText = @"Manual";  srcColor = kVCTextMuted;    break;
    }

    static NSDateFormatter *fmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MM-dd HH:mm";
    });

    NSString *dateStr = date ? [fmt stringFromDate:date] : @"--";
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%@ | %@", srcText, dateStr]
            attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11],
                         NSForegroundColorAttributeName: kVCTextMuted}];
    [attr addAttribute:NSForegroundColorAttributeName value:srcColor range:NSMakeRange(0, srcText.length)];
    self.metaLabel.attributedText = attr;
}

- (void)applySafeModeStyle:(BOOL)safeMode title:(NSString *)title {
    if (safeMode) {
        self.contentView.alpha = 0.4;
        self.titleLabel.text = [title stringByAppendingString:@" [SafeMode]"];
    } else {
        self.contentView.alpha = 1.0;
    }
}

@end
