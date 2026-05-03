/**
 * VCGeminiAdapter.mm -- Google Gemini API
 * NDJSON streaming: each line is a complete JSON object
 * Note: Gemini uses "user"/"model" roles (not "assistant")
 */

#import "VCGeminiAdapter.h"
#import "../Models/VCProviderConfig.h"
#import "../../../VansonCLI.h"

@implementation VCGeminiAdapter {
    NSURLSessionDataTask *_task;
    NSURLSession *_session;
    NSMutableData *_buffer;
    void (^_onChunk)(NSString *);
    void (^_onToolCall)(NSDictionary *);
    void (^_onUsage)(NSUInteger, NSUInteger);
    void (^_completion)(NSDictionary *, NSError *);
    NSMutableString *_fullContent;
    NSMutableDictionary *_fullResponse;
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
    _fullResponse = [NSMutableDictionary new];
    _buffer = [NSMutableData new];

    // Convert messages to Gemini format
    NSString *systemInstruction = nil;
    NSMutableArray *contents = [NSMutableArray new];
    for (NSDictionary *msg in messages) {
        NSString *role = msg[@"role"];
        NSString *content = msg[@"content"];
        if ([role isEqualToString:@"system"]) {
            systemInstruction = content;
            continue;
        }
        // Gemini uses "model" instead of "assistant"
        NSString *geminiRole = [role isEqualToString:@"assistant"] ? @"model" : @"user";
        [contents addObject:@{
            @"role": geminiRole,
            @"parts": @[@{@"text": content ?: @""}]
        }];
    }

    // Build URL
    NSString *method = streaming ? @"streamGenerateContent" : @"generateContent";
    NSString *urlStr = [NSString stringWithFormat:@"%@/v1beta/models/%@:%@?key=%@",
        config.endpoint, config.selectedModel, method, config.apiKey];
    NSURL *url = [NSURL URLWithString:urlStr];

    // Build body
    NSMutableDictionary *body = [NSMutableDictionary new];
    body[@"contents"] = contents;
    if (systemInstruction) {
        body[@"systemInstruction"] = @{
            @"parts": @[@{@"text": systemInstruction}]
        };
    }
    if (tools.count > 0) {
        NSMutableArray *declarations = [NSMutableArray new];
        for (NSDictionary *tool in tools) {
            NSString *name = [tool[@"name"] isKindOfClass:[NSString class]] ? tool[@"name"] : nil;
            NSDictionary *parameters = [tool[@"parameters"] isKindOfClass:[NSDictionary class]] ? tool[@"parameters"] : nil;
            if (!name.length || parameters.count == 0) continue;
            [declarations addObject:@{
                @"name": name,
                @"description": [tool[@"description"] isKindOfClass:[NSString class]] ? tool[@"description"] : @"",
                @"parameters": parameters
            }];
        }
        if (declarations.count > 0) {
            body[@"tools"] = @[@{@"functionDeclarations": declarations}];
        }
    }

    NSData *jsonBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = jsonBody;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
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
    NSString *urlStr = [NSString stringWithFormat:@"%@/v1beta/models?key=%@",
        config.endpoint, config.apiKey];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [req setValue:kVCInternalRequestAIValue forHTTPHeaderField:kVCInternalRequestHeader];
    req.timeoutInterval = 30;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *modelsArr = json[@"models"];
        NSMutableArray *names = [NSMutableArray new];
        for (NSDictionary *m in modelsArr) {
            NSString *name = m[@"name"]; // "models/gemini-2.5-flash"
            if (name) {
                NSString *shortName = [name lastPathComponent];
                [names addObject:shortName];
            }
        }
        if (completion) completion(names, nil);
    }];
    [task resume];
}

- (void)cancel {
    [_task cancel];
    _task = nil;
    [_session invalidateAndCancel];
    _session = nil;
}

#pragma mark - NSURLSessionDataDelegate (NDJSON Streaming)

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    [_buffer appendData:data];
    [self _processNDJSONBuffer];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
    // Process any remaining buffer
    [self _processNDJSONBuffer];

    if (error && error.code != NSURLErrorCancelled) {
        if (_completion) _completion(nil, error);
    } else {
        _fullResponse[@"content"] = [_fullContent copy];
        if (_completion) _completion(_fullResponse, nil);
    }
    [self _cleanup];
}

#pragma mark - NDJSON Parsing

- (void)_processNDJSONBuffer {
    NSString *str = [[NSString alloc] initWithData:_buffer encoding:NSUTF8StringEncoding];
    if (!str) return;

    // Gemini streaming returns a JSON array with chunks separated by newlines
    // Each chunk may start with [ or , and end with ] or newline
    // We need to handle: [{...}\n,{...}\n,{...}]
    NSArray *lines = [str componentsSeparatedByString:@"\n"];
    NSMutableString *remainder = [NSMutableString new];
    BOOL hasRemainder = NO;

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;

        // Strip leading [ or , and trailing ] or ,
        NSString *cleaned = trimmed;
        if ([cleaned hasPrefix:@"["]) cleaned = [cleaned substringFromIndex:1];
        if ([cleaned hasPrefix:@","]) cleaned = [cleaned substringFromIndex:1];
        if ([cleaned hasSuffix:@"]"]) cleaned = [cleaned substringToIndex:cleaned.length - 1];
        if ([cleaned hasSuffix:@","]) cleaned = [cleaned substringToIndex:cleaned.length - 1];
        cleaned = [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (cleaned.length == 0) continue;

        NSData *jsonData = [cleaned dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if (json) {
            [self _parseGeminiChunk:json];
        } else {
            // Incomplete JSON, keep as remainder
            [remainder appendString:line];
            [remainder appendString:@"\n"];
            hasRemainder = YES;
        }
    }

    if (hasRemainder) {
        _buffer = [[remainder dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    } else {
        _buffer = [NSMutableData new];
    }
}

- (void)_parseGeminiChunk:(NSDictionary *)json {
    // Check for error
    NSDictionary *errorObj = json[@"error"];
    if (errorObj) {
        VCLog(@"Gemini error: %@", errorObj[@"message"]);
        return;
    }

    // candidates[0].content.parts
    NSArray *candidates = json[@"candidates"];
    NSDictionary *content = [candidates.firstObject objectForKey:@"content"];
    NSArray *parts = content[@"parts"];

    for (NSDictionary *part in parts) {
        NSString *text = part[@"text"];
        if (text.length) {
            [_fullContent appendString:text];
            if (_onChunk) _onChunk(text);
        }
        NSDictionary *functionCall = part[@"functionCall"];
        if (functionCall && _onToolCall) {
            _onToolCall(functionCall);
        }
    }

    // Usage metadata
    NSDictionary *usageMeta = json[@"usageMetadata"];
    if (usageMeta && _onUsage) {
        _onUsage([usageMeta[@"promptTokenCount"] unsignedIntegerValue],
                 [usageMeta[@"candidatesTokenCount"] unsignedIntegerValue]);
    }
}

#pragma mark - Non-Streaming

- (void)_handleNonStreamingResponse:(NSData *)data {
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!json) {
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (_completion) _completion(nil, [NSError errorWithDomain:@"VCGemini" code:-1
            userInfo:@{NSLocalizedDescriptionKey: raw ?: @"Invalid response"}]);
        return;
    }

    NSDictionary *errorObj = json[@"error"];
    if (errorObj) {
        if (_completion) _completion(json, [NSError errorWithDomain:@"VCGemini" code:-1
            userInfo:@{NSLocalizedDescriptionKey: errorObj[@"message"] ?: @"API error"}]);
        return;
    }

    [self _parseGeminiChunk:json];
    _fullResponse[@"content"] = [_fullContent copy];
    if (_completion) _completion(json, nil);
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
