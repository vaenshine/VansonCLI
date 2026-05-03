/**
 * VCChatStatusBannerView -- Compact status banner for chat messages
 */

#import "VCChatStatusBannerView.h"
#import "../../../VansonCLI.h"

static NSString *VCChatStatusSafeString(id value) {
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
}

@interface VCChatStatusBannerView ()
@property (nonatomic, strong) UIView *accentBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *contentLabel;
@end

@implementation VCChatStatusBannerView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.layer.cornerRadius = 12.0;
        self.layer.borderWidth = 1.0;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _accentBar = [[UIView alloc] init];
        _accentBar.layer.cornerRadius = 1.5;
        _accentBar.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_accentBar];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _contentLabel = [[UILabel alloc] init];
        _contentLabel.numberOfLines = 0;
        _contentLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
        _contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_contentLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_accentBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_accentBar.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_accentBar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
            [_accentBar.widthAnchor constraintEqualToConstant:3.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_accentBar.trailingAnchor constant:10],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],

            [_contentLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
            [_contentLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_contentLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_contentLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                   content:(NSString *)content
                      tone:(NSString *)tone {
    NSString *safeTone = VCChatStatusSafeString(tone);
    UIColor *accent = kVCAccent;
    UIColor *surface = [kVCAccentDim colorWithAlphaComponent:0.45];
    UIColor *border = [kVCAccent colorWithAlphaComponent:0.18];

    if ([safeTone isEqualToString:@"error"]) {
        accent = kVCRed;
        surface = [kVCRedDim colorWithAlphaComponent:0.55];
        border = [kVCRed colorWithAlphaComponent:0.18];
    } else if ([safeTone isEqualToString:@"warning"]) {
        accent = kVCYellow;
        surface = [kVCYellow colorWithAlphaComponent:0.10];
        border = [kVCYellow colorWithAlphaComponent:0.18];
    } else if ([safeTone isEqualToString:@"success"]) {
        accent = kVCGreen;
        surface = [kVCGreenDim colorWithAlphaComponent:0.55];
        border = [kVCGreen colorWithAlphaComponent:0.18];
    }

    self.backgroundColor = surface;
    self.layer.borderColor = border.CGColor;
    self.accentBar.backgroundColor = accent;
    self.titleLabel.text = VCChatStatusSafeString(title).length > 0 ? VCChatStatusSafeString(title) : VCTextLiteral(@"Status");
    self.titleLabel.textColor = accent;
    self.contentLabel.text = VCChatStatusSafeString(content);
    self.contentLabel.hidden = (VCChatStatusSafeString(content).length == 0);
    self.contentLabel.textColor = kVCTextPrimary;
}

@end
