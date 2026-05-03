/**
 * VCMemoryManager.mm -- Durable chat memory store
 */

#import "VCMemoryManager.h"
#import "../ToolCall/VCToolCallParser.h"
#import "../../Core/VCConfig.h"
#import "../../../VansonCLI.h"

static NSString *const kVCMemoryFileName = @"chat_memory.json";

static BOOL VCTextContainsCJK(NSString *text) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    for (NSUInteger idx = 0; idx < text.length; idx++) {
        unichar ch = [text characterAtIndex:idx];
        if ((ch >= 0x4E00 && ch <= 0x9FFF) || (ch >= 0x3400 && ch <= 0x4DBF)) {
            return YES;
        }
    }
    return NO;
}

@implementation VCMemoryManager {
    NSMutableArray<NSMutableDictionary *> *_memories;
}

+ (instancetype)shared {
    static VCMemoryManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCMemoryManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _memories = [NSMutableArray new];
        [self _load];
        [self ingestProjectContext];
    }
    return self;
}

- (NSArray<NSDictionary *> *)allMemories {
    @synchronized (self) {
        return [[NSArray alloc] initWithArray:_memories copyItems:YES];
    }
}

- (void)ingestUserText:(NSString *)text {
    NSString *trimmed = [[text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (trimmed.length == 0) return;

    NSString *lower = trimmed.lowercaseString;
    if (VCTextContainsCJK(trimmed)) {
        [self _upsertMemoryWithKind:@"user"
                                key:@"preferred_language"
                              title:@"Preferred language"
                            content:@"Respond in Chinese unless the user clearly switches language."
                             source:@"heuristic"];
    } else if ([lower rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location != NSNotFound) {
        [self _upsertMemoryWithKind:@"user"
                                key:@"preferred_language"
                              title:@"Preferred language"
                            content:@"Respond in English unless the user clearly switches language."
                             source:@"heuristic"];
    }

    NSArray<NSString *> *directExecutionPatterns = @[
        @"不需要问我", @"不要问我", @"不用问我", @"直接做", @"不用确认", @"直接改",
        @"don't ask", @"dont ask", @"just do it", @"no need to ask", @"no need to confirm"
    ];
    for (NSString *pattern in directExecutionPatterns) {
        if ([lower containsString:pattern]) {
            [self _upsertMemoryWithKind:@"feedback"
                                    key:@"execution_style"
                                  title:@"Execution style"
                                content:@"Act directly when the risk is obvious and local. Only pause for hidden tradeoffs or destructive changes."
                                 source:@"user"];
            break;
        }
    }

    NSArray<NSString *> *concisePatterns = @[@"简洁", @"简短", @"别啰嗦", @"concise", @"brief", @"short answer"];
    for (NSString *pattern in concisePatterns) {
        if ([lower containsString:pattern]) {
            [self _upsertMemoryWithKind:@"feedback"
                                    key:@"response_style"
                                  title:@"Response style"
                                content:@"Prefer concise, high-signal responses unless the user asks for depth."
                                 source:@"user"];
            break;
        }
    }

    [self recordReferenceFromText:trimmed];
}

- (void)ingestProjectContext {
    VCConfig *config = [VCConfig shared];
    if (config.targetBundleID.length) {
        [self _upsertMemoryWithKind:@"project"
                                key:@"target_bundle"
                              title:@"Target bundle"
                            content:[NSString stringWithFormat:@"Current target bundle is %@.", config.targetBundleID]
                             source:@"runtime"];
    }
    if (config.targetVersion.length) {
        [self _upsertMemoryWithKind:@"project"
                                key:@"target_version"
                              title:@"Target version"
                            content:[NSString stringWithFormat:@"Current target version is %@.", config.targetVersion]
                             source:@"runtime"];
    }
    if (config.vcVersion.length) {
        [self _upsertMemoryWithKind:@"project"
                                key:@"vansoncli_version"
                              title:@"VansonCLI version"
                            content:[NSString stringWithFormat:@"Current VansonCLI build is %@.", config.vcVersion]
                             source:@"runtime"];
    }
}

- (void)recordReferenceFromText:(NSString *)text {
    if (text.length == 0) return;

    NSError *error = nil;
    NSRegularExpression *urlRegex = [NSRegularExpression regularExpressionWithPattern:@"https?://\\S+" options:0 error:&error];
    if (!error) {
        NSArray<NSTextCheckingResult *> *matches = [urlRegex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
        for (NSTextCheckingResult *match in matches) {
            NSString *url = [text substringWithRange:match.range];
            NSString *key = [NSString stringWithFormat:@"url:%@", url];
            [self _upsertMemoryWithKind:@"reference" key:key title:@"External reference" content:url source:@"user"];
        }
    }

    NSRegularExpression *pathRegex = [NSRegularExpression regularExpressionWithPattern:@"/Users/[^\\s\\]\\)\\\">]+" options:0 error:&error];
    if (!error) {
        NSArray<NSTextCheckingResult *> *matches = [pathRegex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
        for (NSTextCheckingResult *match in matches) {
            NSString *path = [text substringWithRange:match.range];
            NSString *key = [NSString stringWithFormat:@"path:%@", path];
            [self _upsertMemoryWithKind:@"reference" key:key title:@"Workspace reference" content:path source:@"user"];
        }
    }
}

- (NSDictionary *)promptPayload {
    NSMutableDictionary *grouped = [NSMutableDictionary dictionaryWithDictionary:@{
        @"user": [NSMutableArray new],
        @"feedback": [NSMutableArray new],
        @"project": [NSMutableArray new],
        @"reference": [NSMutableArray new],
    }];

    NSArray<NSDictionary *> *sorted = [[self allMemories] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSTimeInterval ta = [a[@"updatedAt"] doubleValue];
        NSTimeInterval tb = [b[@"updatedAt"] doubleValue];
        if (ta == tb) return NSOrderedSame;
        return ta > tb ? NSOrderedAscending : NSOrderedDescending;
    }];

    for (NSDictionary *memory in sorted) {
        NSString *kind = memory[@"kind"] ?: @"reference";
        NSMutableArray *bucket = grouped[kind];
        if (![bucket isKindOfClass:[NSMutableArray class]]) continue;
        if (bucket.count >= 5) continue;
        [bucket addObject:@{
            @"title": memory[@"title"] ?: @"",
            @"content": memory[@"content"] ?: @"",
            @"source": memory[@"source"] ?: @"",
        }];
    }

    NSUInteger totalCount = 0;
    for (NSString *kind in grouped.allKeys) {
        totalCount += [grouped[kind] count];
    }
    return @{
        @"totalCount": @(totalCount),
        @"memory": grouped,
    };
}

- (void)save {
    [self _save];
}

#pragma mark - Private

- (NSString *)_memoryPath {
    return [[VCConfig shared].configPath stringByAppendingPathComponent:kVCMemoryFileName];
}

- (void)_upsertMemoryWithKind:(NSString *)kind
                          key:(NSString *)key
                        title:(NSString *)title
                      content:(NSString *)content
                       source:(NSString *)source {
    if (kind.length == 0 || key.length == 0 || content.length == 0) return;
    @synchronized (self) {
        NSMutableDictionary *found = nil;
        for (NSMutableDictionary *memory in _memories) {
            if ([memory[@"kind"] isEqualToString:kind] && [memory[@"key"] isEqualToString:key]) {
                found = memory;
                break;
            }
        }
        if (!found) {
            found = [NSMutableDictionary new];
            found[@"kind"] = kind;
            found[@"key"] = key;
            [_memories addObject:found];
        }
        found[@"title"] = title ?: @"";
        found[@"content"] = content ?: @"";
        found[@"source"] = source ?: @"";
        found[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);
    }
    [self _save];
}

- (void)_load {
    NSData *data = [NSData dataWithContentsOfFile:[self _memoryPath]];
    if (!data.length) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if ([json isKindOfClass:[NSArray class]]) {
        _memories = [json mutableCopy];
    }
}

- (void)_save {
    @synchronized (self) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:_memories options:NSJSONWritingPrettyPrinted error:nil];
        if (data) {
            [data writeToFile:[self _memoryPath] atomically:YES];
        }
    }
}

@end
