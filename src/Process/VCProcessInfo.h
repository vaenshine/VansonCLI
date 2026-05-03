/**
 * VCProcessInfo.h -- Process Information Engine
 * Slide-2: Process Engine
 *
 * In-process queries via dyld/mach APIs (no cross-process mach_port).
 * Supports: basic info, loaded modules, memory regions,
 *           RVA<->runtime address conversion, entitlements, env vars.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ═══════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════

@interface VCModuleInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *category; // "app" / "framework" / "system" / "thirdparty"
@property (nonatomic, assign) uint64_t loadAddress;
@property (nonatomic, assign) uint64_t slide;
@property (nonatomic, assign) uint32_t size;
@end

@interface VCMemRegion : NSObject
@property (nonatomic, assign) uint64_t start;
@property (nonatomic, assign) uint64_t end;
@property (nonatomic, assign) uint32_t size;
@property (nonatomic, copy) NSString *protection; // "r-x" / "rw-" / "r--" etc.
@end

// ═══════════════════════════════════════════════════════════════
// VCProcessInfo
// ═══════════════════════════════════════════════════════════════

@interface VCProcessInfo : NSObject

+ (instancetype)shared;

/**
 * Basic process info: pid, bundleID, version, executablePath, sandboxPaths.
 */
- (NSDictionary *)basicInfo;

/**
 * All loaded dylibs/frameworks with load address, slide, size, category.
 */
- (NSArray<VCModuleInfo *> *)loadedModules;

/**
 * Virtual memory region map via vm_region_recurse_64.
 */
- (NSArray<VCMemRegion *> *)memoryRegions;

/**
 * Convert RVA offset to runtime address for a given module.
 * @return Runtime address, or 0 if module not found.
 */
- (uint64_t)rvaToRuntime:(uint64_t)rva module:(NSString *)moduleName;

/**
 * Convert runtime address to RVA, optionally returning the owning module name.
 * @return RVA offset, or 0 if address not in any known module.
 */
- (uint64_t)runtimeToRva:(uint64_t)addr module:(NSString *_Nullable *_Nullable)outModule;

/**
 * Process entitlements via SecTask API.
 */
- (NSDictionary *)entitlements;

/**
 * Current process environment variables.
 */
- (NSDictionary *)environmentVariables;

@end

NS_ASSUME_NONNULL_END
