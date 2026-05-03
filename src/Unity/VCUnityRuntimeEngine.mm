/**
 * VCUnityRuntimeEngine -- lightweight Unity/IL2CPP/Mono runtime detection
 * and exported symbol resolution for guided analysis.
 */

#import "VCUnityRuntimeEngine.h"
#import "../Process/VCProcessInfo.h"
#import "../UI/Base/VCOverlayRootViewController.h"
#import "../UI/Base/VCOverlayCanvasManager.h"

#import <UIKit/UIKit.h>
#include <dlfcn.h>

typedef struct {
    float x;
    float y;
    float z;
} VCUnityVector3;

typedef struct {
    VCUnityVector3 center;
    VCUnityVector3 extents;
} VCUnityBounds;

typedef struct {
    void *klass;
    void *monitor;
    int32_t length;
    uint16_t chars[1];
} VCUnityString;

typedef struct {
    void *klass;
    void *monitor;
    void *bounds;
    uintptr_t max_length;
    void *vector[1];
} VCUnityObjectArray;

typedef void *(*VCUnityResolveICallFunc)(const char *);
typedef void *(*VCUnityCameraGetMainFunc)(void);
typedef void *(*VCUnityGetTransformFunc)(void *);
typedef void *(*VCUnityStringNewFunc)(const char *);
typedef void *(*VCUnityGameObjectFindFunc)(void *);
typedef void *(*VCUnityGameObjectFindManyFunc)(void *);
typedef void *(*VCUnityGetComponentByNameFunc)(void *, void *);
typedef void (*VCUnityTransformGetPositionInjectedFunc)(void *, VCUnityVector3 *);
typedef void (*VCUnityWorldToScreenInjectedEyeFunc)(void *, const VCUnityVector3 *, int, VCUnityVector3 *);
typedef void (*VCUnityWorldToScreenInjectedFunc)(void *, const VCUnityVector3 *, VCUnityVector3 *);
typedef int (*VCUnityScreenIntGetterFunc)(void);
typedef void (*VCUnityRendererGetBoundsInjectedFunc)(void *, VCUnityBounds *);

static NSString *VCUnityTrimmedString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] copy];
    }
    return @"";
}

static NSString *VCUnityHexAddress(uint64_t address) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)address];
}

static BOOL VCUnityStringContainsAny(NSString *text, NSArray<NSString *> *patterns) {
    NSString *normalized = VCUnityTrimmedString(text).lowercaseString;
    if (normalized.length == 0) return NO;
    for (NSString *pattern in patterns) {
        if (pattern.length > 0 && [normalized containsString:pattern]) return YES;
    }
    return NO;
}

static BOOL VCUnityModuleLooksRelevant(VCModuleInfo *moduleInfo) {
    if (!moduleInfo) return NO;
    NSString *name = VCUnityTrimmedString(moduleInfo.name).lowercaseString;
    NSString *path = VCUnityTrimmedString(moduleInfo.path).lowercaseString;
    NSArray<NSString *> *patterns = @[
        @"unityframework",
        @"unityplayer",
        @"libunity",
        @"libil2cpp",
        @"monobleedingedge",
        @"mono"
    ];
    return VCUnityStringContainsAny(name, patterns) || VCUnityStringContainsAny(path, patterns);
}

static NSArray<NSString *> *VCUnityBaseDefaultSymbols(void) {
    return @[
        @"UnitySendMessage",
        @"UnityPause",
        @"UnitySetPlayerFocus"
    ];
}

static NSArray<NSString *> *VCUnityIL2CPPDefaultSymbols(void) {
    return @[
        @"il2cpp_domain_get",
        @"il2cpp_thread_attach",
        @"il2cpp_class_from_name",
        @"il2cpp_class_get_method_from_name",
        @"il2cpp_object_get_class",
        @"il2cpp_string_new",
        @"il2cpp_resolve_icall"
    ];
}

static NSArray<NSString *> *VCUnityMonoDefaultSymbols(void) {
    return @[
        @"mono_get_root_domain",
        @"mono_thread_attach",
        @"mono_class_from_name",
        @"mono_class_get_method_from_name",
        @"mono_object_get_class",
        @"mono_string_new",
        @"mono_lookup_internal_call"
    ];
}

static NSArray<NSString *> *VCUnityDrawingDefaultICalls(void) {
    return @[
        @"UnityEngine.Camera::get_main()",
        @"UnityEngine.Camera::WorldToScreenPoint_Injected(UnityEngine.Vector3&,UnityEngine.Camera/MonoOrStereoscopicEye,UnityEngine.Vector3&)",
        @"UnityEngine.Camera::WorldToScreenPoint_Injected(UnityEngine.Vector3&,UnityEngine.Vector3&)",
        @"UnityEngine.Transform::get_position_Injected(UnityEngine.Vector3&)",
        @"UnityEngine.Component::get_transform()",
        @"UnityEngine.GameObject::get_transform()",
        @"UnityEngine.Renderer::get_bounds_Injected(UnityEngine.Bounds&)",
        @"UnityEngine.Screen::get_width()",
        @"UnityEngine.Screen::get_height()"
    ];
}

static NSArray<NSString *> *VCUnityMainCameraICallCandidates(void) {
    return @[
        @"UnityEngine.Camera::get_main()"
    ];
}

static NSArray<NSString *> *VCUnityWorldToScreenICallCandidates(void) {
    return @[
        @"UnityEngine.Camera::WorldToScreenPoint_Injected(UnityEngine.Vector3&,UnityEngine.Camera/MonoOrStereoscopicEye,UnityEngine.Vector3&)",
        @"UnityEngine.Camera::WorldToScreenPoint_Injected(UnityEngine.Vector3&,UnityEngine.Vector3&)"
    ];
}

static NSArray<NSString *> *VCUnityTransformPositionICallCandidates(void) {
    return @[
        @"UnityEngine.Transform::get_position_Injected(UnityEngine.Vector3&)"
    ];
}

static NSArray<NSString *> *VCUnityRendererBoundsICallCandidates(void) {
    return @[
        @"UnityEngine.Renderer::get_bounds_Injected(UnityEngine.Bounds&)"
    ];
}

static NSArray<NSString *> *VCUnityComponentTransformICallCandidates(void) {
    return @[
        @"UnityEngine.Component::get_transform()"
    ];
}

static NSArray<NSString *> *VCUnityGameObjectTransformICallCandidates(void) {
    return @[
        @"UnityEngine.GameObject::get_transform()"
    ];
}

static NSArray<NSString *> *VCUnityScreenWidthICallCandidates(void) {
    return @[
        @"UnityEngine.Screen::get_width()"
    ];
}

static NSArray<NSString *> *VCUnityScreenHeightICallCandidates(void) {
    return @[
        @"UnityEngine.Screen::get_height()"
    ];
}

static NSArray<NSString *> *VCUnityGameObjectFindICallCandidates(void) {
    return @[
        @"UnityEngine.GameObject::Find(System.String)",
        @"UnityEngine.GameObject::Find(System.String, System.Boolean)"
    ];
}

static NSArray<NSString *> *VCUnityGameObjectsWithTagICallCandidates(void) {
    return @[
        @"UnityEngine.GameObject::FindGameObjectsWithTag(System.String)"
    ];
}

static NSArray<NSString *> *VCUnityGameObjectWithTagICallCandidates(void) {
    return @[
        @"UnityEngine.GameObject::FindGameObjectWithTag(System.String)"
    ];
}

static NSArray<NSString *> *VCUnityGameObjectGetComponentByNameCandidates(void) {
    return @[
        @"UnityEngine.GameObject::GetComponentByName(System.String)",
        @"UnityEngine.GameObject::GetComponent(System.String)"
    ];
}

static NSArray<NSString *> *VCUnityComponentGetComponentByNameCandidates(void) {
    return @[
        @"UnityEngine.Component::GetComponent(System.String)",
        @"UnityEngine.Component::GetComponentByName(System.String)"
    ];
}

@implementation VCUnityRuntimeEngine

+ (instancetype)shared {
    static VCUnityRuntimeEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCUnityRuntimeEngine alloc] init];
    });
    return instance;
}

- (NSDictionary *)detectUnityRuntime {
    NSArray<VCModuleInfo *> *modules = [self _unityModules];
    BOOL hasUnityFramework = [self _hasModuleMatchingPatterns:@[@"unityframework", @"unityplayer", @"libunity"]];
    BOOL hasIL2CPP = [self _hasModuleMatchingPatterns:@[@"libil2cpp"]] || [self _symbolAddressForName:@"il2cpp_domain_get" preferredModule:nil ownerModule:nil] != NULL;
    BOOL hasMono = [self _hasModuleMatchingPatterns:@[@"mono", @"monobleedingedge"]] || [self _symbolAddressForName:@"mono_get_root_domain" preferredModule:nil ownerModule:nil] != NULL;

    NSString *runtimeFlavor = @"unknown";
    if (hasIL2CPP) runtimeFlavor = @"il2cpp";
    else if (hasMono) runtimeFlavor = @"mono";
    else if (hasUnityFramework) runtimeFlavor = @"unity";

    NSDictionary *objcClasses = @{
        @"UnityAppController": @(NSClassFromString(@"UnityAppController") != Nil),
        @"UnityFramework": @(NSClassFromString(@"UnityFramework") != Nil),
        @"UnityView": @(NSClassFromString(@"UnityView") != Nil),
        @"UnityViewControllerBase": @(NSClassFromString(@"UnityViewControllerBase") != Nil)
    };

    NSArray<NSString *> *defaultSymbols = [self _defaultSymbolsForRuntimeFlavor:runtimeFlavor];
    NSDictionary *resolved = [self resolveSymbols:@[] preferredModule:nil includeDefaultSymbols:YES];
    NSArray *resolvedItems = [resolved[@"symbols"] isKindOfClass:[NSArray class]] ? resolved[@"symbols"] : @[];
    NSUInteger resolvedCount = 0;
    for (NSDictionary *item in resolvedItems) {
        if ([item[@"found"] boolValue]) resolvedCount++;
    }

    BOOL likelyUnity = hasUnityFramework || hasIL2CPP || hasMono;
    for (NSNumber *flag in objcClasses.allValues) {
        if ([flag boolValue]) {
            likelyUnity = YES;
            break;
        }
    }

    NSMutableArray<NSString *> *recommendedNextSteps = [NSMutableArray new];
    if (!likelyUnity) {
        [recommendedNextSteps addObject:@"No clear Unity runtime markers were found. Start with query_process modules, then use signature_scan or memory_scan on the target object data."];
    } else if ([runtimeFlavor isEqualToString:@"il2cpp"]) {
        [recommendedNextSteps addObject:@"Use il2cpp exported symbols first, then stabilize object or field addresses with signature_scan, pointer_chain, or address_resolve."];
        [recommendedNextSteps addObject:@"For drawing, resolve Camera.main and Transform position, project to overlay coordinates with world_to_screen, then render with overlay_canvas."];
    } else if ([runtimeFlavor isEqualToString:@"mono"]) {
        [recommendedNextSteps addObject:@"Use mono exported symbols to resolve classes and methods, then pivot to memory or signatures for stable locators."];
        [recommendedNextSteps addObject:@"For drawing, the next missing bridge is safe Camera/Transform access that works like the IL2CPP WorldToScreen path."];
    } else {
        [recommendedNextSteps addObject:@"Unity is likely present, but exported scripting symbols are limited. Fall back to signatures, module-relative locators, and memory inspection."];
    }

    return @{
        @"likelyUnity": @(likelyUnity),
        @"runtimeFlavor": runtimeFlavor,
        @"hasUnityFramework": @(hasUnityFramework),
        @"hasIL2CPP": @(hasIL2CPP),
        @"hasMono": @(hasMono),
        @"unityModuleCount": @(modules.count),
        @"unityModules": [self unityModuleSummariesWithLimit:12],
        @"objcClasses": objcClasses,
        @"defaultSymbols": defaultSymbols,
        @"resolvedDefaultSymbolCount": @(resolvedCount),
        @"recommendedNextSteps": [recommendedNextSteps copy]
    };
}

- (NSArray<NSDictionary *> *)unityModuleSummariesWithLimit:(NSUInteger)limit {
    NSArray<VCModuleInfo *> *modules = [self _unityModules];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    NSUInteger maxCount = limit == 0 ? modules.count : MIN(limit, modules.count);
    for (NSUInteger idx = 0; idx < maxCount; idx++) {
        VCModuleInfo *moduleInfo = modules[idx];
        [items addObject:@{
            @"name": moduleInfo.name ?: @"",
            @"path": moduleInfo.path ?: @"",
            @"category": moduleInfo.category ?: @"",
            @"loadAddress": VCUnityHexAddress(moduleInfo.loadAddress),
            @"slide": VCUnityHexAddress(moduleInfo.slide),
            @"size": @(moduleInfo.size)
        }];
    }
    return [items copy];
}

- (NSDictionary *)resolveSymbols:(NSArray<NSString *> *)symbolNames
                 preferredModule:(NSString *)preferredModuleName
           includeDefaultSymbols:(BOOL)includeDefaultSymbols {
    NSDictionary *detect = [self detectUnityRuntimeWithoutSymbols];
    NSString *runtimeFlavor = detect[@"runtimeFlavor"] ?: @"unknown";
    NSMutableOrderedSet<NSString *> *requestedSymbols = [NSMutableOrderedSet orderedSet];

    for (NSString *symbol in symbolNames ?: @[]) {
        NSString *trimmed = VCUnityTrimmedString(symbol);
        if (trimmed.length > 0) [requestedSymbols addObject:trimmed];
    }
    if (includeDefaultSymbols || requestedSymbols.count == 0) {
        for (NSString *symbol in [self _defaultSymbolsForRuntimeFlavor:runtimeFlavor]) {
            if (symbol.length > 0) [requestedSymbols addObject:symbol];
        }
    }

    NSArray<VCModuleInfo *> *candidateModules = [self _candidateModulesForPreferredModule:preferredModuleName];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    NSUInteger resolvedCount = 0;

    for (NSString *symbol in requestedSymbols.array) {
        NSString *ownerModule = nil;
        void *address = [self _symbolAddressForName:symbol preferredModule:preferredModuleName ownerModule:&ownerModule];
        NSString *moduleName = VCUnityTrimmedString(ownerModule);
        NSString *rva = @"";
        if (address) {
            NSString *resolvedModule = nil;
            uint64_t runtimeAddress = (uint64_t)(uintptr_t)address;
            uint64_t resolvedRva = [[VCProcessInfo shared] runtimeToRva:runtimeAddress module:&resolvedModule];
            if (resolvedModule.length > 0) moduleName = resolvedModule;
            rva = resolvedRva > 0 ? VCUnityHexAddress(resolvedRva) : @"";
            resolvedCount++;
        }

        [items addObject:@{
            @"symbol": symbol,
            @"found": @(address != NULL),
            @"address": address ? VCUnityHexAddress((uint64_t)(uintptr_t)address) : @"",
            @"ownerModule": moduleName ?: @"",
            @"rva": rva ?: @"",
            @"preferredModule": VCUnityTrimmedString(preferredModuleName)
        }];
    }

    return @{
        @"runtimeFlavor": runtimeFlavor,
        @"preferredModule": VCUnityTrimmedString(preferredModuleName),
        @"candidateModules": [self _moduleNameListForModules:candidateModules],
        @"requestedSymbols": requestedSymbols.array ?: @[],
        @"resolvedCount": @(resolvedCount),
        @"symbols": [items copy]
    };
}

- (NSDictionary *)runtimeNotes {
    NSDictionary *detect = [self detectUnityRuntimeWithoutSymbols];
    NSString *runtimeFlavor = detect[@"runtimeFlavor"] ?: @"unknown";
    NSArray<NSString *> *recommendedTools = nil;
    NSArray<NSString *> *missingPieces = nil;

    if ([runtimeFlavor isEqualToString:@"il2cpp"]) {
        recommendedTools = @[@"unity_runtime", @"signature_scan", @"pointer_chain", @"address_resolve", @"memory_browser"];
        missingPieces = @[
            @"IL2CPP metadata/class browser",
            @"Unity object enumeration",
            @"Renderer bounds / object extent bridge",
            @"Per-frame tracked overlay updates"
        ];
    } else if ([runtimeFlavor isEqualToString:@"mono"]) {
        recommendedTools = @[@"unity_runtime", @"signature_scan", @"pointer_chain", @"memory_scan", @"memory_browser"];
        missingPieces = @[
            @"Mono class/object browser",
            @"Component and Transform bridge",
            @"Safe WorldToScreen bridge",
            @"Per-frame tracked overlay updates"
        ];
    } else {
        recommendedTools = @[@"query_process", @"signature_scan", @"memory_scan", @"pointer_chain", @"memory_browser"];
        missingPieces = @[
            @"Positive Unity runtime detection",
            @"Unity scripting bridge",
            @"Tracked overlay drawing flow"
        ];
    }

    return @{
        @"runtimeFlavor": runtimeFlavor,
        @"recommendedTools": recommendedTools ?: @[],
        @"missingPieces": missingPieces ?: @[],
        @"drawingGuidance": @[
            @"First confirm Unity/IL2CPP/Mono markers.",
            @"Then stabilize object or field addresses with signature_scan or pointer_chain.",
            @"For real-time object drawing, resolve an explicit camera or transform, call world_to_screen, then draw with overlay_canvas."
        ]
    };
}

- (NSDictionary *)resolveICalls:(NSArray<NSString *> *)icallNames
             includeDefaultICalls:(BOOL)includeDefaultICalls {
    NSDictionary *detect = [self detectUnityRuntimeWithoutSymbols];
    NSString *runtimeFlavor = detect[@"runtimeFlavor"] ?: @"unknown";
    void *resolverAddress = dlsym(RTLD_DEFAULT, "il2cpp_resolve_icall");
    BOOL canResolveICalls = (resolverAddress != NULL);

    NSMutableOrderedSet<NSString *> *requestedICalls = [NSMutableOrderedSet orderedSet];
    for (NSString *name in icallNames ?: @[]) {
        NSString *trimmed = VCUnityTrimmedString(name);
        if (trimmed.length > 0) [requestedICalls addObject:trimmed];
    }
    if (includeDefaultICalls || requestedICalls.count == 0) {
        for (NSString *name in VCUnityDrawingDefaultICalls()) {
            if (name.length > 0) [requestedICalls addObject:name];
        }
    }

    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    NSUInteger resolvedCount = 0;
    if (canResolveICalls) {
        void *(*resolveICall)(const char *) = (void *(*)(const char *))resolverAddress;
        for (NSString *name in requestedICalls.array) {
            void *address = resolveICall(name.UTF8String);
            NSString *ownerModule = @"";
            NSString *rva = @"";
            if (address) {
                NSString *resolvedModule = nil;
                uint64_t runtimeAddress = (uint64_t)(uintptr_t)address;
                uint64_t resolvedRva = [[VCProcessInfo shared] runtimeToRva:runtimeAddress module:&resolvedModule];
                ownerModule = resolvedModule ?: @"";
                rva = resolvedRva > 0 ? VCUnityHexAddress(resolvedRva) : @"";
                resolvedCount++;
            }
            [items addObject:@{
                @"icall": name,
                @"found": @(address != NULL),
                @"address": address ? VCUnityHexAddress((uint64_t)(uintptr_t)address) : @"",
                @"ownerModule": ownerModule ?: @"",
                @"rva": rva ?: @""
            }];
        }
    } else {
        for (NSString *name in requestedICalls.array) {
            [items addObject:@{
                @"icall": name,
                @"found": @NO,
                @"address": @"",
                @"ownerModule": @"",
                @"rva": @""
            }];
        }
    }

    NSString *resolverModule = @"";
    if (resolverAddress) {
        NSString *resolvedModule = nil;
        [[VCProcessInfo shared] runtimeToRva:(uint64_t)(uintptr_t)resolverAddress module:&resolvedModule];
        resolverModule = resolvedModule ?: @"";
    }

    return @{
        @"runtimeFlavor": runtimeFlavor,
        @"canResolveICalls": @(canResolveICalls),
        @"resolverSymbol": @"il2cpp_resolve_icall",
        @"resolverAddress": resolverAddress ? VCUnityHexAddress((uint64_t)(uintptr_t)resolverAddress) : @"",
        @"resolverModule": resolverModule ?: @"",
        @"requestedICalls": requestedICalls.array ?: @[],
        @"resolvedCount": @(resolvedCount),
        @"icalls": [items copy]
    };
}

- (NSDictionary *)drawingSupportSummary {
    NSDictionary *detect = [self detectUnityRuntime] ?: @{};
    NSDictionary *icalls = [self resolveICalls:@[] includeDefaultICalls:YES] ?: @{};
    NSArray<NSDictionary *> *items = [icalls[@"icalls"] isKindOfClass:[NSArray class]] ? icalls[@"icalls"] : @[];

    BOOL (^matchICall)(NSString *) = ^BOOL(NSString *needle) {
        for (NSDictionary *item in items) {
            NSString *name = VCUnityTrimmedString(item[@"icall"]);
            if ([name containsString:needle]) {
                return [item[@"found"] boolValue];
            }
        }
        return NO;
    };

    BOOL hasMainCamera = matchICall(@"Camera::get_main");
    BOOL hasWorldToScreen = matchICall(@"Camera::WorldToScreenPoint");
    BOOL hasTransformPosition = matchICall(@"Transform::get_position");
    BOOL hasComponentTransform = matchICall(@"Component::get_transform") || matchICall(@"GameObject::get_transform");
    BOOL hasRendererBounds = matchICall(@"Renderer::get_bounds");
    BOOL hasScreenWidth = matchICall(@"Screen::get_width");
    BOOL hasScreenHeight = matchICall(@"Screen::get_height");

    NSMutableArray<NSString *> *missingPieces = [NSMutableArray new];
    if (![icalls[@"canResolveICalls"] boolValue]) [missingPieces addObject:@"il2cpp_resolve_icall bridge"];
    if (!hasMainCamera) [missingPieces addObject:@"main camera icall"];
    if (!hasWorldToScreen) [missingPieces addObject:@"WorldToScreen icall"];
    if (!hasTransformPosition) [missingPieces addObject:@"Transform position icall"];
    if (!hasComponentTransform) [missingPieces addObject:@"Component/GameObject transform icall"];
    if (!hasRendererBounds) [missingPieces addObject:@"Renderer bounds icall"];
    if (![VCOverlayCanvasManager hasAttachedCanvas]) [missingPieces addObject:@"overlay canvas bootstrap"];
    [missingPieces addObject:@"tracked per-frame overlay updates"];

    return @{
        @"runtimeFlavor": detect[@"runtimeFlavor"] ?: @"unknown",
        @"likelyUnity": detect[@"likelyUnity"] ?: @NO,
        @"canResolveICalls": icalls[@"canResolveICalls"] ?: @NO,
        @"hasMainCameraICall": @(hasMainCamera),
        @"hasWorldToScreenICall": @(hasWorldToScreen),
        @"hasTransformPositionICall": @(hasTransformPosition),
        @"hasTransformLookupICall": @(hasComponentTransform),
        @"hasRendererBoundsICall": @(hasRendererBounds),
        @"hasScreenSizeICalls": @((hasScreenWidth && hasScreenHeight)),
        @"canPrepareWorldToScreenBridge": @([icalls[@"canResolveICalls"] boolValue] && hasMainCamera && hasWorldToScreen),
        @"canPrepareObjectDrawingBridge": @([icalls[@"canResolveICalls"] boolValue] && hasMainCamera && hasWorldToScreen && (hasTransformPosition || hasComponentTransform)),
        @"canPrepareRendererBoxBridge": @([icalls[@"canResolveICalls"] boolValue] && hasMainCamera && hasWorldToScreen && hasRendererBounds),
        @"overlayCanvasPresent": @([VCOverlayCanvasManager hasAttachedCanvas]),
        @"icallSummary": icalls,
        @"missingPieces": [missingPieces copy]
    };
}

- (NSDictionary *)mainCameraSummary {
    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSString *resolvedICall = nil;
        void *cameraGetterAddress = [self _resolvedICallAddressForCandidates:VCUnityMainCameraICallCandidates()
                                                                resolvedName:&resolvedICall];
        if (!cameraGetterAddress) {
            result = @{
                @"success": @NO,
                @"queryType": @"camera_main",
                @"error": @"Camera.main icall could not be resolved."
            };
            return;
        }

        VCUnityCameraGetMainFunc getMain = (VCUnityCameraGetMainFunc)cameraGetterAddress;
        void *camera = getMain ? getMain() : NULL;
        NSString *ownerModule = nil;
        uint64_t icallRva = [[VCProcessInfo shared] runtimeToRva:(uint64_t)(uintptr_t)cameraGetterAddress module:&ownerModule];

        result = @{
            @"success": @(camera != NULL),
            @"queryType": @"camera_main",
            @"cameraAddress": camera ? VCUnityHexAddress((uint64_t)(uintptr_t)camera) : @"",
            @"resolvedICall": resolvedICall ?: @"",
            @"icallAddress": cameraGetterAddress ? VCUnityHexAddress((uint64_t)(uintptr_t)cameraGetterAddress) : @"",
            @"icallModule": ownerModule ?: @"",
            @"icallRva": icallRva > 0 ? VCUnityHexAddress(icallRva) : @"",
            @"runtimeFlavor": [self detectUnityRuntimeWithoutSymbols][@"runtimeFlavor"] ?: @"unknown"
        };
    }];
    return result ?: @{ @"success": @NO, @"queryType": @"camera_main", @"error": @"Camera lookup failed." };
}

- (NSDictionary *)findGameObjectByName:(NSString *)name {
    NSString *trimmedName = VCUnityTrimmedString(name);
    if (trimmedName.length == 0) {
        return @{@"success": @NO, @"queryType": @"find_by_name", @"error": @"A concrete Unity object name is required."};
    }

    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        VCUnityStringNewFunc stringNew = [self _stringNewFunction];
        NSString *resolvedFindICall = nil;
        void *findAddress = [self _resolvedICallAddressForCandidates:VCUnityGameObjectFindICallCandidates()
                                                        resolvedName:&resolvedFindICall];
        if (!stringNew || !findAddress) {
            result = @{@"success": @NO, @"queryType": @"find_by_name", @"error": @"Unity GameObject.Find bridge could not be resolved."};
            return;
        }

        void *managedName = stringNew(trimmedName.UTF8String);
        VCUnityGameObjectFindFunc findFunc = (VCUnityGameObjectFindFunc)findAddress;
        void *gameObject = findFunc ? findFunc(managedName) : NULL;
        NSString *resolvedTransformICall = @"";
        void *transform = gameObject ? [self _transformForObjectAddress:(uintptr_t)gameObject kind:@"gameobject" resolvedICall:&resolvedTransformICall] : NULL;

        result = @{
            @"success": @(gameObject != NULL),
            @"queryType": @"find_by_name",
            @"name": trimmedName,
            @"gameObjectAddress": gameObject ? VCUnityHexAddress((uint64_t)(uintptr_t)gameObject) : @"",
            @"transformAddress": transform ? VCUnityHexAddress((uint64_t)(uintptr_t)transform) : @"",
            @"resolvedFindICall": resolvedFindICall ?: @"",
            @"resolvedTransformICall": resolvedTransformICall ?: @"",
            @"runtimeFlavor": [self detectUnityRuntimeWithoutSymbols][@"runtimeFlavor"] ?: @"unknown",
            @"error": gameObject ? @"" : [NSString stringWithFormat:@"No Unity GameObject named \"%@\" was found.", trimmedName]
        };
    }];
    return result ?: @{@"success": @NO, @"queryType": @"find_by_name", @"error": @"Unity object lookup failed."};
}

- (NSDictionary *)findGameObjectsByTag:(NSString *)tag limit:(NSUInteger)limit {
    NSString *trimmedTag = VCUnityTrimmedString(tag);
    if (trimmedTag.length == 0) {
        return @{@"success": @NO, @"queryType": @"find_by_tag", @"error": @"A concrete Unity tag is required."};
    }

    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        VCUnityStringNewFunc stringNew = [self _stringNewFunction];
        NSString *resolvedFindManyICall = nil;
        void *findManyAddress = [self _resolvedICallAddressForCandidates:VCUnityGameObjectsWithTagICallCandidates()
                                                            resolvedName:&resolvedFindManyICall];
        NSString *resolvedFindOneICall = nil;
        void *findOneAddress = [self _resolvedICallAddressForCandidates:VCUnityGameObjectWithTagICallCandidates()
                                                           resolvedName:&resolvedFindOneICall];
        if (!stringNew || (!findManyAddress && !findOneAddress)) {
            result = @{@"success": @NO, @"queryType": @"find_by_tag", @"error": @"Unity tag search bridge could not be resolved."};
            return;
        }

        void *managedTag = stringNew(trimmedTag.UTF8String);
        NSUInteger maxCount = MAX((NSUInteger)1, MIN(limit > 0 ? limit : 16, (NSUInteger)64));
        NSMutableArray *objects = [NSMutableArray new];

        if (findManyAddress) {
            VCUnityGameObjectFindManyFunc findMany = (VCUnityGameObjectFindManyFunc)findManyAddress;
            VCUnityObjectArray *array = (VCUnityObjectArray *)(findMany ? findMany(managedTag) : NULL);
            NSUInteger count = [self _objectArrayLength:array];
            for (NSUInteger idx = 0; idx < count && objects.count < maxCount; idx++) {
                void *gameObject = array->vector[idx];
                if (!gameObject) continue;
                NSString *resolvedTransformICall = @"";
                void *transform = [self _transformForObjectAddress:(uintptr_t)gameObject kind:@"gameobject" resolvedICall:&resolvedTransformICall];
                [objects addObject:@{
                    @"gameObjectAddress": VCUnityHexAddress((uint64_t)(uintptr_t)gameObject),
                    @"transformAddress": transform ? VCUnityHexAddress((uint64_t)(uintptr_t)transform) : @"",
                    @"resolvedTransformICall": resolvedTransformICall ?: @""
                }];
            }
        } else if (findOneAddress) {
            VCUnityGameObjectFindFunc findOne = (VCUnityGameObjectFindFunc)findOneAddress;
            void *gameObject = findOne ? findOne(managedTag) : NULL;
            if (gameObject) {
                NSString *resolvedTransformICall = @"";
                void *transform = [self _transformForObjectAddress:(uintptr_t)gameObject kind:@"gameobject" resolvedICall:&resolvedTransformICall];
                [objects addObject:@{
                    @"gameObjectAddress": VCUnityHexAddress((uint64_t)(uintptr_t)gameObject),
                    @"transformAddress": transform ? VCUnityHexAddress((uint64_t)(uintptr_t)transform) : @"",
                    @"resolvedTransformICall": resolvedTransformICall ?: @""
                }];
            }
        }

        result = @{
            @"success": @(objects.count > 0),
            @"queryType": @"find_by_tag",
            @"tag": trimmedTag,
            @"returnedCount": @(objects.count),
            @"objects": [objects copy],
            @"resolvedFindICall": resolvedFindManyICall.length > 0 ? resolvedFindManyICall : (resolvedFindOneICall ?: @""),
            @"runtimeFlavor": [self detectUnityRuntimeWithoutSymbols][@"runtimeFlavor"] ?: @"unknown",
            @"error": objects.count > 0 ? @"" : [NSString stringWithFormat:@"No Unity GameObjects with tag \"%@\" were found.", trimmedTag]
        };
    }];
    return result ?: @{@"success": @NO, @"queryType": @"find_by_tag", @"error": @"Unity tag lookup failed."};
}

- (NSDictionary *)componentForObjectAddress:(uintptr_t)address
                                 objectKind:(NSString *)objectKind
                              componentName:(NSString *)componentName {
    NSString *trimmedComponent = VCUnityTrimmedString(componentName);
    NSString *normalizedKind = VCUnityTrimmedString(objectKind).lowercaseString;
    if (address == 0 || trimmedComponent.length == 0) {
        return @{@"success": @NO, @"queryType": @"get_component", @"error": @"A concrete Unity object address and component name are required."};
    }
    if (normalizedKind.length == 0) normalizedKind = @"gameobject";

    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSString *resolvedKind = normalizedKind;
        VCUnityStringNewFunc stringNew = [self _stringNewFunction];
        if (!stringNew) {
            result = @{@"success": @NO, @"queryType": @"get_component", @"error": @"il2cpp_string_new is unavailable, so component lookup cannot create managed strings."};
            return;
        }

        NSString *resolvedICall = nil;
        NSArray<NSString *> *candidates = [resolvedKind isEqualToString:@"component"]
            ? VCUnityComponentGetComponentByNameCandidates()
            : VCUnityGameObjectGetComponentByNameCandidates();
        void *lookupAddress = [self _resolvedICallAddressForCandidates:candidates resolvedName:&resolvedICall];
        if (!lookupAddress) {
            result = @{@"success": @NO, @"queryType": @"get_component", @"error": @"Unity component lookup icall could not be resolved."};
            return;
        }

        void *targetObject = (void *)address;
        NSString *resolvedTransformICall = @"";
        if ([resolvedKind isEqualToString:@"transform"]) {
            targetObject = (void *)address;
            resolvedKind = @"component";
        }
        if ([resolvedKind isEqualToString:@"gameobject"] || [resolvedKind isEqualToString:@"game_object"]) {
            resolvedKind = @"gameobject";
        } else if ([resolvedKind isEqualToString:@"component"]) {
            resolvedKind = @"component";
        }

        VCUnityGetComponentByNameFunc getComponent = (VCUnityGetComponentByNameFunc)lookupAddress;
        void *managedName = stringNew(trimmedComponent.UTF8String);
        void *component = getComponent ? getComponent(targetObject, managedName) : NULL;
        void *transform = NULL;
        if (component) {
            if ([trimmedComponent.lowercaseString containsString:@"transform"]) {
                transform = component;
            } else {
                transform = [self _transformForObjectAddress:(uintptr_t)component kind:@"component" resolvedICall:&resolvedTransformICall];
            }
        }

        result = @{
            @"success": @(component != NULL),
            @"queryType": @"get_component",
            @"objectAddress": VCUnityHexAddress(address),
            @"objectKind": resolvedKind ?: @"",
            @"componentName": trimmedComponent,
            @"componentAddress": component ? VCUnityHexAddress((uint64_t)(uintptr_t)component) : @"",
            @"transformAddress": transform ? VCUnityHexAddress((uint64_t)(uintptr_t)transform) : @"",
            @"resolvedICall": resolvedICall ?: @"",
            @"resolvedTransformICall": resolvedTransformICall ?: @"",
            @"error": component ? @"" : [NSString stringWithFormat:@"Component %@ was not found on the Unity object.", trimmedComponent]
        };
    }];
    return result ?: @{@"success": @NO, @"queryType": @"get_component", @"error": @"Unity component lookup failed."};
}

- (NSDictionary *)rendererCandidatesForName:(NSString *)name
                                        tag:(NSString *)tag
                                      limit:(NSUInteger)limit {
    NSString *trimmedName = VCUnityTrimmedString(name);
    NSString *trimmedTag = VCUnityTrimmedString(tag);
    if (trimmedName.length == 0 && trimmedTag.length == 0) {
        return @{@"success": @NO, @"queryType": @"list_renderers", @"error": @"list_renderers needs a Unity object name or tag."};
    }

    NSMutableArray<NSDictionary *> *objects = [NSMutableArray new];
    if (trimmedName.length > 0) {
        NSDictionary *single = [self findGameObjectByName:trimmedName];
        if ([single[@"success"] boolValue]) {
            [objects addObject:@{
                @"gameObjectAddress": single[@"gameObjectAddress"] ?: @"",
                @"transformAddress": single[@"transformAddress"] ?: @""
            }];
        }
    } else {
        NSDictionary *many = [self findGameObjectsByTag:trimmedTag limit:limit];
        if ([many[@"success"] boolValue]) {
            NSArray *found = [many[@"objects"] isKindOfClass:[NSArray class]] ? many[@"objects"] : @[];
            [objects addObjectsFromArray:found];
        }
    }

    NSMutableArray *renderers = [NSMutableArray new];
    NSUInteger maxCount = MAX((NSUInteger)1, MIN(limit > 0 ? limit : 16, (NSUInteger)32));
    for (NSDictionary *object in objects) {
        NSString *addressString = VCUnityTrimmedString(object[@"gameObjectAddress"]);
        uintptr_t gameObjectAddress = (uintptr_t)strtoull(addressString.UTF8String, NULL, 0);
        if (gameObjectAddress == 0) continue;

        for (NSString *componentName in [self _rendererComponentNames]) {
            NSDictionary *component = [self componentForObjectAddress:gameObjectAddress objectKind:@"gameobject" componentName:componentName];
            if (![component[@"success"] boolValue]) continue;
            NSMutableDictionary *entry = [component mutableCopy];
            entry[@"gameObjectAddress"] = addressString;
            [renderers addObject:[entry copy]];
            break;
        }
        if (renderers.count >= maxCount) break;
    }

    return @{
        @"success": @(renderers.count > 0),
        @"queryType": @"list_renderers",
        @"name": trimmedName ?: @"",
        @"tag": trimmedTag ?: @"",
        @"returnedCount": @(renderers.count),
        @"renderers": [renderers copy],
        @"error": renderers.count > 0 ? @"" : @"No Unity Renderer candidates were found from the supplied name or tag."
    };
}

- (NSDictionary *)transformPositionForAddress:(uintptr_t)address objectKind:(NSString *)objectKind {
    NSString *normalizedKind = VCUnityTrimmedString(objectKind).lowercaseString;
    if (address == 0) {
        return @{
            @"success": @NO,
            @"queryType": @"transform_position",
            @"error": @"A concrete Unity object address is required."
        };
    }
    if (normalizedKind.length == 0) normalizedKind = @"transform";

    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSString *resolvedPositionICall = nil;
        void *positionAddress = [self _resolvedICallAddressForCandidates:VCUnityTransformPositionICallCandidates()
                                                            resolvedName:&resolvedPositionICall];
        if (!positionAddress) {
            result = @{
                @"success": @NO,
                @"queryType": @"transform_position",
                @"error": @"Transform position icall could not be resolved."
            };
            return;
        }

        void *transformObject = (void *)address;
        NSString *resolvedTransformICall = @"";
        if ([normalizedKind isEqualToString:@"component"]) {
            transformObject = [self _transformForObjectAddress:address
                                                      kind:@"component"
                                              resolvedICall:&resolvedTransformICall];
        } else if ([normalizedKind isEqualToString:@"gameobject"] || [normalizedKind isEqualToString:@"game_object"]) {
            transformObject = [self _transformForObjectAddress:address
                                                      kind:@"gameobject"
                                              resolvedICall:&resolvedTransformICall];
        } else if (![normalizedKind isEqualToString:@"transform"]) {
            result = @{
                @"success": @NO,
                @"queryType": @"transform_position",
                @"error": [NSString stringWithFormat:@"Unsupported object kind %@. Use transform, component, or gameobject.", normalizedKind]
            };
            return;
        }

        if (!transformObject) {
            result = @{
                @"success": @NO,
                @"queryType": @"transform_position",
                @"error": @"The object could not be resolved to a Unity Transform."
            };
            return;
        }

        VCUnityTransformGetPositionInjectedFunc getPosition = (VCUnityTransformGetPositionInjectedFunc)positionAddress;
        VCUnityVector3 position = {0};
        getPosition(transformObject, &position);

        result = @{
            @"success": @YES,
            @"queryType": @"transform_position",
            @"objectKind": normalizedKind ?: @"transform",
            @"sourceAddress": VCUnityHexAddress(address),
            @"transformAddress": VCUnityHexAddress((uint64_t)(uintptr_t)transformObject),
            @"resolvedPositionICall": resolvedPositionICall ?: @"",
            @"resolvedTransformICall": resolvedTransformICall ?: @"",
            @"world": @{
                @"x": @(position.x),
                @"y": @(position.y),
                @"z": @(position.z)
            }
        };
    }];
    return result ?: @{ @"success": @NO, @"queryType": @"transform_position", @"error": @"Transform position lookup failed." };
}

- (NSDictionary *)rendererBoundsForAddress:(uintptr_t)address {
    if (address == 0) {
        return @{
            @"success": @NO,
            @"queryType": @"renderer_bounds",
            @"error": @"A concrete Unity Renderer address is required."
        };
    }

    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSString *resolvedBoundsICall = nil;
        void *boundsAddress = [self _resolvedICallAddressForCandidates:VCUnityRendererBoundsICallCandidates()
                                                           resolvedName:&resolvedBoundsICall];
        if (!boundsAddress) {
            result = @{
                @"success": @NO,
                @"queryType": @"renderer_bounds",
                @"error": @"Renderer bounds icall could not be resolved."
            };
            return;
        }

        VCUnityRendererGetBoundsInjectedFunc getBounds = (VCUnityRendererGetBoundsInjectedFunc)boundsAddress;
        VCUnityBounds bounds = {{0.0f, 0.0f, 0.0f}, {0.0f, 0.0f, 0.0f}};
        getBounds((void *)address, &bounds);

        result = @{
            @"success": @YES,
            @"queryType": @"renderer_bounds",
            @"rendererAddress": VCUnityHexAddress(address),
            @"resolvedBoundsICall": resolvedBoundsICall ?: @"",
            @"center": @{
                @"x": @(bounds.center.x),
                @"y": @(bounds.center.y),
                @"z": @(bounds.center.z)
            },
            @"extents": @{
                @"x": @(bounds.extents.x),
                @"y": @(bounds.extents.y),
                @"z": @(bounds.extents.z)
            },
            @"size": @{
                @"x": @(bounds.extents.x * 2.0f),
                @"y": @(bounds.extents.y * 2.0f),
                @"z": @(bounds.extents.z * 2.0f)
            }
        };
    }];
    return result ?: @{ @"success": @NO, @"queryType": @"renderer_bounds", @"error": @"Renderer bounds lookup failed." };
}

- (NSDictionary *)projectRendererBoundsForAddress:(uintptr_t)address cameraAddress:(uintptr_t)cameraAddress {
    NSDictionary *boundsPayload = [self rendererBoundsForAddress:address] ?: @{};
    if (![boundsPayload[@"success"] boolValue]) {
        return boundsPayload.count > 0 ? boundsPayload : @{
            @"success": @NO,
            @"queryType": @"project_renderer_bounds",
            @"error": @"Renderer bounds could not be resolved."
        };
    }

    NSDictionary *center = [boundsPayload[@"center"] isKindOfClass:[NSDictionary class]] ? boundsPayload[@"center"] : @{};
    NSDictionary *extents = [boundsPayload[@"extents"] isKindOfClass:[NSDictionary class]] ? boundsPayload[@"extents"] : @{};
    double cx = [center[@"x"] respondsToSelector:@selector(doubleValue)] ? [center[@"x"] doubleValue] : 0.0;
    double cy = [center[@"y"] respondsToSelector:@selector(doubleValue)] ? [center[@"y"] doubleValue] : 0.0;
    double cz = [center[@"z"] respondsToSelector:@selector(doubleValue)] ? [center[@"z"] doubleValue] : 0.0;
    double ex = [extents[@"x"] respondsToSelector:@selector(doubleValue)] ? [extents[@"x"] doubleValue] : 0.0;
    double ey = [extents[@"y"] respondsToSelector:@selector(doubleValue)] ? [extents[@"y"] doubleValue] : 0.0;
    double ez = [extents[@"z"] respondsToSelector:@selector(doubleValue)] ? [extents[@"z"] doubleValue] : 0.0;

    NSArray<NSDictionary *> *corners = @[
        @{@"x": @(cx - ex), @"y": @(cy - ey), @"z": @(cz - ez)},
        @{@"x": @(cx - ex), @"y": @(cy - ey), @"z": @(cz + ez)},
        @{@"x": @(cx - ex), @"y": @(cy + ey), @"z": @(cz - ez)},
        @{@"x": @(cx - ex), @"y": @(cy + ey), @"z": @(cz + ez)},
        @{@"x": @(cx + ex), @"y": @(cy - ey), @"z": @(cz - ez)},
        @{@"x": @(cx + ex), @"y": @(cy - ey), @"z": @(cz + ez)},
        @{@"x": @(cx + ex), @"y": @(cy + ey), @"z": @(cz - ez)},
        @{@"x": @(cx + ex), @"y": @(cy + ey), @"z": @(cz + ez)}
    ];

    NSMutableArray<NSDictionary *> *projectedCorners = [NSMutableArray new];
    CGFloat minX = CGFLOAT_MAX;
    CGFloat minY = CGFLOAT_MAX;
    CGFloat maxX = -CGFLOAT_MAX;
    CGFloat maxY = -CGFLOAT_MAX;
    NSUInteger visibleCount = 0;

    for (NSDictionary *corner in corners) {
        NSDictionary *projection = [self worldToScreenForWorldX:[corner[@"x"] doubleValue]
                                                             y:[corner[@"y"] doubleValue]
                                                             z:[corner[@"z"] doubleValue]
                                                 cameraAddress:cameraAddress] ?: @{};
        NSMutableDictionary *entry = [corner mutableCopy];
        entry[@"projection"] = projection;
        [projectedCorners addObject:[entry copy]];

        if (![projection[@"success"] boolValue] || ![projection[@"onScreen"] boolValue]) continue;
        NSDictionary *overlayPoint = [projection[@"overlayPoint"] isKindOfClass:[NSDictionary class]] ? projection[@"overlayPoint"] : @{};
        CGFloat px = [overlayPoint[@"x"] respondsToSelector:@selector(doubleValue)] ? [overlayPoint[@"x"] doubleValue] : 0.0;
        CGFloat py = [overlayPoint[@"y"] respondsToSelector:@selector(doubleValue)] ? [overlayPoint[@"y"] doubleValue] : 0.0;
        minX = MIN(minX, px);
        minY = MIN(minY, py);
        maxX = MAX(maxX, px);
        maxY = MAX(maxY, py);
        visibleCount++;
    }

    BOOL hasVisibleBox = visibleCount > 0 && minX != CGFLOAT_MAX && minY != CGFLOAT_MAX && maxX >= minX && maxY >= minY;
    return @{
        @"success": @(hasVisibleBox),
        @"queryType": @"project_renderer_bounds",
        @"rendererAddress": VCUnityHexAddress(address),
        @"cameraAddress": cameraAddress > 0 ? VCUnityHexAddress(cameraAddress) : @"",
        @"visibleCornerCount": @(visibleCount),
        @"bounds": boundsPayload,
        @"projectedCorners": [projectedCorners copy],
        @"screenBox": hasVisibleBox ? @{
            @"x": @(minX),
            @"y": @(minY),
            @"width": @(maxX - minX),
            @"height": @(maxY - minY)
        } : @{},
        @"onScreen": @(hasVisibleBox),
        @"error": hasVisibleBox ? @"" : @"Projected renderer bounds are currently off-screen or behind the camera."
    };
}

- (NSDictionary *)worldToScreenForWorldX:(double)x
                                       y:(double)y
                                       z:(double)z
                           cameraAddress:(uintptr_t)cameraAddress {
    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSString *resolvedWorldToScreen = nil;
        void *worldToScreenAddress = [self _resolvedICallAddressForCandidates:VCUnityWorldToScreenICallCandidates()
                                                                 resolvedName:&resolvedWorldToScreen];
        if (!worldToScreenAddress) {
            result = @{
                @"success": @NO,
                @"queryType": @"world_to_screen",
                @"error": @"WorldToScreen icall could not be resolved."
            };
            return;
        }

        void *cameraObject = NULL;
        NSDictionary *cameraSummary = nil;
        if (cameraAddress > 0) {
            cameraObject = (void *)cameraAddress;
        } else {
            cameraSummary = [self mainCameraSummary];
            cameraObject = (void *)(uintptr_t)strtoull([VCUnityTrimmedString(cameraSummary[@"cameraAddress"]) UTF8String], NULL, 0);
        }

        if (!cameraObject) {
            result = @{
                @"success": @NO,
                @"queryType": @"world_to_screen",
                @"error": @"A Unity camera could not be resolved."
            };
            return;
        }

        VCUnityVector3 world = { (float)x, (float)y, (float)z };
        VCUnityVector3 rawScreen = {0};

        if ([resolvedWorldToScreen containsString:@"MonoOrStereoscopicEye"]) {
            VCUnityWorldToScreenInjectedEyeFunc func = (VCUnityWorldToScreenInjectedEyeFunc)worldToScreenAddress;
            func(cameraObject, &world, 0, &rawScreen);
        } else {
            VCUnityWorldToScreenInjectedFunc func = (VCUnityWorldToScreenInjectedFunc)worldToScreenAddress;
            func(cameraObject, &world, &rawScreen);
        }

        NSDictionary *screenMetrics = [self _screenMetrics];
        CGFloat overlayWidth = [screenMetrics[@"overlayWidth"] doubleValue];
        CGFloat overlayHeight = [screenMetrics[@"overlayHeight"] doubleValue];
        CGFloat unityWidth = [screenMetrics[@"unityWidth"] doubleValue];
        CGFloat unityHeight = [screenMetrics[@"unityHeight"] doubleValue];
        if (overlayWidth <= 0.0 || overlayHeight <= 0.0) {
            result = @{
                @"success": @NO,
                @"queryType": @"world_to_screen",
                @"error": @"Screen metrics could not be determined."
            };
            return;
        }

        CGFloat safeUnityWidth = unityWidth > 0.0 ? unityWidth : overlayWidth;
        CGFloat safeUnityHeight = unityHeight > 0.0 ? unityHeight : overlayHeight;
        CGFloat overlayX = rawScreen.x * overlayWidth / MAX(safeUnityWidth, 1.0);
        CGFloat overlayY = overlayHeight - (rawScreen.y * overlayHeight / MAX(safeUnityHeight, 1.0));
        BOOL onScreen = rawScreen.z > 0.0f &&
            overlayX >= 0.0 && overlayX <= overlayWidth &&
            overlayY >= 0.0 && overlayY <= overlayHeight;

        result = @{
            @"success": @YES,
            @"queryType": @"world_to_screen",
            @"cameraAddress": VCUnityHexAddress((uint64_t)(uintptr_t)cameraObject),
            @"resolvedICall": resolvedWorldToScreen ?: @"",
            @"world": @{
                @"x": @(world.x),
                @"y": @(world.y),
                @"z": @(world.z)
            },
            @"unityScreen": @{
                @"x": @(rawScreen.x),
                @"y": @(rawScreen.y),
                @"z": @(rawScreen.z)
            },
            @"overlayPoint": @{
                @"x": @(overlayX),
                @"y": @(overlayY)
            },
            @"normalizedOverlayPoint": @{
                @"x": @(overlayWidth > 0.0 ? overlayX / overlayWidth : 0.0),
                @"y": @(overlayHeight > 0.0 ? overlayY / overlayHeight : 0.0)
            },
            @"screen": screenMetrics ?: @{},
            @"onScreen": @(onScreen)
        };
    }];
    return result ?: @{ @"success": @NO, @"queryType": @"world_to_screen", @"error": @"WorldToScreen failed." };
}

#pragma mark - Private

- (NSDictionary *)detectUnityRuntimeWithoutSymbols {
    NSArray<VCModuleInfo *> *modules = [self _unityModules];
    BOOL hasUnityFramework = [self _hasModuleMatchingPatterns:@[@"unityframework", @"unityplayer", @"libunity"]];
    BOOL hasIL2CPP = [self _hasModuleMatchingPatterns:@[@"libil2cpp"]] || dlsym(RTLD_DEFAULT, "il2cpp_domain_get") != NULL;
    BOOL hasMono = [self _hasModuleMatchingPatterns:@[@"mono", @"monobleedingedge"]] || dlsym(RTLD_DEFAULT, "mono_get_root_domain") != NULL;
    NSString *runtimeFlavor = @"unknown";
    if (hasIL2CPP) runtimeFlavor = @"il2cpp";
    else if (hasMono) runtimeFlavor = @"mono";
    else if (hasUnityFramework) runtimeFlavor = @"unity";

    NSDictionary *objcClasses = @{
        @"UnityAppController": @(NSClassFromString(@"UnityAppController") != Nil),
        @"UnityFramework": @(NSClassFromString(@"UnityFramework") != Nil),
        @"UnityView": @(NSClassFromString(@"UnityView") != Nil),
        @"UnityViewControllerBase": @(NSClassFromString(@"UnityViewControllerBase") != Nil)
    };

    BOOL likelyUnity = hasUnityFramework || hasIL2CPP || hasMono;
    for (NSNumber *flag in objcClasses.allValues) {
        if ([flag boolValue]) {
            likelyUnity = YES;
            break;
        }
    }

    return @{
        @"likelyUnity": @(likelyUnity),
        @"runtimeFlavor": runtimeFlavor,
        @"hasUnityFramework": @(hasUnityFramework),
        @"hasIL2CPP": @(hasIL2CPP),
        @"hasMono": @(hasMono),
        @"unityModuleCount": @(modules.count),
        @"objcClasses": objcClasses
    };
}

- (NSArray<NSString *> *)_defaultSymbolsForRuntimeFlavor:(NSString *)runtimeFlavor {
    NSMutableOrderedSet<NSString *> *symbols = [NSMutableOrderedSet orderedSet];
    for (NSString *symbol in VCUnityBaseDefaultSymbols()) {
        [symbols addObject:symbol];
    }
    NSString *normalizedFlavor = VCUnityTrimmedString(runtimeFlavor).lowercaseString;
    if ([normalizedFlavor isEqualToString:@"il2cpp"]) {
        for (NSString *symbol in VCUnityIL2CPPDefaultSymbols()) [symbols addObject:symbol];
    } else if ([normalizedFlavor isEqualToString:@"mono"]) {
        for (NSString *symbol in VCUnityMonoDefaultSymbols()) [symbols addObject:symbol];
    } else {
        for (NSString *symbol in VCUnityIL2CPPDefaultSymbols()) [symbols addObject:symbol];
        for (NSString *symbol in VCUnityMonoDefaultSymbols()) [symbols addObject:symbol];
    }
    return symbols.array ?: @[];
}

- (NSArray<VCModuleInfo *> *)_unityModules {
    NSMutableArray<VCModuleInfo *> *modules = [NSMutableArray new];
    for (VCModuleInfo *moduleInfo in [[VCProcessInfo shared] loadedModules] ?: @[]) {
        if (VCUnityModuleLooksRelevant(moduleInfo)) {
            [modules addObject:moduleInfo];
        }
    }
    return [modules copy];
}

- (BOOL)_hasModuleMatchingPatterns:(NSArray<NSString *> *)patterns {
    for (VCModuleInfo *moduleInfo in [[VCProcessInfo shared] loadedModules] ?: @[]) {
        if (VCUnityStringContainsAny(moduleInfo.name, patterns) || VCUnityStringContainsAny(moduleInfo.path, patterns)) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<VCModuleInfo *> *)_candidateModulesForPreferredModule:(NSString *)preferredModuleName {
    NSString *preferred = VCUnityTrimmedString(preferredModuleName).lowercaseString;
    NSArray<VCModuleInfo *> *modules = [self _unityModules];
    if (preferred.length == 0) return modules;

    NSMutableArray<VCModuleInfo *> *filtered = [NSMutableArray new];
    for (VCModuleInfo *moduleInfo in modules) {
        NSString *name = VCUnityTrimmedString(moduleInfo.name).lowercaseString;
        NSString *path = VCUnityTrimmedString(moduleInfo.path).lowercaseString;
        if ([name isEqualToString:preferred] || [path isEqualToString:preferred] || [name containsString:preferred] || [path containsString:preferred]) {
            [filtered addObject:moduleInfo];
        }
    }
    return filtered.count > 0 ? [filtered copy] : modules;
}

- (NSArray<NSString *> *)_moduleNameListForModules:(NSArray<VCModuleInfo *> *)modules {
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (VCModuleInfo *moduleInfo in modules ?: @[]) {
        if (moduleInfo.name.length > 0) [names addObject:moduleInfo.name];
    }
    return [names copy];
}

- (void *)_symbolAddressForName:(NSString *)symbolName
                preferredModule:(NSString *)preferredModuleName
                    ownerModule:(NSString * _Nullable __autoreleasing *)ownerModule {
    NSString *trimmedSymbol = VCUnityTrimmedString(symbolName);
    if (trimmedSymbol.length == 0) return NULL;

    for (VCModuleInfo *moduleInfo in [self _candidateModulesForPreferredModule:preferredModuleName]) {
        void *handle = dlopen(moduleInfo.path.UTF8String, RTLD_LAZY | RTLD_NOLOAD);
        if (!handle) continue;
        void *address = dlsym(handle, trimmedSymbol.UTF8String);
        dlclose(handle);
        if (address) {
            if (ownerModule) *ownerModule = moduleInfo.name;
            return address;
        }
    }

    void *address = dlsym(RTLD_DEFAULT, trimmedSymbol.UTF8String);
    if (address) {
        NSString *resolvedModule = nil;
        [[VCProcessInfo shared] runtimeToRva:(uint64_t)(uintptr_t)address module:&resolvedModule];
        if (ownerModule) *ownerModule = resolvedModule ?: @"";
        return address;
    }
    return NULL;
}

- (void)_performOnMainThread:(dispatch_block_t)block {
    if (!block) return;
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

- (VCUnityStringNewFunc)_stringNewFunction {
    void *address = [self _symbolAddressForName:@"il2cpp_string_new"
                                 preferredModule:@"libil2cpp"
                                     ownerModule:nil];
    if (!address) {
        address = [self _symbolAddressForName:@"il2cpp_string_new" preferredModule:nil ownerModule:nil];
    }
    return (VCUnityStringNewFunc)address;
}

- (VCUnityResolveICallFunc)_icallResolverFunction {
    void *resolverAddress = [self _symbolAddressForName:@"il2cpp_resolve_icall"
                                        preferredModule:@"libil2cpp"
                                            ownerModule:nil];
    if (!resolverAddress) {
        resolverAddress = [self _symbolAddressForName:@"il2cpp_resolve_icall" preferredModule:nil ownerModule:nil];
    }
    return (VCUnityResolveICallFunc)resolverAddress;
}

- (NSString *)_stringFromManagedString:(void *)managedString {
    if (!managedString) return @"";
    VCUnityString *string = (VCUnityString *)managedString;
    int32_t length = string->length;
    if (length <= 0 || length > 4096) return @"";
    return [[NSString alloc] initWithCharacters:(const unichar *)string->chars length:(NSUInteger)length] ?: @"";
}

- (NSUInteger)_objectArrayLength:(void *)arrayObject {
    if (!arrayObject) return 0;
    VCUnityObjectArray *array = (VCUnityObjectArray *)arrayObject;
    return (NSUInteger)MIN(array->max_length, (uintptr_t)2048);
}

- (NSArray<NSString *> *)_rendererComponentNames {
    return @[@"Renderer", @"MeshRenderer", @"SkinnedMeshRenderer", @"SpriteRenderer"];
}

- (void *)_resolvedICallAddressForCandidates:(NSArray<NSString *> *)candidates
                                resolvedName:(NSString * _Nullable __autoreleasing *)resolvedName {
    VCUnityResolveICallFunc resolver = [self _icallResolverFunction];
    if (!resolver) return NULL;

    for (NSString *candidate in candidates ?: @[]) {
        NSString *trimmed = VCUnityTrimmedString(candidate);
        if (trimmed.length == 0) continue;
        void *address = resolver(trimmed.UTF8String);
        if (address) {
            if (resolvedName) *resolvedName = trimmed;
            return address;
        }
    }
    return NULL;
}

- (void *)_transformForObjectAddress:(uintptr_t)address
                                kind:(NSString *)kind
                        resolvedICall:(NSString * _Nullable __autoreleasing *)resolvedICall {
    NSArray<NSString *> *candidates = [kind isEqualToString:@"component"]
        ? VCUnityComponentTransformICallCandidates()
        : VCUnityGameObjectTransformICallCandidates();
    void *icallAddress = [self _resolvedICallAddressForCandidates:candidates resolvedName:resolvedICall];
    if (!icallAddress) return NULL;

    VCUnityGetTransformFunc getTransform = (VCUnityGetTransformFunc)icallAddress;
    return getTransform ? getTransform((void *)address) : NULL;
}

- (NSDictionary *)_screenMetrics {
    CGRect hostBounds = [VCOverlayRootViewController currentHostBounds];
    CGFloat overlayWidth = CGRectGetWidth(hostBounds);
    CGFloat overlayHeight = CGRectGetHeight(hostBounds);
    CGFloat hostScale = UIScreen.mainScreen.scale;

    NSString *resolvedWidthICall = nil;
    NSString *resolvedHeightICall = nil;
    void *widthAddress = [self _resolvedICallAddressForCandidates:VCUnityScreenWidthICallCandidates()
                                                      resolvedName:&resolvedWidthICall];
    void *heightAddress = [self _resolvedICallAddressForCandidates:VCUnityScreenHeightICallCandidates()
                                                       resolvedName:&resolvedHeightICall];

    NSInteger unityWidth = 0;
    NSInteger unityHeight = 0;
    if (widthAddress) {
        VCUnityScreenIntGetterFunc getWidth = (VCUnityScreenIntGetterFunc)widthAddress;
        unityWidth = getWidth ? getWidth() : 0;
    }
    if (heightAddress) {
        VCUnityScreenIntGetterFunc getHeight = (VCUnityScreenIntGetterFunc)heightAddress;
        unityHeight = getHeight ? getHeight() : 0;
    }

    if (unityWidth <= 0 && overlayWidth > 0.0) unityWidth = (NSInteger)llround(overlayWidth * hostScale);
    if (unityHeight <= 0 && overlayHeight > 0.0) unityHeight = (NSInteger)llround(overlayHeight * hostScale);

    return @{
        @"overlayWidth": @(overlayWidth),
        @"overlayHeight": @(overlayHeight),
        @"overlayScale": @(hostScale),
        @"unityWidth": @(unityWidth),
        @"unityHeight": @(unityHeight),
        @"resolvedWidthICall": resolvedWidthICall ?: @"",
        @"resolvedHeightICall": resolvedHeightICall ?: @""
    };
}

@end
