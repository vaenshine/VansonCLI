/**
 * VCUIInspector.mm -- UI hierarchy inspector implementation
 * Slide-4: UI Inspector Engine
 */

#import "VCUIInspector.h"
#import "../Hook/VCHookManager.h"
#import "../../VansonCLI.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString *const kVCUIInspectorDidSelectViewNotification = @"com.vanson.cli.ui.selected-view";

// ═══════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════

static NSString *VCHexFromColor(UIColor *color) {
    if (!color) return nil;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        // Try converting color space
        color = [UIColor colorWithCGColor:color.CGColor];
        if (![color getRed:&r green:&g blue:&b alpha:&a]) return nil;
    }
    return [NSString stringWithFormat:@"%02X%02X%02X",
            (int)(r * 255), (int)(g * 255), (int)(b * 255)];
}

static UIColor *VCColorFromHex(NSString *hex) {
    if (!hex || hex.length < 6) return nil;
    unsigned int val = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&val];
    return [UIColor colorWithRed:((val >> 16) & 0xFF) / 255.0
                           green:((val >> 8) & 0xFF) / 255.0
                            blue:(val & 0xFF) / 255.0
                           alpha:1.0];
}

static const char *VCSkipObjCQualifiers(const char *type) {
    while (type && (*type == 'r' || *type == 'n' || *type == 'N' ||
                    *type == 'o' || *type == 'O' || *type == 'R' || *type == 'V')) {
        type++;
    }
    return type;
}

static CGRect VCFrameFromValue(id value, CGRect fallback) {
    if ([value isKindOfClass:[NSString class]]) {
        CGRect parsed = CGRectFromString(value);
        if (!CGRectIsEmpty(parsed) && !CGRectEqualToRect(parsed, CGRectZero)) return parsed;
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = value;
        return CGRectMake([dict[@"x"] doubleValue],
                          [dict[@"y"] doubleValue],
                          [dict[@"width"] doubleValue],
                          [dict[@"height"] doubleValue]);
    }
    return fallback;
}

static UIColor *VCColorFromValue(id value) {
    if ([value isKindOfClass:[UIColor class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        NSString *string = [[(NSString *)value stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
        return VCColorFromHex(string);
    }
    return nil;
}

static NSString *VCStringFromInvocationReturn(NSInvocation *invocation, NSMethodSignature *signature) {
    const char *returnType = VCSkipObjCQualifiers(signature.methodReturnType);
    if (!returnType || returnType[0] == 'v') return @"Invoked successfully";
    switch (returnType[0]) {
        case '@': {
            __unsafe_unretained id value = nil;
            [invocation getReturnValue:&value];
            return value ? [NSString stringWithFormat:@"Returned %@", value] : @"Returned nil";
        }
        case 'B': {
            BOOL value = NO;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"Returned %@", value ? @"YES" : @"NO"];
        }
        case 'c': case 'C': case 's': case 'S': case 'i': case 'I': case 'l': case 'L': case 'q': case 'Q': {
            long long value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"Returned %lld", value];
        }
        case 'f': {
            float value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"Returned %.3f", value];
        }
        case 'd': {
            double value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"Returned %.3f", value];
        }
        default:
            return [NSString stringWithFormat:@"Invoked with return type %s", returnType];
    }
}

static BOOL VCIsOwnWindow(UIWindow *window) {
    NSString *cls = NSStringFromClass([window class]);
    return [cls hasPrefix:@"VC"];
}

static NSString *VCBriefForView(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *text = ((UILabel *)view).text ?: @"";
        if (text.length > 20) text = [[text substringToIndex:20] stringByAppendingString:@"..."];
        return [NSString stringWithFormat:@"UILabel \"%@\"", text];
    }
    if ([view isKindOfClass:[UIButton class]]) {
        NSString *title = ((UIButton *)view).titleLabel.text ?: @"";
        if (title.length > 20) title = [[title substringToIndex:20] stringByAppendingString:@"..."];
        return [NSString stringWithFormat:@"UIButton \"%@\"", title];
    }
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *field = (UITextField *)view;
        NSString *text = field.text ?: @"";
        NSString *placeholder = field.placeholder ?: @"";
        if (text.length > 20) text = [[text substringToIndex:20] stringByAppendingString:@"..."];
        if (placeholder.length > 20) placeholder = [[placeholder substringToIndex:20] stringByAppendingString:@"..."];
        if (text.length > 0) {
            return [NSString stringWithFormat:@"UITextField \"%@\"", text];
        }
        if (placeholder.length > 0) {
            return [NSString stringWithFormat:@"UITextField placeholder \"%@\"", placeholder];
        }
        return @"UITextField";
    }
    if ([view isKindOfClass:[UITextView class]]) {
        NSString *text = ((UITextView *)view).text ?: @"";
        if (text.length > 20) text = [[text substringToIndex:20] stringByAppendingString:@"..."];
        if (text.length > 0) {
            return [NSString stringWithFormat:@"UITextView \"%@\"", text];
        }
        return @"UITextView";
    }
    return [NSString stringWithFormat:@"%@ %.0fx%.0f",
            NSStringFromClass([view class]),
            view.frame.size.width, view.frame.size.height];
}

// ═══════════════════════════════════════════════════════════════
// VCViewNode
// ═══════════════════════════════════════════════════════════════

@implementation VCViewNode
@end

// ═══════════════════════════════════════════════════════════════
// VCUIInspector
// ═══════════════════════════════════════════════════════════════

@interface VCUIInspector ()
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSDictionary *> *highlightedViews;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSDictionary *> *originalValues;
@property (nonatomic, weak, readwrite) UIView *currentSelectedView;
@end

@implementation VCUIInspector

+ (instancetype)shared {
    static VCUIInspector *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[VCUIInspector alloc] init]; });
    return inst;
}

- (instancetype)init {
    if (self = [super init]) {
        _highlightedViews = [NSMutableDictionary new];
        _originalValues = [NSMutableDictionary new];
        _selectionHighlightEnabled = YES;
    }
    return self;
}

- (void)setSelectionHighlightEnabled:(BOOL)selectionHighlightEnabled {
    _selectionHighlightEnabled = selectionHighlightEnabled;
    if (!selectionHighlightEnabled) {
        [self clearHighlights];
    }
}

// ═══════════════════════════════════════════════════════════════
// Hierarchy
// ═══════════════════════════════════════════════════════════════

- (VCViewNode *)_nodeForView:(UIView *)view {
    VCViewNode *node = [[VCViewNode alloc] init];
    node.className = NSStringFromClass([view class]);
    node.briefDescription = VCBriefForView(view);
    node.frame = view.frame;
    node.address = (uintptr_t)view;
    node.view = view;

    NSMutableArray<VCViewNode *> *kids = [NSMutableArray new];
    for (UIView *sub in view.subviews) {
        [kids addObject:[self _nodeForView:sub]];
    }
    node.children = [kids copy];
    return node;
}

- (UIView *)_findViewWithAddress:(uintptr_t)address inView:(UIView *)view {
    if (!view) return nil;
    if ((uintptr_t)(__bridge void *)view == address) return view;
    for (UIView *subview in view.subviews) {
        UIView *found = [self _findViewWithAddress:address inView:subview];
        if (found) return found;
    }
    return nil;
}

- (VCViewNode *)viewHierarchyTree {
    VCViewNode *root = [[VCViewNode alloc] init];
    root.className = @"UIScreen";
    root.briefDescription = @"UIScreen main";
    root.frame = [UIScreen mainScreen].bounds;
    root.address = 0;

    NSMutableArray<VCViewNode *> *windowNodes = [NSMutableArray new];
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        if (VCIsOwnWindow(win)) continue;
        [windowNodes addObject:[self _nodeForView:win]];
    }
    root.children = [windowNodes copy];
    return root;
}

- (UIView *)viewForAddress:(uintptr_t)address {
    if (address == 0) return nil;
    if (_currentSelectedView && (uintptr_t)(__bridge void *)_currentSelectedView == address) {
        return _currentSelectedView;
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (VCIsOwnWindow(window) || window.isHidden) continue;
        UIView *found = [self _findViewWithAddress:address inView:window];
        if (found) return found;
    }
    return nil;
}

// ═══════════════════════════════════════════════════════════════
// Properties
// ═══════════════════════════════════════════════════════════════

- (NSDictionary *)propertiesForView:(UIView *)view {
    if (!view) return @{};
    NSMutableDictionary *props = [NSMutableDictionary new];

    // General
    props[@"class"] = NSStringFromClass([view class]);
    props[@"frame"] = NSStringFromCGRect(view.frame);
    props[@"bounds"] = NSStringFromCGRect(view.bounds);
    props[@"center"] = NSStringFromCGPoint(view.center);
    props[@"alpha"] = @(view.alpha);
    props[@"hidden"] = @(view.isHidden);
    props[@"tag"] = @(view.tag);

    // Color
    props[@"backgroundColor"] = VCHexFromColor(view.backgroundColor) ?: @"nil";
    props[@"tintColor"] = VCHexFromColor(view.tintColor) ?: @"nil";

    // Layout
    props[@"userInteractionEnabled"] = @(view.isUserInteractionEnabled);
    props[@"clipsToBounds"] = @(view.clipsToBounds);

    // Constraints
    NSMutableArray *constraintDescs = [NSMutableArray new];
    for (NSLayoutConstraint *c in view.constraints) {
        [constraintDescs addObject:c.description];
    }
    props[@"constraints"] = [constraintDescs copy];

    // Accessibility
    props[@"accessibilityLabel"] = view.accessibilityLabel ?: @"nil";
    props[@"accessibilityIdentifier"] = view.accessibilityIdentifier ?: @"nil";

    // UILabel
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *lbl = (UILabel *)view;
        props[@"text"] = lbl.text ?: @"nil";
        props[@"font"] = [NSString stringWithFormat:@"%@ %.1f",
                          lbl.font.fontName, lbl.font.pointSize];
        props[@"textColor"] = VCHexFromColor(lbl.textColor) ?: @"nil";
    }

    // UIButton
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        props[@"titleLabel.text"] = btn.titleLabel.text ?: @"nil";
        props[@"currentTitle"] = btn.currentTitle ?: @"nil";
    }

    // UIImageView
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *iv = (UIImageView *)view;
        props[@"hasImage"] = @(iv.image != nil);
        if (iv.image) {
            props[@"imageSize"] = NSStringFromCGSize(iv.image.size);
        }
    }

    // UITextField
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        props[@"text"] = tf.text ?: @"nil";
        props[@"placeholder"] = tf.placeholder ?: @"nil";
    }

    // UITextView
    if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        props[@"text"] = tv.text ?: @"nil";
    }

    return [props copy];
}

// ═══════════════════════════════════════════════════════════════
// Responder Chain
// ═══════════════════════════════════════════════════════════════

- (NSArray<NSString *> *)responderChainForView:(UIView *)view {
    NSMutableArray<NSString *> *chain = [NSMutableArray new];
    UIResponder *responder = view;
    while (responder) {
        [chain addObject:NSStringFromClass([responder class])];
        responder = responder.nextResponder;
    }
    return [chain copy];
}

// ═══════════════════════════════════════════════════════════════
// Highlight
// ═══════════════════════════════════════════════════════════════

- (void)highlightView:(UIView *)view {
    if (!view) return;
    if (!self.selectionHighlightEnabled) {
        [self clearHighlights];
        return;
    }
    NSValue *key = [NSValue valueWithNonretainedObject:view];

    NSDictionary *originalState = self.highlightedViews[key];
    if (!originalState) {
        UIColor *origColor = view.layer.borderColor
            ? [UIColor colorWithCGColor:view.layer.borderColor]
            : nil;
        originalState = @{
            @"borderColor": origColor ?: [NSNull null],
            @"borderWidth": @(view.layer.borderWidth)
        };
    }

    vc_dispatch_main(^{
        for (NSValue *existingKey in self.highlightedViews.allKeys) {
            UIView *highlightedView = [existingKey nonretainedObjectValue];
            if (!highlightedView) continue;
            NSDictionary *orig = self.highlightedViews[existingKey];
            id origColor = orig[@"borderColor"];
            highlightedView.layer.borderColor = (origColor && origColor != [NSNull null]) ? ((UIColor *)origColor).CGColor : nil;
            highlightedView.layer.borderWidth = [orig[@"borderWidth"] doubleValue];
        }
        [self.highlightedViews removeAllObjects];
        self.highlightedViews[key] = originalState;
        view.layer.borderColor = kVCRed.CGColor;
        view.layer.borderWidth = 2.0;
    });
}

- (void)rememberSelectedView:(UIView *)view {
    _currentSelectedView = view;
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    NSDictionary *traceContext = [[VCHookManager shared] currentTraceContextSnapshot];
    if (traceContext.count > 0) {
        userInfo[@"traceContext"] = traceContext;
    }
    if (view) {
        userInfo[@"className"] = NSStringFromClass([view class]) ?: @"UIView";
        userInfo[@"address"] = [NSString stringWithFormat:@"0x%llx", (unsigned long long)(uintptr_t)(__bridge void *)view];
        userInfo[@"frame"] = NSStringFromCGRect(view.frame);
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kVCUIInspectorDidSelectViewNotification
                                                        object:self
                                                      userInfo:[userInfo copy]];
}

- (void)clearHighlights {
    vc_dispatch_main(^{
        for (NSValue *key in self.highlightedViews) {
            UIView *view = [key nonretainedObjectValue];
            if (!view) continue;
            NSDictionary *orig = self.highlightedViews[key];

            id origColor = orig[@"borderColor"];
            if (origColor && origColor != [NSNull null]) {
                view.layer.borderColor = ((UIColor *)origColor).CGColor;
            } else {
                view.layer.borderColor = nil;
            }
            view.layer.borderWidth = [orig[@"borderWidth"] doubleValue];
        }
        [self.highlightedViews removeAllObjects];
    });
}

// ═══════════════════════════════════════════════════════════════
// Modify
// ═══════════════════════════════════════════════════════════════

- (void)modifyView:(UIView *)view property:(NSString *)key value:(id)value {
    if (!view || !key || !value) return;

    // Record original value for undo
    NSValue *viewKey = [NSValue valueWithNonretainedObject:view];
    NSMutableDictionary *origDict = [self.originalValues[viewKey] mutableCopy] ?: [NSMutableDictionary new];

    if ([key isEqualToString:@"hidden"]) {
        if (!origDict[@"hidden"]) origDict[@"hidden"] = @(view.isHidden);
        vc_dispatch_main(^{ view.hidden = [value boolValue]; });
    }
    else if ([key isEqualToString:@"alpha"]) {
        if (!origDict[@"alpha"]) origDict[@"alpha"] = @(view.alpha);
        vc_dispatch_main(^{ view.alpha = [value doubleValue]; });
    }
    else if ([key isEqualToString:@"backgroundColor"]) {
        if (!origDict[@"backgroundColor"]) {
            origDict[@"backgroundColor"] = VCHexFromColor(view.backgroundColor) ?: [NSNull null];
        }
        UIColor *color = VCColorFromHex(value);
        if (color) {
            vc_dispatch_main(^{ view.backgroundColor = color; });
        }
    }
    else if ([key isEqualToString:@"tintColor"]) {
        if (!origDict[@"tintColor"]) {
            origDict[@"tintColor"] = VCHexFromColor(view.tintColor) ?: [NSNull null];
        }
        UIColor *color = VCColorFromHex(value);
        if (color) {
            vc_dispatch_main(^{ view.tintColor = color; });
        }
    }
    else if ([key isEqualToString:@"frame"]) {
        if (!origDict[@"frame"]) origDict[@"frame"] = [NSValue valueWithCGRect:view.frame];
        CGRect rect = CGRectFromString(value);
        vc_dispatch_main(^{ view.frame = rect; });
    }
    else if ([key isEqualToString:@"tag"]) {
        if (!origDict[@"tag"]) origDict[@"tag"] = @(view.tag);
        vc_dispatch_main(^{ view.tag = [value integerValue]; });
    }
    else if ([key isEqualToString:@"text"]) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)view;
            if (!origDict[@"text"]) origDict[@"text"] = lbl.text ?: [NSNull null];
            vc_dispatch_main(^{ lbl.text = value; });
        } else if ([view isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)view;
            if (!origDict[@"text"]) origDict[@"text"] = tf.text ?: [NSNull null];
            vc_dispatch_main(^{ tf.text = value; });
        } else if ([view isKindOfClass:[UITextView class]]) {
            UITextView *tv = (UITextView *)view;
            if (!origDict[@"text"]) origDict[@"text"] = tv.text ?: [NSNull null];
            vc_dispatch_main(^{ tv.text = value; });
        } else if ([view isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)view;
            if (!origDict[@"text"]) origDict[@"text"] = [btn titleForState:UIControlStateNormal] ?: [NSNull null];
            vc_dispatch_main(^{ [btn setTitle:value forState:UIControlStateNormal]; });
        }
    }
    else if ([key isEqualToString:@"textColor"]) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)view;
            if (!origDict[@"textColor"]) origDict[@"textColor"] = VCHexFromColor(lbl.textColor) ?: [NSNull null];
            UIColor *color = VCColorFromHex(value);
            if (color) { vc_dispatch_main(^{ lbl.textColor = color; }); }
        } else if ([view isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)view;
            UIColor *original = [button titleColorForState:UIControlStateNormal];
            if (!origDict[@"textColor"]) origDict[@"textColor"] = VCHexFromColor(original) ?: [NSNull null];
            UIColor *color = VCColorFromHex(value);
            if (color) { vc_dispatch_main(^{ [button setTitleColor:color forState:UIControlStateNormal]; }); }
        } else if ([view isKindOfClass:[UITextField class]]) {
            UITextField *field = (UITextField *)view;
            if (!origDict[@"textColor"]) origDict[@"textColor"] = VCHexFromColor(field.textColor) ?: [NSNull null];
            UIColor *color = VCColorFromHex(value);
            if (color) { vc_dispatch_main(^{ field.textColor = color; }); }
        } else if ([view isKindOfClass:[UITextView class]]) {
            UITextView *textView = (UITextView *)view;
            if (!origDict[@"textColor"]) origDict[@"textColor"] = VCHexFromColor(textView.textColor) ?: [NSNull null];
            UIColor *color = VCColorFromHex(value);
            if (color) { vc_dispatch_main(^{ textView.textColor = color; }); }
        }
    }
    else if ([key isEqualToString:@"clipsToBounds"]) {
        if (!origDict[@"clipsToBounds"]) origDict[@"clipsToBounds"] = @(view.clipsToBounds);
        vc_dispatch_main(^{ view.clipsToBounds = [value boolValue]; });
    }
    else if ([key isEqualToString:@"userInteractionEnabled"]) {
        if (!origDict[@"userInteractionEnabled"]) origDict[@"userInteractionEnabled"] = @(view.isUserInteractionEnabled);
        vc_dispatch_main(^{ view.userInteractionEnabled = [value boolValue]; });
    }

    self.originalValues[viewKey] = [origDict copy];
}

- (UIView *)insertSubviewIntoView:(UIView *)parentView spec:(NSDictionary *)spec {
    if (!parentView || ![spec isKindOfClass:[NSDictionary class]]) return nil;

    NSString *className = spec[@"className"] ?: spec[@"class"] ?: spec[@"viewClass"] ?: spec[@"type"] ?: @"UILabel";
    Class cls = NSClassFromString(className);
    if (!cls || ![cls isSubclassOfClass:[UIView class]]) return nil;

    __block UIView *created = nil;
    void (^work)(void) = ^{
        CGRect defaultFrame = CGRectMake(8,
                                         MAX(8.0, CGRectGetHeight(parentView.bounds) - 30.0),
                                         MAX(80.0, CGRectGetWidth(parentView.bounds) - 16.0),
                                         24.0);
        CGRect frame = VCFrameFromValue(spec[@"frame"] ?: spec, defaultFrame);
        created = [[cls alloc] initWithFrame:frame];
        created.tag = [spec[@"tag"] integerValue];
        created.hidden = [spec[@"hidden"] boolValue];
        created.alpha = spec[@"alpha"] ? [spec[@"alpha"] doubleValue] : 1.0;
        created.userInteractionEnabled = spec[@"userInteractionEnabled"] ? [spec[@"userInteractionEnabled"] boolValue] : YES;
        created.clipsToBounds = spec[@"clipsToBounds"] ? [spec[@"clipsToBounds"] boolValue] : NO;
        NSString *identifier = [spec[@"accessibilityIdentifier"] isKindOfClass:[NSString class]] ? spec[@"accessibilityIdentifier"] : nil;
        if (identifier.length > 0) {
            created.accessibilityIdentifier = identifier;
        }

        UIColor *backgroundColor = VCColorFromValue(spec[@"backgroundColor"] ?: spec[@"background"]);
        if (backgroundColor) {
            created.backgroundColor = backgroundColor;
        }

        NSString *text = [spec[@"text"] isKindOfClass:[NSString class]] ? spec[@"text"] :
                         [spec[@"title"] isKindOfClass:[NSString class]] ? spec[@"title"] : nil;
        UIColor *textColor = VCColorFromValue(spec[@"textColor"]);

        if ([created isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)created;
            label.text = text ?: @"New Label";
            label.numberOfLines = 0;
            if (textColor) label.textColor = textColor;
            NSNumber *fontSize = spec[@"fontSize"];
            if ([fontSize respondsToSelector:@selector(doubleValue)]) {
                label.font = [UIFont systemFontOfSize:[fontSize doubleValue] weight:UIFontWeightSemibold];
            }
        } else if ([created isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)created;
            [button setTitle:(text ?: @"New Button") forState:UIControlStateNormal];
            if (textColor) [button setTitleColor:textColor forState:UIControlStateNormal];
            if (!backgroundColor) {
                button.backgroundColor = kVCAccentDim;
            }
            button.layer.cornerRadius = 10.0;
            button.layer.borderWidth = 1.0;
            button.layer.borderColor = kVCBorder.CGColor;
        } else if ([created isKindOfClass:[UITextField class]]) {
            UITextField *field = (UITextField *)created;
            field.text = text ?: @"";
            field.placeholder = [spec[@"placeholder"] isKindOfClass:[NSString class]] ? spec[@"placeholder"] : @"";
            if (textColor) field.textColor = textColor;
            field.backgroundColor = backgroundColor ?: kVCBgInput;
        } else if ([created isKindOfClass:[UITextView class]]) {
            UITextView *textView = (UITextView *)created;
            textView.text = text ?: @"";
            if (textColor) textView.textColor = textColor;
            textView.backgroundColor = backgroundColor ?: kVCBgInput;
        }

        if ([parentView isKindOfClass:[UIStackView class]]) {
            [(UIStackView *)parentView addArrangedSubview:created];
        } else {
            [parentView addSubview:created];
        }
        [self rememberSelectedView:created];
        [self highlightView:created];
    };

    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);
    return created;
}

- (BOOL)invokeSelector:(NSString *)selectorName onTarget:(id)target argument:(id)argument result:(NSString **)resultMessage {
    if (!selectorName.length || !target) {
        if (resultMessage) *resultMessage = @"Missing selector or target";
        return NO;
    }

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) {
        if (resultMessage) *resultMessage = [NSString stringWithFormat:@"%@ does not respond to %@", NSStringFromClass([target class]), selectorName];
        return NO;
    }

    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature) {
        if (resultMessage) *resultMessage = @"Unable to read method signature";
        return NO;
    }

    NSUInteger argCount = signature.numberOfArguments > 2 ? signature.numberOfArguments - 2 : 0;
    if (argCount > 1) {
        if (resultMessage) *resultMessage = @"Only zero-arg or one-arg selector invocation is supported";
        return NO;
    }

    __block BOOL success = YES;
    __block NSString *message = nil;
    void (^work)(void) = ^{
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = target;
        invocation.selector = selector;

        if (argCount == 1) {
            const char *argType = VCSkipObjCQualifiers([signature getArgumentTypeAtIndex:2]);
            switch (argType[0]) {
                case '@': {
                    id obj = argument;
                    [invocation setArgument:&obj atIndex:2];
                    break;
                }
                case 'B': {
                    BOOL value = [argument respondsToSelector:@selector(boolValue)] ? [argument boolValue] : NO;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'c': {
                    char value = [argument respondsToSelector:@selector(charValue)] ? [argument charValue] : 0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'C': {
                    unsigned char value = [argument respondsToSelector:@selector(unsignedCharValue)] ? [argument unsignedCharValue] : 0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 's': {
                    short value = [argument respondsToSelector:@selector(shortValue)] ? [argument shortValue] : 0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'S': {
                    unsigned short value = [argument respondsToSelector:@selector(unsignedShortValue)] ? [argument unsignedShortValue] : 0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'i': {
                    int value = [argument respondsToSelector:@selector(intValue)] ? [argument intValue] : 0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'I': {
                    unsigned int value = [argument respondsToSelector:@selector(unsignedIntValue)] ? [argument unsignedIntValue] : 0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'l': {
                    long value = [argument respondsToSelector:@selector(longValue)] ? [argument longValue] : 0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'L': {
                    unsigned long value = [argument respondsToSelector:@selector(unsignedLongValue)] ? [argument unsignedLongValue] : 0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'q': {
                    long long value = [argument respondsToSelector:@selector(longLongValue)] ? [argument longLongValue] : 0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'Q': {
                    unsigned long long value = [argument respondsToSelector:@selector(unsignedLongLongValue)] ? [argument unsignedLongLongValue] : 0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'f': {
                    float value = [argument respondsToSelector:@selector(floatValue)] ? [argument floatValue] : 0.0f;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case 'd': {
                    double value = [argument respondsToSelector:@selector(doubleValue)] ? [argument doubleValue] : 0.0;
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case ':': {
                    SEL value = NSSelectorFromString([argument description]);
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                case '#': {
                    Class value = NSClassFromString([argument description]);
                    [invocation setArgument:&value atIndex:2];
                    break;
                }
                default:
                    success = NO;
                    message = [NSString stringWithFormat:@"Unsupported selector argument type %s", argType];
                    return;
            }
        }

        [invocation invoke];
        message = VCStringFromInvocationReturn(invocation, signature);
        if ([target isKindOfClass:[UIView class]]) {
            [self rememberSelectedView:(UIView *)target];
        }
    };

    if ([NSThread isMainThread]) work();
    else dispatch_sync(dispatch_get_main_queue(), work);

    if (resultMessage) *resultMessage = message ?: (success ? @"Invoked successfully" : @"Invocation failed");
    return success;
}

// ═══════════════════════════════════════════════════════════════
// Screenshot
// ═══════════════════════════════════════════════════════════════

- (UIImage *)screenshotView:(UIView *)view {
    if (!view) return nil;
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, NO, 0);
    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end
