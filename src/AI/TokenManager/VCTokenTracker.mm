/**
 * VCTokenTracker.mm -- Token 追踪实现
 */

#import "VCTokenTracker.h"
#import "../../../VansonCLI.h"

@implementation VCTokenTracker

+ (instancetype)shared {
    static VCTokenTracker *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCTokenTracker alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _maxTokens = 128000; // default
    }
    return self;
}

- (NSUInteger)usagePercent {
    if (_maxTokens == 0) return 0;
    NSUInteger total = _inputTokens + _outputTokens;
    return MIN(100, (total * 100) / _maxTokens);
}

- (void)updateForModel:(NSString *)modelName {
    if (!modelName) return;
    NSString *lower = modelName.lowercaseString;

    if ([lower containsString:@"claude"] || [lower containsString:@"opus"] ||
        [lower containsString:@"sonnet"] || [lower containsString:@"haiku"]) {
        _maxTokens = 200000;
    } else if ([lower containsString:@"gpt-4o"]) {
        _maxTokens = 128000;
    } else if ([lower containsString:@"gemini"]) {
        _maxTokens = 1000000;
    } else if ([lower containsString:@"deepseek"]) {
        _maxTokens = 128000;
    } else if ([lower containsString:@"minimax"]) {
        _maxTokens = 1000000;
    } else if ([lower containsString:@"kimi"] || [lower containsString:@"moonshot"]) {
        _maxTokens = 128000;
    } else if ([lower containsString:@"doubao"]) {
        _maxTokens = [lower containsString:@"256k"] ? 256000 : 32000;
    } else if ([lower containsString:@"qwen"]) {
        _maxTokens = 131072;
    } else if ([lower containsString:@"grok"]) {
        _maxTokens = 131072;
    } else {
        _maxTokens = 128000;
    }

    VCLog(@"TokenTracker: model=%@, maxTokens=%lu", modelName, (unsigned long)_maxTokens);
}

- (BOOL)shouldCompactWithMessageCount:(NSUInteger)messageCount {
    return self.usagePercent > 90 && messageCount > 6;
}

- (void)addUsage:(NSUInteger)input output:(NSUInteger)output {
    _inputTokens += input;
    _outputTokens += output;
    if (input > 0) _contextTokens = input; // Latest API input_tokens
}

- (void)reset {
    _inputTokens = 0;
    _outputTokens = 0;
    _contextTokens = 0;
}

@end
