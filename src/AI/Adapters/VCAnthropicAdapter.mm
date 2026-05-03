/**
 * VCAnthropicAdapter.mm -- Anthropic Claude API
 * SSE event types: message_start, content_block_start/delta, message_delta, message_stop
 */

#import "VCAnthropicAdapter.h"
#import "../Models/VCProviderConfig.h"
#import "../../../VansonCLI.h"

@implementation VCAnthropicAdapter {
    NSURLSessionDataTask *_task;
    NSURLSession *_session;
    NSMutableData *_buffer;
    void (^_onChunk)(NSString *);
    void (^_onToolCall)(NSDictionary *);
    void (^_onUsage)(NSUInteger, NSUInteger);
    void (^_completion)(NSDictionary *, NSError *);
    NSMutableString *_fullContent;
    NSMutableArray *_contentBlocks;
    NSMutableDictionary *_fullResponse;
    NSString *_currentEventType;
    // Tool use accumulation
    NSMutableDictionary *_currentToolUse;
    NSMutableString *_toolUseJSON;
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
    _contentBlocks = [NSMutableArray new];
    _fullResponse = [NSMutableDictionary new];
    _buffer = [NSMutableData new];
    _currentEventType = nil;
    _currentToolUse = nil;
    _toolUseJSON = nil;

    // Separate system message from messages
    NSString *systemPrompt = nil;
    NSMutableArray *apiMessages = [NSMutableArray new];
    for (NSDictionary *msg in messages) {
        if ([msg[@"role"] isEqualToString:@"system"]) {
            systemPrompt = msg[@"content"];
        } else {
            [apiMessages addObject:msg];
        }
    }

    // Build URL
    NSString *urlStr = [NSString stringWithFormat:@"%@/v1/messages", config.endpoint];
    NSURL *url = [NSURL URLWithString:urlStr];

    // Build body
    NSMutableDictionary *body = [NSMutableDictionary new];
    body[@"model"] = config.selectedModel;
    body[@"messages"] = apiMessages;
    body[@"max_tokens"] = @([self _maxOutputTokens:config.selectedModel]);
    body[@"stream"] = @(streaming);
    if (systemPrompt) body[@"system"] = systemPrompt;
    if (tools.count > 0) {
        NSMutableArray *anthropicTools = [NSMutableArray new];
        for (NSDictionary *tool in tools) {
            NSString *name = [tool[@"name"] isKindOfClass:[NSString class]] ? tool[@"name"] : nil;
            NSDictionary *parameters = [tool[@"parameters"] isKindOfClass:[NSDictionary class]] ? tool[@"parameters"] : nil;
            if (!name.length || parameters.count == 0) continue;
            [anthropicTools addObject:@{
                @"name": name,
                @"description": [tool[@"description"] isKindOfClass:[NSString class]] ? tool[@"description"] : @"",
                @"input_schema": parameters
            }];
        }
        if (anthropicTools.count > 0) body[@"tools"] = anthropicTools;
    }

    NSData *jsonBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    // Build request
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = jsonBody;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:config.apiKey forHTTPHeaderField:@"x-api-key"];
    [req setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
    [req setValue:kVCInternalRequestAIValue forHTTPHeaderField:kVCInternalRequestHeader];
    req.timeoutInterval = 120;

    if (streaming) {
        NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        _session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:nil];
        _task = [_session dataTaskWithRequest:req];
        [_task resume];
    } else {
        _task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
            if (error) { if (completion) completion(nil, error); return; }
            [self _handleNonStreamingResponse:data];
        }];
        [_task resume];
    }
}

- (void)fetchModelsWithConfig:(VCProviderConfig *)config
                   completion:(void(^)(NSArray<NSString *> *, NSError *))completion {
    // Anthropic doesn't have a public models endpoint; return known models
    if (completion) completion(@[@"claude-sonnet-4-20250514", @"claude-haiku-4-20250414"], nil);
}

- (void)cancel {
    [_task cancel];
    _task = nil;
    [_session invalidateAndCancel];
    _session = nil;
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    [_buffer appendData:data];
    [self _processSSEBuffer];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
    if (error && error.code != NSURLErrorCancelled) {
        if (_completion) _completion(nil, error);
    } else {
        _fullResponse[@"content"] = [_fullContent copy];
        _fullResponse[@"content_blocks"] = [_contentBlocks copy];
        if (_completion) _completion(_fullResponse, nil);
    }
    [self _cleanup];
}

#pragma mark - SSE Parsing

- (void)_processSSEBuffer {
    NSString *str = [[NSString alloc] initWithData:_buffer encoding:NSUTF8StringEncoding];
    if (!str) return;

    NSArray *chunks = [str componentsSeparatedByString:@"\n\n"];
    if (chunks.count <= 1) return;

    NSString *remainder = chunks.lastObject;
    _buffer = [[remainder dataUsingEncoding:NSUTF8StringEncoding] mutableCopy] ?: [NSMutableData new];

    for (NSUInteger i = 0; i < chunks.count - 1; i++) {
        [self _parseSSEEvent:chunks[i]];
    }
}

- (void)_parseSSEEvent:(NSString *)event {
    NSArray *lines = [event componentsSeparatedByString:@"\n"];
    NSString *eventType = nil;
    NSString *dataStr = nil;

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"event: "]) {
            eventType = [trimmed substringFromIndex:7];
        } else if ([trimmed hasPrefix:@"data: "]) {
            dataStr = [trimmed substringFromIndex:6];
        }
    }

    if (eventType) _currentEventType = eventType;
    if (!dataStr) return;

    NSData *jsonData = [dataStr dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    if (!json) return;

    if ([_currentEventType isEqualToString:@"message_start"]) {
        NSDictionary *usage = json[@"message"][@"usage"];
        if (usage && _onUsage) {
            _onUsage([usage[@"input_tokens"] unsignedIntegerValue], 0);
        }
    } else if ([_currentEventType isEqualToString:@"content_block_start"]) {
        NSDictionary *block = json[@"content_block"];
        NSString *type = block[@"type"];
        if ([type isEqualToString:@"tool_use"]) {
            _currentToolUse = [NSMutableDictionary new];
            _currentToolUse[@"id"] = block[@"id"];
            _currentToolUse[@"name"] = block[@"name"];
            _toolUseJSON = [NSMutableString new];
        }
    } else if ([_currentEventType isEqualToString:@"content_block_delta"]) {
        NSDictionary *delta = json[@"delta"];
        NSString *type = delta[@"type"];
        if ([type isEqualToString:@"text_delta"]) {
            NSString *text = delta[@"text"];
            if (text.length) {
                [_fullContent appendString:text];
                if (_onChunk) _onChunk(text);
            }
        } else if ([type isEqualToString:@"input_json_delta"]) {
            NSString *partial = delta[@"partial_json"];
            if (partial.length && _toolUseJSON) {
                [_toolUseJSON appendString:partial];
            }
        }
    } else if ([_currentEventType isEqualToString:@"content_block_stop"]) {
        if (_currentToolUse && _toolUseJSON.length) {
            NSData *d = [_toolUseJSON dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *input = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            _currentToolUse[@"input"] = input ?: @{};
            if (_onToolCall) _onToolCall([_currentToolUse copy]);
            [_contentBlocks addObject:[_currentToolUse copy]];
            _currentToolUse = nil;
            _toolUseJSON = nil;
        }
    } else if ([_currentEventType isEqualToString:@"message_delta"]) {
        NSDictionary *usage = json[@"usage"];
        if (usage && _onUsage) {
            _onUsage(0, [usage[@"output_tokens"] unsignedIntegerValue]);
        }
    }
}

#pragma mark - Non-Streaming

- (void)_handleNonStreamingResponse:(NSData *)data {
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!json) {
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (_completion) _completion(nil, [NSError errorWithDomain:@"VCAnthropic" code:-1
            userInfo:@{NSLocalizedDescriptionKey: raw ?: @"Invalid response"}]);
        return;
    }

    NSDictionary *errorObj = json[@"error"];
    if (errorObj) {
        if (_completion) _completion(json, [NSError errorWithDomain:@"VCAnthropic" code:-1
            userInfo:@{NSLocalizedDescriptionKey: errorObj[@"message"] ?: @"API error"}]);
        return;
    }

    // Parse content blocks
    NSArray *content = json[@"content"];
    for (NSDictionary *block in content) {
        if ([block[@"type"] isEqualToString:@"text"]) {
            NSString *text = block[@"text"];
            if (text.length) {
                [_fullContent appendString:text];
                if (_onChunk) _onChunk(text);
            }
        } else if ([block[@"type"] isEqualToString:@"tool_use"]) {
            if (_onToolCall) _onToolCall(block);
        }
    }

    NSDictionary *usage = json[@"usage"];
    if (usage && _onUsage) {
        _onUsage([usage[@"input_tokens"] unsignedIntegerValue],
                 [usage[@"output_tokens"] unsignedIntegerValue]);
    }

    if (_completion) _completion(json, nil);
}

#pragma mark - Helpers

- (NSInteger)_maxOutputTokens:(NSString *)model {
    if (!model) return 8192;
    NSString *lower = model.lowercaseString;
    if ([lower containsString:@"haiku"]) return 4096;
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
}

@end
