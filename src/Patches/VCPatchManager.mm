/**
 * VCPatchManager -- 统一管理器
 */

#import "VCPatchManager.h"
#import "VCPatchItem.h"
#import "VCValueItem.h"
#import "VCHookItem.h"
#import "VCNetRule.h"
#import "../../VansonCLI.h"
#import "../Core/VCConfig.h"
#import "../Hook/VCHookManager.h"
#import "../Network/VCNetMonitor.h"

NSNotificationName const VCPatchManagerDidUpdateNotification = @"VCPatchManagerDidUpdate";

@interface VCPatchManager ()
@property (nonatomic, strong) NSMutableArray<VCPatchItem *> *patches;
@property (nonatomic, strong) NSMutableArray<VCValueItem *> *values;
@property (nonatomic, strong) NSMutableArray<VCHookItem *> *hooks;
@property (nonatomic, strong) NSMutableArray<VCNetRule *> *rules;
@end

@implementation VCPatchManager

+ (instancetype)shared {
    static VCPatchManager *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[self alloc] init]; });
    return inst;
}

- (instancetype)init {
    if (self = [super init]) {
        _patches = [NSMutableArray new];
        _values = [NSMutableArray new];
        _hooks = [NSMutableArray new];
        _rules = [NSMutableArray new];

        [self load];
        for (VCNetRule *rule in _rules) {
            if (rule.enabled && !rule.isDisabledBySafeMode) {
                [self _syncNetworkRule:rule enabled:YES];
            }
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleSafeModeNotification)
                                                     name:@"VCSafeModeDisablePatches"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 持久化路径

- (NSString *)archivePath {
    NSString *dir = [VCConfig shared].patchesPath;
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [dir stringByAppendingPathComponent:@"patches.dat"];
}

#pragma mark - CRUD

- (void)addPatch:(VCPatchItem *)item {
    if (!item) return;
    @synchronized (self) { [self.patches addObject:item]; }
    [self save];
    [self postUpdate];
}

- (void)addValue:(VCValueItem *)item {
    if (!item) return;
    @synchronized (self) { [self.values addObject:item]; }
    [self save];
    [self postUpdate];
}

- (void)addHook:(VCHookItem *)item {
    if (!item) return;
    @synchronized (self) { [self.hooks addObject:item]; }
    [self save];
    [self postUpdate];
}

- (void)addRule:(VCNetRule *)item {
    if (!item) return;
    @synchronized (self) { [self.rules addObject:item]; }
    [self _syncNetworkRule:item enabled:item.enabled];
    [self save];
    [self postUpdate];
}

- (void)removeItemByID:(NSString *)itemID {
    if (!itemID) return;
    @synchronized (self) {
        // Patches
        for (VCPatchItem *p in [self.patches copy]) {
            if ([p.patchID isEqualToString:itemID]) {
                if (p.enabled) [[VCHookManager shared] revertPatch:p];
                [self.patches removeObject:p];
                break;
            }
        }
        // Values
        for (VCValueItem *v in [self.values copy]) {
            if ([v.valueID isEqualToString:itemID]) {
                if (v.locked) [[VCHookManager shared] stopLocking:v];
                [self.values removeObject:v];
                break;
            }
        }
        // Hooks
        for (VCHookItem *h in [self.hooks copy]) {
            if ([h.hookID isEqualToString:itemID]) {
                if (h.enabled) [[VCHookManager shared] removeHook:h];
                [self.hooks removeObject:h];
                break;
            }
        }
        // Rules
        for (VCNetRule *r in [self.rules copy]) {
            if ([r.ruleID isEqualToString:itemID]) {
                [self _syncNetworkRule:r enabled:NO];
                [self.rules removeObject:r];
                break;
            }
        }
    }
    [self save];
    [self postUpdate];
}

- (void)updateItem:(id)item {
    if (!item) return;
    @synchronized (self) {
        if ([item isKindOfClass:[VCPatchItem class]]) {
            VCPatchItem *p = (VCPatchItem *)item;
            for (NSUInteger i = 0; i < self.patches.count; i++) {
                if ([self.patches[i].patchID isEqualToString:p.patchID]) {
                    self.patches[i] = p;
                    break;
                }
            }
        } else if ([item isKindOfClass:[VCValueItem class]]) {
            VCValueItem *v = (VCValueItem *)item;
            for (NSUInteger i = 0; i < self.values.count; i++) {
                if ([self.values[i].valueID isEqualToString:v.valueID]) {
                    self.values[i] = v;
                    break;
                }
            }
        } else if ([item isKindOfClass:[VCHookItem class]]) {
            VCHookItem *h = (VCHookItem *)item;
            for (NSUInteger i = 0; i < self.hooks.count; i++) {
                if ([self.hooks[i].hookID isEqualToString:h.hookID]) {
                    self.hooks[i] = h;
                    break;
                }
            }
        } else if ([item isKindOfClass:[VCNetRule class]]) {
            VCNetRule *r = (VCNetRule *)item;
            for (NSUInteger i = 0; i < self.rules.count; i++) {
                if ([self.rules[i].ruleID isEqualToString:r.ruleID]) {
                    self.rules[i] = r;
                    break;
                }
            }
        }
    }
    [self save];
    [self postUpdate];
}

#pragma mark - 查询

- (NSArray<VCPatchItem *> *)allPatches {
    @synchronized (self) { return [self.patches copy]; }
}

- (NSArray<VCValueItem *> *)allValues {
    @synchronized (self) { return [self.values copy]; }
}

- (NSArray<VCHookItem *> *)allHooks {
    @synchronized (self) { return [self.hooks copy]; }
}

- (NSArray<VCNetRule *> *)allRules {
    @synchronized (self) { return [self.rules copy]; }
}

#pragma mark - 执行控制

- (void)enableItem:(NSString *)itemID {
    [self setItemEnabled:YES forID:itemID];
}

- (void)disableItem:(NSString *)itemID {
    [self setItemEnabled:NO forID:itemID];
}

- (void)toggleItem:(NSString *)itemID {
    @synchronized (self) {
        for (VCPatchItem *p in self.patches) {
            if ([p.patchID isEqualToString:itemID]) {
                [self setItemEnabled:!p.enabled forID:itemID];
                return;
            }
        }
        for (VCValueItem *v in self.values) {
            if ([v.valueID isEqualToString:itemID]) {
                [self setItemEnabled:!v.locked forID:itemID];
                return;
            }
        }
        for (VCHookItem *h in self.hooks) {
            if ([h.hookID isEqualToString:itemID]) {
                [self setItemEnabled:!h.enabled forID:itemID];
                return;
            }
        }
        for (VCNetRule *r in self.rules) {
            if ([r.ruleID isEqualToString:itemID]) {
                [self setItemEnabled:!r.enabled forID:itemID];
                return;
            }
        }
    }
}

- (void)setItemEnabled:(BOOL)enabled forID:(NSString *)itemID {
    @synchronized (self) {
        for (VCPatchItem *p in self.patches) {
            if ([p.patchID isEqualToString:itemID]) {
                p.enabled = enabled;
                BOOL success = enabled ? [[VCHookManager shared] applyPatch:p] : [[VCHookManager shared] revertPatch:p];
                if (!success) p.enabled = !enabled;
                goto done;
            }
        }
        for (VCHookItem *h in self.hooks) {
            if ([h.hookID isEqualToString:itemID]) {
                h.enabled = enabled;
                BOOL success = enabled ? [[VCHookManager shared] installHook:h] : [[VCHookManager shared] removeHook:h];
                if (!success) h.enabled = !enabled;
                goto done;
            }
        }
        for (VCValueItem *v in self.values) {
            if ([v.valueID isEqualToString:itemID]) {
                v.locked = enabled;
                BOOL success = enabled ? [[VCHookManager shared] startLocking:v] : YES;
                if (enabled && !success) v.locked = NO;
                else if (!enabled) [[VCHookManager shared] stopLocking:v];
                goto done;
            }
        }
        for (VCNetRule *r in self.rules) {
            if ([r.ruleID isEqualToString:itemID]) {
                r.enabled = enabled;
                [self _syncNetworkRule:r enabled:enabled];
                goto done;
            }
        }
    }
done:
    [self save];
    [self postUpdate];
}

#pragma mark - 安全模式

- (void)handleSafeModeNotification {
    [self disableAllForSafeMode];
}

- (void)disableAllForSafeMode {
    @synchronized (self) {
        for (VCPatchItem *p in self.patches) {
            p.isDisabledBySafeMode = YES;
            p.enabled = NO;
        }
        for (VCValueItem *v in self.values) {
            v.isDisabledBySafeMode = YES;
            v.locked = NO;
        }
        for (VCHookItem *h in self.hooks) {
            h.isDisabledBySafeMode = YES;
            h.enabled = NO;
        }
        for (VCNetRule *r in self.rules) {
            [self _syncNetworkRule:r enabled:NO];
            r.isDisabledBySafeMode = YES;
            r.enabled = NO;
        }
    }
    [[VCHookManager shared] stopAllLocks];
    [self save];
    [self postUpdate];
    VCLog("disableAllForSafeMode: all items disabled");
}

- (void)clearSafeModeFlags {
    @synchronized (self) {
        for (VCPatchItem *p in self.patches) p.isDisabledBySafeMode = NO;
        for (VCValueItem *v in self.values) v.isDisabledBySafeMode = NO;
        for (VCHookItem *h in self.hooks) h.isDisabledBySafeMode = NO;
        for (VCNetRule *r in self.rules) r.isDisabledBySafeMode = NO;
    }
    [self save];
    [self postUpdate];
}

- (void)_syncNetworkRule:(VCNetRule *)rule enabled:(BOOL)enabled {
    if (rule.urlPattern.length == 0) return;
    if (enabled) [[VCNetMonitor shared] addInterceptRule:rule.urlPattern];
    else [[VCNetMonitor shared] removeInterceptRule:rule.urlPattern];
}

#pragma mark - 持久化

- (void)save {
    @synchronized (self) {
        NSDictionary *data = @{
            @"patches": [self.patches copy],
            @"values":  [self.values copy],
            @"hooks":   [self.hooks copy],
            @"rules":   [self.rules copy],
        };
        NSError *error = nil;
        NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:data
                                                 requiringSecureCoding:NO
                                                                 error:&error];
        if (archived && !error) {
            [archived writeToFile:[self archivePath] atomically:YES];
        } else {
            VCLog("PatchManager save error: %@", error.localizedDescription);
        }
    }
}

- (void)load {
    NSString *path = [self archivePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;

    NSData *fileData = [NSData dataWithContentsOfFile:path];
    if (!fileData) return;

    NSError *error = nil;
    NSSet *allowedClasses = [NSSet setWithArray:@[
        [NSDictionary class], [NSArray class], [NSMutableArray class],
        [VCPatchItem class], [VCValueItem class], [VCHookItem class], [VCNetRule class],
        [NSString class], [NSNumber class], [NSDate class], [NSData class],
    ]];
    NSDictionary *data = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowedClasses
                                                             fromData:fileData
                                                                error:&error];
    if (error || ![data isKindOfClass:[NSDictionary class]]) {
        VCLog("PatchManager load error: %@", error.localizedDescription);
        // Fallback: try legacy unarchiver for migration
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        data = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
        #pragma clang diagnostic pop
        if (![data isKindOfClass:[NSDictionary class]]) return;
        VCLog("PatchManager: migrated from legacy archive format");
    }

    @synchronized (self) {
        NSArray *p = data[@"patches"];
        NSArray *v = data[@"values"];
        NSArray *h = data[@"hooks"];
        NSArray *r = data[@"rules"];
        if (p) [self.patches setArray:p];
        if (v) [self.values setArray:v];
        if (h) [self.hooks setArray:h];
        if (r) [self.rules setArray:r];
    }
    VCLog("PatchManager loaded: %lu patches, %lu values, %lu hooks, %lu rules",
          (unsigned long)self.patches.count, (unsigned long)self.values.count,
          (unsigned long)self.hooks.count, (unsigned long)self.rules.count);
}

#pragma mark - 统计

- (NSUInteger)enabledCount {
    NSUInteger count = 0;
    @synchronized (self) {
        for (VCPatchItem *p in self.patches) if (p.enabled) count++;
        for (VCValueItem *v in self.values) if (v.locked) count++;
        for (VCHookItem *h in self.hooks) if (h.enabled) count++;
        for (VCNetRule *r in self.rules) if (r.enabled) count++;
    }
    return count;
}

- (NSUInteger)totalCount {
    @synchronized (self) {
        return self.patches.count + self.values.count + self.hooks.count + self.rules.count;
    }
}

- (NSUInteger)aiCreatedCount {
    NSUInteger count = 0;
    @synchronized (self) {
        for (VCPatchItem *p in self.patches) if (p.source == VCItemSourceAI) count++;
        for (VCValueItem *v in self.values) if (v.source == VCItemSourceAI) count++;
        for (VCHookItem *h in self.hooks) if (h.source == VCItemSourceAI) count++;
        for (VCNetRule *r in self.rules) if (r.source == VCItemSourceAI) count++;
    }
    return count;
}

#pragma mark - Notification

- (void)postUpdate {
    vc_dispatch_main(^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VCPatchManagerDidUpdateNotification object:nil];
    });
}

@end
