/**
 * VCChatMarkdownView -- Lightweight markdown/code renderer for chat bubbles
 */

#import "VCChatMarkdownView.h"
#import "../Code/VCCodeTab.h"
#import "../../../VansonCLI.h"
#import <QuartzCore/QuartzCore.h>

static NSString *VCChatMarkdownSafeString(id value) {
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return @"";
}

static NSArray<NSDictionary *> *VCChatMarkdownSegments(NSString *markdown) {
    NSString *source = VCChatMarkdownSafeString(markdown);
    NSMutableArray<NSDictionary *> *segments = [NSMutableArray new];
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"```([^\\n`]*)\\n([\\s\\S]*?)\\n?```"
                                                                           options:0
                                                                             error:&error];
    if (error || !regex) {
        if (source.length > 0) {
            [segments addObject:@{@"type": @"text", @"content": source}];
        }
        return [segments copy];
    }

    __block NSUInteger cursor = 0;
    [regex enumerateMatchesInString:source options:0 range:NSMakeRange(0, source.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        if (!result || result.range.location == NSNotFound) return;
        if (result.range.location > cursor) {
            NSString *text = [source substringWithRange:NSMakeRange(cursor, result.range.location - cursor)];
            if (text.length > 0) {
                [segments addObject:@{@"type": @"text", @"content": text}];
            }
        }
        NSString *lang = @"";
        if ([result rangeAtIndex:1].location != NSNotFound) {
            lang = [[source substringWithRange:[result rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        NSString *code = @"";
        if ([result rangeAtIndex:2].location != NSNotFound) {
            code = [source substringWithRange:[result rangeAtIndex:2]];
        }
        [segments addObject:@{
            @"type": @"code",
            @"lang": lang ?: @"",
            @"content": code ?: @""
        }];
        cursor = result.range.location + result.range.length;
        if (flags & NSMatchingHitEnd) *stop = YES;
    }];

    if (cursor < source.length) {
        NSString *tail = [source substringFromIndex:cursor];
        if (tail.length > 0) {
            [segments addObject:@{@"type": @"text", @"content": tail}];
        }
    }
    if (segments.count == 0 && source.length > 0) {
        [segments addObject:@{@"type": @"text", @"content": source}];
    }
    return [segments copy];
}

static void VCChatMarkdownApplyReplacementPattern(NSMutableAttributedString *attr,
                                                  NSString *pattern,
                                                  NSDictionary<NSAttributedStringKey, id> *extraAttributes) {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    if (error || !regex) return;

    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:attr.string options:0 range:NSMakeRange(0, attr.string.length)];
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if (match.numberOfRanges < 2) continue;
        NSRange fullRange = match.range;
        NSRange captureRange = [match rangeAtIndex:1];
        if (fullRange.location == NSNotFound || captureRange.location == NSNotFound) continue;

        NSString *captured = [attr.string substringWithRange:captureRange];
        NSMutableAttributedString *replacement = [[NSMutableAttributedString alloc] initWithString:captured
                                                                                        attributes:[attr attributesAtIndex:fullRange.location effectiveRange:nil]];
        [replacement addAttributes:extraAttributes range:NSMakeRange(0, replacement.length)];
        [attr replaceCharactersInRange:fullRange withAttributedString:replacement];
    }
}

static NSString *VCChatMarkdownTrimmedLinkTarget(NSString *target) {
    NSString *trimmed = [VCChatMarkdownSafeString(target) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while (trimmed.length > 1 && [trimmed hasPrefix:@"<"] && [trimmed hasSuffix:@">"]) {
        trimmed = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
        trimmed = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    while (trimmed.length > 0) {
        unichar tail = [trimmed characterAtIndex:trimmed.length - 1];
        if (tail == '.' || tail == ',' || tail == ';' || tail == ')' || tail == ']' || tail == '>') {
            trimmed = [trimmed substringToIndex:trimmed.length - 1];
            continue;
        }
        break;
    }
    return trimmed;
}

static NSDictionary<NSString *, id> *VCChatMarkdownParsedFileReference(NSString *rawTarget) {
    NSString *candidate = VCChatMarkdownTrimmedLinkTarget(rawTarget);
    if (candidate.length == 0) return nil;

    if ([candidate hasPrefix:@"file://"]) {
        NSURLComponents *components = [NSURLComponents componentsWithString:candidate];
        NSString *path = components.URL.path ?: @"";
        if (components.fragment.length > 0) {
            candidate = [path stringByAppendingFormat:@"#%@", components.fragment];
        } else {
            candidate = path;
        }
    }

    if (![candidate hasPrefix:@"/"]) return nil;

    NSUInteger line = 0;
    NSRange fragmentRange = [candidate rangeOfString:@"#L" options:NSBackwardsSearch];
    if (fragmentRange.location != NSNotFound) {
        NSString *fragment = [candidate substringFromIndex:fragmentRange.location + 2];
        NSScanner *scanner = [NSScanner scannerWithString:fragment];
        NSInteger parsedLine = 0;
        if ([scanner scanInteger:&parsedLine] && parsedLine > 0) {
            line = (NSUInteger)parsedLine;
        }
        candidate = [candidate substringToIndex:fragmentRange.location];
    } else {
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\/.*\\.[A-Za-z0-9_+\\-]+):(\\d+)(?::\\d+)?$"
                                                                               options:0
                                                                                 error:&error];
        NSTextCheckingResult *match = error ? nil : [regex firstMatchInString:candidate options:0 range:NSMakeRange(0, candidate.length)];
        if (match.numberOfRanges >= 3) {
            NSString *lineString = [candidate substringWithRange:[match rangeAtIndex:2]];
            NSInteger parsedLine = lineString.integerValue;
            if (parsedLine > 0) {
                line = (NSUInteger)parsedLine;
            }
            candidate = [candidate substringWithRange:[match rangeAtIndex:1]];
        }
    }

    if (candidate.length == 0) return nil;
    return @{
        @"path": candidate,
        @"line": @(line),
    };
}

static NSString *VCChatMarkdownNormalizedLinkTarget(NSString *target) {
    NSString *trimmed = VCChatMarkdownTrimmedLinkTarget(target);
    if (trimmed.length == 0) return @"";

    NSDictionary<NSString *, id> *fileReference = VCChatMarkdownParsedFileReference(trimmed);
    if (fileReference) {
        NSURLComponents *components = [NSURLComponents new];
        components.scheme = @"vcfile";
        components.host = @"open";
        NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObject:[NSURLQueryItem queryItemWithName:@"path"
                                                                                                               value:fileReference[@"path"]]];
        NSUInteger line = [fileReference[@"line"] unsignedIntegerValue];
        if (line > 0) {
            [items addObject:[NSURLQueryItem queryItemWithName:@"line" value:[NSString stringWithFormat:@"%lu", (unsigned long)line]]];
        }
        components.queryItems = items;
        return components.string ?: @"";
    }

    NSString *lower = [trimmed lowercaseString];
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] || [lower hasPrefix:@"mailto:"]) {
        return trimmed;
    }
    return @"";
}

static NSDictionary<NSAttributedStringKey, id> *VCChatMarkdownLinkAttributes(void) {
    return @{
        NSForegroundColorAttributeName: kVCAccentHover,
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
    };
}

static void VCChatMarkdownApplyMarkdownLinks(NSMutableAttributedString *attr) {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\(([^)]+)\\)"
                                                                           options:0
                                                                             error:&error];
    if (error || !regex) return;

    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:attr.string options:0 range:NSMakeRange(0, attr.string.length)];
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if (match.numberOfRanges < 3) continue;
        NSRange fullRange = match.range;
        NSRange titleRange = [match rangeAtIndex:1];
        NSRange targetRange = [match rangeAtIndex:2];
        if (fullRange.location == NSNotFound || titleRange.location == NSNotFound || targetRange.location == NSNotFound) continue;

        NSString *label = [attr.string substringWithRange:titleRange];
        NSString *normalizedTarget = VCChatMarkdownNormalizedLinkTarget([attr.string substringWithRange:targetRange]);
        NSDictionary *baseAttributes = fullRange.location < attr.length ? [attr attributesAtIndex:fullRange.location effectiveRange:nil] : @{};
        NSMutableAttributedString *replacement = [[NSMutableAttributedString alloc] initWithString:label attributes:baseAttributes];
        if (normalizedTarget.length > 0) {
            NSMutableDictionary *linkAttributes = [VCChatMarkdownLinkAttributes() mutableCopy];
            if (!linkAttributes) linkAttributes = [NSMutableDictionary new];
            linkAttributes[NSLinkAttributeName] = normalizedTarget;
            [replacement addAttributes:linkAttributes range:NSMakeRange(0, replacement.length)];
        }
        [attr replaceCharactersInRange:fullRange withAttributedString:replacement];
    }
}

static void VCChatMarkdownApplyPlainFileLinks(NSMutableAttributedString *attr) {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?<![\\w\\]])(/[^\\s`\\]\\)]+\\.[A-Za-z0-9_+\\-]+(?:#L\\d+(?:C\\d+)?)?(?::\\d+(?::\\d+)?)?)"
                                                                           options:0
                                                                             error:&error];
    if (error || !regex) return;

    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:attr.string options:0 range:NSMakeRange(0, attr.string.length)];
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        if (match.range.location == NSNotFound) continue;
        NSString *candidate = [attr.string substringWithRange:match.range];
        NSString *normalizedTarget = VCChatMarkdownNormalizedLinkTarget(candidate);
        if (normalizedTarget.length == 0) continue;

        id existingLink = [attr attribute:NSLinkAttributeName atIndex:match.range.location effectiveRange:nil];
        if (existingLink) continue;

        NSMutableDictionary *attributes = [VCChatMarkdownLinkAttributes() mutableCopy];
        if (!attributes) attributes = [NSMutableDictionary new];
        attributes[NSLinkAttributeName] = normalizedTarget;
        [attr addAttributes:attributes range:match.range];
    }
}

static NSAttributedString *VCChatMarkdownAttributedText(NSString *markdown, NSString *role) {
    NSString *source = VCChatMarkdownSafeString(markdown);
    NSMutableAttributedString *result = [NSMutableAttributedString new];
    NSArray<NSString *> *lines = [source componentsSeparatedByString:@"\n"];

    UIFont *bodyFont = [UIFont systemFontOfSize:11.2 weight:UIFontWeightRegular];
    UIFont *bodyBoldFont = [UIFont systemFontOfSize:11.2 weight:UIFontWeightSemibold];
    UIFont *bodyItalicFont = [UIFont italicSystemFontOfSize:11.2];
    UIFont *codeFont = [UIFont monospacedSystemFontOfSize:10.2 weight:UIFontWeightRegular];
    UIColor *bodyColor = [role isEqualToString:@"user"] ? [kVCTextPrimary colorWithAlphaComponent:0.98] : kVCTextPrimary;
    UIColor *mutedColor = [role isEqualToString:@"user"] ? [kVCTextPrimary colorWithAlphaComponent:0.72] : kVCTextMuted;

    for (NSUInteger idx = 0; idx < lines.count; idx++) {
        NSString *rawLine = lines[idx] ?: @"";
        NSString *trimmed = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        UIFont *font = bodyFont;
        UIColor *textColor = bodyColor;
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.lineSpacing = 0.8;
        style.paragraphSpacing = 1.4;

        NSString *displayLine = rawLine;
        if ([trimmed hasPrefix:@"###### "]) {
            displayLine = [trimmed substringFromIndex:7];
            font = [UIFont systemFontOfSize:11.2 weight:UIFontWeightBold];
        } else if ([trimmed hasPrefix:@"##### "]) {
            displayLine = [trimmed substringFromIndex:6];
            font = [UIFont systemFontOfSize:11.2 weight:UIFontWeightBold];
        } else if ([trimmed hasPrefix:@"#### "]) {
            displayLine = [trimmed substringFromIndex:5];
            font = [UIFont systemFontOfSize:11.4 weight:UIFontWeightBold];
        } else if ([trimmed hasPrefix:@"### "]) {
            displayLine = [trimmed substringFromIndex:4];
            font = [UIFont systemFontOfSize:11.8 weight:UIFontWeightBold];
        } else if ([trimmed hasPrefix:@"## "]) {
            displayLine = [trimmed substringFromIndex:3];
            font = [UIFont systemFontOfSize:12.6 weight:UIFontWeightBold];
        } else if ([trimmed hasPrefix:@"# "]) {
            displayLine = [trimmed substringFromIndex:2];
            font = [UIFont systemFontOfSize:13.2 weight:UIFontWeightBold];
        } else if ([trimmed hasPrefix:@"> "]) {
            displayLine = [trimmed substringFromIndex:2];
            font = bodyItalicFont;
            textColor = [bodyColor colorWithAlphaComponent:0.82];
            style.firstLineHeadIndent = 8.0;
            style.headIndent = 8.0;
        } else if ([trimmed hasPrefix:@"- "] || [trimmed hasPrefix:@"* "] || [trimmed hasPrefix:@"+ "]) {
            NSString *listBody = trimmed.length > 2 ? [trimmed substringFromIndex:2] : @"";
            displayLine = [NSString stringWithFormat:@"• %@", listBody];
            style.firstLineHeadIndent = 0.0;
            style.headIndent = 12.0;
        } else {
            NSRegularExpression *orderedRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+)\\.\\s+(.+)$" options:0 error:nil];
            NSTextCheckingResult *orderedMatch = [orderedRegex firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
            if (orderedMatch && orderedMatch.numberOfRanges >= 3) {
                NSString *prefix = [trimmed substringWithRange:[orderedMatch rangeAtIndex:1]];
                NSString *listBody = [trimmed substringWithRange:[orderedMatch rangeAtIndex:2]];
                displayLine = [NSString stringWithFormat:@"%@. %@", prefix, listBody];
                style.firstLineHeadIndent = 0.0;
                style.headIndent = 15.0;
            } else if ([trimmed isEqualToString:@"---"] || [trimmed isEqualToString:@"***"]) {
                displayLine = @"────────────────";
                textColor = mutedColor;
            }
        }

        NSDictionary *baseAttributes = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: textColor,
            NSParagraphStyleAttributeName: style
        };

        NSMutableAttributedString *lineAttr = [[NSMutableAttributedString alloc] initWithString:displayLine attributes:baseAttributes];
        VCChatMarkdownApplyMarkdownLinks(lineAttr);
        VCChatMarkdownApplyReplacementPattern(lineAttr, @"\\*\\*([^*\\n][^\\n]*?)\\*\\*", @{NSFontAttributeName: bodyBoldFont});
        VCChatMarkdownApplyReplacementPattern(lineAttr, @"__([^_\\n][^\\n]*?)__", @{NSFontAttributeName: bodyBoldFont});
        VCChatMarkdownApplyReplacementPattern(lineAttr,
                                              @"`([^`\\n]+)`",
                                              @{
                                                  NSFontAttributeName: codeFont,
                                                  NSForegroundColorAttributeName: [role isEqualToString:@"user"] ? kVCBgPrimary : kVCAccentHover,
                                                  NSBackgroundColorAttributeName: [role isEqualToString:@"user"] ? [UIColor colorWithWhite:1.0 alpha:0.16] : [kVCAccentDim colorWithAlphaComponent:0.85]
                                              });

        NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
        NSArray<NSTextCheckingResult *> *matches = [detector matchesInString:lineAttr.string options:0 range:NSMakeRange(0, lineAttr.length)];
        for (NSTextCheckingResult *match in matches) {
            if (match.range.location == NSNotFound) continue;
            if ([lineAttr attribute:NSLinkAttributeName atIndex:match.range.location effectiveRange:nil]) continue;
            NSMutableDictionary *linkAttributes = [VCChatMarkdownLinkAttributes() mutableCopy];
            if (!linkAttributes) linkAttributes = [NSMutableDictionary new];
            if (match.URL.absoluteString.length > 0) {
                linkAttributes[NSLinkAttributeName] = match.URL.absoluteString;
            }
            [lineAttr addAttributes:linkAttributes range:match.range];
        }
        VCChatMarkdownApplyPlainFileLinks(lineAttr);

        [result appendAttributedString:lineAttr];
        if (idx + 1 < lines.count) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:baseAttributes]];
        }
    }

    return result;
}

static BOOL VCChatMarkdownLineIsBlank(NSString *line) {
    return [[VCChatMarkdownSafeString(line) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0;
}

static NSArray<NSString *> *VCChatMarkdownBlocks(NSString *text) {
    NSMutableArray<NSString *> *blocks = [NSMutableArray new];
    NSMutableArray<NSString *> *currentLines = [NSMutableArray new];
    for (NSString *line in [VCChatMarkdownSafeString(text) componentsSeparatedByString:@"\n"]) {
        if (VCChatMarkdownLineIsBlank(line)) {
            if (currentLines.count > 0) {
                [blocks addObject:[currentLines componentsJoinedByString:@"\n"]];
                [currentLines removeAllObjects];
            }
            continue;
        }
        [currentLines addObject:line ?: @""];
    }
    if (currentLines.count > 0) {
        [blocks addObject:[currentLines componentsJoinedByString:@"\n"]];
    }
    return [blocks copy];
}

static BOOL VCChatMarkdownBlockIsQuote(NSString *block) {
    NSArray<NSString *> *lines = [VCChatMarkdownSafeString(block) componentsSeparatedByString:@"\n"];
    BOOL sawContent = NO;
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;
        sawContent = YES;
        if (![trimmed hasPrefix:@">"]) return NO;
    }
    return sawContent;
}

static NSString *VCChatMarkdownQuoteBody(NSString *block) {
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSString *line in [VCChatMarkdownSafeString(block) componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@">"]) {
            NSString *body = [trimmed substringFromIndex:1];
            if ([body hasPrefix:@" "]) body = [body substringFromIndex:1];
            [lines addObject:body ?: @""];
        }
    }
    return [lines componentsJoinedByString:@"\n"];
}

static BOOL VCChatMarkdownBlockIsTable(NSString *block) {
    NSArray<NSString *> *lines = [VCChatMarkdownSafeString(block) componentsSeparatedByString:@"\n"];
    if (lines.count < 2) return NO;
    NSString *header = [lines[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *separator = [lines[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (![header containsString:@"|"] || ![separator containsString:@"|"]) return NO;
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{2,}:?\\s*)+\\|?$"
                                                                           options:0
                                                                             error:&error];
    if (error || !regex) return NO;
    return [regex firstMatchInString:separator options:0 range:NSMakeRange(0, separator.length)] != nil;
}

static NSArray<NSString *> *VCChatMarkdownTableColumns(NSString *line) {
    NSString *trimmed = [VCChatMarkdownSafeString(line) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed hasPrefix:@"|"]) trimmed = [trimmed substringFromIndex:1];
    if ([trimmed hasSuffix:@"|"]) trimmed = [trimmed substringToIndex:trimmed.length - 1];
    NSMutableArray<NSString *> *columns = [NSMutableArray new];
    for (NSString *part in [trimmed componentsSeparatedByString:@"|"]) {
        [columns addObject:[[part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] copy] ?: @""];
    }
    return [columns copy];
}

static NSArray<NSArray<NSString *> *> *VCChatMarkdownTableRows(NSString *block) {
    NSMutableArray<NSArray<NSString *> *> *rows = [NSMutableArray new];
    NSArray<NSString *> *lines = [VCChatMarkdownSafeString(block) componentsSeparatedByString:@"\n"];
    for (NSUInteger idx = 0; idx < lines.count; idx++) {
        if (idx == 1) continue;
        NSString *trimmed = [lines[idx] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;
        [rows addObject:VCChatMarkdownTableColumns(trimmed)];
    }
    return [rows copy];
}

static UITableView *VCChatMarkdownAncestorTableView(UIView *view) {
    UIView *current = view.superview;
    while (current) {
        if ([current isKindOfClass:[UITableView class]]) return (UITableView *)current;
        current = current.superview;
    }
    return nil;
}

static NSUInteger VCChatMarkdownLineCount(NSString *text) {
    NSString *source = VCChatMarkdownSafeString(text);
    if (source.length == 0) return 0;
    __block NSUInteger count = 1;
    [source enumerateSubstringsInRange:NSMakeRange(0, source.length)
                               options:NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired
                            usingBlock:^(__unused NSString *substring, __unused NSRange substringRange, __unused NSRange enclosingRange, BOOL *stop) {
        count += 1;
    }];
    return MAX(1, count - 1);
}

@interface VCChatInteractiveTextView : UITextView
@end

@implementation VCChatInteractiveTextView {
    CGFloat _lastKnownWidth;
}

- (instancetype)initWithFrame:(CGRect)frame textContainer:(NSTextContainer *)textContainer {
    if (self = [super initWithFrame:frame textContainer:textContainer]) {
        self.scrollEnabled = NO;
        self.editable = NO;
        self.selectable = YES;
        self.backgroundColor = [UIColor clearColor];
        self.textContainerInset = UIEdgeInsetsZero;
        self.textContainer.lineFragmentPadding = 0.0;
    }
    return self;
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    [super setAttributedText:attributedText];
    [self invalidateIntrinsicContentSize];
}

- (CGSize)intrinsicContentSize {
    CGFloat width = CGRectGetWidth(self.bounds);
    if (width <= 0) {
        UITableView *tableView = VCChatMarkdownAncestorTableView(self);
        if (tableView) {
            width = MAX(220.0, CGRectGetWidth(tableView.bounds) - 56.0);
        } else if (self.superview) {
            width = MAX(220.0, CGRectGetWidth(self.superview.bounds) - 24.0);
        } else {
            width = 320.0;
        }
    }
    CGSize fitted = [self sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    return CGSizeMake(UIViewNoIntrinsicMetric, MAX(ceil(fitted.height), 1.0));
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    if (fabs(width - _lastKnownWidth) > 0.5) {
        _lastKnownWidth = width;
        [self invalidateIntrinsicContentSize];
    }
}

@end

@interface VCChatMarkdownView ()
@property (nonatomic, copy) NSString *lastMarkdown;
@property (nonatomic, copy) NSString *lastRole;
@end

@interface VCChatCodeBlockView : UIView
- (void)configureWithLanguage:(NSString *)language code:(NSString *)code;
@end

@implementation VCChatCodeBlockView {
    UILabel *_langLabel;
    UIButton *_copyButton;
    UIButton *_expandButton;
    VCChatInteractiveTextView *_codeTextView;
    NSLayoutConstraint *_codeHeightConstraint;
    UIView *_fadeView;
    CAGradientLayer *_fadeLayer;
    NSString *_languageText;
    NSString *_codeText;
    CGFloat _measuredHeight;
    CGFloat _lastContentWidth;
    BOOL _canExpand;
    BOOL _expanded;
}

static const CGFloat kVCChatCodeBlockCollapsedHeight = 132.0;

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [kVCBgInput colorWithAlphaComponent:0.94];
        self.layer.cornerRadius = 9.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [kVCBorderStrong colorWithAlphaComponent:0.72].CGColor;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _langLabel = [[UILabel alloc] init];
        _langLabel.font = [UIFont systemFontOfSize:8.4 weight:UIFontWeightBold];
        _langLabel.textColor = kVCTextSecondary;
        _langLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_langLabel];

        _expandButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_expandButton setTitle:VCTextLiteral(@"Expand") forState:UIControlStateNormal];
        [_expandButton setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
        _expandButton.titleLabel.font = [UIFont systemFontOfSize:8.6 weight:UIFontWeightBold];
        _expandButton.backgroundColor = [kVCBgHover colorWithAlphaComponent:0.86];
        _expandButton.layer.cornerRadius = 7.0;
        _expandButton.layer.borderWidth = 1.0;
        _expandButton.layer.borderColor = [kVCBorder colorWithAlphaComponent:0.82].CGColor;
        _expandButton.contentEdgeInsets = UIEdgeInsetsMake(3, 7, 3, 7);
        _expandButton.hidden = YES;
        _expandButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_expandButton addTarget:self action:@selector(_toggleExpanded) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_expandButton];

        _copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_copyButton setTitle:VCTextLiteral(@"Copy") forState:UIControlStateNormal];
        [_copyButton setTitleColor:kVCAccentHover forState:UIControlStateNormal];
        _copyButton.titleLabel.font = [UIFont systemFontOfSize:8.6 weight:UIFontWeightBold];
        _copyButton.backgroundColor = [kVCAccentDim colorWithAlphaComponent:0.72];
        _copyButton.layer.cornerRadius = 7.0;
        _copyButton.contentEdgeInsets = UIEdgeInsetsMake(3, 7, 3, 7);
        _copyButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_copyButton addTarget:self action:@selector(_copyCode) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_copyButton];

        _codeTextView = [[VCChatInteractiveTextView alloc] initWithFrame:CGRectZero];
        _codeTextView.font = [UIFont monospacedSystemFontOfSize:10.2 weight:UIFontWeightRegular];
        _codeTextView.textColor = kVCTextPrimary;
        _codeTextView.selectable = YES;
        _codeTextView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_codeTextView];

        _codeHeightConstraint = [_codeTextView.heightAnchor constraintEqualToConstant:56.0];
        _codeHeightConstraint.active = YES;

        _fadeView = [[UIView alloc] init];
        _fadeView.userInteractionEnabled = NO;
        _fadeView.hidden = YES;
        _fadeView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_fadeView];

        _fadeLayer = [CAGradientLayer layer];
        _fadeLayer.startPoint = CGPointMake(0.5, 0.0);
        _fadeLayer.endPoint = CGPointMake(0.5, 1.0);
        [_fadeView.layer addSublayer:_fadeLayer];

        [NSLayoutConstraint activateConstraints:@[
            [_langLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:5],
            [_langLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:7],
            [_langLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_expandButton.leadingAnchor constant:-8],
            [_copyButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [_copyButton.centerYAnchor constraintEqualToAnchor:_langLabel.centerYAnchor],
            [_expandButton.trailingAnchor constraintEqualToAnchor:_copyButton.leadingAnchor constant:-8],
            [_expandButton.centerYAnchor constraintEqualToAnchor:_copyButton.centerYAnchor],
            [_codeTextView.topAnchor constraintEqualToAnchor:_langLabel.bottomAnchor constant:4],
            [_codeTextView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
            [_codeTextView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [_codeTextView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
            [_fadeView.leadingAnchor constraintEqualToAnchor:_codeTextView.leadingAnchor],
            [_fadeView.trailingAnchor constraintEqualToAnchor:_codeTextView.trailingAnchor],
            [_fadeView.bottomAnchor constraintEqualToAnchor:_codeTextView.bottomAnchor],
            [_fadeView.heightAnchor constraintEqualToConstant:44.0],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _fadeLayer.frame = _fadeView.bounds;
    _fadeLayer.colors = @[
        (__bridge id)[[kVCBgInput colorWithAlphaComponent:0.0] CGColor],
        (__bridge id)[[kVCBgInput colorWithAlphaComponent:0.94] CGColor],
    ];

    CGFloat contentWidth = CGRectGetWidth(_codeTextView.bounds);
    if (contentWidth <= 0) {
        contentWidth = CGRectGetWidth(self.bounds) - 20.0;
    }
    if (contentWidth <= 0) return;
    if (fabs(contentWidth - _lastContentWidth) > 0.5) {
        _lastContentWidth = contentWidth;
        [self _recalculateCodeHeight];
    }
}

- (void)configureWithLanguage:(NSString *)language code:(NSString *)code {
    NSString *safeLanguage = VCChatMarkdownSafeString(language);
    NSString *safeCode = VCChatMarkdownSafeString(code);
    if ((_languageText == safeLanguage || [_languageText isEqualToString:safeLanguage]) &&
        (_codeText == safeCode || [_codeText isEqualToString:safeCode])) {
        return;
    }

    _languageText = [safeLanguage copy];
    _codeText = [safeCode copy];
    _langLabel.text = safeLanguage.length > 0 ? [safeLanguage uppercaseString] : VCTextLiteral(@"CODE");
    _codeTextView.text = _codeText;
    _expanded = NO;
    _lastContentWidth = 0;
    [self _copyButtonResetTitle];

    NSUInteger lineCount = VCChatMarkdownLineCount(_codeText);
    _canExpand = (lineCount > 12 || _codeText.length > 720);
    _expandButton.hidden = !_canExpand;
    [self _updateExpandUI];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self _recalculateCodeHeight];
}

- (void)_copyButtonResetTitle {
    [self.copyButton setTitle:VCTextLiteral(@"Copy") forState:UIControlStateNormal];
}

- (UIButton *)copyButton {
    return _copyButton;
}

- (void)_copyCode {
    [UIPasteboard generalPasteboard].string = _codeText ?: @"";
    [self.copyButton setTitle:VCTextLiteral(@"Copied") forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self _copyButtonResetTitle];
    });
}

- (void)_toggleExpanded {
    if (!_canExpand) return;
    _expanded = !_expanded;
    [self _updateExpandUI];
    [self _recalculateCodeHeight];

    UITableView *tableView = VCChatMarkdownAncestorTableView(self);
    [UIView animateWithDuration:0.20
                     animations:^{
        [tableView beginUpdates];
        [tableView endUpdates];
        [self layoutIfNeeded];
    }];
}

- (void)_updateExpandUI {
    if (!_canExpand) {
        _expandButton.hidden = YES;
        _fadeView.hidden = YES;
        return;
    }
    _expandButton.hidden = NO;
    [_expandButton setTitle:(_expanded ? VCTextLiteral(@"Collapse") : VCTextLiteral(@"Expand")) forState:UIControlStateNormal];
    _fadeView.hidden = _expanded;
}

- (void)_recalculateCodeHeight {
    CGFloat width = CGRectGetWidth(_codeTextView.bounds);
    if (width <= 0) {
        width = CGRectGetWidth(self.bounds) - 20.0;
    }
    if (width <= 0) return;

    CGSize measured = [_codeTextView sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    _measuredHeight = MAX(ceil(measured.height), 22.0);
    CGFloat targetHeight = (!_canExpand || _expanded) ? _measuredHeight : MIN(_measuredHeight, kVCChatCodeBlockCollapsedHeight);
    if (fabs(_codeHeightConstraint.constant - targetHeight) > 0.5) {
        _codeHeightConstraint.constant = targetHeight;
    }
    _fadeView.hidden = (_expanded || !_canExpand || _measuredHeight <= kVCChatCodeBlockCollapsedHeight + 1.0);
}

@end

@interface VCChatMarkdownDividerView : UIView
@end

@implementation VCChatMarkdownDividerView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [kVCBorder colorWithAlphaComponent:0.86];
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self.heightAnchor constraintEqualToConstant:1.0].active = YES;
    }
    return self;
}

@end

@interface VCChatQuoteBlockView : UIView
@property (nonatomic, weak) id<UITextViewDelegate> textDelegate;
- (void)configureWithText:(NSString *)text role:(NSString *)role;
@end

@implementation VCChatQuoteBlockView {
    UIView *_accentBar;
    VCChatInteractiveTextView *_textView;
    NSString *_lastText;
    NSString *_lastRole;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.layer.cornerRadius = 12.0;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _accentBar = [[UIView alloc] init];
        _accentBar.layer.cornerRadius = 1.5;
        _accentBar.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_accentBar];

        _textView = [[VCChatInteractiveTextView alloc] initWithFrame:CGRectZero];
        _textView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_textView];

        [NSLayoutConstraint activateConstraints:@[
            [_accentBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_accentBar.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_accentBar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
            [_accentBar.widthAnchor constraintEqualToConstant:3],
            [_textView.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_textView.leadingAnchor constraintEqualToAnchor:_accentBar.trailingAnchor constant:10],
            [_textView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_textView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)setTextDelegate:(id<UITextViewDelegate>)textDelegate {
    _textDelegate = textDelegate;
    _textView.delegate = textDelegate;
}

- (void)configureWithText:(NSString *)text role:(NSString *)role {
    NSString *safeText = VCChatMarkdownSafeString(text);
    NSString *safeRole = VCChatMarkdownSafeString(role);
    if ((_lastText == safeText || [_lastText isEqualToString:safeText]) &&
        (_lastRole == safeRole || [_lastRole isEqualToString:safeRole])) {
        return;
    }

    _lastText = [safeText copy];
    _lastRole = [safeRole copy];
    self.backgroundColor = [kVCBgHover colorWithAlphaComponent:[safeRole isEqualToString:@"user"] ? 0.26 : 0.66];
    _accentBar.backgroundColor = [safeRole isEqualToString:@"user"] ? [UIColor colorWithWhite:1.0 alpha:0.78] : kVCAccentHover;
    _textView.delegate = self.textDelegate;
    _textView.linkTextAttributes = VCChatMarkdownLinkAttributes();
    _textView.attributedText = VCChatMarkdownAttributedText(safeText, safeRole ?: @"assistant");
}

@end

static NSString *VCChatMarkdownTableSignature(NSArray<NSArray<NSString *> *> *rows, NSString *role) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:VCChatMarkdownSafeString(role)];
    for (NSArray<NSString *> *row in rows ?: @[]) {
        [parts addObject:[row componentsJoinedByString:@"\u001F"]];
    }
    return [parts componentsJoinedByString:@"\u001E"];
}

@interface VCChatTableBlockView : UIView
- (void)configureWithRows:(NSArray<NSArray<NSString *> *> *)rows role:(NSString *)role;
@end

@implementation VCChatTableBlockView {
    UIStackView *_columnStack;
    NSString *_lastSignature;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.layer.cornerRadius = 12.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [kVCBorderStrong colorWithAlphaComponent:0.76].CGColor;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _columnStack = [[UIStackView alloc] init];
        _columnStack.axis = UILayoutConstraintAxisVertical;
        _columnStack.spacing = 0.0;
        _columnStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_columnStack];

        [NSLayoutConstraint activateConstraints:@[
            [_columnStack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_columnStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_columnStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_columnStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (UIStackView *)_ensureRowStackAtIndex:(NSUInteger)index {
    while (_columnStack.arrangedSubviews.count <= index) {
        UIStackView *rowStack = [[UIStackView alloc] init];
        rowStack.axis = UILayoutConstraintAxisHorizontal;
        rowStack.distribution = UIStackViewDistributionFillEqually;
        rowStack.spacing = 0.0;
        rowStack.translatesAutoresizingMaskIntoConstraints = NO;
        [_columnStack addArrangedSubview:rowStack];
    }
    UIView *candidate = _columnStack.arrangedSubviews[index];
    if ([candidate isKindOfClass:[UIStackView class]]) {
        return (UIStackView *)candidate;
    }
    UIStackView *replacement = [[UIStackView alloc] init];
    replacement.axis = UILayoutConstraintAxisHorizontal;
    replacement.distribution = UIStackViewDistributionFillEqually;
    replacement.spacing = 0.0;
    replacement.translatesAutoresizingMaskIntoConstraints = NO;
    [_columnStack insertArrangedSubview:replacement atIndex:index];
    return replacement;
}

- (UIView *)_ensureCellAtIndex:(NSUInteger)index inRowStack:(UIStackView *)rowStack {
    while (rowStack.arrangedSubviews.count <= index) {
        UIView *cell = [[UIView alloc] init];
        cell.backgroundColor = [UIColor clearColor];
        cell.layer.borderWidth = 0.5;
        cell.layer.borderColor = [kVCBorder colorWithAlphaComponent:0.70].CGColor;
        cell.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *label = [[UILabel alloc] init];
        label.numberOfLines = 0;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:cell.topAnchor constant:8],
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
            [label.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-8],
        ]];

        [rowStack addArrangedSubview:cell];
    }
    return rowStack.arrangedSubviews[index];
}

- (void)configureWithRows:(NSArray<NSArray<NSString *> *> *)rows role:(NSString *)role {
    NSString *safeRole = VCChatMarkdownSafeString(role);
    NSString *signature = VCChatMarkdownTableSignature(rows, safeRole);
    if ((_lastSignature == signature || [_lastSignature isEqualToString:signature])) {
        return;
    }
    _lastSignature = [signature copy];
    self.backgroundColor = [kVCBgInput colorWithAlphaComponent:0.70];

    NSUInteger maxColumns = 1;
    for (NSArray<NSString *> *row in rows ?: @[]) {
        maxColumns = MAX(maxColumns, row.count);
    }

    while (_columnStack.arrangedSubviews.count > rows.count) {
        UIView *view = _columnStack.arrangedSubviews.lastObject;
        [_columnStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    for (NSUInteger rowIndex = 0; rowIndex < rows.count; rowIndex++) {
        NSArray<NSString *> *row = rows[rowIndex];
        UIStackView *rowStack = [self _ensureRowStackAtIndex:rowIndex];
        rowStack.backgroundColor = rowIndex == 0 ? [kVCBgHover colorWithAlphaComponent:0.92] : [UIColor clearColor];

        while (rowStack.arrangedSubviews.count > maxColumns) {
            UIView *view = rowStack.arrangedSubviews.lastObject;
            [rowStack removeArrangedSubview:view];
            [view removeFromSuperview];
        }

        for (NSUInteger columnIndex = 0; columnIndex < maxColumns; columnIndex++) {
            NSString *value = columnIndex < row.count ? row[columnIndex] : @"";
            UIView *cell = [self _ensureCellAtIndex:columnIndex inRowStack:rowStack];
            UILabel *label = cell.subviews.firstObject;
            if (![label isKindOfClass:[UILabel class]]) continue;
            label.font = rowIndex == 0 ? [UIFont systemFontOfSize:10.2 weight:UIFontWeightBold] : [UIFont systemFontOfSize:10.2 weight:UIFontWeightMedium];
            label.textColor = rowIndex == 0 ? kVCTextPrimary : ([safeRole isEqualToString:@"user"] ? [kVCTextPrimary colorWithAlphaComponent:0.92] : kVCTextSecondary);
            label.text = value;
        }
    }
}

@end

@interface VCChatMarkdownView () <UITextViewDelegate>
@property (nonatomic, strong) UIStackView *stackView;
@end

@implementation VCChatMarkdownView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _stackView = [[UIStackView alloc] init];
        _stackView.axis = UILayoutConstraintAxisVertical;
        _stackView.spacing = 3.0;
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stackView];

        [NSLayoutConstraint activateConstraints:@[
            [_stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (UITextView *)_textViewForMarkdownText:(NSString *)text role:(NSString *)role {
    VCChatInteractiveTextView *textView = [[VCChatInteractiveTextView alloc] initWithFrame:CGRectZero];
    [self _configureTextView:textView markdownText:text role:role];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    return textView;
}

- (void)_configureTextView:(UITextView *)textView markdownText:(NSString *)text role:(NSString *)role {
    if (![textView isKindOfClass:[UITextView class]]) return;
    textView.attributedText = VCChatMarkdownAttributedText(text, role ?: @"assistant");
    textView.delegate = self;
    textView.linkTextAttributes = VCChatMarkdownLinkAttributes();
}

- (UIView *)_preparedArrangedSubviewAtIndex:(NSUInteger)index
                              matchingClass:(Class)viewClass
                                createBlock:(UIView *(^)(void))createBlock {
    NSArray<UIView *> *arrangedSubviews = self.stackView.arrangedSubviews;
    if (index < arrangedSubviews.count) {
        UIView *candidate = arrangedSubviews[index];
        if ([candidate isKindOfClass:viewClass]) {
            return candidate;
        }
    }

    UIView *view = createBlock ? createBlock() : [[viewClass alloc] initWithFrame:CGRectZero];
    if (index < self.stackView.arrangedSubviews.count) {
        [self.stackView insertArrangedSubview:view atIndex:index];
    } else {
        [self.stackView addArrangedSubview:view];
    }
    return view;
}

- (void)_trimArrangedSubviewsStartingAtIndex:(NSUInteger)index {
    NSArray<UIView *> *arrangedSubviews = [self.stackView.arrangedSubviews copy];
    if (index >= arrangedSubviews.count) return;
    for (NSUInteger idx = arrangedSubviews.count; idx > index; idx--) {
        UIView *view = arrangedSubviews[idx - 1];
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

- (void)configureWithMarkdown:(NSString *)markdown role:(NSString *)role {
    NSString *safeMarkdown = VCChatMarkdownSafeString(markdown);
    NSString *safeRole = VCChatMarkdownSafeString(role);
    if ((self.lastMarkdown == safeMarkdown || [self.lastMarkdown isEqualToString:safeMarkdown]) &&
        (self.lastRole == safeRole || [self.lastRole isEqualToString:safeRole])) {
        return;
    }
    self.lastMarkdown = [safeMarkdown copy];
    self.lastRole = [safeRole copy];

    NSUInteger targetIndex = 0;

    for (NSDictionary *segment in VCChatMarkdownSegments(safeMarkdown)) {
        NSString *type = VCChatMarkdownSafeString(segment[@"type"]);
        if ([type isEqualToString:@"code"]) {
            VCChatCodeBlockView *codeBlockView = (VCChatCodeBlockView *)[self _preparedArrangedSubviewAtIndex:targetIndex
                                                                                                 matchingClass:[VCChatCodeBlockView class]
                                                                                                   createBlock:^UIView *{
                return [[VCChatCodeBlockView alloc] initWithFrame:CGRectZero];
            }];
            [codeBlockView configureWithLanguage:VCChatMarkdownSafeString(segment[@"lang"])
                                            code:VCChatMarkdownSafeString(segment[@"content"])];
            targetIndex += 1;
            continue;
        }

        NSString *text = VCChatMarkdownSafeString(segment[@"content"]);
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;

        for (NSString *block in VCChatMarkdownBlocks(text)) {
            NSString *trimmedBlock = [block stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmedBlock.length == 0) continue;
            if ([trimmedBlock isEqualToString:@"---"] || [trimmedBlock isEqualToString:@"***"]) {
                [self _preparedArrangedSubviewAtIndex:targetIndex
                                        matchingClass:[VCChatMarkdownDividerView class]
                                          createBlock:^UIView *{
                    return [[VCChatMarkdownDividerView alloc] initWithFrame:CGRectZero];
                }];
                targetIndex += 1;
                continue;
            }
            if (VCChatMarkdownBlockIsTable(trimmedBlock)) {
                VCChatTableBlockView *tableView = (VCChatTableBlockView *)[self _preparedArrangedSubviewAtIndex:targetIndex
                                                                                                   matchingClass:[VCChatTableBlockView class]
                                                                                                     createBlock:^UIView *{
                    return [[VCChatTableBlockView alloc] initWithFrame:CGRectZero];
                }];
                [tableView configureWithRows:VCChatMarkdownTableRows(trimmedBlock) role:safeRole];
                targetIndex += 1;
                continue;
            }
            if (VCChatMarkdownBlockIsQuote(trimmedBlock)) {
                VCChatQuoteBlockView *quoteView = (VCChatQuoteBlockView *)[self _preparedArrangedSubviewAtIndex:targetIndex
                                                                                                   matchingClass:[VCChatQuoteBlockView class]
                                                                                                     createBlock:^UIView *{
                    return [[VCChatQuoteBlockView alloc] initWithFrame:CGRectZero];
                }];
                quoteView.textDelegate = self;
                [quoteView configureWithText:VCChatMarkdownQuoteBody(trimmedBlock) role:safeRole];
                targetIndex += 1;
                continue;
            }
            VCChatInteractiveTextView *textView = (VCChatInteractiveTextView *)[self _preparedArrangedSubviewAtIndex:targetIndex
                                                                                                        matchingClass:[VCChatInteractiveTextView class]
                                                                                                          createBlock:^UIView *{
                return [self _textViewForMarkdownText:trimmedBlock role:safeRole];
            }];
            [self _configureTextView:textView markdownText:trimmedBlock role:safeRole];
            targetIndex += 1;
        }
    }

    [self _trimArrangedSubviewsStartingAtIndex:targetIndex];
}

- (BOOL)_handleURLInteraction:(NSURL *)URL {
    if (![URL isKindOfClass:[NSURL class]]) return NO;

    NSString *scheme = [URL.scheme lowercaseString] ?: @"";
    if ([scheme isEqualToString:@"vcfile"]) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
        NSString *path = @"";
        NSUInteger line = 0;
        for (NSURLQueryItem *item in components.queryItems ?: @[]) {
            if ([item.name isEqualToString:@"path"]) {
                path = item.value ?: @"";
            } else if ([item.name isEqualToString:@"line"]) {
                line = (NSUInteger)MAX(item.value.integerValue, 0);
            }
        }
        if (path.length > 0) {
            [[NSNotificationCenter defaultCenter] postNotificationName:VCCodeTabRequestOpenFileNotification
                                                                object:self
                                                              userInfo:@{
                                                                  VCCodeTabOpenFilePathKey: path,
                                                                  VCCodeTabOpenFileLineKey: @(line),
                                                              }];
        }
        return NO;
    }

    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"mailto"]) {
        UIApplication *application = UIApplication.sharedApplication;
        [application openURL:URL options:@{} completionHandler:nil];
        return NO;
    }

    return YES;
}

- (BOOL)textView:(UITextView *)textView
shouldInteractWithURL:(NSURL *)URL
         inRange:(NSRange)characterRange
     interaction:(UITextItemInteraction)interaction {
    return [self _handleURLInteraction:URL];
}

- (BOOL)textView:(UITextView *)textView
shouldInteractWithURL:(NSURL *)URL
         inRange:(NSRange)characterRange {
    return [self _handleURLInteraction:URL];
}

@end
