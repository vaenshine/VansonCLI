/**
 * VCAboutTab -- About Tab
 * Version, credits, environment info
 */

#import "VCAboutTab.h"
#import "../../../VansonCLI.h"
#import "../../Core/VCConfig.h"
#import "../Base/VCBrandIcon.h"

@interface VCAboutTab ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *updateStatusLabel;
@property (nonatomic, strong) UIButton *updateCheckButton;
@property (nonatomic, copy) NSString *latestReleaseURL;
@end

@implementation VCAboutTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;

    [self _buildLayout];
    VCInstallKeyboardDismissAccessory(self.view);
}

#pragma mark - Layout

- (UIView *)_makeCardView {
    UIView *card = [[UIView alloc] init];
    VCApplyPanelSurface(card, 12.0);
    if (@available(iOS 13.0, *)) {
        card.layer.cornerCurve = kCACornerCurveContinuous;
    }
    return card;
}

- (UILabel *)_monoDetailLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = kVCFontMonoSm;
    label.textColor = kVCTextSecondary;
    label.numberOfLines = 2;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return label;
}

- (void)_buildLayout {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 10.0;
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.contentStack];

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

        [self.contentStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14],
    ]];

    [self.contentStack addArrangedSubview:[self _buildHeroCard]];
    [self.contentStack addArrangedSubview:[self _buildLinksCard]];
    [self.contentStack addArrangedSubview:[self _buildUpdateCard]];
    [self.contentStack addArrangedSubview:[self _buildEnvironmentCard]];
    [self.contentStack addArrangedSubview:[self _sectionCardWithTitle:VCTextLiteral(@"Capabilities")
                                                           subtitle:VCTextLiteral(@"Primary tools available in this injected workspace")
                                                             accent:kVCTextSecondary
                                                              lines:@[
                                                                  @"Runtime Inspector (ObjC classes, methods, ivars)",
                                                                  @"UI Hierarchy Inspector + Touch Select",
                                                                  @"Network Monitor (HTTP/HTTPS/WebSocket)",
                                                                  @"AI Chat (Multi-provider, Tool Call)",
                                                                  @"Code Editor + Project Export",
                                                                  @"CLI Console + Command Aliases",
                                                                  @"Patch Manager (Methods, Values, Hooks, Rules)"
                                                              ]]];
    [self.contentStack addArrangedSubview:[self _sectionCardWithTitle:VCTextLiteral(@"Open Source")
                                                           subtitle:VCTextLiteral(@"MIT License")
                                                             accent:kVCAccentHover
                                                              lines:@[
                                                                  @"GitHub: https://github.com/vaenshine/VansonCLI",
                                                                  @"Telegram: https://t.me/VansonCLI",
                                                                  @"License: MIT",
                                                                  VCTextLiteral(@"For testing, research, and technical exchange only.")
                                                              ]]];
    [self.contentStack addArrangedSubview:[self _sectionCardWithTitle:VCTextLiteral(@"Disclaimer")
                                                           subtitle:VCTextLiteral(@"Use only on apps, devices, and accounts you own or are authorized to test.")
                                                             accent:kVCYellow
                                                              lines:@[
                                                                  VCTextLiteral(@"VansonCLI is provided for lawful testing, debugging, learning, and security research."),
                                                                  VCTextLiteral(@"Users are responsible for complying with local laws, platform rules, and third-party terms."),
                                                                  VCTextLiteral(@"The project authors are not responsible for misuse, data loss, account risk, or service violations.")
                                                              ]]];
    [self.contentStack addArrangedSubview:[self _sectionCardWithTitle:VCTextLiteral(@"Credits")
                                                           subtitle:VCTextLiteral(@"Author: Vanson")
                                                             accent:kVCAccentHover
                                                              lines:@[
                                                                  @"Built with Theos",
                                                                  @"Interface refined with Stitch-guided direction",
                                                                  @"Native UIKit execution surface"
                                                              ]]];
}

- (UIView *)_buildHeroCard {
    UIView *card = [self _makeCardView];

    UIView *logoBox = [[UIView alloc] init];
    logoBox.backgroundColor = [UIColor clearColor];
    logoBox.layer.cornerRadius = 14.0;
    logoBox.layer.borderWidth = 0.0;
    logoBox.layer.borderColor = UIColor.clearColor.CGColor;
    logoBox.clipsToBounds = YES;
    logoBox.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:logoBox];

    UIImageView *logoImageView = [[UIImageView alloc] initWithImage:VCBrandIconImage()];
    logoImageView.contentMode = UIViewContentModeScaleAspectFit;
    logoImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [logoBox addSubview:logoImageView];

    UILabel *eyebrow = [[UILabel alloc] init];
    eyebrow.text = VCTextLiteral(@"INJECTED DEBUG WORKSPACE");
    eyebrow.textColor = kVCAccent;
    eyebrow.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:eyebrow];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"VansonCLI";
    title.textColor = kVCTextPrimary;
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    VCPrepareSingleLineLabel(title, NSLineBreakByTruncatingTail);
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:title];

    UILabel *version = [[UILabel alloc] init];
    version.text = [NSString stringWithFormat:@"Version %@", [[VCConfig shared] vcVersion] ?: @"--"];
    version.textColor = kVCTextPrimary;
    version.backgroundColor = [kVCAccent colorWithAlphaComponent:0.16];
    version.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    version.textAlignment = NSTextAlignmentCenter;
    version.layer.cornerRadius = 10.0;
    version.layer.borderWidth = 1.0;
    version.layer.borderColor = [kVCAccent colorWithAlphaComponent:0.28].CGColor;
    version.clipsToBounds = YES;
    version.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:version];

    UILabel *summary = [[UILabel alloc] init];
    summary.text = VCTextLiteral(@"Inspect runtime state, drive AI tooling in-process, and keep device plus environment information in one place.");
    summary.textColor = kVCTextSecondary;
    summary.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    summary.numberOfLines = 2;
    summary.lineBreakMode = NSLineBreakByTruncatingTail;
    summary.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:summary];

    [NSLayoutConstraint activateConstraints:@[
        [logoBox.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [logoBox.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [logoBox.widthAnchor constraintEqualToConstant:58],
        [logoBox.heightAnchor constraintEqualToConstant:58],

        [logoImageView.topAnchor constraintEqualToAnchor:logoBox.topAnchor],
        [logoImageView.leadingAnchor constraintEqualToAnchor:logoBox.leadingAnchor],
        [logoImageView.trailingAnchor constraintEqualToAnchor:logoBox.trailingAnchor],
        [logoImageView.bottomAnchor constraintEqualToAnchor:logoBox.bottomAnchor],

        [eyebrow.topAnchor constraintEqualToAnchor:logoBox.topAnchor constant:2],
        [eyebrow.leadingAnchor constraintEqualToAnchor:logoBox.trailingAnchor constant:12],
        [eyebrow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],

        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:6],
        [title.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-120],

        [version.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [version.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [version.heightAnchor constraintEqualToConstant:24],
        [version.widthAnchor constraintLessThanOrEqualToConstant:128],

        [summary.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [summary.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [summary.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [summary.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [summary.bottomAnchor constraintGreaterThanOrEqualToAnchor:logoBox.bottomAnchor constant:0],
    ]];

    return card;
}

- (UIView *)_buildLinksCard {
    UIView *card = [self _makeCardView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = VCTextLiteral(@"Project Links");
    titleLabel.textColor = kVCTextPrimary;
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];

    UIButton *github = [self _linkButtonWithTitle:@"GitHub"
                                           symbol:@"chevron.left.forwardslash.chevron.right"
                                              url:@"https://github.com/vaenshine/VansonCLI"];
    UIButton *telegram = [self _linkButtonWithTitle:@"Telegram"
                                             symbol:@"paperplane.fill"
                                                url:@"https://t.me/VansonCLI"];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, github, telegram]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [github.heightAnchor constraintEqualToConstant:38],
        [telegram.heightAnchor constraintEqualToConstant:38],
    ]];

    return card;
}

- (UIView *)_buildUpdateCard {
    UIView *card = [self _makeCardView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = VCTextLiteral(@"Updates");
    titleLabel.textColor = kVCTextPrimary;
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    VCPrepareSingleLineLabel(titleLabel, NSLineBreakByTruncatingTail);

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = VCTextLiteral(@"GitHub Release tags are used for update detection.");
    subtitleLabel.textColor = kVCAccent;
    subtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.updateStatusLabel = [self _monoDetailLabel];
    self.updateStatusLabel.numberOfLines = 3;
    self.updateStatusLabel.text = [NSString stringWithFormat:@"%@ %@", VCTextLiteral(@"Current version:"), [[VCConfig shared] vcVersion] ?: @"--"];

    self.updateCheckButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.updateCheckButton setTitle:VCTextLiteral(@"Check for Updates") forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(self.updateCheckButton);
    VCApplyCompactIconTitleButtonLayout(self.updateCheckButton, @"arrow.down.circle", 13.0);
    self.updateCheckButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.updateCheckButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    [self.updateCheckButton addTarget:self action:@selector(_checkForUpdates:) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel, self.updateStatusLabel, self.updateCheckButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [self.updateCheckButton.heightAnchor constraintEqualToConstant:38],
    ]];

    return card;
}

- (UIButton *)_linkButtonWithTitle:(NSString *)title symbol:(NSString *)symbol url:(NSString *)url {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(button);
    VCApplyCompactIconTitleButtonLayout(button, symbol, 13.0);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    button.accessibilityIdentifier = url;
    [button addTarget:self action:@selector(_openLinkButton:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)_openLinkButton:(UIButton *)sender {
    NSString *urlString = sender.accessibilityIdentifier ?: @"";
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)_checkForUpdates:(UIButton *)sender {
    if (self.latestReleaseURL.length > 0) {
        NSURL *url = [NSURL URLWithString:self.latestReleaseURL];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            return;
        }
    }

    sender.enabled = NO;
    [sender setTitle:VCTextLiteral(@"Checking GitHub Releases...") forState:UIControlStateNormal];
    VCApplyCompactIconTitleButtonLayout(sender, @"arrow.triangle.2.circlepath", 13.0);
    self.updateStatusLabel.text = VCTextLiteral(@"Checking GitHub Releases...");

    vc_weakify(self);
    [[VCConfig shared] checkForUpdatesWithCompletion:^(NSDictionary *info, NSError *error) {
        vc_strongify(self);
        sender.enabled = YES;
        if (error) {
            [sender setTitle:VCTextLiteral(@"Check for Updates") forState:UIControlStateNormal];
            VCApplyCompactIconTitleButtonLayout(sender, @"arrow.down.circle", 13.0);
            self.updateStatusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"Update check failed: %@"), error.localizedDescription ?: VCTextLiteral(@"Unknown")];
            return;
        }

        NSString *current = [info[@"currentVersion"] isKindOfClass:[NSString class]] ? info[@"currentVersion"] : ([[VCConfig shared] vcVersion] ?: @"--");
        NSString *latest = [info[@"latestVersion"] isKindOfClass:[NSString class]] ? info[@"latestVersion"] : @"--";
        NSString *releaseURL = [info[@"releaseURL"] isKindOfClass:[NSString class]] ? info[@"releaseURL"] : @"";
        BOOL updateAvailable = [info[@"updateAvailable"] boolValue];
        if (updateAvailable) {
            self.latestReleaseURL = releaseURL;
            [sender setTitle:VCTextLiteral(@"Open Latest Release") forState:UIControlStateNormal];
            VCApplyCompactIconTitleButtonLayout(sender, @"safari", 13.0);
            self.updateStatusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"New version %@ is available. Current: %@."), latest, current];
        } else {
            self.latestReleaseURL = nil;
            [sender setTitle:VCTextLiteral(@"Check for Updates") forState:UIControlStateNormal];
            VCApplyCompactIconTitleButtonLayout(sender, @"arrow.down.circle", 13.0);
            self.updateStatusLabel.text = [NSString stringWithFormat:VCTextLiteral(@"You are on the latest version (%@)."), current];
        }
    }];
}

- (UIView *)_buildEnvironmentCard {
    NSString *targetName = [[VCConfig shared] targetDisplayName] ?: VCTextLiteral(@"Unknown");
    NSString *deviceName = [UIDevice currentDevice].model ?: VCTextLiteral(@"Device");
    return [self _sectionCardWithTitle:VCTextLiteral(@"Environment")
                              subtitle:[NSString stringWithFormat:@"%@ · %@", targetName, deviceName]
                                accent:kVCAccent
                                 lines:@[
                                     [NSString stringWithFormat:@"Bundle: %@", [[VCConfig shared] targetBundleID] ?: @"--"],
                                     [NSString stringWithFormat:@"PID: %d", [[NSProcessInfo processInfo] processIdentifier]],
                                     [NSString stringWithFormat:@"OS: iOS %@", [UIDevice currentDevice].systemVersion ?: @"--"],
                                     [NSString stringWithFormat:@"Build root: %@", [[[VCConfig shared] sandboxPath] lastPathComponent] ?: @"Sandbox"]
                                 ]];
}

- (UIView *)_sectionCardWithTitle:(NSString *)title
                         subtitle:(NSString *)subtitle
                           accent:(UIColor *)accent
                            lines:(NSArray<NSString *> *)lines {
    UIView *card = [self _makeCardView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title ?: @"";
    titleLabel.textColor = kVCTextPrimary;
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    VCPrepareSingleLineLabel(titleLabel, NSLineBreakByTruncatingTail);

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = subtitle ?: @"";
    subtitleLabel.textColor = accent ?: kVCTextSecondary;
    subtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    subtitleLabel.numberOfLines = 1;
    subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    [stack addArrangedSubview:titleLabel];
    [stack addArrangedSubview:subtitleLabel];

    for (NSString *line in lines ?: @[]) {
        UILabel *detail = [self _monoDetailLabel];
        detail.text = line;
        [stack addArrangedSubview:detail];
    }

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
    ]];

    return card;
}

@end
