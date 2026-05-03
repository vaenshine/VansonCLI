/**
 * VCProviderManager.mm -- Provider CRUD + 持久化实现
 */

#import "VCProviderManager.h"
#import "../Adapters/VCAIAdapter.h"
#import "../../../VansonCLI.h"
#import "../../Core/VCCore.hpp"
#import "../../Core/VCConfig.h"
#import "../../Core/VCCrypto.h"

static NSString *const kVCProvidersKey = @"com.vanson.cli.providers";
static NSString *const kVCActiveProviderKey = @"com.vanson.cli.activeProvider";
NSNotificationName const VCProviderManagerDidChangeNotification = @"VCProviderManagerDidChangeNotification";

static NSString *VCSafeManagerString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value copy];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] copy];
    }
    return @"";
}

@implementation VCProviderManager {
    NSMutableArray<VCProviderConfig *> *_providers;
    NSString *_activeProviderID;
    NSData *_encryptionKey;
}

+ (instancetype)shared {
    static VCProviderManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCProviderManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _providers = [NSMutableArray new];
        [self _initEncryptionKey];
        [self load];
        if (_providers.count == 0) {
            [self _setupBuiltinProviders];
        }
    }
    return self;
}

#pragma mark - Encryption Key

- (void)_initEncryptionKey {
    // Derive a stable key from device info for API key encryption
    NSString *seed = [NSString stringWithFormat:@"vc.ai.%@",
        [UIDevice currentDevice].identifierForVendor.UUIDString ?: @"default"];
    NSData *seedData = [seed dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hmacKey = [@"VansonCLI-AI-KeyStore" dataUsingEncoding:NSUTF8StringEncoding];
    _encryptionKey = [VCCrypto hmacSHA256:seedData withKey:hmacKey];
}

#pragma mark - Builtin Providers

- (void)_setupBuiltinProviders {
    NSArray *builtins = @[
        @{@"name": @"OpenAI",
          @"endpoint": @"https://api.openai.com",
          @"protocol": @(VCAPIProtocolOpenAI),
          @"models": @[@"gpt-4o", @"gpt-4o-mini", @"o3-mini", @"o4-mini"]},
        @{@"name": @"Anthropic",
          @"endpoint": @"https://api.anthropic.com",
          @"protocol": @(VCAPIProtocolAnthropic),
          @"models": @[@"claude-sonnet-4-20250514", @"claude-opus-4-20250514", @"claude-haiku-4-20250414"]},
        @{@"name": @"DeepSeek",
          @"endpoint": @"https://api.deepseek.com",
          @"protocol": @(VCAPIProtocolOpenAI),
          @"models": @[@"deepseek-chat", @"deepseek-reasoner"]},
        @{@"name": @"Gemini",
          @"endpoint": @"https://generativelanguage.googleapis.com",
          @"protocol": @(VCAPIProtocolGemini),
          @"models": @[@"gemini-2.5-flash", @"gemini-2.5-pro"]},
        @{@"name": @"MiniMax",
          @"endpoint": @"https://api.minimaxi.com/anthropic/v1/messages",
          @"protocol": @(VCAPIProtocolAnthropic),
          @"models": @[@"MiniMax-M2.7", @"MiniMax-M1", @"MiniMax-T1"]},
        @{@"name": @"Kimi (Moonshot)",
          @"endpoint": @"https://api.moonshot.cn",
          @"protocol": @(VCAPIProtocolOpenAI),
          @"models": @[@"moonshot-v1-128k", @"moonshot-v1-32k", @"moonshot-v1-8k"]},
        @{@"name": @"Doubao (ByteDance)",
          @"endpoint": @"https://ark.cn-beijing.volces.com/api",
          @"protocol": @(VCAPIProtocolOpenAI),
          @"models": @[@"doubao-1.5-pro-256k", @"doubao-1.5-pro-32k", @"doubao-1.5-lite-32k"]},
        @{@"name": @"Qwen (Alibaba)",
          @"endpoint": @"https://dashscope.aliyuncs.com/compatible-mode",
          @"protocol": @(VCAPIProtocolOpenAI),
          @"models": @[@"qwen-max", @"qwen-plus", @"qwen-turbo"]},
        @{@"name": @"Grok (xAI)",
          @"endpoint": @"https://api.x.ai",
          @"protocol": @(VCAPIProtocolOpenAI),
          @"models": @[@"grok-3", @"grok-3-mini"]},
    ];

    for (NSInteger i = 0; i < builtins.count; i++) {
        NSDictionary *info = builtins[i];
        VCProviderConfig *p = [VCProviderConfig configWithName:info[@"name"]
                                                      endpoint:info[@"endpoint"]
                                                      protocol:(VCAPIProtocol)[info[@"protocol"] integerValue]
                                                        models:info[@"models"]];
        p.sortOrder = i;
        p.isBuiltin = YES;
        [_providers addObject:p];
    }
    _activeProviderID = _providers.firstObject.providerID;
    [self save];
}

#pragma mark - CRUD

- (void)addProvider:(VCProviderConfig *)provider {
    if (!provider) return;
    provider = [VCProviderConfig fromDictionary:[provider toDictionary]];
    if (!provider) return;
    if (!provider.providerID) provider.providerID = [[NSUUID UUID] UUIDString];
    provider.sortOrder = (NSInteger)_providers.count;
    [_providers addObject:provider];
    [self save];
    [self _notifyProviderChange];
}

- (void)updateProvider:(VCProviderConfig *)provider {
    if (!provider) return;
    provider = [VCProviderConfig fromDictionary:[provider toDictionary]];
    if (!provider) return;
    for (NSUInteger i = 0; i < _providers.count; i++) {
        if ([_providers[i].providerID isEqualToString:provider.providerID]) {
            _providers[i] = provider;
            [self save];
            [self _notifyProviderChange];
            return;
        }
    }
}

- (void)removeProvider:(NSString *)providerID {
    VCProviderConfig *p = [self providerForID:providerID];
    if (!p || p.isBuiltin) return; // builtin 不可删除
    [_providers removeObject:p];
    if ([_activeProviderID isEqualToString:providerID]) {
        _activeProviderID = _providers.firstObject.providerID;
    }
    [self save];
    [self _notifyProviderChange];
}

- (VCProviderConfig *)providerForID:(NSString *)providerID {
    for (VCProviderConfig *p in _providers) {
        if ([p.providerID isEqualToString:providerID]) return p;
    }
    return nil;
}

#pragma mark - List & Active

- (NSArray<VCProviderConfig *> *)allProviders {
    return [_providers sortedArrayUsingComparator:^NSComparisonResult(VCProviderConfig *a, VCProviderConfig *b) {
        if (a.sortOrder == b.sortOrder) return NSOrderedSame;
        return a.sortOrder < b.sortOrder ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (VCProviderConfig *)activeProvider {
    VCProviderConfig *p = [self providerForID:_activeProviderID];
    return p ?: _providers.firstObject;
}

- (NSString *)effectiveSelectedModelForProvider:(VCProviderConfig *)provider {
    if (!provider) return @"";
    NSString *selected = [VCSafeManagerString(provider.selectedModel) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (selected.length > 0) return selected;
    NSArray *models = [provider.models isKindOfClass:[NSArray class]] ? provider.models : @[];
    for (id candidate in models) {
        if (![candidate isKindOfClass:[NSString class]]) continue;
        NSString *trimmed = [(NSString *)candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) return trimmed;
    }
    return @"";
}

- (void)setActiveProviderID:(NSString *)providerID {
    _activeProviderID = VCSafeManagerString(providerID);
    [[NSUserDefaults standardUserDefaults] setObject:_activeProviderID forKey:kVCActiveProviderKey];
    [self _notifyProviderChange];
}

#pragma mark - Sort

- (void)moveProvider:(NSString *)providerID toIndex:(NSInteger)index {
    VCProviderConfig *p = [self providerForID:providerID];
    if (!p) return;
    [_providers removeObject:p];
    if (index >= (NSInteger)_providers.count) [_providers addObject:p];
    else [_providers insertObject:p atIndex:MAX(0, index)];
    for (NSInteger i = 0; i < (NSInteger)_providers.count; i++) {
        _providers[i].sortOrder = i;
    }
    [self save];
    [self _notifyProviderChange];
}

#pragma mark - Fetch Models

- (void)fetchModelsForProvider:(NSString *)providerID
                    completion:(void(^)(NSArray<NSString *> *, NSError *))completion {
    VCProviderConfig *config = [self providerForID:providerID];
    NSString *apiKey = VCSafeManagerString(config.apiKey);
    if (!config || apiKey.length == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"VCProvider"
            code:-1 userInfo:@{NSLocalizedDescriptionKey: @"No API key configured"}]);
        return;
    }
    // Delegate to the appropriate adapter
    id<NSObject> adapter = [self _adapterForProtocol:config.protocol];
    if ([adapter respondsToSelector:@selector(fetchModelsWithConfig:completion:)]) {
        [(id<VCAIAdapter>)adapter fetchModelsWithConfig:config completion:completion];
    }
}

- (id)_adapterForProtocol:(VCAPIProtocol)protocol {
    // Lazy import -- adapters are resolved at runtime to avoid circular deps
    switch (protocol) {
        case VCAPIProtocolOpenAI:
        case VCAPIProtocolOpenAIResponses:
            return [NSClassFromString(@"VCOpenAIAdapter") new];
        case VCAPIProtocolAnthropic:
            return [NSClassFromString(@"VCAnthropicAdapter") new];
        case VCAPIProtocolGemini:
            return [NSClassFromString(@"VCGeminiAdapter") new];
    }
    return nil;
}

#pragma mark - Persistence

- (void)save {
    NSMutableArray *arr = [NSMutableArray new];
    for (VCProviderConfig *p in _providers) {
        NSMutableDictionary *dict = [[p toDictionary] mutableCopy];
        NSString *apiKey = VCSafeManagerString(dict[@"apiKey"]);
        // Encrypt API key before saving
        if (apiKey.length > 0 && _encryptionKey) {
            NSData *plain = [apiKey dataUsingEncoding:NSUTF8StringEncoding];
            NSData *encrypted = [VCCrypto encryptData:plain withKey:_encryptionKey];
            dict[@"apiKey"] = encrypted ? [VCCrypto hexStringFromData:encrypted] : @"";
        }
        [arr addObject:dict];
    }
    NSString *path = [[VCConfig shared].configPath stringByAppendingPathComponent:@"providers.json"];
    NSData *json = [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:path atomically:YES];
    [[NSUserDefaults standardUserDefaults] setObject:_activeProviderID forKey:kVCActiveProviderKey];
}

- (void)load {
    _activeProviderID = VCSafeManagerString([[NSUserDefaults standardUserDefaults] stringForKey:kVCActiveProviderKey]);
    NSString *path = [[VCConfig shared].configPath stringByAppendingPathComponent:@"providers.json"];
    NSData *json = [NSData dataWithContentsOfFile:path];
    if (!json) return;

    NSArray *arr = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (![arr isKindOfClass:[NSArray class]]) return;

    [_providers removeAllObjects];
    BOOL didMigrateLegacyData = NO;
    for (id entry in arr) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            didMigrateLegacyData = YES;
            continue;
        }
        NSDictionary *dict = (NSDictionary *)entry;
        NSMutableDictionary *mdict = [dict mutableCopy];
        // Decrypt API key
        NSString *encHex = VCSafeManagerString(mdict[@"apiKey"]);
        if (encHex.length > 0 && _encryptionKey) {
            NSData *encrypted = [VCCrypto dataFromHexString:encHex];
            NSData *decrypted = [VCCrypto decryptData:encrypted withKey:_encryptionKey];
            NSString *decryptedKey = decrypted ? [[NSString alloc] initWithData:decrypted encoding:NSUTF8StringEncoding] : nil;
            NSString *lowerKey = encHex.lowercaseString ?: @"";
            BOOL looksLikePlainKey = [lowerKey hasPrefix:@"sk-"] ||
                                     [lowerKey hasPrefix:@"bearer "] ||
                                     [lowerKey containsString:@"api_key"] ||
                                     [lowerKey containsString:@"openai_api_key"];
            if (decryptedKey.length > 0) {
                mdict[@"apiKey"] = decryptedKey;
            } else if (looksLikePlainKey) {
                mdict[@"apiKey"] = encHex;
                didMigrateLegacyData = YES;
            } else {
                mdict[@"apiKey"] = @"";
            }
        } else if (![mdict[@"apiKey"] isKindOfClass:[NSString class]]) {
            mdict[@"apiKey"] = @"";
            didMigrateLegacyData = YES;
        }
        VCProviderConfig *p = [VCProviderConfig fromDictionary:mdict];
        if (p) {
            [_providers addObject:p];
            if (![[p toDictionary] isEqualToDictionary:mdict]) {
                didMigrateLegacyData = YES;
            }
        } else {
            didMigrateLegacyData = YES;
        }
    }

    if (didMigrateLegacyData && _providers.count > 0) {
        [self save];
    }
}

- (void)_notifyProviderChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:VCProviderManagerDidChangeNotification object:nil];
}

@end
