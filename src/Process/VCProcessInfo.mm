/**
 * VCProcessInfo.mm -- Process Information Engine
 * Slide-2: Process Engine
 *
 * In-process only -- uses dyld, mach VM, SecTask APIs directly.
 */

#import "VCProcessInfo.h"
#import "../Core/VCCore.hpp"
#import "../../VansonCLI.h"

#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <mach/vm_region.h>
#include <dlfcn.h>
#include <unistd.h>
#import <Security/Security.h>

// ═══════════════════════════════════════════════════════════════
// VCModuleInfo
// ═══════════════════════════════════════════════════════════════

@implementation VCModuleInfo
@end

// ═══════════════════════════════════════════════════════════════
// VCMemRegion
// ═══════════════════════════════════════════════════════════════

@implementation VCMemRegion
@end

// ═══════════════════════════════════════════════════════════════
// VCProcessInfo
// ═══════════════════════════════════════════════════════════════

@implementation VCProcessInfo

+ (instancetype)shared {
    static VCProcessInfo *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[VCProcessInfo alloc] init];
    });
    return inst;
}

#pragma mark - Basic Info

- (NSDictionary *)basicInfo {
    NSBundle *main = [NSBundle mainBundle];
    NSDictionary *info = main.infoDictionary;

    NSString *bundleID = main.bundleIdentifier ?: @"N/A";
    NSString *shortVer = info[@"CFBundleShortVersionString"] ?: @"N/A";
    NSString *buildVer = info[@"CFBundleVersion"] ?: @"N/A";
    NSString *execPath = main.executablePath ?: @"N/A";

    // Sandbox paths
    NSString *docPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: @"N/A";
    NSString *libPath = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject ?: @"N/A";
    NSString *tmpPath = NSTemporaryDirectory() ?: @"N/A";

    return @{
        @"pid":            @(getpid()),
        @"bundleID":       bundleID,
        @"version":        [NSString stringWithFormat:@"%@ (%@)", shortVer, buildVer],
        @"executablePath": execPath,
        @"documentsPath":  docPath,
        @"libraryPath":    libPath,
        @"tmpPath":        tmpPath
    };
}

#pragma mark - Module Classification

static NSString *classifyModule(const char *path) {
    if (!path) return @"thirdparty";
    NSString *p = [NSString stringWithUTF8String:path];
    if ([p containsString:@".app/"])        return @"app";
    if ([p containsString:@".framework/"])  return @"framework";
    if ([p hasPrefix:@"/usr/lib/"])          return @"system";
    return @"thirdparty";
}

#pragma mark - Mach-O Size Calculation

static uint32_t machOImageSize(const struct mach_header *header) {
    if (!header) return 0;

    uint32_t totalSize = 0;
    const uint8_t *ptr = (const uint8_t *)header;

    if (header->magic == MH_MAGIC_64) {
        const struct mach_header_64 *h64 = (const struct mach_header_64 *)header;
        ptr += sizeof(struct mach_header_64);

        for (uint32_t i = 0; i < h64->ncmds; i++) {
            const struct load_command *lc = (const struct load_command *)ptr;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)ptr;
                totalSize += (uint32_t)seg->vmsize;
            }
            ptr += lc->cmdsize;
        }
    } else if (header->magic == MH_MAGIC) {
        ptr += sizeof(struct mach_header);

        for (uint32_t i = 0; i < header->ncmds; i++) {
            const struct load_command *lc = (const struct load_command *)ptr;
            if (lc->cmd == LC_SEGMENT) {
                const struct segment_command *seg = (const struct segment_command *)ptr;
                totalSize += seg->vmsize;
            }
            ptr += lc->cmdsize;
        }
    }

    return totalSize;
}

#pragma mark - Loaded Modules

- (NSArray<VCModuleInfo *> *)loadedModules {
    NSMutableArray<VCModuleInfo *> *modules = [NSMutableArray array];
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        const struct mach_header *header = _dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);

        if (!name || !header) continue;

        VCModuleInfo *mod = [[VCModuleInfo alloc] init];
        mod.path = [NSString stringWithUTF8String:name];
        mod.name = mod.path.lastPathComponent;
        mod.loadAddress = (uint64_t)header;
        mod.slide = (uint64_t)slide;
        mod.size = machOImageSize(header);
        mod.category = classifyModule(name);

        [modules addObject:mod];
    }

    return [modules copy];
}

#pragma mark - Memory Regions

- (NSArray<VCMemRegion *> *)memoryRegions {
    NSMutableArray<VCMemRegion *> *regions = [NSMutableArray array];

    mach_port_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t vmSize = 0;
    uint32_t depth = 1;

    while (YES) {
        struct vm_region_submap_info_64 info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;

        kern_return_t kr = vm_region_recurse_64(task, &address, &vmSize, &depth,
                                                (vm_region_recurse_info_t)&info, &count);
        if (kr != KERN_SUCCESS) break;

        if (info.is_submap) {
            depth++;
            continue;
        }

        VCMemRegion *region = [[VCMemRegion alloc] init];
        region.start = (uint64_t)address;
        region.end   = (uint64_t)(address + vmSize);
        region.size  = (uint32_t)vmSize;

        // Build protection string
        char prot[4] = "---";
        if (info.protection & VM_PROT_READ)    prot[0] = 'r';
        if (info.protection & VM_PROT_WRITE)   prot[1] = 'w';
        if (info.protection & VM_PROT_EXECUTE) prot[2] = 'x';
        region.protection = [NSString stringWithUTF8String:prot];

        [regions addObject:region];
        address += vmSize;
    }

    return [regions copy];
}

#pragma mark - RVA Conversion

- (uint64_t)rvaToRuntime:(uint64_t)rva module:(NSString *)moduleName {
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;

        NSString *path = [NSString stringWithUTF8String:name];
        if (![path.lastPathComponent isEqualToString:moduleName] &&
            ![path isEqualToString:moduleName]) {
            continue;
        }

        const struct mach_header *header = _dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        return (uint64_t)header + slide + rva;
    }

    VCLog("rvaToRuntime: module '%@' not found", moduleName);
    return 0;
}

- (uint64_t)runtimeToRva:(uint64_t)addr module:(NSString *_Nullable *_Nullable)outModule {
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *header = _dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        if (!header) continue;

        uint64_t base = (uint64_t)header;
        uint32_t imgSize = machOImageSize(header);

        if (addr >= base && addr < base + imgSize) {
            if (outModule) {
                const char *name = _dyld_get_image_name(i);
                *outModule = name ? [NSString stringWithUTF8String:name].lastPathComponent : @"unknown";
            }
            return addr - base - (uint64_t)slide;
        }
    }

    if (outModule) *outModule = nil;
    return 0;
}

#pragma mark - Entitlements

- (NSDictionary *)entitlements {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    // SecTask APIs are private on iOS -- resolve via dlsym
    typedef CFTypeRef (*SecTaskCreateFromSelfFunc)(CFAllocatorRef);
    typedef CFTypeRef (*SecTaskCopyValueFunc)(CFTypeRef, CFStringRef, CFErrorRef *);

    SecTaskCreateFromSelfFunc createFromSelf = (SecTaskCreateFromSelfFunc)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    SecTaskCopyValueFunc copyValue = (SecTaskCopyValueFunc)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");

    if (!createFromSelf || !copyValue) {
        VCLog("SecTask APIs not available");
        return @{};
    }

    CFTypeRef task = createFromSelf(kCFAllocatorDefault);
    if (!task) {
        VCLog("Failed to create SecTask from self");
        return @{};
    }

    NSArray *keys = @[
        @"application-identifier",
        @"com.apple.developer.team-identifier",
        @"keychain-access-groups",
        @"com.apple.security.application-groups",
        @"get-task-allow",
        @"com.apple.private.security.no-sandbox",
        @"platform-application",
        @"com.apple.private.skip-library-validation"
    ];

    for (NSString *key in keys) {
        CFTypeRef value = copyValue(task, (__bridge CFStringRef)key, NULL);
        if (value) {
            result[key] = (__bridge_transfer id)value;
        }
    }

    CFRelease(task);
    return [result copy];
}

#pragma mark - Environment Variables

- (NSDictionary *)environmentVariables {
    return [[NSProcessInfo processInfo] environment];
}

@end
