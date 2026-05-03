/**
 * VansonCLI - Main Header
 * CLI-ify the injected process
 */

#ifndef VANSONCLI_H
#define VANSONCLI_H

#import <UIKit/UIKit.h>
#import "src/Core/VCLanguage.h"

// ═══════════════════════════════════════════════════════════════
// VCTheme -- 全局配色
// ═══════════════════════════════════════════════════════════════

#define UIColorFromHex(hex) \
    [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0 \
                    green:((hex >> 8) & 0xFF) / 255.0 \
                     blue:(hex & 0xFF) / 255.0 \
                    alpha:1.0]

#define UIColorFromHexA(hex, a) \
    [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0 \
                    green:((hex >> 8) & 0xFF) / 255.0 \
                     blue:(hex & 0xFF) / 255.0 \
                    alpha:(a)]

// Background
#define kVCBgPrimary    UIColorFromHex(0x0d1220)   // --bg-primary
#define kVCBgSecondary  UIColorFromHex(0x0b0f1a)   // --bg-secondary
#define kVCBgTertiary   UIColorFromHex(0x090d15)   // --bg-tertiary
#define kVCBgSurface    UIColorFromHex(0x141c2c)   // --bg-surface
#define kVCBgHover      UIColorFromHex(0x1a2538)   // --bg-hover
#define kVCBgInput      UIColorFromHex(0x0a0e18)   // --bg-input

// Border
#define kVCBorder       UIColorFromHexA(0x6EFFFF, 0.08)  // --border
#define kVCBorderLight  UIColorFromHexA(0x6EFFFF, 0.15)  // --border-light
#define kVCBorderStrong UIColorFromHexA(0x6EFFFF, 0.22)  // strong border
#define kVCBorderAccent UIColorFromHexA(0x00D4FF, 0.32)  // accent border

// Text
#define kVCTextPrimary    UIColorFromHex(0xf1faff) // --text-primary
#define kVCTextSecondary  UIColorFromHex(0x9ed8ff) // --text-secondary
#define kVCTextMuted      UIColorFromHex(0x4a6a8a) // --text-muted

// Accent
#define kVCAccent       UIColorFromHex(0x00d4ff)   // --accent (cyan)
#define kVCAccentHover  UIColorFromHex(0x31ffc7)   // --accent-hover
#define kVCAccentDim    UIColorFromHexA(0x00d4ff, 0.12)
#define kVCGreenDim     UIColorFromHexA(0x31ffc7, 0.14)
#define kVCRedDim       UIColorFromHexA(0xff4a6a, 0.14)

// Semantic
#define kVCGreen        UIColorFromHex(0x31ffc7)   // --green (success)
#define kVCRed          UIColorFromHex(0xff4a6a)   // --red (error/danger)
#define kVCYellow       UIColorFromHex(0xffd24a)   // --yellow (warning)
#define kVCOrange       UIColorFromHex(0xFB923C)   // --orange

// Radius
#define kVCRadius       8.0
#define kVCRadiusLg     12.0
#define kVCRadiusSm     4.0

// Font
#define kVCFontMono     [UIFont fontWithName:@"Menlo" size:13]
#define kVCFontMonoSm   [UIFont fontWithName:@"Menlo" size:11]

static inline void VCApplyPanelSurface(UIView *view, CGFloat radius) {
    if (!view) return;
    view.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.94];
    view.layer.cornerRadius = radius > 0.0 ? radius : kVCRadiusLg;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = kVCBorderStrong.CGColor;
}

static inline void VCApplyInputSurface(UIView *view, CGFloat radius) {
    if (!view) return;
    view.backgroundColor = kVCBgInput;
    view.layer.cornerRadius = radius > 0.0 ? radius : kVCRadiusLg;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = kVCBorder.CGColor;
}

static inline void VCPrepareSingleLineLabel(UILabel *label, NSLineBreakMode mode) {
    if (!label) return;
    label.numberOfLines = 1;
    label.lineBreakMode = mode;
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
}

static inline void VCPrepareButtonTitle(UIButton *button, NSLineBreakMode mode, CGFloat minimumScale) {
    if (!button) return;
    button.titleLabel.numberOfLines = 1;
    button.titleLabel.lineBreakMode = mode;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = minimumScale > 0.0 ? minimumScale : 0.82;
    [button setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
}

static inline void VCSetButtonSymbol(UIButton *button, NSString *symbolName) {
    if (!button || symbolName.length == 0) return;
    [button setImage:[UIImage systemImageNamed:symbolName] forState:UIControlStateNormal];
    button.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 5.0, 0, -5.0);
    button.imageEdgeInsets = UIEdgeInsetsMake(0, -2.0, 0, 2.0);
}

static inline void VCApplyCompactIconTitleButtonLayout(UIButton *button, NSString *symbolName, CGFloat pointSize) {
    if (!button) return;
    if (symbolName.length > 0) {
        CGFloat resolvedPointSize = pointSize > 0.0 ? pointSize : 11.0;
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:resolvedPointSize
                                                                                             weight:UIImageSymbolWeightSemibold];
        UIImage *image = [[UIImage systemImageNamed:symbolName] imageWithConfiguration:config];
        [button setImage:image forState:UIControlStateNormal];
        [button setPreferredSymbolConfiguration:config forImageInState:UIControlStateNormal];
    }

    NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
    BOOL hasTitle = title.length > 0;
    button.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.imageEdgeInsets = hasTitle ? UIEdgeInsetsMake(0, -1.0, 0, 3.0) : UIEdgeInsetsZero;
    button.titleEdgeInsets = hasTitle ? UIEdgeInsetsMake(0, 3.0, 0, -3.0) : UIEdgeInsetsZero;
}

// ═══════════════════════════════════════════════════════════════
// Forward Declarations
// ═══════════════════════════════════════════════════════════════

@class VCConfig;
@class VCSafeMode;

// ═══════════════════════════════════════════════════════════════
// Global Macros
// ═══════════════════════════════════════════════════════════════

// Log prefix
#define VCLog(fmt, ...) NSLog(@"[VansonCLI] " fmt, ##__VA_ARGS__)

// Weak self for blocks (ObjC++ compatible)
#define vc_weakify(var) __weak __typeof__(var) vc_weak_##var = var
#define vc_strongify(var) __strong __typeof__(vc_weak_##var) var = vc_weak_##var

// Main thread dispatch
#define vc_dispatch_main(block) \
    if ([NSThread isMainThread]) { block(); } \
    else { dispatch_async(dispatch_get_main_queue(), block); }

// Localization
static inline NSString *VCText(NSString *key, NSString *fallback) {
    return [VCLanguage textForKey:key fallback:fallback];
}

static inline NSString *VCTextKey(NSString *key) {
    return [VCLanguage textForKey:key fallback:nil];
}

static inline NSString *VCTextLiteral(NSString *literal) {
    return [VCLanguage textForKey:literal fallback:literal];
}

// Internal network request marker used to keep VansonCLI's own provider traffic
// out of capture/rule pipelines.
static NSString *const kVCInternalRequestHeader = @"X-VansonCLI-Internal";
static NSString *const kVCInternalRequestAIValue = @"ai";

static inline BOOL VCRequestIsInternal(NSURLRequest *request) {
    if (![request isKindOfClass:[NSURLRequest class]]) return NO;
    NSString *marker = [request valueForHTTPHeaderField:kVCInternalRequestHeader];
    if (![marker isKindOfClass:[NSString class]]) return NO;
    return [[marker lowercaseString] isEqualToString:kVCInternalRequestAIValue];
}

// Keyboard accessory helpers
static inline UIToolbar *VCKeyboardDismissToolbar(UIResponder *target) {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
    toolbar.translucent = YES;
    toolbar.barTintColor = kVCBgSurface;
    toolbar.tintColor = kVCAccent;
    toolbar.accessibilityIdentifier = @"vc.keyboard.dismiss.toolbar";

    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                           target:nil
                                                                           action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:VCTextLiteral(@"Hide")
                                                             style:UIBarButtonItemStyleDone
                                                            target:target
                                                            action:@selector(resignFirstResponder)];
    toolbar.items = @[flex, done];
    [toolbar sizeToFit];
    return toolbar;
}

static inline void VCEnsureKeyboardDismissAccessory(UIResponder *responder, BOOL reloadIfFirstResponder) {
    if ([responder isKindOfClass:[UITextField class]]) {
        UITextField *field = (UITextField *)responder;
        if (!field.inputAccessoryView ||
            [field.inputAccessoryView.accessibilityIdentifier isEqualToString:@"vc.keyboard.dismiss.toolbar"]) {
            field.inputAccessoryView = VCKeyboardDismissToolbar(field);
            if (reloadIfFirstResponder && field.isFirstResponder) {
                [field reloadInputViews];
            }
        }
    } else if ([responder isKindOfClass:[UITextView class]]) {
        UITextView *textView = (UITextView *)responder;
        if (!textView.editable) return;
        if (!textView.inputAccessoryView ||
            [textView.inputAccessoryView.accessibilityIdentifier isEqualToString:@"vc.keyboard.dismiss.toolbar"]) {
            textView.inputAccessoryView = VCKeyboardDismissToolbar(textView);
            if (reloadIfFirstResponder && textView.isFirstResponder) {
                [textView reloadInputViews];
            }
        }
    }
}

static inline void VCInstallKeyboardDismissAccessory(UIView *view) {
    if (!view) return;

    if ([view isKindOfClass:[UITextField class]]) {
        VCEnsureKeyboardDismissAccessory((UIResponder *)view, NO);
    } else if ([view isKindOfClass:[UITextView class]]) {
        VCEnsureKeyboardDismissAccessory((UIResponder *)view, NO);
    }

    for (UIView *subview in view.subviews) {
        VCInstallKeyboardDismissAccessory(subview);
    }
}

static inline void VCApplyReadablePlaceholder(UITextField *field, NSString *placeholder) {
    if (!field) return;
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:(placeholder ?: @"")
                                                                  attributes:@{
                                                                      NSForegroundColorAttributeName: [kVCTextPrimary colorWithAlphaComponent:0.72]
                                                                  }];
}

static inline void VCApplyReadableSearchPlaceholder(UISearchBar *searchBar, NSString *placeholder) {
    if (!searchBar) return;
    if (@available(iOS 13.0, *)) {
        searchBar.searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:(placeholder ?: @"")
                                                                                           attributes:@{
                                                                                               NSForegroundColorAttributeName: [kVCTextPrimary colorWithAlphaComponent:0.72]
                                                                                           }];
    } else {
        searchBar.placeholder = placeholder;
    }
}

// Shared button chrome helpers
static const CGFloat kVCButtonCornerRadiusCompact = 10.0;
static const CGFloat kVCButtonCornerRadiusRegular = 12.0;
static const CGFloat kVCButtonCornerRadiusAction = 13.0;
static const CGFloat kVCButtonHeightCompact = 32.0;
static const CGFloat kVCButtonHeightRegular = 40.0;

static inline void VCApplyButtonChrome(UIButton *button,
                                       UIColor *titleColor,
                                       UIColor *tintColor,
                                       UIColor *backgroundColor,
                                       UIColor *borderColor,
                                       CGFloat cornerRadius,
                                       UIFont *font) {
    if (!button) return;
    UIColor *resolvedTitleColor = titleColor ?: kVCTextPrimary;
    UIColor *resolvedTintColor = tintColor ?: resolvedTitleColor;
    [button setTitleColor:resolvedTitleColor forState:UIControlStateNormal];
    button.tintColor = resolvedTintColor;
    button.titleLabel.font = font ?: [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    button.backgroundColor = backgroundColor ?: kVCAccentDim;
    button.layer.cornerRadius = MAX(cornerRadius, 0.0);
    button.layer.borderWidth = borderColor ? 1.0 : 0.0;
    button.layer.borderColor = (borderColor ?: UIColor.clearColor).CGColor;
    button.adjustsImageWhenHighlighted = NO;
}

static inline void VCApplySecondaryButtonStyle(UIButton *button) {
    VCApplyButtonChrome(button,
                        kVCTextPrimary,
                        kVCTextPrimary,
                        kVCAccentDim,
                        kVCBorderAccent,
                        kVCButtonCornerRadiusRegular,
                        [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]);
}

static inline void VCApplyCompactSecondaryButtonStyle(UIButton *button) {
    VCApplyButtonChrome(button,
                        kVCTextPrimary,
                        kVCTextPrimary,
                        kVCAccentDim,
                        kVCBorderAccent,
                        kVCButtonCornerRadiusCompact,
                        [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]);
}

static inline void VCApplyPrimaryButtonStyle(UIButton *button) {
    VCApplyButtonChrome(button,
                        kVCBgPrimary,
                        kVCBgPrimary,
                        kVCAccent,
                        kVCBorderAccent,
                        kVCButtonCornerRadiusAction,
                        [UIFont systemFontOfSize:13 weight:UIFontWeightBold]);
}

static inline void VCApplyCompactPrimaryButtonStyle(UIButton *button) {
    VCApplyButtonChrome(button,
                        kVCBgPrimary,
                        kVCBgPrimary,
                        kVCAccent,
                        kVCBorderAccent,
                        kVCButtonCornerRadiusRegular,
                        [UIFont systemFontOfSize:12 weight:UIFontWeightBold]);
}

static inline void VCApplyDangerButtonStyle(UIButton *button) {
    VCApplyButtonChrome(button,
                        [UIColor whiteColor],
                        [UIColor whiteColor],
                        kVCRed,
                        [kVCRed colorWithAlphaComponent:0.32],
                        kVCButtonCornerRadiusAction,
                        [UIFont systemFontOfSize:13 weight:UIFontWeightBold]);
}

static inline void VCApplyCompactDangerButtonStyle(UIButton *button) {
    VCApplyButtonChrome(button,
                        [UIColor whiteColor],
                        [UIColor whiteColor],
                        kVCRed,
                        [kVCRed colorWithAlphaComponent:0.24],
                        kVCButtonCornerRadiusCompact,
                        [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]);
}

static inline void VCApplyCompactAccentButtonStyle(UIButton *button) {
    VCApplyButtonChrome(button,
                        kVCAccentHover,
                        kVCAccentHover,
                        [kVCAccent colorWithAlphaComponent:0.11],
                        [kVCAccent colorWithAlphaComponent:0.24],
                        kVCButtonCornerRadiusCompact,
                        [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]);
}

static inline void VCApplyPositiveButtonStyle(UIButton *button) {
    VCApplyButtonChrome(button,
                        kVCTextPrimary,
                        kVCTextPrimary,
                        UIColorFromHex(0x133b2f),
                        kVCBorderAccent,
                        kVCButtonCornerRadiusAction,
                        [UIFont systemFontOfSize:13 weight:UIFontWeightBold]);
}

static inline void VCApplyTabBarButtonBaseStyle(UIButton *button) {
    VCApplyButtonChrome(button,
                        kVCTextMuted,
                        kVCTextMuted,
                        [UIColor clearColor],
                        nil,
                        kVCButtonCornerRadiusRegular,
                        [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]);
}

static inline UILabel *VCBuildEmptyStateLabel(NSString *text) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = kVCTextMuted;
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    label.numberOfLines = 0;
    return label;
}

#endif // VANSONCLI_H
