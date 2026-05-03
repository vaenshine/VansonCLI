/**
 * VCConfig.mm -- 全局配置管理
 */

#import "VCConfig.h"
#import "../../VansonCLI.h"
#import "VCCore.hpp"

static NSString *const kVCFeatureFlagsKey = @"com.vanson.cli.features";
static NSString *const kVCGitHubLatestReleaseURL = @"https://api.github.com/repos/vaenshine/VansonCLI/releases/latest";

static NSArray<NSNumber *> *VCVersionComponents(NSString *version) {
    NSString *clean = [[version ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([clean hasPrefix:@"v"]) clean = [clean substringFromIndex:1];
    NSMutableArray<NSNumber *> *parts = [NSMutableArray array];
    NSCharacterSet *separators = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    for (NSString *rawPart in [clean componentsSeparatedByCharactersInSet:separators]) {
        if (rawPart.length == 0) continue;
        [parts addObject:@(rawPart.integerValue)];
    }
    return parts.count ? [parts copy] : @[@0];
}

static NSComparisonResult VCCompareVersions(NSString *left, NSString *right) {
    NSArray<NSNumber *> *lhs = VCVersionComponents(left);
    NSArray<NSNumber *> *rhs = VCVersionComponents(right);
    NSUInteger count = MAX(lhs.count, rhs.count);
    for (NSUInteger index = 0; index < count; index++) {
        NSInteger l = index < lhs.count ? lhs[index].integerValue : 0;
        NSInteger r = index < rhs.count ? rhs[index].integerValue : 0;
        if (l < r) return NSOrderedAscending;
        if (l > r) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

@implementation VCConfig {
    NSMutableDictionary *_featureFlags;
}

+ (instancetype)shared {
    static VCConfig *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCConfig alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        [self _loadFeatureFlags];
        [self _ensureDirectories];
    }
    return self;
}

#pragma mark - Target Info

- (NSString *)targetBundleID {
    return [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
}

- (NSString *)targetDisplayName {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"]
        ?: [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]
        ?: @"Unknown";
}

- (NSString *)targetVersion {
    NSString *short_ = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    return [NSString stringWithFormat:@"%@ (%@)", short_, build];
}

#pragma mark - Paths

- (NSString *)sandboxPath {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        path = [docs.firstObject stringByAppendingPathComponent:@"VansonCLI"];
    });
    return path;
}

- (NSString *)patchesPath {
    return [self.sandboxPath stringByAppendingPathComponent:@"patches"];
}

- (NSString *)sessionsPath {
    return [self.sandboxPath stringByAppendingPathComponent:@"sessions"];
}

- (NSString *)configPath {
    return [self.sandboxPath stringByAppendingPathComponent:@"config"];
}

#pragma mark - Feature Flags

- (BOOL)isFeatureEnabled:(NSString *)featureID {
    NSNumber *val = _featureFlags[featureID];
    return val ? val.boolValue : YES; // 默认启用
}

- (void)setFeature:(NSString *)featureID enabled:(BOOL)enabled {
    _featureFlags[featureID] = @(enabled);
    [[NSUserDefaults standardUserDefaults] setObject:[_featureFlags copy] forKey:kVCFeatureFlagsKey];
}

#pragma mark - Version

- (NSString *)vcVersion {
#ifdef VC_VERSION_STR
    return @VC_VERSION_STR;
#else
    return @"dev";
#endif
}

- (void)checkForUpdatesWithCompletion:(VCUpdateCheckCompletion)completion {
    NSURL *url = [NSURL URLWithString:kVCGitHubLatestReleaseURL];
    if (!url) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"VansonCLI.Update"
                                                code:-1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid update URL"}]);
        }
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 12.0;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"VansonCLI/%@", self.vcVersion ?: @"dev"] forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        void (^finish)(NSDictionary *, NSError *) = ^(NSDictionary *info, NSError *err) {
            if (!completion) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(info, err);
            });
        };

        if (error) {
            finish(nil, error);
            return;
        }

        NSInteger statusCode = 0;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            statusCode = ((NSHTTPURLResponse *)response).statusCode;
        }
        if (statusCode < 200 || statusCode >= 300) {
            finish(nil, [NSError errorWithDomain:@"VansonCLI.Update"
                                            code:statusCode
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"GitHub returned HTTP %ld", (long)statusCode]}]);
            return;
        }

        NSError *jsonError = nil;
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError] : nil;
        if (![json isKindOfClass:[NSDictionary class]]) {
            finish(nil, jsonError ?: [NSError errorWithDomain:@"VansonCLI.Update"
                                                         code:-2
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid release response"}]);
            return;
        }

        NSDictionary *release = (NSDictionary *)json;
        NSString *tag = [release[@"tag_name"] isKindOfClass:[NSString class]] ? release[@"tag_name"] : @"";
        NSString *name = [release[@"name"] isKindOfClass:[NSString class]] ? release[@"name"] : tag;
        NSString *htmlURL = [release[@"html_url"] isKindOfClass:[NSString class]] ? release[@"html_url"] : @"https://github.com/vaenshine/VansonCLI/releases";
        NSString *publishedAt = [release[@"published_at"] isKindOfClass:[NSString class]] ? release[@"published_at"] : @"";
        NSString *body = [release[@"body"] isKindOfClass:[NSString class]] ? release[@"body"] : @"";
        NSString *current = self.vcVersion ?: @"0";
        NSComparisonResult comparison = VCCompareVersions(current, tag);
        NSDictionary *info = @{
            @"currentVersion": current,
            @"latestVersion": tag.length ? tag : @"0",
            @"releaseName": name ?: @"",
            @"releaseURL": htmlURL ?: @"",
            @"publishedAt": publishedAt ?: @"",
            @"body": body ?: @"",
            @"updateAvailable": @(comparison == NSOrderedAscending),
        };
        finish(info, nil);
    }];
    [task resume];
}

#pragma mark - Private

- (void)_loadFeatureFlags {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVCFeatureFlagsKey];
    _featureFlags = saved ? [saved mutableCopy] : [NSMutableDictionary new];
}

- (void)_ensureDirectories {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in @[self.sandboxPath, self.patchesPath, self.sessionsPath, self.configPath]) {
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
}

@end
