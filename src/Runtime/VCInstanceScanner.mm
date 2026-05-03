/**
 * VCInstanceScanner.mm -- Live instance scanner
 * Slide-1: Runtime Engine
 */

#import "VCInstanceScanner.h"
#import "../Core/VCCore.hpp"
#import "../../VansonCLI.h"

#import <objc/runtime.h>
#import <malloc/malloc.h>

// ═══════════════════════════════════════════════════════════════
// Heap scan context
// ═══════════════════════════════════════════════════════════════

static const NSTimeInterval kScanTimeout = 5.0; // seconds
static const NSUInteger kMaxInstances = 500;

typedef struct {
    Class targetClass;
    NSMutableArray *results;
    NSUInteger count;
    BOOL timedOut;
    CFAbsoluteTime deadline;
} VCHeapScanCtx;

// ═══════════════════════════════════════════════════════════════
// Weak alloc tracking
// ═══════════════════════════════════════════════════════════════

static NSMutableDictionary<NSString *, NSHashTable *> *sTrackedClasses;
static dispatch_queue_t sTrackQueue;

static void vc_ensureTrackingInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sTrackedClasses = [NSMutableDictionary dictionary];
        sTrackQueue = dispatch_queue_create("com.vanson.cli.instance-track",
                                            DISPATCH_QUEUE_SERIAL);
    });
}

// ═══════════════════════════════════════════════════════════════
// malloc zone enumerator callback
// ═══════════════════════════════════════════════════════════════

static void vc_heapEnumCallback(task_t task, void *baton,
                                 unsigned type, vm_range_t *ranges,
                                 unsigned rangeCount) {
    VCHeapScanCtx *ctx = (VCHeapScanCtx *)baton;
    if (ctx->timedOut || ctx->count >= kMaxInstances) return;

    // Periodic timeout check
    if (CFAbsoluteTimeGetCurrent() > ctx->deadline) {
        ctx->timedOut = YES;
        return;
    }

    for (unsigned i = 0; i < rangeCount; i++) {
        if (ctx->count >= kMaxInstances || ctx->timedOut) break;

        void *ptr = (void *)ranges[i].address;
        size_t size = ranges[i].size;

        // Minimum object size: isa pointer
        if (size < sizeof(void *)) continue;

        @try {
            // Read isa - on arm64 with tagged isa, use object_getClass
            Class isa = (__bridge Class)(*(void **)ptr);
            if (!isa) continue;

            // Validate: is this actually our target class?
            // Use a safer check: compare class pointer directly
            if (isa == ctx->targetClass ||
                object_getClass((__bridge id)ptr) == ctx->targetClass) {

                id obj = (__bridge id)ptr;
                VCInstanceRecord *rec = [[VCInstanceRecord alloc] init];
                rec.className = NSStringFromClass(ctx->targetClass);
                rec.address = (uintptr_t)ptr;
                rec.discoveredAt = [NSDate date];
                rec.instance = obj;

                @try {
                    rec.briefDescription = [obj debugDescription] ?: [obj description];
                    if (rec.briefDescription.length > 200) {
                        rec.briefDescription = [[rec.briefDescription substringToIndex:197]
                                                stringByAppendingString:@"..."];
                    }
                } @catch (NSException *e) {
                    rec.briefDescription = @"<description unavailable>";
                }

                [ctx->results addObject:rec];
                ctx->count++;
            }
        } @catch (NSException *e) {
            continue; // Bad pointer
        }
    }
}

@implementation VCInstanceScanner

+ (NSArray<VCInstanceRecord *> *)scanInstancesOfClass:(NSString *)className {
    if (!className) return @[];

    Class cls = objc_getClass([className UTF8String]);
    if (!cls) {
        VCLog("InstanceScanner: class '%@' not found", className);
        return @[];
    }

    VCHeapScanCtx ctx;
    ctx.targetClass = cls;
    ctx.results = [NSMutableArray array];
    ctx.count = 0;
    ctx.timedOut = NO;
    ctx.deadline = CFAbsoluteTimeGetCurrent() + kScanTimeout;

    // Enumerate all malloc zones
    vm_address_t *zones = NULL;
    unsigned int zoneCount = 0;
    kern_return_t kr = malloc_get_all_zones(mach_task_self(), NULL, &zones, &zoneCount);

    if (kr == KERN_SUCCESS) {
        for (unsigned int i = 0; i < zoneCount; i++) {
            if (ctx.timedOut || ctx.count >= kMaxInstances) break;

            malloc_zone_t *zone = (malloc_zone_t *)zones[i];
            if (!zone || !zone->introspect || !zone->introspect->enumerator) continue;

            zone->introspect->enumerator(mach_task_self(),
                                         &ctx,
                                         MALLOC_PTR_IN_USE_RANGE_TYPE,
                                         (vm_address_t)zone,
                                         NULL, // memory_reader
                                         vc_heapEnumCallback);
        }
    }

    if (ctx.timedOut) {
        VCLog("InstanceScanner: scan timed out after %.1fs, found %lu instances",
              kScanTimeout, (unsigned long)ctx.count);
    }

    return [ctx.results copy];
}

+ (void)trackAllocsForClass:(NSString *)className {
    if (!className) return;
    vc_ensureTrackingInit();

    dispatch_sync(sTrackQueue, ^{
        if (!sTrackedClasses[className]) {
            sTrackedClasses[className] = [NSHashTable weakObjectsHashTable];
            VCLog("InstanceScanner: now tracking allocs for '%@'", className);
        }
    });
}

+ (NSArray<VCInstanceRecord *> *)trackedInstancesOfClass:(NSString *)className {
    if (!className) return @[];
    vc_ensureTrackingInit();

    __block NSArray *allObjects = nil;
    dispatch_sync(sTrackQueue, ^{
        NSHashTable *table = sTrackedClasses[className];
        allObjects = table ? [table allObjects] : @[];
    });

    NSMutableArray<VCInstanceRecord *> *results = [NSMutableArray array];
    for (id obj in allObjects) {
        VCInstanceRecord *rec = [[VCInstanceRecord alloc] init];
        rec.className = className;
        rec.address = (uintptr_t)(__bridge void *)obj;
        rec.discoveredAt = [NSDate date];
        rec.instance = obj;

        @try {
            rec.briefDescription = [obj debugDescription] ?: [obj description];
            if (rec.briefDescription.length > 200) {
                rec.briefDescription = [[rec.briefDescription substringToIndex:197]
                                        stringByAppendingString:@"..."];
            }
        } @catch (NSException *e) {
            rec.briefDescription = @"<description unavailable>";
        }

        [results addObject:rec];
    }
    return [results copy];
}

+ (void)recordInstance:(id)instance forClass:(NSString *)className {
    if (!instance || !className) return;
    vc_ensureTrackingInit();

    dispatch_async(sTrackQueue, ^{
        NSHashTable *table = sTrackedClasses[className];
        if (table) {
            [table addObject:instance];
        }
    });
}

@end
