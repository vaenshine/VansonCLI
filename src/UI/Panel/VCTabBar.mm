/**
 * VCTabBar -- 水平滚动 Tab 栏 + 选中指示线
 */

#import "VCTabBar.h"
#import "../../../VansonCLI.h"

static const CGFloat kTabHeight = 42.0;
static const CGFloat kIndicatorHeight = 2.0;
static const CGFloat kTabInset = 8.0;
static const CGFloat kTabSpacing = 6.0;
static const CGFloat kTabHorizontalPadding = 12.0;
static const CGFloat kTabIconSpacing = 6.0;
static const CGFloat kTabMinWidth = 72.0;
static const CGFloat kVerticalInset = 8.0;
static const CGFloat kVerticalSpacing = 8.0;
static const CGFloat kVerticalButtonHeight = 48.0;
static const CGFloat kCompactVerticalInset = 4.0;
static const CGFloat kCompactVerticalSpacing = 6.0;
static const CGFloat kCompactVerticalButtonHeight = 44.0;

static BOOL VCLayoutStyleUsesVerticalRail(VCTabBarLayoutStyle style) {
    return style == VCTabBarLayoutStyleVertical || style == VCTabBarLayoutStyleCompactVertical;
}

static BOOL VCLayoutStyleUsesCompactVerticalRail(VCTabBarLayoutStyle style) {
    return style == VCTabBarLayoutStyleCompactVertical;
}

static NSString *VCIconNameForTitle(NSString *title) {
    static NSDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"AI Chat": @"sparkles",
            @"Inspect": @"waveform.path.ecg.rectangle",
            @"UI": @"rectangle.3.group.bubble.left",
            @"Network": @"network",
            @"Console": @"terminal",
            @"Artifacts": @"archivebox",
            @"Patches": @"wrench.and.screwdriver",
            @"Settings": @"slider.horizontal.3",
            @"Workspace": @"square.grid.2x2"
        };
    });
    return map[title] ?: @"circle";
}

static NSString *VCCompactTitleForTitle(NSString *title) {
    if ([title isEqualToString:@"AI Chat"]) return @"AI";
    if ([title isEqualToString:@"Inspect"]) return @"Inspect";
    if ([title isEqualToString:@"Network"]) return @"Network";
    if ([title isEqualToString:@"Settings"]) return @"Settings";
    if ([title isEqualToString:@"Artifacts"]) return @"Artifacts";
    if ([title isEqualToString:@"Patches"]) return @"Patches";
    if ([title isEqualToString:@"Console"]) return @"Console";
    if ([title isEqualToString:@"Workspace"]) return @"Hub";
    return title ?: @"";
}

static NSString *VCHorizontalTitleForTitle(NSString *title, BOOL compact) {
    if (!compact) return title ?: @"";
    if ([title isEqualToString:@"AI Chat"]) return @"AI";
    if ([title isEqualToString:@"Network"]) return @"Network";
    if ([title isEqualToString:@"Workspace"]) return @"Hub";
    return title ?: @"";
}

@interface VCTabBar ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@property (nonatomic, strong) UIView *indicator;
@property (nonatomic, copy) NSArray<NSString *> *titles;
@end

@implementation VCTabBar

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles {
    CGFloat height = kTabHeight;
    if (self = [super initWithFrame:CGRectMake(0, 0, 320, height)]) {
        _titles = [titles copy];
        _selectedIndex = 0;
        _layoutStyle = VCTabBarLayoutStyleHorizontal;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_languageDidChange) name:VCLanguageDidChangeNotification object:nil];
        [self _setup];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_setup {
    self.backgroundColor = [UIColor clearColor];

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.bounces = YES;
    [self addSubview:_scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    NSMutableArray *btns = [NSMutableArray new];

    for (NSUInteger i = 0; i < _titles.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        [btn setTitle:VCTextLiteral(_titles[i]) forState:UIControlStateNormal];
        [btn setImage:[UIImage systemImageNamed:VCIconNameForTitle(_titles[i])] forState:UIControlStateNormal];
        btn.tag = (NSInteger)i;
        VCApplyTabBarButtonBaseStyle(btn);
        btn.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
        btn.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        btn.titleLabel.adjustsFontSizeToFitWidth = YES;
        btn.titleLabel.minimumScaleFactor = 0.74;
        btn.layer.cornerRadius = kVCRadiusLg;
        [btn addTarget:self action:@selector(_tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_scrollView addSubview:btn];
        [btns addObject:btn];
    }
    _buttons = [btns copy];

    // Indicator
    UIButton *first = _buttons.firstObject;
    _indicator = [[UIView alloc] initWithFrame:[self _indicatorFrameForButton:first]];
    _indicator.backgroundColor = kVCAccent;
    _indicator.layer.cornerRadius = 1.0;
    [_scrollView addSubview:_indicator];

    [self _applyLayoutStyleToButtons];
    [self _layoutButtons];
    [self _updateSelection];
}

- (void)_languageDidChange {
    for (NSUInteger i = 0; i < self.buttons.count; i++) {
        UIButton *button = self.buttons[i];
        if (i < self.titles.count) {
            NSString *title = VCLayoutStyleUsesVerticalRail(self.layoutStyle)
                ? VCCompactTitleForTitle(self.titles[i])
                : self.titles[i];
            [button setTitle:VCTextLiteral(title) forState:UIControlStateNormal];
        }
    }
    [self _applyLayoutStyleToButtons];
    [self _layoutButtons];
    [self _updateSelection];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self _layoutButtons];
    if (self.buttons.count > 0 && self.selectedIndex < self.buttons.count) {
        UIButton *selected = self.buttons[self.selectedIndex];
        if (VCLayoutStyleUsesCompactVerticalRail(self.layoutStyle)) {
            self.scrollView.contentOffset = CGPointZero;
            return;
        }
        CGRect visible = VCLayoutStyleUsesVerticalRail(self.layoutStyle)
            ? CGRectInset(selected.frame, 0, -20)
            : CGRectInset(selected.frame, -20, 0);
        [self.scrollView scrollRectToVisible:visible animated:NO];
    }
}

- (void)_tabTapped:(UIButton *)btn {
    NSUInteger idx = (NSUInteger)btn.tag;
    if (idx == _selectedIndex) {
        [self.delegate tabBar:self didSelectIndex:idx];
        return;
    }
    _selectedIndex = idx;
    [self _updateSelection];
    [self.delegate tabBar:self didSelectIndex:idx];
}

- (void)setLayoutStyle:(VCTabBarLayoutStyle)layoutStyle {
    if (_layoutStyle == layoutStyle) return;
    _layoutStyle = layoutStyle;
    [self _applyLayoutStyleToButtons];
    [self setNeedsLayout];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    if (selectedIndex >= _buttons.count) return;
    if (selectedIndex == _selectedIndex) {
        [self _updateSelection];
        return;
    }
    _selectedIndex = selectedIndex;
    [self _updateSelection];
}

- (void)_applyLayoutStyleToButtons {
    BOOL vertical = VCLayoutStyleUsesVerticalRail(self.layoutStyle);
    BOOL compactVertical = VCLayoutStyleUsesCompactVerticalRail(self.layoutStyle);
    BOOL compactHorizontal = !vertical && CGRectGetHeight(self.bounds) <= 38.5;
    self.scrollView.alwaysBounceHorizontal = !vertical;
    self.scrollView.alwaysBounceVertical = vertical;
    self.scrollView.scrollEnabled = vertical || !compactVertical;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.indicator.hidden = NO;

    for (NSUInteger i = 0; i < self.buttons.count; i++) {
        UIButton *button = self.buttons[i];
        NSString *title = i < self.titles.count ? self.titles[i] : @"";
        NSString *displayTitle = vertical ? VCCompactTitleForTitle(title) : title;
        [button setImage:[UIImage systemImageNamed:VCIconNameForTitle(title)] forState:UIControlStateNormal];
        [button setTitle:VCTextLiteral(displayTitle) forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:(vertical ? (compactVertical ? 10.5 : 10.5) : (compactHorizontal ? 10.5 : 12.0))
                                                   weight:UIFontWeightSemibold];
        if (vertical && compactVertical) {
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
            button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
            button.titleLabel.textAlignment = NSTextAlignmentCenter;
            button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 4.0, 0.0, 4.0);
            button.imageEdgeInsets = UIEdgeInsetsZero;
            button.titleEdgeInsets = UIEdgeInsetsMake(0.0, 5.0, 0.0, -5.0);
        } else if (vertical) {
            NSString *localizedTitle = VCTextLiteral(displayTitle);
            CGSize titleSize = [localizedTitle sizeWithAttributes:@{ NSFontAttributeName: button.titleLabel.font }];
            CGFloat titleWidth = MIN(ceil(titleSize.width), compactVertical ? 42.0 : 64.0);
            CGFloat imageWidth = button.currentImage ? ceil(button.currentImage.size.width) : 0.0;
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
            button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
            button.titleLabel.textAlignment = NSTextAlignmentCenter;
            button.contentEdgeInsets = UIEdgeInsetsMake(1.0, 2.0, 1.0, 2.0);
            button.imageEdgeInsets = UIEdgeInsetsMake(compactVertical ? -8.0 : -12.0,
                                                      titleWidth * 0.5,
                                                      compactVertical ? 5.0 : 8.0,
                                                      -titleWidth * 0.5);
            button.titleEdgeInsets = UIEdgeInsetsMake(compactVertical ? 15.0 : 21.0,
                                                      -imageWidth,
                                                      0.0,
                                                      0.0);
        } else {
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
            button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
            button.titleLabel.textAlignment = NSTextAlignmentNatural;
            button.imageEdgeInsets = UIEdgeInsetsZero;
            button.titleEdgeInsets = UIEdgeInsetsZero;
            button.contentEdgeInsets = UIEdgeInsetsMake(0, compactHorizontal ? 10.0 : kTabHorizontalPadding, 0, compactHorizontal ? 10.0 : kTabHorizontalPadding);
        }
    }
}

- (void)_updateSelection {
    if (_buttons.count == 0) return;

    for (NSUInteger i = 0; i < _buttons.count; i++) {
        UIButton *btn = _buttons[i];
        BOOL sel = (i == _selectedIndex);
        UIColor *titleColor = sel ? kVCAccentHover : kVCTextMuted;
        btn.tintColor = sel ? kVCAccent : kVCTextMuted;
        [btn setTitleColor:titleColor forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor clearColor];
        btn.layer.borderColor = UIColor.clearColor.CGColor;
        btn.layer.borderWidth = 0.0;
    }

    UIButton *sel = _buttons[_selectedIndex];
    [UIView animateWithDuration:0.2 animations:^{
        self.indicator.frame = [self _indicatorFrameForButton:sel];
    }];

    if (VCLayoutStyleUsesCompactVerticalRail(self.layoutStyle)) {
        _scrollView.contentOffset = CGPointZero;
    } else {
        // Scroll to visible
        CGRect visible = VCLayoutStyleUsesVerticalRail(self.layoutStyle)
            ? CGRectInset(sel.frame, 0, -20)
            : CGRectInset(sel.frame, -20, 0);
        [_scrollView scrollRectToVisible:visible animated:YES];
    }
}

- (void)_layoutButtons {
    CGFloat barHeight = MAX(CGRectGetHeight(self.bounds), 30.0);
    if (VCLayoutStyleUsesVerticalRail(self.layoutStyle)) {
        BOOL compactVertical = VCLayoutStyleUsesCompactVerticalRail(self.layoutStyle);
        CGFloat inset = compactVertical ? kCompactVerticalInset : kVerticalInset;
        CGFloat spacing = compactVertical ? kCompactVerticalSpacing : kVerticalSpacing;
        CGFloat buttonHeight = compactVertical ? kCompactVerticalButtonHeight : kVerticalButtonHeight;
        CGFloat width = MAX(compactVertical ? 50.0 : 72.0, CGRectGetWidth(self.bounds) - (inset * 2.0));
        CGFloat y = inset;
        for (UIButton *button in self.buttons) {
            button.frame = CGRectMake(inset, y, width, buttonHeight);
            button.layer.cornerRadius = MIN(12.0, buttonHeight * 0.5);
            y += buttonHeight + spacing;
        }
        _scrollView.contentSize = CGSizeMake(CGRectGetWidth(self.bounds),
                                             MAX(CGRectGetHeight(self.bounds) + 1.0, y));
        if (compactVertical && y <= CGRectGetHeight(self.bounds)) _scrollView.contentOffset = CGPointZero;
    } else {
        CGFloat availableWidth = CGRectGetWidth(self.bounds);
        BOOL heightCompact = barHeight <= 38.5;
        CGFloat naturalWidth = kTabInset * 2.0 + MAX((NSInteger)self.buttons.count - 1, 0) * kTabSpacing;
        UIFont *naturalFont = [UIFont systemFontOfSize:(heightCompact ? 10.5 : 12.0) weight:UIFontWeightSemibold];
        for (NSUInteger i = 0; i < _buttons.count; i++) {
            naturalWidth += [self _widthForButton:_buttons[i] title:VCTextLiteral(_titles[i]) font:naturalFont compact:heightCompact];
        }
        BOOL compactHorizontal = heightCompact || (availableWidth > 0.0 && naturalWidth > availableWidth + 1.0);
        UIFont *font = [UIFont systemFontOfSize:(compactHorizontal ? 10.2 : 12.0) weight:UIFontWeightSemibold];
        CGFloat horizontalInset = compactHorizontal ? 5.0 : kTabInset;
        CGFloat spacing = compactHorizontal ? 4.0 : kTabSpacing;
        CGFloat buttonHeight = MAX(24.0, barHeight - (compactHorizontal ? 8.0 : 10.0));
        CGFloat buttonY = MAX(2.0, (barHeight - buttonHeight) * 0.5);
        CGFloat x = horizontalInset;

        for (NSUInteger i = 0; i < _buttons.count; i++) {
            UIButton *btn = _buttons[i];
            BOOL selected = (i == self.selectedIndex);
            NSString *sourceTitle = (compactHorizontal && !selected) ? VCHorizontalTitleForTitle(_titles[i], YES) : _titles[i];
            NSString *title = VCTextLiteral(sourceTitle);
            [btn setTitle:title forState:UIControlStateNormal];
            btn.titleLabel.font = font;
            btn.contentEdgeInsets = UIEdgeInsetsMake(0, compactHorizontal ? 8.0 : kTabHorizontalPadding, 0, compactHorizontal ? 8.0 : kTabHorizontalPadding);
            CGFloat w = [self _widthForButton:btn title:title font:font compact:compactHorizontal];
            btn.frame = CGRectMake(x, buttonY, w, buttonHeight);
            btn.layer.cornerRadius = MIN(12.0, buttonHeight * 0.5);
            x += w + spacing;
        }
        _scrollView.contentSize = CGSizeMake(MAX(CGRectGetWidth(self.bounds) + 1.0, x + horizontalInset), barHeight);
    }

    if (_buttons.count > 0) {
        NSUInteger index = MIN(_selectedIndex, _buttons.count - 1);
        _indicator.frame = [self _indicatorFrameForButton:_buttons[index]];
    }
}

- (CGFloat)_widthForButton:(UIButton *)button title:(NSString *)title font:(UIFont *)font compact:(BOOL)compact {
    CGSize titleSize = [title sizeWithAttributes:@{NSFontAttributeName: font}];
    CGFloat iconWidth = button.currentImage ? ceil(button.currentImage.size.width) : 0.0;
    CGFloat spacing = (button.currentImage && title.length > 0) ? (compact ? 4.0 : kTabIconSpacing) : 0.0;
    CGFloat horizontalPadding = button.contentEdgeInsets.left + button.contentEdgeInsets.right;
    CGFloat totalWidth = ceil(titleSize.width) + iconWidth + spacing + horizontalPadding;
    CGFloat minWidth = compact ? 54.0 : kTabMinWidth;
    return MAX(minWidth, totalWidth);
}

- (CGRect)_indicatorFrameForButton:(UIButton *)button {
    CGFloat barHeight = MAX(CGRectGetHeight(self.bounds), 30.0);
    if (!button) return CGRectMake(kTabInset, barHeight - kIndicatorHeight, 24.0, kIndicatorHeight);
    if (VCLayoutStyleUsesVerticalRail(self.layoutStyle)) {
        BOOL compactVertical = VCLayoutStyleUsesCompactVerticalRail(self.layoutStyle);
        CGFloat indicatorInsetY = compactVertical ? 9.0 : 8.0;
        CGFloat indicatorHeight = compactVertical ? 18.0 : 16.0;
        CGFloat indicatorX = compactVertical ? 2.0 : 3.0;
        return CGRectMake(indicatorX,
                          CGRectGetMinY(button.frame) + indicatorInsetY,
                          2.0,
                          MAX(18.0, CGRectGetHeight(button.frame) - indicatorHeight));
    }
    CGFloat width = MAX(24.0, CGRectGetWidth(button.frame) - 24.0);
    return CGRectMake(CGRectGetMinX(button.frame) + 12.0, barHeight - kIndicatorHeight, width, kIndicatorHeight);
}

@end
