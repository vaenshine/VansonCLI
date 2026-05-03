/**
 * VCChatBubble -- Message bubble cell
 */

#import "VCChatBubble.h"
#import "VCChatMessageBlockView.h"
#import "../../../VansonCLI.h"
#import "../../AI/Chat/VCMessage.h"
#import "../../AI/ToolCall/VCToolCallParser.h"

static NSString *VCChatBubbleTimeString(NSDate *timestamp) {
    if (![timestamp isKindOfClass:[NSDate class]]) return @"";
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"HH:mm";
    });
    formatter.locale = [NSLocale currentLocale];
    return [formatter stringFromDate:timestamp] ?: @"";
}

static UIColor *VCChatBubbleUserSurfaceColor(void) {
    return [UIColor colorWithRed:0.03 green:0.25 blue:0.30 alpha:0.96];
}

static NSString *VCChatBubbleBlockType(NSDictionary *block) {
    return [block[@"type"] isKindOfClass:[NSString class]] ? (NSString *)block[@"type"] : @"markdown";
}

static BOOL VCChatBubbleBlockTypeIsTextLike(NSString *type) {
    return [type isEqualToString:@"markdown"] || [type isEqualToString:@"text"];
}

static BOOL VCChatBubbleBlockTypeIsCardLike(NSString *type) {
    return [type isEqualToString:@"reference"] ||
           [type isEqualToString:@"tool_call"] ||
           [type isEqualToString:@"diagram"] ||
           [type isEqualToString:@"status"];
}

static CGFloat VCChatBubbleSpacingAfterBlock(NSString *currentType, NSString *nextType) {
    if (nextType.length == 0) return 0.0;
    if ([currentType isEqualToString:@"status"] || [nextType isEqualToString:@"status"]) return 6.0;
    if (VCChatBubbleBlockTypeIsTextLike(currentType) && VCChatBubbleBlockTypeIsTextLike(nextType)) return 4.0;
    if (VCChatBubbleBlockTypeIsCardLike(currentType) && VCChatBubbleBlockTypeIsCardLike(nextType)) return 5.0;
    if (VCChatBubbleBlockTypeIsTextLike(currentType) != VCChatBubbleBlockTypeIsTextLike(nextType)) return 6.0;
    return 5.0;
}

static NSString *VCChatBubbleSafeString(id value) {
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
}

static UITableView *VCChatBubbleAncestorTableView(UIView *view) {
    UIView *current = view.superview;
    while (current) {
        if ([current isKindOfClass:[UITableView class]]) return (UITableView *)current;
        current = current.superview;
    }
    return nil;
}

static CGFloat VCChatBubbleMeasuredLineWidth(NSString *line, UIFont *font) {
    NSString *source = VCChatBubbleSafeString(line);
    if (source.length == 0) return 0.0;
    CGRect rect = [source boundingRectWithSize:CGSizeMake(10000.0, CGFLOAT_MAX)
                                       options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                    attributes:@{NSFontAttributeName: font}
                                       context:nil];
    return ceil(CGRectGetWidth(rect));
}

static CGFloat VCChatBubbleMeasuredTextWidth(NSString *text) {
    NSString *source = VCChatBubbleSafeString(text);
    if (source.length == 0) return 0.0;
    UIFont *bodyFont = [UIFont systemFontOfSize:11.2 weight:UIFontWeightRegular];
    UIFont *headingFont = [UIFont systemFontOfSize:13.2 weight:UIFontWeightBold];
    CGFloat width = 0.0;
    NSArray<NSString *> *lines = [source componentsSeparatedByString:@"\n"];
    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;
        UIFont *font = bodyFont;
        if ([line hasPrefix:@"# "]) {
            line = [line substringFromIndex:2];
            font = headingFont;
        } else if ([line hasPrefix:@"## "]) {
            line = [line substringFromIndex:3];
            font = [UIFont systemFontOfSize:12.6 weight:UIFontWeightBold];
        } else if ([line hasPrefix:@"### "]) {
            line = [line substringFromIndex:4];
            font = [UIFont systemFontOfSize:11.8 weight:UIFontWeightBold];
        } else if ([line hasPrefix:@"- "] || [line hasPrefix:@"* "] || [line hasPrefix:@"+ "]) {
            line = line.length > 2 ? [NSString stringWithFormat:@"• %@", [line substringFromIndex:2]] : @"•";
        } else if ([line hasPrefix:@"> "]) {
            line = [line substringFromIndex:2];
        }
        width = MAX(width, VCChatBubbleMeasuredLineWidth(line, font));
    }
    return width;
}

@interface VCChatBubble ()
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UIView *avatarView;
@property (nonatomic, strong) UILabel *avatarLabel;
@property (nonatomic, strong) UILabel *roleBadgeLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIStackView *bodyStack;
@property (nonatomic, strong) NSLayoutConstraint *assistantLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *assistantTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *userTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *minimumLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *maximumTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bubbleWidthLimitConstraint;
@property (nonatomic, strong) NSLayoutConstraint *assistantMaximumWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *assistantContentWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *userMaximumWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *userContentWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarSpacingConstraint;
@property (nonatomic, copy) NSString *lastRenderSignature;
@property (nonatomic, copy) NSString *currentRole;
@property (nonatomic, copy) NSArray<NSDictionary *> *currentBlocks;
@end

@implementation VCChatBubble

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self _buildUI];
    }
    return self;
}

- (void)_buildUI {
    _bubbleView = [[UIView alloc] init];
    _bubbleView.layer.cornerRadius = 10.0;
    _bubbleView.layer.borderWidth = 1.0;
    _bubbleView.layer.shadowColor = [UIColor blackColor].CGColor;
    _bubbleView.layer.shadowOpacity = 0.07;
    _bubbleView.layer.shadowRadius = 6.0;
    _bubbleView.layer.shadowOffset = CGSizeMake(0, 2.0);
    _bubbleView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_bubbleView];

    UIView *headerRow = [[UIView alloc] init];
    headerRow.backgroundColor = [UIColor clearColor];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_bubbleView addSubview:headerRow];

    _avatarView = [[UIView alloc] init];
    _avatarView.layer.cornerRadius = 10.0;
    _avatarView.layer.borderWidth = 1.0;
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:_avatarView];

    _avatarLabel = [[UILabel alloc] init];
    _avatarLabel.font = [UIFont systemFontOfSize:8.2 weight:UIFontWeightBold];
    _avatarLabel.textAlignment = NSTextAlignmentCenter;
    _avatarLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_avatarView addSubview:_avatarLabel];

    _roleBadgeLabel = [[UILabel alloc] init];
    _roleBadgeLabel.font = [UIFont systemFontOfSize:8.8 weight:UIFontWeightBold];
    _roleBadgeLabel.textAlignment = NSTextAlignmentCenter;
    _roleBadgeLabel.layer.cornerRadius = 9.0;
    _roleBadgeLabel.clipsToBounds = YES;
    VCPrepareSingleLineLabel(_roleBadgeLabel, NSLineBreakByTruncatingTail);
    _roleBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:_roleBadgeLabel];

    _timeLabel = [[UILabel alloc] init];
    _timeLabel.font = [UIFont systemFontOfSize:8.4 weight:UIFontWeightMedium];
    _timeLabel.textColor = [kVCTextMuted colorWithAlphaComponent:0.92];
    _timeLabel.textAlignment = NSTextAlignmentRight;
    VCPrepareSingleLineLabel(_timeLabel, NSLineBreakByTruncatingTail);
    _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:_timeLabel];

    _bodyStack = [[UIStackView alloc] init];
    _bodyStack.axis = UILayoutConstraintAxisVertical;
    _bodyStack.spacing = 3.0;
    _bodyStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_bubbleView addSubview:_bodyStack];

    _assistantLeadingConstraint = [_bubbleView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:6];
    _assistantTrailingConstraint = [_bubbleView.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-6];
    _userTrailingConstraint = [_bubbleView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6];
    _minimumLeadingConstraint = [_bubbleView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:6];
    _maximumTrailingConstraint = [_bubbleView.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-6];
    _bubbleWidthLimitConstraint = [_bubbleView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.985];
    _assistantMaximumWidthConstraint = [_bubbleView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.94];
    _assistantContentWidthConstraint = [_bubbleView.widthAnchor constraintEqualToConstant:96.0];
    _userMaximumWidthConstraint = [_bubbleView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.84];
    _userContentWidthConstraint = [_bubbleView.widthAnchor constraintEqualToConstant:72.0];
    _assistantContentWidthConstraint.priority = UILayoutPriorityRequired - 1;
    _userContentWidthConstraint.priority = UILayoutPriorityRequired - 1;
    _avatarWidthConstraint = [_avatarView.widthAnchor constraintEqualToConstant:18.0];
    _avatarSpacingConstraint = [_roleBadgeLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:5.0];

    [NSLayoutConstraint activateConstraints:@[
        [_bubbleView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3],
        [_bubbleView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
        _minimumLeadingConstraint,
        _maximumTrailingConstraint,
        _bubbleWidthLimitConstraint,
        [_bubbleView.widthAnchor constraintGreaterThanOrEqualToConstant:72.0],

        [headerRow.topAnchor constraintEqualToAnchor:_bubbleView.topAnchor constant:4],
        [headerRow.leadingAnchor constraintEqualToAnchor:_bubbleView.leadingAnchor constant:6],
        [headerRow.trailingAnchor constraintEqualToAnchor:_bubbleView.trailingAnchor constant:-6],

        [_avatarView.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor],
        [_avatarView.centerYAnchor constraintEqualToAnchor:_roleBadgeLabel.centerYAnchor],
        _avatarWidthConstraint,
        [_avatarView.heightAnchor constraintEqualToConstant:18.0],
        [_avatarLabel.leadingAnchor constraintEqualToAnchor:_avatarView.leadingAnchor],
        [_avatarLabel.trailingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor],
        [_avatarLabel.topAnchor constraintEqualToAnchor:_avatarView.topAnchor],
        [_avatarLabel.bottomAnchor constraintEqualToAnchor:_avatarView.bottomAnchor],

        _avatarSpacingConstraint,
        [_roleBadgeLabel.topAnchor constraintEqualToAnchor:headerRow.topAnchor],
        [_roleBadgeLabel.bottomAnchor constraintEqualToAnchor:headerRow.bottomAnchor],
        [_roleBadgeLabel.heightAnchor constraintEqualToConstant:16.0],
        [_timeLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_roleBadgeLabel.trailingAnchor constant:4],
        [_timeLabel.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor],
        [_timeLabel.centerYAnchor constraintEqualToAnchor:_roleBadgeLabel.centerYAnchor],

        [_bodyStack.topAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:3],
        [_bodyStack.leadingAnchor constraintEqualToAnchor:_bubbleView.leadingAnchor constant:6],
        [_bodyStack.trailingAnchor constraintEqualToAnchor:_bubbleView.trailingAnchor constant:-6],
        [_bodyStack.bottomAnchor constraintEqualToAnchor:_bubbleView.bottomAnchor constant:-5],
    ]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.lastRenderSignature = nil;
    self.currentRole = nil;
    self.currentBlocks = nil;
    self.assistantMaximumWidthConstraint.active = NO;
    self.assistantContentWidthConstraint.active = NO;
    self.userMaximumWidthConstraint.active = NO;
    self.userContentWidthConstraint.active = NO;
    for (UIView *view in [self.bodyStack.arrangedSubviews copy]) {
        [self.bodyStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self _updateContentWidthConstraints];
}

- (void)configureWithRole:(NSString *)role content:(NSString *)content references:(NSArray<NSDictionary *> *)references toolCalls:(NSArray<VCToolCall *> *)toolCalls {
    VCMessage *message = [VCMessage messageWithRole:role content:content];
    message.references = references;
    message.toolCalls = toolCalls;
    [self configureWithMessage:message];
}

- (void)configureWithMessage:(VCMessage *)message {
    NSString *role = [message.role isKindOfClass:[NSString class]] ? message.role : @"assistant";
    BOOL isUser = [role isEqualToString:@"user"];
    BOOL isSystem = [role isEqualToString:@"system"];
    BOOL isError = [message.content hasPrefix:@"[Error]"];
    NSArray<NSDictionary *> *blocks = [message resolvedBlocks];
    if (blocks.count == 0) {
        blocks = @[@{@"type": @"markdown", @"content": message.content ?: @""}];
    }
    self.currentRole = role;
    self.currentBlocks = blocks;
    NSString *renderSignature = [NSString stringWithFormat:@"%@|%@|%@|%lu|%lu|%lu|%.3f",
                                 message.messageID ?: @"",
                                 role ?: @"",
                                 message.content ?: @"",
                                 (unsigned long)(message.references.count),
                                 (unsigned long)(message.toolCalls.count),
                                 (unsigned long)blocks.count,
                                 message.timestamp.timeIntervalSince1970];
    if ((self.lastRenderSignature == renderSignature || [self.lastRenderSignature isEqualToString:renderSignature]) &&
        self.bodyStack.arrangedSubviews.count == blocks.count) {
        return;
    }
    self.lastRenderSignature = renderSignature;

    UIColor *bubbleBackground = [kVCBgSurface colorWithAlphaComponent:0.97];
    UIColor *bubbleBorder = kVCBorder;
    UIColor *badgeBackground = [kVCAccentDim colorWithAlphaComponent:0.95];
    UIColor *badgeTextColor = kVCAccentHover;
    UIColor *avatarBackground = [kVCAccent colorWithAlphaComponent:0.16];
    UIColor *avatarBorder = [kVCAccent colorWithAlphaComponent:0.28];
    UIColor *avatarTextColor = kVCAccentHover;
    NSString *avatarText = @"VC";
    NSString *badgeTitle = @" VansonCLI ";

    if (isUser) {
        bubbleBackground = VCChatBubbleUserSurfaceColor();
        bubbleBorder = [kVCAccent colorWithAlphaComponent:0.34];
        badgeBackground = [UIColor colorWithWhite:1.0 alpha:0.16];
        badgeTextColor = kVCTextPrimary;
        badgeTitle = @" You ";
        avatarText = @"";
    } else if (isSystem) {
        bubbleBackground = [kVCBgSecondary colorWithAlphaComponent:0.96];
        bubbleBorder = [kVCYellow colorWithAlphaComponent:0.26];
        badgeBackground = [kVCYellow colorWithAlphaComponent:0.14];
        badgeTextColor = kVCYellow;
        badgeTitle = @" Summary ";
        avatarBackground = [kVCYellow colorWithAlphaComponent:0.14];
        avatarBorder = [kVCYellow colorWithAlphaComponent:0.24];
        avatarTextColor = kVCYellow;
        avatarText = @"Σ";
    } else if (isError) {
        bubbleBackground = [kVCRedDim colorWithAlphaComponent:0.94];
        bubbleBorder = [kVCRed colorWithAlphaComponent:0.32];
        badgeBackground = [kVCRed colorWithAlphaComponent:0.18];
        badgeTextColor = kVCRed;
        badgeTitle = @" Error ";
        avatarBackground = [kVCRed colorWithAlphaComponent:0.15];
        avatarBorder = [kVCRed colorWithAlphaComponent:0.28];
        avatarTextColor = kVCRed;
        avatarText = @"!";
    }

    self.bubbleView.backgroundColor = bubbleBackground;
    self.bubbleView.layer.borderColor = bubbleBorder.CGColor;
    self.roleBadgeLabel.font = [UIFont systemFontOfSize:8.8 weight:UIFontWeightBold];
    self.roleBadgeLabel.layer.cornerRadius = 8.0;
    self.roleBadgeLabel.layer.borderWidth = 1.0;
    self.roleBadgeLabel.layer.borderColor = [badgeTextColor colorWithAlphaComponent:0.18].CGColor;
    self.roleBadgeLabel.backgroundColor = badgeBackground;
    self.roleBadgeLabel.textColor = badgeTextColor;
    self.roleBadgeLabel.text = badgeTitle;
    self.avatarView.hidden = isUser;
    self.avatarWidthConstraint.constant = isUser ? 0.0 : 18.0;
    self.avatarSpacingConstraint.constant = isUser ? 0.0 : 5.0;
    self.avatarView.backgroundColor = avatarBackground;
    self.avatarView.layer.borderColor = avatarBorder.CGColor;
    self.avatarLabel.textColor = avatarTextColor;
    self.avatarLabel.text = avatarText;
    self.timeLabel.text = VCChatBubbleTimeString(message.timestamp);
    self.timeLabel.hidden = (self.timeLabel.text.length == 0);

    self.assistantLeadingConstraint.active = !isUser;
    self.assistantTrailingConstraint.active = !isUser;
    self.userTrailingConstraint.active = isUser;
    self.bubbleWidthLimitConstraint.active = YES;
    self.assistantMaximumWidthConstraint.active = !isUser;
    self.assistantContentWidthConstraint.active = !isUser;
    self.userMaximumWidthConstraint.active = isUser;
    self.userContentWidthConstraint.active = isUser;

    NSMutableDictionary<NSString *, VCToolCall *> *toolLookup = [NSMutableDictionary new];
    for (VCToolCall *toolCall in message.toolCalls ?: @[]) {
        if ([toolCall.toolID isKindOfClass:[NSString class]] && toolCall.toolID.length > 0) {
            toolLookup[toolCall.toolID] = toolCall;
        }
    }

    BOOL canReuseBlockViews = (self.bodyStack.arrangedSubviews.count == blocks.count);
    for (UIView *view in self.bodyStack.arrangedSubviews) {
        if (![view isKindOfClass:[VCChatMessageBlockView class]]) {
            canReuseBlockViews = NO;
            break;
        }
    }
    if (!canReuseBlockViews) {
        for (UIView *view in [self.bodyStack.arrangedSubviews copy]) {
            [self.bodyStack removeArrangedSubview:view];
            [view removeFromSuperview];
        }
    }

    for (NSUInteger idx = 0; idx < blocks.count; idx++) {
        NSDictionary *block = blocks[idx];
        VCChatMessageBlockView *blockView = canReuseBlockViews ? (VCChatMessageBlockView *)self.bodyStack.arrangedSubviews[idx] : [[VCChatMessageBlockView alloc] initWithFrame:CGRectZero];
        [blockView configureWithBlock:block role:role toolCallLookup:toolLookup];
        if (!canReuseBlockViews) {
            [self.bodyStack addArrangedSubview:blockView];
        }
        if (idx + 1 < blocks.count) {
            NSString *currentType = VCChatBubbleBlockType(block);
            NSString *nextType = VCChatBubbleBlockType(blocks[idx + 1]);
            [self.bodyStack setCustomSpacing:VCChatBubbleSpacingAfterBlock(currentType, nextType) afterView:blockView];
        }
    }
    [self _updateContentWidthConstraints];
}

- (CGFloat)_availableBubbleContainerWidth {
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    if (width > 0.0) return width;

    UITableView *tableView = VCChatBubbleAncestorTableView(self);
    width = CGRectGetWidth(tableView.bounds);
    if (width > 0.0) return width;

    width = CGRectGetWidth([UIScreen mainScreen].bounds);
    return width > 0.0 ? width : 320.0;
}

- (CGFloat)_preferredBubbleWidthForMaximumWidth:(CGFloat)maximumWidth minimumWidth:(CGFloat)minimumWidth {
    CGFloat contentWidth = 0.0;
    BOOL hasWideBlock = NO;

    for (NSDictionary *block in self.currentBlocks ?: @[]) {
        NSString *type = VCChatBubbleBlockType(block);
        if (!VCChatBubbleBlockTypeIsTextLike(type)) {
            hasWideBlock = YES;
            break;
        }
        NSString *text = VCChatBubbleSafeString(block[@"content"]);
        if ([text containsString:@"```"] || [text containsString:@"|---"] || [text containsString:@"---|"]) {
            hasWideBlock = YES;
            break;
        }
        contentWidth = MAX(contentWidth, VCChatBubbleMeasuredTextWidth(text));
    }

    if (hasWideBlock) return MAX(minimumWidth, maximumWidth);

    CGFloat bodyWidth = contentWidth + 12.0;
    CGFloat headerWidth = 12.0;
    if (!self.avatarView.hidden) {
        headerWidth += self.avatarWidthConstraint.constant + self.avatarSpacingConstraint.constant;
    }
    if (!self.roleBadgeLabel.hidden) {
        headerWidth += ceil([self.roleBadgeLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width);
    }
    if (!self.timeLabel.hidden) {
        headerWidth += 4.0 + ceil([self.timeLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width);
    }

    CGFloat preferredWidth = MAX(minimumWidth, MAX(bodyWidth, headerWidth));
    return MIN(maximumWidth, preferredWidth);
}

- (void)_updateContentWidthConstraints {
    BOOL isUser = [self.currentRole isEqualToString:@"user"];
    BOOL isAssistant = !isUser && self.currentRole.length > 0;
    self.assistantContentWidthConstraint.active = isAssistant;
    self.assistantMaximumWidthConstraint.active = isAssistant;
    self.userContentWidthConstraint.active = isUser;
    self.userMaximumWidthConstraint.active = isUser;
    if (!isUser && !isAssistant) return;

    CGFloat availableWidth = [self _availableBubbleContainerWidth];
    CGFloat maximumWidth = MAX(72.0, availableWidth * (isUser ? 0.84 : 0.94));
    CGFloat minimumWidth = isUser ? 72.0 : 96.0;
    CGFloat preferredWidth = [self _preferredBubbleWidthForMaximumWidth:maximumWidth minimumWidth:minimumWidth];
    NSLayoutConstraint *contentWidthConstraint = isUser ? self.userContentWidthConstraint : self.assistantContentWidthConstraint;
    if (fabs(contentWidthConstraint.constant - preferredWidth) > 0.5) {
        contentWidthConstraint.constant = preferredWidth;
    }
}

@end
