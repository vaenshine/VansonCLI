/**
 * VCAIEngine.mm -- AI 对话引擎实现
 */

#import "VCAIEngine.h"
#import "VCChatDiagnostics.h"
#import "VCMessage.h"
#import "VCChatSession.h"
#import "VCAutoSave.h"
#import "../../../VansonCLI.h"
#import "../Models/VCProviderConfig.h"
#import "../Models/VCProviderManager.h"
#import "../Adapters/VCAIAdapter.h"
#import "../Adapters/VCOpenAIAdapter.h"
#import "../Adapters/VCAnthropicAdapter.h"
#import "../Adapters/VCGeminiAdapter.h"
#import "../TokenManager/VCTokenTracker.h"
#import "../TokenManager/VCContextCompactor.h"
#import "../Memory/VCMemoryManager.h"
#import "../Security/VCPromptLeakGuard.h"
#import "../ToolCall/VCToolCallParser.h"
#import "../ToolCall/VCToolSchemaRegistry.h"
#import "../ToolCall/VCAIReadOnlyToolExecutor.h"
#import "../../UI/Chat/VCToolCallBlock.h"
#import "../Context/VCContextCollector.h"
#import "../Prompts/VCPromptManager.h"

static id VCAINormalizedToolValue(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *normalized = [NSMutableDictionary new];
        NSArray *keys = [[(NSDictionary *)value allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [[a description] compare:[b description]];
        }];
        for (id key in keys) {
            normalized[[key description]] = VCAINormalizedToolValue([(NSDictionary *)value objectForKey:key]) ?: [NSNull null];
        }
        return [normalized copy];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *items = [NSMutableArray new];
        for (id item in (NSArray *)value) {
            [items addObject:VCAINormalizedToolValue(item) ?: [NSNull null]];
        }
        return [items copy];
    }
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSNull class]]) {
        return value;
    }
    return [[value description] copy] ?: @"";
}

static NSString *VCAIToolCallSignature(VCToolCall *toolCall) {
    id normalizedParams = VCAINormalizedToolValue(toolCall.params ?: @{});
    NSData *data = [NSJSONSerialization dataWithJSONObject:normalizedParams ?: @{}
                                                   options:0
                                                     error:nil];
    NSString *params = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
    return [NSString stringWithFormat:@"%ld|%@|%@",
            (long)toolCall.type,
            toolCall.title ?: @"",
            params ?: @"{}"];
}

static NSData *VCAIJSONObjectData(id object) {
    if (![NSJSONSerialization isValidJSONObject:object]) return nil;
    return [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
}

static NSString *VCAIJSONString(id object) {
    NSData *data = VCAIJSONObjectData(object);
    if (!data) return @"{}";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

static NSDictionary *VCAIManualToolResult(VCToolCall *toolCall) {
    NSMutableDictionary *payload = [NSMutableDictionary new];
    if (toolCall.params) [payload addEntriesFromDictionary:toolCall.params];
    if (toolCall.resultMessage.length > 0) payload[@"resultMessage"] = toolCall.resultMessage;
    if (toolCall.verificationMessage.length > 0) payload[@"verificationMessage"] = toolCall.verificationMessage;
    payload[@"executed"] = @(toolCall.executed);
    payload[@"verificationStatus"] = @(toolCall.verificationStatus);

    return @{
        @"tool": toolCall.title ?: @"tool",
        @"success": @(toolCall.success),
        @"summary": toolCall.resultMessage ?: @"",
        @"payload": payload
    };
}

static NSString *VCAIManualToolResultsMessage(NSArray<NSDictionary *> *results) {
    return [NSString stringWithFormat:
            @"[Manual Tool Results]\n%@\nThese mutation tools already ran in the app. Use payload values such as insertedAddress as current runtime state. If the user requested a dependent next operation, call the next tool now. Otherwise provide a concise final answer.",
            VCAIJSONString(results ?: @[])];
}

static NSString *VCAIManualToolCompletionText(NSArray<NSDictionary *> *results) {
    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    for (NSDictionary *result in results ?: @[]) {
        NSString *tool = [result[@"tool"] isKindOfClass:[NSString class]] ? result[@"tool"] : @"tool";
        NSString *summary = [result[@"summary"] isKindOfClass:[NSString class]] ? result[@"summary"] : @"";
        if (summary.length > 0) {
            [parts addObject:[NSString stringWithFormat:@"%@: %@", tool, summary]];
        } else {
            BOOL success = [result[@"success"] respondsToSelector:@selector(boolValue)] ? [result[@"success"] boolValue] : NO;
            [parts addObject:[NSString stringWithFormat:@"%@: %@", tool, success ? @"completed" : @"failed"]];
        }
    }
    if (parts.count == 0) return @"已完成。";
    return [NSString stringWithFormat:@"已完成：%@", [parts componentsJoinedByString:@"；"]];
}

static NSString *VCAIStringFromMessageContent(id content) {
    if ([content isKindOfClass:[NSString class]]) return content;
    if (![content isKindOfClass:[NSArray class]]) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    for (id item in (NSArray *)content) {
        if ([item isKindOfClass:[NSString class]]) {
            [parts addObject:item];
        } else if ([item isKindOfClass:[NSDictionary class]]) {
            NSString *text = [(NSDictionary *)item objectForKey:@"text"];
            if ([text isKindOfClass:[NSString class]] && text.length > 0) {
                [parts addObject:text];
            }
        }
    }
    return [parts componentsJoinedByString:@"\n"];
}

static NSString *VCAIExtractPromptValue(NSString *text, NSArray<NSString *> *keys) {
    if (text.length == 0 || keys.count == 0) return @"";
    for (NSString *key in keys) {
        NSString *escaped = [NSRegularExpression escapedPatternForString:key];
        NSString *pattern = [NSString stringWithFormat:@"(?i)\\b%@\\b\\s*(?:[:=]|is|to|为|设为|改成)?\\s*[\\\"']?([^\\s,;，。}\\]]+)", escaped];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (match.numberOfRanges > 1) {
            NSString *value = [text substringWithRange:[match rangeAtIndex:1]];
            value = [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'` "]];
            if (value.length > 0) return value;
        }
    }
    return @"";
}

@implementation VCAIEngine {
    id<VCAIAdapter> _currentAdapter;
    BOOL _isGenerating;
}

+ (instancetype)shared {
    static VCAIEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCAIEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _isGenerating = NO;
        // Start auto-save
        [[VCAutoSave shared] start];
    }
    return self;
}

- (BOOL)isGenerating {
    return _isGenerating;
}

#pragma mark - Core API

- (void)sendMessage:(NSString *)text
        withContext:(NSDictionary *)context
          streaming:(BOOL)streaming
            onChunk:(void(^)(NSString *))onChunk
         onToolCall:(void(^)(VCToolCall *))onToolCall
         completion:(void(^)(VCMessage *, NSError *))completion {

    if (_isGenerating) {
        if (completion) completion(nil, [NSError errorWithDomain:@"VCAIEngine" code:-1
            userInfo:@{NSLocalizedDescriptionKey: @"Already generating"}]);
        return;
    }

    NSString *blockedResponse = [VCPromptLeakGuard blockedLocalResponseForUserText:text];
    if (blockedResponse.length > 0) {
        VCChatSession *session = [VCChatSession shared];
        VCMessage *userMsg = [VCMessage messageWithRole:@"user" content:text];
        NSArray *manualReferences = [context[@"manualReferences"] isKindOfClass:[NSArray class]] ? context[@"manualReferences"] : nil;
        if (manualReferences.count > 0) {
            userMsg.references = manualReferences;
        }
        [session addMessage:userMsg];

        VCMessage *assistantMsg = [VCMessage messageWithRole:@"assistant" content:blockedResponse];
        [session addMessage:assistantMsg];
        [session saveAll];
        [[VCMemoryManager shared] ingestUserText:text];
        [[VCMemoryManager shared] save];
        if (completion) completion(assistantMsg, nil);
        return;
    }

    VCProviderConfig *provider = [[VCProviderManager shared] activeProvider];
    if (!provider || !provider.apiKey.length) {
        if (completion) completion(nil, [NSError errorWithDomain:@"VCAIEngine" code:-2
            userInfo:@{NSLocalizedDescriptionKey: @"No API key configured"}]);
        return;
    }
    NSString *effectiveModel = [[VCProviderManager shared] effectiveSelectedModelForProvider:provider];
    if (effectiveModel.length == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"VCAIEngine" code:-3
            userInfo:@{NSLocalizedDescriptionKey: @"No model selected for the active provider"}]);
        return;
    }
    VCProviderConfig *requestProvider = [provider copy];
    requestProvider.selectedModel = effectiveModel;
    provider = requestProvider;

    _isGenerating = YES;

    VCChatSession *session = [VCChatSession shared];
    VCMessage *userMsg = [VCMessage messageWithRole:@"user" content:text];
    NSArray *manualReferences = [context[@"manualReferences"] isKindOfClass:[NSArray class]] ? context[@"manualReferences"] : nil;
    if (manualReferences.count > 0) {
        userMsg.references = manualReferences;
    }
    [session addMessage:userMsg];
    NSDictionary *workspace = [context[@"workspace"] isKindOfClass:[NSDictionary class]] ? context[@"workspace"] : @{};
    NSUInteger workspaceSignalCount = 0;
    for (NSString *key in @[@"inspect", @"network", @"ui", @"patches", @"console"]) {
        id payload = workspace[key];
        BOOL hasSignal = NO;
        if ([payload isKindOfClass:[NSDictionary class]]) {
            hasSignal = [(NSDictionary *)payload count] > 0;
        } else if ([payload isKindOfClass:[NSArray class]]) {
            hasSignal = [(NSArray *)payload count] > 0;
        } else if (payload) {
            hasSignal = YES;
        }
        if (hasSignal) workspaceSignalCount += 1;
    }
    NSDictionary *contextSummary = @{
        @"manualReferenceCount": @(manualReferences.count),
        @"workspaceSignalCount": @(workspaceSignalCount),
        @"toolSchemaCount": @([VCToolSchemaRegistry toolSchemasForRuntimeCapabilities:context[@"runtimeCapabilities"]].count)
    };
    NSString *requestID = [[VCChatDiagnostics shared] beginRequestForSessionID:session.currentSessionID
                                                                  messageCount:session.currentMessages.count
                                                                contextSummary:contextSummary];
    [session saveAll];
    [[VCMemoryManager shared] ingestUserText:text];
    [[VCMemoryManager shared] ingestProjectContext];

    NSMutableArray<NSDictionary *> *apiMessages = [self _buildAPIMessages:context
                                                                 messages:session.currentMessages];
    NSArray<NSDictionary *> *tools = [VCToolSchemaRegistry toolSchemasForRuntimeCapabilities:context[@"runtimeCapabilities"]];
    [[VCChatDiagnostics shared] recordEventWithPhase:@"request"
                                            subphase:@"prepared_messages"
                                           sessionID:session.currentSessionID
                                           requestID:requestID
                                          durationMS:0.0
                                               extra:@{
                                                   @"apiMessageCount": @(apiMessages.count),
                                                   @"toolSchemaCount": @(tools.count)
                                               }];

    [[VCTokenTracker shared] updateForModel:effectiveModel];

    if ([[VCTokenTracker shared] shouldCompactWithMessageCount:session.currentMessages.count]) {
        NSMutableArray<VCMessage *> *msgs = [session.currentMessages mutableCopy];
        [VCContextCompactor compactMessages:msgs withProvider:provider completion:^(BOOL success, NSDictionary *artifact) {
            if (success) {
                [session replaceCurrentMessages:msgs];
                [session updateCurrentContinuationArtifact:artifact];
                [[VCChatDiagnostics shared] recordEventWithPhase:@"request"
                                                        subphase:@"context_compacted"
                                                       sessionID:session.currentSessionID
                                                       requestID:requestID
                                                      durationMS:0.0
                                                           extra:@{
                                                               @"messageCount": @(session.currentMessages.count)
                                                           }];
            }
            NSMutableArray<NSDictionary *> *compactedMessages = [self _buildAPIMessages:context
                                                                                 messages:session.currentMessages];
            [self _sendToAPI:compactedMessages provider:provider tools:tools streaming:streaming
                     onChunk:onChunk onToolCall:onToolCall completion:completion];
        }];
    } else {
        [self _sendToAPI:apiMessages provider:provider tools:tools streaming:streaming
                 onChunk:onChunk onToolCall:onToolCall completion:completion];
    }
}

- (void)_sendToAPI:(NSArray<NSDictionary *> *)apiMessages
          provider:(VCProviderConfig *)provider
             tools:(NSArray<NSDictionary *> *)tools
         streaming:(BOOL)streaming
           onChunk:(void(^)(NSString *))onChunk
        onToolCall:(void(^)(VCToolCall *))onToolCall
        completion:(void(^)(VCMessage *, NSError *))completion {

    [self _sendConversationStep:apiMessages
                       provider:provider
                          tools:tools
                      streaming:streaming
                        onChunk:onChunk
                     onToolCall:onToolCall
            accumulatedReferences:[NSMutableArray new]
          accumulatedToolResults:[NSMutableArray new]
          accumulatedManualToolCalls:[NSMutableArray new]
            seenAutoToolSignatures:[NSMutableSet new]
              duplicateNudgeUsed:NO
          manualContinuationUsed:NO
             remainingAutoSteps:8
                     completion:completion];
}

- (void)_sendConversationStep:(NSArray<NSDictionary *> *)apiMessages
                     provider:(VCProviderConfig *)provider
                        tools:(NSArray<NSDictionary *> *)tools
                    streaming:(BOOL)streaming
                      onChunk:(void(^)(NSString *))onChunk
                   onToolCall:(void(^)(VCToolCall *))onToolCall
          accumulatedReferences:(NSMutableArray<NSDictionary *> *)accumulatedReferences
         accumulatedToolResults:(NSMutableArray<NSDictionary *> *)accumulatedToolResults
      accumulatedManualToolCalls:(NSMutableArray<VCToolCall *> *)accumulatedManualToolCalls
          seenAutoToolSignatures:(NSMutableSet<NSString *> *)seenAutoToolSignatures
              duplicateNudgeUsed:(BOOL)duplicateNudgeUsed
            manualContinuationUsed:(BOOL)manualContinuationUsed
           remainingAutoSteps:(NSUInteger)remainingAutoSteps
                   completion:(void(^)(VCMessage *, NSError *))completion {

    _currentAdapter = [self _adapterForProtocol:provider.protocol];
    __block NSMutableString *streamAccumulator = [NSMutableString new];
    __block NSUInteger streamedVisibleLength = 0;
    __block BOOL streamingLeakTriggered = NO;
    const NSUInteger streamingSafetyBuffer = 96;

    void (^safeChunkHandler)(NSString *) = ^(NSString *text) {
        if (!onChunk || streamingLeakTriggered) return;
        NSString *chunk = [text isKindOfClass:[NSString class]] ? text : @"";
        if (chunk.length == 0) return;

        [streamAccumulator appendString:chunk];
        BOOL didSanitize = NO;
        NSString *sanitized = [VCPromptLeakGuard sanitizedAssistantText:streamAccumulator didSanitize:&didSanitize];
        if (didSanitize) {
            streamingLeakTriggered = YES;
            if (streamedVisibleLength == 0) {
                onChunk(sanitized);
                streamedVisibleLength = sanitized.length;
            }
            return;
        }

        if (streamAccumulator.length <= streamingSafetyBuffer) {
            return;
        }

        NSUInteger safeVisibleLength = streamAccumulator.length - streamingSafetyBuffer;
        if (safeVisibleLength <= streamedVisibleLength) return;
        NSString *visiblePrefix = [streamAccumulator substringToIndex:safeVisibleLength];
        NSString *delta = [visiblePrefix substringFromIndex:streamedVisibleLength];
        if (delta.length > 0) {
            onChunk(delta);
            streamedVisibleLength = safeVisibleLength;
            [[VCChatDiagnostics shared] noteChunkWithSize:delta.length totalLength:streamedVisibleLength];
        }
    };

    void (^usageHandler)(NSUInteger, NSUInteger) = ^(NSUInteger inputTokens, NSUInteger outputTokens) {
        [[VCTokenTracker shared] addUsage:inputTokens output:outputTokens];
    };

    vc_weakify(self);
    void (^completionHandler)(NSDictionary *, NSError *) = ^(NSDictionary *fullResponse, NSError *error) {
        vc_strongify(self);
        if (error) {
            self->_isGenerating = NO;
            if ([VCContextCompactor isTokenLimitError:error.localizedDescription]) {
                VCLog(@"AIEngine: token limit hit, triggering compaction");
            }
            [[VCChatDiagnostics shared] finishActiveRequestWithError:error totalLength:streamedVisibleLength];
            if (completion) completion(nil, error);
            return;
        }

        BOOL didSanitize = NO;
        NSString *content = [VCPromptLeakGuard sanitizedAssistantText:(fullResponse[@"content"] ?: @"")
                                                          didSanitize:&didSanitize];
        NSArray<VCToolCall *> *toolCalls = didSanitize ? @[] : [VCToolCallParser parseToolCalls:fullResponse
                                                                                            text:content
                                                                                        protocol:provider.protocol];
        NSArray<VCToolCall *> *autoToolCalls = [VCAIReadOnlyToolExecutor readOnlyToolCallsFromArray:toolCalls];
        NSArray<VCToolCall *> *manualToolCalls = [VCAIReadOnlyToolExecutor manualToolCallsFromArray:toolCalls];

        if (autoToolCalls.count > 0 && remainingAutoSteps > 0) {
            NSMutableArray<VCToolCall *> *newAutoToolCalls = [NSMutableArray new];
            for (VCToolCall *toolCall in autoToolCalls) {
                NSString *signature = VCAIToolCallSignature(toolCall);
                if ([seenAutoToolSignatures containsObject:signature]) continue;
                [seenAutoToolSignatures addObject:signature];
                [newAutoToolCalls addObject:toolCall];
            }

            if (newAutoToolCalls.count == 0) {
                VCToolCall *followUpMutation = [self _activeScanMutationToolCallFromMessages:apiMessages
                                                                                  toolResults:accumulatedToolResults];
                if ([self _finishWithLocalMutationToolCall:followUpMutation
                                     accumulatedReferences:accumulatedReferences
                                                onToolCall:onToolCall
                                                completion:completion]) {
                    return;
                }
                if (!duplicateNudgeUsed) {
                    NSMutableArray<NSDictionary *> *nextMessages = [apiMessages mutableCopy];
                    if (content.length > 0) {
                        [nextMessages addObject:@{@"role": @"assistant", @"content": content}];
                    }
                    [nextMessages addObject:@{
                        @"role": @"system",
                        @"content": @"[Auto Tool Results]\nThe requested read-only tool call duplicated an earlier call in this turn, so it was skipped. Use the prior tool results already provided as ground truth. If the user asked for a mutation based on those results, call the mutation tool now. Otherwise provide the final answer without more duplicate read-only tool calls."
                    }];
                    [self _sendConversationStep:nextMessages
                                       provider:provider
                                          tools:tools
                                      streaming:streaming
                                        onChunk:onChunk
                            onToolCall:onToolCall
                    accumulatedReferences:accumulatedReferences
                  accumulatedToolResults:accumulatedToolResults
             accumulatedManualToolCalls:accumulatedManualToolCalls
                   seenAutoToolSignatures:seenAutoToolSignatures
                              duplicateNudgeUsed:YES
                            manualContinuationUsed:manualContinuationUsed
                             remainingAutoSteps:remainingAutoSteps - 1
                                     completion:completion];
                    return;
                } else {
                    content = content.length > 0 ? content : [self _fallbackContentForAutoToolResults:accumulatedToolResults
                                                                                              repeated:YES];
                    autoToolCalls = @[];
                }
            } else {
            CFAbsoluteTime autoToolStart = CFAbsoluteTimeGetCurrent();
            NSArray<NSDictionary *> *toolResults = [VCAIReadOnlyToolExecutor executeToolCalls:newAutoToolCalls];
            if (toolResults.count > 0) {
                [accumulatedToolResults addObjectsFromArray:toolResults];
            }
            VCToolCall *followUpMutation = [self _activeScanMutationToolCallFromMessages:apiMessages
                                                                              toolResults:accumulatedToolResults];
            if ([self _finishWithLocalMutationToolCall:followUpMutation
                                 accumulatedReferences:accumulatedReferences
                                            onToolCall:onToolCall
                                            completion:completion]) {
                return;
            }
            [[VCChatDiagnostics shared] recordEventWithPhase:@"tool"
                                                    subphase:@"auto_execute"
                                                   durationMS:MAX(0.0, (CFAbsoluteTimeGetCurrent() - autoToolStart) * 1000.0)
                                                        extra:@{
                                                            @"count": @(newAutoToolCalls.count),
                                                            @"remainingAutoSteps": @(remainingAutoSteps)
                                                        }];
            NSArray<NSDictionary *> *artifactReferences = [VCAIReadOnlyToolExecutor artifactReferencesFromToolResults:toolResults];
            if (artifactReferences.count > 0) {
                [accumulatedReferences addObjectsFromArray:artifactReferences];
            }

            NSMutableArray<NSDictionary *> *nextMessages = [apiMessages mutableCopy];
            if (content.length > 0) {
                [nextMessages addObject:@{@"role": @"assistant", @"content": content}];
            }
            [nextMessages addObject:@{
                @"role": @"system",
                @"content": [VCAIReadOnlyToolExecutor systemMessageForToolResults:toolResults]
            }];

            [self _sendConversationStep:nextMessages
                               provider:provider
                                  tools:tools
                              streaming:streaming
                                onChunk:onChunk
                             onToolCall:onToolCall
                    accumulatedReferences:accumulatedReferences
                  accumulatedToolResults:accumulatedToolResults
             accumulatedManualToolCalls:accumulatedManualToolCalls
                   seenAutoToolSignatures:seenAutoToolSignatures
                      duplicateNudgeUsed:duplicateNudgeUsed
                    manualContinuationUsed:manualContinuationUsed
                     remainingAutoSteps:remainingAutoSteps - 1
                             completion:completion];
            return;
            }
        }

        if (manualToolCalls.count > 0) {
            CFAbsoluteTime toolStart = CFAbsoluteTimeGetCurrent();
            if ([NSThread isMainThread]) {
                for (VCToolCall *toolCall in manualToolCalls) {
                    [VCToolCallBlock executeToolCall:toolCall resultMessage:nil];
                }
            } else {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    for (VCToolCall *toolCall in manualToolCalls) {
                        [VCToolCallBlock executeToolCall:toolCall resultMessage:nil];
                    }
                });
            }
            [[VCChatDiagnostics shared] recordEventWithPhase:@"tool"
                                                    subphase:@"manual_execute"
                                                   durationMS:MAX(0.0, (CFAbsoluteTimeGetCurrent() - toolStart) * 1000.0)
                                                        extra:@{
                                                            @"count": @(manualToolCalls.count)
                                                        }];
            NSMutableArray<NSDictionary *> *manualToolResults = [NSMutableArray new];
            for (VCToolCall *toolCall in manualToolCalls) {
                [manualToolResults addObject:VCAIManualToolResult(toolCall)];
            }
            if (manualToolCalls.count > 0) {
                [accumulatedManualToolCalls addObjectsFromArray:manualToolCalls];
            }
            if (manualToolResults.count > 0 && !manualContinuationUsed && remainingAutoSteps > 0) {
                NSMutableArray<NSDictionary *> *nextMessages = [apiMessages mutableCopy];
                if (content.length > 0) {
                    [nextMessages addObject:@{@"role": @"assistant", @"content": content}];
                }
                [nextMessages addObject:@{
                    @"role": @"system",
                    @"content": VCAIManualToolResultsMessage(manualToolResults)
                }];
                [self _sendConversationStep:nextMessages
                                   provider:provider
                                      tools:tools
                                  streaming:streaming
                                    onChunk:onChunk
                                 onToolCall:onToolCall
                        accumulatedReferences:accumulatedReferences
                      accumulatedToolResults:accumulatedToolResults
                 accumulatedManualToolCalls:accumulatedManualToolCalls
                       seenAutoToolSignatures:seenAutoToolSignatures
                          duplicateNudgeUsed:duplicateNudgeUsed
                       manualContinuationUsed:YES
                         remainingAutoSteps:remainingAutoSteps - 1
                                 completion:completion];
                return;
            }
            if (content.length == 0) {
                content = VCAIManualToolCompletionText(manualToolResults);
            }
        }

        if (content.length == 0 && manualToolCalls.count == 0 && autoToolCalls.count == 0) {
            NSString *message = [fullResponse[@"message"] isKindOfClass:[NSString class]] ? fullResponse[@"message"] : @"The model returned an empty response.";
            self->_isGenerating = NO;
            [[VCChatDiagnostics shared] finishActiveRequestWithError:[NSError errorWithDomain:@"VCAIEngine"
                                                                                          code:-4
                                                                                      userInfo:@{NSLocalizedDescriptionKey: message}]
                                                          totalLength:streamedVisibleLength];
            if (completion) completion(nil, [NSError errorWithDomain:@"VCAIEngine" code:-4
                userInfo:@{NSLocalizedDescriptionKey: message}]);
            return;
        }

        if (content.length == 0 && autoToolCalls.count > 0 && manualToolCalls.count == 0) {
            content = [self _fallbackContentForAutoToolResults:accumulatedToolResults repeated:NO];
        }

        VCMessage *assistantMsg = [VCMessage messageWithRole:@"assistant" content:content];
        NSArray<VCToolCall *> *finalManualToolCalls = accumulatedManualToolCalls.count > 0 ? [accumulatedManualToolCalls copy] : manualToolCalls;
        if (finalManualToolCalls.count) {
            assistantMsg.toolCalls = finalManualToolCalls;
            if (onToolCall) {
                for (VCToolCall *tc in finalManualToolCalls) {
                    onToolCall(tc);
                }
            }
        }
        if (accumulatedReferences.count > 0) {
            assistantMsg.references = [accumulatedReferences copy];
        }

        [[VCChatSession shared] addMessage:assistantMsg];
        [[VCMemoryManager shared] save];
        [[VCChatSession shared] clearStreamingDraft];
        [[VCChatSession shared] saveAll];
        self->_isGenerating = NO;
        [[VCChatDiagnostics shared] finishActiveRequestWithError:nil totalLength:MAX(streamedVisibleLength, content.length)];
        if (completion) completion(assistantMsg, nil);
    };

    if (tools.count > 0 && [_currentAdapter respondsToSelector:@selector(sendMessages:withConfig:tools:streaming:onChunk:onToolCall:onUsage:completion:)]) {
        [(id<VCAIAdapter>)_currentAdapter sendMessages:apiMessages
                                            withConfig:provider
                                                 tools:tools
                                             streaming:streaming
                                               onChunk:^(NSString *text) {
            safeChunkHandler(text);
        }
                                            onToolCall:^(NSDictionary *toolCallDict) {
            // Will be parsed from full response at completion
        }
                                               onUsage:usageHandler
                                            completion:completionHandler];
        return;
    }

    [_currentAdapter sendMessages:apiMessages
                       withConfig:provider
                        streaming:streaming
                          onChunk:^(NSString *text) {
        safeChunkHandler(text);
    }
                       onToolCall:^(NSDictionary *toolCallDict) {
        // Will be parsed from full response at completion
    }
                          onUsage:usageHandler
                       completion:completionHandler];
}

#pragma mark - Provider/Model Switching

- (NSString *)_latestUserTextFromAPIMessages:(NSArray<NSDictionary *> *)apiMessages {
    for (NSDictionary *message in [apiMessages reverseObjectEnumerator]) {
        if (![message isKindOfClass:[NSDictionary class]]) continue;
        NSString *role = [message[@"role"] isKindOfClass:[NSString class]] ? message[@"role"] : @"";
        if (![role isEqualToString:@"user"]) continue;
        NSString *text = VCAIStringFromMessageContent(message[@"content"]);
        if (text.length > 0) return text;
    }
    return @"";
}

- (BOOL)_toolResultsContainSuccessfulMemoryScan:(NSArray<NSDictionary *> *)toolResults {
    for (NSDictionary *result in toolResults ?: @[]) {
        if (![result isKindOfClass:[NSDictionary class]]) continue;
        NSString *tool = [result[@"tool"] isKindOfClass:[NSString class]] ? result[@"tool"] : @"";
        BOOL success = [result[@"success"] respondsToSelector:@selector(boolValue)] ? [result[@"success"] boolValue] : YES;
        if (success && [tool isEqualToString:@"memory_scan"]) return YES;
    }
    return NO;
}

- (VCToolCall *)_activeScanMutationToolCallFromMessages:(NSArray<NSDictionary *> *)apiMessages
                                            toolResults:(NSArray<NSDictionary *> *)toolResults {
    if (![self _toolResultsContainSuccessfulMemoryScan:toolResults]) return nil;

    NSString *text = [self _latestUserTextFromAPIMessages:apiMessages];
    NSString *lower = text.lowercaseString ?: @"";
    if (![lower containsString:@"modify_value"] && ![lower containsString:@"modifiedvalue"]) return nil;
    if (![lower containsString:@"active_memory_scan"] && ![lower containsString:@"active scan"]) return nil;

    NSString *modifiedValue = VCAIExtractPromptValue(text, @[@"modifiedValue", @"modified_value", @"value", @"newValue", @"new_value"]);
    NSString *matchValue = VCAIExtractPromptValue(text, @[@"matchValue", @"match_value", @"currentValue", @"originalValue"]);
    if (modifiedValue.length == 0 || matchValue.length == 0) return nil;

    NSString *mode = VCAIExtractPromptValue(text, @[@"mode"]);
    NSString *maxWrites = VCAIExtractPromptValue(text, @[@"maxWrites", @"max_writes", @"limit"]);
    NSString *dataType = VCAIExtractPromptValue(text, @[@"dataType", @"data_type", @"type"]);

    NSMutableDictionary *params = [@{
        @"source": @"active_memory_scan",
        @"matchValue": matchValue,
        @"modifiedValue": modifiedValue,
        @"mode": mode.length > 0 ? mode : @"write_once"
    } mutableCopy];
    if (maxWrites.length > 0) params[@"maxWrites"] = @([maxWrites integerValue]);
    if (dataType.length > 0 && [dataType.lowercaseString rangeOfString:@"auto"].location == NSNotFound) {
        params[@"dataType"] = dataType;
    }

    VCToolCall *toolCall = [[VCToolCall alloc] init];
    toolCall.toolID = [[NSUUID UUID] UUIDString];
    toolCall.title = @"modify_value";
    toolCall.type = VCToolCallModifyValue;
    toolCall.params = params;
    [VCToolCallParser normalizeToolCall:toolCall];
    return toolCall;
}

- (BOOL)_finishWithLocalMutationToolCall:(VCToolCall *)toolCall
                   accumulatedReferences:(NSArray<NSDictionary *> *)accumulatedReferences
                              onToolCall:(void(^)(VCToolCall *))onToolCall
                              completion:(void(^)(VCMessage *, NSError *))completion {
    if (![toolCall isKindOfClass:[VCToolCall class]]) return NO;

    CFAbsoluteTime toolStart = CFAbsoluteTimeGetCurrent();
    NSString *resultMessage = nil;
    [VCToolCallBlock executeToolCall:toolCall resultMessage:&resultMessage];
    [[VCChatDiagnostics shared] recordEventWithPhase:@"tool"
                                            subphase:@"local_followup_mutation"
                                           durationMS:MAX(0.0, (CFAbsoluteTimeGetCurrent() - toolStart) * 1000.0)
                                                extra:@{
                                                    @"tool": toolCall.title ?: @"modify_value",
                                                    @"success": @(toolCall.success)
                                                }];

    NSString *content = [NSString stringWithFormat:@"已根据扫描结果执行 modify_value：%@",
                         resultMessage.length > 0 ? resultMessage : (toolCall.success ? @"完成" : @"失败")];
    VCMessage *assistantMsg = [VCMessage messageWithRole:@"assistant" content:content];
    assistantMsg.toolCalls = @[toolCall];
    if (accumulatedReferences.count > 0) {
        assistantMsg.references = [accumulatedReferences copy];
    }
    [[VCChatSession shared] addMessage:assistantMsg];
    [[VCMemoryManager shared] save];
    [[VCChatSession shared] clearStreamingDraft];
    [[VCChatSession shared] saveAll];
    _isGenerating = NO;
    [[VCChatDiagnostics shared] finishActiveRequestWithError:nil totalLength:content.length];
    if (onToolCall) onToolCall(toolCall);
    if (completion) completion(assistantMsg, nil);
    return YES;
}

- (NSString *)_fallbackContentForAutoToolResults:(NSArray<NSDictionary *> *)toolResults repeated:(BOOL)repeated {
    if (toolResults.count == 0) {
        return repeated
            ? @"已停止重复的自动查询。当前没有可展示的工具结果，请换一个更具体的目标继续。"
            : @"已完成自动查询。当前没有可展示的工具结果，请换一个更具体的目标继续。";
    }

    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:(repeated ? @"已停止重复的自动查询，当前工具结果如下：" : @"已完成自动查询，当前工具结果如下：")];
    NSUInteger index = 1;
    for (NSDictionary *result in toolResults) {
        NSString *toolName = [result[@"tool"] isKindOfClass:[NSString class]] ? result[@"tool"] : @"tool";
        NSString *summary = [result[@"summary"] isKindOfClass:[NSString class]] ? result[@"summary"] : @"Completed";
        BOOL success = [result[@"success"] respondsToSelector:@selector(boolValue)] ? [result[@"success"] boolValue] : YES;
        [lines addObject:[NSString stringWithFormat:@"%lu. %@：%@%@", (unsigned long)index, toolName, success ? @"" : @"失败，", summary]];
        index += 1;
        if (index > 8) break;
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)switchProvider:(NSString *)providerID model:(NSString *)model {
    [[VCProviderManager shared] setActiveProviderID:providerID];
    if (model) {
        VCProviderConfig *p = [[VCProviderManager shared] providerForID:providerID];
        p.selectedModel = model;
        [[VCProviderManager shared] updateProvider:p];
    }
    [[VCTokenTracker shared] updateForModel:model];
    VCLog(@"AIEngine: switched to %@ / %@", providerID, model);
}

#pragma mark - Message Operations

- (void)editAndResend:(NSString *)messageID newText:(NSString *)text {
    VCChatSession *session = [VCChatSession shared];
    NSUInteger idx = [session indexOfMessage:messageID];
    if (idx == NSNotFound) return;

    // Truncate from this message onward
    [session truncateFromMessage:messageID];

    // Reset token stats
    [[VCTokenTracker shared] reset];

    // Send edited message
    [self sendMessage:text withContext:nil streaming:YES onChunk:nil onToolCall:nil completion:nil];
}

- (void)deleteMessage:(NSString *)messageID {
    [[VCChatSession shared] deleteMessage:messageID];
}

- (void)resendMessage:(NSString *)messageID {
    VCMessage *msg = [[VCChatSession shared] messageForID:messageID];
    if (!msg) return;

    // Truncate from this message onward
    [[VCChatSession shared] truncateFromMessage:messageID];

    // Resend same content
    [self sendMessage:msg.content withContext:nil streaming:YES onChunk:nil onToolCall:nil completion:nil];
}

#pragma mark - Stop

- (void)stopGeneration {
    [_currentAdapter cancel];
    _isGenerating = NO;
    VCLog(@"AIEngine: generation stopped");
}

#pragma mark - Private

- (NSMutableArray<NSDictionary *> *)_buildAPIMessages:(NSDictionary *)context
                                             messages:(NSArray<VCMessage *> *)messages {
    NSMutableArray<NSDictionary *> *apiMessages = [NSMutableArray new];

    NSString *systemPrompt = [[VCPromptManager shared] buildSystemPrompt];
    [apiMessages addObject:@{@"role": @"system", @"content": systemPrompt}];

    NSString *rolePreset = [[[VCProviderManager shared] activeProvider].rolePreset stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (rolePreset.length > 0) {
        [apiMessages addObject:@{@"role": @"system",
                                 @"content": [NSString stringWithFormat:@"[Provider Role Preset]\n%@", rolePreset]}];
    }

    NSDictionary *memoryPayload = [[VCMemoryManager shared] promptPayload];
    if ([memoryPayload[@"totalCount"] unsignedIntegerValue] > 0) {
        NSData *memoryData = [NSJSONSerialization dataWithJSONObject:memoryPayload options:NSJSONWritingPrettyPrinted error:nil];
        NSString *memoryString = [[NSString alloc] initWithData:memoryData encoding:NSUTF8StringEncoding];
        [apiMessages addObject:@{@"role": @"system",
                                 @"content": [NSString stringWithFormat:@"[Durable Memory]\n%@",
                                              memoryString ?: @"{}"]}];
    }

    NSDictionary *artifact = [[VCChatSession shared] currentContinuationArtifact];
    if (artifact.count > 0) {
        [apiMessages addObject:@{@"role": @"system",
                                 @"content": [NSString stringWithFormat:@"[Structured Session Summary]\n%@",
                                              [VCContextCompactor renderArtifact:artifact]]}];
    }

    if (context.count) {
        NSData *ctxData = [NSJSONSerialization dataWithJSONObject:context options:NSJSONWritingPrettyPrinted error:nil];
        NSString *ctxStr = [[NSString alloc] initWithData:ctxData encoding:NSUTF8StringEncoding];
        [apiMessages addObject:@{@"role": @"system",
            @"content": [NSString stringWithFormat:@"[Current Context]\n%@", ctxStr]}];
    }

    for (VCMessage *msg in messages) {
        if ([msg.role isEqualToString:@"system"] && [msg.content hasPrefix:@"[Structured Session Summary]"]) {
            continue;
        }
        [apiMessages addObject:[msg toAPIFormat]];
    }

    return apiMessages;
}

- (id<VCAIAdapter>)_adapterForProtocol:(VCAPIProtocol)protocol {
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
