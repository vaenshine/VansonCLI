/**
 * VCNetRecord.mm -- 网络请求记录数据模型
 */

#import "VCNetRecord.h"

#pragma mark - VCNetRecord

@implementation VCNetRecord

- (instancetype)init {
    if (self = [super init]) {
        _requestID = [[NSUUID UUID] UUIDString];
        _startTime = [[NSProcessInfo processInfo] systemUptime];
    }
    return self;
}

#pragma mark - Body Helpers

static NSString *_bodyToString(NSData *data) {
    if (!data || data.length == 0) return @"(empty)";

    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!str) {
        return [NSString stringWithFormat:@"(binary %lu bytes)", (unsigned long)data.length];
    }

    // 尝试 JSON 格式化
    NSError *err = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (json && !err) {
        NSData *pretty = [NSJSONSerialization dataWithJSONObject:json
                                                        options:NSJSONWritingPrettyPrinted
                                                          error:nil];
        if (pretty) {
            return [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding] ?: str;
        }
    }
    return str;
}

- (NSString *)requestBodyAsString {
    return _bodyToString(_requestBody);
}

- (NSString *)responseBodyAsString {
    return _bodyToString(_responseBody);
}

#pragma mark - cURL Export

- (NSString *)curlCommand {
    NSMutableString *curl = [NSMutableString stringWithFormat:@"curl -X %@", _method ?: @"GET"];

    // Headers
    [_requestHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *val, BOOL *stop) {
        NSString *escaped = [val stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
        [curl appendFormat:@" \\\n  -H '%@: %@'", key, escaped];
    }];

    // Body
    if (_requestBody && _requestBody.length > 0) {
        NSString *bodyStr = [[NSString alloc] initWithData:_requestBody encoding:NSUTF8StringEncoding];
        if (bodyStr) {
            NSString *escaped = [bodyStr stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
            [curl appendFormat:@" \\\n  -d '%@'", escaped];
        } else {
            [curl appendFormat:@" \\\n  --data-binary @- # (%lu bytes binary)", (unsigned long)_requestBody.length];
        }
    }

    // URL
    NSString *escapedURL = [_url stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    [curl appendFormat:@" \\\n  '%@'", escapedURL ?: @""];

    return [curl copy];
}

@end

#pragma mark - VCWebSocketFrame

@implementation VCWebSocketFrame

- (instancetype)init {
    if (self = [super init]) {
        _frameID = [[NSUUID UUID] UUIDString];
        _timestamp = [[NSProcessInfo processInfo] systemUptime];
    }
    return self;
}

@end
