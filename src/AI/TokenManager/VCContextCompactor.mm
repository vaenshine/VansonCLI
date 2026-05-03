/**
 * VCContextCompactor.mm -- 上下文压缩实现
 */

#import "VCContextCompactor.h"
#import "../Chat/VCMessage.h"
#import "../Models/VCProviderConfig.h"
#import "../Adapters/VCAIAdapter.h"
#import "../Adapters/VCOpenAIAdapter.h"
#import "../Adapters/VCAnthropicAdapter.h"
#import "../Adapters/VCGeminiAdapter.h"
#import "../../../VansonCLI.h"

static const NSUInteger kKeepRecent = 4;
static const NSUInteger kSummaryMaxLen = 4000;

static NSDictionary *VCFallbackArtifact(NSArray<VCMessage *> *oldMessages) {
    NSMutableArray<NSString *> *userMessages = [NSMutableArray new];
    NSMutableArray<NSString *> *assistantActions = [NSMutableArray new];

    for (VCMessage *message in oldMessages) {
        NSString *content = [[message.content ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
        if (content.length == 0) continue;
        if ([message.role isEqualToString:@"user"]) {
            [userMessages addObject:content];
        } else if ([message.role isEqualToString:@"assistant"]) {
            [assistantActions addObject:content];
        }
    }

    NSString *latestUser = userMessages.lastObject ?: @"No explicit user request was preserved.";
    NSString *currentWork = assistantActions.lastObject ?: @"Conversation history was compacted without a detailed assistant recap.";
    NSString *nextStep = latestUser.length ? [NSString stringWithFormat:@"Continue from the latest user goal: %@",
                                              latestUser.length > 120 ? [[latestUser substringToIndex:120] stringByAppendingString:@"..."] : latestUser]
                                          : @"Ask for the next concrete debugging step only if needed.";

    return @{
        @"primaryRequestAndIntent": latestUser,
        @"keyTechnicalConcepts": assistantActions.count ? @[assistantActions.lastObject] : @[],
        @"filesAndCodeSections": @[],
        @"errorsAndFixes": @[],
        @"problemSolving": assistantActions.count ? @[currentWork] : @[],
        @"allUserMessages": userMessages.count ? userMessages : @[@"No preserved user messages."],
        @"pendingTasks": @[@"Conversation was compacted. Reconstruct remaining work from the latest user goal and current runtime context."],
        @"currentWork": currentWork,
        @"nextAlignedStep": nextStep,
    };
}

@implementation VCContextCompactor

+ (void)compactMessages:(NSMutableArray<VCMessage *> *)messages
           withProvider:(VCProviderConfig *)provider
             completion:(void(^)(BOOL success, NSDictionary *artifact))completion {

    if (messages.count <= kKeepRecent) {
        if (completion) completion(NO, nil);
        return;
    }

    // Split: old messages to summarize, recent to keep
    NSUInteger splitIdx = messages.count - kKeepRecent;
    NSArray<VCMessage *> *oldMessages = [messages subarrayWithRange:NSMakeRange(0, splitIdx)];
    NSArray<VCMessage *> *recentMessages = [messages subarrayWithRange:NSMakeRange(splitIdx, kKeepRecent)];

    // Build summary text from old messages
    NSString *summaryText = [self messagesToSummaryText:oldMessages maxLength:kSummaryMaxLen];
    NSString *schema = @"{\"primaryRequestAndIntent\":\"\",\"keyTechnicalConcepts\":[],\"filesAndCodeSections\":[],\"errorsAndFixes\":[],\"problemSolving\":[],\"allUserMessages\":[],\"pendingTasks\":[],\"currentWork\":\"\",\"nextAlignedStep\":\"\"}";

    NSArray<NSDictionary *> *summaryMessages = @[
        @{@"role": @"system", @"content":
              @"You compress coding/debugging conversations into a structured continuation artifact. "
               "Return JSON only. Preserve user intent, actions already taken, current state, remaining work, and the most recent relevant user messages. "
               "Do not include markdown fences or commentary."},
        @{@"role": @"user", @"content": [NSString stringWithFormat:
            @"Build a continuation artifact for the following chat history. "
             "Use exactly this JSON shape and keep every field concise but useful:\n%@\n\n"
             "Rules:\n"
             "- `primaryRequestAndIntent`: one short paragraph\n"
             "- list fields: arrays of short strings\n"
             "- `allUserMessages`: preserve user asks and corrections worth keeping\n"
             "- `pendingTasks`: only unfinished work\n"
             "- `currentWork`: what has already been done and where things stand now\n"
             "- `nextAlignedStep`: the best next step that matches the user's direction\n\n"
             "Conversation:\n%@",
             schema, summaryText]}
    ];

    id<VCAIAdapter> adapter = [self _adapterForProtocol:provider.protocol];
    [adapter sendMessages:summaryMessages
               withConfig:provider
                streaming:NO
                  onChunk:nil
               onToolCall:nil
                  onUsage:nil
               completion:^(NSDictionary *response, NSError *error) {
        NSDictionary *artifact = nil;
        if (!error && [response[@"content"] isKindOfClass:[NSString class]]) {
            NSString *raw = [response[@"content"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([raw hasPrefix:@"```"]) {
                NSRange firstNewline = [raw rangeOfString:@"\n"];
                if (firstNewline.location != NSNotFound) {
                    raw = [raw substringFromIndex:firstNewline.location + 1];
                }
                NSRange fenceRange = [raw rangeOfString:@"```" options:NSBackwardsSearch];
                if (fenceRange.location != NSNotFound) {
                    raw = [raw substringToIndex:fenceRange.location];
                }
                raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
            NSData *jsonData = [raw dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *parsed = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
            if ([parsed isKindOfClass:[NSDictionary class]]) {
                artifact = parsed;
            }
        }
        if (![artifact isKindOfClass:[NSDictionary class]]) {
            artifact = VCFallbackArtifact(oldMessages);
            VCLog(@"ContextCompactor: AI summary failed, using fallback");
        }

        VCMessage *summaryMsg = [VCMessage messageWithRole:@"system"
            content:[NSString stringWithFormat:@"[Structured Session Summary]\n%@",
                     [self renderArtifact:artifact]]];

        [messages removeAllObjects];
        [messages addObject:summaryMsg];
        [messages addObjectsFromArray:recentMessages];

        VCLog(@"ContextCompactor: compacted %lu -> %lu messages",
            (unsigned long)(oldMessages.count + recentMessages.count),
            (unsigned long)messages.count);

        if (completion) completion(YES, artifact);
    }];
}

+ (BOOL)isTokenLimitError:(NSString *)errorMessage {
    if (!errorMessage) return NO;
    NSString *lower = errorMessage.lowercaseString;
    NSArray *keywords = @[
        @"maximum context length",
        @"token limit",
        @"max_tokens",
        @"context_length_exceeded",
        @"context window is full",
        @"too many tokens",
        @"request too large",
        @"content too large",
        @"input is too long",
        @"prompt is too long",
    ];
    for (NSString *kw in keywords) {
        if ([lower containsString:kw]) return YES;
    }
    return NO;
}

+ (NSString *)messagesToSummaryText:(NSArray<VCMessage *> *)messages
                          maxLength:(NSUInteger)maxLen {
    NSMutableString *text = [NSMutableString new];
    for (VCMessage *msg in messages) {
        [text appendFormat:@"[%@]: %@\n", msg.role, msg.content ?: @""];
        if (text.length > maxLen) {
            return [text substringToIndex:maxLen];
        }
    }
    return text;
}

+ (NSString *)renderArtifact:(NSDictionary *)artifact {
    if (![artifact isKindOfClass:[NSDictionary class]] || artifact.count == 0) {
        return @"No structured handoff was generated.";
    }

    NSArray<NSDictionary *> *sections = @[
        @{@"title": @"Intent", @"value": artifact[@"primaryRequestAndIntent"] ?: @""},
        @{@"title": @"Key Concepts", @"value": artifact[@"keyTechnicalConcepts"] ?: @[]},
        @{@"title": @"Files", @"value": artifact[@"filesAndCodeSections"] ?: @[]},
        @{@"title": @"Errors And Fixes", @"value": artifact[@"errorsAndFixes"] ?: @[]},
        @{@"title": @"Problem Solving", @"value": artifact[@"problemSolving"] ?: @[]},
        @{@"title": @"User Messages", @"value": artifact[@"allUserMessages"] ?: @[]},
        @{@"title": @"Pending Tasks", @"value": artifact[@"pendingTasks"] ?: @[]},
        @{@"title": @"Current Work", @"value": artifact[@"currentWork"] ?: @""},
        @{@"title": @"Next Step", @"value": artifact[@"nextAlignedStep"] ?: @""},
    ];

    NSMutableString *rendered = [NSMutableString new];
    for (NSDictionary *section in sections) {
        NSString *title = section[@"title"];
        id value = section[@"value"];
        [rendered appendFormat:@"%@:\n", title];
        if ([value isKindOfClass:[NSArray class]]) {
            NSArray *items = value;
            if (items.count == 0) {
                [rendered appendString:@"- none\n"];
            } else {
                for (id item in items) {
                    [rendered appendFormat:@"- %@\n", [item description]];
                }
            }
        } else {
            NSString *text = [[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            [rendered appendFormat:@"%@\n", text.length ? text : @"none"];
        }
        [rendered appendString:@"\n"];
    }
    return [rendered stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Private

+ (id<VCAIAdapter>)_adapterForProtocol:(VCAPIProtocol)protocol {
    switch (protocol) {
        case VCAPIProtocolOpenAI:
        case VCAPIProtocolOpenAIResponses:
            return [[VCOpenAIAdapter alloc] init];
        case VCAPIProtocolAnthropic:
            return [[VCAnthropicAdapter alloc] init];
        case VCAPIProtocolGemini:
            return [[VCGeminiAdapter alloc] init];
    }
    return [[VCOpenAIAdapter alloc] init];
}

@end
