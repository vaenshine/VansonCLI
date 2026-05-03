/**
 * VCMermaidPreviewView -- native inline preview for Mermaid diagrams
 */

#import "VCMermaidPreviewView.h"
#import "../../../VansonCLI.h"

static NSString *VCMermaidTrimmedString(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *VCMermaidUnquotedLabel(NSString *value) {
    NSString *text = VCMermaidTrimmedString(value);
    if (text.length == 0) return @"";

    while (([text hasPrefix:@"["] && [text hasSuffix:@"]"]) ||
           ([text hasPrefix:@"("] && [text hasSuffix:@")"]) ||
           ([text hasPrefix:@"{"] && [text hasSuffix:@"}"])) {
        text = VCMermaidTrimmedString([text substringWithRange:NSMakeRange(1, text.length - 2)]);
    }
    if (([text hasPrefix:@"\""] && [text hasSuffix:@"\""]) ||
        ([text hasPrefix:@"'"] && [text hasSuffix:@"'"])) {
        text = [text substringWithRange:NSMakeRange(1, text.length - 2)];
    }
    return [text stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
}

static NSArray<NSString *> *VCMermaidLines(NSString *content) {
    NSString *safeContent = [content isKindOfClass:[NSString class]] ? content : @"";
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSString *rawLine in [safeContent componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = VCMermaidTrimmedString(rawLine);
        if (line.length == 0 || [line hasPrefix:@"%%"]) continue;
        [lines addObject:line];
    }
    return [lines copy];
}

static NSDictionary *VCMermaidNodeInfoFromFragment(NSString *fragment) {
    NSString *text = VCMermaidTrimmedString(fragment);
    if (text.length == 0) return nil;

    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"_"];
    NSUInteger idx = 0;
    while (idx < text.length && [allowed characterIsMember:[text characterAtIndex:idx]]) {
        idx++;
    }
    if (idx == 0) return nil;

    NSString *nodeID = [text substringToIndex:idx];
    NSString *remainder = VCMermaidTrimmedString([text substringFromIndex:idx]);
    NSString *label = @"";
    if (remainder.length > 0) {
        label = VCMermaidUnquotedLabel(remainder);
    }

    return @{
        @"id": nodeID ?: @"",
        @"label": label.length > 0 ? label : nodeID
    };
}

static NSString *VCMermaidIdentifierFromText(NSString *text) {
    NSString *trimmed = VCMermaidTrimmedString(text);
    if (trimmed.length == 0) return @"";
    if ([trimmed isEqualToString:@"[*]"]) return @"[*]";

    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"_.$:-"];
    NSUInteger idx = 0;
    while (idx < trimmed.length && [allowed characterIsMember:[trimmed characterAtIndex:idx]]) {
        idx++;
    }
    if (idx == 0) return @"";
    return [trimmed substringToIndex:idx];
}

static NSDictionary *VCMermaidEntityInfoFromText(NSString *text) {
    NSString *trimmed = VCMermaidTrimmedString(text);
    if (trimmed.length == 0) return nil;
    if ([trimmed isEqualToString:@"[*]"]) {
        return @{@"id": @"[*]", @"label": @"[*]"};
    }

    NSRange aliasRange = [trimmed rangeOfString:@" as " options:NSCaseInsensitiveSearch];
    if (aliasRange.location != NSNotFound) {
        NSString *left = VCMermaidTrimmedString([trimmed substringToIndex:aliasRange.location]);
        NSString *right = VCMermaidTrimmedString([trimmed substringFromIndex:(aliasRange.location + aliasRange.length)]);
        NSString *rightID = VCMermaidIdentifierFromText(right);
        if (rightID.length > 0) {
            NSString *label = VCMermaidUnquotedLabel(left);
            return @{
                @"id": rightID,
                @"label": label.length > 0 ? label : rightID
            };
        }

        NSString *leftID = VCMermaidIdentifierFromText(left);
        if (leftID.length > 0) {
            NSString *label = VCMermaidUnquotedLabel(right);
            return @{
                @"id": leftID,
                @"label": label.length > 0 ? label : leftID
            };
        }
    }

    NSString *identifier = VCMermaidIdentifierFromText(trimmed);
    if (identifier.length == 0) return nil;
    NSString *remainder = VCMermaidTrimmedString([trimmed substringFromIndex:identifier.length]);
    NSString *label = remainder.length > 0 ? VCMermaidUnquotedLabel(remainder) : identifier;
    return @{
        @"id": identifier,
        @"label": label.length > 0 ? label : identifier
    };
}

static void VCMermaidEnsureGraphNode(NSMutableDictionary<NSString *, NSString *> *nodes,
                                    NSString *nodeID,
                                    NSString *label) {
    NSString *safeID = VCMermaidTrimmedString(nodeID);
    if (safeID.length == 0) return;
    NSString *safeLabel = VCMermaidTrimmedString(label);
    NSString *existing = nodes[safeID];
    if (existing.length == 0 || [existing isEqualToString:safeID]) {
        nodes[safeID] = safeLabel.length > 0 ? safeLabel : safeID;
    }
}

static NSString *VCMermaidClassRelationLabel(NSString *token) {
    if ([token isEqualToString:@"<|--"] || [token isEqualToString:@"--|>"] ||
        [token isEqualToString:@"<|.."] || [token isEqualToString:@"..|>"]) {
        return @"inherits";
    }
    if ([token isEqualToString:@"*--"] || [token isEqualToString:@"--*"]) return @"composes";
    if ([token isEqualToString:@"o--"] || [token isEqualToString:@"--o"]) return @"aggregates";
    if ([token isEqualToString:@"..>"] || [token isEqualToString:@"<.."]) return @"depends";
    if ([token isEqualToString:@"-->"] || [token isEqualToString:@"<--"]) return @"uses";
    if ([token isEqualToString:@".."]) return @"relates";
    if ([token isEqualToString:@"--"]) return @"associates";
    return @"links";
}

static NSDictionary *VCMermaidParseClassRelation(NSString *line) {
    NSString *working = VCMermaidTrimmedString(line);
    if (working.length == 0) return nil;

    NSString *label = @"";
    NSRange colonRange = [working rangeOfString:@":" options:NSBackwardsSearch];
    if (colonRange.location != NSNotFound) {
        label = VCMermaidUnquotedLabel([working substringFromIndex:(colonRange.location + 1)]);
        working = VCMermaidTrimmedString([working substringToIndex:colonRange.location]);
    }

    NSArray<NSString *> *tokens = @[@"<|--", @"--|>", @"<|..", @"..|>", @"*--", @"--*", @"o--", @"--o", @"..>", @"<..", @"-->", @"<--", @"..", @"--"];
    NSSet<NSString *> *reversed = [NSSet setWithArray:@[@"<|--", @"<|..", @"<..", @"<--", @"--*", @"--o"]];

    for (NSString *token in tokens) {
        NSRange tokenRange = [working rangeOfString:token];
        if (tokenRange.location == NSNotFound) continue;

        NSString *left = VCMermaidTrimmedString([working substringToIndex:tokenRange.location]);
        NSString *right = VCMermaidTrimmedString([working substringFromIndex:(tokenRange.location + tokenRange.length)]);
        NSDictionary *leftInfo = VCMermaidEntityInfoFromText(left);
        NSDictionary *rightInfo = VCMermaidEntityInfoFromText(right);
        if (!leftInfo || !rightInfo) return nil;

        BOOL reverse = [reversed containsObject:token];
        NSString *fromID = reverse ? rightInfo[@"id"] : leftInfo[@"id"];
        NSString *toID = reverse ? leftInfo[@"id"] : rightInfo[@"id"];
        NSString *displayLabel = label.length > 0 ? label : VCMermaidClassRelationLabel(token);
        return @{
            @"from": fromID ?: @"",
            @"to": toID ?: @"",
            @"dashed": @([token containsString:@".."]),
            @"label": displayLabel ?: @""
        };
    }
    return nil;
}

static NSDictionary *VCMermaidParseClassDiagram(NSString *content) {
    NSArray<NSString *> *lines = VCMermaidLines(content);
    if (lines.count == 0) return nil;
    if (![[lines.firstObject lowercaseString] hasPrefix:@"classdiagram"]) return nil;

    NSMutableDictionary<NSString *, NSString *> *nodes = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *membersByID = [NSMutableDictionary new];
    NSMutableArray<NSDictionary *> *edges = [NSMutableArray new];
    NSString *currentClassID = nil;

    for (NSUInteger idx = 1; idx < lines.count; idx++) {
        NSString *line = lines[idx];
        NSString *lower = [line lowercaseString];

        if (currentClassID.length > 0) {
            if ([line isEqualToString:@"}"]) {
                currentClassID = nil;
                continue;
            }
            NSString *memberLine = VCMermaidTrimmedString(line);
            if (memberLine.length > 0) {
                if (!membersByID[currentClassID]) membersByID[currentClassID] = [NSMutableArray new];
                [membersByID[currentClassID] addObject:memberLine];
            }
            continue;
        }

        if ([lower hasPrefix:@"direction "] || [lower hasPrefix:@"namespace "] || [line isEqualToString:@"}"]) {
            continue;
        }

        if ([lower hasPrefix:@"class "]) {
            NSString *body = VCMermaidTrimmedString([line substringFromIndex:6]);
            BOOL opensBlock = [body hasSuffix:@"{"];
            if (opensBlock) {
                body = VCMermaidTrimmedString([body substringToIndex:body.length - 1]);
            }
            NSDictionary *info = VCMermaidEntityInfoFromText(body);
            if (info) {
                VCMermaidEnsureGraphNode(nodes, info[@"id"], info[@"label"]);
                if (opensBlock) {
                    currentClassID = info[@"id"];
                }
            }
            continue;
        }

        NSDictionary *relation = VCMermaidParseClassRelation(line);
        if (relation) {
            VCMermaidEnsureGraphNode(nodes, relation[@"from"], relation[@"from"]);
            VCMermaidEnsureGraphNode(nodes, relation[@"to"], relation[@"to"]);
            [edges addObject:relation];
            continue;
        }

        NSRange memberRange = [line rangeOfString:@":"];
        if (memberRange.location != NSNotFound) {
            NSString *ownerText = VCMermaidTrimmedString([line substringToIndex:memberRange.location]);
            NSString *memberLine = VCMermaidTrimmedString([line substringFromIndex:(memberRange.location + 1)]);
            NSString *ownerID = VCMermaidIdentifierFromText(ownerText);
            if (ownerID.length > 0 && memberLine.length > 0) {
                VCMermaidEnsureGraphNode(nodes, ownerID, ownerID);
                if (!membersByID[ownerID]) membersByID[ownerID] = [NSMutableArray new];
                [membersByID[ownerID] addObject:memberLine];
                continue;
            }
        }

        NSDictionary *info = VCMermaidEntityInfoFromText(line);
        if (info) {
            VCMermaidEnsureGraphNode(nodes, info[@"id"], info[@"label"]);
        }
    }

    if (nodes.count == 0) return nil;

    NSMutableDictionary<NSString *, NSString *> *displayNodes = [NSMutableDictionary new];
    for (NSString *nodeID in nodes) {
        NSString *label = nodes[nodeID] ?: nodeID;
        NSArray<NSString *> *members = [membersByID[nodeID] copy] ?: @[];
        if (members.count > 0) {
            NSString *body = [members componentsJoinedByString:@"\n"];
            displayNodes[nodeID] = [NSString stringWithFormat:@"%@\n\n%@", label, body];
        } else {
            displayNodes[nodeID] = label;
        }
    }

    return @{
        @"kind": @"flowchart",
        @"sourceKind": @"class",
        @"nodes": [displayNodes copy],
        @"edges": [edges copy]
    };
}

static NSDictionary *VCMermaidStateEndpointInfo(NSString *text, BOOL sourceSide) {
    NSString *trimmed = VCMermaidTrimmedString(text);
    if ([trimmed isEqualToString:@"[*]"]) {
        return @{
            @"id": sourceSide ? @"__state_start__" : @"__state_end__",
            @"label": sourceSide ? @"Start" : @"End"
        };
    }
    return VCMermaidEntityInfoFromText(trimmed);
}

static NSDictionary *VCMermaidParseStateTransition(NSString *line) {
    NSString *working = VCMermaidTrimmedString(line);
    if (working.length == 0) return nil;

    NSString *label = @"";
    NSRange colonRange = [working rangeOfString:@":" options:NSBackwardsSearch];
    if (colonRange.location != NSNotFound) {
        label = VCMermaidUnquotedLabel([working substringFromIndex:(colonRange.location + 1)]);
        working = VCMermaidTrimmedString([working substringToIndex:colonRange.location]);
    }

    NSArray<NSString *> *tokens = @[@"-.->", @"-->"];
    for (NSString *token in tokens) {
        NSRange tokenRange = [working rangeOfString:token];
        if (tokenRange.location == NSNotFound) continue;

        NSDictionary *fromInfo = VCMermaidStateEndpointInfo([working substringToIndex:tokenRange.location], YES);
        NSDictionary *toInfo = VCMermaidStateEndpointInfo([working substringFromIndex:(tokenRange.location + tokenRange.length)], NO);
        if (!fromInfo || !toInfo) return nil;

        return @{
            @"from": fromInfo[@"id"] ?: @"",
            @"to": toInfo[@"id"] ?: @"",
            @"fromLabel": fromInfo[@"label"] ?: fromInfo[@"id"] ?: @"",
            @"toLabel": toInfo[@"label"] ?: toInfo[@"id"] ?: @"",
            @"dashed": @([token containsString:@".-"]),
            @"label": label ?: @""
        };
    }
    return nil;
}

static NSDictionary *VCMermaidParseStateDiagram(NSString *content) {
    NSArray<NSString *> *lines = VCMermaidLines(content);
    if (lines.count == 0) return nil;
    if (![[lines.firstObject lowercaseString] hasPrefix:@"statediagram"]) return nil;

    NSMutableDictionary<NSString *, NSString *> *nodes = [NSMutableDictionary new];
    NSMutableArray<NSDictionary *> *edges = [NSMutableArray new];

    for (NSUInteger idx = 1; idx < lines.count; idx++) {
        NSString *line = lines[idx];
        NSString *lower = [line lowercaseString];
        if ([line isEqualToString:@"}"] || [lower hasPrefix:@"direction "] || [line isEqualToString:@"{"]) {
            continue;
        }

        if ([lower hasPrefix:@"state "]) {
            NSString *body = VCMermaidTrimmedString([line substringFromIndex:6]);
            if ([body hasSuffix:@"{"]) {
                body = VCMermaidTrimmedString([body substringToIndex:body.length - 1]);
            }
            NSDictionary *info = VCMermaidEntityInfoFromText(body);
            if (info) {
                VCMermaidEnsureGraphNode(nodes, info[@"id"], info[@"label"]);
            }
            continue;
        }

        NSDictionary *transition = VCMermaidParseStateTransition(line);
        if (transition) {
            VCMermaidEnsureGraphNode(nodes, transition[@"from"], transition[@"fromLabel"]);
            VCMermaidEnsureGraphNode(nodes, transition[@"to"], transition[@"toLabel"]);
            [edges addObject:transition];
            continue;
        }

        NSDictionary *info = VCMermaidEntityInfoFromText(line);
        if (info) {
            VCMermaidEnsureGraphNode(nodes, info[@"id"], info[@"label"]);
        }
    }

    if (nodes.count == 0) return nil;
    return @{
        @"kind": @"flowchart",
        @"sourceKind": @"state",
        @"nodes": [nodes copy],
        @"edges": [edges copy]
    };
}

static NSDictionary *VCMermaidParseFlowchart(NSString *content) {
    NSArray<NSString *> *lines = VCMermaidLines(content);
    if (lines.count == 0) return nil;
    NSString *header = [lines.firstObject lowercaseString];
    if (![header hasPrefix:@"flowchart"] && ![header hasPrefix:@"graph"]) return nil;

    NSMutableDictionary<NSString *, NSString *> *nodes = [NSMutableDictionary new];
    NSMutableArray<NSDictionary *> *edges = [NSMutableArray new];

    for (NSUInteger idx = 1; idx < lines.count; idx++) {
        NSString *line = lines[idx];
        NSString *edgeToken = nil;
        BOOL dashed = NO;
        if ([line containsString:@"-.->"]) {
            edgeToken = @"-.->";
            dashed = YES;
        } else if ([line containsString:@"-->"]) {
            edgeToken = @"-->";
        }

        if (edgeToken.length > 0) {
            NSRange tokenRange = [line rangeOfString:edgeToken];
            NSString *left = [line substringToIndex:tokenRange.location];
            NSString *right = [line substringFromIndex:(tokenRange.location + tokenRange.length)];
            NSDictionary *fromInfo = VCMermaidNodeInfoFromFragment(left);
            NSDictionary *toInfo = VCMermaidNodeInfoFromFragment(right);
            if (!fromInfo || !toInfo) continue;

            nodes[fromInfo[@"id"]] = fromInfo[@"label"];
            nodes[toInfo[@"id"]] = toInfo[@"label"];
            [edges addObject:@{
                @"from": fromInfo[@"id"],
                @"to": toInfo[@"id"],
                @"dashed": @(dashed)
            }];
            continue;
        }

        NSDictionary *nodeInfo = VCMermaidNodeInfoFromFragment(line);
        if (nodeInfo) {
            nodes[nodeInfo[@"id"]] = nodeInfo[@"label"];
        }
    }

    if (nodes.count == 0) return nil;
    return @{
        @"kind": @"flowchart",
        @"nodes": [nodes copy],
        @"edges": [edges copy]
    };
}

static NSDictionary *VCMermaidParseSequence(NSString *content) {
    NSArray<NSString *> *lines = VCMermaidLines(content);
    if (lines.count == 0) return nil;
    if (![[lines.firstObject lowercaseString] hasPrefix:@"sequencediagram"]) return nil;

    NSMutableArray<NSDictionary *> *participants = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSDictionary *> *participantsByID = [NSMutableDictionary new];
    NSMutableArray<NSDictionary *> *messages = [NSMutableArray new];

    void (^ensureParticipant)(NSString *, NSString *, BOOL) = ^(NSString *identifier, NSString *label, BOOL actor) {
        NSString *safeID = VCMermaidTrimmedString(identifier);
        if (safeID.length == 0) return;
        if (participantsByID[safeID]) return;
        NSDictionary *entry = @{
            @"id": safeID,
            @"label": (VCMermaidTrimmedString(label).length > 0 ? VCMermaidTrimmedString(label) : safeID),
            @"actor": @(actor)
        };
        participantsByID[safeID] = entry;
        [participants addObject:entry];
    };

    for (NSUInteger idx = 1; idx < lines.count; idx++) {
        NSString *line = lines[idx];
        NSString *lower = [line lowercaseString];

        if ([lower hasPrefix:@"actor "] || [lower hasPrefix:@"participant "]) {
            BOOL actor = [lower hasPrefix:@"actor "];
            NSString *body = VCMermaidTrimmedString([line substringFromIndex:(actor ? 6 : 12)]);
            NSRange aliasRange = [body rangeOfString:@" as " options:NSCaseInsensitiveSearch];
            NSString *identifier = body;
            NSString *label = body;
            if (aliasRange.location != NSNotFound) {
                identifier = VCMermaidTrimmedString([body substringToIndex:aliasRange.location]);
                label = VCMermaidUnquotedLabel([body substringFromIndex:(aliasRange.location + aliasRange.length)]);
            }
            ensureParticipant(identifier, label, actor);
            continue;
        }

        NSString *messageToken = nil;
        BOOL dashed = NO;
        if ([line containsString:@"-->>"]) {
            messageToken = @"-->>";
            dashed = YES;
        } else if ([line containsString:@"->>"]) {
            messageToken = @"->>";
        }
        if (messageToken.length == 0) continue;

        NSRange tokenRange = [line rangeOfString:messageToken];
        NSString *left = VCMermaidTrimmedString([line substringToIndex:tokenRange.location]);
        NSString *right = VCMermaidTrimmedString([line substringFromIndex:(tokenRange.location + tokenRange.length)]);
        NSRange colonRange = [right rangeOfString:@":"];
        NSString *targetID = colonRange.location == NSNotFound ? right : VCMermaidTrimmedString([right substringToIndex:colonRange.location]);
        NSString *label = colonRange.location == NSNotFound ? @"" : VCMermaidUnquotedLabel([right substringFromIndex:(colonRange.location + 1)]);
        ensureParticipant(left, left, [left isEqualToString:@"User"]);
        ensureParticipant(targetID, targetID, [targetID isEqualToString:@"User"]);
        [messages addObject:@{
            @"from": left ?: @"",
            @"to": targetID ?: @"",
            @"label": label ?: @"",
            @"dashed": @(dashed)
        }];
    }

    if (participants.count == 0) return nil;
    return @{
        @"kind": @"sequence",
        @"participants": [participants copy],
        @"messages": [messages copy]
    };
}

static NSDictionary *VCMermaidParseDiagram(NSString *content) {
    NSDictionary *sequence = VCMermaidParseSequence(content);
    if (sequence) return sequence;
    NSDictionary *classDiagram = VCMermaidParseClassDiagram(content);
    if (classDiagram) return classDiagram;
    NSDictionary *stateDiagram = VCMermaidParseStateDiagram(content);
    if (stateDiagram) return stateDiagram;
    NSDictionary *flowchart = VCMermaidParseFlowchart(content);
    if (flowchart) return flowchart;
    return @{
        @"kind": @"fallback"
    };
}

static CGSize VCMermaidTextSize(NSString *text, UIFont *font, CGFloat maxWidth) {
    NSString *safeText = [text isKindOfClass:[NSString class]] ? text : @"";
    CGRect rect = [safeText boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      attributes:@{NSFontAttributeName: font}
                                         context:nil];
    return CGSizeMake(ceil(rect.size.width), ceil(rect.size.height));
}

@interface VCMermaidPreviewView ()
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) NSLayoutConstraint *scrollHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *summaryTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *summaryHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *scrollTopConstraint;
@property (nonatomic, copy) NSString *mermaidContent;
@property (nonatomic, copy) NSString *diagramType;
@property (nonatomic, copy) NSDictionary *parsedDiagram;
@property (nonatomic, assign) CGFloat lastRenderedWidth;
@end

@implementation VCMermaidPreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self _buildUI];
    }
    return self;
}

- (void)_buildUI {
    _cardView = [[UIView alloc] init];
    _cardView.backgroundColor = [kVCBgHover colorWithAlphaComponent:0.94];
    _cardView.layer.cornerRadius = kVCRadius;
    _cardView.layer.borderWidth = 1.0;
    _cardView.layer.borderColor = kVCBorderStrong.CGColor;
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_cardView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _titleLabel.textColor = kVCAccentHover;
    _titleLabel.numberOfLines = 1;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_titleLabel];

    _summaryLabel = [[UILabel alloc] init];
    _summaryLabel.font = [UIFont systemFontOfSize:10];
    _summaryLabel.textColor = kVCTextMuted;
    _summaryLabel.numberOfLines = 2;
    _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_summaryLabel];

    _scrollView = [[UIScrollView alloc] init];
    _scrollView.showsHorizontalScrollIndicator = YES;
    _scrollView.showsVerticalScrollIndicator = YES;
    _scrollView.backgroundColor = [kVCBgPrimary colorWithAlphaComponent:0.45];
    _scrollView.layer.cornerRadius = 8.0;
    _scrollView.layer.borderWidth = 1.0;
    _scrollView.layer.borderColor = kVCBorder.CGColor;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardView addSubview:_scrollView];

    _canvasView = [[UIView alloc] initWithFrame:CGRectZero];
    _canvasView.backgroundColor = [UIColor clearColor];
    [_scrollView addSubview:_canvasView];

    _scrollHeightConstraint = [_scrollView.heightAnchor constraintEqualToConstant:184.0];
    _summaryTopConstraint = [_summaryLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3];
    _summaryHeightConstraint = [_summaryLabel.heightAnchor constraintEqualToConstant:0.0];
    _scrollTopConstraint = [_scrollView.topAnchor constraintEqualToAnchor:_summaryLabel.bottomAnchor constant:8];

    [NSLayoutConstraint activateConstraints:@[
        [_cardView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_cardView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:10],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:10],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-10],
        _summaryTopConstraint,
        [_summaryLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_summaryLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        _scrollTopConstraint,
        [_scrollView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:10],
        [_scrollView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-10],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-10],
        _scrollHeightConstraint,
    ]];
}

- (void)configureWithTitle:(NSString *)title
                   summary:(NSString *)summary
                   content:(NSString *)content
               diagramType:(NSString *)diagramType {
    self.titleLabel.text = VCMermaidTrimmedString(title).length > 0 ? VCMermaidTrimmedString(title) : @"Mermaid Diagram";
    self.summaryLabel.text = VCMermaidTrimmedString(summary);
    BOOL hasSummary = (self.summaryLabel.text.length > 0);
    self.summaryLabel.hidden = !hasSummary;
    self.summaryHeightConstraint.active = !hasSummary;
    self.summaryTopConstraint.constant = hasSummary ? 3.0 : 0.0;
    self.scrollTopConstraint.constant = hasSummary ? 8.0 : 6.0;
    self.mermaidContent = [content isKindOfClass:[NSString class]] ? content : @"";
    self.diagramType = [diagramType isKindOfClass:[NSString class]] ? diagramType : @"";
    self.parsedDiagram = VCMermaidParseDiagram(self.mermaidContent);
    self.lastRenderedWidth = 0;
    self.scrollHeightConstraint.constant = [self _preferredPreviewHeight];
    [self setNeedsLayout];
}

- (CGFloat)_preferredPreviewHeight {
    NSString *kind = self.parsedDiagram[@"kind"];
    if ([kind isEqualToString:@"sequence"]) {
        NSUInteger count = [self.parsedDiagram[@"messages"] count];
        return MIN(280.0, MAX(150.0, 88.0 + count * 36.0));
    }
    if ([kind isEqualToString:@"flowchart"]) {
        NSUInteger nodeCount = [self.parsedDiagram[@"nodes"] count];
        NSString *sourceKind = self.parsedDiagram[@"sourceKind"];
        if ([sourceKind isEqualToString:@"class"]) {
            return MIN(360.0, MAX(180.0, 128.0 + ceil(nodeCount / 2.0) * 52.0));
        }
        if ([sourceKind isEqualToString:@"state"]) {
            return MIN(320.0, MAX(170.0, 118.0 + ceil(nodeCount / 2.0) * 42.0));
        }
        return MIN(300.0, MAX(160.0, 110.0 + ceil(nodeCount / 2.0) * 34.0));
    }
    return 150.0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat renderWidth = MAX(220.0, CGRectGetWidth(self.scrollView.bounds));
    if (renderWidth <= 0) return;
    if (fabs(renderWidth - self.lastRenderedWidth) < 1.0 && self.canvasView.subviews.count > 0) return;
    self.lastRenderedWidth = renderWidth;
    [self _renderForWidth:renderWidth];
}

- (void)_renderForWidth:(CGFloat)renderWidth {
    for (UIView *subview in [self.canvasView.subviews copy]) {
        [subview removeFromSuperview];
    }
    self.canvasView.layer.sublayers = nil;

    NSString *kind = self.parsedDiagram[@"kind"];
    if ([kind isEqualToString:@"sequence"]) {
        [self _renderSequenceForWidth:renderWidth];
        return;
    }
    if ([kind isEqualToString:@"flowchart"]) {
        [self _renderFlowchartForWidth:renderWidth];
        return;
    }
    [self _renderFallbackForWidth:renderWidth];
}

- (void)_renderFallbackForWidth:(CGFloat)renderWidth {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, 12, MAX(200.0, renderWidth - 24.0), 0)];
    label.font = kVCFontMonoSm ?: [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    label.textColor = kVCTextSecondary;
    label.numberOfLines = 0;
    label.text = VCMermaidTrimmedString(self.mermaidContent);
    [label sizeToFit];
    CGRect frame = label.frame;
    frame.size.width = MAX(frame.size.width, MIN(renderWidth - 24.0, 280.0));
    label.frame = frame;
    [self.canvasView addSubview:label];
    self.canvasView.frame = CGRectMake(0, 0, MAX(renderWidth, CGRectGetMaxX(label.frame) + 12.0), CGRectGetMaxY(label.frame) + 12.0);
    self.scrollView.contentSize = self.canvasView.frame.size;
}

- (void)_renderFlowchartForWidth:(CGFloat)renderWidth {
    NSDictionary<NSString *, NSString *> *nodes = [self.parsedDiagram[@"nodes"] isKindOfClass:[NSDictionary class]] ? self.parsedDiagram[@"nodes"] : @{};
    NSArray<NSDictionary *> *edges = [self.parsedDiagram[@"edges"] isKindOfClass:[NSArray class]] ? self.parsedDiagram[@"edges"] : @[];
    NSString *sourceKind = [self.parsedDiagram[@"sourceKind"] isKindOfClass:[NSString class]] ? self.parsedDiagram[@"sourceKind"] : @"";
    BOOL isClassDiagram = [sourceKind isEqualToString:@"class"];
    BOOL isStateDiagram = [sourceKind isEqualToString:@"state"];
    NSArray<NSString *> *nodeIDs = [[nodes allKeys] sortedArrayUsingSelector:@selector(compare:)];
    if (nodeIDs.count == 0) {
        [self _renderFallbackForWidth:renderWidth];
        return;
    }

    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *children = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSNumber *> *indegree = [NSMutableDictionary new];
    for (NSString *nodeID in nodeIDs) {
        children[nodeID] = [NSMutableArray new];
        indegree[nodeID] = @0;
    }
    for (NSDictionary *edge in edges) {
        NSString *from = edge[@"from"];
        NSString *to = edge[@"to"];
        if (!children[from]) children[from] = [NSMutableArray new];
        [children[from] addObject:to ?: @""];
        indegree[to] = @([indegree[to] integerValue] + 1);
    }

    NSMutableArray<NSString *> *roots = [NSMutableArray new];
    for (NSString *nodeID in nodeIDs) {
        if ([indegree[nodeID] integerValue] == 0) {
            [roots addObject:nodeID];
        }
    }
    if (roots.count == 0) {
        [roots addObjectsFromArray:nodeIDs];
    }

    NSMutableDictionary<NSString *, NSNumber *> *depths = [NSMutableDictionary new];
    NSMutableArray<NSString *> *queue = [roots mutableCopy];
    for (NSString *nodeID in roots) {
        depths[nodeID] = @0;
    }
    for (NSUInteger idx = 0; idx < queue.count; idx++) {
        NSString *nodeID = queue[idx];
        NSUInteger nextDepth = [depths[nodeID] unsignedIntegerValue] + 1;
        for (NSString *childID in children[nodeID] ?: @[]) {
            NSUInteger currentDepth = [depths[childID] unsignedIntegerValue];
            if (!depths[childID] || nextDepth > currentDepth) {
                depths[childID] = @(nextDepth);
            }
            if (![queue containsObject:childID]) {
                [queue addObject:childID];
            }
        }
    }
    for (NSString *nodeID in nodeIDs) {
        if (!depths[nodeID]) depths[nodeID] = @0;
    }

    NSMutableDictionary<NSNumber *, NSMutableArray<NSString *> *> *layers = [NSMutableDictionary new];
    NSUInteger maxDepth = 0;
    for (NSString *nodeID in nodeIDs) {
        NSNumber *depthNumber = depths[nodeID] ?: @0;
        maxDepth = MAX(maxDepth, [depthNumber unsignedIntegerValue]);
        if (!layers[depthNumber]) layers[depthNumber] = [NSMutableArray new];
        [layers[depthNumber] addObject:nodeID];
    }

    UIFont *font = isClassDiagram
        ? (kVCFontMonoSm ?: [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular])
        : [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    CGFloat horizontalGap = isClassDiagram ? 28.0 : 24.0;
    CGFloat verticalGap = isClassDiagram ? 54.0 : (isStateDiagram ? 48.0 : 44.0);
    CGFloat paddingX = isClassDiagram ? 14.0 : 12.0;
    CGFloat paddingY = isClassDiagram ? 10.0 : 8.0;
    CGFloat minNodeWidth = isClassDiagram ? 128.0 : (isStateDiagram ? 92.0 : 84.0);
    CGFloat maxNodeWidth = isClassDiagram ? 230.0 : 180.0;
    NSMutableDictionary<NSString *, NSValue *> *frames = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, NSNumber *> *layerHeights = [NSMutableDictionary new];
    CGFloat canvasWidth = renderWidth;

    for (NSUInteger depth = 0; depth <= maxDepth; depth++) {
        NSArray<NSString *> *layerNodeIDs = layers[@(depth)] ?: @[];
        CGFloat totalWidth = 0;
        CGFloat maxHeight = 0;
        NSMutableDictionary<NSString *, NSValue *> *sizes = [NSMutableDictionary new];
        for (NSString *nodeID in layerNodeIDs) {
            NSString *label = nodes[nodeID] ?: nodeID;
            CGSize textSize = VCMermaidTextSize(label, font, maxNodeWidth - paddingX * 2.0);
            CGFloat nodeWidth = MIN(maxNodeWidth, MAX(minNodeWidth, textSize.width + paddingX * 2.0));
            CGFloat nodeHeight = MAX(36.0, textSize.height + paddingY * 2.0);
            sizes[nodeID] = [NSValue valueWithCGSize:CGSizeMake(nodeWidth, nodeHeight)];
            totalWidth += nodeWidth;
            maxHeight = MAX(maxHeight, nodeHeight);
        }
        totalWidth += MAX(0, (CGFloat)layerNodeIDs.count - 1.0) * horizontalGap;
        canvasWidth = MAX(canvasWidth, totalWidth + 40.0);
        layerHeights[@(depth)] = @(maxHeight);
        CGFloat x = MAX(20.0, (canvasWidth - totalWidth) * 0.5);
        CGFloat y = 20.0;
        for (NSUInteger prior = 0; prior < depth; prior++) {
            y += [layerHeights[@(prior)] doubleValue] + verticalGap;
        }
        for (NSString *nodeID in layerNodeIDs) {
            CGSize nodeSize = [sizes[nodeID] CGSizeValue];
            CGRect frame = CGRectMake(x, y, nodeSize.width, nodeSize.height);
            frames[nodeID] = [NSValue valueWithCGRect:frame];
            x += nodeSize.width + horizontalGap;
        }
    }

    CGFloat canvasHeight = 24.0;
    for (NSUInteger depth = 0; depth <= maxDepth; depth++) {
        NSArray<NSString *> *layerNodeIDs = layers[@(depth)] ?: @[];
        for (NSString *nodeID in layerNodeIDs) {
            canvasHeight = MAX(canvasHeight, CGRectGetMaxY([frames[nodeID] CGRectValue]));
        }
    }
    canvasHeight += 28.0;

    self.canvasView.frame = CGRectMake(0, 0, canvasWidth, canvasHeight);

    CAShapeLayer *solidEdgeLayer = [CAShapeLayer layer];
    solidEdgeLayer.strokeColor = [kVCAccent colorWithAlphaComponent:0.55].CGColor;
    solidEdgeLayer.fillColor = UIColor.clearColor.CGColor;
    solidEdgeLayer.lineWidth = 1.5;
    UIBezierPath *solidEdgePath = [UIBezierPath bezierPath];

    CAShapeLayer *dashedEdgeLayer = [CAShapeLayer layer];
    dashedEdgeLayer.strokeColor = [kVCTextSecondary colorWithAlphaComponent:0.42].CGColor;
    dashedEdgeLayer.fillColor = UIColor.clearColor.CGColor;
    dashedEdgeLayer.lineWidth = 1.2;
    dashedEdgeLayer.lineDashPattern = @[@4, @4];
    UIBezierPath *dashedEdgePath = [UIBezierPath bezierPath];

    CAShapeLayer *arrowHeadLayer = [CAShapeLayer layer];
    arrowHeadLayer.strokeColor = [kVCAccent colorWithAlphaComponent:0.55].CGColor;
    arrowHeadLayer.fillColor = UIColor.clearColor.CGColor;
    arrowHeadLayer.lineWidth = 1.35;
    UIBezierPath *arrowHeadPath = [UIBezierPath bezierPath];
    NSMutableArray<NSDictionary *> *edgeLabels = [NSMutableArray new];

    for (NSDictionary *edge in edges) {
        CGRect fromFrame = [frames[edge[@"from"]] CGRectValue];
        CGRect toFrame = [frames[edge[@"to"]] CGRectValue];
        if (CGRectIsEmpty(fromFrame) || CGRectIsEmpty(toFrame)) continue;
        CGPoint start = CGPointMake(CGRectGetMidX(fromFrame), CGRectGetMaxY(fromFrame));
        CGPoint end = CGPointMake(CGRectGetMidX(toFrame), CGRectGetMinY(toFrame));
        CGFloat midY = (start.y + end.y) * 0.5;
        UIBezierPath *targetPath = [edge[@"dashed"] boolValue] ? dashedEdgePath : solidEdgePath;
        [targetPath moveToPoint:start];
        [targetPath addCurveToPoint:end
                      controlPoint1:CGPointMake(start.x, midY)
                      controlPoint2:CGPointMake(end.x, midY)];
        CGFloat arrowAngle = atan2(end.y - midY, 0.0);
        CGPoint headA = CGPointMake(end.x - cos(arrowAngle - M_PI / 6.0) * 6.0,
                                    end.y - sin(arrowAngle - M_PI / 6.0) * 6.0);
        CGPoint headB = CGPointMake(end.x - cos(arrowAngle + M_PI / 6.0) * 6.0,
                                    end.y - sin(arrowAngle + M_PI / 6.0) * 6.0);
        [arrowHeadPath moveToPoint:end];
        [arrowHeadPath addLineToPoint:headA];
        [arrowHeadPath moveToPoint:end];
        [arrowHeadPath addLineToPoint:headB];

        NSString *edgeLabel = VCMermaidTrimmedString(edge[@"label"]);
        if (edgeLabel.length > 0) {
            [edgeLabels addObject:@{
                @"label": edgeLabel,
                @"point": [NSValue valueWithCGPoint:CGPointMake((start.x + end.x) * 0.5, midY)]
            }];
        }
    }
    solidEdgeLayer.path = solidEdgePath.CGPath;
    dashedEdgeLayer.path = dashedEdgePath.CGPath;
    arrowHeadLayer.path = arrowHeadPath.CGPath;
    if (!CGPathIsEmpty(solidEdgeLayer.path)) {
        [self.canvasView.layer addSublayer:solidEdgeLayer];
    }
    if (!CGPathIsEmpty(dashedEdgeLayer.path)) {
        [self.canvasView.layer addSublayer:dashedEdgeLayer];
    }
    if (!CGPathIsEmpty(arrowHeadLayer.path)) {
        [self.canvasView.layer addSublayer:arrowHeadLayer];
    }

    for (NSDictionary *edgeLabelEntry in edgeLabels) {
        NSString *text = edgeLabelEntry[@"label"];
        CGPoint point = [edgeLabelEntry[@"point"] CGPointValue];
        UILabel *edgeChip = [[UILabel alloc] initWithFrame:CGRectZero];
        edgeChip.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        edgeChip.textColor = kVCTextSecondary;
        edgeChip.backgroundColor = [kVCBgPrimary colorWithAlphaComponent:0.9];
        edgeChip.layer.cornerRadius = 8.0;
        edgeChip.clipsToBounds = YES;
        edgeChip.textAlignment = NSTextAlignmentCenter;
        edgeChip.text = [NSString stringWithFormat:@" %@ ", text];
        [edgeChip sizeToFit];
        CGRect chipFrame = edgeChip.frame;
        chipFrame.size.width = MIN(MAX(chipFrame.size.width + 8.0, 48.0), isClassDiagram ? 150.0 : 120.0);
        chipFrame.size.height = 18.0;
        chipFrame.origin.x = point.x - chipFrame.size.width * 0.5;
        chipFrame.origin.y = point.y - 9.0;
        edgeChip.frame = chipFrame;
        [self.canvasView addSubview:edgeChip];
    }

    for (NSString *nodeID in nodeIDs) {
        CGRect frame = [frames[nodeID] CGRectValue];
        UIView *nodeCard = [[UIView alloc] initWithFrame:frame];
        nodeCard.backgroundColor = isStateDiagram ? [kVCBgHover colorWithAlphaComponent:0.98] : [kVCBgSurface colorWithAlphaComponent:0.98];
        nodeCard.layer.cornerRadius = isStateDiagram ? 14.0 : 10.0;
        nodeCard.layer.borderWidth = 1.0;
        nodeCard.layer.borderColor = (isClassDiagram ? [kVCBorderStrong colorWithAlphaComponent:0.7] : [kVCBorderAccent colorWithAlphaComponent:0.55]).CGColor;
        [self.canvasView addSubview:nodeCard];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(nodeCard.bounds, isClassDiagram ? 10.0 : 8.0, isClassDiagram ? 8.0 : 6.0)];
        label.font = font;
        label.textColor = kVCTextPrimary;
        label.numberOfLines = 0;
        label.textAlignment = isClassDiagram ? NSTextAlignmentLeft : NSTextAlignmentCenter;
        label.text = nodes[nodeID] ?: nodeID;
        [nodeCard addSubview:label];
    }

    self.scrollView.contentSize = self.canvasView.frame.size;
}

- (void)_renderSequenceForWidth:(CGFloat)renderWidth {
    NSArray<NSDictionary *> *participants = [self.parsedDiagram[@"participants"] isKindOfClass:[NSArray class]] ? self.parsedDiagram[@"participants"] : @[];
    NSArray<NSDictionary *> *messages = [self.parsedDiagram[@"messages"] isKindOfClass:[NSArray class]] ? self.parsedDiagram[@"messages"] : @[];
    if (participants.count == 0) {
        [self _renderFallbackForWidth:renderWidth];
        return;
    }

    CGFloat columnSpacing = 136.0;
    CGFloat leftInset = 60.0;
    CGFloat topInset = 18.0;
    CGFloat labelWidth = 110.0;
    CGFloat rowHeight = 42.0;
    CGFloat messageStartY = 70.0;
    CGFloat canvasWidth = MAX(renderWidth, leftInset * 2.0 + (participants.count - 1) * columnSpacing + labelWidth);
    CGFloat canvasHeight = MAX(140.0, messageStartY + messages.count * rowHeight + 28.0);
    self.canvasView.frame = CGRectMake(0, 0, canvasWidth, canvasHeight);

    NSMutableDictionary<NSString *, NSNumber *> *xPositions = [NSMutableDictionary new];
    for (NSUInteger idx = 0; idx < participants.count; idx++) {
        NSDictionary *participant = participants[idx];
        CGFloat centerX = leftInset + idx * columnSpacing;
        xPositions[participant[@"id"]] = @(centerX);

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(centerX - labelWidth * 0.5, topInset, labelWidth, 32.0)];
        label.font = [UIFont systemFontOfSize:11 weight:[participant[@"actor"] boolValue] ? UIFontWeightBold : UIFontWeightSemibold];
        label.textColor = [participant[@"actor"] boolValue] ? kVCAccentHover : kVCTextPrimary;
        label.textAlignment = NSTextAlignmentCenter;
        label.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
        label.layer.cornerRadius = 10.0;
        label.layer.borderWidth = 1.0;
        label.layer.borderColor = kVCBorder.CGColor;
        label.clipsToBounds = YES;
        label.text = participant[@"label"] ?: participant[@"id"];
        [self.canvasView addSubview:label];

        CAShapeLayer *lifeline = [CAShapeLayer layer];
        lifeline.strokeColor = [kVCBorderLight colorWithAlphaComponent:0.7].CGColor;
        lifeline.fillColor = UIColor.clearColor.CGColor;
        lifeline.lineWidth = 1.0;
        lifeline.lineDashPattern = @[@5, @4];
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(centerX, CGRectGetMaxY(label.frame) + 6.0)];
        [path addLineToPoint:CGPointMake(centerX, canvasHeight - 16.0)];
        lifeline.path = path.CGPath;
        [self.canvasView.layer addSublayer:lifeline];
    }

    CAShapeLayer *solidMessageLayer = [CAShapeLayer layer];
    solidMessageLayer.strokeColor = [kVCAccent colorWithAlphaComponent:0.62].CGColor;
    solidMessageLayer.fillColor = UIColor.clearColor.CGColor;
    solidMessageLayer.lineWidth = 1.35;
    UIBezierPath *solidMessagePath = [UIBezierPath bezierPath];

    CAShapeLayer *dashedMessageLayer = [CAShapeLayer layer];
    dashedMessageLayer.strokeColor = [kVCTextSecondary colorWithAlphaComponent:0.45].CGColor;
    dashedMessageLayer.fillColor = UIColor.clearColor.CGColor;
    dashedMessageLayer.lineWidth = 1.1;
    dashedMessageLayer.lineDashPattern = @[@4, @4];
    UIBezierPath *dashedMessagePath = [UIBezierPath bezierPath];

    CAShapeLayer *messageArrowHeadLayer = [CAShapeLayer layer];
    messageArrowHeadLayer.strokeColor = [kVCAccent colorWithAlphaComponent:0.62].CGColor;
    messageArrowHeadLayer.fillColor = UIColor.clearColor.CGColor;
    messageArrowHeadLayer.lineWidth = 1.25;
    UIBezierPath *messageArrowHeadPath = [UIBezierPath bezierPath];

    for (NSUInteger idx = 0; idx < messages.count; idx++) {
        NSDictionary *message = messages[idx];
        CGFloat y = messageStartY + idx * rowHeight;
        CGFloat fromX = [xPositions[message[@"from"]] doubleValue];
        CGFloat toX = [xPositions[message[@"to"]] doubleValue];
        if (fromX <= 0 || toX <= 0) continue;

        UIBezierPath *shaftPath = [message[@"dashed"] boolValue] ? dashedMessagePath : solidMessagePath;
        [shaftPath moveToPoint:CGPointMake(fromX, y)];
        [shaftPath addLineToPoint:CGPointMake(toX, y)];
        CGFloat arrowAngle = atan2(0.0, toX - fromX);
        CGPoint end = CGPointMake(toX, y);
        CGPoint headA = CGPointMake(end.x - cos(arrowAngle - M_PI / 6.0) * 7.0,
                                    end.y - sin(arrowAngle - M_PI / 6.0) * 7.0);
        CGPoint headB = CGPointMake(end.x - cos(arrowAngle + M_PI / 6.0) * 7.0,
                                    end.y - sin(arrowAngle + M_PI / 6.0) * 7.0);
        [messageArrowHeadPath moveToPoint:end];
        [messageArrowHeadPath addLineToPoint:headA];
        [messageArrowHeadPath moveToPoint:end];
        [messageArrowHeadPath addLineToPoint:headB];

        UILabel *messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        messageLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        messageLabel.textColor = kVCTextSecondary;
        messageLabel.backgroundColor = [kVCBgPrimary colorWithAlphaComponent:0.86];
        messageLabel.layer.cornerRadius = 8.0;
        messageLabel.clipsToBounds = YES;
        messageLabel.textAlignment = NSTextAlignmentCenter;
        messageLabel.text = [NSString stringWithFormat:@" %@ ", VCMermaidTrimmedString(message[@"label"])];
        [messageLabel sizeToFit];
        CGRect labelFrame = messageLabel.frame;
        labelFrame.size.width = MIN(MAX(labelFrame.size.width + 8.0, 44.0), 180.0);
        labelFrame.size.height = 18.0;
        labelFrame.origin.x = MIN(fromX, toX) + fabs(toX - fromX) * 0.5 - labelFrame.size.width * 0.5;
        labelFrame.origin.y = y - 24.0;
        messageLabel.frame = labelFrame;
        [self.canvasView addSubview:messageLabel];
    }

    solidMessageLayer.path = solidMessagePath.CGPath;
    dashedMessageLayer.path = dashedMessagePath.CGPath;
    messageArrowHeadLayer.path = messageArrowHeadPath.CGPath;
    if (!CGPathIsEmpty(solidMessageLayer.path)) {
        [self.canvasView.layer addSublayer:solidMessageLayer];
    }
    if (!CGPathIsEmpty(dashedMessageLayer.path)) {
        [self.canvasView.layer addSublayer:dashedMessageLayer];
    }
    if (!CGPathIsEmpty(messageArrowHeadLayer.path)) {
        [self.canvasView.layer addSublayer:messageArrowHeadLayer];
    }
    self.scrollView.contentSize = self.canvasView.frame.size;
}

@end
