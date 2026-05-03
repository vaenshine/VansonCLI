/**
 * VCMessage.mm -- 消息模型实现
 */

#import "VCMessage.h"
#import "../ToolCall/VCToolCallParser.h"

static NSString *VCMessageTrimmedString(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL VCMessageLooksLikeMermaidDiagram(NSString *content) {
    NSString *trimmed = VCMessageTrimmedString(content);
    NSString *lower = [trimmed lowercaseString];
    return [lower hasPrefix:@"sequencediagram"] ||
           [lower hasPrefix:@"flowchart"] ||
           [lower hasPrefix:@"graph "] ||
           [lower hasPrefix:@"classdiagram"] ||
           [lower hasPrefix:@"statediagram"];
}

static NSArray<NSDictionary *> *VCMessageInlineDiagramBlocks(NSString *content, NSString **cleanedContentOut) {
    NSString *source = [content isKindOfClass:[NSString class]] ? content : @"";
    NSMutableArray<NSDictionary *> *blocks = [NSMutableArray new];
    NSMutableString *cleaned = [source mutableCopy];

    NSRange searchRange = NSMakeRange(0, cleaned.length);
    while (searchRange.location < cleaned.length) {
        NSRange openRange = [cleaned rangeOfString:@"```mermaid" options:0 range:searchRange];
        if (openRange.location == NSNotFound) break;
        NSRange openNewline = [cleaned rangeOfString:@"\n" options:0 range:NSMakeRange(openRange.location, cleaned.length - openRange.location)];
        if (openNewline.location == NSNotFound) break;
        NSRange closeRange = [cleaned rangeOfString:@"```" options:0 range:NSMakeRange(openNewline.location + 1, cleaned.length - openNewline.location - 1)];
        if (closeRange.location == NSNotFound) break;

        NSRange fullBlockRange = NSMakeRange(openRange.location, closeRange.location + closeRange.length - openRange.location);
        NSString *blockContent = [cleaned substringWithRange:NSMakeRange(openNewline.location + 1, closeRange.location - openNewline.location - 1)];
        NSString *trimmedBlock = VCMessageTrimmedString(blockContent);
        if (trimmedBlock.length > 0) {
            [blocks addObject:@{
                @"type": @"diagram",
                @"title": @"Diagram in Response",
                @"summary": @"Rendered from assistant Mermaid output.",
                @"content": trimmedBlock,
                @"diagramType": @"content"
            }];
        }
        [cleaned replaceCharactersInRange:fullBlockRange withString:@""];
        NSUInteger nextLocation = openRange.location;
        if (nextLocation >= cleaned.length) break;
        searchRange = NSMakeRange(nextLocation, cleaned.length - nextLocation);
    }

    NSString *trimmedSource = VCMessageTrimmedString(source);
    if (blocks.count == 0 && VCMessageLooksLikeMermaidDiagram(trimmedSource)) {
        [blocks addObject:@{
            @"type": @"diagram",
            @"title": @"Diagram in Response",
            @"summary": @"Rendered from assistant Mermaid output.",
            @"content": trimmedSource,
            @"diagramType": @"content"
        }];
        cleaned = [NSMutableString new];
    }

    if (cleanedContentOut) {
        *cleanedContentOut = VCMessageTrimmedString(cleaned);
    }
    return [blocks copy];
}

static NSArray<NSDictionary *> *VCMessageDiagramReferenceBlocks(NSArray<NSDictionary *> *references) {
    NSMutableArray<NSDictionary *> *results = [NSMutableArray new];
    for (NSDictionary *reference in references ?: @[]) {
        NSDictionary *payload = [reference[@"payload"] isKindOfClass:[NSDictionary class]] ? reference[@"payload"] : nil;
        if (!payload || ![payload[@"type"] isEqual:@"mermaid"]) continue;

        NSString *path = VCMessageTrimmedString(payload[@"path"]);
        NSString *content = @"";
        if (path.length > 0) {
            NSError *readError = nil;
            NSString *fileContent = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
            if (!readError && fileContent.length > 0) {
                content = fileContent;
            }
        }
        if (content.length == 0) {
            content = VCMessageTrimmedString(payload[@"contentPreview"]);
        }
        if (content.length == 0) continue;

        [results addObject:@{
            @"type": @"diagram",
            @"title": VCMessageTrimmedString(reference[@"title"]).length > 0 ? VCMessageTrimmedString(reference[@"title"]) : @"Diagram",
            @"summary": VCMessageTrimmedString(payload[@"summary"]),
            @"content": content,
            @"diagramType": VCMessageTrimmedString(payload[@"diagramType"])
        }];
    }
    return [results copy];
}

static NSDictionary *VCMessageParsedStatusLead(NSString *role, NSString *content, NSString **bodyOut) {
    NSString *raw = [content isKindOfClass:[NSString class]] ? content : @"";
    NSString *body = raw;
    NSDictionary *status = nil;

    if ([raw hasPrefix:@"[Error]"]) {
        body = [[raw substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        status = @{
            @"type": @"status",
            @"tone": @"error",
            @"title": @"Error",
            @"content": body.length > 0 ? body : @"The assistant returned an error."
        };
        body = @"";
    } else if ([raw hasPrefix:@"[Recovered Draft]"]) {
        NSArray<NSString *> *parts = [raw componentsSeparatedByString:@"\n"];
        NSString *rest = parts.count > 1 ? [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"\n"] : @"";
        body = VCMessageTrimmedString(rest);
        status = @{
            @"type": @"status",
            @"tone": @"warning",
            @"title": @"Recovered Draft",
            @"content": @"Recovered from the last interrupted streaming response."
        };
    } else if ([role isEqualToString:@"system"]) {
        status = @{
            @"type": @"status",
            @"tone": @"info",
            @"title": @"Session Summary",
            @"content": @"Condensed context carried forward for the current chat."
        };
        body = VCMessageTrimmedString(raw);
    }

    if (bodyOut) *bodyOut = body ?: @"";
    return status;
}

static NSArray<NSDictionary *> *VCMessageReferenceBlocks(NSArray<NSDictionary *> *references) {
    NSMutableArray<NSDictionary *> *blocks = [NSMutableArray new];
    for (NSDictionary *reference in references ?: @[]) {
        NSDictionary *payload = [reference[@"payload"] isKindOfClass:[NSDictionary class]] ? reference[@"payload"] : nil;
        if ([payload[@"type"] isEqual:@"mermaid"]) continue;
        NSString *kind = [reference[@"kind"] isKindOfClass:[NSString class]] ? reference[@"kind"] : @"Ref";
        NSString *title = [reference[@"title"] isKindOfClass:[NSString class]] ? reference[@"title"] : @"Attached reference";
        [blocks addObject:@{
            @"type": @"reference",
            @"kind": kind,
            @"title": title,
            @"payload": payload ?: @{}
        }];
    }
    return [blocks copy];
}

static NSArray<NSDictionary *> *VCMessageToolBlocks(NSArray<VCToolCall *> *toolCalls) {
    NSMutableArray<NSDictionary *> *blocks = [NSMutableArray new];
    for (VCToolCall *toolCall in toolCalls ?: @[]) {
        if (![toolCall.toolID isKindOfClass:[NSString class]] || toolCall.toolID.length == 0) continue;
        [blocks addObject:@{
            @"type": @"tool_call",
            @"toolID": toolCall.toolID
        }];
    }
    return [blocks copy];
}

static NSArray<NSDictionary *> *VCMessageBuildBlocks(NSString *role,
                                                     NSString *content,
                                                     NSArray<NSDictionary *> *references,
                                                     NSArray<VCToolCall *> *toolCalls) {
    NSMutableArray<NSDictionary *> *blocks = [NSMutableArray new];
    [blocks addObjectsFromArray:VCMessageReferenceBlocks(references)];

    NSString *statusBody = nil;
    NSDictionary *statusBlock = VCMessageParsedStatusLead(role, content, &statusBody);
    if (statusBlock) {
        [blocks addObject:statusBlock];
    }

    NSString *cleanedBody = nil;
    NSArray<NSDictionary *> *inlineDiagrams = VCMessageInlineDiagramBlocks(statusBody ?: content, &cleanedBody);
    NSString *markdownBody = VCMessageTrimmedString(cleanedBody);
    if (markdownBody.length > 0) {
        [blocks addObject:@{
            @"type": @"markdown",
            @"content": markdownBody
        }];
    }

    NSMutableArray<NSDictionary *> *allDiagrams = [NSMutableArray new];
    NSMutableSet<NSString *> *seenContents = [NSMutableSet set];
    for (NSDictionary *diagram in VCMessageDiagramReferenceBlocks(references)) {
        NSString *key = VCMessageTrimmedString(diagram[@"content"]);
        if (key.length == 0 || [seenContents containsObject:key]) continue;
        [seenContents addObject:key];
        [allDiagrams addObject:diagram];
    }
    for (NSDictionary *diagram in inlineDiagrams) {
        NSString *key = VCMessageTrimmedString(diagram[@"content"]);
        if (key.length == 0 || [seenContents containsObject:key]) continue;
        [seenContents addObject:key];
        [allDiagrams addObject:diagram];
    }
    [blocks addObjectsFromArray:allDiagrams];
    [blocks addObjectsFromArray:VCMessageToolBlocks(toolCalls)];

    if (blocks.count == 0) {
        [blocks addObject:@{
            @"type": @"markdown",
            @"content": VCMessageTrimmedString(content)
        }];
    }

    return [blocks copy];
}

@implementation VCMessage {
    BOOL _usesExplicitBlocks;
}

+ (instancetype)messageWithRole:(NSString *)role content:(NSString *)content {
    VCMessage *msg = [[VCMessage alloc] init];
    msg.messageID = [[NSUUID UUID] UUIDString];
    msg.timestamp = [NSDate date];
    msg.isEdited = NO;
    msg.role = role;
    msg.content = content;
    return msg;
}

- (void)setRole:(NSString *)role {
    _role = [role copy];
    [self _refreshBlocksIfNeeded];
}

- (void)setContent:(NSString *)content {
    _content = [content copy];
    [self _refreshBlocksIfNeeded];
}

- (void)setToolCalls:(NSArray<VCToolCall *> *)toolCalls {
    _toolCalls = [toolCalls copy];
    [self _refreshBlocksIfNeeded];
}

- (void)setReferences:(NSArray<NSDictionary *> *)references {
    _references = [references copy];
    [self _refreshBlocksIfNeeded];
}

- (void)setBlocks:(NSArray<NSDictionary *> *)blocks {
    _blocks = [blocks copy];
    _usesExplicitBlocks = (_blocks.count > 0);
}

- (void)_refreshBlocksIfNeeded {
    if (_usesExplicitBlocks) return;
    _blocks = VCMessageBuildBlocks(_role, _content, _references, _toolCalls);
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_messageID forKey:@"messageID"];
    [coder encodeObject:_role forKey:@"role"];
    [coder encodeObject:_content forKey:@"content"];
    [coder encodeObject:_toolCalls forKey:@"toolCalls"];
    [coder encodeObject:_references forKey:@"references"];
    [coder encodeObject:_blocks forKey:@"blocks"];
    [coder encodeObject:_timestamp forKey:@"timestamp"];
    [coder encodeBool:_isEdited forKey:@"isEdited"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _messageID = [coder decodeObjectForKey:@"messageID"];
        _role = [[coder decodeObjectForKey:@"role"] copy];
        _content = [[coder decodeObjectForKey:@"content"] copy];
        _toolCalls = [[coder decodeObjectForKey:@"toolCalls"] copy];
        _references = [[coder decodeObjectForKey:@"references"] copy];
        _blocks = [[coder decodeObjectForKey:@"blocks"] copy];
        _timestamp = [coder decodeObjectForKey:@"timestamp"];
        _isEdited = [coder decodeBoolForKey:@"isEdited"];
        _usesExplicitBlocks = (_blocks.count > 0);
        if (_blocks.count == 0) {
            [self _refreshBlocksIfNeeded];
        }
    }
    return self;
}

#pragma mark - Serialization

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary new];
    dict[@"messageID"] = _messageID ?: @"";
    dict[@"role"] = _role ?: @"";
    dict[@"content"] = _content ?: @"";
    dict[@"timestamp"] = _timestamp ? @([_timestamp timeIntervalSince1970]) : @(0);
    dict[@"isEdited"] = @(_isEdited);
    dict[@"blocks"] = _blocks ?: @[];
    if (_references.count) dict[@"references"] = _references;
    if (_toolCalls.count) {
        NSMutableArray *tcArr = [NSMutableArray new];
        for (VCToolCall *tc in _toolCalls) {
            [tcArr addObject:[tc toDictionary]];
        }
        dict[@"toolCalls"] = tcArr;
    }
    return dict;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    VCMessage *msg = [[VCMessage alloc] init];
    msg.messageID = dict[@"messageID"] ?: [[NSUUID UUID] UUIDString];
    NSNumber *ts = dict[@"timestamp"];
    msg.timestamp = ts ? [NSDate dateWithTimeIntervalSince1970:ts.doubleValue] : [NSDate date];
    msg.isEdited = [dict[@"isEdited"] boolValue];
    msg.role = dict[@"role"] ?: @"user";
    msg.content = dict[@"content"] ?: @"";
    if ([dict[@"references"] isKindOfClass:[NSArray class]]) {
        msg.references = dict[@"references"];
    }
    NSArray *tcArr = dict[@"toolCalls"];
    if ([tcArr isKindOfClass:[NSArray class]] && tcArr.count > 0) {
        NSMutableArray *tcs = [NSMutableArray new];
        for (NSDictionary *tcDict in tcArr) {
            VCToolCall *tc = [VCToolCall fromDictionary:tcDict];
            if (tc) [tcs addObject:tc];
        }
        msg.toolCalls = tcs;
    }
    if ([dict[@"blocks"] isKindOfClass:[NSArray class]] && [dict[@"blocks"] count] > 0) {
        msg.blocks = dict[@"blocks"];
    }
    return msg;
}

#pragma mark - API Format

- (NSDictionary *)toAPIFormat {
    NSMutableString *apiContent = [NSMutableString stringWithString:_content ?: @""];
    if (_references.count > 0) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:_references options:NSJSONWritingPrettyPrinted error:nil];
        NSString *referencesText = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : _references.description;
        [apiContent appendFormat:@"\n\n[Attached References]\n%@", referencesText ?: @"[]"];
    }
    return @{@"role": _role ?: @"user", @"content": apiContent ?: @""};
}

- (NSArray<NSDictionary *> *)resolvedBlocks {
    return _blocks ?: @[];
}

@end
