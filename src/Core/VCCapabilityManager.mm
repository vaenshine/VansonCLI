/**
 * VCCapabilityManager.mm -- runtime mutation capability detection
 */

#import "VCCapabilityManager.h"
#import "VCSafeMode.h"
#import "../../VansonCLI.h"
#import <mach-o/dyld.h>

static NSString *const kVCDeveloperOverrideKey = @"com.vanson.cli.allowUnsafeRuntimeMutations";

@interface VCCapabilityManager ()
@property (nonatomic, readwrite, copy) NSString *hookBackend;
@property (nonatomic, readwrite) BOOL jailbreakEnvironmentLikely;
@property (nonatomic, readwrite) BOOL canModifyRuntime;
@property (nonatomic, readwrite) BOOL canInstallHooks;
@property (nonatomic, readwrite) BOOL canWriteMemory;
@property (nonatomic, readwrite) BOOL canWriteDataMemory;
@property (nonatomic, readwrite) BOOL canPatchExecutableText;
@property (nonatomic, readwrite) BOOL developerOverrideEnabled;
@end

@implementation VCCapabilityManager

+ (instancetype)shared {
    static VCCapabilityManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCCapabilityManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        [self _refreshCapabilities];
    }
    return self;
}

- (NSDictionary *)capabilitiesSnapshot {
    [self _refreshCapabilities];
    return @{
        @"hookBackend": self.hookBackend ?: @"none",
        @"jailbreakEnvironmentLikely": @(self.jailbreakEnvironmentLikely),
        @"canModifyRuntime": @(self.canModifyRuntime),
        @"canInstallHooks": @(self.canInstallHooks),
        @"canWriteMemory": @(self.canWriteMemory),
        @"canWriteDataMemory": @(self.canWriteDataMemory),
        @"canPatchExecutableText": @(self.canPatchExecutableText),
        @"textPatchingNeedsBypass": @YES,
        @"toolExecutionMode": @"automatic",
        @"developerOverrideEnabled": @(self.developerOverrideEnabled),
        @"safeMode": @([VCSafeMode isInSafeMode]),
    };
}

- (BOOL)canUseRuntimePatchingWithReason:(NSString * _Nullable * _Nullable)reason {
    [self _refreshCapabilities];
    if ([VCSafeMode isInSafeMode]) {
        if (reason) *reason = @"Runtime patching is unavailable while Safe Mode is active.";
        return NO;
    }
    if (self.canModifyRuntime) return YES;
    if (reason) *reason = [self _defaultDenialReasonForAction:@"runtime patching"];
    return NO;
}

- (BOOL)canUseHookingWithReason:(NSString * _Nullable * _Nullable)reason {
    [self _refreshCapabilities];
    if ([VCSafeMode isInSafeMode]) {
        if (reason) *reason = @"Method hooking is unavailable while Safe Mode is active.";
        return NO;
    }
    if (self.canInstallHooks) return YES;
    if (reason) *reason = [self _defaultDenialReasonForAction:@"method hooking"];
    return NO;
}

- (BOOL)canUseMemoryWritesWithReason:(NSString * _Nullable * _Nullable)reason {
    [self _refreshCapabilities];
    if ([VCSafeMode isInSafeMode]) {
        if (reason) *reason = @"Memory writes are unavailable while Safe Mode is active.";
        return NO;
    }
    if (self.canWriteMemory) return YES;
    if (reason) *reason = [self _defaultDenialReasonForAction:@"memory writes"];
    return NO;
}

#pragma mark - Private

- (void)_refreshCapabilities {
    self.developerOverrideEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kVCDeveloperOverrideKey];

    NSString *backend = [self _detectHookBackendFromLoadedImages];
    BOOL jailbreakLike = self.developerOverrideEnabled || [self _hasJailbreakIndicators] || ![backend isEqualToString:@"none"];

    self.hookBackend = backend ?: @"none";
    self.jailbreakEnvironmentLikely = jailbreakLike;
    self.canInstallHooks = self.developerOverrideEnabled || jailbreakLike;
    self.canPatchExecutableText = self.developerOverrideEnabled || jailbreakLike;
    self.canModifyRuntime = self.canPatchExecutableText;
    self.canWriteDataMemory = YES;
    self.canWriteMemory = self.canWriteDataMemory;
}

- (NSString *)_detectHookBackendFromLoadedImages {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *lower = [[NSString stringWithUTF8String:name] lowercaseString];
        if ([lower containsString:@"ellekit"]) return @"ElleKit";
        if ([lower containsString:@"libhooker"]) return @"libhooker";
        if ([lower containsString:@"substitute"]) return @"Substitute";
        if ([lower containsString:@"substrate"]) return @"Substrate";
    }
    return @"none";
}

- (BOOL)_hasJailbreakIndicators {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *paths = @[
        @"/var/jb",
        @"/Library/MobileSubstrate",
        @"/var/jb/Library/MobileSubstrate",
        @"/usr/lib/substitute-inserter.dylib",
        @"/var/jb/usr/lib/substitute-inserter.dylib",
        @"/usr/lib/libhooker.dylib",
        @"/var/jb/usr/lib/libhooker.dylib",
        @"/usr/lib/libellekit.dylib",
        @"/var/jb/usr/lib/libellekit.dylib",
        @"/Applications/Sileo.app",
        @"/Applications/Cydia.app",
    ];
    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) return YES;
    }
    return NO;
}

- (NSString *)_defaultDenialReasonForAction:(NSString *)action {
    NSString *backend = self.hookBackend.length > 0 ? self.hookBackend : @"none";
    return [NSString stringWithFormat:
            @"%@ is blocked because this environment does not look patch-safe. Detected hook backend: %@.",
            [action capitalizedString], backend];
}

@end
