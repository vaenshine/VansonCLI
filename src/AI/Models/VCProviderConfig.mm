/**
 * VCProviderConfig.mm -- Provider 配置模型实现
 */

#import "VCProviderConfig.h"
#import "../../../VansonCLI.h"

static NSString *VCSafeProviderString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value copy];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] copy];
    }
    return @"";
}

static NSString *VCTrimmedProviderString(id value) {
    return [VCSafeProviderString(value) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *VCStripWrappingCharacters(NSString *value) {
    NSString *result = VCTrimmedProviderString(value);
    while (result.length >= 2) {
        unichar first = [result characterAtIndex:0];
        unichar last = [result characterAtIndex:result.length - 1];
        BOOL matchingQuotes = ((first == '"' && last == '"') ||
                               (first == '\'' && last == '\'') ||
                               (first == '`' && last == '`'));
        if (!matchingQuotes) break;
        result = [result substringWithRange:NSMakeRange(1, result.length - 2)];
        result = VCTrimmedProviderString(result);
    }
    return result;
}

static NSString *VCNormalizedProviderAPIKey(id value) {
    NSString *raw = VCStripWrappingCharacters(value);
    if (raw.length == 0) return @"";

    NSString *lowerRaw = raw.lowercaseString;
    if ([lowerRaw hasPrefix:@"bearer "]) {
        raw = VCTrimmedProviderString([raw substringFromIndex:7]);
        raw = VCStripWrappingCharacters(raw);
    }

    NSError *regexError = nil;
    NSRegularExpression *structuredValueRegex =
        [NSRegularExpression regularExpressionWithPattern:@"[\"']?(?:OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY|API_KEY)[\"']?\\s*[:=]\\s*[\"']?([^\"'\\s,}\\]]+)"
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:&regexError];
    NSTextCheckingResult *structuredMatch = regexError ? nil : [structuredValueRegex firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
    if (structuredMatch.numberOfRanges > 1) {
        NSString *captured = [raw substringWithRange:[structuredMatch rangeAtIndex:1]];
        NSString *normalizedCapture = VCStripWrappingCharacters(captured);
        if (normalizedCapture.length > 0) return normalizedCapture;
    }

    NSRegularExpression *secretTokenRegex =
        [NSRegularExpression regularExpressionWithPattern:@"\\bsk-[A-Za-z0-9._-]+\\b"
                                                  options:0
                                                    error:&regexError];
    NSTextCheckingResult *tokenMatch = regexError ? nil : [secretTokenRegex firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
    if (tokenMatch.range.location != NSNotFound) {
        return [raw substringWithRange:tokenMatch.range];
    }

    return raw;
}

static NSArray<NSString *> *VCNormalizedProviderModels(id value) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSArray *source = nil;

    if ([value isKindOfClass:[NSArray class]]) {
        source = (NSArray *)value;
    } else if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
        NSString *raw = VCSafeProviderString(value);
        NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",\n\r"];
        source = [raw componentsSeparatedByCharactersInSet:separators];
    } else {
        source = @[];
    }

    for (id candidate in source) {
        NSString *model = VCTrimmedProviderString(candidate);
        if (model.length == 0) continue;
        NSString *lookupKey = model.lowercaseString;
        if ([seen containsObject:lookupKey]) continue;
        [seen addObject:lookupKey];
        [result addObject:model];
    }
    return result;
}

static VCAPIProtocol VCNormalizedProviderProtocol(id value) {
    NSInteger rawValue = VCAPIProtocolOpenAI;
    if ([value isKindOfClass:[NSNumber class]]) {
        rawValue = [(NSNumber *)value integerValue];
    } else if ([value isKindOfClass:[NSString class]]) {
        NSString *text = VCTrimmedProviderString(value).lowercaseString;
        if ([text isEqualToString:@"responses"] || [text containsString:@"response"]) {
            rawValue = VCAPIProtocolOpenAIResponses;
        } else if ([text containsString:@"anthropic"]) {
            rawValue = VCAPIProtocolAnthropic;
        } else if ([text containsString:@"gemini"]) {
            rawValue = VCAPIProtocolGemini;
        } else if ([text containsString:@"openai"]) {
            rawValue = VCAPIProtocolOpenAI;
        } else if (text.length > 0) {
            rawValue = [text integerValue];
        }
    }
    rawValue = MAX(VCAPIProtocolOpenAI, MIN(rawValue, VCAPIProtocolGemini));
    return (VCAPIProtocol)rawValue;
}

static NSString *VCNormalizedProviderAPIVersion(id value) {
    NSString *version = VCTrimmedProviderString(value);
    if (version.length == 0) return @"/v1";
    if (![version hasPrefix:@"/"]) version = [@"/" stringByAppendingString:version];
    while (version.length > 1 && [version hasSuffix:@"/"]) {
        version = [version substringToIndex:version.length - 1];
    }
    return version;
}

static NSInteger VCNormalizedProviderMaxTokens(id value) {
    NSInteger tokens = 0;
    if ([value respondsToSelector:@selector(integerValue)]) {
        tokens = [value integerValue];
    }
    return MAX(0, MIN(tokens, 1000000));
}

static NSString *VCNormalizedProviderReasoningEffort(id value) {
    NSString *effort = VCTrimmedProviderString(value).lowercaseString;
    if ([effort isEqualToString:@"low"] ||
        [effort isEqualToString:@"medium"] ||
        [effort isEqualToString:@"high"]) {
        return effort;
    }
    return @"off";
}

@implementation VCProviderConfig

+ (NSString *)normalizedAPIKeyString:(id)value {
    return VCNormalizedProviderAPIKey(value);
}

+ (NSString *)portableFileExtension {
    return @"vcmc";
}

+ (instancetype)configWithName:(NSString *)name
                      endpoint:(NSString *)endpoint
                      protocol:(VCAPIProtocol)protocol
                        models:(NSArray<NSString *> *)models {
    VCProviderConfig *config = [[VCProviderConfig alloc] init];
    NSArray<NSString *> *normalizedModels = VCNormalizedProviderModels(models);
    config.providerID = [[NSUUID UUID] UUIDString];
    config.name = VCTrimmedProviderString(name);
    config.endpoint = VCTrimmedProviderString(endpoint);
    config.apiVersion = @"/v1";
    config.protocol = VCNormalizedProviderProtocol(@(protocol));
    config.rolePreset = @"";
    config.models = normalizedModels;
    config.selectedModel = normalizedModels.firstObject ?: @"";
    config.maxTokens = 0;
    config.reasoningEffort = @"off";
    config.sortOrder = 0;
    config.isBuiltin = NO;
    return config;
}

- (void)setApiKey:(NSString *)apiKey {
    _apiKey = VCNormalizedProviderAPIKey(apiKey);
}

- (void)setApiVersion:(NSString *)apiVersion {
    _apiVersion = VCNormalizedProviderAPIVersion(apiVersion);
}

- (void)setReasoningEffort:(NSString *)reasoningEffort {
    _reasoningEffort = VCNormalizedProviderReasoningEffort(reasoningEffort);
}

- (void)setMaxTokens:(NSInteger)maxTokens {
    _maxTokens = VCNormalizedProviderMaxTokens(@(maxTokens));
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:VCSafeProviderString(_providerID) forKey:@"providerID"];
    [coder encodeObject:VCSafeProviderString(_name) forKey:@"name"];
    [coder encodeObject:VCSafeProviderString(_endpoint) forKey:@"endpoint"];
    [coder encodeObject:VCNormalizedProviderAPIVersion(_apiVersion) forKey:@"apiVersion"];
    [coder encodeObject:VCTrimmedProviderString(_apiKey) forKey:@"apiKey"];
    [coder encodeInteger:VCNormalizedProviderProtocol(@(_protocol)) forKey:@"protocol"];
    [coder encodeObject:VCTrimmedProviderString(_rolePreset) forKey:@"rolePreset"];
    [coder encodeObject:VCNormalizedProviderModels(_models) forKey:@"models"];
    [coder encodeObject:VCTrimmedProviderString(_selectedModel) forKey:@"selectedModel"];
    [coder encodeInteger:VCNormalizedProviderMaxTokens(@(_maxTokens)) forKey:@"maxTokens"];
    [coder encodeObject:VCNormalizedProviderReasoningEffort(_reasoningEffort) forKey:@"reasoningEffort"];
    [coder encodeInteger:_sortOrder forKey:@"sortOrder"];
    [coder encodeBool:_isBuiltin forKey:@"isBuiltin"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _providerID = VCSafeProviderString([coder decodeObjectForKey:@"providerID"]);
        if (_providerID.length == 0) _providerID = [[NSUUID UUID] UUIDString];
        _name = VCSafeProviderString([coder decodeObjectForKey:@"name"]);
        _endpoint = VCSafeProviderString([coder decodeObjectForKey:@"endpoint"]);
        _apiVersion = VCNormalizedProviderAPIVersion([coder decodeObjectForKey:@"apiVersion"]);
        _apiKey = VCTrimmedProviderString([coder decodeObjectForKey:@"apiKey"]);
        _protocol = VCNormalizedProviderProtocol(@([coder decodeIntegerForKey:@"protocol"]));
        _rolePreset = VCTrimmedProviderString([coder decodeObjectForKey:@"rolePreset"]);
        _models = VCNormalizedProviderModels([coder decodeObjectForKey:@"models"]);
        _selectedModel = VCTrimmedProviderString([coder decodeObjectForKey:@"selectedModel"]);
        _maxTokens = VCNormalizedProviderMaxTokens(@([coder decodeIntegerForKey:@"maxTokens"]));
        _reasoningEffort = VCNormalizedProviderReasoningEffort([coder decodeObjectForKey:@"reasoningEffort"]);
        _sortOrder = [coder decodeIntegerForKey:@"sortOrder"];
        _isBuiltin = [coder decodeBoolForKey:@"isBuiltin"];
        if (_selectedModel.length > 0 && ![_models containsObject:_selectedModel]) {
            _selectedModel = @"";
        }
        if (_selectedModel.length == 0 && _models.count > 0) {
            _selectedModel = _models.firstObject;
        }
    }
    return self;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    VCProviderConfig *copy = [[VCProviderConfig alloc] init];
    copy.providerID = VCSafeProviderString(_providerID);
    copy.name = VCSafeProviderString(_name);
    copy.endpoint = VCSafeProviderString(_endpoint);
    copy.apiVersion = VCNormalizedProviderAPIVersion(_apiVersion);
    copy.apiKey = VCTrimmedProviderString(_apiKey);
    copy.protocol = VCNormalizedProviderProtocol(@(_protocol));
    copy.rolePreset = VCTrimmedProviderString(_rolePreset);
    copy.models = VCNormalizedProviderModels(_models);
    copy.selectedModel = VCTrimmedProviderString(_selectedModel);
    copy.maxTokens = VCNormalizedProviderMaxTokens(@(_maxTokens));
    copy.reasoningEffort = VCNormalizedProviderReasoningEffort(_reasoningEffort);
    copy.sortOrder = _sortOrder;
    copy.isBuiltin = _isBuiltin;
    if (copy.selectedModel.length > 0 && ![copy.models containsObject:copy.selectedModel]) {
        copy.selectedModel = @"";
    }
    if (copy.selectedModel.length == 0 && copy.models.count > 0) {
        copy.selectedModel = copy.models.firstObject;
    }
    return copy;
}

#pragma mark - Serialization

- (NSDictionary *)toDictionary {
    NSArray<NSString *> *models = VCNormalizedProviderModels(_models);
    NSString *selectedModel = VCTrimmedProviderString(_selectedModel);
    if (selectedModel.length > 0 && ![models containsObject:selectedModel]) {
        selectedModel = @"";
    }
    if (selectedModel.length == 0 && models.count > 0) {
        selectedModel = models.firstObject;
    }
    return @{
        @"providerID": VCSafeProviderString(_providerID).length > 0 ? VCSafeProviderString(_providerID) : [[NSUUID UUID] UUIDString],
        @"name": VCSafeProviderString(_name),
        @"endpoint": VCSafeProviderString(_endpoint),
        @"apiVersion": VCNormalizedProviderAPIVersion(_apiVersion),
        @"apiKey": VCTrimmedProviderString(_apiKey),
        @"protocol": @(VCNormalizedProviderProtocol(@(_protocol))),
        @"rolePreset": VCTrimmedProviderString(_rolePreset),
        @"models": models,
        @"selectedModel": selectedModel,
        @"maxTokens": @(VCNormalizedProviderMaxTokens(@(_maxTokens))),
        @"reasoningEffort": VCNormalizedProviderReasoningEffort(_reasoningEffort),
        @"sortOrder": @(_sortOrder),
        @"isBuiltin": @(_isBuiltin),
    };
}

- (NSDictionary *)portableExportDictionary {
    NSMutableDictionary *provider = [[self toDictionary] mutableCopy];
    provider[@"sortOrder"] = @0;
    return @{
        @"format": @"vcmc",
        @"version": @1,
        @"exportedAt": @([[NSDate date] timeIntervalSince1970]),
        @"provider": provider ?: @{},
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    VCProviderConfig *config = [[VCProviderConfig alloc] init];
    config.providerID = VCSafeProviderString(dict[@"providerID"]);
    if (config.providerID.length == 0) config.providerID = [[NSUUID UUID] UUIDString];
    config.name = VCSafeProviderString(dict[@"name"]);
    config.endpoint = VCSafeProviderString(dict[@"endpoint"]);
    config.apiVersion = VCNormalizedProviderAPIVersion(dict[@"apiVersion"]);
    config.apiKey = VCTrimmedProviderString(dict[@"apiKey"]);
    config.protocol = VCNormalizedProviderProtocol(dict[@"protocol"]);
    config.rolePreset = VCTrimmedProviderString(dict[@"rolePreset"]);
    config.models = VCNormalizedProviderModels(dict[@"models"]);
    config.selectedModel = VCTrimmedProviderString(dict[@"selectedModel"]);
    if (config.selectedModel.length > 0 && ![config.models containsObject:config.selectedModel]) {
        config.selectedModel = @"";
    }
    if (config.selectedModel.length == 0 && config.models.count > 0) {
        config.selectedModel = config.models.firstObject;
    }
    config.maxTokens = VCNormalizedProviderMaxTokens(dict[@"maxTokens"]);
    config.reasoningEffort = VCNormalizedProviderReasoningEffort(dict[@"reasoningEffort"]);
    config.sortOrder = [dict[@"sortOrder"] respondsToSelector:@selector(integerValue)] ? [dict[@"sortOrder"] integerValue] : 0;
    config.isBuiltin = [dict[@"isBuiltin"] respondsToSelector:@selector(boolValue)] ? [dict[@"isBuiltin"] boolValue] : NO;
    return config;
}

+ (instancetype)fromPortableImportDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;

    NSDictionary *providerDict = dict;
    NSString *format = VCTrimmedProviderString(dict[@"format"]).lowercaseString;
    if (format.length > 0 || [dict[@"provider"] isKindOfClass:[NSDictionary class]]) {
        providerDict = [dict[@"provider"] isKindOfClass:[NSDictionary class]] ? dict[@"provider"] : nil;
    }
    if (![providerDict isKindOfClass:[NSDictionary class]]) return nil;

    VCProviderConfig *config = [self fromDictionary:providerDict];
    if (!config) return nil;
    config.sortOrder = 0;
    return config;
}

@end
