/**
 * VCContextCollector.mm -- 上下文收集实现
 */

#import "VCContextCollector.h"
#import "../../Process/VCProcessInfo.h"
#import "../../Runtime/VCRuntimeEngine.h"
#import "../../Runtime/VCRuntimeModels.h"
#import "../../Network/VCNetMonitor.h"
#import "../../Network/VCNetRecord.h"
#import "../../UIInspector/VCUIInspector.h"
#import "../../Patches/VCPatchManager.h"
#import "../../Patches/VCPatchItem.h"
#import "../../Patches/VCValueItem.h"
#import "../../Patches/VCHookItem.h"
#import "../../Patches/VCNetRule.h"
#import "../../Console/VCCommandRouter.h"
#import "../../../VansonCLI.h"

static NSArray *VCRecentTail(NSArray *items, NSUInteger count) {
    if (items.count <= count) return items ?: @[];
    return [items subarrayWithRange:NSMakeRange(items.count - count, count)];
}

static NSString *VCHexAddress(uintptr_t address) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)address];
}

@implementation VCContextCollector

+ (instancetype)shared {
    static VCContextCollector *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCContextCollector alloc] init];
    });
    return instance;
}

- (NSDictionary *)collectContextForTab:(NSString *)tabName {
    if ([tabName isEqualToString:@"inspect"]) {
        return [self _collectInspectContext];
    } else if ([tabName isEqualToString:@"network"]) {
        return [self _collectNetworkContext];
    } else if ([tabName isEqualToString:@"ui"]) {
        return [self _collectUIContext];
    } else if ([tabName isEqualToString:@"patches"]) {
        return [self _collectPatchesContext];
    } else if ([tabName isEqualToString:@"console"]) {
        return [self _collectConsoleContext];
    }
    return @{};
}

#pragma mark - Tab Context Collectors

- (NSDictionary *)_collectInspectContext {
    VCProcessInfo *processInfo = [VCProcessInfo shared];
    NSDictionary *basicInfo = [processInfo basicInfo];
    NSArray<VCModuleInfo *> *modules = [processInfo loadedModules];
    NSMutableArray<NSDictionary *> *moduleSummary = [NSMutableArray new];
    for (VCModuleInfo *mod in VCRecentTail(modules, 5)) {
        [moduleSummary addObject:@{
            @"name": mod.name ?: @"",
            @"category": mod.category ?: @"",
            @"address": VCHexAddress((uintptr_t)mod.loadAddress),
            @"size": @(mod.size)
        }];
    }

    NSArray<VCClassInfo *> *sampleClasses = [[VCRuntimeEngine shared] allClassesFilteredBy:nil module:nil offset:0 limit:5];
    NSMutableArray<NSString *> *classNames = [NSMutableArray new];
    for (VCClassInfo *info in sampleClasses) {
        if (info.className.length) [classNames addObject:info.className];
    }

    return @{
        @"tab": @"inspect",
        @"process": @{
            @"pid": basicInfo[@"pid"] ?: @0,
            @"bundleID": basicInfo[@"bundleID"] ?: @"",
            @"version": basicInfo[@"version"] ?: @""
        },
        @"runtime": @{
            @"totalClasses": @([[VCRuntimeEngine shared] totalClassCount]),
            @"loadedModuleCount": @(modules.count),
            @"sampleClasses": classNames
        },
        @"recentModules": moduleSummary
    };
}

- (NSDictionary *)_collectNetworkContext {
    VCNetMonitor *monitor = [VCNetMonitor shared];
    NSArray<VCNetRecord *> *records = [monitor allRecords];
    NSMutableArray<NSDictionary *> *recentRequests = [NSMutableArray new];
    for (VCNetRecord *record in VCRecentTail(records, 5)) {
        [recentRequests addObject:@{
            @"method": record.method ?: @"GET",
            @"url": record.url ?: @"",
            @"status": @(record.statusCode),
            @"durationMs": @((NSUInteger)llround(record.duration * 1000.0))
        }];
    }

    return @{
        @"tab": @"network",
        @"monitoring": @(monitor.isMonitoring),
        @"totalRecords": @(records.count),
        @"recentRequests": recentRequests
    };
}

- (NSDictionary *)_collectUIContext {
    VCUIInspector *inspector = [VCUIInspector shared];
    UIView *selectedView = inspector.currentSelectedView;
    VCViewNode *root = [inspector viewHierarchyTree];

    NSMutableDictionary *context = [@{
        @"tab": @"ui",
        @"windowCount": @(root.children.count)
    } mutableCopy];

    if (selectedView) {
        NSDictionary *props = [inspector propertiesForView:selectedView];
        NSArray<NSString *> *keys = [props.allKeys sortedArrayUsingSelector:@selector(compare:)];
        NSMutableDictionary *sampleProps = [NSMutableDictionary new];
        for (NSString *key in VCRecentTail(keys, MIN((NSUInteger)keys.count, 8))) {
            id value = props[key];
            if (value) sampleProps[key] = value;
        }

        context[@"selectedView"] = @{
            @"class": NSStringFromClass([selectedView class]) ?: @"",
            @"frame": NSStringFromCGRect(selectedView.frame),
            @"address": VCHexAddress((uintptr_t)(__bridge void *)selectedView),
            @"properties": sampleProps,
            @"responders": [inspector responderChainForView:selectedView] ?: @[]
        };
    } else {
        NSMutableArray<NSDictionary *> *windowSummary = [NSMutableArray new];
        for (VCViewNode *node in VCRecentTail(root.children, 3)) {
            [windowSummary addObject:@{
                @"class": node.className ?: @"",
                @"frame": NSStringFromCGRect(node.frame),
                @"children": @(node.children.count)
            }];
        }
        context[@"windows"] = windowSummary;
    }

    return [context copy];
}

- (NSDictionary *)_collectPatchesContext {
    VCPatchManager *manager = [VCPatchManager shared];
    NSMutableArray<NSDictionary *> *enabledItems = [NSMutableArray new];

    for (VCPatchItem *item in [manager allPatches]) {
        if (!item.enabled) continue;
        [enabledItems addObject:@{
            @"kind": @"patch",
            @"target": [NSString stringWithFormat:@"-[%@ %@]", item.className ?: @"?", item.selector ?: @"?"],
            @"mode": item.patchType ?: @"nop"
        }];
    }
    for (VCHookItem *item in [manager allHooks]) {
        if (!item.enabled) continue;
        [enabledItems addObject:@{
            @"kind": @"hook",
            @"target": [NSString stringWithFormat:@"-[%@ %@]", item.className ?: @"?", item.selector ?: @"?"],
            @"mode": item.hookType ?: @"log"
        }];
    }
    for (VCValueItem *item in [manager allValues]) {
        if (!item.locked) continue;
        [enabledItems addObject:@{
            @"kind": @"value",
            @"target": item.targetDesc ?: VCHexAddress(item.address),
            @"mode": item.modifiedValue ?: @""
        }];
    }
    for (VCNetRule *item in [manager allRules]) {
        if (!item.enabled) continue;
        [enabledItems addObject:@{
            @"kind": @"rule",
            @"target": item.urlPattern ?: @"",
            @"mode": item.action ?: @""
        }];
    }

    return @{
        @"tab": @"patches",
        @"enabledCount": @([manager enabledCount]),
        @"totalCount": @([manager totalCount]),
        @"aiCreatedCount": @([manager aiCreatedCount]),
        @"enabledItems": VCRecentTail(enabledItems, 8)
    };
}

- (NSDictionary *)_collectConsoleContext {
    NSArray<NSString *> *history = [[VCCommandRouter shared] commandHistory];
    return @{
        @"tab": @"console",
        @"historyCount": @(history.count),
        @"recentCommands": VCRecentTail(history, 10)
    };
}

@end
