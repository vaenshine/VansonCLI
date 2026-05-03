/**
 * VCOpenAIAdapter.mm -- OpenAI Compatible + Responses API
 * SSE streaming via NSURLSessionDataDelegate
 */

#import "VCOpenAIAdapter.h"
#import "../Models/VCProviderConfig.h"
#import "../../../VansonCLI.h"

static NSString *VCOpenAITrimmedString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return @"";
}

static NSString *VCOpenAIStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return (NSString *)value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    return nil;
}

static NSString *VCOpenAIUserAgent(void) {
    return @"VansonCLI/1.0 CFNetwork/1496.0.7 Darwin/23.5.0";
}

static NSString *VCOpenAINormalizedAPIKey(id value) {
    NSString *key = [VCProviderConfig normalizedAPIKeyString:value];
    NSString *lower = key.lowercaseString ?: @"";
    if ([lower hasPrefix:@"bearer "]) {
        key = VCOpenAITrimmedString([key substringFromIndex:7]);
    }
    return key;
}

@implementation VCOpenAIAdapter {
    NSURLSessionDataTask *_task;
    NSURLSession *_session;
    NSMutableData *_buffer;
    NSMutableData *_rawResponseData;
    // Callbacks (retained during streaming)
    void (^_onChunk)(NSString *);
    void (^_onToolCall)(NSDictionary *);
    void (^_onUsage)(NSUInteger, NSUInteger);
    void (^_completion)(NSDictionary *, NSError *);
    // Accumulated response
    NSMutableString *_fullContent;
    NSMutableArray *_toolCallAccumulator;
    NSMutableDictionary *_responsesToolCallLookup;
    NSMutableDictionary *_fullResponse;
    BOOL _isResponsesAPI;
    NSInteger _httpStatusCode;
    NSString *_responseMIMEType;
}

#pragma mark - VCAIAdapter

- (void)sendMessages:(NSArray<NSDictionary *> *)messages
          withConfig:(VCProviderConfig *)config
               tools:(NSArray<NSDictionary *> *)tools
           streaming:(BOOL)streaming
             onChunk:(void(^)(NSString *))onChunk
          onToolCall:(void(^)(NSDictionary *))onToolCall
             onUsage:(void(^)(NSUInteger, NSUInteger))onUsage
          completion:(void(^)(NSDictionary *, NSError *))completion {
    [self _sendMessages:messages withConfig:config tools:tools streaming:streaming onChunk:onChunk onToolCall:onToolCall onUsage:onUsage completion:completion];
}

- (void)sendMessages:(NSArray<NSDictionary *> *)messages
          withConfig:(VCProviderConfig *)config
           streaming:(BOOL)streaming
             onChunk:(void(^)(NSString *))onChunk
          onToolCall:(void(^)(NSDictionary *))onToolCall
             onUsage:(void(^)(NSUInteger, NSUInteger))onUsage
          completion:(void(^)(NSDictionary *, NSError *))completion {
    [self _sendMessages:messages withConfig:config tools:nil streaming:streaming onChunk:onChunk onToolCall:onToolCall onUsage:onUsage completion:completion];
}

- (void)_sendMessages:(NSArray<NSDictionary *> *)messages
           withConfig:(VCProviderConfig *)config
                tools:(NSArray<NSDictionary *> *)tools
            streaming:(BOOL)streaming
              onChunk:(void(^)(NSString *))onChunk
           onToolCall:(void(^)(NSDictionary *))onToolCall
              onUsage:(void(^)(NSUInteger, NSUInteger))onUsage
           completion:(void(^)(NSDictionary *, NSError *))completion {
    _onChunk = onChunk;
    _onToolCall = onToolCall;
    _onUsage = onUsage;
    _completion = completion;
    _fullContent = [NSMutableString new];
    _toolCallAccumulator = [NSMutableArray new];
    _responsesToolCallLookup = [NSMutableDictionary new];
    _fullResponse = [NSMutableDictionary new];
    _buffer = [NSMutableData new];
    _rawResponseData = [NSMutableData new];
    _isResponsesAPI = (config.protocol == VCAPIProtocolOpenAIResponses);
    _httpStatusCode = 0;
    _responseMIMEType = nil;

    // Build URL
    NSString *urlStr;
    if (_isResponsesAPI) {
        urlStr = [self _buildURLStringWithEndpoint:config.endpoint apiPath:[self _apiPathForConfig:config terminalPath:@"/responses"]];
    } else {
        urlStr = [self _buildURLStringWithEndpoint:config.endpoint apiPath:[self _apiPathForConfig:config terminalPath:@"/chat/completions"]];
    }
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url || url.scheme.length == 0 || url.host.length == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"VCOpenAI" code:-9
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid provider endpoint URL"}]);
        return;
    }

    // Build body
    NSMutableDictionary *body = [NSMutableDictionary new];
    body[@"model"] = config.selectedModel;
    body[@"stream"] = @(streaming);
    if (_isResponsesAPI) {
        NSArray<NSDictionary *> *inputItems = [self _responsesInputItemsFromMessages:messages];
        if (inputItems.count > 0) {
            body[@"input"] = inputItems;
        }
    } else {
        body[@"messages"] = messages ?: @[];
    }
    [self _applyToolSchemas:tools toBody:body responsesMode:_isResponsesAPI];

    NSInteger maxOut = config.maxTokens > 0 ? config.maxTokens : (config.isBuiltin ? [self _maxOutputTokensForModel:config.selectedModel] : 0);
    if (maxOut > 0) {
        body[_isResponsesAPI ? @"max_output_tokens" : @"max_tokens"] = @(maxOut);
    }
    NSString *reasoningEffort = VCOpenAITrimmedString(config.reasoningEffort).lowercaseString;
    if ([reasoningEffort isEqualToString:@"low"] ||
        [reasoningEffort isEqualToString:@"medium"] ||
        [reasoningEffort isEqualToString:@"high"]) {
        if (_isResponsesAPI) {
            body[@"reasoning"] = @{@"effort": reasoningEffort};
        } else {
            body[@"reasoning_effort"] = reasoningEffort;
        }
    }

    NSData *jsonBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    // Build request
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = jsonBody;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json, text/event-stream" forHTTPHeaderField:@"Accept"];
    [req setValue:VCOpenAIUserAgent() forHTTPHeaderField:@"User-Agent"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", VCOpenAINormalizedAPIKey(config.apiKey)] forHTTPHeaderField:@"Authorization"];
    [req setValue:kVCInternalRequestAIValue forHTTPHeaderField:kVCInternalRequestHeader];
    req.timeoutInterval = 120;

    if (streaming) {
        // Use delegate-based session for SSE
        NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        _session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:nil];
        _task = [_session dataTaskWithRequest:req];
        [_task resume];
    } else {
        // Non-streaming: simple completion handler
        _task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
            if (error) {
                if (completion) completion(nil, error);
                return;
            }
            [self _handleNonStreamingResponse:data];
        }];
        [_task resume];
    }
}

- (void)fetchModelsWithConfig:(VCProviderConfig *)config
                   completion:(void(^)(NSArray<NSString *> *, NSError *))completion {
    NSString *urlStr = [self _buildURLStringWithEndpoint:config.endpoint apiPath:[self _apiPathForConfig:config terminalPath:@"/models"]];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url || url.scheme.length == 0 || url.host.length == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"VCOpenAI" code:-9
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid provider endpoint URL"}]);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", VCOpenAINormalizedAPIKey(config.apiKey)] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:VCOpenAIUserAgent() forHTTPHeaderField:@"User-Agent"];
    [req setValue:kVCInternalRequestAIValue forHTTPHeaderField:kVCInternalRequestHeader];
    req.timeoutInterval = 30;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        NSInteger statusCode = [(NSHTTPURLResponse *)resp statusCode];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *errorObj = [json[@"error"] isKindOfClass:[NSDictionary class]] ? json[@"error"] : nil;
        if (statusCode >= 400 || errorObj.count > 0) {
            NSString *message = VCOpenAIStringValue(errorObj[@"message"]);
            NSString *code = VCOpenAIStringValue(errorObj[@"code"]);
            if (message.length == 0) {
                message = VCOpenAIStringValue(json[@"message"]);
            }
            if (message.length == 0) {
                message = VCOpenAIStringValue(json[@"detail"]);
            }
            if (code.length == 0) {
                code = VCOpenAIStringValue(json[@"code"]);
            }
            NSString *cloudflareCode = VCOpenAIStringValue(json[@"error_code"]);
            NSString *cloudflareName = VCOpenAIStringValue(json[@"error_name"]);
            if (cloudflareCode.length > 0 || cloudflareName.length > 0) {
                NSString *label = cloudflareCode.length > 0 ? [NSString stringWithFormat:@"Cloudflare %@", cloudflareCode] : @"Cloudflare";
                if (cloudflareName.length > 0) {
                    label = [label stringByAppendingFormat:@": %@", cloudflareName];
                }
                message = message.length > 0 ? [NSString stringWithFormat:@"Provider blocked the request (%@). %@", label, message] : [NSString stringWithFormat:@"Provider blocked the request (%@).", label];
            } else if (code.length > 0 && message.length > 0) {
                message = [NSString stringWithFormat:@"%@: %@", code, message];
            }
            if (message.length == 0) {
                message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Failed to fetch models";
            }
            if (completion) completion(nil, [NSError errorWithDomain:@"VCOpenAI" code:(statusCode ?: -1)
                                                            userInfo:@{NSLocalizedDescriptionKey: message}]);
            return;
        }
        NSArray *dataArr = json[@"data"];
        NSMutableArray *models = [NSMutableArray new];
        for (NSDictionary *m in dataArr) {
            NSString *mid = m[@"id"];
            if (mid) [models addObject:mid];
        }
        [models sortUsingSelector:@selector(compare:)];
        if (completion) completion(models, nil);
    }];
    [task resume];
}

- (void)cancel {
    [_task cancel];
    _task = nil;
    [_session invalidateAndCancel];
    _session = nil;
}

#pragma mark - NSURLSessionDataDelegate (SSE Streaming)

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        _httpStatusCode = httpResponse.statusCode;
        _responseMIMEType = httpResponse.MIMEType.lowercaseString ?: @"";
    }
    if (completionHandler) completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    [_rawResponseData appendData:data];
    [_buffer appendData:data];
    [self _processSSEBuffer];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
    if (error && error.code != NSURLErrorCancelled) {
        if (_completion) _completion(nil, error);
    } else {
        NSError *apiError = [self _errorFromResponseData:_rawResponseData statusCode:_httpStatusCode];
        if (apiError) {
            if (_completion) _completion(nil, apiError);
            [self _cleanup];
            return;
        }

        if ((_fullContent.length == 0 && _toolCallAccumulator.count == 0) || ![_responseMIMEType containsString:@"event-stream"]) {
            NSDictionary *fallbackResponse = [self _fallbackResponseFromRawData:_rawResponseData];
            if (fallbackResponse.count > 0) {
                if (_completion) _completion(fallbackResponse, nil);
                [self _cleanup];
                return;
            }
        }

        _fullResponse[@"content"] = [_fullContent copy];
        _fullResponse[@"tool_calls"] = [_toolCallAccumulator copy];
        if (_completion) _completion(_fullResponse, nil);
    }
    [self _cleanup];
}

#pragma mark - SSE Parsing

- (void)_processSSEBuffer {
    NSString *str = [[NSString alloc] initWithData:_buffer encoding:NSUTF8StringEncoding];
    if (!str) return;

    // Split by double newline (SSE event boundary)
    NSArray *chunks = [str componentsSeparatedByString:@"\n\n"];
    if (chunks.count <= 1) return; // No complete event yet

    // Keep the last incomplete chunk in buffer
    NSString *remainder = chunks.lastObject;
    _buffer = [[remainder dataUsingEncoding:NSUTF8StringEncoding] mutableCopy] ?: [NSMutableData new];

    for (NSUInteger i = 0; i < chunks.count - 1; i++) {
        NSString *chunk = chunks[i];
        [self _parseSSEEvent:chunk];
    }
}

- (void)_parseSSEEvent:(NSString *)event {
    // Extract "data: " lines
    NSArray *lines = [event componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"data: "]) {
            NSString *payload = [trimmed substringFromIndex:6];
            if ([payload isEqualToString:@"[DONE]"]) return;
            [self _parseSSEPayload:payload];
        }
    }
}

- (void)_parseSSEPayload:(NSString *)payload {
    NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!json) return;

    if (_isResponsesAPI) {
        [self _parseResponsesPayload:json];
    } else {
        [self _parseChatCompletionsPayload:json];
    }
}

- (void)_parseChatCompletionsPayload:(NSDictionary *)json {
    NSArray *choices = [json[@"choices"] isKindOfClass:[NSArray class]] ? json[@"choices"] : nil;
    NSDictionary *choice = [choices.firstObject isKindOfClass:[NSDictionary class]] ? choices.firstObject : nil;
    NSDictionary *delta = [choice[@"delta"] isKindOfClass:[NSDictionary class]] ? choice[@"delta"] : nil;
    NSDictionary *message = [choice[@"message"] isKindOfClass:[NSDictionary class]] ? choice[@"message"] : nil;
    NSDictionary *payload = delta ?: message;
    if (!payload && ([json[@"tool_calls"] isKindOfClass:[NSArray class]] || json[@"content"])) {
        payload = json;
    }
    if (!payload) return;

    // Text content
    NSString *content = [self _stringFromContentValue:payload[@"content"]];
    if (content.length) {
        [_fullContent appendString:content];
        if (_onChunk) _onChunk(content);
    }

    // Tool calls
    NSArray *toolCalls = [payload[@"tool_calls"] isKindOfClass:[NSArray class]] ? payload[@"tool_calls"] : nil;
    if (toolCalls.count) {
        for (NSDictionary *tc in toolCalls) {
            if (![tc isKindOfClass:[NSDictionary class]]) continue;
            NSInteger idx = [tc[@"index"] respondsToSelector:@selector(integerValue)] ? [tc[@"index"] integerValue] : NSNotFound;
            NSString *tcID = VCOpenAITrimmedString(tc[@"id"]);
            if (idx == NSNotFound && tcID.length > 0) {
                for (NSUInteger existingIdx = 0; existingIdx < _toolCallAccumulator.count; existingIdx++) {
                    NSDictionary *existing = [_toolCallAccumulator[existingIdx] isKindOfClass:[NSDictionary class]] ? _toolCallAccumulator[existingIdx] : nil;
                    if ([VCOpenAITrimmedString(existing[@"id"]) isEqualToString:tcID]) {
                        idx = (NSInteger)existingIdx;
                        break;
                    }
                }
            }
            if (idx == NSNotFound) idx = (NSInteger)_toolCallAccumulator.count;
            // Accumulate tool call chunks
            while ((NSInteger)_toolCallAccumulator.count <= idx) {
                [_toolCallAccumulator addObject:[NSMutableDictionary new]];
            }
            NSMutableDictionary *acc = _toolCallAccumulator[idx];
            if (tcID.length > 0) acc[@"id"] = tcID;
            NSDictionary *fn = [tc[@"function"] isKindOfClass:[NSDictionary class]] ? tc[@"function"] : nil;
            NSString *name = VCOpenAITrimmedString(fn[@"name"]);
            if (name.length == 0) name = VCOpenAITrimmedString(tc[@"name"]);
            if (name.length > 0) acc[@"name"] = name;

            id argumentsValue = fn[@"arguments"] ?: tc[@"arguments"] ?: tc[@"input"];
            NSString *arguments = VCOpenAIStringValue(argumentsValue);
            if (arguments.length == 0 && [argumentsValue isKindOfClass:[NSDictionary class]]) {
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:argumentsValue options:0 error:nil];
                arguments = jsonData.length > 0 ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"";
            }
            if (arguments.length > 0) {
                NSString *existing = [acc[@"arguments"] isKindOfClass:[NSString class]] ? acc[@"arguments"] : @"";
                acc[@"arguments"] = (tc[@"index"] != nil || existing.length == 0) ? [existing stringByAppendingString:arguments] : arguments;
            }
        }
    }

    // Usage (some providers include in final chunk)
    NSDictionary *usage = [json[@"usage"] isKindOfClass:[NSDictionary class]] ? json[@"usage"] : nil;
    if (usage && _onUsage) {
        NSUInteger inputTokens = [usage[@"prompt_tokens"] unsignedIntegerValue];
        if (inputTokens == 0) inputTokens = [usage[@"input_tokens"] unsignedIntegerValue];
        NSUInteger outputTokens = [usage[@"completion_tokens"] unsignedIntegerValue];
        if (outputTokens == 0) outputTokens = [usage[@"output_tokens"] unsignedIntegerValue];
        _onUsage(inputTokens, outputTokens);
    }
}

- (void)_parseResponsesPayload:(NSDictionary *)json {
    // OpenAI Responses API format
    NSString *type = VCOpenAITrimmedString(json[@"type"]);
    if ([type isEqualToString:@"response.output_text.delta"]) {
        NSString *delta = VCOpenAIStringValue(json[@"delta"]);
        if (delta.length) {
            [_fullContent appendString:delta];
            if (_onChunk) _onChunk(delta);
        }
    } else if ([type isEqualToString:@"response.output_item.added"] ||
               [type isEqualToString:@"response.output_item.done"]) {
        [self _mergeResponsesOutputItem:json];
    } else if ([type isEqualToString:@"response.function_call_arguments.delta"]) {
        NSMutableDictionary *acc = [self _responsesToolCallAccumulatorForEvent:json create:YES];
        NSString *delta = VCOpenAIStringValue(json[@"delta"]);
        if (acc && delta.length > 0) {
            NSString *existing = [acc[@"arguments"] isKindOfClass:[NSString class]] ? acc[@"arguments"] : @"";
            acc[@"arguments"] = [existing stringByAppendingString:delta];
        }
    } else if ([type isEqualToString:@"response.function_call_arguments.done"]) {
        NSMutableDictionary *acc = [self _responsesToolCallAccumulatorForEvent:json create:YES];
        NSString *arguments = VCOpenAIStringValue(json[@"arguments"]);
        if (acc && arguments.length > 0) {
            acc[@"arguments"] = arguments;
        }
    } else if ([type isEqualToString:@"response.completed"]) {
        NSDictionary *response = json[@"response"];
        NSDictionary *usage = response[@"usage"];
        if (usage && _onUsage) {
            _onUsage([usage[@"input_tokens"] unsignedIntegerValue],
                     [usage[@"output_tokens"] unsignedIntegerValue]);
        }
    }
}

- (BOOL)_responsesItemIsToolCall:(NSDictionary *)item {
    NSString *itemType = VCOpenAITrimmedString(item[@"type"]).lowercaseString;
    if (itemType.length == 0) return NO;
    return [itemType containsString:@"function"] || [itemType containsString:@"tool"];
}

- (NSMutableDictionary *)_responsesToolCallAccumulatorForEvent:(NSDictionary *)event create:(BOOL)create {
    NSDictionary *item = [event[@"item"] isKindOfClass:[NSDictionary class]] ? event[@"item"] : nil;
    NSString *itemID = VCOpenAITrimmedString(event[@"item_id"]);
    if (itemID.length == 0) itemID = VCOpenAITrimmedString(item[@"id"]);
    NSString *callID = VCOpenAITrimmedString(item[@"call_id"]);
    NSInteger outputIndex = [event[@"output_index"] respondsToSelector:@selector(integerValue)]
        ? [event[@"output_index"] integerValue]
        : NSNotFound;

    NSString *lookupKey = itemID;
    if (lookupKey.length == 0 && callID.length > 0) {
        lookupKey = [NSString stringWithFormat:@"call:%@", callID];
    }
    if (lookupKey.length == 0 && outputIndex != NSNotFound) {
        lookupKey = [NSString stringWithFormat:@"idx:%ld", (long)outputIndex];
    }

    NSMutableDictionary *acc = lookupKey.length > 0 ? _responsesToolCallLookup[lookupKey] : nil;
    if (!acc && create) {
        if (outputIndex != NSNotFound) {
            while ((NSInteger)_toolCallAccumulator.count <= outputIndex) {
                [_toolCallAccumulator addObject:[NSMutableDictionary new]];
            }
            id existing = _toolCallAccumulator[outputIndex];
            if ([existing isKindOfClass:[NSMutableDictionary class]]) {
                acc = (NSMutableDictionary *)existing;
            } else if ([existing isKindOfClass:[NSDictionary class]]) {
                acc = [existing mutableCopy];
                _toolCallAccumulator[outputIndex] = acc;
            } else {
                acc = [NSMutableDictionary new];
                _toolCallAccumulator[outputIndex] = acc;
            }
        } else {
            acc = [NSMutableDictionary new];
            [_toolCallAccumulator addObject:acc];
        }
    }

    if (acc && lookupKey.length > 0) {
        _responsesToolCallLookup[lookupKey] = acc;
    }
    return acc;
}

- (void)_mergeResponsesOutputItem:(NSDictionary *)event {
    NSDictionary *item = [event[@"item"] isKindOfClass:[NSDictionary class]] ? event[@"item"] : nil;
    if (![self _responsesItemIsToolCall:item]) return;

    NSMutableDictionary *acc = [self _responsesToolCallAccumulatorForEvent:event create:YES];
    if (!acc) return;

    NSString *callID = VCOpenAITrimmedString(item[@"call_id"]);
    NSString *itemID = VCOpenAITrimmedString(item[@"id"]);
    NSString *name = VCOpenAITrimmedString(item[@"name"]);
    NSString *arguments = VCOpenAIStringValue(item[@"arguments"]);
    if (arguments.length == 0 && [item[@"input"] isKindOfClass:[NSDictionary class]]) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:item[@"input"] options:0 error:nil];
        if (jsonData.length > 0) {
            arguments = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
    }

    if (callID.length > 0) acc[@"id"] = callID;
    else if (itemID.length > 0) acc[@"id"] = itemID;
    if (name.length > 0) acc[@"name"] = name;
    if (arguments.length > 0) acc[@"arguments"] = arguments;
}

#pragma mark - Non-Streaming

- (void)_handleNonStreamingResponse:(NSData *)data {
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!json) {
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (_completion) _completion(nil, [NSError errorWithDomain:@"VCOpenAI" code:-1
            userInfo:@{NSLocalizedDescriptionKey: raw ?: @"Invalid response"}]);
        return;
    }

    // Check for API error
    NSDictionary *errorObj = json[@"error"];
    if (errorObj) {
        if (_completion) _completion(json, [NSError errorWithDomain:@"VCOpenAI" code:-1
            userInfo:@{NSLocalizedDescriptionKey: errorObj[@"message"] ?: @"API error"}]);
        return;
    }

    // Extract content
    NSString *content = _isResponsesAPI ? [self _contentFromResponsesJSON:json] : [self _contentFromChatJSON:json];
    if (content && _onChunk) _onChunk(content);

    // Tool calls
    NSArray *toolCalls = [self _toolCallsFromJSON:json];
    if (toolCalls && _onToolCall) {
        for (NSDictionary *tc in toolCalls) {
            _onToolCall(tc);
        }
    }

    // Usage
    NSDictionary *usage = json[@"usage"];
    if (usage && _onUsage) {
        _onUsage([usage[@"prompt_tokens"] unsignedIntegerValue],
                 [usage[@"completion_tokens"] unsignedIntegerValue]);
    }

    if (_completion) _completion(json, nil);
}

#pragma mark - Helpers

- (NSString *)_buildURLStringWithEndpoint:(NSString *)endpoint apiPath:(NSString *)apiPath {
    NSString *base = VCOpenAITrimmedString(endpoint);
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    NSString *normalizedAPIPath = apiPath ?: @"";
    if (base.length == 0 || normalizedAPIPath.length == 0) return base;
    NSArray<NSString *> *pathParts = [normalizedAPIPath componentsSeparatedByString:@"/"];
    NSString *versionSegment = @"";
    for (NSString *part in pathParts) {
        if (part.length > 0) {
            versionSegment = part;
            break;
        }
    }
    NSString *versionPrefix = versionSegment.length > 0 ? [@"/" stringByAppendingString:versionSegment] : @"";
    NSString *shortPath = (versionPrefix.length > 0 && [normalizedAPIPath hasPrefix:versionPrefix])
        ? [normalizedAPIPath substringFromIndex:versionPrefix.length]
        : normalizedAPIPath;
    if (shortPath.length == 0) shortPath = @"/";

    NSURLComponents *components = [NSURLComponents componentsWithString:base];
    if (components.scheme.length == 0 || components.host.length == 0) {
        NSString *lower = base.lowercaseString;
        if ([lower hasSuffix:normalizedAPIPath.lowercaseString] || (shortPath.length > 0 && [lower hasSuffix:shortPath.lowercaseString])) {
            return base;
        }
        if (versionPrefix.length > 0 && [lower hasSuffix:versionPrefix.lowercaseString]) {
            return [base stringByAppendingString:shortPath];
        }
        return [base stringByAppendingString:normalizedAPIPath];
    }

    components.query = nil;
    components.fragment = nil;
    NSString *path = components.path ?: @"";
    NSString *lowerPath = path.lowercaseString ?: @"";
    if ([lowerPath hasSuffix:normalizedAPIPath.lowercaseString] || (shortPath.length > 0 && [lowerPath hasSuffix:shortPath.lowercaseString])) {
        return components.string ?: base;
    }

    NSString *versionNeedle = versionPrefix.length > 0 ? [versionPrefix stringByAppendingString:@"/"] : @"";
    NSRange versionedRange = versionNeedle.length > 0 ? [lowerPath rangeOfString:versionNeedle.lowercaseString] : NSMakeRange(NSNotFound, 0);
    if (versionedRange.location != NSNotFound) {
        NSString *prefix = [path substringToIndex:versionedRange.location];
        components.path = [prefix stringByAppendingString:versionPrefix];
        return [components.string stringByAppendingString:shortPath];
    }
    if (versionPrefix.length > 0 && [lowerPath hasSuffix:versionPrefix.lowercaseString]) {
        return [components.string stringByAppendingString:shortPath];
    }
    components.path = path;
    return [components.string stringByAppendingString:normalizedAPIPath];
}

- (NSString *)_apiPathForConfig:(VCProviderConfig *)config terminalPath:(NSString *)terminalPath {
    NSString *version = VCOpenAITrimmedString(config.apiVersion);
    if (version.length == 0) version = @"/v1";
    if (![version hasPrefix:@"/"]) version = [@"/" stringByAppendingString:version];
    while (version.length > 1 && [version hasSuffix:@"/"]) {
        version = [version substringToIndex:version.length - 1];
    }
    NSString *path = VCOpenAITrimmedString(terminalPath);
    if (path.length == 0) return version;
    if (![path hasPrefix:@"/"]) path = [@"/" stringByAppendingString:path];
    return [version stringByAppendingString:path];
}

- (NSArray<NSDictionary *> *)_responsesInputItemsFromMessages:(NSArray<NSDictionary *> *)messages {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    NSSet<NSString *> *allowedRoles = [NSSet setWithArray:@[@"system", @"developer", @"user", @"assistant"]];

    for (NSDictionary *message in messages ?: @[]) {
        if (![message isKindOfClass:[NSDictionary class]]) continue;
        NSString *role = VCOpenAITrimmedString(message[@"role"]).lowercaseString;
        NSString *content = VCOpenAITrimmedString(message[@"content"]);
        if (content.length == 0) continue;
        if (![allowedRoles containsObject:role]) role = @"user";
        [items addObject:@{
            @"type": @"message",
            @"role": role,
            @"content": @[@{
                @"type": @"input_text",
                @"text": content
            }]
        }];
    }

    return [items copy];
}

- (void)_applyToolSchemas:(NSArray<NSDictionary *> *)tools
                   toBody:(NSMutableDictionary *)body
            responsesMode:(BOOL)responsesMode {
    if (![body isKindOfClass:[NSMutableDictionary class]] || tools.count == 0) return;

    NSMutableArray *normalizedTools = [NSMutableArray new];
    for (NSDictionary *tool in tools) {
        NSString *name = [tool[@"name"] isKindOfClass:[NSString class]] ? tool[@"name"] : nil;
        NSDictionary *parameters = [tool[@"parameters"] isKindOfClass:[NSDictionary class]] ? tool[@"parameters"] : nil;
        if (!name.length || parameters.count == 0) continue;

        if (responsesMode) {
            [normalizedTools addObject:@{
                @"type": @"function",
                @"name": name,
                @"description": [tool[@"description"] isKindOfClass:[NSString class]] ? tool[@"description"] : @"",
                @"parameters": parameters
            }];
        } else {
            [normalizedTools addObject:@{
                @"type": @"function",
                @"function": @{
                    @"name": name,
                    @"description": [tool[@"description"] isKindOfClass:[NSString class]] ? tool[@"description"] : @"",
                    @"parameters": parameters
                }
            }];
        }
    }

    if (normalizedTools.count > 0) {
        body[@"tools"] = normalizedTools;
    }
}

- (NSError *)_errorFromResponseData:(NSData *)data statusCode:(NSInteger)statusCode {
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *errorObj = [json[@"error"] isKindOfClass:[NSDictionary class]] ? json[@"error"] : nil;
    NSString *message = errorObj[@"message"];
    NSString *code = VCOpenAIStringValue(errorObj[@"code"]);
    if (message.length == 0 && [json[@"detail"] isKindOfClass:[NSString class]]) {
        message = json[@"detail"];
    }
    if (message.length == 0 && [json[@"message"] isKindOfClass:[NSString class]]) {
        message = json[@"message"];
    }
    if (message.length == 0 && [json[@"title"] isKindOfClass:[NSString class]]) {
        message = json[@"title"];
    }
    if (code.length == 0 && [json[@"code"] isKindOfClass:[NSString class]]) {
        code = json[@"code"];
    }
    NSString *cloudflareCode = VCOpenAIStringValue(json[@"error_code"]);
    NSString *cloudflareName = VCOpenAIStringValue(json[@"error_name"]);
    if (cloudflareCode.length > 0 || cloudflareName.length > 0) {
        NSString *label = cloudflareCode.length > 0 ? [NSString stringWithFormat:@"Cloudflare %@", cloudflareCode] : @"Cloudflare";
        if (cloudflareName.length > 0) {
            label = [label stringByAppendingFormat:@": %@", cloudflareName];
        }
        message = message.length > 0 ? [NSString stringWithFormat:@"Provider blocked the request (%@). %@", label, message] : [NSString stringWithFormat:@"Provider blocked the request (%@).", label];
    } else if (code.length > 0 && message.length > 0) {
        message = [NSString stringWithFormat:@"%@: %@", code, message];
    }
    if (message.length == 0 && statusCode >= 400) {
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        message = raw.length ? raw : @"The provider returned an error response";
    }
    if (message.length == 0) return nil;
    if (statusCode < 400 && errorObj.count == 0) return nil;
    return [NSError errorWithDomain:@"VCOpenAI" code:(statusCode ?: -1)
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (NSDictionary *)_fallbackResponseFromRawData:(NSData *)data {
    if (data.length == 0) return @{};
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return @{};
    NSDictionary *errorObj = [json[@"error"] isKindOfClass:[NSDictionary class]] ? json[@"error"] : nil;
    if (errorObj.count > 0) return @{};

    NSString *content = _isResponsesAPI ? [self _contentFromResponsesJSON:json] : [self _contentFromChatJSON:json];
    NSArray *toolCalls = [self _toolCallsFromJSON:json];
    NSDictionary *usage = [json[@"usage"] isKindOfClass:[NSDictionary class]] ? json[@"usage"] : nil;
    if (usage && _onUsage) {
        NSUInteger inputTokens = [usage[@"prompt_tokens"] unsignedIntegerValue];
        if (inputTokens == 0) inputTokens = [usage[@"input_tokens"] unsignedIntegerValue];
        NSUInteger outputTokens = [usage[@"completion_tokens"] unsignedIntegerValue];
        if (outputTokens == 0) outputTokens = [usage[@"output_tokens"] unsignedIntegerValue];
        _onUsage(inputTokens, outputTokens);
    }
    if (content.length > 0 && _onChunk) {
        _onChunk(content);
    }

    NSMutableDictionary *fullResponse = [json mutableCopy];
    if (content.length > 0) {
        fullResponse[@"content"] = content;
    }
    if (toolCalls.count > 0) {
        fullResponse[@"tool_calls"] = toolCalls;
    }
    if (content.length == 0 && toolCalls.count == 0) {
        NSString *message = [json[@"message"] isKindOfClass:[NSString class]] ? json[@"message"] : @"The provider returned an empty response";
        fullResponse[@"message"] = message;
    }
    return fullResponse;
}

- (NSArray *)_toolCallsFromJSON:(NSDictionary *)json {
    if (_isResponsesAPI) {
        NSArray *output = [json[@"output"] isKindOfClass:[NSArray class]] ? json[@"output"] : nil;
        NSMutableArray *calls = [NSMutableArray array];
        for (NSDictionary *item in output) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            if ([item[@"type"] containsString:@"tool"] || [item[@"type"] containsString:@"function"]) {
                [calls addObject:item];
            }
        }
        return calls;
    }
    NSArray *choices = [json[@"choices"] isKindOfClass:[NSArray class]] ? json[@"choices"] : nil;
    NSDictionary *message = [choices.firstObject[@"message"] isKindOfClass:[NSDictionary class]] ? choices.firstObject[@"message"] : nil;
    NSArray *toolCalls = [message[@"tool_calls"] isKindOfClass:[NSArray class]] ? message[@"tool_calls"] : nil;
    return toolCalls ?: @[];
}

- (NSString *)_contentFromChatJSON:(NSDictionary *)json {
    NSArray *choices = [json[@"choices"] isKindOfClass:[NSArray class]] ? json[@"choices"] : nil;
    NSDictionary *message = [choices.firstObject[@"message"] isKindOfClass:[NSDictionary class]] ? choices.firstObject[@"message"] : nil;
    return [self _stringFromContentValue:message[@"content"]];
}

- (NSString *)_contentFromResponsesJSON:(NSDictionary *)json {
    NSString *topLevel = [json[@"output_text"] isKindOfClass:[NSString class]] ? json[@"output_text"] : nil;
    if (topLevel.length > 0) return topLevel;
    NSArray *output = [json[@"output"] isKindOfClass:[NSArray class]] ? json[@"output"] : nil;
    NSMutableString *content = [NSMutableString string];
    for (NSDictionary *item in output) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *text = [self _stringFromContentValue:item[@"content"]];
        if (text.length > 0) {
            if (content.length > 0) [content appendString:@"\n"];
            [content appendString:text];
        }
    }
    return content.copy;
}

- (NSString *)_stringFromContentValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (id entry in (NSArray *)value) {
            if ([entry isKindOfClass:[NSString class]]) {
                [parts addObject:entry];
                continue;
            }
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *dict = (NSDictionary *)entry;
            NSString *text = [dict[@"text"] isKindOfClass:[NSString class]] ? dict[@"text"] : nil;
            if (text.length == 0 && [dict[@"type"] isEqualToString:@"output_text"]) {
                text = [dict[@"text"] isKindOfClass:[NSString class]] ? dict[@"text"] : nil;
            }
            if (text.length == 0 && [dict[@"type"] isEqualToString:@"text"]) {
                text = [dict[@"value"] isKindOfClass:[NSString class]] ? dict[@"value"] : nil;
            }
            if (text.length > 0) {
                [parts addObject:text];
            }
        }
        return [parts componentsJoinedByString:@"\n"];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)value;
        NSString *text = [dict[@"text"] isKindOfClass:[NSString class]] ? dict[@"text"] : nil;
        if (text.length > 0) return text;
        NSString *valueText = [dict[@"value"] isKindOfClass:[NSString class]] ? dict[@"value"] : nil;
        if (valueText.length > 0) return valueText;
    }
    return @"";
}

- (NSInteger)_maxOutputTokensForModel:(NSString *)model {
    if (!model) return 8192;
    NSString *lower = model.lowercaseString;
    if ([lower containsString:@"minimax"]) return 196608;
    if ([lower containsString:@"haiku"]) return 4096;
    if ([lower containsString:@"claude"]) return 8192;
    if ([lower containsString:@"gpt-4"] || [lower containsString:@"o3"] || [lower containsString:@"o4"]) return 16384;
    if ([lower containsString:@"gemini"]) return 8192;
    if ([lower containsString:@"deepseek"]) return 8192;
    if ([lower containsString:@"kimi"] || [lower containsString:@"moonshot"]) return 8192;
    if ([lower containsString:@"doubao"]) return 8192;
    if ([lower containsString:@"qwen"]) return 8192;
    if ([lower containsString:@"grok"]) return 16384;
    return 8192;
}

- (void)_cleanup {
    _onChunk = nil;
    _onToolCall = nil;
    _onUsage = nil;
    _completion = nil;
    _task = nil;
    [_session finishTasksAndInvalidate];
    _session = nil;
    _responsesToolCallLookup = nil;
    _rawResponseData = nil;
    _responseMIMEType = nil;
    _httpStatusCode = 0;
}

@end
